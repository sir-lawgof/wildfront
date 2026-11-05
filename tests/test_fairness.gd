extends TestCase
## U5 fair fights (docs/COMMUNITY_UPDATES.md): kill credit and protected states.


## Duel sim plus a third fighter C (id 3) on A's team, all shields off, B on 40 HP.
func _three() -> Sim:
	var sim := make_duel()
	var unl := Progression.unlocked_set({"melee": 1, "ranged": 1, "magic": 1})
	var cid := sim.add_fighter("C", 0, false, Loadout.build(DB.classes["defaults"]["warrior"], unl, {"supply": "full"}), unl)
	sim.get_fighter(cid).spawn_shield = 0
	(sim.fighters[2] as Fighter).hp = 40
	return sim


func test_kill_goes_to_most_damage_not_last_hit() -> void:
	var sim := _three()
	var b: Fighter = sim.fighters[2]
	sim.deal_damage(b, 30, 1, "melee", {})
	sim.deal_damage(b, 10, 3, "ranged", {})
	sim._process_deaths()
	eq((sim.fighters[1] as Fighter).kills, 1, "A (30 dmg) gets the kill")
	eq((sim.fighters[3] as Fighter).kills, 0, "C (last hit, 10 dmg) doesn't")
	eq((sim.fighters[3] as Fighter).assists, 1, "C gets the assist")
	eq((sim.fighters[1] as Fighter).kill_styles["melee"], 1, "kill style is A's own last hit")


func test_kill_credit_window_and_tie() -> void:
	var sim := _three()
	var b: Fighter = sim.fighters[2]
	sim.deal_damage(b, 30, 1, "melee", {})
	sim.tick += int(DB.rule("kill_credit_window_ticks", 50)) + 1
	sim.deal_damage(b, 10, 3, "melee", {})
	sim._process_deaths()
	eq((sim.fighters[3] as Fighter).kills, 1, "old damage falls out of the window")
	var sim2 := _three()
	var b2: Fighter = sim2.fighters[2]
	sim2.deal_damage(b2, 20, 1, "melee", {})
	sim2.tick += 1
	sim2.deal_damage(b2, 20, 3, "melee", {})
	sim2._process_deaths()
	eq((sim2.fighters[3] as Fighter).kills, 1, "tie goes to the latest hitter")


func test_spawn_shield_blocks_everything() -> void:
	var sim := make_duel()
	var b: Fighter = sim.fighters[2]
	b.spawn_shield = 5
	var hp := b.hp
	sim.deal_damage(b, 20, 1, "typeless", {"streak": true, "weapon": "Meteor Strike"})
	sim.deal_damage(b, 5, 1, "poison", {})
	eq(b.hp, hp, "no damage from meteors, poison or any source while shielded")
	check(not sim._freeze(b, 8), "no freeze while shielded")
	sim.traps.append({"pos": b.pos, "team": 0, "owner": 1})
	check(not sim._check_trap(b), "trap doesn't fire on a shielded player")
	eq(sim.traps.size(), 1, "trap stays armed")
	b.spawn_shield = 0
	check(sim._check_trap(b), "trap fires once the shield is gone")


func test_no_trap_before_the_fight() -> void:
	DB.ensure_loaded()
	var sim := Sim.new()
	sim.setup("duel", "castle_courtyard", {"seed": 1, "pre_ticks": 20})
	var unl := Progression.unlocked_set({"melee": 40, "ranged": 40, "magic": 40})
	var cls: Dictionary = DB.classes["defaults"]["warrior"].duplicate(true)
	sim.add_fighter("A", 0, false, Loadout.build(cls, unl, {"supply": "full"}), unl)
	var a: Fighter = sim.fighters[1]
	a.perks.append("snare_trap")
	a.trap_available = true
	sim.queue_intent(1, {"type": "trap"})
	sim.step()
	eq(sim.traps.size(), 0, "no traps during pre-match")


## FFA sim with three fighters (ids 1-3) on their own teams, shields off.
func _ffa(mode: String = "ffa") -> Sim:
	DB.ensure_loaded()
	var sim := Sim.new()
	sim.setup(mode, "frostgate_ruins", {"seed": 3, "pre_ticks": 1})
	var unl := Progression.unlocked_set({"melee": 1, "ranged": 1, "magic": 1})
	for i in range(3):
		sim.add_fighter("P%d" % i, i, false, Loadout.build(DB.classes["defaults"]["warrior"], unl, {"supply": "full"}), unl)
	sim.step()
	for f in sim.fighters.values():
		(f as Fighter).spawn_shield = 0
	return sim


