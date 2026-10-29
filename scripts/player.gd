## The Lamplighter.
##
## One state at a time ("move" is free movement; the rest are committed
## actions with their own timers), with short input buffers so a press made
## a beat early still counts. The World calls step() once per physics tick.
##
## The drawing is a greybox stand-in for the sprite, posed from the real
## attack timings so what you see matches the hitboxes.
extends CharacterBody2D

const T = preload("res://scripts/tuning.gd")
const Combat = preload("res://scripts/combat.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Glow = preload("res://scripts/glow.gd")
const Figure = preload("res://scripts/figure.gd")
const Art = preload("res://scripts/art.gd")

const W := 16.0
const H := 42.0
## How long (s) each press is remembered.
const BUFFER := {"jump": 0.12, "attack": 0.2, "transform": 0.2, "shoot": 0.15, "dash": 0.12, "heal": 0.12, "interact": 0.12}

const COAT := Color("4b4658")
const COAT_DARK := Color("2a2733")
const SCARF := Color("9a2a2c")
const SKIN := Color("d9cdb8")
const HAT := Color("2a2730")
const POLE := Color("7a5a40")
const IRON := Color("46464f")
const LAMP := Color("ffcf7a")
const TROUSERS := Color("26232c")
const LEATHER := Color("1d1a1e")
const BRASS := Color("a8854a")
const LINING := Color("421c1f")
const MANTLE := Color("3a3644")
const GLOVE := Color("19171b")
const HAIR := Color("1b1716")
const VIAL := Color("c42b2f")
const GUNMETAL := Color("34312f")

## The drawing's canvas in world px, and where the feet are on it.
const FIG_SIZE := Vector2(160, 120)
const FIG_ORIGIN := Vector2(80, 108)
## Painted animations (docs/ART.md) and their frame counts. Each comes in
## both forms, "hook_idle" and "lantern_idle"; the Lantern's combo has two
## hits. <form>_transform is turning into that form; <form>_trick starts in
## that form and lands in the other.
const ART_ANIMS := {
	"idle": 4, "run": 6, "jump": 1, "fall": 1, "wall": 1, "dash": 2,
	"combo1": 4, "combo2": 4, "combo3": 4, "trick": 4, "transform": 3,
	"shoot": 2, "heal": 2, "blood": 2, "hurt": 1, "visceral": 3, "dead": 3,
}

var world
var hp := 100.0
var max_hp := 100.0
var rally := 0.0
var rally_hold := 0.0
var vials := 5
var max_vials := 5
var bullets := 12
var max_bullets := 12
var arm := "pole"
var form := "hook"
var state := "move"
var t := 0.0
var facing := 1.0
var attack := {}
var kind := ""
var combo := 0
var hit_set: Array = []
var lunged := false
var done := false
var target = null
var buf := {}
var coyote := 0.0
var iframes := 0.0
var dash_cd := 0.0
var dash_dir := 1.0
var air_dash := true
var drop_t := 0.0
var jumping := false
var safe := Vector2.ZERO
var in_hazard := false
var run_t := 0.0
## What you've found (Tuning.ABILITIES); all start locked.
var abilities := {}
## How long strike has been held (negative once it's turned the Pole, until
## you let go).
var attack_hold := 0.0
## The paint-over templates set this to pose the figure in the air or on the
## ground; null asks the physics.
var air_override = null
var sliding := false
var wall_dir := 0.0
var wall_grace := 0.0
var wall_lock := 0.0
var _time := 0.0
var _lantern := Vector2.ZERO
var _light: PointLight2D
var _body_light: PointLight2D
var _fig: Sprite2D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 3
	floor_snap_length = 6.0
	for k in BUFFER:
		buf[k] = 0.0
	for a in T.ABILITIES:
		abilities[a] = false
	max_hp = T.PLAYER.max_hp
	max_vials = T.PLAYER.vials
	max_bullets = T.PLAYER.bullets
	refill()
	_light = Glow.light(Color(1.0, 0.8, 0.55), 70.0, 1.2, 30.0)
	add_child(_light)
	_body_light = Glow.light(Color(0.82, 0.84, 1.0), 72.0, 0.95, 40.0)
	_body_light.position = Vector2(0, -H / 2.0)
	add_child(_body_light)
	# Room for the pole overhead, the lantern flung out, quickstep ghosts
	# behind, and lying down when dead.
	_fig = Figure.new()
	add_child(_fig)
	_fig.setup(FIG_SIZE, FIG_ORIGIN, _paint)


func has(ability: String) -> bool:
	return abilities.get(ability, false)


func unlock_all() -> void:
	for a in T.ABILITIES:
		abilities[a] = true


func refill() -> void:
	hp = max_hp
	rally = 0.0
	vials = max_vials
	bullets = max_bullets


func form_data() -> Dictionary:
	return T.ARMS[arm].forms[form]


func body_rect() -> Rect2:
	return Rect2(position.x - W / 2.0, position.y - H, W, H)


func attack_box(a: Dictionary) -> Rect2:
	var r := body_rect()
	var front := r.end.x if facing > 0 else r.position.x
	var x: float = front if facing > 0 else front - a.reach
	return Rect2(x, position.y + a.top, a.reach, a.bottom - a.top)


## Presses are buffered even during hit-stop, so nothing pressed in a
## freeze-frame is lost.
func buffer_input(pressed: Dictionary) -> void:
	for k in BUFFER:
		if pressed.get(k, false):
			buf[k] = BUFFER[k]


func to_move() -> void:
	state = "move"
	t = 0.0
	attack = {}


func step(input: Dictionary, delta: float) -> void:
	var held: Dictionary = input.held
	_time += delta
	t += delta
	for k in buf:
		buf[k] = maxf(0.0, buf[k] - delta)
	coyote = maxf(0.0, coyote - delta)
	iframes = maxf(0.0, iframes - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	drop_t = maxf(0.0, drop_t - delta)
	wall_grace = maxf(0.0, wall_grace - delta)
	wall_lock = maxf(0.0, wall_lock - delta)
	if held.attack:
		attack_hold += delta
	else:
		attack_hold = 0.0
	if rally_hold > 0.0:
		rally_hold -= delta
	else:
		rally = maxf(0.0, rally - T.RALLY.decay * delta)

	var dir_x := (1.0 if held.move_right else 0.0) - (1.0 if held.move_left else 0.0)
	var control := 0.0
	var gravity := true

	match state:
		"move":
			# Just after a wall jump you're carried away from the wall.
			control = 0.0 if wall_lock > 0.0 else 1.0
			_free_actions(held, dir_x)
		"attack":
			control = 0.0 if is_on_floor() else 0.35
			_tick_attack(held, dir_x)
		"transform":
			control = 0.5
			if t >= T.TRANSFORM_TIME:
				to_move()
		"dash":
			gravity = false
			velocity = Vector2(dash_dir * T.DASH.speed, 0.0)
			if t >= T.DASH.time:
				to_move()
				velocity.x = dash_dir * T.PLAYER.run
		"shoot":
			control = 0.0 if is_on_floor() else 0.5
			if not done and t >= T.GUN.startup:
				done = true
				_fire()
			# Once the shot is off: quickstep out, or go straight into the
			# Visceral on whatever it just staggered.
			var finish = _visceral_target() if done and buf.attack > 0.0 else null
			if finish:
				buf.attack = 0.0
				_start_visceral(finish)
			elif done and buf.dash > 0.0 and _can_dash():
				_start_dash(dir_x)
			elif t >= T.GUN.startup + T.GUN.recovery:
				to_move()
		"heal":
			control = 0.3
			if not done and t >= T.PLAYER.heal_at:
				done = true
				vials -= 1
				hp = minf(max_hp, hp + T.PLAYER.vial_heal)
				rally = minf(rally, max_hp - hp)
				world.fx.burst(position + Vector2(0, -22), {"count": 14, "color": Color("f0bd62"), "spread": 70.0, "up": 80.0, "gravity": -80.0, "glow": true})
				Sfx.play("heal")
			if t >= T.PLAYER.heal_time:
				to_move()
		"blood":
			# Out of bullets, holding the pistol cuts you for more; let go
			# early to back out.
			if not held.shoot:
				to_move()
			elif t >= T.BLOOD.time:
				hp -= T.BLOOD.cost
				rally = minf(rally + T.BLOOD.cost, max_hp - hp)
				rally_hold = T.RALLY.hold
				bullets = mini(max_bullets, bullets + T.BLOOD.bullets)
				world.fx.burst(position + Vector2(0, -24), {"count": 12, "color": Color("8e1b1e"), "spread": 90.0})
				Sfx.play("blood")
				to_move()
		"hurt":
			if t >= T.PLAYER.hurt_time:
				to_move()
		"visceral":
			_tick_visceral()
		# "rest" (at a lamp) and "dead" are run by the World.

	var on_floor := is_on_floor()
	if control > 0.0:
		var accel: float = (T.PLAYER.accel_ground if on_floor else T.PLAYER.accel_air) * control
		var stopping := dir_x == 0.0 and on_floor
		velocity.x = move_toward(velocity.x, dir_x * T.PLAYER.run, (T.PLAYER.friction if stopping else accel) * delta)
		if dir_x != 0.0 and state == "move":
			facing = dir_x
	elif on_floor and state != "dash":
		velocity.x = move_toward(velocity.x, 0.0, T.PLAYER.friction * 0.5 * delta)

	# Let go of jump early for a short hop.
	if jumping and not held.jump and velocity.y < 0.0:
		velocity.y *= T.PLAYER.jump_cut
		jumping = false
	if gravity:
		velocity.y = minf(velocity.y + T.GRAVITY * delta, T.MAX_FALL)
	if sliding and velocity.y > T.WALL.slide:
		velocity.y = T.WALL.slide

	# Down + jump on a walkway drops through it for a moment.
	collision_mask = 1 if drop_t > 0.0 else 3
	move_and_slide()
	_ledge_assist(dir_x)
	_wall_slide(dir_x)
	if is_on_floor():
		coyote = T.PLAYER.coyote
		air_dash = true
		jumping = false
		if absf(velocity.x) > 20.0:
			run_t += delta
		if _firm_footing():
			safe = position
	_check_hazard()
	_update_look()


func _free_actions(held: Dictionary, dir_x: float) -> void:
	var f := form_data()
	if buf.dash > 0.0 and _can_dash():
		_start_dash(dir_x)
		return
	if buf.attack > 0.0:
		buf.attack = 0.0
		var e = _visceral_target() if has("pistol") else null
		if e:
			_start_visceral(e)
			return
		combo = 0
		_start_attack(f.combo[0], "combo")
		return
	if buf.transform > 0.0 and has("lantern"):
		buf.transform = 0.0
		form = f.trick.to
		state = "transform"
		t = 0.0
		Sfx.play("swing")
		return
	if buf.shoot > 0.0 and has("pistol"):
		buf.shoot = 0.0
		if bullets <= 0:
			# Empty: keep holding to spend blood on bullets.
			if held.shoot and hp > T.BLOOD.cost:
				state = "blood"
				t = 0.0
			else:
				Sfx.play("click")
			return
		state = "shoot"
		t = 0.0
		done = false
		return
	if buf.heal > 0.0:
		buf.heal = 0.0
		if vials <= 0 or hp >= max_hp:
			Sfx.play("deny")
			return
		state = "heal"
		t = 0.0
		done = false
		return
	if buf.jump > 0.0 and (is_on_floor() or coyote > 0.0):
		buf.jump = 0.0
		if held.move_down and _on_walkway():
			drop_t = 0.25
			return
		velocity.y = -T.PLAYER.jump
		jumping = true
		coyote = 0.0
		Sfx.play("jump")
	elif buf.jump > 0.0 and wall_grace > 0.0:
		# Climbing Irons: kick off the wall, up and away.
		buf.jump = 0.0
		velocity = Vector2(-wall_dir * T.WALL.push, -T.WALL.jump)
		facing = -wall_dir
		jumping = true
		sliding = false
		wall_grace = 0.0
		wall_lock = T.WALL.lock
		Sfx.play("jump")


func _start_attack(a: Dictionary, k: String) -> void:
	state = "attack"
	t = 0.0
	attack = a
	kind = k
	hit_set = []
	lunged = false


func _tick_attack(held: Dictionary, dir_x: float) -> void:
	var a := attack
	var on: float = a.startup
	var off: float = on + a.active
	var end: float = off + a.recovery
	if t >= on and not lunged:
		lunged = true
		# A trick attack lands in the other form.
		if kind == "trick":
			form = a.to
		if is_on_floor():
			velocity.x = facing * a.lunge
		Sfx.play("heavy" if a.damage >= 22.0 else "swing")
	if t >= on and t < off:
		_melee_hits(a)
	if t < off:
		return

	# Recovery: chain into the next swing, turn it into a trick attack, or
	# quickstep out.
	if buf.dash > 0.0 and _can_dash():
		_start_dash(dir_x)
		return
	# Holding strike (or the transform key) turns the Pole: a trick attack.
	var turn: bool = buf.transform > 0.0 or (held.attack and attack_hold >= T.TRICK_HOLD)
	if turn and kind == "combo" and has("lantern"):
		buf.transform = 0.0
		attack_hold = -1000.0
		_start_attack(form_data().trick, "trick")
		return
	if buf.attack > 0.0 and t >= off + a.recovery * 0.35:
		buf.attack = 0.0
		var e = _visceral_target() if has("pistol") else null
		if e:
			_start_visceral(e)
			return
		if dir_x != 0.0:
			facing = dir_x
		var chain: Array = form_data().combo
		combo = 0 if kind == "trick" else (combo + 1) % chain.size()
		_start_attack(chain[combo], "combo")
		return
	if t >= end:
		to_move()


func _melee_hits(a: Dictionary) -> void:
	var box := attack_box(a)
	if form_data().burns:
		var burnt: Array[Vector2i] = world.level.burn(box)
		for cell in burnt:
			world.fx.burst((Vector2(cell) + Vector2(0.5, 0.5)) * T.TILE, {"count": 14, "color": Color("ffb35a"), "spread": 120.0, "up": 100.0, "gravity": -150.0, "life": 0.9, "glow": true})
		if not burnt.is_empty():
			Sfx.play("burn")
	for e in world.enemies:
		if not e.alive or hit_set.has(e) or not box.intersects(e.body_rect()):
			continue
		hit_set.append(e)
		var dmg: float = roundf(a.damage * (1.0 + 0.08 * world.stats.strength))
		Combat.damage_enemy(world, e, dmg, facing)
		# Rally: hitting back wins back what you just lost.
		var back := minf(rally, dmg * T.RALLY.regain)
		hp += back
		rally -= back
		world.hitstop = maxf(world.hitstop, T.HITSTOP.hit)
		world.fx.add_shake(2.0)
		Sfx.play("hit")


func _fire() -> void:
	bullets -= 1
	Sfx.play("shot")
	var r := body_rect()
	var gx := r.end.x + 6.0 if facing > 0 else r.position.x - 6.0
	var gy: float = position.y - T.GUN.y
	var reach: float = world.level.ray_length(Vector2(gx, gy), facing, T.GUN.range)
	var hit = null
	for e in world.enemies:
		if not e.alive:
			continue
		var er: Rect2 = e.body_rect()
		if gy < er.position.y - 10.0 or gy > er.end.y + 10.0:
			continue
		var d := er.position.x - gx if facing > 0 else gx - er.end.x
		if d > -er.size.x and d < reach:
			reach = maxf(0.0, d)
			hit = e
	world.shot = {"from": Vector2(gx, gy), "to": Vector2(gx + facing * reach, gy), "t": 0.07}
	if hit == null:
		return
	if Combat.parryable(hit):
		Combat.stagger_enemy(world, hit)
	else:
		Combat.damage_enemy(world, hit, roundf(T.GUN.damage * (1.0 + 0.15 * world.stats.steady)), facing)


## A staggered enemy close enough on either side to finish.
func _visceral_target():
	for e in world.enemies:
		if not e.alive or e.state != "stagger" or absf(e.position.y - position.y) > 40.0:
			continue
		var gap: float = absf(e.position.x - position.x) - (e.def.w + W) / 2.0
		if gap < T.VISCERAL.reach:
			return e
	return null


func _start_visceral(e) -> void:
	state = "visceral"
	t = 0.0
	done = false
	target = e
	var d := signf(e.position.x - position.x)
	if d != 0.0:
		facing = d
	velocity.x = 0.0
	e.state = "held"
	e.t = 0.0


func _tick_visceral() -> void:
	if not done and t >= T.VISCERAL.at:
		done = true
		var dmg: float = roundf(T.VISCERAL.damage * (1.0 + 0.08 * world.stats.strength))
		Combat.damage_enemy(world, target, dmg, facing, true)
		# A Visceral wins back all of your rally at once.
		hp = minf(max_hp, hp + rally)
		rally = 0.0
		world.hitstop = maxf(world.hitstop, T.HITSTOP.visceral)
		world.fx.add_shake(9.0)
		Sfx.play("visceral")
	if t >= T.VISCERAL.time:
		to_move()


func _can_dash() -> bool:
	return has("quickstep") and dash_cd <= 0.0 and (is_on_floor() or air_dash)


## Pushing into a ledge with your feet just below its top pops you up onto
## it, so a jump that barely clips the edge still lands.
func _ledge_assist(dir_x: float) -> void:
	if dir_x == 0.0 or is_on_floor() or velocity.y < -80.0 or not is_on_wall() or state != "move":
		return
	var level = world.level
	var front := position.x + signf(dir_x) * (W / 2.0 + 2.0)
	var top := floorf((position.y - 1.0) / T.TILE) * T.TILE
	if position.y - top > T.LEDGE_ASSIST:
		return
	if not level.solid_at(Vector2(front, top + 1.0)) or level.solid_at(Vector2(front, top - 1.0)):
		return
	if level.solid_at(Vector2(front, top - H + 2.0)) or level.solid_at(Vector2(position.x, top - H + 2.0)):
		return
	position = Vector2(position.x + signf(dir_x) * 3.0, top - 0.5)
	velocity.y = 0.0


## Climbing Irons: pressing into a wall in the air slides you down it
## slowly, and jump kicks off (see _free_actions).
func _wall_slide(dir_x: float) -> void:
	sliding = false
	if not has("irons") or state != "move" or is_on_floor() or not is_on_wall() or dir_x == 0.0:
		return
	var n := get_wall_normal().x
	if n == 0.0 or signf(dir_x) != -signf(n) or velocity.y < 0.0:
		return
	sliding = true
	wall_dir = -signf(n)
	wall_grace = T.WALL.grace
	air_dash = true


func _start_dash(dir_x: float) -> void:
	state = "dash"
	t = 0.0
	dash_dir = dir_x if dir_x != 0.0 else facing
	facing = dash_dir
	dash_cd = T.DASH.cooldown
	buf.dash = 0.0
	if not is_on_floor():
		air_dash = false
	jumping = false
	Sfx.play("dash")


## Both feet on something, so it's a fair place to be put back after a fall
## into the canal.
func _firm_footing() -> bool:
	var y := position.y + 1.0
	return world.level.standable_at(Vector2(position.x - W / 2.0 - 4.0, y)) \
		and world.level.standable_at(Vector2(position.x + W / 2.0 + 4.0, y))


func _on_walkway() -> bool:
	var y := position.y + 1.0
	var any := false
	for x in [position.x - W / 2.0, position.x + W / 2.0 - 0.01]:
		var k: String = world.level.kind_at(world.level.cell_at(Vector2(x, y)))
		if k == "stone" or k == "veil":
			return false
		if k == "walkway":
			any = true
	return any


func _check_hazard() -> void:
	var y := position.y - 6.0
	in_hazard = world.level.hazard_at(Vector2(position.x - W / 2.0, y)) \
		or world.level.hazard_at(Vector2(position.x + W / 2.0 - 0.01, y))
	if not in_hazard or state == "dead":
		return
	world.fx.burst(Vector2(position.x, floorf(y / T.TILE) * T.TILE), {"count": 20, "color": Color("4b8c7c"), "spread": 140.0, "up": 160.0})
	Sfx.play("splash")
	hp -= T.HAZARD_DAMAGE
	rally = 0.0
	if hp <= 0.0:
		Combat.kill_player(world)
		return
	position = safe
	velocity = Vector2.ZERO
	iframes = 1.0
	in_hazard = false
	to_move()


# --- Look: pose, lights, drawing ------------------------------------------

func _update_look() -> void:
	if state == "dead":
		modulate.a = maxf(0.0, 1.0 - maxf(0.0, t - 1.2) / 1.2)
	elif iframes > 0.0 and state != "dash" and int(_time * 20.0) % 2 == 1:
		modulate.a = 0.45
	else:
		modulate.a = 1.0
	var f := form_data()
	var l := _lantern_point()
	_lantern = Vector2(l.x * facing, l.y + 5.0)
	_light.position = _lantern if f.burns else _wick()
	Glow.set_radius(_light, f.light)
	_light.energy = (1.5 if f.burns else 1.1) * (1.0 + sin(_time * 11.0) * sin(_time * 6.7) * 0.06)
	_light.enabled = state != "dead" or t < 1.4
	_body_light.enabled = _light.enabled
	_fig.redraw()


static func _lerp(a: float, b: float, x: float) -> float:
	return lerpf(a, b, clampf(x, 0.0, 1.0))


static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


## The pole's angle in radians (0 points forward, negative is up).
func _pole_angle() -> float:
	var rest := -1.25 + sin(_time * 2.0) * 0.04
	match state:
		"attack":
			var a := attack
			var sweep := _sweep()
			if t < a.startup:
				return _lerp(rest, sweep.x, t / a.startup)
			if t < a.startup + a.active:
				return lerpf(sweep.x, sweep.y, _ease((t - a.startup) / a.active))
			return _lerp(sweep.y, rest, (t - a.startup - a.active) / a.recovery)
		"transform":
			return rest + (t / T.TRANSFORM_TIME) * TAU
		"dash":
			return -0.5
		"visceral":
			return _lerp(-0.4, 0.1, t / 0.22)
		"hurt":
			return -2.0
		"shoot":
			return -1.9
		"dead":
			return 1.3
	return -1.0 if absf(velocity.x) > 40.0 else rest


## Start and end angle of the current swing; every other combo hit swings up.
func _sweep() -> Vector2:
	return Vector2(0.9, -2.4) if kind == "combo" and combo % 2 == 1 else Vector2(-2.6, 0.7)


func _lean() -> float:
	return 3.0 if state == "dash" or state == "visceral" else 0.0


func _shoulder() -> Vector2:
	return Vector2(2.0 + _lean(), -34.0)


func _hand() -> Vector2:
	var th := _pole_angle()
	return _shoulder() + Vector2(cos(th), sin(th)) * 9.0


## The swing's trail, in world space, for the overlay to draw unshaded:
## { center, radius, from, to, color, width }, or empty between swings.
func swoosh() -> Dictionary:
	if state != "attack" or t < attack.startup or t > attack.startup + attack.active + 0.05:
		return {}
	var sweep := _sweep()
	var to := lerpf(sweep.x, sweep.y, _ease((t - attack.startup) / attack.active))
	var fade: float = 1.0 - (t - attack.startup) / (attack.active + 0.05)
	var burns: bool = form_data().burns
	var a := minf(sweep.x, to)
	var b := maxf(sweep.x, to)
	if facing < 0:
		# Mirror the arc: an angle θ facing right is π - θ facing left.
		var mirrored := [PI - b, PI - a]
		a = mirrored[0]
		b = mirrored[1]
	var s := _shoulder()
	return {
		"center": position + Vector2(s.x * facing, s.y),
		"radius": attack.reach * 0.7 + 12.0,
		"from": a, "to": b,
		"color": Color(1.0, 0.75, 0.43, 0.5 * fade) if burns else Color(0.91, 0.87, 0.81, 0.4 * fade),
		"width": 9.0 if burns else 6.0,
	}


## Where the lantern or the hook's wick is, in world space, for the glow.
func flame_at() -> Vector2:
	return position + (_lantern if form_data().burns else _wick())


## Where the Lantern hangs, in the node's unmirrored space: from the pole
## tip, flung outward mid-swing. (The light follows it, painted or not.)
func _lantern_point() -> Vector2:
	var th := _pole_angle()
	var dir := Vector2(cos(th), sin(th))
	var tip := _hand() + dir * 30.0
	var flung: bool = state == "attack" and t > attack.startup * 0.5
	var swing := sin(_time * 3.0) * 0.25 - clampf(velocity.x * facing / 300.0, -1.0, 1.0) * 0.5
	return tip + dir * 18.0 if flung else tip + Vector2(sin(swing), cos(swing)) * 14.0


## In the air, as far as the drawing is concerned.
func _airborne() -> bool:
	if air_override != null:
		return air_override
	return not is_on_floor()


## Every painted animation the Lamplighter can use: "hook_idle" -> 4, ...
static func art_anims() -> Dictionary:
	var out := {}
	var forms: Dictionary = T.ARMS.pole.forms
	for f in forms:
		var hits: int = forms[f].combo.size()
		for a in ART_ANIMS:
			if a.begins_with("combo") and int(a.right(1)) > hits:
				continue
			out["%s_%s" % [f, a]] = ART_ANIMS[a]
	return out


## The painted frame for what you're doing now: [animation, frame].
func art_frame() -> Array:
	var name := "idle"
	var phase := 0.0
	match state:
		"attack":
			var a := attack
			var f := 3
			if t < a.startup:
				f = 0
			elif t < a.startup + a.active * 0.5:
				f = 1
			elif t < a.startup + a.active:
				f = 2
			if kind == "trick":
				return ["%s_trick" % ("hook" if a.to == "lantern" else "lantern"), f]
			return ["%s_combo%d" % [form, combo + 1], f]
		"shoot":
			return [form + "_shoot", 1 if done else 0]
		"heal":
			return [form + "_heal", 1 if done else 0]
		"transform":
			name = "transform"
			phase = t / T.TRANSFORM_TIME
		"dash":
			name = "dash"
			phase = t / T.DASH.time
		"blood":
			name = "blood"
			phase = t / T.BLOOD.time
		"hurt":
			name = "hurt"
		"visceral":
			name = "visceral"
			phase = t / T.VISCERAL.time
		"dead":
			name = "dead"
			phase = t / 1.2
		_:
			if sliding:
				name = "wall"
			elif _airborne():
				name = "jump" if velocity.y < 0.0 else "fall"
			elif absf(velocity.x) > 20.0:
				name = "run"
				phase = fposmod(run_t * 13.0 / TAU, 1.0)
			else:
				phase = fposmod(_time / 1.6, 1.0)
	var n: int = ART_ANIMS[name]
	return ["%s_%s" % [form, name], clampi(int(phase * n), 0, n - 1)]


## Poses the Lamplighter as frame `frame` of painted animation `anim`
## ("hook_combo2"), at the middle of the moment it covers, facing right. For
## the paint-over templates (tests/art_templates.gd).
func art_pose(anim: String, frame: int) -> void:
	var parts := anim.split("_", true, 1)
	form = parts[0]
	var name := parts[1]
	var n: int = ART_ANIMS[name]
	var mid := (frame + 0.5) / n
	state = "move"
	t = 0.0
	_time = 0.0
	run_t = 0.0
	velocity = Vector2.ZERO
	sliding = false
	done = false
	air_override = false
	facing = 1.0
	dash_dir = 1.0
	match name:
		"idle":
			_time = mid * 1.6
		"run":
			velocity.x = T.PLAYER.run
			run_t = mid * TAU / 13.0
		"jump":
			air_override = true
			velocity.y = -300.0
		"fall":
			air_override = true
			velocity.y = 300.0
		"wall":
			air_override = true
			sliding = true
		"dash":
			state = "dash"
			t = mid * T.DASH.time
		"transform":
			state = "transform"
			t = mid * T.TRANSFORM_TIME
		"shoot":
			state = "shoot"
			done = frame == 1
			t = T.GUN.startup * (0.5 if frame == 0 else 1.5)
		"heal":
			state = "heal"
			done = frame == 1
			t = T.PLAYER.heal_at * (0.5 if frame == 0 else 1.2)
		"blood":
			state = "blood"
			t = mid * T.BLOOD.time
		"hurt":
			state = "hurt"
		"visceral":
			state = "visceral"
			t = mid * T.VISCERAL.time
		"dead":
			state = "dead"
			t = mid * 1.2
		_:
			state = "attack"
			var f: Dictionary = T.ARMS[arm].forms[form]
			if name == "trick":
				kind = "trick"
				combo = 0
				attack = f.trick
			else:
				kind = "combo"
				combo = int(name.right(1)) - 1
				attack = f.combo[combo]
			var a := attack
			var at := [a.startup * 0.5, a.startup + a.active * 0.25, a.startup + a.active * 0.75, a.startup + a.active + a.recovery * 0.5]
			t = at[frame]
			# A trick lands in the other form as it strikes.
			if name == "trick" and frame > 0:
				form = a.to


## The hook's wick, in the node's (unmirrored) space.
func _wick() -> Vector2:
	var th := _pole_angle()
	var tip := _hand() + Vector2(cos(th), sin(th)) * 47.0
	return Vector2(tip.x * facing, tip.y)


## Draws the Lamplighter (and quickstep afterimages) onto ci, the Figure's
## painter, with the feet at 0, 0.
func _paint(ci: CanvasItem) -> void:
	var pose := art_frame()
	if state == "dash":
		for i in range(3, 0, -1):
			_paint_figure(ci, -dash_dir * i * 11.0, 0.12 * (4 - i), true, pose)
	_paint_figure(ci, 0.0, 1.0, false, pose)
	ci.draw_set_transform(Vector2.ZERO)


func _paint_figure(ci: CanvasItem, offset: float, alpha: float, ghost: bool, pose: Array) -> void:
	var painted: bool = Art.frames("lamplighter").has(pose[0])
	# A painted fall is in the frames; the greybox tips over instead.
	var rot := minf(1.0, t * 2.0) * 1.35 if state == "dead" and not painted else 0.0
	ci.draw_set_transform(Vector2(offset, 0), rot * facing, Vector2(facing, 1))
	if painted:
		Art.draw(ci, "lamplighter", pose, FIG_SIZE, FIG_ORIGIN, Color(1, 1, 1, alpha))
		return
	var c := func(col: Color) -> Color: return Color(col, col.a * alpha)
	var air := _airborne() and state != "dead"
	var moving := not _airborne() and absf(velocity.x) > 20.0
	var cyc := sin(run_t * 13.0) if moving else 0.0
	var bob := absf(cos(run_t * 13.0)) * 1.2 if moving else 0.0
	var sway := clampf(-velocity.x / 300.0, -1.0, 1.0) * 6.0
	var lean := _lean()
	var top := -bob

	# The far arm, hanging behind the body (unless it's busy in front).
	if not ghost and not (state in ["shoot", "heal", "blood"]):
		var back_s := Vector2(-3.0 + lean, -35.0 + top)
		var back_h := back_s + Vector2(-2.0 - cyc * 3.0 + sway * 0.25, 11.5)
		_limb(ci, back_s, back_h, -1.0, c.call(COAT_DARK.darkened(0.25)), 3.4, 3.0)
		ci.draw_circle(back_h + Vector2(0, 1), 1.6, c.call(GLOVE))

	# Legs: the far one darker; thigh, shin and boot, the knee bending
	# forward. In the air, tucked.
	for side in [-1.0, 1.0]:
		var shade := 0.3 if side < 0.0 else 0.0
		var hip := Vector2(side * 2.0 + lean * 0.3, -14.0 + top)
		var foot: Vector2
		if air:
			foot = hip + (Vector2(5.0, 8.0) if side > 0.0 else Vector2(-4.0, 10.0))
		else:
			foot = Vector2(side * 1.5 + cyc * 5.0 * side, 0.0)
		var lift := maxf(0.0, -cyc * side) * 2.5 if moving else 0.0
		foot.y -= lift
		var knee := (hip + foot) * 0.5 + Vector2(2.2 + absf(cyc) * 1.5, -0.5)
		if air:
			knee = (hip + foot) * 0.5 + Vector2(3.5 * side + 1.0, -1.5)
		ci.draw_line(hip, knee, c.call(TROUSERS.darkened(shade)), 4.2)
		ci.draw_line(knee, foot + Vector2(0, -6), c.call(TROUSERS.darkened(shade)), 3.6)
		# The boot: shaft, heel, a pointed toe.
		var boot: Color = c.call(LEATHER.darkened(shade))
		ci.draw_colored_polygon(PackedVector2Array([
			foot + Vector2(-2.2, -7.5), foot + Vector2(2.0, -7.5), foot + Vector2(2.4, -2.2),
			foot + Vector2(5.4, -1.4), foot + Vector2(5.8, 0.0), foot + Vector2(-2.6, 0.0),
		]), boot)
		ci.draw_line(foot + Vector2(-2.4, -7.6), foot + Vector2(2.2, -7.6), c.call(LEATHER.lightened(0.15)), 1.0)

	# The greatcoat: tails split and trailing, flaring with the run.
	var flare := sway * 1.1 - cyc * 1.5
	var coat := PackedVector2Array([
		Vector2(-6.5 + lean, -38 + top), Vector2(5.5 + lean, -38.5 + top), Vector2(7.0 + lean * 0.8, -30 + top),
		Vector2(6.0 + lean * 0.5, -24 + top), Vector2(8.5 + cyc * 1.5, -9.5), Vector2(4.0 + cyc, -8.0),
		Vector2(0.5, -11.0), Vector2(-3.0, -7.5 + absf(flare) * 0.3), Vector2(-10.0 + flare, -6.5 + absf(flare) * 0.5),
		Vector2(-7.5 + lean * 0.3, -24 + top), Vector2(-7.5 + lean, -34 + top),
	])
	ci.draw_colored_polygon(coat, c.call(COAT))
	# The lining, oxblood, where the coat parts below the belt.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(0.8 + lean * 0.4, -22 + top), Vector2(3.6 + cyc, -8.5), Vector2(0.5, -11.0), Vector2(-2.6, -8.0),
	]), c.call(LINING))
	# Shade down the back, and the seam.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-7.5 + lean, -34 + top), Vector2(-5.0 + lean, -34 + top), Vector2(-5.5, -22 + top),
		Vector2(-7.0 + flare * 0.6, -8.0), Vector2(-10.0 + flare, -6.5 + absf(flare) * 0.5), Vector2(-7.5 + lean * 0.3, -24 + top),
	]), c.call(COAT_DARK))
	ci.draw_line(Vector2(1.0 + lean * 0.6, -37 + top), Vector2(0.8 + lean * 0.4, -22 + top), c.call(COAT_DARK), 1.0)
	# Two rows of brass buttons.
	for i in 4:
		var by := -35.0 + i * 3.2 + top
		ci.draw_rect(Rect2(2.2 + lean * 0.6, by, 1.1, 1.1), c.call(BRASS))
		ci.draw_rect(Rect2(4.6 + lean * 0.6, by, 1.1, 1.1), c.call(BRASS.darkened(0.3)))
	# The belt: buckle, a pouch, a vial.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-7.6 + lean * 0.3, -25.5 + top), Vector2(6.2 + lean * 0.5, -25.5 + top),
		Vector2(6.1 + lean * 0.5, -23.3 + top), Vector2(-7.6 + lean * 0.3, -23.3 + top),
	]), c.call(LEATHER))
	ci.draw_rect(Rect2(2.6 + lean * 0.5, -25.8 + top, 2.4, 2.8), c.call(BRASS))
	ci.draw_rect(Rect2(3.2 + lean * 0.5, -25.2 + top, 1.2, 1.6), c.call(LEATHER))
	ci.draw_rect(Rect2(-6.5 + lean * 0.3, -23.5 + top, 3.4, 3.6), c.call(LEATHER.lightened(0.08)))
	if vials > 0:
		ci.draw_rect(Rect2(-2.4 + lean * 0.4, -23.6 + top, 1.6, 3.2), c.call(VIAL))
		ci.draw_rect(Rect2(-2.4 + lean * 0.4, -24.4 + top, 1.6, 0.9), c.call(LEATHER.lightened(0.3)))

	# The mantle over the shoulders, its hem ragged.
	var mantle := PackedVector2Array([
		Vector2(-8.5 + lean, -38.5 + top), Vector2(6.0 + lean, -39.5 + top), Vector2(8.5 + lean, -32.5 + top),
		Vector2(6.0 + lean, -30.5 + top), Vector2(3.5 + lean, -31.8 + top), Vector2(0.5 + lean, -29.8 + top),
		Vector2(-2.5 + lean, -31.2 + top), Vector2(-5.5 + lean + sway * 0.2, -29.5 + top),
		Vector2(-9.5 + lean + sway * 0.35, -31.5 + top),
	])
	ci.draw_colored_polygon(mantle, c.call(MANTLE))
	ci.draw_polyline(PackedVector2Array([Vector2(-9.0 + lean, -36 + top), Vector2(-1.0 + lean, -37 + top), Vector2(7.5 + lean, -35 + top)]), c.call(MANTLE.darkened(0.35)), 1.0)
	# The high collar, turned up behind the head.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-6.5 + lean, -38 + top), Vector2(-2.0 + lean, -39 + top), Vector2(-3.0 + lean, -45 + top), Vector2(-6.0 + lean, -43.5 + top),
	]), c.call(COAT_DARK))

	# The face, mostly shadow: a pale strip under the brim, an eye.
	ci.draw_rect(Rect2(-2.0 + lean, -47.5 + top, 7.0, 7.0), c.call(SKIN))
	ci.draw_rect(Rect2(-2.0 + lean, -47.5 + top, 7.0, 1.8), c.call(SKIN.darkened(0.55)))
	ci.draw_rect(Rect2(2.6 + lean, -45.2 + top, 1.6, 0.9), c.call(Color("1a1414")))
	ci.draw_rect(Rect2(-3.8 + lean, -47.5 + top, 2.4, 6.0), c.call(HAIR))
	# The scarf: wound over the mouth and nose, the tail streaming.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-6.5 + lean, -41.5 + top), Vector2(5.8 + lean, -43.2 + top), Vector2(6.2 + lean, -39.0 + top),
		Vector2(-6.0 + lean, -37.2 + top),
	]), c.call(SCARF))
	ci.draw_line(Vector2(-5.5 + lean, -39.8 + top), Vector2(5.5 + lean, -41.2 + top), c.call(SCARF.darkened(0.35)), 0.8)
	var tail := PackedVector2Array()
	for i in 5:
		var k := i / 4.0
		var wave := sin(_time * 8.0 - i * 0.9) * 1.6 * k
		tail.append(Vector2(-5.5 + lean - k * (6.0 - sway * 1.6), -39.5 + top + k * (4.0 - absf(sway) * 0.5) + wave))
	ci.draw_polyline(tail, c.call(SCARF), 2.6)
	ci.draw_polyline(tail, c.call(SCARF.darkened(0.3)), 0.8)

	# The hat: a tall stovepipe, a little tapered, worn back; a band and a
	# curled brim.
	var tilt := -0.8 + sin(run_t * 13.0) * 0.3 if moving else -0.8
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-4.8 + lean, -48.0 + top), Vector2(5.4 + lean, -48.0 + top),
		Vector2(5.0 + lean + tilt, -59.5 + top), Vector2(-4.2 + lean + tilt, -60.2 + top),
	]), c.call(HAT))
	ci.draw_line(Vector2(5.2 + lean, -48.5 + top), Vector2(4.8 + lean + tilt, -59.3 + top), c.call(HAT.lightened(0.18)), 0.8)
	ci.draw_line(Vector2(-4.2 + lean + tilt, -60.0 + top), Vector2(5.0 + lean + tilt, -59.4 + top), c.call(HAT.lightened(0.12)), 0.8)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-4.8 + lean, -48.2 + top), Vector2(5.4 + lean, -48.2 + top), Vector2(5.3 + lean, -50.4 + top), Vector2(-4.7 + lean, -50.6 + top),
	]), c.call(SCARF.darkened(0.25)))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-9.5 + lean, -49.2 + top), Vector2(-7.5 + lean, -48.0 + top), Vector2(8.5 + lean, -47.6 + top),
		Vector2(10.5 + lean, -48.8 + top), Vector2(9.5 + lean, -46.6 + top), Vector2(-8.5 + lean, -47.0 + top),
	]), c.call(HAT))

	if not ghost:
		_paint_arms(ci)


