## The 2.5D stage: the night drawn in 3D around the 2D game. Gameplay is
## untouched (the World and its 2D physics run exactly as before); this
## builds a 3D scene from the same level and keeps it in step:
##   - stone, walkways, water, veils and back walls extruded from the tiles
##     (a tile is a metre; the gameplay plane is z = 0, stone runs from
##     FRONT in front of it to BACK behind),
##   - a city of houses behind, with lit windows, and the church spire,
##   - the moon behind it all (backlight, long shadows toward you, shining
##     in the wet stone), lamps and your lantern as lights with shadows,
##     all in volumetric fog,
##   - rain that stops at roofs, and water dripping off every ledge,
##   - a camera that frames at z = 0 exactly what the 2D camera frames.
## Everything on the gameplay plane (actors, lamp posts, signs, finds,
## gates, sparks) is drawn in 2D into a transparent viewport that shares the
## World's canvas, and shown on a lit, shadow-casting quad at z = 0
## (shaders/plane3d.gdshader). Glows, swooshes and health bars stay 2D on
## top. Main adds the stage unless the address has ?2d.
extends Node3D

const Figure = preload("res://scripts/figure.gd")
const STONE := preload("res://shaders/stone3d.gdshader")
const WATER := preload("res://shaders/water3d.gdshader")
const VEIL := preload("res://shaders/veil3d.gdshader")
const SKY := preload("res://shaders/night_sky.gdshader")
const WINDOWS := preload("res://shaders/windows3d.gdshader")
const PLANE := preload("res://shaders/plane3d.gdshader")

## World px per metre: one tile is a metre.
const PX := 32.0
## How far stone reaches in front of the gameplay plane, and behind it (m).
const FRONT := 1.2
const BACK := 3.0
## Vertical field of view. The camera stands back just far enough that the
## plane z = 0 fills the view, so 2D and 3D line up there exactly.
const FOV := 50.0
## Toward the moon: behind the scene, a little right and up.
const MOON_DIR := Vector3(0.3, 0.2, -1.0)
## The district's street level (the top of tile row 20), in metres.
const STREET := -20.0
## Level geometry is built in chunks this many tiles wide (see _build_level).
const CHUNK := 16
## The city is built in chunks this many metres wide.
const CITY_CHUNK := 40.0
## 3D render layer for what moves with the camera or the actors (the plane,
## rain, drips): reflection probes leave it out of their one-time capture.
const MOVING := 2
## Visibility layers of the 2D world: OVERLAY is drawn flat over the 3D
## (glows, swooshes, bars), ON_PLANE goes on the lit quad.
const OVERLAY := 1
const ON_PLANE := 2

var main
var world
var camera: Camera3D
var env: Environment
var moon: DirectionalLight3D
var plane_vp: SubViewport
var plane: MeshInstance3D
## What got built, for the playtest.
var counts := {}

var _cam_z := 12.0
var _stone_mat: ShaderMaterial
var _wet_noise: NoiseTexture2D
var _lamps := []
var _finds := []
var _lantern: OmniLight3D
var _fill: OmniLight3D
var _pile: OmniLight3D
var _veil: MeshInstance3D
var _veil_mat: ShaderMaterial
var _city: Node3D
var _rain: GPUParticles3D
var _drips: GPUParticles3D
var _shadowed: Array[Light3D] = []
var _time := 0.0
## The browser's lighter renderer: lamps and the lantern throw no shadows,
## the moon's are simpler, the city casts none, and it rains less.
var _lite := false


