# Decisions log

The owner asked for this build to be done autonomously ("make decisions on your own … like OSRS and CoD4").
These are the calls made where the GDD was silent, conflicted with itself, or had to change. Each is easy to
revisit; most are a single data value.

## Platform and architecture

- **Godot 4.7 + GDScript instead of a TypeScript/Three.js browser stack.** The owner asked for Godot, and the
  installed Godot has no .NET, so GDScript rather than C#. GDD 11's shape is kept: `shared/` rules,
  `server/` authority, `client/` renders, `data/` content.
- **Server in-process for single player, ENet for LAN.** `MatchServer` ticks the authoritative `Sim` locally;
  `NetSession` hosts the same server for LAN peers. Clients only ever send intents and read snapshots, so a
  dedicated or headless server could come later.
- **Accounts: one local profile** (`user://profile.json`) instead of SQLite usernames and passwords. XP is still
  computed on the server side (`MatchServerCore.summary`) with shared rules.
- **Maps are rectangle lists in JSON** (`data/maps/*.json`, mirrored by point symmetry) instead of Tiled
  exports. They're easier to edit by hand and keep both sides fair automatically. A Tiled importer can come later.
- **Tests:** a small GDScript runner (`tests/run_tests.gd`) instead of Vitest. Script errors count as failures.

## Combat rules

- **Bonus categories are simplified** to melee/ranged/magic attack and defence (no stab/slash/crush split),
  plus melee strength, ranged strength, magic damage % and prayer. This keeps the combat triangle readable.
- **Accuracy, damage and the target's ward are decided when the attack is made**, then the hit lands after
  projectile travel (OSRS PvP behaviour). Splashed spells have no effect.
- **Melee can't attack diagonally**, as in OSRS.
- **Magic defence = 70% Magic + 30% Defence** (OSRS PvP rule).
- **Global `damage_scale` = 1.5** (`data/rules.json`). With 99 HP and GDD tier-1 gear (bronze scimitar max 14,
  Ember Dart 8), bot duels ran 3–5x longer than OSRS PvP and hit the round timer. One multiplier on every max
  hit keeps the GDD's spell table, tier steps and triangle in proportion. Set it to 1.0 to return to the raw
  OSRS numbers.
- **Supply packs per mode** (`data/classes.json`): respawn modes use a small "skirmish" pack and Last Stand a
  "full" pack. Class food counts (Warrior 18 … Tribrid 10) are scaled, so the inventory budget still matters.
  This was tuned with `tools/balance_sim.gd` to about 5 kills per minute in Clan Clash. Duel uses the
  skirmish pack so rounds last 1.5–2.5 minutes.
- **Combo food** delays the next attack by 2 ticks (main food 3). Potions don't delay attacks. Main food,
  combo food and potions each have their own 3-tick timer, so pike + brew + kelp roll can all land in one tick.
- **Freeze durations in ticks:** 5 s = 8, 10 s = 16, 15 s = 24, 20 s = 32. Immunity is 8 ticks (5 with Unbound).
- **Prayer drain** uses OSRS-style drain values with resistance 60 + 2 × prayer bonus.
- **Rebuke (T) and Snare Trap (Y)** are activated abilities on hotkeys. Rebuke has a 30 s cooldown.
- **Meteor Strike hits enemies only** (no friendly fire anywhere else in the game).
- **Stone Maul special** fires the moment you press it (ignores the attack timer); two presses can land in one tick.
- **Overhead prayers of enemies are visible within 15 tiles** (Eagle Sight: 20), so the Eagle Sight perk does
  something.
- **Spawn shield** ends early when you attack. Spawns score enemy distance and line of sight, plus teammate
  proximity.

## Progression

- XP curve, titles, unlock tables, perks and challenge values are taken straight from the GDD.
- **Even Ground** gives everyone every unlock, so default classes pick top-tier gear.
- **Pure Brawl** sets Defence to 1 and swaps plate for the best hide set.
- **Bots are matchmade** within ±3 levels per style of the players, the stand-in for combat-level brackets.
- **Custom class food** = 18 − 2 × (secondaries + switch pieces), minimum 6, then scaled by the mode's pack.
- **Some challenges are approximated**: Kiter = ranged kills taking no damage that life; Pinned Down =
  ranged kills on frozen targets. Spec Knockout, Comeback, Ritual Runner, Double Tap and Hybrid Master are
  not tracked yet. The weapon ladder's Master step isn't implemented.