## An arm (or leg) from a to b, its joint bent `bend` (1 down/out, -1 the
## other way), as two segments.
func _limb(ci: CanvasItem, a: Vector2, b: Vector2, bend: float, col: Color, w0: float, w1: float) -> void:
	var mid := (a + b) * 0.5
	var d := b - a
	var joint := mid + Vector2(-d.y, d.x).normalized() * bend * minf(2.5, d.length() * 0.18)
	ci.draw_line(a, joint, col, w0)
	ci.draw_line(joint, b, col, w1)
	ci.draw_circle(joint, w1 * 0.5, col)


func _paint_arms(ci: CanvasItem) -> void:
	var s := _shoulder()
	var th := _pole_angle()
	var dir := Vector2(cos(th), sin(th))
	var across := Vector2(-dir.y, dir.x)
	var hand := _hand()
	var f := form_data()

	# The pole: ash, iron-shod at the butt, banded below the head.
	var length := 30.0 if f.burns else 46.0
	var tip := hand + dir * length
	var butt := hand - dir * 12.0
	ci.draw_line(butt, tip, POLE, 2.6)
	ci.draw_line(butt + across * 0.5, tip + across * 0.5, POLE.darkened(0.35), 0.8)
	ci.draw_line(butt, butt + dir * 2.5, IRON, 3.2)
	ci.draw_line(tip - dir * 5.0, tip - dir * 3.0, IRON, 3.2)
	if not f.burns:
		# The hook, curling back, and the wick holder at the very end.
		var hook := PackedVector2Array()
		for i in 9:
			var a := th - 0.15 * PI + i / 8.0 * 1.15 * PI
			hook.append(tip - dir * 3.0 + across * -4.5 + Vector2(cos(a), sin(a)) * 4.5)
		ci.draw_polyline(hook, IRON, 1.8)
		ci.draw_circle(hook[hook.size() - 1], 0.9, IRON)
		ci.draw_line(tip, tip + dir * 2.5, IRON.lightened(0.15), 1.6)
		ci.draw_circle(hand + dir * (length + 3.0), 1.5 + sin(_time * 20.0) * 0.4, LAMP)
	else:
		# The Lantern on its chain: a peaked iron cage round a glass.
		var l := _lantern_point()
		var links := 4
		for i in links:
			ci.draw_line(tip.lerp(l, i / float(links)), tip.lerp(l, (i + 0.6) / float(links)), IRON, 1.0)
		ci.draw_colored_polygon(PackedVector2Array([l + Vector2(-5.5, 1), l + Vector2(0, -3), l + Vector2(5.5, 1)]), IRON)
		ci.draw_rect(Rect2(l.x - 4.5, l.y + 1, 9, 9), LAMP)
		ci.draw_rect(Rect2(l.x - 1.5, l.y + 3, 3, 5), LAMP.lightened(0.5))
		for bx in [-4.5, -1.5, 1.5, 4.5]:
			ci.draw_line(Vector2(l.x + bx, l.y + 1), Vector2(l.x + bx, l.y + 10), IRON, 0.9)
		ci.draw_rect(Rect2(l.x - 5.5, l.y + 10, 11, 2), IRON)
		ci.draw_rect(Rect2(l.x - 1.5, l.y + 12, 3, 1.5), IRON)

	# The arm holding it: sleeve, cuff, glove.
	_limb(ci, s, hand, 1.0, COAT, 4.2, 3.6)
	ci.draw_line(hand - (hand - s).normalized() * 3.0, hand - (hand - s).normalized() * 1.6, MANTLE.lightened(0.15), 4.0)
	ci.draw_circle(hand, 2.0, GLOVE)

	# Off hand: the pistol, a vial, or the blade for blood bullets.
	match state:
		"shoot":
			var gy: float = -T.GUN.y
			var gh := Vector2(12.5, gy)
			_limb(ci, s + Vector2(-2, 2), gh, -1.0, COAT, 4.0, 3.4)
			ci.draw_circle(gh, 1.9, GLOVE)
			# A long-barrelled pistol, brass at the lock.
			ci.draw_colored_polygon(PackedVector2Array([Vector2(11, gy - 3), Vector2(22, gy - 3), Vector2(22, gy - 1.2), Vector2(14, gy - 0.8), Vector2(13.5, gy + 4), Vector2(11, gy + 3.5)]), GUNMETAL)
			ci.draw_rect(Rect2(13.5, gy - 2.6, 2.5, 1.6), BRASS)
			ci.draw_line(Vector2(15, gy - 3.4), Vector2(21.5, gy - 3.4), GUNMETAL.lightened(0.25), 0.7)
			if not world.shot.is_empty():
				ci.draw_colored_polygon(PackedVector2Array([Vector2(22, gy - 6), Vector2(32, gy - 2), Vector2(22, gy + 2)]), Color(1.0, 0.9, 0.67, 0.9))
		"heal":
			_limb(ci, s + Vector2(-2, 2), Vector2(4, -44), -1.0, COAT, 4.0, 3.4)
			ci.draw_circle(Vector2(4, -44), 1.9, GLOVE)
			ci.draw_rect(Rect2(3, -49, 3.5, 6), VIAL)
			ci.draw_rect(Rect2(3.6, -50.2, 2.3, 1.4), LEATHER.lightened(0.3))
		"blood":
			_limb(ci, s + Vector2(-2, 2), Vector2(6, -24), -1.0, COAT, 4.0, 3.4)
			ci.draw_circle(Vector2(6, -24), 1.9, GLOVE)
			ci.draw_line(Vector2(6, -24), Vector2(12, -28), Color("b8b2a6"), 1.2)
			ci.draw_arc(Vector2(0, -70), 6.0, -PI / 2.0, -PI / 2.0 + (t / T.BLOOD.time) * TAU, 16, VIAL, 2.0)
