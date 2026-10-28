"""Greybox surfaces for the 3D stage: tileable 512x512 textures, each a
colour map, a normal map (OpenGL convention: green up) and a roughness map.

  assets/3d/stone_*.png   cut-stone blocks, running bond (walls, faces)
  assets/3d/cobble_*.png  rounded setts (the tops of things: streets, ledges)
  assets/3d/wood_*.png    planks (walkways)

One texture spans 2 m of the world (scripts/stage.gd, TILE_M), so a stone
block is about 50 x 25 cm. Wetness (darkening, puddles, running water) is
added on top by shaders/stone3d.gdshader, not baked in here.

Run from the repo root:  python3 tools/textures3d.py
"""
import os

import numpy as np
from PIL import Image

S = 512
OUT = "assets/3d"
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)


def noise(cells, seed):
    """Smooth tileable value noise, `cells` cells across."""
    r = np.random.default_rng(seed)
    g = r.random((cells, cells)).astype(np.float32)
    fx, fy = xx / S * cells, yy / S * cells
    x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - x0, fy - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a, b = g[y0 % cells, x0 % cells], g[y0 % cells, (x0 + 1) % cells]
    c, d = g[(y0 + 1) % cells, x0 % cells], g[(y0 + 1) % cells, (x0 + 1) % cells]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm(seed, octaves=(4, 8, 16, 32, 64)):
    out = np.zeros((S, S), np.float32)
    w, total = 0.5, 0.0
    for i, cells in enumerate(octaves):
        out += noise(cells, seed + i * 31) * w
        total += w
        w *= 0.55
    return out / total


def blur(h, passes=2):
    for _ in range(passes):
        h = (h + np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1)) / 5.0
    return h


