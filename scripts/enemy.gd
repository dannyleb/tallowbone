## An enemy of the Long Night. One script for every type: `kind` picks the
## numbers (Tuning.ENEMIES) and the look.
##
## Placed in the level, it remembers where it started and is put back there
## (alive, full health) whenever you rest or die. `gorged` (tallow it took
## from your pile) survives that reset; only your next death clears it.
##
## The drawing is a greybox stand-in for sprites, posed from the real attack
## timings so what you see matches the hitboxes.
extends CharacterBody2D

const T = preload("res://scripts/tuning.gd")
const Combat = preload("res://scripts/combat.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Figure = preload("res://scripts/figure.gd")
const Art = preload("res://scripts/art.gd")

const ROBE := Color("4d4038")
const ROBE_DARK := Color("2f2722")
const FLESH := Color("c9bba1")
const HOUND := Color("45372f")
const GORGED_COLOR := Color("ff6a3d")

## Each kind's drawing canvas in world px, and where the feet are on it.
const FIGS := {"communicant": [Vector2(104, 92), Vector2(52, 80)], "hound": [Vector2(90, 48), Vector2(45, 38)]}
## Painted animations (docs/ART.md) and their frame counts, the same for
## every kind: art/characters/<kind>/<animation>/.
const ART_ANIMS := {"idle": 2, "walk": 4, "windup": 3, "strike": 2, "recover": 2, "flinch": 1, "stagger": 2, "held": 1, "dead": 3}

@export_enum("communicant", "hound") var kind := "communicant"

var world
var def: Dictionary
var spawn_pos := Vector2.ZERO
var gorged := 0
var hp := 1.0
var max_hp := 1.0
var alive := true
var state := "idle"
var t := 0.0
var facing := -1.0
var cooldown := 0.0
var lost := 0.0
var wander_t := 0.0
var wander_dir := 0.0
var hit_done := false
var glinted := false
var flash := 0.0
var dead_t := 0.0
var run_t := 0.0
var _time := 0.0
var _fig: Sprite2D


func _ready() -> void:
	def = T.ENEMIES[kind]
	spawn_pos = position
	_fig = Figure.new()
	add_child(_fig)
	_fig.setup(FIGS[kind][0], FIGS[kind][1], _paint)
	reset()


func reset() -> void:
	position = spawn_pos
	velocity = Vector2.ZERO
	facing = -1.0
	max_hp = roundf(def.hp * (T.GORGED.hp if gorged > 0 else 1.0))
	hp = max_hp
	alive = true
	visible = true
	state = "idle"
	t = 0.0
	cooldown = 0.0
	lost = 0.0
	wander_t = 0.0
	flash = 0.0
	dead_t = 0.0


func die() -> void:
	alive = false
	state = "dead"
	dead_t = 0.0


func body_rect() -> Rect2:
	return Rect2(position.x - def.w / 2.0, position.y - def.h, def.w, def.h)


func strike_box() -> Rect2:
	var h: Dictionary = def.hit
	var r := body_rect()
	var front := r.end.x if facing > 0 else r.position.x
	var x: float = front if facing > 0 else front - h.reach
	var w: float = h.reach
	if h.body:
		x = minf(x, r.position.x)
		w = h.reach + r.size.x
	return Rect2(x, position.y + h.top, w, h.bottom - h.top)


func step(delta: float) -> void:
	_time += delta
	if not alive:
		dead_t += delta
		visible = dead_t < 0.9
		_fig.redraw()
		return
	var level = world.level
	var p = world.player
	t += delta
	cooldown -= delta
	flash = maxf(0.0, flash - delta)

	var dx: float = p.position.x - position.x
	var dy: float = p.position.y - position.y
	var gap: float = absf(dx) - (def.w + p.W) / 2.0
	var speed: float = def.speed * (T.GORGED.speed if gorged > 0 else 1.0)
	var sees: bool = p.state != "dead" and absf(dx) < def.aggro and absf(dy) < 120.0 \
		and level.line_of_sight(position + Vector2(0, -def.h + 8), p.position + Vector2(0, -p.H + 8))
	var walk := 0.0

	match state:
		"idle":
			if sees:
				state = "chase"
				t = 0.0
			else:
				# Shuffle about near where it spawned.
				wander_t -= delta
				if wander_t <= 0.0:
					var home := spawn_pos.x - position.x
					wander_dir = signf(home) if absf(home) > 48.0 else [-1.0, 0.0, 0.0, 1.0][randi() % 4]
					wander_t = 1.0 + randf() * 1.5
					if wander_dir != 0.0:
						facing = wander_dir
				walk = wander_dir * 0.35
		"chase":
			facing = signf(dx) if dx != 0.0 else facing
			lost = 0.0 if sees else lost + delta
			if lost > 2.5 or p.state == "dead":
				state = "idle"
				t = 0.0
			elif gap < def.range and absf(dy) < 48.0 and cooldown <= 0.0 and is_on_floor():
				state = "windup"
				t = 0.0
				glinted = false
				if absf(dx) < 420.0:
					Sfx.play("growl" if kind == "hound" else "moan")
			else:
				walk = facing if gap > 4.0 else 0.0
		"windup":
			# Tracks you for the first half, then it's committed.
			if t < def.windup * 0.5 and dx != 0.0:
				facing = signf(dx)
			if not glinted and t >= def.windup - def.parry:
				glinted = true
				if absf(dx) < 420.0:
					Sfx.play("glint")
			if t >= def.windup:
				state = "strike"
				t = 0.0
				hit_done = false
				if kind == "hound" and absf(dx) < 420.0:
					Sfx.play("snarl")
				if def.lunge > 0.0:
					velocity = Vector2(facing * def.lunge, -160.0)
				else:
					velocity.x = facing * def.step
		"strike":
			if not hit_done and strike_box().intersects(p.body_rect()):
				var dmg: float = def.damage * (T.GORGED.damage if gorged > 0 else 1.0)
				if Combat.hurt_player(world, roundf(dmg), position.x):
					hit_done = true
			if t >= def.strike and (def.lunge == 0.0 or is_on_floor()):
				state = "recover"
				t = 0.0
		"recover":
			if t >= def.recover:
				state = "chase"
				t = 0.0
				cooldown = def.cooldown
		"flinch":
			if t >= 0.22:
				state = "chase"
				t = 0.0
		"stagger":
			if t >= 1.6:
				state = "chase"
				t = 0.0
				cooldown = 0.3
		"held": # in the middle of a Visceral attack
			velocity.x = 0.0

	if walk != 0.0 and (not _floor_ahead(level, signf(walk)) or _wall_ahead(level, signf(walk))):
		if state == "idle":
			wander_dir = -wander_dir
		walk = 0.0
	if state == "idle" or state == "chase":
		velocity.x = walk * speed
		if walk != 0.0 and is_on_floor():
			run_t += delta * absf(walk)
	elif not (state == "strike" and def.lunge > 0.0):
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	velocity.y = minf(velocity.y + T.GRAVITY * delta, T.MAX_FALL)
	move_and_slide()

	# The canal takes anything that falls in, and what it carried comes to you.
	if level.hazard_at(position + Vector2(0, -4)):
		Combat.kill_enemy(world, self)
	_fig.redraw()


func _floor_ahead(level, dir: float) -> bool:
	var r := body_rect()
	var x := r.end.x + 2.0 if dir > 0 else r.position.x - 2.0
	return level.standable_at(Vector2(x, position.y + 2.0))


func _wall_ahead(level, dir: float) -> bool:
	var r := body_rect()
	var x := r.end.x + 2.0 if dir > 0 else r.position.x - 2.0
	return level.solid_at(Vector2(x, position.y - 4.0)) or level.solid_at(Vector2(x, r.position.y))


## Where its eye is (for the glow drawn over the dark), or nowhere (null)
## when it shouldn't show: dead, staggered, or painted art (which may have
## no eye there).
func eye_at():
	if not alive or state == "stagger" or state == "held" or Art.frames(kind).has(art_frame()[0]):
		return null
	if kind == "hound":
		return position + Vector2(facing * 17.5 * _stretch, -18.2 + _crouch)
	return position + Vector2(facing * 13.6, -34.6)


## Where the parry glint shows: the claw tip, or the hound's teeth.
func weapon_point() -> Vector2:
	if kind == "hound":
		return position + Vector2(facing * 20.0, -13.0)
	var th := _claw_angle()
	return position + Vector2(facing * (4.0 + cos(th) * 24.0), -30.0 + sin(th) * 24.0)


# --- Drawing ---------------------------------------------------------------

## Draws the enemy onto ci, its Figure's painter, with the feet at 0, 0.
func _paint(ci: CanvasItem) -> void:
	if not alive and dead_t > 0.9:
		return
	var pose := art_frame()
	if Art.frames(kind).has(pose[0]):
		_paint_art(ci, pose)
		return
	_fig.set_flash(0.0)
	_fig.set_textured(true)
	var a := 1.0 - dead_t / 0.9 if not alive else 1.0
	var sink := dead_t * 10.0 if not alive else 0.0
	var rot := 0.0
	var lift := 0.0
	if state == "stagger" or state == "held":
		rot = 0.22
		lift = 4.0
	if not alive:
		rot = -dead_t * 1.2
	ci.draw_set_transform(Vector2(0, sink + lift), rot * facing, Vector2(facing, 1))
	var fl := flash > 0.0
	if kind == "hound":
		_paint_hound(ci, fl, a)
	else:
		_paint_communicant(ci, fl, a)
	ci.draw_set_transform(Vector2.ZERO)


## A painted frame: facing your way, white on a hit, redder when Gorged,
## fading out at the end of its death.
func _paint_art(ci: CanvasItem, pose: Array) -> void:
	var a := clampf((0.9 - dead_t) / 0.3, 0.0, 1.0) if not alive else 1.0
	var tint := Color(1.0, 0.72, 0.66, a) if gorged > 0 else Color(1, 1, 1, a)
	_fig.set_flash(1.0 if flash > 0.0 else 0.0)
	_fig.set_textured(false)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing, 1))
	Art.draw(ci, kind, pose, FIGS[kind][0], FIGS[kind][1], tint)
	ci.draw_set_transform(Vector2.ZERO)


