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
		if a.begins_with("--autoplay="):
			var mode := a.substr(11)
			var maps: Array = DB.modes["modes"][mode]["maps"]
			var map_id: String = maps[0]
			for b in OS.get_cmdline_user_args():
				if str(b).begins_with("--map=") and DB.maps.has(str(b).substr(6)):
					map_id = str(b).substr(6)
			_start_match({"mode": mode, "map": map_id, "playlist": "standard", "pre_ticks": 3, "bot_skill": 0.55})


func player_info() -> Dictionary:
	return {"name": str(profile.data["name"]), "class_def": profile.selected_class_def(), "levels": profile.levels()}


func _start_match(cfg: Dictionary, link: Node = null) -> void:
	cfg = cfg.duplicate()
	if link == null:
		cfg["player"] = player_info()
	if match_view != null:
		match_view.queue_free()
	menus.visible = false
	match_view = MatchView.new()
	add_child(match_view)
	match_view.finished.connect(_on_finished)
	match_view.start(cfg, profile, sfx, link)


func _on_finished(summary: Dictionary) -> void:
	var applied := _apply(summary)
	if match_view != null:
		match_view.queue_free()
		match_view = null
	menus.visible = true
	menus.show_results(summary, applied)


func _apply(summary: Dictionary) -> Dictionary:
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
	var ps: Dictionary = profile.data["stats"]
	ps["matches"] = int(ps["matches"]) + 1
	ps["wins"] = int(ps["wins"]) + (1 if summary.get("won", false) else 0)
	for k in ["kills", "deaths", "assists", "damage"]:
		ps[k] = int(ps[k]) + int(st.get(k, 0))
	var ups := profile.add_xp(total)
	profile.save()
	return {"total": total, "challenges": ch, "level_ups": ups}
