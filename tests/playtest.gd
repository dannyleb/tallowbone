## Headless playtest: plays through every core mechanic with simulated input
## and checks the results. CI runs it on every push:
##   godot --headless --fixed-fps 60 --path . --script res://tests/playtest.gd
## Exits 1 if any check fails.
extends SceneTree

const Combat = preload("res://scripts/combat.gd")
const T = preload("res://scripts/tuning.gd")
const Art = preload("res://scripts/art.gd")
const Controls = preload("res://scripts/controls.gd")
const Keys = preload("res://scripts/keys.gd")

var main
var world
var player
var failures := 0
var checks := 0


func _initialize() -> void:
	seed(1)
	# A script that fails to compile would otherwise log errors every frame
	# for the whole run: stop at once instead.
	var broken := _broken_scripts("res://scripts")
	if _scripts_seen < 10:
		broken.append("(only %d scripts found to check)" % _scripts_seen)
	if not broken.is_empty():
		print("FAIL  scripts don't compile: ", ", ".join(broken))
		quit(1)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(2)
	world = main.world
	player = world.player
	# Lessons slow time; the mechanics checks run at full speed, and the
	# lessons get their own check at the end.
	world.teaching = false
	main.start_game()
	await _frames(30)

	await _scenario("_level_loaded", _level_loaded)
	await _scenario("_stage", _stage)
	await _scenario("_starts_with_little", _starts_with_little)
	await _scenario("_movement", _movement)
	await _scenario("_ledge_assist", _ledge_assist)
	await _scenario("_canal", _canal)
	await _scenario("_canal_jumps", _canal_jumps)
	await _scenario("_finds", _finds)
	await _scenario("_keyboard", _keyboard)
	await _scenario("_lamps", _lamps)
	await _scenario("_melee", _melee)
	await _scenario("_parry_and_visceral", _parry_and_visceral)
	await _scenario("_rally", _rally)
	await _scenario("_blood_and_vials", _blood_and_vials)
	await _scenario("_quickstep", _quickstep)
	await _scenario("_veil", _veil)
	await _scenario("_gates", _gates)
	await _scenario("_chimney", _chimney)
	await _scenario("_map", _map)
	await _scenario("_death_pile_and_gorge", _death_pile_and_gorge)
	await _scenario("_levelling", _levelling)
	await _scenario("_controls", _controls)
	await _scenario("_footsteps", _footsteps)
	await _scenario("_ambience", _ambience)
	await _scenario("_storm", _storm)
	await _scenario("_render_scale", _render_scale)
	await _scenario("_art", _art)
	await _scenario("_lessons", _lessons)

	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


# --- Helpers ---------------------------------------------------------------

var _scripts_seen := 0


func _broken_scripts(dir: String) -> PackedStringArray:
	var broken := PackedStringArray()
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			broken.append_array(_broken_scripts(dir.path_join(entry.trim_suffix("/"))))
		elif entry.ends_with(".gd"):
			_scripts_seen += 1
			var script: GDScript = load(dir.path_join(entry))
			if script == null or not script.can_instantiate():
				broken.append(entry)
	return broken


## Runs one scenario, announcing it first, so a log that stops short shows
## where.
func _scenario(name: String, f: Callable) -> void:
	print("--- ", name.trim_prefix("_"))
	await f.call()


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
	_check("entities placed", world.enemies.size() == 9 and world.lamps.size() == 2 and world.signs.size() == 8 and world.pickups.size() == 7 and world.gates.size() == 2,
		"%d enemies, %d lamps, %d signs, %d pickups, %d gates" % [world.enemies.size(), world.lamps.size(), world.signs.size(), world.pickups.size(), world.gates.size()])
	_check("player lands at the start", player.is_on_floor() and absf(player.position.y - 640.0) < 1.0, str(player.position))
	var lit_figures: bool = player._fig.texture != null and world.enemies.all(func(e): return e._fig.texture != null)
	_check("actors are drawn as lit, rounded figures", lit_figures)


