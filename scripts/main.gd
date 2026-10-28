## The root of the game: the title screen, pause, and wiring the World to
## the backdrop and HUD that draw it.
extends Node

const FELL := preload("res://assets/fonts/IMFellEnglish-Regular.ttf")
const FELL_ITALIC := preload("res://assets/fonts/IMFellEnglish-Italic.ttf")
const FELL_SC := preload("res://assets/fonts/IMFellEnglishSC-Regular.ttf")
const Glow = preload("res://scripts/glow.gd")
const Keys = preload("res://scripts/keys.gd")
const MapView = preload("res://scripts/map_view.gd")

const INK := Color("07080d")
const BONE := Color("e8dfcf")
const BONE_DIM := Color(0.91, 0.87, 0.81, 0.6)
const TALLOW := Color("f0bd62")
const LAMP := Color("ffcf7a")

## The title screen shows only what you need to start; everything else is
## found on the way, and each find shows its own key.
const KEYBOARD := [
	["A  D", "walk"], ["Space", "jump"], ["Left-click", "strike"],
	["E", "light lamps, open gates"], ["Esc", "pause and map"],
]
const GAMEPAD := [
	["Left stick", "walk"], ["A", "jump"], ["X", "strike"],
	["D-pad ↑", "lamps and gates"], ["Start", "pause and map"],
]

var title: Control
var pause_screen: Control
var _begin: Button
var _resume: Button
var _map: Control
var _keys: Label
var _debug_allowed := false

@onready var world = $World


func _ready() -> void:
	$HudLayer/Hud.world = world
	$BackdropLayer/Backdrop.world = world
	var web_debug := _web_debug()
	_debug_allowed = OS.is_debug_build() or web_debug
	world.show_hitboxes = web_debug
	title = _build_title()
	pause_screen = _build_pause()
	$UiLayer.add_child(title)
	$UiLayer.add_child(pause_screen)
	pause_screen.visible = false
	_begin.grab_focus()


func start_game() -> void:
	if world.running:
		return
	world.running = true
	title.visible = false


func set_paused(on: bool) -> void:
	get_tree().paused = on
	pause_screen.visible = on
	if on:
		_keys.text = _keys_text()
		_map.queue_redraw()
		_resume.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hitboxes") and _debug_allowed:
		world.show_hitboxes = not world.show_hitboxes
	if not world.running:
		if event.is_action_pressed("confirm"):
			start_game()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if get_tree().paused:
			set_paused(false)
		elif world.menu.is_empty():
			set_paused(true)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and world and world.running and not get_tree().paused:
		set_paused(true)


## ?debug in the page address shows hitboxes on the web build.
func _web_debug() -> bool:
	if not OS.has_feature("web"):
		return false
	var q = JavaScriptBridge.eval("window.location.search", true)
	return q is String and q.contains("debug")


# --- Screens ------------------------------------------------------------

func _label(text: String, font: Font, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", FELL_SC)
	b.add_theme_font_size_override("font_size", 12)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state, INK)
	for state in ["normal", "hover", "focus", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = LAMP if state != "normal" else TALLOW
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		b.add_theme_stylebox_override(state, s)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


## A full-screen dimmer with a framed card in the middle; returns
## [screen, the card's VBox].
func _card(width: float) -> Array:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.024, 0.04, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.047, 0.8)
	style.border_color = Color(0.91, 0.87, 0.81, 0.18)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	return [screen, box]


func _build_title() -> Control:
	var parts := _card(340.0)
	var box: VBoxContainer = parts[1]
	var flame := TextureRect.new()
	flame.texture = Glow.texture()
	flame.custom_minimum_size = Vector2(16, 20)
	flame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flame.stretch_mode = TextureRect.STRETCH_SCALE
	flame.modulate = TALLOW
	flame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(flame)
	box.add_child(_label("Tallowbone", FELL_SC, 34, BONE))
	box.add_child(_label("The church's lamps hold back the dark. Nobody asks what they burn.", FELL_ITALIC, 9, BONE_DIM))
	box.add_child(_label("The Canal District  ·  first playable slice", FELL_SC, 9, TALLOW))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(_controls("Mouse & keyboard", KEYBOARD, "No mouse? J strikes."))
	columns.add_child(_controls("Gamepad", GAMEPAD, ""))
	box.add_child(columns)

	_begin = _button("Begin the night")
	_begin.pressed.connect(start_game)
	box.add_child(_begin)
	box.add_child(_label("Everything else you'll find along the way.", FELL_ITALIC, 9, BONE_DIM))
	box.add_child(_label("Greybox: shapes stand in for the art.", FELL, 7, Color(0.91, 0.87, 0.81, 0.45)))
	return parts[0]


func _controls(heading: String, rows: Array, footnote: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.add_child(_label(heading, FELL_SC, 10, LAMP, HORIZONTAL_ALIGNMENT_LEFT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 0)
	for row in rows:
		grid.add_child(_label(row[0], FELL_SC, 8, BONE, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(_label(row[1], FELL, 8, BONE_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	col.add_child(grid)
	if footnote != "":
		col.add_child(_label(footnote, FELL_ITALIC, 7, BONE_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	return col


func _build_pause() -> Control:
	var parts := _card(600.0)
	var box: VBoxContainer = parts[1]
	box.add_child(_label(world.level.level_name, FELL_SC, 18, BONE))
	_map = MapView.new()
	_map.world = world
	_map.custom_minimum_size = Vector2(580, 130)
	box.add_child(_map)
	var legend := HBoxContainer.new()
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 10)
	for item in [[MapView.LAMP, "lamp"], [MapView.GATE, "barred gate"], [MapView.FIND, "something you've seen"],
			[MapView.TALLOW, "your tallow"], [MapView.GORGED, "Gorged"], [MapView.YOU, "you"]]:
		var swatch := ColorRect.new()
		swatch.color = item[0]
		swatch.custom_minimum_size = Vector2(5, 5)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(swatch)
		legend.add_child(_label(item[1], FELL, 8, BONE_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(legend)
	_keys = _label("", FELL, 8, BONE_DIM)
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_keys)
	_resume = _button("Resume")
	_resume.pressed.connect(func(): set_paused(false))
	box.add_child(_resume)
	return parts[0]


## The keys you have now, for the pause screen.
func _keys_text() -> String:
	var p = world.player
	var parts := ["{move} walk", "{jump} jump", "{attack} strike"]
	if p.has("lantern"):
		parts.append("hold {attack} to turn the Pole")
	if p.has("pistol"):
		parts.append("{shoot} pistol (hold when empty for blood)")
	if p.has("quickstep"):
		parts.append("{dash} quickstep")
	parts.append("{heal} vial")
	if p.has("irons"):
		parts.append("press into a wall to cling, {jump} to kick off")
	parts.append("{interact} lamps and gates")
	return Keys.fill("   ·   ".join(parts))