## The painted frame for what it's doing now: [animation, frame].
func art_frame() -> Array:
	var name := "idle"
	var phase := 0.0
	var stride := 16.0 if kind == "hound" else 9.0
	if not alive:
		name = "dead"
		phase = dead_t / 0.9
	else:
		match state:
			"idle", "chase":
				if absf(velocity.x) > 5.0:
					name = "walk"
					phase = fposmod(run_t * stride / TAU, 1.0)
				else:
					phase = fposmod(_time / 1.4, 1.0)
			"windup":
				name = "windup"
				phase = t / def.windup
			"strike":
				name = "strike"
				phase = t / def.strike
			"recover":
				name = "recover"
				phase = t / def.recover
			"flinch":
				name = "flinch"
			"stagger":
				name = "stagger"
				phase = t / 1.6
			"held":
				name = "held"
	var n: int = ART_ANIMS[name]
	return [name, clampi(int(phase * n), 0, n - 1)]


## Poses it as frame `frame` of painted animation `anim`, at the middle of
## the moment it covers, facing right (tests/art_templates.gd).
func art_pose(anim: String, frame: int) -> void:
	var n: int = ART_ANIMS[anim]
	var mid := (frame + 0.5) / n
	alive = true
	dead_t = 0.0
	flash = 0.0
	state = "idle"
	t = 0.0
	_time = 0.0
	run_t = 0.0
	velocity = Vector2.ZERO
	facing = 1.0
	match anim:
		"idle":
			_time = mid * 1.4
		"walk":
			state = "chase"
			velocity.x = def.speed
			run_t = mid * TAU / (16.0 if kind == "hound" else 9.0)
		"windup":
			state = "windup"
			t = mid * def.windup
		"strike":
			state = "strike"
			t = mid * def.strike
		"recover":
			state = "recover"
			t = mid * def.recover
		"flinch", "held":
			state = anim
		"stagger":
			state = "stagger"
			t = mid * 1.6
		"dead":
			alive = false
			state = "dead"
			dead_t = mid * 0.9


