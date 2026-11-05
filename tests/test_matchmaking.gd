extends TestCase
## U3 fair-start safeguards: combat-level window that widens with waiting, bots inside it, tier cap option A.


func test_window_widens_with_waiting() -> void:
	DB.ensure_loaded()
	var c := Matchmaker.cfg()
	eq(Matchmaker.window(0.0), int(c["window"]), "starts at the GDD's ~8 levels")
	eq(Matchmaker.window(float(c["widen_every_s"])), int(c["window"]) + int(c["widen_by"]), "widens after a wait")
	eq(Matchmaker.window(99999.0), int(c["max_window"]), "capped")


func test_lobbies_respect_the_window() -> void:
	DB.ensure_loaded()
	var q: Array = []
	for i in range(8):
		q.append({"id": "low%d" % i, "cl": 5 + i % 3, "wait_s": 0})
	for i in range(8):
		q.append({"id": "high%d" % i, "cl": 30 + i % 3, "wait_s": 0})
	var r := Matchmaker.form_lobbies(q, 4)
	eq((r["lobbies"] as Array).size(), 4, "four full lobbies")
	for lob in r["lobbies"]:
		var lows := (lob as Array).filter(func(id): return str(id).begins_with("low")).size()
		check(lows == 0 or lows == (lob as Array).size(), "no lobby mixes level ~6 with level ~31")


func test_long_wait_widens_into_a_match() -> void:
	DB.ensure_loaded()
	var q: Array = [{"id": "a", "cl": 10, "wait_s": 0}, {"id": "b", "cl": 22, "wait_s": 0}]
	eq((Matchmaker.form_lobbies(q, 2)["lobbies"] as Array).size(), 0, "12 levels apart: no match at first")
	q = [{"id": "a", "cl": 10, "wait_s": 20}, {"id": "b", "cl": 22, "wait_s": 20}]
	eq((Matchmaker.form_lobbies(q, 2)["lobbies"] as Array).size(), 1, "after waiting, they're matched")


func test_bots_are_inside_the_window() -> void:
	DB.ensure_loaded()
	for seed in range(5):
		var core := MatchServerCore.new()
		core.setup({"mode": "clan_clash", "map": "frostgate_ruins", "seed": seed, "pre_ticks": 1,
			"player": {"name": "P", "class_def": DB.classes["defaults"]["warrior"], "levels": {"melee": 12, "ranged": 25, "magic": 3}}})
		var me := core.sim.get_fighter(core.player_id)
		for f in core.sim.fighters.values():
			check(absi((f as Fighter).combat_level - me.combat_level) <= Matchmaker.window(0.0), "bot within the window")


## Owner decision: tier cap option A (no cap). A low-level player keeps their own gear next to a high-level one.
func test_no_tier_cap_in_standard() -> void:
	DB.ensure_loaded()
	var core := MatchServerCore.new()
	core.setup({"mode": "duel", "map": "castle_courtyard", "seed": 2, "pre_ticks": 1, "private": {"bots": false}, "players": [
		{"name": "New", "class_def": DB.classes["defaults"]["warrior"], "levels": {"melee": 1, "ranged": 1, "magic": 1}, "peer": 1},
		{"name": "Vet", "class_def": DB.classes["defaults"]["warrior"], "levels": {"melee": 40, "ranged": 40, "magic": 40}, "peer": 2}]})
	var tiers: Array = []
	for f in core.sim.fighters.values():
		tiers.append(Matchmaker.gear_tier((f as Fighter).equipment))
	check(float(tiers.min()) < 2.0 and float(tiers.max()) > 6.0, "gear isn't scaled down (tiers %s)" % str(tiers))
	var snap := core.sim.snapshot(core.player_id)
	check((snap["fighters"][0] as Dictionary).has("gear_tier"), "the loading screen gets every player's gear tier")
