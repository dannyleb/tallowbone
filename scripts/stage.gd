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
const Storm = preload("res://scripts/storm.gd")
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
## 3D render layer for surfaces inside rooms (facing a cell with a back
## wall): the moon doesn't light it, so no moonlight leaks indoors through
## shadow-map seams.
const INDOOR := 4
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
## Lightning and what it shows (scripts/storm.gd).
var storm
## Rooftops of the middle row of houses, where the watchers stand:
## [x from, x to, top y, z] (m).
var roofs := []
## What got built, for the playtest.
var counts := {}
## How much of the night is drawn (QUALITY): 0 everything, 1 Balanced (no
## bounce light or screen reflections, no MSAA, street lamps without
## shadows, two moon-shadow splits), 2 Fast (also no volumetric fog or
## mist, no ambient occlusion, no lantern shadow). The pause menu sets it;
## main steps it down when frames stay slow at the lowest render scale.
const QUALITY := ["High", "Balanced", "Fast"]
var quality := 0
var _mist: Array[FogVolume] = []

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
## Where drainpipes empty onto the street (filled by _build_city).
var _pours := PackedVector3Array()
var _splashes: GPUParticles3D
var _pour: GPUParticles3D
var _moths: GPUParticles3D
var _moth_count := -1
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
	var started := Time.get_ticks_msec()
	_lite = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var game: SubViewport = main.game
	game.positional_shadow_atlas_size = 4096
	game.use_debanding = true
	# 4x: with 2x, depth of field read the depth wrong and blurred everything.
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
	_build_splashes()
	_build_pours()
	_build_moths()
	_build_mist()
	_build_probes()
	storm = Storm.new()
	storm.stage = self
	add_child(storm)
	_prewarm()
	if main.ambience:
		main.ambience.lightning.connect(storm.flash)
	world.level.burnt.connect(func(_cells): _build_veil())
	fit()
	counts.build_ms = Time.get_ticks_msec() - started
	print("3D stage built in %d ms" % counts.build_ms)


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


## Wet stone (shaders/stone3d.gdshader): `wall` on the sides, `top` on
## anything facing up (assets/3d/<set>_*).
func _stone(tint: Color, puddles: float, wall := "stone", top := "cobble") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STONE
	for part in ["albedo", "normal", "rough"]:
		m.set_shader_parameter("wall_" + part, load("res://assets/3d/%s_%s.png" % [wall, part]))
		m.set_shader_parameter("top_" + part, load("res://assets/3d/%s_%s.png" % [top, part]))
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
	env.ambient_light_energy = 1.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.25
	env.tonemap_white = 6.0
	env.ssr_enabled = true
	env.ssr_max_steps = 32
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	# Light bouncing off what it hits (lamplight warming the walls round a
	# lamp, the floor under the lantern): desktop only.
	env.ssil_enabled = not _lite
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# The grade: a little more contrast, a little less colour, shadows
	# cooled toward blue and highlights warmed toward lamplight.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.86
	env.adjustment_color_correction = _grade()
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
	moon.directional_shadow_max_distance = 40.0 if _lite else 64.0
	moon.basis = Basis.looking_at(-MOON_DIR.normalized(), Vector3.UP)
	moon.light_cull_mask = 0xFFFFF & ~INDOOR
	add_child(moon)
	_shadowed.append(moon)

	# The glow of the city on the near side: a faint cool fill from over
	# your shoulder, so the fronts of things read instead of going black.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.45, 0.52, 0.75)
	fill.light_energy = 0.45
	fill.light_volumetric_fog_energy = 0.0
	fill.basis = Basis.looking_at(Vector3(0.35, -0.45, -1.0).normalized(), Vector3.UP)
	add_child(fill)


