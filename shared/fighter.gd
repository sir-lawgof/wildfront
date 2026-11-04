class_name Fighter
extends RefCounted
## All state for one player, bot or NPC inside a match. Owned by the Sim (server).

const STATS: Array[String] = ["attack", "strength", "defence", "ranged", "magic"]

var id: int = 0
var name: String = ""
var team: int = 0
var is_bot: bool = false
var npc_kind: String = ""          ## "" for players; "guardian" for the streak NPC
var owner_id: int = -1             ## guardian owner
var npc_expire_tick: int = 0
var combat_level: int = 1
var style_levels: Dictionary = {"melee": 1, "ranged": 1, "magic": 1}

# Position
var pos: Vector2i = Vector2i.ZERO
var trail: Array[Vector2i] = []    ## tiles stepped through this tick (for client smoothing)
var path: Array[Vector2i] = []
var dest: Vector2i = Vector2i(-1, -1)
var running: bool = true
var run_energy: float = 100.0

# Vital stats
var max_hp: int = 99
var hp: int = 99
var prayer_points: int = 99
var prayer_drain_counter: float = 0.0
var base_levels: Dictionary = {}
var levels: Dictionary = {}        ## current (boosted / drained) levels
var dead: bool = false
var dying: bool = false
var respawn_ticks: int = 0
var spawn_shield: int = 0
var life_id: int = 0
var out_of_round: bool = false     ## elimination modes: dead until the next round

# Gear
var equipment: Dictionary = {}
var inventory: Array = []          ## 28 entries: null or {"id": String, "doses": int}
var bonuses: Dictionary = {}
var spellbook: String = "elemental"
var autocast: String = ""
var pending_spell: String = ""
var stance: String = "aggressive"  ## accurate | aggressive | defensive
var perks: Array = []
var loadout: Dictionary = {}       ## the class loadout used on each spawn
var next_loadout: Dictionary = {}  ## class change applies on next life
var unlocked: Dictionary = {}      ## id -> true, for prayer/spell checks
var rune_casts: int = 30

# Combat state
var target_id: int = -1
var attack_timer: int = 0
var spec_energy: int = 100
var spec_armed: bool = false
var auto_retaliate: bool = true
var active_prayers: Array[String] = []
var ward_block_ticks: int = 0      ## Sever special: wards disabled
var frozen_ticks: int = 0
var freeze_immune_ticks: int = 0
var poison_hits_left: int = 0
var poison_timer: int = 0
var poison_damage: int = 0
var bleed: Array = []              ## [{ticks_left, per_tick, attacker}]
var food_timer: int = 0
var combo_timer: int = 0
var potion_timer: int = 0
var rebuke_cooldown: int = 0
var rebuke_armed: bool = false
var trap_available: bool = false
var second_wind_used: bool = false
var second_wind_ticks: int = 0
var boost_timer: int = 0
var hp_regen_timer: int = 0
var spec_regen_timer: int = 0
var devotion_timer: int = 0
var last_attack_tick: int = -100
var last_attack_style: String = ""
var last_attacked_by: int = -1
var last_attacked_tick: int = -100

# Queues filled from intents (phase 1) and consumed later in the tick.
var action_queue: Array = []       ## [{type: equip|unequip|use|spec, ...}] processed in phase 2 in order
var prayer_queue: Array = []       ## prayer ids to toggle in phase 3

# Damage bookkeeping (this life) for kills/assists/XP
var damage_from: Dictionary = {}   ## attacker id -> total damage this life
var damage_from_style: Dictionary = {} ## attacker id -> {style: dmg}
var last_hit_by: int = -1
var last_hit_style: String = ""
var last_hit_spec: bool = false
var last_hit_streak: bool = false
var last_hit_weapon: String = ""
var damage_taken_life: int = 0
var first_hit_from: Dictionary = {}  ## attacker id -> tick of their first damaging hit this life

