## The sky and the city behind the play space: a moon, two layers of
## rooftops and spires that drift slower than you (parallax), and fog.
## Everything is generated from a fixed seed, so the skyline is the same
## every time. Drawn in screen space on its own CanvasLayer, so the night's
## darkness (CanvasModulate) doesn't touch it.
##
## Stand-in for painted parallax layers (Parallax2D) once the art exists.
extends Node2D

const MOON := Color("ebe5d5")
const FAR := Color("141a26")
const MID := Color("10141d")
const WINDOW := Color(0.91, 0.66, 0.31)
const FOG := Color(0.35, 0.41, 0.48)

var world
var _far := []
var _far_w := 0.0
var _mid := []
var _mid_w := 0.0


func _ready() -> void:
	var far := _skyline(7, 70.0, 170.0, 0.22, 0.12)
	_far = far[0]
	_far_w = far[1]
	# The near layer keeps to rooftops: a spire this close reads as part of
	# the play space.
	var mid := _skyline(23, 40.0, 110.0, 0.0, 0.3)
	_mid = mid[0]
	_mid_w = mid[1]


func _skyline(seed_value: int, min_h: float, max_h: float, spires: float, windows: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var shapes := []
	var x := 0.0
	while x < 1600.0:
		var w := 28.0 + rng.randf() * 64.0
		var h := min_h + rng.randf() * (max_h - min_h)
		var roll := rng.randf()
		var roof := "spire" if roll < spires else ("gable" if roll < spires + 0.35 else "flat")
		var s := {"x": x, "w": w, "h": h, "roof": roof, "spire_h": 50.0 + rng.randf() * 110.0, "chimney": rng.randf() < 0.45, "lit": []}
		for i in 4:
			if rng.randf() < windows:
				s.lit.append(Vector3(5.0 + rng.randf() * (w - 12.0), 14.0 + rng.randf() * (h - 24.0), rng.randf()))
		shapes.append(s)
		x += w + (6.0 + rng.randf() * 18.0 if rng.randf() < 0.25 else 0.0)
	return [shapes, x]


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var view: Vector2 = world.view_size()
	var cam: Vector2 = world.cam_top_left()
	var time: float = world.time
	# How far the camera is from the street-level view, for vertical drift.
	var dy := cam.y - 440.0

	_vgradient(0.0, view.y * 0.75, view.x, Color("05060b"), Color("1a2433"))
	_vgradient(view.y * 0.75, view.y, view.x, Color("1a2433"), Color("202a36"))

	# The moon, nearly still.
	var m := Vector2(view.x * 0.74 - cam.x * 0.01, 92.0 - dy * 0.04)
	draw_texture_rect(preload("res://scripts/glow.gd").texture(), Rect2(m - Vector2(190, 190), Vector2(380, 380)), false, Color(0.88, 0.89, 0.93, 0.22))
	draw_circle(m, 34.0, MOON)
	for c in [Vector3(-10, -8, 9), Vector3(12, 6, 6), Vector3(-4, 14, 5), Vector3(9, -14, 4)]:
		draw_circle(m + Vector2(c.x, c.y), c.z, Color(0.47, 0.43, 0.39, 0.12))

	_layer(_far, _far_w, cam.x * 0.15, 268.0 - dy * 0.12, FAR, view.x, time)
	_fog(view.x, 230.0 - dy * 0.15, 90.0, 0.16, time * 4.0)
	_layer(_mid, _mid_w, cam.x * 0.38, 318.0 - dy * 0.3, MID, view.x, time)
	_fog(view.x, 300.0 - dy * 0.3, 70.0, 0.1, time * 9.0)

	# The night sits over the sky too, a little lighter at the top.
	_vgradient(0.0, view.y, view.x, Color(0.016, 0.02, 0.04, 0.38), Color(0.016, 0.02, 0.04, 0.62))


func _layer(shapes: Array, width: float, offset: float, base: float, color: Color, view_w: float, time: float) -> void:
	var start := -fposmod(offset, width)
	var k := start
	while k < view_w:
		for s in shapes:
			var x: float = k + s.x
			if x > view_w or x + s.w < 0.0:
				continue
			var top: float = base - s.h
			draw_rect(Rect2(x, top, s.w, 600.0), color)
			if s.roof == "spire":
				draw_colored_polygon(PackedVector2Array([Vector2(x + s.w * 0.3, top), Vector2(x + s.w / 2.0, top - s.spire_h), Vector2(x + s.w * 0.7, top)]), color)
			elif s.roof == "gable":
				draw_colored_polygon(PackedVector2Array([Vector2(x - 2.0, top), Vector2(x + s.w / 2.0, top - s.w * 0.45), Vector2(x + s.w + 2.0, top)]), color)
			if s.chimney:
				draw_rect(Rect2(x + s.w * 0.7, top - 14.0, 6.0, 14.0), color)
			# A few lit windows; one now and then flickers.
			for w in s.lit:
				var flick := 0.5 + 0.5 * sin(time * 3.0 + w.z * 40.0) if w.z > 0.85 else 1.0
				draw_rect(Rect2(x + w.x, top + w.y, 3.0, 5.0), Color(WINDOW, 0.55 * flick))
		k += width


func _fog(view_w: float, y: float, h: float, alpha: float, drift: float) -> void:
	_vgradient(y - h, y, view_w, Color(FOG, 0.0), Color(FOG, alpha))
	_vgradient(y, y + h, view_w, Color(FOG, alpha), Color(FOG, 0.0))
	# Slow drifting wisps on top of the band.
	for i in 5:
		var x := fposmod(i * 233.0 + drift, view_w + 300.0) - 150.0
		var c := Vector2(x, y + sin(i * 1.7) * h * 0.3)
		var pts := PackedVector2Array()
		for j in 20:
			var ang := TAU * j / 20.0
			pts.append(c + Vector2(cos(ang) * 140.0, sin(ang) * 14.0))
		draw_colored_polygon(pts, Color(0.43, 0.49, 0.55, alpha * 0.5))


func _vgradient(y0: float, y1: float, w: float, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)]),
		PackedColorArray([top, top, bottom, bottom]))
