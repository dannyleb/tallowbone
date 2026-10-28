## Something to find, taken for good once picked up.
##   vial: a Vial Holder (+1 vial, refilled at lamps)
##   bullets: a Bullet Pouch (+3 bullets)
##   quickstep / pistol / lantern / irons: Watchman's Boots, the Watch
##   Pistol, Lamp Oil (the Lantern form), Climbing Irons (wall jump)
extends Node2D

const Glow = preload("res://scripts/glow.gd")

@export_enum("vial", "bullets", "quickstep", "pistol", "lantern", "irons") var kind := "vial"

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
	match kind:
		"vial":
			draw_rect(Rect2(-1.5, y - 9, 3, 3), Color("e8dfcf"))
			draw_circle(Vector2(0, y), 5.5, Color("c42b2f"))
			draw_rect(Rect2(-3, y - 3, 1.5, 3), Color(1, 1, 1, 0.5))
		"bullets":
			draw_rect(Rect2(-6, y - 5, 12, 10), Color("4a3a2a"))
			for i in 3:
				draw_rect(Rect2(-4 + i * 3, y - 8, 2, 4), Color("c9a34a"))
		"quickstep":
			# A pair of boots.
			for bx in [-6.0, 1.0]:
				draw_rect(Rect2(bx, y - 7, 4, 9), Color("3b2f28"))
				draw_rect(Rect2(bx, y, 7, 3), Color("3b2f28"))
			draw_rect(Rect2(-6, y - 7, 11, 1.5), Color("c9a34a"))
		"pistol":
			draw_rect(Rect2(-7, y - 4, 13, 4), Color("4a4650"))
			draw_rect(Rect2(-6, y, 4, 6), Color("5a3a28"))
			draw_rect(Rect2(4, y - 5, 2, 2), Color("c9a34a"))
		"lantern":
			# A flask of lamp oil, glowing.
			draw_rect(Rect2(-1.5, y - 10, 3, 3), Color("e8dfcf"))
			draw_circle(Vector2(0, y), 5.5, Color("f0bd62"))
			draw_rect(Rect2(-3, y - 3, 1.5, 3), Color(1, 1, 1, 0.6))
		"irons":
			# Two climbing hooks.
			for side in [-1.0, 1.0]:
				draw_line(Vector2(side * 2, y + 4), Vector2(side * 2, y - 6), Color("8a8a95"), 2.0)
				draw_arc(Vector2(side * 5, y - 6), 3.0, PI, TAU if side > 0 else PI * 1.0 + PI, 6, Color("8a8a95"), 1.5)
