class_name Sim
extends RefCounted
## The authoritative match simulation. One call to step() = one 600 ms tick, run in
## the fixed GDD order:
##   1 queued inputs  2 eat/drink/equip  3 prayer toggles + drain  4 movement
##   5 attacks        6 hits landing     7 deaths/respawns/objectives/timers
##   8 state broadcast (snapshot())
## Clients never touch this object: they send intents with queue_intent() and draw
## what snapshot() returns. Bots live on the server and use the same intents.

var tick: int = 0
var live_ticks: int = 0
var phase: String = "pre"          ## pre | live | over
var phase_ticks: int = 0
var map: MapGrid
var mode_id: String = ""
var mode: Dictionary = {}
var rules: ModeRules
var options: Dictionary = {}
var fighters: Dictionary = {}      ## id -> Fighter (insertion order = processing order, like OSRS PID)
var pending_hits: Array = []
var events: Array = []
var intents: Array = []
var rng := RandomNumberGenerator.new()
var scores: Array = []
var objectives: Array = []
var meteors: Array = []
var traps: Array = []
var reveal_until: Dictionary = {}  ## team -> tick
var result: Dictionary = {}
var first_blood: bool = false
var _next_id: int = 1


func setup(p_mode_id: String, map_id: String, p_options: Dictionary = {}) -> void:
	DB.ensure_loaded()
	options = p_options
	mode_id = p_mode_id
	mode = DB.modes["modes"][mode_id]
	map = MapGrid.from_json(DB.maps[map_id])
	rules = ModeRules.new(self, mode)
	if options.has("seed"):
		rng.seed = int(options["seed"])
	else:
		rng.randomize()
	var nteams := int(mode.get("teams", 2))
	if nteams <= 0:
		nteams = int(mode.get("team_size", 8))
	scores.resize(nteams)
	scores.fill(0)
	rules.setup_objectives()
	phase = "pre"
	phase_ticks = int(options.get("pre_ticks", DB.ticks(float(DB.modes.get("pre_match_s", 15)))))


## Adds a player or bot. loadout from Loadout.build(); unlocked from Progression.unlocked_set().
func add_fighter(p_name: String, team: int, is_bot: bool, loadout: Dictionary, unlocked: Dictionary, style_levels: Dictionary = {}) -> int:
	var f := Fighter.new()
	f.id = _next_id
	_next_id += 1
	f.name = p_name
	f.team = team
	f.is_bot = is_bot
	f.loadout = loadout
	f.unlocked = unlocked
	if not style_levels.is_empty():
		f.style_levels = style_levels
	f.combat_level = Progression.combat_level(int(f.style_levels["melee"]), int(f.style_levels["ranged"]), int(f.style_levels["magic"]))
	fighters[f.id] = f
	spawn(f)
	return f.id


func queue_intent(fid: int, intent: Dictionary) -> void:
	intents.append([fid, intent])


func add_event(e: Dictionary) -> void:
	events.append(e)


func msg(fid: int, text: String) -> void:
	events.append({"type": "msg", "to": fid, "text": text})


func get_fighter(fid: int) -> Fighter:
	return fighters.get(fid, null)


func alive_players() -> Array:
	var out: Array = []
	for f in fighters.values():
		if (f as Fighter).is_alive():
			out.append(f)
	return out


# =============================================================== the tick

func step() -> void:
	tick += 1
	events.clear()
	if phase == "over":
		return
	if phase == "pre":
		phase_ticks -= 1
		if phase_ticks <= 0:
			phase = "live"
			add_event({"type": "phase", "phase": "live"})
	else:
		live_ticks += 1
	# 1. queued inputs
	var batch := intents
	intents = []
	for it in batch:
		_apply_intent(int(it[0]), it[1])
	var order: Array = fighters.values()
	# 2. eating, drinking and gear equips
	for f in order:
		_process_actions(f)
	# 3. prayer toggles and drain
	for f in order:
		_process_prayers(f)
	# 4. movement
	for f in order:
		_move(f)
	# 5. attacks whose timer has run out
	for f in order:
		_attack(f)
	# 6. hits landing this tick
	_land_hits()
	_land_meteors()
	# 7. deaths, respawns, objectives, timers
	_process_deaths()
	for f in order:
		_timers(f)
	_respawns()
	_expire_npcs()
	rules.tick()


# =============================================================== 1. intents

func _apply_intent(fid: int, it: Dictionary) -> void:
	var f := get_fighter(fid)
	if f == null:
		return
	var kind := str(it.get("type", ""))
	# Class changes and chat are allowed while dead.
	if kind == "class":
		f.next_loadout = it.get("loadout", {})
		msg(fid, "Class change will apply on your next life.")
		return
	if kind == "chat":
		add_event({"type": "chat", "from": fid, "name": f.name, "team": f.team, "text": str(it.get("text", "")).left(80)})
		return
	if kind == "ready":
		if phase == "pre" and live_ticks == 0 and not f.is_bot:
			phase_ticks = mini(phase_ticks, 2)
		return
	if not f.is_alive():
		return
	match kind:
		"move":
			var tile := Vector2i(int(it["x"]), int(it["y"]))
			f.target_id = -1
			f.pending_spell = ""
			f.dest = tile
			f.path = map.find_path(f.pos, [tile])
		"attack":
			var t := get_fighter(int(it["target"]))
			if t != null and rules.can_attack(f, t) and t.is_alive():
				if f.target_id != t.id:
					f.pending_spell = "" if f.weapon_style() == "magic" else f.pending_spell
				f.target_id = t.id
				f.dest = Vector2i(-1, -1)
				f.path.clear()
		"cast":
			var t := get_fighter(int(it["target"]))
			var sid := str(it.get("spell", ""))
			if t != null and rules.can_attack(f, t) and _spell_usable(f, sid, true):
				f.pending_spell = sid
				f.target_id = t.id
				f.dest = Vector2i(-1, -1)
				f.path.clear()
		"spell":
			var sid := str(it.get("spell", ""))
			if sid == "" or _spell_usable(f, sid, true):
				if f.weapon_style() == "magic":
					f.autocast = sid
					if sid != "":
						msg(fid, "Autocast: " + str(DB.spells[sid]["name"]))
		"equip", "use", "unequip", "spec", "switch_set":
			f.action_queue.append(it)
		"prayer":
			f.prayer_queue.append(str(it.get("id", "")))
		"prayers_off":
			for p in f.active_prayers.duplicate():
				f.prayer_queue.append(p)
		"run":
			f.running = bool(it.get("on", not f.running))
		"stance":
			var s := str(it.get("stance", "aggressive"))
			if ["accurate", "aggressive", "defensive"].has(s):
				f.stance = s
		"retaliate":
			f.auto_retaliate = bool(it.get("on", not f.auto_retaliate))
		"streak":
			_use_streak(f, str(it.get("id", "")), Vector2i(int(it.get("x", f.pos.x)), int(it.get("y", f.pos.y))))
		"rebuke":
			if not f.has_perk("rebuke"):
				msg(fid, "You don't have the Rebuke perk.")
			elif f.rebuke_cooldown > 0:
				msg(fid, "Rebuke is ready in %d s." % int(ceil(f.rebuke_cooldown * 0.6)))
			else:
				f.rebuke_armed = true
				f.rebuke_cooldown = int(DB.perks["rebuke"].get("cooldown", 50))
				add_event({"type": "fx", "id": fid, "fx": "rebuke"})
		"trap":
			if f.has_perk("snare_trap") and f.trap_available:
				f.trap_available = false
				traps.append({"pos": f.pos, "team": f.team, "owner": fid})
				msg(fid, "You set a snare trap.")
		"stop":
			f.target_id = -1
			f.path.clear()
			f.dest = Vector2i(-1, -1)


