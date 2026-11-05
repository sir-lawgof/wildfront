extends Node
## App controller: menus <-> match. After a match it applies the server's XP summary
## and challenge results to the local profile.

var profile: Profile
var sfx: Sfx
var menus: Menus
var ui_layer: CanvasLayer
var match_view: MatchView
var net: NetSession


func _ready() -> void:
	DB.ensure_loaded()
	profile = Profile.load_or_create()
	UITheme.colorblind = bool(profile.setting("colorblind"))
	sfx = Sfx.new()
	add_child(sfx)
	sfx.volume = float(profile.setting("volume"))
	net = NetSession.new()
	net.name = "Net"
	add_child(net)
	net.match_started.connect(func(cfg, link): _start_match(cfg, link))
	if OS.get_cmdline_user_args().has("--trace"):
		net.status.connect(func(t): print("[net] ", t))
		net.lobby_changed.connect(func(l): print("[net] lobby ", l))
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	menus = Menus.new()
	ui_layer.add_child(menus)
	menus.setup(profile, sfx)
	menus.net = net
	menus.start_match.connect(_start_match)
	menus.watch_replay.connect(_watch_replay)
	menus.quit_game.connect(func(): get_tree().quit())
	if not DB.errors.is_empty():
		var l := UITheme.label("Data errors:\n" + "\n".join(DB.errors), 14, UITheme.RED)
		ui_layer.add_child(l)
	menus.show_main()
	# Smoke-test hook: `godot -- --autoplay=clan_clash` starts a match straight away.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			# Dev hook: `-- --screenshot=C:/tmp/shot.png --shot-delay=8` saves the screen and quits.
			var path := a.substr(13)
			var delay := 6.0
			for b in OS.get_cmdline_user_args():
				if b.begins_with("--shot-delay="):
					delay = float(b.substr(13))
			get_tree().create_timer(delay).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png(path)
				get_tree().quit())
		if a.begins_with("--menu="):
			match a.substr(7):
				"play": menus.show_play()
				"barracks": menus.show_barracks()
				"options": menus.show_options()
				"training": menus.show_training()
				"tournament": menus.show_tournament()
				"ranked": menus.show_ranked()
				"replays": menus.show_replays()
				"patch": menus.show_patch_notes()
				"editor": menus.show_class_editor(0)
		if a == "--lan-host":
			# Dev hook: host and auto-start Clan Clash as soon as a second player joins.
			net.host(player_info())
			net.lobby_changed.connect(func(list):
				if list.size() >= 2 and net.server == null:
					net.start_match({"mode": "duel", "map": "castle_courtyard", "playlist": "standard", "pre_ticks": 3, "bot_skill": 0.5}))
		if a.begins_with("--lan-join="):
			net.join(a.substr(11), player_info())
		if a.begins_with("--timescale="):
			Engine.time_scale = float(a.substr(12))
		if a.begins_with("--name="):
			profile.data["name"] = a.substr(7)
		if a.begins_with("--replay="):
			# Dev hook: `-- --replay=C:/path/file.wfreplay` plays a replay.
			_watch_replay(a.substr(9))
		if a.begins_with("--training="):
			# Dev hook: `-- --training=wards` starts a Proving Grounds drill, exam or the dummy room.
			var tf := Training.find(a.substr(11))
			if not tf.is_empty():
				_start_match({"training": a.substr(11), "mode": "duel" if str(tf["kind"]) == "exam" else "training", "map": str(DB.training.get("map", "castle_courtyard")), "pre_ticks": 3})
		if a.begins_with("--autoplay="):
			var mode := a.substr(11)
			var maps: Array = DB.modes["modes"][mode]["maps"]
			var map_id: String = maps[0]
			for b in OS.get_cmdline_user_args():
				if str(b).begins_with("--map=") and DB.maps.has(str(b).substr(6)):
					map_id = str(b).substr(6)
			_start_match({"mode": mode, "map": map_id, "playlist": "standard", "pre_ticks": 3, "bot_skill": 0.55})


## U1: first pass of a drill or exam gives its XP (split across styles) and any reward (cape trim).
func _apply_training(tr: Dictionary) -> Dictionary:
	var total := {"melee": 0, "ranged": 0, "magic": 0}
	var rewards: Array = []
	var tid := str(tr.get("id", ""))
	if not profile.data.has("training"):
		profile.data["training"] = {}
	if bool(tr.get("passed", false)) and not bool(profile.data["training"].get(tid, false)):
		profile.data["training"][tid] = true
		var d: Dictionary = Training.find(tid).get("def", {})
		var each := int(d.get("xp", 0)) / 3
		for s in total:
			total[s] = each
		var reward := str(d.get("reward", ""))
		if reward.begins_with("cape_trim:"):
			if not profile.data.has("cape_trims"):
				profile.data["cape_trims"] = []
			if not (profile.data["cape_trims"] as Array).has(reward.substr(10)):
				profile.data["cape_trims"].append(reward.substr(10))
				rewards.append("%s cape trim" % reward.substr(10).capitalize())
	var ups := profile.add_xp(total)
	profile.save()
	return {"total": total, "challenges": {}, "level_ups": ups, "training_rewards": rewards}