## Collects quads into one mesh.
class Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## A quad through a, b, c, d (in order round its edge), facing n.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col := Color.WHITE) -> void:
		# Godot's front faces wind clockwise seen from the front.
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = d
			d = t
		var i := verts.size()
		verts.append_array(PackedVector3Array([a, b, c, d]))
		for k in 4:
			normals.append(n)
			colors.append(col)
		indices.append_array(PackedInt32Array([i, i + 1, i + 2, i, i + 2, i + 3]))

	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col := Color.WHITE) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		var i := verts.size()
		verts.append_array(PackedVector3Array([a, b, c]))
		for k in 3:
			normals.append(n)
			colors.append(col)
		indices.append_array(PackedInt32Array([i, i + 1, i + 2]))

	func box(lo: Vector3, hi: Vector3, col := Color.WHITE) -> void:
		var x0 := lo.x
		var y0 := lo.y
		var z0 := lo.z
		var x1 := hi.x
		var y1 := hi.y
		var z1 := hi.z
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, col)
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.FORWARD, col)
		quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, col)
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN, col)
		quad(Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3.LEFT, col)
		quad(Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3.RIGHT, col)

	func faces() -> int:
		return indices.size() / 3

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if verts.is_empty():
			return m
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


func _ready() -> void:
	# The plane viewport draws the figures; they must repaint whenever they
	# change, whether or not the 2D view "sees" them.
	Figure.always = true
	_lite = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var game: SubViewport = main.game
	game.positional_shadow_atlas_size = 4096
	game.use_debanding = true
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		game.msaa_3d = Viewport.MSAA_4X
	_wet_noise = _noise(3, 0.02)
	_stone_mat = _stone(Color(1, 1, 1), 0.45)
	_hide_2d()
	_environment()
	_camera()
	_build_level()
	_build_veil()
	_build_city()
	_build_lights()
	_build_plane()
	_build_rain()
	_build_drips()
	_build_probes()
	world.level.burnt.connect(func(_cells): _build_veil())
	fit()


# --- Setup -------------------------------------------------------------------

## The 2D night's own look is switched off; its plane things are moved to
## the plane viewport's layer.
func _hide_2d() -> void:
	var lv = world.level
	lv.ground.visible = false
	lv.back_wall.visible = false
	var water: CanvasItem = lv.get_node_or_null("Water")
	if water:
		water.visible = false
	for n in ["Night", "Moon", "Weather"]:
		var item: CanvasItem = world.get_node(n)
		item.visible = false
	for l in world.find_children("*", "Light2D", true, false):
		l.visible = false
	world.visibility_layer = OVERLAY | ON_PLANE
	lv.visibility_layer = OVERLAY | ON_PLANE
	_set_layer(lv.entities, ON_PLANE)
	_set_layer(world.player, ON_PLANE)
	_set_layer(world.get_node("FxShaded"), ON_PLANE)
	var game: SubViewport = main.game
	game.canvas_cull_mask = OVERLAY
	main.get_node("View/Game/BackdropLayer").visible = false


func _set_layer(node: Node, layer: int) -> void:
	if node is Viewport:
		return
	if node is CanvasItem:
		(node as CanvasItem).visibility_layer = layer
	for child in node.get_children():
		_set_layer(child, layer)


func _noise(seed_value: int, frequency: float, normal := false) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = frequency
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	t.generate_mipmaps = true
	t.as_normal_map = normal
	t.bump_strength = 6.0
	return t


