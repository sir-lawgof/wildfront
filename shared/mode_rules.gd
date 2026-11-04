class_name ModeRules
extends RefCounted
## Win conditions, scoring, rounds and spawn selection for each mode type (GDD 3).
## Mode numbers come from data/modes.json.

var sim: Sim
var mode: Dictionary
var type: String = "tdm"
var num_teams: int = 2
var score_limit: int = 50
var time_limit: int = 1000
var rounds_to_win: int = 4
var round_time: int = 250
var round_num: int = 1
var round_ticks: int = 0
var round_over_ticks: int = 0
var last_round_winner: int = -1
var score_timer: int = 0


func _init(p_sim: Sim, p_mode: Dictionary) -> void:
	sim = p_sim
	mode = p_mode
	type = str(mode.get("type", "tdm"))
	score_limit = int(mode.get("score_limit", 50))
	time_limit = DB.ticks(float(mode.get("time_limit_s", 600)))
	rounds_to_win = int(mode.get("rounds_to_win", 4))
	round_time = DB.ticks(float(mode.get("round_time_s", 150)))


func is_ffa() -> bool:
	return type == "ffa"


func is_rounds() -> bool:
	return type == "elimination"


func respawns() -> bool:
	return bool(mode.get("respawn", true))


func streaks_enabled() -> bool:
	return bool(mode.get("streaks", true))


func can_attack(a: Fighter, b: Fighter) -> bool:
	if a == null or b == null or a.id == b.id:
		return false
	if a.npc_kind == "guardian" and b.id == a.owner_id:
		return false
	return a.team != b.team


func setup_objectives() -> void:
	if type == "domination":
		for p in sim.map.obelisks:
			sim.objectives.append({"pos": p, "owner": -1, "cap_team": -1, "progress": 0, "name": ["A", "B", "C", "D", "E"][sim.objectives.size() % 5]})


func on_kill(killer: Fighter, victim: Fighter) -> void:
	if type == "tdm" or type == "ffa":
		if killer != null and killer.team >= 0 and killer.team < sim.scores.size():
			sim.scores[killer.team] += 1


func on_death(victim: Fighter) -> void:
	if is_rounds():
		victim.out_of_round = true
	elif respawns():
		victim.respawn_ticks = DB.ticks(float(DB.modes.get("respawn_s", 5)))


## Called once per live tick in phase 7.
func tick() -> void:
	if sim.phase != "live":
		return
	match type:
		"domination":
			_tick_domination()
		"elimination":
			_tick_rounds()
			return
	if score_limit > 0:
		for t in range(sim.scores.size()):
			if sim.scores[t] >= score_limit:
				sim.end_match(t)
				return
	if sim.live_ticks >= time_limit:
		sim.end_match(_leader())


func _leader() -> int:
	var best := -1
	var best_s := -1
	var tie := false
	for t in range(sim.scores.size()):
		if sim.scores[t] > best_s:
			best_s = sim.scores[t]
			best = t
			tie = false
		elif sim.scores[t] == best_s:
			tie = true
	return -1 if tie else best


func _tick_domination() -> void:
	var cap_ticks := int(mode.get("capture_ticks", 8))
	var radius := int(mode.get("capture_radius", 1))
	for ob in sim.objectives:
		var present := {}
		for f in sim.fighters.values():
			var fi: Fighter = f
			if fi.npc_kind != "" or not fi.is_alive():
				continue
			if MapGrid.chebyshev(fi.pos, ob["pos"]) <= radius:
				present[fi.team] = int(present.get(fi.team, 0)) + 1
		if present.size() == 1:
			var team: int = present.keys()[0]
			if team == int(ob["owner"]):
				ob["progress"] = 0
				ob["cap_team"] = -1
			else:
				if int(ob["cap_team"]) != team:
					ob["cap_team"] = team
					ob["progress"] = 0
				ob["progress"] = int(ob["progress"]) + 1
				if int(ob["progress"]) >= cap_ticks:
					ob["owner"] = team
					ob["progress"] = 0
					ob["cap_team"] = -1
					for f in sim.fighters.values():
						var fi: Fighter = f
						if fi.npc_kind == "" and fi.is_alive() and fi.team == team and MapGrid.chebyshev(fi.pos, ob["pos"]) <= radius:
							fi.captures += 1
							fi.objective_score += 1
							fi.challenge_events.append({"type": "capture"})
					sim.add_event({"type": "capture", "team": team, "name": ob["name"]})
		elif present.is_empty():
			ob["progress"] = maxi(0, int(ob["progress"]) - 1)
			if int(ob["progress"]) == 0:
				ob["cap_team"] = -1
	score_timer += 1
	if score_timer >= int(mode.get("score_interval_ticks", 8)):
		score_timer = 0
		for ob in sim.objectives:
			var o := int(ob["owner"])
			if o >= 0:
				sim.scores[o] += 1