func _spell_usable(f: Fighter, sid: String, tell: bool) -> bool:
	if not DB.spells.has(sid):
		return false
	var sp: Dictionary = DB.spells[sid]
	if str(sp["book"]) != f.spellbook:
		if tell:
			msg(f.id, "That spell isn't in your spellbook.")
		return false
	if not f.unlocked.has(sid):
		if tell:
			msg(f.id, "You haven't unlocked %s." % sp["name"])
		return false
	if str(sp["book"]) == "forbidden" and not bool(f.weapon().get("forbidden", false)):
		if tell:
			msg(f.id, "You need a Forbidden staff to cast that.")
		return false
	if bool(sp.get("rune_limited", false)) and f.rune_casts <= 0 and not f.has_perk("spell_satchel"):
		if tell:
			msg(f.id, "You're out of runes for freeze spells.")
		return false
	return true


# =============================================================== 2. actions

func _process_actions(f: Fighter) -> void:
	if f.action_queue.is_empty():
		return
	if not f.is_alive():
		f.action_queue.clear()
		return
	var limit := int(DB.rule("quick_hands_equips", 10)) if f.has_perk("quick_hands") else int(DB.rule("max_equips_per_tick", 8))
	var equips := 0
	var carry: Array = []
	for a in f.action_queue:
		var kind := str(a.get("type", ""))
		if (kind == "equip" or kind == "unequip" or kind == "switch_set") and equips >= limit:
			carry.append(a)
			continue
		match kind:
			"use", "equip":
				var idx := int(a.get("slot", -1))
				if idx < 0 or idx >= 28 or f.inventory[idx] == null:
					continue
				var e: Dictionary = f.inventory[idx]
				if a.has("id") and str(a["id"]) != str(e["id"]):
					continue
				var itm := DB.item(str(e["id"]))
				if str(itm.get("slot", "")) != "":
					if _equip(f, idx):
						equips += 1
				else:
					_consume(f, idx)
			"unequip":
				_unequip(f, str(a.get("slot", "")))
				equips += 1
			"switch_set":
				equips += _switch_set(f, str(a.get("style", "")), limit - equips)
			"spec":
				_toggle_spec(f)
	f.action_queue = carry


func _equip(f: Fighter, idx: int) -> bool:
	var e: Dictionary = f.inventory[idx]
	var iid := str(e["id"])
	var it := DB.item(iid)
	var slot := str(it["slot"])
	if f.loadout.get("pure", false) and str(it.get("armour_class", "")) == "plate":
		msg(f.id, "Pure Brawl: plate armour is not allowed.")
		return false
	var remove: Array = [slot]
	if bool(it.get("two_handed", false)):
		remove = ["weapon", "shield"]
	elif slot == "shield" and bool(f.weapon().get("two_handed", false)):
		remove = ["shield", "weapon"]
	var removed: Array = []
	for s in remove:
		if str(f.equipment[s]) != "":
			removed.append(str(f.equipment[s]))
	if removed.size() - 1 > f.free_slots():
		msg(f.id, "You don't have enough inventory space to do that.")
		return false
	var weapon_before := str(f.equipment["weapon"])
	f.inventory[idx] = null
	for s in remove:
		f.equipment[s] = ""
	f.equipment[slot] = iid
	for i in range(removed.size()):
		var entry := {"id": removed[i], "doses": 1}
		if i == 0:
			f.inventory[idx] = entry
		else:
			f.inventory[f.first_free_slot()] = entry
	f.recalc_bonuses()
	if str(f.equipment["weapon"]) != weapon_before:
		_on_weapon_changed(f)
	return true


func _unequip(f: Fighter, slot: String) -> void:
	if not f.equipment.has(slot) or str(f.equipment[slot]) == "":
		return
	var free := f.first_free_slot()
	if free < 0:
		msg(f.id, "You don't have enough inventory space to do that.")
		return
	f.inventory[free] = {"id": str(f.equipment[slot]), "doses": 1}
	f.equipment[slot] = ""
	f.recalc_bonuses()
	if slot == "weapon":
		_on_weapon_changed(f)


func _on_weapon_changed(f: Fighter) -> void:
	f.spec_armed = false
	if f.weapon_style() == "magic":
		if f.autocast == "" or not _spell_usable(f, f.autocast, false):
			f.autocast = Loadout.best_damage_spell(f.spellbook if bool(f.weapon().get("forbidden", false)) else "elemental", f.unlocked)


## Hotkey switch: equip every inventory item whose style matches (GDD 2 optional switch hotkeys).
func _switch_set(f: Fighter, style: String, budget: int) -> int:
	var n := 0
	# Weapon first so two-handed swaps free the shield before shields are placed.
	var order: Array = []
	for i in range(28):
		var e = f.inventory[i]
		if e == null:
			continue
		var it := DB.item(str(e["id"]))
		if str(it.get("slot", "")) == "" or str(it.get("style", "")) != style:
			continue
		order.append(i if str(it["slot"]) == "weapon" else i + 100)
	order.sort()
	for k in order:
		if n >= budget:
			break
		var idx: int = k if k < 100 else k - 100
		if f.inventory[idx] != null and _equip(f, idx):
			n += 1
	return n


func _toggle_spec(f: Fighter) -> void:
	var w := f.weapon()
	if not w.has("spec"):
		msg(f.id, "Your weapon has no special attack.")
		f.spec_armed = false
		return
	var cost := _spec_cost(f, w)
	if f.spec_energy < cost:
		msg(f.id, "You don't have enough special attack energy.")
		f.spec_armed = false
		return
	if str(w["spec"]["id"]) == "instant_maul":
		# Stone Maul: hits instantly, ignoring the attack timer. Two can land in one tick.
		var t := get_fighter(f.target_id)
		if t != null and t.is_alive() and t.spawn_shield <= 0 and _in_attack_position(f, t, "melee"):
			f.spec_energy -= cost
			Specials.perform(self, f, t, "instant_maul", "melee")
			add_event({"type": "attack", "id": f.id, "target": t.id, "style": "melee", "spec": true, "weapon": str(w.get("id", ""))})
			f.attack_timer = int(w.get("speed", 7))
			f.spawn_shield = 0
			f.challenge_events.append({"type": "maul_spec", "tick": tick})
			return
	f.spec_armed = not f.spec_armed


func _spec_cost(f: Fighter, w: Dictionary) -> int:
	var cost := int(w["spec"]["cost"])
	if str(w.get("mod_id", "")) == "wrapped_hilt":
		cost -= 5
	return cost