## The colour grade's curves: per channel, input level -> output.
func _grade() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.5, 0.85, 1.0])
	g.colors = PackedColorArray([
		Color(0.012, 0.014, 0.022), Color(0.125, 0.135, 0.158), Color(0.5, 0.505, 0.51),
		Color(0.87, 0.85, 0.8), Color(1.0, 0.98, 0.94),
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


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
	var iron_mat := _iron()
	var vine_mat := _vine()
	var solid := func(c: int, r: int) -> bool: return lv.kind_at(Vector2i(c, r)) == "stone"
	counts.stone_faces = 0
	counts.back_faces = 0
	for c0 in range(0, w, CHUNK):
		var stone := Builder.new()
		var inner := Builder.new()
		var back := Builder.new()
		var wood := Builder.new()
		var water := Builder.new()
		var iron := Builder.new()
		var vines := Builder.new()
		for r in h:
			for c in range(c0, mini(w, c0 + CHUNK)):
				_build_cell(lv, c, r, h, solid, stone, inner, back, wood, water)
				if not _lite:
					_dress_cell(lv, c, r, solid, stone, inner, iron)
					_overgrow(lv, c, r, solid, stone, vines, iron)
					_culvert(lv, c, r, solid, stone, water, iron)
		# The stone is open at the back and the back walls are single quads
		# facing you, and the moon shines from behind: both cast shadows from
		# either side, or moonlight leaks into the rooms underground.
		for part in [[stone, _stone_mat, 1], [inner, _stone_mat, INDOOR], [back, back_mat, INDOOR]]:
			var mi := _add_mesh(part[0].mesh(), part[1])
			if mi:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
				mi.layers = part[2]
		_add_mesh(wood.mesh(), wood_mat)
		_add_mesh(water.mesh(), water_mat)
		_add_mesh(vines.mesh(), vine_mat)
		var rails := _add_mesh(iron.mesh(), iron_mat)
		if rails:
			rails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		counts.stone_faces += stone.faces() + inner.faces()
		counts.back_faces += back.faces()


func _build_cell(lv, c: int, r: int, h: int, solid: Callable, stone: Builder, inner: Builder, back: Builder, wood: Builder, water: Builder) -> void:
	var cell := Vector2i(c, r)
	var k: String = lv.kind_at(cell)
	var x0 := float(c)
	var x1 := float(c + 1)
	var yt := -float(r)
	var yb := -float(r + 1)
	# Stone reaches a little behind the back walls, and back walls overlap
	# their neighbours, so no moonlight slips through the joints.
	var zb := -BACK - 0.08
	# A face looking into a room goes in the indoor mesh.
	var side := func(dc: int, dr: int) -> Builder: return inner if lv.back_wall.get_cell_source_id(Vector2i(c + dc, r + dr)) != -1 else stone
	match k:
		"stone":
			stone.quad(Vector3(x0, yt, FRONT), Vector3(x1, yt, FRONT), Vector3(x1, yb, FRONT), Vector3(x0, yb, FRONT), Vector3.BACK)
			if not solid.call(c, r - 1):
				side.call(0, -1).quad(Vector3(x0, yt, zb), Vector3(x1, yt, zb), Vector3(x1, yt, FRONT), Vector3(x0, yt, FRONT), Vector3.UP)
			if r + 1 < h and not solid.call(c, r + 1):
				side.call(0, 1).quad(Vector3(x0, yb, zb), Vector3(x1, yb, zb), Vector3(x1, yb, FRONT), Vector3(x0, yb, FRONT), Vector3.DOWN)
			if not solid.call(c - 1, r):
				side.call(-1, 0).quad(Vector3(x0, yt, zb), Vector3(x0, yt, FRONT), Vector3(x0, yb, FRONT), Vector3(x0, yb, zb), Vector3.LEFT)
			if not solid.call(c + 1, r):
				side.call(1, 0).quad(Vector3(x1, yt, zb), Vector3(x1, yt, FRONT), Vector3(x1, yb, FRONT), Vector3(x1, yb, zb), Vector3.RIGHT)
		"walkway":
			wood.box(Vector3(x0, yt - 0.14, -1.1), Vector3(x1, yt, 0.75))
		"water":
			var top := yt
			if lv.kind_at(Vector2i(c, r - 1)) != "water":
				top = yt - 0.15
				water.quad(Vector3(x0, top, -BACK), Vector3(x1, top, -BACK), Vector3(x1, top, FRONT), Vector3(x0, top, FRONT), Vector3.UP)
			water.quad(Vector3(x0, top, FRONT), Vector3(x1, top, FRONT), Vector3(x1, yb, FRONT), Vector3(x0, yb, FRONT), Vector3.BACK)
	if lv.back_wall.get_cell_source_id(cell) != -1:
		back.quad(Vector3(x0 - 0.03, yt + 0.06, -BACK), Vector3(x1 + 0.03, yt + 0.06, -BACK), Vector3(x1 + 0.03, yb - 0.06, -BACK), Vector3(x0 - 0.03, yb - 0.06, -BACK), Vector3.BACK)


## The masonry around the play: a coping stone along the front of every
## ledge (its lip throws a line of shadow), pilasters at a steady rhythm
## down the big stone fronts, and iron railings along the back of the
## walkways, behind you. Desktop only.
func _dress_cell(lv, c: int, r: int, solid: Callable, stone: Builder, inner: Builder, iron: Builder) -> void:
	var k: String = lv.kind_at(Vector2i(c, r))
	var x0 := float(c)
	var x1 := float(c + 1)
	var yt := -float(r)
	var yb := -float(r + 1)
	if k == "stone":
		var into: Builder = inner if lv.back_wall.get_cell_source_id(Vector2i(c, r - 1)) != -1 else stone
		var open_above: bool = not solid.call(c, r - 1) and lv.kind_at(Vector2i(c, r - 1)) != "veil"
		if open_above:
			var lip := 0.06 + _hash(c, r) * 0.07
			var drop := 0.15 + _hash(c + 7, r) * 0.07
			into.box(Vector3(x0 - 0.01, yt - drop, FRONT), Vector3(x1 + 0.01, yt - 0.004, FRONT + lip))
		if c % 6 == 3 and solid.call(c, r + 1):
			var top := yt - (0.24 if open_above else 0.0)
			stone.box(Vector3(x0 + 0.15, yb, FRONT), Vector3(x0 + 0.8, top, FRONT + 0.1))
		elif _hash(c * 3, r * 5) < 0.45:
			# A stone or two sitting proud of the face, for the light to catch.
			for i in 1 + int(_hash(c, r * 7) * 2.0):
				var sx := x0 + _hash(c + i * 13, r) * 0.6
				var sy := yb + 0.08 + _hash(c, r + i * 17) * 0.62
				var sw := 0.22 + _hash(c + i, r + 3) * 0.3
				var sh := 0.12 + _hash(c + 5, r + i) * 0.12
				stone.box(Vector3(sx, sy, FRONT), Vector3(minf(sx + sw, x1), minf(sy + sh, yt - 0.02), FRONT + 0.015 + _hash(c + i * 7, r + 11) * 0.035))
	if lv.back_wall.get_cell_source_id(Vector2i(c, r)) != -1 and k == "":
		var zb := -BACK
		if c % 4 == 0:
			inner.box(Vector3(x0 + 0.1, yb - 0.02, zb), Vector3(x0 + 0.65, yt + 0.02, zb + 0.28))
		# Chains hanging from the vault here and there.
		if solid.call(c, r - 1) and c % 7 == 2:
			var length := 0.8 + _hash(c, r) * 1.2
			var links := int(length / 0.09)
			for i in links:
				var y := yt - i * 0.09
				var wide := i % 2 == 0
				iron.box(Vector3(x0 + 0.5 - (0.03 if wide else 0.008), y - 0.1, -2.3 - (0.008 if wide else 0.03)), Vector3(x0 + 0.5 + (0.03 if wide else 0.008), y, -2.3 + (0.008 if wide else 0.03)))
		# An arched rib springing from the pilasters, where the room's ceiling is.
		if solid.call(c, r - 1):
			var k4 := c % 4
			var drop: float = [0.55, 0.22, 0.08, 0.22][k4]
			inner.box(Vector3(x0, yt - drop - 0.18, zb), Vector3(x1, yt, zb + 0.22))
	if k == "walkway":
		var z := -1.0
		for i in 2:
			var px := x0 + 0.25 + i * 0.5
			iron.box(Vector3(px - 0.018, yt, z - 0.018), Vector3(px + 0.018, yt + 0.95, z + 0.018))
		iron.box(Vector3(x0, yt + 0.92, z - 0.03), Vector3(x1, yt + 0.97, z + 0.03))
		iron.box(Vector3(x0, yt + 0.12, z - 0.02), Vector3(x1, yt + 0.15, z + 0.02))


## Life and ruin on the masonry: creepers hanging over the open ledges in
## wandering strands, rubble along the back of the floors, now and then an
## iron drain grate in the street. Desktop only.
func _overgrow(lv, c: int, r: int, solid: Callable, stone: Builder, vines: Builder, iron: Builder) -> void:
	if lv.kind_at(Vector2i(c, r)) != "stone" or solid.call(c, r - 1):
		return
	var outdoors: bool = lv.back_wall.get_cell_source_id(Vector2i(c, r - 1)) == -1
	var yt := -float(r)
	# Creepers: a few strands over the lip, swaying out and back as they hang.
	if outdoors and _hash(c * 7, r * 3) < 0.22:
		for s in 2 + int(_hash(c, r * 11) * 4.0):
			var x := c + 0.1 + _hash(c + s * 5, r) * 0.8
			var length := 0.4 + _hash(c + s, r * 3) * 1.6
			var steps := int(length / 0.08)
			var phase := _hash(c * 3 + s, r) * TAU
			for i in steps:
				var y := yt - 0.05 - i * 0.08
				var dx := sin(i * 0.5 + phase) * 0.04
				var z := FRONT + 0.06 + absf(sin(i * 0.31 + phase)) * 0.05
				var leaf := 0.02 + 0.03 * absf(sin(i * 1.7 + phase * 2.0))
				vines.box(Vector3(x + dx - leaf, y - 0.08, z - 0.015), Vector3(x + dx + leaf, y, z + 0.015))
	# Rubble along the back of the floor, out of the way.
	if _hash(c * 5, r * 13) < 0.35:
		for i in 1 + int(_hash(c + 9, r) * 3.0):
			var x := c + _hash(c + i * 3, r + 1) * 0.85
			var z := -BACK + 0.15 + _hash(c, r + i * 5) * 0.9
			var s := 0.06 + _hash(c + i, r * 2) * 0.12
			stone.box(Vector3(x, yt - 0.01, z), Vector3(x + s * 1.4, yt + s * 0.7, z + s))
	# A drain grate in the street.
	if outdoors and _hash(c * 11, r * 7) < 0.06:
		var gx := c + 0.2
		for i in 6:
			iron.box(Vector3(gx + i * 0.1, yt, -0.6), Vector3(gx + i * 0.1 + 0.03, yt + 0.012, 0.3))


## A drain's mouth in a big stone front, every dozen metres or so where the
## wall is deep enough: a dark wet arch in a ring of voussoirs behind an
## iron grille, water pouring from its sill.
func _culvert(lv, c: int, r: int, solid: Callable, stone: Builder, water: Builder, iron: Builder) -> void:
	if c % 13 != 6:
		return
	for dc in [-1, 0, 1, 2]:
		for dr in [0, 1]:
			if not solid.call(c + dc, r + dr):
				return
	# Only below an open street: two rows of stone above, then air.
	if not (solid.call(c, r - 1) and solid.call(c, r - 2) and not solid.call(c, r - 3)):
		return
	var cx := c + 0.5
	var base := -float(r + 2) + 0.35
	var half := 0.85
	var spring := base + 0.9
	var z := FRONT + 0.01
	var segs := 10
	# The dark mouth: a rectangle below, a half-round above.
	water.quad(Vector3(cx - half, spring, z), Vector3(cx + half, spring, z), Vector3(cx + half, base, z), Vector3(cx - half, base, z), Vector3.BACK)
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		water.tri(Vector3(cx, spring, z), Vector3(cx + cos(a0) * half, spring + sin(a0) * half, z), Vector3(cx + cos(a1) * half, spring + sin(a1) * half, z), Vector3.BACK)
	# Voussoirs round the arch, a keystone proud at the top.
	for i in segs + 1:
		var a := PI * i / segs
		var p := Vector3(cx + cos(a) * (half + 0.13), spring + sin(a) * (half + 0.13), FRONT)
		var big := 0.11 if i == segs / 2 else 0.08
		stone.box(p - Vector3(big, big, 0), p + Vector3(big, big, 0.06 + (0.04 if i == segs / 2 else 0.0)))
	stone.box(Vector3(cx - half - 0.2, base - 0.12, FRONT), Vector3(cx + half + 0.2, base, FRONT + 0.14))
	# The grille.
	for i in 7:
		var bx := cx - half + 0.15 + i * (2.0 * half - 0.3) / 6.0
		var top := spring + sqrt(maxf(0.0, half * half - (bx - cx) * (bx - cx))) - 0.05
		iron.box(Vector3(bx - 0.018, base, FRONT + 0.05), Vector3(bx + 0.018, top, FRONT + 0.09))
	iron.box(Vector3(cx - half, spring - 0.05, FRONT + 0.05), Vector3(cx + half, spring, FRONT + 0.09))
	_pours.append(Vector3(cx, base + 0.05, FRONT + 0.16))
	counts.culverts = counts.get("culverts", 0) + 1


func _vine() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.11, 0.14, 0.08)
	m.roughness = 0.7
	return m


## A steady pseudo-random number in [0, 1) for a cell.
static func _hash(a: int, b: int) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


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


## The city behind: three rows of houses (nearer ones shorter), gabled,
## chimneyed or parapeted; a cornice under every eave. The nearer two rows
## get string courses between the floors and framed windows with sills,
## a few lit and the rest dark glass that catches the sky; the nearest row
## gets doors, and drainpipes pouring onto the street. Gas lamps burn along
## the street behind the district; the church spire stands over the plaza.
## The far row is only a skyline in the fog.
func _build_city() -> void:
	_city = Node3D.new()
	add_child(_city)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1850
	var w: float = world.level.size_tiles.x
	var win_mat := ShaderMaterial.new()
	win_mat.shader = WINDOWS
	var mats := {
		"walls": _stone(Color(0.8, 0.8, 0.84), 0.3, "brick", "cobble"),
		"roofs": _stone(Color(0.9, 0.9, 0.95), 0.0, "slate", "slate"),
		"trim": _stone(Color(0.62, 0.62, 0.66), 0.1),
		"glass": _glass(),
		"iron": _iron(),
		"wood": _wood(),
		"windows": win_mat,
	}
	# The ground the city stands on: it only receives shadows.
	var ground := Builder.new()
	ground.box(Vector3(-90, -46, -260), Vector3(w + 90, STREET, -BACK - 0.12))
	var g := _add_mesh(ground.mesh(), mats.walls, _city)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var buildings := 0
	# z of the frontage, depth, lowest and highest height. Low enough to
	# leave a band of sky over the rooftops (the moon, the storm, what the
	# storm shows); only the church stands into it. Only the nearest row
	# throws shadows that land anywhere you'd see.
	var row_index := 0
	for row in [[-7.0, 5.0, 4.0, 7.5], [-17.0, 7.0, 6.5, 11.0], [-38.0, 12.0, 9.0, 16.0]]:
		var z: float = row[0]
		var depth: float = row[1]
		var x := -80.0
		var b := _city_builders()
		var chunk_end := x + CITY_CHUNK
		var shadows := row_index == 0 and not _lite
		while x < w + 80.0:
			if x >= chunk_end:
				_add_city_chunk(b, mats, shadows)
				b = _city_builders()
				chunk_end += CITY_CHUNK
			var bw := rng.randf_range(4.0, 8.5)
			var bh := rng.randf_range(row[2], row[3])
			var front := z + rng.randf_range(-0.6, 0.6)
			_house(b, rng, x, bw, bh, front, depth, row_index)
			buildings += 1
			x += bw + (rng.randf_range(1.0, 3.0) if rng.randf() < 0.15 else 0.0)
		_add_city_chunk(b, mats, shadows)
		row_index += 1
	_gas_lamps(rng, w, mats)
	_far_spires(rng, w, mats)
	if not _lite:
		_street_clutter(rng, w, mats)
	# The church, a landmark over the plaza: a tower and its spire.
	var church := _city_builders()
	var cx := 128.0
	var cz := -26.0
	church.walls.box(Vector3(cx - 3.5, STREET - 2.0, cz - 7.0), Vector3(cx + 3.5, STREET + 30.0, cz))
	church.trim.box(Vector3(cx - 3.8, STREET + 29.4, cz - 7.3), Vector3(cx + 3.8, STREET + 30.2, cz + 0.3))
	church.trim.box(Vector3(cx - 3.7, STREET + 18.0, cz - 7.2), Vector3(cx + 3.7, STREET + 18.4, cz + 0.2))
	var apex := Vector3(cx, STREET + 52.0, cz - 3.5)
	var corners := [Vector3(cx - 3.5, STREET + 30.0, cz), Vector3(cx + 3.5, STREET + 30.0, cz), Vector3(cx + 3.5, STREET + 30.0, cz - 7.0), Vector3(cx - 3.5, STREET + 30.0, cz - 7.0)]
	var middle := Vector3(cx, STREET + 30.0, cz - 3.5)
	for i in 4:
		var a: Vector3 = corners[i]
		var c: Vector3 = corners[(i + 1) % 4]
		var n := (c - a).cross(apex - a).normalized()
		if n.dot((a + c) * 0.5 - middle) < 0.0:
			n = -n
		church.roofs.tri(a, c, apex, n)
	# Pinnacles at the tower's corners.
	for corner in corners:
		var k: Vector3 = corner
		church.trim.box(k + Vector3(-0.35, 0.0, -0.35), k + Vector3(0.35, 3.5, 0.35))
	church.windows.quad(Vector3(cx - 0.6, STREET + 24.0, cz + 0.03), Vector3(cx + 0.6, STREET + 24.0, cz + 0.03), Vector3(cx + 0.6, STREET + 21.0, cz + 0.03), Vector3(cx - 0.6, STREET + 21.0, cz + 0.03), Vector3.BACK, Color(0.8, 0.0, 0.0))
	_church_nave(church, cx + 3.5, cz)
	_add_city_chunk(church, mats, false)
	counts.buildings = buildings


## The church's nave, east of the tower: a long hall under a steep roof,
## buttresses between tall pointed windows (a few glowing like coals), a
## pinnacle on each buttress, and a rose window high on the tower's face.
func _church_nave(b: Dictionary, x0: float, cz: float) -> void:
	var x1 := x0 + 26.0
	var front := cz - 1.0
	var back := cz - 13.0
	var eave := STREET + 17.0
	var ridge := STREET + 27.0
	var mid := (front + back) * 0.5
	b.walls.box(Vector3(x0, STREET - 2.0, back), Vector3(x1, eave, front))
	b.roofs.quad(Vector3(x0, eave, front + 0.4), Vector3(x1 + 0.4, eave, front + 0.4), Vector3(x1 + 0.4, ridge, mid), Vector3(x0, ridge, mid), Vector3(0, 0.6, 0.8).normalized())
	b.roofs.tri(Vector3(x1, eave, front), Vector3(x1, ridge, mid), Vector3(x1, eave, back), Vector3.RIGHT)
	b.trim.box(Vector3(x0, eave - 0.5, front - 0.1), Vector3(x1, eave, front + 0.5))
	var bx := x0 + 1.0
	while bx < x1 - 1.0:
		# A buttress, stepped, its pinnacle.
		b.trim.box(Vector3(bx, STREET - 1.0, front), Vector3(bx + 0.9, STREET + 9.0, front + 1.8))
		b.trim.box(Vector3(bx + 0.1, STREET + 9.0, front), Vector3(bx + 0.8, eave + 0.8, front + 1.0))
		b.trim.box(Vector3(bx + 0.25, eave + 0.8, front + 0.25), Vector3(bx + 0.65, eave + 3.2, front + 0.65))
		# A lancet window in the bay beyond it.
		var wx := bx + 1.7
		if wx + 1.0 < x1 - 0.5:
			var glow := Color(0.35, 0.0, 0.0) if fmod(wx, 9.0) < 3.0 else Color(0.0, 0.0, 0.0)
			var z := front + 0.03
			var wy := STREET + 6.0
			if glow.r > 0.0:
				b.windows.quad(Vector3(wx, wy + 6.5, z), Vector3(wx + 1.0, wy + 6.5, z), Vector3(wx + 1.0, wy, z), Vector3(wx, wy, z), Vector3.BACK, glow)
				b.windows.tri(Vector3(wx, wy + 6.5, z), Vector3(wx + 1.0, wy + 6.5, z), Vector3(wx + 0.5, wy + 7.6, z), Vector3.BACK, glow)
			else:
				b.glass.quad(Vector3(wx, wy + 6.5, z), Vector3(wx + 1.0, wy + 6.5, z), Vector3(wx + 1.0, wy, z), Vector3(wx, wy, z), Vector3.BACK)
				b.glass.tri(Vector3(wx, wy + 6.5, z), Vector3(wx + 1.0, wy + 6.5, z), Vector3(wx + 0.5, wy + 7.6, z), Vector3.BACK)
			b.trim.box(Vector3(wx - 0.15, wy - 0.3, front), Vector3(wx + 1.15, wy, front + 0.25))
		bx += 4.2
	# The rose window on the tower.
	var rc := Vector3(x0 - 3.5, STREET + 13.5, cz + 0.04)
	var spokes := 16
	for i in spokes:
		var a0 := TAU * i / spokes
		var a1 := TAU * (i + 1) / spokes
		var col := Color(0.55, 0.0, 0.0) if i % 2 == 0 else Color(0.3, 0.0, 0.0)
		b.windows.tri(rc, rc + Vector3(cos(a0), sin(a0), 0) * 1.9, rc + Vector3(cos(a1), sin(a1), 0) * 1.9, Vector3.BACK, col)
	for i in spokes:
		var a0 := TAU * i / spokes
		var a1 := TAU * (i + 1) / spokes
		var p0 := rc + Vector3(cos(a0), sin(a0), 0) * 1.9
		var p1 := rc + Vector3(cos(a1), sin(a1), 0) * 1.9
		var q0 := rc + Vector3(cos(a0), sin(a0), 0) * 2.3
		var q1 := rc + Vector3(cos(a1), sin(a1), 0) * 2.3
		b.trim.quad(p0 + Vector3(0, 0, 0.02), p1 + Vector3(0, 0, 0.02), q1 + Vector3(0, 0, 0.02), q0 + Vector3(0, 0, 0.02), Vector3.BACK)


## One house, its front at z = front, from x to x + bw, bh high.
func _house(b: Dictionary, rng: RandomNumberGenerator, x: float, bw: float, bh: float, front: float, depth: float, row: int) -> void:
	var walls: Builder = b.walls
	var trim: Builder = b.trim
	var roof: Builder = b.roofs
	var top := STREET + bh
	# The small things (frames, sills, courses, pots, dormers) only on the
	# desktop, and only on the nearer two rows.
	var near := row < 2 and not _lite
	walls.box(Vector3(x, STREET - 2.0, front - depth), Vector3(x + bw, top, front))
	# The cornice under the eaves.
	trim.box(Vector3(x - 0.12, top - 0.32, front - 0.05), Vector3(x + bw + 0.12, top, front + 0.3))
	var style := rng.randf()
	if style < 0.3:
		# A steep gable facing the street, the ridge running back, a finial
		# at its point: the jagged skyline of the old town.
		var peak := top + bw * rng.randf_range(0.7, 0.95)
		var mx := x + bw * 0.5
		if row == 1:
			roofs.append([mx - 0.6, mx + 0.6, peak, front - 0.4])
		walls.tri(Vector3(x, top, front), Vector3(x + bw, top, front), Vector3(mx, peak, front), Vector3.BACK)
		roof.quad(Vector3(x - 0.25, top - 0.2, front + 0.35), Vector3(mx, peak + 0.15, front + 0.35), Vector3(mx, peak + 0.15, front - depth - 0.3), Vector3(x - 0.25, top - 0.2, front - depth - 0.3), Vector3(-(peak - top), bw * 0.5, 0).normalized())
		roof.quad(Vector3(x + bw + 0.25, top - 0.2, front + 0.35), Vector3(mx, peak + 0.15, front + 0.35), Vector3(mx, peak + 0.15, front - depth - 0.3), Vector3(x + bw + 0.25, top - 0.2, front - depth - 0.3), Vector3(peak - top, bw * 0.5, 0).normalized())
		trim.box(Vector3(mx - 0.07, peak, front - 0.07), Vector3(mx + 0.07, peak + 1.1, front + 0.25))
		if near:
			# A tall window in the gable.
			_window(b, rng, mx - 0.3, top + 0.4, front, 0.6, minf(1.6, (peak - top) * 0.45), true)
	elif style < 0.72:
		# A gable along the street.
		var ridge := top + bw * (rng.randf_range(0.2, 0.32) if row == 0 else rng.randf_range(0.25, 0.42))
		var mid := front - depth / 2.0
		if row == 1:
			roofs.append([x, x + bw, ridge, mid])
		roof.quad(Vector3(x - 0.2, top, front + 0.3), Vector3(x + bw + 0.2, top, front + 0.3), Vector3(x + bw + 0.2, ridge, mid), Vector3(x - 0.2, ridge, mid), Vector3(0, 0.7, 0.7).normalized())
		roof.quad(Vector3(x - 0.2, top, front - depth - 0.3), Vector3(x + bw + 0.2, top, front - depth - 0.3), Vector3(x + bw + 0.2, ridge, mid), Vector3(x - 0.2, ridge, mid), Vector3(0, 0.7, -0.7).normalized())
		roof.tri(Vector3(x, top, front), Vector3(x, ridge, mid), Vector3(x, top, front - depth), Vector3.LEFT)
		roof.tri(Vector3(x + bw, top, front), Vector3(x + bw, ridge, mid), Vector3(x + bw, top, front - depth), Vector3.RIGHT)
		if near and rng.randf() < 0.5:
			# A dormer in the roof.
			var dx := x + rng.randf_range(0.8, maxf(0.9, bw - 2.0))
			var dz := front - 0.3
			walls.box(Vector3(dx, top, dz - 1.4), Vector3(dx + 1.1, top + 1.5, dz))
			trim.box(Vector3(dx - 0.1, top + 1.5, dz - 1.5), Vector3(dx + 1.2, top + 1.65, dz + 0.1))
			_window(b, rng, dx + 0.3, top + 0.35, dz, 0.5, 0.8, true)
	elif rng.randf() < 0.7:
		if row == 1:
			roofs.append([x, x + bw, top, front - depth * 0.3])
		# Chimney stacks, each with its pots.
		var cx := x + rng.randf_range(0.5, bw - 1.2)
		var cz := front - depth * 0.6
		var ch := top + rng.randf_range(1.0, 2.2)
		walls.box(Vector3(cx, top, cz), Vector3(cx + 0.7, ch, cz + 0.7))
		trim.box(Vector3(cx - 0.08, ch - 0.15, cz - 0.08), Vector3(cx + 0.78, ch, cz + 0.78))
		if near:
			for k in rng.randi_range(1, 3):
				var px := cx + 0.12 + k * 0.2
				trim.box(Vector3(px, ch, cz + 0.25), Vector3(px + 0.14, ch + rng.randf_range(0.25, 0.45), cz + 0.39))
	else:
		# A parapet with coping.
		if row == 1:
			roofs.append([x, x + bw, top + 0.7, front - 0.3])
		walls.box(Vector3(x, top, front - 0.35), Vector3(x + bw, top + 0.7, front))
		trim.box(Vector3(x - 0.08, top + 0.7, front - 0.42), Vector3(x + bw + 0.08, top + 0.82, front + 0.08))
	# A corner turret under a cone, now and then on the nearer rows.
	if row < 2 and bw > 5.5 and rng.randf() < 0.18:
		_turret(b, Vector3(x + bw - 0.2, top - 3.0, front + 0.3), rng.randf_range(0.7, 1.0), top + rng.randf_range(1.2, 2.2), rng)
	# Floors: a string course at each, then the windows.
	var door_x := x + rng.randf_range(0.6, maxf(0.7, bw - 1.8)) if row == 0 else -1000.0
	var floor_y := STREET + 1.6
	while floor_y < top - 1.4:
		if near and floor_y > STREET + 2.0:
			trim.box(Vector3(x, floor_y - 0.55, front), Vector3(x + bw, floor_y - 0.38, front + 0.12))
		var wx := x + 0.8
		while wx < x + bw - 1.2:
			if not (floor_y < STREET + 3.0 and absf(wx + 0.22 - door_x - 0.55) < 1.2):
				_window(b, rng, wx, floor_y, front, 0.45, 0.85, near)
			wx += 1.6
		floor_y += 3.0
	if row == 0 and not _lite and rng.randf() < 0.3:
		# A shop sign on an iron bracket, beside the door.
		var sx := x + rng.randf_range(0.4, bw - 1.2)
		var sy := STREET + rng.randf_range(2.6, 3.2)
		b.iron.box(Vector3(sx, sy, front), Vector3(sx + 0.04, sy + 0.04, front + 1.0))
		b.iron.box(Vector3(sx, sy - 0.3, front), Vector3(sx + 0.04, sy, front + 0.04))
		b.wood.box(Vector3(sx - 0.01, sy - 0.6, front + 0.25), Vector3(sx + 0.05, sy - 0.04, front + 0.95))
	if row == 0 and not _lite:
		# A door, recessed in its frame, a step before it.
		b.wood.box(Vector3(door_x, STREET, front - 0.12), Vector3(door_x + 1.1, STREET + 2.3, front - 0.02))
		trim.box(Vector3(door_x - 0.16, STREET, front - 0.12), Vector3(door_x, STREET + 2.5, front + 0.08))
		trim.box(Vector3(door_x + 1.1, STREET, front - 0.12), Vector3(door_x + 1.26, STREET + 2.5, front + 0.08))
		trim.box(Vector3(door_x - 0.22, STREET + 2.3, front - 0.12), Vector3(door_x + 1.32, STREET + 2.62, front + 0.1))
		trim.box(Vector3(door_x - 0.25, STREET, front), Vector3(door_x + 1.35, STREET + 0.16, front + 0.45))
		if rng.randf() < 0.55:
			# A gutter along the eaves, its downpipe, and the water out of it.
			var px := x + bw - 0.3 if door_x < x + bw - 2.0 else x + 0.3
			var iron: Builder = b.iron
			iron.box(Vector3(x, top - 0.34, front + 0.3), Vector3(x + bw, top - 0.2, front + 0.44))
			iron.box(Vector3(px - 0.06, STREET + 0.45, front + 0.06), Vector3(px + 0.06, top - 0.3, front + 0.18))
			iron.box(Vector3(px - 0.06, STREET + 0.33, front + 0.06), Vector3(px + 0.06, STREET + 0.47, front + 0.42))
			for band in range(1, int(bh / 2.5)):
				iron.box(Vector3(px - 0.08, STREET + band * 2.5, front), Vector3(px + 0.08, STREET + band * 2.5 + 0.06, front + 0.2))
			_pours.append(Vector3(px, STREET + 0.38, front + 0.44))


## A round turret standing at `base` (its centre, bottom), up to `top`,
## under a steep slate cone with a finial.
func _turret(b: Dictionary, base: Vector3, radius: float, top: float, rng: RandomNumberGenerator) -> void:
	var sides := 8
	var cone := top + radius * rng.randf_range(2.6, 3.4)
	var ring := []
	for i in sides + 1:
		var a := TAU * i / sides
		ring.append(Vector2(cos(a), sin(a)))
	for i in sides:
		var p: Vector2 = ring[i]
		var q: Vector2 = ring[i + 1]
		var n := Vector3((p.x + q.x) * 0.5, 0, (p.y + q.y) * 0.5).normalized()
		var a0 := base + Vector3(p.x, 0, p.y) * radius
		var a1 := base + Vector3(q.x, 0, q.y) * radius
		b.walls.quad(a0, a1, Vector3(a1.x, top, a1.z), Vector3(a0.x, top, a0.z), n)
		var e0 := base + Vector3(p.x, 0, p.y) * (radius + 0.2)
		var e1 := base + Vector3(q.x, 0, q.y) * (radius + 0.2)
		var apex := Vector3(base.x, cone, base.z)
		b.roofs.tri(Vector3(e0.x, top, e0.z), Vector3(e1.x, top, e1.z), apex, (n + Vector3(0, 0.35, 0)).normalized())
	b.trim.box(Vector3(base.x - 0.05, cone - 0.1, base.z - 0.05), Vector3(base.x + 0.05, cone + 0.9, base.z + 0.05))


## A window at (x, y) on a front at z: lit (one in six), or dark glass;
## nearer houses frame it and give it a sill.
func _window(b: Dictionary, rng: RandomNumberGenerator, x: float, y: float, front: float, ww: float, wh: float, framed: bool) -> void:
	var z := front + 0.05
	if rng.randf() < 0.16:
		# Lit; one in six of those flickers.
		var col := Color(rng.randf_range(0.35, 0.9), rng.randf() if rng.randf() < 0.17 else 0.0, 0.0)
		b.windows.quad(Vector3(x, y + wh, z), Vector3(x + ww, y + wh, z), Vector3(x + ww, y, z), Vector3(x, y, z), Vector3.BACK, col)
	elif framed:
		b.glass.quad(Vector3(x, y + wh, z), Vector3(x + ww, y + wh, z), Vector3(x + ww, y, z), Vector3(x, y, z), Vector3.BACK)
	if framed and ww < 0.48 and rng.randf() < 0.35:
		# Shutters folded back, one a little ajar.
		b.wood.box(Vector3(x - 0.09 - ww * 0.5, y - 0.02, front + 0.04), Vector3(x - 0.1, y + wh, front + 0.08))
		b.wood.box(Vector3(x + ww + 0.1, y - 0.02, front + 0.04), Vector3(x + ww + 0.09 + ww * 0.5, y + wh, front + 0.14))
	if framed and y < STREET + 2.5 and rng.randf() < 0.6:
		# Bars on a ground-floor window.
		for i in 4:
			var bx := x + ww * (i + 0.5) / 4.0
			b.iron.box(Vector3(bx - 0.015, y, front + 0.07), Vector3(bx + 0.015, y + wh, front + 0.1))
	elif framed and ww < 0.48 and y > STREET + 3.0 and rng.randf() < 0.18:
		# A small iron balcony.
		b.trim.box(Vector3(x - 0.3, y - 0.22, front), Vector3(x + ww + 0.3, y - 0.12, front + 0.55))
		b.iron.box(Vector3(x - 0.3, y + 0.55, front + 0.5), Vector3(x + ww + 0.3, y + 0.59, front + 0.55))
		for i in 7:
			var px := x - 0.28 + (ww + 0.56) * i / 6.0
			b.iron.box(Vector3(px - 0.012, y - 0.12, front + 0.5), Vector3(px + 0.012, y + 0.57, front + 0.53))
	if framed:
		b.trim.box(Vector3(x - 0.09, y - 0.08, front), Vector3(x + ww + 0.09, y + wh + 0.1, front + 0.04))
		b.trim.box(Vector3(x - 0.14, y - 0.17, front), Vector3(x + ww + 0.14, y - 0.07, front + 0.16))
		if rng.randf() < 0.3:
			# A lintel.
			b.trim.box(Vector3(x - 0.16, y + wh + 0.1, front), Vector3(x + ww + 0.16, y + wh + 0.26, front + 0.1))


## Gas lamps along the street behind the district, every dozen metres or
## so, a few gone out: no light of their own, only their glow in the fog.
func _gas_lamps(rng: RandomNumberGenerator, w: float, mats: Dictionary) -> void:
	var b := _city_builders()
	var x := rng.randf_range(2.0, 8.0)
	var lit := 0
	while x < w:
		var z := -5.2
		b.iron.box(Vector3(x - 0.05, STREET, z - 0.05), Vector3(x + 0.05, STREET + 3.0, z + 0.05))
		b.iron.box(Vector3(x - 0.1, STREET, z - 0.1), Vector3(x + 0.1, STREET + 0.35, z + 0.1))
		b.iron.box(Vector3(x - 0.2, STREET + 3.0, z - 0.2), Vector3(x + 0.2, STREET + 3.06, z + 0.2))
		b.iron.box(Vector3(x - 0.14, STREET + 3.5, z - 0.14), Vector3(x + 0.14, STREET + 3.58, z + 0.14))
		if rng.randf() < 0.75:
			b.windows.box(Vector3(x - 0.13, STREET + 3.06, z - 0.13), Vector3(x + 0.13, STREET + 3.5, z + 0.13), Color(1.0, rng.randf() if rng.randf() < 0.3 else 0.0, 0.0))
			lit += 1
		else:
			b.glass.box(Vector3(x - 0.13, STREET + 3.06, z - 0.13), Vector3(x + 0.13, STREET + 3.5, z + 0.13))
		x += rng.randf_range(10.0, 15.0)
	_add_city_chunk(b, mats, false)
	counts.gas_lamps = lit


## What's left in the street behind the district: barrels, crates, a
## handcart on its side, sacks against the walls. Desktop only.
func _street_clutter(rng: RandomNumberGenerator, w: float, mats: Dictionary) -> void:
	var b := _city_builders()
	var wood: Builder = b.wood
	var iron: Builder = b.iron
	var x := rng.randf_range(1.0, 5.0)
	var placed := 0
	while x < w:
		var z := rng.randf_range(-6.4, -4.0)
		match rng.randi() % 4:
			0:
				for i in rng.randi_range(1, 3):
					_barrel(wood, iron, Vector3(x + i * 0.65, STREET, z + rng.randf_range(-0.3, 0.3)), rng.randf_range(0.26, 0.32))
			1:
				var s := rng.randf_range(0.5, 0.75)
				wood.box(Vector3(x, STREET, z - s), Vector3(x + s, STREET + s, z))
				if rng.randf() < 0.6:
					var t := s * 0.75
					wood.box(Vector3(x + 0.1, STREET + s, z - t - 0.05), Vector3(x + 0.1 + t, STREET + s + t, z - 0.05))
			2:
				# A handcart: its bed, two spoked wheels, the shafts down.
				wood.box(Vector3(x, STREET + 0.45, z - 0.7), Vector3(x + 1.4, STREET + 0.6, z))
				wood.box(Vector3(x, STREET + 0.6, z - 0.06), Vector3(x + 1.4, STREET + 0.9, z))
				for wz in [z + 0.04, z - 0.78]:
					_wheel(wood, Vector3(x + 0.7, STREET + 0.45, wz), 0.45)
				wood.box(Vector3(x + 1.4, STREET + 0.05, z - 0.62), Vector3(x + 2.3, STREET + 0.1, z - 0.55))
				wood.box(Vector3(x + 1.4, STREET + 0.05, z - 0.15), Vector3(x + 2.3, STREET + 0.1, z - 0.08))
			3:
				for i in rng.randi_range(2, 4):
					var sx := x + i * 0.45
					wood.box(Vector3(sx, STREET, z - 0.35), Vector3(sx + 0.42, STREET + rng.randf_range(0.35, 0.5), z), Color(0.75, 0.68, 0.55))
		placed += 1
		x += rng.randf_range(4.0, 11.0)
	_add_city_chunk(b, mats, false)
	counts.clutter = placed


## A barrel standing at `base`: eight staves round, iron hoops.
func _barrel(wood: Builder, iron: Builder, base: Vector3, radius: float) -> void:
	var height := radius * 2.9
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		for k in 2:
			var y0 := height * 0.5 * k
			var r0 := radius * (0.88 if k == 0 else 1.0)
			var r1 := radius * (1.0 if k == 0 else 0.88)
			wood.quad(base + p0 * r0 + Vector3(0, y0, 0), base + p1 * r0 + Vector3(0, y0, 0), base + p1 * r1 + Vector3(0, y0 + height * 0.5, 0), base + p0 * r1 + Vector3(0, y0 + height * 0.5, 0), n)
		wood.tri(base + Vector3(0, height, 0), base + p0 * radius * 0.88 + Vector3(0, height, 0), base + p1 * radius * 0.88 + Vector3(0, height, 0), Vector3.UP)
	for hy in [0.15, 0.85]:
		var y: float = base.y + height * hy
		var r := radius * 0.93 + 0.012
		iron.box(Vector3(base.x - r, y, base.z - r), Vector3(base.x + r, y + 0.04, base.z + r))


## A cart wheel facing you at `centre`: rim, hub and six spokes.
func _wheel(wood: Builder, centre: Vector3, radius: float) -> void:
	for i in 12:
		var a0 := TAU * i / 12.0
		var a1 := TAU * (i + 1) / 12.0
		var o0 := Vector3(cos(a0), sin(a0), 0) * radius
		var o1 := Vector3(cos(a1), sin(a1), 0) * radius
		var i0 := o0 * 0.84
		var i1 := o1 * 0.84
		wood.quad(centre + o0, centre + o1, centre + i1, centre + i0, Vector3.BACK)
	for i in 6:
		var a := TAU * i / 6.0
		var d := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-d.y, d.x, 0) * 0.025
		wood.quad(centre + side, centre - side, centre - side + d * radius * 0.85, centre + side + d * radius * 0.85, Vector3.BACK)
	wood.box(centre - Vector3(0.07, 0.07, 0.06), centre + Vector3(0.07, 0.07, 0.06))


