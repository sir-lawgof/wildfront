extends TestCase
## U2 brackets: fixed kits, stat overrides, gear limits, weekly featured bracket.


func test_every_bracket_builds_every_kit() -> void:
	DB.ensure_loaded()
	for bid in Brackets.ids():
		for ck in DB.classes["defaults"]:
			var lo := Brackets.build_loadout(bid, DB.classes["defaults"][ck], "full")
			var w := str(lo["equipment"]["weapon"])
			check(w != "", "%s/%s has a weapon" % [bid, ck])
			for slot in lo["equipment"]:
				var id := str(lo["equipment"][slot])
				if id != "":
					check(Brackets.item_allowed(bid, id), "%s/%s: %s allowed" % [bid, ck, id])
			for e in lo["inventory"]:
				if e != null:
					check(Brackets.item_allowed(bid, str(e["id"])), "%s/%s: inventory %s allowed" % [bid, ck, e["id"]])


func test_kits_are_fixed_regardless_of_player_unlocks() -> void:
	DB.ensure_loaded()
	var cls: Dictionary = DB.classes["defaults"]["warrior"]
	var core_lo := Brackets.build_loadout("vanguard", cls, "full")
	var low := MatchServerCore.new()
	low.setup({"mode": "duel", "map": "castle_courtyard", "seed": 1, "playlist": "vanguard", "pre_ticks": 1,
		"player": {"name": "New", "class_def": cls, "levels": {"melee": 1, "ranged": 1, "magic": 1}}})
	var me := low.sim.get_fighter(low.player_id)
	eq(me.equipment, core_lo["equipment"], "a level-1 player gets the same Vanguard kit")
	eq(int(me.base_levels["defence"]), 70, "Vanguard Defence 70")


func test_skirmisher_rules() -> void:
	DB.ensure_loaded()
	var lo := Brackets.build_loadout("skirmisher", DB.classes["defaults"]["warrior"], "full")
	eq(str(DB.item(str(lo["equipment"]["body"])).get("armour_class", "")), "hide", "plate swapped for hide")
	var sim := Sim.new()
	sim.setup("duel", "castle_courtyard", {"seed": 1, "pre_ticks": 1})
	var fid := sim.add_fighter("A", 0, false, lo, Brackets.unlocked("skirmisher"))
	var f := sim.get_fighter(fid)
	eq(int(f.base_levels["defence"]), 1, "Defence 1")
	eq(int(f.base_levels["attack"]), int(DB.rule("base_level", 99)), "other stats untouched")
	var plate := str(DB.sets["plate:1"][0])
	f.inventory[27] = {"id": plate, "doses": 1}
	check(not sim._equip(f, 27), "plate can't be equipped")
	check(not Brackets.unlocked("skirmisher").has(plate), "plate not in the kit unlocks")


func test_vanguard_bans_uniques_and_warlord_has_all() -> void:
	DB.ensure_loaded()
	for id in DB.items:
		if bool(DB.items[id].get("unique", false)):
			check(not Brackets.unlocked("vanguard").has(id), "vanguard bans unique " + str(id))
			break
	eq(Brackets.unlocked("warlord").size(), Loadout.all_unlocked().size(), "warlord = every unlock")


func test_featured_bracket_is_weekly_and_deterministic() -> void:
	DB.ensure_loaded()
	var epoch := int(Time.get_unix_time_from_datetime_string(str(DB.brackets["rotation_epoch"])))
	var rot: Array = DB.brackets["rotation"]
	eq(Brackets.featured(epoch + 10), str(rot[0]), "week 0")
	eq(Brackets.featured(epoch + 604800 * 6 + 5), str(rot[0]), "same after a full cycle")
	eq(Brackets.featured(epoch + 604800 + 1), str(rot[1]), "week 1")
	eq(Brackets.featured(epoch + 3600), Brackets.featured(epoch + 3600 * 100), "stable within a week")
	eq(Brackets.seconds_to_rotation(epoch + 100), 604800 - 100, "countdown")


func test_every_bracket_plays_in_every_mode() -> void:
	DB.ensure_loaded()
	for pl in DB.modes["playlists"]:
		for mode in DB.modes["modes"]:
			var core := MatchServerCore.new()
			core.setup({"mode": mode, "map": str(DB.modes["modes"][mode]["maps"][0]), "seed": 4, "playlist": pl, "pre_ticks": 1})
			for i in range(40):
				core.tick()
			check(core.sim.fighters.size() >= 2, "%s in %s runs" % [pl, mode])
			check(core.sim.phase != "pre", "%s in %s went live" % [pl, mode])


func test_validator_catches_bad_brackets() -> void:
	DB.ensure_loaded()
	var saved: Dictionary = DB.brackets.duplicate(true)
	DB.brackets["brackets"]["bad"] = {"name": "Bad", "kit_levels": "all", "stats": {"luck": 5}, "allowed_armour": ["paper"], "kits": {}}
	DB.brackets["rotation"].append("nope")
	var errs: Array[String] = []
	Brackets.validate(errs)
	DB.brackets = saved
	Brackets._unl_cache = {}
	check(errs.size() >= 4, "unknown stat, armour class, missing kits, rotation id: %s" % str(errs))
