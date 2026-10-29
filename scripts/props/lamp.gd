## A street lamp. The first press lights it and makes it your checkpoint;
## after that, pressing again rests there: heal, refill, level up, and the
## night's horrors come back.
extends Node2D

const Glow = preload("res://scripts/glow.gd")

const IRON := Color("2a2a30")
const GLASS_DARK := Color("26252a")
const GLASS_LIT := Color("ffcf7a")

@export var lit := false
## The 3D stage builds this lamp in iron (scripts/stage.gd); then only its
## light and logic are this node's.
var in_3d := false

var _lit_t := 0.0
var _time := 0.0
var _light: PointLight2D
var _drawn_dark := false


func _ready() -> void:
	_light = Glow.light(Color(1.0, 0.76, 0.45), 190.0, 1.9, 50.0)
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
	_light.energy = 1.9 * flicker * minf(1.0, _lit_t * 2.0 + 0.3)
	# Only a lit lamp changes (its glass flickers); a dark one is drawn once.
	if lit or not _drawn_dark:
		_drawn_dark = not lit
		queue_redraw()


## A Victorian gas lamp: a stepped plinth, a fluted post with collars, the
## lamplighter's ladder bar, scrolled brackets, and the lantern: a glass
## cage widening upward under a peaked cap and finial.
func _draw() -> void:
	if in_3d:
		return
	var dark := IRON.darkened(0.35)
	draw_rect(Rect2(-8, -5, 16, 5), IRON)
	draw_rect(Rect2(-6, -9, 12, 4), IRON)
	draw_circle(Vector2(0, -12), 3.6, IRON)
	draw_colored_polygon(PackedVector2Array([Vector2(-2.6, -14), Vector2(2.6, -14), Vector2(1.8, -57), Vector2(-1.8, -57)]), IRON)
	draw_line(Vector2(-0.8, -15), Vector2(-0.5, -55), dark, 0.6)
	draw_line(Vector2(0.9, -15), Vector2(0.6, -55), dark, 0.6)
	draw_rect(Rect2(-3.4, -31, 6.8, 2), IRON)
	draw_rect(Rect2(-3, -57.5, 6, 2), IRON)
	# The ladder bar, knobbed at the ends.
	draw_rect(Rect2(-10, -50.8, 20, 1.6), IRON)
	draw_circle(Vector2(-10, -50), 1.3, IRON)
	draw_circle(Vector2(10, -50), 1.3, IRON)
	# Scrolls up to the lantern's base.
	draw_arc(Vector2(-4, -57), 3.0, PI * 0.5, PI * 1.5, 8, IRON, 1.0)
	draw_arc(Vector2(4, -57), 3.0, -PI * 0.5, PI * 0.5, 8, IRON, 1.0)
	draw_rect(Rect2(-6, -61, 12, 1.6), IRON)
	var glass := GLASS_DARK
	if lit:
		glass = GLASS_LIT
		glass.a = 0.85 + 0.15 * sin(_time * 13.0 + position.x) * sin(_time * 7.3)
	draw_colored_polygon(PackedVector2Array([Vector2(-5, -60), Vector2(5, -60), Vector2(7, -75), Vector2(-7, -75)]), glass)
	for x in [-6.0, 0.0, 6.0]:
		draw_line(Vector2(x * 0.72, -60), Vector2(x, -75), IRON, 0.8)
	draw_rect(Rect2(-8, -76.5, 16, 1.8), IRON)
	draw_colored_polygon(PackedVector2Array([Vector2(-8.5, -76), Vector2(8.5, -76), Vector2(2, -82), Vector2(-2, -82)]), IRON)
	draw_circle(Vector2(0, -83), 1.4, IRON)
	draw_line(Vector2(0, -84), Vector2(0, -88), IRON, 0.8)
