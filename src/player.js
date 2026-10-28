import { ARMS, TRANSFORM_TIME } from "./arms.js";
import { BLOOD, DASH, GRAVITY, GUN, HAZARD_DAMAGE, HITSTOP, MAX_FALL, PLAYER, RALLY, TILE, VISCERAL } from "./config.js";
import { damageEnemy, killPlayer, parryable, staggerEnemy } from "./combat.js";
import { approach } from "./enemies.js";
import { burst, shake } from "./fx.js";
import { moveBody, overlaps, rayLength } from "./physics.js";
import { sfx } from "./sfx.js";

// The Lamplighter. One state at a time ("move" is free movement; the rest
// are committed actions with their own timers), with short input buffers
// so a press made a beat early still counts.
export function createPlayer(spawn) {
  return {
    x: spawn.x - PLAYER.w / 2, y: spawn.y - PLAYER.h, w: PLAYER.w, h: PLAYER.h,
    vx: 0, vy: 0, facing: 1, onGround: false, jumping: false,
    hp: PLAYER.maxHp, maxHp: PLAYER.maxHp, rally: 0, rallyHold: 0,
    vials: PLAYER.vials, maxVials: PLAYER.vials, bullets: PLAYER.bullets, maxBullets: PLAYER.bullets,
    arm: "pole", form: "hook",
    state: "move", t: 0,
    attack: null, kind: null, combo: 0, hitSet: null, lunged: false, done: false, target: null,
    buf: { jump: 0, attack: 0, transform: 0, shoot: 0, dash: 0, heal: 0, interact: 0 },
    coyote: 0, iframes: 0, dashCd: 0, dashDir: 1, airDash: true, dropT: 0,
    safe: { x: spawn.x, y: spawn.y }, inHazard: false, runT: 0,
  };
}

export const currentForm = (p) => ARMS[p.arm].forms[p.form];

const BUFFER = { jump: PLAYER.jumpBuffer, attack: 0.2, transform: 0.2, shoot: 0.15, dash: 0.12, heal: 0.12, interact: 0.12 };

// Presses are buffered even during hit-stop, so nothing pressed in a
// freeze-frame is lost.
export function bufferInput(p, pressed) {
  for (const k in BUFFER) if (pressed[k]) p.buf[k] = BUFFER[k];
}

export function attackBox(p, a) {
  const front = p.facing > 0 ? p.x + p.w : p.x;
  return { x: p.facing > 0 ? front : front - a.reach, y: p.y + p.h + a.top, w: a.reach, h: a.bottom - a.top };
}

export function updatePlayer(game, input, dt) {
  const p = game.player, { held } = input;
  p.t += dt;
  for (const k in p.buf) p.buf[k] = Math.max(0, p.buf[k] - dt);
  p.coyote = Math.max(0, p.coyote - dt);
  p.iframes = Math.max(0, p.iframes - dt);
  p.dashCd = Math.max(0, p.dashCd - dt);
  p.dropT = Math.max(0, p.dropT - dt);
  if (p.rallyHold > 0) p.rallyHold -= dt;
  else p.rally = Math.max(0, p.rally - RALLY.decay * dt);

  const dirX = (held.right ? 1 : 0) - (held.left ? 1 : 0);
  let control = 0, gravity = true;

  switch (p.state) {
    case "move":
      control = 1;
      freeActions(game, p, held, dirX);
      break;
    case "attack":
      control = p.onGround ? 0 : 0.35;
      tickAttack(game, p, dirX);
      break;
    case "transform":
      control = 0.5;
      if (p.t >= TRANSFORM_TIME) toMove(p);
      break;
    case "dash":
      gravity = false;
      p.vy = 0;
      p.vx = p.dashDir * DASH.speed;
      if (p.t >= DASH.time) { toMove(p); p.vx = p.dashDir * PLAYER.run; }
      break;
    case "shoot":
      control = p.onGround ? 0 : 0.5;
      if (!p.done && p.t >= GUN.startup) { p.done = true; fire(game, p); }
      if (p.done && p.buf.dash && canDash(p)) startDash(p, dirX);
      else if (p.t >= GUN.startup + GUN.recovery) toMove(p);
      break;
    case "heal":
      control = 0.3;
      if (!p.done && p.t >= PLAYER.healAt) {
        p.done = true;
        p.vials--;
        p.hp = Math.min(p.maxHp, p.hp + PLAYER.vialHeal);
        p.rally = Math.min(p.rally, p.maxHp - p.hp);
        burst(game.fx, p.x + p.w / 2, p.y + 20, { count: 14, color: "#f0bd62", spread: 70, up: 80, gravity: -80, glow: true });
        sfx.heal();
      }
      if (p.t >= PLAYER.healTime) toMove(p);
      break;
    case "blood":
      // Hold to cut yourself for bullets; let go early to back out.
      if (!held.blood) toMove(p);
      else if (p.t >= BLOOD.time) {
        p.hp -= BLOOD.cost;
        p.rally = Math.min(p.rally + BLOOD.cost, p.maxHp - p.hp);
        p.rallyHold = RALLY.hold;
        p.bullets = Math.min(p.maxBullets, p.bullets + BLOOD.bullets);
        burst(game.fx, p.x + p.w / 2, p.y + 18, { count: 12, color: "#8e1b1e", spread: 90 });
        sfx.blood();
        toMove(p);
      }
      break;
    case "hurt":
      if (p.t >= PLAYER.hurtTime) toMove(p);
      break;
    case "visceral":
      tickVisceral(game, p);
      break;
    // "rest" (at a lamp) and "dead" are run by game.js.
  }

  if (control > 0) {
    const accel = (p.onGround ? PLAYER.accelGround : PLAYER.accelAir) * control;
    const stopping = dirX === 0 && p.onGround;
    p.vx = approach(p.vx, dirX * PLAYER.run, (stopping ? PLAYER.friction : accel) * dt);
    if (dirX && p.state === "move") p.facing = dirX;
  } else if (p.onGround && p.state !== "dash") {
    p.vx = approach(p.vx, 0, PLAYER.friction * 0.5 * dt);
  }

  // Let go of jump early for a short hop.
  if (p.jumping && !held.jump && p.vy < 0) { p.vy *= PLAYER.jumpCut; p.jumping = false; }
  if (gravity) p.vy = Math.min(p.vy + GRAVITY * dt, MAX_FALL);

  moveBody(p, game.level, dt, p.dropT > 0);
  if (p.onGround) {
    p.coyote = PLAYER.coyote;
    p.airDash = true;
    p.jumping = false;
    if (Math.abs(p.vx) > 20) p.runT += dt;
    if (firmFooting(p, game.level)) p.safe = { x: p.x + p.w / 2, y: p.y + p.h };
  }
  checkHazard(game, p);
}

