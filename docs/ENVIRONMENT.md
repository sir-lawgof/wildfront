# Wildfront Environment Art — instructions for Claude Code

Read this whole file, plus `docs/ASSETS.md` and `docs/DECISIONS.md`, before starting. This file covers everything in a map that isn't a character, gear or effect: ground, water, sky, lighting, walls, pillars, buildings, map borders, scenery outside the arena, decoration, objective models and ambient effects.

It builds on the pipeline that already exists:

- **Model generators:** Blender generators in `art/blender/`, collected by `build_all.py` and exported to `assets/models/<category>/<id>.glb`.
- **Build:** `python tools/build_assets.py` (palette → Blender → Godot import → checks), plus its `shots` mode.
- **Rules:** the import script `tools/import/model_post_import.gd` and the rules in `tools/import/asset_rules.gd`.
- **Palette:** colours come from palette cells (`lib/palette.py`, `art/palette/make_palette.py`).
- **Current map code:** `client/match/world_view.gd` currently builds the maps from placeholder boxes, cylinders and a checker floor. That's what this work replaces.

Follow the same working rules as `docs/ASSETS.md` section 1:

- One phase at a time (section 10), starting with E0.
- Show me a plan first and wait for approval.
- Take screenshots and check them yourself before showing me.
- Don't make git commits.
- Explain new concepts briefly.
- Log any decision this file doesn't cover in `docs/DECISIONS.md`.

## 1. The golden rule: gameplay data owns the map

The maps are defined in `data/maps/*.json` as rectangles: `walls` and `pillars` block movement **and** line of sight, `water` blocks movement only, and a 1-tile border wall is added automatically. Point symmetry mirrors everything for team B. `shared/map_grid.gd` turns this into tile flags.

**Environment art must never change gameplay and must never lie about it.**

1. **Footprints match tiles exactly.** Anything that blocks fills its blocked tiles. It may overhang a walkable neighbour by at most 0.1 tile. Nothing solid-looking ever sits on a walkable tile.
2. **Blockers read as blockers, and the two kinds look different.** Walls and pillars (block line of sight) are tall and solid: at least 1.4 tiles high. Water (blocks movement only) is flat, at most 0.25 tiles above the ground, with a visible rim. A player must be able to tell at a glance whether they can shoot past something.
3. **Decoration on walkable tiles is flat or tiny.** Rugs, cracks, puddles, grass tufts and pebbles are under 0.25 tiles tall. Never put decoration on spawn tiles, inside an obelisk's capture radius, or on tiles that bots path through in a way that would hide a player's feet.
4. **Tall decoration lives only on blocked tiles or outside the border**: banners on walls, lanterns on posts on wall tiles, trees beyond the border.
5. **Dressing is deterministic.** All random placement is seeded from the map id, so every player sees the same map.
6. **Add a test** (`tests/test_environment.gd`). For every map, the tiles covered by blocking environment pieces must exactly equal the tiles `MapGrid` marks as blocked. No decoration taller than 0.25 may sit on a walkable tile, and none may sit on spawn or capture tiles.

The camera rotates freely, tilts from 30° to 85° and zooms (`client/match/match_view.gd`). Every model must look finished from all sides and from low angles, with no open backs.

## 2. How map shapes become models

The JSON only says "wall rectangle w × h". Turn each rectangle into themed models with these classification rules (thresholds live in data so they can be tuned):

| Rectangle shape | Class | What it becomes |
| --- | --- | --- |
| 1 × n (a line) | `wall_line` | Wall segments, autotiled: straight, end cap, corner, T-junction and cross pieces, chosen per tile from its blocked neighbours. Lines that touch each other join up. |
| 2 × 2 | `block_small` | A single themed object filling the footprint: market stall, crate stack, boulder, statue base and so on (theme decides, seeded variant). |
| 2 × n, n ≥ 3 | `rampart` | A thick wall: two-tile-deep wall pieces with a walkway-style top. |
| 3 × 3 or larger | `structure` | A building, tower or ruin generated **to fit the footprint exactly** (parametric width × depth), with detail on all four sides. |
| Pillar 1 × 1 | `pillar` | A themed column or tree trunk, 2.0–2.6 tiles tall; 3 seeded variants per theme. |
| Water w × h | `water` | A themed water body: surface, rim on the edges that touch walkable tiles, edge decoration inside the water tiles only. |
| Border wall | `border` | Themed boundary pieces plus an outer skirt and backdrop (section 6). |

