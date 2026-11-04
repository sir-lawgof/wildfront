extends SceneTree
## Headless balance simulator (GDD M5). Runs bot-vs-bot fights using the shared rules.
##   godot --headless --path . --script res://tools/balance_sim.gd -- [duels=N] [levels=L] [matches=M] [mode=clan_clash]
## Prints duel win rates for every pair of default classes (same tier and one tier apart)
## and the pacing of full bot matches (kills per minute, time to win).

var args := {"duels": "40", "levels": "1", "matches": "2", "mode": "clan_clash", "map": "frostgate_ruins"}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	DB.ensure_loaded()
	var n := int(args["duels"])
	var lv := int(args["levels"])
	if n > 0:
		_duels(n, lv, lv, "same tier")
		_duels(n, mini(lv + 5, 40), lv, "row class one tier (5 levels) ahead")
	var m := int(args["matches"])
	if m > 0:
		_matches(m, lv)
	quit(0)


func _duels(n: int, lv_a: int, lv_b: int, label: String) -> void:
	print("\n== Duels (%s), %d per pair, levels %d vs %d ==" % [label, n, lv_a, lv_b])
	var ids: Array = DB.classes["defaults"].keys()
	var header := "%-11s" % ""
	for b in ids:
		header += "%-11s" % b
	print(header + "avg ticks")
	for a in ids:
		var row := "%-11s" % a
		var ticks_total := 0
		var fights := 0
		for b in ids:
			var wins := 0
			for i in range(n):
				var r := _duel(a, b, lv_a, lv_b, i * 7919 + 13)
				if r[0] == 0:
					wins += 1
				ticks_total += int(r[1])
				fights += 1
			row += "%-11s" % ("%d%%" % int(100.0 * wins / n))
		print(row + str(ticks_total / maxi(fights, 1)))


## Returns [winner team (0/1/-1), ticks].
func _duel(a: String, b: String, lv_a: int, lv_b: int, seed: int) -> Array:
	var core := MatchServerCore.new()
	core.setup({"mode": "duel", "map": "castle_courtyard", "seed": seed, "pre_ticks": 1, "player": {}})
	# Replace the random bot classes with the pair under test.
	var sim := core.sim
	var fl: Array = sim.fighters.values()
	var defs: Dictionary = DB.classes["defaults"]
	for i in range(2):
		var f: Fighter = fl[i]
		var lvl := lv_a if f.team == 0 else lv_b
		var cls := a if f.team == 0 else b
		var levels := {"melee": lvl, "ranged": lvl, "magic": lvl}
		f.unlocked = Progression.unlocked_set(levels)
		f.loadout = Loadout.build(defs[cls], f.unlocked, {"supply": str(sim.mode.get("supply", "full"))})
		sim.spawn(f)
		(core.bots[f.id] as BotBrain).skill = 0.7
	# Start them 6 tiles apart in the courtyard.
	(fl[0] as Fighter).pos = Vector2i(20, 24)
	(fl[1] as Fighter).pos = Vector2i(27, 24)
	for i in range(3000):
		core.tick()
		if sim.phase == "over" or sim.rules.round_num > 1 or sim.rules.round_over_ticks > 0:
			break
	return [sim.rules.last_round_winner, sim.live_ticks]


func _matches(m: int, lv: int) -> void:
	print("\n== Bot matches: %s on %s, levels ~%d ==" % [args["mode"], args["map"], lv])
	for i in range(m):
		var core := MatchServerCore.new()
		core.setup({"mode": args["mode"], "map": args["map"], "seed": 1000 + i, "pre_ticks": 1, "player": {}})
		var sim := core.sim
		var limit := DB.ticks(float(sim.mode.get("time_limit_s", 600))) + 50
		var stats := {"attacks": 0, "dmg": 0, "eats": 0, "engaged": 0, "samples": 0, "blocked": 0, "splash": 0}
		for t in range(limit):
			core.tick()
			for e in sim.events:
				match str(e["type"]):
					"attack": stats["attacks"] += 1
					"splat":
						if e["kind"] == "hit": stats["dmg"] += int(e["amount"])
					"consume": stats["eats"] += 1
					"splash": stats["splash"] += 1
			if t % 10 == 0:
				for f in sim.fighters.values():
					var fi: Fighter = f
					if not fi.is_alive():
						continue
					stats["samples"] += 1
					for o in sim.fighters.values():
						var of: Fighter = o
						if of.is_alive() and sim.rules.can_attack(fi, of) and MapGrid.chebyshev(fi.pos, of.pos) <= 10:
							stats["engaged"] += 1
							break
			if sim.phase == "over":
				break
		print("    attacks %d, damage %d (%.1f/attack), consumables %d, splashes %d, %.0f%% of bot-time within 10 tiles of an enemy" % [stats["attacks"], stats["dmg"], float(stats["dmg"]) / maxf(1, stats["attacks"]), stats["eats"], stats["splash"], 100.0 * stats["engaged"] / maxf(1, stats["samples"])])
		var kills := 0
		var food_left := 0
		for f in sim.fighters.values():
			kills += (f as Fighter).kills
		var minutes := sim.live_ticks * 0.6 / 60.0
		print("  match %d: scores %s, %d kills in %.1f min (%.1f kills/min), winner %s" % [i + 1, str(sim.scores), kills, minutes, kills / maxf(minutes, 0.01), str(sim.result.get("winner", "none"))])
