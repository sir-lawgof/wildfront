class_name Balance
extends RefCounted
## Bot-vs-bot duel runner shared by tools/balance_sim.gd and the U9 balance check in the tests.


## One duel round between default classes a (team 0) and b (team 1). bracket "" = own unlocks at the given
## levels; otherwise both use that bracket's fixed kits. Returns [winner team (0/1/-1), ticks].
static func duel(a: String, b: String, lv_a: int, lv_b: int, seed: int, bracket: String = "", skill: float = 0.7) -> Array:
	var core := MatchServerCore.new()
	core.setup({"mode": "duel", "map": "castle_courtyard", "seed": seed, "pre_ticks": 1, "player": {}})
	var sim := core.sim
	var fl: Array = sim.fighters.values()
	var defs: Dictionary = DB.classes["defaults"]
	var supply := str(sim.mode.get("supply", "full"))
	for i in range(2):
		var f: Fighter = fl[i]
		var lvl := lv_a if f.team == 0 else lv_b
		var cls := a if f.team == 0 else b
		if bracket != "":
			f.unlocked = Brackets.unlocked(bracket)
			f.loadout = Brackets.build_loadout(bracket, defs[cls], supply)
		else:
			f.unlocked = Progression.unlocked_set({"melee": lvl, "ranged": lvl, "magic": lvl})
			f.loadout = Loadout.build(defs[cls], f.unlocked, {"supply": supply})
		sim.spawn(f)
		f.spawn_shield = 0
		(core.bots[f.id] as BotBrain).skill = skill
	(fl[0] as Fighter).pos = Vector2i(20, 24)
	(fl[1] as Fighter).pos = Vector2i(27, 24)
	for i in range(3000):
		core.tick()
		if sim.phase == "over" or sim.rules.round_num > 1 or sim.rules.round_over_ticks > 0:
			break
	return [sim.rules.last_round_winner, sim.live_ticks]


## Win rates of every class pair: {a: {b: win fraction for a}}, plus "_overall": {class: fraction}.
## Each pair plays n duels with sides swapped every other duel, so map side can't bias it.
static func matrix(n: int, bracket: String = "", lv: int = 40) -> Dictionary:
	var ids: Array = DB.classes["defaults"].keys()
	var out := {}
	var tot_w := {}
	var tot_n := {}
	for a in ids:
		out[a] = {}
		for b in ids:
			var wins := 0.0
			for i in range(n):
				var swap := i % 2 == 1
				var r := duel(b if swap else a, a if swap else b, lv, lv, i * 7919 + 13, bracket)
				var a_team := 1 if swap else 0
				if int(r[0]) == a_team:
					wins += 1.0
				elif int(r[0]) == -1:
					wins += 0.5
			out[a][b] = wins / n
			if a != b:
				tot_w[a] = float(tot_w.get(a, 0.0)) + wins
				tot_n[a] = int(tot_n.get(a, 0)) + n
	var overall := {}
	for a in ids:
		overall[a] = float(tot_w.get(a, 0.0)) / maxf(1.0, float(tot_n.get(a, 0)))
	out["_overall"] = overall
	return out
