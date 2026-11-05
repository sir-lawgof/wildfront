extends TestCase
## U7 The Lab: every mutator changes only data the game already reads, and works in play.


func _lab(mode: String, mut: String, seed: int = 5) -> MatchServerCore:
	DB.ensure_loaded()
	var core := MatchServerCore.new()
	core.setup({"mode": mode, "map": str(DB.modes["modes"][mode]["maps"][0]), "seed": seed, "pre_ticks": 1, "playlist": "lab", "mutator": mut})
	return core


func test_no_wards() -> void:
	var core := _lab("duel", "no_wards")
	var f: Fighter = core.sim.fighters.values()[0]
	core.sim.step()
	core.sim.queue_intent(f.id, {"type": "prayer", "id": "ward_blades"})
	core.sim.step()
	check(not f.has_prayer("ward_blades"), "wards can't be turned on")
	var off := _lab("duel", "spec_frenzy")
	var g: Fighter = off.sim.fighters.values()[0]
	off.sim.step()
	off.sim.queue_intent(g.id, {"type": "prayer", "id": "ward_blades"})
	off.sim.step()
	check(g.has_prayer("ward_blades"), "other mutators keep wards")


func test_iron_wards() -> void:
	var core := _lab("duel", "iron_wards")
	var a: Fighter = core.sim.fighters.values()[0]
	var b: Fighter = core.sim.fighters.values()[1]
	b.active_prayers.append("ward_blades")
	var h := core.sim.make_attack(a, b, "melee", {"fixed_damage": 20, "force_hit": true})
	eq(int(h["dmg"]), 8, "60% blocked: 20 -> 8")


func test_spec_frenzy() -> void:
	var core := _lab("duel", "spec_frenzy")
	var f: Fighter = core.sim.fighters.values()[0]
	f.spec_energy = 0
	var interval := int(DB.rule("spec_regen_interval", 50))
	for i in range(interval + 2):
		core.sim.step()
	eq(f.spec_energy, 20, "double regeneration (20 per interval)")


func test_frozen_front() -> void:
	var core := _lab("clan_clash", "frozen_front")
	for f in core.sim.fighters.values():
		eq((f as Fighter).weapon_style(), "magic", "everyone gets a magic kit")
	var t: Fighter = core.sim.fighters.values()[1]
	t.spawn_shield = 0
	core.sim._freeze(t, 8)
	eq(t.frozen_ticks, 16, "freezes last twice as long")


func test_low_rations() -> void:
	var normal := MatchServerCore.new()
	normal.setup({"mode": "duel", "map": "castle_courtyard", "seed": 5, "pre_ticks": 1, "playlist": "warlord"})
	var lab := _lab("duel", "low_rations")
	var nf: Fighter = normal.sim.fighters.values()[0]
	var lf: Fighter = lab.sim.fighters.values()[0]
	var cls: Dictionary = DB.classes["defaults"]["warrior"]
	var n_lo := Brackets.build_loadout("warlord", cls, "full")
	var l_lo := Brackets.build_loadout("warlord", cls, "full", Mutators.get_def("low_rations")["loadout"])
	var count := func(lo: Dictionary, id: String) -> int:
		return (lo["inventory"] as Array).filter(func(e): return e != null and str(e["id"]) == id).size()
	check(int(count.call(l_lo, "pike")) <= int(ceil(int(count.call(n_lo, "pike")) / 2.0)), "about half the main food")
	check(int(count.call(l_lo, "kelp_roll")) <= int(ceil(int(count.call(n_lo, "kelp_roll")) / 2.0)), "about half the combo food")
	check(nf != null and lf != null, "both matches set up")


func test_one_life_in_team_and_ffa_modes() -> void:
	for mode in ["clan_clash", "ffa"]:
		var core := _lab(mode, "one_life")
		eq(core.sim.rules.type, "elimination", "%s plays elimination rounds" % mode)
		check(not core.sim.rules.respawns(), "%s: no respawns" % mode)
		var rounds_seen := 0
		for i in range(4000):
			core.tick()
			for e in core.sim.events:
				if str(e.get("type", "")) == "round_end":
					rounds_seen += 1
			for f in core.sim.fighters.values():
				var fi: Fighter = f
				check(fi.respawn_ticks <= 0 or not fi.dead, "nobody waits to respawn")
			if core.sim.phase == "over":
				break
		check(rounds_seen >= 3, "%s: rounds were played (%d)" % [mode, rounds_seen])
		eq(core.sim.phase, "over", "%s: the match ends by rounds" % mode)


func test_weekly_rotation_and_votes() -> void:
	DB.ensure_loaded()
	var rot: Array = DB.mutators["rotation"]
	eq(Mutators.at_week(0), str(rot[0]), "week 0")
	eq(Mutators.at_week(rot.size()), str(rot[0]), "wraps")
	eq(Mutators.ids().size(), 6, "six mutators")
	var votes := {"3": {"mutator": Mutators.at_week(3), "keep": 2, "change": 1, "drop": 0}}
	var t := Mutators.tally(votes, 3)
	eq(int(t["keep"]), 2, "keep votes")
	eq(str(t["mutator"]), Mutators.at_week(3), "the week's mutator")
	# A vote saved into a telemetry record shows up in the report.
	var core := _lab("duel", "iron_wards")
	for i in range(30):
		core.tick()
	var s := core.summary(false)
	check(s.has("lab") and str(s["lab"]["mutator"]) == "iron_wards", "summary names the mutator")
	var rec: Dictionary = s["telemetry"]
	rec["lab"]["vote"] = "keep"
	check(Telemetry.report([rec]).contains("| Iron Wards | 1 | 0 | 0 |") or Telemetry.report([rec]).contains("| iron_wards | 1 | 0 | 0 |"), "vote counted in the telemetry report")
