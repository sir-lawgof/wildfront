# Instructions for Claude Code — read this first

This file is the game design document (GDD) for **Wildfront**, a browser PvP game with Old School RuneScape-style tick combat and Call of Duty 4-style progression. Save it in the repo as `docs/GDD.md`. It is the source of truth for every design decision.

## How we work

1. Build one milestone at a time, in the order listed in section 12 ("Build roadmap and Claude Code prompts"), starting with **M0**. Each milestone there has a goal, a "Done when" test and a prompt.
2. At the start of each milestone, read the GDD sections that milestone names, then show me a short plan (files you'll create or change, and how you'll test it). Wait for my approval before writing code.
3. While building: write unit tests for game rules, run the tests and fix failures before calling the milestone done.
4. At the end of each milestone, tell me how to run and play-test it myself, and check the "Done when" test with me. Don't start the next milestone until I say so.
5. Don't make git commits. I'll review and commit each milestone myself.
6. I'm getting back into coding after a long break. Explain new tools, commands and concepts briefly in plain language.

## Ground rules for the code

- The server is authoritative and runs a fixed 600 ms tick (section 2). Clients only send intents and render what the server says.
- Game rules (formulas, tick order, combat) live in `shared/` and are imported by both client and server. Never put game rules in client-only code.
- Content (weapons, armour, spells, prayers, perks, levels, unlocks, challenges, maps, modes) lives in `data/*.json`, validated against schemas. Balance changes should be data edits, not code edits.
- Use only the original in-game names in this document. The "OSRS analogue" columns are reference for the pitch only. Never use OSRS names, models, sprites, sounds, music or game data in the game (section 13).
- Use placeholder art (capsules, boxes, flat colours) until milestone M11.
- If this document doesn't answer a design question, ask me instead of inventing an answer. If a change to the design seems needed, propose the edit to `docs/GDD.md` first.

## Your first task

Start milestone **M0 — Project setup** from section 12. Read section 11 ("Technical architecture") and show me your plan.

---

# Wildfront — Game Design Document

Design document, last updated Nov 2, 2026.

## 1. Overview

Wildfront (working title) is a round-based team PvP game. Fights use Old School RuneScape's 0.6-second tick combat. Progression copies Call of Duty 4: create-a-class, challenges, kill streaks and prestige. A match lasts 8–12 minutes. Melee, Ranged and Magic each level up separately from 1 to 40. You start in bronze-tier gear, and every level unlocks stronger weapons, armour, spells or prayers.

| Item | Decision |
| --- | --- |
| Genre | Tick-based team PvP arena with persistent progression |
| Platform | PC, browser-first (desktop build later) |
| Players per match | 1v1 up to 5v5; 8-player free-for-all |
| Match length | 8–12 minutes; objective modes play in rounds |
| Camera and controls | 3D isometric camera you can rotate, tile grid, point-and-click, hotkeys for prayers and gear switches |
| Audience | OSRS PvPers and Last Man Standing players; CoD fans who like a progression loop |
| End goal | A playable prototype that shows Jagex how this could work as an OSRS minigame |

### Design pillars

1. **Ticks, not twitch.** Every action resolves on a 600 ms server tick. Fights are won by timing: prayer switches, gear swaps, eating and special attacks, not aim.
2. **Earn your gear, keep it fair.** Players start weak and unlock stronger gear, spells and prayers in each style. Small tier steps, combat-level matchmaking and an equal-gear playlist keep skill as the deciding factor.
3. **One more match.** A steady drip of XP, unlocks, challenges and cosmetics, the way CoD4 did it.
4. **Built to be pitched.** Every system maps cleanly onto an existing OSRS system. Jagex should be able to picture it as a minigame next to Last Man Standing, PvP Arena and Soul Wars.

## 2. Core combat

Combat follows OSRS rules as closely as possible. That makes it feel right to PvPers and makes the pitch credible. Every rule below lives in a shared, unit-tested combat module that both the server and client use.

### The tick

- One game tick = 600 ms. The server is authoritative. Clients send intents, and the server resolves them on the next tick.
- Each tick runs in a fixed order: (1) queued inputs, (2) eating, drinking and gear equips, (3) prayer toggles and drain, (4) movement, (5) attacks whose timer has run out, (6) hits landing this tick, (7) deaths, respawns and objectives, (8) a state broadcast to clients.
- Weapon speed is in ticks: 4 (fast, e.g. scimitar), 5 (crossbow), 6 (greatblade, battleaxe), 7 (maul).
- Hits are delayed by projectile travel: melee lands the same tick, ranged 1–3 ticks later, magic 1–4 ticks later depending on distance.

### Movement

- Players move on a tile grid. Walking covers 1 tile per tick and running 2.
- Run energy runs from 0 to 100% and drains while running. It regenerates while walking or standing still. There is no Agility stat, so drain is a fixed rate.
- Pathfinding is OSRS-style: breadth-first search to the clicked tile, or to the nearest reachable tile.
- Line of sight matters for ranged and magic. Pillars and walls block it, so pillar-dancing and safe-spotting are real tactics.

### Stats

In standard playlists every player has 99 Attack, Strength, Defence, Ranged, Magic, Hitpoints and Prayer. Stats never change with level; progression comes from gear, spells and prayers. Bracket playlists (section 3, `data/brackets.json`) override some stats, for example the Skirmisher bracket locks Defence at 1 for pure-style builds.

### Combat triangle

Melee beats Ranged, Ranged beats Magic, and Magic beats Melee. As in OSRS, this comes from equipment defence bonuses, not hard-coded multipliers. Plate armour has high melee and ranged defence but weak magic defence. Hides are strong against magic. Robes have weak melee defence, so mages rely on freezes and distance to stay out of melee range.

### Accuracy and damage

Use the OSRS formulas directly. The effective level is the base level times the prayer multiplier, rounded down, plus the stance bonus (0–3) plus 8.

```latex
\text{MaxRoll} = \text{EffectiveLevel} \times (\text{EquipmentBonus} + 64)
```

If the attacker's roll A is greater than the defender's roll D, hit chance = 1 − (D + 2) / (2 × (A + 1)). Otherwise it is A / (2 × (D + 1)). On a hit, damage is uniform from 0 to the max hit.

```latex
\text{MeleeMaxHit} = \left\lfloor 0.5 + \frac{\text{EffectiveStrength} \times (\text{StrengthBonus} + 64)}{640} \right\rfloor
```

Ranged uses the same shape with Ranged Strength. Magic max hit comes from the spell's base damage, scaled by magic damage percentage bonuses on gear.

### Prayers in combat

- Overhead protection prayers cut damage of the matching style by 30% (`protect_reduction` in `data/prayers.json`). The OSRS PvP value is 40%; the U9 balance pass lowered it so single-style classes aren't shut down by a correct ward (see `docs/DECISIONS.md`).
- Prayer points drain each tick based on which prayers are active. Points reach 0 → all prayers switch off.
- Switching overheads in reaction to the enemy's gear swap is the core skill of the game.

### Gear switching and inventory

- 28-slot inventory, 11 equipment slots, as in OSRS.
- Clicking an inventory item to equip it takes effect at the start of the next tick. Up to 8 equips per tick, so a full hybrid switch is possible in one tick if you can click fast enough.
- Optional switch hotkeys: bind a set of items to one key. This is a quality-of-life feature Jagex will debate; keep it as a toggle so both versions can be tested.

