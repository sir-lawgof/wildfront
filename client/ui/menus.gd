class_name Menus
extends Control
## Front-end screens (GDD 10 Menus): Main menu -> Play (playlists), Barracks
## (create-a-class, unlocks, challenges, prestige, stats), Options, and the
## end-of-match scoreboard + XP summary.

signal start_match(cfg: Dictionary)
signal watch_replay(path: String)

var _offer_dialog: Window = null
signal quit_game

var profile: Profile
var sfx: Sfx
var net: NetSession
var _body: Control
var _play_cfg := {"mode": "clan_clash", "map": "frostgate_ruins", "playlist": "standard"}


func setup(p: Profile, s: Sfx) -> void:
	profile = p
	sfx = s
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("1e1912")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var tex := TextureRect.new()
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.texture = _backdrop()
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.modulate = Color(1, 1, 1, 0.35)
	add_child(tex)
	_body = Control.new()
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_body)


func _backdrop() -> Texture2D:
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	for y in range(36):
		for x in range(64):
			var v := 0.12 + 0.08 * sin(x * 0.3) * cos(y * 0.4) + 0.04 * ((x + y) % 2)
			img.set_pixel(x, y, Color(v * 1.4, v, v * 0.6))
	var t := ImageTexture.create_from_image(img)
	return t


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()


