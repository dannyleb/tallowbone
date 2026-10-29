## What to call each button, for whatever the player is holding.
##
## The device is whichever was touched last: mouse and keyboard, or a
## gamepad. Signs and prompts write actions as tokens, like "{attack} to
## strike", and fill() swaps in the right name.
extends RefCounted

const Controls = preload("res://scripts/controls.gd")

const NAMES := {
	"keyboard": {
		"move": "A / D", "jump": "Space", "attack": "Left-click", "shoot": "Right-click",
		"dash": "Shift", "transform": "Q", "heal": "F", "interact": "E",
		"confirm": "Enter", "back": "Esc", "down": "S",
	},
	"gamepad": {
		"move": "Left stick", "jump": "A", "attack": "X", "shoot": "LT",
		"dash": "B", "transform": "LB", "heal": "Y", "interact": "D-pad ↑",
		"confirm": "A", "back": "B", "down": "Down",
	},
}

static var device := "keyboard"


## Call with every input event (the HUD does).
static func notice(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		device = "gamepad"
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		device = "gamepad"
	elif event is InputEventKey or event is InputEventMouseButton:
		device = "keyboard"


## On the keyboard, names come from the live bindings (so rebinding shows
## up everywhere): the mouse button if there is one, then the key,
## "Left-click / J".
static func label(action: String) -> String:
	if device == "keyboard":
		var live := _keyboard(action)
		if live != "":
			return live
	return NAMES[device].get(action, action)


static func _keyboard(action: String) -> String:
	match action:
		"move":
			return "%s / %s" % [_key("move_left"), _key("move_right")]
		"down":
			return _key("move_down")
	var mouse := ""
	for ev in InputMap.action_get_events(action) if InputMap.has_action(action) else []:
		if ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					mouse = "Left-click"
				MOUSE_BUTTON_RIGHT:
					mouse = "Right-click"
			if mouse != "":
				break
	var key := _key(action)
	if mouse != "" and key != "":
		return "%s / %s" % [mouse, key]
	return mouse if mouse != "" else key


static func _key(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	var k := Controls.keys(action)
	return Controls.key_name(k[0]) if not k.is_empty() else ""


## "{attack} to strike" -> "Left-click / J to strike" (or "X to strike").
static func fill(text: String) -> String:
	var out := text
	for action in NAMES[device]:
		out = out.replace("{%s}" % action, label(action))
	return out
