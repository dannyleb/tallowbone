"""The night's soundscape, synthesized into assets/ambience/*.ogg.

Beds (seamless loops, played all the time and mixed by scripts/ambience.gd):
  rain_out   rain on stone and puddles, a drainpipe running off to the left
  rain_in    the same rain heard from under a roof: muffled, with cave drips
  wind       gusts that swell and fall, whistling through gaps when strong
  water      the canal lapping at its walls
  drone      the low dread under everything: beating sub tones, a tritone,
             a hummed choir, glass harmonics

One-shots (distance and reverb baked in; the web build can't run bus
effects, so nothing is added at runtime):
  howl_a/b/c        wolves far off; the third is not a wolf
  bell              a cracked church bell tolling somewhere in the city
  thunder_near/mid/far
  whisper_a/b/c     voices with no words; the third runs backwards
  call              something enormous, very far away
  creak_a/b         a hanging sign and an iron gate in the wind

Bodies (to assets/sfx/, several takes each, for scripts/sfx.gd):
  step_stone, step_wood, land   boots on wet stone and planks, a landing
  growl, snarl                  the Hound's windup and bite
  moan                          a Communicant before it strikes

Every loop is built circularly (noise shaped in the frequency domain,
events and reverb wrapped around the end), so it repeats without a seam.
Tones in loops are rounded to whole cycles per loop for the same reason.

Run from the repo root (needs numpy, scipy and ffmpeg with libvorbis):
  python3 tools/make_ambience.py
"""
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy import signal

SR = 32000
OUT = "assets/ambience"


# ---------------------------------------------------------------- basics

def rng(seed):
    return np.random.default_rng(seed)


def secs(t):
    return int(round(t * SR))


def times(n):
    return np.arange(n) / SR


def pan_gains(p):
    """Equal-power gains for a pan from -1 (left) to 1 (right)."""
    a = (p + 1) * np.pi / 4
    return np.cos(a), np.sin(a)


def place(out, x, at, p=0.0, gain=1.0, wrap=False):
    """Adds mono x into stereo out at sample `at`, panned; wraps past the
    end when the output is a loop."""
    gl, gr = pan_gains(p)
    n = out.shape[1]
    end = at + len(x)
    if wrap:
        idx = np.arange(at, end) % n
        np.add.at(out[0], idx, x * gl * gain)
        np.add.at(out[1], idx, x * gr * gain)
        return
    end = min(end, n)
    if at >= n:
        return
    out[0, at:end] += x[: end - at] * gl * gain
    out[1, at:end] += x[: end - at] * gr * gain


def shape(x, gain_fn):
    """Filters along the last axis in the frequency domain (zero phase,
    circular): gain_fn(freqs in Hz) -> gain."""
    n = x.shape[-1]
    f = np.fft.rfftfreq(n, 1 / SR)
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * gain_fn(f), n, axis=-1)


def lowpass_curve(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order))