func _stone(tint: Color, puddles: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STONE
	for part in ["albedo", "normal", "rough"]:
		m.set_shader_parameter("wall_" + part, load("res://assets/3d/stone_%s.png" % part))
		m.set_shader_parameter("top_" + part, load("res://assets/3d/cobble_%s.png" % part))
	m.set_shader_parameter("wet_noise", _wet_noise)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("puddles", puddles)
	return m


func _wood() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/3d/wood_albedo.png")
	m.normal_enabled = true
	m.normal_texture = load("res://assets/3d/wood_normal.png")
	m.roughness_texture = load("res://assets/3d/wood_rough.png")
	m.roughness = 0.55
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.albedo_color = Color(0.75, 0.75, 0.75)
	return m


## Adds a mesh with its material; nothing for an empty mesh (returns null).
func _add_mesh(mesh: Mesh, material: Material, parent: Node = self) -> MeshInstance3D:
	if mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	parent.add_child(mi)
	return mi


func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY
	sky_mat.set_shader_parameter("clouds", _noise(5, 0.012))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	# A cold ambient, so what the moon and lamps don't reach is deep blue
	# rather than black.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.19, 0.27)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Depth fog starts at the gameplay plane, so the play space stays clear
	# and everything behind it sinks into the night.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	# Lighter than the buildings, so the rows behind stand out as layered
	# silhouettes, each paler than the last.
	env.fog_light_color = Color(0.1, 0.12, 0.17)
	env.fog_depth_begin = 16.0
	env.fog_depth_end = 80.0
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.5
	# Thin enough not to haze the play space, thick enough that lamps and
	# the moon throw shafts through it.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.7, 0.75, 0.85)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.1
	env.volumetric_fog_temporal_reprojection_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.68, 0.92)
	moon.light_energy = 1.1
	moon.light_angular_distance = 0.8
	moon.light_volumetric_fog_energy = 2.0
	moon.shadow_enabled = true
	moon.shadow_blur = 1.5
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if _lite else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.directional_shadow_max_distance = 40.0 if _lite else 90.0
	moon.basis = Basis.looking_at(-MOON_DIR.normalized(), Vector3.UP)
	add_child(moon)
	_shadowed.append(moon)

	# The glow of the city on the near side: a faint cool fill from over
	# your shoulder, so the fronts of things read instead of going black.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.45, 0.52, 0.75)
	fill.light_energy = 0.22
	fill.light_volumetric_fog_energy = 0.0
	fill.basis = Basis.looking_at(Vector3(0.35, -0.45, -1.0).normalized(), Vector3.UP)
	add_child(fill)


func _camera() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.5
	camera.far = 400.0
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_transition = 30.0
	attrs.dof_blur_amount = 0.05
	camera.attributes = attrs
	add_child(camera)
	camera.current = true


# --- The level ---------------------------------------------------------------

## Built in chunks of CHUNK columns, so each light (and each shadow pass)
## only draws the stone near it.
func _build_level() -> void:
	var lv = world.level
	var w: int = lv.size_tiles.x
	var h: int = lv.size_tiles.y
	var water_mat := ShaderMaterial.new()
	water_mat.shader = WATER
	water_mat.set_shader_parameter("ripples", _noise(9, 0.03, true))
	var back_mat := _stone(Color(0.62, 0.6, 0.6), 0.0)
	var wood_mat := _wood()
	var solid := func(c: int, r: int) -> bool: return lv.kind_at(Vector2i(c, r)) == "stone"
	counts.stone_faces = 0
	counts.back_faces = 0
	for c0 in range(0, w, CHUNK):
		var stone := Builder.new()
		var back := Builder.new()
		var wood := Builder.new()
		var water := Builder.new()
		for r in h:
			for c in range(c0, mini(w, c0 + CHUNK)):
				_build_cell(lv, c, r, h, solid, stone, back, wood, water)
		_add_mesh(stone.mesh(), _stone_mat)
		_add_mesh(back.mesh(), back_mat)
		_add_mesh(wood.mesh(), wood_mat)
		_add_mesh(water.mesh(), water_mat)
		counts.stone_faces += stone.faces()
		counts.back_faces += back.faces()


