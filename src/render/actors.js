import { TRANSFORM_TIME } from "../arms.js";
import { BLOOD, GUN } from "../config.js";
import { parryable } from "../combat.js";
import { currentForm } from "../player.js";
import { C } from "./palette.js";

// Placeholder figures, built from shapes, drawn facing right with their
// feet at the origin and mirrored for facing left. They're stand-ins for
// the hand-drawn sprites, but posed from the real animation timings, so
// what you see is what the hitboxes do.

const lerp = (a, b, t) => a + (b - a) * Math.max(0, Math.min(1, t));
const ease = (t) => 1 - (1 - Math.max(0, Math.min(1, t))) ** 3;

// The pole's angle in radians (0 points forward, negative is up).
function poleAngle(p, time) {
  const rest = -1.25 + Math.sin(time * 2) * 0.04;
  switch (p.state) {
    case "attack": {
      const a = p.attack, t = p.t, up = p.kind === "combo" && p.combo % 2 === 1;
      const [from, to] = up ? [0.9, -2.4] : [-2.6, 0.7];
      if (t < a.startup) return lerp(rest, from, t / a.startup);
      if (t < a.startup + a.active) return lerp(from, to, ease((t - a.startup) / a.active));
      return lerp(to, rest, (t - a.startup - a.active) / a.recovery);
    }
    case "transform": return rest + (p.t / TRANSFORM_TIME) * Math.PI * 2;
    case "dash": return -0.5;
    case "visceral": return p.t < 0.22 ? lerp(-0.4, 0.1, p.t / 0.22) : 0.1;
    case "hurt": return -2.0;
    case "shoot": return -1.9;
    case "dead": return 1.3;
    default: return Math.abs(p.vx) > 40 ? -1.0 : rest;
  }
}

function attackArc(p) {
  if (p.state !== "attack") return null;
  const a = p.attack, t = p.t - a.startup;
  if (t < 0 || t > a.active + 0.05) return null;
  const up = p.kind === "combo" && p.combo % 2 === 1;
  const [from, to] = up ? [0.9, -2.4] : [-2.6, 0.7];
  return { from, to: lerp(from, to, ease(t / a.active)), r: a.reach * 0.7 + 12, fade: 1 - t / (a.active + 0.05) };
}

export function drawPlayer(ctx, p, game) {
  const cx = p.x + p.w / 2, fy = p.y + p.h;
  ctx.save();
  if (p.state === "dead") ctx.globalAlpha = Math.max(0, 1 - Math.max(0, p.t - 1.2) / 1.2);
  else if (p.iframes > 0 && Math.floor(game.time * 20) % 2) ctx.globalAlpha = 0.45;
  if (p.state === "dash") {
    const a = ctx.globalAlpha;
    for (let i = 3; i >= 1; i--) {
      ctx.globalAlpha = a * 0.12 * (4 - i);
      figure(ctx, p, cx - p.dashDir * i * 11, fy, game, true);
    }
    ctx.globalAlpha = a;
  }
  figure(ctx, p, cx, fy, game, false);
  ctx.restore();
}

function figure(ctx, p, cx, fy, game, ghost) {
  ctx.save();
  ctx.translate(cx, fy);
  ctx.scale(p.facing, 1);
  if (p.state === "dead") { ctx.rotate(Math.min(1, p.t * 2) * 1.35); }
  const air = !p.onGround && p.state !== "dead";
  const cyc = p.onGround && Math.abs(p.vx) > 20 ? Math.sin(p.runT * 13) : 0;
  const sway = Math.max(-1, Math.min(1, -p.vx / 300)) * 6;
  const lean = p.state === "dash" || p.state === "visceral" ? 3 : 0;

  // Legs.
  ctx.fillStyle = C.coatDark;
  if (air) { ctx.fillRect(-5, -15, 4, 11); ctx.fillRect(1, -14, 4, 9); }
  else { ctx.fillRect(-5 + cyc * 4, -14, 4, 14); ctx.fillRect(1 - cyc * 4, -14, 4, 14); }

  // Long coat, tails trailing.
  ctx.fillStyle = C.coat;
  ctx.beginPath();
  ctx.moveTo(-6 + lean, -38); ctx.lineTo(6 + lean, -38);
  ctx.lineTo(8, -12); ctx.lineTo(-9 + sway, -8 + Math.abs(sway) * 0.4);
  ctx.closePath();
  ctx.fill();
  ctx.fillStyle = C.coatDark;
  ctx.fillRect(-1 + lean * 0.5, -36, 2, 22);

  // Oxblood scarf, its tail streaming behind.
  ctx.fillStyle = C.scarf;
  ctx.fillRect(-6 + lean, -40, 12, 4);
  ctx.beginPath();
  ctx.moveTo(-5 + lean, -39); ctx.lineTo(-13 + sway * 1.4, -35 + Math.sin(game.time * 8) * 1.5); ctx.lineTo(-5 + lean, -36);
  ctx.fill();

  // Face, under a tall hat.
  ctx.fillStyle = C.skin;
  ctx.fillRect(-2 + lean, -46, 7, 6);
  ctx.fillStyle = C.hat;
  ctx.fillRect(-8 + lean, -47, 17, 2);
  ctx.fillRect(-5 + lean, -58, 11, 11);
  ctx.fillStyle = C.scarf;
  ctx.fillRect(-5 + lean, -50, 11, 1.5);

  if (!ghost) arms(ctx, p, game, lean);
  ctx.restore();
}