## Far beyond the houses, deep in the fog: towers and spires of the rest
## of the city, only pale shapes, so it reads as going on and on.
func _far_spires(rng: RandomNumberGenerator, w: float, mats: Dictionary) -> void:
	var b := _city_builders()
	var x := -60.0
	while x < w + 60.0:
		var z := rng.randf_range(-95.0, -78.0)
		var s := rng.randf_range(3.0, 5.0)
		var h := rng.randf_range(10.0, 20.0)
		b.walls.box(Vector3(x, STREET - 2.0, z - s), Vector3(x + s, STREET + h, z))
		var apex := Vector3(x + s * 0.5, STREET + h + s * rng.randf_range(1.8, 3.2), z - s * 0.5)
		var c := [Vector3(x, STREET + h, z), Vector3(x + s, STREET + h, z), Vector3(x + s, STREET + h, z - s), Vector3(x, STREET + h, z - s)]
		for i in 4:
			var a: Vector3 = c[i]
			var d: Vector3 = c[(i + 1) % 4]
			var n := (d - a).cross(apex - a).normalized()
			if n.dot((a + d) * 0.5 - Vector3(apex.x, a.y, apex.z)) < 0.0:
				n = -n
			b.roofs.tri(a, d, apex, n)
		if rng.randf() < 0.4:
			var wy := STREET + h * rng.randf_range(0.5, 0.85)
			b.windows.quad(Vector3(x + s * 0.4, wy + 1.2, z + 0.05), Vector3(x + s * 0.6, wy + 1.2, z + 0.05), Vector3(x + s * 0.6, wy, z + 0.05), Vector3(x + s * 0.4, wy, z + 0.05), Vector3.BACK, Color(0.6, 0.0, 0.0))
		x += rng.randf_range(28.0, 55.0)
	_add_city_chunk(b, mats, false)