- **Weapon mods** are unlocked by the Marksman I/II/III weapon challenges. Their numbers are in
  `data/mods.json`. **Ornament kits** are weapon colour swaps chosen in create-a-class.

## UI

- The OSRS layer has orbs, minimap, side panel tabs, hitsplats and overhead icons. The CoD layer has the kill
  feed, score bar, XP pop-ups, hit markers, streak prompts and Tab scoreboard.
- F-keys: F1 Inventory, F2 Equipment, F3 Prayer, F4 Magic, F5 Combat.
- **Gear-switch hotkeys** (Z/X/C) default to ON with a toggle in Options (GDD open question).
- All icons and sounds are generated in code (`client/ui/icons.gd`, `client/sfx.gd`), so there are no
  external or copied assets.

## Art pipeline (docs/ASSETS.md, phases A0-A6)

- **Tool paths** live in `art/tools.json` (Blender 5.2 at its default install path, Godot 4.7.2 console exe).
  `python tools/build_assets.py` runs palette -> gear_visuals.json -> Blender -> Godot import -> checks.
- **No Node.js.** Godot imports `.glb` itself, so glTF Transform/Meshopt aren't needed; the screenshot mode is a
  Godot scene (`tools/dev/asset_viewer.tscn`) instead of Playwright. jsfxr (A8, sounds) is not started yet.
- **`art/` lives inside the project** with a `.gdignore`, so it's one repo. `art/previews/` is git-ignored.
- **Character height ~1.84 tiles, not 0.9.** The doc asks for both "0.9 tiles tall" and "80-120 px at the default
  camera"; at the game's camera a 0.9-tile character is ~40 px. Readability won: the old placeholder was already
  1.8 tiles. The default camera distance also moved from 20 to 17 so a player is ~100 px tall at 1600x900.
