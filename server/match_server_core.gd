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
var training: Training = null      ## Proving Grounds drill / exam / dummy room (U1)
var mutator: String = ""           ## The Lab (U7): this match's mutator id
var loadout_mods: Dictionary = {}  ## mutator loadout changes (food_mult, kit)
var recording: Dictionary = {}     ## U8 replay: setup + every human input by tick
var record: bool = true
var rng := RandomNumberGenerator.new()


## cfg keys: mode, map, playlist, seed, pre_ticks,
##   player: {name, class_def, levels: {melee, ranged, magic}} (empty = bots only)
##   players: [{name, class_def, levels, peer}] for LAN matches (first = host; humans alternate teams)
##   bot_skill: 0..1 (default 0.6)
func setup(cfg: Dictionary) -> void:
	DB.ensure_loaded()
	config = cfg
	playlist = str(cfg.get("playlist", "standard"))
	playlist = str({"even_ground": "warlord", "pure_brawl": "skirmisher"}.get(playlist, playlist))  # pre-U2 ids
	var seed := int(cfg["seed"]) if cfg.has("seed") else int(Time.get_ticks_usec() * 7919 + randi())
	rng.seed = seed
	if record:
		var rc := cfg.duplicate(true)
		rc["seed"] = seed
		recording = {"version": 1, "game_version": str(ProjectSettings.get_setting("application/config/version", "dev")),
			"date": Time.get_datetime_string_from_system(), "cfg": rc, "intents": [], "events": []}
	if cfg.has("training"):
		training = Training.new()
		training.setup(self, cfg)
		return
	sim = Sim.new()
	var sim_opts := {"seed": rng.randi()}
	# Mutators: The Lab's weekly one, plus any chosen for a private match (U8). Later ones win on conflicts.
	var priv: Dictionary = cfg.get("private", {})
	var mut_ids: Array = []
	if bool(DB.modes.get("playlists", {}).get(playlist, {}).get("lab", false)):
		mutator = str(cfg.get("mutator", Mutators.current()))
		mut_ids.append(mutator)
		if record:
			recording["cfg"]["mutator"] = mutator
	for m in priv.get("mutators", []):
		if not mut_ids.has(str(m)) and not Mutators.get_def(str(m)).is_empty():
			mut_ids.append(str(m))
	var rule_over := {}
	var mode_over := {}
	for m in mut_ids:
		var md := Mutators.get_def(str(m))
		rule_over.merge(md.get("rules", {}), true)
		mode_over.merge(md.get("mode", {}), true)
		var lm: Dictionary = md.get("loadout", {})
		if lm.has("kit"):
			loadout_mods["kit"] = str(lm["kit"])
		if lm.has("food_mult"):
			loadout_mods["food_mult"] = float(loadout_mods.get("food_mult", 1.0)) * float(lm["food_mult"])
	for k in ["score_limit", "time_limit_s", "rounds_to_win", "round_time_s"]:
		if priv.has(k) and int(priv[k]) > 0:
			mode_over[k] = int(priv[k])
	if not rule_over.is_empty():
		sim_opts["rule_overrides"] = rule_over
	if not mode_over.is_empty():
		sim_opts["mode_overrides"] = mode_over
	if cfg.has("pre_ticks"):
		sim_opts["pre_ticks"] = int(cfg["pre_ticks"])
	sim.setup(str(cfg.get("mode", "clan_clash")), str(cfg.get("map", "frostgate_ruins")), sim_opts)
	var mode: Dictionary = sim.mode
	var ffa := int(mode.get("teams", 2)) <= 0
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
	if players.is_empty() and not (cfg.get("player", {}) as Dictionary).is_empty() and not bool(priv.get("spectate", false)):
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
		if int(p.get("peer", 1)) == 1:
			player_id = fid  # the local (host) player; -1 when the host only spectates
	var names := BOT_NAMES.duplicate()
	_shuffle(names)
	var skill := float(cfg.get("bot_skill", 0.6))
	if not bool(priv.get("bots", true)):
		slots.clear()  # private match with bots off
	for i in range(slots.size()):
		var team: int = slots[i]
		var lv := _bot_levels(base_levels)
		var cls_id := _pick_class()
		var fid := _add(str(names[i % names.size()]), team, true, DB.classes["defaults"][cls_id], lv)
		var s := clampf(skill + rng.randf_range(-0.2, 0.2), 0.15, 0.95)
		bots[fid] = BotBrain.new(fid, s, rng.randi())