func _consume(f: Fighter, idx: int) -> void:
	var e: Dictionary = f.inventory[idx]
	var it := DB.item(str(e["id"]))
	var timer := str(it.get("timer", "food"))
	match timer:
		"food":
			if f.food_timer > 0:
				return
			f.food_timer = 3
		"combo":
			if f.combo_timer > 0:
				return
			f.combo_timer = 3
		"potion":
			if f.potion_timer > 0:
				return
			f.potion_timer = 3
	var verb := "eat"
	if it.has("heal"):
		f.hp = mini(f.max_hp, f.hp + int(it["heal"]))
		f.attack_timer += int(it.get("attack_delay", 0))
	match str(it.get("effect", "")):
		"brew":
			verb = "drink"
			var b: Dictionary = DB.consumables_meta["brew"]
			var heal := int(floor(f.max_hp * float(b["heal_pct"]))) + int(b["heal_flat"])
			f.hp = mini(f.max_hp + int(b["max_overheal"]), f.hp + heal)
			var bd := int(f.base_levels["defence"])
			f.levels["defence"] = mini(bd + int(floor(bd * float(b["def_pct"]))) + int(b["def_flat"]), int(f.levels["defence"]) + int(floor(bd * float(b["def_pct"]))) + int(b["def_flat"]))
			for s in ["attack", "strength", "ranged", "magic"]:
				var lower := int(floor(int(f.levels[s]) * float(b["lower_pct"]))) + int(b["lower_flat"])
				f.levels[s] = maxi(1, int(f.levels[s]) - lower)
		"restore":
			verb = "drink"
			var r: Dictionary = DB.consumables_meta["restore"]
			for s in Fighter.STATS:
				var base := int(f.base_levels[s])
				if int(f.levels[s]) < base:
					f.levels[s] = mini(base, int(f.levels[s]) + int(floor(base * float(r["stat_pct"]))) + int(r["stat_flat"]))
			f.prayer_points = mini(int(DB.rule("max_prayer", 99)), f.prayer_points + int(floor(99 * float(r["prayer_pct"]))) + int(r["prayer_flat"]))
		"antidote":
			verb = "drink"
			f.poison_hits_left = 0
		"spec_restore":
			verb = "drink"
			f.spec_energy = mini(100, f.spec_energy + 25)
	e["doses"] = int(e.get("doses", 1)) - 1
	if int(e["doses"]) <= 0:
		f.inventory[idx] = null
	add_event({"type": "consume", "id": f.id, "item": str(it["id"])})
	msg(f.id, "You %s the %s." % [verb, str(it["name"]).to_lower()])


# =============================================================== 3. prayers

func _process_prayers(f: Fighter) -> void:
	if not f.is_alive():
		f.prayer_queue.clear()
		return
	for pid in f.prayer_queue:
		var pr: Dictionary = DB.prayers.get(pid, {})
		if pr.is_empty():
			continue
		if f.has_prayer(pid):
			f.active_prayers.erase(pid)
			continue
		if not f.unlocked.has(pid):
			msg(f.id, "You haven't unlocked %s." % pr["name"])
			continue
		if f.prayer_points <= 0:
			msg(f.id, "You need to recharge your prayer.")
			continue
		if pr.has("protect") and f.ward_block_ticks > 0:
			msg(f.id, "Your wards have been severed!")
			continue
		var groups: Array = pr.get("groups", [])
		for other in f.active_prayers.duplicate():
			var og: Array = DB.prayers[other].get("groups", [])
			for g in groups:
				if og.has(g):
					f.active_prayers.erase(other)
					break
		f.active_prayers.append(pid)
	f.prayer_queue.clear()
	if f.active_prayers.is_empty():
		return
	var drain := 0.0
	for p in f.active_prayers:
		drain += float(DB.prayers[p]["drain"])
	if f.has_perk("iron_will"):
		drain *= 0.75
	f.prayer_drain_counter += drain
	var resistance := 60.0 + 2.0 * float(f.bonuses["prayer"])
	resistance = maxf(resistance, 10.0)
	while f.prayer_drain_counter >= resistance:
		f.prayer_drain_counter -= resistance
		f.prayer_points -= 1
	if f.prayer_points <= 0:
		f.prayer_points = 0
		f.active_prayers.clear()
		msg(f.id, "You have run out of prayer points.")
		add_event({"type": "fx", "id": f.id, "fx": "prayer_out"})


# =============================================================== 4. movement

func _attack_range(f: Fighter, style: String) -> int:
	if style == "magic":
		return 10 + (int(f.weapon().get("range", 10)) - 10 if f.weapon_style() == "magic" else 0)
	return int(f.weapon().get("range", 1))


func _in_attack_position(f: Fighter, t: Fighter, style: String = "") -> bool:
	if style == "":
		style = f.attack_style()
	if f.npc_kind == "guardian":
		style = "magic"
	var d := t.pos - f.pos
	var r := _attack_range(f, style) if f.npc_kind == "" else int(DB.streaks["guardian"].get("range", 8))
	if style == "melee" and r <= 1:
		return absi(d.x) + absi(d.y) == 1
	var cd := maxi(absi(d.x), absi(d.y))
	return cd > 0 and cd <= r and map.has_los(f.pos, t.pos)


func _attack_goals(f: Fighter, t: Fighter) -> Array:
	if f.attack_style() == "melee" and f.npc_kind == "":
		var goals: Array = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var g: Vector2i = t.pos + d
			if map.walkable_v(g):
				goals.append(g)
		if goals.is_empty():
			goals.append(t.pos)
		return goals
	return [t.pos]


func _move(f: Fighter) -> void:
	f.trail = [f.pos]
	if not f.is_alive() or phase != "live":
		return
	var t: Fighter = null
	if f.target_id != -1:
		t = get_fighter(f.target_id)
		if t == null or not t.is_alive():
			f.target_id = -1
			t = null
	if f.frozen_ticks > 0:
		f.path.clear()
		_regen_run(f)
		return
	if t != null:
		if _in_attack_position(f, t):
			f.path.clear()
			_regen_run(f)
			return
		f.path = map.find_path(f.pos, _attack_goals(f, t))
	var steps := 2 if (f.running and f.run_energy >= 1.0 and f.npc_kind == "") else 1
	var moved := 0
	for i in range(steps):
		if f.path.is_empty():
			break
		if t != null and _in_attack_position(f, t):
			break
		var nxt: Vector2i = f.path[0]
		f.path.remove_at(0)
		if MapGrid.chebyshev(nxt, f.pos) != 1 or not map.can_step(f.pos, nxt - f.pos):
			f.path.clear()
			break
		f.pos = nxt
		f.trail.append(nxt)
		moved += 1
		if _check_trap(f):
			break
	if moved >= 2:
		var drain := float(DB.rule("run_drain_per_tick", 0.67))
		if f.has_perk("fleet_foot"):
			drain *= 0.5
		var body := DB.item(str(f.equipment["body"]))
		drain *= float(body.get("run_drain_mult", 1.0))
		f.run_energy = maxf(0.0, f.run_energy - drain)
		if f.run_energy < 1.0:
			f.running = false
	else:
		_regen_run(f)
	if f.path.is_empty() and t == null:
		f.dest = Vector2i(-1, -1)


