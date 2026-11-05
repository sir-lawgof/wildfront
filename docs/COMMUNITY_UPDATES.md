# Wildfront Community-Driven PvP Updates — instructions for Claude Code

Read this whole file, plus `docs/GDD.md` and `docs/DECISIONS.md`, before starting. It turns what the Old School RuneScape community and Jagex have said about PvP into a set of Wildfront updates. Research is current to November 2026. Sources are listed at the end.

Work the same way as the other docs:

- One update at a time (section 4), starting with **U0**.
- Show me a plan first and wait for approval.
- Run the tests.
- Don't make git commits.
- Log decisions in `docs/DECISIONS.md`.
- Every new number goes in `data/*.json` so it can be tuned without code.
- Anything marked **[Owner decision]** needs my answer before you build it. Ask me with the options and your recommendation.

Never use OSRS names, NPCs, places or items in the game. This file mentions them only as evidence.

## 1. What the community has said

### 1.1 PvP is hard to learn

- Jagex calls PvP "an iconic activity" and an "underserved segment" of the community. It also says players who only want PvP must engage with almost every other part of the game to get ready to fight, which puts newer players off.
- Jagex's 2024 PvP survey asked directly whether players understand PvP mechanics and why they do or don't take part.
- In October 2026 OSRS added its first proper PvP tutorial: an NPC teacher at a safe zone with drills for protection prayers, freezes, special attacks, gear switching and combo eating, then two fights against the teacher.
- The main feedback was that the **final fight was too hard** and players hadn't been told it was meant for people already PvP-ready. Jagex slowed the teacher's action delay after eating from 3 to 5 ticks and shortened his attack range. It also relabelled the challenges to separate "learning" from "aspirational".

### 1.2 Fairness matters more than anything

- In the Wilderness survey (30,064 responses):
  - 68% try to avoid the Wilderness, and only about 32% fight back when attacked.
  - About 75% would spend more time there if fights were fairer for solo players.
  - 88% think organised groups have too much advantage over solo players.
- Jagex's list of problems: skull-tricking, luring and scams, exploiting combat-area rules, using NPCs as shields, and **"PJing"** (jumping into someone else's fight to steal the kill).
- In March 2026 Jagex doubled the PvP-world PJ timer from 8 to 16 ticks, to stop bad actors PJing fights when both opponents eat at the same time.

### 1.3 Players want instant, even builds and set brackets

- OSRS's PvP Arena and Last Man Standing give everyone a preset build, so nobody has to grind gear first. Both use named brackets: **1 Defence Pure, Zerker and Max/Med**.
- Ranked play rotates the featured bracket every week.
- In March 2026 Jagex refreshed the starter kits and allowed-item lists to match the current meta, and raised bracket levels (Max/Med Defence to 85, Zerker Attack to 80).
- People asked for more modes. Jagex specifically noted a community idea for a **mode with no Protect Prayers**.

### 1.4 Rewards and polls are touchy

- Most respondents want rewards that come **from** PvP: 83% chose PvP-based rewards, ahead of best-in-slot gear at 39%. Players also said early PvP Arena reward points were too low.
- The first PvP Arena reward poll failed. Jagex found 80% of the "no" votes came from players with no PvP kills at all. Voters worried about skipping well-known grinds and getting gear without earning it.
- Jagex then set up an invite-only PvP feedback Discord with community representatives, to test changes before polling.

### 1.5 Experiments are welcome, if they're reversible

- Jagex once made protection prayers stronger in Last Man Standing as a trial. Some players liked it; others said it made games longer and widened the gap between new and veteran players. Jagex reverted it, thanked players for trying it, and floated a dedicated experimental mode.

### 1.6 Bots and cheating erode trust

- Players have shown that bots playing Last Man Standing could be baited with a simple chat prompt, and Jagex banned them.
- Bots in competitive modes are a sore point. Players need to know when they're facing a bot.

### 1.7 Watching and events are part of PvP culture

