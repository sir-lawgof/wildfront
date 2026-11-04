class_name Challenges
extends RefCounted
## Event-driven challenge tracker (GDD 9). The sim records challenge_events on each
## fighter; at match end this turns them into progress, completions and rewards.
## Progress is stored in the profile and survives prestige.

static var _data: Dictionary = {}
static var _mods: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = DB.load_json("res://data/challenges.json")
	return _data


static func mods() -> Dictionary:
	if _mods.is_empty():
		_mods = DB.load_json("res://data/mods.json")
	return _mods


static func mod_category(weapon_type: String) -> String:
	var cats: Dictionary = mods().get("categories", {})
	for c in cats:
		if (cats[c] as Array).has(weapon_type):
			return c
	return ""


## Mods of a category in order (index 0 = Mod 1).
static func mods_for(weapon_type: String) -> Array:
	var c := mod_category(weapon_type)
	return mods().get("mods", {}).get(c, [])


static func find_mod(weapon_type: String, mod_id: String) -> Dictionary:
	for m in mods_for(weapon_type):
		if str(m["id"]) == mod_id:
			return m
	return {}


static func _matches(ev: Dictionary, filter: Dictionary) -> bool:
	for k in filter:
		var v = filter[k]
		match k:
			"hp_below":
				if int(ev.get("hp", 99)) >= int(v):
					return false
			"min_dist":
				if int(ev.get("dist", 0)) < int(v):
					return false
			"max_dist":
				if int(ev.get("dist", 99)) > int(v):
					return false
			"min_damage_taken":
				if int(ev.get("damage_taken_life", 0)) < int(v):
					return false
			"max_damage_taken":
				if int(ev.get("damage_taken_life", 0)) > int(v):
					return false
			"min_kills":
				if int(ev.get("kills", 0)) < int(v):
					return false
			_:
				if ev.get(k) != v:
					return false
	return true


## Adds derived events (rampage, double maul, tribrid, match) to the raw list.
static func derive(events: Array, match_info: Dictionary) -> Array:
	var out := events.duplicate()
	var melee_ticks: Array = []
	var maul_ticks := {}
	for e in events:
		match str(e.get("type", "")):
			"kill":
				if str(e.get("style", "")) == "melee" and not bool(e.get("streak_kill", false)):
					melee_ticks.append(int(e.get("tick", 0)))
			"maul_spec":
				var t := int(e.get("tick", 0))
				maul_ticks[t] = int(maul_ticks.get(t, 0)) + 1
	melee_ticks.sort()
	var i := 0
	while i + 2 < melee_ticks.size():
		if int(melee_ticks[i + 2]) - int(melee_ticks[i]) <= 17:
			out.append({"type": "rampage"})
			i += 3
		else:
			i += 1
	for t in maul_ticks:
		if int(maul_ticks[t]) >= 2:
			out.append({"type": "double_maul"})
	out.append({"type": "match", "won": bool(match_info.get("won", false)), "deaths": int(match_info.get("deaths", 0)), "kills": int(match_info.get("kills", 0))})
	return out


