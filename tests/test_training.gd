extends TestCase
## U1 Proving Grounds: every drill passes for a player who does it right and fails for one who doesn't;
## both exams run; the Graduation pass rate for a drill-trained player is inside the target band.


func _start(tid: String, seed: int = 3) -> MatchServerCore:
	DB.ensure_loaded()
	var core := MatchServerCore.new()
	core.setup({"training": tid, "seed": seed, "pre_ticks": 2,
		"player": {"name": "Student", "class_def": DB.classes["defaults"]["warrior"], "levels": {"melee": 40, "ranged": 40, "magic": 40}}})
	return core


## Runs until the drill ends; driver(core, me, bot) is called before every tick. Returns the final status.
func _run(core: MatchServerCore, driver: Callable, max_ticks: int = 400) -> String:
	var me := core.sim.get_fighter(core.player_id)
	var bot := core.training.bot
	for i in range(max_ticks):
		if core.sim.phase == "live" and driver.is_valid():
			driver.call(core, me, bot)
		core.tick()
		if core.training.status != "running":
			break
	return core.training.status


func _ward(style: String) -> String:
	return {"melee": "ward_blades", "ranged": "ward_arrows", "magic": "ward_spells"}[style]


func _idle(_c: MatchServerCore, _m: Fighter, _b: Fighter) -> void:
	pass


# ---------------------------------------------------------------- wards

func test_wards_drill() -> void:
	var good := func(c: MatchServerCore, me: Fighter, bot: Fighter) -> void:
		var want := _ward(bot.attack_style())
		if not me.has_prayer(want):
			c.submit(me.id, {"type": "prayer", "id": want})
	eq(_run(_start("wards"), good), "passed", "matching every style passes")
	eq(_run(_start("wards"), _idle), "failed", "never praying fails")


# ---------------------------------------------------------------- freezes

func test_freezes_drill() -> void:
	var good := func(c: MatchServerCore, me: Fighter, bot: Fighter) -> void:
		if c.training.stage == 1:
			if me.pending_spell == "" and me.attack_timer <= 0:
				c.submit(me.id, {"type": "cast", "spell": Loadout.best_freeze_spell(me.spellbook, me.unlocked), "target": bot.id})
		elif me.path.is_empty():
			var away := me.pos + (me.pos - bot.pos) * 4
			away = c.sim.map.nearest_walkable(Vector2i(clampi(away.x, 1, c.sim.map.w - 2), clampi(away.y, 1, c.sim.map.h - 2)))
			c.submit(me.id, {"type": "run", "on": true})
			c.submit(me.id, {"type": "move", "x": away.x, "y": away.y})
	var core := _start("freezes")
	eq(_run(core, good), "passed", "freeze then run away passes")
	eq(_run(_start("freezes"), _idle, 400), "failed", "doing nothing times out")


# ---------------------------------------------------------------- specials

func test_specials_drill() -> void:
	var good := func(c: MatchServerCore, me: Fighter, bot: Fighter) -> void:
		if me.target_id != bot.id:
			c.submit(me.id, {"type": "attack", "target": bot.id})
		var ready := (c.training.stage == 1 and bot.hp <= bot.max_hp / 2) or (c.training.stage == 2 and bot.frozen_ticks > 2)
		if ready and not me.spec_armed and me.spec_energy >= 25:
			c.submit(me.id, {"type": "spec"})
		elif not ready and me.spec_armed:
			c.submit(me.id, {"type": "spec"})  # disarm until the right moment
	eq(_run(_start("specials"), good, 500), "passed", "spec at low HP, then on a frozen target")
	var early := _start("specials")
	var eager := func(c: MatchServerCore, me: Fighter, bot: Fighter) -> void:
		if me.target_id != bot.id:
			c.submit(me.id, {"type": "attack", "target": bot.id})
		if not me.spec_armed and bot.hp > bot.max_hp * 0.8:
			c.submit(me.id, {"type": "spec"})
	_run(early, eager, 60)
	eq(early.training.stage, 1, "speccing at full HP doesn't count")


# ---------------------------------------------------------------- switching

func test_switching_drill() -> void:
	var order := ["ranged", "melee", "magic"]
	var good := func(c: MatchServerCore, me: Fighter, _bot: Fighter) -> void:
		if c.sim.live_ticks % 3 == 0:
			c.submit(me.id, {"type": "switch_set", "style": order[(c.sim.live_ticks / 3) % 3]})
	eq(_run(_start("switching"), good), "passed", "three full one-tick switches pass")
	var weapon_only := func(c: MatchServerCore, me: Fighter, _bot: Fighter) -> void:
		if c.sim.live_ticks % 3 == 0:
			var slot := me.find_item(func(it): return str(it.get("slot", "")) == "weapon")
			if slot >= 0:
				c.submit(me.id, {"type": "equip", "slot": slot})
	eq(_run(_start("switching"), weapon_only), "failed", "weapon-only swaps don't count")