## A fresh set of builders for a city chunk. In the browser the small
## things go in with the walls (one draw instead of four) and there's no
## dark glass.
func _city_builders() -> Dictionary:
	var walls := Builder.new()
	if _lite:
		return {"walls": walls, "roofs": Builder.new(), "windows": Builder.new(), "trim": walls, "iron": walls, "wood": walls, "glass": Builder.new()}
	return {"walls": walls, "roofs": Builder.new(), "windows": Builder.new(), "trim": Builder.new(), "iron": Builder.new(), "wood": Builder.new(), "glass": Builder.new()}


func _add_city_chunk(b: Dictionary, mats: Dictionary, shadows: bool) -> void:
	var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var done := {}
	for part in ["walls", "roofs", "trim", "iron", "wood", "glass", "windows"]:
		var builder: Builder = b[part]
		if done.has(builder) or (_lite and part == "glass"):
			continue
		done[builder] = true
		var mi := _add_mesh(builder.mesh(), mats[part], _city)
		if mi:
			mi.cast_shadow = cast if part in ["walls", "roofs", "trim", "iron"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.015, 0.018, 0.024)
	m.roughness = 0.05
	m.metallic_specular = 0.8
	return m


func _iron() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.045, 0.045, 0.05)
	m.metallic = 0.75
	m.roughness = 0.32
	return m


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
	# Lights well off screen fade out, and their shadows sooner: every
	# shadowed light re-renders its shadow whenever the plane moves.
	l.distance_fade_enabled = true
	l.distance_fade_begin = 30.0
	l.distance_fade_length = 6.0
	l.distance_fade_shadow = 18.0
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
	_fill = _omni(Color(0.7, 0.78, 1.0), 0.75, 4.5, false)
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


