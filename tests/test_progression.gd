extends TestCase
## XP curve and titles must match the GDD 5 table.


func test_xp_table_matches_gdd() -> void:
	eq(Progression.xp_for_next(4), 740, "XP for level 5")
	eq(Progression.total_xp_for(5), 2670, "total to 5")
	eq(Progression.total_xp_for(10), 7190, "total to 10")
	eq(Progression.total_xp_for(20), 22440, "total to 20")
	eq(Progression.total_xp_for(30), 52410, "total to 30")
	eq(Progression.xp_for_next(39), 7850, "XP for level 40")
	eq(Progression.total_xp_for(40), 111400, "total to 40")


func test_level_for_xp() -> void:
	eq(Progression.level_for_xp(0), 1, "0 xp")
	eq(Progression.level_for_xp(599), 1, "just under 2")
	eq(Progression.level_for_xp(600), 2, "level 2")
	eq(Progression.level_for_xp(111400), 40, "max")
	eq(Progression.level_for_xp(999999), 40, "capped")


func test_combat_level_and_titles() -> void:
	eq(Progression.combat_level(40, 1, 1), 14, "avg rounds down")
	eq(Progression.title(1), "Recruit I", "title 1")
	eq(Progression.title(5), "Squire II", "title 5")
	eq(Progression.title(40), "Grandmaster", "title 40")


func test_unlocks() -> void:
	var u := Progression.unlocked_set({"melee": 5, "ranged": 1, "magic": 1})
	check(u.has("iron_scimitar"), "iron scim at melee 5")
	check(u.has("iron_platebody"), "set expands to pieces")
	check(not u.has("iron_dagger"), "iron dagger is level 6")
	check(u.has("ward_blades"), "protection prayers from the start")
	check(not u.has("feature:create_a_class"), "create-a-class at combat 4")
	var u2 := Progression.unlocked_set({"melee": 4, "ranged": 4, "magic": 4})
	check(u2.has("feature:create_a_class"), "create-a-class unlocked at combat 4")


func test_match_xp_routes_to_style() -> void:
	var f := Fighter.new()
	f.damage_by_style = {"melee": 0, "ranged": 50, "magic": 0}
	f.kill_styles = {"melee": 0, "ranged": 2, "magic": 0}
	var x := Progression.match_xp(f, true, 0, "melee")
	eq(x["melee"], 0, "no melee xp")
	eq(x["ranged"], 50 * 4 + 200 + 1000, "ranged gets damage, kills and all split XP")
	var g := Fighter.new()
	var y := Progression.match_xp(g, false, 0, "magic")
	eq(y["magic"], 300, "no damage: split goes to primary style")
