## Rain, splashes and ground mist over the play space. Faint and unshaded:
## the night stays dark but everything feels wet. Rain stays out of
## anywhere with a roof.
extends Node2D

const Glow = preload("res://scripts/glow.gd")

const DROPS := 180
const SPLASHES := 26
const WISPS := 9

var world
var _drops := PackedVector3Array()
var _time := 0.0


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in DROPS:
		_drops.append(Vector3(rng.randf(), rng.randf(), rng.randf()))


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var level = world.level
	var view: Vector2 = world.view_size() + Vector2(80, 60)
	var tl: Vector2 = world.cam_top_left() - Vector2(40, 30)
	# Rain and splashes are all one batch of lines: one draw call.
	var lines := PackedVector2Array()
	var colors := PackedColorArray()

	# Rain, fixed to the world (it doesn't slide when the camera moves).
	for d in _drops:
		var fall := 520.0 + d.z * 280.0
		var length := 8.0 + d.z * 10.0
		var x := tl.x + fposmod(d.x * view.x - _time * 60.0 - tl.x, view.x)
		var y := tl.y + fposmod(d.y * view.y + _time * fall - tl.y, view.y)
		var at := Vector2(x, y)
		if level.roofed_at(at) or level.solid_at(at):
			continue
		lines.append(at)
		lines.append(at + Vector2(-length * 0.12, length))
		colors.append(Color(0.72, 0.78, 0.9, 0.08 + 0.12 * d.z))

	# Splashes where it lands.
	for i in SPLASHES:
		var k := fposmod(_time * (1.7 + (i % 5) * 0.23) + i * 0.37, 1.0)
		var sx := tl.x + fposmod(i * 97.3 + floorf(_time * 1.7 + i * 0.37) * 53.1 - tl.x, view.x)
		var gy: float = level.ground_below(sx, tl.y, tl.y + view.y)
		if gy < 0.0 or k > 0.35:
			continue
		var a := (0.35 - k) * 1.2
		var sz := 1.5 + k * 8.0
		var c := Color(0.75, 0.82, 0.92, a)
		lines.append_array(PackedVector2Array([Vector2(sx, gy), Vector2(sx - sz, gy - sz * 0.8), Vector2(sx, gy), Vector2(sx + sz, gy - sz * 0.8)]))
		colors.append_array(PackedColorArray([c, c]))
	if not lines.is_empty():
		draw_multiline_colors(lines, colors, 1.0)

	# Low mist drifting along open ground.
	for i in WISPS:
		var wx := tl.x + fposmod(i * 211.0 + _time * (6.0 + i * 1.3) - tl.x * 0.9, view.x)
		var gy: float = level.ground_below(wx, tl.y, tl.y + view.y)
		if gy < 0.0:
			continue
		var w := 170.0 + (i % 3) * 60.0
		draw_texture_rect(Glow.texture(), Rect2(wx - w / 2.0, gy - 22.0, w, 30.0), false, Color(0.6, 0.66, 0.76, 0.09))