func _build_cell(lv, c: int, r: int, h: int, solid: Callable, stone: Builder, back: Builder, wood: Builder, water: Builder) -> void:
	var cell := Vector2i(c, r)
	var k: String = lv.kind_at(cell)
	var x0 := float(c)
	var x1 := float(c + 1)
	var yt := -float(r)
	var yb := -float(r + 1)
	match k:
		"stone":
			stone.quad(Vector3(x0, yt, FRONT), Vector3(x1, yt, FRONT), Vector3(x1, yb, FRONT), Vector3(x0, yb, FRONT), Vector3.BACK)
			if not solid.call(c, r - 1):
				stone.quad(Vector3(x0, yt, -BACK), Vector3(x1, yt, -BACK), Vector3(x1, yt, FRONT), Vector3(x0, yt, FRONT), Vector3.UP)
			if r + 1 < h and not solid.call(c, r + 1):
				stone.quad(Vector3(x0, yb, -BACK), Vector3(x1, yb, -BACK), Vector3(x1, yb, FRONT), Vector3(x0, yb, FRONT), Vector3.DOWN)
			if not solid.call(c - 1, r):
				stone.quad(Vector3(x0, yt, -BACK), Vector3(x0, yt, FRONT), Vector3(x0, yb, FRONT), Vector3(x0, yb, -BACK), Vector3.LEFT)
			if not solid.call(c + 1, r):
				stone.quad(Vector3(x1, yt, -BACK), Vector3(x1, yt, FRONT), Vector3(x1, yb, FRONT), Vector3(x1, yb, -BACK), Vector3.RIGHT)
		"walkway":
			wood.box(Vector3(x0, yt - 0.14, -1.1), Vector3(x1, yt, 0.75))
		"water":
			var top := yt
			if lv.kind_at(Vector2i(c, r - 1)) != "water":
				top = yt - 0.15
				water.quad(Vector3(x0, top, -BACK), Vector3(x1, top, -BACK), Vector3(x1, top, FRONT), Vector3(x0, top, FRONT), Vector3.UP)
			water.quad(Vector3(x0, top, FRONT), Vector3(x1, top, FRONT), Vector3(x1, yb, FRONT), Vector3(x0, yb, FRONT), Vector3.BACK)
	if lv.back_wall.get_cell_source_id(cell) != -1:
		back.quad(Vector3(x0, yt, -BACK), Vector3(x1, yt, -BACK), Vector3(x1, yb, -BACK), Vector3(x0, yb, -BACK), Vector3.BACK)


## The veils, rebuilt whenever one burns: two thin sheets across the
## doorway, so it reads as a membrane you half see through.
func _build_veil() -> void:
	if _veil:
		_veil.queue_free()
		_veil = null
	if _veil_mat == null:
		_veil_mat = ShaderMaterial.new()
		_veil_mat.shader = VEIL
		_veil_mat.set_shader_parameter("crawl", _noise(13, 0.03))
	var lv = world.level
	var w: int = lv.size_tiles.x
	var h: int = lv.size_tiles.y
	var b := Builder.new()
	var cells := 0
	for r in h:
		for c in w:
			if lv.kind_at(Vector2i(c, r)) == "veil":
				for z in [-0.35, 0.35]:
					b.quad(Vector3(c, -r, z), Vector3(c + 1, -r, z), Vector3(c + 1, -(r + 1), z), Vector3(c, -(r + 1), z), Vector3.BACK)
				cells += 1
	counts.veil = cells
	if cells > 0:
		_veil = _add_mesh(b.mesh(), _veil_mat)
		_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The city behind: three rows of houses (nearer ones shorter), gabled or
