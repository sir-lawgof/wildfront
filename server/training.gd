class_name Training
extends RefCounted
## Proving Grounds (U1): sets up drills, exams and the dummy room from data/training.json and judges them
## on the server, each tick, from the sim and its combat log. The judge writes sim.training_status for the
## HUD and ends the match when the drill is passed or failed.

var core: MatchServerCore
var id: String = ""
var def: Dictionary = {}
var kind: String = ""          ## drill | exam | dummy
var player: Fighter
var bot: Fighter
var brain: BotBrain
var status: String = "running" ## running | passed | failed
var stage: int = 1
var note: String = ""
var _n: Dictionary = {}        ## counters per goal
var _prev_eq: Dictionary = {}
var _log_from: int = 0         ## combat log index already judged


static func data() -> Dictionary:
	return DB.training


static func find(tid: String) -> Dictionary:
	for d in data().get("drills", []):
		if str(d["id"]) == tid:
			return {"kind": "drill", "def": d}
	for e in data().get("exams", []):
		if str(e["id"]) == tid:
			return {"kind": "exam", "def": e}
	var dm: Dictionary = data().get("dummy", {})
	if str(dm.get("id", "")) == tid:
		return {"kind": "dummy", "def": dm}
	return {}


static func all_ids() -> Array:
	var out: Array = []
	for d in data().get("drills", []):
		out.append(str(d["id"]))
	for e in data().get("exams", []):
		out.append(str(e["id"]))
	return out


## Builds a kit from {bracket, kit}: kit "player" maps the player's own class into the bracket
## (or, with no bracket, uses their own unlocks).
static func kit_loadout(kit: Dictionary, player_class: Dictionary, player_levels: Dictionary, supply: String) -> Array:
	var bid := str(kit.get("bracket", ""))
	var key := str(kit.get("kit", "melee"))
	if bid == "":
		var unl := Progression.unlocked_set(player_levels)
		return [Loadout.build(player_class, unl, {"supply": supply}), unl]
	var cls := player_class
	if key != "player":
		cls = (Brackets.get_def(bid)["kits"] as Dictionary).get(key, {})
	return [Brackets.build_loadout(bid, cls, supply), Brackets.unlocked(bid)]


## Called by MatchServerCore.setup when cfg has "training".
func setup(p_core: MatchServerCore, cfg: Dictionary) -> void:
	core = p_core
	id = str(cfg["training"])
	var f := find(id)
	kind = str(f.get("kind", ""))
	def = f.get("def", {})
	var player_cfg: Dictionary = cfg.get("player", {})
	var pclass: Dictionary = player_cfg.get("class_def", DB.classes["defaults"]["warrior"])
	var plevels: Dictionary = player_cfg.get("levels", {"melee": 40, "ranged": 40, "magic": 40})
	var opts := {"seed": core.rng.randi(), "pre_ticks": int(cfg.get("pre_ticks", 5)), "no_afk": true}
	var mode_id := "training"
	if kind == "exam":
		mode_id = "duel"
		opts["mode_overrides"] = {"rounds_to_win": int(def.get("rounds_to_win", 2))}
	var sim := Sim.new()
	core.sim = sim
	sim.setup(mode_id, str(data().get("map", "castle_courtyard")), opts)
	var supply := str(sim.mode.get("supply", "full"))
	var pk: Array = kit_loadout(def.get("player_kit", {"bracket": "warlord", "kit": "melee"}), pclass, plevels, supply)
	var pid := sim.add_fighter(str(player_cfg.get("name", "You")).left(12), 0, false, pk[0], pk[1], plevels)
	core.player_id = pid
	core.humans[pid] = 1
	core.peer_to_fid[1] = pid
	player = sim.get_fighter(pid)
	if def.has("player_inventory"):
		_set_inventory(player, def["player_inventory"])
	var bdef: Dictionary = def.get("bot", {"name": "Training Dummy", "kit": {"bracket": "warlord", "kit": "melee"}, "config": {"mode": "passive", "pray": false}})
	var bk: Array = kit_loadout(bdef.get("kit", {}), pclass, plevels, supply)
	var bid := sim.add_fighter(str(bdef.get("name", "Dummy")), 1, true, bk[0], bk[1], {"melee": 40, "ranged": 40, "magic": 40})
	bot = sim.get_fighter(bid)
	var cfgb: Dictionary = bdef.get("config", {"mode": "passive", "pray": false})
	bot.dmg_out_mult = float(cfgb.get("damage_mult", 1.0))
	brain = BotBrain.new(bid, float(cfgb.get("skill", 0.7)), core.rng.randi())
	brain.configure(cfgb)
	core.bots[bid] = brain
	# Face off in the open near the middle of the courtyard, with line of sight.
	var gap := 6 if (kind == "drill" and str(def.get("goal", {}).get("type", "")) == "freezes") else 5
	var mid := Vector2i(sim.map.w / 2, sim.map.h / 2)
	for dy in [3, -3, 5, -5, 7, -7, 0]:
		var a := sim.map.nearest_walkable(mid + Vector2i(-gap / 2, dy))
		var b := sim.map.nearest_walkable(mid + Vector2i(gap - gap / 2, dy))
		if sim.map.has_los(a, b) and a.y == b.y:
			player.pos = a
			bot.pos = b
			break
	player.trail = [player.pos]
	bot.trail = [bot.pos]
	_publish()


