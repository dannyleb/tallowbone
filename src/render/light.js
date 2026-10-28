// The night: a dark layer over the whole scene with holes cut where the
// light is (lit lamps, your pole's wick or lantern, your dropped tallow,
// muzzle flashes), then a warm glow added over the brightest sources. It
// renders at half resolution; it's all soft gradients anyway.
import { currentForm } from "../player.js";

export function createLight() {
  const canvas = document.createElement("canvas");
  return { canvas, ctx: canvas.getContext("2d") };
}

export function gatherLights(game) {
  const t = game.time, out = [];
  const flick = (seed, amt) => 1 + Math.sin(t * 11 + seed) * Math.sin(t * 6.7 + seed * 2) * amt;
  for (const l of game.level.spawns.lamps) {
    if (l.lit) out.push({ x: l.x, y: l.y - 68, r: 165 * flick(l.x, 0.04) * Math.min(1, (l.litT ?? 1) * 2 + 0.3), warm: 0.22 });
  }
  const p = game.player;
  if (p.state !== "dead" || p.t < 1.4) {
    const form = currentForm(p);
    const at = p.lanternAt || { x: p.x + p.w / 2 + p.facing * 10, y: p.y + 6 };
    out.push({ x: at.x, y: at.y, r: form.light * flick(3, 0.06), warm: form.burns ? 0.16 : 0.05 });
    out.push({ x: p.x + p.w / 2, y: p.y + p.h / 2, r: 46, warm: 0 });
  }
  if (game.pile) out.push({ x: game.pile.x, y: game.pile.y - 12, r: 70 * flick(9, 0.12), warm: 0.14 });
  for (const it of game.level.spawns.pickups) if (!it.taken) out.push({ x: it.x, y: it.y - 14, r: 34, warm: 0.05 });
  for (const e of game.enemies) if (e.alive && e.gorged) out.push({ x: e.x + e.w / 2, y: e.y + 6, r: 40, warm: 0.12, color: "255, 106, 61" });
  if (game.shot) out.push({ x: game.shot.x1, y: game.shot.y, r: 130, warm: 0.2 });
  return out;
}

// toScreen: world -> canvas pixels. w, h: canvas size in pixels.
export function drawLight(ctx, light, lights, toScreen, scale, w, h, viewTop) {
  const lc = light.ctx, cw = Math.ceil(w / 2), ch = Math.ceil(h / 2);
  if (light.canvas.width !== cw || light.canvas.height !== ch) { light.canvas.width = cw; light.canvas.height = ch; }
  lc.globalCompositeOperation = "source-over";
  lc.clearRect(0, 0, cw, ch);
  // Darker toward the ground; the sky keeps a little of the moon.
  const dark = lc.createLinearGradient(0, viewTop / 2, 0, ch);
  dark.addColorStop(0, "rgba(4, 5, 10, 0.38)");
  dark.addColorStop(0.6, "rgba(4, 5, 10, 0.62)");
  dark.addColorStop(1, "rgba(4, 5, 10, 0.72)");
  lc.fillStyle = dark;
  lc.fillRect(0, 0, cw, ch);
  lc.globalCompositeOperation = "destination-out";
  for (const l of lights) {
    const [sx, sy] = toScreen(l.x, l.y), r = (l.r * scale) / 2;
    const g = lc.createRadialGradient(sx / 2, sy / 2, 0, sx / 2, sy / 2, r);
    g.addColorStop(0, "rgba(0, 0, 0, 1)");
    g.addColorStop(0.45, "rgba(0, 0, 0, 0.75)");
    g.addColorStop(1, "rgba(0, 0, 0, 0)");
    lc.fillStyle = g;
    lc.fillRect(sx / 2 - r, sy / 2 - r, r * 2, r * 2);
  }
  ctx.drawImage(light.canvas, 0, 0, w, h);

  // Warm glow on top.
  ctx.globalCompositeOperation = "lighter";
  for (const l of lights) {
    if (!l.warm) continue;
    const [sx, sy] = toScreen(l.x, l.y), r = l.r * scale * 0.8, col = l.color || "255, 186, 100";
    const g = ctx.createRadialGradient(sx, sy, 0, sx, sy, r);
    g.addColorStop(0, `rgba(${col}, ${l.warm})`);
    g.addColorStop(1, `rgba(${col}, 0)`);
    ctx.fillStyle = g;
    ctx.fillRect(sx - r, sy - r, r * 2, r * 2);
  }
  ctx.globalCompositeOperation = "source-over";
}