func test_engagement_blocks_third_party_and_expires() -> void:
	var sim := _ffa()
	var a: Fighter = sim.fighters[1]
	var b: Fighter = sim.fighters[2]
	var c: Fighter = sim.fighters[3]
	sim.rules.on_attack(a, b)
	check(not sim.rules.may_engage(c, a), "C can't attack A")
	check(not sim.rules.may_engage(c, b), "C can't attack B")
	check(not sim.rules.may_engage(a, c), "A can't attack C")
	check(sim.rules.may_engage(b, a), "B can fight back")
	sim.tick += sim.rules.engagement_ticks()
	check(sim.rules.may_engage(c, a), "timer ran out")
	sim.rules.on_attack(a, b)
	b.dead = true
	check(sim.rules.may_engage(c, a), "engagement ends when the partner dies")


func test_brawl_has_no_engagement_timer() -> void:
	var sim := _ffa("ffa_brawl")
	sim.rules.on_attack(sim.fighters[1], sim.fighters[2])
	check(sim.rules.may_engage(sim.fighters[3], sim.fighters[1]), "anyone can jump in")


## Seeded 8-bot FFA: no attack ever lands on a fighter engaged with someone else, and the
## timer did turn bots away.
func test_bot_ffa_respects_engagement() -> void:
	var core := MatchServerCore.new()
	core.setup({"mode": "ffa", "map": "frostgate_ruins", "seed": 7, "pre_ticks": 1})
	var sim := core.sim
	var violations := 0
	var attacks := 0
	for i in range(600):
		var before := {}
		for f in sim.fighters.values():
			var fi: Fighter = f
			before[fi.id] = [fi.engaged_with, fi.engaged_until]
		core.tick()
		for e in sim.events:
			if str(e.get("type", "")) != "attack":
				continue
			attacks += 1
			var aid := int(e["id"])
			var tid := int(e["target"])
			for pair in [[aid, tid], [tid, aid]]:
				var st: Array = before.get(pair[0], [-1, 0])
				var partner := sim.get_fighter(int(st[0]))
				if int(st[0]) != -1 and int(st[0]) != int(pair[1]) and sim.tick - 1 < int(st[1]) and partner != null and partner.is_alive():
					violations += 1
		if sim.phase == "over":
			break
	check(attacks > 50, "bots fought (%d attacks)" % attacks)
	eq(violations, 0, "no third-party attacks")


func test_afk_warning_then_bot_takeover() -> void:
	var core := MatchServerCore.new()
	core.setup({"mode": "duel", "map": "castle_courtyard", "seed": 5, "pre_ticks": 1,
		"player": {"name": "Me", "class_def": DB.classes["defaults"]["warrior"], "levels": {"melee": 10, "ranged": 10, "magic": 10}}})
	core.bots.clear()  # the opponent stands still, so only the AFK rule acts
	var me := core.sim.get_fighter(core.player_id)
	var warn := DB.ticks(float(DB.rule("afk_warn_s", 60)))
	var takeover := DB.ticks(float(DB.rule("afk_takeover_s", 90)))
	var warned_at := -1
	var start := -1
	for i in range(takeover + 20):
		core.tick()
		if start == -1 and core.sim.phase == "live":
			start = core.sim.tick
		if me.afk and warned_at == -1:
			warned_at = core.sim.tick
		if me.left_match:
			break
	eq(warned_at - start, warn, "AFK warning after afk_warn_s")
	check(me.left_match, "bot took over")
	check(core.bots.has(me.id) and me.is_bot, "fighter now driven by a tagged bot")
	check(bool(core.summary(false)["forfeit"]), "match counts as left")
	check(warn < takeover, "warning comes before takeover")


func test_kill_on_afk_player_scores_but_gives_no_xp() -> void:
	var sim := _ffa()
	var b: Fighter = sim.fighters[2]
	b.hp = 40
	b.afk = true
	var before: int = sim.scores[0]
	sim.deal_damage(b, 40, 1, "melee", {})
	sim._process_deaths()
	var a: Fighter = sim.fighters[1]
	eq(a.kills, 0, "no kill stat (no kill XP)")
	eq(a.challenge_events.filter(func(e): return str(e["type"]) == "kill").size(), 0, "no challenge progress")
	eq(sim.scores[0], before + 1, "team still scores")


