## Draws the World's effects in one of three passes:
##   shaded:  ordinary particles (blood, water), lit by the scene's lights
##   overlay: health bars, stun rings, the pistol's tracer, debug hitboxes;
##            unshaded so the dark never hides them
##   glow:    added light that sits above the dark: glints, embers, tallow
##            motes, your dropped tallow
extends Node2D

const T = preload("res://scripts/tuning.gd")
const Combat = preload("res://scripts/combat.gd")
const Glow = preload("res://scripts/glow.gd")

@export_enum("shaded", "overlay", "glow") var mode := "shaded"

var world


func _ready() -> void:
	if mode != "shaded":
		var m := CanvasItemMaterial.new()
		m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		if mode == "glow":
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	match mode:
		"shaded":
			_particles(false)
		"overlay":
			_overlay()
		"glow":
			_glow()


func _particles(glow: bool) -> void:
	for p in world.fx.parts:
		if p.glow != glow:
			continue
		var c: Color = p.color
		c.a = clampf(p.life / p.max, 0.0, 1.0)
		# A drop drawn out along its flight (a frame and a half of it): a
		# round head, a tail thinning behind.
		var v: Vector2 = p.vel
		var at: Vector2 = p.pos
		var size: float = p.size
		var speed := v.length()
		var along := v / speed if speed > 1.0 else Vector2.DOWN
		var across := along.orthogonal() * size * 0.42
		var head := at + along * size * 0.45
		var tail := at - along * (size * 0.5 + minf(speed * 0.025, size * 3.0))
		draw_colored_polygon(PackedVector2Array([head + along * size * 0.15, head + across * 0.8, at + across, tail, at - across, head - across * 0.8]), c)


func _overlay() -> void:
	for e in world.enemies:
		if not e.alive:
			continue
		if e.state == "stagger" or e.state == "held":
			var a := 0.35 + 0.25 * sin(world.time * 10.0)
			_ellipse_outline(e.position + Vector2(0, -e.def.h - 4), 12.0, 4.0, Color(1.0, 0.96, 0.85, a))
		if e.hp < e.max_hp or e.gorged > 0:
			var w := 28.0
			var at: Vector2 = e.position + Vector2(-w / 2.0, -e.def.h - 12.0)
			draw_rect(Rect2(at - Vector2(1, 1), Vector2(w + 2, 4)), Color(0, 0, 0, 0.6))
			var col := Color("ff6a3d") if e.gorged > 0 else Color("8e1b1e")
			draw_rect(Rect2(at, Vector2(w * maxf(0.0, e.hp / e.max_hp), 2)), col)
	var sw: Dictionary = world.player.swoosh()
	if not sw.is_empty():
		_swoosh(sw)
	if not world.shot.is_empty():
		var s: Dictionary = world.shot
		draw_line(s.from, s.to, Color(1.0, 0.93, 0.78, s.t / 0.07), 1.2)
	if world.show_hitboxes:
		_hitboxes()


## The swing's trail as a blur rather than a painted band: thin and faint
## at its tail, full where the pole's head is now, bright along the outer
## edge and fading inward.
func _swoosh(sw: Dictionary) -> void:
	var head: float = sw.head
	var tail: float = sw.from if absf(sw.from - head) > absf(sw.to - head) else sw.to
	var c: Color = sw.color
	var n := 18
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in n + 1:
		var k := float(i) / n
		var ang := lerpf(tail, head, k)
		var dir := Vector2(cos(ang), sin(ang))
		var w: float = sw.width * (0.3 + 0.9 * k) * 1.5
		outer.append(sw.center + dir * (float(sw.radius) + w * 0.35))
		inner.append(sw.center + dir * (float(sw.radius) - w * 0.65))
	for i in n:
		var a0 := c.a * pow(float(i) / n, 1.6)
		var a1 := c.a * pow(float(i + 1) / n, 1.6)
		draw_polygon(PackedVector2Array([outer[i], outer[i + 1], inner[i + 1], inner[i]]),
			PackedColorArray([Color(c, a0), Color(c, a1), Color(c, a1 * 0.1), Color(c, a0 * 0.1)]))


