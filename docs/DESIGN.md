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
| Transform | Switch form. Mid-combo it's a **trick attack** that lands in the other form | [slice] |
| Pistol | Hitscan, small damage. Its job is the parry | [slice] |
| Parry | Shoot an enemy during its **glint** (the last part of its wind-up): it staggers | [slice] |
| Visceral | Strike a staggered enemy: heavy damage, invulnerable, refills Rally | [slice] |
| Quickstep | Short dash. Can't be hit for most of it, passes through enemies, one per jump | [slice] |
| Vials | Limited heals. Lamps refill them. Vial Holders raise the cap | [slice] |
| Blood bullets | Hold to spend 20 HP for 4 rounds. The HP becomes Rally | [slice] |
| Air attacks | Same moveset in the air, no lunge | [slice] |

### 6.3 The Blood Loop
1. **Rally:** damage you take hangs on as a pale bar for ~0.6 s, then
   drains. Melee hits win back 60% of the damage you deal.
2. **Blood bullets:** turn HP into ammo whenever you want. Rally can win it
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

## 10. Art direction
- **Hand-illustrated**, not pixel art. Blasphemous and The Last Faith are
  both pixel art, so this sets us apart and plays to the artist's
  strengths.
- **Production plan:** painted backgrounds, plus cut-out / skeletal or
  low-frame-count character animation with strong poses. Hand-drawn
  frame-by-frame for everything is too expensive.
- **Palette:** soot black, bone, oxblood, lantern amber. Spirit-cyan only for
  Second Sight.
- **Light is the art:** the scene is dark by default. Lamps, your lantern,
  Tallow and muzzle flashes cut it open. **[slice]**
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
- Plain JavaScript (ES modules) + Canvas 2D, bundled with esbuild. No
  framework. Same setup as Hairy Popsicles.
- Fixed 60 Hz simulation, render whenever the browser asks.
- Deployed to GitHub Pages on every push to `main`. itch.io once
  `ITCH_TARGET` is set.
- Levels are ASCII maps (`src/levels/`). Move to a level editor (LDtk) once
  the map grows past a few rooms.
- `?debug` in the URL shows hitboxes (H toggles them) and exposes
  `window.tallowbone`.

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

## 14. Open questions
- Lore: who is the Medium, and what is the church actually burning?
- How much story is spoken vs. found (item text, signs, NPCs)?
- Hand-drawn animation pipeline: scan and trace (like Hairy Popsicles'
  `tools/trace.mjs`), or digital cut-out rigs?
- Difficulty options, yes or no? (Accessibility vs. the soulslike contract.)
