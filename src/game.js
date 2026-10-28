import { LEVEL, NEAR, STATS, VIEW } from "./config.js";
import { createEnemy, updateEnemy } from "./enemies.js";
import { banner, burst, createFx, notice, updateFx } from "./fx.js";
import { parseLevel } from "./level.js";
import { canal } from "./levels/canal.js";
import { bufferInput, createPlayer, updatePlayer } from "./player.js";
import { sfx } from "./sfx.js";
import { dropTallow, updatePile } from "./tallow.js";

export function createGame() {
  const level = parseLevel(canal);
  const game = {
    level,
    player: createPlayer(level.spawns.player),
    enemies: [],
    fx: createFx(),
    tallow: 0, gained: null, pile: null, lostTallow: 0, dropped: false,
    checkpoint: null,
    levelNo: 1, stats: { vitality: 0, strength: 0, steady: 0 },
    menu: null, sign: null, prompt: null, shot: null,
    hitstop: 0, time: 0, deaths: 0,
    cam: { x: 0, y: 0, look: 0 }, viewW: VIEW.minWidth,
  };
  resetEnemies(game);
  snapCamera(game);
  return game;
}

export const levelCost = (game) => Math.round(LEVEL.base * LEVEL.growth ** (game.levelNo - 1));

export function update(game, input, dt) {
  const p = game.player;
  game.time += dt;
  updateFx(game.fx, dt);
  if (game.shot && (game.shot.t -= dt) <= 0) game.shot = null;
  if (game.gained && (game.gained.t += dt) > 1.6) game.gained = null;
  for (const l of game.level.spawns.lamps) if (l.litT !== undefined) l.litT += dt;

  if (game.menu) return updateMenu(game, input);
  bufferInput(p, input.pressed);
  if (game.hitstop > 0) { game.hitstop -= dt; return; }

  updatePlayer(game, input, dt);
  for (const e of game.enemies) updateEnemy(game, e, dt);
  updatePile(game);
  updatePickups(game);
  updateLampsAndSigns(game);

  if (p.state === "dead") {
    if (!game.dropped && p.t >= 0.5) { game.dropped = true; dropTallow(game); }
    if (p.t >= 2.8) respawn(game);
  }
  updateCamera(game, dt);
}

function resetEnemies(game) {
  game.enemies = game.level.spawns.enemies.map(createEnemy);
}

// Full health, vials and bullets, and the night's horrors back where they
// started. Happens when you rest at a lamp and when you die.
function refresh(game) {
  const p = game.player;
  p.hp = p.maxHp;
  p.rally = 0;
  p.vials = p.maxVials;
  p.bullets = p.maxBullets;
  resetEnemies(game);
}

function respawn(game) {
  const p = game.player, at = game.checkpoint || game.level.spawns.player;
  p.x = at.x - p.w / 2;
  p.y = at.y - p.h;
  p.vx = p.vy = 0;
  p.state = "move";
  p.t = 0;
  p.iframes = 1;
  p.safe = { x: at.x, y: at.y };
  refresh(game);
  snapCamera(game);
  if (game.lostTallow) notice(game.fx, `${game.lostTallow} tallow is lost for good.`);
  game.lostTallow = 0;
}

// The first press lights a lamp (and makes it your checkpoint); after
// that, pressing again rests there.
function lightLamp(game, lamp) {
  lamp.lit = true;
  lamp.litT = 0;
  game.checkpoint = lamp;
  banner(game.fx, "LAMP LIT", game.level.name, 2.6, "lamp");
  burst(game.fx, lamp.x, lamp.y - 54, { count: 30, color: "#ffcf7a", spread: 90, up: 60, gravity: -40, glow: true });
  sfx.lamp();
}

function restAt(game, lamp) {
  const p = game.player;
  game.checkpoint = lamp;
  game.fx.banner = null;
  p.state = "rest";
  p.vx = 0;
  refresh(game);
  game.menu = { index: 0 };
}

