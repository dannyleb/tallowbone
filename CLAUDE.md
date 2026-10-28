# Tallowbone

Gothic 2D Metroidvania / soulslike in Godot 4.7 (GDScript, Compatibility
renderer), exported to the web and deployed to GitHub Pages from `main`.
The design lives in `docs/DESIGN.md`. Keep its status markers ([slice] /
[planned]) and the milestone table up to date when features land.

## Checking work
- Godot can't run in the cloud sessions; CI does it. Every push runs
  `.github/workflows/godot.yml`: import, `tests/playtest.gd` (headless,
  scripted mechanics checks), `tests/screenshots.gd` (Xvfb), web export,
  deploy.
- Logs and screenshots for each push go to the `ci-reports` branch:
  `git fetch origin +ci-reports:refs/remotes/origin/ci-reports && git show
  origin/ci-reports:playtest.log` (it's force-pushed each time). The
  browser benchmark lands there too, a few minutes later:
  `bench/bench.md`. Failed steps are also annotations on the check run.
- Locally, `gdparse` (pip `gdtoolkit`) catches GDScript syntax errors
  before pushing. It doesn't catch type errors; Godot does, in CI.
- When adding a mechanic, add a check for it to `tests/playtest.gd`.
  Abilities (`ABILITIES` in tuning) start locked and pickups unlock them
  (`player.has("pistol")`); scenarios that need one run after `_finds`.

## Conventions
- GDScript with tabs, doc comments (`##`) on scripts and non-obvious
  functions. No `class_name` and no autoloads: scripts `preload` each other
  (`const T = preload("res://scripts/tuning.gd")`), so `--script` test runs
  work.
- Every gameplay number goes in `scripts/tuning.gd` with a comment on what
  it means.
- The World steps everything itself in `_physics_process` (fixed 60 Hz):
  player, then enemies, then Tallow, pickups, lamps. Game logic never reads
  the clock. Presses are buffered on the player (`buf`).
- Positions are feet: an actor's origin is the middle of its feet.
- Avoid `:=` when the value comes from a Dictionary (tuning data) or a
  call on an untyped variable (`level.get_node_or_null(...)`); it's
  Variant and Godot refuses to infer it. Write the type. gdparse won't
  catch this; a script that fails to compile stops the playtest at once.
- Mind draw calls: Firefox's WebGL pays far more per call than Chrome's.
  Batch (one `draw_multiline_colors`, texture rects with one texture),
  paint static things once, and prefer drawn glows to extra lights.
- Greybox drawing (`_draw`) stands in for art. Keep it posed from the real
  timings so hitboxes match.
- Levels are scenes (`scenes/levels/`). `tools/build_level.py` generated
  the first one from ASCII; after editing a level in Godot the scene is the
  source of truth.
- Use the setting's own words (Tallow, Bone, Lamps, the Parlor, Second
  Sight, Gorged), never Bloodborne's.