- **Characters face +Z in Godot** (glTF's front), not -Z as the doc guessed. ActorView already rotates by
  atan2(dir.x, dir.z), so nothing extra was needed.
- **One material for everything:** `assets/materials/palette.tres` is a ShaderMaterial (Lambert, roughness 1, low
  specular). Emission uses a 16x16 mask texture generated from the emissive swatch list (option 1 in the doc), so
  repainting `palette.png` never breaks glow. Team colour replaces the three `team.*` swatch cells through an
  `instance uniform` (no per-player materials); `recolor` does ornament kits and `flash` the hit flash.
- **Team colour** is friend/foe from the viewer's side (blue allies, red enemies, like the rings and names), and
  shows on a tabard/stole on every body armour piece, the kite shield emblem and the base tunic.
- **gear_visuals.json is generated** from the item data by `tools/dev/gen_gear_visuals.gd`, so coverage can't
  drift; hand tweaks go in `data/art/gear_visuals_overrides.json`. One model file per item.
- **Pose convention:** poses are world-axis Euler degrees per bone (documented in `art/blender/anims/poses.py`);
  the baker converts them to bone-local quaternions, so poses don't depend on bone roll.
- **Stance variants:** idle/walk/run exist per stance (unarmed, 1h, 2h, bow, xbow, staff, throw): 21 locomotion
  clips. `anim_sets.json` is generated from `art/blender/anims/clips.py` with impact times.
- **Impact sync:** melee hits land on the attack tick on the server, so the client delays the melee hitsplat by
  the clip's impact time, and launches projectiles on the clip's release frame so they still land on their tick.
- **Bows are held in the right hand** (the weapon socket), since every weapon uses `socket_weapon`.
- **Budgets:** body armour sits close to the 300-triangle cap (hidden caps removed). Worst-case full character is
  ~1,560 triangles (cap 2,500); base body 874.
- **Greyscale check:** neighbouring tiers differ in value except magic robes 2/3 and 6/7, which are close in grey;
  their silhouettes differ (staff heads, trims, glowing accents). Repaint `palette.png` if you want more contrast.

## Environment art (docs/ENVIRONMENT.md, phases E0-E7)

- **Kits per map** come from a new `"dressing"` block in each map JSON (`kit`, rectangle `styles`, `castles`).
  Styles match a rectangle exactly or its point-mirrored copy: Castle Courtyard's 1x4 side lines are `hedge`, the
  central 6x1 line is `arch`; two short Mirewatch lines are log `palisade`. Dressing never changes gameplay.
- **Map themes** gained `sky_top`, `sky_horizon`, `sky_ground`, `cloud`, `cloud_cover`, `sun_*`, `ambient_energy`,
  `fog_color`, `fog_density` and `weather` (snow, sand, fireflies, leaves).
- **Rectangle classes:** 1-wide = wall line, 2x2 = small block, 2xN = rampart, 3x3+ = structure (thresholds in
  `client/match/env/env_layout.gd`). Wall lines autotile per tile: straight (2 opposite neighbours), end (1), join
  (corner/T/cross/single); neighbours include the border, ramparts and structures. Exposed faces get seeded face
  decorations (icicles, vents, lanterns, vines, arrow slits, banners).
- **Structures are built to the exact footprint** found in the map data (Frostgate 4x4 towers, Ember 6x5 houses);
  the Blender build scans `data/maps` for sizes, so new maps just need a rebuild.
- **Obelisks stand on walkable capture tiles**, so the "2.6 tall obelisk" is a flat rune plate (0.16 tall) plus a
  crystal floating from 1.75 to 2.65: a clear landmark that never hides feet or looks like a blocker.
- **Merged chunks instead of GridMap/MultiMesh.** The doc suggests GridMap + MultiMesh; merging every static piece
  into a 4x4 grid of chunk meshes per map (variation baked into vertex colours) costs far fewer draw calls and
  still culls what the camera can't see. Only friend/foe-tinted banners stay as small MultiMeshes.
- **Characters are merged into one rigidly skinned mesh** (every vertex 100% on its part's bone, so they still
  move as rigid segments): one draw call per player instead of ~25. Rebuilt on every equipment change.
- **Render settings:** depth prepass off; one orthogonal sun shadow pass (40 tiles) instead of 2 splits; name
  labels, HP bars, hitsplats and other billboards don't cast shadows. The renderer is unchanged (Forward+).
- **Performance (Obelisks 5v5 bot matches, 1600x900, RTX 4070):** 165 fps (vsync cap) on all maps.
  3D + shadow draw calls 25-137 and primitives 87k (Frostgate) to 140k (Castle) and 115-170k (Mirewatch at its
  busiest framing). The existing HUD adds ~118 2D canvas draw calls on top of that; batching the HUD is UI work
  for later. `--perf` prints these numbers every 5 s.
- **Ground** is one generated mesh per map with layers: checker A/B, noise patches, wall edging, shores, spawn
  paving, obelisk plazas, a Frostgate courtyard, and paths from `MapGrid.find_path` between spawns, obelisks
  and the centre (wider on Ember). Mirewatch boardwalks are flat planks (0.04 tall) beside water and on paths.
- **Water** is generated per tile with a shore factor in vertex colour; frozen (Frostgate) and murky (Mirewatch)
  variants are shader options. Rims are 0.14 tall lips inside the water tiles.
- **Occlusion cut-out** uses a global shader parameter (`player_pos`) set by the match view each frame.
- **Traps:** the server already sent only the viewer's team's traps; the client now draws them.
- **Palette tweaks after review:** Mirewatch walls were lightened (they matched the ground), Castle grass darkened.
- **Placeholder map art** stays available behind Options -> "Placeholder map art" and `--placeholder-map` until
  you approve the kits (ENVIRONMENT.md E6 says to remove it after approval).

## Not built yet (next steps)

- Modes: Rune Ritual (Search and Destroy) and Hold the Banner. Private matches with custom rules. Ranked.
- Prestige emblems and cape-trim visuals (prestige itself works). Title selection UI.
- Art: spell particles and the freeze ice shell/shatter (A5), inventory icons rendered from models (A6),
  jsfxr sounds (A8). HUD draw-call batching. Music, spectator camera, hosted demo (M11).
- Dedicated or headless server and internet play (LAN only for now).
