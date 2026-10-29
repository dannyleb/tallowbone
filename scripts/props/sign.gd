## A wooden sign. Stand near it to read it; the HUD shows the text. Two
## spaces in the text start a new line.
extends Node2D

@export_multiline var text := ""

var near := false


## A church noticeboard: two weathered planks on a post under a little
## gabled cap, nailed, a paper notice pinned to it.
func _draw() -> void:
	var wood := Color("6d5440") if near else Color("4a372a")
	var dark := Color("2a1e16")
	draw_rect(Rect2(-3, -3, 6, 3), dark)
	draw_rect(Rect2(-1.6, -26, 3.2, 24), Color("3b2a1f"))
	draw_rect(Rect2(-12.5, -35.5, 25, 16), dark)
	draw_rect(Rect2(-11.5, -34.5, 23, 6.6), wood)
	draw_rect(Rect2(-11.5, -27.6, 23, 6.6), wood.darkened(0.12))
	draw_line(Vector2(-11.5, -31.5), Vector2(11.5, -31.2), wood.darkened(0.3), 0.5)
	draw_colored_polygon(PackedVector2Array([Vector2(-14, -35.3), Vector2(14, -35.3), Vector2(0, -40.5)]), dark)
	for p in [Vector2(-10.3, -33.4), Vector2(10.3, -33.4), Vector2(-10.3, -22.2), Vector2(10.3, -22.2)]:
		draw_circle(p, 0.55, Color("1c1714"))
	# The notice: pale paper, curling at a corner, lines of print.
	var paper := Color(0.91, 0.87, 0.78, 0.8 if near else 0.6)
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -33.5), Vector2(4, -33.8), Vector2(4.3, -23.5), Vector2(-6.5, -23.2), Vector2(-8.2, -24.6)]), paper)
	draw_circle(Vector2(-1.8, -33.2), 0.5, Color("8a2a24"))
	for i in 4:
		draw_rect(Rect2(-6.5, -31.5 + i * 2.0, 9.5 - (i % 2) * 2.5, 0.6), Color(0.15, 0.12, 0.1, 0.6))


func set_near(value: bool) -> void:
	if value != near:
		near = value
		queue_redraw()
