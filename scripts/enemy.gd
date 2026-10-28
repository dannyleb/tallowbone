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


func _c(color: Color, white: bool, a: float) -> Color:
	var c := Color.WHITE if white else color
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
	var stride := sin(run_t * 9.0) * 2.0
	ci.draw_rect(Rect2(-6 + stride, -8, 4, 8), _c(ROBE_DARK, fl, a))
	ci.draw_rect(Rect2(2 - stride, -8, 4, 8), _c(ROBE_DARK, fl, a))
	# Hunched robe, ragged hem.
	var hump := PackedVector2Array()
	for i in 9:
		var k := i / 8.0
		hump.append(Vector2(-10, -26).lerp(Vector2(-6, -42), k).lerp(Vector2(-6, -42).lerp(Vector2(6, -36), k), k))
	hump.append_array(PackedVector2Array([Vector2(10, -6), Vector2(7, -2), Vector2(4, -6), Vector2(0, -1), Vector2(-4, -6), Vector2(-8, -1), Vector2(-11, -6)]))
	ci.draw_colored_polygon(hump, robe)
	# Hooded head, thrust forward.
	ci.draw_circle(Vector2(8, -36), 7.0, robe)
	ci.draw_rect(Rect2(10, -37, 5, 6), _c(FLESH, fl, a))
	ci.draw_rect(Rect2(12, -36, 2, 1.5), _c(GORGED_COLOR if gorged > 0 else Color("1a1412"), fl, a))
	# The long arm and its claw.
	var th := _claw_angle()
	var s := Vector2(4, -30)
	var e := s + Vector2(cos(th), sin(th)) * 24.0
	var mid := s + Vector2(cos(th - 0.5), sin(th - 0.5)) * 14.0
	ci.draw_polyline(PackedVector2Array([s, mid, e]), _c(FLESH, fl, a), 2.5)
	for k in [-0.5, 0.0, 0.5]:
		ci.draw_line(e, e + Vector2(cos(th + k), sin(th + k)) * 7.0, _c(FLESH, fl, a), 1.5)
	if state == "strike":
		ci.draw_arc(s, 24.0, minf(-2.3, th), maxf(-2.3, th), 12, Color(0.79, 0.73, 0.63, 0.35 * a), 6.0)


func _paint_hound(ci: CanvasItem, fl: bool, a: float) -> void:
	var body := _c(Color("5a2c24") if gorged > 0 else HOUND, fl, a)
	_crouch = minf(1.0, t / 0.2) * 4.0 if state == "windup" else 0.0
	_stretch = 1.18 if state == "strike" else 1.0
	var g := sin(run_t * 16.0) * 4.0
	for leg in [Vector2(-11, 1), Vector2(-7, -1), Vector2(6, -1), Vector2(10, 1)]:
		ci.draw_line(_h(Vector2(leg.x, -10)), _h(Vector2(leg.x + g * leg.y, -_crouch)), body, 3.0)
	ci.draw_colored_polygon(_ellipse(_h(Vector2(-1, -14)), 15.0 * _stretch, 6.5), body)
	for i in 3:
		ci.draw_line(_h(Vector2(-4 + i * 4, -19)), _h(Vector2(-5 + i * 4, -10)), Color(0, 0, 0, 0.35 * a), 1.0)
	var tail := PackedVector2Array([_h(Vector2(-15, -15)), _h(Vector2(-21, -19 + sin(_time * 6.0) * 3.0)), _h(Vector2(-24, -12))])
	ci.draw_polyline(tail, body, 2.0)
	ci.draw_colored_polygon(_ellipse(_h(Vector2(13, -15)), 7.0, 5.0), body)
	ci.draw_colored_polygon(PackedVector2Array([_h(Vector2(9, -19)), _h(Vector2(11, -25)), _h(Vector2(13, -19))]), body)
	ci.draw_rect(Rect2(_h(Vector2(12, -12)), Vector2(8, 2)), body)
	for i in 3:
		ci.draw_rect(Rect2(_h(Vector2(14 + i * 2, -13)), Vector2(1, 2)), _c(FLESH, fl, a))
	ci.draw_rect(Rect2(_h(Vector2(14, -17)), Vector2(2, 1.5)), _c(GORGED_COLOR if gorged > 0 else Color("8a2a1e"), fl, a))


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