def normals(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    # Image rows run down; green is "up the image", so a height rising
    # downward tilts the normal down (negative green).
    n = np.dstack([-dx * strength, dy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def save(name, img):
    arr = np.clip(img * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(arr).save(os.path.join(OUT, name), optimize=True)


def rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


def per_cell(ids, seed, lo=-1.0, hi=1.0):
    r = np.random.default_rng(seed)
    table = r.uniform(lo, hi, ids.max() + 1).astype(np.float32)
    return table[ids]


def stone():
    rows, cols = 8, 4                      # 25 cm courses, 50 cm blocks
    ch, cw = S // rows, S // cols
    row = (yy // ch).astype(int)
    shift = (row % 2) * (cw // 2)
    xs = (xx + shift) % S
    col = (xs // cw).astype(int)
    fx, fy = xs % cw, yy % ch
    edge = np.minimum(np.minimum(fx, cw - 1 - fx), np.minimum(fy, ch - 1 - fy))
    face = np.clip(edge / 7.0, 0, 1)
    ids = row * cols + col
    tint = per_cell(ids, 3)
    tilt_x, tilt_y = per_cell(ids, 4, -0.4, 0.4), per_cell(ids, 5, -0.4, 0.4)
    grain = fbm(10)
    chips = blur((fbm(20, (32, 64, 128)) > 0.68).astype(np.float32), 1)
    h = face * (0.85 + 0.15 * grain) + face * (tilt_x * (fx / cw - 0.5) + tilt_y * (fy / ch - 0.5)) * 0.25
    h -= chips * 0.25 * face
    base = rgb("#5a5c66")
    col_ = base * (0.82 + 0.12 * tint[..., None] + 0.3 * (grain[..., None] - 0.5))
    # Grime gathers low on each block and in the mortar; lichen here and there.
    grime = np.clip((fy / ch)[..., None] * 0.25 + (1 - face[..., None]) * 0.6, 0, 1)
    col_ = col_ * (1 - 0.45 * grime)
    lichen = np.clip((fbm(30, (4, 8, 16)) - 0.62) * 4, 0, 1)[..., None]
    col_ = col_ * (1 - lichen) + rgb("#3d4a35") * lichen * (0.8 + 0.4 * grain[..., None])
    mortar = rgb("#24252b")
    albedo = np.where(face[..., None] > 0.05, col_, mortar)
    rough = np.where(face > 0.05, 0.62 + 0.25 * grain + 0.1 * chips, 0.95)
    save("stone_albedo.png", albedo)
    save("stone_normal.png", normals(blur(h, 1), 5.0))
    save("stone_rough.png", np.repeat(rough[..., None], 3, 2))


def cobble():
    cells = 10                             # setts about 20 cm across
    r = np.random.default_rng(7)
    pts = r.random((cells, cells, 2)).astype(np.float32) * 0.6 + 0.2
    cell = S / cells
    gx, gy = (xx // cell).astype(int), (yy // cell).astype(int)
    d1 = np.full((S, S), 9e9, np.float32)
    d2 = np.full((S, S), 9e9, np.float32)
    owner = np.zeros((S, S), int)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx, cy = gx + ox, gy + oy
            p = pts[cy % cells, cx % cells]
            px = (cx + p[..., 0]) * cell
            py = (cy + p[..., 1]) * cell
            d = np.hypot(xx - px, yy - py)
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            owner = np.where(closer, (cy % cells) * cells + (cx % cells), owner)
            d1 = np.where(closer, d, d1)
    gap = np.clip((d2 - d1) / 9.0, 0, 1)
    dome = np.clip(1 - (d1 / (cell * 0.75)) ** 2, 0, 1)
    grain = fbm(40)
    h = gap * (0.6 + 0.4 * dome) * (0.9 + 0.1 * grain)
    tint = per_cell(owner, 8)
    base = rgb("#4c4e58")
    col_ = base * (0.8 + 0.15 * tint[..., None] + 0.3 * (grain[..., None] - 0.5)) * (0.75 + 0.25 * dome[..., None])
    albedo = np.where(gap[..., None] > 0.12, col_, rgb("#1c1d22"))
    # Worn smooth on top, rough in the joints.
    rough = np.where(gap > 0.12, 0.55 - 0.15 * dome + 0.2 * grain, 0.9)
    save("cobble_albedo.png", albedo)
    save("cobble_normal.png", normals(blur(h, 1), 6.0))
    save("cobble_rough.png", np.repeat(rough[..., None], 3, 2))


def wood():
    planks = 8                             # 25 cm boards
    ph = S // planks
    row = (yy // ph).astype(int)
    fy = yy % ph
    # Board ends staggered along each plank.
    r = np.random.default_rng(12)
    offsets = r.integers(0, S, planks)
    xs = (xx + offsets[row]) % S
    board = (xs // (S // 2)).astype(int)
    fx = xs % (S // 2)
    edge = np.minimum(np.minimum(fx, S // 2 - 1 - fx), np.minimum(fy, ph - 1 - fy))
    face = np.clip(edge / 3.0, 0, 1)
    stretch_r = np.random.default_rng(13).random((64, 4)).astype(np.float32)
    gy, gx = (yy / S * 64).astype(int) % 64, (xx / S * 4).astype(int) % 4
    grain = 0.5 + 0.5 * np.sin(yy * 0.9 + stretch_r[gy, gx] * 6.0 + fbm(50, (2, 4, 8)) * 20.0)
    ids = row * 2 + board
    tint = per_cell(ids, 14)
    base = rgb("#5a4030")
    col_ = base * (0.75 + 0.15 * tint[..., None] + 0.2 * grain[..., None])
    albedo = np.where(face[..., None] > 0.1, col_, rgb("#120c08"))
    h = face * (0.9 + 0.1 * grain)
    rough = np.where(face > 0.1, 0.6 + 0.2 * grain, 0.95)
    save("wood_albedo.png", albedo)
    save("wood_normal.png", normals(blur(h, 1), 3.0))
    save("wood_rough.png", np.repeat(rough[..., None], 3, 2))


def main():
    os.makedirs(OUT, exist_ok=True)
    stone()
    cobble()
    wood()
    print("wrote", ", ".join(sorted(os.listdir(OUT))))


if __name__ == "__main__":
    main()