### Food and potions

- Each life starts with the class's supply pack (section 6).
- Main food heals 20 and delays your next attack by 3 ticks. Combo food heals 18 and can be eaten in the same tick as main food (the shark + karambwan combo).
- Saradomin-brew-style potion: heals up to 16, boosts Defence, lowers offensive stats. Restore potion: restores those stats and prayer points.
- Combat potions (super combat, ranging, magic) start each life already sipped.

### Special attacks

- Special energy is a 0–100% bar that regenerates 10% every 30 seconds and refills on respawn.
- Special attacks cost 25–100% energy depending on the weapon (per-weapon, section 7). Classic plays: spec-switch to a dagger or claws for a fast knockout.

### Freezes and status effects

- Freezes stop movement but allow attacking. Durations come from the spell: 5, 10, 15 or 20 seconds.
- After a freeze ends, the player is immune to freezes for 5 seconds (3 seconds with the Unbound perk).
- Poison and venom: per-tick damage on a timer, cured by antidotes.

### Death

- No items are lost. On death you drop nothing and respawn with your class loadout (rules differ by mode, section 3).
- All combat is multi-way: anyone can attack anyone. Single-way zones are an option for future maps.

## 3. Match structure and game modes

Every match follows the same flow, borrowed from CoD4's lobby loop: queue → lobby (pick or edit classes) → 15-second pre-match countdown → match → scoreboard → XP and unlock summary → back to the lobby with the same players.

### Respawning

- Respawn delay: 5 seconds. You can change class during it; the new class applies on your next life.
- Spawn shield: 3 seconds after spawning you can't be attacked. Attacking ends the shield early.
- Spawns are picked away from enemies and toward teammates, as in CoD's TDM spawn logic.

### Modes

| Mode | CoD4 equivalent | Teams | Win condition | Respawns |
| --- | --- | --- | --- | --- |
| Clan Clash | Team Deathmatch | 5v5 | First to 50 kills, or most kills after 10 min | Yes |
| Free-for-All | Free-for-All | 8 players | First to 20 kills, or most after 10 min | Yes |
| Obelisks | Domination | 5v5 | Hold 3 capture points; 1 point per obelisk held every 5 s; first to 200 | Yes |
| Rune Ritual | Search and Destroy | 5v5 | Attackers carry a ritual rune to one of two altars (8-second channel). Defenders cleanse it (5-second channel). First to 4 rounds; sides swap at halftime | No, one life per round |
| Hold the Banner | Headquarters | 5v5 | A banner spawns at a random point; hold it to score. Holders can't respawn until it is taken | Partial |
| Last Stand | Team elimination | 3v3 | Wipe the other team; best of 7 rounds | No |
| Duel | 1v1 arena | 1v1 | First to 3 kills | Between kills |
| Brackets (Skirmisher, Vanguard, Warlord) | Playlist variant | Any mode | Fixed kits per bracket: Skirmisher Defence 1 and no plate; Vanguard Defence 70, mid-tier kit; Warlord everything maxed | Mode's rule |

### Playlists

- Casual playlists for every mode at launch, with join-in-progress for respawn modes and matchmaking by combat level (section 5). Bracket playlists: everyone gets the same fixed kit (the Warlord bracket replaces Even Ground). One bracket is featured each week.
- Ranked: Duel and Last Stand, using the week's featured bracket kits, with seasonal ranks separate from style levels. Unlocks at combat level 20. (Owner decision, 2026-11-05; was Rune Ritual and Duel.)
- Private matches with custom rules (kill limit, time, allowed gear, tick-speed toggle) for testing and tournaments.

### Bots

Bots fill empty slots. They matter for a solo developer: they let you test every mode without real players. Bot logic: pick a target, keep the right overhead against the target's current weapon style, eat below 40 HP, use specials when the target is low.

## 4. Maps

Launch with four maps that support every mode. Each map is a tile grid stored as data (JSON or Tiled `.tmj`). Each map lists its spawn zones, obelisk points, altars and banner points.

| Map | Size (tiles) | Theme | Layout idea | OSRS flavour for the pitch |
| --- | --- | --- | --- | --- |
| Frostgate Ruins | 64 × 64 | Frozen ruined fort | Three lanes; a central courtyard ringed by pillars for line-of-sight play | Deep Wilderness ruins |
| Ember Outpost | 56 × 56 | Desert trading post | Tight market alleys plus one long open road that favours ranged | Al Kharid / desert |
| Mirewatch Keep | 72 × 72 | Swamp keep | Raised walkways; a central keep with two entrances (good for Rune Ritual) | Morytania |
| Castle Courtyard | 48 × 48 | Two facing castles | Small and symmetric; built for Last Stand and Duel | Castle Wars |

### Design rules

- Every route has cover. Ranged and magic users must be able to break line of sight within about 5 tiles.
- Use CoD-style three-lane layouts on the larger maps, with one main fight area and two flanks.
- Use pillars and walls on purpose so pillar-dancing and safe spots exist but can't be held forever.
- Space spawns at least 20 tiles from the nearest objective so respawning players can't contest it at once.
- Keep the art low-detail and readable. Players must be able to see an enemy's gear at a glance, because gear tells you which prayer to use.

## 5. Progression

Melee, Ranged and Magic each have their own level, from 1 to 40, and level up separately. Every level of every style unlocks at least one item, spell or prayer (section 7). You start with bronze-tier gear and earn stronger gear as you level. Your combat level is the average of the three, and it unlocks shared rewards such as perks and utility prayers.

### Style levels

- **Melee level** unlocks melee weapons, plate armour, defenders and melee prayers.
- **Ranged level** unlocks bows, crossbows, thrown weapons, ammunition, hides and ranged prayers.
- **Magic level** unlocks staffs, wands, robes, spells and magic prayers.
- **Combat level** = (Melee + Ranged + Magic) ÷ 3, rounded down. It unlocks shared rewards and is the number used for matchmaking and titles.

### XP curve

XP needed to go from level L to L + 1 = 600 × 1.07^(L − 1), rounded to the nearest 10. The curve is the same for all three styles and lives in `levels.json` so it can be retuned. Getting one style to 40 takes 111,400 XP. All three take 334,200 XP, about 167 matches at 2,000 XP a match.

| Reach level | XP for that level | Total XP for the style |
| --- | --- | --- |
| 5 | 740 | 2,670 |
| 10 | 1,030 | 7,190 |
| 15 | 1,450 | 13,530 |
| 20 | 2,030 | 22,440 |
| 25 | 2,840 | 34,910 |
| 30 | 3,990 | 52,410 |
| 35 | 5,600 | 76,970 |
| 40 (max) | 7,850 | 111,400 |

### XP sources

XP goes to the style that earned it, like OSRS combat XP. Damage done with a bow trains Ranged; damage done with a spell trains Magic.

| Action | XP | Goes to |
| --- | --- | --- |
| Damage dealt | 4 per point of damage | The style that dealt it |
| Kill | 100 | The style of the killing hit |
| Assist (10+ damage to the victim) | 30 | The style you did the most damage with |
| Kill with a special attack | +50 bonus | That weapon's style |
| Revenge kill (killing your last killer) | +50 bonus | The style of the killing hit |
| Capture an obelisk or banner | 150 | Split by your damage share this match |
| Deliver or cleanse the ritual rune | 300 | Split by your damage share this match |
| Round win | 300 | Split by your damage share this match |
| Match win / match loss | 1,000 / 300 | Split by your damage share this match |
| Style challenge | 250–5,000 | That style |
| Weapon challenge | 500–5,000 | That weapon's style |
| Shared challenge | 250–10,000 | Split evenly across all three |

