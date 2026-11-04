extends TestCase
## Challenge tracker (GDD 9) and multi-player server setup.


func test_counter_challenge_progress_and_completion() -> void:
	var progress := {}
	var completed: Array = []
	var ev: Array = [{"type": "first_blood"}, {"type": "kill", "style": "melee", "weapon_type": "scimitar", "tick": 10, "first_hit_tick": 9, "life_type_kills": 1}]
	var r := Challenges.process(ev, progress, completed, {"won": false, "deaths": 1, "kills": 1})
	check(completed.has("first_blood"), "First Blood completes")
	eq(int(progress.get("brawler", 0)), 1, "Brawler counts melee kills")
	check(int(r["xp"]["melee"]) + int(r["xp"]["ranged"]) + int(r["xp"]["magic"]) >= 250, "shared XP granted")
	# Same events again don't re-complete First Blood.
	var r2 := Challenges.process(ev, progress, completed, {"won": false, "deaths": 1, "kills": 1})
	eq(int(progress.get("brawler", 0)), 2, "progress accumulates across matches")
	for c in r2["completed"]:
		check(c["name"] != "First Blood", "no double completion")


func test_weapon_ladder_unlocks_mod_at_25_kills() -> void:
	var progress := {}
	var completed: Array = []
	var ev: Array = []
	for i in range(25):
		ev.append({"type": "kill", "style": "melee", "weapon_type": "scimitar", "tick": 100 + i * 20, "first_hit_tick": 100 + i * 20 - 10, "life_type_kills": 1})
	var r := Challenges.process(ev, progress, completed, {})
	check(completed.has("scimitar:marksman_1"), "Marksman I done")
	check((r["rewards"] as Array).has("mod:scimitar:1"), "mod 1 reward")
	eq(Challenges.mods_for("scimitar").size(), 3, "three melee mods")


func test_rampage_derived() -> void:
	var ev: Array = [
		{"type": "kill", "style": "melee", "tick": 10}, {"type": "kill", "style": "melee", "tick": 15}, {"type": "kill", "style": "melee", "tick": 22},
	]
	var d := Challenges.derive(ev, {})
	var found := false
	for e in d:
		if e["type"] == "rampage":
			found = true
	check(found, "3 melee kills within 10 s = rampage")


func test_two_humans_split_teams() -> void:
	var core := MatchServerCore.new()
	var unl_def: Dictionary = DB.classes["defaults"]["warrior"]
	core.setup({"mode": "clan_clash", "map": "castle_courtyard", "seed": 1, "pre_ticks": 1,
		"players": [{"name": "A", "class_def": unl_def, "levels": {"melee": 1, "ranged": 1, "magic": 1}, "peer": 1},
					{"name": "B", "class_def": unl_def, "levels": {"melee": 1, "ranged": 1, "magic": 1}, "peer": 77}]})
	eq(core.humans.size(), 2, "two humans")
	var fa := core.sim.get_fighter(core.peer_to_fid[1])
	var fb := core.sim.get_fighter(core.peer_to_fid[77])
	check(fa.team != fb.team, "humans on opposite teams")
	eq(core.sim.fighters.size(), 10, "bots fill to 5v5")
	core.submit(core.peer_to_fid[77], {"type": "run", "on": false})
	core.tick()
	check(not fb.running, "remote player's intent applied")
