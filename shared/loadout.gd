class_name Loadout
extends RefCounted
## Turns a class definition (default or create-a-class) plus the player's unlocks into
## concrete starting equipment, inventory and supplies for one life (GDD 6).


static func all_unlocked() -> Dictionary:
	var out := {}
	for id in DB.items:
		out[id] = true
	for id in DB.spells:
		out[id] = true
	for id in DB.prayers:
		out[id] = true
	for id in DB.perks:
		out[id] = true
	for track in DB.unlocks:
		for lv in DB.unlocks[track]:
			for e in DB.unlocks[track][lv]:
				out[str(e)] = true
	return out


## Best unlocked tier of a tiered weapon type (e.g. "scimitar"). "" if none.
static func best_weapon(type_key: String, unlocked: Dictionary) -> String:
	var best := ""
	var best_tier := 0
	for id in DB.items:
		var it: Dictionary = DB.items[id]
		if str(it.get("weapon_type", "")) == type_key and not it.get("unique", false) and unlocked.has(id):
			if int(it["tier"]) > best_tier:
				best_tier = int(it["tier"])
				best = id
	return best


## Best unlocked full tier set of an armour class ("plate", "hide", "robe").
static func best_set(cls: String, unlocked: Dictionary) -> Array:
	for t in range(DB.tiers.size(), 0, -1):
		var key := "%s:%d" % [cls, t]
		var ids: Array = DB.sets.get(key, [])
		var ok := not ids.is_empty()
		for id in ids:
			if not unlocked.has(str(id)):
				ok = false
				break
		if ok:
			return ids
	return []


static func best_ammo(ammo_type: String, unlocked: Dictionary) -> String:
	var best := ""
	var best_str := -1
	for id in DB.items:
		var it: Dictionary = DB.items[id]
		if str(it.get("slot", "")) == "ammo" and str(it.get("ammo_type", "")) == ammo_type and unlocked.has(id):
			# Plain ammo first; enchanted bolts are an explicit create-a-class choice.
			if it.has("bolt_effect"):
				continue
			var s := int(it["bonuses"]["str_ranged"])
			if s > best_str:
				best_str = s
				best = id
	return best


static func best_damage_spell(book: String, unlocked: Dictionary) -> String:
	var best := ""
	var best_hit := -1
	for sid in DB.spell_order:
		var s: Dictionary = DB.spells[sid]
		if str(s["book"]) != book or not unlocked.has(sid):
			continue
		if int(s["freeze"]) > 0 or int(s["area"]) > 1:
			continue
		if int(s["max_hit"]) > best_hit:
			best_hit = int(s["max_hit"])
			best = sid
	return best


static func best_freeze_spell(book: String, unlocked: Dictionary) -> String:
	var best := ""
	var best_f := -1
	for sid in DB.spell_order:
		var s: Dictionary = DB.spells[sid]
		if str(s["book"]) != book or not unlocked.has(sid) or int(s["freeze"]) <= 0:
			continue
		if int(s["freeze"]) * 2 + int(s["max_hit"]) > best_f:
			best_f = int(s["freeze"]) * 2 + int(s["max_hit"])
			best = sid
	return best


## Resolves "best:<type>", "best:<class>:<slot>" or a plain id.
static func resolve(ref: String, unlocked: Dictionary) -> String:
	if not ref.begins_with("best:"):
		return ref if (unlocked.has(ref) or ref == "") else ""
	var parts := ref.substr(5).split(":")
	if parts.size() == 2:
		for id in best_set(parts[0], unlocked):
			if str(DB.item(str(id)).get("slot", "")) == parts[1]:
				return str(id)
		return ""
	return best_weapon(parts[0], unlocked)


static func _accessory_score(it: Dictionary, style: String) -> float:
	var b: Dictionary = it.get("bonuses", {})
	var att: String = {"melee": "att_melee", "ranged": "att_ranged", "magic": "att_magic"}[style]
	var st: String = {"melee": "str_melee", "ranged": "str_ranged", "magic": "dmg_magic"}[style]
	var stw := 5.0 if style == "magic" else 1.5
	return float(b.get(att, 0)) + float(b.get(st, 0)) * stw + 0.2 * float(b.get("def_melee", 0) + b.get("def_ranged", 0) + b.get("def_magic", 0))


static func _best_accessory(slot: String, style: String, unlocked: Dictionary) -> String:
	var best := ""
	var best_score := 0.5
	for id in DB.items:
		var it: Dictionary = DB.items[id]
		if not it.get("unique", false) or str(it.get("slot", "")) != slot or not unlocked.has(id):
			continue
		if str(it.get("style", "")) != style:
			continue
		var sc := _accessory_score(it, style)
		if sc > best_score:
			best_score = sc
			best = id
	return best


