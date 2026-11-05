extends TestCase
## U8 tournament helper: single and double elimination, byes, a real 4-player run with bot duels.


func _play_out(t: Dictionary, r: RandomNumberGenerator) -> int:
	var played := 0
	for guard in range(200):
		var ready := Tournament.ready_matches(t)
		if ready.is_empty():
			break
		var mid: int = ready[0]
		var m: Dictionary = t["matches"][mid]
		var a := Tournament.slot_entrant(t, m["a"])
		var b := Tournament.slot_entrant(t, m["b"])
		check(Tournament.report(t, mid, a if r.randf() < 0.5 else b), "result accepted")
		played += 1
	return played


func test_single_elimination_all_sizes() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4
	for n in [2, 3, 4, 5, 8, 11, 16]:
		var names: Array = []
		for i in range(n):
			names.append("P%d" % i)
		var t := Tournament.create(names, "single")
		var played := _play_out(t, r)
		check(Tournament.is_done(t), "%d players: finished" % n)
		eq(played, n - 1, "%d players: n-1 real matches" % n)
		var st := Tournament.standings(t)
		eq(st.size(), n, "%d players: everyone placed" % n)
		eq(int(st[0][0]), 1, "champion first")


func test_double_elimination() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 9
	for n in [4, 6, 8]:
		for trial in range(10):
			var names: Array = []
			for i in range(n):
				names.append("P%d" % i)
			var t := Tournament.create(names, "double")
			var played := _play_out(t, r)
			check(Tournament.is_done(t), "%d players double: finished" % n)
			check(played >= 2 * n - 2 and played <= 2 * n - 1, "%d players: %d matches (2n-2 or 2n-1)" % [n, played])
			var losses := {}
			for m in t["matches"]:
				if int(m["loser"]) >= 0 and not bool(m.get("skipped", false)):
					losses[int(m["loser"])] = int(losses.get(int(m["loser"]), 0)) + 1
			var champ := Tournament.champion(t)
			check(int(losses.get(champ, 0)) <= 1, "the champion lost at most once")
			for e in range(n):
				if e != champ:
					eq(int(losses.get(e, 0)), 2, "%d players: P%d out after exactly two losses" % [n, e])
			eq(Tournament.standings(t).size(), n, "everyone placed")


func test_rejects_bad_reports() -> void:
	var t := Tournament.create(["A", "B", "C", "D"], "single")
	var ready := Tournament.ready_matches(t)
	eq(ready.size(), 2, "two first-round matches")
	var final_id := int(t["final"])
	check(not Tournament.report(t, final_id, 0), "can't report a match whose players aren't known")
	var m: Dictionary = t["matches"][ready[0]]
	var outsider := 3 - Tournament.slot_entrant(t, m["a"]) - Tournament.slot_entrant(t, m["b"])
	check(not Tournament.report(t, ready[0], outsider) or outsider == Tournament.slot_entrant(t, m["a"]), "only one of the two players can win")


## A 4-player single-elimination tournament run start to finish with real (bot-played) Duels.
func test_four_player_tournament_with_duels() -> void:
	DB.ensure_loaded()
	var t := Tournament.create(["Ash", "Bryn", "Cole", "Dara"], "single")
	var played := 0
	for guard in range(10):
		var ready := Tournament.ready_matches(t)
		if ready.is_empty():
			break
		var mid: int = ready[0]
		var m: Dictionary = t["matches"][mid]
		var ea := Tournament.slot_entrant(t, m["a"])
		var eb := Tournament.slot_entrant(t, m["b"])
		var core := MatchServerCore.new()
		core.setup({"mode": "duel", "map": "castle_courtyard", "seed": 30 + mid, "pre_ticks": 1, "private": {"rounds_to_win": 1}})
		var fl: Array = core.sim.fighters.values()
		(fl[0] as Fighter).name = str(t["entrants"][ea])
		(fl[1] as Fighter).name = str(t["entrants"][eb])
		for i in range(3000):
			core.tick()
			if core.sim.phase == "over":
				break
		var w := int(core.sim.result.get("winner", -1))
		check(w >= 0, "%s has a winner" % Tournament.match_label(t, mid))
		check(Tournament.report(t, mid, ea if w == (fl[0] as Fighter).team else eb), "result reported")
		played += 1
	check(Tournament.is_done(t), "the tournament finished")
	eq(played, 3, "three matches")
	check(str(t["entrants"][Tournament.champion(t)]) != "", "there's a champion")
