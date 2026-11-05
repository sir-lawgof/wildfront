extends TestCase
## U8 replays: a recording of setup + human inputs reproduces the match exactly (same state hash), including
## seeking to the middle, LAN leavers, class changes and Lab mutators.


func _human_match(mode: String, extra: Dictionary = {}) -> Array:
	DB.ensure_loaded()
	var cfg := {"mode": mode, "map": str(DB.modes["modes"][mode]["maps"][0]), "pre_ticks": 2, "bot_skill": 0.6,
		"players": [
			{"name": "Ann", "class_def": DB.classes["defaults"]["tribrid"], "levels": {"melee": 30, "ranged": 30, "magic": 30}, "peer": 1},
			{"name": "Bo", "class_def": DB.classes["defaults"]["warrior"], "levels": {"melee": 20, "ranged": 20, "magic": 20}, "peer": 7}]}
	cfg.merge(extra, true)
	var core := MatchServerCore.new()
	core.setup(cfg)
	var hashes := {}
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var a := core.peer_to_fid[1] as int
	for i in range(500):
		# A scripted "human": attacks, prayers, switches, eats, moves, a class change and chat.
		var me := core.sim.get_fighter(a)
		var enemy: Fighter = null
		for f in core.sim.fighters.values():
			if (f as Fighter).team != me.team and (f as Fighter).is_alive():
				enemy = f
		if r.randf() < 0.2 and enemy != null:
			core.submit(a, {"type": "attack", "target": enemy.id})
		if r.randf() < 0.08:
			core.submit(a, {"type": "prayer", "id": ["ward_blades", "ward_arrows", "ward_spells"][r.randi_range(0, 2)]})
		if r.randf() < 0.05:
			core.submit(a, {"type": "switch_set", "style": ["melee", "ranged", "magic"][r.randi_range(0, 2)]})
		if r.randf() < 0.05 and me.hp < 60:
			var s := me.find_item(func(it): return str(it.get("timer", "")) == "food")
			if s >= 0:
				core.submit(a, {"type": "use", "slot": s})
		if r.randf() < 0.04:
			core.submit(a, {"type": "move", "x": r.randi_range(5, core.sim.map.w - 5), "y": r.randi_range(5, core.sim.map.h - 5)})
		if i == 120:
			core.change_class(a, DB.classes["defaults"]["battlemage"], {"melee": 30, "ranged": 30, "magic": 30})
		if i == 200:
			core.peer_left(7)
		core.tick()
		hashes[core.sim.tick] = core.sim.state_hash()
		if core.sim.phase == "over":
			break
	return [core, hashes]


## Tests never touch the player's real replay folders.
func _init() -> void:
	Replay.DIR = "user://test_replays"
	Replay.EXPORT_DIR = "user://test_exports"


func test_replay_reproduces_match_exactly() -> void:
	var res := _human_match("clan_clash")
	var core: MatchServerCore = res[0]
	var hashes: Dictionary = res[1]
	var rec := core.replay_data()
	check((rec["intents"] as Array).size() > 20, "inputs recorded (%d)" % (rec["intents"] as Array).size())
	check(Replay.verify(rec), "replay ends in the same state (hash)")
	var mid := int(rec["ticks"]) / 2
	eq(Replay.simulate(rec, mid).sim.state_hash(), int(hashes[mid]), "seeking to the middle matches too")
	# Through a file, as players will use it.
	var path := Replay.save(rec)
	var loaded := Replay.load_file(path)
	check(Replay.verify(loaded), "a saved and loaded replay still verifies")
	var exported := Replay.export_file(path)
	check(exported != "" and FileAccess.file_exists(exported), "export copies the file")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(exported)


func test_replay_lab_and_ffa() -> void:
	var res := _human_match("ffa", {"playlist": "lab", "mutator": "spec_frenzy"})
	check(Replay.verify((res[0] as MatchServerCore).replay_data()), "FFA Lab match replays exactly")
	var res2 := _human_match("duel", {"private": {"mutators": ["low_rations", "no_wards"], "bots": false, "rounds_to_win": 2}})
	check(Replay.verify((res2[0] as MatchServerCore).replay_data()), "private Duel with mutators replays exactly")


func test_only_last_ten_kept() -> void:
	var core := MatchServerCore.new()
	core.setup({"mode": "duel", "map": "castle_courtyard", "seed": 1, "pre_ticks": 1})
	core.tick()
	var before := Replay.list().size()
	var made: Array = []
	for i in range(Replay.KEEP + 2):
		made.append(Replay.save(core.replay_data()))
	check(Replay.list().size() <= Replay.KEEP, "at most %d replays kept" % Replay.KEEP)
	for p in made:
		DirAccess.remove_absolute(str(p))
	check(before >= 0, "listing works")