func test_lan_leaver_is_taken_over() -> void:
	var core := MatchServerCore.new()
	var cls: Dictionary = DB.classes["defaults"]["warrior"]
	core.setup({"mode": "duel", "map": "castle_courtyard", "seed": 2, "pre_ticks": 1, "players": [
		{"name": "Host", "class_def": cls, "levels": {"melee": 1, "ranged": 1, "magic": 1}, "peer": 1},
		{"name": "Guest", "class_def": cls, "levels": {"melee": 1, "ranged": 1, "magic": 1}, "peer": 42}]})
	var fid := int(core.peer_to_fid[42])
	core.peer_left(42)
	check(core.bots.has(fid), "a bot plays the leaver's fighter")
	check(core.sim.get_fighter(fid).left_match, "flagged as left")
	check(bool(core.summary(false, fid)["forfeit"]), "counts as a loss")


func test_human_only_challenges_ignore_bot_kills() -> void:
	DB.ensure_loaded()
	var list: Array = Challenges.data()["challenges"]
	list.append({"id": "_t_human", "name": "Test Human", "cat": "shared", "event": "kill", "target": 2, "xp": 0, "human_only": true})
	var progress := {}
	var r := Challenges.process([{"type": "kill", "style": "melee", "victim_bot": true}, {"type": "kill", "style": "melee", "victim_bot": false}], progress, [], {})
	list.pop_back()
	eq(int(progress.get("_t_human", 0)), 1, "only the human kill counts")
	eq(int(progress.get("brawler", 0)), 2, "normal challenges still count bot kills")
	check(r != null, "processed")


func test_leave_cooldown_escalates() -> void:
	DB.ensure_loaded()
	var now := 1_000_000
	eq(Progression.leave_cooldown_s([now], now), 0, "first leave: no cooldown")
	eq(Progression.leave_cooldown_s([now - 100, now], now), 120, "second: 2 min")
	eq(Progression.leave_cooldown_s([now - 300, now - 100, now], now), 300, "third: 5 min")
	eq(Progression.leave_cooldown_s([now - 400, now - 300, now - 100, now, now], now), 900, "then 15 min, repeating")
	eq(Progression.leave_cooldown_s([now - 90000, now], now), 0, "old leaves fall out of the 24 h window")


## Exploit review: each protected state against attacks, damage (traps/meteors/Reckoning/poison) and freezes.
func test_protected_states_matrix() -> void:
	for state in ["none", "shield", "dying", "dead", "out_of_round"]:
		var sim := make_duel()
		var b: Fighter = sim.fighters[2]
		var a: Fighter = sim.fighters[1]
		match state:
			"shield": b.spawn_shield = 5
			"dying": b.dying = true
			"dead": b.dead = true
			"out_of_round": b.out_of_round = true
		var hp := b.hp
		sim.deal_damage(b, 10, a.id, "typeless", {"streak": true})
		if state == "none":
			eq(b.hp, hp - 10, "control: damage lands")
			b.hp = hp
		else:
			eq(b.hp, hp, "%s: no damage" % state)
		if state == "shield":
			check(not sim._freeze(b, 8), "shield: no freeze")
		a.pos = b.pos + Vector2i(1, 0)
		a.target_id = b.id
		a.attack_timer = 0
		sim.events.clear()
		sim._attack(a)
		eq(sim.events.filter(func(e): return str(e.get("type", "")) == "attack").size(), 1 if state == "none" else 0, "%s: attack made only when unprotected" % state)
	# Pre-match: no attacks before the fight starts.
	DB.ensure_loaded()
	var pre := Sim.new()
	pre.setup("duel", "castle_courtyard", {"seed": 1, "pre_ticks": 20})
	var unl := Progression.unlocked_set({"melee": 1, "ranged": 1, "magic": 1})
	pre.add_fighter("A", 0, false, Loadout.build(DB.classes["defaults"]["warrior"], unl, {"supply": "full"}), unl)
	pre.add_fighter("B", 1, false, Loadout.build(DB.classes["defaults"]["warrior"], unl, {"supply": "full"}), unl)
	var pa: Fighter = pre.fighters[1]
	var pb: Fighter = pre.fighters[2]
	pa.spawn_shield = 0
	pb.spawn_shield = 0
	pa.pos = pb.pos + Vector2i(1, 0)
	pre.queue_intent(1, {"type": "attack", "target": 2})
	pre.step()
	eq(pre.events.filter(func(e): return str(e.get("type", "")) == "attack").size(), 0, "pre-match: no attack")
	eq(pb.hp, pb.max_hp, "pre-match: no damage")
