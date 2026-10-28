"""ASCII level -> Godot scene.

Reads tools/levels/<name>.txt and writes scenes/levels/<name>.tscn: a
BackWall and a Ground TileMapLayer (using tiles/greybox_tileset.tres),
a PlayerStart marker, and the lamps, signs, pickups and enemies placed
as instances under Entities, so all of it can be moved and edited in
the Godot editor afterwards.

Run from the repo root:  python3 tools/build_level.py canal_district
"""
import struct
import sys

sys.path.insert(0, "tools")
from tiles import BY_NAME  # noqa: E402

T = 32
SOLID = set("#V")
SCENES = {
    "lamp": "res://scenes/props/lamp.tscn",
    "sign": "res://scenes/props/sign.tscn",
    "pickup": "res://scenes/props/pickup.tscn",
    "communicant": "res://scenes/actors/communicant.tscn",
    "hound": "res://scenes/actors/hound.tscn",
}


def read(path):
    sections, cur = {}, None
    for line in open(path).read().split("\n"):
        if line.startswith("#") and cur != "map":
            continue
        if line.startswith("[") and line.endswith("]"):
            cur = line[1:-1]
            sections[cur] = []
        elif cur:
            sections[cur].append(line)
    name = next(l for l in sections["name"] if l.strip()).strip()
    signs = {}
    for l in sections.get("signs", []):
        if "=" in l:
            k, v = l.split("=", 1)
            signs[k.strip()] = v.strip()
    rows = [l for l in sections["map"] if l]
    return name, signs, rows


def build(rows):
    h, w = len(rows), len(rows[0])
    for i, r in enumerate(rows):
        assert len(r) == w, f"row {i} is {len(r)} wide, not {w}"
    grid = [list(r) for r in rows]
    marks = []
    for r in range(h):
        for c in range(w):
            ch = grid[r][c]
            if ch in "PLchvb123456789":
                marks.append((ch, c, r))
                grid[r][c] = "."

    def at(c, r):
        if c < 0 or c >= w or r >= h:
            return "#"
        if r < 0:
            return "."
        return grid[r][c]

    solid = lambda c, r: at(c, r) in SOLID
    ground, back = [], []
    for r in range(h):
        for c in range(w):
            t = at(c, r)
            name = None
            if t == "#":
                op = lambda dc, dr: not solid(c + dc, r + dr)
                if not (op(0, -1) or op(-1, 0) or op(1, 0) or op(0, 1) or op(0, -2)):
                    name = "stone_deep"
                else:
                    sides = ("l" if op(-1, 0) else "") + ("r" if op(1, 0) else "")
                    name = "stone_" + ("top" if op(0, -1) else "face") + (f"_{sides}" if sides else "")
            elif t == "=":
                sides = ("l" if at(c - 1, r) != "=" else "") + ("r" if at(c + 1, r) != "=" else "")
                name = "walkway" + (f"_{sides}" if sides else "")
            elif t == "~":
                name = "water_surface" if at(c, r - 1) != "~" else "water_deep"
            elif t == "V":
                name = "veil"
            if name:
                ground.append((c, r, BY_NAME[name]))

    # Back wall wherever there's stone somewhere overhead: indoors and
    # underground get brick instead of sky.
    for c in range(w):
        covered = False
        for r in range(h):
            if covered and at(c, r) != "#":
                variant = ["wall", "wall", "wall_b", "wall", "wall_c"][(c * 7 + r * 13) % 5]
                back.append((c, r, BY_NAME[variant]))
            if solid(c, r):
                covered = True
    return w, h, ground, back, marks


def tile_data(cells):
    # TileMapLayer.tile_map_data: a uint16 format version (0), then 12 bytes
    # per cell: x, y (int16), source id, atlas x, atlas y, alternative (uint16).
    b = bytearray(struct.pack("<H", 0))
    for c, r, (ax, ay) in cells:
        b += struct.pack("<hhHHHH", c, r, 0, ax, ay, 0)
    return "PackedByteArray(" + ", ".join(str(x) for x in b) + ")"


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def write(slug, name, signs, w, h, ground, back, marks):
    ext = [("Script", "res://scripts/level.gd", "1_level"), ("TileSet", "res://tiles/greybox_tileset.tres", "2_tiles")]
    ids = {}
    for i, (key, path) in enumerate(SCENES.items()):
        ids[key] = f"{i + 3}_{key}"
        ext.append(("PackedScene", path, ids[key]))
    out = [f"[gd_scene load_steps={len(ext) + 1} format=3]", ""]
    out += [f'[ext_resource type="{t}" path="{p}" id="{i}"]' for t, p, i in ext]
    root = "".join(part.capitalize() for part in slug.split("_"))
    out += ["", f'[node name="{root}" type="Node2D"]', 'script = ExtResource("1_level")',
            f'level_name = "{esc(name)}"', f"size_tiles = Vector2i({w}, {h})", ""]
    out += ['[node name="BackWall" type="TileMapLayer" parent="."]', "z_index = -1",
            f"tile_map_data = {tile_data(back)}", 'tile_set = ExtResource("2_tiles")', ""]
    out += ['[node name="Ground" type="TileMapLayer" parent="."]',
            f"tile_map_data = {tile_data(ground)}", 'tile_set = ExtResource("2_tiles")', ""]

    counts = {}

    def node(kind, label, c, r, extra=()):
        counts[label] = counts.get(label, 0) + 1
        x, y = (c + 0.5) * T, (r + 1) * T
        lines = [f'[node name="{label}{counts[label]}" parent="Entities" instance=ExtResource("{ids[kind]}")]',
                 f"position = Vector2({x:g}, {y:g})"]
        return lines + list(extra) + [""]

    start = next((c, r) for ch, c, r in marks if ch == "P")
    out += ['[node name="PlayerStart" type="Marker2D" parent="."]',
            f"position = Vector2({(start[0] + 0.5) * T:g}, {(start[1] + 1) * T:g})", ""]
    out += ['[node name="Entities" type="Node2D" parent="."]', ""]
    for ch, c, r in marks:
        if ch == "L":
            out += node("lamp", "Lamp", c, r)
        elif ch == "c":
            out += node("communicant", "Communicant", c, r)
        elif ch == "h":
            out += node("hound", "Hound", c, r)
        elif ch == "v":
            out += node("pickup", "VialHolder", c, r, ['kind = "vial"'])
        elif ch == "b":
            out += node("pickup", "BulletPouch", c, r, ['kind = "bullets"'])
        elif ch.isdigit():
            out += node("sign", "Sign", c, r, [f'text = "{esc(signs[ch])}"'])
    path = f"scenes/levels/{slug}.tscn"
    with open(path, "w") as f:
        f.write("\n".join(out))
    return path


if __name__ == "__main__":
    slug = sys.argv[1] if len(sys.argv) > 1 else "canal_district"
    name, signs, rows = read(f"tools/levels/{slug}.txt")
    w, h, ground, back, marks = build(rows)
    path = write(slug, name, signs, w, h, ground, back, marks)
    print(f"wrote {path}: {w}x{h} tiles, {len(ground)} ground, {len(back)} back wall, {len(marks)} markers")
