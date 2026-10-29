## The storm over the 3D stage: lightning, and what it shows.
##
## The Ambience decides when lightning strikes (it times the thunder);
## this draws it: a light from the clouds that rakes the wet roofs and
## streets, the fog and the sky going white, and for a near strike the bolt
## itself, in a few flickering pulses. A strike that reveals shows the
## thing that stands in the fog beyond the city, black against the flash,
## and opens its eyes, which stay lit a while after the dark comes back;
## the moon's pupil widens; and afterwards there are watchers on the
## rooftops, until a later flash finds them gone.
extends Node3D

const COLOSSUS := preload("res://shaders/colossus3d.gdshader")
const BOLT := preload("res://shaders/bolt3d.gdshader")
const WATCHER := preload("res://shaders/watcher3d.gdshader")

## How far behind the plane the thing stands (m), where its head sits
## (degrees above the camera's level: over the rooftops, below the top of
## the view), and how far below it its base is hidden (degrees).
const COLOSSUS_Z := -200.0
const HEAD_ELEVATION := 21.0
const BASE_DEPTH := 8.0
## The shape is drawn at this size (shaders/colossus3d.gdshader) and the
## head's height in it; the quad is scaled to put the head where it goes.
const SHAPE := Vector2(440.0, 420.0)
const SHAPE_HEAD := 196.0
## After a reveal its shape lingers this faintly, fading over LINGER s; its
## eyes stay open EYES_OPEN s, then close over EYES_CLOSE s.
const AFTERIMAGE := 0.12
const LINGER := 5.0
const EYES_OPEN := 7.0
const EYES_CLOSE := 4.0
## The lightning light's energy and the fog's whitening at full flash.
const LIGHT_ENERGY := 1.8
const FOG_FLASH := Color(0.3, 0.33, 0.46)
const AMBIENT_FLASH := 0.12
const SKY_FLASH := 1.4
## A strike stronger than this draws its bolt.
const BOLT_STRENGTH := 0.4
## The moon's pupil after a reveal, narrowing back over PUPIL_REST s (in
## steps, since every change redraws the sky).
const PUPIL_REST := 30.0
## Watchers on the rooftops after a reveal: how many at most, and how far
## from the camera's x (m) they may stand.
const WATCHERS := 3
const WATCH_RANGE := 26.0

var stage
var light: DirectionalLight3D
var colossus: MeshInstance3D
var bolt: MeshInstance3D
var watchers: Array[MeshInstance3D] = []
## The flash now (0 none, about 1 a full strike), for the playtest.
var level := 0.0
var revealed := 0.0
var eyes := 0.0

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _pulses: Array = []
var _strength := 0.0
var _since_reveal := 1000.0
var _pupil := 0.0
var _sky_flash := -1.0
var _sky_pupil := -1.0
var _fog_base := Color()
var _ambient_base := 0.0
var _sky_mat: ShaderMaterial


func _ready() -> void:
	_rng.randomize()
	_sky_mat = stage.env.sky.sky_material
	_fog_base = stage.env.fog_light_color
	_ambient_base = stage.env.ambient_light_energy

	light = DirectionalLight3D.new()
	light.light_color = Color(0.78, 0.84, 1.0)
	light.light_energy = 0.0
	light.light_volumetric_fog_energy = 0.25
	light.shadow_enabled = false
	light.light_cull_mask = 0xFFFFF & ~stage.INDOOR
	light.visible = false
	add_child(light)

	colossus = MeshInstance3D.new()
	colossus.mesh = QuadMesh.new()
	var cm := ShaderMaterial.new()
	cm.shader = COLOSSUS
	cm.set_shader_parameter("size", SHAPE)
	cm.set_shader_parameter("grain", stage._noise(41, 0.05))
	colossus.material_override = cm
	colossus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	colossus.visible = false
	add_child(colossus)

	bolt = MeshInstance3D.new()
	var bm := ShaderMaterial.new()
	bm.shader = BOLT
	bolt.material_override = bm
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.visible = false
	add_child(bolt)

	var wm := ShaderMaterial.new()
	wm.shader = WATCHER
	wm.set_shader_parameter("presence", 1.0)
	for i in WATCHERS:
		var w := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.4, 4.0)
		w.mesh = q
		w.material_override = wm
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.visible = false
		add_child(w)
		watchers.append(w)


