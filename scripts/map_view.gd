## The district map, drawn from what you've explored (World.explored): stone,
## walkways, water and veils, plus lamps, gates, finds you've seen, your
## dropped tallow, Gorged enemies, and you. Shown on the pause screen.
extends Control

const T = preload("res://scripts/tuning.gd")
const Glow = preload("res://scripts/glow.gd")

const STONE := Color("3a3c4a")
const SURFACE := Color("8a8ca0")
const INDOOR := Color("15151c")
const OUTDOOR := Color("0d0f16")
const WALKWAY := Color("8a6446")
const WATER := Color("1f5a52")
const VEIL := Color("d8d0bc")
const LAMP := Color("ffcf7a")
const UNLIT := Color("6a6870")
const GATE := Color("b0603a")
const FIND := Color("e8dfcf")
const TALLOW := Color("f0bd62")
const GORGED := Color("ff6a3d")
const YOU := Color("e3443e")

var world


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var level = world.level
	var w: int = level.size_tiles.x
	var h: int = level.size_tiles.y
	var cell := minf(size.x / w, size.y / h)
	var origin := (size - Vector2(w, h) * cell) / 2.0
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))

	# Tiles.
	for r in h:
		for c in w:
			var at := Vector2i(c, r)
			if not world.is_explored(at):
				continue
			var rect := Rect2(origin + Vector2(c, r) * cell, Vector2(cell, cell))
			var k: String = level.kind_at(at)
			match k:
				"stone":
					draw_rect(rect, STONE)
					if level.kind_at(at + Vector2i.UP) != "stone":
						draw_rect(Rect2(rect.position, Vector2(cell, maxf(1.0, cell * 0.25))), SURFACE)
				"walkway":
					draw_rect(Rect2(rect.position, Vector2(cell, maxf(1.0, cell * 0.3))), WALKWAY)
				"water":
					draw_rect(rect, WATER)
				"veil":
					draw_rect(rect, VEIL)
				_:
					var roofed: bool = level.back_wall.get_cell_source_id(at) != -1
					draw_rect(rect, INDOOR if roofed else OUTDOOR)

	var to_map := func(p: Vector2) -> Vector2: return origin + p / T.TILE * cell
	var seen := func(p: Vector2) -> bool: return world.is_explored(Vector2i(floori(p.x / T.TILE), floori((p.y - 1.0) / T.TILE)))

	for l in world.lamps:
		if seen.call(l.position):
			var m: Vector2 = to_map.call(l.position + Vector2(0, -12))
			if l.lit:
				Glow.draw(self, m, cell * 2.5, Color(1.0, 0.8, 0.45, 0.6))
			draw_circle(m, maxf(2.0, cell * 0.55), LAMP if l.lit else UNLIT)
	for g in world.gates:
		if seen.call(g.position):
			var top: Vector2 = to_map.call(g.position + Vector2(0, -96))
			var bottom: Vector2 = to_map.call(g.position)
			if g.open:
				draw_line(top, top + Vector2(0, cell * 0.6), GATE, 1.0)
			else:
				draw_line(top, bottom, GATE, maxf(1.5, cell * 0.45))
	for it in world.pickups:
		if not it.taken and seen.call(it.position):
			var m: Vector2 = to_map.call(it.position + Vector2(0, -12))
			var s := maxf(1.5, cell * 0.4)
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, -s), m + Vector2(s, 0), m + Vector2(0, s), m + Vector2(-s, 0)]), FIND)
	for e in world.enemies:
		if e.alive and e.gorged > 0 and seen.call(e.position):
			draw_circle(to_map.call(e.position + Vector2(0, -12)), maxf(2.0, cell * 0.5), GORGED)
	if not world.pile.is_empty():
		var m: Vector2 = to_map.call(world.pile.pos + Vector2(0, -12))
		Glow.draw(self, m, cell * 2.0, Color(1.0, 0.75, 0.4, 0.6))
		draw_circle(m, maxf(2.0, cell * 0.5), TALLOW)

	# You, pointing the way you face.
	var p = world.player
	var m: Vector2 = to_map.call(p.position + Vector2(0, -20))
	var s := maxf(3.0, cell * 0.9)
	var f: float = p.facing
	draw_colored_polygon(PackedVector2Array([m + Vector2(f * s, 0), m + Vector2(-f * s * 0.6, -s * 0.7), m + Vector2(-f * s * 0.6, s * 0.7)]), YOU)