Optional per-map overrides go in a new `"dressing"` block in the map JSON. They only change looks, never gameplay. For example:

```json
"dressing": {
  "kit": "ember",
  "styles": [{"rect": [12, 47, 6, 5], "style": "merchant_house"}],
  "decor": [{"id": "rug_red", "tile": [30, 40], "rot": 90}]
}
```

Rectangle styles match by exact rectangle and apply to the mirrored copy too. Hand-placed decor follows the rules in section 1, and the test checks it.

### Shapes in the current maps

Counts include point-mirrored copies.

| Map | Size | Wall lines | Blocks and structures | Pillars | Water | Obelisks |
| --- | --- | --- | --- | --- | --- | --- |
| Frostgate Ruins | 64 × 64 | 20 (lengths 3–5) | 4 ramparts 2 × 6, 4 ramparts 2 × 9, 4 structures 4 × 4 | 26 | 2 pools 6 × 2 | 3 |
| Ember Outpost | 56 × 56 | 12 (lengths 3–6) | 30 small blocks 2 × 2, 4 structures 5 × 6 | 6 | 2 small 1 × 2 | 3 |
| Mirewatch Keep | 72 × 72 | 10 (lengths 4–14) | — | 14 | 10 large bog pools (6 × 8 to 8 × 14) | 3 |
| Castle Courtyard | 48 × 48 | 18 (lengths 3–8) | — | 18 | 4 pools 7 × 2 | 3 |

Re-count these in E0 from the real data with code; don't trust this table if the maps have changed.

## 3. Technical setup (extend the existing pipeline)

### New asset category

- Add a Blender package `art/blender/env/` and include it in `build_all.py`'s `collect()`. Output goes to `assets/models/env/<id>.glb`.
- Ids look like `env_<kit>_<piece>[_v<n>]`, for example `env_frost_wall_straight`, `env_ember_stall_v2`, `env_common_obelisk`.
- Add environment budgets to `asset_rules.gd` and the checks (section 9).
- **No collision shapes.** Movement and line of sight come from `MapGrid`, and clicks resolve against the ground plane, so environment meshes need no physics.

### Palette and material

The main palette (`palette.png`, 16 × 16 cells) is full: all 256 swatches are used by characters and gear, and its shader gives row 8 a team-colour meaning.

- Add a **separate environment palette** made by a new `art/palette/make_env_palette.py`: `assets/palette/palette_env.png` (16 × 16 cells) plus `art/palette/palette_env.json`.
- Lay it out as **two rows per theme kit** (frost, ember, mire, castle = 8 rows), each with the same column meanings:
  - Row one: ground A, ground B, path, ground detail, wall base, wall dark, wall light, wall trim.
  - Row two: pillar base, pillar dark, wood, cloth or roof, foliage, water shallow, water deep, glow.
- Rows 8–15 are shared: neutral stone, metals, rope, glass, neutral cloth, objective colours, team-neutral banner cloth (tinted at runtime) and glows.
- Generators use names like `frost.wall.base` or `common.rope`, exactly like `lib/palette.py`; extend it to accept the env palette.
- Add `assets/materials/env.gdshader` and `env.tres`. They take the same palette lookup and lighting approach as `palette.gdshader`, plus:
  - **Vertex colour multiply** for baked ambient occlusion and per-instance colour variation (±5% brightness), so repeated pieces don't look copy-pasted.
  - **Occlusion cut-out.** A global shader parameter holds the local player's world position. Fragments that are between the camera and the player, and within a small screen radius of the player, are dither-discarded. Players are never hidden behind walls or buildings when the camera tilts low, and it works with MultiMesh and GridMap.
  - An optional instance uniform for banner cloth tint (team colour), reusing the friend/foe rule in DECISIONS.md.
- Update `model_post_import.gd` to apply `env.tres` to models in `assets/models/env/` and `palette.tres` everywhere else.
- **Water and sky** get their own small shaders (section 5).