## flat, windows lit here and there; the church spire over the plaza; and
## the ground they stand on.
func _build_city() -> void:
	_city = Node3D.new()
	add_child(_city)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1850
	var w: float = world.level.size_tiles.x
	var wall_mat := _stone(Color(0.55, 0.55, 0.6), 0.3)
	var roof_mat := _stone(Color(0.38, 0.38, 0.42), 0.0)
	var win_mat := ShaderMaterial.new()
	win_mat.shader = WINDOWS
	# The ground the city stands on: it only receives shadows.
	var ground := Builder.new()
	ground.box(Vector3(-90, -46, -260), Vector3(w + 90, STREET, -BACK - 0.05))
	var g := _add_mesh(ground.mesh(), wall_mat, _city)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var buildings := 0
	# z of the frontage, depth, lowest and highest height. Only the nearest
	# row throws shadows that land anywhere you'd see.
	var row_index := 0
	for row in [[-7.0, 5.0, 5.0, 11.0], [-17.0, 7.0, 8.0, 17.0], [-38.0, 12.0, 12.0, 26.0]]:
		var z: float = row[0]
		var depth: float = row[1]
		var x := -80.0
		var walls := Builder.new()
		var roofs := Builder.new()
		var windows := Builder.new()
		var chunk_end := x + CITY_CHUNK
		while x < w + 80.0:
			if x >= chunk_end:
				_add_city_chunk(walls, roofs, windows, wall_mat, roof_mat, win_mat, row_index == 0 and not _lite)
				walls = Builder.new()
				roofs = Builder.new()
				windows = Builder.new()
				chunk_end += CITY_CHUNK
			var bw := rng.randf_range(4.0, 8.5)
			var bh := rng.randf_range(row[2], row[3])
			var front := z + rng.randf_range(-0.6, 0.6)
			walls.box(Vector3(x, STREET - 2.0, front - depth), Vector3(x + bw, STREET + bh, front))
			var top := STREET + bh
			if rng.randf() < 0.6:
				# A gable along the street.
				var ridge := top + bw * rng.randf_range(0.3, 0.5)
				var mid := front - depth / 2.0
				roofs.quad(Vector3(x - 0.2, top, front + 0.3), Vector3(x + bw + 0.2, top, front + 0.3), Vector3(x + bw + 0.2, ridge, mid), Vector3(x - 0.2, ridge, mid), Vector3(0, 0.7, 0.7).normalized())
				roofs.quad(Vector3(x - 0.2, top, front - depth - 0.3), Vector3(x + bw + 0.2, top, front - depth - 0.3), Vector3(x + bw + 0.2, ridge, mid), Vector3(x - 0.2, ridge, mid), Vector3(0, 0.7, -0.7).normalized())
				roofs.tri(Vector3(x, top, front), Vector3(x, ridge, mid), Vector3(x, top, front - depth), Vector3.LEFT)
				roofs.tri(Vector3(x + bw, top, front), Vector3(x + bw, ridge, mid), Vector3(x + bw, top, front - depth), Vector3.RIGHT)
			elif rng.randf() < 0.7:
				# Chimney stacks.
				var cx := x + rng.randf_range(0.5, bw - 1.2)
				walls.box(Vector3(cx, top, front - depth * 0.6), Vector3(cx + 0.7, top + rng.randf_range(1.0, 2.2), front - depth * 0.6 + 0.7))
			# Windows, a few lit; one in six of those flickers.
			var floor_y := STREET + 1.6
			while floor_y < top - 1.4:
				var wx := x + 0.8
				while wx < x + bw - 1.2:
					if rng.randf() < 0.16:
						var col := Color(rng.randf_range(0.35, 0.9), rng.randf() if rng.randf() < 0.17 else 0.0, 0.0)
						windows.quad(Vector3(wx, floor_y + 0.85, front + 0.03), Vector3(wx + 0.45, floor_y + 0.85, front + 0.03), Vector3(wx + 0.45, floor_y, front + 0.03), Vector3(wx, floor_y, front + 0.03), Vector3.BACK, col)
					wx += 1.6
				floor_y += 3.0
			buildings += 1
			x += bw + (rng.randf_range(1.0, 3.0) if rng.randf() < 0.15 else 0.0)
		_add_city_chunk(walls, roofs, windows, wall_mat, roof_mat, win_mat, row_index == 0 and not _lite)
		row_index += 1
	# The church, a landmark over the plaza: a tower and its spire.
	var walls := Builder.new()
	var roofs := Builder.new()
	var windows := Builder.new()
	var cx := 128.0
	var cz := -26.0
	walls.box(Vector3(cx - 3.5, STREET - 2.0, cz - 7.0), Vector3(cx + 3.5, STREET + 30.0, cz))
	var apex := Vector3(cx, STREET + 52.0, cz - 3.5)
	var corners := [Vector3(cx - 3.5, STREET + 30.0, cz), Vector3(cx + 3.5, STREET + 30.0, cz), Vector3(cx + 3.5, STREET + 30.0, cz - 7.0), Vector3(cx - 3.5, STREET + 30.0, cz - 7.0)]
	var middle := Vector3(cx, STREET + 30.0, cz - 3.5)
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var n := (b - a).cross(apex - a).normalized()
		if n.dot((a + b) * 0.5 - middle) < 0.0:
			n = -n
		roofs.tri(a, b, apex, n)
	windows.quad(Vector3(cx - 0.6, STREET + 24.0, cz + 0.03), Vector3(cx + 0.6, STREET + 24.0, cz + 0.03), Vector3(cx + 0.6, STREET + 21.0, cz + 0.03), Vector3(cx - 0.6, STREET + 21.0, cz + 0.03), Vector3.BACK, Color(0.8, 0.0, 0.0))
	_add_city_chunk(walls, roofs, windows, wall_mat, roof_mat, win_mat, false)
	counts.buildings = buildings