function freeActions(game, p, held, dirX) {
  const b = p.buf, form = currentForm(p);
  if (b.dash && canDash(p)) return startDash(p, dirX);
  if (b.attack) {
    b.attack = 0;
    const target = visceralTarget(game, p);
    if (target) return startVisceral(game, p, target);
    p.combo = 0;
    return startAttack(p, form.combo[0], "combo");
  }
  if (b.transform) {
    b.transform = 0;
    p.form = form.trick.to;
    p.state = "transform";
    p.t = 0;
    sfx.swing();
    return;
  }
  if (b.shoot) {
    b.shoot = 0;
    if (p.bullets <= 0) return sfx.click();
    p.state = "shoot"; p.t = 0; p.done = false;
    return;
  }
  if (b.heal) {
    b.heal = 0;
    if (p.vials <= 0 || p.hp >= p.maxHp) return sfx.deny();
    p.state = "heal"; p.t = 0; p.done = false;
    return;
  }
  if (held.blood && p.onGround && p.hp > BLOOD.cost && p.bullets < p.maxBullets) {
    p.state = "blood"; p.t = 0;
    return;
  }
  if (b.jump && (p.onGround || p.coyote > 0)) {
    b.jump = 0;
    if (held.down && onWalkway(p, game.level)) { p.dropT = 0.25; return; }
    p.vy = -PLAYER.jump;
    p.jumping = true;
    p.coyote = 0;
    p.onGround = false;
    sfx.jump();
  }
}

function startAttack(p, a, kind) {
  p.state = "attack";
  p.t = 0;
  p.attack = a;
  p.kind = kind;
  p.hitSet = new Set();
  p.lunged = false;
}

function tickAttack(game, p, dirX) {
  const a = p.attack, b = p.buf;
  const on = a.startup, off = a.startup + a.active, end = off + a.recovery;
  if (p.t >= on && !p.lunged) {
    p.lunged = true;
    // A trick attack lands in the other form.
    if (p.kind === "trick") p.form = a.to;
    if (p.onGround) p.vx = p.facing * a.lunge;
    (a.damage >= 22 ? sfx.heavy : sfx.swing)();
  }
  if (p.t >= on && p.t < off) meleeHits(game, p, a);
  if (p.t < off) return;

  // Recovery: chain into the next swing, turn it into a trick attack, or
  // quickstep out.
  if (b.dash && canDash(p)) return startDash(p, dirX);
  if (b.transform && p.kind === "combo") {
    b.transform = 0;
    return startAttack(p, currentForm(p).trick, "trick");
  }
  if (b.attack && p.t >= off + a.recovery * 0.35) {
    b.attack = 0;
    const target = visceralTarget(game, p);
    if (target) return startVisceral(game, p, target);
    if (dirX) p.facing = dirX;
    const combo = currentForm(p).combo;
    p.combo = p.kind === "trick" ? 0 : (p.combo + 1) % combo.length;
    return startAttack(p, combo[p.combo], "combo");
  }
  if (p.t >= end) toMove(p);
}

