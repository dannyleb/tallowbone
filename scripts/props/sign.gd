## A wooden sign. Stand near it to read it; the HUD shows the text. Two
## spaces in the text start a new line.
extends Node2D

@export_multiline var text := ""

var near := false


func _draw() -> void:
	draw_rect(Rect2(-1.5, -26, 3, 26), Color("3b2a1f"))
	draw_rect(Rect2(-11, -34, 22, 13), Color("6d5440") if near else Color("4a372a"))
	for i in 3:
		draw_rect(Rect2(-7, -31 + i * 3.5, 14 - i * 3, 1), Color(0.91, 0.87, 0.81, 0.45))


func set_near(value: bool) -> void:
	if value != near:
		near = value
		queue_redraw()