If you dealt no damage in a match, split XP goes to the style of your class's primary weapon.

### Matchmaking and fairness

Gear now gets stronger with level, so a level-40 player has a real edge over a level-1 player. Three rules keep new players in the game:

- **Combat level brackets.** Casual playlists match players within about 8 combat levels of each other when the queue allows. This is the game's version of OSRS Wilderness level ranges.
- **Bracket playlists (Even Ground is now the Warlord bracket).** Everyone gets the same fixed kit for the match, as in Last Man Standing. New players can try endgame gear, and it is the fairest test of skill. XP still counts.
- **Balanced tiers.** Each tier is roughly 6–8% stronger than the one before, not double. Skill at switching and prayer still beats a one-tier gear edge.

### Titles

Titles come from combat level, each band with numbered steps (Squire I, II, III, IV).

| Combat level | Title |
| --- | --- |
| 1–3 | Recruit |
| 4–7 | Squire |
| 8–11 | Footman |
| 12–15 | Man-at-Arms |
| 16–19 | Sergeant |
| 20–23 | Knight |
| 24–27 | Knight-Captain |
| 28–31 | Paladin |
| 32–35 | Champion |
| 36–39 | Warlord |
| 40 | Grandmaster |

### Prestige

- Each style prestiges on its own once it reaches 40. Only that style resets to level 1 and loses its unlocks. Your combat level drops to match.
- Up to 10 prestiges per style. Each grants a style emblem and a cape trim in a new colour.
- Kept through prestige: completed challenges, ornament kits, banners, stats and the other two styles.
- Reaching prestige 10 in all three styles grants a unique cape, the game's version of a max cape.
- Prestige is optional; nothing competitive is locked behind it.

## 6. Loadouts and perks

A class is a full OSRS setup: worn gear, switch items and supplies, plus three perks. Four default classes are available from the start. Create-a-class unlocks at combat level 4, as it did at rank 4 in CoD4. It starts with 2 custom slots and grows to 5.

### Class slots

| Slot | What you pick | CoD4 equivalent |
| --- | --- | --- |
| Primary weapon | Any unlocked melee weapon, ranged weapon or staff | Primary weapon |
| Weapon mod | One unlocked mod or ammo type for the primary (section 9) | Attachment |
| Secondary weapon | A switch or special-attack weapon, carried in the inventory | Secondary weapon |
| Armour set | Robes, hides or plate, at any unlocked tier | (no equivalent) |
| Switch pieces | Up to 4 extra armour pieces carried in the inventory for hybrid switching | (no equivalent) |
| Spellbook | Elemental or Forbidden (Forbidden unlocks at Magic level 11) | Special grenade |
| Supply pack | A fixed preset of food and potions; perks can change it | Frag grenade |
| Perk 1, 2, 3 | One from each tier | Perk 1, 2, 3 |

Inventory space is the real budget. Every switch piece or secondary weapon takes a slot that could hold food. A pure tank class carries 20 food; a 4-way hybrid carries 10.

### Default classes

| Class | Primary | Secondary | Armour | Style |
| --- | --- | --- | --- | --- |
| Warrior | Bronze scimitar | None (extra food instead) | Bronze armour | Melee |
| Archer | Oak shortbow | None (extra food instead) | Leather armour | Ranged |
| Battlemage | Novice staff with Ember Dart | Bronze scimitar | Woven robes | Magic with a melee switch |
| Tribrid | Novice staff | Oak shortbow and Bronze scimitar | Woven robes, with Leather and Bronze switch pieces | All three styles, fewer supplies |

The table shows the classes at level 1. Default classes upgrade on their own to the best tier you have unlocked in each style. A player who never opens create-a-class still gets stronger.

### Perks

| Perk | Tier | Effect | Combat level |
| --- | --- | --- | --- |
| Extra Rations | 1 | +3 main food | 1 |
| Extra Brew | 1 | +1 brew and +1 restore potion | 6 |
| Spell Satchel | 1 | Freeze spells cost no runes this life (otherwise 30 casts) | 9 |
| Snare Trap | 1 | Place one trap on a tile; an enemy who steps on it is frozen 5 s. Shows on the minimap for allies | 17 |
| Spare Spec | 1 | Start each life with 100% spec plus a 25% spec restore potion | 32 |
| Rebuke | 2 | Cast once every 30 s: the next hit taken reflects 75% of its damage | 1 |
| Iron Will | 2 | Prayer drains 25% slower | 3 |
| Fleet Foot | 2 | Run energy drains 50% slower | 8 |
| Antivenom | 2 | Immune to poison and venom for the whole life | 18 |
| Steady Hand | 2 | Special energy regenerates twice as fast | 22 |
| Unbound | 3 | Freeze immunity after a freeze lasts 3 s instead of 5 | 1 |
| Quick Hands | 3 | Up to 10 equips per tick instead of 8 | 11 |
| Shadowstep | 3 | Hidden from the Scrying Orb streak; no footstep sounds | 13 |
| Eagle Sight | 3 | See enemy overhead prayers from 5 tiles further away | 28 |
| Second Wind | 3 | Once per life, the first time you drop below 10 HP, heal 15 HP over 5 ticks | 34 |

Balance rule for perks: a perk may change your options or resources. It may not add flat accuracy, damage or defence. Power comes from gear tiers, which the matchmaking accounts for; perks only add options.

## 7. Unlocks by level

Every level from 1 to 40 in each style unlocks at least one thing, and some levels unlock several. Gear comes in seven tiers. Each tier is about 7% stronger than the last in offence and defence bonuses. Special attacks only appear on top-tier and unique weapons. In-game names are original; the OSRS analogue columns are for the pitch only (section 13). All of it lives in data files: a build script reads them and generates `unlocks.json`, which drives the menus and the level-up screen.

### Gear tiers

| Tier | Style level | Melee (metal) | Ranged (bow wood / hide) | Magic (robes) | OSRS analogue |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 | Bronze | Oak / Leather | Woven | Bronze |
| 2 | 5 | Iron | Willow / Hardleather | Apprentice | Iron |
| 3 | 10 | Steel | Maple / Studded | Adept | Steel |
| 4 | 15 | Cobalt | Yew / Drakehide | Warlock | Mithril |
| 5 | 20 | Orichalcum | Elder / Basilisk hide | Archmage | Adamant |
| 6 | 28 | Starmetal | Starwood / Starhide | Starweave | Rune |
| 7 | 36 | Wyrmforged | Wyrmwood / Wyrmhide | Wyrmweave | Dragon |

Armour sets are helm, body, legs, shield (or off-hand) and boots. Each style also has three sidegrade sets that trade defence for offence or utility; they appear in the level tables.

### Weapon types and special attacks

Tiered weapons get stronger each tier. Only their Starmetal and Wyrmforged versions carry a special attack. Unique weapons exist in one version and always have a special.