func _regen_run(f: Fighter) -> void:
	f.run_energy = minf(100.0, f.run_energy + float(DB.rule("run_regen_per_tick", 0.45)))


func _check_trap(f: Fighter) -> bool:
	for i in range(traps.size()):
		var tr: Dictionary = traps[i]
		if tr["pos"] == f.pos and int(tr["team"]) != f.team:
			traps.remove_at(i)
			if _freeze(f, 8):
				msg(f.id, "You step on a snare trap!")
				var owner := get_fighter(int(tr["owner"]))
				if owner != null:
					msg(owner.id, "Your snare trap caught %s!" % f.name)
				f.path.clear()
				return true
			return false
	return false


func _freeze(t: Fighter, ticks: int) -> bool:
	if t.frozen_ticks > 0 or t.freeze_immune_ticks > 0 or ticks <= 0:
		return false
	t.frozen_ticks = ticks
	t.path.clear()
	add_event({"type": "fx", "id": t.id, "fx": "freeze"})
	return true


# =============================================================== 5. attacks

func _attack(f: Fighter) -> void:
	if f.attack_timer > 0:
		f.attack_timer -= 1
	if not f.is_alive() or phase != "live" or f.target_id == -1:
		return
	var t := get_fighter(f.target_id)
	if t == null or not t.is_alive() or not rules.can_attack(f, t):
		f.target_id = -1
		return
	if t.spawn_shield > 0 or f.attack_timer > 0:
		return
	if not _in_attack_position(f, t):
		return
	_perform_attack(f, t)


func _perform_attack(f: Fighter, t: Fighter) -> void:
	var w := f.weapon()
	var style := f.attack_style()
	var spell := f.current_spell()
	var speed := int(w.get("speed", 4))
	if f.npc_kind == "guardian":
		style = "magic"
		speed = int(DB.streaks["guardian"].get("speed", 5))
		make_attack(f, t, "magic", {"proj": "guardian"})
	elif style == "magic" and spell != "" and not _spell_usable(f, spell, true):
		f.pending_spell = ""
		f.target_id = -1
		return
	elif f.spec_armed and w.has("spec") and f.spec_energy >= _spec_cost(f, w):
		f.spec_energy -= _spec_cost(f, w)
		f.spec_armed = false
		var spec_style := str(w.get("style", "melee"))
		Specials.perform(self, f, t, str(w["spec"]["id"]), spec_style)
		style = spec_style
		add_event({"type": "fx", "id": f.id, "fx": "spec", "spec": str(w["spec"]["id"])})
		if str(w["spec"]["id"]) == "armour_break":
			f.challenge_events.append({"type": "hammer_spec"})
	else:
		if f.spec_armed:
			f.spec_armed = false
			msg(f.id, "You don't have enough special attack energy.")
		if style == "magic":
			speed = 5
			_cast(f, t, spell)
		elif style == "ranged":
			var opts := {}
			var ammo := DB.item(str(f.equipment["ammo"]))
			var needs := str(w.get("uses_ammo", ""))
			if needs != "" and str(ammo.get("ammo_type", "")) != needs:
				msg(f.id, "You have no ammunition for that weapon.")
				f.target_id = -1
				return
			if ammo.has("bolt_effect") and needs == "bolt":
				var be: Dictionary = ammo["bolt_effect"]
				var chance := float(be["chance"])
				if str(w.get("mod_id", "")) == "bolt_rack":
					chance += 0.02
				if rng.randf() < chance:
					f.challenge_events.append({"type": "bolt_proc"})
					match str(be["id"]):
						"pierce":
							opts["def_mult"] = 0.5
						"fire_burst":
							opts["dmg_mult"] = 1.2
							opts["force_hit"] = true
						"life_leech":
							opts["effects"] = {"heal_pct": 0.25}
					add_event({"type": "fx", "id": t.id, "fx": "bolt_" + str(be["id"])})
			make_attack(f, t, "ranged", opts)
		else:
			make_attack(f, t, "melee", {})
	f.attack_timer = speed
	f.last_attack_tick = tick
	f.last_attack_style = style
	t.last_attacked_by = f.id
	t.last_attacked_tick = tick
	f.spawn_shield = 0
	add_event({"type": "attack", "id": f.id, "target": t.id, "style": style, "spell": spell if style == "magic" else "", "weapon": str(w.get("id", ""))})
	if t.target_id == -1 and t.auto_retaliate and not t.is_bot and t.path.is_empty():
		t.target_id = f.id
	if f.pending_spell != "":
		f.pending_spell = ""
		if f.weapon_style() != "magic":
			f.target_id = -1


func _cast(f: Fighter, t: Fighter, spell: String) -> void:
	var sp: Dictionary = DB.spells[spell]
	if bool(sp.get("rune_limited", false)) and not f.has_perk("spell_satchel"):
		f.rune_casts -= 2 if f.loadout.get("spell_mods", {}).has("ember_bonus") else 1
	var effects := {}
	for k in ["freeze", "poison", "heal_pct", "att_drain"]:
		if sp.has(k):
			effects[k] = sp[k]
	if effects.has("freeze"):
		var ring := DB.item(str(f.equipment["ring"]))
		effects["freeze"] = int(effects["freeze"]) + int(ring.get("freeze_bonus_ticks", 0))
	var targets: Array = [t]
	if int(sp.get("area", 1)) >= 3:
		for o in fighters.values():
			var of: Fighter = o
			if of != t and of.is_alive() and rules.can_attack(f, of) and MapGrid.chebyshev(of.pos, t.pos) <= 1:
				targets.append(of)
				if targets.size() >= 9:
					break
	var frozen_count := 0
	for x in targets:
		var h := make_attack(f, x, "magic", {"spell": spell, "effects": effects.duplicate()})
		if bool(h["accurate"]) and effects.has("freeze"):
			frozen_count += 1
	if frozen_count >= 3:
		f.challenge_events.append({"type": "multi_freeze", "count": frozen_count})


