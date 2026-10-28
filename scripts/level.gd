## A level: its tile layers and everything placed in it.
##
## Ground tiles carry a custom-data "kind": stone (solid), walkway (one-way),
## water (hazard), veil (solid until the Lantern burns it). Props and
## enemies live under Entities; the game finds them by group.
extends Node2D

const T = preload("res://scripts/tuning.gd")

@export var level_name := "Unnamed"
## Width and height in tiles. Past the sides and the bottom counts as stone.
@export var size_tiles := Vector2i(100, 30)

@onready var ground: TileMapLayer = $Ground
@onready var back_wall: TileMapLayer = $BackWall
@onready var entities: Node2D = $Entities
@onready var player_start: Marker2D = $PlayerStart


func size_px() -> Vector2:
	return Vector2(size_tiles * T.TILE)


static func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / T.TILE), floori(p.y / T.TILE))


func kind_at(cell: Vector2i) -> String:
	if cell.x < 0 or cell.x >= size_tiles.x or cell.y >= size_tiles.y:
		return "stone"
	if cell.y < 0:
		return ""
	var data := ground.get_cell_tile_data(cell)
	return "" if data == null else String(data.get_custom_data("kind"))


func solid_at(p: Vector2) -> bool:
	var k := kind_at(cell_at(p))
	return k == "stone" or k == "veil"


func standable_at(p: Vector2) -> bool:
	return solid_at(p) or kind_at(cell_at(p)) == "walkway"


func hazard_at(p: Vector2) -> bool:
	return kind_at(cell_at(p)) == "water"


## Indoors or underground: there's a back wall here instead of sky.
func roofed_at(p: Vector2) -> bool:
	return back_wall.get_cell_source_id(cell_at(p)) != -1


## The y of the first open-air floor at x between y0 and y1 (stone or a
## walkway with sky above it), or -1 if there isn't one.
func ground_below(x: float, y0: float, y1: float) -> float:
	var c := floori(x / T.TILE)
	for r in range(maxi(0, floori(y0 / T.TILE)), mini(size_tiles.y + 1, floori(y1 / T.TILE) + 1)):
		var k := kind_at(Vector2i(c, r))
		if k != "stone" and k != "walkway":
			continue
		var above := Vector2i(c, r - 1)
		if kind_at(above) == "" and back_wall.get_cell_source_id(above) == -1:
			return r * float(T.TILE)
	return -1.0


## Things placed in the level, by group: "lamps", "signs", "pickups",
## "enemies".
func members(group: String) -> Array:
	return entities.get_children().filter(func(n): return n.is_in_group(group))


## Burns any veil touching the rect, and the rest of that veil with it (fire
## spreads through connected veil tiles). Returns the burnt cells.
func burn(rect: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var todo: Array[Vector2i] = []
	var a := cell_at(rect.position)
	var b := cell_at(rect.end)
	for r in range(a.y, b.y + 1):
		for c in range(a.x, b.x + 1):
			todo.append(Vector2i(c, r))
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_back()
		if kind_at(cell) != "veil":
			continue
		ground.erase_cell(cell)
		out.append(cell)
		todo.append(cell + Vector2i.RIGHT)
		todo.append(cell + Vector2i.LEFT)
		todo.append(cell + Vector2i.DOWN)
		todo.append(cell + Vector2i.UP)
	return out


## How far a horizontal ray from `from` gets in direction `dir` before
## hitting stone, up to `max_dist`.
func ray_length(from: Vector2, dir: float, max_dist: float) -> float:
	var d := 0.0
	while d < max_dist:
		if solid_at(from + Vector2(dir * d, 0)):
			return d
		d += 4.0
	return max_dist


## Can `a` see `b`? Samples the straight line between them.
func line_of_sight(a: Vector2, b: Vector2) -> bool:
	var n := ceili(a.distance_to(b) / (T.TILE / 2.0))
	for i in range(1, n):
		if solid_at(a.lerp(b, float(i) / n)):
			return false
	return true