func _set_inventory(f: Fighter, spec: Array) -> void:
	var inv: Array = []
	for row in spec:
		var iid := str(row[0])
		var it := DB.item(iid)
		for i in range(int(row[1])):
			inv.append({"id": iid, "doses": int(it.get("doses", 1))})
	var keep: Array = []
	for e in f.inventory:
		if e != null and str(DB.item(str(e["id"])).get("slot", "")) != "":
			keep.append(e)
	inv = keep + inv
	while inv.size() < 28:
		inv.append(null)
	f.inventory = inv.slice(0, 28)
	f.loadout["inventory"] = f.inventory.duplicate(true)


func goal() -> Dictionary:
	return def.get("goal", {})


## After every sim tick.
func tick() -> void:
	var sim := core.sim
	if status != "running":
		return
	if sim.phase == "over":
		if kind == "exam":
			_finish(int(sim.result.get("winner", -1)) == player.team, "")
		elif status == "running":
			_finish(false, "Out of time.")
		return
	if sim.phase != "live":
		_publish()
		return
	var new: Array = sim.clog.entries.slice(_log_from)
	_log_from = sim.clog.entries.size()
	match kind:
		"drill":
			if player.dead or player.dying:
				_finish(false, "You were knocked out. Try again!")
				return
			_keep_bot_alive()
			match str(goal().get("type", "")):
				"wards": _judge_wards(new)
				"freezes": _judge_freezes(new)
				"specials": _judge_specials(new)
				"switching": _judge_switching()
				"combo_eating": _judge_combo(new)
				"reading": _judge_reading(new)
			if status == "running" and sim.live_ticks >= DB.ticks(float(def.get("time_limit_s", 120))):
				_finish(false, "Out of time.")
		"exam":
			note = "Round %d  -  you %d : %d %s" % [sim.rules.round_num, sim.scores[player.team], sim.scores[bot.team], bot.name]
		"dummy":
			_keep_bot_alive()
			_judge_dummy(new)
	_publish()


func _keep_bot_alive() -> void:
	if bot.hp < 30 and goal().get("type", "") != "specials":
		bot.hp = bot.max_hp
	elif bot.hp < 12:
		bot.hp = bot.max_hp
		note = "The target patches itself up."


func _finish(passed: bool, why: String) -> void:
	status = "passed" if passed else "failed"
	if why != "":
		note = why
	elif passed:
		note = "Passed!"
	else:
		note = "Not this time."
	_publish()
	core.sim.end_match(player.team if passed else bot.team)


func _publish() -> void:
	core.sim.training_status = {
		"id": id, "kind": kind, "name": str(def.get("name", "")), "desc": str(def.get("desc", "")),
		"label": str(def.get("label", "")), "status": status, "stage": stage, "note": note,
		"progress": _progress_text(), "callouts": str(goal().get("type", "")) == "reading",
		"dummy": _n.get("dummy", {}),
	}


func _progress_text() -> String:
	match str(goal().get("type", "")):
		"wards":
			return "Correct wards: %d / %d needed  (%d attacks of %d)" % [int(_n.get("ok", 0)), int(goal()["need"]), int(_n.get("seen", 0)), int(goal()["attacks"])]
		"freezes":
			return "Stage 1: freeze the runner" if stage == 1 else "Stage 2: get more than %d tiles from the freezer (now %d)" % [int(goal()["escape_distance"]) - 1, MapGrid.chebyshev(player.pos, bot.pos)]
		"specials":
			return "Stage 1: land a special attack at %d%% HP or lower" % int(float(goal()["hp_fraction"]) * 100) if stage == 1 else "Stage 2: land a special attack on the frozen target"
		"switching":
			return "One-tick switches: %d / %d" % [int(_n.get("done", 0)), int(goal()["count"])]
		"combo_eating":
			return "Bursts survived: %d / %d   Combo eats: %d" % [int(_n.get("survived", 0)), int(goal()["bursts"]), int(_n.get("combos", 0))]
		"reading":
			return "Correct calls: %d / %d needed  (%d attacks of %d)" % [int(_n.get("ok", 0)), int(goal()["need"]), int(_n.get("seen", 0)), int(goal()["attacks"])]
	return ""