## The 3D stage (on unless ?2d) is built from the level, and the flat 2D
## look is off under it.
func _stage() -> void:
	var st = main.stage
	_check("the 3D stage is on", st != null)
	if st == null:
		return
	_check("it extrudes the level's stone and back walls", st.counts.stone_faces > 2000 and st.counts.back_faces > 100, str(st.counts))
	_check("a light for every street lamp, and a city behind", st.counts.lamp_lights == world.lamps.size() and st.counts.buildings > 50, str(st.counts))
	_check("veils are built, and water drips off the ledges", st.counts.veil == 3 and st.counts.drips > 15, str(st.counts))
	_check("indoor spaces get reflection probes (no sky in their puddles)", st.counts.probes >= 2 and st.counts.probes <= 12, str(st.counts))
	_check("rain splashes where it lands, drainpipes pour, gas lamps burn in the street behind",
		st.counts.splashes > 150 and st.counts.pours >= 3 and st.counts.gas_lamps >= 4, str(st.counts))
	_check("mist lies over the streets and the canal", st.counts.mist >= 4, str(st.counts))
	_check("watchers have rooftops to stand on", st.roofs.size() > 10, str(st.roofs.size()))
	_check("every material is drawn once at load (no first-sight hitches)", st.counts.prewarmed >= 12, str(st.counts.prewarmed))
	st.set_quality(2)
	var fast: bool = not st.env.volumetric_fog_enabled and not st.env.ssao_enabled and not st.env.ssr_enabled
	st.set_quality(0)
	_check("quality steps down (Fast drops fog, occlusion, reflections) and back up",
		fast and st.env.volumetric_fog_enabled and st.env.ssao_enabled and st.quality == 0)
	_check("the flat 2D tiles and night are off", not world.level.ground.visible and not world.get_node("Night").visible)
	_check("actors and props draw onto the 3D plane, effects over it",
		st.plane_vp.world_2d == main.game.world_2d and world.player.visibility_layer == st.ON_PLANE and main.game.canvas_cull_mask == st.OVERLAY)


## You start with walk, jump and strike; the rest is found.
func _starts_with_little() -> void:
	_check("every ability starts locked", T.ABILITIES.all(func(a): return not player.has(a)), str(player.abilities))
	var bullets: int = player.bullets
	await _tap("shoot")
	await _tap("dash")
	await _tap("transform")
	await _frames(10)
	_check("pistol, quickstep and transform do nothing yet", player.state == "move" and player.bullets == bullets and player.form == "hook",
		"%s bullets %d form %s" % [player.state, player.bullets, player.form])
	_check("the title shows five essentials per device", main.KEYBOARD.size() == 5 and main.GAMEPAD.size() == 5)
	main.set_paused(true)
	await process_frame
	await process_frame
	var map_shown: bool = main._map.is_visible_in_tree()
	var keys_text: String = main._keys.text
	main.set_paused(false)
	_check("pausing shows the map", map_shown)
	_check("the pause screen lists only the keys you have", "strike" in keys_text and not ("pistol" in keys_text) and not ("quickstep" in keys_text), keys_text)
	_check("the map starts with only the start seen", world.is_explored(Vector2i(4, 19)) and not world.is_explored(Vector2i(140, 19)))


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


## Pushing into a ledge with your feet just under its top pops you onto it.
func _ledge_assist() -> void:
	# The two-tile block on Lamplighter's Row: cols 14-15, top at y 576.
	# Coming in from mid-air, feet a few px short of its top.
	await _tp(400.0, 640.0, 1.0, 99.0)
	player.position = Vector2(14 * 32 - 18.0, 576.0 + 4.0)
	player.velocity = Vector2(200.0, 0.0)
	Input.action_press("move_right")
	await _frames(10)
	Input.action_release("move_right")
	_check("a jump that clips a ledge still lands on it", player.is_on_floor() and absf(player.position.y - 576.0) < 1.0, str(player.position))
	await _frames(5)
	_fresh()


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
	await _hold("shoot", 40)
	await _frames(2)
	_check("out of bullets, holding the pistol trades 20 HP for 4 rounds", player.bullets == 4 and absf(player.hp - 60.0) < 0.01, "bullets %d hp %s" % [player.bullets, player.hp])
	_check("the blood spent becomes rally", player.rally > 15.0, str(player.rally))
	var vials: int = player.vials
	await _tap("heal")
	await _frames(45)
	_check("a vial heals", player.hp > 95.0 and player.vials == vials - 1, "hp %s vials %d" % [player.hp, player.vials])
	_fresh()