## Rolls accuracy and damage now (OSRS: decided when the attack is made) and queues the
## hit to land after projectile travel. opts: acc_mult, dmg_mult, def_mult, spell, effects,
## spec, force_hit, fixed_damage, min_damage, max_override, delay, delay_add, proj.
func make_attack(f: Fighter, t: Fighter, style: String, opts: Dictionary = {}) -> Dictionary:
	var spell := str(opts.get("spell", ""))
	var att := int(Combat.attack_roll(f, style) * float(opts.get("acc_mult", 1.0)))
	var dfn := int(Combat.defence_roll(t, style) * float(opts.get("def_mult", 1.0)))
	var chance := Combat.hit_chance(att, dfn)
	var accurate := bool(opts.get("force_hit", false)) or rng.randf() < chance
	var max_hit := int(opts.get("max_override", Combat.fighter_max_hit(f, style, spell)))
	max_hit = int(floor(max_hit * float(opts.get("dmg_mult", 1.0))))
	var dmg := 0
	if opts.has("fixed_damage"):
		dmg = int(opts["fixed_damage"])
	elif accurate:
		dmg = rng.randi_range(0, max_hit)
	if opts.has("min_damage"):
		dmg = maxi(dmg, int(opts["min_damage"]))
		accurate = true
	var protected := t.protect_style() == style and style != "typeless"
	var raw := dmg
	if protected and dmg > 0:
		dmg = Combat.protect_damage(dmg)
	if protected:
		t.challenge_events.append({"type": "blocked"})
	var dist := MapGrid.chebyshev(f.pos, t.pos)
	var delay := int(opts.get("delay", Combat.hit_delay(style, dist))) + int(opts.get("delay_add", 0))
	var h := {
		"land": tick + delay, "attacker": f.id, "target": t.id, "life": t.life_id, "dmg": dmg, "raw": raw,
		"style": style, "accurate": accurate, "max_hit": max_hit, "spec": str(opts.get("spec", "")),
		"spell": spell, "effects": opts.get("effects", {}), "protected": protected,
		"weapon": str(f.weapon().get("name", "")) if spell == "" else str(DB.spells[spell]["name"]),
		"weapon_type": str(f.weapon().get("weapon_type", "")), "dist": dist,
	}
	pending_hits.append(h)
	if style != "melee":
		var proj := str(opts.get("proj", ""))
		if proj == "":
			if spell != "":
				proj = str(DB.spells[spell].get("family", "ember"))
			else:
				var wt := str(f.weapon().get("weapon_type", ""))
				proj = "bolt" if str(f.weapon().get("uses_ammo", "")) == "bolt" else ("knife" if wt == "throwing_knives" or wt == "javelins" else "arrow")
		add_event({"type": "projectile", "from": f.id, "to": t.id, "kind": proj, "land": tick + delay, "start": tick})
	return h


# =============================================================== 6. hits

func _land_hits() -> void:
	if pending_hits.is_empty():
		return
	var keep: Array = []
	var now: Array = []
	for h in pending_hits:
		if int(h["land"]) <= tick:
			now.append(h)
		else:
			keep.append(h)
	pending_hits = keep
	for h in now:
		_apply_hit(h)


func _apply_hit(h: Dictionary) -> void:
	var t := get_fighter(int(h["target"]))
	if t == null or not t.is_alive() or t.life_id != int(h["life"]):
		return
	var a := get_fighter(int(h["attacker"]))
	var style := str(h["style"])
	if style == "magic" and not bool(h["accurate"]):
		add_event({"type": "splash", "target": t.id})
		return
	var dmg := int(h["dmg"])
	if t.rebuke_armed and dmg > 0 and a != null and a.is_alive():
		t.rebuke_armed = false
		var refl := int(floor(dmg * float(DB.perks["rebuke"].get("reflect", 0.75))))
		add_event({"type": "fx", "id": t.id, "fx": "rebuke_hit"})
		deal_damage(a, refl, t.id, "typeless", {})
		t.challenge_events.append({"type": "rebuke_reflect"})
	deal_damage(t, dmg, int(h["attacker"]), style, h)
	if a != null and dmg > 0 and int(h["raw"]) >= int(h["max_hit"]) and int(h["max_hit"]) > 0:
		a.challenge_events.append({"type": "max_hit", "weapon_type": h["weapon_type"]})
	if not t.is_alive() and not t.dying:
		return
	var fx: Dictionary = h.get("effects", {})
	if bool(h["accurate"]) and not fx.is_empty():
		if fx.has("freeze"):
			var ft := int(fx["freeze"])
			if _freeze(t, ft) and a != null:
				a.challenge_events.append({"type": "freeze", "target": t.id, "spec": str(h["spec"])})
		if fx.has("poison") and not t.has_perk("antivenom") and t.poison_hits_left <= 0:
			var p: Dictionary = DB.consumables_meta.get("poison", {})
			t.poison_hits_left = int(p.get("hits", 5))
			t.poison_damage = int(p.get("damage", 4))
			t.poison_timer = int(p.get("interval", 15))
			msg(t.id, "You have been poisoned!")
			if a != null:
				a.challenge_events.append({"type": "poison"})
		if fx.has("heal_pct") and a != null and a.is_alive() and dmg > 0:
			var heal := int(floor(dmg * float(fx["heal_pct"])))
			a.hp = mini(a.max_hp, a.hp + heal)
			if heal > 0:
				add_event({"type": "splat", "target": a.id, "amount": heal, "kind": "heal"})
				a.challenge_events.append({"type": "leech", "amount": heal})
		if fx.has("att_drain"):
			t.levels["attack"] = maxi(1, int(floor(int(t.levels["attack"]) * (1.0 - float(fx["att_drain"])))))
		if fx.has("def_drain") and dmg > 0:
			t.levels["defence"] = maxi(1, int(floor(int(t.levels["defence"]) * (1.0 - float(fx["def_drain"])))))
			msg(t.id, "Your armour has been weakened!")
		if fx.has("ward_block"):
			t.ward_block_ticks = int(fx["ward_block"])
			for p in t.active_prayers.duplicate():
				if DB.prayers[p].has("protect"):
					t.active_prayers.erase(p)
			msg(t.id, "Your wards have been severed!")
		if fx.has("energy_drain") and a != null:
			var x := t.run_energy * float(fx["energy_drain"])
			t.run_energy -= x
			a.run_energy = minf(100.0, a.run_energy + x)
		if fx.has("bleed") and dmg > 0:
			t.bleed.append({"ticks": 5, "left": dmg, "attacker": int(h["attacker"])})
	if a != null and a.has_prayer("sap") and dmg > 0:
		var drained := mini(t.prayer_points, int(floor(dmg / 4.0)))
		t.prayer_points -= drained
		a.challenge_events.append({"type": "sap", "amount": drained})
		if t.prayer_points <= 0:
			t.active_prayers.clear()


## Applies damage and all the bookkeeping. style "typeless" for meteors, rebuke, poison.
func deal_damage(t: Fighter, dmg: int, src_id: int, style: String, info: Dictionary) -> void:
	if not t.is_alive():
		return
	dmg = clampi(dmg, 0, t.hp)
	t.hp -= dmg
	var kind := "hit" if dmg > 0 else "block"
	if style == "poison":
		kind = "poison"
	add_event({"type": "splat", "target": t.id, "amount": dmg, "kind": kind, "style": style})
	var src := get_fighter(src_id)
	if src != null and src != t:
		src.damage_dealt += dmg
		var credit_style := style
		if not DB.STYLES.has(credit_style):
			credit_style = src.weapon_style()
		if src.npc_kind == "" and dmg > 0:
			src.damage_by_style[credit_style] = int(src.damage_by_style.get(credit_style, 0)) + dmg
		if not t.first_hit_from.has(src_id) and dmg > 0:
			t.first_hit_from[src_id] = tick
		t.damage_from[src_id] = int(t.damage_from.get(src_id, 0)) + dmg
		if not t.damage_from_style.has(src_id):
			t.damage_from_style[src_id] = {}
		t.damage_from_style[src_id][credit_style] = int(t.damage_from_style[src_id].get(credit_style, 0)) + dmg
		t.last_hit_by = src_id
		t.last_hit_style = credit_style
		t.last_hit_spec = str(info.get("spec", "")) != ""
		t.last_hit_streak = bool(info.get("streak", false))
		t.last_hit_weapon = str(info.get("weapon", style.capitalize()))
	t.damage_taken_life += dmg
	if t.hp <= 0:
		t.dying = true
		return
	if t.has_prayer("last_rites") and t.hp < int(DB.rule("last_rites_threshold", 10)):
		var heal := int(floor(99 * 0.25))
		t.hp = mini(t.max_hp, t.hp + heal)
		t.prayer_points = 0
		t.active_prayers.clear()
		add_event({"type": "splat", "target": t.id, "amount": heal, "kind": "heal"})
		add_event({"type": "fx", "id": t.id, "fx": "last_rites"})
	if t.has_perk("second_wind") and not t.second_wind_used and t.hp < int(DB.rule("second_wind_threshold", 10)):
		t.second_wind_used = true
		t.second_wind_ticks = int(DB.rule("second_wind_ticks", 5))
		msg(t.id, "Second Wind!")


