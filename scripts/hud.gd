## Everything drawn over the scene: health (with the pale Rally stretch),
## vials, bullets, the weapon form, Tallow, lamp prompts, signs, banners and
## the level-up menu at a lamp. In screen space (the 640x360 base view).
extends Control

const T = preload("res://scripts/tuning.gd")
const Glow = preload("res://scripts/glow.gd")
const Keys = preload("res://scripts/keys.gd")

const FELL := preload("res://assets/fonts/IMFellEnglish-Regular.ttf")
const FELL_ITALIC := preload("res://assets/fonts/IMFellEnglish-Italic.ttf")
const FELL_SC := preload("res://assets/fonts/IMFellEnglishSC-Regular.ttf")
## IM Fell's old-style figures make 0 read as o; numbers use Cinzel.
const NUM := preload("res://assets/fonts/Cinzel-Regular.ttf")

const BONE := Color("e8dfcf")
const BONE_DIM := Color(0.91, 0.87, 0.81, 0.55)
const BLOOD := Color("8e1b1e")
const BLOOD_BRIGHT := Color("c42b2f")
const RALLY := Color("e3ad92")
const TALLOW := Color("f0bd62")
const LAMP := Color("ffcf7a")
const TONES := {"death": Color("b3262a"), "lamp": Color("ffcf7a"), "tallow": Color("f0bd62"), "pale": Color("e8dfcf")}

var world


