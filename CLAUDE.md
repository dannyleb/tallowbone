# Tallowbone

Gothic 2D Metroidvania / soulslike, plain JavaScript + Canvas 2D, bundled
with esbuild, deployed to GitHub Pages from `main`. The design lives in
`docs/DESIGN.md`. Keep its status markers ([slice] / [planned]) and the
milestone table up to date when features land.

## Commands
- `npm run check`: lint + production build. Run before every commit.
- `npm run dev`: dev server on :8080.
- `?debug` in the URL: hitboxes + `window.tallowbone.game` for scripted
  playtests (Playwright).

## Conventions
- ES modules, factory functions (`createX`), no classes, no framework.
- Tuning numbers belong in `src/config.js` (or `arms.js` / `enemies.js`
  for per-weapon / per-enemy data), with a comment on what they mean.
- The simulation is fixed-step (1/60 s). Game logic never reads the clock.
  Presses are buffered on the player (`p.buf`).
- Rendering is separate from logic (`src/render/`). Greybox shapes stand in
  for art; keep them posed from the real timings so hitboxes match.
- Levels are ASCII maps in `src/levels/` with the legend at the top.
- Use the setting's own words (Tallow, Bone, Lamps, the Parlor, Second
  Sight, Gorged), never Bloodborne's.