func _land_meteors() -> void:
	var keep: Array = []
	for m in meteors:
		if int(m["land"]) > tick:
			keep.append(m)
			continue
		var half := int(m["size"]) / 2
		var owner := get_fighter(int(m["owner"]))
		add_event({"type": "fx", "fx": "meteor_impact", "x": m["x"], "y": m["y"], "size": m["size"]})
		for o in fighters.values():
			var of: Fighter = o
			if not of.is_alive() or int(m["team"]) == of.team:
				continue
			if absi(of.pos.x - int(m["x"])) <= half and absi(of.pos.y - int(m["y"])) <= half:
				var cfg: Dictionary = DB.streaks["meteor_strike"]
				var dmg := rng.randi_range(int(cfg["min_damage"]), int(cfg["max_damage"]))
				deal_damage(of, dmg, owner.id if owner != null else -1, "typeless", {"streak": true, "weapon": "Meteor Strike"})
	meteors = keep


# =============================================================== 7. deaths, timers, respawns

func _process_deaths() -> void:
	var guard := 0
	while guard < 4:
		guard += 1
		var dying: Array = []
		for f in fighters.values():
			if (f as Fighter).dying:
				dying.append(f)
		if dying.is_empty():
			return
		for f in dying:
			_kill(f)


func _kill(v: Fighter) -> void:
	v.dying = false
	v.dead = true
	v.hp = 0
	var had_reckoning := v.has_prayer("reckoning")
	v.active_prayers.clear()
	v.target_id = -1
	v.path.clear()
	v.frozen_ticks = 0
	var killer := get_fighter(v.last_hit_by)
	var credit := killer
	var streak_kill := v.last_hit_streak
	if killer != null and killer.npc_kind == "guardian":
		credit = get_fighter(killer.owner_id)
		streak_kill = true
	if v.npc_kind == "guardian":
		add_event({"type": "kill", "killer": credit.id if credit != null else -1, "victim": v.id, "weapon": v.last_hit_weapon, "style": v.last_hit_style, "npc": true})
		if credit != null:
			credit.guardian_kills += 1
			credit.challenge_events.append({"type": "guardian_kill"})
		fighters.erase(v.id)
		return
	v.deaths += 1
	if had_reckoning:
		for o in fighters.values():
			var of: Fighter = o
			if of.is_alive() and rules.can_attack(v, of) and MapGrid.chebyshev(of.pos, v.pos) <= 1:
				deal_damage(of, rng.randi_range(0, int(floor(99 * 0.25))), v.id, "typeless", {"weapon": "Reckoning"})
		add_event({"type": "fx", "id": v.id, "fx": "reckoning"})
	var kstyle := v.last_hit_style
	if credit != null and credit != v:
		credit.kills += 1
		if not DB.STYLES.has(kstyle):
			kstyle = credit.weapon_style()
		credit.kill_styles[kstyle] = int(credit.kill_styles.get(kstyle, 0)) + 1
		if v.last_hit_spec:
			credit.spec_kills[kstyle] = int(credit.spec_kills.get(kstyle, 0)) + 1
		if credit.last_killer_id == v.id:
			credit.revenge_kills[kstyle] = int(credit.revenge_kills.get(kstyle, 0)) + 1
			msg(credit.id, "Revenge!")
		credit.kills_this_life_styles[kstyle] = true
		var kwt := _weapon_type_of_kill(credit, v)
		credit.life_weapon_kills[kwt] = int(credit.life_weapon_kills.get(kwt, 0)) + 1
		if credit.kills_this_life_styles.size() >= 3 and not credit.tribrid_done:
			credit.tribrid_done = true
			credit.challenge_events.append({"type": "tribrid"})
		credit.challenge_events.append({
			"type": "kill", "style": kstyle, "spec": v.last_hit_spec, "weapon_type": kwt, "life_type_kills": int(credit.life_weapon_kills[kwt]),
			"victim_frozen": v.frozen_ticks > 0, "dist": MapGrid.chebyshev(credit.pos, v.pos), "hp": credit.hp,
			"victim_rebuke": v.rebuke_armed, "first_hit_tick": _first_hit_tick(v, credit.id), "tick": tick,
			"damage_taken_life": credit.damage_taken_life, "streak_kill": streak_kill,
		})
		if not first_blood:
			first_blood = true
			credit.challenge_events.append({"type": "first_blood"})
			add_event({"type": "first_blood", "id": credit.id})
		if not streak_kill and credit.npc_kind == "":
			credit.streak += 1
			credit.best_streak = maxi(credit.best_streak, credit.streak)
			_check_streak(credit)
		rules.on_kill(credit, v)
	for src_id in v.damage_from:
		if credit != null and src_id == credit.id:
			continue
		var src := get_fighter(src_id)
		if src == null or src.npc_kind != "" or src == v:
			continue
		if int(v.damage_from[src_id]) >= int(DB.levels["xp"].get("assist_min_damage", 10)):
			src.assists += 1
			var best_style := src.weapon_style()
			var best_dmg := -1
			var per: Dictionary = v.damage_from_style.get(src_id, {})
			for s in per:
				if DB.STYLES.has(s) and int(per[s]) > best_dmg:
					best_dmg = int(per[s])
					best_style = s
			src.assist_styles[best_style] = int(src.assist_styles.get(best_style, 0)) + 1
	v.last_killer_id = credit.id if credit != null else -1
	v.streak = 0
	add_event({"type": "kill", "killer": credit.id if credit != null else -1, "victim": v.id, "weapon": v.last_hit_weapon, "style": kstyle})
	rules.on_death(v)


func _first_hit_tick(v: Fighter, src: int) -> int:
	return int(v.first_hit_from.get(src, tick))


func _weapon_type_of_kill(credit: Fighter, v: Fighter) -> String:
	if v.last_hit_style == "magic":
		var sp := credit.current_spell()
		if sp != "":
			return "spell_" + str(DB.spells[sp].get("family", ""))
	return str(credit.weapon().get("weapon_type", ""))


