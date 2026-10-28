// Keyboard and gamepad, merged into one poll(): which actions are held
// right now, plus which were pressed since the last simulation step
// (presses are kept until a step consumes them, so a tap between two
// frames on a fast display is never lost).
//
// Keyboard: two layouts at once, so either hand position works.
//   WASD + Space / J K L          Arrows + Z / X C V
// Gamepad (standard mapping): A jump, X attack, B quickstep, LB transform,
// LT shoot, Y vial, Select (hold) blood bullets, D-pad up interact.
const KEYS = {
  left: ["a", "arrowleft"],
  right: ["d", "arrowright"],
  up: ["w", "arrowup"],
  down: ["s", "arrowdown"],
  jump: [" ", "z"],
  attack: ["j", "x"],
  transform: ["k", "c"],
  shoot: ["l", "v"],
  dash: ["shift"],
  heal: ["f"],
  blood: ["r"],
  interact: ["e", "w", "arrowup"],
  confirm: ["enter", " ", "j", "x"],
  back: ["escape", "e", "shift"],
  pause: ["escape", "p"],
};

const PAD = {
  jump: [0], dash: [1], attack: [2, 5], heal: [3], transform: [4], shoot: [6, 7],
  blood: [8], pause: [9], up: [12], down: [13], left: [14], right: [15],
  interact: [12], confirm: [0], back: [1],
};

const ACTIONS = Object.keys(KEYS);
const keys = new Set();
const pressed = new Set();
let padPrev = {};
export let lastDevice = "keyboard";

const GAME_KEYS = new Set(Object.values(KEYS).flat());

window.addEventListener("keydown", (e) => {
  const k = e.key.toLowerCase();
  if (GAME_KEYS.has(k) && !(e.target instanceof HTMLButtonElement)) e.preventDefault();
  if (!keys.has(k)) for (const a of ACTIONS) if (KEYS[a].includes(k)) pressed.add(a);
  keys.add(k);
  lastDevice = "keyboard";
});
window.addEventListener("keyup", (e) => keys.delete(e.key.toLowerCase()));
window.addEventListener("blur", () => keys.clear());

function padState() {
  const held = {};
  for (const pad of navigator.getGamepads ? navigator.getGamepads() : []) {
    if (!pad) continue;
    for (const a in PAD) if (PAD[a].some((i) => pad.buttons[i]?.pressed)) held[a] = true;
    const [ax = 0, ay = 0] = pad.axes;
    if (ax < -0.4) held.left = true;
    if (ax > 0.4) held.right = true;
    if (ay < -0.6) held.up = held.interact = true;
    if (ay > 0.6) held.down = true;
  }
  return held;
}

export function poll() {
  const pad = padState();
  for (const a in pad) if (!padPrev[a]) { pressed.add(a); lastDevice = "gamepad"; }
  padPrev = pad;

  const held = {};
  for (const a of ACTIONS) held[a] = !!pad[a] || KEYS[a].some((k) => keys.has(k));
  const was = {};
  for (const a of ACTIONS) was[a] = pressed.has(a);
  return { held, pressed: was };
}

// Called once a simulation step has seen this frame's presses.
export function consumePresses() {
  pressed.clear();
}

export const NO_PRESSES = Object.fromEntries(ACTIONS.map((a) => [a, false]));
