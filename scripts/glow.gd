## Shared soft-light textures and a helper to make 2D lights from them.
extends RefCounted

static var _glow: GradientTexture2D
static var _vignette: GradientTexture2D


## White in the middle, fading to nothing at the edge. Used for every
## PointLight2D and for drawn glows (glints, embers, halos).
static func texture() -> GradientTexture2D:
	if _glow == null:
		_glow = _radial(PackedFloat32Array([0.0, 0.45, 1.0]),
			PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)]))
	return _glow


## Clear in the middle, darkening toward the corners.
static func vignette() -> GradientTexture2D:
	if _vignette == null:
		_vignette = _radial(PackedFloat32Array([0.0, 0.62, 1.0]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.6)]))
	return _vignette


static func _radial(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


## A soft point light of the given radius (px). height: how far (px) it
## stands out from the wall, toward you; it decides how the bumps in the
## normal maps catch it (low = raking light, high = flat on).
static func light(color: Color, radius: float, energy: float, height := 40.0) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = texture()
	l.color = color
	l.energy = energy
	l.height = height
	# Mask 2 is indoor back walls: lamps and lanterns light them, the moon
	# doesn't.
	l.range_item_cull_mask = 3
	set_radius(l, radius)
	return l


static func set_radius(l: PointLight2D, radius: float) -> void:
	l.texture_scale = maxf(0.01, radius * 2.0 / 256.0)


## Draws a glow of the given radius on a CanvasItem.
static func draw(ci: CanvasItem, at: Vector2, radius: float, color: Color) -> void:
	ci.draw_texture_rect(texture(), Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)