## Lightning: strength 0..1 (1 is overhead); reveal shows the thing.
func flash(strength: float, reveal: bool) -> void:
	_strength = strength
	_t = 0.0
	# Two to four pulses in the first half second, each fainter.
	_pulses.clear()
	var at := 0.0
	var n := _rng.randi_range(2, 4)
	for i in n:
		_pulses.append([at, _rng.randf_range(0.05, 0.14), _rng.randf_range(0.6, 1.0) * pow(0.75, i)])
		at += _rng.randf_range(0.06, 0.22)
	# Where it comes from: high, behind the city, left or right.
	var side := _rng.randf_range(-0.8, 0.8)
	light.basis = Basis.looking_at(Vector3(side, -0.9, 0.55).normalized(), Vector3.UP)
	if strength > BOLT_STRENGTH:
		_build_bolt()
	else:
		bolt.visible = false
	# Whatever was on the roofs may be gone when the light comes.
	for w in watchers:
		if w.visible and _rng.randf() < 0.6:
			w.visible = false
	if reveal:
		_reveal()


## Holds the storm at one moment, for the screenshots: flash f (with the
## bolt, if any), and if since_reveal isn't negative, the thing shown that
## many seconds ago.
func pose(f: float, since_reveal: float) -> void:
	_strength = 1.0
	_t = 0.1
	_pulses = [[0.0, 1.0e6, f]]
	if f > 0.0:
		_build_bolt()
	else:
		bolt.visible = false
	if since_reveal >= 0.0:
		_reveal()
		_since_reveal = since_reveal
	_process(0.0)


func _reveal() -> void:
	_since_reveal = 0.0
	_pupil = 1.0
	var cam: Camera3D = stage.camera
	var dist := cam.position.z - COLOSSUS_Z
	var s := (tan(deg_to_rad(HEAD_ELEVATION)) + tan(deg_to_rad(BASE_DEPTH))) * dist / SHAPE_HEAD
	var q: QuadMesh = colossus.mesh
	q.size = SHAPE * s
	var x := cam.position.x + tan(deg_to_rad(_rng.randf_range(-12.0, 12.0))) * dist
	var base := cam.position.y - tan(deg_to_rad(BASE_DEPTH)) * dist
	colossus.position = Vector3(x, base + q.size.y * 0.5, COLOSSUS_Z)
	colossus.scale = Vector3(-1.0 if _rng.randf() < 0.5 else 1.0, 1.0, 1.0)
	colossus.visible = true
	_place_watchers()


func _place_watchers() -> void:
	var roofs: Array = stage.roofs
	var cx: float = stage.camera.position.x
	var near := roofs.filter(func(r): return absf((r[0] + r[1]) * 0.5 - cx) < WATCH_RANGE)
	if near.is_empty():
		return
	var count := _rng.randi_range(1, WATCHERS)
	for i in count:
		var r: Array = near[_rng.randi() % near.size()]
		var w := watchers[i]
		w.position = Vector3(_rng.randf_range(r[0] + 0.8, r[1] - 0.8), r[2] + 2.0, r[3])
		var m: ShaderMaterial = w.material_override
		m.set_shader_parameter("lean", _rng.randf_range(-1.0, 1.0))
		w.visible = true


## A jagged bolt from the clouds down to the rooftops, with a few branches.
func _build_bolt() -> void:
	var cam: Camera3D = stage.camera
	var z := _rng.randf_range(-140.0, -70.0)
	var dist := cam.position.z - z
	var top := cam.position.y + tan(deg_to_rad(30.0)) * dist
	var bottom := cam.position.y + tan(deg_to_rad(_rng.randf_range(4.0, 10.0))) * dist
	var x := cam.position.x + tan(deg_to_rad(_rng.randf_range(-30.0, 30.0))) * dist
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _jag(Vector2(x, top), Vector2(x + _rng.randf_range(-25.0, 25.0), bottom), 6, dist * 0.022)
	_ribbon(mesh, main, z, dist * 0.004, 1.0)
	for i in _rng.randi_range(2, 4):
		var from: Vector2 = main[_rng.randi_range(4, main.size() - 12)]
		var to := from + Vector2(_rng.randf_range(-1.0, 1.0) * dist * 0.15, -_rng.randf_range(0.1, 0.3) * dist)
		_ribbon(mesh, _jag(from, to, 4, dist * 0.015), z + 0.5, dist * 0.0022, 0.55)
	mesh.surface_end()
	bolt.mesh = mesh
	bolt.visible = true


