class_name DB
extends RefCounted
## Loads every data/*.json file, expands tiered weapons and armour into concrete
## items, and validates references. Static so both the sim (server) and the
## client read the same tables. Call DB.ensure_loaded() before use.

const BONUS_KEYS: Array[String] = [
	"att_melee", "att_ranged", "att_magic",
	"def_melee", "def_ranged", "def_magic",
	"str_melee", "str_ranged", "dmg_magic", "prayer",
]
const EQUIP_SLOTS: Array[String] = [
	"head", "cape", "neck", "ammo", "weapon", "body", "shield", "legs", "hands", "feet", "ring",
]
const STYLES: Array[String] = ["melee", "ranged", "magic"]

static var loaded: bool = false
static var errors: Array[String] = []

static var rules: Dictionary = {}
static var tiers: Array = []
static var items: Dictionary = {}       ## id -> item dict
static var sets: Dictionary = {}        ## "plate:1" / "berserker_plate" -> [item ids]
static var spells: Dictionary = {}      ## id -> spell
static var spell_order: Array[String] = []
static var spells_meta: Dictionary = {}
static var prayers: Dictionary = {}     ## id -> prayer
static var prayer_order: Array[String] = []
static var protect_reduction: float = 0.4
static var perks: Dictionary = {}
static var perk_order: Array[String] = []
static var levels: Dictionary = {}
static var unlocks: Dictionary = {}     ## track -> {int level -> [ids]}
static var classes: Dictionary = {}
static var modes: Dictionary = {}
static var streaks: Dictionary = {}
static var streak_order: Array[String] = []
static var consumables_meta: Dictionary = {}
static var maps: Dictionary = {}        ## id -> raw json
static var weapon_types: Dictionary = {}
static var armour_types: Dictionary = {}