def highpass_curve(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def band_curve(lo, hi, order=2):
    a, b = lowpass_curve(hi, order), highpass_curve(lo, order)
    return lambda f: a(f) * b(f)


def reson_curve(f0, q):
    """A resonant band around f0 (peak gain 1)."""
    return lambda f: 1 / np.sqrt(1 + q * q * (np.maximum(f, 1e-3) / f0 - f0 / np.maximum(f, 1e-3)) ** 2)


def noise(n, r, colour="white"):
    x = r.standard_normal(n)
    if colour == "white":
        return x
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    X = np.fft.rfft(x) / (np.sqrt(f) if colour == "pink" else f)
    y = np.fft.irfft(X, n)
    return y / np.std(y)


def smooth_random(n, r, cutoff, lo=0.0, hi=1.0):
    """A random curve that changes no faster than `cutoff` Hz and loops
    over n samples, scaled into [lo, hi]."""
    y = shape(r.standard_normal(n), lambda f: (f < cutoff) * (f > 0))
    y = (y - y.min()) / max(1e-9, y.max() - y.min())
    return lo + (hi - lo) * y


def butter(x, kind, f, order=2):
    sos = signal.butter(order, f, btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def env_adsr(n, attack, release, curve=2.0):
    t = times(n)
    dur = n / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((dur - t) / max(release, 1e-4), 0, 1)
    return (a * r) ** curve


def loop_freq(f, length):
    """f rounded to a whole number of cycles in `length` seconds."""
    return round(f * length) / length


# ---------------------------------------------------------------- reverb

def impulse(rt60, length, r, bright=7000.0, dark=900.0, pre=0.015, width=1.0):
    """A stereo room: decaying noise that darkens as it dies, early
    reflections in front."""
    n = secs(length)
    t = times(n)
    decay = 10 ** (-3 * t / rt60)
    w = np.clip(t / rt60, 0, 1) ** 0.6
    chans = []
    for _ in range(2):
        x = r.standard_normal(n) * decay
        x = butter(x, "low", bright) * (1 - w) + butter(x, "low", dark) * w
        er = np.zeros(n)
        for _ in range(8):
            i = secs(r.uniform(0.004, 0.06))
            er[i] += r.uniform(-1, 1) * 2.0
        x = x + butter(er, "low", bright)
        x = np.concatenate([np.zeros(secs(pre)), x])[:n]
        chans.append(x)
    ir = np.stack(chans)
    mid = ir.mean(axis=0, keepdims=True)
    ir = mid + (ir - mid) * width
    return ir / np.sqrt(np.sum(ir ** 2) / 2)


def reverb(dry, ir, wet=0.5, loop=False):
    """dry: stereo. Returns dry + reverb (longer by the tail unless loop,
    where the tail wraps round to the start)."""
    if loop:
        n = dry.shape[1]
        m = ir.shape[1]
        if m > n:
            ir = ir[:, :n]
        pad = np.zeros_like(dry)
        pad[:, : ir.shape[1]] = ir
        w = np.fft.irfft(np.fft.rfft(dry, axis=-1) * np.fft.rfft(pad, axis=-1), n, axis=-1)
        return dry * (1 - wet) + w * wet
    tail = ir.shape[1]
    out = np.zeros((2, dry.shape[1] + tail))
    w = np.stack([signal.fftconvolve(dry[c], ir[c]) for c in range(2)])
    out[:, : dry.shape[1]] += dry * (1 - wet)
    out[:, : w.shape[1]] += w * wet
    return out


def trim_tail(x, floor_db=-70):
    """Cuts the silent end off a one-shot."""
    mag = np.max(np.abs(x), axis=0)
    above = np.nonzero(mag > np.max(mag) * 10 ** (floor_db / 20))[0]
    end = min(x.shape[1], (above[-1] if len(above) else 0) + secs(0.05))
    x = x[:, :end].copy()
    fade = min(secs(0.3), end)
    x[:, end - fade:] *= np.linspace(1, 0, fade) ** 2
    return x


# ---------------------------------------------------------------- pieces

def bubble(r, f0, dur, rise=0.4, click=0.0):
    """A drop into water: a sine that rises as the bubble shrinks (the
    sound of rain on puddles), with an optional impact click."""
    n = secs(dur * 5)
    t = times(n)
    f = f0 * (1 + rise * t / dur)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / dur)
    x *= np.clip(t / 0.0008, 0, 1)
    if click > 0:
        c = r.standard_normal(secs(0.002)) * np.linspace(1, 0, secs(0.002))
        x[: len(c)] += c * click
    return x


def tick(r, f0, dur):
    """A drop on stone: a tiny bright click."""
    n = secs(dur * 4)
    t = times(n)
    x = r.standard_normal(n) * np.exp(-t / dur)
    return butter(x, "band", [f0 * 0.6, min(f0 * 1.6, SR * 0.45)])


def additive(f, partials, amps_fn=None):
    """Harmonic tone with time-varying fundamental f (array, Hz).
    partials: list of (harmonic number, amplitude). amps_fn(k, f_k) can
    weight each partial over time (formants)."""
    phase = 2 * np.pi * np.cumsum(f) / SR
    out = np.zeros(len(f))
    for k, a in partials:
        fk = f * k
        g = a * (fk < SR * 0.45)
        if amps_fn is not None:
            g = g * amps_fn(k, fk)
        out += g * np.sin(k * phase)
    return out


def formant_gain(fk, centre, bw):
    return 1 / (1 + ((fk - centre) / bw) ** 2)


def glide(points, n):
    """Piecewise curve through (time s, value) points, smoothed."""
    t = times(n)
    ts = [p[0] for p in points]
    vs = [p[1] for p in points]
    y = np.interp(t, ts, vs)
    k = secs(0.08)
    if k > 1:
        y = np.convolve(np.pad(y, (k, k), mode="edge"), np.ones(k) / k, mode="same")[k:-k]
    return y


# ---------------------------------------------------------------- beds

def rain_out():
    L = 32.0
    n = secs(L)
    r = rng(11)
    out = np.zeros((2, n))
    gust = smooth_random(n, r, 0.12, 0.7, 1.15)
    # The hiss of rain on everything, and the roar of it on the roofs.
    for c in range(2):
        out[c] += 0.16 * shape(noise(n, r, "pink"), band_curve(500, 8000)) * gust
        out[c] += 0.10 * shape(noise(n, r, "brown"), band_curve(60, 380)) * gust
    # Drops on stone: thousands of small ticks.
    ticks = [tick(r, r.uniform(2500, 6500), r.uniform(0.0008, 0.0025)) for _ in range(48)]
    for _ in range(int(L * 700)):
        place(out, ticks[r.integers(len(ticks))], r.integers(n), r.uniform(-1, 1), r.uniform(0.01, 0.06), wrap=True)
    # Drops into puddles: the wet, rising plinks.
    plinks = [bubble(r, r.uniform(700, 2600), r.uniform(0.006, 0.02), r.uniform(0.2, 0.7), click=0.3) for _ in range(64)]
    for _ in range(int(L * 55)):
        place(out, plinks[r.integers(len(plinks))], r.integers(n), r.uniform(-0.9, 0.9), r.uniform(0.02, 0.16) * r.uniform(0.3, 1) ** 2, wrap=True)
    # A drainpipe pouring onto the setts, off to the left.
    pour = shape(noise(n, r), band_curve(700, 3500)) * smooth_random(n, r, 3.0, 0.6, 1.0)
    place(out, pour * 0.045, 0, -0.65, wrap=True)
    gurgle = [bubble(r, r.uniform(400, 1400), r.uniform(0.01, 0.03), r.uniform(0.3, 0.9)) for _ in range(32)]
    for _ in range(int(L * 30)):
        place(out, gurgle[r.integers(len(gurgle))], r.integers(n), r.uniform(-0.8, -0.5), r.uniform(0.02, 0.07), wrap=True)
    return reverb(out, impulse(1.2, 1.5, r, bright=6000, dark=1500), wet=0.25, loop=True)


def rain_in():
    L = 32.0
    n = secs(L)
    r = rng(12)
    out = np.zeros((2, n))
    # Rain on the roof far above: only the low roar gets through.
    for c in range(2):
        out[c] += 0.22 * shape(noise(n, r, "pink"), band_curve(40, 320)) * smooth_random(n, r, 0.1, 0.75, 1.1)
        out[c] += 0.02 * shape(noise(n, r, "pink"), band_curve(900, 2500))
    # Drips from the vault: four places, each with its own note and rhythm.
    for spot in range(5):
        f = r.uniform(900, 2400)
        p = r.uniform(-0.9, 0.9)
        every = r.uniform(1.1, 3.2)
        t = r.uniform(0, every)
        while t < L:
            d = bubble(r, f * r.uniform(0.97, 1.03), r.uniform(0.012, 0.03), r.uniform(0.3, 0.6), click=0.15)
            place(out, d, secs(t), p, r.uniform(0.15, 0.32), wrap=True)
            t += every * r.uniform(0.85, 1.15)
    # Water running somewhere in the walls.
    trickle = shape(noise(n, r), band_curve(1200, 3200)) * smooth_random(n, r, 2.0, 0.3, 1.0)
    place(out, trickle * 0.012, 0, 0.6, wrap=True)
    return reverb(out, impulse(3.2, 4.0, r, bright=5000, dark=700), wet=0.55, loop=True)


def wind():
    """The gust is the whole shape: louder and higher as it rises, and when
    it is strong enough, a whistle through gaps in the stone."""
    L = 48.0
    n = secs(L)
    r = rng(13)
    out = np.zeros((2, n))
    gust = smooth_random(n, r, 0.07) ** 1.3
    flutter = smooth_random(n, r, 1.5, 0.8, 1.0)
    bands = np.geomspace(110, 1500, 14)
    for c in range(2):
        g = np.roll(gust, secs(0.4) * c) * flutter
        centre = 160 * 5 ** g
        body = np.zeros(n)
        total = np.zeros(n)
        for fb in bands:
            w = np.exp(-((np.log(fb) - np.log(centre)) / 0.45) ** 2)
            body += w * shape(noise(n, r, "pink"), reson_curve(fb, 2.2))
            total += w * w
        body /= np.sqrt(total + 1e-6)
        out[c] += body * (0.15 + 0.85 * g) * 0.5
        out[c] += 0.25 * shape(noise(n, r, "brown"), band_curve(25, 110)) * g ** 2
    # Whistles: narrow, sliding, only in the strongest gusts.
    for side, p in ((0, -0.5), (1, 0.6)):
        g2 = np.roll(gust, secs(r.uniform(1, 4)))
        on = np.clip((g2 - 0.35) / 0.4, 0, 1) ** 1.5
        pitch = 420 * 3 ** smooth_random(n, r, 0.09)
        wb = np.geomspace(380, 1500, 22)
        wh = np.zeros(n)
        total = np.zeros(n)
        for fb in wb:
            w = np.exp(-((np.log(fb) - np.log(pitch)) / 0.06) ** 2)
            band = shape(noise(n, r), reson_curve(fb, 40))
            wh += w * band / np.std(band)
            total += w * w
        wh /= np.sqrt(total + 1e-6)
        place(out, wh * on * 0.1, 0, p, wrap=True)
    return reverb(out, impulse(2.0, 2.5, r, bright=5000, dark=900), wet=0.3, loop=True)


def water():
    L = 24.0
    n = secs(L)
    r = rng(14)
    out = np.zeros((2, n))
    waves = np.zeros(n)
    t = 0.0
    hits = []
    while t < L:
        a = secs(t)
        size = r.uniform(0.4, 1.0)
        rise, fall = r.uniform(0.3, 0.6), r.uniform(0.6, 1.2)
        k = np.arange(secs(rise + fall))
        e = np.where(k < secs(rise), k / secs(rise), np.exp(-(k - secs(rise)) / secs(fall) * 2.5))
        idx = (a + k) % n
        np.add.at(waves, idx, e * size)
        hits.append((t + rise, size))
        t += r.uniform(1.3, 3.2)
    for c in range(2):
        lap = shape(noise(n, r, "pink"), band_curve(80, 900))
        out[c] += 0.3 * lap * (0.25 + np.roll(waves, secs(0.15) * c))
    for at, size in hits:
        slap = r.standard_normal(secs(0.25)) * np.exp(-times(secs(0.25)) / 0.05)
        slap = butter(slap, "band", [250, 2200])
        place(out, slap, secs(at), r.uniform(-0.7, 0.7), 0.25 * size, wrap=True)
        for _ in range(r.integers(2, 6)):
            b = bubble(r, r.uniform(160, 600), r.uniform(0.02, 0.05), r.uniform(0.2, 0.6))
            place(out, b, secs(at + r.uniform(0, 0.6)), r.uniform(-0.8, 0.8), r.uniform(0.04, 0.12), wrap=True)
    return reverb(out, impulse(1.8, 2.2, r, bright=4000, dark=800), wet=0.35, loop=True)


def drone():
    """Under everything: two sub tones beating against each other, a
    tritone cluster that swells and recedes, a choir humming one note with
    no breath, and glass harmonics that come and go."""
    L = 60.0
    n = secs(L)
    t = times(n)
    r = rng(15)
    out = np.zeros((2, n))
    lf = lambda period: loop_freq(1 / period, L)

    def tone(f, partials, vib=0.0, vib_rate=0.25):
        f = loop_freq(f, L)
        ph = 2 * np.pi * (f * t + (vib * f / (2 * np.pi * lf(1 / vib_rate))) * np.sin(2 * np.pi * lf(1 / vib_rate) * t))
        return sum(a * np.sin(k * ph) for k, a in partials)

    sub = tone(36.7, [(1, 1.0), (2, 0.35), (3, 0.12)]) + tone(37.1, [(1, 1.0), (2, 0.35), (3, 0.12)])
    out += 0.07 * sub
    saw = [(k, 1 / k) for k in range(1, 14)]
    for f, period, p in ((73.4, 12.0, -0.3), (103.8, 20.0, 0.35), (110.1, 15.0, 0.0)):
        swell = 0.5 - 0.5 * np.cos(2 * np.pi * lf(period) * t + r.uniform(0, 6.28))
        x = shape(tone(f, saw, vib=0.002), lowpass_curve(420, 2))
        place(out, x * swell * 0.1, 0, p)
    # The choir: D3 hummed on an "oo", formants fixed, very slow vibrato.
    choir_f = loop_freq(146.8, L)
    for detune, p in ((1.0, -0.6), (1.004, 0.6), (0.997, 0.0)):
        parts = [(k, 1 / k * formant_gain(choir_f * k, 320, 90) + 0.4 / k * formant_gain(choir_f * k, 800, 150)) for k in range(1, 24)]
        x = tone(146.8 * detune, parts, vib=0.006, vib_rate=0.2)
        breath = 0.5 - 0.5 * np.cos(2 * np.pi * lf(30.0) * t + r.uniform(0, 6.28))
        place(out, x * breath * 0.06, 0, p)
    # Glass: tones in no key, each blooming once or twice a loop.
    for f in (1174.7 * 1.0, 1174.7 * 1.414, 1174.7 * 1.732, 1174.7 * 2.236, 587.3 * 2.618):
        bloom = (0.5 - 0.5 * np.cos(2 * np.pi * lf(r.choice([20.0, 30.0, 60.0])) * t + r.uniform(0, 6.28))) ** 4
        place(out, tone(f, [(1, 1.0)]) * bloom * 0.012, 0, r.uniform(-0.9, 0.9))
    # A faint rushing, like blood in the ears.
    for c in range(2):
        out[c] += 0.03 * shape(noise(n, r, "pink"), band_curve(150, 1200))
    return reverb(out, impulse(6.0, 7.0, r, bright=3500, dark=500), wet=0.6, loop=True)


# ---------------------------------------------------------------- one-shots

def wolf(r, contour, dur, harsh=0.0):
    n = secs(dur)
    f = glide(contour, n)
    f = f * (1 + 0.012 * np.sin(2 * np.pi * 5.2 * times(n)) * np.clip(times(n) / 0.8, 0, 1))
    f = f * (1 + 0.004 * smooth_random(n, r, 8.0, -1, 1))
    parts = [(1, 1.0), (2, 0.55), (3, 0.22), (4, 0.12), (5, 0.06), (6, 0.03)]
    x = additive(f, parts, lambda k, fk: formant_gain(fk, 900, 700) + 0.3)
    breath = butter(r.standard_normal(n), "band", [600, 2400]) * 0.04
    x = (x + breath * (1 + harsh * 4)) * env_adsr(n, 0.25, 1.2, 1.5)
    return x


def howl_a():
    r = rng(21)
    dry = np.zeros((2, secs(6)))
    w = wolf(r, [(0, 410), (0.45, 640), (1.8, 670), (2.6, 610), (3.4, 470), (3.9, 380)], 4.0)
    place(dry, butter(w, "low", 1600), secs(0.1), -0.65, 0.5)
    return trim_tail(reverb(dry, impulse(4.0, 5.0, r, bright=3000, dark=600), wet=0.75))


def howl_b():
    """Two of them, answering each other a tritone apart."""
    r = rng(22)
    dry = np.zeros((2, secs(8)))
    a = wolf(r, [(0, 360), (0.4, 560), (1.6, 590), (2.5, 520), (3.2, 400)], 3.4)
    b = wolf(r, [(0, 520), (0.5, 800), (2.0, 830), (2.8, 760), (3.6, 560)], 3.8)
    place(dry, butter(a, "low", 1500), secs(0.1), 0.45, 0.45)
    place(dry, butter(b, "low", 1100), secs(1.7), 0.85, 0.3)
    return trim_tail(reverb(dry, impulse(4.5, 5.5, r, bright=2800, dark=500), wet=0.8))


def howl_c():
    """Starts as a wolf. Then it splits: one voice drops far below any
    throat, the other climbs, and it doesn't stop when it should."""
    r = rng(23)
    dry = np.zeros((2, secs(10)))
    n = secs(7.5)
    t = times(n)
    lo = glide([(0, 450), (0.5, 620), (1.8, 640), (3.0, 300), (4.5, 110), (7.5, 70)], n)
    hi = glide([(0, 450), (0.5, 620), (1.8, 640), (3.0, 900), (4.5, 1150), (7.5, 1210)], n)
    vib = 1 + 0.015 * np.sin(2 * np.pi * 4.7 * t) * np.clip(t / 0.8, 0, 1)
    parts = [(1, 1.0), (2, 0.6), (3, 0.3), (4, 0.18), (5, 0.1), (6, 0.06), (7, 0.04)]
    low = additive(lo * vib, parts + [(k, 0.05) for k in range(8, 20)])
    high = additive(hi * vib * 1.002, parts[:4])
    split = np.clip((t - 2.2) / 1.5, 0, 1)
    voice = low * (1 - 0.3 * split) + high * split * 0.45
    voice *= 1 + 0.6 * split * np.sin(2 * np.pi * 31 * t)
    voice *= env_adsr(n, 0.3, 0.4, 1.2)
    voice += butter(r.standard_normal(n), "band", [200, 1600]) * 0.05 * split * env_adsr(n, 0.3, 0.4)
    place(dry, butter(voice, "low", 1400), secs(0.1), -0.25, 0.45)
    return trim_tail(reverb(dry, impulse(5.5, 7.0, r, bright=2500, dark=400), wet=0.8))


def bell():
    """A big bell, slightly cracked (its partials beat), across the city."""
    r = rng(24)
    n = secs(16)
    t = times(n)
    prime = 130.8
    partials = [  # ratio to prime, amplitude, seconds to fade by e
        (0.5, 0.55, 4.5), (1.0, 0.6, 3.2), (1.183, 0.5, 2.6), (1.5, 0.25, 1.8), (2.0, 0.7, 1.6),
        (2.52, 0.22, 1.0), (2.66, 0.15, 0.8), (3.01, 0.16, 0.65), (4.07, 0.1, 0.45), (5.1, 0.05, 0.3),
    ]
    x = np.zeros(n)
    for ratio, a, tau in partials:
        f = prime * ratio
        beat = r.uniform(0.25, 0.9)
        x += a * np.exp(-t / tau) * (np.sin(2 * np.pi * f * t) + 0.6 * np.sin(2 * np.pi * (f + beat) * t + r.uniform(0, 6.28)))
    strike = butter(r.standard_normal(secs(0.03)), "band", [800, 4000]) * np.linspace(1, 0, secs(0.03))
    x[: len(strike)] += strike * 0.6
    x = butter(x, "low", 2200) * env_adsr(n, 0.0005, 3.0, 1.0)
    dry = np.zeros((2, n))
    place(dry, x, 0, 0.25, 0.4)
    return trim_tail(reverb(dry, impulse(5.0, 6.0, r, bright=2500, dark=500), wet=0.6))


def thunder(seed, crack, cutoff, rolls, dur, onset):
    r = rng(seed)
    n = secs(dur)
    t = times(n)
    out = np.zeros((2, n))
    roll = np.zeros(n)
    at = onset
    for i in range(rolls):
        w = r.uniform(0.4, 1.4)
        roll += np.exp(-((t - at) / w) ** 2) * r.uniform(0.5, 1.0) * 0.8 ** i
        at += r.uniform(0.3, 1.4)
    roll *= np.clip(t / max(onset, 0.01), 0, 1)
    for c in range(2):
        rumble = shape(noise(n, r, "brown"), band_curve(25, cutoff))
        out[c] += rumble * roll * 0.9
        out[c] += shape(noise(n, r, "pink"), band_curve(120, cutoff * 2.2)) * roll * 0.25
    if crack > 0:
        tear = np.zeros(n)
        for _ in range(int(60 * crack)):
            i = secs(r.uniform(0, 0.12) + r.exponential(0.12))
            k = secs(r.uniform(0.001, 0.006))
            if i + k < n:
                tear[i:i + k] += r.standard_normal(k) * r.uniform(0.3, 1.0) * np.exp(-i / secs(0.5))
        tear = butter(tear, "band", [250, 6000])
        boom = np.sin(2 * np.pi * np.cumsum(glide([(0, 70), (0.4, 38), (2, 30)], n)) / SR) * np.exp(-t / 0.9)
        place(out, tear * crack * 1.4, 0, 0.2)
        place(out, boom * 0.6 * crack, 0, 0.0)
    out *= np.exp(-np.maximum(t - dur * 0.5, 0) / (dur * 0.2))
    return trim_tail(reverb(out, impulse(2.5, 3.0, r, bright=3000, dark=500), wet=0.4))


VOWELS = [(730, 1090, 2440), (530, 1840, 2480), (270, 2290, 3010), (570, 840, 2410), (300, 870, 2240), (440, 1020, 2240)]


def whisper_voice(r, dur, scale):
    """Breath through a mouth: noise shaped by three formants that jump
    from vowel to vowel, with s and sh between. No words."""
    n = secs(dur)
    out = np.zeros(n)
    t = r.uniform(0.0, 0.3)
    while t < dur - 0.3:
        phrase = r.integers(3, 9)
        for _ in range(phrase):
            if t > dur - 0.3:
                break
            if r.random() < 0.3:
                k = secs(r.uniform(0.06, 0.14))
                hi = r.choice([2600, 3800])
                s = butter(r.standard_normal(k), "band", [hi * scale, min(9000, hi * 2.2 * scale)])
                out[secs(t):secs(t) + k] += s[: max(0, min(k, n - secs(t)))] * np.hanning(k)[: max(0, min(k, n - secs(t)))] * 0.6
                t += k / SR
            k = secs(r.uniform(0.09, 0.22))
            f1, f2, f3 = VOWELS[r.integers(len(VOWELS))]
            src = r.standard_normal(k)
            v = (butter(src, "band", [f1 * scale * 0.85, f1 * scale * 1.15]) * 1.0
                 + butter(src, "band", [f2 * scale * 0.9, f2 * scale * 1.1]) * 0.7
                 + butter(src, "band", [f3 * scale * 0.93, f3 * scale * 1.07]) * 0.4)
            m = max(0, min(k, n - secs(t)))
            out[secs(t):secs(t) + m] += (v * np.hanning(k) ** 0.7)[:m]
            t += k / SR + r.uniform(0.0, 0.05)
        t += r.uniform(0.25, 0.7)
    return out


def whisper_a():
    r = rng(31)
    dry = np.zeros((2, secs(5)))
    place(dry, whisper_voice(r, 4.6, 0.95), 0, -0.95, 0.5)
    place(dry, whisper_voice(r, 4.0, 1.1), secs(0.6), -0.55, 0.35)
    return trim_tail(reverb(dry, impulse(1.6, 2.0, r, bright=6000, dark=1200), wet=0.35))


def whisper_b():
    r = rng(32)
    dry = np.zeros((2, secs(6.5)))
    for i, (sc, p) in enumerate(((0.9, 0.95), (1.05, 0.6), (0.82, 0.3))):
        place(dry, whisper_voice(r, 5.5 - i * 0.8, sc), secs(0.4 * i), p, 0.4 - 0.08 * i)
    return trim_tail(reverb(dry, impulse(2.2, 2.8, r, bright=5000, dark=1000), wet=0.45))


def whisper_c():
    """Backwards: the echo arrives before the voice, then cuts off."""
    r = rng(33)
    dry = np.zeros((2, secs(3)))
    place(dry, whisper_voice(r, 2.6, 0.85), 0, -0.2, 0.6)
    wet = reverb(dry, impulse(5.0, 5.0, r, bright=4000, dark=600), wet=0.85)
    x = wet[:, ::-1].copy()
    fade = secs(0.4)
    x[:, :fade] *= np.linspace(0, 1, fade)
    x[:, -secs(0.01):] *= np.linspace(1, 0, secs(0.01))
    return x


def call():
    """Very far off and very large: a moan with its formant opening and
    closing, beating against itself, and the groan of something like a
    hull under strain."""
    r = rng(41)
    n = secs(12)
    t = times(n)
    f = glide([(0, 29), (2.5, 37), (5.5, 38.5), (8.0, 31), (10.5, 23), (12, 21)], n)
    f = f * (1 + 0.02 * np.sin(2 * np.pi * 0.31 * t))
    centre = glide([(0, 160), (3, 520), (6, 380), (9, 220), (12, 150)], n)
    parts = [(k, 1 / k ** 0.7) for k in range(1, 40)]
    moan = additive(f, parts, lambda k, fk: formant_gain(fk, centre, 110) + 0.5 * formant_gain(fk, centre * 2.4, 200))
    moan += 0.8 * additive(f * 1.006, parts, lambda k, fk: formant_gain(fk, centre * 1.05, 120))
    moan += 0.5 * np.sin(2 * np.pi * np.cumsum(f / 2) / SR)
    groan = np.zeros(n)
    for base in (147, 233, 311, 389):
        g = base * glide([(0, 0.96), (6, 1.03), (12, 0.98)], n)
        groan += np.sin(2 * np.pi * np.cumsum(g) / SR) * smooth_random(n, r, 0.6) ** 3
    breath = butter(r.standard_normal(n), "band", [60, 500]) * 0.3
    x = (moan * 0.12 + groan * 0.05 + breath) * env_adsr(n, 2.0, 2.5, 1.3)
    x = butter(x, "low", 900)
    dry = np.zeros((2, n))
    place(dry, x, 0, 0.1, 0.8)
    return trim_tail(reverb(dry, impulse(7.0, 9.0, r, bright=1800, dark=300, width=1.0), wet=0.75))


def creak(seed, modes, rate, dur, q):
    """Stick-slip: a train of tiny catches exciting a body's resonances."""
    r = rng(seed)
    n = secs(dur)
    imp = np.zeros(n)
    rr = glide(rate, n)
    pos = 0.0
    while True:
        pos += SR / (rr[min(int(pos), n - 1)] * r.uniform(0.85, 1.15))
        if pos >= n:
            break
        imp[int(pos)] += r.uniform(0.5, 1.0)
    x = np.zeros(n)
    for f, a in modes:
        b, a_ = signal.iirpeak(f, q, fs=SR)
        x += a * signal.lfilter(b, a_, imp)
    x *= env_adsr(n, 0.15, 0.3, 1.0)
    dry = np.zeros((2, n))
    place(dry, x, 0, r.uniform(-0.7, 0.7), 0.5)
    return trim_tail(reverb(dry, impulse(1.5, 2.0, r, bright=4000, dark=800), wet=0.35))


# ---------------------------------------------------------------- bodies
# Sound effects tied to the bodies, written to assets/sfx/ for
# scripts/sfx.gd (which picks one of each sound's takes at random).

def _drops(r, n, count, lo, hi, spread):
    wet = np.zeros(n)
    for _ in range(count):
        b = bubble(r, r.uniform(lo, hi), r.uniform(0.002, 0.007), r.uniform(0.2, 0.7))
        at = secs(r.uniform(0.004, spread))
        m = max(0, min(len(b), n - at))
        wet[at:at + m] += b[:m] * r.uniform(0.08, 0.3)
    return wet


def step_stone(seed):
    """A boot on wet stone: the heel, the weight, the splatter."""
    r = rng(seed)
    n = secs(0.4)
    t = times(n)
    thud = butter(r.standard_normal(n) * np.exp(-t / 0.014), "low", 240) * 2.2
    heel = butter(r.standard_normal(n) * np.exp(-t / 0.004), "band", [900, 3800]) * 0.45
    hiss = butter(r.standard_normal(n), "band", [2500, 7500]) * np.exp(-np.maximum(t - 0.01, 0) / 0.035) * 0.22
    x = thud + heel + hiss + _drops(r, n, r.integers(4, 10), 1800, 4800, 0.08)
    dry = np.zeros((2, n))
    place(dry, x, 0, r.uniform(-0.1, 0.1))
    return trim_tail(reverb(dry, impulse(0.9, 1.2, r, bright=5000, dark=1200), wet=0.18))


def step_wood(seed):
    """A boot on wet planks: a hollow knock, a little give."""
    r = rng(seed)
    n = secs(0.45)
    t = times(n)
    imp = np.zeros(n)
    imp[0] = 1.0
    imp[secs(0.006)] = 0.5
    x = np.zeros(n)
    for f, a in ((r.uniform(170, 210), 1.0), (r.uniform(300, 350), 0.6), (r.uniform(480, 560), 0.35)):
        b, a_ = signal.iirpeak(f, 14, fs=SR)
        x += a * signal.lfilter(b, a_, imp) * 6.0
    x += butter(r.standard_normal(n) * np.exp(-t / 0.005), "band", [1000, 4000]) * 0.4
    x += _drops(r, n, r.integers(2, 5), 2000, 4500, 0.06)
    dry = np.zeros((2, n))
    place(dry, x * np.exp(-t / 0.12), 0, r.uniform(-0.1, 0.1))
    return trim_tail(reverb(dry, impulse(0.9, 1.2, r, bright=5000, dark=1200), wet=0.18))


def land(seed):
    """Coming down hard on wet stone: weight, coat, a sheet of water."""
    r = rng(seed)
    n = secs(0.7)
    t = times(n)
    thud = butter(r.standard_normal(n) * np.exp(-t / 0.03), "low", 180) * 3.0
    cloth = butter(r.standard_normal(n), "band", [250, 1400]) * np.exp(-t / 0.05) * 0.5
    splash = butter(r.standard_normal(n), "band", [900, 6000]) * (np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.09)) * 0.7
    x = thud + cloth + splash + _drops(r, n, 18, 900, 4200, 0.25)
    dry = np.zeros((2, n))
    place(dry, x, 0, 0.0)
    return trim_tail(reverb(dry, impulse(1.0, 1.3, r, bright=5000, dark=1100), wet=0.2))


