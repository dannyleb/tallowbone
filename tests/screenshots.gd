## Renders a set of screenshots of the game for review. CI runs it on a
## virtual display and publishes the images to the ci-reports branch:
##   godot --path . --fixed-fps 60 --resolution 1280x720 \
##     --script res://tests/screenshots.gd -- <output folder>
extends SceneTree

const Combat = preload("res://scripts/combat.gd")

var main
var world
var player
var out_dir := "ci-out/shots"


func _initialize() -> void:
	seed(3)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(10)
	world = main.world
	player = world.player
	# CI draws with the CPU, so the game runs at a tiny render scale between
	# shots, and each shot is drawn at 2x (see _shot).
	main.fixed_scale = 0.5
	main.fit_view()
	await _shot("01-title")
	main.start_game()
	# The shots show the whole kit; the playtest covers finding it.
	player.unlock_all()

	# Lamplighter's Row, the first lamp just lit.
	var lamp = world.level.get_node("Entities/Lamp1")
	await _tp(lamp.position.x + 60.0, 640.0, -1.0)
	world.light_lamp(lamp)
	await _frames(40)
	await _shot("02-lamp-lit")

	# A Communicant glinting: the moment to shoot.
	var e = world.level.get_node("Entities/Communicant2")
	await _tp(e.position.x - 90.0, 640.0, 1.0)
	for i in 400:
		if e.state == "windup" and e.t >= e.def.windup - e.def.parry + 0.04:
			break
		await physics_frame
	await _shot("03-glint")
	# The glint starts the parry lesson (time slows, a prompt shows); the rest
	# of the shots are without it.
	world.teaching = false
	world.end_lesson()

	# The Lantern form mid-swing in the undercroft, by the second lamp.
	var lamp2 = world.level.get_node("Entities/Lamp2")
	lamp2.light_up()
	player.form = "lantern"
	await _tp(lamp2.position.x + 100.0, lamp2.position.y, 1.0)
	await _frames(50)
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(10)
	await _shot("04-undercroft-lantern")

	# The veil and the canal crossing.
	player.form = "hook"
	await _tp(2650.0, 640.0, 1.0)
	await _frames(40)
	await _shot("05-veil")
	await _tp(1000.0, 640.0, 1.0)
	await _frames(40)
	await _shot("06-canal")

	# A Gorged Communicant beside your guttering tallow.
	var g = world.level.get_node("Entities/Communicant4")
	g.gorged = 240
	g.reset()
	world.pile = {"pos": Vector2(g.position.x - 40.0, 640.0), "amount": 180}
	world.fx.show_notice("A communicant has gorged itself on your tallow.")
	await _tp(g.position.x - 150.0, 640.0, 1.0)
	world.pile = {"pos": Vector2(g.position.x - 60.0, 640.0), "amount": 180}
	await _frames(30)
	await _shot("07-gorged")

	# Death.
	world.pile = {}
	Combat.kill_player(world)
	await _frames(50)
	await _shot("08-death")
	await _frames(150)

	# Resting at a lamp.
	world.tallow = 240
	await _tp(lamp.position.x - 10.0, 640.0)
	world.rest_at(lamp)
	await _frames(10)
	await _shot("09-lamp-menu")
	world.menu = {}
	player.to_move()

	# Debug hitboxes.
	world.show_hitboxes = true
	await _tp(e.position.x - 70.0, 640.0, 1.0)
	await _frames(30)
	await _shot("10-hitboxes")

	world.show_hitboxes = false

	# A shortcut gate in the undercroft, seen from the side it won't open from.
	var gate = world.level.get_node("Entities/Gate2")
	await _tp(gate.position.x - 70.0, gate.position.y, 1.0)
	await _frames(30)
	await _shot("11-gate")

	# Halfway up the chimney on the Climbing Irons.
	await _tp(44.0, 400.0, -1.0)
	player.velocity = Vector2(-60.0, 60.0)
	Input.action_press("move_left")
	await _frames(6)
	await _shot("12-chimney")
	Input.action_release("move_left")

	# The pause screen's map after a walk through most of the district.
	for x in range(0, 4800, 96):
		world.reveal(Vector2(x, 640.0))
	for x in range(2500, 4150, 96):
		world.reveal(Vector2(x, 896.0))
	for y in range(160, 640, 96):
		world.reveal(Vector2(64.0, y))
	await _tp(3100.0, 896.0, 1.0)
	main.set_paused(true)
	await _frames(4)
	await _shot("13-map")
	main.open_controls(main.pause_screen)
	await _shot("14-controls")
	main.close_controls()
	main.set_paused(false)

	print("screenshots written to ", out_dir)
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _tp(x: float, y: float, facing := 1.0) -> void:
	player.position = Vector2(x, y)
	player.velocity = Vector2.ZERO
	player.facing = facing
	player.to_move()
	player.iframes = 999.0
	world.snap_camera()
	await _frames(2)


## Draws the moment at 2x with the game held still, lets the 3D stage's
## temporal effects (fog, reflections) settle for a few frames, and saves it.
func _shot(name: String) -> void:
	# Invulnerable between shots, but not blinking in them (a step to clear
	# the blink before the game is held still).
	player.iframes = 0.0
	if not paused:
		await physics_frame
		await physics_frame
	player.modulate.a = 1.0 if player.state != "dead" else player.modulate.a
	var was_paused := paused
	paused = true
	main.fixed_scale = 2.0
	main.fit_view()
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	main.fixed_scale = 0.5
	main.fit_view()
	paused = was_paused
	player.iframes = 999.0
	print("saved ", name)
