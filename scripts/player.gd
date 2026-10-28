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
	_fig.setup(Vector2(160, 120), Vector2(80, 108), _paint)


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
	if rally_hold > 0.0:
		rally_hold -= delta
	else:
		rally = maxf(0.0, rally - T.RALLY.decay * delta)

	var dir_x := (1.0 if held.move_right else 0.0) - (1.0 if held.move_left else 0.0)
	var control := 0.0
	var gravity := true

	match state:
		"move":
			control = 1.0
			_free_actions(held, dir_x)
		"attack":
			control = 0.0 if is_on_floor() else 0.35
			_tick_attack(dir_x)
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

	# Down + jump on a walkway drops through it for a moment.
	collision_mask = 1 if drop_t > 0.0 else 3
	move_and_slide()
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
		var e = _visceral_target()
		if e:
			_start_visceral(e)
			return
		combo = 0
		_start_attack(f.combo[0], "combo")
		return
	if buf.transform > 0.0:
		buf.transform = 0.0
		form = f.trick.to
		state = "transform"
		t = 0.0
		Sfx.play("swing")
		return
	if buf.shoot > 0.0:
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


func _start_attack(a: Dictionary, k: String) -> void:
	state = "attack"
	t = 0.0
	attack = a
	kind = k
	hit_set = []
	lunged = false


func _tick_attack(dir_x: float) -> void:
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
	if buf.transform > 0.0 and kind == "combo":
		buf.transform = 0.0
		_start_attack(form_data().trick, "trick")
		return
	if buf.attack > 0.0 and t >= off + a.recovery * 0.35:
		buf.attack = 0.0
		var e = _visceral_target()
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
	return dash_cd <= 0.0 and (is_on_floor() or air_dash)


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


## The hook's wick, in the node's (unmirrored) space.
func _wick() -> Vector2:
	var th := _pole_angle()
	var tip := _hand() + Vector2(cos(th), sin(th)) * 47.0
	return Vector2(tip.x * facing, tip.y)


## Draws the Lamplighter (and quickstep afterimages) onto ci, the Figure's
## painter, with the feet at 0, 0.
func _paint(ci: CanvasItem) -> void:
	if state == "dash":
		for i in range(3, 0, -1):
			_paint_figure(ci, -dash_dir * i * 11.0, 0.12 * (4 - i), true)
	_paint_figure(ci, 0.0, 1.0, false)
	ci.draw_set_transform(Vector2.ZERO)


func _paint_figure(ci: CanvasItem, offset: float, alpha: float, ghost: bool) -> void:
	var rot := minf(1.0, t * 2.0) * 1.35 if state == "dead" else 0.0
	ci.draw_set_transform(Vector2(offset, 0), rot * facing, Vector2(facing, 1))
	var c := func(col: Color) -> Color: return Color(col, col.a * alpha)
	var air := not is_on_floor() and state != "dead"
	var cyc := sin(run_t * 13.0) if is_on_floor() and absf(velocity.x) > 20.0 else 0.0
	var sway := clampf(-velocity.x / 300.0, -1.0, 1.0) * 6.0
	var lean := _lean()

	# Legs.
	if air:
		ci.draw_rect(Rect2(-5, -15, 4, 11), c.call(COAT_DARK))
		ci.draw_rect(Rect2(1, -14, 4, 9), c.call(COAT_DARK))
	else:
		ci.draw_rect(Rect2(-5 + cyc * 4.0, -14, 4, 14), c.call(COAT_DARK))
		ci.draw_rect(Rect2(1 - cyc * 4.0, -14, 4, 14), c.call(COAT_DARK))

	# Long coat, tails trailing.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-6 + lean, -38), Vector2(6 + lean, -38), Vector2(8, -12), Vector2(-9 + sway, -8 + absf(sway) * 0.4),
	]), c.call(COAT))
	ci.draw_rect(Rect2(-1 + lean * 0.5, -36, 2, 22), c.call(COAT_DARK))

	# Oxblood scarf, its tail streaming behind.
	ci.draw_rect(Rect2(-6 + lean, -40, 12, 4), c.call(SCARF))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-5 + lean, -39), Vector2(-13 + sway * 1.4, -35 + sin(_time * 8.0) * 1.5), Vector2(-5 + lean, -36),
	]), c.call(SCARF))

	# Face, under a tall hat.
	ci.draw_rect(Rect2(-2 + lean, -46, 7, 6), c.call(SKIN))
	ci.draw_rect(Rect2(-8 + lean, -47, 17, 2), c.call(HAT))
	ci.draw_rect(Rect2(-5 + lean, -58, 11, 11), c.call(HAT))
	ci.draw_rect(Rect2(-5 + lean, -50, 11, 1.5), c.call(SCARF))

	if not ghost:
		_paint_arms(ci)