## A colour of the drawing: blanched toward bone-white on a hit (not pure
## white, so the hit still shows its form), faded by a.
func _c(color: Color, white: bool, a: float) -> Color:
	var c := color.lerp(Color(1.0, 0.95, 0.88), 0.7) if white else color
	c.a *= a
	return c


func _claw_angle() -> float:
	match state:
		"windup":
			return lerpf(1.0, -2.3, _ease(t / (def.windup * 0.6)))
		"strike":
			return lerpf(-2.3, 0.7, _ease(t / def.strike))
		"recover":
			return lerpf(0.7, 1.0, clampf(t / def.recover, 0.0, 1.0))
		"flinch":
			return -0.4
	return 1.05 + sin(_time * 2.0 + spawn_pos.x) * 0.08


static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


func _paint_communicant(ci: CanvasItem, fl: bool, a: float) -> void:
	var robe := _c(Color("5c302a") if gorged > 0 else ROBE, fl, a)
	var dark := _c((Color("5c302a") if gorged > 0 else ROBE).darkened(0.4), fl, a)
	var flesh := _c(FLESH, fl, a)
	var bone := _c(FLESH.darkened(0.25), fl, a)
	var stride := sin(run_t * 9.0) * 2.0
	var th := _claw_angle()
	# The far arm, thin, hanging behind.
	var bs := Vector2(-2, -31)
	var bh := bs + Vector2(-1.5 - stride * 0.6, 15.0)
	ci.draw_polyline(PackedVector2Array([bs, bs + Vector2(-2.5, 7.5), bh]), _c(FLESH.darkened(0.45), fl, a), 1.8)
	for k in [-0.35, 0.0, 0.35]:
		ci.draw_line(bh, bh + Vector2(sin(k) * 3.0, 4.5), _c(FLESH.darkened(0.45), fl, a), 1.0)
	# Bony shins and long bare feet under the hem.
	for side in [-1.0, 1.0]:
		var x: float = side * 4.0 + stride * side
		var col := flesh if side > 0.0 else bone
		ci.draw_line(Vector2(x - 0.5, -9), Vector2(x, -1.2), col, 1.8)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x - 1.5, -1.6), Vector2(x + 4.5, -0.9), Vector2(x + 4.8, 0.0), Vector2(x - 1.8, 0.0)]), col)
	# A tattered underhem, swaying.
	for i in 7:
		var hx := -10.0 + i * 3.2
		var sw := sin(_time * 3.0 + i * 1.7) * 1.2
		ci.draw_colored_polygon(PackedVector2Array([Vector2(hx, -9), Vector2(hx + 3.0, -9), Vector2(hx + 1.6 + sw, -1.5 - float(i % 3))]), dark)
	# The hunched robe.
	var hump := PackedVector2Array()
	for i in 11:
		var k := i / 10.0
		hump.append(Vector2(-11, -24).lerp(Vector2(-7, -43), k).lerp(Vector2(-7, -43).lerp(Vector2(7, -36), k), k))
	hump.append_array(PackedVector2Array([
		Vector2(9, -30), Vector2(10, -8), Vector2(7, -4), Vector2(4, -7), Vector2(1, -3),
		Vector2(-2, -7), Vector2(-5, -3.5), Vector2(-8, -7), Vector2(-11.5, -4.5), Vector2(-12, -14),
	]))
	ci.draw_colored_polygon(hump, robe)
	# Folds, and the shadow down its back.
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-11, -24), Vector2(-8, -38), Vector2(-6, -30), Vector2(-7, -8), Vector2(-11.5, -4.5), Vector2(-12, -14)]), dark)
	for fx in [-3.0, 1.5, 5.5]:
		ci.draw_line(Vector2(fx, -26), Vector2(fx + 0.8, -6), dark, 0.9)
	# The spine standing out through the cloth.
	for i in 5:
		var k := 0.25 + i * 0.13
		var p := Vector2(-11, -24).lerp(Vector2(-7, -43), k).lerp(Vector2(-7, -43).lerp(Vector2(7, -36), k), k)
		ci.draw_circle(p + Vector2(0.6, 0.8), 1.3, dark)
	# Tallow it has drunk, sweating out of it and running down the hump.
	var wax := _c(Color("d6c99a"), fl, a)
	for d in [[Vector2(-6, -40), 7.0], [Vector2(-2, -41), 11.0], [Vector2(2, -39), 5.0]]:
		var top: Vector2 = d[0]
		var len: float = d[1]
		ci.draw_line(top, top + Vector2(-0.6, len), wax, 1.3)
		ci.draw_circle(top + Vector2(-0.6, len + 0.4), 1.0, wax)
	# A rope belt hung with knuckle bones.
	ci.draw_line(Vector2(-11, -19), Vector2(9.5, -21), _c(Color("6b5a44"), fl, a), 1.3)
	for bx in [-4.0, 2.0, 6.0]:
		var by: float = -20.0 + bx * -0.1
		var cord := Vector2(bx + sin(_time * 2.0 + bx) * 0.8, by + 5.0)
		ci.draw_line(Vector2(bx, by), cord, _c(Color("6b5a44"), fl, a), 0.8)
		ci.draw_rect(Rect2(cord.x - 0.9, cord.y, 1.8, 2.6), bone)
	# The hood, peaked and drooping forward over the face.
	var hood := robe
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(1, -31), Vector2(0, -40), Vector2(5, -45), Vector2(11, -44), Vector2(17, -40.5),
		Vector2(18.5, -37), Vector2(15, -38), Vector2(15.5, -30), Vector2(10, -28),
	]), hood)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(10, -38), Vector2(15, -38.5), Vector2(15.5, -30), Vector2(11, -29)]), _c(Color("0f0b0a"), fl, a))
	# What's in the hood: a gaunt jaw, a slit of a mouth, one eye lit.
	ci.draw_colored_polygon(PackedVector2Array([Vector2(12, -36), Vector2(15.2, -35.5), Vector2(15.4, -31), Vector2(13, -29.5), Vector2(11.5, -31.5)]), flesh)
	ci.draw_line(Vector2(12.2, -32.2), Vector2(15.4, -32.6), _c(Color("1a1412"), fl, a), 0.8)
	for tx in [12.8, 13.8, 14.8]:
		ci.draw_line(Vector2(tx, -32.4), Vector2(tx, -31.7), bone, 0.5)
	var eye := GORGED_COLOR if gorged > 0 else Color("e8d9a0")
	ci.draw_circle(Vector2(13.6, -34.6), 0.9, _c(eye, fl, a))
	# The long arm, all bone and sinew, and its claw.
	var s := Vector2(4, -30)
	var e := s + Vector2(cos(th), sin(th)) * 24.0
	var mid := s + Vector2(cos(th - 0.5), sin(th - 0.5)) * 14.0
	ci.draw_line(s, mid, robe, 3.6)
	ci.draw_line(s.lerp(mid, 0.55), mid, flesh, 2.4)
	ci.draw_line(mid, e, flesh, 1.9)
	ci.draw_circle(mid, 1.5, bone)
	ci.draw_circle(e, 1.6, flesh)
	for k in [-0.55, -0.15, 0.25, 0.65]:
		var j := e + Vector2(cos(th + k), sin(th + k)) * 4.5
		var tip := j + Vector2(cos(th + k * 1.6 + 0.35), sin(th + k * 1.6 + 0.35)) * 4.0
		ci.draw_line(e, j, flesh, 1.3)
		ci.draw_line(j, tip, flesh, 1.0)
		ci.draw_line(tip, tip + (tip - j).normalized() * 1.6, _c(Color("2a211c"), fl, a), 0.9)
	if state == "strike":
		ci.draw_arc(s, 24.0, minf(-2.3, th), maxf(-2.3, th), 12, Color(0.79, 0.73, 0.63, 0.35 * a), 6.0)


