"""Surfaces for the 3D stage: tileable textures, each a colour map (alpha:
height, so water can settle in the low parts), a normal map (OpenGL
convention: green up) and a roughness map.

  assets/3d/stone_*   weathered ashlar: blocks of uneven size, chipped
                      arrises, pits and cracks, soot run down from above,
                      grime in the joints, salt bloom, moss low down
  assets/3d/cobble_*  granite setts, worn smooth on top, mud in the joints
  assets/3d/wood_*    old wet planks: grain, splits, rot at the ends, nails
  assets/3d/brick_*   soot-blackened brick (the houses behind)
  assets/3d/slate_*   slate roofs: overlapping courses, some slipped

Everything is built at 1024 and stored at 512: one texture spans 2 m
(scripts/stage.gd), and the camera never sees more than about 100 screen
pixels a metre, so the detail is in what's painted, not in more pixels.
Wetness (darkening, puddles, running water) is the shader's
(shaders/stone3d.gdshader), not baked in here.

Run from the repo root:  python3 tools/textures3d.py   (numpy, Pillow)
"""
import os

import numpy as np
from PIL import Image

N = 1024          # built at
OUT_SIZE = 512    # stored at
OUT = "assets/3d"
PX_M = N / 2.0    # pixels per metre while building
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)


# ---------------------------------------------------------------- noise