# ---------------------------------------------------------------- drill judges

func _judge_wards(new: Array) -> void:
	for e in new:
		if str(e["k"]) == "hit" and int(e["d"]) == player.id and int(e["a"]) == bot.id and DB.STYLES.has(str(e["style"])):
			_n["seen"] = int(_n.get("seen", 0)) + 1
			if str(e["ward"]) == str(e["style"]):
				_n["ok"] = int(_n.get("ok", 0)) + 1
	var need := int(goal()["need"])
	var total := int(goal()["attacks"])
	if int(_n.get("ok", 0)) >= need:
		_finish(true, "")
	elif int(_n.get("seen", 0)) - int(_n.get("ok", 0)) > total - need:
		_finish(false, "Too many wrong wards. Watch the weapon, then switch.")


func _judge_freezes(new: Array) -> void:
	var sim := core.sim
	if stage == 1:
		for e in new:
			if str(e["k"]) == "freeze" and int(e["a"]) == player.id and int(e["d"]) == bot.id:
				stage = 2
				note = "Frozen! Now the freezer comes for you. Run!"
				var cfg2: Dictionary = def.get("stage2_bot_config", {"mode": "freezer"})
				brain.configure(cfg2)
				bot.dmg_out_mult = float(cfg2.get("damage_mult", 0.0))
				bot.frozen_ticks = 0
				bot.freeze_immune_ticks = 0
				var start := int(goal().get("escape_start_distance", 4))
				bot.pos = sim.map.nearest_walkable(player.pos + Vector2i(start, 0))
				bot.trail = [bot.pos]
				bot.path.clear()
				return
		return
	if player.frozen_ticks > 0:
		note = "Frozen. Wait it out, then move while you're immune."
		return
	if MapGrid.chebyshev(player.pos, bot.pos) >= int(goal()["escape_distance"]):
		_finish(true, "")


func _judge_specials(new: Array) -> void:
	var sim := core.sim
	var frac := float(goal()["hp_fraction"])
	player.spec_energy = 100  # practice: energy never runs out, timing is what's being taught
	if stage == 2:
		var every := int(goal().get("freeze_every_ticks", 20))
		if bot.frozen_ticks == 0 and sim.live_ticks % every == 0:
			bot.freeze_immune_ticks = 0
			sim._freeze(bot, int(goal().get("freeze_ticks", 16)), -1)
			note = "Varn freezes the target. Spec it now!"
	for e in new:
		if str(e["k"]) == "hit" and int(e["a"]) == player.id and int(e["d"]) == bot.id and bool(e.get("spec", false)) and int(e["dmg"]) > 0:
			if stage == 1:
				# HP before this hit landed.
				if float(bot.hp + int(e["dmg"])) <= frac * bot.max_hp:
					stage = 2
					note = "Good timing. Now spec a frozen target."
					bot.hp = bot.max_hp
				else:
					note = "Too early: wait until the target is at %d%% HP or lower." % int(frac * 100)
			elif bot.frozen_ticks > 0:
				_finish(true, "")
				return


func _judge_switching() -> void:
	var eq := player.equipment.duplicate()
	if not _prev_eq.is_empty():
		var w0 := str(DB.item(str(_prev_eq["weapon"])).get("style", ""))
		var w1 := str(DB.item(str(eq["weapon"])).get("style", ""))
		if w0 != w1 and str(_prev_eq["body"]) != str(eq["body"]) and str(_prev_eq["legs"]) != str(eq["legs"]):
			var want: String = {"melee": "plate", "ranged": "hide", "magic": "robe"}.get(w1, "")
			if str(DB.item(str(eq["body"])).get("armour_class", "")) == want and str(DB.item(str(eq["legs"])).get("armour_class", "")) == want:
				_n["done"] = int(_n.get("done", 0)) + 1
				note = "Clean switch to %s!" % w1
				if int(_n["done"]) >= int(goal()["count"]):
					_finish(true, "")
		elif w0 != w1:
			note = "Weapon only. Switch the body and legs in the same tick too."
	_prev_eq = eq


