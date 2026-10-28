# Tallowbone: Design Document

A gothic 2D Metroidvania with a soulslike core. Inspired by the beauty,
dread and combat feel of *Bloodborne*, but it doesn't copy it: its own
setting, its own names, and a combat system built for two dimensions.

Status markers: **[slice]** is playable in the current build. **[planned]**
is designed but not built yet.

---

## 1. Pitch

**The church's lamps hold back the dark. Nobody asks what they burn.**

1850s, a canal city in upstate New York's Burned-over District. A revival
church held the Great Séance, and something answered. Its congregants took
the "Communion", a blood that grants second sight, and they are changing.

You are a **Lamplighter** of the Night Watch. Your job is to keep the lamps
lit through the Long Night, because what's out there can't stand the light.
The light you carry, and the light you collect from the dead, is **tallow**.
The city's lamps burn tallow rendered from its own victims.

## 2. Pillars

1. **Aggression is rewarded.** No shields. Rally, the gun parry and
   Visceral attacks all pay off pressing forward.
2. **Every weapon is a key.** Each Trick Arm's second form is both a combat
   moveset and a way through the map.
3. **The map changes with how you see it.** Second Sight reveals another
   layer of the world, at a cost.
4. **Loss you can win back.** Tallow drops when you die. Something may take
   it, and you have one chance to get it back.
5. **Beauty in decay.** Hand-illustrated, lamp-lit, foggy. The horror comes
   from what you aren't shown.

### What every good Metroidvania needs, and how we meet it
| Fundamental | In Tallowbone | Status |
|---|---|---|
| **Utility-gated exploration**: the way on is blocked by an ability you don't have yet, not a key | You start with walk, jump and strike; everything else is found (section 6.7). The Lantern burns veils, the **Climbing Irons** climb the chimney by the start **[slice]**. Next: Boathook vault, Chain-Cane swing, Bell-Maul floors, Mill-Saw walls; **Updraft** (the lantern's heat lifts a second jump) | two gates so far |
| **Backtracking that changes things**: old dead ends become shortcuts and secrets | Souls-style **shortcut gates**, barred from one side, lifted from the other, open for good **[slice]**: the undercroft gate opens onto a shaft back up to the street before the hall, the hall door joins the plaza to the hall. The chimney at the start pays off once you have the Irons **[slice]**. New forms reopen old places; Second Sight shows a hidden layer; the Long Night changes the city after each boss | started |
| **One interconnected, memorable map** | One continuous city, districts joined in loops; landmarks you can see from far off in the backdrop (church spire, canal locks, mill wheel); a **self-updating map** on the pause screen: only where you've been, with lamps, gates, finds you've seen, your Tallow and Gorged enemies **[slice]** | map done |
| **Tight, responsive movement** | Coyote time, jump buffer, variable jump, quickstep, buffered presses, freeze-frames, **ledge assist** (a jump that barely clips a ledge pops you onto it), wall slide and wall jump with the Irons **[slice]** | ongoing |
| **Rewards that matter**: never filler | Vial Holders, Bullet Pouches **[slice]**; Bone, new Trick Arms, Second Sight relics. Rule: every secret gives something you can feel in play | ongoing |
| **Environmental storytelling** | The setting tells it: the church, the meeting hall, what's under it, what the lamps burn; item text and overheard Communicants. The tutorial signs become lore and in-world prompts later | [planned] |

## 3. Setting

**Real-world roots, made fiction:**
- **The Burned-over District** (western and central NY, 1800s): constant
  religious revivals. Spiritualism, Adventism and Mormonism all started there.
- **1848, Hydesville, NY:** the Fox sisters' "spirit rappings" start
  Spiritualism. Our church's Great Séance echoes that.
- **Lily Dale, NY:** a town of mediums that still exists. The model for
  the Parlor.
- **The Erie Canal, mill towns, asylum architecture, gothic revival
  churches.**
- **Hudson River School painting:** American Romanticism, the same family as
  Caspar David Friedrich, one of Bloodborne's painterly influences.

**Places (first pass):**
| Area | What it is |
|---|---|
| The Canal District | Streets, locks and bridges. The first area. **[slice]** |
| The Meeting Hall & Undercroft | Where the congregation gathers, and what's under it. **[slice]** |
| The Church Plaza | The church's front door, barred. **[slice]** |
| The Mill | Textile mill. Rails, saw-wheels, machinery. **[planned]** |
| The Asylum | Where the first to "see" were sent. **[planned]** |
| The Locks | Flooded lower city. **[planned]** |
| Lily Hollow | The mediums' town, over the hill. **[planned]** |

