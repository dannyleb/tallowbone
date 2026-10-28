## Headless playtest: plays through every core mechanic with simulated input
## and checks the results. CI runs it on every push:
##   godot --headless --fixed-fps 60 --path . --script res://tests/playtest.gd
## Exits 1 if any check fails.
extends SceneTree

const Combat = preload("res://scripts/combat.gd")

var main
var world
var player
var failures := 0
var checks := 0


func _initialize() -> void:
	seed(1)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(2)
	world = main.world
	player = world.player
	main.start_game()
	await _frames(30)

	await _level_loaded()
	await _movement()
	await _lamps()
	await _melee()
	await _parry_and_visceral()
	await _rally()
	await _blood_and_vials()
	await _veil()
	await _canal()
	await _gap()
	await _death_pile_and_gorge()
	await _levelling()
	await _pickup()

	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


# --- Helpers ---------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _tap(action: String, frames := 3) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)
	await _frames(1)


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


func _check(name: String, ok: bool, detail := "") -> void:
	checks += 1
	if ok:
		print("PASS  ", name)
	else:
		failures += 1
		print("FAIL  ", name, "  ", detail)


## Put the Lamplighter somewhere, standing, ready, and safe for `iframes` s.
func _tp(x: float, y: float, facing := 1.0, iframes := 0.0) -> void:
	player.position = Vector2(x, y)
	player.velocity = Vector2.ZERO
	player.facing = facing
	player.to_move()
	player.iframes = iframes
	_clear_buffers()
	world.snap_camera()
	await _frames(2)


func _enemy(name: String):
	return world.level.get_node("Entities/" + name)


func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await physics_frame
	return cond.call()


## Presses left over from the last scenario shouldn't leak into the next.
func _clear_buffers() -> void:
	for k in player.buf:
		player.buf[k] = 0.0


func _fresh() -> void:
	player.max_hp = 100.0
	player.refill()
	player.iframes = 0.0
	player.to_move()
	_clear_buffers()


# --- Scenarios ---------------------------------------------------------------

func _level_loaded() -> void:
	var lv = world.level
	_check("ground tiles loaded", lv.kind_at(Vector2i(5, 20)) == "stone", lv.kind_at(Vector2i(5, 20)))
	_check("veil tiles loaded", lv.kind_at(Vector2i(85, 18)) == "veil")
	_check("canal water loaded", lv.kind_at(Vector2i(33, 23)) == "water")
	_check("walkways loaded", lv.kind_at(Vector2i(63, 17)) == "walkway")
	_check("entities placed", world.enemies.size() == 9 and world.lamps.size() == 2 and world.signs.size() == 7 and world.pickups.size() == 2,
		"%d enemies, %d lamps, %d signs, %d pickups" % [world.enemies.size(), world.lamps.size(), world.signs.size(), world.pickups.size()])
	_check("player lands at the start", player.is_on_floor() and absf(player.position.y - 640.0) < 1.0, str(player.position))


func _movement() -> void:
	var x0: float = player.position.x
	await _hold("move_right", 20)
	_check("walks right", player.position.x > x0 + 40.0, "%s -> %s" % [x0, player.position.x])
	await _frames(10)
	var y0: float = player.position.y
	var top := y0
	Input.action_press("jump")
	for i in 30:
		await physics_frame
		top = minf(top, player.position.y)
	Input.action_release("jump")
	await _frames(30)
	_check("jumps about three tiles", y0 - top > 85.0 and y0 - top < 120.0, "rose %.1f" % (y0 - top))
	_check("lands again", player.is_on_floor())


func _lamps() -> void:
	var lamp = world.level.get_node("Entities/Lamp1")
	await _tp(lamp.position.x - 10.0, 640.0)
	_check("lamp prompt shows", not world.prompt.is_empty())
	await _tap("interact")
	_check("lamp lights and becomes the checkpoint", lamp.lit and world.checkpoint == lamp)
	await _tap("interact")
	_check("resting opens the lamp menu", not world.menu.is_empty() and player.state == "rest")
	await _tap("back")
	_check("leaving closes it", world.menu.is_empty() and player.state == "move")


func _melee() -> void:
	var e = _enemy("Communicant1")
	await _tp(e.position.x - 70.0, 640.0, 1.0, 99.0)
	for i in 24:
		if not e.alive:
			break
		await _tap("attack", 2)
		await _frames(8)
	_check("melee kills a Communicant", not e.alive, "hp %s state %s" % [e.hp, e.state])
	_check("its tallow is yours", world.tallow == 40, str(world.tallow))
	_fresh()


func _parry_and_visceral() -> void:
	var e = _enemy("Communicant2")
	await _tp(e.position.x - 90.0, 640.0, 1.0)
	var ready: bool = await _wait_until(func(): return e.state == "windup" and e.t >= e.def.windup - e.def.parry + 0.03, 400)
	_check("enemy winds up and glints", ready and Combat.parryable(e), e.state)
	await _tap("shoot", 2)
	await _frames(6)
	_check("a shot on the glint staggers it", e.state == "stagger", e.state)
	player.position.x = e.position.x - 30.0
	player.facing = 1.0
	await _tap("attack", 2)
	# The parry's freeze-frame has to pass first.
	var finishing: bool = await _wait_until(func(): return player.state == "visceral", 20)
	_check("striking a staggered enemy is a Visceral", finishing, player.state)
	await _frames(45)
	_check("the Visceral kills it", not e.alive, "hp %s" % e.hp)
	_fresh()


