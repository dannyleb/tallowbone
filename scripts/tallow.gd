## Tallow is the currency (the souls). Die and it spills where you fell as a
## ghost-light, the pile. Walk back into it to reclaim it. Let an enemy walk
## through it first and the enemy takes it and becomes Gorged. Die again
## before you get it back, from the ground or from the Gorged thing, and
## it's gone for good.
extends RefCounted

const T = preload("res://scripts/tuning.gd")
const Sfx = preload("res://scripts/sfx.gd")


## Called partway through the death animation.
static func drop(world) -> void:
	var p = world.player
	var lost := 0
	if not world.pile.is_empty():
		lost += world.pile.amount
		world.pile = {}
	for e in world.enemies:
		if e.gorged > 0:
			lost += e.gorged
			e.gorged = 0
	world.lost_tallow = lost

	if world.tallow > 0:
		# Where you fell, or your last firm footing if you died in the air
		# or in the canal.
		var at: Vector2 = p.position if p.is_on_floor() and not p.in_hazard else p.safe
		world.pile = {"pos": at, "amount": world.tallow}
		world.tallow = 0


static func update(world) -> void:
	var p = world.player
	# Nothing touches it until you're back on your feet; the night resets
	# first, then whatever wanders through it takes it.
	if world.pile.is_empty() or p.state == "dead":
		return
	var pile: Dictionary = world.pile
	if _near(p.body_rect(), pile.pos):
		world.tallow += pile.amount
		world.gained = {"amount": pile.amount, "t": 0.0}
		world.pile = {}
		world.fx.burst(pile.pos + Vector2(0, -14), {"count": 24, "color": Color("f0bd62"), "spread": 120.0, "up": 120.0, "gravity": -100.0, "glow": true})
		world.fx.show_banner("TALLOW RECLAIMED", "", 2.0, "tallow")
		Sfx.play("tallow")
		return
	for e in world.enemies:
		if e.alive and e.gorged == 0 and _near(e.body_rect(), pile.pos):
			_gorge(world, e, pile.amount)
			return


static func _near(r: Rect2, at: Vector2) -> bool:
	return absf(r.get_center().x - at.x) < T.PILE_REACH + r.size.x / 2.0 and r.position.y < at.y and r.end.y > at.y - 30.0


static func _gorge(world, e, amount: int) -> void:
	e.gorged = amount
	e.max_hp = roundf(e.def.hp * T.GORGED.hp)
	e.hp = e.max_hp
	world.pile = {}
	world.fx.burst(e.position + Vector2(0, -e.def.h / 2.0), {"count": 30, "color": Color("ff6a3d"), "spread": 140.0, "up": 60.0, "gravity": -60.0, "glow": true})
	world.fx.show_notice("A %s has gorged itself on your tallow." % String(e.def.name).to_lower())
	Sfx.play("gorge")