## Rain splashing where it lands: on the first stone, walkway or water
## each column of the level offers the sky, and on the street behind. One
## emitter; its points are spread through the level.
func _build_splashes() -> void:
	var lv = world.level
	var w: int = lv.size_tiles.x
	var h: int = lv.size_tiles.y
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var points := PackedVector3Array()
	for c in w:
		for r in h:
			if lv.back_wall.get_cell_source_id(Vector2i(c, r)) != -1:
				break
			var k: String = lv.kind_at(Vector2i(c, r))
			if k == "":
				continue
			var y := -float(r) + 0.02
			var z0 := -BACK + 0.2
			var z1 := FRONT - 0.1
			if k == "walkway":
				z0 = -1.0
				z1 = 0.7
			elif k == "water":
				y = -float(r) - 0.13
			elif k == "veil":
				break
			for i in 3:
				points.append(Vector3(c + rng.randf(), y, rng.randf_range(z0, z1)))
			break
		points.append(Vector3(c + rng.randf(), STREET + 0.02, rng.randf_range(-6.6, -3.4)))
	counts.splashes = points.size()
	_splashes = _point_emitter(points, mini(points.size() * 2, 700 if _lite else 1800), 0.32)
	var pm: ParticleProcessMaterial = _splashes.process_material
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 38.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var drop := QuadMesh.new()
	drop.size = Vector2(0.014, 0.05)
	drop.material = _rain_material()
	_splashes.draw_pass_1 = drop