# Match stats
var kills: int = 0
var deaths: int = 0
var assists: int = 0
var damage_dealt: int = 0
var damage_by_style: Dictionary = {"melee": 0, "ranged": 0, "magic": 0}
var kill_styles: Dictionary = {"melee": 0, "ranged": 0, "magic": 0}
var assist_styles: Dictionary = {"melee": 0, "ranged": 0, "magic": 0}
var spec_kills: Dictionary = {"melee": 0, "ranged": 0, "magic": 0}
var revenge_kills: Dictionary = {"melee": 0, "ranged": 0, "magic": 0}
var captures: int = 0
var rounds_won: int = 0
var objective_score: int = 0
var guardian_kills: int = 0
var last_killer_id: int = -1
var streak: int = 0
var best_streak: int = 0
var streak_rewards: Array[String] = []
var kills_this_life_styles: Dictionary = {}
var life_weapon_kills: Dictionary = {}
var tribrid_done: bool = false
var challenge_events: Array = []   ## raw events for the challenge tracker


func _init() -> void:
	for s in DB.EQUIP_SLOTS:
		equipment[s] = ""
	inventory.resize(28)
	var base := int(DB.rule("base_level", 99))
	for s in STATS:
		base_levels[s] = base
		levels[s] = base
	bonuses = DB.empty_bonuses()


# ---------------------------------------------------------------- gear

func recalc_bonuses() -> void:
	bonuses = DB.empty_bonuses()
	for s in DB.EQUIP_SLOTS:
		var iid: String = equipment[s]
		if iid == "":
			continue
		var it := DB.item(iid)
		var b: Dictionary = it.get("bonuses", {})
		for k in b:
			bonuses[k] += int(b[k])
	var w := weapon()
	if w.has("mod_bonuses"):
		for k in w["mod_bonuses"]:
			bonuses[k] += int(w["mod_bonuses"][k])


func weapon() -> Dictionary:
	var iid: String = equipment.get("weapon", "")
	if iid == "":
		return DB.rule("unarmed", {})
	var it := DB.item(iid)
	# Weapon mods (create-a-class) live in the loadout and are layered on top.
	var mods: Dictionary = loadout.get("weapon_mods", {})
	if mods.has(iid):
		it = it.duplicate()
		it["mod_bonuses"] = mods[iid].get("bonuses", {})
		it["range"] = int(it.get("range", 1)) + int(mods[iid].get("range", 0))
		it["mod_id"] = mods[iid].get("id", "")
	return it


func weapon_style() -> String:
	return str(weapon().get("style", "melee"))


## The style this fighter will attack with next (spells override the weapon).
func attack_style() -> String:
	if pending_spell != "":
		return "magic"
	if autocast != "" and weapon_style() == "magic":
		return "magic"
	if weapon_style() == "magic":
		return "melee"  # staff with no spell: bash
	return weapon_style()


func current_spell() -> String:
	if pending_spell != "":
		return pending_spell
	if weapon_style() == "magic":
		return autocast
	return ""


func armour_class() -> String:
	var body := DB.item(equipment.get("body", ""))
	return str(body.get("armour_class", "none"))


func has_perk(p: String) -> bool:
	return perks.has(p)


func free_slots() -> int:
	var n := 0
	for e in inventory:
		if e == null:
			n += 1
	return n


func first_free_slot() -> int:
	for i in range(inventory.size()):
		if inventory[i] == null:
			return i
	return -1


func find_item(pred: Callable) -> int:
	for i in range(inventory.size()):
		if inventory[i] != null and pred.call(DB.item(inventory[i]["id"])):
			return i
	return -1


func count_item(iid: String) -> int:
	var n := 0
	for e in inventory:
		if e != null and e["id"] == iid:
			n += 1
	return n


# ---------------------------------------------------------------- prayers

func has_prayer(pid: String) -> bool:
	return active_prayers.has(pid)


func protect_style() -> String:
	if ward_block_ticks > 0:
		return ""
	for p in active_prayers:
		var pr: Dictionary = DB.prayers.get(p, {})
		if pr.has("protect"):
			return str(pr["protect"])
	return ""


func overhead() -> String:
	for p in active_prayers:
		var pr: Dictionary = DB.prayers.get(p, {})
		if (pr.get("groups", []) as Array).has("overhead"):
			return p
	return ""


func prayer_mult(key: String) -> float:
	var m := 1.0
	for p in active_prayers:
		var pr: Dictionary = DB.prayers.get(p, {})
		var mults: Dictionary = pr.get("mult", {})
		if mults.has(key):
			m = maxf(m, float(mults[key]))
	return m


func is_alive() -> bool:
	return not dead and not dying and not out_of_round


func public_level() -> int:
	return combat_level