func _judge_combo(new: Array) -> void:
	var sim := core.sim
	var t := sim.live_ticks
	var first := int(goal().get("first_burst_tick", 5))
	var every := int(goal().get("interval_ticks", 7))
	var burst: Array = goal().get("burst", [40, 40])
	var bursts := int(goal()["bursts"])
	if t >= first:
		var k := (t - first) / every
		var step := (t - first) % every
		if k < bursts and step < burst.size():
			sim.deal_damage(player, int(burst[step]), bot.id, "typeless", {"weapon": "Bruiser's combo"})
			if step == 0:
				note = "Burst %d incoming!" % (k + 1)
			if player.hp <= 0:
				return  # judged next tick as a knock-out
			if step == burst.size() - 1:
				_n["survived"] = k + 1
	var by_tick := {}
	for e in new:
		if str(e["k"]) == "eat" and int(e["f"]) == player.id:
			var timer := str(DB.item(str(e["item"])).get("timer", ""))
			if not by_tick.has(int(e["tick"])):
				by_tick[int(e["tick"])] = {}
			by_tick[int(e["tick"])][timer] = true
	for tk in by_tick:
		if (by_tick[tk] as Dictionary).size() >= 3:
			_n["combos"] = int(_n.get("combos", 0)) + 1
			note = "Combo eat!"
	if int(_n.get("survived", 0)) >= bursts and player.hp > 0:
		if bool(goal().get("need_combo", true)) and int(_n.get("combos", 0)) == 0:
			_finish(false, "You survived, but without a combo eat (food, combo food and brew in one tick).")
		else:
			_finish(true, "")


func _judge_reading(new: Array) -> void:
	for e in new:
		if str(e["k"]) == "hit" and int(e["a"]) == bot.id and int(e["d"]) == player.id and DB.STYLES.has(str(e["style"])):
			_n["seen"] = int(_n.get("seen", 0)) + 1
			var call := str(_n.get("call", ""))
			if call == str(e["style"]) and int(_n.get("call_tick", -1)) >= int(_n.get("switch_tick", 0)):
				_n["ok"] = int(_n.get("ok", 0)) + 1
				note = "Right: %s." % call
			else:
				note = "That was %s." % str(e["style"])
		elif str(e["k"]) == "callout" and int(e["f"]) == player.id:
			_n["call"] = str(e["style"])
			_n["call_tick"] = int(e["tick"])
	# The duelist's weapon style changing starts a new read.
	var ws := bot.weapon_style()
	if ws != str(_n.get("bot_style", "")):
		_n["bot_style"] = ws
		_n["switch_tick"] = core.sim.tick
	var need := int(goal()["need"])
	if int(_n.get("ok", 0)) >= need:
		_finish(true, "")
	elif int(_n.get("seen", 0)) - int(_n.get("ok", 0)) > int(goal()["attacks"]) - need:
		_finish(false, "Too many wrong calls. Watch the weapon swap, then call it.")


# ---------------------------------------------------------------- dummy room

func _judge_dummy(new: Array) -> void:
	var sim := core.sim
	var style := player.attack_style()
	var spell := player.current_spell()
	var att := Combat.attack_roll(player, style)
	var dfn := Combat.defence_roll(bot, style)
	var chance := Combat.hit_chance(att, dfn)
	var max_hit := Combat.fighter_max_hit(player, style, spell)
	var speed := 5 if style == "magic" else int(player.weapon().get("speed", 4))
	var hist: Array = _n.get("hist", [])
	for e in new:
		if str(e["k"]) == "hit" and int(e["a"]) == player.id and int(e["d"]) == bot.id:
			hist.append([int(e["tick"]), int(e["dmg"]), not bool(e.get("splash", false)) and int(e["dmg"]) > 0])
	var window := int(def.get("window_ticks", 25))
	hist = hist.filter(func(h): return int(h[0]) > sim.tick - window)
	_n["hist"] = hist
	var dealt := 0
	var landed := 0
	for h in hist:
		dealt += int(h[1])
		if bool(h[2]):
			landed += 1
	_n["dummy"] = {
		"style": style, "accuracy": chance, "max_hit": max_hit, "speed": speed,
		"expected_dpt": chance * max_hit / 2.0 / speed,
		"observed_dpt": float(dealt) / window, "hits": hist.size(), "landed": landed,
		"prayers": player.active_prayers.duplicate(),
	}
	note = ""
