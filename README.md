# Tallowbone

A gothic 2D Metroidvania with a soulslike core, made in **Godot 4.7**. You
are a Lamplighter in a canal city in 1850s upstate New York, on the night a
séance went wrong. The church's lamps hold back the dark. Nobody asks what
they burn.

**Play in the browser:** https://dannyleb.github.io/tallowbone/ (deploys
from `main`).
**Design:** [docs/DESIGN.md](docs/DESIGN.md).

The current build is the **first playable slice** (greybox: shapes stand in
for the art). It covers the Canal District with the full core loop:
- combat: Lamplighter's Pole (Hook and Lantern forms), trick attacks, the
  gun parry and Visceral attacks, Rally, blood bullets
- lamps and levelling
- Tallow drops and Gorged enemies

## Open it in Godot

1. Install **Godot 4.7** (the standard build, not .NET) from
   https://godotengine.org/download.
2. Clone this repo, open Godot, choose **Import**, and pick `project.godot`.
3. Press **F5** to play. The first import takes a minute, and Godot adds
   `.import` files next to the fonts, sounds and tiles: commit those (the
   `.godot/` folder it also makes is ignored).

Where things are:
- **The level:** `scenes/levels/canal_district.tscn`. Paint tiles on the
  `Ground` and `BackWall` layers. Drag lamps, signs, pickups and enemies
  around under `Entities`, or drop in new ones from `scenes/props` and
  `scenes/actors`.
- **Tuning:** every number (speeds, damage, attack timings, costs) is in
  `scripts/tuning.gd`.
- **Hitboxes:** press **H** while playing from the editor. On the web build,
  add `?debug` to the address.

## Controls

| Action | Mouse & keyboard | No mouse | Gamepad |
|---|---|---|---|
| Walk | A D | A D (or arrows) | Left stick / D-pad |
| Jump (S + jump drops through walkways) | Space | Space | A |
| Strike | Left-click | J | X / RB |
| Pistol (shoot as an enemy glints to parry; hold when empty for blood bullets) | Right-click | K | LT / RT |
| Quickstep | Shift | L | B |
| Transform (mid-combo: trick attack) | Q or mouse wheel | I | LB |
| Vial | F | F | Y |
| Light / rest at a lamp | E or W | E or W | D-pad up |
| Pause | Esc | Esc | Start |

Signs and prompts show the keys for whatever you're holding. The first
parry and the first Visceral are taught in the moment (time slows, a prompt
says what to press). Rebind in **Project → Project Settings → Input Map**,
or edit `tools/input_map.py` and run it.

## How it's built and tested

Every push runs [the CI workflow](.github/workflows/godot.yml) on GitHub
Actions with Godot 4.7.2:
1. **Import** the project.
2. **Playtest:** `tests/playtest.gd` plays through every mechanic headless
   with simulated input and checks the results (movement, lamps, melee,
   parry → Visceral, Rally, blood bullets, vials, the veil, the canal,
   death → Tallow pile → Gorged → reclaim, levelling, pickups).
3. **Screenshots:** `tests/screenshots.gd` renders key moments.
4. **Export** the web build.
5. **Deploy** to GitHub Pages (pushes to `main` only).

Logs and screenshots for the latest push land on the `ci-reports` branch.

## Layout

```
project.godot        settings, input map
scenes/
  main.tscn          title, pause, backdrop, HUD around the World
  world.tscn         the night: level, player, effects, camera
  levels/            levels (TileMapLayers + placed entities)
  actors/            player, Communicant, Hound
  props/             lamp, sign, pickup
scripts/
  tuning.gd          every gameplay number
  world.gd           game state: Tallow, lamps, levelling, death, camera
  player.gd          the Lamplighter's state machine and look
  enemy.gd           enemy AI and look (one script, per-type numbers)
  combat.gd          damage, Rally, parries, deaths
  tallow.gd          Tallow drop, pickup, Gorged enemies
  level.gd           tile queries, veil burning
  hud.gd, main.gd    HUD, title/pause screens, lesson prompts
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
                     ASCII level (tools/levels/*.txt), the input map
tests/               headless playtest and screenshot scripts (CI)
docs/DESIGN.md       the design document
```

The first prototype (plain JavaScript in the browser) lives on the
`js-prototype` branch.

Illustrations and design © 2026 Danny LeBlanc. Fonts: IM Fell English by
Igino Marini and Cinzel by Natanael Gama, both under the SIL Open Font
License (`assets/fonts/OFL-*.txt`).