## Midpoint displacement from a to b, `depth` times.
func _jag(a: Vector2, b: Vector2, depth: int, rough: float) -> Array:
	var pts: Array = [a, b]
	for d in depth:
		var next: Array = [pts[0]]
		for i in range(1, pts.size()):
			var p: Vector2 = pts[i - 1]
			var q: Vector2 = pts[i]
			var normal := (q - p).orthogonal().normalized()
			next.append((p + q) * 0.5 + normal * _rng.randf_range(-1.0, 1.0) * rough * pow(0.6, d))
			next.append(q)
		pts = next
	return pts


## A flat ribbon along pts at depth z, `width` wide, thinning to the end.
func _ribbon(mesh: ImmediateMesh, pts: Array, z: float, width: float, alpha: float) -> void:
	for i in range(1, pts.size()):
		var p: Vector2 = pts[i - 1]
		var q: Vector2 = pts[i]
		var n := (q - p).orthogonal().normalized()
		var k0 := 1.0 - float(i - 1) / pts.size() * 0.7
		var k1 := 1.0 - float(i) / pts.size() * 0.7
		var a0 := Vector3(p.x, p.y, z) + Vector3(n.x, n.y, 0.0) * width * k0
		var b0 := Vector3(p.x, p.y, z) - Vector3(n.x, n.y, 0.0) * width * k0
		var a1 := Vector3(q.x, q.y, z) + Vector3(n.x, n.y, 0.0) * width * k1
		var b1 := Vector3(q.x, q.y, z) - Vector3(n.x, n.y, 0.0) * width * k1
		for v in [[a0, 0.0, k0], [b0, 1.0, k0], [a1, 0.0, k1], [b0, 1.0, k0], [b1, 1.0, k1], [a1, 0.0, k1]]:
			mesh.surface_set_color(Color(1, 1, 1, alpha * v[2]))
			mesh.surface_set_uv(Vector2(v[1], 0.0))
			mesh.surface_add_vertex(v[0])


func _process(delta: float) -> void:
	_t += delta
	_since_reveal += delta
	# The flash: the pulses, and a faint afterglow.
	var f := 0.0
	for p in _pulses:
		var dt: float = _t - p[0]
		if dt >= 0.0:
			f = maxf(f, p[2] * (clampf(dt / 0.012, 0.0, 1.0) * exp(-maxf(0.0, dt - 0.012) / p[1])))
	f *= lerpf(0.35, 1.0, _strength)
	if _t > 2.0:
		_pulses.clear()
	level = f
	light.visible = f > 0.01
	light.light_energy = f * LIGHT_ENERGY
	stage.env.fog_light_color = _fog_base + FOG_FLASH * f
	stage.env.ambient_light_energy = _ambient_base + f * AMBIENT_FLASH
	var sky_f := snappedf(f * SKY_FLASH, 0.02)
	if sky_f != _sky_flash:
		_sky_flash = sky_f
		_sky_mat.set_shader_parameter("flash", sky_f)
	(bolt.material_override as ShaderMaterial).set_shader_parameter("intensity", f * 3.0)
	if bolt.visible and _t > 1.0:
		bolt.visible = false

	# The thing in the fog: black while the flash lasts, then an afterimage
	# fading; its eyes stay open, then close.
	if colossus.visible:
		var linger := AFTERIMAGE * clampf(1.0 - (_since_reveal - 0.6) / LINGER, 0.0, 1.0)
		revealed = clampf(maxf(f * 2.5, linger), 0.0, 1.0)
		eyes = clampf(_since_reveal / 0.4, 0.0, 1.0) * clampf(1.0 - (_since_reveal - EYES_OPEN) / EYES_CLOSE, 0.0, 1.0)
		var cm: ShaderMaterial = colossus.material_override
		cm.set_shader_parameter("reveal", revealed)
		cm.set_shader_parameter("eyes", eyes)
		if _since_reveal > maxf(LINGER, EYES_OPEN + EYES_CLOSE) + 1.0:
			colossus.visible = false
			revealed = 0.0
			eyes = 0.0
	# The moon's pupil narrows back, a step at a time.
	_pupil = maxf(0.0, 1.0 - _since_reveal / PUPIL_REST)
	var pupil_step := snappedf(_pupil, 0.25)
	if pupil_step != _sky_pupil:
		_sky_pupil = pupil_step
		_sky_mat.set_shader_parameter("pupil", pupil_step)
