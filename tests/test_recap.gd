extends TestCase
## U6 death recap and fight report, from a scripted fight and from a recorded bot match.


func test_scripted_recap_and_report() -> void:
	var sim := make_duel()
	var a: Fighter = sim.fighters[1]
	var b: Fighter = sim.fighters[2]
	# A prays against magic; B hits A with ranged (wrong ward), then magic (right ward).
	a.active_prayers.append(_protect("magic"))
	sim._log_ward(a)
	sim._apply_hit({"land": sim.tick, "attacker": b.id, "target": a.id, "life": a.life_id, "dmg": 20, "raw": 20, "style": "ranged", "accurate": true,
		"max_hit": 25, "spec": "", "spell": "", "effects": {}, "protected": false, "ward": "magic", "weapon": "Oak shortbow", "weapon_type": "shortbow", "dist": 3})
	sim.tick += 1
	sim._apply_hit({"land": sim.tick, "attacker": b.id, "target": a.id, "life": a.life_id, "dmg": 6, "raw": 10, "style": "magic", "accurate": true,
		"max_hit": 20, "spec": "", "spell": "", "effects": {}, "protected": true, "ward": "magic", "weapon": "Ember Dart", "weapon_type": "staff", "dist": 3})
	# A eats a pike near full HP: some healing is wasted.
	var food := -1
	for i in range(28):
		if a.inventory[i] != null and str(a.inventory[i]["id"]) == "pike":
			food = i
			break
	a.hp = a.max_hp - 5
	sim._consume(a, food)
	sim.tick += 1
	a.hp = 3
	sim.deal_damage(a, 3, b.id, "ranged", {"weapon": "Oak shortbow", "land": 0})
	sim._process_deaths()
	var r := a.last_recap
	check(not r.is_empty(), "recap stored on death")
	eq(str(r["killer"]), b.name, "killer named")
	var hits: Array = r["hits"]
	eq(hits.size(), 2, "two attack hits logged")
	check(bool(hits[0]["wrong_ward"]), "ranged hit flagged as wrong ward")
	check(not bool(hits[1]["wrong_ward"]), "magic hit prayed correctly")
	eq(int(r["wrong_wards"]), 1, "one wrong-ward hit")
	eq((r["eats"] as Array).size(), 1, "the pike is in the recap")
	check(int(r["wasted_heal"]) > 0, "wasted healing counted")
	var rep := sim.clog.report(a.id, 10)
	near(float(rep["ward_accuracy"]), 0.5, 0.001, "1 of 2 incoming attacks prayed")
	eq(int(rep["deaths"]), 1, "one death")
	check(CombatLog.tip(rep) != "", "a tip is chosen")


func test_reaction_time_after_style_switch() -> void:
	var log := CombatLog.new()
	log.add({"k": "ward", "tick": 0, "f": 1, "ward": "melee"})
	log.add({"k": "hit", "tick": 10, "a": 2, "d": 1, "style": "melee", "weapon": "x", "spec": false, "ward": "melee", "dmg": 5})
	log.add({"k": "hit", "tick": 14, "a": 2, "d": 1, "style": "magic", "weapon": "x", "spec": false, "ward": "melee", "dmg": 5})
	log.add({"k": "ward", "tick": 17, "f": 1, "ward": "magic"})
	log.add({"k": "hit", "tick": 19, "a": 2, "d": 1, "style": "magic", "weapon": "x", "spec": false, "ward": "magic", "dmg": 0})
	var r := log.report(1, 20)
	eq(int(r["reaction_samples"]), 1, "one style switch seen")
	near(float(r["reaction_avg"]), 3.0, 0.001, "ward matched 3 ticks after the switch")
	near(float(r["ward_accuracy"]), 2.0 / 3.0, 0.001, "2 of 3 prayed")


## Recorded bot match: every death's recap accounts for at least all the HP lost, comes only from things the
## victim could see, and agrees with the kill feed.
func test_recorded_match_recaps_are_consistent() -> void:
	DB.ensure_loaded()
	var core := MatchServerCore.new()
	core.setup({"mode": "clan_clash", "map": "frostgate_ruins", "seed": 21, "pre_ticks": 1})
	var kills := {}  # victim -> [tick, killer]
	for i in range(700):
		core.tick()
		for e in core.sim.events:
			if str(e.get("type", "")) == "kill" and not e.has("npc"):
				kills["%d@%d" % [int(e["victim"]), core.sim.tick]] = int(e["killer"])
	var sim := core.sim
	var deaths := 0
	var allowed := ["tick", "attacker", "style", "weapon", "dmg", "ward", "wrong_ward", "splash", "spec"]
	for e in sim.clog.entries:
		if str(e["k"]) != "death":
			continue
		deaths += 1
		var vid := int(e["v"])
		var t := int(e["tick"])
		var r := sim.clog.recap(vid, t)
		var dmg := 0
		var last := -1
		for h in r["hits"]:
			for k in (h as Dictionary).keys():
				check(allowed.has(k), "recap only has visible fields (%s)" % k)
			check(int(h["tick"]) >= last and int(h["tick"]) <= t, "hits in order within the life")
			last = int(h["tick"])
			dmg += int(h["dmg"])
		var healed := 0
		for x in r["eats"]:
			healed += int(x["heal"]) - int(x["wasted"])
		check(dmg >= 99 + healed, "death %d@%d: recap damage %d covers 99 HP + %d healed" % [vid, t, dmg, healed])
		var key := "%d@%d" % [vid, t]
		if kills.has(key):
			eq(int(r["killer"]), int(kills[key]), "recap killer matches the kill feed")
	check(deaths >= 10, "recorded match had deaths (%d)" % deaths)
	for f in sim.fighters.values():
		var rep := sim.clog.report((f as Fighter).id, sim.live_ticks)
		check(float(rep["ward_accuracy"]) <= 1.0, "ward accuracy is a fraction")


func _protect(style: String) -> String:
	for p in DB.prayers:
		if str(DB.prayers[p].get("protect", "")) == style:
			return str(p)
	return ""