func _paint_arms(ci: CanvasItem) -> void:
	var s := _shoulder()
	var th := _pole_angle()
	var dir := Vector2(cos(th), sin(th))
	var hand := _hand()
	var f := form_data()

	# The pole.
	var length := 30.0 if f.burns else 46.0
	var tip := hand + dir * length
	ci.draw_line(hand - dir * 12.0, tip, POLE, 2.5)
	if not f.burns:
		# Hook and wick.
		var hook := hand + dir * (length - 4.0) + Vector2(-dir.y, dir.x) * -5.0
		ci.draw_arc(hook, 5.0, th - 0.1 * PI, th + 0.5 * PI, 10, IRON, 2.0)
		ci.draw_circle(hand + dir * (length + 1.0), 1.6 + sin(_time * 20.0) * 0.4, LAMP)
	else:
		# Lantern on its chain: hangs from the pole tip, flung outward mid-swing.
		var flung: bool = state == "attack" and t > attack.startup * 0.5
		var swing := sin(_time * 3.0) * 0.25 - clampf(velocity.x * facing / 300.0, -1.0, 1.0) * 0.5
		var l := tip + dir * 18.0 if flung else tip + Vector2(sin(swing), cos(swing)) * 14.0
		ci.draw_line(tip, l, IRON, 1.0)
		ci.draw_rect(Rect2(l.x - 5, l.y - 1, 10, 2), IRON)
		ci.draw_rect(Rect2(l.x - 4, l.y + 1, 8, 9), LAMP)
		ci.draw_rect(Rect2(l.x - 5, l.y + 10, 10, 2), IRON)
		_lantern = Vector2((l.x) * facing, l.y + 5.0)

	# The arm holding it.
	ci.draw_line(s, hand, COAT, 4.0)

	# Off hand: the pistol, a vial, or the blade for blood bullets.
	match state:
		"shoot":
			var gy: float = -T.GUN.y
			ci.draw_line(s + Vector2(-2, 2), Vector2(13, gy), COAT, 4.0)
			ci.draw_rect(Rect2(11, gy - 3, 9, 3), Color("3a3633"))
			ci.draw_rect(Rect2(12, gy - 1, 3, 4), Color("3a3633"))
			if not world.shot.is_empty():
				ci.draw_colored_polygon(PackedVector2Array([Vector2(20, gy - 6), Vector2(30, gy - 1.5), Vector2(20, gy + 3)]), Color(1.0, 0.9, 0.67, 0.9))
		"heal":
			ci.draw_line(s + Vector2(-2, 2), Vector2(4, -44), COAT, 4.0)
			ci.draw_rect(Rect2(3, -48, 4, 6), Color("c42b2f"))
		"blood":
			ci.draw_line(s + Vector2(-2, 2), Vector2(6, -24), COAT, 4.0)
			ci.draw_arc(Vector2(0, -70), 6.0, -PI / 2.0, -PI / 2.0 + (t / T.BLOOD.time) * TAU, 16, Color("c42b2f"), 2.0)
