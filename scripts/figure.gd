## Shows an actor as a lit, rounded form. Its greybox drawing is painted into
## a small SubViewport at twice the resolution, then shown here through the
## volume shader (shaders/volume.gdshader), so the scene's lights shade it
## like something solid instead of flat paper. Illustrated sprites can use
## the same shader directly.
##
## The viewport only renders when the actor is on screen and its drawing
## changed: off-screen actors cost nothing to draw.
extends Sprite2D

## Render resolution: viewport pixels per world pixel.
const RES := 2.0
const VOLUME := preload("res://shaders/volume.gdshader")

var _viewport: SubViewport
var _painter: Node2D
var _seen: VisibleOnScreenNotifier2D
var _active := true


## size: the drawing's bounds in world px. origin: where the actor's feet are
## inside them. paint: called with the CanvasItem to draw on, in the actor's
## own coordinates (feet at 0, 0).
func setup(size: Vector2, origin: Vector2, paint: Callable) -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.size = Vector2i(size * RES)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_painter = Node2D.new()
	_painter.position = origin * RES
	_painter.scale = Vector2(RES, RES)
	_painter.draw.connect(func(): paint.call(_painter))
	_viewport.add_child(_painter)
	texture = _viewport.get_texture()
	centered = false
	offset = -origin * RES
	scale = Vector2.ONE / RES
	var m := ShaderMaterial.new()
	m.shader = VOLUME
	material = m
	# In this sprite's own (scaled) coordinates, like the texture.
	_seen = VisibleOnScreenNotifier2D.new()
	_seen.rect = Rect2(-origin * RES, size * RES)
	_seen.screen_entered.connect(_render)
	add_child(_seen)


## Asks for a fresh drawing this frame, if anyone can see it.
func redraw() -> void:
	if _painter and _active and _seen.is_on_screen():
		_render()


func _render() -> void:
	_painter.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Shows or hides the figure and stops or starts its viewport (the
## benchmark switches figures off this way).
func set_active(on: bool) -> void:
	_active = on
	visible = on
	if on:
		_render()
	else:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
