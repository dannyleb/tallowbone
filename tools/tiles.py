"""Greybox tile textures, lit like real surfaces.

Draws every tile at 64x64 (shown at 32 world px, so twice the detail) as
three matching atlases:
  assets/tiles/greybox_albedo.png    colour
  assets/tiles/greybox_normal.png    bumps (from a height map), for 2D lights
  assets/tiles/greybox_specular.png  gloss: bright is wet and shiny
and writes the TileSet that uses them (tiles/greybox_tileset.tres).

Each tile has a custom-data "kind" the game reads: stone (solid), walkway
(one-way), water (hazard), veil (solid until the Lantern burns it), wall
(back wall, decoration only). Stone comes in a few variants and with its
exposed edges drawn; tools/build_level.py picks them from the neighbours.

Run from the repo root:  python3 tools/tiles.py
"""
import numpy as np
from PIL import Image

S = 64          # texture px per tile
COLS = 8
BUMP = 3.2      # normal-map strength

# name -> (col, row, kind). Filled in by build().
TILES = {}
BY_NAME = {}

rng = np.random.default_rng(11)
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)


def value_noise(scale, seed):
    """Smooth tileable noise in 0..1 at roughly `scale` px per cell."""
    r = np.random.default_rng(seed)
    n = max(1, S // scale)
    g = r.random((n, n)).astype(np.float32)
    fx, fy = xx / S * n, yy / S * n
    x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - x0, fy - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a, b = g[y0 % n, x0 % n], g[y0 % n, (x0 + 1) % n]
    c, d = g[(y0 + 1) % n, x0 % n], g[(y0 + 1) % n, (x0 + 1) % n]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm(seed, scales=(32, 16, 8, 4)):
    out = np.zeros((S, S), np.float32)
    w = 0.5
    total = 0.0
    for i, sc in enumerate(scales):
        out += value_noise(sc, seed + i * 17) * w
        total += w
        w *= 0.55
    return out / total


def blocks(course_h, block_w, offset, seed, bevel=5.0):
    """Height and per-block shade for a running-bond wall. Height is 1 on a
    block's face, falling to 0 in the mortar; faces bulge a little."""
    h = np.zeros((S, S), np.float32)
    shade = np.zeros((S, S), np.float32)
    r = np.random.default_rng(seed)
    rows = S // course_h
    for row in range(rows):
        y0 = row * course_h
        shift = offset if row % 2 else 0
        for k in range(-1, S // block_w + 1):
            x0 = k * block_w + shift
            tint = r.uniform(-1, 1)
            bulge = r.uniform(0.0, 0.35)
            ys = slice(y0, y0 + course_h)
            for x in range(max(0, x0), min(S, x0 + block_w)):
                dx = min(x - x0, x0 + block_w - 1 - x)
                for y in range(y0, y0 + course_h):
                    dy = min(y - y0, y0 + course_h - 1 - y)
                    edge = min(dx, dy)
                    face = min(1.0, edge / bevel)
                    cx = (x - x0) / block_w - 0.5
                    cy = (y - y0) / course_h - 0.5
                    h[y, x] = face * (1.0 + bulge * (1 - (cx * cx + cy * cy) * 2))
                    shade[y, x] = tint
            del ys
    return h, shade


def normal_map(h):
    # OpenGL convention (green = up on screen), which Godot's 2D lights use.
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    n = np.dstack([-dx * BUMP, dy * BUMP, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def rgb(c):
    return np.array([int(c[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


STONE = rgb("#3a3b47")
STONE_TOP = rgb("#5b5d6c")
MORTAR = rgb("#16161c")
DEEP = rgb("#121218")
WOOD = rgb("#4a3424")
WOOD_DARK = rgb("#2a1d14")
IRON = rgb("#2c2c33")
WATER = rgb("#0c2622")
VEIL = rgb("#e4dcc6")
WALL = rgb("#22222b")


def stone_tile(variant, top, left, right):
    seed = 100 + variant * 7
    h, shade = blocks(32, 64, 32, seed)
    grain = fbm(seed + 3)
    pits = fbm(seed + 5, (4, 2))
    h = h * (0.75 + 0.25 * grain) - (pits > 0.72) * 0.25
    col = np.where(h[..., None] > 0.2, STONE * (0.85 + 0.15 * shade[..., None] * 0.6 + 0.25 * (grain[..., None] - 0.5)), MORTAR)
    # Faint rain-dark streaks running down the face, fading as they go.
    across = value_noise(2, seed + 9)[0:1, :].repeat(S, 0)
    down = 1.0 - yy / S * (0.4 + 0.6 * value_noise(8, seed + 10))
    streak = np.clip((across - 0.55) * 3.0, 0, 1) * down
    col *= 1.0 - 0.1 * streak[..., None]
    gloss = np.where(h > 0.2, 0.35 + 0.25 * streak + 0.2 * grain, 0.08)
    if top:
        # Rounded cobbles along the top edge, wet and catching the light.
        band = 18
        r2 = np.random.default_rng(seed + 1)
        th = np.zeros((band, S), np.float32)
        x = 0
        while x < S:
            w = int(r2.integers(10, 16))
            cx, cy, rx = x + w / 2, band / 2 + r2.uniform(-1, 1), w / 2
            d = ((xx[:band] - cx) / rx) ** 2 + ((yy[:band] - cy) / (band * 0.45)) ** 2
            th = np.maximum(th, np.clip(1 - d, 0, 1) ** 0.5)
            x += w
        h[:band] = th * 1.1
        cob = STONE_TOP * (0.8 + 0.3 * grain[:band, :, None])
        col[:band] = np.where(th[..., None] > 0.05, cob, MORTAR)
        gloss[:band] = np.where(th > 0.05, 0.75 + 0.2 * grain[:band], 0.3)
    if left:
        col[:, :4] *= 0.6
        h[:, :4] *= np.linspace(0.3, 1, 4)[None, :]
    if right:
        col[:, -4:] *= 0.6
        h[:, -4:] *= np.linspace(1, 0.3, 4)[None, :]
    return col, h, gloss, np.ones((S, S), np.float32)


def deep_tile(variant):
    g = fbm(300 + variant)
    col = DEEP[None, None, :] * (0.8 + 0.4 * g[..., None])
    return col, g * 0.3, 0.05 + 0.05 * g, np.ones((S, S), np.float32)


def walkway_tile(left, right):
    col = np.zeros((S, S, 3), np.float32)
    h = np.zeros((S, S), np.float32)
    gloss = np.zeros((S, S), np.float32)
    alpha = np.zeros((S, S), np.float32)
    grain = value_noise(2, 41)[:, :] * 0.5 + fbm(42, (16, 8)) * 0.5
    plank = slice(0, 13)
    col[plank] = WOOD * (0.75 + 0.5 * grain[plank, :, None])
    col[0:3] = WOOD * 1.35
    h[plank] = 0.6 + 0.4 * grain[plank]
    h[0:2] = 1.0
    gloss[plank] = 0.25 + 0.3 * (grain[plank] > 0.6)
    alpha[plank] = 1
    for sx in (0, 31):
        col[2:12, sx] = WOOD_DARK
        h[2:12, sx] = 0.2
    for nx in (6, 37):
        col[5:8, nx:nx + 3] = IRON * 1.6
        h[5:8, nx:nx + 3] = 1.0
        gloss[5:8, nx:nx + 3] = 0.9
    for side, x in (("l", 6), ("r", S - 10)):
        if (side == "l" and left) or (side == "r" and right):
            col[13:46, x:x + 4] = IRON
            h[13:46, x:x + 4] = np.linspace(0.4, 1.0, 4)[None, :]
            gloss[13:46, x:x + 4] = 0.6
            alpha[13:46, x:x + 4] = 1
    return col, h, gloss, alpha


def water_tile(surface):
    ripple = fbm(60, (16, 8, 4))
    col = WATER[None, None, :] * (0.7 + 0.5 * ripple[..., None]) * (1.0 if surface else 0.55)
    h = ripple * 0.4
    gloss = np.full((S, S), 0.95 if surface else 0.6, np.float32)
    if surface:
        line = (np.abs(yy - (5 + 2 * np.sin(xx * 0.2))) < 1.2)
        col[line] = rgb("#4b8c7c")
    return col, h, gloss, np.ones((S, S), np.float32)


def veil_tile():
    col = np.tile(VEIL, (S, S, 1))
    h = np.zeros((S, S), np.float32)
    alpha = np.full((S, S), 0.12, np.float32)
    r = np.random.default_rng(7)
    for i in range(9):
        sx = r.uniform(3, S - 3)
        sway = r.uniform(-5, 5)
        for y in range(S):
            x = sx + np.sin(y / S * np.pi * 1.5 + i) * sway
            xi = int(round(x))
            for dx in (-1, 0, 1):
                if 0 <= xi + dx < S:
                    a = 0.6 if dx == 0 else 0.25
                    alpha[y, xi + dx] = max(alpha[y, xi + dx], a)
                    h[y, xi + dx] = max(h[y, xi + dx], a)
    return col, h, np.full((S, S), 0.5, np.float32), alpha


def wall_tile(variant):
    seed = 500 + variant * 13
    h, shade = blocks(16, 32, 16 if variant != 1 else 8, seed, bevel=3.0)
    grain = fbm(seed + 1)
    damp = value_noise(8, seed + 2)
    col = np.where(h[..., None] > 0.2, WALL * (0.85 + 0.25 * shade[..., None] * 0.5 + 0.3 * (grain[..., None] - 0.5)), WALL * 0.45)
    col *= 1.0 - 0.25 * damp[..., None]
    if variant == 2:
        # Moss in the joints.
        moss = (h < 0.3) & (fbm(seed + 4) > 0.55)
        col[moss] = rgb("#26331f")
    gloss = np.where(h > 0.2, 0.15 + 0.5 * (damp > 0.55), 0.05)
    return col, h * 0.7, gloss, np.ones((S, S), np.float32)


def build():
    tiles = []
    for v in range(3):
        tiles.append((f"stone_face_{v}", "stone", stone_tile(v, False, False, False)))
    for v in range(2):
        tiles.append((f"stone_top_{v}", "stone", stone_tile(v, True, False, False)))
    for top in (False, True):
        for sides in ("l", "r", "lr"):
            name = f"stone_{'top' if top else 'face'}_{sides}"
            tiles.append((name, "stone", stone_tile(0, top, "l" in sides, "r" in sides)))
    for v in range(2):
        tiles.append((f"stone_deep_{v}", "stone", deep_tile(v)))
    for sides in ("", "l", "r", "lr"):
        tiles.append(("walkway" + (f"_{sides}" if sides else ""), "walkway", walkway_tile("l" in sides, "r" in sides)))
    tiles.append(("water_surface", "water", water_tile(True)))
    tiles.append(("water_deep", "water", water_tile(False)))
    tiles.append(("veil", "veil", veil_tile()))
    for v in range(3):
        tiles.append((f"wall_{v}", "wall", wall_tile(v)))

    rows = (len(tiles) + COLS - 1) // COLS
    albedo = np.zeros((rows * S, COLS * S, 4), np.float32)
    normal = np.zeros((rows * S, COLS * S, 4), np.float32)
    spec = np.zeros((rows * S, COLS * S, 4), np.float32)
    for i, (name, kind, (col, h, gloss, alpha)) in enumerate(tiles):
        c, r = i % COLS, i // COLS
        TILES[name] = (c, r, kind)
        BY_NAME[name] = (c, r)
        sl = (slice(r * S, r * S + S), slice(c * S, c * S + S))
        albedo[sl] = np.dstack([np.clip(col, 0, 1), alpha])
        normal[sl] = np.dstack([normal_map(h), np.ones((S, S))])
        g = np.clip(gloss, 0, 1)
        spec[sl] = np.dstack([g, g, g, np.ones((S, S))])
    return albedo, normal, spec


def save(arr, path):
    Image.fromarray((np.clip(arr, 0, 1) * 255).round().astype(np.uint8), "RGBA").save(path)


def write_tileset():
    h = S // 2
    full = f"PackedVector2Array({-h}, {-h}, {h}, {-h}, {h}, {h}, {-h}, {h})"
    plank = f"PackedVector2Array({-h}, {-h}, {h}, {-h}, {h}, {-h + 12}, {-h}, {-h + 12})"
    lines = []
    for name, (c, r, kind) in sorted(TILES.items(), key=lambda kv: (kv[1][1], kv[1][0])):
        k = f"{c}:{r}/0"
        lines.append(f"{k} = 0")
        if kind in ("stone", "veil"):
            lines.append(f"{k}/physics_layer_0/polygon_0/points = {full}")
        elif kind == "walkway":
            lines.append(f"{k}/physics_layer_1/polygon_0/points = {plank}")
            lines.append(f"{k}/physics_layer_1/polygon_0/one_way = true")
        lines.append(f'{k}/custom_data_0 = "{kind}"')
    body = "\n".join(lines)
    out = f"""[gd_resource type="TileSet" load_steps=6 format=3]

[ext_resource type="Texture2D" path="res://assets/tiles/greybox_albedo.png" id="1_albedo"]
[ext_resource type="Texture2D" path="res://assets/tiles/greybox_normal.png" id="2_normal"]
[ext_resource type="Texture2D" path="res://assets/tiles/greybox_specular.png" id="3_specular"]

[sub_resource type="CanvasTexture" id="CanvasTexture_greybox"]
diffuse_texture = ExtResource("1_albedo")
normal_texture = ExtResource("2_normal")
specular_texture = ExtResource("3_specular")
specular_color = Color(0.82, 0.88, 1, 1)
specular_shininess = 0.7

[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_greybox"]
texture = SubResource("CanvasTexture_greybox")
texture_region_size = Vector2i({S}, {S})
{body}

[resource]
tile_size = Vector2i({S}, {S})
physics_layer_0/collision_layer = 1
physics_layer_0/collision_mask = 0
physics_layer_1/collision_layer = 2
physics_layer_1/collision_mask = 0
custom_data_layer_0/name = "kind"
custom_data_layer_0/type = 4
sources/0 = SubResource("TileSetAtlasSource_greybox")
"""
    with open("tiles/greybox_tileset.tres", "w") as f:
        f.write(out)


albedo, normal, spec = build()

if __name__ == "__main__":
    save(albedo, "assets/tiles/greybox_albedo.png")
    save(normal, "assets/tiles/greybox_normal.png")
    save(spec, "assets/tiles/greybox_specular.png")
    write_tileset()
    print(f"wrote {len(TILES)} tiles ({S}px) and tiles/greybox_tileset.tres")
