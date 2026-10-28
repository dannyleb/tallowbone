import { GAME_TITLE, STEP } from "./config.js";
import { consumePresses, NO_PRESSES, poll } from "./controls.js";
import { createGame, update } from "./game.js";
import { createRenderer } from "./render/index.js";
import { unlockAudio } from "./sfx.js";

document.title = GAME_TITLE;

const debug = new URLSearchParams(location.search).has("debug");
const canvas = document.getElementById("game");
const title = document.getElementById("title");
const pause = document.getElementById("pause");
const begin = document.getElementById("begin");
const resume = document.getElementById("resume");

const view = { hitboxes: debug };
const renderer = createRenderer(canvas, view);
const game = createGame();
let mode = "title"; // "title" | "play" | "pause"

function start() {
  unlockAudio();
  title.hidden = true;
  pause.hidden = true;
  mode = "play";
  consumePresses();
  canvas.focus();
}
function setPaused(on) {
  pause.hidden = !on;
  mode = on ? "pause" : "play";
  consumePresses();
  if (on) resume.focus();
}
begin.addEventListener("click", start);
resume.addEventListener("click", () => setPaused(false));
window.addEventListener("pointerdown", unlockAudio);
document.addEventListener("visibilitychange", () => { if (document.hidden && mode === "play") setPaused(true); });

// The world runs in fixed 1/60 s steps; the display draws whenever the
// browser asks. Presses are handed to the first step that runs.
let last = performance.now(), acc = 0;
function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  const input = poll();

  if (mode === "title" && input.pressed.confirm) start();
  else if (mode === "pause" && (input.pressed.pause || input.pressed.confirm)) setPaused(false);
  else if (mode === "play" && input.pressed.pause && !game.menu) setPaused(true);
  else if (mode === "play") {
    acc += dt;
    let first = true;
    while (acc >= STEP) {
      update(game, first ? input : { held: input.held, pressed: NO_PRESSES }, STEP);
      if (first) consumePresses();
      first = false;
      acc -= STEP;
    }
  }
  if (mode !== "play") { consumePresses(); acc = 0; }

  renderer.draw(game);
  requestAnimationFrame(frame);
}

// Canvas text needs the fonts in before the first frame.
Promise.all([
  document.fonts.load('16px "IM Fell English"'),
  document.fonts.load('16px "IM Fell English SC"'),
  document.fonts.load('16px "Cinzel"'),
]).catch(() => {}).finally(() => {
  begin.disabled = false;
  begin.textContent = "Begin the night";
  requestAnimationFrame(frame);
});

if (debug) {
  window.tallowbone = { game, start, view };
  window.addEventListener("keydown", (e) => { if (e.key === "h") view.hitboxes = !view.hitboxes; });
}