function meleeHits(game, p, a) {
  const box = attackBox(p, a);
  if (currentForm(p).burns) {
    const burnt = game.level.burn(box);
    for (const { c, r } of burnt) {
      burst(game.fx, (c + 0.5) * TILE, (r + 0.5) * TILE, { count: 14, color: "#ffb35a", spread: 120, up: 100, gravity: -150, life: 0.9, glow: true });
    }
    if (burnt.length) sfx.burn();
  }
  for (const e of game.enemies) {
    if (!e.alive || p.hitSet.has(e) || !overlaps(box, e)) continue;
    p.hitSet.add(e);
    const dmg = Math.round(a.damage * (1 + 0.08 * game.stats.strength));
    damageEnemy(game, e, dmg, p.facing);
    // Rally: hitting back wins back what you just lost.
    const back = Math.min(p.rally, dmg * RALLY.regain);
    p.hp += back;
    p.rally -= back;
    game.hitstop = Math.max(game.hitstop, HITSTOP.hit);
    shake(game.fx, 2);
    sfx.hit();
  }
}

function fire(game, p) {
  p.bullets--;
  sfx.shot();
  const gx = p.facing > 0 ? p.x + p.w + 6 : p.x - 6, gy = p.y + p.h - GUN.y;
  let reach = rayLength(game.level, gx, gy, p.facing, GUN.range), hit = null;
  for (const e of game.enemies) {
    if (!e.alive || gy < e.y - 10 || gy > e.y + e.h + 10) continue;
    const d = p.facing > 0 ? e.x - gx : gx - (e.x + e.w);
    if (d > -e.w && d < reach) { reach = Math.max(0, d); hit = e; }
  }
  game.shot = { x1: gx, y: gy, x2: gx + p.facing * reach, t: 0.07 };
  if (!hit) return;
  if (parryable(hit)) staggerEnemy(game, hit);
  else damageEnemy(game, hit, Math.round(GUN.damage * (1 + 0.15 * game.stats.steady)), p.facing);
}

// A staggered enemy close enough on either side to finish.
function visceralTarget(game, p) {
  return game.enemies.find((e) => {
    if (!e.alive || e.state !== "stagger" || Math.abs(e.y + e.h - (p.y + p.h)) > 40) return false;
    const gap = Math.abs(e.x + e.w / 2 - (p.x + p.w / 2)) - (e.w + p.w) / 2;
    return gap < VISCERAL.reach;
  });
}

function startVisceral(game, p, e) {
  p.state = "visceral";
  p.t = 0;
  p.done = false;
  p.target = e;
  p.facing = Math.sign(e.x + e.w / 2 - (p.x + p.w / 2)) || p.facing;
  p.vx = 0;
  e.state = "held";
  e.t = 0;
}

function tickVisceral(game, p) {
  const e = p.target;
  if (!p.done && p.t >= VISCERAL.at) {
    p.done = true;
    const dmg = Math.round(VISCERAL.damage * (1 + 0.08 * game.stats.strength));
    damageEnemy(game, e, dmg, p.facing, { visceral: true });
    // A Visceral wins back all of your rally at once.
    p.hp = Math.min(p.maxHp, p.hp + p.rally);
    p.rally = 0;
    game.hitstop = Math.max(game.hitstop, HITSTOP.visceral);
    shake(game.fx, 9);
    sfx.visceral();
  }
  if (p.t >= VISCERAL.time) toMove(p);
}

const canDash = (p) => p.dashCd <= 0 && (p.onGround || p.airDash);

function startDash(p, dirX) {
  p.state = "dash";
  p.t = 0;
  p.dashDir = dirX || p.facing;
  p.facing = p.dashDir;
  p.dashCd = DASH.cooldown;
  p.buf.dash = 0;
  if (!p.onGround) p.airDash = false;
  p.jumping = false;
  sfx.dash();
}

function toMove(p) {
  p.state = "move";
  p.t = 0;
  p.attack = null;
}

// Both feet on something, so it's a fair place to be put back after a
// fall into the canal.
function firmFooting(p, level) {
  const r = Math.floor((p.y + p.h + 1) / TILE);
  const ok = (x) => { const c = Math.floor(x / TILE); return level.solid(c, r) || level.oneWay(c, r); };
  return ok(p.x - 4) && ok(p.x + p.w + 4);
}

function onWalkway(p, level) {
  const r = Math.floor((p.y + p.h + 1) / TILE);
  const cols = [Math.floor(p.x / TILE), Math.floor((p.x + p.w - 0.01) / TILE)];
  return cols.every((c) => !level.solid(c, r)) && cols.some((c) => level.oneWay(c, r));
}

function checkHazard(game, p) {
  const r = Math.floor((p.y + p.h - 6) / TILE);
  p.inHazard = [p.x, p.x + p.w - 0.01].some((x) => game.level.hazard(Math.floor(x / TILE), r));
  if (!p.inHazard || p.state === "dead") return;
  burst(game.fx, p.x + p.w / 2, r * TILE, { count: 20, color: "#4b8c7c", spread: 140, up: 160 });
  sfx.splash();
  p.hp -= HAZARD_DAMAGE;
  p.rally = 0;
  if (p.hp <= 0) return killPlayer(game);
  p.x = p.safe.x - p.w / 2;
  p.y = p.safe.y - p.h;
  p.vx = p.vy = 0;
  p.iframes = 1;
  p.inHazard = false;
  toMove(p);
}