func _add_city_chunk(walls: Builder, roofs: Builder, windows: Builder, wall_mat: Material, roof_mat: Material, win_mat: Material, shadows: bool) -> void:
	var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for part in [[walls, wall_mat], [roofs, roof_mat]]:
		var mi := _add_mesh(part[0].mesh(), part[1], _city)
		if mi:
			mi.cast_shadow = cast
	var lit := _add_mesh(windows.mesh(), win_mat, _city)
	if lit:
		lit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Lights ------------------------------------------------------------------

func _omni(color: Color, energy: float, radius: float, shadow: bool) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadow and not _lite
	l.light_size = 0.12
	l.light_volumetric_fog_energy = 2.5
	add_child(l)
	if shadow and not _lite:
		_shadowed.append(l)
	return l


func _build_lights() -> void:
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(1.0, 0.72, 0.4) * 4.0
	for lamp in world.lamps:
		var at := _to_3d(lamp.position + Vector2(0, -68), 0.5)
		var light := _omni(Color(1.0, 0.7, 0.4), 5.0, 9.0, true)
		light.position = at
		var bulb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.14
		sphere.height = 0.28
		bulb.mesh = sphere
		bulb.material_override = glass
		bulb.position = _to_3d(lamp.position + Vector2(0, -68), 0.05)
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bulb)
		_lamps.append({"lamp": lamp, "light": light, "bulb": bulb})
	_lantern = _omni(Color(1.0, 0.74, 0.46), 2.0, 5.0, true)
	# A faint cold fill so you can always read the Lamplighter.
	_fill = _omni(Color(0.7, 0.78, 1.0), 0.5, 4.0, false)
	_fill.light_volumetric_fog_energy = 0.0
	_pile = _omni(Color(1.0, 0.72, 0.4), 1.6, 3.5, false)
	for it in world.pickups:
		var l := _omni(Color(1.0, 0.85, 0.8), 0.9, 1.6, false)
		l.position = _to_3d(it.position + Vector2(0, -14), 0.4)
		_finds.append({"find": it, "light": l})
	counts.lamp_lights = _lamps.size()


## A point in the 2D world (px, y down) at depth z (m) in the 3D stage.
func _to_3d(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x / PX, -p.y / PX, z)


# --- The plane ---------------------------------------------------------------

func _build_plane() -> void:
	var game: SubViewport = main.game
	plane_vp = SubViewport.new()
	plane_vp.transparent_bg = true
	plane_vp.disable_3d = true
	plane_vp.world_2d = game.world_2d
	plane_vp.canvas_cull_mask = ON_PLANE
	plane_vp.size_2d_override_stretch = true
	plane_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(plane_vp)
	plane = MeshInstance3D.new()
	plane.mesh = QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = PLANE
	m.set_shader_parameter("plane", plane_vp.get_texture())
	plane.material_override = m
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	plane.layers = MOVING
	add_child(plane)


# --- Rain --------------------------------------------------------------------