### Building the map in Godot

Replace the placeholder geometry in `world_view.gd` with an `EnvironmentBuilder` (client side, no game rules):

1. **Ground:** a generated mesh (section 4).
2. **Structures:** classify every rectangle (section 2), pick modules and seeded variants, and place them. Use a `GridMap` with a `MeshLibrary` built from the env `.glb` files for tile-aligned modules (wall pieces, ramparts), and `MultiMeshInstance3D` for repeated free-placed pieces (pillars, decoration, scatter). Structures sized to their footprint are single instances.
3. **Water, border, backdrop, sky, lighting, ambient effects:** sections 5–7.
4. Keep the old placeholder builder behind a debug option ("Placeholder map art") until E6 is done, so it's easy to compare.

`minimap.gd` keeps drawing from `MapGrid` but takes its colours from the theme. Optionally, later: render a top-down minimap image of the real environment.

## 4. Ground

The ground is generated at runtime from the map data as one mesh per map (or a few chunks), not from a texture image.

- **Tiles stay readable** like OSRS: each tile is a flat quad. Neighbouring tiles alternate slightly in shade (ground A/B swatches with vertex colour variation) and have a faint edge. Keep the existing grid toggle.
- **Walkable ground stays flat at y = 0** so feet always meet the floor. Height variation is only allowed outside the border (section 6).
- **Generated layers**, all from data:
  - **Paths:** run `MapGrid.find_path` between spawns, obelisks and the map centre, and paint the tiles it uses with the path swatch, so roads appear where players actually walk.
  - **Wall edging:** a ring of rubble, dirt, sand or moss swatch on tiles touching walls and pillars.
  - **Shores:** tiles touching water get a shoreline swatch (ice edge, wet sand, mud, gravel).
  - **Spawn zones:** a subtle tint or flagstones, never a hard colour.
  - **Noise patches:** large soft patches (seeded noise) of the ground-detail swatch, so big open areas aren't flat colour.
- **Flat decals** for detail: cracks, footprints, cart tracks, puddles and leaves. These are textured quads at y = 0.01, from a small decal atlas painted in the env palette style, placed with MultiMesh.
- The ground must stay **darker and less saturated than characters**, so players pop.

## 5. Water, sky and lighting

### Water (`assets/materials/water.gdshader`)

- A flat surface at y = −0.05, slightly below the ground, so it reads as a hole you can't walk into.
- Stylised, not realistic: palette shallow and deep colours, gentle scrolling noise ripples, and a light foam line along shores (a per-vertex distance-to-shore value from the builder). No real reflections or refraction.
- Every edge that touches a walkable tile gets a rim mesh (stone lip, ice chunks, mud bank, sandstone kerb) so the "no walking" edge is obvious.
- Water blocks movement but not line of sight, so edge decoration (reeds, lily pads, ice shards, floating logs) stays inside water tiles and **below 0.6 tiles tall**.

### Sky (`assets/materials/sky.gdshader`, Godot sky shader)

- A painted-look gradient (top, horizon and ground colours), a soft sun disc and one or two layers of slowly drifting, flat-shaded stylised clouds, made with noise in the shader. No photo skyboxes or HDRIs.
- Every value comes from the map's `theme` block in JSON. Extend it, for example:

```json
"theme": {
  "...existing keys": "...",
  "sky_top": "#7f9fbf", "sky_horizon": "#c8d4e0", "cloud": "#eef2f6", "cloud_cover": 0.4,
  "sun_color": "#fff2dc", "sun_yaw": -35, "sun_pitch": -50, "sun_energy": 1.1,
  "ambient_energy": 0.9, "fog_color": "#c8d4e0", "fog_density": 0.004, "weather": "snow"
}
```

### Lighting

- One `DirectionalLight3D` with shadows, as now. Tune the shadow distance and bias so wall shadows stay crisp at the default zoom.
- Ambient light comes from the sky.
- Keep the current Filmic tonemapper unless a phase proposes a change. Screenshot it before and after.
- Light props (braziers, lanterns, glowing runes) are **emissive palette cells**, not real lights. At most 4 `OmniLight3D`s per map without shadows, for key spots like obelisks or a central brazier.

## 6. Border and backdrop