func _frame(title: String, w: int = 1100, h: int = 760) -> VBoxContainer:
	_clear()
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -w / 2.0
	panel.offset_right = w / 2.0
	panel.offset_top = -h / 2.0
	panel.offset_bottom = h / 2.0
	_body.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var t := UITheme.label(title, 34, UITheme.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	return vb


func _click() -> void:
	if sfx:
		sfx.play("click", 0.5)


# ================================================================ main menu

func show_main() -> void:
	_clear()
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.08
	vb.offset_left = -330
	vb.offset_right = 330
	vb.add_theme_constant_override("separation", 12)
	_body.add_child(vb)
	var title := UITheme.label("WILDFRONT", 84, UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	vb.add_child(title)
	var sub := UITheme.label("Tick-based team PvP  ·  inspired by Old School RuneScape and Call of Duty 4", 18, UITheme.CREAM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	vb.add_child(_profile_card())
	for b in [["Play vs bots", show_play], ["Proving Grounds", show_training], ["LAN multiplayer", show_lan], ["Barracks", show_barracks], ["Replays", show_replays], ["Options", show_options], ["Patch notes", func(): show_patch_notes()], ["Quit", func(): quit_game.emit()]]:
		var btn := UITheme.button(str(b[0]), func(): _click(); (b[1] as Callable).call())
		btn.custom_minimum_size = Vector2(0, 52)
		btn.add_theme_font_size_override("font_size", 24)
		vb.add_child(btn)
	var news: Array = profile.ranked_housekeeping()
	if not news.is_empty():
		var nl := UITheme.label("\n".join(news), 15, UITheme.YELLOW)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(nl)
	if not bool(profile.data.get("proving_offered", false)):
		profile.data["proving_offered"] = true
		profile.data["seen_patch"] = DB.latest_patch()  # a brand-new player doesn't need patch notes
		profile.save()
		_offer_training()
	elif str(profile.data.get("seen_patch", "")) != DB.latest_patch():
		show_patch_notes()  # once after an update
		return
	var foot := UITheme.label("An original fan-made prototype. Not affiliated with or endorsed by Jagex or Activision.", 12, Color(0.6, 0.55, 0.45))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(foot)


# ================================================================ Proving Grounds (U1)

## First launch only: offer the Proving Grounds once.
func _offer_training() -> void:
	var d := ConfirmationDialog.new()
	d.theme = UITheme.get_theme()
	d.title = "Welcome to Wildfront"
	d.dialog_text = "New to tick-based PvP?\n\n%s runs short drills on wards, freezes, special attacks,\ngear switching, combo eating and reading your enemy, then a fair Graduation fight.\n\nGo to the Proving Grounds now? (It's always on the main menu.)" % str(DB.training["instructor"]["name"])
	d.ok_button_text = "Train now"
	d.cancel_button_text = "Maybe later"
	d.confirmed.connect(func(): show_training())
	add_child(d)
	_offer_dialog = d
	d.popup_centered()


## Closes the first-launch offer if a match starts while it's open.
func close_popups() -> void:
	if is_instance_valid(_offer_dialog):
		_offer_dialog.queue_free()


func _training_cfg(tid: String) -> Dictionary:
	var f := Training.find(tid)
	return {"training": tid, "mode": "duel" if str(f.get("kind", "")) == "exam" else "training", "map": str(DB.training.get("map", "castle_courtyard")), "pre_ticks": 5}


func show_training() -> void:
	var vb := _frame("Proving Grounds", 1100, 820)
	var ins: Dictionary = DB.training["instructor"]
	var intro := UITheme.label("%s: \"%s\"  Each drill teaches one mechanic. Pass them, then take the Graduation fight." % [ins["name"], ins["desc"]], 15)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(intro)
	var done: Dictionary = profile.data.get("training", {})
	vb.add_child(UITheme.label("Drills", 22, UITheme.GOLD))
	for d in DB.training["drills"]:
		vb.add_child(_training_row(d, bool(done.get(str(d["id"]), false)), "drill"))
	vb.add_child(UITheme.label("Exams", 22, UITheme.GOLD))
	for e in DB.training["exams"]:
		vb.add_child(_training_row(e, bool(done.get(str(e["id"]), false)), str(e["label"])))
	vb.add_child(_training_row(DB.training["dummy"], false, "practice"))
	vb.add_child(UITheme.button("Back", func(): _click(); show_main()))


func _training_row(d: Dictionary, passed: bool, tag: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var b := UITheme.button(str(d["name"]), func(): _click(); start_match.emit(_training_cfg(str(d["id"]))), 240)
	hb.add_child(b)
	var badge_col: Color = {"learning": Color("7fd07f"), "aspirational": Color("ff8060"), "drill": UITheme.GOLD, "practice": UITheme.CREAM}.get(tag, UITheme.CREAM)
	var badge := UITheme.label(tag.capitalize(), 13, badge_col)
	badge.custom_minimum_size.x = 96
	hb.add_child(badge)
	var desc := UITheme.label(("[passed]  " if passed else "") + str(d["desc"]), 13, Color("ffd23f") if passed else UITheme.CREAM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size.x = 700
	hb.add_child(desc)
	return hb


func show_training_results(summary: Dictionary, applied: Dictionary) -> void:
	var tr: Dictionary = summary.get("training", {})
	var passed := bool(tr.get("passed", false))
	var vb := _frame(str(tr.get("name", "Proving Grounds")), 900, 520)
	var head := UITheme.label("PASSED" if passed else "NOT YET", 40, UITheme.YELLOW if passed else UITheme.RED)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	if str(tr.get("label", "")) != "":
		var lab := UITheme.label("(%s challenge)" % str(tr["label"]), 16, UITheme.CREAM)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(lab)
	var note := UITheme.label(str(tr.get("note", "")), 18)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(note)
	var tot: Dictionary = applied.get("total", {})
	if int(tot.get("melee", 0)) + int(tot.get("ranged", 0)) + int(tot.get("magic", 0)) > 0:
		vb.add_child(UITheme.label("First pass reward: +%d melee, +%d ranged, +%d magic XP" % [int(tot["melee"]), int(tot["ranged"]), int(tot["magic"])], 16, UITheme.GOLD))
	for r in applied.get("training_rewards", []):
		vb.add_child(UITheme.label("Unlocked: %s" % str(r), 16, UITheme.YELLOW))
	var rep := RichTextLabel.new()
	rep.bbcode_enabled = true
	rep.fit_content = true
	rep.text = _fight_report_text(summary.get("fight_report", {})) if str(tr.get("kind", "")) == "exam" else ""
	vb.add_child(rep)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(UITheme.button("Try again", func(): start_match.emit(_training_cfg(str(tr.get("id", ""))))))
	hb.add_child(UITheme.button("Proving Grounds", func(): show_training()))
	hb.add_child(UITheme.button("Main menu", func(): show_main()))


func _profile_card() -> Control:
	var pc := PanelContainer.new()
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	var cl := profile.combat_level()
	var head := UITheme.label("%s  -  %s  (Combat level %d)" % [profile.data["name"], profile.title(), cl], 20, UITheme.YELLOW)
	vb.add_child(head)
	for s in DB.STYLES:
		var hb := HBoxContainer.new()
		vb.add_child(hb)
		var lv := profile.level(s)
		var pr := profile.prestige(s)
		var l := UITheme.label("%s %d%s" % [s.capitalize(), lv, ("  ★%d" % pr) if pr > 0 else ""], 16, UITheme.style_color(s))
		l.custom_minimum_size.x = 150
		hb.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(380, 18)
		bar.max_value = 1.0
		bar.step = 0.001
		bar.value = Progression.level_progress(profile.xp(s))
		bar.show_percentage = false
		bar.add_theme_stylebox_override("fill", UITheme.box(UITheme.style_color(s).darkened(0.2), Color.BLACK, 1))
		hb.add_child(bar)
		var need := "MAX" if lv >= 40 else "%d xp to %d" % [Progression.total_xp_for(lv + 1) - profile.xp(s), lv + 1]
		hb.add_child(UITheme.label("  " + need, 13))
	return pc


# ================================================================ play

func show_play() -> void:
	var vb := _frame("Play", 1100, 780)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	var modes_box := VBoxContainer.new()
	modes_box.custom_minimum_size.x = 520
	hb.add_child(modes_box)
	modes_box.add_child(UITheme.label("Mode", 20, UITheme.GOLD))
	var mode_buttons := {}
	var desc := UITheme.label("", 15)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size = Vector2(500, 60)
	var map_opt := OptionButton.new()
	for mk in DB.modes["modes"]:
		var m: Dictionary = DB.modes["modes"][mk]
		if bool(m.get("hidden", false)):
			continue
		var team_txt := "%dv%d" % [int(m["team_size"]), int(m["team_size"])] if int(m.get("teams", 2)) > 0 else "%d players" % int(m["team_size"])
		var b := UITheme.button("%s  (%s)" % [m["name"], team_txt], func():
			_click()
			_play_cfg["mode"] = mk
			_fill_maps(map_opt, mk)
			desc.text = str(m["desc"])
			for k in mode_buttons:
				(mode_buttons[k] as Button).add_theme_color_override("font_color", UITheme.YELLOW if k == mk else UITheme.GOLD))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		modes_box.add_child(b)
		mode_buttons[mk] = b
	modes_box.add_child(desc)
	modes_box.add_child(_private_box())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size.x = 500
	hb.add_child(right)
	right.add_child(UITheme.label("Map", 20, UITheme.GOLD))
	map_opt.item_selected.connect(func(i): _play_cfg["map"] = str(map_opt.get_item_metadata(i)))
	right.add_child(map_opt)
	right.add_child(UITheme.label("Playlist", 20, UITheme.GOLD))
	var feat := Brackets.featured()
	if feat != "":
		var days := int(ceil(Brackets.seconds_to_rotation() / 86400.0))
		right.add_child(UITheme.label("Featured bracket this week: %s (ranked uses it; changes in %d day%s)" % [Brackets.display_name(feat), days, "" if days == 1 else "s"], 14, UITheme.YELLOW))
	var mut := Mutators.current()
	if mut != "":
		var md := Mutators.get_def(mut)
		right.add_child(UITheme.label("This week in The Lab: %s - %s" % [str(md["name"]), str(md["desc"])], 14, Color("8fc7ff")))
		var wk := Brackets.week_index(int(Time.get_unix_time_from_system()))
		var last := Mutators.tally(profile.data.get("lab_votes", {}), wk - 1)
		if int(last["keep"]) + int(last["change"]) + int(last["drop"]) > 0:
			right.add_child(UITheme.label("Last week's Lab (%s), your votes: keep %d, change %d, drop %d" % [Mutators.display_name(str(last["mutator"])), int(last["keep"]), int(last["change"]), int(last["drop"])], 13, UITheme.CREAM))
	var pl := OptionButton.new()
	var keys: Array = DB.modes["playlists"].keys()
	for i in range(keys.size()):
		var p: Dictionary = DB.modes["playlists"][keys[i]]
		pl.add_item("%s%s - %s" % [p["name"], "  [Featured]" if str(p.get("bracket", "")) == feat and feat != "" else "", p["desc"]])
		pl.set_item_metadata(i, keys[i])
		if keys[i] == _play_cfg["playlist"]:
			pl.select(i)
	pl.item_selected.connect(func(i): _play_cfg["playlist"] = str(pl.get_item_metadata(i)))
	right.add_child(pl)
	right.add_child(UITheme.label("Class", 20, UITheme.GOLD))
	var co := OptionButton.new()
	var classes := profile.class_list()
	for i in range(classes.size()):
		co.add_item(str(classes[i]["name"]))
		co.set_item_metadata(i, classes[i]["key"])
		if classes[i]["key"] == str(profile.data["selected_class"]):
			co.select(i)
	var class_desc := UITheme.label("", 14)
	class_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	class_desc.custom_minimum_size = Vector2(480, 90)
	var show_cls := func():
		var bid := str(DB.modes["playlists"].get(_play_cfg["playlist"], {}).get("bracket", ""))
		var lo := Brackets.build_loadout(bid, profile.selected_class_def(), "full") if bid != "" else Loadout.build(profile.selected_class_def(), profile.unlocked(), {"supply": "full"})
		class_desc.text = ("%s bracket kit: " % Brackets.display_name(bid) if bid != "" else "") + _loadout_text(lo)
	co.item_selected.connect(func(i):
		profile.data["selected_class"] = str(co.get_item_metadata(i))
		profile.save()
		show_cls.call())
	right.add_child(co)
	right.add_child(class_desc)
	show_cls.call()
	pl.item_selected.connect(func(_i): show_cls.call())
	var rng_now := Matchmaker.range_for(profile.combat_level())
	right.add_child(UITheme.label("Casual matchmaking: combat levels %d-%d (within %d of yours; widens by %d every %d s of waiting). Bots are matched the same way." % [int(rng_now[0]), int(rng_now[1]), Matchmaker.window(0.0), int(Matchmaker.cfg()["widen_by"]), int(Matchmaker.cfg()["widen_every_s"])], 13, UITheme.CREAM))
	right.add_child(UITheme.label("Bot difficulty", 20, UITheme.GOLD))
	var sl := HSlider.new()
	sl.min_value = 0.15
	sl.max_value = 0.95
	sl.step = 0.05
	sl.value = float(profile.setting("bot_skill"))
	var sl_lbl := UITheme.label("", 14)
	var upd := func(v):
		profile.set_setting("bot_skill", v)
		sl_lbl.text = "Bots react in about %d tick(s) and pray correctly %d%% of the time" % [clampi(int(round(lerpf(3.0, 1.0, v))), 1, 3), int((0.35 + 0.6 * v) * 100)]
	sl.value_changed.connect(upd)
	upd.call(sl.value)
	right.add_child(sl)
	right.add_child(sl_lbl)
	var go := UITheme.button("Find match", func():
		_click()
		var cfg := _match_cfg()
		cfg["bot_skill"] = float(profile.setting("bot_skill"))
		if bool(profile.setting("short_countdown")):
			cfg["pre_ticks"] = 5
		start_match.emit(cfg))
	go.custom_minimum_size = Vector2(0, 56)
	go.add_theme_font_size_override("font_size", 26)
	vb.add_child(go)
	vb.add_child(UITheme.button("Ranked  -  %s" % Ranked.visible_rank(profile.data["ranked"]), func(): _click(); show_ranked()))
	vb.add_child(UITheme.button("Back", func(): _click(); show_main()))
	(mode_buttons[_play_cfg["mode"]] as Button).emit_signal("pressed")


## U8 private match: custom rules for this computer's matches (and the LAN host's).
var _private := {"on": false, "bots": true, "spectate": false, "score": 0, "time_min": 0, "mutators": []}


func _private_box() -> Control:
	var vb := VBoxContainer.new()
	var toggle := CheckBox.new()
	toggle.text = "Private match with custom rules"
	toggle.button_pressed = bool(_private["on"])
	vb.add_child(toggle)
	var box := VBoxContainer.new()
	box.visible = bool(_private["on"])
	vb.add_child(box)
	toggle.toggled.connect(func(v): _private["on"] = v; box.visible = v)
	for opt in [["bots", "Bots fill empty slots"], ["spectate", "Watch only: bots play, you spectate"]]:
		var cb := CheckBox.new()
		cb.text = str(opt[1])
		cb.button_pressed = bool(_private[opt[0]])
		cb.toggled.connect(func(v): _private[opt[0]] = v)
		box.add_child(cb)
	for opt in [["score", "Score limit / rounds to win (0 = mode default)", 0, 200], ["time_min", "Time limit in minutes (0 = mode default)", 0, 30]]:
		var row := HBoxContainer.new()
		row.add_child(UITheme.label(str(opt[1]) + "  ", 14))
		var sp := SpinBox.new()
		sp.min_value = int(opt[2])
		sp.max_value = int(opt[3])
		sp.value = int(_private[opt[0]])
		sp.value_changed.connect(func(v): _private[opt[0]] = int(v))
		row.add_child(sp)
		box.add_child(row)
	box.add_child(UITheme.label("Mutators (stack them):", 14, UITheme.GOLD))
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	for mid in Mutators.ids():
		var cb := CheckBox.new()
		cb.text = Mutators.display_name(str(mid))
		cb.tooltip_text = str(Mutators.get_def(str(mid)).get("desc", ""))
		cb.button_pressed = (_private["mutators"] as Array).has(mid)
		cb.toggled.connect(func(v):
			var ms: Array = _private["mutators"]
			if v and not ms.has(mid):
				ms.append(mid)
			elif not v:
				ms.erase(mid))
		grid.add_child(cb)
	return vb


## The match config from the Play screen, including private-match rules when they're on.
func _match_cfg() -> Dictionary:
	var cfg := _play_cfg.duplicate(true)
	cfg["bot_skill"] = float(profile.setting("bot_skill"))
	if bool(profile.setting("short_countdown")):
		cfg["pre_ticks"] = 5
	if bool(_private["on"]):
		var p := {"bots": bool(_private["bots"]), "spectate": bool(_private["spectate"]), "mutators": (_private["mutators"] as Array).duplicate()}
		var elim := str(DB.modes["modes"][cfg["mode"]].get("type", "")) == "elimination"
		if int(_private["score"]) > 0:
			p["rounds_to_win" if elim else "score_limit"] = int(_private["score"])
		if int(_private["time_min"]) > 0:
			p["round_time_s" if elim else "time_limit_s"] = int(_private["time_min"]) * 60
		cfg["private"] = p
	return cfg


# ================================================================ ranked (U4)

func show_ranked() -> void:
	var vb := _frame("Ranked", 1100, 820)
	var now := int(Time.get_unix_time_from_system())
	var st: Dictionary = profile.data["ranked"]
	var unlocked := profile.unlocked().has("feature:ranked")
	var feat := Brackets.featured(now)
	vb.add_child(_wrapped("Season %d  -  %d days left   ·   Duel and Last Stand on this week's featured bracket: %s" % [int(st["season"]) + 1, Ranked.season_days_left(now), Brackets.display_name(feat)], 16, UITheme.GOLD))
	vb.add_child(UITheme.label(Ranked.visible_rank(st), 40, UITheme.YELLOW))
	var peak := ("Season peak: %s   ·   " % str(Ranked.rank_for(float(st["peak"]))["label"])) if float(st["peak"]) > 0.0 else ""
	var wr := float(st["wins"]) / maxf(1.0, float(st["matches"]))
	vb.add_child(UITheme.label("%s%d matches, %d wins   ·   %d points" % [peak, int(st["matches"]), int(st["wins"]), int(st["points"])], 16))
	vb.add_child(_wrapped("You earn %d points per win and %d per loss: about %d points an hour at a 50%% win rate%s." % [int(DB.ranked["points"]["win"]), int(DB.ranked["points"]["loss"]), int(round(Ranked.points_per_hour(0.5))), (", %d at your %d%%" % [int(round(Ranked.points_per_hour(wr))), int(wr * 100)]) if int(st["matches"]) >= 5 else ""], 15))
	vb.add_child(UITheme.label("Season rewards (cosmetic only)", 20, UITheme.GOLD))
	for r in DB.ranked["points_rewards"]:
		var got := int(st["points"]) >= int(r["points"])
		var hours := maxf(0.0, (int(r["points"]) - int(st["points"])) / Ranked.points_per_hour(maxf(wr, 0.5) if int(st["matches"]) >= 5 else 0.5))
		vb.add_child(UITheme.label("%s %5d  %s%s" % ["[x]" if got else "[ ]", int(r["points"]), str(r["name"]), "" if got else ("  (about %.0f h)" % hours)], 15, UITheme.YELLOW if got else UITheme.CREAM))
	var peaks: Array = []
	for b in DB.ranked["peak_rewards"]:
		peaks.append("%s: %s" % [b, str(DB.ranked["peak_rewards"][b]).split(":")[1].replace("_", " ")])
	vb.add_child(_wrapped("End of season, by peak rank: " + ", ".join(peaks), 13))
	var status := UITheme.label("", 15, UITheme.RED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.custom_minimum_size.x = 1000
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	for m in DB.ranked["modes"]:
		var mode := str(m)
		hb.add_child(UITheme.button("Ranked %s" % str(DB.modes["modes"][mode]["name"]), func(): status.text = _start_ranked(mode)))
	vb.add_child(status)
	if not unlocked:
		status.text = "Ranked unlocks at combat level 20 (you're %d)." % profile.combat_level()
	vb.add_child(_wrapped("Ranked is human vs human only: bots never play and kills on bots never count. Host or join a LAN lobby with enough players, then start here (host). Leaving a ranked match counts as a loss and adds a queue cooldown.", 13))
	vb.add_child(UITheme.button("Back", func(): _click(); show_play()))


func _wrapped(text: String, size: int = 15, col: Color = UITheme.CREAM) -> Label:
	var l := UITheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 1040
	return l


## Starts a ranked LAN match if allowed; returns an explanation if not.
func _start_ranked(mode: String) -> String:
	if not profile.unlocked().has("feature:ranked"):
		return "Ranked unlocks at combat level 20."
	var wait := Progression.leave_cooldown_s(profile.data["ranked"]["leave_times"], int(Time.get_unix_time_from_system()))
	if wait > 0:
		return "Queue cooldown for leaving ranked matches: %d:%02d left." % [wait / 60, wait % 60]
	var need := 2 * int(DB.modes["modes"][mode]["team_size"])
	if net == null or not net.active():
		return "Ranked needs %d human players. Host a LAN lobby (LAN multiplayer) and start from here." % need
	if not net.is_host:
		return "Only the host can start a ranked match."
	var humans: Array = net._lobby_list().filter(func(p): return not bool(p.get("spectator", false)))
	if humans.size() != need:
		return "Ranked %s needs exactly %d players in the lobby (you have %d)." % [str(DB.modes["modes"][mode]["name"]), need, humans.size()]
	net.start_match({"mode": mode, "map": str(DB.modes["modes"][mode]["maps"][0]), "playlist": Ranked.featured_playlist(),
		"ranked": true, "pre_ticks": 10, "private": {"bots": false}})
	return ""


# ================================================================ tournaments (U8)

const TOUR_PATH := "user://tournament.json"


func _tour() -> Dictionary:
	if FileAccess.file_exists(TOUR_PATH):
		var j = JSON.parse_string(FileAccess.get_file_as_string(TOUR_PATH))
		if j is Dictionary:
			return _tour_ints(j)
	return {}


## JSON turns ints into floats; the tournament logic compares ints.
func _tour_ints(t: Dictionary) -> Dictionary:
	for k in ["size", "final", "grand_final"]:
		if t.has(k):
			t[k] = int(t[k])
	for m in t.get("matches", []):
		for k in ["id", "round", "winner", "loser"]:
			m[k] = int(m[k])
		for side in ["a", "b"]:
			for k in m[side]:
				if k != "bye":
					m[side][k] = int(m[side][k])
	return t


func _save_tour(t: Dictionary) -> void:
	var f := FileAccess.open(TOUR_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(t, "\t"))


## Called after a LAN tournament match: reports the winner (the human on the winning team).
func apply_tournament_result(summary: Dictionary) -> void:
	if not summary.has("tournament_match") or net == null or not net.is_host:
		return
	var t := _tour()
	if t.is_empty():
		return
	var w := int(summary.get("winner", -1))
	for r in summary.get("rows", []):
		if int(r["team"]) == w and not bool(r.get("bot", false)):
			var idx := (t["entrants"] as Array).find(str(r["name"]))
			if idx >= 0 and Tournament.report(t, int(summary["tournament_match"]), idx):
				_save_tour(t)
			return


func show_tournament() -> void:
	var t := _tour()
	var vb := _frame("Tournament", 1100, 820)
	if t.is_empty():
		vb.add_child(UITheme.label("Enter one player per line (2-16). Matches are private Duels using the Play screen's playlist. On LAN, players whose names match the lobby can play their match while everyone else spectates; otherwise report results by hand.", 15))
		var names := TextEdit.new()
		names.custom_minimum_size = Vector2(500, 300)
		var lobby_names: Array = []
		if net != null and net.is_host:
			for p in net._lobby_list():
				if not bool(p.get("spectator", false)):
					lobby_names.append(str(p["name"]))
		names.text = "\n".join(lobby_names)
		vb.add_child(names)
		var kind := OptionButton.new()
		kind.add_item("Single elimination")
		kind.add_item("Double elimination")
		vb.add_child(kind)
		vb.add_child(UITheme.button("Start tournament", func():
			var list: Array = []
			for line in names.text.split("\n"):
				var nm := line.strip_edges().left(12)
				if nm != "" and not list.has(nm):
					list.append(nm)
			if list.size() < 2 or list.size() > 16:
				return
			_save_tour(Tournament.create(list, "double" if kind.selected == 1 else "single"))
			show_tournament()))
		vb.add_child(UITheme.button("Back", func(): _click(); show_lan()))
		return
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1060, 600)
	vb.add_child(sc)
	var list_box := VBoxContainer.new()
	sc.add_child(list_box)
	if Tournament.is_done(t):
		list_box.add_child(UITheme.label("Champion: %s" % str(t["entrants"][Tournament.champion(t)]), 28, UITheme.YELLOW))
		for st in Tournament.standings(t):
			list_box.add_child(UITheme.label("%d.  %s" % [int(st[0]), str(t["entrants"][int(st[1])])], 18))
	var ready := Tournament.ready_matches(t)
	for m in t["matches"]:
		if bool(m.get("bye", false)) or bool(m.get("skipped", false)):
			continue
		var mid := int(m["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var a := Tournament.slot_entrant(t, m["a"])
		var b := Tournament.slot_entrant(t, m["b"])
		if a == Tournament.BYE or b == Tournament.BYE:
			continue  # decided automatically
		var res := ""
		if int(m["winner"]) >= 0:
			res = "  ->  %s wins" % str(t["entrants"][int(m["winner"])])
		var lab := UITheme.label(Tournament.match_label(t, mid) + res, 16, UITheme.GOLD if ready.has(mid) else UITheme.CREAM)
		lab.custom_minimum_size.x = 520
		row.add_child(lab)
		if ready.has(mid):
			for e in [a, b]:
				row.add_child(UITheme.button("%s won" % str(t["entrants"][e]), func():
					var tt := _tour()
					Tournament.report(tt, mid, e)
					_save_tour(tt)
					show_tournament()))
			var peers := _tour_peers(t, a, b)
			if not peers.is_empty():
				row.add_child(UITheme.button("Play on LAN", func():
					var cfg := _match_cfg()
					cfg["mode"] = "duel"
					cfg["map"] = "castle_courtyard"
					cfg["only_peers"] = peers
					cfg["tournament_match"] = mid
					var p: Dictionary = cfg.get("private", {})
					p["bots"] = false
					cfg["private"] = p
					net.start_match(cfg)))
		list_box.add_child(row)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(UITheme.button("New tournament", func():
		DirAccess.remove_absolute(TOUR_PATH)
		show_tournament()))
	hb.add_child(UITheme.button("Back", func(): _click(); show_lan()))


## LAN peer ids for two entrants, if both are in the host's lobby by name.
func _tour_peers(t: Dictionary, a: int, b: int) -> Array:
	if net == null or not net.is_host:
		return []
	var out: Array = []
	for e in [a, b]:
		for p in net._lobby_list():
			if str(p["name"]) == str(t["entrants"][e]):
				out.append(int(p["peer"]))
				break
	return out if out.size() == 2 else []


# ================================================================ replays (U8)

func show_replays() -> void:
	var vb := _frame("Replays", 1100, 760)
	vb.add_child(UITheme.label("Your last %d matches are saved automatically. Export copies one to %s so it isn't rotated out." % [Replay.KEEP, ProjectSettings.globalize_path(Replay.EXPORT_DIR)], 14))
	var status := UITheme.label("", 14, UITheme.GOLD)
	var list := Replay.list()
	if list.is_empty():
		vb.add_child(UITheme.label("No replays yet. Play a match!", 18, UITheme.GOLD))
	for r in list:
		var info: Dictionary = r["info"]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		var secs := int(int(r["ticks"]) * 0.6)
		var who := ", ".join((info.get("fighters", []) as Array).slice(0, 4))
		var lab := UITheme.label("%s  %s on %s  (%d:%02d)  %s%s" % [str(r["date"]).replace("T", " ").left(16), str(info.get("mode_name", "")), str(info.get("map", "")), secs / 60, secs % 60, who, "..." if (info.get("fighters", []) as Array).size() > 4 else ""], 14)
		lab.custom_minimum_size.x = 720
		lab.clip_text = true
		hb.add_child(lab)
		var path := str(r["path"])
		hb.add_child(UITheme.button("Watch", func(): _click(); watch_replay.emit(path)))
		hb.add_child(UITheme.button("Export", func():
			var dest := Replay.export_file(path)
			status.text = ("Exported to " + ProjectSettings.globalize_path(dest)) if dest != "" else "Export failed."
			if dest != "":
				OS.shell_show_in_file_manager(ProjectSettings.globalize_path(dest))))
		hb.add_child(UITheme.button("Verify", func():
			status.text = "Replay reproduces the match exactly." if Replay.verify(Replay.load_file(path)) else "Replay does NOT match (made with another game version?)."))
		vb.add_child(hb)
	vb.add_child(status)
	vb.add_child(UITheme.button("Back", func(): _click(); show_main()))


func _fill_maps(opt: OptionButton, mode_key: String) -> void:
	opt.clear()
	var maps: Array = DB.modes["modes"][mode_key]["maps"]
	var sel := 0
	for i in range(maps.size()):
		var m: Dictionary = DB.maps[maps[i]]
		opt.add_item("%s (%dx%d)" % [m["name"], int(m["size"][0]), int(m["size"][1])])
		opt.set_item_metadata(i, maps[i])
		if maps[i] == _play_cfg["map"]:
			sel = i
	opt.select(sel)
	_play_cfg["map"] = str(maps[sel])


func _loadout_text(lo: Dictionary) -> String:
	var eq: Dictionary = lo["equipment"]
	var parts: Array = []
	for s in ["weapon", "ammo", "head", "body", "legs", "shield", "hands", "feet", "neck", "cape", "ring"]:
		if str(eq.get(s, "")) != "":
			parts.append(str(DB.item(str(eq[s]))["name"]))
	var inv := {}
	for e in lo["inventory"]:
		if e != null:
			var nm := str(DB.item(str(e["id"]))["name"])
			inv[nm] = int(inv.get(nm, 0)) + 1
	var invp: Array = []
	for k in inv:
		invp.append("%dx %s" % [inv[k], k] if int(inv[k]) > 1 else k)
	var perks: Array = []
	for p in lo["perks"]:
		perks.append(str(DB.perks[p]["name"]))
	var spell := ""
	if str(lo.get("autocast", "")) != "":
		spell = "\nAutocast: " + str(DB.spells[lo["autocast"]]["name"])
	return "Wearing: %s\nCarrying (full pack): %s%s\nPerks: %s" % [", ".join(parts), ", ".join(invp), spell, ", ".join(perks)]


# ================================================================ barracks

func show_barracks(tab_idx: int = 0) -> void:
	var vb := _frame("Barracks", 1240, 820)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(1200, 660)
	vb.add_child(tabs)
	tabs.add_child(_tab_classes())
	tabs.add_child(_tab_unlocks())
	tabs.add_child(_tab_challenges())
	tabs.add_child(_tab_prestige())
	tabs.add_child(_tab_stats())
	tabs.add_child(_tab_meta())
	tabs.current_tab = tab_idx
	vb.add_child(UITheme.button("Back", func(): _click(); show_main()))


## U9 meta report from this computer's match telemetry.
func _tab_meta() -> Control:
	var r := _scroll("Meta")
	var inner: VBoxContainer = r[1]
	var recs := Telemetry.load_dir(Telemetry.DIR)
	inner.add_child(UITheme.label("Win rate, pick rate and average time-to-kill per class and bracket, from the %d matches recorded on this computer (bots included). Turn telemetry on in Options to collect it." % recs.size(), 15))
	var meta := Telemetry.meta(recs)
	if meta.is_empty():
		inner.add_child(UITheme.label("No matches recorded yet.", 16, UITheme.GOLD))
	for b in meta:
		var name := Brackets.display_name(str(b)) if Brackets.has(str(b)) else str(DB.modes["playlists"].get(b, {}).get("name", str(b).capitalize()))
		inner.add_child(UITheme.label(name, 20, UITheme.GOLD))
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		var t := "[code]%-20s %8s %8s %8s %10s[/code]\n" % ["Class", "Slots", "Pick", "Win", "TTK (s)"]
		for cn in meta[b]:
			var c: Dictionary = meta[b][cn]
			t += "[code]%-20s %8d %7d%% %7d%% %10s[/code]\n" % [str(cn).left(20), int(c["picks"]), int(round(float(c["pick_rate"]) * 100)), int(round(float(c["win_rate"]) * 100)), ("%.1f" % float(c["ttk_s"])) if float(c["ttk_s"]) >= 0.0 else "-"]
		rt.text = t
		inner.add_child(rt)
	return r[0]


# ================================================================ patch notes (U9)

## The selected class's default-class key for the "what changed for my class" filter.
func _my_class_key() -> String:
	var key := str(profile.data.get("selected_class", "warrior"))
	if DB.classes["defaults"].has(key):
		return key
	return {"melee": "warrior", "ranged": "archer", "magic": "battlemage", "hybrid": "tribrid"}[Brackets.kit_key(profile.selected_class_def())]


func show_patch_notes(only_mine: bool = false) -> void:
	var vb := _frame("Patch notes", 1100, 800)
	profile.data["seen_patch"] = DB.latest_patch()
	profile.save()
	var mine := _my_class_key()
	var cb := CheckBox.new()
	cb.text = "Only what changed for my class (%s)" % str(DB.classes["defaults"][mine]["name"])
	cb.button_pressed = only_mine
	cb.toggled.connect(func(v): show_patch_notes(v))
	vb.add_child(cb)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.custom_minimum_size = Vector2(1060, 600)
	var tag_col := {"new": "7fd07f", "change": "ffd23f", "fix": "8fc7ff", "balance": "ff981f", "qol": "e8dcc0"}
	var t := ""
	for v in DB.patch_notes.get("versions", []):
		t += "[b][color=#ff981f]%s  -  %s[/color][/b]  [color=#aaaaaa]%s[/color]\n" % [str(v["version"]), str(v["title"]), str(v["date"])]
		for n in v["notes"]:
			var cls: Array = n.get("classes", ["all"])
			if only_mine and not (cls.has("all") or cls.has(mine)):
				continue
			var tg := str(n.get("tag", "change"))
			t += "  [color=#%s][%s][/color] %s\n" % [str(tag_col.get(tg, "e8dcc0")), tg.to_upper(), str(n["text"])]
		t += "\n"
	rt.text = t
	vb.add_child(rt)
	vb.add_child(UITheme.button("Continue", func(): _click(); show_main()))


func _scroll(name: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	sc.add_child(inner)
	return [sc, inner]


func _tab_classes() -> Control:
	var r := _scroll("Classes")
	var inner: VBoxContainer = r[1]
	var unl := profile.unlocked()
	inner.add_child(UITheme.label("Default classes upgrade on their own to the best gear you've unlocked.", 15))
	for k in DB.classes["defaults"]:
		var d: Dictionary = DB.classes["defaults"][k]
		var lo := Loadout.build(d, unl, {"supply": "full"})
		inner.add_child(UITheme.label("%s - %s" % [d["name"], d.get("desc", "")], 18, UITheme.YELLOW))
		var l := UITheme.label(_loadout_text(lo), 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size.x = 1150
		inner.add_child(l)
	inner.add_child(HSeparator.new())
	if not unl.has("feature:create_a_class"):
		inner.add_child(UITheme.label("Create-a-class unlocks at combat level 4 (you are %d)." % profile.combat_level(), 18, UITheme.GOLD))
		return r[0]
	var slots := Progression.custom_class_slots(profile.combat_level())
	inner.add_child(UITheme.label("Create-a-class: %d custom slot(s)" % slots, 20, UITheme.GOLD))
	var cc: Array = profile.data["custom_classes"]
	for i in range(slots):
		var hb := HBoxContainer.new()
		inner.add_child(hb)
		var nm := str(cc[i]["name"]) if i < cc.size() else "(empty)"
		hb.add_child(UITheme.label("Slot %d: %s" % [i + 1, nm], 16))
		hb.add_child(UITheme.button("Edit", func(): _click(); show_class_editor(i)))
	return r[0]


func _tab_unlocks() -> Control:
	var r := _scroll("Unlocks")
	var inner: VBoxContainer = r[1]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	inner.add_child(grid)
	var lv := profile.levels()
	lv["combat"] = profile.combat_level()
	for track in ["melee", "ranged", "magic", "combat"]:
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 280
		grid.add_child(col)
		col.add_child(UITheme.label("%s (level %d)" % [track.capitalize(), int(lv[track])], 18, UITheme.style_color(track)))
		var levels: Array = DB.unlocks[track].keys()
		levels.sort()
		for l in levels:
			var got := int(l) <= int(lv[track])
			var labels: Array = []
			for e in DB.unlocks[track][l]:
				labels.append(Progression.unlock_label(str(e)))
			var t := UITheme.label("%2d  %s" % [int(l), ", ".join(labels)], 12, UITheme.CREAM if got else Color(0.5, 0.45, 0.38))
			t.autowrap_mode = TextServer.AUTOWRAP_WORD
			t.custom_minimum_size.x = 270
			col.add_child(t)
	return r[0]


func _tab_challenges() -> Control:
	var r := _scroll("Challenges")
	var inner: VBoxContainer = r[1]
	var prog: Dictionary = profile.data["challenges"]
	var done: Array = profile.data["completed"]
	for cat in ["shared", "melee", "ranged", "magic"]:
		inner.add_child(UITheme.label(cat.capitalize() + " challenges", 18, UITheme.style_color("combat" if cat == "shared" else cat)))
		for c in Challenges.data().get("challenges", []):
			if str(c["cat"]) != cat:
				continue
			var cid := str(c["id"])
			var p := mini(int(prog.get(cid, 0)), int(c["target"]))
			var mark := "[done]" if done.has(cid) else "%d / %d" % [p, int(c["target"])]
			var rw := str(c.get("reward", "")).replace("title:", "title ").replace("banner:", "banner ")
			inner.add_child(UITheme.label("  %-16s %-56s %12s   %d XP %s" % [c["name"], c["desc"], mark, int(c["xp"]), rw], 13, UITheme.YELLOW if done.has(cid) else UITheme.CREAM))
	inner.add_child(UITheme.label("Weapon challenges (25/75/150 kills unlock mods 1/2/3; Expert steps unlock ornament kits)", 18, UITheme.GOLD))
	for wt in Challenges.weapon_types():
		var steps: Array = []
		for st in Challenges.data().get("weapon_ladder", []):
			var sid := "%s:%s" % [wt, st["id"]]
			steps.append("%s %s" % [st["name"], "✓" if done.has(sid) else "%d/%d" % [mini(int(prog.get(sid, 0)), int(st["target"])), int(st["target"])]])
		inner.add_child(UITheme.label("  %-18s %s" % [Challenges._type_label(wt), "   ".join(steps)], 12))
	return r[0]


func _tab_prestige() -> Control:
	var r := _scroll("Prestige")
	var inner: VBoxContainer = r[1]
	inner.add_child(UITheme.label("Each style prestiges on its own at level 40: that style resets to 1 and loses its unlocks.\nYou keep challenges, kits, banners, stats and the other two styles. Up to 10 prestiges per style.", 15))
	for s in DB.STYLES:
		var hb := HBoxContainer.new()
		inner.add_child(hb)
		hb.add_child(UITheme.label("%s: level %d, prestige %d" % [s.capitalize(), profile.level(s), profile.prestige(s)], 18, UITheme.style_color(s)))
		var b := UITheme.button("Prestige %s" % s.capitalize(), func():
			profile.do_prestige(s)
			sfx.play("level_up")
			show_barracks(3))
		b.disabled = not profile.can_prestige(s)
		hb.add_child(b)
	var all10 := true
	for s in DB.STYLES:
		if profile.prestige(s) < 10:
			all10 = false
	inner.add_child(UITheme.label("Max cape: %s" % ("UNLOCKED" if all10 else "reach prestige 10 in all three styles"), 16, UITheme.GOLD))
	return r[0]


func _tab_stats() -> Control:
	var r := _scroll("Stats")
	var inner: VBoxContainer = r[1]
	var st: Dictionary = profile.data["stats"]
	var kd := float(st["kills"]) / maxf(1.0, float(st["deaths"]))
	inner.add_child(UITheme.label("Matches %d   Wins %d   Kills %d   Deaths %d   Assists %d   K/D %.2f   Damage %d" % [int(st["matches"]), int(st["wins"]), int(st["kills"]), int(st["deaths"]), int(st["assists"]), kd, int(st["damage"])], 18))
	inner.add_child(UITheme.label("Titles: %s" % (", ".join(profile.data["titles"]) if not (profile.data["titles"] as Array).is_empty() else "none yet"), 16))
	inner.add_child(UITheme.label("Banners: %s" % (", ".join(profile.data["banners"]) if not (profile.data["banners"] as Array).is_empty() else "none yet"), 16))
	return r[0]


# ================================================================ create-a-class

func _opt(parent: Control, label: String, items: Array, current: String) -> OptionButton:
	## items: [[id, text], ...]
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := UITheme.label(label, 15, UITheme.GOLD)
	l.custom_minimum_size.x = 150
	hb.add_child(l)
	var o := OptionButton.new()
	o.custom_minimum_size.x = 380
	o.fit_to_longest_item = false
	o.clip_text = true
	o.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for i in range(items.size()):
		o.add_item(str(items[i][1]))
		o.set_item_metadata(i, items[i][0])
		if str(items[i][0]) == current:
			o.select(i)
	hb.add_child(o)
	return o


func _val(o: OptionButton) -> String:
	if o.selected < 0:
		return ""
	return str(o.get_item_metadata(o.selected))


func show_class_editor(slot: int, override: Dictionary = {}) -> void:
	var vb := _frame("Create-a-class  (slot %d)" % (slot + 1), 1180, 840)
	var unl := profile.unlocked()
	var cc: Array = profile.data["custom_classes"]
	var cur: Dictionary = cc[slot] if slot < cc.size() else {"name": "Custom %d" % (slot + 1), "primary": "bronze_scimitar", "armour": "set:plate:1", "perks": ["extra_rations", "rebuke", "unbound"], "spellbook": "elemental"}
	if not override.is_empty():
		cur = override
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	vb.add_child(cols)
	var left := VBoxContainer.new()
	cols.add_child(left)
	var name_edit := LineEdit.new()
	name_edit.text = str(cur.get("name", "Custom"))
	name_edit.custom_minimum_size.x = 400
	var nhb := HBoxContainer.new()
	var nl := UITheme.label("Name", 15, UITheme.GOLD)
	nl.custom_minimum_size.x = 150
	nhb.add_child(nl)
	nhb.add_child(name_edit)
	left.add_child(nhb)
	var weapons: Array = []
	var none := [["", "(none)"]]
	for id in DB.items:
		var it: Dictionary = DB.items[id]
		if str(it.get("slot", "")) == "weapon" and unl.has(id):
			weapons.append([id, "%s  [%s, %d ticks]" % [it["name"], it["style"], int(it.get("speed", 4))]])
	weapons.sort_custom(func(a, b): return str(a[1]) < str(b[1]))
	var o_primary := _opt(left, "Primary", weapons, str(cur.get("primary", "")))
	var mod_items := none.duplicate()
	var wt_primary := str(DB.item(str(cur.get("primary", ""))).get("weapon_type", ""))
	var mod_level := int(profile.data["unlocked_mods"].get(wt_primary, 0))
	var mods := Challenges.mods_for(wt_primary)
	for i in range(mini(mod_level, mods.size())):
		mod_items.append([mods[i]["id"], "%s (%s)" % [mods[i]["name"], mods[i]["desc"]]])
	var o_mod := _opt(left, "Weapon mod", mod_items, str(cur.get("mod", "")))
	var kit_items := none.duplicate()
	for k in profile.data["kits"].get(wt_primary, []):
		kit_items.append([k, str(k).replace("_", " ").capitalize()])
	var o_kit := _opt(left, "Ornament kit", kit_items, str(cur.get("kit", "")))
	var secs: Array = cur.get("secondary", [])
	var o_sec1 := _opt(left, "Secondary 1", none + weapons, str(secs[0]) if secs.size() > 0 else "")
	var o_sec2 := _opt(left, "Secondary 2", none + weapons, str(secs[1]) if secs.size() > 1 else "")
	var ammo_items := none.duplicate()
	for id in DB.items:
		var it: Dictionary = DB.items[id]
		if str(it.get("slot", "")) == "ammo" and unl.has(id):
			ammo_items.append([id, str(it["name"])])
	var o_ammo := _opt(left, "Ammo", ammo_items, str(cur.get("ammo", "")))
	var set_items: Array = []
	for key in DB.sets:
		var ids: Array = DB.sets[key]
		var ok := true
		for id in ids:
			if not unl.has(str(id)):
				ok = false
		if ok:
			set_items.append(["set:" + str(key), Progression.unlock_label("set:" + str(key))])
	var o_set := _opt(left, "Armour set", set_items, str(cur.get("armour", "")))
	var right := VBoxContainer.new()
	cols.add_child(right)
	var armour_items := none.duplicate()
	for id in DB.items:
		var it: Dictionary = DB.items[id]
		if str(it.get("kind", "")) == "armour" and unl.has(id) and ["head", "body", "legs", "shield", "feet", "hands"].has(str(it["slot"])):
			armour_items.append([id, "%s (%s)" % [it["name"], it["slot"]]])
	armour_items.sort_custom(func(a, b): return str(a[1]) < str(b[1]))
	var sw: Array = cur.get("switches", [])
	var o_sw: Array = []
	for i in range(4):
		o_sw.append(_opt(right, "Switch piece %d" % (i + 1), armour_items, str(sw[i]) if sw.size() > i else ""))
	var acc: Array = cur.get("accessories", [])
	var o_acc := {}
	for slot_name in ["ring", "neck", "cape", "shield"]:
		var items := none.duplicate()
		for id in DB.items:
			var it: Dictionary = DB.items[id]
			if str(it.get("slot", "")) == slot_name and unl.has(id) and (it.get("unique", false) or str(it.get("weapon_type", "")) == "defender"):
				items.append([id, str(it["name"])])
		var curv := ""
		for a in acc:
			if str(DB.item(str(a)).get("slot", "")) == slot_name:
				curv = str(a)
		o_acc[slot_name] = _opt(right, "Off-hand" if slot_name == "shield" else slot_name.capitalize(), items, curv)
	var books := [["elemental", "Elemental"]]
	if unl.has("feature:forbidden_book"):
		books.append(["forbidden", "Forbidden (needs a Forbidden staff)"])
	var o_book := _opt(right, "Spellbook", books, str(cur.get("spellbook", "elemental")))
	var spell_items := [["", "(best damage spell)"]]
	for sid in DB.spell_order:
		if unl.has(sid):
			spell_items.append([sid, "%s (%s)" % [DB.spells[sid]["name"], DB.spells[sid]["book"]]])
	var o_auto := _opt(right, "Autocast", spell_items, str(cur.get("autocast", "")))
	var o_perks: Array = []
	var cperks: Array = cur.get("perks", [])
	for tier in [1, 2, 3]:
		var items: Array = []
		var curp := ""
		for pid in DB.perk_order:
			var p: Dictionary = DB.perks[pid]
			if int(p["tier"]) == tier and unl.has(pid):
				items.append([pid, "%s - %s" % [p["name"], p["desc"]]])
				if cperks.has(pid):
					curp = pid
		o_perks.append(_opt(right, "Perk %d" % tier, items, curp))
	var info := UITheme.label("Inventory space is the budget: every secondary or switch piece costs 2 food.", 14)
	vb.add_child(info)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(UITheme.button("Save class", func():
		var prim := _val(o_primary)
		var secondary: Array = []
		for o in [o_sec1, o_sec2]:
			if _val(o) != "" and _val(o) != prim:
				secondary.append(_val(o))
		var switches: Array = []
		for o in o_sw:
			if _val(o) != "":
				switches.append(_val(o))
		var accessories: Array = []
		for k in o_acc:
			if _val(o_acc[k]) != "":
				accessories.append(_val(o_acc[k]))
		var perks: Array = []
		for o in o_perks:
			if _val(o) != "":
				perks.append(_val(o))
		var d := {
			"name": name_edit.text.strip_edges().left(20) if name_edit.text.strip_edges() != "" else "Custom",
			"primary": prim, "secondary": secondary, "armour": _val(o_set), "switches": switches,
			"accessories": accessories, "ammo": _val(o_ammo), "spellbook": _val(o_book), "autocast": _val(o_auto),
			"perks": perks, "main_food": clampi(18 - 2 * (secondary.size() + switches.size()), 6, 18),
			"mod": _val(o_mod), "kit": _val(o_kit),
		}
		var pwt := str(DB.item(prim).get("weapon_type", ""))
		var mod := Challenges.find_mod(pwt, _val(o_mod))
		if not mod.is_empty():
			d["weapon_mods"] = {prim: {"id": mod["id"], "bonuses": mod.get("bonuses", {}), "range": int(mod.get("range", 0))}}
			if mod.has("ember_bonus"):
				d["spell_mods"] = {"ember_bonus": int(mod["ember_bonus"])}
		if _val(o_kit) != "":
			d["kits"] = {pwt: str(Challenges.data()["kits"].get(_val(o_kit), ""))}
		while cc.size() <= slot:
			cc.append({"name": "Custom %d" % (cc.size() + 1), "primary": "bronze_scimitar", "armour": "set:plate:1", "perks": [], "secondary": [], "switches": []})
		cc[slot] = d
		profile.data["selected_class"] = "custom:%d" % slot
		profile.save()
		sfx.play("level_up", 0.5)
		show_barracks(0)))
	hb.add_child(UITheme.button("Cancel", func(): show_barracks(0)))
	# Changing the primary refreshes the mod and kit lists for that weapon type.
	o_primary.item_selected.connect(func(_i):
		var nxt := cur.duplicate(true)
		nxt["primary"] = _val(o_primary)
		nxt["name"] = name_edit.text
		nxt["mod"] = ""
		nxt["kit"] = ""
		show_class_editor(slot, nxt))


# ================================================================ options

func show_options() -> void:
	var vb := _frame("Options", 760, 700)
	var nh := HBoxContainer.new()
	vb.add_child(nh)
	nh.add_child(UITheme.label("Player name ", 16, UITheme.GOLD))
	var ne := LineEdit.new()
	ne.text = str(profile.data["name"])
	ne.custom_minimum_size.x = 300
	ne.text_changed.connect(func(t): profile.data["name"] = t.strip_edges().left(12); profile.save())
	nh.add_child(ne)
	for opt in [
		["tick_sound", "Tick metronome sound (practise prayer switching)"],
		["tick_visual", "Visual tick indicator (flashes every game tick)"],
		["telemetry", "Save match telemetry on this computer (no personal data; for playtest reports)"],
		["switch_hotkeys", "Gear-switch hotkeys Z / X / C (QoL toggle - GDD open question)"],
		["colorblind", "Colour-blind palette (blue / orange teams)"],
		["short_countdown", "Short pre-match countdown (3 s instead of 15 s)"],
		["show_tile_grid", "Show tile grid lines"],
		["placeholder_map_art", "Placeholder map art (debug: compare with the old boxes)"],
	]:
		var cb := CheckBox.new()
		cb.text = str(opt[1])
		cb.button_pressed = profile.setting(str(opt[0])) == true
		cb.toggled.connect(func(v):
			profile.set_setting(str(opt[0]), v)
			if str(opt[0]) == "colorblind":
				UITheme.colorblind = v)
		vb.add_child(cb)
	vb.add_child(UITheme.label("Minimap size", 16, UITheme.GOLD))
	var ms := HSlider.new()
	ms.min_value = 140
	ms.max_value = 280
	ms.step = 10
	ms.value = int(profile.setting("minimap_size"))
	ms.value_changed.connect(func(v): profile.set_setting("minimap_size", int(v)))
	vb.add_child(ms)
	vb.add_child(UITheme.label("Volume", 16, UITheme.GOLD))
	var vs := HSlider.new()
	vs.min_value = 0.0
	vs.max_value = 1.0
	vs.step = 0.05
	vs.value = float(profile.setting("volume"))
	vs.value_changed.connect(func(v):
		profile.set_setting("volume", v)
		sfx.volume = v
		sfx.play("click"))
	vb.add_child(vs)
	var tel := HBoxContainer.new()
	vb.add_child(tel)
	var tel_status := UITheme.label("", 13, UITheme.GOLD)
	tel.add_child(UITheme.button("Export telemetry", func():
		var path := Telemetry.export_zip()
		if path == "":
			tel_status.text = "  Nothing to export yet."
		else:
			tel_status.text = "  Saved " + ProjectSettings.globalize_path(path)
			OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))))
	tel.add_child(tel_status)
	vb.add_child(HSeparator.new())
	vb.add_child(UITheme.label("Developer / testing", 16, UITheme.GOLD))
	var dev := HBoxContainer.new()
	vb.add_child(dev)
	dev.add_child(UITheme.button("+10,000 XP to every style", func():
		profile.add_xp({"melee": 10000, "ranged": 10000, "magic": 10000})
		sfx.play("level_up")))
	dev.add_child(UITheme.button("Reset profile", func():
		var nm: String = profile.data["name"]
		profile.data = {}
		profile._defaults()
		profile.data["name"] = nm
		profile.save()
		show_options()))
	vb.add_child(UITheme.button("Back", func(): _click(); show_main()))


# ================================================================ results

func show_results(summary: Dictionary, applied: Dictionary) -> void:
	if summary.has("replay_view"):
		show_replays()
		return
	if summary.has("training"):
		show_training_results(summary, applied)
		return
	var vb := _frame("Match results", 1240, 840)
	var won := bool(summary.get("won", false))
	var head := UITheme.label("%s  -  %s on %s%s" % ["VICTORY" if won else ("FORFEIT" if summary.get("forfeit", false) else ("DRAW" if int(summary.get("winner", -1)) < 0 and not bool(summary.get("ffa", false)) else "DEFEAT")), summary.get("mode_name", ""), summary.get("map", ""), ("  (%s)" % Brackets.display_name(str(summary["bracket"]))) if str(summary.get("bracket", "")) != "" else ""], 24, UITheme.YELLOW if won else UITheme.RED)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	vb.add_child(cols)
	# Scoreboard.
	var sb := RichTextLabel.new()
	sb.bbcode_enabled = true
	sb.custom_minimum_size = Vector2(600, 560)
	sb.add_theme_font_size_override("mono_font_size", 15)
	cols.add_child(sb)
	var rows: Array = summary.get("rows", [])
	var my_team := int(summary.get("my_team", 0))
	var ffa := bool(summary.get("ffa", false))
	rows.sort_custom(func(a, b):
		if not ffa and int(a["team"]) != int(b["team"]):
			return int(a["team"]) == my_team
		return int(a["kills"]) * 1000 + int(a["damage"]) > int(b["kills"]) * 1000 + int(b["damage"]))
	var txt := "[code]%-14s %4s %4s %4s %6s %4s[/code]\n" % ["Name", "K", "D", "A", "Dmg", "Obj"]
	var last_team := -99
	for r in rows:
		if not ffa and int(r["team"]) != last_team:
			last_team = int(r["team"])
			txt += "[color=#%s][b]%s - %d[/b][/color]\n" % [UITheme.team_color(last_team, my_team).to_html(false), "Your team" if last_team == my_team else "Enemy team", int(summary["scores"][last_team])]
		var line := "%-14s %4d %4d %4d %6d %4d" % [str(r["name"]).left(14), int(r["kills"]), int(r["deaths"]), int(r["assists"]), int(r["damage"]), int(r["obj"])]
		txt += ("[color=#ffff00][code]%s[/code][/color]\n" if int(r["id"]) == int(summary.get("my_id", -1)) else "[code]%s[/code]\n") % line
	sb.text = txt
	# XP breakdown, challenges and level-ups.
	var right := RichTextLabel.new()
	right.bbcode_enabled = true
	right.custom_minimum_size = Vector2(580, 560)
	cols.add_child(right)
	var x: Dictionary = summary.get("xp", {})
	var rt := "[b][color=#ff981f]XP earned[/color][/b]\n"
	for line in x.get("lines", []):
		rt += "  %s  [color=#%s]+%d[/color]\n" % [line["label"], UITheme.style_color(str(line["style"])).to_html(false), int(line["amount"])]
	var ch: Dictionary = applied.get("challenges", {})
	for c in ch.get("completed", []):
		rt += "  [color=#ffd23f]Challenge complete: %s[/color]  +%d XP %s\n" % [c["name"], int(c["xp"]), ("(" + str(c["reward"]) + ")") if str(c["reward"]) != "" else ""]
	var tot: Dictionary = applied.get("total", {})
	rt += "\n[b]Total:[/b]  [color=#e04a3a]Melee +%d[/color]   [color=#4fbf4f]Ranged +%d[/color]   [color=#4f8fff]Magic +%d[/color]\n\n" % [int(tot.get("melee", 0)), int(tot.get("ranged", 0)), int(tot.get("magic", 0))]
	for up in applied.get("level_ups", []):
		var s := str(up["style"])
		rt += "[b][color=#%s]%s level %d -> %d![/color][/b]\n" % [UITheme.style_color(s).to_html(false), s.capitalize(), int(up["from"]), int(up["to"])]
		for u in up["unlocks"]:
			rt += "    Unlocked: %s\n" % u
	var rk: Dictionary = applied.get("ranked", {})
	if not rk.is_empty():
		var mid := Ranked.mid_reward()
		rt += "\n[b][color=#ff981f]Ranked[/color][/b]  %s%s   +%d points (%d)%s\n" % [str(rk["after"]),
			("  (%+.0f)" % float(rk["delta"])) if bool(rk["placed"]) else "", int(rk["points"]), int(rk["total_points"]),
			"" if int(rk["total_points"]) >= int(mid.get("points", 0)) else ("  -  %d to %s" % [int(mid["points"]) - int(rk["total_points"]), str(mid["name"])])]
		if float(rk["mult"]) < 1.0:
			rt += "  [color=#ff8060]Repeat opponent: this match counted %d%%.[/color]\n" % int(float(rk["mult"]) * 100)
		for g in rk["rewards"]:
			rt += "  [color=#ffd23f]Unlocked %s[/color]\n" % str(g)
	rt += _fight_report_text(summary.get("fight_report", {}))
	right.text = rt
	if not (applied.get("level_ups", []) as Array).is_empty():
		sfx.play("level_up")
	if summary.has("lab"):
		vb.add_child(_lab_vote_row(summary))
	if Profile.playtest_build():
		vb.add_child(_feedback_row(str(summary.get("telemetry_path", ""))))
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(UITheme.button("Play again", func(): start_match.emit(_match_cfg())))
	hb.add_child(UITheme.button("Change mode", func(): show_play()))
	hb.add_child(UITheme.button("Main menu", func(): show_main()))


## U6 post-match fight report.
func _fight_report_text(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	var t := "\n[b][color=#ff981f]Fight report[/color][/b]\n"
	t += "  Ward accuracy: [b]%s[/b] of %d incoming hits" % [_pct(float(r["ward_accuracy"])), int(r["incoming"])]
	var by: Dictionary = r.get("ward_accuracy_by_style", {})
	var bits: Array = []
	for s in ["melee", "ranged", "magic"]:
		if float(by.get(s, -1.0)) >= 0.0:
			bits.append("[color=#%s]%s %s[/color]" % [UITheme.style_color(s).to_html(false), s.capitalize(), _pct(float(by[s]))])
	if not bits.is_empty():
		t += "  (" + ", ".join(bits) + ")"
	t += "\n"
	if float(r["reaction_avg"]) >= 0.0:
		t += "  Ward reaction after an enemy switched style: %.1f ticks (%d switches)\n" % [float(r["reaction_avg"]), int(r["reaction_samples"])]
	t += "  Special attacks: %d used of about %d available   Freeze uptime: %s\n" % [int(r["specs_used"]), int(r["specs_available"]), _pct(float(r["freeze_uptime"]))]
	t += "  Food left unused at death: %d   Healing wasted: %d\n" % [int(r["food_unused"]), int(r["wasted_heal"])]
	var dpt: Dictionary = r.get("dmg_per_tick", {})
	t += "  Damage per tick: [color=#e04a3a]melee %.2f[/color]  [color=#4fbf4f]ranged %.2f[/color]  [color=#4f8fff]magic %.2f[/color]\n" % [float(dpt.get("melee", 0)), float(dpt.get("ranged", 0)), float(dpt.get("magic", 0))]
	t += "  [color=#ffd23f]Tip: %s[/color]\n" % CombatLog.tip(r)
	return t


func _pct(x: float) -> String:
	return "-" if x < 0.0 else "%d%%" % int(round(x * 100.0))


## U7: one-tap Lab vote after a Lab match. Stored in the profile (shown next week) and in telemetry.
func _lab_vote_row(summary: Dictionary) -> Control:
	var lab: Dictionary = summary["lab"]
	var row := HBoxContainer.new()
	row.add_child(UITheme.label("The Lab: %s. Keep it, change it or drop it?  " % str(lab.get("name", "")), 16, Color("8fc7ff")))
	var done := UITheme.label("", 14, UITheme.GOLD)
	var buttons: Array = []
	for v in ["keep", "change", "drop"]:
		var b := UITheme.button(v.capitalize(), func():
			var votes: Dictionary = profile.data.get("lab_votes", {})
			var wk := str(int(lab.get("week", 0)))
			if not votes.has(wk):
				votes[wk] = {"mutator": str(lab.get("mutator", "")), "keep": 0, "change": 0, "drop": 0}
			votes[wk][v] = int(votes[wk].get(v, 0)) + 1
			profile.data["lab_votes"] = votes
			profile.save()
			var lab_rec: Dictionary = lab.duplicate()
			lab_rec["vote"] = v
			Telemetry.amend(str(summary.get("telemetry_path", "")), {"lab": lab_rec})
			for bb in buttons:
				(bb as Button).disabled = true
			done.text = "  Vote recorded: %s. Results show on the Play screen next week." % v)
		buttons.append(b)
		row.add_child(b)
	row.add_child(done)
	return row


## Playtest feedback (U11): 1-5 rating plus free text, saved into this match's telemetry record.
func _feedback_row(path: String) -> Control:
	var row := HBoxContainer.new()
	row.add_child(UITheme.label("Playtest feedback  ", 15, UITheme.GOLD))
	var rating := OptionButton.new()
	for i in range(1, 6):
		rating.add_item("%d / 5" % i, i)
	rating.select(2)
	row.add_child(rating)
	var text := LineEdit.new()
	text.placeholder_text = "What felt good or bad this match?"
	text.custom_minimum_size.x = 560
	text.max_length = 300
	row.add_child(text)
	var done := UITheme.label("", 14, UITheme.GOLD)
	row.add_child(UITheme.button("Send", func():
		Telemetry.amend(path, {"feedback": {"rating": rating.get_selected_id(), "text": text.text.strip_edges()}})
		done.text = "  Thanks!" if path != "" else "  Saved nowhere: telemetry is off."))
	row.add_child(done)
	return row


# ================================================================ LAN multiplayer

func show_lan() -> void:
	var vb := _frame("LAN multiplayer", 900, 700)
	var info := UITheme.label("One player hosts; others join with the host's IP address (port %d).
Humans are split across teams and bots fill the empty slots. The host picks mode, map and playlist on the Play screen settings." % NetSession.PORT, 15)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.custom_minimum_size.x = 860
	vb.add_child(info)
	var status := UITheme.label("", 15, UITheme.YELLOW)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.custom_minimum_size.x = 860
	var players := RichTextLabel.new()
	players.bbcode_enabled = true
	players.custom_minimum_size = Vector2(860, 220)
	var spec_cb := CheckBox.new()
	spec_cb.text = "Join or host as a spectator (watch with the overlay, don't play)"
	var me := func() -> Dictionary:
		return {"name": str(profile.data["name"]), "class_def": profile.selected_class_def(), "levels": profile.levels(), "spectator": spec_cb.button_pressed}
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(UITheme.button("Host game", func():
		_click()
		net.host(me.call())))
	var ip := LineEdit.new()
	ip.placeholder_text = "Host IP, e.g. 192.168.1.20"
	ip.text = "127.0.0.1"
	ip.custom_minimum_size.x = 300
	hb.add_child(ip)
	hb.add_child(UITheme.button("Join", func():
		_click()
		net.join(ip.text.strip_edges(), me.call())))
	vb.add_child(spec_cb)
	vb.add_child(status)
	vb.add_child(UITheme.label("Players in lobby", 18, UITheme.GOLD))
	vb.add_child(players)
	var mode_lbl := UITheme.label("", 15)
	vb.add_child(mode_lbl)
	var refresh_mode := func():
		mode_lbl.text = "Match settings: %s on %s, %s playlist (change them on the Play screen)" % [DB.modes["modes"][_play_cfg["mode"]]["name"], DB.maps[_play_cfg["map"]]["name"], DB.modes["playlists"][_play_cfg["playlist"]]["name"]]
	refresh_mode.call()
	var start := UITheme.button("Start match (host)", func():
		_click()
		if net.is_host:
			net.start_match(_match_cfg())
		else:
			status.text = "Only the host can start the match.")
	start.custom_minimum_size.y = 48
	vb.add_child(start)
	vb.add_child(UITheme.button("Tournament helper", func(): _click(); show_tournament()))
	vb.add_child(UITheme.button("Leave / Back", func():
		_click()
		net.close()
		show_main()))
	var on_status := func(t: String):
		if is_instance_valid(status):
			status.text = t
	var on_lobby := func(list: Array):
		if not is_instance_valid(players):
			return
		var t := ""
		var cls: Array = list.filter(func(p): return not bool(p.get("spectator", false))).map(func(p): return int(p["cl"]))
		if cls.size() >= 2 and int(cls.max()) - int(cls.min()) > Matchmaker.window(0.0):
			t += "[color=#ff981f]Combat levels %d-%d: wider than the %d-level casual window. Consider a bracket playlist for even gear.[/color]\n" % [int(cls.min()), int(cls.max()), Matchmaker.window(0.0)]
		for p in list:
			t += "%s  (combat %d)%s%s
" % [p["name"], int(p["cl"]), "  [host]" if int(p["peer"]) == 1 else "", "  [spectator]" if bool(p.get("spectator", false)) else ""]
		players.text = t
	for c in net.status.get_connections():
		net.status.disconnect(c["callable"])
	for c in net.lobby_changed.get_connections():
		net.lobby_changed.disconnect(c["callable"])
	net.status.connect(on_status)
	net.lobby_changed.connect(on_lobby)
	if net.active():
		on_lobby.call(net._lobby_list() if net.is_host else [])

