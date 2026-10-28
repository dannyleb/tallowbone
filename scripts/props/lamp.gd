## A street lamp. The first press lights it and makes it your checkpoint;
## after that, pressing again rests there: heal, refill, level up, and the
## night's horrors come back.
extends Node2D

const Glow = preload("res://scripts/glow.gd")

const IRON := Color("2a2a30")
const GLASS_DARK := Color("26252a")
const GLASS_LIT := Color("ffcf7a")

@export var lit := false

var _lit_t := 0.0
var _time := 0.0
var _light: PointLight2D


func _ready() -> void:
	_light = Glow.light(Color(1.0, 0.76, 0.45), 165.0, 1.15)
	_light.position = Vector2(0, -68)
	add_child(_light)


func light_up() -> void:
	lit = true
	_lit_t = 0.0


func _process(delta: float) -> void:
	_time += delta
	_lit_t += delta
	var flicker := 1.0 + sin(_time * 11.0 + position.x) * sin(_time * 6.7 + position.x * 2.0) * 0.05
	_light.enabled = lit
	_light.energy = 1.15 * flicker * minf(1.0, _lit_t * 2.0 + 0.3)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-2, -60, 4, 60), IRON)
	draw_rect(Rect2(-7, -4, 14, 4), IRON)
	draw_rect(Rect2(-9, -50, 18, 2), IRON) # the lamplighter's ladder bar
	var glass := GLASS_DARK
	if lit:
		glass = GLASS_LIT
		glass.a = 0.85 + 0.15 * sin(_time * 13.0 + position.x) * sin(_time * 7.3)
	draw_colored_polygon(PackedVector2Array([Vector2(-7, -60), Vector2(7, -60), Vector2(5, -76), Vector2(-5, -76)]), glass)
	draw_rect(Rect2(-8, -79, 16, 3), IRON)
	draw_rect(Rect2(-1, -84, 2, 5), IRON)
