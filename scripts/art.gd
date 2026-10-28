## Painted character frames (docs/ART.md): art/characters/<who>/<anim>/
## 01.png, 02.png, ... Each frame is the actor's whole drawing canvas at
## SCALE art px per world px, facing right, feet on the template's feet
## line. Found once at startup; an animation without frames falls back to
## the greybox drawing, so art can arrive one animation at a time.
extends RefCounted

## Art px per world px.
const SCALE := 4.0

## Where the frames live. The playtest points it at its own fixtures.
static var root := "res://art/characters"
static var _cache := {}


## Every painted animation for `who`: name -> Array of textures, in order.
static func frames(who: String) -> Dictionary:
	if _cache.has(who):
		return _cache[who]
	var out := {}
	var dir := root.path_join(who)
	for anim in _list(dir, true):
		var textures := []
		for n in _list(dir.path_join(anim), false):
			if n.get_extension().to_lower() != "png":
				continue
			var tex = load(dir.path_join(anim).path_join(n))
			if tex is Texture2D:
				textures.append(tex)
		if not textures.is_empty():
			out[anim] = textures
	_cache[who] = out
	return out


## The folders (or files) in a res:// folder, sorted; none if it's missing.
## ResourceLoader's listing also works in exported builds, where the images
## themselves aren't files any more.
static func _list(dir: String, folders: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with("/") == folders:
			out.append(entry.trim_suffix("/"))
	out.sort()
	return out


## Forgets what was found (after changing `root`).
static func reload() -> void:
	_cache.clear()


## Draws the painted frame for pose [anim, frame] on ci, if there is one:
## the canvas `size` (world px) with the feet at `origin`, under whatever
## transform ci has set (facing, lean). Says whether it drew.
static func draw(ci: CanvasItem, who: String, pose: Array, size: Vector2, origin: Vector2, modulate := Color.WHITE) -> bool:
	var anims := frames(who)
	if not anims.has(pose[0]):
		return false
	var list: Array = anims[pose[0]]
	var i := clampi(int(pose[1]), 0, list.size() - 1)
	ci.draw_texture_rect(list[i], Rect2(-origin, size), false, modulate)
	return true
