class_name BotBrain
extends RefCounted
## Server-side bot (GDD 3 "Bots"): picks a target, keeps the right overhead against the
## target's weapon style (with a human-like reaction delay), eats below 40 HP, switches
## to the style the target isn't praying against, freezes and kites melee, and specs
## when the target is low. Bots only ever send intents, like a real client.

var id: int = 0
var skill: float = 0.7          ## 0..1: reaction speed and how often it gets prayers right
var reaction: int = 2           ## ticks before it notices a gear switch
var perceived: Dictionary = {}  ## enemy id -> style the bot believes they're using
var _changes: Dictionary = {}   ## enemy id -> [style, tick first seen]
var _last_switch_tick: int = -10
var _last_kite_tick: int = -10
var _spec_weapon_slot: int = -1
var _primary: String = ""
var _objective_minded: bool = false
var _chatted_low: bool = false
var rng := RandomNumberGenerator.new()
## Data-driven behaviour (U1, data/training.json): mode, reaction_ticks, prayer_accuracy, pray, eat_hp, eat_delay,
## fake_switch_chance, spec_hp, spec_chance, attack_range, cycle_every, telegraph_ticks, walk. Empty = normal bot.
var config: Dictionary = {}
var _ate_tick: int = -100
var _pending_switch: Array = []   ## [style, tick] after a fake switch
var _cycle_attacks: int = 0
var _cycle_last_attack: int = -1
var _tele_state: String = "switch"
var _tele_until: int = 0
var _tele_attack_from: int = 0
var _walk_set: bool = false

const QUICK_CHAT := ["Freeze them!", "Spec now!", "Falling back!", "On me!", "gf", "Nice one."]


func _init(p_id: int, p_skill: float, seed: int) -> void:
	id = p_id
	skill = p_skill
	rng.seed = seed
	reaction = clampi(int(round(lerpf(3.0, 1.0, skill))), 1, 3)
	_objective_minded = rng.randf() < 0.6


## Applies a training / exam behaviour config (see data/training.json _doc).
func configure(cfg: Dictionary) -> void:
	config = cfg.duplicate()
	if cfg.has("skill"):
		skill = float(cfg["skill"])
		reaction = clampi(int(round(lerpf(3.0, 1.0, skill))), 1, 3)
	if cfg.has("reaction_ticks"):
		reaction = maxi(0, int(cfg["reaction_ticks"]))


func _mode() -> String:
	return str(config.get("mode", "fight"))


func think(sim: Sim) -> void:
	var me := sim.get_fighter(id)
	if me == null:
		return
	if not me.is_alive():
		_spec_weapon_slot = -1
		_chatted_low = false
		return
	if _primary == "" or sim.tick < 3:
		_primary = str(me.loadout.get("primary", ""))
	_perceive(sim, me)
	if sim.phase != "live":
		return
	if bool(config.get("walk", false)) and not _walk_set:
		_walk_set = true
		sim.queue_intent(id, {"type": "run", "on": false})
	if _mode() == "passive":
		return
	_supplies(sim, me)
	var t := _choose_target(sim, me)
	if bool(config.get("pray", true)):
		_prayers(sim, me, t)
	match _mode():
		"flee":
			_flee(sim, me, t)
			return
		"freezer":
			_freezer(sim, me, t)
			return
		"telegraph":
			_telegraph(sim, me, t)
			return
		"cycle":
			_cycle(sim, me, t)
			return
	if sim.rules.type == "domination" and _objective_minded and _play_objective(sim, me, t):
		return
	if t != null:
		_fight(sim, me, t)
	else:
		_roam(sim, me)


# ---------------------------------------------------------------- perception