def voice(r, f0, dur, formants, rough, breath, partials=40):
    """A throat: a buzzing source shaped by formants that slide,
    roughened by a fast flutter."""
    n = secs(dur)
    t = times(n)
    f = glide(f0, n) * (1 + 0.02 * smooth_random(n, r, 12.0, -1, 1))
    flutter = 1.0 - rough * smooth_random(n, r, 35.0)
    tracks = [glide(fm, n) for fm in formants]
    x = additive(f, [(k, 1.0 / k ** 0.8) for k in range(1, partials)],
                 lambda k, fk: sum(formant_gain(fk, c, 90.0 + 0.08 * c) * w for c, w in zip(tracks, (1.0, 0.6, 0.3))))
    x = x * flutter
    x += butter(r.standard_normal(n), "band", [300, 3000]) * breath
    return x


def growl(seed):
    r = rng(seed)
    dur = r.uniform(1.0, 1.3)
    x = voice(r, [(0, 62), (dur * 0.6, 84), (dur, 72)], dur,
              [[(0, 380), (dur, 520)], [(0, 850), (dur, 1100)], [(0, 2300), (dur, 2400)]], 0.75, 0.25)
    x *= env_adsr(len(x), 0.3, 0.25, 1.2)
    dry = np.zeros((2, len(x)))
    place(dry, x, 0, 0.0)
    return trim_tail(reverb(dry, impulse(1.2, 1.5, r, bright=4000, dark=900), wet=0.2))