The map currently ends in a plain border wall and a dark plane.

- **Border pieces** per kit, autotiled like wall lines: straight, inner corner and outer corner, and gate/arch variants placed at seeded spots for visual interest. They're never walkable openings, because the border always blocks.
- **Outer skirt:** a ring of ground from the border out to about 40 tiles. It may have height (hills, dunes, banks, cliffs) and dense scatter (trees, rocks, tents, ruins). It's never walkable and never blocks the camera's view of the arena.
- **Backdrop ring:** a few large, very low-detail silhouette meshes 60–150 tiles out (mountains, mesas, forest walls, distant castle towers) that fade into the fog. This gives each map a sense of place for almost no cost.
- Fog density and colour tie the backdrop into the sky.

## 7. Theme kits

Make each kit original: no recreations of OSRS locations or landmarks. The GDD's "OSRS flavour" column is for the pitch only.

### Frostgate Ruins (`frost`): a frozen, ruined fort

- **Mood:** cold blue-white, low sun, light snowfall, long pale shadows.
- **Ground:** packed snow (A/B), frozen flagstones in the central courtyard, icy blue paths, frost-rubble edging.
- **Wall lines:** ruined fort masonry. The silhouette is jagged and broken, with snow-capped tops, icicles under ledges, and end caps that look snapped off.
- **Ramparts (2 × 6, 2 × 9):** thick fortified walls with crenellations, a snow-covered walkway on top, a frozen tattered banner on a wall face, and buttresses every 3 tiles.
- **Structures (4 × 4):** ruined square guard towers, about 2.4 tiles tall with a collapsed roof corner, frost on stone and an arrow slit on each side.
- **Pillars (3 variants):** an intact column with a capital, a column snapped at about 1.6 tiles with a fallen chunk at its base (inside its tile), and one encased in ice crystals.
- **Water (6 × 2):** a frozen pool of cracked pale ice with a few dark open-water holes and an ice-chunk rim. It must still read as "can't walk here".
- **Border:** ruined outer curtain wall with drift snow.
- **Skirt and backdrop:** snowy slopes with dark pine silhouettes; jagged white mountains in the fog.
- **Decor (flat or tiny):** snow drifts as flat mounds under 0.15 tall, scattered stones, a half-buried shield or broken spear lying flat, frozen puddles, footprint decals.
- **Ambient:** snowfall particles around the camera, with occasional drifting mist planes.

### Ember Outpost (`ember`): a desert trading post

- **Mood:** warm orange afternoon light, dusty haze, drifting sand and the odd ember from braziers.
- **Ground:** sand (A/B), a packed-dirt road along the long open middle lane (from the path layer, made wider here), cobbled plaza tiles around the obelisks, and wet-sand shores.
- **Wall lines:** mud-brick walls with rounded tops, protruding wooden beam ends, small square vents and the occasional hanging lantern on the wall face.
- **Small blocks (2 × 2, 30 of them):** at least **6 seeded variants** so the market alleys don't repeat. Examples:
  - a covered stall with a closed counter and goods (pots, rolled rugs, fruit baskets);
  - a crate-and-barrel stack;
  - spice sacks with a scale;
  - a stacked pottery display;
  - a hay-bale cart;
  - a tarp-covered goods pile.

  Canopies stay inside the 2 × 2 footprint and at least 1.6 tall, so nothing looks walk-under.
- **Structures (5 × 6):** flat-roofed adobe merchant houses with a parapet, doors and shuttered windows on all four sides, rooftop clutter (jars, a rolled awning, a ladder against the wall) and an optional wind-catcher tower. At most 3.0 tiles tall; rely on the occlusion cut-out.
- **Pillars (3 variants):** carved sandstone columns, a sandstone column wrapped with cloth strips, and a weathered stone marker. None of them may be thin, so they read as line-of-sight blockers.
- **Water (1 × 2):** a stone well-trough with a wooden pulley frame no taller than 0.6 inside the water tiles.
- **Border:** an adobe outer wall with arch gates and palisade sections.
- **Skirt and backdrop:** dunes, palms, caravan tents and cart silhouettes; flat-topped mesas in the haze.
- **Decor:** flat rugs, pottery shards, cart-track decals, small low cacti and scattered coins.
- **Ambient:** drifting sand particles near the ground and slow embers rising from a few braziers on wall tiles.