func _veil() -> void:
	await _tp(2680.0, 640.0, 1.0, 99.0)
	# Hold strike: a swing, then the Pole turns into a Lantern trick attack.
	await _hold("attack", 40)
	await _frames(30)
	_check("holding strike turns the Pole to its Lantern", player.form == "lantern", player.form)
	var lv = world.level
	_check("the Lantern burns the whole veil", lv.kind_at(Vector2i(85, 17)) == "" and lv.kind_at(Vector2i(85, 18)) == "" and lv.kind_at(Vector2i(85, 19)) == "")
	if main.stage:
		_check("and it's gone from the 3D stage too", main.stage.counts.veil == 0, str(main.stage.counts))
	await _tap("transform")
	await _frames(20)
	_check("the transform key still turns it back", player.form == "hook", player.form)
	_fresh()


func _canal() -> void:
	await _tp(990.0, 640.0, 1.0)
	await _hold("move_right", 15)
	await _frames(40)
	_check("the canal hurts and puts you back on firm ground", absf(player.hp - 80.0) < 0.01 and player.position.x < 1024.0 and player.is_on_floor(),
		"hp %s at %s" % [player.hp, player.position])
	_fresh()


## The canal: three plain jumps, bank to post to post to bank, with no
## abilities at all.
func _canal_jumps() -> void:
	await _tp(30 * 32 + 16.0, 640.0, 1.0)
	var hp: float = player.hp
	var edges := [32 * 32.0, 37 * 32.0, 42 * 32.0]
	var next := 0
	Input.action_press("move_right")
	for f in 300:
		if next < edges.size() and player.is_on_floor() and player.position.x >= edges[next] - 6.0:
			next += 1
			Input.action_press("jump")
		elif Input.is_action_pressed("jump") and player.velocity.y > 0.0:
			Input.action_release("jump")
		if player.position.x > 46 * 32.0 and player.is_on_floor():
			break
		await physics_frame
	Input.action_release("jump")
	Input.action_release("move_right")
	await _frames(5)
	_check("plain jumps cross the canal post to post", player.position.x > 45 * 32.0 and player.is_on_floor() and player.hp == hp,
		"at %s hp %s" % [player.position, player.hp])
	_fresh()


## Each find on the way unlocks its ability.
func _finds() -> void:
	for pair in [["WatchmansBoots1", "quickstep"], ["WatchPistol1", "pistol"], ["LampOil1", "lantern"], ["ClimbingIrons1", "irons"]]:
		var it = world.level.get_node("Entities/" + pair[0])
		await _tp(it.position.x, it.position.y, 1.0, 99.0)
		await _frames(3)
		_check("%s gives %s" % [pair[0], pair[1]], it.taken and player.has(pair[1]))
	_fresh()


## Trackpads: J strikes, K or Ctrl-click fires; keys can be rebound, saved
## and reset; prompts name whatever is bound.
func _keyboard() -> void:
	_check("prompts name the mouse button and the key", Keys.label("attack") == "Left-click / J" and Keys.label("shoot") == "Right-click / K",
		"%s | %s" % [Keys.label("attack"), Keys.label("shoot")])
	await _tp(1600.0, 640.0, 1.0, 99.0)
	player.bullets = player.max_bullets
	var bullets: int = player.bullets
	_key_event(KEY_CTRL, true)
	_click(true)
	var fired: bool = await _wait_until(func(): return player.state == "shoot", 10)
	var struck: bool = player.state == "attack"
	_click(false)
	_key_event(KEY_CTRL, false)
	await _frames(30)
	_check("Ctrl-click fires the pistol, and doesn't strike", fired and not struck and player.bullets == bullets - 1,
		"fired %s struck %s bullets %d of %d" % [fired, struck, player.bullets, bullets])

	Controls.rebind("attack", KEY_Z)
	var attack_keys := Controls.keys("attack")
	_check("rebinding strike to Z replaces J, and prompts say Z", attack_keys.size() == 1 and attack_keys[0] == KEY_Z and Keys.label("attack") == "Left-click / Z",
		"%s %s" % [attack_keys, Keys.label("attack")])
	Controls.rebind("attack", KEY_K)
	var shoot_keys := Controls.keys("shoot")
	_check("taking another action's key swaps them", shoot_keys.size() == 1 and shoot_keys[0] == KEY_Z, str(shoot_keys))
	Controls.save()
	InputMap.load_from_project_settings()
	Controls.load_saved()
	_check("bindings are saved and come back", Controls.keys("attack")[0] == KEY_K and Controls.keys("shoot")[0] == KEY_Z)
	Controls.reset()
	_check("reset brings back J and K, and forgets the saved ones",
		Controls.keys("attack").has(KEY_J) and Controls.keys("shoot").has(KEY_K) and not FileAccess.file_exists(Controls.FILE))
	_fresh()


