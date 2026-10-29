## Shows an actor as a lit, rounded form. Its greybox drawing is painted into
## a small SubViewport at twice the resolution, then shown here through the
## volume shader (shaders/volume.gdshader), so the scene's lights shade it
## like something solid instead of flat paper. Illustrated sprites can use
## the same shader directly.
##
## The viewport only renders when the actor is on screen and its drawing
## changed: off-screen actors cost nothing to draw.
extends Sprite2D

## Render resolution: viewport pixels per world pixel. The desktop draws
## the world at up to 3 render px per world px, so figures match it there;
## the browser keeps 2.
const RES := 2.0
const RES_DESKTOP := 3.0
const VOLUME := preload("res://shaders/volume.gdshader")
## The painter's shader: turns the drawing white for a hit flash (painted
## frames can't be recoloured the way the greybox is), and gives the greybox
## some surface so it isn't flat vector colour: a woven grain, long folds,
## a darker wet hem, colour a little muted. It works in the actor's own
## coordinates, so the texture moves with it. Painted frames are shown as
## painted (`textured` off).
const PAINTER := preload("res://shaders/figure_paint.gdshader")

## Repaint whenever the drawing changes, seen or not (the 3D stage shows
## figures through its own viewport, which the on-screen check can't see).
static var always := false

var _viewport: SubViewport
var _painter: Node2D
var _seen: VisibleOnScreenNotifier2D
var _active := true


## size: the drawing's bounds in world px. origin: where the actor's feet are
## inside them. paint: called with the CanvasItem to draw on, in the actor's
## own coordinates (feet at 0, 0).
func setup(size: Vector2, origin: Vector2, paint: Callable) -> void:
	var res := RES_DESKTOP if RenderingServer.get_current_rendering_method() == "forward_plus" else RES
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.size = Vector2i(size * res)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_painter = Node2D.new()
	_painter.position = origin * res
	_painter.scale = Vector2(res, res)
	_painter.draw.connect(func(): paint.call(_painter))
	# Painted frames (scripts/art.gd) are drawn smaller than they're painted.
	_painter.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var paint_mat := ShaderMaterial.new()
	paint_mat.shader = PAINTER
	_painter.material = paint_mat
	_viewport.add_child(_painter)
	texture = _viewport.get_texture()
	centered = false
	offset = -origin * res
	scale = Vector2.ONE / res
	var m := ShaderMaterial.new()
	m.shader = VOLUME
	material = m
	# In this sprite's own (scaled) coordinates, like the texture.
	_seen = VisibleOnScreenNotifier2D.new()
	_seen.rect = Rect2(-origin * res, size * res)
	_seen.screen_entered.connect(_render)
	add_child(_seen)


## Asks for a fresh drawing this frame, if anyone can see it.
func redraw() -> void:
	if _painter and _active and (always or _seen.is_on_screen()):
		_render()


func _render() -> void:
	_painter.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## How white the drawing is, 0 to 1 (hit flashes on painted frames).
func set_flash(amount: float) -> void:
	if _painter:
		(_painter.material as ShaderMaterial).set_shader_parameter("flash", amount)


## Whether the greybox surface texture applies (off for painted frames).
func set_textured(on: bool) -> void:
	if _painter:
		(_painter.material as ShaderMaterial).set_shader_parameter("textured", on)


## Shows or hides the figure and stops or starts its viewport (the
## benchmark switches figures off this way).
func set_active(on: bool) -> void:
	_active = on
	visible = on
	if on:
		_render()
	else:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
