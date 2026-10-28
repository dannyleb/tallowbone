## What to call each button, for whatever the player is holding.
##
## The device is whichever was touched last: mouse and keyboard, or a
## gamepad. Signs and prompts write actions as tokens, like "{attack} to
## strike", and fill() swaps in the right name.
extends RefCounted

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


static func label(action: String) -> String:
	return NAMES[device].get(action, action)


## "{attack} to strike" -> "Left-click to strike" (or "X to strike").
static func fill(text: String) -> String:
	var out := text
	for action in NAMES[device]:
		out = out.replace("{%s}" % action, NAMES[device][action])
	return out