func _perceive(sim: Sim, me: Fighter) -> void:
	for o in sim.fighters.values():
		var e: Fighter = o
		if not sim.rules.can_attack(me, e) or not e.is_alive():
			continue
		if MapGrid.chebyshev(e.pos, me.pos) > 20:
			continue
		var style := e.attack_style() if e.npc_kind == "" else "magic"
		if not perceived.has(e.id):
			perceived[e.id] = style
			continue
		if perceived[e.id] == style:
			_changes.erase(e.id)
			continue
		if not _changes.has(e.id) or _changes[e.id][0] != style:
			_changes[e.id] = [style, sim.tick]
		elif sim.tick - int(_changes[e.id][1]) >= reaction:
			perceived[e.id] = style
			_changes.erase(e.id)


# ---------------------------------------------------------------- supplies

func _slot_of(me: Fighter, pred: Callable) -> int:
	return me.find_item(pred)


func _supplies(sim: Sim, me: Fighter) -> void:
	var low := int(config.get("eat_hp", 40))
	if me.hp < low and me.food_timer == 0:
		var s := _slot_of(me, func(it): return str(it.get("timer", "")) == "food")
		if s >= 0:
			sim.queue_intent(id, {"type": "use", "slot": s})
			_ate_tick = sim.tick
		else:
			var b := _slot_of(me, func(it): return str(it.get("effect", "")) == "brew")
			if b >= 0 and me.potion_timer == 0:
				sim.queue_intent(id, {"type": "use", "slot": b})
	if me.hp < 28 and me.combo_timer == 0:
		var c := _slot_of(me, func(it): return str(it.get("timer", "")) == "combo")
		if c >= 0:
			sim.queue_intent(id, {"type": "use", "slot": c})
	if me.hp < 55 and me.potion_timer == 0 and me.hp >= low:
		var b := _slot_of(me, func(it): return str(it.get("effect", "")) == "brew")
		if b >= 0 and me.count_item("pike") <= 2:
			sim.queue_intent(id, {"type": "use", "slot": b})
	if me.potion_timer == 0 and (me.prayer_points < 20 or int(me.levels["attack"]) < int(me.base_levels["attack"]) - 12):
		var r := _slot_of(me, func(it): return str(it.get("effect", "")) == "restore")
		if r >= 0:
			sim.queue_intent(id, {"type": "use", "slot": r})
	if me.hp < 25 and not _chatted_low and rng.randf() < 0.25:
		_chatted_low = true
		sim.queue_intent(id, {"type": "chat", "text": "Falling back!"})


# ---------------------------------------------------------------- targeting

func _choose_target(sim: Sim, me: Fighter) -> Fighter:
	var cur := sim.get_fighter(me.target_id)
	var best: Fighter = null
	var best_s := INF
	for o in sim.fighters.values():
		var e: Fighter = o
		if not e.is_alive() or not sim.rules.may_engage(me, e):
			continue
		var d := MapGrid.chebyshev(me.pos, e.pos)
		if d > 22:
			continue
		var s := float(d) + e.hp * 0.08
		if e.spawn_shield > 0:
			s += 8.0
		if e.last_attacked_by == id or (me.last_attacked_by == e.id and sim.tick - me.last_attacked_tick < 8):
			s -= 4.0
		if cur != null and e == cur:
			s -= 3.0
		if not sim.map.has_los(me.pos, e.pos):
			s += 4.0
		if e.npc_kind == "guardian":
			s += 3.0
		if s < best_s:
			best_s = s
			best = e
	return best


# ---------------------------------------------------------------- prayers

func _ward_for(style: String) -> String:
	return {"melee": "ward_blades", "ranged": "ward_arrows", "magic": "ward_spells"}.get(style, "")