- Deadman: All-Stars and PvP tournaments are popular, and Jagex counts them as evidence that PvP is a core part of the game.
- 2026 brought creator events: a live PvP bootcamp where coaches trained new players, and a PvP "classic" tournament with well-known streamers.

### 1.8 Small quality-of-life fixes are noticed

- **Autocast:** in March 2026 Jagex made autocast settings persist through weapon swaps when you haven't attacked a player for 20 ticks.
- **Kits:** starter kits were made current, so first-time players don't start with outdated gear.

## 2. What this means for Wildfront

Wildfront already answers some of these points: matchmade rounds, bots that fill slots, an Even Ground playlist, a Pure Brawl playlist, a tick metronome option, and leaving counts as a loss. The rest are gaps:

| Community point | Wildfront today (from code and DECISIONS.md) | Update |
| --- | --- | --- |
| Hard to learn; tutorial final fight was too hard | No tutorial or practice area; only the metronome option | U1, U6 |
| Players want to know why they died | Post-match stats only (kills, deaths, assists, damage, streak) | U6 |
| Named brackets (Pure, Zerker, Max/Med) with a weekly rotation | Playlists: Standard, Even Ground, Pure Brawl | U2 |
| "Skip the grind" vs "earn it": gear can't decide fights | Gear gets stronger with level; casual matchmaking only for bots (±3 levels) | U3 |
| Ranked play with fair rewards | Not built (GDD lists it for later) | U4 |
| Third-party kill stealing, leavers, AFK, bot trust | Spawn shield, leaving counts as a loss; nothing for third-party fights or AFK; bots aren't clearly labelled | U5 |
| Experimental modes (no protection prayers) | None | U7 |
| Watching, replays, tournaments | Not built (spectator camera planned in M11; private matches not built) | U8 |
| Meta stays current; changes are visible | Balance simulator exists; no in-game patch notes | U9 |
| Small quality-of-life fixes | Autocast exists; not remembered per weapon; no presets or quick rematch | U10 |
| Testing changes with real PvPers before release | No feedback or telemetry tools | U11 |

## 3. Design principles from the research

1. **Skill decides fights, not grind.** Ranked and competitive play use fixed bracket kits. Unlocks stay a casual and cosmetic reward loop.
2. **Teach, then test.** Every mechanic gets a drill before players face it in a real match. Practice content is clearly labelled as "learning" or "aspirational", and its difficulty is tunable data, not code.
3. **Fair fights by default.** No kill stealing, no free kills on AFK players, no unlabelled bots, no exploits around protected states.
4. **Rewards are earned through PvP and are cosmetic.** Show earn rates openly and make them generous enough to feel worth it.
5. **Experiment safely.** Big rule changes ship first as opt-in experimental playlists, with data and feedback collected before any becomes standard.
6. **Pitch-ready.** Everything stays inside the minigame, with no effect on any main-game economy. That's the concern behind failed OSRS PvP polls.

## 4. Updates

### U0 — Audit

Done when: you've given me a short report and I've approved the order of U1–U11.

Confirm the "Wildfront today" column against the current code, and correct anything that has changed. Estimate effort for each update and flag dependencies, for example: U4 needs online play to be meaningful; U8 replays need a deterministic simulation. List the **[Owner decision]** questions. Don't change any code yet.

### U1 — Proving Grounds: a PvP tutorial and practice area

Community basis: 1.1 and 1.6.

- A safe, gear-free practice area, reached from the main menu. On first launch, offer it to new players once.
- An original instructor character; name and look are up to you, but not based on any OSRS character.
- **Drills**, one mechanic each, against scripted bot opponents that use the existing `BotBrain` with data-driven settings:
  1. **Wards:** switch protection prayers to match a bot that changes style every few attacks.
  2. **Freezes:** freeze a fleeing bot; escape freeze range when you're the target.
  3. **Special attacks:** spec a bot below a threshold; stack a special on a frozen target.
  4. **Gear switching:** complete a hybrid switch in one tick using clicks or hotkeys.
  5. **Combo eating:** survive a burst by eating main food, then combo food, then a brew in the right ticks.
  6. **Reading the enemy:** call out the bot's weapon style before its attack lands.
