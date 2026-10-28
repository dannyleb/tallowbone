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
## Turns the drawing white for a hit flash (painted frames can't be
## recoloured the way the greybox is).
const FLASH_CODE := "shader_type canvas_item;\nuniform float flash = 0.0;\nvoid fragment() { COLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash); }\n"
static var _flash_shader: Shader

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
	# Painted frames (scripts/art.gd) are drawn smaller than they're painted.
	_painter.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_CODE
	var flash_mat := ShaderMaterial.new()
	flash_mat.shader = _flash_shader
	_painter.material = flash_mat
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
	if _painter and _active and (always or _seen.is_on_screen()):
		_render()


func _render() -> void:
	_painter.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## How white the drawing is, 0 to 1 (hit flashes on painted frames).
func set_flash(amount: float) -> void:
	if _painter:
		(_painter.material as ShaderMaterial).set_shader_parameter("flash", amount)


## Shows or hides the figure and stops or starts its viewport (the
## benchmark switches figures off this way).
func set_active(on: bool) -> void:
	_active = on
	visible = on
	if on:
		_render()
	else:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