## Water out of the drainpipes in the street behind, splashing.
func _build_pours() -> void:
	counts.pours = _pours.size()
	if _pours.is_empty():
		return
	_pour = _point_emitter(_pours, _pours.size() * 30, 0.45)
	var pm: ParticleProcessMaterial = _pour.process_material
	pm.direction = Vector3(0, -0.3, 1.0)
	pm.spread = 7.0
	pm.initial_velocity_min = 0.7
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, -9.8, 0)
	var drop := QuadMesh.new()
	drop.size = Vector2(0.035, 0.12)
	var m := _rain_material()
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.5)
	drop.material = m
	_pour.draw_pass_1 = drop


## Moths round the lit lamps (rebuilt as lamps are lit).
func _build_moths() -> void:
	var points := PackedVector3Array()
	for e in _lamps:
		if e.lamp.lit:
			points.append((e.light as OmniLight3D).position)
	_moth_count = points.size()
	if _moths:
		_moths.queue_free()
		_moths = null
	if points.is_empty():
		return
	_moths = _point_emitter(points, points.size() * 7, 3.0)
	var pm: ParticleProcessMaterial = _moths.process_material
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 3.0
	pm.turbulence_noise_scale = 1.2
	pm.turbulence_noise_speed_random = 0.5
	pm.turbulence_influence_min = 0.3
	pm.turbulence_influence_max = 0.6
	_moths.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	var speck := QuadMesh.new()
	speck.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.75, 0.45) * 1.6
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	speck.material = m
	_moths.draw_pass_1 = speck


