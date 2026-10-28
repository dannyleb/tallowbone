## Renders the paint-over templates for the character art (docs/ART.md):
## every frame of every painted animation, posed from the greybox at the
## middle of the moment it covers, at Art.SCALE px per world px, facing
## right, with the feet line, the centre line and the body box marked; and
## a contact sheet per character (both forms of the Lamplighter apart).
## CI runs it on a virtual display and publishes the result:
##   godot --path . --rendering-method gl_compatibility \
##     --script res://tests/art_templates.gd -- <out dir> 2d
extends SceneTree

const Art = preload("res://scripts/art.gd")
const Player = preload("res://scripts/player.gd")
const Enemy = preload("res://scripts/enemy.gd")

## Guides: the feet line and body box, the centre line, the canvas edge.
const FEET := Color(0.2, 0.9, 1.0, 0.9)
const BODY := Color(0.2, 0.9, 1.0, 0.45)
const CENTRE := Color(0.2, 0.9, 1.0, 0.3)
const EDGE := Color(1.0, 1.0, 1.0, 0.25)

var out_dir := "ci-out/art-templates"
var main


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	# Templates are always posed from the greybox, whatever art exists.
	Art.use_root("res://nothing-painted")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for i in 3:
		await process_frame
	var world = main.world
	world.running = false
	var cast := [["lamplighter", world.player, Player.art_anims(), Player.FIG_SIZE, Player.FIG_ORIGIN]]
	for kind in ["communicant", "hound"]:
		for e in world.enemies:
			if e.kind == kind:
				cast.append([kind, e, Enemy.ART_ANIMS, Enemy.FIGS[kind][0], Enemy.FIGS[kind][1]])
				break
	var total := 0
	for c in cast:
		total += await _render(c[0], c[1], c[2], c[3], c[4])
	print("art templates: %d frames written to %s" % [total, out_dir])
	quit(0)


## Renders every frame of `who`, then its contact sheet(s). Returns the
## number of frames.
func _render(who: String, actor, anims: Dictionary, size: Vector2, origin: Vector2) -> int:
	var px := Vector2i(size * Art.SCALE)
	var vp := SubViewport.new()
	vp.size = px
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var painter := Node2D.new()
	painter.position = origin * Art.SCALE
	painter.scale = Vector2(Art.SCALE, Art.SCALE)
	painter.draw.connect(func(): actor._paint(painter))
	vp.add_child(painter)
	var label := {"text": ""}
	var guides := Node2D.new()
	guides.draw.connect(func(): _guides(guides, actor, size, origin, label.text))
	vp.add_child(guides)

	var names: Array = anims.keys()
	names.sort()
	var done := {}
	var count := 0
	for anim in names:
		var frames: Array = []
		for f in int(anims[anim]):
			actor.art_pose(anim, f)
			label.text = "%s  %s  frame %d of %d" % [who, anim, f + 1, anims[anim]]
			painter.queue_redraw()
			guides.queue_redraw()
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			var dir := "%s/%s/%s" % [out_dir, who, anim]
			DirAccess.make_dir_recursive_absolute(dir)
			img.save_png("%s/%02d.png" % [dir, f + 1])
			frames.append(img)
			count += 1
		done[anim] = frames
	vp.queue_free()

	# Contact sheets: one row per animation. The Lamplighter gets one per form.
	var groups := {}
	for anim in names:
		var group := who
		if who == "lamplighter":
			group = "lamplighter-" + String(anim).get_slice("_", 0)
		if not groups.has(group):
			groups[group] = []
		groups[group].append(anim)
	for group in groups:
		await _sheet(group, groups[group], done, px)
	return count


func _guides(ci: Node2D, actor, size: Vector2, origin: Vector2, text: String) -> void:
	var s := Art.SCALE
	var feet := origin * s
	ci.draw_rect(Rect2(Vector2.ZERO, size * s), EDGE, false, 1.0)
	ci.draw_line(Vector2(0, feet.y), Vector2(size.x * s, feet.y), FEET, 2.0)
	ci.draw_line(Vector2(feet.x, 0), Vector2(feet.x, size.y * s), CENTRE, 1.0)
	var body: Rect2 = actor.body_rect()
	body.position -= actor.position
	ci.draw_rect(Rect2(feet + body.position * s, body.size * s), BODY, false, 2.0)
	ci.draw_string(ThemeDB.fallback_font, Vector2(8, 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))


## Every frame of the animations in one image, half size, a row each.
func _sheet(name: String, anims: Array, done: Dictionary, px: Vector2i) -> void:
	var cell := px / 2
	var cols := 1
	for anim in anims:
		cols = maxi(cols, done[anim].size())
	var size := Vector2i(cols * cell.x, anims.size() * (cell.y + 22))
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp)
	var canvas := Node2D.new()
	var textures := {}
	for anim in anims:
		textures[anim] = done[anim].map(func(img): return ImageTexture.create_from_image(img))
	canvas.draw.connect(func():
		canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(size)), Color(0.08, 0.08, 0.1))
		var y := 0
		for anim in anims:
			canvas.draw_string(ThemeDB.fallback_font, Vector2(6, y + 16), anim, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.85, 0.6))
			var x := 0
			for tex in textures[anim]:
				canvas.draw_texture_rect(tex, Rect2(x, y + 22, cell.x, cell.y), false)
				x += cell.x
			y += cell.y + 22
	)
	vp.add_child(canvas)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s/%s-sheet.png" % [out_dir, name])
	vp.queue_free()