function arms(ctx, p, game, lean) {
  const sx = 2 + lean, sy = -34;
  const theta = poleAngle(p, game.time), form = currentForm(p);
  const hx = sx + Math.cos(theta) * 9, hy = sy + Math.sin(theta) * 9;

  const arc = attackArc(p);
  if (arc) {
    ctx.strokeStyle = form.burns ? `rgba(255, 190, 110, ${0.5 * arc.fade})` : `rgba(232, 223, 207, ${0.4 * arc.fade})`;
    ctx.lineWidth = form.burns ? 9 : 6;
    ctx.beginPath();
    ctx.arc(sx, sy, arc.r, Math.min(arc.from, arc.to), Math.max(arc.from, arc.to));
    ctx.stroke();
  }

  // The pole.
  ctx.save();
  ctx.translate(hx, hy);
  ctx.rotate(theta);
  const len = form.burns ? 30 : 46;
  ctx.strokeStyle = C.poleWood;
  ctx.lineWidth = 2.5;
  ctx.beginPath(); ctx.moveTo(-12, 0); ctx.lineTo(len, 0); ctx.stroke();
  if (!form.burns) {
    // Hook and wick.
    ctx.strokeStyle = C.iron;
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(len - 4, -5, 5, Math.PI * 0.5, Math.PI * 1.9, true); ctx.stroke();
    ctx.fillStyle = C.lamp;
    ctx.beginPath(); ctx.arc(len + 1, 0, 1.6 + Math.sin(game.time * 20) * 0.4, 0, Math.PI * 2); ctx.fill();
  }
  ctx.restore();

  if (form.burns) {
    // Lantern on its chain: hangs from the pole tip, flung outward mid-swing.
    const ex = hx + Math.cos(theta) * 30, ey = hy + Math.sin(theta) * 30;
    const flung = p.state === "attack" && p.t > p.attack.startup * 0.5;
    const swing = Math.sin(game.time * 3) * 0.25 - Math.max(-1, Math.min(1, p.vx / 300)) * 0.5;
    const lx = flung ? ex + Math.cos(theta) * 18 : ex + Math.sin(swing) * 14;
    const ly = flung ? ey + Math.sin(theta) * 18 : ey + Math.cos(swing) * 14;
    ctx.strokeStyle = C.iron;
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(ex, ey); ctx.lineTo(lx, ly); ctx.stroke();
    ctx.fillStyle = C.iron;
    ctx.fillRect(lx - 5, ly - 1, 10, 2);
    ctx.fillStyle = C.lamp;
    ctx.fillRect(lx - 4, ly + 1, 8, 9);
    ctx.fillStyle = C.iron;
    ctx.fillRect(lx - 5, ly + 10, 10, 2);
    p.lanternAt = { x: p.x + p.w / 2 + lx * p.facing, y: p.y + p.h + ly };
  } else {
    p.lanternAt = null;
  }

  // The arm holding it.
  ctx.strokeStyle = C.coat;
  ctx.lineWidth = 4;
  ctx.lineCap = "round";
  ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(hx, hy); ctx.stroke();

  // Off hand: the pistol, a vial, or the blade for blood bullets.
  if (p.state === "shoot") {
    const gy = -GUN.y;
    ctx.beginPath(); ctx.moveTo(sx - 2, sy + 2); ctx.lineTo(13, gy); ctx.stroke();
    ctx.fillStyle = "#3a3633";
    ctx.fillRect(11, gy - 3, 9, 3);
    ctx.fillRect(12, gy - 1, 3, 4);
    if (game.shot) {
      ctx.fillStyle = "rgba(255, 230, 170, 0.9)";
      ctx.beginPath(); ctx.moveTo(20, gy - 6); ctx.lineTo(30, gy - 1.5); ctx.lineTo(20, gy + 3); ctx.fill();
    }
  } else if (p.state === "heal") {
    ctx.beginPath(); ctx.moveTo(sx - 2, sy + 2); ctx.lineTo(4, -44); ctx.stroke();
    ctx.fillStyle = C.bloodBright;
    ctx.fillRect(3, -48, 4, 6);
  } else if (p.state === "blood") {
    ctx.beginPath(); ctx.moveTo(sx - 2, sy + 2); ctx.lineTo(6, -24); ctx.stroke();
    // Progress ring.
    ctx.strokeStyle = C.bloodBright;
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(0, -70, 6, -Math.PI / 2, -Math.PI / 2 + (p.t / BLOOD.time) * Math.PI * 2); ctx.stroke();
  }
  ctx.lineCap = "butt";
}