| Weapon | Style | Speed (ticks) | Spec cost | Special attack | OSRS analogue |
| --- | --- | --- | --- | --- | --- |
| Dagger (tiered) | Melee | 4 | 25% | Two quick hits, +15% accuracy and damage | Dragon dagger |
| Scimitar (tiered) | Melee | 4 | 55% | Sever: next hit +20% accuracy, blocks Wards for 5 ticks | Dragon scimitar |
| Longsword (tiered) | Melee | 5 | 25% | Cleave: +25% damage | Dragon longsword |
| Battleaxe (tiered) | Melee | 6 | 100% | Rampage: +20% Strength, −10% Attack and Defence for the life | Dragon battleaxe |
| Warhammer (tiered) | Melee | 6 | 50% | On hit, lowers the target's Defence 30% | Dragon warhammer |
| Whip | Melee | 4 | 50% | Drains 10% of target's run energy and gives it to you | Abyssal whip |
| Stone Maul | Melee | 7 | 50% | Hits instantly; two specs can land in one tick | Granite maul |
| Greatblade | Melee | 6 | 50% | +37.5% damage, double accuracy | Armadyl godsword |
| Claws | Melee | 4 | 50% | Four hits in a cascade | Dragon claws |
| Void Blade | Melee | 4 | 50% | Magic-damage hit for 50–150% of max hit | Voidwaker |
| Shortbow / Longbow (tiered) | Ranged | 4 / 6 | 55% | Twin Shot: two arrows, slightly lower accuracy | Magic shortbow |
| Crossbow (tiered) | Ranged | 5 | 50% | Pinning Bolt: +25% accuracy, freezes 3 s | Dragon crossbow |
| Throwing knives (tiered) | Ranged | 3 | 25% | Fan: three knives at once | Rune knives |
| Javelins | Ranged | 5 | 50% | Bleed for the same damage again over 5 ticks | Morrigan's javelins |
| Duskbow | Ranged | 9 | 55% | Two arrows, each dealing at least 8 | Dark bow |
| Heavy Ballista | Ranged | 7 | 65% | +25% accuracy and damage | Heavy ballista |
| Sunfire Crossbow | Ranged | 5 | 40% | Double accuracy | Armadyl crossbow |
| Staff (tiered) | Magic | 5 | — | No special; staffs boost magic accuracy | Mystic staves |
| Wand (tiered) | Magic | 5 | — | No special; higher accuracy, lower defence | Master wand |
| Forbidden Staff | Magic | 5 | — | Required for the Forbidden book | Ancient staff |
| Eruption Staff | Magic | 5 | 55% | A heavy blast up to 50 damage | Volatile nightmare staff |
| Tempest Staff | Magic | 5 | 50% | Chain lightning: hits up to 3 nearby enemies | (new) |

### Spells

| Spell | Book | Max hit | Effect | Magic level | OSRS analogue |
| --- | --- | --- | --- | --- | --- |
| Ember Dart | Elemental | 8 | — | 1 | Fire Strike |
| Root | Elemental | 0 | Freeze 5 s | 2 | Bind |
| Ember Bolt | Elemental | 12 | — | 3 | Fire Bolt |
| Ember Blast | Elemental | 16 | — | 6 | Fire Blast |
| Thorn Snare | Elemental | 3 | Freeze 10 s | 8 | Snare |
| Frost Shard | Forbidden | 18 | Freeze 5 s | 11 | Ice Rush |
| Ember Wave | Elemental | 20 | — | 12 | Fire Wave |
| Frost Nova | Forbidden | 22 | Freeze 10 s, 3 × 3 area | 14 | Ice Burst |
| Bramble Grasp | Elemental | 5 | Freeze 15 s | 17 | Entangle |
| Miasma Storm | Forbidden | 27 | Poison, 3 × 3 area | 18 | Smoke Barrage |
| Frost Spear | Forbidden | 26 | Freeze 15 s | 21 | Ice Blitz |
| Leech Bolt | Forbidden | 25 | Heals you 25% of damage dealt | 23 | Blood Blitz |
| Ember Surge | Elemental | 24 | — | 24 | Fire Surge |
| Gloom Storm | Forbidden | 28 | Lowers target Attack 15%, 3 × 3 area | 26 | Shadow Barrage |
| Glacial Storm | Forbidden | 30 | Freeze 20 s, 3 × 3 area | 30 | Ice Barrage |
| Leech Storm | Forbidden | 29 | Heals you 25% of damage dealt, 3 × 3 area | 32 | Blood Barrage |

### Prayers

Only one prayer of each kind can be active (for example, one Strength boost). Higher prayers replace lower ones.

| Prayer | Unlocked by | Level | Effect | OSRS analogue |
| --- | --- | --- | --- | --- |
| Ward of Blades / Arrows / Spells | Combat level | 1 | −30% damage from that style | Protect from Melee / Missiles / Magic |
| Stone Skin I / II / III | Combat level | 2 / 7 / 12 | +5 / 10 / 15% Defence | Thick Skin / Rock Skin / Steel Skin |
| Mending | Combat level | 5 | Hitpoints regenerate twice as fast | Rapid Heal |
| Endurance | Combat level | 10 | Potion boosts wear off 50% slower | Preserve |
| Sap | Combat level | 14 | Drains target's prayer by 1/4 of your damage | Smite |
| Last Rites | Combat level | 21 | Below 10% HP: heal 25% of Prayer level, prayer drops to 0 | Redemption |
| Reckoning | Combat level | 25 | On death, hits adjacent enemies for up to 25% of Prayer level | Retribution |
| Devotion | Combat level | 36 | Prayer points regenerate slowly | Rapid Restore |
| Keen Focus I / II / III | Melee | 1 / 7 / 13 | +5 / 10 / 15% Attack | Clarity / Improved / Incredible Reflexes |
| Brute Force I / II / III | Melee | 2 / 8 / 14 | +5 / 10 / 15% Strength | Burst / Superhuman / Ultimate Strength |
| Gallantry | Melee | 23 | +15% Attack, +18% Strength, +20% Defence | Chivalry |
| Valor | Melee | 31 | +20% Attack, +23% Strength, +25% Defence | Piety |
| Sharp Sight I / II / III | Ranged | 1 / 7 / 13 | +5 / 10 / 15% ranged accuracy and strength | Sharp / Hawk / Eagle Eye |
| Precision | Ranged | 31 | +20% ranged accuracy, +23% ranged strength, +25% Defence | Rigour |
| Arcane Will I / II / III | Magic | 1 / 7 / 13 | +5 / 10 / 15% magic accuracy | Mystic Will / Lore / Might |
| Insight | Magic | 31 | +25% magic accuracy, +25% Defence | Augury |

### Melee unlocks

Defenders are off-hand items that add attack and defence bonuses. Sidegrade sets appear at 25, 33 and 39.