func _check_streak(f: Fighter) -> void:
	if not rules.streaks_enabled():
		return
	for sid in DB.streak_order:
		var s: Dictionary = DB.streaks[sid]
		if f.streak == int(s["kills"]):
			f.streak_rewards.append(sid)
			add_event({"type": "streak_ready", "id": f.id, "reward": sid})
			msg(f.id, "%s ready! Press %s." % [s["name"], s["hotkey"]])
			f.challenge_events.append({"type": "streak_earned", "reward": sid})


func _use_streak(f: Fighter, sid: String, tile: Vector2i) -> void:
	if not f.streak_rewards.has(sid):
		return
	var s: Dictionary = DB.streaks.get(sid, {})
	match sid:
		"scrying_orb":
			reveal_until[f.team] = tick + int(s.get("duration_ticks", 50))
			add_event({"type": "streak_used", "id": f.id, "reward": sid, "team": f.team})
		"meteor_strike":
			if not map.in_bounds(tile.x, tile.y):
				return
			meteors.append({"land": tick + int(s.get("warning_ticks", 3)), "x": tile.x, "y": tile.y, "size": int(s.get("size", 5)), "owner": f.id, "team": f.team})
			add_event({"type": "streak_used", "id": f.id, "reward": sid, "x": tile.x, "y": tile.y})
		"guardian":
			var g := Fighter.new()
			g.id = _next_id
			_next_id += 1
			g.name = "%s's Guardian" % f.name
			g.team = f.team
			g.is_bot = true
			g.npc_kind = "guardian"
			g.owner_id = f.id
			g.max_hp = int(s.get("hp", 150))
			g.hp = g.max_hp
			g.npc_expire_tick = tick + int(s.get("duration_ticks", 75))
			g.pos = map.nearest_walkable(f.pos + Vector2i(1, 0))
			g.trail = [g.pos]
			g.life_id = 1
			g.bonuses["def_melee"] = 60
			g.bonuses["def_ranged"] = 60
			g.bonuses["def_magic"] = 60
			fighters[g.id] = g
			add_event({"type": "streak_used", "id": f.id, "reward": sid, "guardian": g.id})
		_:
			return
	f.streak_rewards.erase(sid)


func _timers(f: Fighter) -> void:
	if f.food_timer > 0:
		f.food_timer -= 1
	if f.combo_timer > 0:
		f.combo_timer -= 1
	if f.potion_timer > 0:
		f.potion_timer -= 1
	if not f.is_alive():
		return
	if f.spawn_shield > 0:
		f.spawn_shield -= 1
	if f.ward_block_ticks > 0:
		f.ward_block_ticks -= 1
	if f.rebuke_cooldown > 0:
		f.rebuke_cooldown -= 1
	if f.frozen_ticks > 0:
		f.frozen_ticks -= 1
		if f.frozen_ticks == 0:
			f.freeze_immune_ticks = int(DB.spells_meta.get("unbound_immunity_ticks", 5)) if f.has_perk("unbound") else int(DB.spells_meta.get("freeze_immunity_ticks", 8))
	elif f.freeze_immune_ticks > 0:
		f.freeze_immune_ticks -= 1
	# Hitpoints regen (and brew overheal decay).
	f.hp_regen_timer += 1
	var hp_int := int(DB.rule("hp_regen_interval", 100))
	if f.has_prayer("mending"):
		hp_int /= 2
	if f.hp_regen_timer >= hp_int:
		f.hp_regen_timer = 0
		if f.hp < f.max_hp:
			f.hp += 1
		elif f.hp > f.max_hp:
			f.hp -= 1
	# Special energy.
	f.spec_regen_timer += 1
	var sp_int := int(DB.rule("spec_regen_interval", 50))
	if f.has_perk("steady_hand"):
		sp_int /= 2
	if f.spec_regen_timer >= sp_int:
		f.spec_regen_timer = 0
		f.spec_energy = mini(100, f.spec_energy + int(DB.rule("spec_regen_amount", 10)))
	# Stat boosts and drains drift back to base.
	f.boost_timer += 1
	var b_int := int(DB.consumables_meta.get("boost_decay_ticks", 100))
	if f.has_prayer("endurance"):
		b_int = int(b_int * 1.5)
	if f.boost_timer >= b_int:
		f.boost_timer = 0
		for s in Fighter.STATS:
			var cur := int(f.levels[s])
			var base := int(f.base_levels[s])
			if cur > base:
				f.levels[s] = cur - 1
			elif cur < base:
				f.levels[s] = cur + 1
	if f.has_prayer("devotion"):
		f.devotion_timer += 1
		if f.devotion_timer >= int(DB.rule("devotion_interval", 30)):
			f.devotion_timer = 0
			f.prayer_points = mini(99, f.prayer_points + 1)
	# Poison.
	if f.poison_hits_left > 0:
		f.poison_timer -= 1
		if f.poison_timer <= 0:
			f.poison_timer = int(DB.consumables_meta.get("poison", {}).get("interval", 15))
			f.poison_hits_left -= 1
			deal_damage(f, f.poison_damage, f.last_hit_by, "poison", {"weapon": "Poison"})
	# Bleed (Javelin special).
	if not f.bleed.is_empty():
		var keep: Array = []
		for b in f.bleed:
			var per := int(ceil(float(b["left"]) / float(b["ticks"])))
			b["left"] = int(b["left"]) - per
			b["ticks"] = int(b["ticks"]) - 1
			if f.is_alive():
				deal_damage(f, per, int(b["attacker"]), "typeless", {"weapon": "Bleed"})
			if int(b["ticks"]) > 0 and int(b["left"]) > 0:
				keep.append(b)
		f.bleed = keep
	if f.second_wind_ticks > 0 and f.is_alive():
		f.second_wind_ticks -= 1
		var h := int(DB.rule("second_wind_heal", 15)) / int(DB.rule("second_wind_ticks", 5))
		f.hp = mini(f.max_hp, f.hp + h)
		add_event({"type": "splat", "target": f.id, "amount": h, "kind": "heal"})
	if f.dying:
		_process_deaths()


func _respawns() -> void:
	if phase == "over":
		return
	for f in fighters.values():
		var fi: Fighter = f
		if fi.dead and not fi.out_of_round and fi.npc_kind == "" and rules.respawns():
			fi.respawn_ticks -= 1
			if fi.respawn_ticks <= 0:
				spawn(fi)


func _expire_npcs() -> void:
	for f in fighters.values():
		var fi: Fighter = f
		if fi.npc_kind != "" and tick >= fi.npc_expire_tick:
			fighters.erase(fi.id)
			add_event({"type": "fx", "id": fi.id, "fx": "despawn"})