func _rain_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.3)
	m.roughness = 0.15
	m.emission_enabled = true
	m.emission = Color(0.45, 0.5, 0.6)
	m.emission_energy_multiplier = 0.12
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 1500 if _lite else 4000
	_rain.lifetime = 1.5
	_rain.preprocess = 1.5
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Only on the open side of the cutaway: from the city back to the front
	# of the street, never in front of the rooms cut open.
	pm.emission_box_extents = Vector3(18.0, 0.5, 6.5)
	pm.direction = Vector3(-0.12, -1.0, 0.0)
	pm.spread = 2.0
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 17.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.016, 0.5)
	drop.material = _rain_material()
	_rain.draw_pass_1 = drop
	_rain.layers = MOVING
	add_child(_rain)
	# Rain stops where it lands: on roofs, streets, ledges.
	var ground := GPUParticlesCollisionHeightField3D.new()
	ground.size = Vector3(60.0, 50.0, 30.0)
	ground.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	ground.follow_camera_enabled = true
	add_child(ground)


## Water dripping off the underside of every ledge and ceiling: one emitter,
## its points spread through the level.
func _build_drips() -> void:
	var lv = world.level
	var w: int = lv.size_tiles.x
	var h: int = lv.size_tiles.y
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var points := PackedVector3Array()
	for r in h - 1:
		for c in w:
			if lv.kind_at(Vector2i(c, r)) != "stone" or lv.kind_at(Vector2i(c, r + 1)) != "":
				continue
			if rng.randf() < 0.8:
				points.append(Vector3(c + rng.randf(), -(r + 1) - 0.03, rng.randf_range(-BACK + 0.3, FRONT - 0.15)))
	counts.drips = points.size()
	if points.is_empty():
		return
	var img := Image.create_empty(points.size(), 1, false, Image.FORMAT_RGBF)
	for i in points.size():
		var p := points[i]
		img.set_pixel(i, 0, Color(p.x, p.y, p.z))
	_drips = GPUParticles3D.new()
	_drips.amount = mini(points.size() * 2, 800)
	_drips.lifetime = 2.2
	_drips.preprocess = 2.2
	_drips.local_coords = false
	_drips.visibility_aabb = AABB(Vector3(-5, -40, -10), Vector3(w + 10, 45, 20))
	_drips.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = points.size()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_drips.process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.025, 0.09)
	drop.material = _rain_material()
	_drips.draw_pass_1 = drop
	_drips.layers = MOVING
	add_child(_drips)


## Indoors (wherever the level has a back wall) wet floors should reflect
## the room, not the open sky. Indoor cells are grouped into boxes (runs of
## rows with about the same span), each with an interior reflection probe,
## captured once without the moving things.
func _build_probes() -> void:
	var lv = world.level
	var w: int = lv.size_tiles.x
	var h: int = lv.size_tiles.y
	var boxes := []
	var growing := []
	for r in h:
		var next := []
		var c := 0
		while c < w:
			if lv.back_wall.get_cell_source_id(Vector2i(c, r)) == -1:
				c += 1
				continue
			var start := c
			while c < w and lv.back_wall.get_cell_source_id(Vector2i(c, r)) != -1:
				c += 1
			var joined = null
			for b in growing:
				if absi(b[2] - start) <= 2 and absi(b[3] - c) <= 2:
					joined = b
					break
			if joined:
				growing.erase(joined)
				joined[1] = r
				joined[2] = mini(joined[2], start)
				joined[3] = maxi(joined[3], c)
			else:
				# [first row, last row, first column, column past the end]
				joined = [r, r, start, c]
				boxes.append(joined)
			next.append(joined)
		growing = next
	for b in boxes:
		var r0: int = b[0]
		var r1: int = b[1]
		var c0: int = b[2]
		var c1: int = b[3]
		var p := ReflectionProbe.new()
		p.size = Vector3(c1 - c0 + 0.6, r1 - r0 + 1.6, BACK + FRONT + 1.0)
		p.position = Vector3((c0 + c1) * 0.5, -(r0 + r1 + 1) * 0.5, (FRONT - BACK) * 0.5)
		p.interior = true
		p.box_projection = true
		p.update_mode = ReflectionProbe.UPDATE_ONCE
		p.ambient_mode = ReflectionProbe.AMBIENT_COLOR
		p.ambient_color = Color(0.11, 0.11, 0.14)
		p.ambient_color_energy = 0.6
		p.blend_distance = 0.5
		p.cull_mask = 0xFFFFF & ~MOVING
		add_child(p)
	counts.probes = boxes.size()


