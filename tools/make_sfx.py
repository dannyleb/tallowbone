"""Placeholder sound effects, synthesized into assets/sfx/*.wav.

The same recipes the browser prototype played live: filtered-noise
sweeps and sliding tones. They exist for feel and timing (the parry glint
has to be heard as well as seen) until real recordings replace them.

Run from the repo root:  python3 tools/make_sfx.py
"""
import math
import random
import struct
import wave

RATE = 22050


def env(i, n, attack, dur):
    t = i / RATE
    if t < attack:
        return t / attack
    return max(0.0, math.exp(-5.0 * (t - attack) / max(1e-3, dur - attack)))


def noise(dur=0.15, freq=1000, to=None, q=1.0, kind="band", gain=0.4, delay=0.0):
    to = to or freq
    rnd = random.Random(int(freq * 7 + dur * 1000))
    n = int((dur + delay) * RATE)
    out = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    for i in range(int(delay * RATE), n):
        k = (i - delay * RATE) / max(1, dur * RATE)
        f = freq * (to / freq) ** k
        w = 2 * math.pi * min(f, RATE * 0.45) / RATE
        alpha = math.sin(w) / (2 * q)
        cw = math.cos(w)
        if kind == "band":
            b0, b1, b2 = alpha, 0.0, -alpha
        elif kind == "low":
            b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
        else:
            b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
        x = rnd.uniform(-1, 1)
        y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, x, y1, y
        out[i] = y * gain * env(i - int(delay * RATE), n, 0.005, dur)
    return out


def tone(freq=440, to=None, dur=0.2, wave_="sine", gain=0.2, attack=0.005, delay=0.0):
    to = to or freq
    n = int((dur + delay) * RATE)
    out = [0.0] * n
    phase = 0.0
    for i in range(int(delay * RATE), n):
        k = (i - delay * RATE) / max(1, dur * RATE)
        phase += freq * (to / freq) ** k / RATE
        p = phase % 1.0
        if wave_ == "sine":
            v = math.sin(2 * math.pi * p)
        elif wave_ == "triangle":
            v = 4 * abs(p - 0.5) - 1
        elif wave_ == "square":
            v = 1.0 if p < 0.5 else -1.0
        else:
            v = 2 * p - 1
        out[i] = v * gain * env(i - int(delay * RATE), n, attack, dur)
    return out


def mixdown(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, v in enumerate(p):
            out[i] += v
    return out


SOUNDS = {
    "swing": lambda: noise(0.12, 700, 2600, q=0.7, gain=0.5),
    "heavy": lambda: noise(0.22, 300, 1400, q=0.6, gain=0.7),
    "hit": lambda: mixdown(noise(0.09, 500, 200, q=0.8, gain=1.2), tone(140, 60, 0.1, "square", 0.12)),
    "shot": lambda: mixdown(noise(0.2, 2400, 600, kind="low", gain=0.9), tone(110, 40, 0.14, gain=0.4)),
    "click": lambda: tone(900, 700, 0.05, "square", 0.06),
    "glint": lambda: mixdown(tone(2093, None, 0.18, "triangle", 0.18), tone(3136, None, 0.12, "sine", 0.09, delay=0.02)),
    "parry": lambda: mixdown(tone(1568, 1480, 0.6, "triangle", 0.25), tone(2349, None, 0.45, "sine", 0.12, delay=0.01), noise(0.1, 3000, gain=0.6)),
    "visceral": lambda: mixdown(tone(90, 35, 0.4, "saw", 0.3), noise(0.35, 400, 120, q=0.5, gain=1.3, delay=0.05)),
    "dash": lambda: noise(0.14, 1600, 500, q=0.5, gain=0.4),
    "jump": lambda: noise(0.08, 600, 1200, q=0.8, gain=0.25),
    "hurt": lambda: mixdown(tone(220, 90, 0.25, "saw", 0.18), noise(0.12, 300, gain=0.8)),
    "splash": lambda: noise(0.4, 900, 300, q=0.4, gain=1.0),
    "heal": lambda: tone(392, 523, 0.4, "sine", 0.18, attack=0.08),
    "blood": lambda: mixdown(noise(0.15, 800, 300, gain=0.7), tone(180, 120, 0.2, "triangle", 0.14)),
    "burn": lambda: mixdown(noise(0.5, 1200, 400, q=0.3, gain=0.8), noise(0.3, 4000, kind="high", gain=0.15, delay=0.1)),
    "lamp": lambda: mixdown(*[tone(f, None, 1.4, "triangle", 0.1, attack=0.15, delay=d) for f, d in ((196, 0), (294, 0.08), (392, 0.16))]),
    "tallow": lambda: tone(1320, 1760, 0.12, "sine", 0.08),
    "gorge": lambda: tone(120, 70, 0.8, "saw", 0.14, attack=0.2),
    "death": lambda: mixdown(tone(110, 55, 2.2, "saw", 0.15, attack=0.05), tone(116, 58, 2.2, "sine", 0.15, attack=0.05)),
    "buy": lambda: mixdown(tone(659, None, 0.25, "triangle", 0.15), tone(988, None, 0.35, "triangle", 0.12, delay=0.08)),
    "deny": lambda: tone(160, 140, 0.15, "square", 0.07),
}


def write(name, samples):
    peak = max(1e-6, max(abs(v) for v in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(f"assets/sfx/{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * scale)) * 32767)) for v in samples))


if __name__ == "__main__":
    for name, make in SOUNDS.items():
        write(name, make())
    print(f"wrote {len(SOUNDS)} sounds to assets/sfx/")
