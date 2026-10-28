## The sky and the city behind the play space: a moon, two layers of
## rooftops and spires that drift slower than you (parallax), and fog.
## Everything is generated from a fixed seed, so the skyline is the same
## every time. Drawn in screen space on its own CanvasLayer, so the night's
## darkness (CanvasModulate) doesn't touch it; that darkness is mixed into
## its colours instead (NIGHT).
##
## Cheap to draw: each skyline layer is painted once into a texture (a
## SubViewport rendered a single time) and scrolled; the sky and fog bands
## are gradient textures. Only the flickering windows redraw each frame.
## About ten draw calls in all.
##
## Stand-in for painted parallax layers (Parallax2D) once the art exists.
extends Node2D

const Glow = preload("res://scripts/glow.gd")

const MOON := Color("ebe5d5")
const FAR := Color("141a26")
const MID := Color("10141d")
const WINDOW := Color(0.91, 0.66, 0.31)
const FOG := Color(0.35, 0.41, 0.48)
## The night over the sky: this colour, mixed in more toward the bottom.
const NIGHT := Color(0.016, 0.02, 0.04)
const NIGHT_TOP := 0.38
const NIGHT_BOTTOM := 0.62
## Layer textures are painted at this many pixels per screen pixel.
const PAINT_RES := 2.0
## Room above a layer's base for the tallest spire.
const LAYER_H := 340.0
## The street-level camera y (top of the view) the layers are placed for.
const STREET_Y := 440.0

var world
var _sky: TextureRect
var _moon_glow: Sprite2D
var _moon: Node2D
var _layers := []
var _fogs := []


func _ready() -> void:
	_sky = TextureRect.new()
	_sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sky.stretch_mode = TextureRect.STRETCH_SCALE
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky.texture = _vertical([0.0, 0.75, 1.0], [_night(Color("05060b"), 0.0), _night(Color("1a2433"), 0.75), _night(Color("202a36"), 1.0)])
	add_child(_sky)

	_moon_glow = Sprite2D.new()
	_moon_glow.texture = Glow.texture()
	_moon_glow.scale = Vector2(380, 380) / 256.0
	_moon_glow.modulate = Color(0.88, 0.89, 0.93, 0.22 * (1.0 - _mix_at(92.0)))
	add_child(_moon_glow)
	_moon = Node2D.new()
	_moon.draw.connect(_draw_moon)
	add_child(_moon)

	# Far layer, fog, near layer, fog: back to front. The near layer keeps
	# to rooftops: a spire this close reads as part of the play space.
	_layers.append(_layer(7, 70.0, 170.0, 0.22, 0.12, FAR, 268.0, 0.15, 0.12))
	_fogs.append(_fog_band(230.0, 90.0, 0.16, 4.0, 0.15))
	_layers.append(_layer(23, 40.0, 110.0, 0.0, 0.3, MID, 318.0, 0.38, 0.3))
	_fogs.append(_fog_band(300.0, 70.0, 0.1, 9.0, 0.3))


## A colour with the night mixed in, as at fraction y of the screen height.
func _night(c: Color, y: float) -> Color:
	return c.lerp(Color(NIGHT, c.a), lerpf(NIGHT_TOP, NIGHT_BOTTOM, y))


func _mix_at(y: float) -> float:
	return lerpf(NIGHT_TOP, NIGHT_BOTTOM, clampf(y / 360.0, 0.0, 1.0))


