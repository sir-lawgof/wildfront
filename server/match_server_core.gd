class_name MatchServerCore
extends RefCounted
## Owns one match: the authoritative Sim plus the bots that fill empty slots.
## Has no Node dependencies, so tests and the balance simulator can run it headless.
## server/match_server.gd wraps it in a Node that ticks every 600 ms.

const BOT_NAMES := [
	"Grimbold", "Ashka", "Thorne", "Velka", "Brannoc", "Isolde", "Kettrick", "Morwen", "Dunstan", "Sable",
	"Orrin", "Wren", "Haldor", "Fenna", "Corvin", "Elsbeth", "Garrick", "Ysolde", "Torvald", "Maelis",
	"Rook", "Brielle", "Osric", "Talia", "Edric", "Nyssa", "Bertram", "Liesel", "Cadoc", "Rowena",
]
const BOT_CLASS_WEIGHTS := {"warrior": 30, "archer": 25, "battlemage": 25, "tribrid": 20}

var sim: Sim
var bots: Dictionary = {}          ## fighter id -> BotBrain
var player_id: int = -1           ## the local (host) player's fighter
var humans: Dictionary = {}        ## fighter id -> network peer id (1 = host)
var peer_to_fid: Dictionary = {}   ## network peer id -> fighter id
var config: Dictionary = {}
var playlist: String = "standard"
var rng := RandomNumberGenerator.new()


## cfg keys: mode, map, playlist, seed, pre_ticks,
##   player: {name, class_def, levels: {melee, ranged, magic}} (empty = bots only)
##   players: [{name, class_def, levels, peer}] for LAN matches (first = host; humans alternate teams)
##   bot_skill: 0..1 (default 0.6)
func setup(cfg: Dictionary) -> void:
	DB.ensure_loaded()
	config = cfg
	playlist = str(cfg.get("playlist", "standard"))
	if cfg.has("seed"):
		rng.seed = int(cfg["seed"])
	else:
		rng.randomize()
	sim = Sim.new()
	var sim_opts := {"seed": rng.randi()}
	if cfg.has("pre_ticks"):
		sim_opts["pre_ticks"] = int(cfg["pre_ticks"])
	sim.setup(str(cfg.get("mode", "clan_clash")), str(cfg.get("map", "frostgate_ruins")), sim_opts)
	var mode: Dictionary = sim.mode
	var ffa := str(mode.get("type", "")) == "ffa"
	var team_size := int(mode.get("team_size", 5))
	var slots: Array = []   # team per slot
	if ffa:
		for i in range(team_size):
			slots.append(i)
	else:
		for i in range(team_size):
			slots.append(0)
			slots.append(1)
	var players: Array = cfg.get("players", [])
	if players.is_empty() and not (cfg.get("player", {}) as Dictionary).is_empty():
		players = [cfg["player"]]
	var base_levels := {"melee": 1, "ranged": 1, "magic": 1}
	if not players.is_empty():
		for s in DB.STYLES:
			var tot := 0
			for p in players:
				tot += int(p.get("levels", {}).get(s, 1))
			base_levels[s] = int(round(float(tot) / players.size()))
	for i in range(players.size()):
		var p: Dictionary = players[i]
		var team: int = i if ffa else i % 2
		if not slots.has(team):
			team = slots[0]
		var fid := _add(str(p.get("name", "Player")).left(12), team, false, p.get("class_def", DB.classes["defaults"]["warrior"]), p.get("levels", base_levels))
		slots.erase(team)
		humans[fid] = int(p.get("peer", 1))
		peer_to_fid[int(p.get("peer", 1))] = fid
		if i == 0:
			player_id = fid
	var names := BOT_NAMES.duplicate()
	_shuffle(names)
	var skill := float(cfg.get("bot_skill", 0.6))
	for i in range(slots.size()):
		var team: int = slots[i]
		var lv := _bot_levels(base_levels)
		var cls_id := _pick_class()
		var fid := _add(str(names[i % names.size()]), team, true, DB.classes["defaults"][cls_id], lv)
		var s := clampf(skill + rng.randf_range(-0.2, 0.2), 0.15, 0.95)
		bots[fid] = BotBrain.new(fid, s, rng.randi())


