class_name Mutators
extends RefCounted
## The Lab (U7, data/mutators.json): one experimental mutator per week. A mutator only overrides data the game
## already reads (rules.json keys via Sim.rule(), mode keys via mode_overrides, loadout food_mult / kit).


static func ids() -> Array:
	return (DB.mutators.get("mutators", {}) as Dictionary).keys()


static func get_def(mid: String) -> Dictionary:
	return DB.mutators.get("mutators", {}).get(mid, {})


static func display_name(mid: String) -> String:
	return str(get_def(mid).get("name", mid.capitalize()))


## This week's mutator (same weekly clock as the featured bracket).
static func current(unix_time: int = -1) -> String:
	return at_week(Brackets.week_index(unix_time if unix_time >= 0 else int(Time.get_unix_time_from_system())))


static func at_week(week: int) -> String:
	var rot: Array = DB.mutators.get("rotation", [])
	if rot.is_empty():
		return ""
	return str(rot[posmod(week, rot.size())])


## Lab votes for one week from a profile's lab_votes: {keep, change, drop} for that week's mutator.
static func tally(lab_votes: Dictionary, week: int) -> Dictionary:
	var out := {"mutator": at_week(week), "keep": 0, "change": 0, "drop": 0}
	var w: Dictionary = lab_votes.get(str(week), {})
	for k in ["keep", "change", "drop"]:
		out[k] = int(w.get(k, 0))
	return out


static func validate(errors: Array[String]) -> void:
	var ms: Dictionary = DB.mutators.get("mutators", {})
	if ms.is_empty():
		errors.append("mutators.json: no mutators")
	var lab_rules := ["protect_reduction"]
	for mid in ms:
		var m: Dictionary = ms[mid]
		if not m.has("name") or not m.has("desc"):
			errors.append("Mutator %s: needs name and desc" % mid)
		for k in m.get("rules", {}):
			if not DB.rules.has(str(k)) and not lab_rules.has(str(k)):
				errors.append("Mutator %s: '%s' isn't a rule the game reads (rules.json)" % [mid, k])
		for k in m.get("mode", {}):
			if not ["type", "respawn", "streaks", "rounds_to_win", "round_time_s", "score_limit", "time_limit_s", "supply", "engagement_ticks"].has(str(k)):
				errors.append("Mutator %s: unknown mode key '%s'" % [mid, k])
		if m.get("mode", {}).has("type") and not ["tdm", "ffa", "domination", "elimination"].has(str(m["mode"]["type"])):
			errors.append("Mutator %s: unknown mode type" % mid)
		for k in m.get("loadout", {}):
			if not ["food_mult", "kit"].has(str(k)):
				errors.append("Mutator %s: unknown loadout key '%s'" % [mid, k])
		if m.get("loadout", {}).has("kit") and not ["melee", "ranged", "magic", "hybrid"].has(str(m["loadout"]["kit"])):
			errors.append("Mutator %s: unknown kit" % mid)
	for r in DB.mutators.get("rotation", []):
		if not ms.has(str(r)):
			errors.append("mutators.json rotation: unknown mutator %s" % r)