## progress: profile["challenges"] (id -> number). completed: profile["completed"] (Array of ids).
## Returns {"xp": {melee, ranged, magic}, "completed": [{name, xp, reward, cat}], "rewards": [..]}
static func process(events: Array, progress: Dictionary, completed: Array, match_info: Dictionary) -> Dictionary:
	var all := derive(events, match_info)
	var res := {"xp": {"melee": 0, "ranged": 0, "magic": 0}, "completed": [], "rewards": []}
	for c in data().get("challenges", []):
		var cid := str(c["id"])
		if completed.has(cid):
			continue
		var add := 0
		for e in all:
			if str(e.get("type", "")) != str(c["event"]):
				continue
			if not _matches(e, c.get("filter", {})):
				continue
			add += int(e.get(str(c["sum"]), 0)) if c.has("sum") else 1
		if add == 0:
			continue
		var cur := int(progress.get(cid, 0)) + add
		progress[cid] = cur
		if cur >= int(c["target"]):
			completed.append(cid)
			_grant(res, str(c["cat"]), int(c["xp"]), str(c["name"]), str(c.get("reward", "")))
	# Weapon ladders: one per weapon type (spells count per family).
	var per_type := {}
	for e in all:
		if str(e.get("type", "")) == "kill" and str(e.get("weapon_type", "")) != "":
			var wt := str(e["weapon_type"])
			if not per_type.has(wt):
				per_type[wt] = {"kills": 0, "spec_kills": 0, "fast_kills": 0, "life_kills": 0}
			var pt: Dictionary = per_type[wt]
			pt["kills"] += 1
			if bool(e.get("spec", false)):
				pt["spec_kills"] += 1
			if int(e.get("tick", 0)) - int(e.get("first_hit_tick", 0)) <= 2:
				pt["fast_kills"] += 1
			pt["life_kills"] = maxi(int(pt["life_kills"]), int(e.get("life_type_kills", 0)))
		elif str(e.get("type", "")) == "max_hit":
			var wt2 := str(e.get("weapon_type", ""))
			if wt2 != "" and not DB.items.values().any(func(it): return str(it.get("weapon_type", "")) == wt2 and it.has("spec")):
				if not per_type.has(wt2):
					per_type[wt2] = {"kills": 0, "spec_kills": 0, "fast_kills": 0, "life_kills": 0}
				per_type[wt2]["spec_kills"] += 1
	for wt in per_type:
		var pt: Dictionary = per_type[wt]
		var style := _type_style(str(wt))
		for step in data().get("weapon_ladder", []):
			var sid := "%s:%s" % [wt, step["id"]]
			if completed.has(sid):
				continue
			var kind := str(step["kind"])
			var cur := int(pt[kind])
			if kind != "life_kills":
				cur += int(progress.get(sid, 0))
			else:
				cur = maxi(cur, int(progress.get(sid, 0)))
			progress[sid] = cur
			if cur >= int(step["target"]):
				completed.append(sid)
				var reward := str(step.get("reward", ""))
				if reward.begins_with("mod:"):
					reward = "mod:%s:%s" % [wt, reward.substr(4)]
				elif reward.begins_with("kit:"):
					reward = "kit:%s:%s" % [wt, reward.substr(4)]
				_grant(res, style, int(step["xp"]), "%s - %s" % [_type_label(str(wt)), step["name"]], reward)
	return res


static func _grant(res: Dictionary, cat: String, xp: int, name: String, reward: String) -> void:
	if cat == "shared":
		var each := xp / 3
		for s in DB.STYLES:
			res["xp"][s] += each
		res["xp"]["melee"] += xp - each * 3
	elif DB.STYLES.has(cat):
		res["xp"][cat] += xp
	(res["completed"] as Array).append({"name": name, "xp": xp, "reward": reward, "cat": cat})
	if reward != "":
		(res["rewards"] as Array).append(reward)


static func _type_style(wt: String) -> String:
	if wt.begins_with("spell_"):
		return "magic"
	for it in DB.items.values():
		if str(it.get("weapon_type", "")) == wt:
			return str(it.get("style", "melee"))
	return "melee"


static func _type_label(wt: String) -> String:
	if wt.begins_with("spell_"):
		return wt.substr(6).capitalize() + " spells"
	return wt.replace("_", " ").capitalize()


## Weapon-type list for the Barracks challenge screen.
static func weapon_types() -> Array:
	var out: Array = []
	for it in DB.items.values():
		var wt := str(it.get("weapon_type", ""))
		if wt != "" and str(it.get("slot", "")) == "weapon" and not out.has(wt):
			out.append(wt)
	for fam in ["ember", "frost", "leech", "storm", "binding"]:
		out.append("spell_" + fam)
	return out