// --- Enemies -------------------------------------------------------------

export function drawEnemy(ctx, e, game) {
  if (!e.alive && e.deadT > 0.9) return;
  ctx.save();
  if (!e.alive) ctx.globalAlpha = 1 - e.deadT / 0.9;
  ctx.translate(e.x + e.w / 2, e.y + e.h + (e.alive ? 0 : e.deadT * 10));
  ctx.scale(e.facing, 1);
  if (e.state === "stagger" || e.state === "held") { ctx.translate(0, 4); ctx.rotate(0.22); }
  if (!e.alive) ctx.rotate(-e.deadT * 1.2);
  const flash = e.flash > 0;
  if (e.type === "hound") hound(ctx, e, flash, game.time);
  else communicant(ctx, e, flash, game.time);
  ctx.restore();

  if (!e.alive) return;
  if (parryable(e)) glint(ctx, weaponPoint(e), e.t - (e.def.windup - e.def.parry), game.time);
  if (e.state === "stagger" || e.state === "held") stunRing(ctx, e, game.time);
  if (e.hp < e.maxHp || e.gorged) {
    const w = 28, x = e.x + e.w / 2 - w / 2, y = e.y - 12;
    ctx.fillStyle = "rgba(0, 0, 0, 0.6)";
    ctx.fillRect(x - 1, y - 1, w + 2, 4);
    ctx.fillStyle = e.gorged ? C.gorged : C.blood;
    ctx.fillRect(x, y, w * Math.max(0, e.hp / e.maxHp), 2);
  }
}

// Arm angle for the Communicant's claw (0 forward, negative up).
function clawAngle(e, time) {
  const d = e.def;
  switch (e.state) {
    case "windup": return lerp(1.0, -2.3, ease(e.t / (d.windup * 0.6)));
    case "strike": return lerp(-2.3, 0.7, ease(e.t / d.strike));
    case "recover": return lerp(0.7, 1.0, e.t / d.recover);
    case "flinch": return -0.4;
    default: return 1.05 + Math.sin(time * 2 + e.spawn.x) * 0.08;
  }
}

