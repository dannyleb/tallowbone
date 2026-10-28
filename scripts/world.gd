## The game in progress: the level, the Lamplighter, the night's enemies,
## and everything that ties them together (Tallow, lamps, levelling, death
## and respawn, the camera).
##
## Runs the simulation itself, one fixed step per physics tick, so the order
## of things is always the same and hit-stop can freeze it cleanly.
extends Node2D

const T = preload("res://scripts/tuning.gd")
const FxState = preload("res://scripts/fx_state.gd")
const Combat = preload("res://scripts/combat.gd")
const Tallow = preload("res://scripts/tallow.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Keys = preload("res://scripts/keys.gd")

const ACTIONS := [
	"move_left", "move_right", "move_up", "move_down", "jump", "attack", "transform", "shoot",
	"dash", "heal", "interact", "confirm", "back",
]

## False until the title screen is dismissed: the world draws but doesn't run.
var running := false
var show_hitboxes := false
## Lessons in the parry and the Visceral (see Tuning.LESSON). Tests turn
## them off.
var teaching := true
var learned := {"parry": false, "visceral": false}
## The lesson on now: { kind, enemy, text }, or empty.
var lesson := {}

var level
var player
var enemies: Array = []
var lamps: Array = []
var signs: Array = []
var pickups: Array = []
var gates: Array = []
var fx := FxState.new()

var tallow := 0
## { amount, t } for the "+40" under the Tallow count, or empty.
var gained := {}
## Your dropped tallow: { pos, amount }, or empty.
var pile := {}
var lost_tallow := 0
var dropped := false
var checkpoint = null
var level_no := 1
var stats := {"vitality": 0, "strength": 0, "steady": 0}
## The level-up menu while resting at a lamp: { index }, or empty.
var menu := {}
## The sign you're standing at, and the lamp prompt { pos, text }.
var sign_node = null
var prompt := {}
## The pistol's tracer: { from, to, t }, or empty.
var shot := {}
var hitstop := 0.0
var time := 0.0
var deaths := 0
var look := 0.0
var cam_center := Vector2.ZERO

## The map: one byte per tile, 1 once you've been near enough to see it.
var explored := PackedByteArray()
## Hints already given (so each shows once).
var hinted := {}

var _prev := {}
var _counted := {}

@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	level = $Level
	player = $Player
	player.world = self
	for e in level.members("enemies"):
		e.world = self
		enemies.append(e)
	lamps = level.members("lamps")
	signs = level.members("signs")
	pickups = level.members("pickups")
	gates = level.members("gates")
	explored.resize(level.size_tiles.x * level.size_tiles.y)
	for n in ["FxShaded", "FxOverlay", "FxGlow", "Weather"]:
		get_node(n).world = self
	player.position = level.player_start.position
	player.safe = player.position
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(level.size_px().x)
	camera.limit_bottom = int(level.size_px().y)
	snap_camera()


func level_cost() -> int:
	return roundi(T.LEVEL.base * pow(T.LEVEL.growth, level_no - 1))


func view_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func cam_top_left() -> Vector2:
	return cam_center - view_size() / 2.0


## Held and newly pressed actions this tick. A press counts once: when Godot
## reports it as just pressed, or when it's held now and wasn't last tick,
## whichever comes first (so a tap between two ticks is never lost and a
## held button never counts twice).
func read_input() -> Dictionary:
	var held := {}
	var pressed := {}
	for a in ACTIONS:
		var now := Input.is_action_pressed(a)
		var edge: bool = Input.is_action_just_pressed(a) or (now and not _prev.get(a, false))
		pressed[a] = edge and not _counted.get(a, false)
		_counted[a] = now and (pressed[a] or _counted.get(a, false))
		held[a] = now
	_prev = held
	return {"held": held, "pressed": pressed}


func _physics_process(delta: float) -> void:
	var input := read_input()
	if not running:
		return
	time += delta
	fx.update(delta)
	if not shot.is_empty():
		shot.t -= delta
		if shot.t <= 0.0:
			shot = {}
	if not gained.is_empty():
		gained.t += delta
		if gained.t > 1.6:
			gained = {}

	if not menu.is_empty():
		_update_menu(input.pressed)
		return
	player.buffer_input(input.pressed)
	if hitstop > 0.0:
		hitstop -= delta
		return

	if player.state != "rest":
		player.step(input, delta)
	for e in enemies:
		e.step(delta)
	Tallow.update(self)
	_update_pickups()
	_update_lamps_and_signs()
	_update_lesson()
	_update_hints()
	if Engine.get_physics_frames() % 6 == 0:
		reveal(player.position)

	if player.state == "dead":
		if not dropped and player.t >= 0.5:
			dropped = true
			Tallow.drop(self)
		if player.t >= 2.8:
			respawn()
	_update_camera(delta)


func _process(_delta: float) -> void:
	# Screen shake rides on top of the camera's own position.
	camera.offset = Vector2(randf() - 0.5, randf() - 0.5) * fx.shake


## Full health, vials and bullets, and the night's horrors back where they
## started. Happens when you rest at a lamp and when you die.
func refresh() -> void:
	player.refill()
	for e in enemies:
		e.reset()


## Slows time and prompts the first parry, then the first Visceral, until
## you've done each once.
func _update_lesson() -> void:
	if not lesson.is_empty():
		var e = lesson.enemy
		var over: bool = not e.alive or player.state == "dead" or not teaching
		if lesson.kind == "parry":
			if e.state == "stagger" or e.state == "held":
				learned.parry = true
				over = true
			elif not Combat.parryable(e):
				over = true
		elif player.state == "visceral":
			learned.visceral = true
			over = true
		elif e.state != "stagger":
			over = true
		if over:
			end_lesson()
		return
	if not teaching or player.state == "dead" or not player.has("pistol") or (learned.parry and learned.visceral):
		return
	for e in enemies:
		if not e.alive or absf(e.position.x - player.position.x) > T.LESSON.range or absf(e.position.y - player.position.y) > 60.0:
			continue
		if not learned.parry and Combat.parryable(e):
			_start_lesson("parry", e, "{shoot}   Shoot it now, as it glints")
			return
		if learned.parry and not learned.visceral and e.state == "stagger":
			_start_lesson("visceral", e, "{attack}   Strike to finish it")
			return


func _start_lesson(kind: String, e, text: String) -> void:
	lesson = {"kind": kind, "enemy": e, "text": text}
	Engine.time_scale = T.LESSON.slow


func end_lesson() -> void:
	lesson = {}
	Engine.time_scale = 1.0


func respawn() -> void:
	var at: Vector2 = checkpoint.position if checkpoint else level.player_start.position
	player.position = at
	player.velocity = Vector2.ZERO
	player.to_move()
	player.iframes = 1.0
	player.safe = at
	refresh()
	snap_camera()
	if lost_tallow > 0:
		fx.show_notice("%d tallow is lost for good." % lost_tallow)
	lost_tallow = 0


func light_lamp(lamp) -> void:
	lamp.light_up()
	checkpoint = lamp
	fx.show_banner("LAMP LIT", level.level_name, 2.6, "lamp")
	fx.burst(lamp.position + Vector2(0, -54), {"count": 30, "color": Color("ffcf7a"), "spread": 90.0, "up": 60.0, "gravity": -40.0, "glow": true})
	Sfx.play("lamp")


func rest_at(lamp) -> void:
	checkpoint = lamp
	fx.banner = {}
	player.state = "rest"
	player.velocity.x = 0.0
	refresh()
	menu = {"index": 0}


## Levelling up at a lamp: spend tallow on a stat.
func _update_menu(pressed: Dictionary) -> void:
	var n: int = T.STATS.size() + 1
	if pressed.move_up:
		menu.index = (menu.index + n - 1) % n
		Sfx.play("click")
	if pressed.move_down:
		menu.index = (menu.index + 1) % n
		Sfx.play("click")
	if pressed.back or (pressed.confirm and menu.index == T.STATS.size()):
		menu = {}
		player.to_move()
		for k in player.buf:
			player.buf[k] = 0.0
		return
	if not pressed.confirm:
		return
	var cost := level_cost()
	if tallow < cost:
		Sfx.play("deny")
		return
	var stat: Dictionary = T.STATS[menu.index]
	tallow -= cost
	level_no += 1
	stats[stat.id] += 1
	if stat.id == "vitality":
		player.max_hp += 12.0
		player.hp = player.max_hp
	elif stat.id == "steady":
		player.max_bullets += 2
		player.bullets = player.max_bullets
	Sfx.play("buy")


## What each find is called, and the line under its name. {tokens} become
## the keys for whatever you're holding.
const FINDS := {
	"vial": ["VIAL HOLDER", "Carry one more vial. Lamps refill them."],
	"bullets": ["BULLET POUCH", "Carry three more quicksilver rounds."],
	"quickstep": ["WATCHMAN'S BOOTS", "{dash} to quickstep. Nothing touches you mid-step."],
	"pistol": ["WATCH PISTOL", "{shoot} to fire. Shoot an enemy the instant it glints."],
	"lantern": ["LAMP OIL", "The Pole's lantern takes flame. Hold {attack} to turn it."],
	"irons": ["CLIMBING IRONS", "Press into a wall to cling. {jump} to kick off it."],
}


func _update_pickups() -> void:
	var r: Rect2 = player.body_rect()
	for it in pickups:
		if it.taken or absf(it.position.x - player.position.x) > 18.0 or it.position.y < r.position.y or it.position.y - 20.0 > r.end.y:
			continue
		it.take()
		match it.kind:
			"vial":
				player.max_vials += 1
				player.vials += 1
			"bullets":
				player.max_bullets += 3
				player.bullets = player.max_bullets
			_:
				player.abilities[it.kind] = true
		var find: Array = FINDS[it.kind]
		fx.show_banner(find[0], Keys.fill(find[1]), 3.4)
		fx.burst(it.position + Vector2(0, -12), {"count": 16, "color": Color("e8dfcf"), "spread": 80.0, "up": 80.0, "gravity": -50.0, "glow": true})
		Sfx.play("find" if it.kind in T.ABILITIES else "buy")


## One-time nudges, the first time each is useful.
func _update_hints() -> void:
	if player.state == "dead":
		return
	if not hinted.get("vial", false) and player.hp < player.max_hp * 0.5 and player.vials > 0:
		hinted.vial = true
		fx.show_notice(Keys.fill("{heal} drinks a vial."), 4.0)
	if not hinted.get("blood", false) and player.has("pistol") and player.bullets == 0:
		hinted.blood = true
		fx.show_notice(Keys.fill("Out of bullets: hold {shoot} to spend blood on more."), 4.5)


## Marks the tiles around a point as seen, for the map.
func reveal(at: Vector2) -> void:
	var w: int = level.size_tiles.x
	var h: int = level.size_tiles.y
	var c0 := floori(at.x / T.TILE)
	var r0 := floori(at.y / T.TILE)
	for r in range(maxi(0, r0 - 7), mini(h, r0 + 5)):
		for c in range(maxi(0, c0 - 11), mini(w, c0 + 12)):
			explored[r * w + c] = 1


func is_explored(cell: Vector2i) -> bool:
	var w: int = level.size_tiles.x
	if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= level.size_tiles.y:
		return false
	return explored[cell.y * w + cell.x] == 1


func _update_lamps_and_signs() -> void:
	prompt = {}
	var near_sign = null
	if player.state != "dead":
		for l in lamps:
			if absf(l.position.x - player.position.x) > T.NEAR or absf(l.position.y - player.position.y) > 40.0:
				continue
			prompt = {"pos": l.position + Vector2(0, -92), "text": "Rest" if l.lit else "Light the lamp"}
			if player.buf.interact > 0.0 and player.state == "move" and player.is_on_floor():
				player.buf.interact = 0.0
				if l.lit:
					rest_at(l)
				else:
					light_lamp(l)
		for g in gates:
			if g.open or absf(g.position.x - player.position.x) > T.NEAR + 6.0 or absf(g.position.y - player.position.y) > 40.0:
				continue
			if not g.reachable_from(player.position.x):
				prompt = {"pos": g.position + Vector2(0, -108), "text": "Barred from the other side", "key": false}
				continue
			prompt = {"pos": g.position + Vector2(0, -108), "text": "Lift the bar"}
			if player.buf.interact > 0.0 and player.state == "move" and player.is_on_floor():
				player.buf.interact = 0.0
				open_gate(g)
		for s in signs:
			if absf(s.position.x - player.position.x) < T.NEAR * 1.6 and absf(s.position.y - player.position.y) < 60.0:
				near_sign = s
	if near_sign != sign_node:
		if sign_node:
			sign_node.set_near(false)
		if near_sign:
			near_sign.set_near(true)
		sign_node = near_sign


func open_gate(g) -> void:
	g.open_gate()
	fx.show_notice("A shortcut opens. The way back is shorter now.", 3.6)
	fx.add_shake(3.0)
	Sfx.play("gate")


func _update_camera(delta: float) -> void:
	look += (player.facing * 50.0 - look) * minf(1.0, delta * 2.5)
	var target := Vector2(player.position.x + look, player.position.y - T.PLAYER.h / 2.0 - view_size().y * 0.08)
	cam_center.x += (target.x - cam_center.x) * minf(1.0, delta * 7.0)
	cam_center.y += (target.y - cam_center.y) * minf(1.0, delta * (9.0 if player.velocity.y > 300.0 else 5.0))
	_clamp_camera()


func snap_camera() -> void:
	look = player.facing * 50.0
	cam_center = Vector2(player.position.x + look, player.position.y - T.PLAYER.h / 2.0 - view_size().y * 0.08)
	_clamp_camera()


func _clamp_camera() -> void:
	var half := view_size() / 2.0
	var size: Vector2 = level.size_px()
	cam_center.x = clampf(cam_center.x, half.x, maxf(half.x, size.x - half.x))
	cam_center.y = clampf(cam_center.y, half.y, maxf(half.y, size.y - half.y))
	camera.position = cam_center