func _prayers(sim: Sim, me: Fighter, t: Fighter) -> void:
	if me.prayer_points <= 0:
		return
	var threat: Fighter = null
	if me.last_attacked_by != -1 and sim.tick - me.last_attacked_tick < 6:
		threat = sim.get_fighter(me.last_attacked_by)
	if threat == null or not threat.is_alive():
		threat = t
	if threat != null and MapGrid.chebyshev(threat.pos, me.pos) <= 14:
		var style: String = perceived.get(threat.id, threat.attack_style())
		var want := _ward_for(style)
		if want != "" and not me.has_prayer(want) and me.ward_block_ticks == 0:
			# Skill check: weaker bots sometimes miss the switch this tick.
			if rng.randf() < float(config.get("prayer_accuracy", 0.35 + 0.6 * skill)):
				sim.queue_intent(id, {"type": "prayer", "id": want})
		var off := _best_offensive(me)
		for p in off:
			if not me.has_prayer(p) and me.prayer_points > 15:
				sim.queue_intent(id, {"type": "prayer", "id": p})
	elif me.overhead() != "" and rng.randf() < 0.1:
		sim.queue_intent(id, {"type": "prayer", "id": me.overhead()})


func _best_offensive(me: Fighter) -> Array:
	var style := me.attack_style()
	var lists := {
		"melee": [["valor"], ["gallantry"], ["keen_focus_3", "brute_force_3"], ["keen_focus_2", "brute_force_2"], ["keen_focus_1", "brute_force_1"], ["keen_focus_1"]],
		"ranged": [["precision"], ["sharp_sight_3"], ["sharp_sight_2"], ["sharp_sight_1"]],
		"magic": [["insight"], ["arcane_will_3"], ["arcane_will_2"], ["arcane_will_1"]],
	}
	for combo in lists.get(style, []):
		var ok := true
		for p in combo:
			if not me.unlocked.has(p):
				ok = false
		if ok:
			return combo
	return []


# ---------------------------------------------------------------- fighting

func _styles_available(me: Fighter) -> Dictionary:
	var out := {me.weapon_style(): true}
	for e in me.inventory:
		if e == null:
			continue
		var it := DB.item(str(e["id"]))
		if str(it.get("slot", "")) == "weapon":
			out[str(it["style"])] = true
	return out


func _counter_style(armour_class: String) -> String:
	return {"plate": "magic", "hide": "melee", "robe": "ranged"}.get(armour_class, "")