def snarl(seed):
    r = rng(seed)
    dur = 0.45
    x = voice(r, [(0, 140), (0.1, 190), (dur, 120)], dur,
              [[(0, 700), (dur, 600)], [(0, 1500), (dur, 1300)], [(0, 2800), (dur, 2600)]], 0.6, 0.7)
    x *= env_adsr(len(x), 0.02, 0.2, 1.0)
    clack = butter(r.standard_normal(secs(0.01)), "band", [2000, 6000]) * np.hanning(secs(0.01)) * 0.8
    x[secs(0.38):secs(0.38) + len(clack)] += clack
    dry = np.zeros((2, len(x)))
    place(dry, x, 0, 0.0)
    return trim_tail(reverb(dry, impulse(1.2, 1.5, r, bright=4000, dark=900), wet=0.2))


def moan(seed):
    """A Communicant before it strikes: a wet, wavering moan, half breath,
    opening from oo to ah, a gurgle in the throat."""
    r = rng(seed)
    dur = r.uniform(1.0, 1.4)
    base = r.uniform(95, 125)
    x = voice(r, [(0, base), (dur * 0.5, base * 1.18), (dur, base * 0.9)], dur,
              [[(0, 320), (dur * 0.6, 700), (dur, 650)], [(0, 850), (dur * 0.6, 1150), (dur, 1100)], [(0, 2300), (dur, 2500)]], 0.3, 0.2)
    n = len(x)
    x *= env_adsr(n, 0.25, 0.35, 1.3)
    x += _drops(r, n, 10, 180, 600, dur * 0.8) * 1.5
    x += whisper_voice(r, dur, 0.9) * 0.12
    dry = np.zeros((2, n))
    place(dry, x, 0, 0.0)
    return trim_tail(reverb(dry, impulse(1.4, 1.8, r, bright=4000, dark=800), wet=0.25))


