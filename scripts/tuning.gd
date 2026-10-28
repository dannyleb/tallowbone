## Every number that shapes how Tallowbone plays, in one place.
##
## World units are pixels at the 640x360 base resolution; one tile is TILE
## across. Times are seconds, speeds px/s. An actor's position is the middle
## of its feet.
extends RefCounted

const TILE := 32
const GRAVITY := 2200.0
const MAX_FALL := 900.0

## jump: launch speed (about 3.3 tiles high). jump_cut: how much upward
## speed is kept when the button is let go early. coyote / jump_buffer:
## grace windows for jumping just after leaving a ledge or just before
## landing.
const PLAYER := {
	"w": 16.0, "h": 42.0,
	"run": 230.0, "accel_ground": 2600.0, "accel_air": 1700.0, "friction": 3000.0,
	"jump": 680.0, "jump_cut": 0.45, "coyote": 0.1, "jump_buffer": 0.12,
	"max_hp": 100.0,
	"vials": 5, "vial_heal": 45.0, "heal_time": 0.6, "heal_at": 0.35,
	"bullets": 12,
	"iframes_hurt": 0.6, "hurt_time": 0.25, "knockback_x": 170.0, "knockback_y": 260.0,
}

## Quickstep: a short dash that can't be hit for most of its length and
## passes through enemies. One per airtime.
const DASH := {"time": 0.17, "speed": 480.0, "iframes": 0.15, "cooldown": 0.32}

## Rally: health lost to a hit hangs on as "rally" for `hold`, then drains
## at `decay` HP a second. Landing melee hits wins back `regain` x the
## damage dealt, up to whatever rally is left.
const RALLY := {"hold": 0.6, "decay": 12.0, "regain": 0.6}

## Blood bullets: hold for `time` to cut yourself for `cost` HP and load
## `bullets` more. The HP spent becomes rally, so you can win it back.
const BLOOD := {"time": 0.5, "cost": 20.0, "bullets": 4}

## The pistol is hitscan. Its damage is small; its job is the parry.
## y: height of the shot above the feet.
const GUN := {"range": 320.0, "damage": 8.0, "startup": 0.08, "recovery": 0.26, "y": 26.0}

## Visceral: strike a staggered (parried) enemy within `reach`. Damage lands
## `at` seconds in; you can't be touched for the whole `time`.
const VISCERAL := {"reach": 54.0, "time": 0.6, "at": 0.22, "damage": 110.0}

## Freeze-frames on impact. Small numbers, big feel.
const HITSTOP := {"hit": 0.045, "parry": 0.14, "visceral": 0.16, "hurt": 0.08}

## Falling into the canal: this much damage, then back to firm footing.
const HAZARD_DAMAGE := 20.0

## Tallow pile: how close (px) the player or an enemy has to come to pick
## it up. An enemy that does becomes Gorged: tougher, hits harder, never
## flinches, and carries your tallow until you kill it.
const PILE_REACH := 22.0
const GORGED := {"hp": 1.6, "damage": 1.3, "speed": 1.1}

## Levelling at a lamp. Level n -> n+1 costs base x growth^(n-1) tallow.
const LEVEL := {"base": 60.0, "growth": 1.12}
const STATS := [
	{"id": "vitality", "label": "Vitality", "note": "+12 max health"},
	{"id": "strength", "label": "Strength", "note": "+8% melee damage"},
	{"id": "steady", "label": "Steady Hand", "note": "+2 bullets, +15% shot damage"},
]

## How far (px) from a lamp or sign you have to be to use or read it.
const NEAR := 30.0

## Trick Arms. Every weapon has two forms with their own movesets; turning
## it mid-combo is a trick attack that lands in the other form. Each Arm's
## second form is also a key to the map: the Lantern burns veils.
##
## The hitbox runs from your front edge out to `reach`, and from `top` to
## `bottom` px relative to the feet (negative is up). lunge: forward speed
## on the first active frame, ground only. light: radius (px) of the light
## the form throws around you.
const ARMS := {
	"pole": {
		"name": "Lamplighter's Pole",
		"forms": {
			"hook": {
				"label": "Hook", "light": 70.0, "burns": false,
				"combo": [
					{"damage": 14.0, "reach": 44.0, "top": -38.0, "bottom": -8.0, "startup": 0.07, "active": 0.08, "recovery": 0.17, "lunge": 70.0},
					{"damage": 14.0, "reach": 44.0, "top": -38.0, "bottom": -8.0, "startup": 0.07, "active": 0.08, "recovery": 0.17, "lunge": 70.0},
					{"damage": 22.0, "reach": 52.0, "top": -44.0, "bottom": -4.0, "startup": 0.11, "active": 0.09, "recovery": 0.26, "lunge": 120.0},
				],
				"trick": {"damage": 28.0, "reach": 74.0, "top": -64.0, "bottom": 0.0, "startup": 0.1, "active": 0.12, "recovery": 0.28, "lunge": 60.0, "to": "lantern"},
			},
			"lantern": {
				"label": "Lantern", "light": 150.0, "burns": true,
				"combo": [
					{"damage": 26.0, "reach": 78.0, "top": -64.0, "bottom": 4.0, "startup": 0.16, "active": 0.12, "recovery": 0.3, "lunge": 40.0},
					{"damage": 34.0, "reach": 84.0, "top": -70.0, "bottom": 4.0, "startup": 0.2, "active": 0.12, "recovery": 0.36, "lunge": 50.0},
				],
				"trick": {"damage": 30.0, "reach": 50.0, "top": -44.0, "bottom": -4.0, "startup": 0.08, "active": 0.09, "recovery": 0.22, "lunge": 140.0, "to": "hook"},
			},
		},
	},
}
## Turning without attacking: a short beat where you can't strike.
const TRANSFORM_TIME := 0.22

## Enemy types. range: how close (edge to edge, px) you must be for it to
## start an attack. windup / strike / recover: attack timings; the last
## `parry` seconds of the wind-up are the parry window, and that's when it
## glints. hit: the attack's hitbox from its front edge out to `reach`
## (body: also covers its own body, for lunges).
const ENEMIES := {
	"communicant": {
		"name": "Communicant", "w": 20.0, "h": 44.0, "hp": 60.0, "speed": 62.0, "aggro": 260.0,
		"damage": 22.0, "tallow": 40,
		"range": 40.0, "windup": 0.62, "parry": 0.28, "strike": 0.14, "recover": 0.7, "cooldown": 0.4,
		"step": 90.0, "lunge": 0.0,
		"hit": {"reach": 52.0, "top": -42.0, "bottom": -6.0, "body": false},
	},
	"hound": {
		"name": "Hound", "w": 34.0, "h": 22.0, "hp": 42.0, "speed": 170.0, "aggro": 300.0,
		"damage": 18.0, "tallow": 30,
		"range": 110.0, "windup": 0.45, "parry": 0.24, "strike": 0.3, "recover": 0.65, "cooldown": 0.6,
		"step": 0.0, "lunge": 430.0,
		"hit": {"reach": 10.0, "top": -22.0, "bottom": 0.0, "body": true},
	},
}