## 4. Our terms (vs. Bloodborne)

| Bloodborne | Tallowbone |
|---|---|
| Blood Echoes | **Tallow**: the light of the dead, collected in your lantern |
| Blood Stone | **Bone**: weapon upgrade material |
| Lanterns | **Street lamps** you light yourself |
| Hunter's Dream | **The Parlor**: a séance room between worlds |
| The Doll | **The Medium** |
| Insight | **Second Sight** |
| Frenzy | **Dread** |
| Trick weapons | **Trick Arms** |
| Quicksilver bullets | **Quicksilver rounds** |
| The night progresses | **The Long Night** |

## 5. Core loop

Explore, fight, collect Tallow, light a lamp, rest (heal and refill, but
enemies return), spend Tallow to level up, push further. Die, and your
Tallow stays behind.

## 6. Combat

### 6.1 Philosophy
Bloodborne pushes the player forward: no shields, health you can win back
by hitting back, and a parry that rewards reading the enemy. All of that
carries over into 2D. The main danger is *commitment*: attacks can't be
cancelled during startup, only during recovery.

**No stamina bar.** Stamina in 2D platforming feels sluggish. The risk comes
from the Rally window and committed attacks instead.

### 6.2 Moves
| Move | Notes | Status |
|---|---|---|
| Strike combo | Per-form combos with startup / active / recovery frames | [slice] |
| Transform | **Hold strike**: the swing turns into a **trick attack** that lands in the other form. (A transform key exists too, for players who want it.) | [slice] |
| Pistol | Hitscan, small damage. Its job is the parry | [slice] |
| Parry | Shoot an enemy during its **glint** (the last part of its wind-up): it staggers | [slice] |
| Visceral | Strike a staggered enemy: heavy damage, invulnerable, refills Rally | [slice] |
| Quickstep | Short dash. Can't be hit for most of it, passes through enemies, one per jump | [slice] |
| Vials | Limited heals. Lamps refill them. Vial Holders raise the cap | [slice] |
| Blood bullets | Out of bullets, hold the pistol: 20 HP for 4 rounds. The HP becomes Rally | [slice] |
| Air attacks | Same moveset in the air, no lunge | [slice] |
| Wall slide / wall jump | With the Climbing Irons: press into a wall in the air to slide down it slowly, jump to kick off, up and away | [slice] |

### 6.3 The Blood Loop
1. **Rally:** damage you take hangs on as a pale bar for ~0.6 s, then
   drains. Melee hits win back 60% of the damage you deal.
2. **Blood bullets:** out of ammo, keep holding the pistol to turn HP into
   rounds. Rally can win it
   back, so aggressive players never run dry.
3. **Parry:** shoot during the glint, and the enemy staggers.
4. **Visceral:** big damage and **all** your Rally back at once.
5. Aggression is the most efficient way to play.

### 6.4 Enemy rules
- Every attack has a wind-up, and the last part of it **glints** (seen and
  heard). That's the parry window.
- Hits make enemies flinch, **except** during their own wind-up and strike.
  Once they commit, you have to dodge or parry.
- Gorged enemies never flinch.
- Human "hunter" bosses will use the same toolkit as you, gun parries
  included. **[planned]**

### 6.5 Trick Arms: every weapon is a key
| Arm | Form 1 → Form 2 | Traversal use | Status |
|---|---|---|---|
| **Lamplighter's Pole** (starter) | Hook → burning Lantern | Lantern burns veils and lights dark places | [slice] |
| **Boathook** | Short hook → vaulting pike | Pole-vault gaps, bounce off enemies and spikes | [planned] |
| **Chain-Cane** | Cane → chain whip | Latch onto iron hooks and swing | [planned] |
| **Bell-Maul** | Hammer → ringing bell | Slam through cracked floors. A ring briefly shows the Second Sight layer | [planned] |
| **Mill-Saw** | Cleaver → spinning saw-wheel | Grind along rails, climb walls | [planned] |

Off-hand guns: pistol **[slice]**, blunderbuss (spread, close stagger)
**[planned]**, flare pistol (lights dark areas) **[planned]**.

### 6.6 Controls: easy to pick up
Mouse-first on PC, because that's what PC players already know, and every
action stays one press. You start with **five**: walk, jump, strike,
lamps/gates, pause. Each find adds one, and its banner names the key.