| Melee level | Unlocks |
| --- | --- |
| 1 | Bronze scimitar, Bronze armour set, Keen Focus I |
| 2 | Bronze dagger, Brute Force I |
| 3 | Bronze longsword |
| 4 | Bronze battleaxe, Bronze warhammer |
| 5 | Iron scimitar, Iron armour set |
| 6 | Iron dagger, Iron longsword |
| 7 | Iron battleaxe, Keen Focus II |
| 8 | Iron warhammer, Brute Force II |
| 9 | Iron defender |
| 10 | Steel scimitar, Steel armour set |
| 11 | Steel dagger, Steel longsword |
| 12 | Steel battleaxe, Steel warhammer |
| 13 | Keen Focus III |
| 14 | Brute Force III |
| 15 | Cobalt scimitar, Cobalt armour set |
| 16 | Cobalt dagger, Cobalt longsword |
| 17 | Cobalt battleaxe, Cobalt warhammer |
| 18 | Cobalt defender |
| 19 | Whip |
| 20 | Orichalcum scimitar, Orichalcum armour set |
| 21 | Orichalcum dagger, Orichalcum longsword |
| 22 | Orichalcum battleaxe, Orichalcum warhammer |
| 23 | Gallantry prayer |
| 24 | Stone Maul |
| 25 | Berserker Plate set (+strength, lower defence) |
| 26 | Orichalcum defender |
| 27 | Warrior's Ring (+strength) |
| 28 | Starmetal scimitar (first tiered melee weapon with a special), Starmetal armour set |
| 29 | Starmetal dagger, Starmetal longsword |
| 30 | Starmetal battleaxe, Starmetal warhammer |
| 31 | Valor prayer |
| 32 | Greatblade |
| 33 | Bulwark Plate set (highest defence, lower prayer bonus, faster run drain) |
| 34 | Starmetal defender |
| 35 | Claws |
| 36 | Wyrmforged scimitar, Wyrmforged armour set |
| 37 | Wyrmforged dagger, Wyrmforged longsword |
| 38 | Wyrmforged battleaxe, Wyrmforged warhammer |
| 39 | Wyrmforged defender, Duelist's Plate set (+attack, lower defence) |
| 40 | Void Blade, Melee cape (cosmetic) |

The Whip at 19 and the Stone Maul at 24 give melee players a special attack before the Starmetal tier.

### Ranged unlocks

Each ammo tier matches its bow tier. Enchanted bolts are ammo types for any crossbow. Sidegrade sets appear at 25, 33 and 39.

| Ranged level | Unlocks |
| --- | --- |
| 1 | Oak shortbow, Bronze arrows, Leather armour set, Sharp Sight I |
| 2 | Oak longbow |
| 3 | Bronze throwing knives |
| 4 | Bronze crossbow, Bronze bolts |
| 5 | Willow shortbow and longbow, Iron arrows, Hardleather armour set |
| 6 | Iron throwing knives |
| 7 | Iron crossbow, Iron bolts, Sharp Sight II |
| 8 | Ranger's Boots (+ranged accuracy) |
| 9 | Archer's Quiver (cape slot, +ranged strength) |
| 10 | Maple shortbow and longbow, Steel arrows, Studded armour set |
| 11 | Steel throwing knives |
| 12 | Steel crossbow, Steel bolts |
| 13 | Sharp Sight III |
| 14 | Archer's Ring (+ranged accuracy) |
| 15 | Yew shortbow and longbow, Cobalt arrows, Drakehide armour set |
| 16 | Cobalt throwing knives |
| 17 | Cobalt crossbow, Cobalt bolts |
| 18 | Diamond-tipped bolts (10% chance to ignore some Defence) |
| 19 | Javelins (first ranged special) |
| 20 | Elder shortbow and longbow, Orichalcum arrows, Basilisk hide armour set |
| 21 | Orichalcum throwing knives |
| 22 | Orichalcum crossbow, Orichalcum bolts |
| 23 | Dragonfire bolts (6% chance of a fire burst) |
| 24 | Eagle-eye Coif (helm, +ranged accuracy) |
| 25 | Armoured Hide set (more defence, lower ranged accuracy) |
| 26 | Onyx bolts (11% chance to heal 25% of damage dealt) |
| 27 | Fletcher's Pouch (cape upgrade: +ranged strength, recovers some ammo) |
| 28 | Starwood shortbow and longbow (Twin Shot special), Starmetal arrows, Starhide armour set |
| 29 | Starmetal throwing knives (Fan special) |
| 30 | Starmetal crossbow (Pinning Bolt special), Starmetal bolts |
| 31 | Precision prayer |
| 32 | Duskbow |
| 33 | Tracker's Leathers set (+ranged strength, lower defence) |
| 34 | Archer's Buckler (off-hand shield for one-handed crossbows and knives) |
| 35 | Heavy Ballista |
| 36 | Wyrmwood shortbow and longbow, Wyrmforged arrows, Wyrmhide armour set |
| 37 | Wyrmforged throwing knives |
| 38 | Wyrmforged crossbow, Wyrmforged bolts |
| 39 | Skirmisher's Hide set (slower run drain, lower defence) |
| 40 | Sunfire Crossbow, Ranged cape (cosmetic) |

### Magic unlocks

Staffs follow the robe tiers; wands start at tier 3. Tomes are off-hand items that add magic damage. Sidegrade sets appear at 25, 33 and 39.

| Magic level | Unlocks |
| --- | --- |
| 1 | Novice staff, Woven robes set, Ember Dart, Arcane Will I |
| 2 | Root |
| 3 | Ember Bolt |
| 4 | Wizard Boots (+magic accuracy) |
| 5 | Apprentice staff, Apprentice robes set |
| 6 | Ember Blast |
| 7 | Arcane Will II |
| 8 | Thorn Snare |
| 9 | Spellcaster's Ring (+magic accuracy) |
| 10 | Adept staff, Adept wand, Adept robes set |
| 11 | Forbidden Staff, the Forbidden spellbook, Frost Shard |
| 12 | Ember Wave |
| 13 | Arcane Will III |
| 14 | Frost Nova |
| 15 | Warlock staff, Warlock wand, Warlock robes set |
| 16 | Novice Tome (off-hand, +1% magic damage) |
| 17 | Bramble Grasp |
| 18 | Miasma Storm |
| 19 | Mage's Mantle (cape slot, +magic accuracy) |
| 20 | Archmage staff, Archmage wand, Archmage robes set |
| 21 | Frost Spear |
| 22 | Arcane Tome (off-hand, +2% magic damage) |
| 23 | Leech Bolt |
| 24 | Ember Surge |
| 25 | Warded Robes set (more defence, no magic damage bonus) |
| 26 | Gloom Storm |
| 27 | Storm Amulet (+2% magic damage) |
| 28 | Starstaff, Star wand, Starweave robes set |
| 29 | Frostbound Charm (ring: freezes last 1 s longer, lower magic accuracy) |
| 30 | Glacial Storm |
| 31 | Insight prayer |
| 32 | Leech Storm |
| 33 | Sorcerer's Robes set (+5% magic damage, lower defence) |
| 34 | Starbound Tome (off-hand, +3% magic damage) |
| 35 | Wyrm-eye Amulet (+magic accuracy, +3% magic damage) |
| 36 | Wyrmbone staff, Wyrmbone wand, Wyrmweave robes set |
| 37 | Eruption Staff (first magic special) |
| 38 | Wyrmbone Tome (off-hand, +4% magic damage) |
| 39 | Battlemage Robes set (more melee defence, lower magic accuracy) |
| 40 | Tempest Staff, Magic cape (cosmetic) |

Magic gets its first special attack late, at 37. It makes up for this with freezes from level 2 and healing spells from 23.

### Shared unlocks (combat level)

Shared rewards work for every style, so they come from combat level. Protection prayers and kill streaks are available from the start because PvP doesn't work without them.