function communicant(ctx, e, flash, time) {
  const robe = flash ? "#fff" : e.gorged ? "#3a2420" : C.robe;
  const step = Math.sin(e.runT * 9) * 2;
  ctx.fillStyle = flash ? "#fff" : C.robeDark;
  ctx.fillRect(-6 + step, -8, 4, 8);
  ctx.fillRect(2 - step, -8, 4, 8);
  // Hunched robe, ragged hem.
  ctx.fillStyle = robe;
  ctx.beginPath();
  ctx.moveTo(-10, -26); ctx.quadraticCurveTo(-6, -42, 6, -36);
  ctx.lineTo(10, -6); ctx.lineTo(7, -2); ctx.lineTo(4, -6); ctx.lineTo(0, -1); ctx.lineTo(-4, -6); ctx.lineTo(-8, -1); ctx.lineTo(-11, -6);
  ctx.closePath();
  ctx.fill();
  // Hooded head, thrust forward.
  ctx.beginPath(); ctx.arc(8, -36, 7, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = flash ? "#fff" : C.flesh;
  ctx.fillRect(10, -37, 5, 6);
  ctx.fillStyle = e.gorged ? C.gorged : "#1a1412";
  ctx.fillRect(12, -36, 2, 1.5);
  if (e.gorged) embers(ctx, time, e.spawn.x);
  // The long arm and its claw.
  const th = clawAngle(e, time), sx = 4, sy = -30, len = 24;
  const ex = sx + Math.cos(th) * len, ey = sy + Math.sin(th) * len;
  ctx.strokeStyle = flash ? "#fff" : C.flesh;
  ctx.lineWidth = 2.5;
  ctx.lineCap = "round";
  ctx.beginPath(); ctx.moveTo(sx, sy); ctx.quadraticCurveTo(sx + Math.cos(th - 0.5) * 14, sy + Math.sin(th - 0.5) * 14, ex, ey); ctx.stroke();
  ctx.lineWidth = 1.5;
  for (const k of [-0.5, 0, 0.5]) {
    ctx.beginPath(); ctx.moveTo(ex, ey); ctx.lineTo(ex + Math.cos(th + k) * 7, ey + Math.sin(th + k) * 7); ctx.stroke();
  }
  ctx.lineCap = "butt";
  if (e.state === "strike") {
    ctx.strokeStyle = "rgba(201, 187, 161, 0.35)";
    ctx.lineWidth = 6;
    ctx.beginPath(); ctx.arc(sx, sy, len, -2.3, th); ctx.stroke();
  }
}

function hound(ctx, e, flash, time) {
  const body = flash ? "#fff" : e.gorged ? "#3a211c" : C.hound;
  const crouch = e.state === "windup" ? Math.min(1, e.t / 0.2) * 4 : 0;
  const stretch = e.state === "strike" ? 1.18 : 1;
  ctx.scale(stretch, 1);
  ctx.translate(0, crouch);
  const g = Math.sin(e.runT * 16) * 4;
  // Legs.
  ctx.strokeStyle = body;
  ctx.lineWidth = 3;
  for (const [x, ph] of [[-11, 1], [-7, -1], [6, -1], [10, 1]]) {
    ctx.beginPath(); ctx.moveTo(x, -10); ctx.lineTo(x + g * ph, -crouch); ctx.stroke();
  }
  // Body, ribs, tail.
  ctx.fillStyle = body;
  ctx.beginPath(); ctx.ellipse(-1, -14, 15, 6.5, -0.05, 0, Math.PI * 2); ctx.fill();
  ctx.strokeStyle = "rgba(0, 0, 0, 0.35)";
  ctx.lineWidth = 1;
  for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.moveTo(-4 + i * 4, -19); ctx.lineTo(-5 + i * 4, -10); ctx.stroke(); }
  ctx.strokeStyle = body;
  ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(-15, -15); ctx.quadraticCurveTo(-22, -20 + Math.sin(time * 6) * 3, -24, -12); ctx.stroke();
  // Head: low, jaw hanging.
  ctx.fillStyle = body;
  ctx.beginPath(); ctx.ellipse(13, -15, 7, 5, 0.15, 0, Math.PI * 2); ctx.fill();
  ctx.beginPath(); ctx.moveTo(9, -19); ctx.lineTo(11, -25); ctx.lineTo(13, -19); ctx.fill();
  ctx.fillRect(12, -12, 8, 2);
  ctx.fillStyle = flash ? "#fff" : C.flesh;
  for (let i = 0; i < 3; i++) ctx.fillRect(14 + i * 2, -13, 1, 2);
  ctx.fillStyle = e.gorged ? C.gorged : "#8a2a1e";
  ctx.fillRect(14, -17, 2, 1.5);
  if (e.gorged) embers(ctx, time, e.spawn.x);
}

function embers(ctx, time, seed) {
  ctx.fillStyle = C.gorged;
  for (let i = 0; i < 6; i++) {
    const t = (time * 0.7 + i / 6 + seed * 0.01) % 1;
    ctx.globalAlpha = (1 - t) * 0.9;
    ctx.fillRect(Math.sin(i * 2.7 + time * 2) * 9, -20 - t * 32, 1.5, 1.5);
  }
  ctx.globalAlpha = 1;
}

// Where the glint shows: the claw tip, or the hound's teeth.
export function weaponPoint(e) {
  const f = e.facing, cx = e.x + e.w / 2, fy = e.y + e.h;
  if (e.type === "hound") return { x: cx + f * 20, y: fy - 13 };
  const th = clawAngle(e, 0);
  return { x: cx + f * (4 + Math.cos(th) * 24), y: fy - 30 + Math.sin(th) * 24 };
}

function glint(ctx, at, t, time) {
  const s = 5 + Math.min(1, t / 0.08) * 9 - Math.max(0, t - 0.1) * 10;
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  const g = ctx.createRadialGradient(at.x, at.y, 0, at.x, at.y, s * 2.2);
  g.addColorStop(0, "rgba(255, 246, 216, 0.9)");
  g.addColorStop(1, "rgba(255, 246, 216, 0)");
  ctx.fillStyle = g;
  ctx.fillRect(at.x - s * 2.2, at.y - s * 2.2, s * 4.4, s * 4.4);
  ctx.fillStyle = C.glint;
  ctx.translate(at.x, at.y);
  ctx.rotate(time * 2);
  ctx.beginPath();
  for (let i = 0; i < 8; i++) {
    const r = i % 2 ? s * 0.18 : s;
    ctx.lineTo(Math.cos((i * Math.PI) / 4) * r, Math.sin((i * Math.PI) / 4) * r);
  }
  ctx.fill();
  ctx.restore();
}

function stunRing(ctx, e, time) {
  ctx.strokeStyle = `rgba(255, 246, 216, ${0.35 + 0.25 * Math.sin(time * 10)})`;
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.ellipse(e.x + e.w / 2, e.y - 4, 12, 4, 0, 0, Math.PI * 2);
  ctx.stroke();
}