static func ensure_loaded() -> void:
	if not loaded:
		load_all()


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("Missing data file: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		errors.append("%s: JSON error line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	return json.data


static func load_all() -> void:
	errors.clear()
	items.clear()
	sets.clear()
	rules = load_json("res://data/rules.json")
	tiers = load_json("res://data/tiers.json").get("tiers", [])
	weapon_types = load_json("res://data/weapon_types.json")
	armour_types = load_json("res://data/armour_types.json")
	_build_tiered_weapons()
	_build_armour()
	_load_uniques()
	_load_consumables()
	_load_spells()
	_load_prayers()
	_load_perks()
	levels = load_json("res://data/levels.json")
	_load_unlocks()
	classes = load_json("res://data/classes.json")
	modes = load_json("res://data/modes.json")
	_load_streaks()
	_load_maps()
	loaded = true
	_validate()
	if not errors.is_empty():
		for e in errors:
			push_error("[DB] " + e)


# ---------------------------------------------------------------- helpers

static func slug(s: String) -> String:
	return s.to_lower().replace(" ", "_").replace("'", "").replace("-", "_")


static func tier_name(tier: int, family: String) -> String:
	return str(tiers[tier - 1]["names"][family])


static func tier_color(tier: int) -> Color:
	return Color.html(str(tiers[tier - 1]["color"]))


static func empty_bonuses() -> Dictionary:
	var b := {}
	for k in BONUS_KEYS:
		b[k] = 0
	return b


static func item(id: String) -> Dictionary:
	return items.get(id, {})


static func has_item(id: String) -> bool:
	return items.has(id)


static func rule(key: String, default: Variant = null) -> Variant:
	return rules.get(key, default)


static func ticks(seconds: float) -> int:
	return int(round(seconds / float(rules.get("tick_seconds", 0.6))))


# ---------------------------------------------------------------- builders

static func _build_tiered_weapons() -> void:
	var wts: Dictionary = weapon_types.get("weapons", {})
	for type_key in wts:
		var wt: Dictionary = wts[type_key]
		var min_tier := int(wt.get("min_tier", 1))
		for t in range(min_tier, tiers.size() + 1):
			var mat := tier_name(t, str(wt["family"]))
			var id := slug(mat) + "_" + str(type_key)
			var nm := mat + " " + str(wt["name"])
			var overrides: Dictionary = wt.get("name_override", {})
			if overrides.has(str(t)):
				nm = str(overrides[str(t)])
			var bonuses := empty_bonuses()
			var base: Dictionary = wt.get("base", {})
			var per: Dictionary = wt.get("per_tier", {})
			for k in bonuses:
				bonuses[k] = int(base.get(k, 0)) + int(per.get(k, 0)) * (t - 1)
			var it := {
				"id": id, "name": nm, "slot": str(wt.get("slot", "weapon")), "style": str(wt["style"]),
				"kind": str(wt.get("kind", "weapon")), "weapon_type": str(type_key), "tier": t,
				"speed": int(wt.get("speed", 4)), "range": int(wt.get("range", 1)),
				"two_handed": bool(wt.get("two_handed", false)), "uses_ammo": str(wt.get("uses_ammo", "")),
				"bonuses": bonuses, "mesh": str(wt.get("mesh", "sword")),
				"color": str(tiers[t - 1]["color"]), "forbidden": false,
			}
			if wt.has("spec") and t >= int(wt.get("spec_from_tier", 99)):
				it["spec"] = (wt["spec"] as Dictionary).duplicate()
			items[id] = it
	var ammo: Dictionary = weapon_types.get("ammo", {})
	for ak in ammo:
		var a: Dictionary = ammo[ak]
		for t in range(1, tiers.size() + 1):
			var mat := tier_name(t, str(a["family"]))
			var id := slug(mat) + "_" + str(ak)
			var bonuses := empty_bonuses()
			for k in bonuses:
				bonuses[k] = int(a.get("base", {}).get(k, 0)) + int(a.get("per_tier", {}).get(k, 0)) * (t - 1)
			items[id] = {
				"id": id, "name": mat + " " + str(a["name"]), "slot": "ammo", "style": "ranged", "kind": "ammo",
				"ammo_type": str(a["ammo_type"]), "tier": t, "bonuses": bonuses, "color": str(tiers[t - 1]["color"]),
			}


static func _armour_piece(id: String, nm: String, cls_key: String, cls: Dictionary, piece: Dictionary, totals: Dictionary, tier: int, set_key: String, color: String) -> Dictionary:
	var bonuses := empty_bonuses()
	var frac := float(piece["fraction"])
	for k in bonuses:
		bonuses[k] = int(round(float(totals.get(k, 0)) * frac))
	return {
		"id": id, "name": nm, "slot": str(piece["slot"]), "style": str(cls["style"]), "kind": "armour",
		"armour_class": cls_key, "tier": tier, "set": set_key, "bonuses": bonuses, "color": color,
	}


static func _build_armour() -> void:
	var classes_def: Dictionary = armour_types.get("classes", {})
	for ck in classes_def:
		var cls: Dictionary = classes_def[ck]
		for t in range(1, tiers.size() + 1):
			var mat := tier_name(t, str(cls["family"]))
			var totals := {}
			for k in BONUS_KEYS:
				totals[k] = float(cls.get("base", {}).get(k, 0)) + float(cls.get("per_tier", {}).get(k, 0)) * (t - 1)
			var set_key := "%s:%d" % [ck, t]
			var ids: Array = []
			for piece in cls["pieces"]:
				var id := slug(mat) + "_" + str(piece["id"])
				var nm := mat + " " + str(piece["name"])
				items[id] = _armour_piece(id, nm, ck, cls, piece, totals, t, set_key, str(tiers[t - 1]["color"]))
				ids.append(id)
			sets[set_key] = ids
	for sg in armour_types.get("sidegrades", []):
		var ck := str(sg["class"])
		var cls: Dictionary = classes_def[ck]
		var t := int(sg["tier"])
		var totals := {}
		for k in BONUS_KEYS:
			var v := float(cls.get("base", {}).get(k, 0)) + float(cls.get("per_tier", {}).get(k, 0)) * (t - 1)
			v *= float(sg.get("scale", {}).get(k, 1.0))
			v += float(sg.get("add", {}).get(k, 0))
			totals[k] = v
		var ids: Array = []
		var col := Color.html(str(tiers[t - 1]["color"])).lerp(Color(0.1, 0.1, 0.1), 0.35).to_html(false)
		for piece in cls["pieces"]:
			var id := str(sg["id"]) + "_" + str(piece["id"])
			var nm := str(sg["name"]) + " " + str(piece["name"])
			var it := _armour_piece(id, nm, ck, cls, piece, totals, t, str(sg["id"]), "#" + col)
			if sg.has("run_drain_mult") and str(piece["slot"]) == "body":
				it["run_drain_mult"] = float(sg["run_drain_mult"])
			items[id] = it
			ids.append(id)
		sets[str(sg["id"])] = ids


static func _load_uniques() -> void:
	var d: Dictionary = load_json("res://data/items_unique.json")
	for raw in d.get("items", []):
		var it: Dictionary = (raw as Dictionary).duplicate(true)
		var bonuses := empty_bonuses()
		for k in it.get("bonuses", {}):
			bonuses[k] = int(it["bonuses"][k])
		it["bonuses"] = bonuses
		if not it.has("kind"):
			it["kind"] = "weapon" if str(it["slot"]) == "weapon" else ("ammo" if str(it["slot"]) == "ammo" else "armour")
		it["unique"] = true
		for k in ["speed", "range"]:
			if it.has(k):
				it[k] = int(it[k])
		if not it.has("tier"):
			it["tier"] = 5
		items[str(it["id"])] = it


static func _load_consumables() -> void:
	consumables_meta = load_json("res://data/consumables.json")
	for raw in consumables_meta.get("items", []):
		var it: Dictionary = (raw as Dictionary).duplicate(true)
		it["slot"] = ""
		it["bonuses"] = empty_bonuses()
		it["style"] = "none"
		if it.has("heal"):
			it["heal"] = int(it["heal"])
		if it.has("attack_delay"):
			it["attack_delay"] = int(it["attack_delay"])
		it["doses"] = int(it.get("doses", 1))
		items[str(it["id"])] = it


static func _load_spells() -> void:
	spells.clear()
	spell_order.clear()
	spells_meta = load_json("res://data/spells.json")
	for raw in spells_meta.get("spells", []):
		var s: Dictionary = (raw as Dictionary).duplicate(true)
		s["max_hit"] = int(s.get("max_hit", 0))
		s["level"] = int(s.get("level", 1))
		s["freeze"] = int(s.get("freeze", 0))
		s["area"] = int(s.get("area", 1))
		spells[str(s["id"])] = s
		spell_order.append(str(s["id"]))


static func _load_prayers() -> void:
	prayers.clear()
	prayer_order.clear()
	var d: Dictionary = load_json("res://data/prayers.json")
	protect_reduction = float(d.get("protect_reduction", 0.4))
	for raw in d.get("prayers", []):
		var p: Dictionary = (raw as Dictionary).duplicate(true)
		p["level"] = int(p.get("level", 1))
		p["drain"] = float(p.get("drain", 1))
		prayers[str(p["id"])] = p
		prayer_order.append(str(p["id"]))


static func _load_perks() -> void:
	perks.clear()
	perk_order.clear()
	var d: Dictionary = load_json("res://data/perks.json")
	for raw in d.get("perks", []):
		var p: Dictionary = (raw as Dictionary).duplicate(true)
		p["tier"] = int(p["tier"])
		p["level"] = int(p["level"])
		perks[str(p["id"])] = p
		perk_order.append(str(p["id"]))


static func _load_unlocks() -> void:
	unlocks.clear()
	var d: Dictionary = load_json("res://data/unlocks.json")
	for track in ["melee", "ranged", "magic", "combat"]:
		var per_level := {}
		var src: Dictionary = d.get(track, {})
		for lv in src:
			per_level[int(lv)] = src[lv]
		unlocks[track] = per_level


static func _load_streaks() -> void:
	streaks.clear()
	streak_order.clear()
	var d: Dictionary = load_json("res://data/streaks.json")
	for raw in d.get("rewards", []):
		streaks[str(raw["id"])] = raw
		streak_order.append(str(raw["id"]))


static func _load_maps() -> void:
	maps.clear()
	var dir := DirAccess.open("res://data/maps")
	if dir == null:
		errors.append("Missing res://data/maps")
		return
	for f in dir.get_files():
		if f.ends_with(".json"):
			var m: Dictionary = load_json("res://data/maps/" + f)
			if m.has("id"):
				maps[str(m["id"])] = m


## Expands an unlock entry into concrete ids (sets become their pieces).
static func expand_unlock(entry: String) -> Array:
	if entry.begins_with("set:"):
		var key := entry.substr(4)
		return sets.get(key, [])
	return [entry]


static func exists(entry: String) -> bool:
	if entry.begins_with("feature:"):
		return true
	if entry.begins_with("set:"):
		return sets.has(entry.substr(4))
	return items.has(entry) or spells.has(entry) or prayers.has(entry) or perks.has(entry)


# ---------------------------------------------------------------- validation

static func _validate() -> void:
	for id in items:
		var it: Dictionary = items[id]
		for key in ["id", "name", "slot", "bonuses", "style"]:
			if not it.has(key):
				errors.append("Item %s missing '%s'" % [id, key])
		var slot := str(it.get("slot", ""))
		if slot != "" and not EQUIP_SLOTS.has(slot):
			errors.append("Item %s has bad slot '%s'" % [id, slot])
		if it.has("spec") and not (it["spec"] as Dictionary).has("cost"):
			errors.append("Item %s spec missing cost" % id)
	for track in unlocks:
		for lv in unlocks[track]:
			for entry in unlocks[track][lv]:
				if not exists(str(entry)):
					errors.append("Unlock %s level %d references unknown '%s'" % [track, lv, entry])
	for sid in spells:
		var s: Dictionary = spells[sid]
		if not ["elemental", "forbidden"].has(str(s.get("book", ""))):
			errors.append("Spell %s has bad book" % sid)
	for pid in prayers:
		if not (prayers[pid] as Dictionary).has("groups"):
			errors.append("Prayer %s missing groups" % pid)
	for mk in modes.get("modes", {}):
		var m: Dictionary = modes["modes"][mk]
		for mp in m.get("maps", []):
			if not maps.has(str(mp)):
				errors.append("Mode %s references unknown map %s" % [mk, mp])
	for ck in classes.get("defaults", {}):
		var c: Dictionary = classes["defaults"][ck]
		for p in c.get("perks", []):
			if not perks.has(str(p)):
				errors.append("Class %s references unknown perk %s" % [ck, p])
