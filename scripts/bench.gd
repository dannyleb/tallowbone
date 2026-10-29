## Frame-time benchmark for the web build. Open the game with ?bench in the
## address (or run with `-- --bench`): it starts the night, visits a few
## spots, and times frames with everything on, then with each system
## switched off in turn, so the cost of each shows. Results go on screen,
## to the console (lines starting BENCH), and, on the web, as JSON to
## POST /bench on the page's own server (tools/bench_web.py collects them
## in CI). ?bench=quick skips switching systems off.
extends Node

## Where to stand: a lamp-lit street with figures, the canal (water), the
## undercroft (lamp, enemies, back wall).
const SPOTS := [["street", Vector2(400, 640)], ["canal", Vector2(1000, 640)], ["undercroft", Vector2(3150, 896)]]
## Systems switched off, one at a time, then all at once ("everything":
## what's left is the level and the engine). The flat 2D look (?2d) has
## SYSTEMS; the 3D stage has STAGE_SYSTEMS.
const SYSTEMS := ["figures", "lights", "normals", "water", "weather", "backdrop", "fx", "hud"]
const STAGE_SYSTEMS := ["shadows", "fog", "reflections", "bounce", "glow", "rain", "far city", "city", "foreground", "clutter", "water light", "plane", "fx", "hud"]
## Then everything on again, with the game view drawn at these render
## scales (render px per world px; those below the starting scale only).
const SCALES := [2.0, 1.5, 1.0]
## Wall-clock seconds measured per spot, and the frame count bounds.
const MEASURE := 1.5
const MIN_FRAMES := 5
const MAX_SECONDS := 6.0
## A frame this long (ms) counts as a hitch.
const HITCH_MS := 50.0
## The longest it waits on the title for the shaders to finish (s).
const SETTLE_MAX := 60.0

var main
var world
var player
var quick := false

var _last := 0
var _frame_ms := PackedFloat32Array()
var _process_ms := 0.0
var _physics_ms := 0.0
var _draw_calls := 0.0
var _saved_textures := []
var _label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.add_theme_font_size_override("font_size", 7)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 3)
	main.get_node("UiLayer").add_child(_label)
	_run.call_deferred()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last > 0:
		_frame_ms.append((now - _last) / 1000.0)
		_process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_last = now