## A particle emitter whose particles start at the given points.
func _point_emitter(points: PackedVector3Array, amount: int, lifetime: float) -> GPUParticles3D:
	var img := Image.create_empty(points.size(), 1, false, Image.FORMAT_RGBF)
	for i in points.size():
		var p := points[i]
		img.set_pixel(i, 0, Color(p.x, p.y, p.z))
	var gp := GPUParticles3D.new()
	gp.amount = maxi(1, amount)
	gp.lifetime = lifetime
	gp.preprocess = lifetime
	gp.local_coords = false
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	gp.visibility_aabb = AABB(lo - Vector3(3, 3, 3), hi - lo + Vector3(6, 6, 6))
	gp.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = points.size()
	gp.process_material = pm
	gp.layers = MOVING
	add_child(gp)
	return gp


## Mist lying low over every open street and walkway, thicker over the
## canal, for the lamps to light (volumetric fog; not in the browser).
func _build_mist() -> void:
	counts.mist = 0
	if _lite:
		return
	var lv = world.level
	var w: int = lv.size_tiles.x
	var h: int = lv.size_tiles.y
	var floors := []
	for c in w:
		var y: float = lv.ground_below(c * PX + PX * 0.5, 0.0, h * PX)
		var water := false
		for r in h:
			if lv.kind_at(Vector2i(c, r)) == "water":
				water = true
				break
		floors.append([y, water])
	var street := FogMaterial.new()
	street.density = 0.09
	street.albedo = Color(0.75, 0.8, 0.9)
	street.height_falloff = 1.6
	street.edge_fade = 0.6
	var canal := FogMaterial.new()
	canal.density = 0.16
	canal.albedo = Color(0.7, 0.78, 0.85)
	canal.height_falloff = 1.0
	canal.edge_fade = 0.7
	var c0 := 0
	while c0 < w:
		var c1 := c0 + 1
		while c1 < w and floors[c1][0] == floors[c0][0] and floors[c1][1] == floors[c0][1]:
			c1 += 1
		var y: float = floors[c0][0]
		if y >= 0.0:
			var over_water: bool = floors[c0][1]
			var tall := 2.2 if over_water else 1.3
			var fog := FogVolume.new()
			fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
			fog.size = Vector3(c1 - c0 + 1.0, tall, BACK + FRONT + 3.0)
			fog.position = Vector3((c0 + c1) * 0.5, -y / PX + tall * 0.5 - 0.2, (FRONT - BACK - 1.5) * 0.5)
			fog.material = canal if over_water else street
			add_child(fog)
			_mist.append(fog)
			counts.mist += 1
		c0 = c1


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
		# The same ambient as outside: rooms are dark, not black.
		p.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
		p.blend_distance = 0.5
		p.cull_mask = 0xFFFFF & ~MOVING
		add_child(p)
	counts.probes = boxes.size()