func _tick_rounds() -> void:
	if round_over_ticks > 0:
		round_over_ticks -= 1
		if round_over_ticks == 0:
			_start_next_round()
		return
	round_ticks += 1
	var alive := [0, 0]
	var hp := [0, 0]
	for f in sim.fighters.values():
		var fi: Fighter = f
		if fi.npc_kind != "":
			continue
		if fi.is_alive():
			alive[fi.team] += 1
			hp[fi.team] += fi.hp
	var winner := -2
	if alive[0] == 0 and alive[1] == 0:
		winner = -1
	elif alive[0] == 0:
		winner = 1
	elif alive[1] == 0:
		winner = 0
	elif round_ticks >= round_time:
		winner = 0 if hp[0] > hp[1] else (1 if hp[1] > hp[0] else -1)
	if winner == -2:
		return
	last_round_winner = winner
	if winner >= 0:
		sim.scores[winner] += 1
		for f in sim.fighters.values():
			var fi: Fighter = f
			if fi.npc_kind == "" and fi.team == winner:
				fi.objective_score += 1
				fi.rounds_won += 1
	sim.add_event({"type": "round_end", "winner": winner, "round": round_num})
	if winner >= 0 and sim.scores[winner] >= rounds_to_win:
		sim.end_match(winner)
		return
	round_over_ticks = 5


func _start_next_round() -> void:
	round_num += 1
	round_ticks = 0
	sim.pending_hits.clear()
	for f in sim.fighters.values():
		var fi: Fighter = f
		if fi.npc_kind == "":
			fi.out_of_round = false
			sim.spawn(fi)
			fi.spawn_shield = 0
	sim.phase = "pre"
	sim.phase_ticks = 5
	sim.add_event({"type": "round_start", "round": round_num})


func _side(team: int) -> int:
	return clampi(team, 0, 1)


func pick_spawn(f: Fighter) -> Vector2i:
	var cands: Array = []
	var own: Array = []
	if is_ffa():
		cands = sim.map.ffa_spawns + sim.map.spawns[0] + sim.map.spawns[1]
	else:
		own = sim.map.spawns[_side(f.team)]
		cands = own.duplicate()
		if type == "tdm":
			cands += sim.map.ffa_spawns
	if cands.is_empty():
		return sim.map.nearest_walkable(Vector2i(sim.map.w / 2, sim.map.h / 2))
	if is_rounds() or sim.phase == "pre":
		# Fixed starting spots: spread teammates over the team's spawn list.
		var idx := 0
		for o in sim.fighters.values():
			var of: Fighter = o
			if of == f:
				break
			if of.team == f.team and of.npc_kind == "":
				idx += 1
		var list: Array = own if not own.is_empty() else cands
		if is_ffa():
			list = cands
			idx = sim.fighters.keys().find(f.id)
		return sim.map.nearest_walkable(list[idx % list.size()])
	var best: Vector2i = cands[0]
	var best_score := -INF
	for c in cands:
		var cv: Vector2i = c
		var dmin := 40.0
		var dally := 0.0
		var nally := 0
		var penalty := 0.0
		for o in sim.fighters.values():
			var of: Fighter = o
			if of == f or not of.is_alive():
				continue
			var d := Vector2(cv - of.pos).length()
			if can_attack(f, of) or can_attack(of, f):
				dmin = minf(dmin, d)
				if d < 13.0 and sim.map.has_los(cv, of.pos):
					penalty += 40.0
			else:
				dally += d
				nally += 1
		var s := dmin - penalty + sim.rng.randf() * 4.0
		if nally > 0:
			s -= 0.15 * (dally / nally)
		if own.has(cv):
			s += 5.0
		if s > best_score:
			best_score = s
			best = cv
	return sim.map.nearest_walkable(best)


func time_left_ticks() -> int:
	if is_rounds():
		return maxi(0, round_time - round_ticks)
	return maxi(0, time_limit - sim.live_ticks)