func _fight(sim: Sim, me: Fighter, t: Fighter) -> void:
	var dist := MapGrid.chebyshev(me.pos, t.pos)
	var styles := _styles_available(me)
	var cur_style := me.weapon_style()
	# Training config: pause attacking for eat_delay ticks after eating (the exam bot's tell).
	var eat_delay := int(config.get("eat_delay", 0))
	if eat_delay > 0 and sim.tick - _ate_tick < eat_delay:
		if me.target_id != -1:
			sim.queue_intent(id, {"type": "stop"})
		return
	# Finish a fake switch: the real style one tick after the decoy.
	if not _pending_switch.is_empty() and sim.tick >= int(_pending_switch[1]):
		var real := str(_pending_switch[0])
		_pending_switch = []
		sim.queue_intent(id, {"type": "switch_set", "style": real})
		sim.queue_intent(id, {"type": "attack", "target": t.id})
		return
	# Limited attack range: walk in closer before attacking.
	var ar := int(config.get("attack_range", 0))
	if ar > 0 and dist > ar and t.frozen_ticks == 0:
		if me.target_id != -1:
			sim.queue_intent(id, {"type": "stop"})
		if me.path.is_empty() or me.dest != t.pos:
			sim.queue_intent(id, {"type": "move", "x": t.pos.x, "y": t.pos.y})
		return
	# 1. Specials when the target is low.
	if _try_spec(sim, me, t, dist):
		return
	# 2. Hybrid switching: avoid the style the target prays against, prefer the triangle counter.
	if styles.size() > 1 and sim.tick - _last_switch_tick >= 3 and t.npc_kind == "":
		var protect := t.protect_style()
		var want := cur_style
		if protect == cur_style or (cur_style == "magic" and me.autocast == ""):
			want = ""
		var counter := _counter_style(t.armour_class())
		if counter != "" and styles.has(counter) and counter != protect and rng.randf() < 0.5 * skill:
			want = counter
		if want == "":
			for s in ["magic", "ranged", "melee"]:
				if styles.has(s) and s != protect:
					want = s
					break
		# Battlemage trick: switch to melee on a target frozen next to us.
		if t.frozen_ticks > 2 and dist <= 1 and styles.has("melee") and protect != "melee":
			want = "melee"
		if want != "" and want != cur_style:
			_last_switch_tick = sim.tick
			var fake := float(config.get("fake_switch_chance", 0.0))
			if fake > 0.0 and rng.randf() < fake:
				for s in ["melee", "ranged", "magic"]:
					if styles.has(s) and s != want and s != cur_style:
						sim.queue_intent(id, {"type": "switch_set", "style": s})
						_pending_switch = [want, sim.tick + 1]
						return
			sim.queue_intent(id, {"type": "switch_set", "style": want})
			sim.queue_intent(id, {"type": "attack", "target": t.id})
			return
	# 3. Freeze melee attackers who get close, if we have a freeze spell.
	var t_style: String = perceived.get(t.id, t.attack_style())
	if t_style == "melee" and dist <= 4 and t.frozen_ticks == 0 and t.freeze_immune_ticks == 0 and me.attack_timer <= 1:
		var fz := Loadout.best_freeze_spell(me.spellbook, me.unlocked)
		if fz != "" and (me.weapon_style() != "melee" or rng.randf() < 0.5) and sim._spell_usable(me, fz, false):
			if rng.randf() < 0.4 + 0.5 * skill:
				sim.queue_intent(id, {"type": "cast", "spell": fz, "target": t.id})
				return
	# 4. Kite: ranged/magic step away from a frozen melee user.
	if me.weapon_style() != "melee" and t_style == "melee" and t.frozen_ticks > 1 and dist <= 1 and me.frozen_ticks == 0 and sim.tick - _last_kite_tick > 4:
		var away := me.pos + (me.pos - t.pos) * 3
		away = sim.map.nearest_walkable(Vector2i(clampi(away.x, 1, sim.map.w - 2), clampi(away.y, 1, sim.map.h - 2)))
		_last_kite_tick = sim.tick
		sim.queue_intent(id, {"type": "move", "x": away.x, "y": away.y})
		return
	if me.target_id != t.id or me.pending_spell != "":
		if me.pending_spell == "":
			sim.queue_intent(id, {"type": "attack", "target": t.id})


func _try_spec(sim: Sim, me: Fighter, t: Fighter, dist: int) -> bool:
	if t.npc_kind != "":
		return false
	var w := me.weapon()
	# Switch back to the primary after specs are spent.
	if _spec_weapon_slot >= 0 and w.has("spec") and me.spec_energy < int(w["spec"]["cost"]):
		_spec_weapon_slot = -1
		var p := me.find_item(func(it): return str(it.get("id", "")) == _primary)
		if p >= 0:
			sim.queue_intent(id, {"type": "equip", "slot": p})
		return false
	if t.hp > int(config.get("spec_hp", 55)) or rng.randf() > float(config.get("spec_chance", 0.3 + 0.5 * skill)):
		return false
	if w.has("spec") and me.spec_energy >= int(w["spec"]["cost"]):
		if not me.spec_armed:
			sim.queue_intent(id, {"type": "spec"})
		if me.target_id != t.id:
			sim.queue_intent(id, {"type": "attack", "target": t.id})
		return true
	var slot := me.find_item(func(it): return it.has("spec") and str(it.get("slot", "")) == "weapon")
	if slot < 0:
		return false
	var it := DB.item(str(me.inventory[slot]["id"]))
	if me.spec_energy < int(it["spec"]["cost"]):
		return false
	if str(it["style"]) == "melee" and dist > 2:
		return false
	_spec_weapon_slot = slot
	sim.queue_intent(id, {"type": "equip", "slot": slot})
	sim.queue_intent(id, {"type": "spec"})
	sim.queue_intent(id, {"type": "attack", "target": t.id})
	return true


