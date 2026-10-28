"""Greybox tile atlas: draws assets/tiles/greybox.png and writes the
TileSet that uses it (tiles/greybox_tileset.tres).

Each tile has a custom-data "kind" the game reads: stone (solid), walkway
(one-way), water (hazard), veil (solid until the Lantern burns it), wall
(back wall, decoration only). Stone variants differ only in which edges
are drawn as exposed; the level builder picks them from the neighbours.

Run from the repo root:  python3 tools/tiles.py
"""
from PIL import Image, ImageDraw
import math
import random

T = 32
COLS, ROWS = 8, 3

# atlas (col, row) -> (name, kind)
TILES = {
    (0, 0): ("stone_top", "stone"),
    (1, 0): ("stone_face", "stone"),
    (2, 0): ("stone_deep", "stone"),
    (3, 0): ("stone_top_l", "stone"),
    (4, 0): ("stone_top_r", "stone"),
    (5, 0): ("stone_top_lr", "stone"),
    (6, 0): ("stone_face_l", "stone"),
    (7, 0): ("stone_face_r", "stone"),
    (0, 1): ("stone_face_lr", "stone"),
    (1, 1): ("walkway", "walkway"),
    (2, 1): ("walkway_l", "walkway"),
    (3, 1): ("walkway_r", "walkway"),
    (4, 1): ("walkway_lr", "walkway"),
    (5, 1): ("water_surface", "water"),
    (6, 1): ("water_deep", "water"),
    (7, 1): ("veil", "veil"),
    (0, 2): ("wall", "wall"),
    (1, 2): ("wall_b", "wall"),
    (2, 2): ("wall_c", "wall"),
}
BY_NAME = {name: pos for pos, (name, _) in TILES.items()}

STONE = (29, 30, 40)
STONE_DEEP = (18, 18, 25)
STONE_TOP = (74, 76, 92)
STONE_EDGE = (44, 46, 59)
# Drawing on an RGBA image replaces pixels rather than blending, so
# translucent details are pre-mixed against what they sit on.
def mix(base, over, a):
    return tuple(round(b + (o - b) * a) for b, o in zip(base, over))


MORTAR = mix((29, 30, 40), (0, 0, 0), 0.32)
WOOD = (59, 42, 31)
WOOD_TOP = (106, 76, 53)
IRON = (42, 42, 48)
WATER = (13, 40, 36)
WATER_DEEP = (5, 16, 14)
WATER_LINE = (75, 140, 124)
VEIL = (228, 220, 198)
WALL = (18, 18, 25)


def tile(img, pos):
    return img.crop((pos[0] * T, pos[1] * T, pos[0] * T + T, pos[1] * T + T))


def bricks(d, x0, y0):
    for y in (15, 31):
        d.line([(x0, y0 + y), (x0 + T - 1, y0 + y)], fill=MORTAR)
    d.line([(x0 + 0, y0), (x0 + 0, y0 + 14)], fill=MORTAR)
    d.line([(x0 + 16, y0), (x0 + 16, y0 + 14)], fill=MORTAR)
    d.line([(x0 + 8, y0 + 16), (x0 + 8, y0 + 30)], fill=MORTAR)
    d.line([(x0 + 24, y0 + 16), (x0 + 24, y0 + 30)], fill=MORTAR)


def stone(d, x0, y0, top, left, right):
    d.rectangle([x0, y0, x0 + T - 1, y0 + T - 1], fill=STONE)
    bricks(d, x0, y0)
    if top:
        d.rectangle([x0, y0, x0 + T - 1, y0 + 2], fill=STONE_TOP)
        for i, off in enumerate((1, 3, 0, 2)):
            d.rectangle([x0 + i * 8 + off, y0 + 3, x0 + i * 8 + off + 4, y0 + 4], fill=STONE_EDGE)
    if left:
        d.rectangle([x0, y0, x0 + 1, y0 + T - 1], fill=STONE_EDGE)
    if right:
        d.rectangle([x0 + T - 2, y0, x0 + T - 1, y0 + T - 1], fill=STONE_EDGE)


def walkway(d, x0, y0, left, right):
    d.rectangle([x0, y0, x0 + T - 1, y0 + 6], fill=WOOD)
    d.rectangle([x0, y0, x0 + T - 1, y0 + 1], fill=WOOD_TOP)
    d.line([(x0 + 15, y0 + 2), (x0 + 15, y0 + 6)], fill=mix(WOOD, (0, 0, 0), 0.35))
    if left:
        d.rectangle([x0 + 3, y0 + 7, x0 + 4, y0 + 22], fill=IRON)
    if right:
        d.rectangle([x0 + T - 5, y0 + 7, x0 + T - 4, y0 + 22], fill=IRON)


