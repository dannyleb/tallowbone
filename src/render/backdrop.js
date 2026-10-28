import { C } from "./palette.js";

// The sky and the city behind the play space: a moon, two layers of
// rooftops and spires that drift slower than you (parallax), and fog.
// Everything is generated from a fixed seed, so the skyline is the same
// every time. Drawn in view space (0..viewW, 0..360).

function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function skyline(seed, { minH, maxH, spires, windows }) {
  const r = rng(seed), shapes = [];
  let x = 0;
  while (x < 1600) {
    const w = 28 + r() * 64, h = minH + r() * (maxH - minH);
    const roll = r();
    const roof = roll < spires ? "spire" : roll < spires + 0.35 ? "gable" : "flat";
    const s = { x, w, h, roof, spireH: 50 + r() * 110, chimney: r() < 0.45, lit: [] };
    for (let i = 0; i < 4; i++) if (r() < windows) s.lit.push({ x: 5 + r() * (w - 12), y: 14 + r() * (h - 24), on: r() });
    shapes.push(s);
    x += w + (r() < 0.25 ? 6 + r() * 18 : 0);
  }
  return { width: x, shapes };
}

const FAR = skyline(7, { minH: 70, maxH: 170, spires: 0.22, windows: 0.12 });
// The near layer keeps to rooftops: a spire this close reads as part of
// the play space.
const MID = skyline(23, { minH: 40, maxH: 110, spires: 0, windows: 0.3 });

function drawLayer(ctx, layer, offset, base, color, viewW, time) {
  const start = -(((offset % layer.width) + layer.width) % layer.width);
  for (let k = start; k < viewW; k += layer.width) {
    ctx.fillStyle = color;
    ctx.beginPath();
    for (const s of layer.shapes) {
      const x = k + s.x, top = base - s.h;
      if (x > viewW || x + s.w < 0) continue;
      ctx.rect(x, top, s.w, 600);
      if (s.roof === "spire") {
        ctx.moveTo(x + s.w * 0.3, top); ctx.lineTo(x + s.w / 2, top - s.spireH); ctx.lineTo(x + s.w * 0.7, top);
      } else if (s.roof === "gable") {
        ctx.moveTo(x - 2, top); ctx.lineTo(x + s.w / 2, top - s.w * 0.45); ctx.lineTo(x + s.w + 2, top);
      }
      if (s.chimney) ctx.rect(x + s.w * 0.7, top - 14, 6, 14);
    }
    ctx.fill();
    // A few lit windows; one now and then flickers.
    for (const s of layer.shapes) {
      const x = k + s.x;
      if (x > viewW || x + s.w < 0) continue;
      for (const w of s.lit) {
        const flick = w.on > 0.85 ? 0.5 + 0.5 * Math.sin(time * 3 + w.on * 40) : 1;
        ctx.fillStyle = `rgba(232, 169, 79, ${0.55 * flick})`;
        ctx.fillRect(x + w.x, base - s.h + w.y, 3, 5);
      }
    }
  }
}

export function drawBackdrop(ctx, cam, viewW, viewH, time) {
  // How far the camera is from the street-level view, for vertical drift.
  const dy = cam.y - 440;
  const sky = ctx.createLinearGradient(0, 0, 0, viewH);
  sky.addColorStop(0, C.skyTop);
  sky.addColorStop(0.75, C.skyLow);
  sky.addColorStop(1, "#202a36");
  ctx.fillStyle = sky;
  ctx.fillRect(0, 0, viewW, viewH);

  // The moon, nearly still.
  const mx = viewW * 0.74 - cam.x * 0.01, my = 92 - dy * 0.04;
  const halo = ctx.createRadialGradient(mx, my, 20, mx, my, 190);
  halo.addColorStop(0, "rgba(225, 228, 236, 0.22)");
  halo.addColorStop(1, "rgba(225, 228, 236, 0)");
  ctx.fillStyle = halo;
  ctx.fillRect(mx - 190, my - 190, 380, 380);
  ctx.fillStyle = C.moon;
  ctx.beginPath(); ctx.arc(mx, my, 34, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = "rgba(120, 110, 100, 0.12)";
  for (const [ox, oy, r] of [[-10, -8, 9], [12, 6, 6], [-4, 14, 5], [9, -14, 4]]) {
    ctx.beginPath(); ctx.arc(mx + ox, my + oy, r, 0, Math.PI * 2); ctx.fill();
  }

  drawLayer(ctx, FAR, cam.x * 0.15, 268 - dy * 0.12, C.far, viewW, time);
  fog(ctx, viewW, 230 - dy * 0.15, 90, 0.16, time * 4);
  drawLayer(ctx, MID, cam.x * 0.38, 318 - dy * 0.3, C.mid, viewW, time);
  fog(ctx, viewW, 300 - dy * 0.3, 70, 0.1, time * 9);
}

function fog(ctx, viewW, y, h, alpha, drift) {
  const g = ctx.createLinearGradient(0, y - h, 0, y + h);
  g.addColorStop(0, "rgba(90, 104, 122, 0)");
  g.addColorStop(0.5, `rgba(90, 104, 122, ${alpha})`);
  g.addColorStop(1, "rgba(90, 104, 122, 0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, y - h, viewW, h * 2);
  // Slow drifting wisps on top of the band.
  ctx.fillStyle = `rgba(110, 124, 140, ${alpha * 0.5})`;
  for (let i = 0; i < 5; i++) {
    const x = ((i * 233 + drift) % (viewW + 300)) - 150;
    ctx.beginPath();
    ctx.ellipse(x, y + Math.sin(i * 1.7) * h * 0.3, 140, 14, 0, 0, Math.PI * 2);
    ctx.fill();
  }
}