| Action | Mouse & keyboard | No mouse | Gamepad | From |
|---|---|---|---|---|
| Walk / jump | A D / Space | A D / Space | Left stick / A | start |
| Strike (hold: turn the Pole) | Left-click | J | X | start (turning: Lamp Oil) |
| Lamps, gates | E (or W) | E | D-pad up | start |
| Pause and map | Esc | Esc | Start | start |
| Vial | F | F | Y | start (first shown when you're hurt) |
| Quickstep | Shift | L | B | Watchman's Boots |
| Pistol (parry) | Right-click | K | LT | Watch Pistol |
| Wall jump | Space against a wall | Space | A | Climbing Irons |

- No separate blood-bullet button: holding the pistol when empty does it.
  **[slice]**
- Signs and prompts name the keys for whatever you're holding (mouse and
  keyboard or gamepad). **[slice]**
- **Lessons in the moment:** the first time an enemy glints near you, time
  slows and a prompt says to shoot; the first stagger says to strike. Each
  stops once you've done it. **[slice]**
- The pause screen lists only the keys you have. **[slice]**
- Rebinding in an options menu, and touch controls. **[planned]**

### 6.7 Found along the way
The Canal District hands out the kit in order, each find right where it's
first needed, so nothing is taught before it's useful. **[slice]**

| Find | Where | Unlocks |
|---|---|---|
| Watchman's Boots | Just past the canal | Quickstep |
| Watch Pistol | Before the first glinting Communicant | The pistol, the parry, Visceral attacks, blood bullets |
| Lamp Oil | The street before the meeting hall's veil | Hold strike to turn the Pole into its Lantern |
| Climbing Irons | The far end of the undercroft | Wall slide and wall jump: the chimney by the start, and the vial at its top |

## 7. Economy: Tallow & Bone

### Tallow (the souls)
- Enemies drop it. Spend it at lamps to level up. **[slice]**
- **Death:** your Tallow drops where you fell (or at your last firm footing
  if you died in the air or the canal). **[slice]**
- **Gorged:** after you respawn, any enemy that walks through your pile
  absorbs it. It gets 1.6x health and 1.3x damage, never flinches, and
  glows. Kill it to get your Tallow back plus 10%. **[slice]**
- **Die again** before you recover it (from the ground or the Gorged enemy)
  and it's gone for good. **[slice]**
- Emergent tactic: lure enemies *away* from your pile before you go for it.

### Bone (upgrades) [planned]
Rare drops from bosses and elite enemies. Upgrades Trick Arms at the
Parlor.

### Levelling [slice]
Cost: 60 x 1.12^(level-1) Tallow. Stats in the slice: **Vitality** (+12
HP), **Strength** (+8% melee), **Steady Hand** (+2 bullets, +15% shot
damage). The full game adds **Sight** (Second Sight scaling).

## 8. Second Sight & Dread [planned]
The Metroidvania-native mechanic.
- **Gained by:** first sight of a boss, killing bosses, séance relics.
- **High Sight reveals:** ghost platforms, hidden doors, lore, enemies you
  couldn't see before (they could hurt you all along), new shop stock, new
  NPC dialogue.
- **Cost:** **Dread** builds faster at high Sight. A full bar means a burst
  of damage.
- **Spendable** at the Parlor for rare items. Spending lowers Sight and the
  layer fades again.
- **Rule:** the critical path never needs more Sight than the story
  guarantees. No soft-locks.
- Visual: the spirit-cyan palette is reserved for this layer.

## 9. World structure
- **Lamps** are checkpoints. First press lights one, next press rests:
  heal, refill, enemies reset. **[slice]**
- **The Parlor** hub: reached from any lit lamp. The Medium levels you up;
  Bone upgrades happen there. Teleport between lamps. **[planned]**
- **The Long Night:** the world changes after major bosses: dusk, then
  midnight, then the witching hour, then something in the sky. Palette,
  enemies and paths change, so backtracking feels new. **[planned]**
- **Gating:** Trick Arm forms (abilities) and Second Sight (perception).
- **Shortcut gates:** barred from one side, lifted from the other, and open
  for good (through rests and deaths). From the barred side they read
  "Barred from the other side", so you know a way round exists. **[slice]**
- **The map** (pause screen) draws only what you've seen. **[slice]**

## 10. Art direction
- **Hand-illustrated**, not pixel art. Blasphemous and The Last Faith are
  both pixel art, so this sets us apart and plays to the artist's
  strengths.
