extends TestCase
## U10 quality of life (docs/COMMUNITY_UPDATES.md): per-staff autocast memory and gear presets.


func _mage() -> Sim:
	DB.ensure_loaded()
	var sim := Sim.new()
	sim.setup("duel", "castle_courtyard", {"seed": 1, "pre_ticks": 1})
	var unl := Progression.unlocked_set({"melee": 40, "ranged": 40, "magic": 40})
	sim.add_fighter("A", 0, false, Loadout.build(DB.classes["defaults"]["battlemage"], unl, {"supply": "full"}), unl)
	sim.add_fighter("B", 1, false, Loadout.build(DB.classes["defaults"]["warrior"], unl, {"supply": "full"}), unl)
	sim.step()
	return sim


func _slot_of(f: Fighter, id: String) -> int:
	for i in range(28):
		if f.inventory[i] != null and str(f.inventory[i]["id"]) == id:
			return i
	return -1


func _free(f: Fighter) -> int:
	for i in range(28):
		if f.inventory[i] == null:
			return i
	return -1


func test_each_staff_remembers_its_autocast() -> void:
	var sim := _mage()
	var f: Fighter = sim.fighters[1]
	var staff1 := str(f.equipment["weapon"])
	var staff2 := ""
	for id in DB.items:
		var it: Dictionary = DB.items[id]
		if str(it.get("weapon_type", "")) == "staff" and str(id) != staff1 and not bool(it.get("forbidden", false)):
			staff2 = str(id)
			break
	var spells: Array = []
	for sid in DB.spells:
		if str(DB.spells[sid]["book"]) == "elemental" and f.unlocked.has(sid) and sim._spell_usable(f, sid, false):
			spells.append(sid)
	check(staff2 != "" and spells.size() >= 2, "test needs two staves and two spells")
	if staff2 == "" or spells.size() < 2:
		return
	var s1: String = spells[0]
	var s2: String = spells[1]
	f.inventory[_free(f)] = {"id": staff2, "doses": 1}
	sim.queue_intent(1, {"type": "spell", "spell": s1})
	sim.step()
	sim.queue_intent(1, {"type": "equip", "slot": _slot_of(f, staff2)})
	sim.step()
	eq(str(f.equipment["weapon"]), staff2, "second staff on")
	sim.queue_intent(1, {"type": "spell", "spell": s2})
	sim.step()
	eq(f.autocast, s2, "second staff autocasts s2")
	sim.queue_intent(1, {"type": "equip", "slot": _slot_of(f, staff1)})
	sim.step()
	eq(f.autocast, s1, "first staff gets s1 back")
	sim.queue_intent(1, {"type": "equip", "slot": _slot_of(f, staff2)})
	sim.step()
	eq(f.autocast, s2, "second staff gets s2 back")


func test_gear_preset_equips_listed_items() -> void:
	var sim := _mage()
	var f: Fighter = sim.fighters[1]
	var staff := str(f.equipment["weapon"])
	var melee := ""
	for i in range(28):
		if f.inventory[i] != null and str(DB.item(str(f.inventory[i]["id"])).get("slot", "")) == "weapon":
			melee = str(f.inventory[i]["id"])
	check(melee != "", "battlemage carries a melee weapon")
	sim.queue_intent(1, {"type": "equip_set", "ids": [melee, "not_an_item"]})
	sim.step()
	eq(str(f.equipment["weapon"]), melee, "preset equipped the weapon (unknown ids ignored)")
	sim.queue_intent(1, {"type": "equip_set", "ids": [staff]})
	sim.step()
	eq(str(f.equipment["weapon"]), staff, "and back")