### Mirewatch Keep (`mire`): a swamp keep

- **Mood:** green-grey murk, heavy fog, low light, fireflies.
- **Ground:** mossy mud and peat (A/B).
- **Walkways:** the GDD calls for raised walkways between bog water, but the floor must stay flat. So paint **wooden boardwalk planks** as flat geometry (height ≤ 0.05) on walkable tiles next to water and on the path layer between pools, with posts only at the water's edge, inside water tiles.
- **Wall lines, including the 1 × 14 keep wall:** dark, mossy stone keep walls with timber reinforcement, vines and roots, and arrow slits. Shorter lines can be part stone, part log palisade.
- **Pillars (3 variants):** a gnarled dead swamp tree (thick trunk, branches above 2.0 so the space reads as solid), a moss-covered stone post with a lantern, and a hollow stump-tower. All stay solid and at least 1.4 tiles tall.
- **Water (large bog pools):** murky green-brown water with patches of lily pads, reeds and cattails at the edges (under 0.6 tall), floating logs, occasional rising bubbles (shader or particles), and a low mist plane.
- **Border:** a dense wall of dead trees and roots with a rotting palisade.
- **Skirt and backdrop:** more bog, stilt-hut silhouettes, a fog-shrouded treeline.
- **Decor:** mushroom clumps, exposed roots (flat), puddles, moss patches, a sunken cart wheel.
- **Ambient:** firefly particles, slow drifting fog planes and a couple of dim emissive lanterns.

### Castle Courtyard (`castle`): two facing castles across a garden

- **Mood:** clear midday, blue sky, soft clouds, birds in the distance.
- **Ground:** trimmed grass (A/B), flagstone paths from the path layer, gravel edging along walls, and stone-paved areas at each castle front.
- **Wall lines:**
  - The long lines at each team's end (y = 36 and its mirror) are **castle curtain walls**: clean masonry, crenellations, gate gaps left exactly where the data has openings, and a banner on the castle face tinted friend or foe for that side.
  - The short side lines (1 × 4) are **clipped hedges** as garden walls, still 1.5 tall and solid.
  - The central 6 × 1 line is a **broken stone archway or dais wall**.
- **Pillars (3 variants):** a stone column, a statue of a generic original knight on a plinth, and a round topiary tree with a solid trunk.
- **Water (7 × 2):** ornamental reflecting pools with a stone rim and a small low fountain spout.
- **Border:** the outer castle wall.
- **Skirt and backdrop:** each team's full castle keep (towers, roofs, flags) beyond its end of the arena, plus rolling hills and trees.
- **Decor:** flower beds (flat), low hedge trims, barrels and weapon racks only against wall tiles, stepping stones.
- **Ambient:** a few distant bird sprites, drifting leaves and a light breeze sway on banners and trees (vertex shader).

## 8. Objectives and gameplay markers

These are shared across maps (`env_common_*`), with a themed base where noted.

| Asset | Notes |
| --- | --- |
| Obelisk | Replaces the placeholder prism and sphere. A themed stone base per kit with a floating crystal on top, about 2.6 tall. The crystal and capture ring take the owner colour, keeping the logic in `world_view.gd`'s `update_objectives()`. The capture-radius ring becomes a stylised ground decal. |
| Capture ring decal | A flat glowing ring showing the capture radius; it pulses while being captured. |
| Spawn markers | Subtle: banner poles on adjacent wall tiles, or flagstone tint. Never block or hide spawn tiles. |
| Meteor Strike target | A stylised flat danger decal with a countdown pulse, replacing the plain red plane in `show_meteors()`. |
| Snare trap | A small, flat iron trap model, visible only to allies (if the game already hides it from enemies, keep that rule). |
| Ritual altar, ritual rune, banner and banner stand | For Rune Ritual and Hold the Banner, which aren't built yet. Make the models now so they're ready, but don't add map data for them. That's gameplay work. |
| Tile click markers | Keep the current yellow/red click markers and only restyle them to match. |

## 9. Budgets and performance

