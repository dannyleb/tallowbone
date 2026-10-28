## Something to find. vial: a Vial Holder (+1 vial, refilled at lamps).
## bullets: a Bullet Pouch (+3 bullets). Taken for good once picked up.
extends Node2D

const Glow = preload("res://scripts/glow.gd")

@export_enum("vial", "bullets") var kind := "vial"

var taken := false
var _time := 0.0
var _light: PointLight2D


func _ready() -> void:
	_light = Glow.light(Color(1.0, 0.85, 0.8), 34.0, 0.7, 16.0)
	_light.position = Vector2(0, -14)
	add_child(_light)


func take() -> void:
	taken = true
	visible = false


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var y := -14.0 + sin(_time * 2.5 + position.x) * 2.5
	if kind == "vial":
		draw_rect(Rect2(-1.5, y - 9, 3, 3), Color("e8dfcf"))
		draw_circle(Vector2(0, y), 5.5, Color("c42b2f"))
		draw_rect(Rect2(-3, y - 3, 1.5, 3), Color(1, 1, 1, 0.5))
	else:
		draw_rect(Rect2(-6, y - 5, 12, 10), Color("4a3a2a"))
		for i in 3:
			draw_rect(Rect2(-4 + i * 3, y - 8, 2, 4), Color("c9a34a"))