# ---------------------------------------------------------------- scripted training modes (U1)

## Runs away from the target and never attacks.
func _flee(sim: Sim, me: Fighter, t: Fighter) -> void:
	if t == null:
		return
	if me.target_id != -1:
		sim.queue_intent(id, {"type": "stop"})
	if not me.path.is_empty() and sim.tick % 4 != 0:
		return
	var dir := me.pos - t.pos
	if dir == Vector2i.ZERO:
		dir = Vector2i(1, 0)
	var away := me.pos + Vector2i(signi(dir.x), signi(dir.y)) * 6 + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
	away = sim.map.nearest_walkable(Vector2i(clampi(away.x, 1, sim.map.w - 2), clampi(away.y, 1, sim.map.h - 2)))
	sim.queue_intent(id, {"type": "move", "x": away.x, "y": away.y})


## Chases (walking) and casts freezes on the target whenever it can.
func _freezer(sim: Sim, me: Fighter, t: Fighter) -> void:
	if t == null:
		return
	var dist := MapGrid.chebyshev(me.pos, t.pos)
	var fz := Loadout.best_freeze_spell(me.spellbook, me.unlocked)
	if dist <= 10 and t.frozen_ticks == 0 and t.freeze_immune_ticks == 0 and fz != "" and me.attack_timer <= 0 and me.pending_spell == "" and sim._spell_usable(me, fz, false):
		sim.queue_intent(id, {"type": "cast", "spell": fz, "target": t.id})
		return
	if dist > 6 and (me.path.is_empty() or sim.tick % 3 == 0) and me.pending_spell == "":
		sim.queue_intent(id, {"type": "move", "x": t.pos.x, "y": t.pos.y})


## Switches to a new style, waits telegraph_ticks so the switch can be read, attacks once, repeats.
func _telegraph(sim: Sim, me: Fighter, t: Fighter) -> void:
	if t == null:
		return
	var styles := _styles_available(me).keys()
	match _tele_state:
		"switch":
			var options: Array = styles.filter(func(s): return s != me.weapon_style())
			if options.is_empty():
				options = styles
			var pick: String = options[rng.randi_range(0, options.size() - 1)]
			sim.queue_intent(id, {"type": "switch_set", "style": pick})
			sim.queue_intent(id, {"type": "stop"})
			_tele_until = sim.tick + int(config.get("telegraph_ticks", 3))
			_tele_state = "wait"
		"wait":
			if sim.tick >= _tele_until:
				_tele_attack_from = sim.tick
				sim.queue_intent(id, {"type": "attack", "target": t.id})
				_tele_state = "attack"
		"attack":
			if me.last_attack_tick >= _tele_attack_from:
				sim.queue_intent(id, {"type": "stop"})
				_tele_state = "switch"
			elif sim.tick - _tele_attack_from > 12:
				_tele_state = "switch"  # couldn't reach; try again


## Fights normally but changes style every cycle_every attacks (melee -> ranged -> magic).
func _cycle(sim: Sim, me: Fighter, t: Fighter) -> void:
	if t == null:
		return
	if me.last_attack_tick != _cycle_last_attack and me.last_attack_tick > 0:
		_cycle_last_attack = me.last_attack_tick
		_cycle_attacks += 1
	var styles := _styles_available(me)
	var order: Array = ["melee", "ranged", "magic"].filter(func(s): return styles.has(s))
	if order.is_empty():
		return
	var want: String = order[(_cycle_attacks / maxi(1, int(config.get("cycle_every", 3)))) % order.size()]
	if me.weapon_style() != want:
		sim.queue_intent(id, {"type": "switch_set", "style": want})
		sim.queue_intent(id, {"type": "attack", "target": t.id})
		return
	if me.target_id != t.id:
		sim.queue_intent(id, {"type": "attack", "target": t.id})