func player_info() -> Dictionary:
	var st: Dictionary = profile.data["ranked"]
	return {"name": str(profile.data["name"]), "class_def": profile.selected_class_def(), "levels": profile.levels(),
		"spectator": OS.get_cmdline_user_args().has("--spectator"),
		"ranked": {"id": str(profile.data["player_id"]), "rating": float(st["rating"]), "rd": float(st["rd"])}}


func _start_match(cfg: Dictionary, link: Node = null) -> void:
	cfg = cfg.duplicate()
	if link == null:
		cfg["player"] = player_info()
	if match_view != null:
		match_view.queue_free()
	menus.visible = false
	menus.close_popups()
	match_view = MatchView.new()
	add_child(match_view)
	match_view.finished.connect(_on_finished)
	match_view.start(cfg, profile, sfx, link)


## U8: plays a saved replay with the normal match view.
func _watch_replay(path: String) -> void:
	var rec := Replay.load_file(path)
	if rec.is_empty():
		return
	var link := ReplayLink.new()
	link.setup(rec)
	add_child(link)
	var cfg: Dictionary = (rec["cfg"] as Dictionary).duplicate(true)
	cfg["replay"] = true
	_start_match(cfg, link)


func _on_finished(summary: Dictionary) -> void:
	menus.apply_tournament_result(summary)  # U8: LAN tournament matches report themselves (host)
	if summary.has("replay_view") or summary.has("spectator"):
		if match_view != null:
			match_view.queue_free()
			match_view = null
		for c in get_children():
			if c is ReplayLink:
				c.queue_free()
		menus.visible = true
		if summary.has("replay_view"):
			menus.show_replays()
		else:
			if bool(profile.setting("telemetry")) and summary.has("telemetry"):
				Telemetry.save(summary["telemetry"])
			menus.show_results(summary, {})
		return
	var applied := _apply(summary)
	if bool(profile.setting("telemetry")) and summary.has("telemetry"):
		summary["telemetry_path"] = Telemetry.save(summary["telemetry"])
	if match_view != null:
		match_view.queue_free()
		match_view = null
	menus.visible = true
	menus.show_results(summary, applied)


func _apply(summary: Dictionary) -> Dictionary:
	if summary.has("training"):
		return _apply_training(summary["training"])
	var x: Dictionary = summary.get("xp", {})
	var total := {"melee": int(x.get("melee", 0)), "ranged": int(x.get("ranged", 0)), "magic": int(x.get("magic", 0))}
	var st: Dictionary = summary.get("stats", {})
	var ch := Challenges.process(summary.get("events", []), profile.data["challenges"], profile.data["completed"],
		{"won": summary.get("won", false), "deaths": int(st.get("deaths", 0)), "kills": int(st.get("kills", 0))})
	for s in DB.STYLES:
		total[s] += int(ch["xp"][s])
	for r in ch["rewards"]:
		var parts := str(r).split(":")
		match parts[0]:
			"title":
				if not (profile.data["titles"] as Array).has(parts[1]):
					profile.data["titles"].append(parts[1])
			"banner":
				if not (profile.data["banners"] as Array).has(parts[1]):
					profile.data["banners"].append(parts[1])
			"mod":
				profile.data["unlocked_mods"][parts[1]] = maxi(int(profile.data["unlocked_mods"].get(parts[1], 0)), int(parts[2]))
			"kit":
				if not profile.data["kits"].has(parts[1]):
					profile.data["kits"][parts[1]] = []
				if not (profile.data["kits"][parts[1]] as Array).has(parts[2]):
					profile.data["kits"][parts[1]].append(parts[2])
	var ranked_out := {}
	if summary.has("ranked"):
		ranked_out = _apply_ranked(summary)
	var ps: Dictionary = profile.data["stats"]
	ps["matches"] = int(ps["matches"]) + 1
	ps["wins"] = int(ps["wins"]) + (1 if summary.get("won", false) else 0)
	for k in ["kills", "deaths", "assists", "damage"]:
		ps[k] = int(ps[k]) + int(st.get(k, 0))
	var ups := profile.add_xp(total)
	profile.save()
	return {"total": total, "challenges": ch, "level_ups": ups, "ranked": ranked_out}


## U4: update this player's rating and points from a ranked match; leaving counts as a loss and starts a cooldown.
func _apply_ranked(summary: Dictionary) -> Dictionary:
	var r: Dictionary = summary["ranked"]
	var st: Dictionary = profile.data["ranked"]
	var now := int(Time.get_unix_time_from_system())
	var before := Ranked.visible_rank(st)
	var res := Ranked.apply_match(st, r.get("opponents", []), bool(summary.get("won", false)), now, bool(r.get("draw", false)))
	var granted: Array = []
	for rw in res["rewards"]:
		var l := profile.grant_cosmetic(str(rw))
		if l != "":
			granted.append(l)
	if bool(summary.get("forfeit", false)):
		(st["leave_times"] as Array).append(now)
	return {"before": before, "after": Ranked.visible_rank(st), "delta": float(res["delta"]), "points": int(res["points"]),
		"mult": float(res["mult"]), "rewards": granted, "total_points": int(st["points"]), "placed": Ranked.placed(st)}
