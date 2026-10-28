# Tallowbone

A gothic 2D Metroidvania with a soulslike core, made in **Godot 4.7**. You
are a Lamplighter in a canal city in 1850s upstate New York, on the night a
séance went wrong. The church's lamps hold back the dark. Nobody asks what
they burn.

**Play in the browser:** https://dannyleb.github.io/tallowbone/ (deploys
from `main`).
**Mac app:** every push to `main` builds one (universal: Apple Silicon and
Intel). Open the latest green run under
[Actions](https://github.com/dannyleb/tallowbone/actions), download
**Tallowbone-mac** under Artifacts, unzip it twice and drag Tallowbone into
Applications. It isn't notarized by Apple yet, so macOS blocks the first
open: System Settings > Privacy & Security, scroll down, **Open Anyway**.
**Design:** [docs/DESIGN.md](docs/DESIGN.md).

The current build is the **first playable slice** (greybox: shapes stand in
for the art). It covers the Canal District with the full core loop:
- combat: Lamplighter's Pole (Hook and Lantern forms), trick attacks, the
  gun parry and Visceral attacks, Rally, blood bullets
- lamps and levelling
- Tallow drops and Gorged enemies
- exploration: abilities found along the way (quickstep, pistol, Lantern,
  Climbing Irons), shortcut gates, a pause-screen map

## Open it in Godot

1. Install **Godot 4.7** (the standard build, not .NET) from
   https://godotengine.org/download.
2. Clone this repo, open Godot, choose **Import**, and pick `project.godot`.
3. Press **F5** to play. The first import takes a minute, and Godot adds
   `.import` files next to the fonts, sounds and tiles: commit those (the
   `.godot/` folder it also makes is ignored).

Where things are:
- **The level:** `scenes/levels/canal_district.tscn`. Paint tiles on the
  `Ground` and `BackWall` layers. Drag lamps, signs, pickups, gates and enemies
  around under `Entities`, or drop in new ones from `scenes/props` and
  `scenes/actors`.
- **Tuning:** every number (speeds, damage, attack timings, costs) is in
  `scripts/tuning.gd`.
- **Hitboxes:** press **H** while playing from the editor. On the web build,
  add `?debug` to the address.
- **Performance:** press **F3** (or add `?perf` to the address) for fps and the render size,
  `?scale=1.5` to fix how sharp the world is drawn (it otherwise starts at
  up to 3x and steps down when frames run slow), or `?bench` to run the
  frame-time benchmark and get a table of what each system costs.

## Controls

You start with five keys; the rest come from things you find, and each
find's banner names its key. **Esc** shows the map and the keys you have.

| Action | Mouse & keyboard | No mouse | Gamepad | From |
|---|---|---|---|---|
| Walk | A D | A D (or arrows) | Left stick / D-pad | start |
| Jump (S + jump drops through walkways) | Space | Space | A | start |
| Strike (hold: turn the Pole, a trick attack) | Left-click | J | X / RB | start |
| Light / rest at a lamp, lift a gate's bar | E or W | E or W | D-pad up | start |
| Pause and map | Esc | Esc | Start | start |
| Vial | F | F | Y | start |
| Quickstep | Shift | L | B | Watchman's Boots |
| Pistol (shoot as an enemy glints to parry; hold when empty for blood bullets) | Right-click | K | LT / RT | Watch Pistol |
| Transform key (same as holding strike) | Q or mouse wheel | I | LB | Lamp Oil |
| Wall jump (press into a wall to cling) | Space | Space | A | Climbing Irons |

Signs and prompts show the keys for whatever you're holding. The first
parry and the first Visceral are taught in the moment (time slows, a prompt
says what to press). Rebind in **Project → Project Settings → Input Map**,
or edit `tools/input_map.py` and run it.

## How it's built and tested

Every push runs [the CI workflow](.github/workflows/godot.yml) on GitHub
Actions with Godot 4.7.2:
1. **Import** the project.
2. **Playtest:** `tests/playtest.gd` plays through every mechanic headless
   with simulated input and checks the results (movement, ledge assist,
   the canal hops, finds unlocking abilities, lamps, melee, parry →
   Visceral, Rally, blood bullets, vials, quickstep, the veil, shortcut
   gates, the chimney wall-jump climb, the map, death → Tallow pile →
   Gorged → reclaim, levelling).
3. **Screenshots:** `tests/screenshots.gd` renders key moments.
4. **Export** the web build and the Mac app (kept two weeks as a run
   artifact).
5. **Deploy** to GitHub Pages (pushes to `main` only).
6. **Benchmark:** `tools/bench_web.py` runs the build's `?bench` in Firefox
   and Chrome on a virtual display (drawn by the CPU, so compare the rows,
   not the speed).

Logs, screenshots and the benchmark (`bench/bench.md`) for the latest push
land on the `ci-reports` branch.

## Layout

```
project.godot        settings, input map
scenes/
  main.tscn          title, pause, HUD; the World and backdrop in their own
                     viewport (View/Game), drawn at the render scale
  world.tscn         the night: level, player, effects, camera
  levels/            levels (TileMapLayers + placed entities)
  actors/            player, Communicant, Hound
  props/             lamp, sign, pickup, gate
scripts/
  tuning.gd          every gameplay number
  world.gd           game state: Tallow, lamps, levelling, death, camera
  player.gd          the Lamplighter's state machine and look
  enemy.gd           enemy AI and look (one script, per-type numbers)
  combat.gd          damage, Rally, parries, deaths
  tallow.gd          Tallow drop, pickup, Gorged enemies
  level.gd           tile queries, veil burning
  hud.gd, main.gd    HUD, title/pause screens, lesson prompts
  map_view.gd        the pause-screen map (what you've explored)
  bench.gd           ?bench: the frame-time benchmark
  keys.gd            key names for the device in use ({attack} -> Left-click)
  figure.gd          paints an actor into a SubViewport, shown lit and rounded
  backdrop.gd        sky, moon, parallax skyline, fog
  weather.gd         rain, splashes, ground mist
  fx_layer.gd        particles, glints, glows, debug hitboxes
shaders/
  volume.gdshader    rounds flat drawings under 2D lights (characters, art)
  water.gdshader     the canal: reflects the scene above it
assets/              fonts (OFL), placeholder sounds, greybox tiles
                     (colour, normal and gloss atlases)
tiles/               the TileSet
tools/               Python generators: lit greybox tiles, sounds, the
                     ASCII level (tools/levels/*.txt), the input map;
                     bench_web.py runs ?bench in browsers (CI)
tests/               headless playtest and screenshot scripts (CI)
docs/DESIGN.md       the design document
```

The first prototype (plain JavaScript in the browser) lives on the
`js-prototype` branch.

Illustrations and design © 2026 Danny LeBlanc. Fonts: IM Fell English by
Igino Marini and Cinzel by Natanael Gama, both under the SIL Open Font
License (`assets/fonts/OFL-*.txt`).