## The bracket this match uses ("" = Standard: everyone's own unlocks).
func bracket() -> String:
	return str(DB.modes.get("playlists", {}).get(playlist, {}).get("bracket", ""))


func _loadout_for(class_def: Dictionary, unl: Dictionary) -> Dictionary:
	var supply := str(sim.mode.get("supply", "full"))
	if bracket() != "":
		return Brackets.build_loadout(bracket(), class_def, supply, loadout_mods)
	return Loadout.build(class_def, unl, {"supply": supply, "food_mult": float(loadout_mods.get("food_mult", 1.0))})


func _add(p_name: String, team: int, is_bot: bool, class_def: Dictionary, levels: Dictionary) -> int:
	var unl: Dictionary = Brackets.unlocked(bracket()) if bracket() != "" else Progression.unlocked_set(levels)
	return sim.add_fighter(p_name, team, is_bot, _loadout_for(class_def, unl), unl, levels)


## Combat-level matchmaking for bots (U3): style levels near the players', redrawn until the bot's combat level is
## inside the matchmaking window around the players' average.
func _bot_levels(base: Dictionary) -> Dictionary:
	var base_cl := Progression.combat_level(int(base.get("melee", 1)), int(base.get("ranged", 1)), int(base.get("magic", 1)))
	var w := Matchmaker.window(0.0)
	var out := {}
	for attempt in range(8):
		for s in ["melee", "ranged", "magic"]:
			out[s] = clampi(int(base.get(s, 1)) + rng.randi_range(-3, 3), 1, 40)
		if absi(Progression.combat_level(int(out["melee"]), int(out["ranged"]), int(out["magic"])) - base_cl) <= w:
			break
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
	if record:
		(recording["intents"] as Array).append([sim.tick, fid, intent.duplicate(true)])
	sim.queue_intent(fid, intent)


## Rebuilds the player's loadout for their next life (create-a-class / class change).
func change_class(fid: int, class_def: Dictionary, levels: Dictionary) -> void:
	var f := sim.get_fighter(fid)
	if f == null:
		return
	var ci := {"type": "class", "loadout": _loadout_for(class_def, f.unlocked)}
	if record:
		(recording["intents"] as Array).append([sim.tick, fid, ci.duplicate(true)])
	sim.queue_intent(fid, ci)


func tick() -> void:
	for bid in bots:
		(bots[bid] as BotBrain).think(sim)
	for f in sim.fighters.values():
		var fi: Fighter = f
		if fi.npc_kind == "guardian" and fi.is_alive():
			BotBrain.think_guardian(sim, fi)
	sim.step()
	for e in sim.events:
		if str(e.get("type", "")) == "afk_takeover":
			_bot_takeover(int(e["id"]))
	if training != null:
		training.tick()


## AFK or disconnected human: a bot plays their fighter for the rest of the match (tagged as a bot) and the
## match counts as left for them.
func _bot_takeover(fid: int) -> void:
	var f := sim.get_fighter(fid)
	if f == null or bots.has(fid):
		return
	f.left_match = true
	f.is_bot = true
	humans.erase(fid)
	bots[fid] = BotBrain.new(fid, float(config.get("bot_skill", 0.6)), rng.randi())


## LAN peer dropped mid-match.
func peer_left(peer: int) -> void:
	if record and peer_to_fid.has(peer):
		(recording["events"] as Array).append([sim.tick, "peer_left", peer])
	if peer_to_fid.has(peer):
		_bot_takeover(int(peer_to_fid[peer]))


