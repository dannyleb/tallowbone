# Tallowbone

A gothic 2D Metroidvania with a soulslike core. You are a Lamplighter in a
canal city in 1850s upstate New York, on the night a séance went wrong.
The church's lamps hold back the dark. Nobody asks what they burn.

**Play:** https://dannyleb.github.io/tallowbone/ (deploys from `main`).
**Design:** [docs/DESIGN.md](docs/DESIGN.md).

The current build is the **first playable slice** (greybox: shapes stand in
for the art). It covers the Canal District with the full core loop:
- combat: Lamplighter's Pole (Hook and Lantern forms), trick attacks, the
  gun parry and Visceral attacks, Rally, blood bullets
- lamps and levelling
- Tallow drops and Gorged enemies

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Walk | A D (or arrows) | Left stick / D-pad |
| Jump (S + jump drops through walkways) | Space or Z | A |
| Strike | J or X | X / RB |
| Transform (mid-combo: trick attack) | K or C | LB |
| Pistol (parry on the glint) | L or V | LT |
| Quickstep | Shift | B |
| Vial | F | Y |
| Blood bullets (hold) | R | Select |
| Light / rest at a lamp | E | D-pad up |
| Pause | Esc | Start |

## Develop

```bash
npm install
npm run dev     # http://localhost:8080, rebuilds on reload
npm run check   # lint + production build into dist/
```

Add `?debug` to the URL to see hitboxes and get `window.tallowbone` in the
console.

## Layout

```
src/
  main.js         boot, title/pause, the fixed-step loop
  config.js       tuning: movement, combat timings, economy
  controls.js     keyboard + gamepad -> actions
  game.js         world state, lamps, levelling, death and respawn
  player.js       the Lamplighter's state machine
  arms.js         Trick Arms (weapon forms and attack frame data)
  enemies.js      enemy types and AI
  combat.js       damage, Rally, parry, deaths
  tallow.js       Tallow drop, pickup, Gorged enemies
  level.js        ASCII map parsing and tile queries
  levels/         maps (legend in each file)
  physics.js      tile collision
  fx.js, sfx.js   particles/banners, placeholder synth sounds
  render/         backdrop, tiles, actors, lighting, HUD
public/           index.html, style.css
docs/DESIGN.md    the design document
```

Illustrations and design © 2026 Danny LeBlanc.