## Obelisks: head for the nearest obelisk we don't own (or one being taken from us),
## only engage enemies who come close, and hold the point once there.
## Returns true when it handled this tick.
func _play_objective(sim: Sim, me: Fighter, t: Fighter) -> bool:
	var radius := int(sim.mode.get("capture_radius", 1))
	var goal := Vector2i(-1, -1)
	var best := 9999
	for ob in sim.objectives:
		var threatened := int(ob["owner"]) == me.team and int(ob["cap_team"]) >= 0 and int(ob["cap_team"]) != me.team
		if int(ob["owner"]) == me.team and not threatened:
			continue
		var d := MapGrid.chebyshev(me.pos, ob["pos"]) - (6 if threatened else 0)
		if d < best:
			best = d
			goal = ob["pos"]
	if goal == Vector2i(-1, -1):
		return false
	var enemy_d := MapGrid.chebyshev(me.pos, t.pos) if t != null else 99
	var on_point := MapGrid.chebyshev(me.pos, goal) <= radius
	var reach := int(me.weapon().get("range", 1)) if me.attack_style() != "magic" else 10
	if not on_point:
		if enemy_d <= 4:
			return false  # fight whoever is in the way
		if me.dest != goal or me.path.is_empty():
			sim.queue_intent(id, {"type": "move", "x": goal.x, "y": goal.y})
		return true
	# On the point: fight only what we can hit without leaving it.
	if t != null and (enemy_d <= maxi(reach, 2)):
		return false
	if me.target_id != -1 or not me.path.is_empty():
		sim.queue_intent(id, {"type": "stop"})
	return true


func _roam(sim: Sim, me: Fighter) -> void:
	if not me.path.is_empty():
		return
	var goal := Vector2i(-1, -1)
	if sim.rules.type == "domination" and _objective_minded:
		var best_d := 9999
		for ob in sim.objectives:
			if int(ob["owner"]) == me.team:
				continue
			var d := MapGrid.chebyshev(me.pos, ob["pos"])
			if d < best_d:
				best_d = d
				goal = ob["pos"]
		if goal != Vector2i(-1, -1) and best_d <= 1:
			return  # hold the point
	if goal == Vector2i(-1, -1):
		var best_d := 9999
		for o in sim.fighters.values():
			var e: Fighter = o
			if e.is_alive() and sim.rules.can_attack(me, e):
				var d := MapGrid.chebyshev(me.pos, e.pos)
				if d < best_d:
					best_d = d
					goal = e.pos
	if goal == Vector2i(-1, -1):
		goal = Vector2i(sim.map.w / 2, sim.map.h / 2)
	goal += Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
	goal = sim.map.nearest_walkable(Vector2i(clampi(goal.x, 1, sim.map.w - 2), clampi(goal.y, 1, sim.map.h - 2)))
	sim.queue_intent(id, {"type": "move", "x": goal.x, "y": goal.y})


## Summoned Guardian AI: attack the nearest enemy.
static func think_guardian(sim: Sim, g: Fighter) -> void:
	var best: Fighter = null
	var best_d := 11
	for o in sim.fighters.values():
		var e: Fighter = o
		if e.is_alive() and sim.rules.can_attack(g, e):
			var d := MapGrid.chebyshev(g.pos, e.pos)
			if d < best_d:
				best_d = d
				best = e
	if best != null and g.target_id != best.id:
		sim.queue_intent(g.id, {"type": "attack", "target": best.id})
	elif best == null:
		var owner := sim.get_fighter(g.owner_id)
		if owner != null and MapGrid.chebyshev(owner.pos, g.pos) > 3:
			sim.queue_intent(g.id, {"type": "move", "x": owner.pos.x, "y": owner.pos.y})