## Main entry. class_def: entry from classes.json "defaults" or a custom class.
## opts: {supply: "full"|"skirmish", armour_classes: [allowed armour classes, empty = all], armour_fallback: class}
static func build(class_def: Dictionary, unlocked: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var eq := {}
	for s in DB.EQUIP_SLOTS:
		eq[s] = ""
	var inv: Array = []
	var is_default := str(class_def.get("primary", "")).begins_with("best:")
	var allowed_armour: Array = opts.get("armour_classes", [])
	var armour_ok := func(id: String) -> bool:
		var ac := str(DB.item(id).get("armour_class", ""))
		return allowed_armour.is_empty() or ac == "" or allowed_armour.has(ac)

	var primary := resolve(str(class_def.get("primary", "")), unlocked)
	if primary == "":
		primary = best_weapon("scimitar", unlocked)
	var pw := DB.item(primary)
	var style := str(pw.get("style", "melee"))
	eq["weapon"] = primary

	# Armour set.
	var armour_ids: Array = []
	var aref := str(class_def.get("armour", ""))
	if aref.begins_with("best:"):
		armour_ids = best_set(aref.substr(5), unlocked)
	elif aref.begins_with("set:"):
		for id in DB.expand_unlock(aref):
			if unlocked.has(str(id)):
				armour_ids.append(id)
	if not allowed_armour.is_empty():
		var replaced: Array = []
		for id in armour_ids:
			if not armour_ok.call(str(id)):
				continue
			replaced.append(id)
		if replaced.size() < armour_ids.size():
			var fb := str(opts.get("armour_fallback", ""))
			replaced = best_set(fb if fb != "" else str(allowed_armour[0]), unlocked)
		armour_ids = replaced
	for id in armour_ids:
		var it := DB.item(str(id))
		var slot := str(it["slot"])
		if slot == "shield" and bool(pw.get("two_handed", false)):
			continue
		eq[slot] = str(id)

	# Accessories: default classes pick the best unlocked; custom classes list them.
	if is_default:
		for slot in ["ring", "neck", "cape"]:
			var acc := _best_accessory(slot, style, unlocked)
			if acc != "":
				eq[slot] = acc
		if eq["shield"] == "" and not bool(pw.get("two_handed", false)):
			var off := _best_accessory("shield", style, unlocked)
			if off != "":
				eq["shield"] = off
	else:
		for acc in class_def.get("accessories", []):
			var it := DB.item(str(acc))
			if not it.is_empty() and unlocked.has(str(acc)):
				eq[str(it["slot"])] = str(acc)

	# Secondaries and switches go in the inventory.
	var secondaries: Array = []
	for ref in class_def.get("secondary", []):
		var id := resolve(str(ref), unlocked)
		if id != "" and id != primary:
			secondaries.append(id)
	var switches: Array = []
	for ref in class_def.get("switches", []):
		var id := resolve(str(ref), unlocked)
		if id != "":
			if not armour_ok.call(id):
				continue
			switches.append(id)
	switches = switches.slice(0, int(DB.classes.get("max_switches", 4)))

	# Ammo: for the primary if it needs it, otherwise for the first secondary that does.
	var ammo_type := str(pw.get("uses_ammo", ""))
	if ammo_type == "":
		for id in secondaries:
			var t := str(DB.item(str(id)).get("uses_ammo", ""))
			if t != "":
				ammo_type = t
				break
	if ammo_type != "":
		var chosen := str(class_def.get("ammo", ""))
		if chosen == "" or not unlocked.has(chosen) or str(DB.item(chosen).get("ammo_type", "")) != ammo_type:
			chosen = best_ammo(ammo_type, unlocked)
		eq["ammo"] = chosen

	for id in secondaries:
		inv.append({"id": id, "doses": 1})
	for id in switches:
		inv.append({"id": id, "doses": 1})

	# Perks: one per tier, must be unlocked.
	var perks: Array = []
	var tiers_used := {}
	for p in class_def.get("perks", []):
		var pd: Dictionary = DB.perks.get(str(p), {})
		if pd.is_empty() or not unlocked.has(str(p)) or tiers_used.has(int(pd["tier"])):
			continue
		tiers_used[int(pd["tier"])] = true
		perks.append(str(p))

	# Supplies.
	var packs: Dictionary = DB.classes.get("supply_packs", {})
	var pack: Dictionary = packs.get(str(opts.get("supply", "full")), packs.get("full", {}))
	var brews := int(pack.get("brew", 0))
	var restores := int(pack.get("restore", 0))
	if perks.has("extra_brew"):
		brews += 1
		restores += 1
	if unlocked.has("sanctum_brew"):
		for i in range(brews):
			inv.append({"id": "sanctum_brew", "doses": 4})
	if unlocked.has("restore_draught"):
		for i in range(restores):
			inv.append({"id": "restore_draught", "doses": 4})
	if perks.has("spare_spec"):
		inv.append({"id": "spec_tonic", "doses": 1})
	if unlocked.has("kelp_roll"):
		for i in range(int(round(int(pack.get("combo", 0)) * float(opts.get("food_mult", 1.0))))):
			inv.append({"id": "kelp_roll", "doses": 1})
	var food := int(round(int(class_def.get("main_food", 28)) * float(pack.get("main_food_scale", 1.0))))
	if perks.has("extra_rations"):
		food += int(pack.get("extra_rations", 3))
	food = int(round(food * float(opts.get("food_mult", 1.0))))  # The Lab's Low Rations
	food = clampi(food, 0, 28 - inv.size())
	for i in range(food):
		inv.append({"id": "pike", "doses": 1})
	while inv.size() < 28:
		inv.append(null)
	inv = inv.slice(0, 28)

	# Spellbook and autocast.
	var book := str(class_def.get("spellbook", "elemental"))
	if book == "forbidden" and not unlocked.has("feature:forbidden_book"):
		book = "elemental"
	var autocast := str(class_def.get("autocast", ""))
	if style == "magic":
		var forb_ok := bool(pw.get("forbidden", false))
		if book == "forbidden" and not forb_ok:
			book = "elemental"
		if autocast == "" or not unlocked.has(autocast) or str(DB.spells.get(autocast, {}).get("book", "")) != book:
			autocast = best_damage_spell(book, unlocked)
	else:
		autocast = ""

	return {
		"name": str(class_def.get("name", "Class")),
		"equipment": eq, "inventory": inv, "spellbook": book, "autocast": autocast,
		"perks": perks, "style": style, "primary": primary,
		"combat_boosts": unlocked.has("feature:combat_potions"),
		"allowed_armour": allowed_armour.duplicate(), "stats": {}, "weapon_mods": class_def.get("weapon_mods", {}),
		"spell_mods": class_def.get("spell_mods", {}),
	}