SFX = {}
for i in range(4):
    SFX[f"step_stone_{i + 1}"] = (lambda s: lambda: step_stone(s))(70 + i)
for i in range(3):
    SFX[f"step_wood_{i + 1}"] = (lambda s: lambda: step_wood(s))(80 + i)
for i in range(2):
    SFX[f"land_{i + 1}"] = (lambda s: lambda: land(s))(90 + i)
    SFX[f"growl_{i + 1}"] = (lambda s: lambda: growl(s))(100 + i)
    SFX[f"snarl_{i + 1}"] = (lambda s: lambda: snarl(s))(110 + i)
for i in range(3):
    SFX[f"moan_{i + 1}"] = (lambda s: lambda: moan(s))(120 + i)


SOUNDS = {
    "rain_out": rain_out,
    "rain_in": rain_in,
    "wind": wind,
    "water": water,
    "drone": drone,
    "howl_a": howl_a,
    "howl_b": howl_b,
    "howl_c": howl_c,
    "bell": bell,
    "thunder_near": lambda: thunder(51, 1.0, 320, 6, 9.0, 0.02),
    "thunder_mid": lambda: thunder(52, 0.35, 240, 5, 8.0, 0.25),
    "thunder_far": lambda: thunder(53, 0.0, 170, 4, 8.0, 0.7),
    "whisper_a": whisper_a,
    "whisper_b": whisper_b,
    "whisper_c": whisper_c,
    "call": call,
    "creak_a": lambda: creak(61, [(410, 1.0), (640, 0.7), (905, 0.5), (1350, 0.3)], [(0, 18), (0.5, 45), (1.0, 60), (1.5, 30)], 1.8, 18),
    "creak_b": lambda: creak(62, [(180, 1.0), (290, 0.8), (515, 0.5), (760, 0.2)], [(0, 9), (0.8, 22), (1.8, 14), (2.6, 8)], 2.8, 30),
}

# Beds are normalized to the same loudness above 150 Hz (what laptop
# speakers and ears mostly hear), one-shots to the same peak;
# scripts/ambience.gd sets the mix.
BED_RMS = 0.1
PEAK = 0.89


def write(name, x, out=OUT):
    x = np.asarray(x, dtype=np.float64)
    if name in ("rain_out", "rain_in", "wind", "water", "drone"):
        heard = butter(x, "high", 150)
        x = x * (BED_RMS / np.sqrt(np.mean(heard ** 2)))
        peak = np.max(np.abs(x))
        if peak > PEAK:
            x = np.tanh(x / PEAK) * PEAK
    else:
        x = x * (PEAK / np.max(np.abs(x)))
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").T.copy()
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3",
                        os.path.join(out, name + ".ogg")], check=True)
    return x


if __name__ == "__main__":
    import sys
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    for table, out in ((SOUNDS, OUT), (SFX, "assets/sfx")):
        for name, make in table.items():
            if only and not any(name.startswith(o) for o in only):
                continue
            x = write(name, make(), out)
            size = os.path.getsize(os.path.join(out, name + ".ogg"))
            print(f"{name:14s} {x.shape[1] / SR:5.1f} s  {size / 1024:6.0f} KB")
