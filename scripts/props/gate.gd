## A barred gate: a shortcut that only opens from one side. From the other
## side it's just bars you can see through. Once opened it stays open,
## through rests and deaths.
extends StaticBody2D

const IRON := Color("3a3a42")
const RUST := Color("5a3a2a")
const HEIGHT := 96.0

## Which side the bar is lifted from.
@export_enum("east", "west") var opens_from := "east"

var open := false
var _lift := 0.0


## Is x on the side the gate opens from?
func reachable_from(x: float) -> bool:
	return (x > position.x) == (opens_from == "east")


func open_gate() -> void:
	open = true
	$Bars.set_deferred("disabled", true)


func _process(delta: float) -> void:
	if open and _lift < 1.0:
		_lift = minf(1.0, _lift + delta * 2.0)
		queue_redraw()


func _draw() -> void:
	var top := -HEIGHT
	# Posts and lintel.
	draw_rect(Rect2(-9, top - 4, 18, 5), IRON)
	draw_rect(Rect2(-9, top, 3, HEIGHT), IRON)
	draw_rect(Rect2(6, top, 3, HEIGHT), IRON)
	# Bars, sliding up into the lintel as it opens.
	var rise := _lift * (HEIGHT - 8.0)
	for i in 4:
		var x := -5.0 + i * 3.4
		draw_rect(Rect2(x, top, 1.6, HEIGHT - rise), IRON)
		# A spear point standing above the lintel.
		draw_colored_polygon(PackedVector2Array([Vector2(x - 0.6, top - 4), Vector2(x + 2.2, top - 4), Vector2(x + 0.8, top - 8.5)]), IRON)
	for x in [-7.5, 7.5]:
		draw_circle(Vector2(x, top - 1.5), 0.7, IRON.lightened(0.15))
	for y in [-30.0, -66.0]:
		var cy: float = y - rise
		if cy > top:
			draw_rect(Rect2(-6, cy, 12, 2), IRON)
	if not open:
		# The bar across it, on the side it opens from.
		var side := 1.0 if opens_from == "east" else -1.0
		draw_rect(Rect2(-12 if side < 0 else -2, -52, 14, 4), RUST)
		draw_rect(Rect2((9.0 if side > 0 else -12.0), -56, 3, 12), RUST)