## (Re)spawns a fighter with a fresh copy of its class loadout.
func spawn(f: Fighter) -> void:
	if not f.next_loadout.is_empty():
		f.loadout = f.next_loadout
		f.next_loadout = {}
	var lo := f.loadout
	f.equipment = (lo.get("equipment", {}) as Dictionary).duplicate()
	for s in DB.EQUIP_SLOTS:
		if not f.equipment.has(s):
			f.equipment[s] = ""
	f.inventory = []
	for e in lo.get("inventory", []):
		f.inventory.append(null if e == null else (e as Dictionary).duplicate())
	while f.inventory.size() < 28:
		f.inventory.append(null)
	f.spellbook = str(lo.get("spellbook", "elemental"))
	f.autocast = str(lo.get("autocast", ""))
	f.perks = (lo.get("perks", []) as Array).duplicate()
	f.recalc_bonuses()
	var base := int(DB.rule("base_level", 99))
	for s in Fighter.STATS:
		f.base_levels[s] = base
	if bool(lo.get("pure", false)):
		f.base_levels["defence"] = 1
	for s in Fighter.STATS:
		f.levels[s] = int(f.base_levels[s])
	if bool(lo.get("combat_boosts", false)):
		var boosts: Dictionary = DB.consumables_meta.get("combat_boosts", {})
		for s in Fighter.STATS:
			if boosts.has(s):
				var b: Array = boosts[s]
				f.levels[s] = int(f.base_levels[s]) + int(b[0]) + int(floor(int(f.base_levels[s]) * float(b[1])))
	f.max_hp = int(DB.rule("max_hp", 99))
	f.hp = f.max_hp
	f.prayer_points = int(DB.rule("max_prayer", 99))
	f.prayer_drain_counter = 0.0
	f.spec_energy = 100
	f.spec_armed = false
	f.run_energy = 100.0
	f.running = true
	f.attack_timer = 0
	f.food_timer = 0
	f.combo_timer = 0
	f.potion_timer = 0
	f.active_prayers.clear()
	f.prayer_queue.clear()
	f.action_queue.clear()
	f.frozen_ticks = 0
	f.freeze_immune_ticks = 0
	f.ward_block_ticks = 0
	f.poison_hits_left = 0
	f.bleed.clear()
	f.rebuke_armed = false
	f.rebuke_cooldown = 0
	f.trap_available = f.has_perk("snare_trap")
	f.second_wind_used = false
	f.second_wind_ticks = 0
	f.rune_casts = int(DB.spells_meta.get("rune_casts_per_life", 30))
	f.target_id = -1
	f.pending_spell = ""
	f.path.clear()
	f.dest = Vector2i(-1, -1)
	f.dead = false
	f.dying = false
	f.spawn_shield = DB.ticks(float(DB.modes.get("spawn_shield_s", 3)))
	f.life_id += 1
	f.damage_from.clear()
	f.damage_from_style.clear()
	f.first_hit_from.clear()
	f.damage_taken_life = 0
	f.kills_this_life_styles.clear()
	f.life_weapon_kills.clear()
	f.tribrid_done = false
	f.last_hit_by = -1
	f.last_hit_streak = false
	f.last_hit_spec = false
	f.pos = rules.pick_spawn(f)
	f.trail = [f.pos]
	add_event({"type": "spawn", "id": f.id})


func end_match(winner: int) -> void:
	if phase == "over":
		return
	phase = "over"
	result = {"winner": winner, "scores": scores.duplicate(), "mode": mode_id, "ticks": live_ticks}
	add_event({"type": "match_over", "winner": winner})


func team_won(team: int) -> bool:
	return not result.is_empty() and int(result.get("winner", -1)) == team


# =============================================================== 8. snapshot

func _pub(f: Fighter, viewer: Fighter) -> Dictionary:
	var ovh := f.overhead()
	if viewer != null and viewer.id != f.id and rules.can_attack(viewer, f):
		var rng_view := int(DB.rule("overhead_view_range", 15))
		if viewer.has_perk("eagle_sight"):
			rng_view += int(DB.rule("eagle_sight_bonus", 5))
		if MapGrid.chebyshev(viewer.pos, f.pos) > rng_view:
			ovh = ""
	return {
		"id": f.id, "name": f.name, "team": f.team, "pos": f.pos, "trail": f.trail.duplicate(),
		"hp": f.hp, "max_hp": f.max_hp, "dead": f.dead or f.out_of_round, "ovh": ovh,
		"frozen": f.frozen_ticks > 0, "shield": f.spawn_shield > 0, "eq": f.equipment.duplicate(),
		"style": f.attack_style(), "cl": f.combat_level, "npc": f.npc_kind, "bot": f.is_bot,
		"kills": f.kills, "deaths": f.deaths, "assists": f.assists, "damage": f.damage_dealt,
		"obj": f.objective_score, "poisoned": f.poison_hits_left > 0, "target": f.target_id,
		"kit": str(f.loadout.get("kits", {}).get(str(f.weapon().get("weapon_type", "")), "")),
	}


func snapshot(viewer_id: int) -> Dictionary:
	var viewer := get_fighter(viewer_id)
	var fl: Array = []
	for f in fighters.values():
		fl.append(_pub(f, viewer))
	var me := {}
	if viewer != null:
		var f := viewer
		me = {
			"id": f.id, "inventory": f.inventory.duplicate(true), "equipment": f.equipment.duplicate(),
			"prayers": f.active_prayers.duplicate(), "prayer": f.prayer_points, "hp": f.hp, "max_hp": f.max_hp,
			"run": f.run_energy, "running": f.running, "spec": f.spec_energy, "spec_armed": f.spec_armed,
			"spellbook": f.spellbook, "autocast": f.autocast, "pending_spell": f.pending_spell,
			"stance": f.stance, "retaliate": f.auto_retaliate, "levels": f.levels.duplicate(),
			"bonuses": f.bonuses.duplicate(), "perks": f.perks.duplicate(), "streak": f.streak,
			"streak_rewards": f.streak_rewards.duplicate(), "frozen": f.frozen_ticks, "immune": f.freeze_immune_ticks,
			"respawn": f.respawn_ticks, "dead": f.dead or f.out_of_round, "rebuke_cd": f.rebuke_cooldown,
			"rebuke_armed": f.rebuke_armed, "trap": f.trap_available, "rune_casts": f.rune_casts,
			"target": f.target_id, "ward_block": f.ward_block_ticks, "team": f.team, "pos": f.pos,
			"unlocked_prayers": _unlocked_list(f, DB.prayer_order), "unlocked_spells": _unlocked_list(f, DB.spell_order),
			"attack_timer": f.attack_timer, "max_hit": Combat.fighter_max_hit(f, f.attack_style(), f.current_spell()),
		}
	var vis_traps: Array = []
	for tr in traps:
		if viewer != null and int(tr["team"]) == viewer.team:
			vis_traps.append(tr["pos"])
	var ev: Array = []
	for e in events:
		if e.has("to") and int(e["to"]) != viewer_id:
			continue
		ev.append(e)
	return {
		"tick": tick, "phase": phase, "phase_ticks": phase_ticks, "time_left": rules.time_left_ticks(),
		"mode": mode_id, "mode_type": rules.type, "scores": scores.duplicate(), "score_limit": rules.score_limit,
		"round": rules.round_num, "rounds_to_win": rules.rounds_to_win,
		"fighters": fl, "me": me, "objectives": objectives.duplicate(true),
		"meteors": meteors.duplicate(true), "traps": vis_traps,
		"reveal": viewer != null and int(reveal_until.get(viewer.team, -1)) > tick,
		"events": ev, "result": result,
	}


func _unlocked_list(f: Fighter, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		if f.unlocked.has(id):
			out.append(id)
	return out
