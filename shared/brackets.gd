class_name Brackets
extends RefCounted
## U2 brackets (data/brackets.json): fixed starter kits, combat stat overrides and gear limits, so
## competitive play is decided by skill, not unlocks. "standard" is not a bracket: it means your own gear.

static var _unl_cache: Dictionary = {}


static func data() -> Dictionary:
	return DB.brackets


static func ids() -> Array:
	return (data().get("brackets", {}) as Dictionary).keys()


static func has(bid: String) -> bool:
	return (data().get("brackets", {}) as Dictionary).has(bid)


static func get_def(bid: String) -> Dictionary:
	return data().get("brackets", {}).get(bid, {})


static func display_name(bid: String) -> String:
	return str(get_def(bid).get("name", bid.capitalize()))


## Is this item allowed in the bracket (armour class, banned ids and tags, spellbook)?
static func item_allowed(bid: String, id: String) -> bool:
	var b := get_def(bid)
	if b.is_empty():
		return true
	var it := DB.item(id)
	var allowed: Array = b.get("allowed_armour", [])
	if not allowed.is_empty() and str(it.get("armour_class", "")) != "" and not allowed.has(str(it["armour_class"])):
		return false
	for ban in b.get("banned", []):
		var s := str(ban)
		if s == id:
			return false
		var kv := s.split(":", true, 1)
		if kv.size() == 2 and it.has(kv[0]) and str(it[kv[0]]).to_lower() == kv[1].to_lower():
			return false
	return true


## The unlock set every kit in this bracket is built from (cached).
static func unlocked(bid: String) -> Dictionary:
	if _unl_cache.has(bid):
		return _unl_cache[bid]
	var b := get_def(bid)
	var lv = b.get("kit_levels", "all")
	var base: Dictionary = Loadout.all_unlocked() if str(lv) == "all" else Progression.unlocked_set(lv)
	var out := {}
	for k in base:
		var key := str(k)
		if DB.has_item(key) and not item_allowed(bid, key):
			continue
		if DB.spells.has(key) and str(b.get("spellbook", "any")) != "any" and str(DB.spells[key]["book"]) != str(b["spellbook"]):
			continue
		if (b.get("banned", []) as Array).has(key):
			continue  # banned spell, prayer or perk id
		if key == "feature:forbidden_book" and str(b.get("spellbook", "any")) != "any":
			continue
		out[key] = true
	_unl_cache[bid] = out
	return out


## Which kit a class maps to: hybrid if it carries weapons of two other styles, else its primary style.
static func kit_key(class_def: Dictionary) -> String:
	var styles := {}
	var unl := Loadout.all_unlocked()
	var prim := Loadout.resolve(str(class_def.get("primary", "")), unl)
	var pstyle := str(DB.item(prim).get("style", class_def.get("style", "melee")))
	styles[pstyle] = true
	for ref in class_def.get("secondary", []):
		var id := Loadout.resolve(str(ref), unl)
		if id != "":
			styles[str(DB.item(id).get("style", ""))] = true
	if styles.size() >= 3:
		return "hybrid"
	return pstyle if DB.STYLES.has(pstyle) else "melee"


## Builds the fixed bracket loadout for a player whose chosen class is class_def.
## extra: {kit: force a kit key, food_mult} (The Lab).
static func build_loadout(bid: String, class_def: Dictionary, supply: String, extra: Dictionary = {}) -> Dictionary:
	var b := get_def(bid)
	var kits: Dictionary = b.get("kits", {})
	var key := str(extra.get("kit", kit_key(class_def)))
	var kit: Dictionary = kits.get(key, kits.get("melee", {}))
	var lo := Loadout.build(kit, unlocked(bid), {"supply": supply, "armour_classes": b.get("allowed_armour", []), "armour_fallback": str(b.get("armour_fallback", "")), "food_mult": float(extra.get("food_mult", 1.0))})
	lo["bracket"] = bid
	lo["kit"] = key
	lo["stats"] = (b.get("stats", {}) as Dictionary).duplicate()
	return lo


## Weekly featured bracket: rotation[week index since rotation_epoch]. Deterministic for a given time.
static func featured(unix_time: int = -1) -> String:
	var rot: Array = data().get("rotation", [])
	if rot.is_empty():
		return ""
	if unix_time < 0:
		unix_time = int(Time.get_unix_time_from_system())
	return str(rot[posmod(week_index(unix_time), rot.size())])


static func week_index(unix_time: int) -> int:
	var epoch := int(Time.get_unix_time_from_datetime_string(str(data().get("rotation_epoch", "2026-01-05T00:00:00"))))
	return int(floor(float(unix_time - epoch) / 604800.0))


## Seconds until the featured bracket changes.
static func seconds_to_rotation(unix_time: int = -1) -> int:
	if unix_time < 0:
		unix_time = int(Time.get_unix_time_from_system())
	var epoch := int(Time.get_unix_time_from_datetime_string(str(data().get("rotation_epoch", "2026-01-05T00:00:00"))))
	return (week_index(unix_time) + 1) * 604800 + epoch - unix_time


static func validate(errors: Array[String]) -> void:
	var d := data()
	if not d.has("brackets"):
		errors.append("brackets.json: missing 'brackets'")
		return
	for bid in d["brackets"]:
		var b: Dictionary = d["brackets"][bid]
		for k in ["name", "kit_levels", "stats", "kits"]:
			if not b.has(k):
				errors.append("Bracket %s missing '%s'" % [bid, k])
		for s in b.get("stats", {}):
			if not Fighter.STATS.has(str(s)):
				errors.append("Bracket %s: unknown stat '%s'" % [bid, s])
			elif int(b["stats"][s]) < 1 or int(b["stats"][s]) > 99:
				errors.append("Bracket %s: stat %s out of range" % [bid, s])
		for ban in b.get("banned", []):
			var bs := str(ban)
			if not bs.contains(":") and not DB.exists(bs):
				errors.append("Bracket %s: banned id '%s' doesn't exist" % [bid, bs])
		var acs: Dictionary = DB.armour_types.get("classes", {})
		for ac in b.get("allowed_armour", []):
			if not acs.has(str(ac)):
				errors.append("Bracket %s: unknown armour class '%s'" % [bid, ac])
		if str(b.get("armour_fallback", "")) != "" and not acs.has(str(b["armour_fallback"])):
			errors.append("Bracket %s: unknown armour_fallback" % bid)
		if not ["any", "elemental", "forbidden"].has(str(b.get("spellbook", "any"))):
			errors.append("Bracket %s: bad spellbook" % bid)
		var kl = b.get("kit_levels", "all")
		if not (str(kl) == "all" or kl is Dictionary):
			errors.append("Bracket %s: kit_levels must be 'all' or {melee, ranged, magic}" % bid)
		for key in ["melee", "ranged", "magic", "hybrid"]:
			if not (b.get("kits", {}) as Dictionary).has(key):
				errors.append("Bracket %s: missing kit '%s'" % [bid, key])
		for key in b.get("kits", {}):
			var kit: Dictionary = b["kits"][key]
			for p in kit.get("perks", []):
				if not DB.perks.has(str(p)):
					errors.append("Bracket %s kit %s: unknown perk %s" % [bid, key, p])
	for r in d.get("rotation", []):
		if not (d["brackets"] as Dictionary).has(str(r)):
			errors.append("brackets.json rotation: unknown bracket %s" % r)
