## Keyboard bindings you can change (the pause menu's Controls panel), kept
## in user://controls.cfg; and Ctrl-click as the pistol, for trackpads with
## no right-click (the Mac's own convention).
##
## Rebinding an action replaces its keyboard keys with the one you press;
## its mouse buttons and gamepad controls stay. A key taken from another
## action is swapped onto it, so no key does two things.
extends RefCounted

const FILE := "user://controls.cfg"

## What you can rebind, in the order the panel lists them: [action, name].
const REBINDABLE := [
	["attack", "Strike"], ["shoot", "Pistol"], ["jump", "Jump"], ["dash", "Quickstep"],
	["transform", "Turn the Pole"], ["heal", "Vial"], ["interact", "Lamps and gates"],
	["move_left", "Walk left"], ["move_right", "Walk right"], ["move_down", "Down"],
]


## The keyboard keys bound to an action (physical keycodes), in order.
static func keys(action: String) -> Array[int]:
	var out: Array[int] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			out.append(int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode))
	return out


## The name of a key as printed on it ("J", "Space", "Shift"): on desktops,
## as the keyboard's layout labels it; elsewhere (the web, headless runs,
## which can't ask), by its US position.
static func key_name(physical: int) -> String:
	var shown := KEY_NONE
	if _can_map_layout():
		shown = DisplayServer.keyboard_get_keycode_from_physical(physical as Key)
	return OS.get_keycode_string(shown if shown != KEY_NONE else physical as Key)


static func _can_map_layout() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return OS.has_feature("macos") or OS.has_feature("windows") or OS.has_feature("linuxbsd")


## Binds `physical` as the action's only keyboard key (see the header).
static func rebind(action: String, physical: int) -> void:
	var old := keys(action)
	for other in REBINDABLE:
		var name: String = other[0]
		if name != action and keys(name).has(physical):
			_set_key(name, old[0] if not old.is_empty() else KEY_NONE)
	_set_key(action, physical)


static func _set_key(action: String, physical: int) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	if physical != KEY_NONE:
		var ev := InputEventKey.new()
		ev.physical_keycode = physical as Key
		InputMap.action_add_event(action, ev)


## Writes the current keyboard bindings.
static func save() -> void:
	var cfg := ConfigFile.new()
	for entry in REBINDABLE:
		var k := keys(entry[0])
		if not k.is_empty():
			cfg.set_value("keys", entry[0], k[0])
	cfg.save(FILE)


## Applies saved bindings, if there are any.
static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(FILE) != OK:
		return
	for entry in REBINDABLE:
		var action: String = entry[0]
		if cfg.has_section_key("keys", action):
			_set_key(action, int(cfg.get_value("keys", action)))


## Back to the project's bindings, and forgets the saved ones.
static func reset() -> void:
	InputMap.load_from_project_settings()
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(FILE)


## Ctrl held with the left button down: the pistol, not a strike.
static func ctrl_click() -> bool:
	return Input.is_key_pressed(KEY_CTRL) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## Is one of the action's keyboard keys down?
static func key_held(action: String) -> bool:
	for k in keys(action):
		if Input.is_physical_key_pressed(k as Key):
			return true
	return false
