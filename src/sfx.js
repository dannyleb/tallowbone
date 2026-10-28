// Placeholder sound effects, made on the fly with Web Audio (no files).
// They're here for feel and timing (the parry glint has to be heard as
// well as seen) and get replaced by real recordings later.
let ac = null, out = null, noiseBuf = null;

// Browsers only allow audio after a key press or click; call this then.
export function unlockAudio() {
  if (ac) { if (ac.state === "suspended") ac.resume(); return; }
  try {
    ac = new AudioContext();
    out = ac.createGain();
    out.gain.value = 0.45;
    out.connect(ac.destination);
    noiseBuf = ac.createBuffer(1, ac.sampleRate, ac.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  } catch { ac = null; }
}

function env(g, t, a, dur, peak) {
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(peak, t + a);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
}

function noise({ dur = 0.15, freq = 1000, to = freq, q = 1, type = "bandpass", gain = 0.4, delay = 0 }) {
  if (!ac) return;
  const t = ac.currentTime + delay;
  const src = ac.createBufferSource(), f = ac.createBiquadFilter(), g = ac.createGain();
  src.buffer = noiseBuf;
  f.type = type;
  f.Q.value = q;
  f.frequency.setValueAtTime(freq, t);
  f.frequency.exponentialRampToValueAtTime(to, t + dur);
  env(g, t, 0.005, dur, gain);
  src.connect(f).connect(g).connect(out);
  src.start(t, Math.random() * 0.5);
  src.stop(t + dur + 0.05);
}

function tone({ freq = 440, to = freq, dur = 0.2, type = "sine", gain = 0.2, attack = 0.005, delay = 0 }) {
  if (!ac) return;
  const t = ac.currentTime + delay;
  const o = ac.createOscillator(), g = ac.createGain();
  o.type = type;
  o.frequency.setValueAtTime(freq, t);
  o.frequency.exponentialRampToValueAtTime(to, t + dur);
  env(g, t, attack, dur, gain);
  o.connect(g).connect(out);
  o.start(t);
  o.stop(t + dur + 0.05);
}

export const sfx = {
  swing: () => noise({ dur: 0.12, freq: 700, to: 2600, q: 0.7, gain: 0.18 }),
  heavy: () => noise({ dur: 0.22, freq: 300, to: 1400, q: 0.6, gain: 0.25 }),
  hit: () => { noise({ dur: 0.09, freq: 500, to: 200, q: 0.8, gain: 0.5 }); tone({ freq: 140, to: 60, dur: 0.1, type: "square", gain: 0.12 }); },
  shot: () => { noise({ dur: 0.2, freq: 2400, to: 600, type: "lowpass", gain: 0.6 }); tone({ freq: 110, to: 40, dur: 0.14, gain: 0.4 }); },
  click: () => tone({ freq: 900, to: 700, dur: 0.05, type: "square", gain: 0.06 }),
  glint: () => { tone({ freq: 2093, dur: 0.18, type: "triangle", gain: 0.12 }); tone({ freq: 3136, dur: 0.12, type: "sine", gain: 0.06, delay: 0.02 }); },
  parry: () => { tone({ freq: 1568, to: 1480, dur: 0.6, type: "triangle", gain: 0.22 }); tone({ freq: 2349, dur: 0.45, gain: 0.1, delay: 0.01 }); noise({ dur: 0.1, freq: 3000, gain: 0.3 }); },
  visceral: () => { tone({ freq: 90, to: 35, dur: 0.4, type: "sawtooth", gain: 0.25 }); noise({ dur: 0.35, freq: 400, to: 120, q: 0.5, gain: 0.6, delay: 0.05 }); },
  dash: () => noise({ dur: 0.14, freq: 1600, to: 500, q: 0.5, gain: 0.14 }),
  jump: () => noise({ dur: 0.08, freq: 600, to: 1200, q: 0.8, gain: 0.07 }),
  hurt: () => { tone({ freq: 220, to: 90, dur: 0.25, type: "sawtooth", gain: 0.16 }); noise({ dur: 0.12, freq: 300, gain: 0.35 }); },
  splash: () => noise({ dur: 0.4, freq: 900, to: 300, q: 0.4, gain: 0.4 }),
  heal: () => { tone({ freq: 392, to: 523, dur: 0.4, gain: 0.12, attack: 0.08 }); },
  blood: () => { noise({ dur: 0.15, freq: 800, to: 300, gain: 0.3 }); tone({ freq: 180, to: 120, dur: 0.2, type: "triangle", gain: 0.12 }); },
  burn: () => { noise({ dur: 0.5, freq: 1200, to: 400, q: 0.3, gain: 0.3 }); noise({ dur: 0.3, freq: 4000, type: "highpass", gain: 0.1, delay: 0.1 }); },
  lamp: () => { for (const [f, d] of [[196, 0], [294, 0.08], [392, 0.16]]) tone({ freq: f, dur: 1.4, type: "triangle", gain: 0.09, attack: 0.15, delay: d }); },
  tallow: () => tone({ freq: 1320, to: 1760, dur: 0.12, type: "sine", gain: 0.05 }),
  gorge: () => { tone({ freq: 120, to: 70, dur: 0.8, type: "sawtooth", gain: 0.12, attack: 0.2 }); },
  death: () => { tone({ freq: 110, to: 55, dur: 2.2, type: "sawtooth", gain: 0.15, attack: 0.05 }); tone({ freq: 116, to: 58, dur: 2.2, type: "sine", gain: 0.15, attack: 0.05 }); },
  buy: () => { tone({ freq: 659, dur: 0.25, type: "triangle", gain: 0.12 }); tone({ freq: 988, dur: 0.35, type: "triangle", gain: 0.1, delay: 0.08 }); },
  deny: () => tone({ freq: 160, to: 140, dur: 0.15, type: "square", gain: 0.06 }),
};
