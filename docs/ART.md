# Character art: painting the cast

The characters are painted 2D frames, lit and shadowed by the 3D night:
you paint flat colour, the game rounds the figure under the lamps, the
moon and your lantern, and throws its shadow on the walls. Until a frame
exists the greybox stand-in is drawn, so the art can arrive one animation
at a time.

## The loop

1. **Get the templates.** Every push renders a paint-over template for each
   frame: the greybox posed at that exact moment, on the right canvas, with
   the feet line, centre line and body box marked. Open the latest green run
   under [Actions](https://github.com/dannyleb/tallowbone/actions) and
   download **art-templates** (Artifacts). Each character also has a contact
   sheet (`lamplighter-hook-sheet.png`, ...) showing every frame at once.
2. **Paint over them**, one template per frame, as a reference layer you
   hide before export. Keep the pose and the reach of the weapon: the
   hitboxes come from the game's timings, and the templates show where they
   are at that moment.
3. **Export** each frame as a PNG at the template's exact size, named
   `01.png`, `02.png`, ... in its animation's folder:
   `art/characters/<character>/<animation>/01.png`
   (for example `art/characters/lamplighter/hook_run/03.png`).
4. **Push.** CI imports them and the screenshots show them in the game; the
   Mac app built from that push plays with them.

Any animation with no folder (or an empty one) keeps the greybox. Fewer
frames than listed is fine; the game holds the last one.

## Canvases

All art is at 4 px per world px (a tile is 32 world px, so 128 px of art per
metre). Paint at that size or larger and scale down to it.

| Character | Canvas (px) | Feet at (px) | Body box (px) |
|---|---|---|---|
| `lamplighter` | 640 x 480 | 320, 432 | 64 x 168 |
| `communicant` | 416 x 368 | 208, 320 | 80 x 176 |
| `hound` | 360 x 192 | 180, 152 | 136 x 88 |

The Lamplighter's canvas is wide and tall because the pole reaches far,
overhead and ahead. Every frame faces right; the game mirrors it.

## How to paint for the 3D light

- **Flat colour, no lighting painted in.** No highlights, no cast shadows,
  no rim light: the game adds them. Local colour and the drawing's own
  value pattern (folds, seams, a pale face) are what you paint; dark
  palettes are fine.
- **The silhouette does the most work.** Shading and the shadow on the
  wall come from the outline, so keep it clear and readable: gaps between
  arm and body, the hat brim, the pole.
- **Hard edges.** Pixels under half opacity are cut away (that is what lets
  figures cast shadows), so no soft glows or faded edges on the figure
  itself. Glows, flames, glints and swooshes are added by the game.
- **Stay inside the canvas**, feet on the feet line, centred on the centre
  line when standing.

## Frames

### Lamplighter (`lamplighter`)

Every animation comes in both forms of the Pole: `hook_<name>` and
`lantern_<name>` (the Hook form has a three-hit combo, the Lantern two).
Start with the Hook form; the Lantern form can follow.

| Animation | Frames | What it covers |
|---|---|---|
| `idle` | 4 | Standing; a 1.6 s loop |
| `run` | 6 | One stride, about half a second |
| `jump` | 1 | Rising |
| `fall` | 1 | Falling |
| `wall` | 1 | Sliding down a wall on the Climbing Irons, the wall ahead |
| `dash` | 2 | Quickstep: the dart, then catching yourself (the game adds afterimages) |
| `combo1`, `combo2`, `combo3` | 4 each | A swing: 1 wind-up, 2 strike begins, 3 strike ends, 4 recovery. The hits alternate down and up; the templates show the arc |
| `trick` | 4 | The trick attack from this form: same four beats, landing in the other form (frames 2 to 4 show the other form's pole) |
| `transform` | 3 | Turning the Pole into this form |
| `shoot` | 2 | Aim, fire (the game adds the shot) |
| `heal` | 2 | Raise the vial, drink |
| `blood` | 2 | Cutting the palm for blood bullets |
| `hurt` | 1 | Struck |
| `visceral` | 3 | The finisher: drive in, wrench, tear free |
| `dead` | 3 | Falling (the game fades it out) |

A suggested order: `hook_idle`, `hook_run`, `hook_jump`, `hook_fall`,
`hook_combo1` to `combo3`, `hook_dash`, `hook_hurt`, `hook_dead`, then the
rest, then the Lantern form.

### Communicant (`communicant`) and Hound (`hound`)

| Animation | Frames | What it covers |
|---|---|---|
| `idle` | 2 | Standing; a 1.4 s loop |
| `walk` | 4 | One stride |
| `windup` | 3 | The tell before the attack; frame 3 is the glint, the moment to shoot (the game adds the flash) |
| `strike` | 2 | The attack (the Hound's is a lunge) |
| `recover` | 2 | Coming back from it |
| `flinch` | 1 | Hit |
| `stagger` | 2 | Parried and reeling, open to a Visceral |
| `held` | 1 | Caught in a Visceral |
| `dead` | 3 | Collapsing (the game fades it out) |

Gorged enemies are tinted redder by the game, and every enemy flashes white
when hit; no separate frames needed.

## Later

- **Normal maps** (optional): for more relief than the silhouette gives,
  a painted or generated normal map per frame (`01_n.png`). Not wired up
  yet.
- **Cut-out rigs**: if frame counts grow, the body can be split into parts
  and animated in Godot instead.
