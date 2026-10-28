import { GORGED, PILE } from "./config.js";
import { banner, burst, notice } from "./fx.js";
import { sfx } from "./sfx.js";

// Tallow is the currency (the souls). Die and it spills where you fell as
// a ghost-light, the pile. Walk back into it to reclaim it. Let an enemy
// walk through it first and the enemy takes it and becomes Gorged. Die
// again before you get it back, from the ground or from the Gorged thing,
// and it's gone for good.

// Called partway through the death animation.
export function dropTallow(game) {
  const p = game.player;
  let lost = 0;
  if (game.pile) { lost += game.pile.amount; game.pile = null; }
  for (const s of game.level.spawns.enemies) if (s.gorged) { lost += s.gorged; s.gorged = 0; }
  game.lostTallow = lost;

  if (game.tallow > 0) {
    // Where you fell, or your last firm footing if you died in the air or
    // in the canal.
    const at = p.onGround && !p.inHazard ? { x: p.x + p.w / 2, y: p.y + p.h } : p.safe;
    game.pile = { x: at.x, y: at.y, amount: game.tallow };
    game.tallow = 0;
  }
}

export function updatePile(game) {
  const pile = game.pile, p = game.player;
  // Nothing touches it until you're back on your feet; the night resets
  // first, then whatever wanders through it takes it.
  if (!pile || p.state === "dead") return;
  const near = (b) => Math.abs(b.x + b.w / 2 - pile.x) < PILE.reach + b.w / 2 && b.y < pile.y && b.y + b.h > pile.y - 30;

  if (near(p)) {
    game.tallow += pile.amount;
    game.gained = { amount: pile.amount, t: 0 };
    game.pile = null;
    burst(game.fx, pile.x, pile.y - 14, { count: 24, color: "#f0bd62", spread: 120, up: 120, gravity: -100, glow: true });
    banner(game.fx, "TALLOW RECLAIMED", "", 2, "tallow");
    sfx.tallow();
    return;
  }
  const taker = game.enemies.find((e) => e.alive && !e.gorged && near(e));
  if (taker) gorge(game, taker, pile.amount);
}

function gorge(game, e, amount) {
  e.gorged = e.spawn.gorged = amount;
  e.maxHp = e.hp = Math.round(e.def.hp * GORGED.hp);
  game.pile = null;
  burst(game.fx, e.x + e.w / 2, e.y + e.h / 2, { count: 30, color: "#ff6a3d", spread: 140, up: 60, gravity: -60, glow: true });
  notice(game.fx, `A ${e.def.name.toLowerCase()} has gorged itself on your tallow.`);
  sfx.gorge();
}
