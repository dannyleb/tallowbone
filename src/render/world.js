import { TILE } from "../config.js";
import { C } from "./palette.js";

// Greybox tiles and props, drawn in world space (the camera transform is
// already applied). Placeholder shapes until the illustrated art arrives,
// but lit and coloured the way the final game will be.

const hash = (c, r) => ((c * 73856093) ^ (r * 19349663)) >>> 0;

export function drawTiles(ctx, level, cam, viewW, viewH, time) {
  const c0 = Math.max(0, Math.floor(cam.x / TILE)), c1 = Math.min(level.w - 1, Math.floor((cam.x + viewW) / TILE));
  const r0 = Math.max(0, Math.floor(cam.y / TILE)), r1 = Math.min(level.h - 1, Math.floor((cam.y + viewH) / TILE));
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      const t = level.at(c, r), x = c * TILE, y = r * TILE;
      if (t !== "#" && level.roofed(c, r)) backWall(ctx, c, r, x, y);
      if (t === "#") stone(ctx, level, c, r, x, y);
      else if (t === "=") walkway(ctx, level, c, r, x, y);
      else if (t === "~") water(ctx, level, c, r, x, y, time);
      else if (t === "V") veil(ctx, c, r, x, y, time);
    }
  }
}

function stone(ctx, level, c, r, x, y) {
  const open = (dc, dr) => !level.solid(c + dc, r + dr);
  const exposed = open(0, -1) || open(-1, 0) || open(1, 0) || open(0, 1) || open(0, -2);
  ctx.fillStyle = exposed ? C.stone : C.stoneDeep;
  ctx.fillRect(x, y, TILE, TILE);
  if (!exposed) return;
  // Brick courses on faces you can see.
  ctx.fillStyle = C.mortar;
  ctx.fillRect(x, y + 15, TILE, 1);
  ctx.fillRect(x, y + 31, TILE, 1);
  const off = r % 2 ? 0 : 16;
  ctx.fillRect(x + off, y, 1, 15);
  ctx.fillRect(x + ((off + 16) % 32), y + 16, 1, 15);
  if (open(0, -1)) {
    // Cobbled top edge.
    ctx.fillStyle = C.stoneTop;
    ctx.fillRect(x, y, TILE, 3);
    ctx.fillStyle = C.stoneEdge;
    const h = hash(c, r);
    for (let i = 0; i < 4; i++) ctx.fillRect(x + i * 8 + (h >> i) % 4, y + 3, 5, 2);
  }
  ctx.fillStyle = C.stoneEdge;
  if (open(-1, 0)) ctx.fillRect(x, y, 2, TILE);
  if (open(1, 0)) ctx.fillRect(x + TILE - 2, y, 2, TILE);
}

function backWall(ctx, c, r, x, y) {
  ctx.fillStyle = C.backWall;
  ctx.fillRect(x, y, TILE, TILE);
  ctx.fillStyle = "rgba(0, 0, 0, 0.3)";
  ctx.fillRect(x, y + 10, TILE, 1);
  ctx.fillRect(x, y + 21, TILE, 1);
  ctx.fillRect(x, y + 31, TILE, 1);
  const h = hash(c, r);
  ctx.fillRect(x + (h % 3) * 8 + 4, y, 1, 10);
  ctx.fillRect(x + ((h >> 3) % 3) * 8 + 8, y + 11, 1, 10);
  ctx.fillRect(x + ((h >> 6) % 3) * 8 + 2, y + 22, 1, 9);
  if (h % 7 === 0) { ctx.fillStyle = "rgba(255, 255, 255, 0.025)"; ctx.fillRect(x + 6, y + 11, 14, 10); }
}

function walkway(ctx, level, c, r, x, y) {
  ctx.fillStyle = C.wood;
  ctx.fillRect(x, y, TILE, 7);
  ctx.fillStyle = C.woodTop;
  ctx.fillRect(x, y, TILE, 2);
  ctx.fillStyle = "rgba(0, 0, 0, 0.35)";
  ctx.fillRect(x + 15, y + 2, 1, 5);
  // Iron brackets under the ends.
  ctx.strokeStyle = C.iron;
  ctx.lineWidth = 2;
  if (level.at(c - 1, r) !== "=") { ctx.beginPath(); ctx.moveTo(x + 4, y + 7); ctx.lineTo(x + 4, y + 22); ctx.stroke(); }
  if (level.at(c + 1, r) !== "=") { ctx.beginPath(); ctx.moveTo(x + TILE - 4, y + 7); ctx.lineTo(x + TILE - 4, y + 22); ctx.stroke(); }
}

function water(ctx, level, c, r, x, y, time) {
  const surface = level.at(c, r - 1) !== "~";
  ctx.fillStyle = surface ? C.water : C.waterDeep;
  ctx.fillRect(x, y, TILE, TILE);
  if (!surface) return;
  ctx.strokeStyle = C.waterLine;
  ctx.globalAlpha = 0.55;
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (let i = 0; i <= TILE; i += 4) {
    const wy = y + 3 + Math.sin((x + i) * 0.09 + time * 2.2) * 1.6;
    if (i === 0) ctx.moveTo(x + i, wy); else ctx.lineTo(x + i, wy);
  }
  ctx.stroke();
  ctx.globalAlpha = 1;
}