func _vertical(offsets: Array, colors: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4
	tex.height = 128
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	return tex


## A row of buildings, painted once into a texture and shown by a sprite
## that repeats it sideways. base: the screen y its street line sits at
## (from the street-level view); drift: how fast it slides with the camera.
func _layer(seed_value: int, min_h: float, max_h: float, spires: float, windows: float, color: Color, base: float, drift: float, rise: float) -> Dictionary:
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
	var width := x
	var tone := _night(color, base / 360.0)
	var window := Color(WINDOW, 0.55)
	window = window.lerp(Color(NIGHT, window.a), _mix_at(base - 60.0))

	# Paint it: the street line is LAYER_H down from the top; the rows run
	# 600 px below it (the old drawing's depth) to cover the bottom.
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.size = Vector2i(Vector2(width, LAYER_H + 260.0) * PAINT_RES)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Node2D.new()
	painter.scale = Vector2(PAINT_RES, PAINT_RES)
	var flickers := []
	painter.draw.connect(func():
		for s in shapes:
			var sx: float = s.x
			var top: float = LAYER_H - s.h
			painter.draw_rect(Rect2(sx, top, s.w, 600.0), tone)
			if s.roof == "spire":
				painter.draw_colored_polygon(PackedVector2Array([Vector2(sx + s.w * 0.3, top), Vector2(sx + s.w / 2.0, top - s.spire_h), Vector2(sx + s.w * 0.7, top)]), tone)
			elif s.roof == "gable":
				painter.draw_colored_polygon(PackedVector2Array([Vector2(sx - 2.0, top), Vector2(sx + s.w / 2.0, top - s.w * 0.45), Vector2(sx + s.w + 2.0, top)]), tone)
			if s.chimney:
				painter.draw_rect(Rect2(sx + s.w * 0.7, top - 14.0, 6.0, 14.0), tone)
			for wi in s.lit:
				if wi.z <= 0.85:
					painter.draw_rect(Rect2(sx + wi.x, top + wi.y, 3.0, 5.0), window)
	)
	vp.add_child(painter)
	add_child(vp)
	for s in shapes:
		for wi in s.lit:
			if wi.z > 0.85:
				flickers.append(Vector3(s.x + wi.x, LAYER_H - s.h + wi.y, wi.z))

	var sprite := Sprite2D.new()
	sprite.texture = vp.get_texture()
	sprite.centered = false
	sprite.region_enabled = true
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.scale = Vector2.ONE / PAINT_RES
	add_child(sprite)
	# The few windows that flicker are drawn live, just over their row.
	var flicker := Node2D.new()
	add_child(flicker)
	var layer := {"sprite": sprite, "flicker": flicker, "width": width, "base": base, "drift": drift, "rise": rise, "flickers": flickers, "window": window}
	flicker.draw.connect(func(): _draw_flicker(layer))
	return layer


## A soft band of fog with a few wisps drifting along it.
func _fog_band(y: float, h: float, alpha: float, speed: float, rise: float) -> Dictionary:
	var c := _night(FOG, y / 360.0)
	var band := TextureRect.new()
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.texture = _vertical([0.0, 0.5, 1.0], [Color(c, 0.0), Color(c, alpha), Color(c, 0.0)])
	add_child(band)
	var wisps := []
	var wc := _night(Color(0.43, 0.49, 0.55), y / 360.0)
	wc.a = alpha * 0.5
	for i in 5:
		var s := Sprite2D.new()
		s.texture = Glow.texture()
		s.scale = Vector2(280.0, 28.0) / 256.0
		s.modulate = wc
		add_child(s)
		wisps.append(s)
	return {"band": band, "y": y, "h": h, "speed": speed, "rise": rise, "wisps": wisps}


func _draw_moon() -> void:
	var dim := 1.0 - _mix_at(92.0)
	_moon.draw_circle(Vector2.ZERO, 34.0, _night(MOON, 92.0 / 360.0))
	for c in [Vector3(-10, -8, 9), Vector3(12, 6, 6), Vector3(-4, 14, 5), Vector3(9, -14, 4)]:
		_moon.draw_circle(Vector2(c.x, c.y), c.z, Color(0.47, 0.43, 0.39, 0.12 * dim))


func _draw_flicker(layer: Dictionary) -> void:
	if world == null:
		return
	var view: Vector2 = world.view_size()
	var time: float = world.time
	var sprite: Sprite2D = layer.sprite
	var flicker: Node2D = layer.flicker
	var window: Color = layer.window
	var start: float = -sprite.region_rect.position.x / PAINT_RES
	for f in layer.flickers:
		var flick := 0.5 + 0.5 * sin(time * 3.0 + f.z * 40.0)
		var x: float = start + f.x
		while x < view.x:
			if x > -4.0:
				flicker.draw_rect(Rect2(x, sprite.position.y + f.y, 3.0, 5.0), Color(window, window.a * flick))
			x += layer.width


func _process(_delta: float) -> void:
	if world == null:
		return
	var view: Vector2 = world.view_size()
	var cam: Vector2 = world.cam_top_left()
	var time: float = world.time
	# How far the camera is from the street-level view, for vertical drift.
	var dy := cam.y - STREET_Y

	_sky.size = view
	_moon.position = Vector2(view.x * 0.74 - cam.x * 0.01, 92.0 - dy * 0.04)
	_moon_glow.position = _moon.position

	for layer in _layers:
		var sprite: Sprite2D = layer.sprite
		var top: float = layer.base - dy * layer.rise - LAYER_H
		sprite.position = Vector2(0.0, top)
		sprite.region_rect = Rect2(fposmod(cam.x * layer.drift, layer.width) * PAINT_RES, 0.0, view.x * PAINT_RES, (LAYER_H + 260.0) * PAINT_RES)
		layer.flicker.queue_redraw()
	for fog in _fogs:
		var y: float = fog.y - dy * fog.rise
		var band: TextureRect = fog.band
		band.position = Vector2(0.0, y - fog.h)
		band.size = Vector2(view.x, fog.h * 2.0)
		var i := 0
		for s in fog.wisps:
			var x := fposmod(i * 233.0 + time * fog.speed, view.x + 300.0) - 150.0
			s.position = Vector2(x, y + sin(i * 1.7) * fog.h * 0.3)
			i += 1