| Combat level | Unlocks |
| --- | --- |
| 1 | Ward of Blades, Arrows and Spells; main food; Extra Rations, Rebuke and Unbound perks; kill streak rewards |
| 2 | Stone Skin I |
| 3 | Combo food; Iron Will perk |
| 4 | Create-a-class with 2 custom slots |
| 5 | Brew and restore potions; Mending |
| 6 | Extra Brew perk |
| 7 | Stone Skin II |
| 8 | Combat potions (each life starts boosted); Fleet Foot perk |
| 9 | Spell Satchel perk |
| 10 | Endurance |
| 11 | Quick Hands perk |
| 12 | Stone Skin III; 3rd custom class slot |
| 13 | Shadowstep perk |
| 14 | Sap |
| 15 | Antidote potions |
| 17 | Snare Trap perk |
| 18 | Antivenom perk |
| 20 | Ranked playlists; 4th custom class slot |
| 21 | Last Rites |
| 22 | Steady Hand perk |
| 25 | Reckoning |
| 28 | Eagle Sight perk |
| 30 | 5th custom class slot |
| 32 | Spare Spec perk |
| 34 | Second Wind perk |
| 36 | Devotion |
| 40 | Grandmaster title and banner |

## 8. Kill streak rewards

Copy CoD4's fixed 3 / 5 / 7 streaks. Kills in a row without dying earn a reward that you trigger with a hotkey when you choose. Kills made by streak rewards don't count toward the next streak, the same rule as CoD4.

| Kills | Reward | Effect | CoD4 equivalent |
| --- | --- | --- | --- |
| 3 | Scrying Orb | Every enemy shows on your team's minimap for 30 s, except players with Shadowstep | UAV |
| 5 | Meteor Strike | Pick a 5 × 5 area; after a 3-tick warning that both teams can see, it hits everyone inside for 15–30 typeless damage | Airstrike |
| 7 | Summoned Guardian | A guardian NPC spawns beside you for 45 s and attacks enemies with magic. It has 150 HP and can be killed (+100 XP) | Attack helicopter |

- Streak rewards are disabled in Duel, Last Stand and ranked playlists.
- Streaks reset on death. An unused reward is kept until you use it or the match ends.
- Later: let players pick their three streaks from a larger pool, as later CoD games did.

## 9. Challenges

There are three kinds of challenges. Shared challenges can be done with any style, and their XP is split across all three. Style challenges belong to Melee, Ranged or Magic, and their XP goes to that style. Weapon challenges unlock mods (CoD4's attachments) and ornament kits (CoD4's camos). All challenges track across matches and survive prestige.

### Shared challenges

| Challenge | Requirement | Reward |
| --- | --- | --- |
| First Blood | Get the first kill of a match | 250 XP |
| Flick Master | Block 500 hits with the correct Ward prayer | 2,500 XP + banner |
| Spec Knockout | Kill an enemy from full HP with one special-attack bar | 1,500 XP |
| Brew Down | Get a kill while below 10 HP | 1,000 XP |
| Pile Breaker | Kill an enemy who has Rebuke active without triggering it | 1,500 XP |
| Sap King | Drain 1,000 enemy prayer points with Sap | 2,500 XP + title |
| Untouchable | Win a match without dying (minimum 10 kills) | 5,000 XP + banner |
| Comeback | Win a round-based match after trailing 0–3 | 3,000 XP + title |
| Ritual Runner | Deliver the ritual rune 25 times | 2,500 XP + banner |
| Obelisk Keeper | Capture 100 obelisks | 2,500 XP + banner |
| Guardian Slayer | Kill 10 Summoned Guardians | 1,500 XP |
| Hat Trick | Earn all three kill streak rewards in one life | 3,000 XP + banner |
| Tribrid | Kill one enemy each with melee, ranged and magic in a single life | 1,000 XP |
| Hybrid Master | Complete 5 style challenges in each of the three styles | 10,000 XP + title |

### Melee challenges

| Challenge | Requirement | Reward |
| --- | --- | --- |
| Brawler | 500 melee kills | 5,000 Melee XP + title |
| Rampage | 3 melee kills within 10 seconds | 2,500 Melee XP + banner |
| Armour Breaker | Land 50 Defence-lowering warhammer specials | 2,000 Melee XP |
| Close Quarters | Kill 25 enemies who were frozen next to you | 1,500 Melee XP |
| Double Maul | Land two Stone Maul specials in the same tick 25 times | 2,000 Melee XP |
| Bloodied | Get a melee kill after taking 150+ damage in that life | 1,000 Melee XP |

### Ranged challenges

| Challenge | Requirement | Reward |
| --- | --- | --- |
| Marksman | 500 ranged kills | 5,000 Ranged XP + title |
| Long Shot | 50 kills from 9 or more tiles away | 2,500 Ranged XP + banner |
| Kiter | Kill 25 melee users without them hitting you | 2,500 Ranged XP |
| Bolt Storm | Trigger 100 enchanted bolt effects | 1,500 Ranged XP |
| Double Tap | Land both Duskbow arrows for 40+ total damage, 10 times | 2,000 Ranged XP |
| Pinned Down | Kill 25 enemies frozen by your Pinning Bolt | 1,500 Ranged XP |

### Magic challenges

| Challenge | Requirement | Reward |
| --- | --- | --- |
| Archmage | 500 magic kills | 5,000 Magic XP + title |
| Ice Cold | Freeze 250 enemies | 2,500 Magic XP + banner |
| Crowd Control | Freeze 3 enemies with one storm spell, 10 times | 2,500 Magic XP |
| Lifeleech | Heal 2,000 HP with Leech spells | 2,000 Magic XP |
| Miasma | Poison 100 enemies | 1,000 Magic XP |
| Frozen Solid | Kill 25 enemies while they are frozen | 1,500 Magic XP |

### Weapon challenges

Every weapon type has the same ladder. Progress counts across all tiers of a type, so kills with a Bronze dagger and a Wyrmforged dagger both count toward Dagger. For Magic, staffs and wands are weapon types, and so is each spell family (Ember, Frost, Leech, Storm and binding spells). XP goes to the weapon's style.

| Step | Requirement (per weapon type) | Reward | XP |
| --- | --- | --- | --- |
| Marksman I | 25 kills | Mod 1 | 500 |
| Marksman II | 75 kills | Mod 2 | 1,000 |
| Marksman III | 150 kills | Mod 3 | 2,000 |
| Expert I | 25 special-attack kills (or 25 max hits for types with no special) | Bronze trim kit | 1,000 |
| Expert II | 10 kills where the target died within 2 ticks of your first hit | Gilded kit | 2,500 |
| Expert III | 5 kills in one life with this weapon type | Shadow kit | 5,000 |
| Master | Every step above on every weapon type of one style | Elite kit for that style's weapons + a title | 5,000 |

Ornament kits are cosmetic recolours, as in OSRS. A kit applies to every tier of its weapon type.

### Weapon mods

A class can fit one mod to its primary weapon. Mods are sidegrades: each gains something and gives something up.

| Weapon type | Mod 1 | Mod 2 | Mod 3 |
| --- | --- | --- | --- |
| Melee weapons | Honed Edge: +accuracy, −strength | Weighted Pommel: +strength, −accuracy | Wrapped Hilt: specials cost 5% less energy, −strength |
| Bows and knives | Waxed String: +accuracy, −ranged strength | Heavy Draw: +ranged strength, −accuracy | Quiver Strap: +1 tile range, −accuracy |
| Crossbows | Light Stock: +1 tile range, −ranged strength | Heavy Limbs: +ranged strength, −accuracy | Bolt Rack: enchanted bolt effects trigger 2% more often, −accuracy |
| Staffs, wands and spell families | Focus Orb: +magic accuracy, −defence | Ember Codex: +10% Ember spell damage, Forbidden spells cost more runes | Spell Lens: +1 tile range, −magic accuracy |

