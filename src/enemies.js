import { GORGED, GRAVITY, MAX_FALL, TILE } from "./config.js";
import { hurtPlayer, killEnemy } from "./combat.js";
import { floorAhead, lineOfSight, moveBody, overlaps } from "./physics.js";
import { sfx } from "./sfx.js";

// Enemy types. range: how close (edge to edge, px) the player must be for
// it to start an attack. windup / strike / recover: attack timings (s);
// the last `parry` seconds of the wind-up are the parry window, and that's
// when it glints. hit: the attack's hitbox, from its front edge out to
// `reach` (body: true also covers its own body, for lunges).
export const ENEMIES = {
  communicant: {
    name: "Communicant", w: 20, h: 44, hp: 60, speed: 62, aggro: 260, damage: 22, tallow: 40,
    range: 40, windup: 0.62, parry: 0.28, strike: 0.14, recover: 0.7, cooldown: 0.4, step: 90,
    hit: { reach: 52, top: -42, bottom: -6 },
  },
  hound: {
    name: "Hound", w: 34, h: 22, hp: 42, speed: 170, aggro: 300, damage: 18, tallow: 30,
    range: 110, windup: 0.45, parry: 0.24, strike: 0.3, recover: 0.65, cooldown: 0.6, lunge: 430,
    hit: { reach: 10, top: -22, bottom: 0, body: true },
  },
};

// A spawn record ({ type, x, y, gorged }) stays with the level; enemies are
// rebuilt from it whenever you rest or die. `gorged` lives on the spawn so
// an enemy holding your tallow still holds it after a reset.
export function createEnemy(spawn) {
  const def = ENEMIES[spawn.type];
  const hp = Math.round(def.hp * (spawn.gorged ? GORGED.hp : 1));
  return {
    type: spawn.type, def, spawn,
    x: spawn.x - def.w / 2, y: spawn.y - def.h, w: def.w, h: def.h,
    vx: 0, vy: 0, facing: -1, onGround: false,
    hp, maxHp: hp, gorged: spawn.gorged,
    state: "idle", t: 0, cooldown: 0, lost: 0, wanderT: 0, wanderDir: 0,
    hitDone: false, glinted: false, flash: 0, alive: true, deadT: 0, runT: 0,
  };
}

export function strikeBox(e) {
  const h = e.def.hit, front = e.facing > 0 ? e.x + e.w : e.x;
  let x = e.facing > 0 ? front : front - h.reach, w = h.reach;
  if (h.body) { x = Math.min(x, e.x); w = h.reach + e.w; }
  return { x, y: e.y + e.h + h.top, w, h: h.bottom - h.top };
}

export function updateEnemy(game, e, dt) {
  if (!e.alive) { e.deadT += dt; return; }
  const { level, player: p } = game, d = e.def;
  e.t += dt;
  e.cooldown -= dt;
  e.flash = Math.max(0, e.flash - dt);

  const ecx = e.x + e.w / 2, pcx = p.x + p.w / 2;
  const dx = pcx - ecx, dy = p.y + p.h - (e.y + e.h);
  const gap = Math.abs(dx) - (e.w + p.w) / 2;
  const speed = d.speed * (e.gorged ? GORGED.speed : 1);
  const sees = p.state !== "dead" && Math.abs(dx) < d.aggro && Math.abs(dy) < 120 &&
    lineOfSight(level, ecx, e.y + 8, pcx, p.y + 8);
  let walk = 0;

  switch (e.state) {
    case "idle":
      if (sees) { e.state = "chase"; e.t = 0; break; }
      // Shuffle about near where it spawned.
      if ((e.wanderT -= dt) <= 0) {
        const home = e.spawn.x - ecx;
        e.wanderDir = Math.abs(home) > 48 ? Math.sign(home) : [-1, 0, 0, 1][Math.floor(Math.random() * 4)];
        e.wanderT = 1 + Math.random() * 1.5;
        if (e.wanderDir) e.facing = e.wanderDir;
      }
      walk = e.wanderDir * 0.35;
      break;
    case "chase":
      e.facing = Math.sign(dx) || e.facing;
      e.lost = sees ? 0 : e.lost + dt;
      if (e.lost > 2.5 || p.state === "dead") { e.state = "idle"; e.t = 0; break; }
      if (gap < d.range && Math.abs(dy) < 48 && e.cooldown <= 0 && e.onGround) {
        e.state = "windup"; e.t = 0; e.glinted = false;
        break;
      }
      walk = gap > 4 ? e.facing : 0;
      break;
    case "windup":
      // Tracks you for the first half, then it's committed.
      if (e.t < d.windup * 0.5) e.facing = Math.sign(dx) || e.facing;
      if (!e.glinted && e.t >= d.windup - d.parry) {
        e.glinted = true;
        if (Math.abs(dx) < 420) sfx.glint();
      }
      if (e.t >= d.windup) {
        e.state = "strike"; e.t = 0; e.hitDone = false;
        if (d.lunge) { e.vx = e.facing * d.lunge; e.vy = -160; }
        else e.vx = e.facing * d.step;
      }
      break;
    case "strike":
      if (!e.hitDone && overlaps(strikeBox(e), p)) {
        if (hurtPlayer(game, Math.round(d.damage * (e.gorged ? GORGED.damage : 1)), ecx)) e.hitDone = true;
      }
      if (e.t >= d.strike && (!d.lunge || e.onGround)) { e.state = "recover"; e.t = 0; }
      break;
    case "recover":
      if (e.t >= d.recover) { e.state = "chase"; e.t = 0; e.cooldown = d.cooldown; }
      break;
    case "flinch":
      if (e.t >= 0.22) { e.state = "chase"; e.t = 0; }
      break;
    case "stagger":
      if (e.t >= 1.6) { e.state = "chase"; e.t = 0; e.cooldown = 0.3; }
      break;
    case "held": // in the middle of a Visceral attack
      e.vx = 0;
      break;
  }

  if (walk !== 0 && (!floorAhead(e, level, Math.sign(walk)) || wallAhead(e, level, Math.sign(walk)))) {
    if (e.state === "idle") e.wanderDir = -e.wanderDir;
    walk = 0;
  }
  if (e.state === "idle" || e.state === "chase") {
    e.vx = walk * speed;
    if (walk && e.onGround) e.runT += dt * Math.abs(walk);
  } else if (!(e.state === "strike" && d.lunge)) {
    e.vx = approach(e.vx, 0, 900 * dt);
  }
  e.vy = Math.min(e.vy + GRAVITY * dt, MAX_FALL);
  moveBody(e, level, dt);

  // The canal takes anything that falls in, and what it carried comes to you.
  if (level.hazard(Math.floor((e.x + e.w / 2) / TILE), Math.floor((e.y + e.h - 4) / TILE))) killEnemy(game, e);
}

function wallAhead(e, level, dir) {
  const c = Math.floor((dir > 0 ? e.x + e.w + 2 : e.x - 2) / TILE);
  return level.solid(c, Math.floor((e.y + e.h - 4) / TILE)) || level.solid(c, Math.floor(e.y / TILE));
}

export const approach = (v, target, step) => (v < target ? Math.min(v + step, target) : Math.max(v - step, target));
