## Damage, Rally, parries and deaths: what happens when something lands.
## Static helpers that act on the World.
extends RefCounted

const T = preload("res://scripts/tuning.gd")
const Sfx = preload("res://scripts/sfx.gd")

const BLOOD_COLOR := Color("8e1b1e")


## Can this enemy be parried right now? Only in the last stretch of its
## wind-up, which is when it glints.
static func parryable(e) -> bool:
	return e.alive and e.state == "windup" and e.t >= e.def.windup - e.def.parry


static func hurt_player(world, damage: float, from_x: float) -> bool:
	var p = world.player
	if p.state == "dead" or p.state == "visceral" or p.iframes > 0.0:
		return false
	if p.state == "dash" and p.t < T.DASH.iframes:
		return false

	p.hp -= damage
	# What a hit takes, Rally can win back, up to the health you had.
	p.rally = minf(p.rally + damage, p.max_hp - maxf(0.0, p.hp))
	p.rally_hold = T.RALLY.hold
	world.hitstop = maxf(world.hitstop, T.HITSTOP.hurt)
	world.fx.add_shake(5.0)
	world.fx.burst(p.position + Vector2(0, -26), {"count": 14, "color": BLOOD_COLOR, "dir": signf(p.position.x - from_x)})
	Sfx.play("hurt")
	if p.hp <= 0.0:
		kill_player(world)
		return true

	p.state = "hurt"
	p.t = 0.0
	p.iframes = T.PLAYER.iframes_hurt
	var dir := signf(p.position.x - from_x)
	if dir == 0.0:
		dir = -p.facing
	p.velocity = Vector2(dir * T.PLAYER.knockback_x, -T.PLAYER.knockback_y)
	return true


static func kill_player(world) -> void:
	var p = world.player
	p.hp = 0.0
	p.rally = 0.0
	p.state = "dead"
	p.t = 0.0
	p.velocity.x *= 0.3
	world.dropped = false
	world.deaths += 1
	Sfx.play("death")
	world.fx.show_banner("THE LIGHT GOES OUT", "", 2.6, "death")


## visceral: a Visceral finisher (an enemy that survives one is knocked
## down rather than flinching).
static func damage_enemy(world, e, damage: float, dir: float, visceral := false) -> void:
	e.hp -= damage
	e.flash = 0.1
	var at: Vector2 = e.position + Vector2(0, -e.def.h * 0.6)
	world.fx.burst(at, {"count": 40 if visceral else 10, "color": BLOOD_COLOR, "dir": dir, "spread": 260.0 if visceral else 160.0})
	if e.hp <= 0.0:
		kill_enemy(world, e)
		return
	if visceral:
		e.state = "recover"
		e.t = 0.0
		e.velocity.x = dir * 160.0
		return
	# Gorged enemies never flinch, and nothing flinches out of its own
	# attack: once it winds up, dodge it or parry it.
	var armoured: bool = e.gorged > 0 or e.state in ["windup", "strike", "stagger"]
	if not armoured:
		e.state = "flinch"
		e.t = 0.0
		e.velocity.x = dir * 120.0


static func kill_enemy(world, e) -> void:
	e.die()
	var at: Vector2 = e.position + Vector2(0, -e.def.h / 2.0)
	var gain: int = e.def.tallow
	if e.gorged > 0:
		# Your tallow back, and a little of what it had of its own.
		gain += roundi(e.gorged * 1.1)
		e.gorged = 0
		world.fx.show_banner("TALLOW RECLAIMED", "", 2.0, "tallow")
	world.tallow += gain
	world.gained = {"amount": gain, "t": 0.0}
	world.fx.add_motes(at, mini(24, 4 + roundi(gain / 10.0)))
	world.fx.burst(at, {"count": 18, "color": BLOOD_COLOR, "spread": 200.0})
	Sfx.play("tallow")


static func stagger_enemy(world, e) -> void:
	e.state = "stagger"
	e.t = 0.0
	e.velocity.x = 0.0
	world.hitstop = maxf(world.hitstop, T.HITSTOP.parry)
	world.fx.add_shake(4.0)
	world.fx.burst(e.position + Vector2(0, -e.def.h * 0.6), {"count": 16, "color": Color("fff6d8"), "spread": 220.0, "up": 40.0, "life": 0.4, "size": 2.0, "gravity": 200.0, "glow": true})
	Sfx.play("parry")