- **Characters: painted 2D frames, lit in 3D.** Low frame counts with
  strong poses (about 90 frames for the Lamplighter across both forms,
  about 20 per enemy), painted over templates CI renders from the greybox
  so the art matches the hitboxes; flat colour, the 3D lights do the rest.
  The pipeline is in [ART.md](ART.md). **[slice: pipeline, art to come]**
- **Environments:** 3D, generated from the level for now; painted textures
  or modelled pieces later.
- **Palette:** soot black, bone, oxblood, lantern amber. Spirit-cyan only for
  Second Sight.
- **Light is the art:** the scene is dark by default. Lamps, your lantern,
  Tallow and muzzle flashes cut it open. **[slice]**
- **2.5D: a real 3D night around 2D play [slice, greybox].** The world is a
  3D scene built from the level: stone with depth, a city of houses behind
  with lit windows and the church spire, all in volumetric fog. The moon
  sits behind the scene, so everything is backlit: dark fronts, rimmed
  tops, long shadows reaching toward you, the moon and lamps shining in wet
  stone. Lamps and your lantern are real lights that throw the characters'
  shadows on the walls. It rains (stopping at roofs) and water drips off
  every ledge and runs down the walls; puddles stand on anything flat.
  Play stays 2D on the plane z = 0; characters and props are drawn there
  and lit by the 3D lights. Full quality is the desktop app; the browser
  gets a reduced version (no volumetric fog or screen-space reflections).
- **The flat look (`?2d`).** Lit like 3D, drawn in 2D: surfaces have normal maps (bumps) and
  specular maps (wet gloss), so lamps, your lantern and the moon light them
  like real stone, wood and water: raking light across brick, glints on wet
  cobbles. Characters go through a volume shader that rounds them under the
  same lights. Rain, splashes, ground mist and a canal that reflects the
  scene. **[slice, greybox]**
- **For the illustrations:** paint flat colour with no lighting baked in;
  the volume shader rounds it automatically (in 3D, `shaders/plane3d.gdshader`
  does the same under the 3D lights). Environments can be painted textures
  on the 3D geometry, or modelled. For more relief, add a normal
  map (painted, or generated from the drawing with a tool such as Laigter)
  and a gloss map for wet or metal parts.
- **Photo reference:** upstate architecture, fog and lamp light. Use it for
  textures and lighting studies.
- Type: IM Fell English (period print), Cinzel for numbers. **[slice]**

## 11. Audio direction
- Period instruments: pump organ / harmonium, bowed saw, fiddle, and
  **Sacred Harp shape-note singing** (a raw 19th-century American hymn
  style).
- The parry glint needs a distinct sound cue as well as the visual one.
  **[slice, placeholder]**
- The current sound effects are synthesized placeholders.

## 12. Tech
- **Godot 4.7**, GDScript. Forward+ renderer on desktop (Metal on the Mac),
  Compatibility on the web.
  Moved from the JavaScript prototype (kept on the `js-prototype` branch)
  for the editor: painting levels, placing things, animation (Skeleton2D /
  AnimationPlayer for cut-out characters), particles, shaders and real 2D
  lights. Mac builds now (CI); Windows / Linux / Steam Deck builds later.
- Fixed 60 Hz simulation: the World steps the player, enemies and systems
  itself, so hit-stop freezes it cleanly.
- **The 3D stage** (`scripts/stage.gd`, in the game viewport): built at
  load from the level's tiles (a tile is a metre; stone runs from 1.2 m in
  front of the gameplay plane to 3 m behind it). Wet stone is
  `shaders/stone3d.gdshader` (world-space triplanar, generated textures
  from `tools/textures3d.py`: blocks on the sides, cobbles on top; puddles
  and running water from noise). Moon: DirectionalLight3D behind the scene
  with 4-split shadows; lamps and the lantern: OmniLight3Ds with shadows;
  WorldEnvironment with volumetric and depth fog, glow, SSR, SSAO, ACES;
  a sky shader with the moon where the light comes from. Rain is
  GPUParticles3D stopped by a heightfield that follows the camera; drips
  fall from points under every ledge. The camera's field of view and
  distance make the plane z = 0 match the 2D view exactly, so the 2D
  overlay (glows, swooshes, bars, HUD prompts) lines up.