| Piece | Triangle budget |
| --- | --- |
| Wall module (per tile) | 150 |
| Rampart module (per 2 × 1) | 250 |
| Pillar or tree | 250 |
| Small block (2 × 2 prop object) | 400 |
| Structure (per footprint) | 1,200 |
| Border module (per tile) | 150 |
| Decoration piece | 60 |
| Backdrop silhouette piece | 2,000 |

- **Per map:** under about 150,000 triangles in view at the default zoom, and under 150 draw calls for the whole frame (characters included). Check with Debugger → Monitors in a full 10-player bot match, and record the numbers in the phase report.
- **Instancing:** use GridMap and MultiMesh for anything repeated. One environment material plus water and sky means very few material switches.
- **Particles:** use `GPUParticles3D` on Forward+, kept small and around the camera, not map-wide.
- **The checks** (`tools/dev/check_assets.gd`) must fail on budget overruns and on env models with missing faces. The new environment test (section 1) runs in `tests/run_tests.gd`.

## 10. Phases

### E0 — Audit and plan

Done when: you've given me a short report and I've approved the plan.

- Read `world_view.gd`, `map_grid.gd`, `minimap.gd`, the four map files and the existing art pipeline.
- Count the rectangle classes per map with code, and list every module and variant each kit needs.
- Propose the env palette layout and the `dressing` JSON format.
- Don't change any code yet.

### E1 — Environment pipeline

Done when: a test wall module and a test pillar build from Blender, import with `env.tres`, show in the asset viewer, and appear in a map through `EnvironmentBuilder` with the occlusion cut-out working.

- Build the env palette, `env.gdshader`/`env.tres`, the import-script branch and the env budgets.
- Build `EnvironmentBuilder` with the placeholder toggle.
- Add an asset-viewer mode for environment pieces.
- Add a new **map screenshot mode**: top-down, 4 corners at the default camera, one low-angle (30°) view and one zoomed-out overview per map.

### E2 — Ground, water, sky and lighting for all four maps

Done when: all four maps have their generated ground, themed water, sky, fog and lighting (structures still placeholders), screenshots pass section 11, and the environment test passes.

### E3 — Frostgate Ruins kit

Done when: Frostgate is fully dressed (walls, ramparts, towers, pillars, frozen pool, border, skirt, backdrop, decor, snowfall) and passes the checklist and performance numbers.

### E4 — Ember Outpost kit

Done when: the same is true for Ember, with at least 6 market-block variants.

### E5 — Mirewatch Keep kit

Done when: the same is true for Mirewatch, including the boardwalks and bog pools.

### E6 — Castle Courtyard kit

Done when: the same is true for Castle Courtyard, including the team castle backdrops and hedges. Remove the placeholder builder option once I've approved E3–E6.

### E7 — Objectives, markers and polish

Done when:

- the obelisk, capture ring, spawn markers, meteor decal and trap are in the game;
- the altar, rune, banner and stand models are built and visible in the asset viewer;
- the ambient effects are tuned;
- a final performance pass on all four maps meets the budgets;
- `docs/DECISIONS.md` is updated.

## 11. Screenshot checklist (check this yourself before showing me)

- [ ] Every blocker reads as a blocker; water reads as "can't walk, can see across"
- [ ] Blocking pieces match their tiles exactly (compare with the grid overlay on)
- [ ] Players stand out clearly from ground and walls, including in the greyscale screenshot
- [ ] Nothing hides a player at low camera angles (occlusion cut-out works)
- [ ] No open backs, gaps, z-fighting or floating pieces from any camera angle
- [ ] Repeated pieces don't look copy-pasted (variants, rotations, colour variation)
- [ ] Each map has a distinct mood from ground, sky, fog and backdrop alone
- [ ] Within budgets; draw calls and fps recorded in the report

## 12. Rules recap

- Gameplay data owns the map; art never changes or contradicts it, and the environment test enforces this.
- Original designs only: no OSRS or Jagex assets, names, landmarks or recreations.
- Everything is generated by scripts in `art/blender/env/` or built at runtime from data. I may override any model with `art/manual/<id>.blend`.
- Ask before downloading third-party assets or using AI generation services; record anything external in `ASSET_LICENSES.md`.
- Seed all randomness from the map id.