func _key_event(key: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = down
	Input.parse_input_event(ev)


func _click(down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	Input.parse_input_event(ev)


func _quickstep() -> void:
	await _tp(1600.0, 640.0, 1.0)
	var x0: float = player.position.x
	await _tap("dash", 2)
	var stepped: bool = await _wait_until(func(): return player.state == "dash", 3)
	var hit_mid: bool = Combat.hurt_player(world, 10.0, player.position.x + 40.0)
	await _frames(15)
	_check("quickstep darts forward, untouchable", stepped and not hit_mid and player.position.x - x0 > 70.0,
		"dashing %s hit %s moved %.1f" % [stepped, hit_mid, player.position.x - x0])
	_fresh()


func _death_pile_and_gorge() -> void:
	var e = _enemy("Communicant4")
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


## Shortcut gates open only from one side, and stay open.
func _gates() -> void:
	var g = world.level.get_node("Entities/Gate2")
	await _tp(g.position.x - 34.0, g.position.y, 1.0, 99.0)
	_check("from the wrong side a gate is barred", world.prompt.get("text", "") == "Barred from the other side", str(world.prompt))
	await _tap("interact")
	await _hold("move_right", 30)
	_check("and it won't open or let you through", not g.open and player.position.x < g.position.x - 12.0, "x %s" % player.position.x)
	await _tp(g.position.x + 26.0, g.position.y, -1.0, 99.0)
	_check("from its own side it offers to open", world.prompt.get("text", "") == "Lift the bar", str(world.prompt))
	await _tap("interact")
	_check("lifting the bar opens it", g.open)
	await _hold("move_left", 30)
	_check("and the way through is open", player.position.x < g.position.x - 30.0, "x %s" % player.position.x)
	var hall = world.level.get_node("Entities/Gate1")
	await _tp(hall.position.x + 26.0, hall.position.y, -1.0, 99.0)
	await _tap("interact")
	_check("the hall door opens from the plaza", hall.open)
	# (No tallow on you, so no pile is left lying in the plaza.)
	world.tallow = 0
	Combat.kill_player(world)
	await _wait_until(func(): return player.state == "move", 300)
	_check("opened gates stay open after dying", g.open and hall.open)
	world.pile = {}
	_fresh()


## Climb the chimney by the start: impossible barehanded, a wall-jump climb
## with the Climbing Irons. A vial waits at the top.
func _chimney() -> void:
	player.abilities.irons = false
	var top_without: float = await _climb(240)
	_check("the chimney is too sheer without the Climbing Irons", top_without > 500.0, "reached y %s" % top_without)
	player.abilities.irons = true
	var vials: int = player.max_vials
	var top: float = await _climb(600)
	var it = world.level.get_node("Entities/VialHolder1")
	_check("with them you wall-jump up it", top <= 160.5, "reached y %s" % top)
	_check("and the vial holder up there adds a vial", it.taken and player.max_vials == vials + 1)
	_fresh()


## Wall-jumps up the chimney (cols 1-2, between walls at cols 0 and 3) like a
## player would: kick off whenever sliding, steer for the other wall, hold
## jump for height. Then walks along the top. Returns the highest feet y.
func _climb(max_frames: int) -> float:
	await _tp(64.0, 640.0, -1.0, 99.0)
	var dir := "move_left"
	var other := {"move_left": "move_right", "move_right": "move_left"}
	var top: float = player.position.y
	var held_for := 0
	Input.action_press(dir)
	Input.action_press("jump")
	for f in max_frames:
		top = minf(top, player.position.y)
		if player.is_on_floor() and player.position.y <= 160.5:
			# On the ledge by the chimney top: walk to the vial.
			Input.action_release(dir)
			Input.action_release("jump")
			dir = "move_right"
			Input.action_press(dir)
			if player.position.x >= 200.0:
				break
		elif player.sliding and not Input.is_action_pressed("jump"):
			Input.action_release(dir)
			dir = other[dir]
			Input.action_press(dir)
			Input.action_press("jump")
			held_for = 0
		elif Input.is_action_pressed("jump"):
			held_for += 1
			if held_for > 16:
				Input.action_release("jump")
		await physics_frame
	Input.action_release(dir)
	Input.action_release("jump")
	await _frames(3)
	return top


## The map fills in where you've been.
func _map() -> void:
	await _tp(4400.0, 640.0, 1.0, 99.0)
	await _frames(8)
	_check("the map fills in where you've been", world.is_explored(Vector2i(137, 19)) and world.is_explored(Vector2i(94, 27)))
	main.set_paused(true)
	await process_frame
	await process_frame
	var keys_text: String = main._keys.text
	main.set_paused(false)
	_check("the pause screen lists what you've found", "pistol" in keys_text and "quickstep" in keys_text and "turn the Pole" in keys_text, keys_text)
	_fresh()


func _controls() -> void:
	var mouse_button := func(action: String, index: int) -> bool:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton and ev.button_index == index:
				return true
		return false
	_check("left-click strikes, right-click shoots", mouse_button.call("attack", MOUSE_BUTTON_LEFT) and mouse_button.call("shoot", MOUSE_BUTTON_RIGHT))
	_check("no separate blood-bullet button", not InputMap.has_action("blood"))


## The world draws into its own viewport, sized to the view, and drops to a
## lower render scale when frames run slow.
func _render_scale() -> void:
	var g: SubViewport = main.game
	_check("the world draws into its own viewport, the size of the view", Vector2(g.size_2d_override) == world.view_size() and g.size.x >= g.size_2d_override.x,
		"%s over %s, view %s" % [g.size, g.size_2d_override, world.view_size()])
	var before: float = main.render_scale
	main.render_cap = 3.0
	main.fixed_scale = 2.0
	main.fit_view()
	var at_two: Vector2i = g.size
	main.fixed_scale = 0.0
	main.fit_view()
	main._settle = 0.0
	for i in 70:
		main._adapt(0.04)
	_check("a forced scale sizes the viewport, and slow frames lower it", at_two == Vector2i(world.view_size() * 2.0) and (main.render_scale < 2.0 or before < 2.0),
		"at 2x %s, after slow frames %.1fx (was %.1fx)" % [at_two, main.render_scale, before])
	main.render_cap = 3.0
	main.fit_view()
	main.toggle_perf()
	await _frames(25)
	var shown: bool = main._perf != null and main._perf.text.contains("fps")
	main.toggle_perf()
	_check("F3 shows the frame rate and render size, and hides it again", shown and main._perf == null)


## Painted character frames (docs/ART.md): every template pose is the frame
## the game would show at that moment, frames are found by animation, and a
## painted frame draws in place of the greybox.
func _art() -> void:
	world.running = false
	var mismatches := PackedStringArray()
	var anims: Dictionary = player.art_anims()
	for anim in anims:
		for f in int(anims[anim]):
			player.art_pose(anim, f)
			var got: Array = player.art_frame()
			if got[0] != anim or got[1] != f:
				mismatches.append("%s %d -> %s %d" % [anim, f, got[0], got[1]])
	for name in ["Communicant1", "Hound1"]:
		var e = _enemy(name)
		for anim in e.ART_ANIMS:
			for f in int(e.ART_ANIMS[anim]):
				e.art_pose(anim, f)
				var got: Array = e.art_frame()
				if got[0] != anim or got[1] != f:
					mismatches.append("%s %s %d -> %s %d" % [e.kind, anim, f, got[0], got[1]])
		e.reset()
	_check("every template pose is the frame the game shows then", mismatches.is_empty(), ", ".join(mismatches))
	player.air_override = null
	player.form = "hook"
	world.running = true
	await _tp(600.0, 640.0, 1.0, 99.0)

	Art.use_root("res://tests/fixtures/art")
	var found := Art.frames("lamplighter")
	_check("painted frames are found by animation, in order", found.has("hook_idle") and found.hook_idle.size() == 2,
		"%s under %s; a frame loads as %s" % [found.keys(), Art.root, load("res://tests/fixtures/art/lamplighter/hook_idle/01.png")])
	await _frames(5)
	var pose: Array = player.art_frame()
	_check("standing still shows the idle animation", pose[0] == "hook_idle", str(pose))
	var drew := {"ok": false}
	var probe := Node2D.new()
	probe.draw.connect(func(): drew.ok = Art.draw(probe, "lamplighter", ["hook_idle", 1], player.FIG_SIZE, player.FIG_ORIGIN))
	world.add_child(probe)
	await _frames(3)
	_check("a painted frame draws in place of the greybox", drew.ok)
	probe.queue_free()
	Art.use_root("res://art/characters")
	_fresh()


func _lessons() -> void:
	world.refresh()
	_fresh()
	world.teaching = true
	world.learned = {"parry": false, "visceral": false}
	var e = _enemy("Communicant1")
	await _tp(e.position.x - 90.0, 640.0, 1.0)
	var started: bool = await _wait_until(func(): return world.lesson.get("kind", "") == "parry", 600)
	_check("the first glint starts a lesson", started and Engine.time_scale < 1.0, "time scale %s" % Engine.time_scale)
	await _tap("shoot", 3)
	var next: bool = await _wait_until(func(): return world.lesson.get("kind", "") == "visceral", 200)
	_check("a parry during it is learned, and the Visceral lesson follows", next and world.learned.parry)
	player.position.x = e.position.x - 30.0
	player.facing = 1.0
	await _tap("attack", 3)
	var done: bool = await _wait_until(func(): return world.learned.visceral, 200)
	_check("finishing it ends the lessons and time runs normally", done and world.lesson.is_empty() and Engine.time_scale == 1.0,
		"time scale %s" % Engine.time_scale)


## The soundscape: beds that loop, mixed by where you are; far-off sounds
## at random; whispers only in the dark; thunder after lightning, and the
## call after a reveal.
func _ambience() -> void:
	var amb = main.ambience
	_check("ambience: there is a soundscape", amb != null)
	if amb == null:
		return
	amb.auto = false
	var bad := []
	for name in amb.BEDS:
		var p: AudioStreamPlayer = amb.bed(name)
		var s: AudioStreamOggVorbis = p.stream as AudioStreamOggVorbis if p else null
		if s == null or not s.loop or s.get_length() < 10.0 or not p.playing:
			bad.append(name)
	_check("ambience: every bed loads, loops and plays", bad.is_empty(), str(bad))

	var start: Vector2 = world.level.player_start.position
	await _tp(start.x, start.y, 1.0, 30.0)
	for i in 60:
		amb.step(0.1)
	var open_air: Dictionary = amb.presence()
	var roofed := _roofed_spot()
	await _tp(roofed.x, roofed.y, 1.0, 30.0)
	for i in 60:
		amb.step(0.1)
	var under: Dictionary = amb.presence()
	_check("ambience: rain in the open, muffled under a roof",
		open_air.rain_out > 0.9 and under.rain_in > 0.9 and under.rain_out < 0.1, "%s / %s at %s" % [open_air, under, roofed])
	_check("ambience: the wind drops under a roof", under.wind <= amb.gust * 0.2 + 0.01, str(under))

	await _tp(start.x, start.y, 1.0, 30.0)
	amb.reseed(7)
	amb.heard.clear()
	var flashes := []
	var on_flash := func(strength: float, reveal: bool): flashes.append([strength, reveal])
	amb.lightning.connect(on_flash)
	for i in 6000:
		amb.step(0.1)
	var count := func(prefix: String) -> int:
		return amb.heard.filter(func(h): return h.begins_with(prefix)).size()
	_check("ambience: ten minutes of night bring howls, the bell, creaks and storms",
		count.call("howl") >= 5 and count.call("bell") >= 2 and count.call("creak") >= 3 and count.call("thunder") >= 6,
		str(amb.heard))
	_check("ambience: every flash has its thunder", count.call("thunder") == flashes.size() or count.call("thunder") == flashes.size() - 1,
		"%d flashes, %d thunders" % [flashes.size(), count.call("thunder")])

	amb.heard.clear()
	amb.dread = 0.1
	amb._fire("whisper")
	var calm: int = count.call("whisper")
	amb.dread = 0.9
	amb._fire("whisper")
	_check("ambience: whispers only in the dark", calm == 0 and count.call("whisper") == 1, str(amb.heard))

	amb.heard.clear()
	flashes.clear()
	for i in 30:
		amb._last_reveal = -1000.0
		amb.strike(1.0)
		if not flashes.is_empty() and flashes[-1][1]:
			break
	for i in 60:
		amb.step(0.1)
	var revealed: bool = not flashes.is_empty() and flashes[-1][1]
	_check("ambience: an overhead strike thunders at once; a reveal brings the call",
		revealed and amb.heard.has("thunder_near") and amb.heard.has("call") and amb.dread > 0.6,
		"%s %s dread %.2f" % [flashes, amb.heard, amb.dread])
	amb.lightning.disconnect(on_flash)
	amb.auto = true
	await _tp(start.x, start.y)


## Somewhere to stand under a roof.
func _roofed_spot() -> Vector2:
	var lv = world.level
	for r in range(1, lv.size_tiles.y):
		for c in lv.size_tiles.x:
			var feet := Vector2((c + 0.5) * T.TILE, r * T.TILE)
			if lv.standable_at(feet + Vector2(0, 4)) and not lv.solid_at(feet + Vector2(0, -8)) \
					and not lv.solid_at(feet + Vector2(0, -40)) and lv.roofed_at(feet + Vector2(0, -24)):
				return feet
	return Vector2.ZERO


## Lightning on the 3D stage: the flash, the thing in the fog, its eyes
## after, the watchers on the roofs.
func _storm() -> void:
	var storm = main.stage.storm if main.stage else null
	_check("storm: the stage has one", storm != null)
	if storm == null:
		return
	main.ambience.auto = false
	storm.flash(1.0, true)
	var peak := 0.0
	var shown := 0.0
	for i in 30:
		await process_frame
		peak = maxf(peak, storm.level)
		shown = maxf(shown, storm.revealed)
	_check("storm: a strike flashes and shows the thing in the fog",
		peak > 0.5 and storm.colossus.visible and shown > 0.9, "flash %.2f shown %.2f" % [peak, shown])
	for i in 150:
		await process_frame
	var near_roofs: bool = main.stage.roofs.any(func(r): return absf((r[0] + r[1]) * 0.5 - main.stage.camera.position.x) < storm.WATCH_RANGE)
	_check("storm: then dark again, its eyes still open, watchers on the roofs",
		storm.level < 0.01 and not storm.light.visible and storm.eyes > 0.5 and storm.revealed < 0.2
		and (storm.watchers.any(func(w): return w.visible) or not near_roofs),
		"flash %.2f eyes %.2f shown %.2f" % [storm.level, storm.eyes, storm.revealed])
	for i in 720:
		await process_frame
	_check("storm: its eyes close and it's gone", not storm.colossus.visible and storm.eyes == 0.0)
	main.ambience.auto = true


## Boots on wet stone as you walk, a landing when you come down hard; every
## take of every body sound loads.
func _footsteps() -> void:
	var sfx = main.get_node("Sfx")
	var missing := []
	for n in sfx.TAKES:
		for stream in sfx._streams[n]:
			if stream == null:
				missing.append(n)
	_check("sfx: every take of the footsteps, landings and voices loads", missing.is_empty(), str(missing))
	var start: Vector2 = world.level.player_start.position
	await _tp(start.x, start.y, 1.0, 30.0)
	var steps: int = sfx.counts.get("step_stone", 0) + sfx.counts.get("step_wood", 0)
	await _hold("move_right", 60)
	var walked: int = sfx.counts.get("step_stone", 0) + sfx.counts.get("step_wood", 0) - steps
	_check("sfx: a second's walk is about four footsteps", walked >= 3 and walked <= 6, "%d steps" % walked)
	if main.stage:
		_check("each footstep kicks up a splash", main.stage.counts.step_splashes >= walked, str(main.stage.counts.step_splashes))
	var landings: int = sfx.counts.get("land", 0)
	await _tp(start.x, start.y - 200.0, 1.0, 30.0)
	await _frames(60)
	_check("sfx: coming down hard lands with a splash", sfx.counts.get("land", 0) == landings + 1, str(sfx.counts.get("land", 0) - landings))
	await _tp(start.x, start.y)