func _paint_hound(ci: CanvasItem, fl: bool, a: float) -> void:
	var base := Color("5a2c24") if gorged > 0 else HOUND
	var body := _c(base, fl, a)
	var far := _c(base.darkened(0.35), fl, a)
	var dark := _c(base.darkened(0.5), fl, a)
	var flesh := _c(FLESH.darkened(0.15), fl, a)
	_crouch = minf(1.0, t / 0.2) * 4.0 if state == "windup" else 0.0
	_stretch = 1.18 if state == "strike" else 1.0
	var g := sin(run_t * 16.0) * 4.0
	# Legs: far pair first. Hind legs bend back at the hock, fore legs
	# forward at the wrist.
	for leg in [[Vector2(-7, -1), true, far], [Vector2(10, 1), false, far], [Vector2(-11, 1), true, body], [Vector2(6, -1), false, body]]:
		var at: Vector2 = leg[0]
		var hind: bool = leg[1]
		var col: Color = leg[2]
		var hip := _h(Vector2(at.x, -12))
		var paw := _h(Vector2(at.x + g * at.y, -_crouch))
		var joint := hip.lerp(paw, 0.55) + Vector2(-2.6 if hind else 1.4, 0)
		ci.draw_line(hip, joint, col, 3.0 if hind else 2.6)
		ci.draw_line(joint, paw, col, 1.8)
		ci.draw_colored_polygon(PackedVector2Array([paw + Vector2(-1.2, -1.2), paw + Vector2(2.6, -0.6), paw + Vector2(2.8, 0.3), paw + Vector2(-1.4, 0.3)]), col)
	# A gaunt body: deep chest, tucked belly, bony rump.
	var torso := PackedVector2Array()
	for p in [Vector2(-16, -16.5), Vector2(-12, -18.5), Vector2(-5, -18.5), Vector2(2, -20), Vector2(7, -21.5), Vector2(10, -19.5),
			Vector2(10, -11), Vector2(6, -8.5), Vector2(1, -10), Vector2(-4, -12.5), Vector2(-10, -12), Vector2(-15, -11.5), Vector2(-17, -13.5)]:
		torso.append(_h(p))
	ci.draw_colored_polygon(torso, body)
	# The flank in shadow, a mangy bare patch, the ribs.
	ci.draw_colored_polygon(PackedVector2Array([_h(Vector2(-15, -12)), _h(Vector2(-4, -12.5)), _h(Vector2(1, -10)), _h(Vector2(6, -8.5)), _h(Vector2(5, -11.5)), _h(Vector2(-12, -14))]), dark)
	var mange := _c(Color("5e3a33"), fl, a)
	ci.draw_colored_polygon(_ellipse(_h(Vector2(-8.5, -15.2)), 2.2, 1.1, 8), mange)
	ci.draw_colored_polygon(_ellipse(_h(Vector2(-6.6, -14.4)), 1.4, 0.9, 8), mange)
	var rib := _c(Color(base.darkened(0.6), 0.55), fl, a)
	for i in 3:
		var rx := 0.5 + i * 2.4
		ci.draw_polyline(PackedVector2Array([_h(Vector2(rx, -17.8)), _h(Vector2(rx + 1.2, -15)), _h(Vector2(rx + 0.6, -12.2))]), rib, 0.6)
	# Hackles: ragged fur over the shoulders and along the spine, rising
	# in the windup.
	var bristle := [1.0, 1.6, 1.2, 1.9, 1.4, 2.2, 1.8, 1.2]
	for i in bristle.size():
		var sx := -12.0 + i * 2.4
		var sy := -18.4 - (1.4 if i > 4 else 0.0)
		var up: float = bristle[i] * (1.6 if state == "windup" else 1.0)
		ci.draw_colored_polygon(PackedVector2Array([_h(Vector2(sx - 1.2, sy + 0.6)), _h(Vector2(sx + 0.9, sy - up)), _h(Vector2(sx + 1.2, sy + 0.6))]), body)
	# A ragged tail, low.
	var tail := PackedVector2Array([_h(Vector2(-16, -16)), _h(Vector2(-21, -17 + sin(_time * 6.0) * 2.0)), _h(Vector2(-25, -12 + sin(_time * 6.0 + 1.0) * 1.5))])
	ci.draw_polyline(tail, body, 2.2)
	ci.draw_line(tail[2], tail[2] + Vector2(-2, 1.5), body, 1.2)
	# The head: long and narrow, ear pinned back, jaw opening for the bite.
	var jaw := 0.0
	match state:
		"windup":
			jaw = minf(1.0, t / (def.windup * 0.7)) * 4.0
		"strike":
			jaw = 4.5
		"idle", "chase":
			jaw = 0.6 + sin(_time * 5.0) * 0.4
	ci.draw_colored_polygon(PackedVector2Array([_h(Vector2(7, -21)), _h(Vector2(12, -22)), _h(Vector2(15, -20.5)), _h(Vector2(21, -17.5)),
		_h(Vector2(25, -16.2)), _h(Vector2(24.6, -14.2)), _h(Vector2(14, -13.6)), _h(Vector2(9.5, -12))]), body)
	ci.draw_colored_polygon(PackedVector2Array([_h(Vector2(14, -14)), _h(Vector2(23, -13.6 + jaw * 0.3)), _h(Vector2(22.5, -11.6 + jaw)), _h(Vector2(13, -11.5))]), dark)
	for i in 5:
		var tx := 16.0 + i * 1.6
		ci.draw_colored_polygon(PackedVector2Array([_h(Vector2(tx, -14.2)), _h(Vector2(tx + 0.9, -14.2)), _h(Vector2(tx + 0.4, -12.8))]), flesh)
		ci.draw_colored_polygon(PackedVector2Array([_h(Vector2(tx, -12.6 + jaw * 0.85)), _h(Vector2(tx + 0.9, -12.6 + jaw * 0.85)), _h(Vector2(tx + 0.4, -13.8 + jaw * 0.85))]), flesh)
	ci.draw_colored_polygon(PackedVector2Array([_h(Vector2(11, -21.5)), _h(Vector2(8.5, -25.5)), _h(Vector2(13.5, -21.5))]), body)
	ci.draw_circle(_h(Vector2(17.5, -18.2)), 0.95, _c(GORGED_COLOR if gorged > 0 else Color("b8321f"), fl, a))
	if jaw > 2.0:
		ci.draw_line(_h(Vector2(21, -11.6 + jaw)), _h(Vector2(21.2, -8.5 + jaw)), _c(Color(0.85, 0.82, 0.75, 0.6), fl, a), 0.6)


# The hound crouches before a lunge and stretches out during it.
var _crouch := 0.0
var _stretch := 1.0


func _h(v: Vector2) -> Vector2:
	return Vector2(v.x * _stretch, v.y + _crouch)


static func _ellipse(c: Vector2, rx: float, ry: float, n := 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var ang := TAU * i / n
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	return pts
