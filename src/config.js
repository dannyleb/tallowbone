export const GAME_TITLE = "Tallowbone";

// World units are pixels at the reference view height. One tile is TILE
// across; the player is a little over a tile tall.
export const TILE = 32;

// height: world px shown top to bottom; the width follows the screen's
// aspect ratio, clamped so ultra-wide or portrait screens don't show too
// much or too little of a room.
export const VIEW = { height: 360, minWidth: 480, maxWidth: 720 };

// The simulation runs at a fixed 60 steps a second, whatever the display.
export const STEP = 1 / 60;

export const GRAVITY = 2200;
export const MAX_FALL = 900;

// jump: launch speed (about 3.3 tiles high). jumpCut: how much upward speed
// is kept when the button is let go early. coyote / jumpBuffer: grace
// windows (seconds) for jumping just after leaving a ledge or just before
// landing.
export const PLAYER = {
  w: 16, h: 42,
  run: 230, accelGround: 2600, accelAir: 1700, friction: 3000,
  jump: 680, jumpCut: 0.45, coyote: 0.1, jumpBuffer: 0.12,
  maxHp: 100,
  vials: 5, vialHeal: 45, healTime: 0.6, healAt: 0.35,
  bullets: 12,
  iframesHurt: 0.6, hurtTime: 0.25, knockback: { x: 170, y: 260 },
};

// Quickstep: a short dash that can't be hit for most of its length and
// passes through enemies. One per airtime.
export const DASH = { time: 0.17, speed: 480, iframes: 0.15, cooldown: 0.32 };

// Rally: health lost to a hit hangs on as "rally" for `hold` seconds, then
// drains at `decay` HP a second. Landing melee hits wins back `regain` x the
// damage dealt, up to whatever rally is left.
export const RALLY = { hold: 0.6, decay: 12, regain: 0.6 };

// Blood bullets: hold the button for `time` seconds to cut yourself for
// `cost` HP and load `bullets` more. The HP spent becomes rally, so an
// aggressive player can win it straight back.
export const BLOOD = { time: 0.5, cost: 20, bullets: 4 };

// The pistol is hitscan. Its damage is small; its job is the parry.
export const GUN = { range: 320, damage: 8, startup: 0.08, recovery: 0.26, y: 26 };

// Visceral: strike a staggered (parried) enemy within `reach`. Damage lands
// `at` seconds in; the player can't be touched for the whole `time`.
export const VISCERAL = { reach: 54, time: 0.6, at: 0.22, damage: 110 };

// Freeze-frames on impact, in seconds. Small numbers, big feel.
export const HITSTOP = { hit: 0.045, parry: 0.14, visceral: 0.16, hurt: 0.08 };

// Falling into the canal: this much damage, then back to the last safe
// footing.
export const HAZARD_DAMAGE = 20;

// Tallow pile: how close (px) the player or an enemy has to come to pick
// it up. An enemy that does becomes Gorged: tougher, hits harder, and
// carries your tallow until you kill it.
export const PILE = { reach: 22 };
export const GORGED = { hp: 1.6, damage: 1.3, speed: 1.1 };

// Levelling at a lamp. Level n -> n+1 costs base x growth^(n-1) tallow.
export const LEVEL = { base: 60, growth: 1.12 };
export const STATS = [
  { id: "vitality", label: "Vitality", note: "+12 max health" },
  { id: "strength", label: "Strength", note: "+8% melee damage" },
  { id: "steady", label: "Steady Hand", note: "+2 bullets, +15% shot damage" },
];

// How far (px) from a lamp or sign the player has to be to use or read it.
export const NEAR = 30;
