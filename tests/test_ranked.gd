extends TestCase
## U4 ranked: Glicko-2 maths, ranks, points, win-trading guard, decay, a simulated season and rewards.


## Glickman's worked example: 1500/200/0.06 vs 1400/30 (win), 1550/100 (loss), 1700/300 (loss), tau 0.5.
func test_glicko2_matches_the_paper() -> void:
	DB.ensure_loaded()
	var r := Ranked.glicko2(1500.0, 200.0, 0.06, [
		{"rating": 1400.0, "rd": 30.0, "score": 1.0},
		{"rating": 1550.0, "rd": 100.0, "score": 0.0},
		{"rating": 1700.0, "rd": 300.0, "score": 0.0}], 0.5)
	near(float(r["rating"]), 1464.06, 0.05, "rating")
	near(float(r["rd"]), 151.52, 0.05, "RD")
	near(float(r["vol"]), 0.05999, 0.00001, "volatility")


func test_placements_ranks_and_points() -> void:
	DB.ensure_loaded()
	var s := Ranked.new_state(0)
	eq(Ranked.visible_rank(s), "Placement 0/%d" % int(DB.ranked["placement_matches"]), "placements hide the rank")
	var now := 1_800_000_000
	for i in range(int(DB.ranked["placement_matches"])):
		Ranked.apply_match(s, [{"id": "opp%d" % i, "rating": 1500.0, "rd": 100.0}], true, now + i * 7200)
	check(Ranked.placed(s), "placed after the placement matches")
	check(float(s["rating"]) > 1600.0, "five wins move the rating up a lot (high RD)")
	check(not Ranked.visible_rank(s).begins_with("Placement"), "a band is shown: %s" % Ranked.visible_rank(s))
	eq(int(s["points"]), 5 * int(DB.ranked["points"]["win"]), "points for wins")
	var before := int(s["points"])
	Ranked.apply_match(s, [{"id": "x", "rating": 1500.0, "rd": 100.0}], false, now + 99999)
	eq(int(s["points"]) - before, int(DB.ranked["points"]["loss"]), "points on a loss too")
	eq(str(Ranked.rank_for(1300.0)["label"]), "Bronze III", "band and division")
	eq(str(Ranked.rank_for(2500.0)["label"]), "Warden", "top band has no divisions")


func test_win_trading_is_dampened() -> void:
	DB.ensure_loaded()
	var s := Ranked.new_state(0)
	var now := 1_800_000_000
	var mults: Array = []
	for i in range(5):
		mults.append(float(Ranked.apply_match(s, [{"id": "friend", "rating": 1500.0, "rd": 80.0}], true, now + i * 300)["mult"]))
	eq(mults, [1.0, 1.0, 0.5, 0.25, 0.0], "repeat matches against one opponent count less and less")
	var fresh := Ranked.apply_match(s, [{"id": "stranger", "rating": 1500.0, "rd": 80.0}], true, now + 1500)
	eq(float(fresh["mult"]), 1.0, "a different opponent counts fully")
	var later := Ranked.apply_match(s, [{"id": "friend", "rating": 1500.0, "rd": 80.0}], true, now + 3 * 3600)
	eq(float(later["mult"]), 1.0, "the window expires")


func test_decay_only_for_inactive_players() -> void:
	DB.ensure_loaded()
	var now := 1_800_000_000
	var active := Ranked.new_state(0)
	var idle := Ranked.new_state(0)
	for s in [active, idle]:
		for i in range(6):
			Ranked.apply_match(s, [{"id": "o%d" % i, "rating": 1700.0, "rd": 60.0}], true, now + i * 7200)
	var week := 604800
	for i in range(3):
		Ranked.apply_match(active, [{"id": "w%d" % i, "rating": 1600.0, "rd": 60.0}], i % 2 == 0, now + week + i * 7200)
	var lost_active := Ranked.apply_decay(active, now + 2 * week + 10)
	var lost_idle := Ranked.apply_decay(idle, now + 2 * week + 10)
	eq(lost_active, 0.0, "3 matches last week: no decay")
	check(lost_idle > 0.0, "an idle week decays (%.0f)" % lost_idle)