## U4: what each client needs to update its own rating: the enemy team's ratings (from the lobby) and the result.
func _ranked_info(me: Fighter) -> Dictionary:
	var by_peer := {}
	for p in config.get("players", []):
		by_peer[int(p.get("peer", 1))] = p.get("ranked", {})
	var opps: Array = []
	for fid in humans:
		var f := sim.get_fighter(int(fid))
		if f != null and f.team != me.team:
			var r: Dictionary = by_peer.get(int(humans[fid]), {})
			if not r.is_empty():
				opps.append(r.duplicate())
	# Fighters taken over by bots after leaving are no longer in humans; their lobby rating still counts.
	for f in sim.fighters.values():
		var fi: Fighter = f
		if fi.left_match and fi.team != me.team:
			for peer in peer_to_fid:
				if int(peer_to_fid[peer]) == fi.id and not by_peer.get(int(peer), {}).is_empty():
					var r2: Dictionary = by_peer[int(peer)]
					if not opps.any(func(o): return str(o.get("id", "")) == str(r2.get("id", ""))):
						opps.append(r2.duplicate())
	return {"opponents": opps, "mode": sim.mode_id, "draw": int(sim.result.get("winner", -1)) < 0}


## U8: the finished replay (setup, inputs, final tick and state hash, a short description).
func replay_data() -> Dictionary:
	var r := recording.duplicate(true)
	r["ticks"] = sim.tick
	r["final_hash"] = sim.state_hash()
	var names: Array = []
	for f in sim.fighters.values():
		var fi: Fighter = f
		if fi.npc_kind == "":
			names.append(fi.name + (" [BOT]" if fi.is_bot else ""))
	r["info"] = {"mode": sim.mode_id, "mode_name": str(sim.mode.get("name", "")), "map": sim.map.name, "playlist": playlist,
		"winner": int(sim.result.get("winner", -1)), "scores": sim.scores.duplicate(), "fighters": names, "mutator": mutator}
	return r


## End-of-match results for the local player: scoreboard, XP breakdown and the raw
## challenge events. XP is computed here, on the server side, with the shared rules.
## spectator = true: results for someone who only watched (no XP, no personal stats).
func summary(forfeit: bool = false, fid: int = -1, spectator: bool = false) -> Dictionary:
	if fid == -1 and not spectator:
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
	if me != null and me.left_match:
		forfeit = true
	var won := me != null and not forfeit and winner == me.team
	var out := {
		"mode": sim.mode_id, "mode_name": str(sim.mode.get("name", "")), "map": sim.map.name, "winner": winner,
		"won": won, "forfeit": forfeit, "scores": sim.scores.duplicate(), "rows": rows, "ffa": sim.rules.is_ffa(),
		"my_id": fid, "my_team": me.team if me != null else 0, "playlist": playlist, "bracket": bracket(),
	}
	if me != null:
		var primary_style := str(DB.item(str(me.loadout.get("primary", ""))).get("style", "melee"))
		out["xp"] = Progression.match_xp(me, won, me.rounds_won, primary_style)
		out["events"] = me.challenge_events.duplicate()
		out["stats"] = {"kills": me.kills, "deaths": me.deaths, "assists": me.assists, "damage": me.damage_dealt, "best_streak": me.best_streak}
		out["fight_report"] = sim.clog.report(me.id, sim.live_ticks)
	out["telemetry"] = Telemetry.record(sim, playlist, {"forfeit": forfeit})
	if spectator:
		out["spectator"] = true
	if bool(config.get("ranked", false)) and me != null:
		out["ranked"] = _ranked_info(me)
	if config.has("tournament_match"):
		out["tournament_match"] = int(config["tournament_match"])
	if mutator != "":
		out["lab"] = {"mutator": mutator, "name": Mutators.display_name(mutator), "week": Brackets.week_index(int(Time.get_unix_time_from_system()))}
		out["telemetry"]["lab"] = out["lab"].duplicate()
	if training != null:
		out["training"] = {"id": training.id, "kind": training.kind, "status": training.status, "label": str(training.def.get("label", "")),
			"name": str(training.def.get("name", "")), "passed": training.status == "passed" or (training.kind == "exam" and won)}
		out["training"]["note"] = training.note
		out["telemetry"]["training"] = out["training"]
		# Practice doesn't give match XP or challenge progress; drills reward XP once (client applies it).
		out["xp"] = {"melee": 0, "ranged": 0, "magic": 0, "lines": []}
		out["events"] = []
		out["stats"] = {}
	return out
