extends TestCase
## Data files load, validate and expand into the items the GDD names.


func test_no_data_errors() -> void:
	eq(DB.errors.size(), 0, "DB errors: " + str(DB.errors))


func test_tiered_items_exist() -> void:
	for id in ["bronze_scimitar", "wyrmforged_scimitar", "oak_shortbow", "wyrmwood_longbow", "novice_staff",
			"star_staff", "adept_wand", "bronze_platebody", "leather_body", "woven_robe_top", "basilisk_hide_body",
			"bronze_arrows", "wyrmforged_bolts", "iron_defender", "bronze_throwing_knives"]:
		check(DB.has_item(id), "missing item " + id)
	eq(DB.item("star_staff").get("name"), "Starstaff", "tier 6 staff name")


func test_specials_only_top_tiers() -> void:
	check(not DB.item("orichalcum_scimitar").has("spec"), "tier 5 scimitar has no spec")
	check(DB.item("starmetal_scimitar").has("spec"), "tier 6 scimitar has spec")
	check(DB.item("whip").has("spec"), "whip has spec")


func test_tiers_scale_about_7_percent() -> void:
	# (bonus + 64) should grow by roughly 7% per tier for the scimitar's accuracy.
	var t1 := int(DB.item("bronze_scimitar")["bonuses"]["att_melee"]) + 64
	var t7 := int(DB.item("wyrmforged_scimitar")["bonuses"]["att_melee"]) + 64
	var per := pow(float(t7) / float(t1), 1.0 / 6.0) - 1.0
	check(per > 0.05 and per < 0.09, "per-tier growth %.3f" % per)


func test_combat_triangle_from_gear() -> void:
	# Plate: better melee defence than robes; robes better magic defence than plate.
	var plate := 0
	var robe_mag := 0
	var plate_mag := 0
	for id in DB.sets["plate:1"]:
		plate += int(DB.item(id)["bonuses"]["def_melee"])
		plate_mag += int(DB.item(id)["bonuses"]["def_magic"])
	for id in DB.sets["robe:1"]:
		robe_mag += int(DB.item(id)["bonuses"]["def_magic"])
	check(plate > 30, "plate melee defence")
	check(plate_mag < 0, "plate is weak to magic")
	check(robe_mag > plate_mag, "robes beat plate vs magic")


func test_every_level_unlocks_something() -> void:
	for track in ["melee", "ranged", "magic"]:
		for lv in range(1, 41):
			check(not (DB.unlocks[track].get(lv, []) as Array).is_empty(), "%s level %d unlocks nothing" % [track, lv])


func test_default_loadouts() -> void:
	var unl := Progression.unlocked_set({"melee": 1, "ranged": 1, "magic": 1})
	var w := Loadout.build(DB.classes["defaults"]["warrior"], unl, {"supply": "full"})
	eq(w["equipment"]["weapon"], "bronze_scimitar", "warrior weapon")
	eq(w["equipment"]["body"], "bronze_platebody", "warrior body")
	var a := Loadout.build(DB.classes["defaults"]["archer"], unl, {"supply": "full"})
	eq(a["equipment"]["ammo"], "bronze_arrows", "archer ammo")
	eq(a["equipment"]["shield"], "", "2h bow leaves shield empty")
	var b := Loadout.build(DB.classes["defaults"]["battlemage"], unl, {"supply": "full"})
	eq(b["autocast"], "ember_dart", "battlemage autocast")
	check(b["inventory"][0] != null and b["inventory"][0]["id"] == "bronze_scimitar", "battlemage carries scimitar")
	var t := Loadout.build(DB.classes["defaults"]["tribrid"], unl, {"supply": "full"})
	eq(t["equipment"]["ammo"], "bronze_arrows", "tribrid gets arrows for its bow switch")


func test_default_classes_auto_upgrade() -> void:
	var unl := Progression.unlocked_set({"melee": 20, "ranged": 10, "magic": 1})
	var w := Loadout.build(DB.classes["defaults"]["warrior"], unl, {"supply": "full"})
	eq(w["equipment"]["weapon"], "orichalcum_scimitar", "warrior upgrades weapon")
	eq(w["equipment"]["body"], "orichalcum_platebody", "warrior upgrades armour")
	var a := Loadout.build(DB.classes["defaults"]["archer"], unl, {"supply": "full"})
	eq(a["equipment"]["weapon"], "maple_shortbow", "archer upgrades bow")
	eq(a["equipment"]["ammo"], "steel_arrows", "archer upgrades arrows")