- **The plane:** actors and props (World layer 2) draw into a transparent
  SubViewport that shares the World's canvas (canvas cull masks split
  them from the overlay, layer 1). A quad at z = 0 shows it through
  `shaders/plane3d.gdshader`: normals from the silhouettes, alpha-scissor
  so it casts shadows.
- **The flat look (`?2d`):** the night is a CanvasModulate, a DirectionalLight2D moon, and
  PointLight2Ds for lamps, your lantern, Tallow and Gorged enemies. Tiles
  use a CanvasTexture (colour + normal + specular, 64px shown at half
  size); indoor back walls are on light mask 2 so the moon skips them.
  Glints and embers draw unshaded on top.
- Actors paint their greybox drawing into a SubViewport (`scripts/figure.gd`)
  shown through `shaders/volume.gdshader`, re-rendered only when on screen
  and changed. The canal is `shaders/water.gdshader` (screen reflection).
- **Web performance [slice]:** the world (and backdrop) draw into their own
  viewport at no more than 3 render px per world px (1920x1080), shown
  scaled; menus and text stay at the window's resolution. Frames averaging
  over 24 ms drop the render scale a step (2x, 1.5x, 1x). Firefox pays far
  more per draw call than Chrome, so the backdrop's skyline is painted once
  into textures and scrolled, rain is one batch of lines, and pickups glow
  with drawn halos instead of lights. Physics catches up at most 3 ticks a
  frame, so a slow frame slows the game instead of spiralling.
- **Mac app [slice]:** CI exports a universal macOS build on every push
  (ad-hoc signed; Developer ID signing and notarization later, so it opens
  without the Gatekeeper prompt). The browser is the weak platform for
  heavy lighting; the desktop builds are where the look gets judged.
- F3 shows fps and the render size. `?bench` runs a frame-time benchmark (each system switched off in turn,
  then lower render scales) and shows the table; `?perf` is F3 from the start;
  `?scale=1.5` fixes the render scale. CI runs `?bench` in
  Firefox and Chrome (`tools/bench_web.py`, CPU-drawn, so compare rows).
- Levels are scenes with TileMapLayers (`Ground`, `BackWall`) and placed
  entities. The first was generated from ASCII by `tools/build_level.py`.
- CI (GitHub Actions) imports the project, runs a headless scripted
  playtest, renders screenshots, exports the web build and deploys it to
  GitHub Pages on every push to `main`, then benchmarks the build in
  Firefox and Chrome.
- H shows hitboxes when playing from the editor; `?debug` does it on the
  web build.

## 13. Milestones
| # | Milestone | Status |
|---|---|---|
| M0 | **Greybox slice:** movement, Lamplighter's Pole (both forms), gun parry, Visceral, Rally, blood bullets, vials, lamps + levelling, Tallow drop / Gorged / reclaim, veil gating, one district | **done** |
| M1 | First boss (a fallen Watchman, a hunter who uses your toolkit). The Parlor hub. Saving | next |
| M2 | Second Weapon (Boathook) and its gated area. Bone upgrades | |
| M3 | Second Sight + Dread, one revealed-layer area | |
| M4 | Art pass on the Canal District: illustrated backgrounds and character animation | |
| M5 | Music and sound pass | |
| M6 | Touch controls, gamepad remapping | |
| — | Engine move: JavaScript prototype → Godot 4.7, same slice | **done** |
| — | Easy controls: mouse-first layout, keys named for your device, lessons for the parry and Visceral | **done** |
| — | Lit greybox: normal and gloss maps, moonlight, rounded characters, rain, mist, reflective water | **done** |
| — | Web performance: capped, adaptive render scale; far fewer draw calls; Firefox and Chrome benchmark in CI | **done** |
| — | Mac app built by CI (universal, ad-hoc signed) | **done** |
| — | 2.5D: 3D stage around the 2D game (geometry from tiles, moon and lamp shadows, volumetric fog, wet stone, rain and drips, city) | **done (greybox)** |
| — | Easier start: canal of short hops, ledge assist, five starting keys with the rest found along the way, hold strike to transform, pause-screen map, shortcut gates, Climbing Irons | **done** |

## 14. Open questions
- Lore: who is the Medium, and what is the church actually burning?
- How much story is spoken vs. found (item text, signs, NPCs)?
- Hand-drawn animation pipeline: scan and trace (like Hairy Popsicles'
  `tools/trace.mjs`), or digital cut-out rigs?
- Difficulty options, yes or no? (Accessibility vs. the soulslike contract.)