Add daily and weekly challenges after launch; they are cheap to build once the challenge system exists.

## 10. UI, art and audio

The in-match screen should look like OSRS so PvPers feel at home. The CoD layer (score, kill feed, XP pop-ups) sits on top.

### In-match HUD

- **Top right (OSRS):** minimap with teammates as blue dots and known enemies as red dots, plus the HP, prayer, run energy and special attack orbs.
- **Bottom right (OSRS):** side panel with Inventory, Equipment, Prayer and Spellbook tabs. F-keys switch tabs.
- **Top centre (CoD):** team scores, match timer, and objective status (obelisk owners, rune carrier).
- **Top left (CoD):** kill feed showing killer, weapon icon and victim.
- **Centre (CoD):** "+100" XP pop-ups, hit markers, and streak-ready prompts.
- **Over each player (OSRS):** hitsplats, HP bar, overhead prayer icon, and a freeze icon while frozen.
- **Bottom left:** team chat and quick-chat commands ("Freeze them", "Spec now", "Falling back").

### Menus

- Main menu → Play (playlists), Barracks (create-a-class, challenges, prestige, stats), Options.
- End-of-match screen: scoreboard (kills, deaths, assists, damage, objective score), then the XP breakdown with a level-up banner for each style that levelled and its new unlocks.
- Options include tick-sound toggle, hotkey binding, minimap size and colour-blind palettes.

### Art direction

- Low-poly, flat-shaded, small textures. It should read like OSRS at a glance and be cheap to produce.
- Characters: one humanoid rig shared by every character, about 1,000–2,000 triangles, with armour sets as swappable meshes. Gear must be readable from across the screen.
- Start with placeholders (coloured capsules and boxes) through the first playable build. Replace them only once combat feels right.
- Pipeline: model in Blender → export glTF (.glb) → load in the client. Animations needed per weapon type: idle, walk, run, attack, special attack, block, cast, eat, death.

### Audio

- Short, punchy sounds for each hit type, prayer toggle, freeze, special attack and eating. In OSRS sound tells you what happened before you see it.
- An optional tick metronome for practising prayer switches.
- Music: one ambient track per map, plus a short lobby theme.

## 11. Technical architecture

Build it as a browser game in TypeScript, with a Node server that owns every tick. This stack suits the project for three reasons. Claude Code is very strong in TypeScript. A browser link is the easiest demo to send to Jagex or testers. Your Blender models load directly as glTF.

```text
Browser client (TypeScript + Three.js)
  - sends clicks as intents
  - smooths tile movement between ticks
        |  intents (WebSocket) ->
        |  <- tick state each 600 ms
Game server (Node + Colyseus rooms)   <-- XP, unlocks -->   Database (SQLite -> PostgreSQL)
  - authoritative 600 ms tick                                 - accounts, levels, unlocks, challenges
  - modes, spawns, bots
Both client and server import:
Shared package (combat formulas, tick rules, data tables from data/*.json)
```

The client never decides an outcome. It shows the state the server sends and smooths movement between ticks.

### Stack

| Part | Choice | Why |
| --- | --- | --- |
| Language | TypeScript everywhere | One language; shared code between client and server |
| Repo | Monorepo: `client/`, `server/`, `shared/`, `data/`, `docs/` | Rules written once and imported by both sides |
| Rendering | Three.js, built with Vite | Mature, well documented, loads .glb files |
| UI | HTML/CSS overlay (Preact if it grows) | Menus and side panels are easier in HTML than in 3D |
| Networking | Colyseus over WebSockets | Rooms, matchmaking and state sync built in |
| Database | SQLite while prototyping, PostgreSQL when online | No setup at first, easy move later |
| Tests | Vitest | Combat formulas must be unit-tested to match OSRS numbers |
| Maps | Tiled map editor, exported as JSON | Free and visual; tiles map straight onto the grid |

If you'd rather ship a desktop game, Godot 4 with C# also works and fits your C# background. The tick and data design stay the same; only the client changes.

### Data-driven content

Every weapon, spell, prayer, perk, level, challenge, map and mode is a JSON file in `data/`, checked against a schema at build time. Balance changes become data edits, not code edits. It also keeps each Claude Code prompt small.

### Networking model

1. The client sends intents only: walk to tile, attack player, equip item, toggle prayer, cast spell on target, eat item, use special.
2. The server queues intents and resolves them in the fixed tick order from section 2.
3. Each tick the server sends a compact state change list: positions, HP, overheads, equipment, hitsplats and projectiles.
4. The client animates movement between tiles over the 600 ms window. Because a tick is 600 ms long, ordinary internet latency is mostly hidden, as in OSRS.
5. Server-side checks reject impossible intents, such as equipping an item you don't have or attacking out of range.

## 12. Build roadmap and Claude Code prompts

Build in 12 milestones, and get the 1v1 fight feeling right before adding anything CoD-like. A tick-combat game that feels wrong can't be saved by progression. Each milestone below has a goal, a "done when" test you can check yourself, and a starter prompt to paste into Claude Code.

### How to work with Claude Code

- Export this doc as Markdown and save it in the repo as `docs/GDD.md`. Every prompt tells Claude Code to read the relevant section first.
- One milestone per session. Start with "Plan this first and show me the plan before writing code", then approve the plan.
- At the end of each milestone, run the tests, play it yourself, and commit before starting the next one.
- When something feels off in play, describe the feeling and an OSRS comparison ("eating should delay my next attack like a shark does"). That works better than guessing at code.
- If you change a design decision, update `docs/GDD.md` first, then ask Claude Code to bring the code in line with it.

### M0 — Project setup

Done when: `npm run dev` opens an empty 3D scene in the browser and `npm test` passes.

```text
Read docs/GDD.md, section "Technical architecture". Set up a TypeScript monorepo with client/ (Vite + Three.js), server/ (Node + Colyseus), shared/, data/ and docs/. Add Vitest, ESLint and Prettier, and npm scripts for dev, test and build. Write a CLAUDE.md that says: the server is authoritative on a 600 ms tick; game rules live in shared/; content lives in data/*.json validated by schemas; never put game rules in client code. Don't build any gameplay yet. Plan first and show me the plan.
```

### M1 — Tick loop and movement

Done when: two browser tabs show two players walking and running on a 32 × 32 test grid, in sync.

```text
Read docs/GDD.md sections "Core combat > The tick" and "Movement". Implement the server's 600 ms tick loop with the fixed processing order, OSRS-style BFS pathfinding on a tile grid, walk (1 tile/tick) and run (2 tiles/tick) with run energy. The client renders the grid, players as capsules, click-to-move, and smooths movement between ticks. Put pathfinding in shared/ with unit tests.
```

### M2 — Melee combat

Done when: two players can fight with scimitars until one dies and respawns. Unit tests confirm the accuracy and max-hit formulas against known OSRS examples.

```text
Read docs/GDD.md sections "Stats", "Combat triangle" and "Accuracy and damage". Implement the OSRS accuracy and melee max-hit formulas in shared/combat with unit tests. Add equipment bonuses from data/items.json, attack speed in ticks, attack range, hitsplats, HP bars, death and a 5-second respawn. Start with the Bronze scimitar and Bronze armour set only.
```