# ---------------------------------------------------------------- combo eating

func _eat(c: MatchServerCore, me: Fighter, pred: Callable) -> void:
	var s := me.find_item(pred)
	if s >= 0:
		c.submit(me.id, {"type": "use", "slot": s})


func test_combo_eating_drill() -> void:
	var good := func(c: MatchServerCore, me: Fighter, _bot: Fighter) -> void:
		if me.hp < 60 and me.food_timer == 0 and me.combo_timer == 0 and me.potion_timer == 0:
			_eat(c, me, func(it): return str(it.get("timer", "")) == "food")
			_eat(c, me, func(it): return str(it.get("timer", "")) == "combo")
			_eat(c, me, func(it): return str(it.get("effect", "")) == "brew")
		elif me.hp < 85 and me.food_timer == 0:
			_eat(c, me, func(it): return str(it.get("timer", "")) == "food")
	eq(_run(_start("combo_eating"), good), "passed", "combo eating survives the bursts")
	var single := func(c: MatchServerCore, me: Fighter, _bot: Fighter) -> void:
		if me.hp < 85 and me.food_timer == 0:
			_eat(c, me, func(it): return str(it.get("timer", "")) == "food")
	eq(_run(_start("combo_eating"), single), "failed", "one food at a time isn't enough")


# ---------------------------------------------------------------- reading

func test_reading_drill() -> void:
	var good := func(c: MatchServerCore, me: Fighter, bot: Fighter) -> void:
		var s := bot.weapon_style()
		if c.training._n.get("my_call", "") != s or int(c.training._n.get("my_call_tick", -1)) < int(c.training._n.get("switch_tick", 0)):
			c.training._n["my_call"] = s
			c.training._n["my_call_tick"] = c.sim.tick + 1
			c.submit(me.id, {"type": "callout", "style": s})
	eq(_run(_start("reading"), good), "passed", "calling the visible weapon style passes")
	var wrong := func(c: MatchServerCore, me: Fighter, bot: Fighter) -> void:
		var s := bot.weapon_style()
		var other := "melee" if s != "melee" else "magic"
		c.submit(me.id, {"type": "callout", "style": other})
	eq(_run(_start("reading"), wrong), "failed", "wrong calls fail")


# ---------------------------------------------------------------- exams and dummy

## A "drill-trained" student (BotBrain at graduation_target.student_skill) plays the player's fighter.
func _exam(tid: String, seed: int) -> bool:
	var core := _start(tid, seed)
	var me := core.sim.get_fighter(core.player_id)
	var student := BotBrain.new(me.id, float(DB.training["graduation_target"]["student_skill"]), seed * 31 + 7)
	core.bots[me.id] = student
	for i in range(4000):
		core.tick()
		if core.sim.phase == "over":
			break
	return core.training.status == "passed"


func test_exams_and_graduation_pass_rate() -> void:
	DB.ensure_loaded()
	var n := 60
	var grad := 0
	var chal := 0
	for i in range(n):
		if _exam("graduation", 100 + i):
			grad += 1
		if _exam("instructors_challenge", 100 + i):
			chal += 1
	var rate := float(grad) / n
	var tgt: Dictionary = DB.training["graduation_target"]
	check(rate >= float(tgt["min"]) and rate <= float(tgt["max"]), "Graduation pass rate %.2f within %.2f-%.2f" % [rate, float(tgt["min"]), float(tgt["max"])])
	check(float(chal) / n < rate, "Instructor's Challenge is harder (%.2f vs %.2f)" % [float(chal) / n, rate])
	print("    graduation %.2f, instructor's challenge %.2f" % [rate, float(chal) / n])


func test_dummy_room_matches_combat_formulas() -> void:
	var core := _start("dummy")
	var me := core.sim.get_fighter(core.player_id)
	var bot := core.training.bot
	for i in range(60):
		if core.sim.phase == "live" and me.target_id != bot.id:
			core.submit(me.id, {"type": "attack", "target": bot.id})
		core.tick()
	var d: Dictionary = core.sim.training_status["dummy"]
	near(float(d["accuracy"]), Combat.hit_chance(Combat.attack_roll(me, me.attack_style()), Combat.defence_roll(bot, me.attack_style())), 0.0001, "accuracy from the shared formula")
	eq(int(d["max_hit"]), Combat.fighter_max_hit(me, me.attack_style(), me.current_spell()), "max hit from the shared formula")
	check(int(d["hits"]) > 0, "hits on the dummy are counted")
	check(bot.is_alive(), "the dummy never dies")


func test_every_training_starts_with_line_of_sight() -> void:
	for tid in Training.all_ids() + ["dummy"]:
		var core := _start(tid)
		var me := core.sim.get_fighter(core.player_id)
		var bot := core.training.bot
		check(core.sim.map.has_los(me.pos, bot.pos), "%s: player can see the opponent at the start" % tid)
		check(me.pos != bot.pos, "%s: separate tiles" % tid)