func _run() -> void:
	world = main.world
	player = world.player
	_status("Benchmark: starting")
	var info := {
		"adapter": "%s / %s, %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()],
		"window": str(DisplayServer.window_get_size()),
		"render": "%dx%d (%.1fx)" % [main.game.size.x, main.game.size.y, main.render_scale],
		"view": str(world.view_size()),
		"agent": _agent(),
	}
	# Title screen first: the world draws behind it, and the shaders compile
	# (the stage's prewarm). Wait for that, as a player reading it would.
	var settled := await _settle()
	var title := await _measure(1.0)
	title.settled_s = settled
	main.start_game()
	world.teaching = false
	player.unlock_all()

	# First visit to each spot: hitches here are shaders compiling.
	var first := []
	for spot in SPOTS:
		_put(spot[1])
		var m := await _measure(1.0)
		m.spot = spot[0]
		first.append(m)
		_status("Benchmark: first visit to %s, worst frame %.0f ms" % [spot[0], m.max_ms])

	# Once round the spots with everything on, unmeasured: what the first
	# visits left compiling (shadow passes, probes) finishes here, not in
	# the first row.
	for spot in SPOTS:
		_put(spot[1])
		await _measure(1.0)

	var rows := []
	var configs: Array = [[]]
	if not quick:
		for s in _systems():
			configs.append([s])
		configs.append(["everything"])
	for off in configs:
		var name: String = "everything on" if off.is_empty() else "no " + ", ".join(PackedStringArray(off))
		_switch(off, true)
		var spots := []
		for spot in SPOTS:
			_put(spot[1])
			await _frames(_warmup())
			var m := await _measure(MEASURE)
			m.spot = spot[0]
			spots.append(m)
			_status("Benchmark: %s at %s: %.1f ms (%.0f fps)" % [name, spot[0], m.avg_ms, m.fps])
		_switch(off, false)
		rows.append({"config": name, "spots": spots})

	var start_scale: float = main.render_scale
	for scale in SCALES:
		if scale >= start_scale - 0.01:
			continue
		main.fixed_scale = scale
		main.fit_view()
		var name := "drawn at %.1fx" % scale
		var spots := []
		for spot in SPOTS:
			_put(spot[1])
			await _frames(_warmup())
			var m := await _measure(MEASURE)
			m.spot = spot[0]
			spots.append(m)
			_status("Benchmark: %s at %s: %.1f ms (%.0f fps)" % [name, spot[0], m.avg_ms, m.fps])
		rows.append({"config": "%s (%dx%d)" % [name, main.game.size.x, main.game.size.y], "spots": spots})
	main.fixed_scale = 0.0
	main.fit_view()

	var result := {"info": info, "title": title, "first_visit": first, "rows": rows}
	var text := _summary(result)
	result.summary = text
	_label.text = text
	print("BENCH ", JSON.stringify(result))
	for line in text.split("\n"):
		print("BENCH | ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("fetch('/bench', {method: 'POST', body: %s}).catch(() => {})" % JSON.stringify(JSON.stringify(result)))
	elif OS.get_cmdline_user_args().has("--bench-quit"):
		# CI's desktop run: done.
		get_tree().quit()


## Frames to settle before measuring (fog and reflections build up over a
## few); fewer on the desktop, whose CI run draws on the CPU.
func _warmup() -> int:
	return 10 if OS.has_feature("web") else 4


func _status(text: String) -> void:
	_label.text = text
	print("BENCH | ", text)


func _agent() -> String:
	if OS.has_feature("web"):
		var a = JavaScriptBridge.eval("navigator.userAgent + ' / dpr ' + window.devicePixelRatio", true)
		return str(a)
	return OS.get_name()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Stand somewhere, safe, with the camera on you.
func _put(at: Vector2) -> void:
	if get_tree().paused:
		main.set_paused(false)
	player.position = at
	player.velocity = Vector2.ZERO
	player.to_move()
	player.iframes = 1e9
	world.snap_camera()


## Times frames for `seconds` of wall-clock time (at least MIN_FRAMES).
## Waits until frames come steadily (8 in a row, none over twice the
## quickest), up to SETTLE_MAX seconds; returns how long that took.
func _settle() -> float:
	var start := Time.get_ticks_usec()
	var last := start
	var recent: Array[float] = []
	while (Time.get_ticks_usec() - start) / 1e6 < SETTLE_MAX:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		recent.append((now - last) / 1000.0)
		last = now
		if recent.size() > 8:
			recent.pop_front()
		if recent.size() == 8 and recent.max() <= recent.min() * 2.0:
			break
	return (Time.get_ticks_usec() - start) / 1e6


func _measure(seconds: float) -> Dictionary:
	await get_tree().process_frame
	_frame_ms = PackedFloat32Array()
	_process_ms = 0.0
	_physics_ms = 0.0
	_draw_calls = 0.0
	var start := Time.get_ticks_usec()
	while true:
		await get_tree().process_frame
		var elapsed := (Time.get_ticks_usec() - start) / 1e6
		if (elapsed >= seconds and _frame_ms.size() >= MIN_FRAMES) or elapsed >= MAX_SECONDS:
			break
	var n := maxi(1, _frame_ms.size())
	var total := 0.0
	var worst := 0.0
	var hitches := 0
	for ms in _frame_ms:
		total += ms
		worst = maxf(worst, ms)
		if ms > HITCH_MS:
			hitches += 1
	var avg := total / n
	return {"frames": _frame_ms.size(), "avg_ms": avg, "fps": 1000.0 / maxf(avg, 0.001), "max_ms": worst, "hitches": hitches,
		"process_ms": _process_ms / n, "physics_ms": _physics_ms / n, "draw_calls": _draw_calls / n}


func _systems() -> Array:
	return STAGE_SYSTEMS if main.stage else SYSTEMS


func _switch(off: Array, now_off: bool) -> void:
	var systems: Array = _systems() if off.has("everything") else off
	for s in systems:
		_switch_system(s, now_off)


func _switch_system(system: String, off: bool) -> void:
	if main.stage and system in ["shadows", "fog", "reflections", "bounce", "glow", "rain", "far city", "city", "foreground", "clutter", "water light", "plane"]:
		main.stage.set_feature(system, not off)
		return
	match system:
		"figures":
			for a in [player] + world.enemies:
				a._fig.set_active(not off)
		"lights":
			for l in world.find_children("*", "Light2D", true, false):
				l.visible = not off
		"normals":
			# The tiles' bump and gloss maps.
			var tex: CanvasTexture = world.level.ground.tile_set.get_source(0).texture
			if off:
				_saved_textures = [tex.normal_texture, tex.specular_texture]
				tex.normal_texture = null
				tex.specular_texture = null
			elif not _saved_textures.is_empty():
				tex.normal_texture = _saved_textures[0]
				tex.specular_texture = _saved_textures[1]
		"water":
			world.level.get_node("Water").visible = not off
		"weather":
			world.get_node("Weather").visible = not off
		"backdrop":
			main.get_node("View/Game/BackdropLayer").visible = not off
		"fx":
			for n in ["FxShaded", "FxOverlay", "FxGlow"]:
				world.get_node(n).visible = not off
		"hud":
			main.get_node("HudLayer").visible = not off


func _summary(r: Dictionary) -> String:
	var lines := PackedStringArray(["BENCHMARK  %s" % r.info.agent, "%s   window %s   view %s   world drawn at %s" % [r.info.adapter, r.info.window, r.info.view, r.info.render]])
	lines.append("title screen: %.1f ms, steady after %.1f s (shaders compiling behind it)" % [r.title.avg_ms, r.title.get("settled_s", 0.0)])
	var first := PackedStringArray()
	for m in r.first_visit:
		first.append("%s worst %.0f ms (%d hitches)" % [m.spot, m.max_ms, m.hitches])
	lines.append("first visits: " + ", ".join(first))
	lines.append("")
	lines.append("%-32s %8s %8s %8s %8s %8s" % ["config", "avg ms", "fps", "worst", "script", "physics"])
	var base := -1.0
	for row in r.rows:
		var avg := 0.0
		var worst := 0.0
		var script := 0.0
		var physics := 0.0
		for m in row.spots:
			avg += m.avg_ms / row.spots.size()
			worst = maxf(worst, m.max_ms)
			script += m.process_ms / row.spots.size()
			physics += m.physics_ms / row.spots.size()
		if base < 0.0:
			base = avg
		var saved := "" if row.config == "everything on" else "   saves %.1f ms" % (base - avg)
		lines.append("%-32s %8.1f %8.0f %8.0f %8.1f %8.1f%s" % [row.config, avg, 1000.0 / maxf(avg, 0.001), worst, script, physics, saved])
	return "\n".join(lines)
