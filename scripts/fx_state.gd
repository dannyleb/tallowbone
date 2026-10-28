## Particles, tallow motes, screen shake and the banners: plain data that the
## FX layers and the HUD draw.
extends RefCounted

var parts: Array = []
var motes: Array = []
var shake := 0.0
## { text, sub, t, dur, tone } or empty.
var banner := {}
## { text, t, dur } or empty.
var notice := {}


## count particles at `at`. spread: speed range; up: extra upward kick;
## glow: drawn additively, above the dark (embers, tallow light).
func burst(at: Vector2, opts := {}) -> void:
	var count: int = opts.get("count", 8)
	var color: Color = opts.get("color", Color("8e1b1e"))
	var spread: float = opts.get("spread", 160.0)
	var up: float = opts.get("up", 60.0)
	var life: float = opts.get("life", 0.6)
	var size: float = opts.get("size", 2.5)
	var gravity: float = opts.get("gravity", 900.0)
	var glow: bool = opts.get("glow", false)
	var dir: float = opts.get("dir", 0.0)
	for i in count:
		var a := randf() * TAU
		var s := spread * (0.3 + randf() * 0.7)
		var l := life * (0.6 + randf() * 0.4)
		parts.append({
			"pos": at,
			"vel": Vector2(cos(a) * s + dir * spread * 0.6, sin(a) * s - up),
			"life": l, "max": l, "color": color,
			"size": size * (0.6 + randf() * 0.8), "gravity": gravity, "glow": glow,
		})


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


func show_banner(text: String, sub := "", dur := 2.4, tone := "pale") -> void:
	banner = {"text": text, "sub": sub, "t": 0.0, "dur": dur, "tone": tone}


## A quieter line near the top of the screen.
func show_notice(text: String, dur := 3.2) -> void:
	notice = {"text": text, "t": 0.0, "dur": dur}


## Tallow motes: little lights that drift up from a kill.
func add_motes(at: Vector2, n: int) -> void:
	for i in n:
		motes.append({"pos": at, "vel": Vector2((randf() - 0.5) * 120.0, -60.0 - randf() * 80.0), "t": -i * 0.03})


func update(delta: float) -> void:
	for p in parts:
		p.life -= delta
		p.vel.y += p.gravity * delta
		p.pos += p.vel * delta
	parts = parts.filter(func(p): return p.life > 0.0)
	for m in motes:
		m.t += delta
		m.vel = Vector2(m.vel.x * 0.96, m.vel.y * 0.96 - 20.0 * delta)
		m.pos += m.vel * delta
	motes = motes.filter(func(m): return m.t < 1.1)
	shake = maxf(0.0, shake - delta * 30.0)
	if not banner.is_empty():
		banner.t += delta
		if banner.t > banner.dur:
			banner = {}
	if not notice.is_empty():
		notice.t += delta
		if notice.t > notice.dur:
			notice = {}