### M3 — Ranged, magic, line of sight and freezes

Done when: a mage can freeze a warrior and kite them behind a pillar, and projectiles land on the correct delayed tick.

```text
Read docs/GDD.md sections "Core combat" and "Weapons, spells and prayers > Spells". Add ranged and magic attacks with projectile travel delay, line-of-sight checks against map walls, the Elemental and Forbidden spellbooks from data/spells.json, freezes with 5-second freeze immunity, and poison. Add the Oak shortbow, Bronze crossbow, Novice staff and Forbidden Staff.
```

### M4 — Inventory, switching, supplies and prayers

Done when: you can do a full hybrid gear switch in one tick, eat a shark + karambwan combo, and protection prayers cut matching damage by 40%.

```text
Read docs/GDD.md sections "Prayers in combat", "Gear switching and inventory" and "Food and potions". Build the 28-slot inventory, 11 equipment slots, equips resolving at the start of the next tick (max 8 per tick), food with attack delay and combo eating, brews and restores, and the prayer system with drain from data/prayers.json. Add an OSRS-style side panel with Inventory, Equipment, Prayer and Spellbook tabs plus F-key switching.
```

### M5 — Special attacks, duel bot and balance simulator

Done when: you can lose a fair fight to a bot, and the simulator prints win rates for every pair of default classes.

```text
Read docs/GDD.md sections "Special attacks", "Bots" and "Weapons". Add special attack energy and every weapon special from data/weapons.json. Build a duel bot that keeps the right overhead, eats below 40 HP and specs when the target is low. Then write a headless balance simulator script that runs 10,000 bot-vs-bot duels per loadout pair using the shared combat code and prints win rates and average damage per tick, both within a gear tier and one tier apart.
```

### M6 — Match flow and Clan Clash

Done when: a full 5v5 Clan Clash match runs from lobby to scoreboard, with bots filling empty slots.

```text
Read docs/GDD.md section "Match structure and game modes". Build the lobby, class select, pre-match countdown, Clan Clash (team deathmatch) rules, spawn selection away from enemies, spawn shield, kill feed, team scores and timer, the end-of-match scoreboard, and bots that fill empty slots. Keep mode rules in data/modes.json so new modes are mostly data.
```

### M7 — Real maps and the minimap

Done when: Frostgate Ruins loads from a Tiled export with working spawns, cover and a minimap.

```text
Read docs/GDD.md section "Maps". Load maps exported from the Tiled editor as JSON: walkable tiles, walls that block line of sight, spawn zones and objective points. Build Frostgate Ruins as the first map with placeholder geometry, and add the OSRS-style minimap with teammates and visible enemies.
```

### M8 — Accounts, style levels and create-a-class

Done when: finishing a match awards XP, XP goes to the right style, level-ups show their unlocks, and create-a-class appears at combat level 4.

```text
Read docs/GDD.md sections "Progression" and "Loadouts and perks". Add simple accounts (username + password, SQLite). Track separate Melee, Ranged and Magic levels with XP routed to the style that earned it, plus combat level and titles, using the curve in data/levels.json. Generate unlocks.json from the per-level tables in section 7 and lock gear, spells and prayers until unlocked. Add the XP breakdown and level-up screens, the four auto-upgrading default classes, the create-a-class editor with 2–5 custom slots, all perks, and combat-level matchmaking.
```

### M9 — Challenges, mods, ornament kits and kill streaks

Done when: challenge progress tracks across matches, a weapon mod unlocks at 25 kills, and the 3 / 5 / 7 streak rewards work.

```text
Read docs/GDD.md sections "Challenges" and "Kill streak rewards". Build an event-driven challenge tracker for shared, style and weapon challenges that reads definitions from data/challenges.json, weapon mods and ornament kits (as material colour swaps), banners and titles, and the Scrying Orb, Meteor Strike and Summoned Guardian streak rewards.
```

### M10 — Remaining modes, maps and prestige

Done when: all eight modes and four maps are playable, and prestiging one style resets only that style.

```text
Read docs/GDD.md sections "Modes", "Maps" and "Prestige". Add Free-for-All, Obelisks, Rune Ritual, Hold the Banner, Last Stand, Duel and Pure Brawl, the remaining three maps, private matches with custom rules, the Even Ground playlist, and per-style prestige with emblems and capes.
```

### M11 — Art, audio and the pitch build

Done when: the game has real models, sound, a hosted demo link and a 2-minute gameplay video.

```text
Read docs/GDD.md section "UI, art and audio". Replace placeholders with the .glb models in client/assets, wire up animations per weapon type, add sound effects and music, and deploy the client and server to a hosted demo. Add a spectator camera for recording gameplay footage.
```

## 13. Jagex pitch, IP and open questions

Build Wildfront as an original game that plays like OSRS, not as an OSRS fan game. Jagex's Fan Content Policy says you can't make any video game content using Jagex Property (clause 6.1.3). It also bars content that could compete with Jagex products (6.1.4) and commercial use of generative-AI items (5.4, 6.1.8). I'm not a lawyer; this is a summary of the published policy, so read it in full before you share anything.

### IP rules for the build

- Use original names, art, maps, sounds and music. Never copy OSRS models, sprites, sounds, music or game data.
- Game mechanics are fair to borrow. Tick timing, accuracy formulas and the combat triangle describe how the game plays; they aren't the game's art or text.
- Keep the OSRS analogue columns out of the game itself. They exist to show Jagex how each system maps onto OSRS.
- Keep it free and non-commercial. That avoids any question of competing with Jagex or selling AI-made work.
- Don't imply Jagex endorses the project. Call it "inspired by" OSRS on any page or video.

### How to pitch it

Many studios won't read unsolicited game ideas, because of disputes over idea theft. I couldn't find a published Jagex policy on this either way. The safer route is public: show it to the OSRS community, and let Jagex see the interest.

1. Finish the pitch build (M11): a hosted demo link and a 2-minute gameplay video.
2. Post it publicly: r/2007scape, the official OSRS Discord, and YouTube. Frame it as "what if OSRS had a CoD-style PvP minigame".
3. Explain what's new compared with OSRS's existing PvP minigames such as Last Man Standing and PvP Arena: separate Melee, Ranged and Magic levels with unlocks at every level, create-a-class, objective round modes and weapon challenges.
4. Show it fits OSRS's rules for minigames: rewards are cosmetic only and nothing touches the main-game economy. Players care about this most.
5. For anything about licensing or IP, Jagex's contact page lists ip@jagex.com.

### Open questions

- [ ] Final title. Wildfront is a placeholder.
- [ ] Allow one-key gear-switch hotkeys, or keep switching to clicks only, as in OSRS?
- [ ] Accounts: email sign-up, or guest play with an optional account?
- [ ] Art source: your own Blender models, AI-generated models, or a mix?
- [ ] Should a future OSRS version reward anything in the main game (for example, a cosmetic cape)?

### Sources

- [Jagex Fan Content Policy](https://legal.jagex.com/docs/policies/fan-content-policy)
- [Jagex legal contact page](https://legal.jagex.com/docs/contact-us)
- [The measures game developers take to avoid unsolicited ideas — Automaton](https://automaton-media.com/en/?p=8496)