- **Two exam fights.** The *Graduation* fight is labelled "learning", fair and beatable. The *Instructor's Challenge* is labelled "aspirational" and plays like a skilled player. Bot settings live in `data/training.json`: reaction delay in ticks, eat delay, how often it fakes a switch, special-attack logic, attack range.
  - Start the Graduation bot at a 5-tick delay after eating (the value Jagex settled on) and tune it with the balance simulator, so a player who passed the drills wins about 70% of the time.
- **Training dummy room:** hit a dummy and see live accuracy, max hit and damage per tick for your current loadout and prayer. It reuses the shared combat formulas, so it always matches the real game.
- **Rewards:** a small amount of XP split across styles for each drill, plus a cosmetic cape trim for passing the Instructor's Challenge. No gear.
- **Done when:** every drill passes and fails as designed in tests, both exam fights work, and the Graduation pass rate in simulation is within 60–80%.

### U2 — Brackets and kits

Community basis: 1.3.

- Turn brackets into data (`data/brackets.json`): stat overrides, allowed armour classes and item tags, spellbook, and a starter kit per style.
- Ship three brackets that mirror the community's favourites with Wildfront's own names and numbers:
  - a **1-Defence** bracket (today's Pure Brawl rules);
  - a **mid-Defence** bracket;
  - a **maxed** bracket.

  [Owner decision] Choose the names and the stat values; propose options.
- **Starter kits** use Even Ground-style fixed gear per bracket, and are reviewed whenever the balance simulator flags a dominant kit.
- **Featured bracket:** one bracket is "featured" each week (date-based, deterministic) and used by ranked play in U4. Show it on the Play screen.
- Turn the Pure Brawl and Even Ground playlists into brackets, so there's one system instead of two.
- **Done when:** all brackets are playable in every mode they allow, the data validator checks them, and the balance simulator reports win rates per bracket and per class.

### U3 — Fair-start safeguards for casual play

Community basis: 1.2 and 1.4.

Gear unlocks are Wildfront's core progression loop, but the community has made it clear that gear shouldn't decide PvP. Keep the loop and limit its effect on fairness:

- **Combat-level matchmaking for humans**, not just bots: casual queues prefer lobbies within the bracket the GDD sets (about 8 combat levels). Widen it over time when the queue is slow, and show the range on screen.
- **Tier cap per lobby** [Owner decision]. Option A: no cap. Option B: in Standard casual, gear above a lobby cap (for example, the highest tier any human in the lobby has unlocked, minus 1) is scaled down to the cap. Option C: as B, but only for lobbies containing a player under combat level 15. Recommend one with reasons.
- Ranked and any competitive playlist always use bracket kits from U2, never personal unlocks.
- Show "Your gear: tier X, lobby average: tier Y" on the loading screen, so any gear gap is visible, not hidden.
- **Done when:** matchmaking tests show the level window working and widening, and the chosen tier-cap option is tested.

### U4 — Ranked and seasons

Community basis: 1.3 and 1.4.

- Ranked queues: **Duel** (1v1) and **Last Stand** (3v3), both using the featured bracket kits from U2.
- **Rating:** Glicko-2 or Elo with placement matches. Show a visible rank band (divisions) plus a hidden rating. Store it in the profile now; design it so a future online server can own it.
- **Seasons** of about 8 weeks: a soft reset at season start and cosmetic rewards by peak rank (cape trims, banners, titles).
- **Earn rates:** award ranked points per match, including on a loss, and show the expected points per hour on the ranked screen. Default values should get an average player to the mid-tier reward in about 15–20 hours per season. [Owner decision] Confirm the target.
- **Integrity:** detect repeated matches against the same opponent within a short window (possible win trading) and reduce the rating change. No rank decay for players who play at least a few matches per week.
- **Done when:** rating maths has unit tests, a full season can be simulated with bots, and rewards are granted correctly.

### U5 — Fair fights and trust

Community basis: 1.2 and 1.6.

- **Third-party protection in Free-for-All.** Add a data-driven **engagement timer** (default 16 ticks, matching the value Jagex chose). Once two players have exchanged hits, a third player can't attack either of them until the timer runs out with no hits between the pair. Make it a setting on the FFA mode, plus a "Brawl" FFA variant with it off, for players who like chaos.
- **Kill credit:** the kill goes to whoever dealt the most damage in the last 30 seconds, with assists for others. Check what `Sim` does now and align it.
- **AFK handling:** a player who sends no intents for 60 seconds (data) gets a warning. After 90 seconds a bot takes over, and the match counts as left. AFK players can't be farmed for challenge progress: no kills counted on a player flagged AFK.
- **Leavers:** keep "leaving counts as a loss". In ranked, add an escalating queue cooldown for repeated leaving.
- **Bot honesty:** bots always show a bot tag on their nameplate, the scoreboard and the kill feed. Kills on bots count toward XP but not toward ranked or any "human" challenges.
- **Exploit review:** list every protected state (spawn shield, round start, respawn, death animation, pre-match), and test that no attack, freeze, Snare Trap or Meteor Strike can affect a protected player.
- **Done when:** each rule has a simulation test, and a bot FFA match shows the timer working.

### U6 — Death recap and fight report

Community basis: 1.1. Teaching continues after the tutorial.

- **Death recap** (shown during the respawn wait):
  - who hit you, with what style and weapon, for how much, on which tick;
  - which ward you had up at each hit, with wrong-ward hits highlighted;
  - when you ate and how much healing was wasted.
- **Post-match fight report:**
  - your ward accuracy (% of incoming hits you prayed against correctly);
  - average reaction in ticks after an enemy's style change;
  - special attacks used vs available, freeze uptime, food left unused, and damage per tick by style.
- A **one-line tip** chosen from your weakest stat, for example "You prayed the wrong ward against 40% of ranged hits."
- All of this comes from events the server already knows. Make sure no hidden information leaks: only show what the player could have seen.
- **Done when:** the recap and report are correct in tests built from recorded matches.

### U7 — The Lab: an experimental playlist

Community basis: 1.3 and 1.5.

- A playlist with one weekly **mutator** from `data/mutators.json`. Each mutator is a set of rule overrides the simulation already reads, so no special-case code. Ideas from community requests and history:
  - **No Wards:** protection prayers disabled.
  - **Iron Wards:** protection prayers block more damage. This is the trial OSRS ran and reverted; we can measure it.
  - **Spec Frenzy:** double special energy regeneration.
  - **Frozen Front:** freezes last twice as long, magic only.
  - **Low Rations:** half food.
  - **One Life:** elimination rules in any mode.
- After each Lab match, a **one-tap vote** (keep, change, drop) plus the telemetry from U11. Show last week's results on the Play screen, so players see their votes matter.
- **Done when:** all six mutators work, are tested, and the vote is recorded.

### U8 — Spectating, replays and tournaments

Community basis: 1.7.

- **Replays.** The simulation is deterministic on a fixed tick, so a replay file can store the match setup and every tick's intents. Save the last 10 matches automatically and let players export one. Replay playback runs the simulation and renders it with the normal client, plus a timeline scrubber and a free camera. Test that a replay reproduces the original match exactly (same final state hash).
- **Spectator mode** for LAN and private matches: free camera, player cameras, an overlay with both teams' HP, prayer and special energy, and a kill feed.
- **Private matches with custom rules:** mode, map, bracket, mutators, time and score limits, bots on or off. The GDD lists this but it isn't built yet.
- **Tournament helper:** single-elimination and double-elimination brackets for private matches, with a results screen. Built for creator events and community nights.
- **Done when:** replays reproduce matches exactly, spectating works on LAN, and a 4-player single-elimination tournament runs start to finish.

### U9 — Keeping the meta current, in the open

Community basis: 1.3 and 1.8.

- **Balance simulator in the test suite:** fail the run if any class or bracket kit wins more than 60% of mirrored duels. Threshold in data.
- **In-game patch notes:** generated from a hand-written `data/patch_notes.json`, shown once after an update, with a "what changed for my class" filter.
- **Meta report** in the Barracks: win rate, pick rate and average time-to-kill per class and bracket, from local telemetry (U11).
- **Done when:** the balance check runs with the tests, and patch notes display correctly.

### U10 — Quality of life

Community basis: 1.8.

- Remember each staff's autocast spell, and restore it when switching back to that staff.
- Loadout presets: save and load gear switch sets per class and assign them to hotkeys. This extends the existing Z/X/C switch hotkeys.
- Quick rematch and "queue again" buttons on the end-of-match screen.
- Keep the tick metronome and add a visual tick indicator option.
- **Done when:** each feature has a test or manual checklist.

### U11 — Feedback and telemetry for playtests

Community basis: 1.4. This is how Jagex now tests PvP changes, and it's evidence for the pitch.

- **Local telemetry:** per-match JSON in `user://telemetry/` with mode, bracket, classes, match length, time-to-kill, ward accuracy, leavers and Lab votes. No personal data. It must be possible to switch it off in Options.
- An `export` button that zips telemetry for playtesters to send me.
- **Playtest build flag:** turns on a feedback button (free text plus a 1–5 rating) at the end of matches.
- A `tools/telemetry_report.gd` script that summarises exported files into a Markdown report I can put in the pitch.
- **Done when:** telemetry is written, can be switched off, exports, and the report script runs on sample data.

## 5. Pitch notes

These are the community and Jagex concerns this work answers, to use when presenting to Jagex:

- **"PvP is underserved and hard to get into."** Proving Grounds, death recaps and fight reports teach every mechanic. Bracket kits remove the gear grind for competitive play.
- **"Fights aren't fair."** Fixed kits in ranked, combat-level matchmaking, third-party protection and clearly labelled bots.
- **"PvP polls fail because they affect everyone."** Wildfront is self-contained: no main-game items, no economy impact, cosmetic rewards only.
- **"Test changes with real PvPers first."** The Lab, in-match voting and telemetry reports give evidence before anything becomes standard.

## 6. Sources

- [Wilderness Changes (OSRS Wiki copy of Jagex news post, with survey results)](https://oldschool.runescape.wiki/w/Update:Wilderness_Changes)
- [The PvP Arena: Poll Summary Blog](https://oldschool.runescape.wiki/w/Update:The_PvP_Arena:_Poll_Summary_Blog)
- [Improving PvP Feedback (PvP feedback Discord)](https://oldschool.runescape.wiki/w/Update%3AImproving_PvP_Feedback)
- [PvP Survey, Wrathmaw, Bounty Hunter Changes & More! (2024 PvP survey)](https://oldschool.runescape.wiki/w/Update:PvP_Survey,_Wrathmaw,_Bounty_Hunter_Changes_%26_More!)
- [Easter 2026 & PvP QoL Improvements](https://oldschool.runescape.wiki/w/Update:Easter_2026_&_PvP_QoL_Improvements)
- [Pete Kayer's Challenges (October 2026 PvP tutorial and feedback blog)](https://oldschool.runescape.wiki/w/Update:Pete_Kayer%27s_Challenges)
- [LMS Game Modes: Pures & Zerks (protection prayer trial and "no protect prayers" request)](https://oldschool.runescape.wiki/w/Update:LMS_Game_Modes:_Pures_%26_Zerks)
- [Old School Roadmap (29 May 2026)](https://oldschool.runescape.wiki/w/Update:Old_School_Roadmap_(29_May_2026))
- [Emir's Arena: Full Launch (reward points feedback)](https://www.runescapeguides.com/?p=9677)
- [Report on bots in Last Man Standing](https://tech.yahoo.com/gaming/articles/report-mmos-bot-problem-players-152759827.html)
