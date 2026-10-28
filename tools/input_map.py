"""Writes the [input] section of project.godot: every action and the
keys, mouse buttons and gamepad controls bound to it.

Run from the repo root:  python3 tools/input_map.py
(You can also rebind in Godot: Project > Project Settings > Input Map.
Running this again overwrites those changes.)

Default layout, mouse and keyboard:
  A D walk, Space jump, Left-click strike, Right-click pistol (hold it
  when out of bullets for blood bullets), Shift quickstep, Q transform,
  F vial, E lamp, Esc pause.
No mouse: J strike, K pistol, L quickstep, I transform.
Gamepad: A jump, X/RB strike, LT/RT pistol, B quickstep, LB transform,
  Y vial, D-pad up lamp, Start pause.
"""
import re

KEY = {"a": 65, "d": 68, "w": 87, "s": 83, "space": 32, "j": 74, "k": 75, "l": 76, "i": 73, "q": 81,
       "shift": 4194325, "f": 70, "e": 69, "escape": 4194305, "p": 80, "enter": 4194309, "kp_enter": 4194310,
       "left": 4194319, "up": 4194320, "right": 4194321, "down": 4194322, "h": 72}
MOUSE = {"left": 1, "right": 2, "middle": 3, "wheel_up": 4, "wheel_down": 5}
# Godot's JoyButton numbering (SDL layout), not the browser's.
JOY = {"a": 0, "b": 1, "x": 2, "y": 3, "back": 4, "start": 6, "lb": 9, "rb": 10,
       "dup": 11, "ddown": 12, "dleft": 13, "dright": 14}


def key(k):
    return ('Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,'
            '"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,'
            f'"keycode":0,"physical_keycode":{KEY[k]},"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)')


def mouse(b):
    return ('Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,'
            '"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,'
            '"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,'
            f'"button_index":{MOUSE[b]},"canceled":false,"pressed":true,"double_click":false,"script":null)')


def btn(b):
    return ('Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,'
            f'"button_index":{JOY[b]},"pressure":0.0,"pressed":true,"script":null)')


def axis(a, v):
    return ('Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,'
            f'"axis":{a},"axis_value":{v},"script":null)')


ACTIONS = [
    ("move_left", 0.4, [key("a"), key("left"), btn("dleft"), axis(0, -1.0)]),
    ("move_right", 0.4, [key("d"), key("right"), btn("dright"), axis(0, 1.0)]),
    ("move_up", 0.6, [key("w"), key("up"), btn("dup"), axis(1, -1.0)]),
    ("move_down", 0.6, [key("s"), key("down"), btn("ddown"), axis(1, 1.0)]),
    ("jump", 0.5, [key("space"), btn("a")]),
    ("attack", 0.5, [mouse("left"), key("j"), btn("x"), btn("rb")]),
    ("shoot", 0.5, [mouse("right"), key("k"), axis(4, 1.0), axis(5, 1.0)]),
    ("dash", 0.5, [key("shift"), key("l"), btn("b")]),
    ("transform", 0.5, [key("q"), key("i"), mouse("middle"), mouse("wheel_up"), mouse("wheel_down"), btn("lb")]),
    ("heal", 0.5, [key("f"), btn("y")]),
    ("interact", 0.6, [key("e"), key("w"), key("up"), btn("dup")]),
    ("confirm", 0.5, [key("enter"), key("kp_enter"), key("space"), key("j"), btn("a")]),
    ("back", 0.5, [key("escape"), key("e"), btn("b")]),
    ("pause", 0.5, [key("escape"), key("p"), btn("start")]),
    ("toggle_hitboxes", 0.5, [key("h")]),
]


def section():
    out = []
    for name, dz, events in ACTIONS:
        out.append(f'{name}={{\n"deadzone": {dz},\n"events": [' + "\n, ".join(events) + "\n]\n}")
    return "[input]\n\n" + "\n".join(out) + "\n\n"


if __name__ == "__main__":
    text = open("project.godot").read()
    text = re.sub(r"\[input\]\n.*?(?=\n\[)", section().rstrip("\n") + "\n", text, flags=re.S)
    open("project.godot", "w").write(text)
    print(f"wrote {len(ACTIONS)} actions to project.godot")