func _input(event: InputEvent) -> void:
	Keys.notice(event)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var view := size
	if not world.running:
		return
	var p = world.player

	# Health: oxblood, with the pale rally stretch after it.
	var per := 1.5
	var x := 14.0
	var y := 14.0
	var bw: float = p.max_hp * per
	draw_rect(Rect2(x - 2, y - 2, bw + 4, 11), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x, y, maxf(0.0, p.hp) * per, 7), BLOOD)
	draw_rect(Rect2(x, y, maxf(0.0, p.hp) * per, 2), BLOOD_BRIGHT)
	if p.rally > 0.0:
		var c := RALLY
		c.a = 0.85 if p.rally_hold > 0.0 else 0.55 + 0.25 * sin(world.time * 14.0)
		draw_rect(Rect2(x + p.hp * per, y, p.rally * per, 7), c)
	draw_rect(Rect2(x - 2, y - 2, bw + 4, 11), BONE_DIM, false, 0.75)

	# Vials and bullets.
	draw_circle(Vector2(x + 4, y + 22), 4.0, BLOOD_BRIGHT)
	draw_rect(Rect2(x + 3, y + 15, 2, 3), BONE)
	_text(str(p.vials), Vector2(x + 11, y + 22), 11, BONE, NUM)
	# Only what you've found: bullets once you have the pistol, the Pole's
	# form once it can turn.
	if p.has("pistol"):
		draw_rect(Rect2(x + 34, y + 18, 3, 8), Color("c9a34a"))
		draw_circle(Vector2(x + 35.5, y + 18), 1.5, Color("c9a34a"))
		_text(str(p.bullets), Vector2(x + 42, y + 22), 11, BONE if p.bullets > 0 else BLOOD_BRIGHT, NUM)

	var arm: Dictionary = T.ARMS[p.arm]
	var weapon: String = arm.name
	if p.has("lantern"):
		weapon = "%s  ·  %s" % [arm.name, p.form_data().label]
	_text(weapon, Vector2(x, y + 38), 10, BONE_DIM, FELL_SC)

	# Tallow, bottom right.
	_text(str(world.tallow), Vector2(view.x - 16, view.y - 20), 16, TALLOW, NUM, HORIZONTAL_ALIGNMENT_RIGHT)
	if not world.gained.is_empty():
		var g: Dictionary = world.gained
		var c := TALLOW
		c.a = 1.0 - g.t / 1.6
		_text("+%d" % g.amount, Vector2(view.x - 16, view.y - 38 - g.t * 8.0), 11, c, NUM, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("tallow", Vector2(view.x - 16, view.y - 8), 9, BONE_DIM, FELL_SC, HORIZONTAL_ALIGNMENT_RIGHT)

	var menu_open: bool = not world.menu.is_empty()
	if not world.prompt.is_empty() and not menu_open:
		var p_text: String = world.prompt.text
		if world.prompt.get("key", true):
			p_text = "%s  %s" % [Keys.label("interact"), p_text]
		_pill(p_text, world.prompt.pos - world.cam_top_left())
	if world.sign_node and not menu_open:
		_sign_box(Keys.fill(world.sign_node.text), view)
	if not world.fx.notice.is_empty():
		_notice(world.fx.notice, view)
	if not world.lesson.is_empty():
		_lesson(Keys.fill(world.lesson.text), view)
	if not world.fx.banner.is_empty():
		_banner(world.fx.banner, view)
	if menu_open:
		_menu(view)


## Text with its vertical middle at pos.y.
func _text(s: String, pos: Vector2, font_size: int, color: Color, font: Font = FELL, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var x := pos.x
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		x -= w if align == HORIZONTAL_ALIGNMENT_RIGHT else w / 2.0
	draw_string(font, Vector2(x, pos.y + font_size * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Centred text with extra space between the letters.
func _spaced(s: String, center: Vector2, font_size: int, color: Color, font: Font, spacing: float) -> void:
	var widths := []
	var total := 0.0
	for ch in s:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		widths.append(w)
		total += w + spacing
	var x := center.x - (total - spacing) / 2.0
	for i in s.length():
		draw_string(font, Vector2(x, center.y + font_size * 0.35), s[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += widths[i] + spacing


func _pill(s: String, center: Vector2) -> void:
	var w := FELL.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0
	var r := Rect2(center.x - w / 2.0, center.y - 8, w, 16)
	draw_rect(r, Color(0.04, 0.035, 0.055, 0.75))
	draw_rect(r, BONE_DIM, false, 0.5)
	_text(s, center + Vector2(0, 0.5), 10, BONE, FELL, HORIZONTAL_ALIGNMENT_CENTER)


func _wrap(s: String, font_size: int, max_w: float) -> Array:
	var lines := []
	for para in s.split("  "):
		var line := ""
		for word in para.split(" "):
			var next: String = word if line == "" else line + " " + word
			if FELL.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w and line != "":
				lines.append(line)
				line = word
			else:
				line = next
		lines.append(line)
	return lines


func _sign_box(s: String, view: Vector2) -> void:
	var w := minf(view.x - 40.0, 440.0)
	var lines := _wrap(s, 12, w - 28.0)
	var h := lines.size() * 16.0 + 18.0
	var r := Rect2((view.x - w) / 2.0, view.y - h - 34.0, w, h)
	draw_rect(r, Color(0.055, 0.047, 0.063, 0.88))
	draw_rect(r.grow(-3.0), Color(0.91, 0.87, 0.81, 0.35), false, 0.75)
	for i in lines.size():
		_text(lines[i], Vector2(r.position.x + 14, r.position.y + 17 + i * 16), 12, BONE)


## A lesson prompt: big, warm, pulsing, under the action.
func _lesson(s: String, view: Vector2) -> void:
	var font_size := 15
	var w := FELL_SC.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 36.0
	var r := Rect2(view.x / 2.0 - w / 2.0, view.y * 0.66 - 15.0, w, 30.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
	Glow.draw(self, r.get_center(), w * 0.7, Color(1.0, 0.75, 0.4, 0.12 + 0.1 * pulse))
	draw_rect(r, Color(0.04, 0.035, 0.05, 0.9))
	draw_rect(r, Color(1.0, 0.81, 0.48, 0.5 + 0.4 * pulse), false, 1.0)
	_text(s, r.get_center(), font_size, LAMP, FELL_SC, HORIZONTAL_ALIGNMENT_CENTER)


func _notice(n: Dictionary, view: Vector2) -> void:
	var c := BONE
	c.a = clampf(minf(n.t * 3.0, (n.dur - n.t) * 2.0), 0.0, 1.0)
	_text(n.text, Vector2(view.x / 2.0, 64), 12, c, FELL_ITALIC, HORIZONTAL_ALIGNMENT_CENTER)


func _banner(b: Dictionary, view: Vector2) -> void:
	var a := clampf(minf(b.t * 2.5, (b.dur - b.t) * 1.5), 0.0, 1.0)
	var y := view.y * 0.4
	# A dark band behind the words.
	draw_polygon(PackedVector2Array([Vector2(0, y - 34), Vector2(view.x, y - 34), Vector2(view.x, y), Vector2(0, y)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55 * a), Color(0, 0, 0, 0.55 * a)]))
	draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(view.x, y), Vector2(view.x, y + 34), Vector2(0, y + 34)]),
		PackedColorArray([Color(0, 0, 0, 0.55 * a), Color(0, 0, 0, 0.55 * a), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	var col: Color = TONES.get(b.tone, BONE)
	col.a = a
	_spaced(b.text, Vector2(view.x / 2.0, y), 30 if b.tone == "death" else 24, col, FELL_SC, 2.0)
	if b.sub != "":
		var c := BONE
		c.a = a
		_text(b.sub, Vector2(view.x / 2.0, y + 22), 12, c, FELL_ITALIC, HORIZONTAL_ALIGNMENT_CENTER)


func _menu(view: Vector2) -> void:
	var w := 260.0
	var h := 168.0
	var r := Rect2((view.x - w) / 2.0, (view.y - h) / 2.0 + 10.0, w, h)
	draw_rect(r, Color(0.04, 0.035, 0.05, 0.92))
	draw_rect(r.grow(-4.0), Color(1.0, 0.81, 0.48, 0.45), false, 0.75)

	var cost: int = world.level_cost()
	var afford: bool = world.tallow >= cost
	var x := r.position.x
	var y := r.position.y
	_text("The lamp burns", Vector2(x + 18, y + 22), 15, LAMP, FELL_SC)
	_text("Level %d   ·   next %d tallow" % [world.level_no, cost], Vector2(x + 18, y + 40), 9, BONE_DIM, NUM)
	_text(str(world.tallow), Vector2(x + w - 18, y + 22), 13, TALLOW, NUM, HORIZONTAL_ALIGNMENT_RIGHT)

	var rows := []
	for s in T.STATS:
		rows.append({"label": s.label, "n": world.stats[s.id], "note": s.note, "buy": true})
	rows.append({"label": "Leave", "note": "", "buy": false})
	for i in rows.size():
		var row: Dictionary = rows[i]
		var ry := y + 62.0 + i * 22.0
		var sel: bool = i == world.menu.index
		if sel:
			draw_rect(Rect2(x + 10, ry - 9, w - 20, 18), Color(1.0, 0.81, 0.48, 0.12))
		var col := BONE
		if row.buy and not afford:
			col = Color(0.91, 0.87, 0.81, 0.4)
		elif sel:
			col = LAMP
		var label := ("› " if sel else "  ") + String(row.label)
		_text(label, Vector2(x + 16, ry), 12, col)
		if row.buy:
			var lw := FELL.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_text(str(row.n), Vector2(x + 22 + lw, ry + 0.5), 10, col, NUM)
		_text(row.note, Vector2(x + w - 16, ry), 10, BONE_DIM, FELL_ITALIC, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("%s choose   ·   %s leave" % [Keys.label("confirm"), Keys.label("back")], Vector2(x + 18, y + h - 12), 9, BONE_DIM)