func _rally() -> void:
	var e = _enemy("Hound1")
	await _tp(e.position.x - 120.0, 640.0, 1.0)
	var hit: bool = await _wait_until(func(): return player.rally > 0.0, 400)
	_check("the hound lands a hit and leaves rally", hit, "hp %s" % player.hp)
	await _frames(16)
	var hp_hit: float = player.hp
	# Step up beside it and strike back.
	var side := signf(player.position.x - e.position.x)
	if side == 0.0:
		side = -1.0
	player.position.x = e.position.x + side * 28.0
	player.facing = -side
	for i in 4:
		await _tap("attack", 2)
		await _frames(6)
	_check("striking back wins health back", player.hp > hp_hit, "%s -> %s" % [hp_hit, player.hp])
	_fresh()


func _blood_and_vials() -> void:
	await _tp(1600.0, 640.0, -1.0, 99.0)
	player.bullets = 0
	player.hp = 80.0
	player.rally = 0.0
	await _hold("blood", 40)
	await _frames(2)
	_check("blood bullets: 20 HP for 4 rounds", player.bullets == 4 and absf(player.hp - 60.0) < 0.01, "bullets %d hp %s" % [player.bullets, player.hp])
	_check("the blood spent becomes rally", player.rally > 15.0, str(player.rally))
	var vials: int = player.vials
	await _tap("heal")
	await _frames(45)
	_check("a vial heals", player.hp > 95.0 and player.vials == vials - 1, "hp %s vials %d" % [player.hp, player.vials])
	_fresh()


func _veil() -> void:
	await _tp(2680.0, 640.0, 1.0, 99.0)
	await _tap("transform")
	await _frames(20)
	_check("the Pole turns to its Lantern form", player.form == "lantern", player.form)
	await _tap("attack")
	await _frames(30)
	var lv = world.level
	_check("the Lantern burns the whole veil", lv.kind_at(Vector2i(85, 17)) == "" and lv.kind_at(Vector2i(85, 18)) == "" and lv.kind_at(Vector2i(85, 19)) == "")
	await _tap("transform")
	await _frames(20)
	_fresh()


func _canal() -> void:
	await _tp(990.0, 640.0, 1.0)
	await _hold("move_right", 15)
	await _frames(40)
	_check("the canal hurts and puts you back on firm ground", absf(player.hp - 80.0) < 0.01 and player.position.x < 1024.0 and player.is_on_floor(),
		"hp %s at %s" % [player.hp, player.position])
	_fresh()


func _gap() -> void:
	await _tp(41 * 32 + 12.0, 640.0, 1.0, 99.0)
	# Run to the end of the mooring post, jump, and quickstep at the top.
	Input.action_press("move_right")
	await _wait_until(func(): return player.position.x >= 1362.0, 60)
	Input.action_press("jump")
	await _frames(14)
	await _tap("dash", 2)
	await _frames(40)
	Input.action_release("jump")
	Input.action_release("move_right")
	await _frames(20)
	_check("jump + air quickstep clears the widest canal gap", player.position.x > 1540.0 and player.is_on_floor() and player.hp == player.max_hp,
		"at %s hp %s" % [player.position, player.hp])
	_fresh()


func _death_pile_and_gorge() -> void:
	var e = _enemy("Communicant3")
	world.tallow = 200
	await _tp(e.position.x - 80.0, 640.0, 1.0)
	player.hp = 1.0
	var died: bool = await _wait_until(func(): return player.state == "dead", 500)
	_check("dies", died)
	await _wait_until(func(): return player.state == "move", 300)
	var lamp = world.level.get_node("Entities/Lamp1")
	_check("respawns at the lamp", player.position.distance_to(lamp.position) < 1.0, str(player.position))
	_check("tallow drops where you fell", not world.pile.is_empty() and world.pile.amount == 200 and world.tallow == 0, str(world.pile))

	e.position.x = world.pile.pos.x
	await _frames(3)
	_check("an enemy that walks through it is Gorged", e.gorged == 200 and world.pile.is_empty(), "gorged %s" % e.gorged)
	_check("Gorged means tougher", e.max_hp > e.def.hp)

	e.hp = 1.0
	await _tp(e.position.x - 30.0, 640.0, 1.0, 99.0)
	player.facing = 1.0
	await _tap("attack", 2)
	await _frames(20)
	_check("killing it reclaims your tallow (+10%)", not e.alive and world.tallow == 40 + 220, str(world.tallow))
	_fresh()

	# Die twice without recovering and it's gone.
	world.tallow = 50
	Combat.kill_player(world)
	await _wait_until(func(): return player.state == "move", 300)
	_check("dying with tallow drops a new pile", world.pile.amount == 50)
	Combat.kill_player(world)
	await _wait_until(func(): return player.state == "move", 300)
	_check("dying again before reclaiming loses it", world.pile.is_empty())
	_fresh()


func _levelling() -> void:
	world.tallow = 300
	var lamp = world.level.get_node("Entities/Lamp1")
	await _tp(lamp.position.x - 10.0, 640.0)
	await _tap("interact")
	await _tap("confirm")
	_check("tallow buys a level", world.level_no == 2 and world.stats.vitality == 1 and player.max_hp == 112.0 and world.tallow == 240,
		"level %d tallow %d max hp %s" % [world.level_no, world.tallow, player.max_hp])
	await _tap("back")
	_check("the menu closes", world.menu.is_empty())


func _pickup() -> void:
	var vials: int = player.max_vials
	var it = world.level.get_node("Entities/VialHolder1")
	await _tp(it.position.x, it.position.y, 1.0, 99.0)
	await _frames(5)
	_check("a Vial Holder adds a vial", it.taken and player.max_vials == vials + 1)