func _add(p_name: String, team: int, is_bot: bool, class_def: Dictionary, levels: Dictionary) -> int:
	var unl: Dictionary
	if playlist == "even_ground":
		unl = Loadout.all_unlocked()
	else:
		unl = Progression.unlocked_set(levels)
	var lo := Loadout.build(class_def, unl, {"supply": str(sim.mode.get("supply", "full")), "pure": playlist == "pure_brawl"})
	return sim.add_fighter(p_name, team, is_bot, lo, unl, levels)


## Combat-level matchmaking stand-in: bots are within a few levels of the player (GDD 5).
func _bot_levels(base: Dictionary) -> Dictionary:
	var out := {}
	for s in ["melee", "ranged", "magic"]:
		out[s] = clampi(int(base.get(s, 1)) + rng.randi_range(-3, 3), 1, 40)
	return out


func _pick_class() -> String:
	var total := 0
	for k in BOT_CLASS_WEIGHTS:
		total += int(BOT_CLASS_WEIGHTS[k])
	var r := rng.randi_range(1, total)
	for k in BOT_CLASS_WEIGHTS:
		r -= int(BOT_CLASS_WEIGHTS[k])
		if r <= 0:
			return k
	return "warrior"


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


## Player intents arrive here (from the local client or, later, the network).
func submit(fid: int, intent: Dictionary) -> void:
	if not humans.has(fid):
		return
	sim.queue_intent(fid, intent)


## Rebuilds the player's loadout for their next life (create-a-class / class change).
func change_class(fid: int, class_def: Dictionary, levels: Dictionary) -> void:
	var f := sim.get_fighter(fid)
	if f == null:
		return
	var lo := Loadout.build(class_def, f.unlocked, {"supply": str(sim.mode.get("supply", "full")), "pure": playlist == "pure_brawl"})
	sim.queue_intent(fid, {"type": "class", "loadout": lo})


func tick() -> void:
	for bid in bots:
		(bots[bid] as BotBrain).think(sim)
	for f in sim.fighters.values():
		var fi: Fighter = f
		if fi.npc_kind == "guardian" and fi.is_alive():
			BotBrain.think_guardian(sim, fi)
	sim.step()


## End-of-match results for the local player: scoreboard, XP breakdown and the raw
## challenge events. XP is computed here, on the server side, with the shared rules.
func summary(forfeit: bool = false, fid: int = -1) -> Dictionary:
	if fid == -1:
		fid = player_id
	var rows: Array = []
	for f in sim.fighters.values():
		var fi: Fighter = f
		if fi.npc_kind != "":
			continue
		rows.append({"id": fi.id, "name": fi.name, "team": fi.team, "kills": fi.kills, "deaths": fi.deaths,
			"assists": fi.assists, "damage": fi.damage_dealt, "obj": fi.objective_score, "cl": fi.combat_level, "bot": fi.is_bot})
	var me := sim.get_fighter(fid)
	var winner := int(sim.result.get("winner", -1))
	if forfeit:
		winner = (1 - me.team) if (me != null and sim.rules.type != "ffa") else -1
	var won := me != null and not forfeit and winner == me.team
	var out := {
		"mode": sim.mode_id, "mode_name": str(sim.mode.get("name", "")), "map": sim.map.name, "winner": winner,
		"won": won, "forfeit": forfeit, "scores": sim.scores.duplicate(), "rows": rows, "ffa": sim.rules.type == "ffa",
		"my_id": fid, "my_team": me.team if me != null else 0, "playlist": playlist,
	}
	if me != null:
		var primary_style := str(DB.item(str(me.loadout.get("primary", ""))).get("style", "melee"))
		out["xp"] = Progression.match_xp(me, won, me.rounds_won, primary_style)
		out["events"] = me.challenge_events.duplicate()
		out["stats"] = {"kills": me.kills, "deaths": me.deaths, "assists": me.assists, "damage": me.damage_dealt, "best_streak": me.best_streak}
	return out