# --- Every frame -------------------------------------------------------------

## Matches the plane viewport and the camera to the game view (call when the
## view or the render scale changes).
func fit() -> void:
	var game: SubViewport = main.game
	plane_vp.size = game.size
	plane_vp.size_2d_override = game.size_2d_override
	var view: Vector2 = world.view_size()
	_cam_z = view.y / PX * 0.5 / tan(deg_to_rad(FOV * 0.5))
	var quad: QuadMesh = plane.mesh
	quad.size = view / PX
	var m: ShaderMaterial = plane.material_override
	m.set_shader_parameter("reach", 3.0 * float(main.render_scale))
	var attrs: CameraAttributesPractical = camera.attributes
	attrs.dof_blur_far_distance = _cam_z + 12.0


func _process(delta: float) -> void:
	_time += delta
	var view: Vector2 = world.view_size()
	var center: Vector2 = world.cam_center
	var shake: Vector2 = world.camera.offset
	camera.position = Vector3((center.x + shake.x) / PX, -(center.y + shake.y) / PX, _cam_z)
	plane.position = Vector3(center.x / PX, -center.y / PX, 0.0)
	plane_vp.canvas_transform = Transform2D(0.0, -(center - view / 2.0))
	_rain.position = Vector3(camera.position.x, camera.position.y + view.y / PX * 0.5 + 4.0, FRONT - 6.6)
	_update_lights()


func _update_lights() -> void:
	for e in _lamps:
		var lamp = e.lamp
		var light: OmniLight3D = e.light
		var bulb: MeshInstance3D = e.bulb
		light.visible = lamp.lit
		bulb.visible = lamp.lit
		var x: float = lamp.position.x
		light.light_energy = 5.0 * (1.0 + sin(_time * 11.0 + x) * sin(_time * 6.7 + x * 2.0) * 0.05)
	var p = world.player
	var flame: Vector2 = p.flame_at()
	var burns: bool = p.form_data().burns
	_lantern.position = _to_3d(flame, 0.45)
	_lantern.light_energy = (3.4 if burns else 1.9) * (1.0 + sin(_time * 11.0) * sin(_time * 6.7) * 0.06)
	_lantern.omni_range = 7.0 if burns else 4.5
	_lantern.visible = p.state != "dead" or p.t < 1.4
	_fill.position = _to_3d(p.position + Vector2(0, -30), 2.2)
	_fill.visible = _lantern.visible
	_pile.visible = not world.pile.is_empty()
	if _pile.visible:
		_pile.position = _to_3d(world.pile.pos + Vector2(0, -14), 0.5)
	for e in _finds:
		var light: OmniLight3D = e.light
		light.visible = not e.find.taken


## Switches a part of the stage on or off (the benchmark measures each).
func set_feature(feature: String, on: bool) -> void:
	match feature:
		"shadows":
			for l in _shadowed:
				l.shadow_enabled = on
		"fog":
			env.volumetric_fog_enabled = on
			env.fog_enabled = on
		"reflections":
			env.ssr_enabled = on
			env.ssao_enabled = on
		"glow":
			env.glow_enabled = on
		"rain":
			_rain.visible = on
			if _drips:
				_drips.visible = on
		"city":
			_city.visible = on
		"plane":
			plane.visible = on
			plane_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