## Every mesh's material drawn once, tiny, just in front of the camera for
## the first moments, so shaders compile at load instead of with a hitch the
## first time each comes into view (the browser compiles them on first
## draw: the canal, the undercroft, the storm).
func _prewarm() -> void:
	var seen := {}
	var holder := Node3D.new()
	camera.add_child(holder)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var m := mi.material_override
		if m == null or seen.has(m):
			continue
		seen[m] = true
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh if mi.mesh else QuadMesh.new()
		copy.material_override = m
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box := copy.mesh.get_aabb()
		copy.scale = Vector3.ONE * (0.02 / maxf(box.size.length(), 0.001))
		copy.position = Vector3((seen.size() % 8) * 0.03 - 0.1, (seen.size() / 8) * 0.03 - 0.1, -1.0) - box.get_center() * copy.scale.x
		holder.add_child(copy)
	counts.prewarmed = seen.size()
	get_tree().create_timer(0.5).timeout.connect(holder.queue_free)


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
	var lit := 0
	for e in _lamps:
		if e.lamp.lit:
			lit += 1
	if lit != _moth_count:
		_build_moths()


## Sets how much is drawn (see QUALITY).
func set_quality(level: int) -> void:
	quality = clampi(level, 0, QUALITY.size() - 1)
	var high := quality == 0
	var fast := quality == 2
	var game: SubViewport = main.game
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		game.msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_DISABLED
		game.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if high else Viewport.SCREEN_SPACE_AA_FXAA
	env.ssil_enabled = high and not _lite
	env.ssr_enabled = high
	env.ssao_enabled = not fast
	env.volumetric_fog_enabled = not fast
	for fog in _mist:
		fog.visible = not fast
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high and not _lite else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	for e in _lamps:
		(e.light as OmniLight3D).shadow_enabled = high and not _lite
	_lantern.shadow_enabled = not fast and not _lite


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
			for p in [_rain, _drips, _splashes, _pour]:
				if p:
					p.visible = on
		"city":
			_city.visible = on
		"plane":
			plane.visible = on
			plane_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
