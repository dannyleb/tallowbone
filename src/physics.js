import { TILE } from "./config.js";

// Bodies are boxes { x, y, w, h, vx, vy } with x, y the top-left corner.
// moveBody moves along x, then y, stopping against solid tiles. One-way
// walkways only stop a body that is falling and was above them last step.
export function moveBody(b, level, dt, dropThrough = false) {
  b.hitWall = 0;
  b.onGround = false;
  const wasBottom = b.y + b.h;

  b.x += b.vx * dt;
  const top = Math.floor(b.y / TILE), bot = Math.floor((b.y + b.h - 0.01) / TILE);
  if (b.vx > 0) {
    const col = Math.floor((b.x + b.w) / TILE);
    for (let r = top; r <= bot; r++) if (level.solid(col, r)) { b.x = col * TILE - b.w; b.vx = 0; b.hitWall = 1; break; }
  } else if (b.vx < 0) {
    const col = Math.floor(b.x / TILE);
    for (let r = top; r <= bot; r++) if (level.solid(col, r)) { b.x = (col + 1) * TILE; b.vx = 0; b.hitWall = -1; break; }
  }

  b.y += b.vy * dt;
  const left = Math.floor(b.x / TILE), right = Math.floor((b.x + b.w - 0.01) / TILE);
  if (b.vy > 0) {
    const row = Math.floor((b.y + b.h) / TILE);
    for (let c = left; c <= right; c++) {
      const land = level.solid(c, row) || (!dropThrough && level.oneWay(c, row) && wasBottom <= row * TILE + 0.5);
      if (land) { b.y = row * TILE - b.h; b.vy = 0; b.onGround = true; break; }
    }
  } else if (b.vy < 0) {
    const row = Math.floor(b.y / TILE);
    for (let c = left; c <= right; c++) if (level.solid(c, row)) { b.y = (row + 1) * TILE; b.vy = 0; break; }
  }
}

export const overlaps = (a, b) => a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;

// Is there floor under the point just past the body's leading edge?
// Enemies use it so they don't walk off ledges.
export function floorAhead(b, level, dir) {
  const x = dir > 0 ? b.x + b.w + 2 : b.x - 2;
  const c = Math.floor(x / TILE), r = Math.floor((b.y + b.h + 2) / TILE);
  return level.solid(c, r) || level.oneWay(c, r);
}

// How far a horizontal ray from (x, y) gets in direction dir before
// hitting stone, up to max.
export function rayLength(level, x, y, dir, max) {
  const r = Math.floor(y / TILE);
  for (let d = 0; d < max; d += 4) if (level.solid(Math.floor((x + dir * d) / TILE), r)) return d;
  return max;
}

// Can a see b? Samples the straight line between their eye points.
export function lineOfSight(level, ax, ay, bx, by) {
  const n = Math.ceil(Math.hypot(bx - ax, by - ay) / (TILE / 2));
  for (let i = 1; i < n; i++) {
    const t = i / n;
    if (level.solid(Math.floor((ax + (bx - ax) * t) / TILE), Math.floor((ay + (by - ay) * t) / TILE))) return false;
  }
  return true;
}