def vnoise(cx, cy, seed):
    """Smooth tileable value noise, cx cells across and cy down."""
    r = np.random.default_rng(seed)
    g = r.random((cy, cx)).astype(np.float32)
    fx, fy = xx / N * cx, yy / N * cy
    x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - x0, fy - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a, b = g[y0 % cy, x0 % cx], g[y0 % cy, (x0 + 1) % cx]
    c, d = g[(y0 + 1) % cy, x0 % cx], g[(y0 + 1) % cy, (x0 + 1) % cx]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm(seed, octaves=(4, 8, 16, 32, 64, 128), gain=0.55, stretch=1):
    out = np.zeros((N, N), np.float32)
    w, total = 1.0, 0.0
    for i, cells in enumerate(octaves):
        out += vnoise(cells, max(1, cells // stretch), seed + i * 31) * w
        total += w
        w *= gain
    return out / total


def gblur(img, sigma):
    """Gaussian blur, wrapping round the edges (FFT)."""
    f = np.fft.fftfreq(N).astype(np.float32)
    k = np.exp(-2 * (np.pi * sigma) ** 2 * (f[:, None] ** 2 + f[None, :] ** 2))
    if img.ndim == 3:
        return np.dstack([np.real(np.fft.ifft2(np.fft.fft2(img[..., i]) * k)) for i in range(img.shape[2])]).astype(np.float32)
    return np.real(np.fft.ifft2(np.fft.fft2(img) * k)).astype(np.float32)


def worley(cells, seed, jitter=0.8):
    """Cellular noise: distance to the nearest and second nearest point, and
    which cell owns each pixel."""
    r = np.random.default_rng(seed)
    pts = r.random((cells, cells, 2)).astype(np.float32) * jitter + (1 - jitter) / 2
    cell = N / cells
    gx, gy = (xx // cell).astype(int), (yy // cell).astype(int)
    d1 = np.full((N, N), 9e9, np.float32)
    d2 = np.full((N, N), 9e9, np.float32)
    owner = np.zeros((N, N), int)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx, cy = gx + ox, gy + oy
            p = pts[cy % cells, cx % cells]
            d = np.hypot(xx - (cx + p[..., 0]) * cell, yy - (cy + p[..., 1]) * cell)
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            owner = np.where(closer, (cy % cells) * cells + (cx % cells), owner)
            d1 = np.where(closer, d, d1)
    return d1, d2, owner


def per_id(ids, seed, lo=-1.0, hi=1.0):
    r = np.random.default_rng(seed)
    return r.uniform(lo, hi, ids.max() + 1).astype(np.float32)[ids]


def rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


def mix(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 else t
    return a * (1 - t) + b * t


def cracks(seed, count, length, width=1.4):
    """Thin wandering cracks: a mask, 1 in the crack."""
    r = np.random.default_rng(seed)
    m = np.zeros((N, N), np.float32)
    for _ in range(count):
        x, y = r.uniform(0, N), r.uniform(0, N)
        ang = r.uniform(0, np.pi * 2)
        heading = ang
        for _ in range(int(length * r.uniform(0.5, 1.0))):
            ang += r.normal(0, 0.12) + (heading - ang) * 0.05
            x, y = (x + np.cos(ang) * 2.0) % N, (y + np.sin(ang) * 2.0) % N
            m[int(y), int(x)] = 1.0
            if r.random() < 0.015:
                ang += r.choice([-1, 1]) * r.uniform(0.4, 0.9)
    return np.clip(gblur(m, width * 0.5) * 6.0, 0, 1)


def cavity(h, sigma=5.0):
    """How far below its surroundings each point is: the joints, pits and
    cracks, where dirt gathers and light doesn't reach."""
    return np.clip((gblur(h, sigma) - h) * 6.0, 0, 1)


# ---------------------------------------------------------------- output

def down(img):
    """Halves the size by averaging 2x2 (antialiases what was built)."""
    if img.ndim == 2:
        return img.reshape(OUT_SIZE, 2, OUT_SIZE, 2).mean(axis=(1, 3))
    return img.reshape(OUT_SIZE, 2, OUT_SIZE, 2, img.shape[2]).mean(axis=(1, 3))


def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    n = np.dstack([-dx * strength, dy * strength, np.ones_like(h)])
    n = down(n)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def save(name, img):
    arr = np.clip(img * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(arr).save(os.path.join(OUT, name), optimize=True)


def write(name, albedo, height, normal_strength, rough):
    a = np.dstack([down(np.clip(albedo, 0, 1)), down(np.clip(height, 0, 1))])
    save(f"{name}_albedo.png", a)
    save(f"{name}_normal.png", normal_map(height, normal_strength))
    save(f"{name}_rough.png", np.repeat(down(np.clip(rough, 0, 1))[..., None], 3, 2))


def rows_of(heights_m, seed):
    """Course boundaries down the texture: random heights from the list,
    summing to the whole height."""
    r = np.random.default_rng(seed)
    out = [0]
    while out[-1] < N:
        out.append(out[-1] + int(r.choice(heights_m) * PX_M))
    out[-1] = N
    if out[-1] - out[-2] < min(heights_m) * PX_M * 0.6:
        out.pop(-2)
    return np.array(out)


def courses(heights_m, widths_m, seed, joint):
    """Blocks laid in courses of uneven height, each course its own random
    joints. Returns the block id, distance to its edge (px), the position
    inside the block (0..1) and the block size."""
    r = np.random.default_rng(seed)
    bounds = rows_of(heights_m, seed)
    row = np.searchsorted(bounds, yy, side="right") - 1
    top = bounds[row]
    ch = (bounds[np.minimum(row + 1, len(bounds) - 1)] - top).astype(np.float32)
    ids = np.zeros((N, N), int)
    dist = np.zeros((N, N), np.float32)
    u = np.zeros((N, N), np.float32)
    v = (yy - top) / ch
    bw = np.zeros((N, N), np.float32)
    next_id = 0
    for k in range(len(bounds) - 1):
        joints = [0]
        while joints[-1] < N:
            joints.append(joints[-1] + int(r.uniform(*widths_m) * PX_M))
        joints[-1] = N
        if joints[-1] - joints[-2] < widths_m[0] * PX_M * 0.6:
            joints.pop(-2)
        joints = np.array(joints)
        shift = r.integers(0, N)
        sel = row == k
        xs = (xx[sel] + shift) % N
        b = np.searchsorted(joints, xs, side="right") - 1
        left = joints[b]
        w = (joints[b + 1] - left).astype(np.float32)
        fx = xs - left
        fy = yy[sel] - bounds[k]
        hgt = bounds[k + 1] - bounds[k]
        dist[sel] = np.minimum(np.minimum(fx, w - fx), np.minimum(fy, hgt - fy))
        u[sel] = fx / w
        ids[sel] = next_id + b
        bw[sel] = w
        next_id += len(joints)
    return ids, dist, u, v, bw, ch


# ---------------------------------------------------------------- surfaces

def stone():
    """Old limestone ashlar, blackened by a century of coal smoke and rain."""
    ids, dist, u, v, bw, ch = courses([0.22, 0.28, 0.34], (0.35, 0.8), 101, 7)
    # Arrises chipped and worn round: the edge wanders.
    wander = (fbm(102, (16, 32, 64, 128)) - 0.5) * 14.0
    d = dist + wander
    bevel = np.clip(d / 16.0, 0, 1)
    bevel = bevel * bevel * (3 - 2 * bevel)
    grain = fbm(103)
    fine = fbm(104, (64, 128, 256))
    # Each face slightly domed and tilted; some blocks sit proud.
    tilt = per_id(ids, 105, -0.08, 0.08) * (u - 0.5) + per_id(ids, 106, -0.08, 0.08) * (v - 0.5)
    proud = per_id(ids, 107, -0.06, 0.06)
    dome = (1 - (2 * u - 1) ** 2) * (1 - (2 * v - 1) ** 2) * 0.08
    # Pits, spalls where a face has flaked away, cracks.
    d1, d2, _ = worley(48, 108)
    pits = np.clip(1 - d1 / 5.0, 0, 1) * (vnoise(16, 16, 109) > 0.55)
    spall = np.clip((fbm(110, (8, 16, 32)) - 0.66) * 6, 0, 1)
    crack = cracks(111, 14, 220)
    h = 0.25 + bevel * (0.58 + dome + tilt + proud + (grain - 0.5) * 0.24 + (fine - 0.5) * 0.12)
    h -= pits * 0.12 + spall * 0.1 * bevel + crack * 0.18 * bevel
    h = np.clip(h, 0, 1)
    cav = cavity(h, 4.0)

    # Colour: limestone greys, each block its own; soot streaks run down
    # from the top of the image (rain carries it), grime in every recess.
    base = rgb("#6b6a68")
    block = per_id(ids, 112, -1, 1)
    warmth = per_id(ids, 113, -1, 1)
    col = base * (0.82 + 0.1 * block[..., None]) + np.array([0.02, 0.01, -0.01], np.float32) * warmth[..., None]
    col = col * (0.85 + 0.3 * (grain[..., None] - 0.5) + 0.2 * (fine[..., None] - 0.5))
    streak = fbm(114, (32, 64, 128), stretch=8)
    soot = np.clip((streak - 0.42) * 2.4, 0, 1) * (0.5 + 0.5 * vnoise(6, 2, 115))
    sooty_blocks = np.clip(per_id(ids, 116, -0.6, 1.0), 0, 1)
    col = col * (1 - 0.55 * np.clip(soot + sooty_blocks * 0.45, 0, 1)[..., None])
    # Salt bloom: pale tide marks near the joints.
    bloom = np.clip((fbm(117, (16, 32, 64)) - 0.6) * 4, 0, 1) * (1 - bevel * 0.7)
    col = mix(col, rgb("#a9a79d"), bloom * 0.35)
    # Moss and algae in the low joints and recesses.
    damp = np.clip(v * 1.4 - 0.5, 0, 1) * np.clip((fbm(118, (8, 16, 32)) - 0.45) * 3, 0, 1)
    moss_col = rgb("#2c3a22") * (0.7 + 0.6 * fine[..., None])
    col = mix(col, moss_col, np.clip((1 - bevel) * 0.8 + cav, 0, 1) * damp * 0.85)
    # Fresh stone where it has spalled, darker in pits and cracks.
    col = mix(col, col * 1.25 + 0.03, spall * 0.5)
    mortar = rgb("#3a3833") * (0.7 + 0.5 * fine[..., None])
    col = mix(mortar, col, bevel)
    col *= (1 - 0.65 * cav)[..., None]
    col *= (1 - 0.5 * crack)[..., None]
    rough = 0.72 + 0.12 * (grain - 0.5) + 0.1 * cav + 0.15 * damp - 0.08 * bevel * (1 - soot)
    write("stone", col, h, 12.0, rough)


def cobble():
    """Granite setts in rows, worn round on top, mud and grit in the joints."""
    ids, dist, u, v, bw, ch = courses([0.09, 0.11, 0.13, 0.15], (0.1, 0.24), 201, 6)
    wander = (fbm(202, (16, 32, 64, 128)) - 0.5) * 22.0
    d = dist + wander - 4.0
    edge = np.clip(d / 14.0, 0, 1)
    crown = np.clip(1 - ((2 * u - 1) ** 2 + (2 * v - 1) ** 2) * 0.55, 0, 1)
    fine = fbm(203, (64, 128, 256))
    grain = fbm(204)
    sink = per_id(ids, 205, -0.12, 0.06)
    h = np.clip(0.15 + edge ** 0.5 * (0.45 + 0.35 * crown + sink + (fine - 0.5) * 0.08), 0, 1)
    cav = cavity(h, 4.0)
    # Granite: grey with flecks; a few setts browner or bluer.
    base = rgb("#5d5c5d")
    tone = per_id(ids, 206, -1, 1)
    col = base * (0.8 + 0.14 * tone[..., None]) + np.array([0.03, 0.015, -0.01], np.float32) * per_id(ids, 207, -1, 1)[..., None]
    flecks = (np.random.default_rng(208).random((N, N)) > 0.985).astype(np.float32)
    flecks = gblur(flecks, 0.6) * 2.5
    col = col * (0.88 + 0.24 * (grain[..., None] - 0.5)) + flecks[..., None] * 0.12
    col = col * (0.85 + 0.25 * crown[..., None])
    mud = rgb("#26221d") * (0.8 + 0.4 * fine[..., None])
    col = mix(mud, col, edge)
    col *= (1 - 0.6 * cav)[..., None]
    # Polished smooth on the crowns where feet and wheels go.
    rough = 0.62 - 0.22 * crown * edge + 0.1 * (grain - 0.5) + 0.3 * (1 - edge)
    write("cobble", col, h, 12.0, rough)


def wood():
    """Planks, long soaked: grain, splits, dark rot toward the ends, nails."""
    r = np.random.default_rng(301)
    ph = int(0.2 * PX_M)
    planks = N // ph
    row = np.minimum((yy // ph).astype(int), planks - 1)
    fy = yy - row * ph
    offsets = r.integers(0, N, planks)
    xs = (xx + offsets[row]) % N
    length = N // 2
    board = (xs // length).astype(int)
    fx = xs % length
    ids = row * 2 + board
    edge = np.minimum(np.minimum(fx, length - 1 - fx), np.minimum(fy, ph - 1 - fy))
    face = np.clip(edge / 4.0, 0, 1)
    warp = fbm(302, (2, 4, 8)) * 30.0
    rings = 0.5 + 0.5 * np.sin(yy * 0.55 + warp + per_id(ids, 303, 0, 6.28))
    streaks = fbm(304, (64, 128, 256), stretch=16)
    grain = rings * 0.5 + streaks * 0.5
    split = cracks(305, 8, 260, 1.0) * (vnoise(4, 64, 306) > 0.5)
    h = face * (0.75 + 0.15 * grain) - split * 0.3 * face
    # Nails over the joists, every 50 cm, two to a board.
    nail = np.zeros((N, N), np.float32)
    for jx in range(0, N, int(0.5 * PX_M)):
        for k in range(planks):
            for oy in (0.3, 0.7):
                cx, cy = (jx + 20 - offsets[k]) % N, k * ph + oy * ph
                nail = np.maximum(nail, np.clip(1 - np.hypot(((xx - cx + N / 2) % N) - N / 2, yy - cy) / 5.0, 0, 1))
    h = np.clip(h + nail * 0.15, 0, 1)
    cav = cavity(h, 3.0)
    base = rgb("#5b4632")
    tone = per_id(ids, 307, -1, 1)
    col = base * (0.7 + 0.12 * tone[..., None] + 0.3 * grain[..., None])
    ends = np.clip(1 - np.minimum(fx, length - fx) / (0.25 * PX_M), 0, 1)
    rot = ends * np.clip((fbm(308, (8, 16, 32)) - 0.3) * 2, 0, 1)
    col = mix(col, rgb("#1d1712"), rot * 0.75)
    col = mix(col, rgb("#2f3826"), np.clip((fbm(309, (8, 16)) - 0.6) * 3, 0, 1) * (1 - face * 0.6) * 0.7)
    rust = np.clip(gblur(nail, 4.0) * 3, 0, 1)
    col = mix(col, rgb("#4a2a18"), rust * 0.6)
    col = mix(col, rgb("#151413"), nail)
    col = mix(rgb("#0c0907"), col, face)
    col *= (1 - 0.5 * cav)[..., None]
    rough = 0.7 + 0.15 * grain + 0.15 * rot - 0.35 * nail
    write("wood", col, h, 6.0, rough)


def brick():
    """London stock brick gone black with soot, the odd one replaced."""
    bh, bwid, mj = int(0.075 * PX_M), int(0.23 * PX_M), 5
    row = (yy // bh).astype(int)
    shift = (row % 2) * (bwid // 2)
    xs = (xx + shift) % N
    col_i = (xs // bwid).astype(int)
    fx, fy = xs % bwid, yy % bh
    edge = np.minimum(np.minimum(fx, bwid - 1 - fx), np.minimum(fy, bh - 1 - fy))
    ids = row * (N // bwid + 1) + col_i
    wander = (fbm(401, (32, 64, 128)) - 0.5) * 4.0
    face = np.clip((edge + wander - mj * 0.5) / 4.0, 0, 1)
    fine = fbm(402, (64, 128, 256))
    spall = np.clip((fbm(403, (16, 32, 64)) - 0.68) * 5, 0, 1)
    h = np.clip(0.3 + face * (0.55 + per_id(ids, 404, -0.05, 0.05) + (fine - 0.5) * 0.1) - spall * 0.12 * face, 0, 1)
    cav = cavity(h, 3.0)
    tone = per_id(ids, 405, -1, 1)
    base = rgb("#4a3a33")
    col = base * (0.75 + 0.18 * tone[..., None]) * (0.85 + 0.3 * (fine[..., None] - 0.5))
    replaced = per_id(ids, 406, 0, 1) > 0.975
    col = np.where(replaced[..., None], rgb("#5a4337") * (0.85 + 0.3 * fine[..., None]), col)
    soot = np.clip((fbm(407, (16, 32, 64), stretch=6) - 0.35) * 2, 0, 1)
    col *= (1 - 0.6 * soot)[..., None]
    col = mix(rgb("#2e2c29") * (0.8 + 0.4 * fine[..., None]), col, face)
    col *= (1 - 0.55 * cav)[..., None]
    rough = 0.8 + 0.1 * (fine - 0.5) + 0.1 * (1 - face)
    write("brick", col, h, 7.0, rough)


def slate():
    """Slates in overlapping courses: each throws a shadow on the one below;
    a few slipped or gone, moss on the old ones."""
    course = int(0.11 * PX_M)
    sw = int(0.22 * PX_M)
    row = (yy // course).astype(int)
    shift = (row % 2) * (sw // 2) + (row * 37 % 11)
    xs = (xx + shift) % N
    col_i = (xs // sw).astype(int)
    fx, fy = xs % sw, yy % course
    ids = row * (N // sw + 1) + col_i
    # Height rises down each course (the lower edge is the thick, exposed
    # edge sitting on the course beneath).
    slope = fy / course
    gap = np.clip(np.minimum(fx, sw - 1 - fx) / 2.5, 0, 1)
    slip = per_id(ids, 501, -0.08, 0.08)
    fine = fbm(502, (64, 128, 256))
    h = np.clip(0.2 + 0.6 * slope * gap + slip + (fine - 0.5) * 0.05, 0, 1)
    missing = per_id(ids, 503, 0, 1) > 0.992
    h = np.where(missing, 0.1 + 0.05 * fine, h)
    cav = cavity(h, 3.0)
    tone = per_id(ids, 504, -1, 1)
    col = rgb("#3a3d44") * (0.8 + 0.15 * tone[..., None]) * (0.85 + 0.3 * (fine[..., None] - 0.5))
    lichen = np.clip((fbm(505, (8, 16, 32)) - 0.58) * 4, 0, 1) * (1 - slope * 0.5)
    col = mix(col, rgb("#4b5236"), lichen * 0.6)
    col = np.where(missing[..., None], rgb("#17140f"), col)
    col *= (1 - 0.6 * cav)[..., None]
    rough = 0.45 + 0.2 * (fine - 0.5) + 0.3 * lichen + 0.2 * cav
    write("slate", col, h, 8.0, rough)


def main():
    os.makedirs(OUT, exist_ok=True)
    for make in (stone, cobble, wood, brick, slate):
        make()
        print("made", make.__name__)


if __name__ == "__main__":
    main()
