class_name Menus
extends Control
## Front-end screens (GDD 10 Menus): Main menu -> Play (playlists), Barracks
## (create-a-class, unlocks, challenges, prestige, stats), Options, and the
## end-of-match scoreboard + XP summary.

signal start_match(cfg: Dictionary)
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
	for b in [["Play vs bots", show_play], ["LAN multiplayer", show_lan], ["Barracks", show_barracks], ["Options", show_options], ["Quit", func(): quit_game.emit()]]:
		var btn := UITheme.button(str(b[0]), func(): _click(); (b[1] as Callable).call())
		btn.custom_minimum_size = Vector2(0, 52)
		btn.add_theme_font_size_override("font_size", 24)
		vb.add_child(btn)
	var foot := UITheme.label("An original fan-made prototype. Not affiliated with or endorsed by Jagex or Activision.", 12, Color(0.6, 0.55, 0.45))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(foot)


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
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size.x = 500
	hb.add_child(right)
	right.add_child(UITheme.label("Map", 20, UITheme.GOLD))
	map_opt.item_selected.connect(func(i): _play_cfg["map"] = str(map_opt.get_item_metadata(i)))
	right.add_child(map_opt)
	right.add_child(UITheme.label("Playlist", 20, UITheme.GOLD))
	var pl := OptionButton.new()
	var keys: Array = DB.modes["playlists"].keys()
	for i in range(keys.size()):
		var p: Dictionary = DB.modes["playlists"][keys[i]]
		pl.add_item("%s - %s" % [p["name"], p["desc"]])
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
		var lo := Loadout.build(profile.selected_class_def(), profile.unlocked(), {"supply": "full"})
		class_desc.text = _loadout_text(lo)
	co.item_selected.connect(func(i):
		profile.data["selected_class"] = str(co.get_item_metadata(i))
		profile.save()
		show_cls.call())
	right.add_child(co)
	right.add_child(class_desc)
	show_cls.call()
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
		var cfg := _play_cfg.duplicate()
		cfg["bot_skill"] = float(profile.setting("bot_skill"))
		if bool(profile.setting("short_countdown")):
			cfg["pre_ticks"] = 5
		start_match.emit(cfg))
	go.custom_minimum_size = Vector2(0, 56)
	go.add_theme_font_size_override("font_size", 26)
	vb.add_child(go)
	vb.add_child(UITheme.button("Back", func(): _click(); show_main()))
	(mode_buttons[_play_cfg["mode"]] as Button).emit_signal("pressed")


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
	tabs.current_tab = tab_idx
	vb.add_child(UITheme.button("Back", func(): _click(); show_main()))


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
	var vb := _frame("Match results", 1240, 840)
	var won := bool(summary.get("won", false))
	var head := UITheme.label("%s  -  %s on %s%s" % ["VICTORY" if won else ("FORFEIT" if summary.get("forfeit", false) else ("DRAW" if int(summary.get("winner", -1)) < 0 and not bool(summary.get("ffa", false)) else "DEFEAT")), summary.get("mode_name", ""), summary.get("map", ""), "  (Even Ground)" if summary.get("playlist", "") == "even_ground" else ""], 24, UITheme.YELLOW if won else UITheme.RED)
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
	right.text = rt
	if not (applied.get("level_ups", []) as Array).is_empty():
		sfx.play("level_up")
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(UITheme.button("Play again", func():
		var cfg := _play_cfg.duplicate()
		cfg["bot_skill"] = float(profile.setting("bot_skill"))
		if bool(profile.setting("short_countdown")):
			cfg["pre_ticks"] = 5
		start_match.emit(cfg)))
	hb.add_child(UITheme.button("Main menu", func(): show_main()))


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
	var me := func() -> Dictionary:
		return {"name": str(profile.data["name"]), "class_def": profile.selected_class_def(), "levels": profile.levels()}
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
			var cfg := _play_cfg.duplicate()
			cfg["bot_skill"] = float(profile.setting("bot_skill"))
			if bool(profile.setting("short_countdown")):
				cfg["pre_ticks"] = 5
			net.start_match(cfg)
		else:
			status.text = "Only the host can start the match.")
	start.custom_minimum_size.y = 48
	vb.add_child(start)
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
		for p in list:
			t += "%s  (combat %d)%s
" % [p["name"], int(p["cl"]), "  [host]" if int(p["peer"]) == 1 else ""]
		players.text = t
	for c in net.status.get_connections():
		net.status.disconnect(c["callable"])
	for c in net.lobby_changed.get_connections():
		net.lobby_changed.disconnect(c["callable"])
	net.status.connect(on_status)
	net.lobby_changed.connect(on_lobby)
	if net.active():
		on_lobby.call(net._lobby_list() if net.is_host else [])