def water(d, x0, y0, surface):
    d.rectangle([x0, y0, x0 + T - 1, y0 + T - 1], fill=WATER if surface else WATER_DEEP)
    if surface:
        pts = [(x0 + i, y0 + 3 + round(math.sin(i * 0.4) * 1.5)) for i in range(T)]
        d.line(pts, fill=mix(WATER, WATER_LINE, 0.6))


def veil(img, x0, y0):
    layer = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle([0, 0, T - 1, T - 1], fill=VEIL + (30,))
    rnd = random.Random(7)
    for i in range(7):
        sx = rnd.randint(2, 29)
        sway = rnd.uniform(-3, 3)
        pts = []
        for s in range(9):
            t = s / 8
            pts.append((sx + math.sin(t * math.pi * 1.5 + i) * sway, t * (T - 1)))
        d.line(pts, fill=VEIL + (140,), width=1)
    img.alpha_composite(layer, (x0, y0))


def wall(d, x0, y0, variant):
    joint = mix(WALL, (0, 0, 0), 0.3)
    d.rectangle([x0, y0, x0 + T - 1, y0 + T - 1], fill=WALL)
    if variant == 1:
        d.rectangle([x0 + 6, y0 + 11, x0 + 19, y0 + 20], fill=mix(WALL, (255, 255, 255), 0.03))
    for y in (10, 21, 31):
        d.line([(x0, y0 + y), (x0 + T - 1, y0 + y)], fill=joint)
    joints = [(4, 12, 20), (8, 16, 2), (12, 4, 26)][variant]
    d.line([(x0 + joints[0], y0), (x0 + joints[0], y0 + 9)], fill=joint)
    d.line([(x0 + joints[1], y0 + 11), (x0 + joints[1], y0 + 20)], fill=joint)
    d.line([(x0 + joints[2], y0 + 22), (x0 + joints[2], y0 + 30)], fill=joint)


def draw_atlas():
    img = Image.new("RGBA", (COLS * T, ROWS * T), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for (c, r), (name, _) in TILES.items():
        x0, y0 = c * T, r * T
        if name.startswith("stone_deep"):
            d.rectangle([x0, y0, x0 + T - 1, y0 + T - 1], fill=STONE_DEEP)
        elif name.startswith("stone"):
            parts = name.split("_")
            sides = parts[2] if len(parts) > 2 else ""
            stone(d, x0, y0, parts[1] == "top", "l" in sides, "r" in sides)
        elif name.startswith("walkway"):
            sides = name.split("_")[1] if "_" in name else ""
            walkway(d, x0, y0, "l" in sides, "r" in sides)
        elif name.startswith("water"):
            water(d, x0, y0, name == "water_surface")
        elif name == "veil":
            veil(img, x0, y0)
        elif name.startswith("wall"):
            wall(d, x0, y0, {"wall": 0, "wall_b": 1, "wall_c": 2}[name])
    img.save("assets/tiles/greybox.png")


def write_tileset():
    h = T // 2
    full = f"PackedVector2Array({-h}, {-h}, {h}, {-h}, {h}, {h}, {-h}, {h})"
    plank = f"PackedVector2Array({-h}, {-h}, {h}, {-h}, {h}, {-h + 6}, {-h}, {-h + 6})"
    lines = []
    for (c, r), (name, kind) in sorted(TILES.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        k = f"{c}:{r}/0"
        lines.append(f"{k} = 0")
        if kind in ("stone", "veil"):
            lines.append(f"{k}/physics_layer_0/polygon_0/points = {full}")
        elif kind == "walkway":
            lines.append(f"{k}/physics_layer_1/polygon_0/points = {plank}")
            lines.append(f"{k}/physics_layer_1/polygon_0/one_way = true")
        lines.append(f'{k}/custom_data_0 = "{kind}"')
    body = "\n".join(lines)
    out = f"""[gd_resource type="TileSet" load_steps=3 format=3]

[ext_resource type="Texture2D" path="res://assets/tiles/greybox.png" id="1_atlas"]

[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_greybox"]
texture = ExtResource("1_atlas")
texture_region_size = Vector2i({T}, {T})
{body}

[resource]
tile_size = Vector2i({T}, {T})
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


if __name__ == "__main__":
    draw_atlas()
    write_tileset()
    print("wrote assets/tiles/greybox.png and tiles/greybox_tileset.tres")
