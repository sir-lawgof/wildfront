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
- **Even Ground** and **Pure Brawl** became the Warlord and Skirmisher brackets in U2 (see below).
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

## Community PvP updates (docs/COMMUNITY_UPDATES.md)

- **Order approved by the owner (2026-11-04):** U5 → U10 → U11 → U2 → U6 → U1 → U9 → U7 → U8 → U3 → U4. U3's
  human matchmaking and U4 ranked only pay off once online play exists.
- **Kill credit in every mode (owner decision):** the kill goes to whoever dealt the most damage in the last
  `kill_credit_window_ticks` (50 = 30 s, `data/rules.json`); ties go to the latest hitter; if nobody hit inside
  the window, the latest hitter. Guardian and streak hits count for their owner. Kill style, weapon, spec and
  streak flags come from the credited player's own last hit. Assists are unchanged (10+ damage).
- **Protected states:** nothing damages or freezes a spawn-shielded player (`Sim.deal_damage`, `Sim._freeze`).
  Before U5, Snare Traps and Meteor Strike ignored the shield. A shielded player doesn't set off (or use up) a
  trap. Traps can't be set before the fight starts.
- **Engagement timer (FFA):** `engagement_ticks` per mode (`ffa` = 16, new `ffa_brawl` "Brawl" = 0). It starts
  on the first attack, hit or miss, not after both sides have hit, so nobody can jump in while the victim
  turns to fight back (like Jagex's single-way timer). Every attack between the pair restarts it; it ends
  when it runs out or either dies. Others can't attack the pair and the pair can't attack others. Area
  damage (Meteor Strike, Reckoning) isn't blocked. Bots pick another target.
- **AFK:** a human with no real input (chat and "ready" don't count) for `afk_warn_s` (60) while alive in a live
  phase is warned and flagged; at `afk_takeover_s` (90) the server hands the fighter to a bot, tags it as a bot
  and the match counts as left (forfeit). Kills on an AFK-flagged player still add to the score, so a player
  standing still isn't impossible to kill, but give no kill stat, kill XP, streak or challenge progress.
- **LAN leavers:** a peer that disconnects mid-match is taken over by a bot straight away and counts as left.
- **Leaver cooldown:** `Progression.leave_cooldown_s()` with `leave_cooldown_steps_min` [0, 2, 5, 15] over
  `leave_cooldown_window_h` (24). Built and tested now; enforced (with a leave history in the profile) when
  ranked exists in U4.
- **Bot honesty:** bots show "[BOT]" on nameplates, hover/right-click text and the kill feed, and a BOT column on
  the scoreboard. Challenges can set `"human_only": true` so kills on bots don't count; none do yet, because
  single-player is all bots. Kill events carry `victim_bot`.
- **FFA pacing with the engagement timer:** bot FFA at level ~10 runs ~3.2 kills/min (Brawl ~3.8). Clan Clash
  is unchanged at ~4.8. Neither FFA variant reaches the 20-kill limit in 10 minutes with bots (Brawl, which
  has no timer, doesn't either), so the limit is worth a look when tuning FFA.

- **Owner decisions (2026-11-05):** brackets Skirmisher / Vanguard / Warlord; U3 tier cap **A (no cap)**; ranked
  is **Duel + Last Stand** and unlocks at combat level 20 (GDD updated); mid-tier season reward in **8-12 hours**.
- **U11 combat log:** `Sim.clog` (`shared/combat_log.gd`) records hits (with the target's ward at the moment the
  attack was made, which is what decides protection), other damage, eating (with wasted healing), ward
  changes, freezes (with source), specs, deaths (time-to-kill, spec energy and food left) and spawns. U6 and
  U11 both read it. Specs "available" = used + spec energy left at each death / 50 (an approximation).
- **U11 telemetry:** one record per match in `user://telemetry/` (Options toggle, default on, no names or
  machine info). Built server-side in `Telemetry.record()` and sent in the summary. Options -> "Export
  telemetry" zips the folder. Playtest build = `-- --playtest` or project setting `wildfront/playtest_build`,
  which adds a 1-5 rating + comment row to the results screen, saved into that match's record.
  `tools/telemetry_report.gd` reads .json and .zip files; sample data and its report are in
  `tools/telemetry_sample/` (regenerate with `-- make_sample=6`).

- **U2 brackets** (`data/brackets.json`, `shared/brackets.gd`): Skirmisher (Defence 1, hide/robes only, kits from
  level-40 unlocks), Vanguard (Defence 70, kits from level-22 unlocks = tier 5, unique items banned so no special
  attacks), Warlord (every unlock, all stats 99). Everyone gets the bracket's fixed kit for their class's style:
  melee, ranged, magic, or hybrid (a class carrying weapons of all three styles). Custom-class gear and perks don't
  apply inside a bracket. Combat stats stay 99 except the bracket's overrides.
- **One system:** the Even Ground and Pure Brawl playlists are now the Warlord and Skirmisher playlists (old ids
  are mapped for safety). `Loadout.build` takes allowed armour classes instead of a `pure` flag; loadouts carry
  `stats` overrides and `allowed_armour`.
- **Featured bracket:** `rotation` in brackets.json, weekly from `rotation_epoch` (a Monday, local time), shown on
  the Play screen with days left. Ranked (U4) uses it.
- **Balance finding:** Battlemage wins 69-75% of duels overall in every bracket (and did before U2: at level 35
  it beat Archer 100%). Tuned in U9. `server/balance.gd` holds the duel runner; `balance_sim.gd -- brackets=N`
  prints per-bracket class tables.

- **U6 death recap:** built on the server when you die (`Sim.death_recap`) from the combat log and sent only to
  you while dead: the last 12 hits (attacker, style, weapon, damage, the ward you had when the attack was made,
  wrong wards in red), what you ate and wasted healing. Post-match fight report + one-line tip on the results
  screen (`CombatLog.report`, `CombatLog.tip`). Reaction time = ticks from an enemy's first attack in a new style
  until your ward matched it (capped at 20).
- **U1 Proving Grounds** (`data/training.json`, `server/training.gd`): main menu entry, offered once on first
  launch. Instructor: Drillmaster Varn (original). Six drills judged on the server from the combat log; a hidden
  "training" mode (no score, no AFK rule); exams are Duels (first to 2 rounds) with both sides on Warlord hybrid
  kits so ward reading and switching matter. BotBrain gained a data-driven `config` (reaction, prayer accuracy,
  eat threshold, eat delay, fake switches, spec logic, attack range, damage multiplier) and scripted modes
  (cycle, flee, freezer, telegraph, passive).
- **Graduation tuning:** started at the 5-tick eat delay; a skill-0.7 "drill-trained" bot wins 72% (target
  60-80%, `tools/training_sim.gd`), at reaction 4 ticks, prayer accuracy 0.40, eats at 28 HP, specs rarely, attack
  range 6. The Instructor's Challenge (fast wards, 35% fake switches, sharp specs) is won 38% of the time.
- **Drill details:** the specials drill refills spec energy (timing is what's taught); keys 8/9/0 call styles in
  the reading drill and stay quick-chat elsewhere. XP is split across styles and granted on the first pass only;
  practice gives no match XP or challenge progress. Passing the Instructor's Challenge stores the "instructor" cape
  trim in the profile (`cape_trims`); cape-trim visuals are still on the not-built list.

- **U9 balance pass** (`tests/test_balance.gd`, limit and sample size in `rules.json` `balance_check`): every
  default class (own unlocks at levels 40 and 20) and every bracket kit must win at most 60% of seeded,
  side-swapped duels against the other classes. Before: Battlemage won 69-83% everywhere. The cause was mostly
  behavioural: hybrids switch to the style the target isn't warding, single-style classes always hit into a
  ward, and the Duel's skirmish pack rounded every class to the same food. Data changes: wards block 30% (was
  40%); plate magic defence 0 (was -12, -1/tier); robes defend 2/4 base vs melee/ranged (was 6/10, +1/+2 per
  tier); Warrior and Archer main food 26 (was 18); Vanguard ranged kit uses a longbow and its melee kit 34 food.
  Result: 26-58% for every class. Known gap: at level 8 (own unlocks) Battlemage still wins ~65%; low levels
  swing a lot between small changes, so they aren't in the check yet. Clan Clash pacing is unchanged (~4.7
  kills/min). Brackets can now also ban spell, prayer and perk ids.
- **U9 patch notes** (`data/patch_notes.json`): shown once after an update (not to brand-new players), with a
  "what changed for my class" filter (custom classes map to the default class of their style); also on the
  main menu. The newest version must equal `application/config/version` (now 0.6.0); the validator checks it.
- **U9 meta report:** Barracks -> Meta, from local telemetry: pick rate, win rate and average time-to-kill per
  class per bracket/playlist, bots included (they're most of the data in single player).

- **U7 The Lab** (`data/mutators.json`, `shared/mutators.gd`): a "lab" playlist on Warlord kits with one mutator
  per week (same weekly clock as the featured bracket). Mutators only override data the game reads: every
  rules.json value now goes through `Sim.rule()` (match overrides first), new rules `wards_enabled` and
  `freeze_mult`, `protect_reduction`, mode keys (via mode overrides) and loadout `food_mult` / forced `kit`. The six
  mutators are No Wards, Iron Wards (60% block), Spec Frenzy, Frozen Front, Low Rations and One Life. One Life turns
  any mode into elimination rounds; rounds now work for any number of sides, so FFA One Life is last player
  standing. After a Lab match: Keep / Change / Drop, saved in the profile (`lab_votes` per week) and the match's
  telemetry. The Play screen shows this week's mutator and last week's votes from this computer (there's no
  server to pool votes yet).

- **U8 replays** (`server/replay.gd`, `client/match/replay_link.gd`): a replay is the match setup (seed and Lab
  mutator resolved) plus every human input and LAN leave by tick; bots replay themselves. Stored with Godot's
  `var_to_str` (keeps ints and vectors) as `.wfreplay` in `user://replays/`, last 10 kept, Export copies one to
  `user://exports/`. `Sim.state_hash()` checks a replay reproduces the match (Replays -> Verify; tests replay
  matches with scripted human input, class changes, a LAN leaver, Lab and private mutators). Playback re-runs the
  shared simulation with the normal client in spectator view; seeking re-simulates from the start. Practice
  (Proving Grounds) isn't saved.
- **U8 spectating:** `Sim.snapshot(-1, true)` shows every fighter's HP, prayer, special energy and overhead.
  Spectators get a free camera (F, WASD), follow players with [ and ], and an overlay; no inputs are sent. LAN
  peers can join (or the host can host) as spectators; a private match can be "watch only" (bots play).
- **U8 private matches:** Play screen -> "Private match with custom rules": bots on/off, watch only, score or
  rounds limit, time limit, and any number of Lab mutators stacked (later ones win conflicts). The LAN host's
  matches use the same settings.
- **U8 tournaments** (`shared/tournament.gd`, LAN screen -> Tournament helper): single or double elimination for
  2-16 players with byes and a grand-final reset. Results are reported by hand, or the host plays a match as a
  LAN Duel between the two entrants (matched by lobby name) while everyone else spectates, and the result
  reports itself. Saved in `user://tournament.json`.

- **U3 fair start** (owner chose tier-cap option **A: no cap**): `shared/matchmaker.gd` groups players within
  `matchmaking.window` (8) combat levels, widening by 4 every 15 s of waiting up to 40 (`rules.json`). There's no
  online queue yet, so today it keeps bots inside the window and the LAN lobby warns when its spread is wider.
  The Play screen shows your matchmaking range; the pre-match countdown shows "Your gear: tier X, lobby average:
  tier Y" and the lobby's combat levels (tier = average tier of weapon and worn armour; unique items ignored).
  Ranked and bracket playlists always use bracket kits.

- **U4 ranked** (`data/ranked.json`, `shared/ranked.gd`; owner: Duel + Last Stand, combat level 20, mid reward in
  8-12 h): Glicko-2 (one match = one rating period; team opponents averaged, RD combined), 5 placement matches
  that hide the band, bands Stone / Bronze / Silver / Gold / Sapphire / Ruby (3 divisions each) and Warden. The
  rating lives in the profile now, as plain data a server can take over. Ranked is human vs human only (no bots;
  LAN lobby with exactly 2 or 6 players), on the week's featured bracket. Each client updates its own rating from
  the opponents' lobby ratings in the summary.
- **U4 seasons and rewards:** 8-week seasons from 2026-11-02; at rollover, peak-rank rewards (Silver banner up to
  the Warden title, each band earns its own and the ones below) and a soft reset halfway to 1500 (RD at least
  200). Points: 30 per win, 12 per loss -> ~150/hour at a 50% win rate using measured match lengths (Duel ~4.2
  min, Last Stand ~10.6 min, +1 min queue/loading) -> the mid reward (Season cape trim, 1500 points) takes ~10 h.
  All rewards are cosmetic (titles, banners, cape trims).
- **U4 integrity:** matches against the same opponent within 60 minutes count 100%, 100%, 50%, 25%, then 0%
  (rating and points). Decay: 25 rating per week, down to 1300, only for placed players with fewer than 3
  matches that week. Leaving a ranked match counts as a loss and feeds the U5 queue cooldown (now enforced).
  The profile has a random `player_id` (not personal) so repeat opponents can be recognised.

- **U10 autocast per staff:** each weapon remembers the last autocast chosen with it (`Fighter.autocast_by_weapon`,
  reset each life). Switching back to a staff restores its spell if it's still usable, otherwise the old rule.
- **U10 gear presets:** V / B / N equip a saved set; Shift+V / B / N save the gear you're wearing. Stored per
  class in the profile (`presets`). The server intent `equip_set` equips each listed item found in the
  inventory, weapon first, within the per-tick equip limit, like Z/X/C.
- **U10 end screen:** the existing "Play again" is the quick rematch (same settings); a new "Change mode"
  button opens the Play screen. **Visual tick indicator:** an Options toggle that flashes a small square at
  the top centre every tick, alongside the metronome sound.

## Not built yet (next steps)

- Modes: Rune Ritual (Search and Destroy) and Hold the Banner.
- Prestige emblems and cape-trim visuals (prestige itself works). Title selection UI.
- Art: spell particles and the freeze ice shell/shatter (A5), inventory icons rendered from models (A6),
  jsfxr sounds (A8). HUD draw-call batching. Music, hosted demo (M11).
- Dedicated or headless server and internet play (LAN only for now).
