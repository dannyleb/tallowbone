// Particles, screen shake and the big centred banners.
export function createFx() {
  return { parts: [], shake: 0, banner: null, notice: null, motes: [] };
}

// count particles at (x, y). spread: speed range; up: extra upward kick;
// glow: drawn additively (embers, tallow light).
export function burst(fx, x, y, { count = 8, color = "#7a1414", spread = 160, up = 60, life = 0.6, size = 2.5, gravity = 900, glow = false, dir = 0 } = {}) {
  for (let i = 0; i < count; i++) {
    const a = Math.random() * Math.PI * 2, s = spread * (0.3 + Math.random() * 0.7);
    fx.parts.push({
      x, y,
      vx: Math.cos(a) * s + dir * spread * 0.6,
      vy: Math.sin(a) * s - up,
      life: life * (0.6 + Math.random() * 0.4), max: life,
      color, size: size * (0.6 + Math.random() * 0.8), gravity, glow,
    });
  }
}

export function shake(fx, amount) {
  fx.shake = Math.max(fx.shake, amount);
}

export function banner(fx, text, sub = "", dur = 2.4, tone = "pale") {
  fx.banner = { text, sub, t: 0, dur, tone };
}

// A quieter line near the top of the screen.
export function notice(fx, text, dur = 3.2) {
  fx.notice = { text, t: 0, dur };
}

// Tallow motes: little lights that drift from a kill to the HUD counter.
export function motes(fx, x, y, n) {
  for (let i = 0; i < n; i++) fx.motes.push({ x, y, vx: (Math.random() - 0.5) * 120, vy: -60 - Math.random() * 80, t: -i * 0.03 });
}

export function updateFx(fx, dt) {
  for (const p of fx.parts) {
    p.life -= dt;
    p.vy += p.gravity * dt;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
  }
  fx.parts = fx.parts.filter((p) => p.life > 0);
  for (const m of fx.motes) {
    m.t += dt;
    m.vx *= 0.96;
    m.vy = m.vy * 0.96 - 20 * dt;
    m.x += m.vx * dt;
    m.y += m.vy * dt;
  }
  fx.motes = fx.motes.filter((m) => m.t < 1.1);
  fx.shake = Math.max(0, fx.shake - dt * 30);
  if (fx.banner && (fx.banner.t += dt) > fx.banner.dur) fx.banner = null;
  if (fx.notice && (fx.notice.t += dt) > fx.notice.dur) fx.notice = null;
}