## A full season: 40 bot players with hidden skill, matched by rating, 8 weeks. Ratings should sort players by
## skill, the average player should reach the mid reward in 8-12 hours, and rewards go out at the season end.
func test_simulated_season() -> void:
	DB.ensure_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var start := int(Time.get_unix_time_from_datetime_string(str(DB.ranked["season"]["epoch"]))) + 3600
	var players: Array = []
	for i in range(40):
		players.append({"id": "bot%d" % i, "skill": 1150.0 + i * 18.0, "s": Ranked.new_state(Ranked.season_of(start))})
	var weeks := int(DB.ranked["season"]["weeks"])
	var t := start
	for w in range(weeks):
		for rnd in range(12):
			players.sort_custom(func(a, b): return float(a["s"]["rating"]) < float(b["s"]["rating"]))
			for i in range(0, players.size() - 1, 2):
				var a: Dictionary = players[i]
				var b: Dictionary = players[i + 1]
				var p_a := 1.0 / (1.0 + pow(10.0, (float(b["skill"]) - float(a["skill"])) / 400.0))
				var a_won := rng.randf() < p_a
				var ra := {"id": a["id"], "rating": float(a["s"]["rating"]), "rd": float(a["s"]["rd"])}
				var rb := {"id": b["id"], "rating": float(b["s"]["rating"]), "rd": float(b["s"]["rd"])}
				Ranked.apply_match(a["s"], [rb], a_won, t)
				Ranked.apply_match(b["s"], [ra], not a_won, t)
			t += 4 * 3600
		t = start + (w + 1) * 604800
	players.sort_custom(func(a, b): return float(a["s"]["rating"]) < float(b["s"]["rating"]))
	var d2 := 0.0
	for i in range(players.size()):
		var skill_rank := int(str(players[i]["id"]).substr(3))
		d2 += pow(i - skill_rank, 2)
	var n := float(players.size())
	var spearman := 1.0 - 6.0 * d2 / (n * (n * n - 1.0))
	check(spearman > 0.8, "ratings sort players by skill (Spearman %.2f)" % spearman)
	var hours := float(Ranked.mid_reward()["points"]) / Ranked.points_per_hour(0.5)
	check(hours >= 8.0 and hours <= 12.0, "mid reward after %.1f hours (target 8-12)" % hours)
	var top: Dictionary = players[players.size() - 1]
	var rolled := Ranked.roll_season(top["s"], start + weeks * 604800 + 60)
	check(not (rolled["rewards"] as Array).is_empty(), "the top player gets peak rewards (%s)" % str(rolled["rewards"]))
	eq(int(top["s"]["points"]), 0, "points reset for the new season")
	var again := Ranked.roll_season(top["s"], start + weeks * 604800 + 120)
	eq((again["rewards"] as Array).size(), 0, "rewards are granted once")
	print("    season sim: Spearman %.2f, mid reward in %.1f h, top player rewards %s" % [spearman, hours, str(rolled["rewards"])])


## A ranked Duel through the real server: no bots, featured bracket kits, opponents' ratings in the summary.
func test_ranked_match_summary() -> void:
	DB.ensure_loaded()
	var cls: Dictionary = DB.classes["defaults"]["warrior"]
	var core := MatchServerCore.new()
	core.setup({"mode": "duel", "map": "castle_courtyard", "seed": 8, "pre_ticks": 1, "ranked": true, "playlist": Ranked.featured_playlist(),
		"private": {"bots": false}, "players": [
			{"name": "A", "class_def": cls, "levels": {"melee": 30, "ranged": 30, "magic": 30}, "peer": 1, "ranked": {"id": "pa", "rating": 1600.0, "rd": 80.0}},
			{"name": "B", "class_def": cls, "levels": {"melee": 30, "ranged": 30, "magic": 30}, "peer": 2, "ranked": {"id": "pb", "rating": 1450.0, "rd": 90.0}}]})
	eq(core.sim.fighters.size(), 2, "no bots in ranked")
	check(core.bracket() != "", "ranked uses bracket kits")
	for f in core.sim.fighters.values():
		core.bots[(f as Fighter).id] = BotBrain.new((f as Fighter).id, 0.7, 5)
	for i in range(4000):
		core.tick()
		if core.sim.phase == "over":
			break
	var s := core.summary(false, int(core.peer_to_fid[1]))
	check(s.has("ranked"), "summary carries ranked info")
	eq(str(s["ranked"]["opponents"][0]["id"]), "pb", "the opponent's rating is included")