// Levelling up at a lamp: spend tallow on a stat.
function updateMenu(game, { pressed }) {
  const m = game.menu, p = game.player, n = STATS.length + 1;
  if (pressed.up) { m.index = (m.index + n - 1) % n; sfx.click(); }
  if (pressed.down) { m.index = (m.index + 1) % n; sfx.click(); }
  const leave = pressed.back || (pressed.confirm && m.index === STATS.length);
  if (leave) {
    game.menu = null;
    p.state = "move";
    p.t = 0;
    for (const k in p.buf) p.buf[k] = 0;
    return;
  }
  if (!pressed.confirm) return;
  const cost = levelCost(game), stat = STATS[m.index];
  if (game.tallow < cost) return sfx.deny();
  game.tallow -= cost;
  game.levelNo++;
  game.stats[stat.id]++;
  if (stat.id === "vitality") { p.maxHp += 12; p.hp = p.maxHp; }
  if (stat.id === "steady") { p.maxBullets += 2; p.bullets = p.maxBullets; }
  sfx.buy();
}

function updatePickups(game) {
  const p = game.player, cx = p.x + p.w / 2;
  for (const it of game.level.spawns.pickups) {
    if (it.taken || Math.abs(it.x - cx) > 18 || it.y < p.y || it.y - 20 > p.y + p.h) continue;
    it.taken = true;
    if (it.kind === "vial") {
      p.maxVials++;
      p.vials++;
      banner(game.fx, "VIAL HOLDER", "Carry one more vial. Lamps refill them.", 2.6, "pale");
    } else {
      p.maxBullets += 3;
      p.bullets = p.maxBullets;
      banner(game.fx, "BULLET POUCH", "Carry three more quicksilver rounds.", 2.6, "pale");
    }
    burst(game.fx, it.x, it.y - 12, { count: 16, color: "#e8dfcf", spread: 80, up: 80, gravity: -50, glow: true });
    sfx.buy();
  }
}

function updateLampsAndSigns(game) {
  const p = game.player, cx = p.x + p.w / 2, feet = p.y + p.h;
  game.prompt = null;
  game.sign = null;
  if (p.state === "dead") return;
  for (const l of game.level.spawns.lamps) {
    if (Math.abs(l.x - cx) > NEAR || Math.abs(l.y - feet) > 40) continue;
    game.prompt = { x: l.x, y: l.y - 74, text: l.lit ? "Rest" : "Light the lamp" };
    if (p.buf.interact && p.state === "move" && p.onGround) {
      p.buf.interact = 0;
      if (l.lit) restAt(game, l);
      else lightLamp(game, l);
    }
  }
  for (const s of game.level.spawns.signs) {
    if (Math.abs(s.x - cx) < NEAR * 1.6 && Math.abs(s.y - feet) < 60) game.sign = s;
  }
}

function updateCamera(game, dt) {
  const { cam, player: p } = game;
  cam.look += (p.facing * 50 - cam.look) * Math.min(1, dt * 2.5);
  const tx = p.x + p.w / 2 + cam.look - game.viewW / 2;
  const ty = p.y + p.h / 2 - VIEW.height * 0.58;
  cam.x += (tx - cam.x) * Math.min(1, dt * 7);
  cam.y += (ty - cam.y) * Math.min(1, dt * (p.vy > 300 ? 9 : 5));
  clampCamera(game);
}

export function snapCamera(game) {
  const { cam, player: p } = game;
  cam.look = p.facing * 50;
  cam.x = p.x + p.w / 2 + cam.look - game.viewW / 2;
  cam.y = p.y + p.h / 2 - VIEW.height * 0.58;
  clampCamera(game);
}

function clampCamera(game) {
  const { cam, level } = game;
  cam.x = Math.max(0, Math.min(level.pxW - game.viewW, cam.x));
  cam.y = Math.max(0, Math.min(level.pxH - VIEW.height, cam.y));
}