func _glow() -> void:
	# Lit lamp glass and your own flame burn through the dark.
	for l in world.lamps:
		# (In 3D the lantern stands behind the plane, so a halo drawn here
		# would sit off its glass; the glass glows there and the haze and
		# bloom make the halo.)
		if l.lit and not l.in_3d:
			var g: Vector2 = l.position + Vector2(0, -68)
			Glow.draw(self, g, 22.0, Color(1.0, 0.72, 0.38, 0.35))
			draw_colored_polygon(PackedVector2Array([g + Vector2(-5, 8), g + Vector2(5, 8), g + Vector2(7, -7), g + Vector2(-7, -7)]), Color(1.0, 0.78, 0.45, 0.55))
	for it in world.pickups:
		if not it.taken:
			Glow.draw(self, it.position + Vector2(0, -14), 22.0, Color(1.0, 0.85, 0.8, 0.28))
	# The things of the night: an eye catching what light there is, burning
	# when they've Gorged.
	for e in world.enemies:
		if not e.visible:
			continue
		var eye = e.eye_at()
		if eye != null:
			var hot: bool = e.gorged > 0
			Glow.draw(self, eye, 4.0 if hot else 3.0, Color(1.0, 0.42, 0.2, 0.6) if hot else Color(0.95, 0.85, 0.55, 0.35))
	var p = world.player
	if p.visible and p.state != "dead":
		var f: Vector2 = p.flame_at()
		Glow.draw(self, f, 14.0 if p.form == "lantern" else 6.0, Color(1.0, 0.75, 0.42, 0.45))
	_particles(true)
	for m in world.fx.motes:
		if m.t < 0.0:
			continue
		var c := Color("f0bd62")
		c.a = maxf(0.0, 1.0 - m.t / 1.1)
		draw_rect(Rect2(m.pos - Vector2(1, 1), Vector2(2.5, 2.5)), c)
	if not world.pile.is_empty():
		_pile(world.pile.pos)
	for e in world.enemies:
		if not e.alive:
			continue
		if e.gorged > 0:
			_embers(e)
		if Combat.parryable(e):
			_glint(e.weapon_point(), e.t - (e.def.windup - e.def.parry))


## The parry cue: a bright four-point star that blooms as the window opens.
func _glint(at: Vector2, since: float) -> void:
	var s := 5.0 + minf(1.0, since / 0.08) * 9.0 - maxf(0.0, since - 0.1) * 10.0
	Glow.draw(self, at, s * 2.2, Color(1.0, 0.96, 0.85, 0.9))
	var pts := PackedVector2Array()
	var spin: float = world.time * 2.0
	for i in 8:
		var r := s * 0.18 if i % 2 == 1 else s
		var ang := spin + i * PI / 4.0
		pts.append(at + Vector2(cos(ang), sin(ang)) * r)
	draw_colored_polygon(pts, Color("fff6d8"))


func _embers(e) -> void:
	for i in 6:
		var k := fmod(world.time * 0.7 + i / 6.0 + e.spawn_pos.x * 0.01, 1.0)
		var c := Color("ff6a3d")
		c.a = (1.0 - k) * 0.9
		var x: float = e.position.x + sin(i * 2.7 + world.time * 2.0) * 9.0
		draw_rect(Rect2(x, e.position.y - 20.0 - k * 32.0, 1.5, 1.5), c)


## Your dropped tallow: a guttering ghost-light where you fell.
func _pile(at: Vector2) -> void:
	var time: float = world.time
	Glow.draw(self, at + Vector2(0, -12), 34.0, Color(1.0, 0.73, 0.4, 0.35))
	var cols := [Color(0.94, 0.74, 0.38, 0.35), Color(1.0, 0.84, 0.55, 0.6), Color(1.0, 0.96, 0.86, 0.85)]
	for i in 3:
		var h := 16.0 + sin(time * 9.0 + i * 2.0) * 4.0 + i * 3.0
		var w := 7.0 - i * 1.8
		var tip := at + Vector2(sin(time * 5.0) * 2.0, -h)
		var pts := PackedVector2Array([at + Vector2(-w, -2)])
		for k in range(1, 6):
			var q := k / 6.0
			pts.append(at + Vector2(-w, -2).lerp(Vector2(-w, -h * 0.6), q).lerp(Vector2(-w, -h * 0.6).lerp(tip - at, q), q))
		pts.append(tip)
		for k in range(1, 6):
			var q := k / 6.0
			pts.append(at + (tip - at).lerp(Vector2(w, -h * 0.6), q).lerp(Vector2(w, -h * 0.6).lerp(Vector2(w, -2), q), q))
		pts.append(at + Vector2(w, -2))
		draw_colored_polygon(pts, cols[i])
	for i in 4:
		var k := fmod(time * 0.6 + i / 4.0, 1.0)
		draw_rect(Rect2(at.x + sin(i * 2.3 + time) * 8.0, at.y - 8.0 - k * 34.0, 1.5, 1.5), Color(1.0, 0.86, 0.63, 0.7))


func _ellipse_outline(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var ang := TAU * i / 16.0
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_polyline(pts, col, 1.0)


## H in a debug build (or ?debug on the web): bodies, attack and strike
## hitboxes.
func _hitboxes() -> void:
	var p = world.player
	draw_rect(p.body_rect(), Color(0.47, 1.0, 0.63, 0.8), false, 1.0)
	if p.state == "attack" and p.t >= p.attack.startup and p.t < p.attack.startup + p.attack.active:
		draw_rect(p.attack_box(p.attack), Color(1.0, 0.86, 0.35, 0.9), false, 1.0)
	for e in world.enemies:
		if not e.alive:
			continue
		draw_rect(e.body_rect(), Color(0.47, 0.7, 1.0, 0.8), false, 1.0)
		if e.state == "strike":
			draw_rect(e.strike_box(), Color(1.0, 0.31, 0.31, 0.9), false, 1.0)