function veil(ctx, c, r, x, y, time) {
  ctx.strokeStyle = C.veil;
  ctx.lineWidth = 1.2;
  const h = hash(c, r);
  for (let i = 0; i < 7; i++) {
    const sx = x + ((h >> (i * 3)) % 28) + 2, sway = Math.sin(time * 1.3 + i + c) * 3;
    ctx.beginPath();
    ctx.moveTo(sx, y);
    ctx.bezierCurveTo(sx + sway, y + 10, sx - sway, y + 22, sx + sway * 0.5, y + TILE);
    ctx.stroke();
  }
  ctx.fillStyle = "rgba(228, 220, 198, 0.12)";
  ctx.fillRect(x, y, TILE, TILE);
}

export function drawLamp(ctx, l, time) {
  const x = l.x, y = l.y;
  ctx.fillStyle = C.iron;
  ctx.fillRect(x - 2, y - 60, 4, 60);
  ctx.fillRect(x - 7, y - 4, 14, 4);
  ctx.fillRect(x - 9, y - 50, 18, 2); // the lamplighter's ladder bar
  // Lantern head.
  ctx.beginPath();
  ctx.moveTo(x - 7, y - 60); ctx.lineTo(x + 7, y - 60); ctx.lineTo(x + 5, y - 76); ctx.lineTo(x - 5, y - 76);
  ctx.closePath();
  const flicker = l.lit ? 0.85 + 0.15 * Math.sin(time * 13 + x) * Math.sin(time * 7.3) : 0;
  ctx.fillStyle = l.lit ? `rgba(255, 207, 122, ${flicker})` : "#26252a";
  ctx.fill();
  ctx.fillStyle = C.iron;
  ctx.fillRect(x - 8, y - 79, 16, 3);
  ctx.fillRect(x - 1, y - 84, 2, 5);
}

export function drawSign(ctx, s, near) {
  ctx.fillStyle = C.wood;
  ctx.fillRect(s.x - 1.5, s.y - 26, 3, 26);
  ctx.fillStyle = near ? "#6d5440" : "#4a372a";
  ctx.fillRect(s.x - 11, s.y - 34, 22, 13);
  ctx.fillStyle = "rgba(232, 223, 207, 0.45)";
  for (let i = 0; i < 3; i++) ctx.fillRect(s.x - 7, s.y - 31 + i * 3.5, 14 - i * 3, 1);
}

export function drawPickup(ctx, it, time) {
  if (it.taken) return;
  const bob = Math.sin(time * 2.5 + it.x) * 2.5, x = it.x, y = it.y - 14 + bob;
  if (it.kind === "vial") {
    ctx.fillStyle = C.bone;
    ctx.fillRect(x - 1.5, y - 9, 3, 3);
    ctx.fillStyle = C.bloodBright;
    ctx.beginPath(); ctx.ellipse(x, y, 5, 6, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = "rgba(255, 255, 255, 0.5)";
    ctx.fillRect(x - 3, y - 3, 1.5, 3);
  } else {
    ctx.fillStyle = "#4a3a2a";
    ctx.fillRect(x - 6, y - 5, 12, 10);
    ctx.fillStyle = "#c9a34a";
    for (let i = 0; i < 3; i++) ctx.fillRect(x - 4 + i * 3, y - 8, 2, 4);
  }
}

// Your dropped tallow: a guttering ghost-light where you fell.
export function drawPile(ctx, pile, time) {
  const x = pile.x, y = pile.y;
  for (let i = 0; i < 3; i++) {
    const h = 16 + Math.sin(time * 9 + i * 2) * 4 + i * 3, w = 7 - i * 1.8;
    ctx.fillStyle = ["rgba(240, 189, 98, 0.35)", "rgba(255, 214, 140, 0.6)", "rgba(255, 245, 220, 0.85)"][i];
    ctx.beginPath();
    ctx.moveTo(x - w, y - 2);
    ctx.quadraticCurveTo(x - w, y - h * 0.6, x + Math.sin(time * 5) * 2, y - h);
    ctx.quadraticCurveTo(x + w, y - h * 0.6, x + w, y - 2);
    ctx.closePath();
    ctx.fill();
  }
  ctx.fillStyle = "rgba(255, 220, 160, 0.7)";
  for (let i = 0; i < 4; i++) {
    const t = (time * 0.6 + i / 4) % 1;
    ctx.fillRect(x + Math.sin(i * 2.3 + time) * 8, y - 8 - t * 34, 1.5, 1.5);
  }
}

export function drawShot(ctx, shot) {
  ctx.strokeStyle = `rgba(255, 236, 200, ${shot.t / 0.07})`;
  ctx.lineWidth = 1.2;
  ctx.beginPath();
  ctx.moveTo(shot.x1, shot.y);
  ctx.lineTo(shot.x2, shot.y);
  ctx.stroke();
}
