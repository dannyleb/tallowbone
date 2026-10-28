import { HITSTOP, PLAYER, RALLY, DASH } from "./config.js";
import { banner, burst, motes, shake } from "./fx.js";
import { sfx } from "./sfx.js";

// Can this enemy be parried right now? Only in the last stretch of its
// wind-up, which is when it glints.
export const parryable = (e) => e.alive && e.state === "windup" && e.t >= e.def.windup - e.def.parry;

export function hurtPlayer(game, damage, fromX) {
  const p = game.player;
  if (p.state === "dead" || p.state === "visceral" || p.iframes > 0) return false;
  if (p.state === "dash" && p.t < DASH.iframes) return false;

  p.hp -= damage;
  // What a hit takes, Rally can win back, up to the health you had.
  p.rally = Math.min(p.rally + damage, p.maxHp - Math.max(0, p.hp));
  p.rallyHold = RALLY.hold;
  game.hitstop = Math.max(game.hitstop, HITSTOP.hurt);
  shake(game.fx, 5);
  burst(game.fx, p.x + p.w / 2, p.y + 16, { count: 14, color: "#8e1b1e", dir: Math.sign(p.x - fromX) });
  sfx.hurt();
  if (p.hp <= 0) { killPlayer(game); return true; }

  p.state = "hurt";
  p.t = 0;
  p.iframes = PLAYER.iframesHurt;
  const dir = Math.sign(p.x + p.w / 2 - fromX) || -p.facing;
  p.vx = dir * PLAYER.knockback.x;
  p.vy = -PLAYER.knockback.y;
  return true;
}

export function killPlayer(game) {
  const p = game.player;
  p.hp = 0;
  p.rally = 0;
  p.state = "dead";
  p.t = 0;
  p.vx *= 0.3;
  game.dropped = false;
  game.deaths++;
  sfx.death();
  banner(game.fx, "THE LIGHT GOES OUT", "", 2.6, "death");
}

// opts.visceral: a Visceral finisher (an enemy that survives one is
// knocked down rather than flinching).
export function damageEnemy(game, e, damage, dir, { visceral = false } = {}) {
  e.hp -= damage;
  e.flash = 0.1;
  const cx = e.x + e.w / 2, cy = e.y + e.h * 0.4;
  burst(game.fx, cx, cy, { count: visceral ? 40 : 10, color: "#8e1b1e", dir, spread: visceral ? 260 : 160 });
  if (e.hp <= 0) { killEnemy(game, e); return; }

  if (visceral) { e.state = "recover"; e.t = 0; e.vx = dir * 160; return; }
  // Gorged enemies never flinch, and nothing flinches out of its own
  // attack: once it winds up, dodge it or parry it.
  const armoured = e.gorged || e.state === "windup" || e.state === "strike" || e.state === "stagger";
  if (!armoured) { e.state = "flinch"; e.t = 0; e.vx = dir * 120; }
}

export function killEnemy(game, e) {
  e.alive = false;
  e.state = "dead";
  e.deadT = 0;
  const cx = e.x + e.w / 2, cy = e.y + e.h / 2;
  let gain = e.def.tallow;
  if (e.gorged) {
    // Your tallow back, and a little of what it had of its own.
    gain += Math.round(e.gorged * 1.1);
    e.spawn.gorged = 0;
    banner(game.fx, "TALLOW RECLAIMED", "", 2, "tallow");
  }
  game.tallow += gain;
  game.gained = { amount: gain, t: 0 };
  motes(game.fx, cx, cy, Math.min(24, 4 + Math.round(gain / 10)));
  burst(game.fx, cx, cy, { count: 18, color: "#8e1b1e", spread: 200 });
  sfx.tallow();
}

export function staggerEnemy(game, e) {
  e.state = "stagger";
  e.t = 0;
  e.vx = 0;
  game.hitstop = Math.max(game.hitstop, HITSTOP.parry);
  shake(game.fx, 4);
  const cx = e.x + e.w / 2, cy = e.y + e.h * 0.4;
  burst(game.fx, cx, cy, { count: 16, color: "#fff6d8", spread: 220, up: 40, life: 0.4, size: 2, gravity: 200, glow: true });
  sfx.parry();
}
