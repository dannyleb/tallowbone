import { VIEW } from "../config.js";
import { strikeBox } from "../enemies.js";
import { attackBox } from "../player.js";
import { drawEnemy, drawPlayer } from "./actors.js";
import { drawBackdrop } from "./backdrop.js";
import { drawHud } from "./hud.js";
import { createLight, drawLight, gatherLights } from "./light.js";
import { drawLamp, drawPickup, drawPile, drawShot, drawSign, drawTiles } from "./world.js";

// Fits the fixed-height view into the window (letterboxed if the screen is
// unusually wide or tall) and draws a frame: backdrop, world, actors,
// effects, the night's darkness, then the HUD.
// view.hitboxes is read every frame, so it can be toggled while playing.
export function createRenderer(canvas, view = { hitboxes: false }) {
  const ctx = canvas.getContext("2d");
  const light = createLight();
  let dpr = 1, scale = 1, viewW = VIEW.minWidth, ox = 0, oy = 0;

  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    const cw = window.innerWidth, ch = window.innerHeight;
    canvas.width = Math.round(cw * dpr);
    canvas.height = Math.round(ch * dpr);
    canvas.style.width = `${cw}px`;
    canvas.style.height = `${ch}px`;
    viewW = Math.max(VIEW.minWidth, Math.min(VIEW.maxWidth, (cw / ch) * VIEW.height));
    scale = Math.min(canvas.height / VIEW.height, canvas.width / viewW);
    ox = (canvas.width - viewW * scale) / 2;
    oy = (canvas.height - VIEW.height * scale) / 2;
  }
  resize();
  window.addEventListener("resize", resize);

  function draw(game) {
    game.viewW = viewW;
    const { cam, fx } = game, H = VIEW.height;
    const sh = fx.shake, sx = (Math.random() - 0.5) * sh, sy = (Math.random() - 0.5) * sh;
    // Snap the camera to whole device pixels so tiles don't shimmer.
    const camX = Math.round((cam.x + sx) * scale) / scale, camY = Math.round((cam.y + sy) * scale) / scale;
    const at = { x: camX, y: camY };

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = "#000";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.save();
    ctx.beginPath();
    ctx.rect(ox, oy, viewW * scale, H * scale);
    ctx.clip();

    // View space.
    ctx.setTransform(scale, 0, 0, scale, ox, oy);
    drawBackdrop(ctx, at, viewW, H, game.time);

    // World space.
    ctx.setTransform(scale, 0, 0, scale, ox - camX * scale, oy - camY * scale);
    drawTiles(ctx, game.level, at, viewW, H, game.time);
    for (const l of game.level.spawns.lamps) drawLamp(ctx, l, game.time);
    for (const s of game.level.spawns.signs) drawSign(ctx, s, game.sign === s);
    for (const it of game.level.spawns.pickups) drawPickup(ctx, it, game.time);
    if (game.pile) drawPile(ctx, game.pile, game.time);
    for (const e of game.enemies) drawEnemy(ctx, e, game);
    drawPlayer(ctx, game.player, game);
    if (game.shot) drawShot(ctx, game.shot);
    drawParticles(ctx, fx, false);
    if (view.hitboxes) drawHitboxes(ctx, game);

    // The dark, in canvas pixels.
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    const toScreen = (x, y) => [ox + (x - camX) * scale, oy + (y - camY) * scale];
    drawLight(ctx, light, gatherLights(game), toScreen, scale, canvas.width, canvas.height, oy);

    // Glowing particles sit above the dark.
    ctx.setTransform(scale, 0, 0, scale, ox - camX * scale, oy - camY * scale);
    drawParticles(ctx, fx, true);

    ctx.setTransform(scale, 0, 0, scale, ox, oy);
    vignette(ctx, viewW, H);
    drawHud(ctx, game, viewW);
    ctx.restore();
  }

  return { draw, resize };
}

function drawParticles(ctx, fx, glow) {
  if (glow) ctx.globalCompositeOperation = "lighter";
  for (const p of fx.parts) {
    if (p.glow !== glow) continue;
    ctx.globalAlpha = Math.max(0, p.life / p.max);
    ctx.fillStyle = p.color;
    ctx.fillRect(p.x - p.size / 2, p.y - p.size / 2, p.size, p.size);
  }
  if (glow) {
    ctx.fillStyle = "#f0bd62";
    for (const m of fx.motes) {
      if (m.t < 0) continue;
      ctx.globalAlpha = Math.max(0, 1 - m.t / 1.1);
      ctx.fillRect(m.x - 1, m.y - 1, 2.5, 2.5);
    }
  }
  ctx.globalAlpha = 1;
  ctx.globalCompositeOperation = "source-over";
}

function vignette(ctx, w, h) {
  const g = ctx.createRadialGradient(w / 2, h / 2, h * 0.45, w / 2, h / 2, w * 0.75);
  g.addColorStop(0, "rgba(0, 0, 0, 0)");
  g.addColorStop(1, "rgba(0, 0, 0, 0.55)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
}

// ?debug (H toggles): bodies, attack and strike hitboxes.
function drawHitboxes(ctx, game) {
  const p = game.player;
  ctx.lineWidth = 1;
  ctx.strokeStyle = "rgba(120, 255, 160, 0.8)";
  ctx.strokeRect(p.x, p.y, p.w, p.h);
  if (p.state === "attack" && p.t >= p.attack.startup && p.t < p.attack.startup + p.attack.active) {
    const b = attackBox(p, p.attack);
    ctx.strokeStyle = "rgba(255, 220, 90, 0.9)";
    ctx.strokeRect(b.x, b.y, b.w, b.h);
  }
  for (const e of game.enemies) {
    if (!e.alive) continue;
    ctx.strokeStyle = "rgba(120, 180, 255, 0.8)";
    ctx.strokeRect(e.x, e.y, e.w, e.h);
    if (e.state === "strike") {
      const b = strikeBox(e);
      ctx.strokeStyle = "rgba(255, 80, 80, 0.9)";
      ctx.strokeRect(b.x, b.y, b.w, b.h);
    }
  }
}
