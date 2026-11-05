class_name Hud
extends CanvasLayer
## In-match HUD (GDD 10). OSRS layer: minimap + orbs (top right), side panel with
## Combat / Inventory / Equipment / Prayer / Spellbook tabs (bottom right, F1-F5), chat
## (bottom left). CoD layer: kill feed (top left), score + timer (top centre),
## XP pop-ups, hit markers and streak prompts (centre). Sends intents via `intent`.

signal intent(data: Dictionary)
signal spell_target_mode(spell_id: String)
signal leave_requested
signal class_change(key: String)

const TABS := ["combat", "inventory", "equipment", "prayer", "magic"]
const TAB_LABELS := {"combat": "Combat (F5)", "inventory": "Inv (F1)", "equipment": "Equip (F2)", "prayer": "Prayer (F3)", "magic": "Magic (F4)"}
const EQUIP_LAYOUT := [["", "head", ""], ["cape", "neck", "ammo"], ["weapon", "body", "shield"], ["", "legs", ""], ["hands", "feet", "ring"]]

var profile: Profile
var sfx: Sfx
var snap: Dictionary = {}
var me: Dictionary = {}
var my_id: int = -1
var my_team: int = 0
var ffa: bool = false
var names: Dictionary = {}
var teams: Dictionary = {}

var root: Control
var tab: String = "inventory"
var _tab_pages: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _inv_buttons: Array = []
var _inv_labels: Array = []
var _inv_cache: Array = []
var _eq_buttons: Dictionary = {}
var _eq_cache: Dictionary = {}
var _bonus_label: Label
var _prayer_buttons: Dictionary = {}
var _prayer_points: Label
var _spell_buttons: Dictionary = {}
var _spell_book_cache: String = ""
var _magic_info: Label
var _stance_buttons: Dictionary = {}
var _spec_bar: ProgressBar
var _spec_btn: Button
var _weapon_label: Label
var _retaliate_btn: Button
var _ability_label: Label
var _streak_box: HBoxContainer
var _streak_cache: Array = []
var _class_opt: OptionButton
var orb_hp: Orb
var orb_prayer: Orb
var orb_run: Orb
var orb_spec: Orb
var minimap: Minimap
var _killfeed: VBoxContainer
var _score_label: RichTextLabel
var _obj_label: RichTextLabel
var _center: Label
var _tick_dot: ColorRect   ## U10 visual tick indicator
var _recap: RichTextLabel  ## U6 death recap, shown while dead
var _training: RichTextLabel  ## U1 Proving Grounds progress panel
var _spec_panel: RichTextLabel  ## U8 spectator overlay: every fighter's HP, prayer and special energy
var spectating: bool = false
var _side_panel: Control
var _recap_tick: int = -1
var _center_sub: Label
var _center_timer: float = 0.0
var _chat: RichTextLabel
var _popups: Control
var _hover: Label
var _prompt: Label
var _scoreboard: PanelContainer
var _scoreboard_body: RichTextLabel
var _pause: PanelContainer
var _xp_accum: int = 0
var _xp_timer: float = 0.0


func setup(p: Profile, s: Sfx, first: Dictionary, map: MapGrid) -> void:
	profile = p
	sfx = s
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	me = first.get("me", {})
	my_id = int(me.get("id", -1))
	my_team = int(me.get("team", 0))
	ffa = bool(first.get("ffa", str(first.get("mode_type", "")) == "ffa"))
	_build_side_panel()
	_build_orbs_and_minimap(map)
	_build_top()
	_build_chat()
	_build_center()
	_build_scoreboard()
	_build_pause()
	update(first)
	_show_tab("inventory")


# ================================================================ layout

func _panel(rect_pos: Vector2, rect_size: Vector2, anchor: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(anchor)
	p.size = rect_size
	p.position = rect_pos
	root.add_child(p)
	return p


func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	_side_panel = panel
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -300
	panel.offset_top = -470
	panel.offset_right = -8
	panel.offset_bottom = -8
	root.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	vb.add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.text = str(TAB_LABELS[t]).split(" ")[0]
		b.tooltip_text = TAB_LABELS[t]
		b.add_theme_font_size_override("font_size", 13)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show_tab.bind(t))
		tabs.add_child(b)
		_tab_buttons[t] = b
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(280, 420)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(stack)
	for t in TABS:
		var page := MarginContainer.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		stack.add_child(page)
		_tab_pages[t] = page
	_build_inventory(_tab_pages["inventory"])
	_build_equipment(_tab_pages["equipment"])
	_build_prayers(_tab_pages["prayer"])
	_build_magic(_tab_pages["magic"])
	_build_combat(_tab_pages["combat"])


func _show_tab(t: String) -> void:
	tab = t
	for k in _tab_pages:
		(_tab_pages[k] as Control).visible = k == t
		(_tab_buttons[k] as Button).add_theme_color_override("font_color", UITheme.YELLOW if k == t else UITheme.GOLD)
	if sfx:
		sfx.play("click", 0.4)


func _slot_button(sz: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = sz
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_stylebox_override("normal", UITheme.box(Color(0, 0, 0, 0.15), Color(0, 0, 0, 0.0), 0))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.15), 1))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(1, 1, 0, 0.15), UITheme.YELLOW, 1))
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build_inventory(page: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)
	page.add_child(grid)
	for i in range(28):
		var b := _slot_button(Vector2(64, 56))
		b.pressed.connect(_on_inv.bind(i))
		grid.add_child(b)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color("ffff00"))
		l.position = Vector2(3, 0)
		b.add_child(l)
		_inv_buttons.append(b)
		_inv_labels.append(l)
		_inv_cache.append("")


func _on_inv(i: int) -> void:
	var inv: Array = me.get("inventory", [])
	if i < inv.size() and inv[i] != null:
		intent.emit({"type": "use", "slot": i, "id": inv[i]["id"]})
		sfx.play("click", 0.5)


func _build_equipment(page: Control) -> void:
	var vb := VBoxContainer.new()
	page.add_child(vb)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	vb.add_child(grid)
	for row in EQUIP_LAYOUT:
		for s in row:
			if s == "":
				var sp := Control.new()
				sp.custom_minimum_size = Vector2(56, 48)
				grid.add_child(sp)
				continue
			var b := _slot_button(Vector2(56, 48))
			b.add_theme_stylebox_override("normal", UITheme.box(Color(0, 0, 0, 0.3), Color("1a160f"), 1))
			b.pressed.connect(func(): intent.emit({"type": "unequip", "slot": s}))
			b.tooltip_text = s.capitalize()
			grid.add_child(b)
			_eq_buttons[s] = b
	_bonus_label = UITheme.label("", 12)
	vb.add_child(_bonus_label)


func _build_prayers(page: Control) -> void:
	var vb := VBoxContainer.new()
	page.add_child(vb)
	_prayer_points = UITheme.label("Prayer: 99 / 99", 14, UITheme.GOLD)
	vb.add_child(_prayer_points)
	var grid := GridContainer.new()
	grid.columns = 5
	vb.add_child(grid)
	for pid in DB.prayer_order:
		var p: Dictionary = DB.prayers[pid]
		var b := _slot_button(Vector2(50, 46))
		b.icon = Icons.prayer(pid)
		b.tooltip_text = _prayer_tooltip(p)
		b.pressed.connect(_toggle_prayer.bind(pid))
		grid.add_child(b)
		_prayer_buttons[pid] = b
	var hint := UITheme.label("Hotkeys: 1 Blades  2 Arrows  3 Spells  4 offensive", 11, Color(0.8, 0.75, 0.6))
	vb.add_child(hint)


func _prayer_tooltip(p: Dictionary) -> String:
	var lines := [str(p["name"])]
	if p.has("protect"):
		lines.append("-40%% damage from %s attacks" % p["protect"])
	for k in p.get("mult", {}):
		lines.append("+%d%% %s" % [int(round((float(p["mult"][k]) - 1.0) * 100)), str(k).replace("_att", " accuracy").replace("_str", " strength")])
	if p.has("special"):
		lines.append({"mending": "Hitpoints regenerate twice as fast", "endurance": "Potion boosts wear off 50% slower",
			"sap": "Drains target prayer by 1/4 of your damage", "last_rites": "Below 10 HP: heal 24, prayer drops to 0",
			"reckoning": "On death, hits adjacent enemies", "devotion": "Prayer regenerates slowly"}.get(str(p["special"]), ""))
	lines.append("Unlock: %s level %d" % [str(p["track"]).capitalize(), int(p["level"])])
	return "\n".join(lines)


func _toggle_prayer(pid: String) -> void:
	intent.emit({"type": "prayer", "id": pid})


func _build_magic(page: Control) -> void:
	var vb := VBoxContainer.new()
	page.add_child(vb)
	_magic_info = UITheme.label("", 13, UITheme.GOLD)
	_magic_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_magic_info.custom_minimum_size.x = 270
	vb.add_child(_magic_info)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.name = "SpellGrid"
	vb.add_child(grid)
	var hint := UITheme.label("Staff equipped: click sets autocast.\nOtherwise: click a spell, then an enemy.", 11, Color(0.8, 0.75, 0.6))
	vb.add_child(hint)


func _rebuild_spells(book: String) -> void:
	_spell_book_cache = book
	var grid: GridContainer = (_tab_pages["magic"] as Control).find_child("SpellGrid", true, false)
	for c in grid.get_children():
		c.queue_free()
	_spell_buttons.clear()
	for sid in DB.spell_order:
		var sp: Dictionary = DB.spells[sid]
		if str(sp["book"]) != book:
			continue
		var b := _slot_button(Vector2(62, 52))
		b.icon = Icons.spell(sid)
		var tip := "%s (Magic %d)\nMax hit %d" % [sp["name"], int(sp["level"]), int(sp["max_hit"])]
		if int(sp["freeze"]) > 0:
			tip += "\nFreezes %d s" % int(round(int(sp["freeze"]) * 0.6))
		if int(sp["area"]) > 1:
			tip += "\n3x3 area"
		if sp.has("heal_pct"):
			tip += "\nHeals 25% of damage"
		if sp.has("poison"):
			tip += "\nPoisons"
		b.tooltip_text = tip
		b.pressed.connect(_on_spell.bind(sid))
		grid.add_child(b)
		_spell_buttons[sid] = b


func _on_spell(sid: String) -> void:
	var w := DB.item(str(me.get("equipment", {}).get("weapon", "")))
	if str(w.get("style", "")) == "magic":
		intent.emit({"type": "spell", "spell": sid})
	else:
		spell_target_mode.emit(sid)


func _build_combat(page: Control) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	page.add_child(vb)
	_weapon_label = UITheme.label("", 15, UITheme.YELLOW)
	vb.add_child(_weapon_label)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	for s in ["accurate", "aggressive", "defensive"]:
		var b := UITheme.button(s.capitalize(), func(): intent.emit({"type": "stance", "stance": s}))
		b.add_theme_font_size_override("font_size", 13)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = {"accurate": "+3 accuracy level", "aggressive": "+3 strength level", "defensive": "+3 defence level"}[s]
		hb.add_child(b)
		_stance_buttons[s] = b
	_retaliate_btn = UITheme.button("Auto retaliate: On", func(): intent.emit({"type": "retaliate"}))
	vb.add_child(_retaliate_btn)
	vb.add_child(UITheme.label("Special attack (E)", 13, UITheme.GOLD))
	_spec_bar = ProgressBar.new()
	_spec_bar.max_value = 100
	_spec_bar.custom_minimum_size = Vector2(260, 22)
	_spec_bar.show_percentage = true
	vb.add_child(_spec_bar)
	_spec_btn = UITheme.button("Use special", func(): intent.emit({"type": "spec"}))
	vb.add_child(_spec_btn)
	_ability_label = UITheme.label("", 12)
	_ability_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_ability_label.custom_minimum_size.x = 270
	vb.add_child(_ability_label)
	vb.add_child(UITheme.label("Kill streak rewards", 13, UITheme.GOLD))
	_streak_box = HBoxContainer.new()
	vb.add_child(_streak_box)
	vb.add_child(UITheme.label("Class for next life", 13, UITheme.GOLD))
	_class_opt = OptionButton.new()
	var classes := profile.class_list()
	for i in range(classes.size()):
		_class_opt.add_item(str(classes[i]["name"]))
		_class_opt.set_item_metadata(i, classes[i]["key"])
		if classes[i]["key"] == str(profile.data.get("selected_class", "")):
			_class_opt.select(i)
	_class_opt.item_selected.connect(func(i): class_change.emit(str(_class_opt.get_item_metadata(i))))
	vb.add_child(_class_opt)


func _build_orbs_and_minimap(map: MapGrid) -> void:
	var px := int(profile.setting("minimap_size"))
	minimap = Minimap.new()
	minimap.setup(map, px)
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -px - 12
	minimap.offset_top = 12
	minimap.offset_right = -12
	minimap.offset_bottom = 12 + px
	minimap.my_id = my_id
	minimap.my_team = my_team
	minimap.ffa = ffa
	minimap.walk_to.connect(func(t): intent.emit({"type": "move", "x": t.x, "y": t.y}))
	root.add_child(minimap)
	var vb := VBoxContainer.new()
	vb.anchor_left = 1.0
	vb.anchor_right = 1.0
	vb.offset_left = -px - 110
	vb.offset_top = 12
	vb.offset_right = -px - 20
	vb.add_theme_constant_override("separation", 4)
	root.add_child(vb)
	orb_hp = _orb(vb, Color("c81e1e"), "+")
	orb_prayer = _orb(vb, Color("2fb8c8"), "*")
	orb_run = _orb(vb, Color("d8c020"), "R")
	orb_spec = _orb(vb, Color("2fa86a"), "S")
	orb_prayer.tooltip_text = "Prayer points. Click: turn all prayers off."
	orb_run.tooltip_text = "Run energy. Click or press R to toggle run."
	orb_spec.tooltip_text = "Special attack energy. Click or press E."
	orb_prayer.clicked.connect(func(): intent.emit({"type": "prayers_off"}))
	orb_run.clicked.connect(func(): intent.emit({"type": "run"}))
	orb_spec.clicked.connect(func(): intent.emit({"type": "spec"}))


func _orb(parent: Control, c: Color, ic: String) -> Orb:
	var o := Orb.new()
	o.fill_color = c
	o.icon_text = ic
	parent.add_child(o)
	return o


func _build_top() -> void:
	_killfeed = VBoxContainer.new()
	_killfeed.position = Vector2(12, 12)
	_killfeed.custom_minimum_size = Vector2(460, 0)
	_killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_killfeed)
	var top := PanelContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -230
	top.offset_right = 230
	top.offset_top = 8
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_stylebox_override("panel", UITheme.box(Color(0.1, 0.08, 0.05, 0.75), Color("5a4d3b")))
	root.add_child(top)
	var vb := VBoxContainer.new()
	top.add_child(vb)
	_score_label = RichTextLabel.new()
	_score_label.bbcode_enabled = true
	_score_label.fit_content = true
	_score_label.scroll_active = false
	_score_label.custom_minimum_size = Vector2(440, 30)
	_score_label.add_theme_font_size_override("normal_font_size", 22)
	_score_label.add_theme_font_size_override("bold_font_size", 22)
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_score_label)
	_obj_label = RichTextLabel.new()
	_obj_label.bbcode_enabled = true
	_obj_label.fit_content = true
	_obj_label.scroll_active = false
	_obj_label.custom_minimum_size = Vector2(440, 0)
	_obj_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_obj_label)


func _build_chat() -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 8
	panel.offset_top = -200
	panel.offset_right = 520
	panel.offset_bottom = -8
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.83, 0.77, 0.62, 0.88), Color("3e3529")))
	root.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	_chat = RichTextLabel.new()
	_chat.bbcode_enabled = true
	_chat.scroll_following = true
	_chat.custom_minimum_size = Vector2(500, 148)
	_chat.add_theme_color_override("default_color", Color.BLACK)
	_chat.add_theme_font_size_override("normal_font_size", 14)
	vb.add_child(_chat)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var i := 8
	for q in ["Freeze them!", "Spec now!", "Falling back!"]:
		var b := UITheme.button("%s [%d]" % [q, i % 10], func(): intent.emit({"type": "chat", "text": q}))
		b.add_theme_font_size_override("font_size", 12)
		b.focus_mode = Control.FOCUS_NONE
		hb.add_child(b)
		i += 1
	chat_line("[color=#000080]Welcome to Wildfront.[/color] Left-click to walk or attack. Right-click for options.")


func _build_center() -> void:
	_popups = Control.new()
	_popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_popups)
	_recap = RichTextLabel.new()
	_recap.bbcode_enabled = true
	_recap.fit_content = true
	_recap.scroll_active = false
	_recap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap.anchor_left = 0.5
	_recap.anchor_right = 0.5
	_recap.anchor_top = 0.42
	_recap.offset_left = -330
	_recap.offset_right = 330
	_recap.add_theme_font_size_override("normal_font_size", 15)
	_recap.add_theme_font_size_override("mono_font_size", 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.03, 0.82)
	sb.border_color = Color("6b5b3e")
	sb.set_border_width_all(2)
	sb.set_content_margin_all(10)
	_recap.add_theme_stylebox_override("normal", sb)
	_recap.visible = false
	root.add_child(_recap)
	_spec_panel = RichTextLabel.new()
	_spec_panel.bbcode_enabled = true
	_spec_panel.fit_content = true
	_spec_panel.scroll_active = false
	_spec_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spec_panel.anchor_top = 0.24
	_spec_panel.offset_left = 10
	_spec_panel.offset_right = 470
	_spec_panel.add_theme_font_size_override("mono_font_size", 13)
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.05, 0.04, 0.03, 0.72)
	ssb.set_content_margin_all(8)
	_spec_panel.add_theme_stylebox_override("normal", ssb)
	_spec_panel.visible = false
	root.add_child(_spec_panel)
	_training = RichTextLabel.new()
	_training.bbcode_enabled = true
	_training.fit_content = true
	_training.scroll_active = false
	_training.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_training.anchor_left = 0.5
	_training.anchor_right = 0.5
	_training.offset_left = -300
	_training.offset_right = 300
	_training.offset_top = 92
	_training.add_theme_font_size_override("normal_font_size", 15)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.05, 0.04, 0.03, 0.78)
	tsb.border_color = Color("6b5b3e")
	tsb.set_border_width_all(2)
	tsb.set_content_margin_all(8)
	_training.add_theme_stylebox_override("normal", tsb)
	_training.visible = false
	root.add_child(_training)
	_tick_dot = ColorRect.new()
	_tick_dot.color = Color(1.0, 0.85, 0.25, 0.0)
	_tick_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tick_dot.anchor_left = 0.5
	_tick_dot.anchor_right = 0.5
	_tick_dot.offset_left = -9
	_tick_dot.offset_right = 9
	_tick_dot.offset_top = 64
	_tick_dot.offset_bottom = 82
	root.add_child(_tick_dot)
	_center = UITheme.label("", 44, UITheme.YELLOW)
	_center.anchor_left = 0.5
	_center.anchor_right = 0.5
	_center.anchor_top = 0.3
	_center.anchor_bottom = 0.3
	_center.offset_left = -500
	_center.offset_right = 500
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_theme_constant_override("outline_size", 8)
	_center.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(_center)
	_center_sub = UITheme.label("", 20, UITheme.CREAM)
	_center_sub.anchor_left = 0.5
	_center_sub.anchor_right = 0.5
	_center_sub.anchor_top = 0.3
	_center_sub.anchor_bottom = 0.3
	_center_sub.offset_left = -500
	_center_sub.offset_right = 500
	_center_sub.offset_top = 60
	_center_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_sub.add_theme_constant_override("outline_size", 6)
	_center_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(_center_sub)
	_prompt = UITheme.label("", 20, Color("ffd23f"))
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.72
	_prompt.anchor_bottom = 0.72
	_prompt.offset_left = -400
	_prompt.offset_right = 400
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(_prompt)
	_hover = UITheme.label("", 15, Color.WHITE)
	_hover.add_theme_constant_override("outline_size", 5)
	_hover.add_theme_color_override("font_outline_color", Color.BLACK)
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hover)


func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.anchor_left = 0.5
	_scoreboard.anchor_right = 0.5
	_scoreboard.anchor_top = 0.5
	_scoreboard.anchor_bottom = 0.5
	_scoreboard.offset_left = -380
	_scoreboard.offset_right = 380
	_scoreboard.offset_top = -260
	_scoreboard.offset_bottom = 260
	_scoreboard.visible = false
	_scoreboard.add_theme_stylebox_override("panel", UITheme.box(Color(0.1, 0.08, 0.05, 0.92), UITheme.GOLD))
	root.add_child(_scoreboard)
	_scoreboard_body = RichTextLabel.new()
	_scoreboard_body.bbcode_enabled = true
	_scoreboard_body.add_theme_font_size_override("normal_font_size", 16)
	_scoreboard_body.add_theme_font_size_override("mono_font_size", 16)
	_scoreboard.add_child(_scoreboard_body)


func _build_pause() -> void:
	_pause = PanelContainer.new()
	_pause.anchor_left = 0.5
	_pause.anchor_right = 0.5
	_pause.anchor_top = 0.5
	_pause.anchor_bottom = 0.5
	_pause.offset_left = -170
	_pause.offset_right = 170
	_pause.offset_top = -170
	_pause.offset_bottom = 170
	_pause.visible = false
	root.add_child(_pause)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	_pause.add_child(vb)
	vb.add_child(UITheme.label("Menu", 28, UITheme.GOLD))
	vb.add_child(UITheme.button("Resume", func(): _pause.visible = false))
	vb.add_child(UITheme.button("Leave match (counts as a loss)", func(): leave_requested.emit()))
	var keys := UITheme.label("Keys: 1/2/3 wards, 4 offence prayer, E spec, Q eat,\nZ/X/C melee/ranged/magic switch, V/B/N gear presets
(Shift to save), R run,\nT Rebuke, Y trap, 5/6/7 streaks, Tab scores,\narrows/middle-mouse camera, wheel zoom", 12)
	vb.add_child(keys)


func toggle_pause() -> void:
	_pause.visible = not _pause.visible


func is_paused() -> bool:
	return _pause.visible


# ================================================================ updates

func update(s: Dictionary) -> void:
	snap = s
	me = s.get("me", {})
	for f in s.get("fighters", []):
		names[int(f["id"])] = str(f["name"]) + (" [BOT]" if bool(f.get("bot", false)) else "")
		teams[int(f["id"])] = int(f["team"])
	if me.is_empty():
		if bool(s.get("spectator", false)):
			_update_spectator(s)
		return
	_update_inventory()
	_update_equipment()
	_update_prayers()
	_update_magic()
	_update_combat()
	orb_hp.set_value(int(me["hp"]), int(me["max_hp"]))
	orb_prayer.set_value(int(me["prayer"]), 99)
	orb_prayer.set_active(not (me["prayers"] as Array).is_empty())
	orb_run.set_value(int(me["run"]), 100)
	orb_run.set_active(bool(me["running"]))
	orb_spec.set_value(int(me["spec"]), 100)
	orb_spec.set_active(bool(me["spec_armed"]))
	minimap.update_snap(s, int(s["tick"]))
	_update_scores()
	_update_center()
	if _scoreboard.visible:
		_fill_scoreboard()
	for e in s.get("events", []):
		_on_event(e)


func _update_inventory() -> void:
	var inv: Array = me.get("inventory", [])
	for i in range(28):
		var e = inv[i] if i < inv.size() else null
		var key := "" if e == null else "%s:%d" % [e["id"], int(e.get("doses", 1))]
		if key == _inv_cache[i]:
			continue
		_inv_cache[i] = key
		var b: Button = _inv_buttons[i]
		var l: Label = _inv_labels[i]
		if e == null:
			b.icon = null
			b.tooltip_text = ""
			l.text = ""
		else:
			var it := DB.item(str(e["id"]))
			b.icon = Icons.item(str(e["id"]))
			var verb := "Wield" if str(it.get("slot", "")) == "weapon" else ("Wear" if str(it.get("slot", "")) != "" else ("Eat" if str(it.get("kind", "")) == "food" else "Drink"))
			b.tooltip_text = "%s %s%s" % [verb, it.get("name", "?"), _bonus_text(it)]
			l.text = "(%d)" % int(e.get("doses", 1)) if str(it.get("kind", "")) == "potion" else ""


func _bonus_text(it: Dictionary) -> String:
	var b: Dictionary = it.get("bonuses", {})
	var parts: Array = []
	for k in DB.BONUS_KEYS:
		if int(b.get(k, 0)) != 0:
			parts.append("%s %+d" % [k.replace("_", " "), int(b[k])])
	if it.has("heal"):
		parts.append("heals %d" % int(it["heal"]))
	if it.has("spec"):
		parts.append("special: %s (%d%%)" % [str(it["spec"]["id"]).replace("_", " "), int(it["spec"]["cost"])])
	if it.has("speed"):
		parts.append("speed %d ticks" % int(it["speed"]))
	return "" if parts.is_empty() else "\n" + "\n".join(parts)


func _update_equipment() -> void:
	var eq: Dictionary = me.get("equipment", {})
	if eq == _eq_cache:
		return
	_eq_cache = eq.duplicate()
	for s in _eq_buttons:
		var b: Button = _eq_buttons[s]
		var id := str(eq.get(s, ""))
		b.icon = Icons.item(id) if id != "" else null
		b.tooltip_text = s.capitalize() if id == "" else "Remove %s%s" % [DB.item(id).get("name", ""), _bonus_text(DB.item(id))]
	var bn: Dictionary = me.get("bonuses", {})
	_bonus_label.text = "Attack:  melee %+d  ranged %+d  magic %+d\nDefence: melee %+d  ranged %+d  magic %+d\nStrength: melee %+d  ranged %+d  magic dmg %+d%%\nPrayer %+d" % [
		int(bn.get("att_melee", 0)), int(bn.get("att_ranged", 0)), int(bn.get("att_magic", 0)),
		int(bn.get("def_melee", 0)), int(bn.get("def_ranged", 0)), int(bn.get("def_magic", 0)),
		int(bn.get("str_melee", 0)), int(bn.get("str_ranged", 0)), int(bn.get("dmg_magic", 0)), int(bn.get("prayer", 0))]


func _update_prayers() -> void:
	var active: Array = me.get("prayers", [])
	var unl: Array = me.get("unlocked_prayers", [])
	_prayer_points.text = "Prayer: %d / 99" % int(me["prayer"])
	for pid in _prayer_buttons:
		var b: Button = _prayer_buttons[pid]
		var on := active.has(pid)
		b.icon = Icons.prayer(pid, on)
		b.modulate = Color.WHITE if unl.has(pid) else Color(0.35, 0.35, 0.35)


func _update_magic() -> void:
	var book := str(me.get("spellbook", "elemental"))
	if book != _spell_book_cache:
		_rebuild_spells(book)
	var unl: Array = me.get("unlocked_spells", [])
	var auto := str(me.get("autocast", ""))
	for sid in _spell_buttons:
		var b: Button = _spell_buttons[sid]
		var ok := unl.has(sid)
		b.icon = Icons.spell(sid, ok)
		b.add_theme_stylebox_override("normal", UITheme.box(Color(1, 1, 0, 0.25) if sid == auto else Color(0, 0, 0, 0.15), UITheme.YELLOW if sid == auto else Color(0, 0, 0, 0), 1))
	var auto_name := str(DB.spells.get(auto, {}).get("name", "none"))
	_magic_info.text = "%s spellbook\nAutocast: %s\nFreeze casts left: %s" % [book.capitalize(), auto_name, "unlimited" if (me.get("perks", []) as Array).has("spell_satchel") else str(int(me.get("rune_casts", 30)))]


func _update_combat() -> void:
	var w := DB.item(str(me.get("equipment", {}).get("weapon", "")))
	var wname := str(w.get("name", "Unarmed"))
	_weapon_label.text = "%s  (max hit %d)" % [wname, int(me.get("max_hit", 0))]
	for s in _stance_buttons:
		(_stance_buttons[s] as Button).add_theme_color_override("font_color", UITheme.YELLOW if me.get("stance", "") == s else UITheme.GOLD)
	_retaliate_btn.text = "Auto retaliate: %s" % ("On" if bool(me.get("retaliate", true)) else "Off")
	_spec_bar.value = int(me.get("spec", 0))
	if w.has("spec"):
		_spec_btn.disabled = false
		_spec_btn.text = ("[ARMED] " if bool(me.get("spec_armed", false)) else "") + "%s (%d%%)" % [str(w["spec"]["id"]).replace("_", " ").capitalize(), int(w["spec"]["cost"])]
	else:
		_spec_btn.disabled = true
		_spec_btn.text = "No special on this weapon"
	var perks: Array = me.get("perks", [])
	var pl: Array = []
	for p in perks:
		pl.append(str(DB.perks.get(p, {}).get("name", p)))
	var ab := "Perks: " + ", ".join(pl)
	if perks.has("rebuke"):
		ab += "\nRebuke [T]: " + ("ARMED" if bool(me.get("rebuke_armed", false)) else ("ready" if int(me.get("rebuke_cd", 0)) == 0 else "%ds" % int(ceil(int(me["rebuke_cd"]) * 0.6))))
	if perks.has("snare_trap"):
		ab += "\nSnare Trap [Y]: " + ("ready" if bool(me.get("trap", false)) else "used")
	_ability_label.text = ab
	var rewards: Array = me.get("streak_rewards", [])
	if rewards != _streak_cache:
		_streak_cache = rewards.duplicate()
		for c in _streak_box.get_children():
			c.queue_free()
		if rewards.is_empty():
			_streak_box.add_child(UITheme.label("Streak: %d kills" % int(me.get("streak", 0)), 12))
		for r in rewards:
			var sd: Dictionary = DB.streaks[r]
			var b := UITheme.button("%s [%s]" % [sd["name"], sd["hotkey"]], func(): use_streak_requested(str(r)))
			b.add_theme_font_size_override("font_size", 12)
			_streak_box.add_child(b)


signal streak_requested(id: String)


func use_streak_requested(id: String) -> void:
	streak_requested.emit(id)


func _team_name(t: int) -> String:
	if spectating:
		return "Blue team" if t == 0 else "Red team"
	return "Your team" if t == my_team else "Enemy team"


func _color_hex(t: int) -> String:
	return UITheme.team_color(t, my_team, ffa and t != my_team).to_html(false)


func _update_scores() -> void:
	var scores: Array = snap.get("scores", [])
	var tl := int(snap.get("time_left", 0))
	var secs := int(tl * 0.6)
	var clock := "%d:%02d" % [secs / 60, secs % 60]
	var mt := str(snap.get("mode_type", ""))
	var txt := ""
	if ffa:
		var best_id := -1
		var best := -1
		for f in snap.get("fighters", []):
			if str(f.get("npc", "")) == "" and int(f["kills"]) > best:
				best = int(f["kills"])
				best_id = int(f["id"])
		var mine := int(scores[my_team]) if my_team < scores.size() else 0
		txt = "[center]You [b]%d[/b]   ·   Leader %s [b]%d[/b]   ·   %s   ·   to %d[/center]" % [mine, names.get(best_id, "-"), best, clock, int(snap.get("score_limit", 20))]
	elif mt == "elimination":
		var them := 1 - my_team
		txt = "[center][color=#%s]You [b]%d[/b][/color]  -  [color=#%s][b]%d[/b] Enemy[/color]   ·   Round %d   ·   %s[/center]" % [_color_hex(my_team), int(scores[my_team]), _color_hex(them), int(scores[them]), int(snap.get("round", 1)), clock]
		if spectating:
			txt = txt.replace("You [b]", "Blue [b]").replace("[/b] Enemy", "[/b] Red")
	else:
		var them := 1 - my_team
		txt = "[center][color=#%s]You [b]%d[/b][/color]  -  [color=#%s][b]%d[/b] Enemy[/color]   ·   %s   ·   to %d[/center]" % [_color_hex(my_team), int(scores[my_team]), _color_hex(them), int(scores[them]), clock, int(snap.get("score_limit", 0))]
		if spectating:
			txt = txt.replace("You [b]", "Blue [b]").replace("[/b] Enemy", "[/b] Red")
	if str(snap.get("mode_type", "")) == "training":
		txt = "[center]Proving Grounds   ·   %s[/center]" % clock
	_score_label.text = txt
	var objs: Array = snap.get("objectives", [])
	if objs.is_empty():
		_obj_label.text = ""
		_obj_label.visible = false
	else:
		_obj_label.visible = true
		var parts: Array = []
		for o in objs:
			var owner := int(o["owner"])
			var c := "dddddd" if owner < 0 else _color_hex(owner)
			var cap := ""
			if int(o["cap_team"]) >= 0:
				cap = " (%d%%)" % int(100.0 * int(o["progress"]) / 8.0)
			parts.append("[color=#%s]■ %s%s[/color]" % [c, o["name"], cap])
		_obj_label.text = "[center]" + "    ".join(parts) + "[/center]"


func _update_center() -> void:
	var phase := str(snap.get("phase", ""))
	if phase == "pre":
		var secs := int(ceil(int(snap.get("phase_ticks", 0)) * 0.6))
		_center.text = "Match starts in %d" % secs if int(snap.get("round", 1)) <= 1 else "Round %d in %d" % [int(snap.get("round", 1)), secs]
		_center_sub.text = "Set your prayers and gear.  Press Space when ready." if int(snap.get("round", 1)) <= 1 else ""
		if int(snap.get("round", 1)) <= 1 and not spectating:
			_center_sub.text += "\n" + _lobby_line()
		_center_timer = 0.0
		return
	if phase == "over":
		return
	_show_recap(me.get("recap", {}) if bool(me.get("dead", false)) else {})
	_show_training(snap.get("training", {}))
	if bool(me.get("dead", false)):
		var mode_t := str(snap.get("mode_type", ""))
		if mode_t == "elimination":
			_center.text = "Eliminated"
			_center_sub.text = "Wait for the next round."
		else:
			_center.text = "Oh dear, you are dead!"
			_center_sub.text = "Respawn in %d s. Change class in the Combat tab." % int(ceil(int(me.get("respawn", 0)) * 0.6))
		_center_timer = 0.5
		return
	if _center_timer <= 0.0:
		_center.text = ""
		_center_sub.text = ""


## U6 death recap panel: hits in the last life (style, weapon, damage, your ward; wrong wards in red) and eating.
func _show_recap(r: Dictionary) -> void:
	if r.is_empty() or (r.get("hits", []) as Array).is_empty():
		_recap.visible = false
		_recap_tick = -1
		return
	_recap.visible = true
	if int(r.get("tick", -1)) == _recap_tick:
		return
	_recap_tick = int(r.get("tick", -1))
	var t := "[b][color=#ff981f]Death recap[/color][/b]"
	if str(r.get("killer", "")) != "":
		t += "  -  killed by [b]%s[/b]" % str(r["killer"])
	t += "\n[code]%6s  %-18s %-22s %4s  %s[/code]\n" % ["when", "from", "weapon", "dmg", "your ward"]
	for h in r["hits"]:
		var style := str(h["style"])
		var col := UITheme.style_color(style).to_html(false) if DB.STYLES.has(style) else "c8c8c8"
		var ward := str(h["ward"])
		var wtxt := "-"
		if DB.STYLES.has(style):
			wtxt = ward.capitalize() if ward != "" else "none"
		var who := str(h["name"]) + (" [BOT]" if bool(h.get("bot", false)) else "")
		var line := "%5.1fs  %-18s %-22s %4s" % [-float(h["ago"]) * 0.6, who.left(18), str(h["weapon"]).left(22), "miss" if bool(h["splash"]) else str(int(h["dmg"]))]
		var wcol := "ff5040" if bool(h["wrong_ward"]) else ("7fd07f" if DB.STYLES.has(style) else "aaaaaa")
		t += "[code][color=#%s]%s[/color]  [color=#%s]%s%s[/color][/code]\n" % [col, line, wcol, wtxt, " (wrong)" if bool(h["wrong_ward"]) else ""]
	var eats: Array = r.get("eats", [])
	if not eats.is_empty():
		var parts: Array = []
		for e in eats:
			parts.append("%s %.1fs%s" % [str(e["name"]), -float(e["ago"]) * 0.6, (" (%d wasted)" % int(e["wasted"])) if int(e["wasted"]) > 0 else ""])
		t += "[color=#e8dcc0]Ate: %s[/color]\n" % ", ".join(parts)
	if int(r.get("wrong_wards", 0)) > 0:
		t += "[color=#ff8060]%d hit%s landed while you prayed the wrong ward.[/color]" % [int(r["wrong_wards"]), "" if int(r["wrong_wards"]) == 1 else "s"]
	_recap.text = t


## U3: "Your gear: tier X, lobby average: tier Y" and the lobby's combat-level range, so gear gaps are visible.
func _lobby_line() -> String:
	var mine := 0.0
	var sum := 0.0
	var n := 0
	var lo := 999
	var hi := 0
	for f in snap.get("fighters", []):
		if str(f.get("npc", "")) != "":
			continue
		var gt := float(f.get("gear_tier", 1.0))
		sum += gt
		n += 1
		lo = mini(lo, int(f["cl"]))
		hi = maxi(hi, int(f["cl"]))
		if int(f["id"]) == my_id:
			mine = gt
	if n == 0:
		return ""
	return "Your gear: tier %.1f   ·   lobby average: tier %.1f   ·   combat levels %d-%d" % [mine, sum / n, lo, hi]


## U8: spectator / replay view. Scores, minimap, kill feed and an overlay with both sides' HP, prayer and spec.
func _update_spectator(s: Dictionary) -> void:
	if not spectating:
		spectating = true
		for o in [orb_hp, orb_prayer, orb_run, orb_spec, _side_panel]:
			if o != null:
				(o as CanvasItem).visible = false
	minimap.update_snap(s, int(s["tick"]))
	_update_scores()
	if _scoreboard.visible:
		_fill_scoreboard()
	for e in s.get("events", []):
		_on_event(e)
	_spec_panel.visible = true
	var by_team := {}
	for f in s.get("fighters", []):
		if str(f.get("npc", "")) != "":
			continue
		var t := int(f["team"]) if not ffa else 0
		if not by_team.has(t):
			by_team[t] = []
		by_team[t].append(f)
	var txt := ""
	for t in by_team:
		if not ffa:
			txt += "[color=#%s][b]%s[/b][/color]\n" % [_color_hex(int(t)), _team_name(int(t))]
		for f in by_team[t]:
			var hp := int(f["hp"])
			var mx := maxi(1, int(f["max_hp"]))
			var bar := "#".repeat(int(round(10.0 * hp / mx))) + "-".repeat(10 - int(round(10.0 * hp / mx)))
			var ovh := str(f.get("ovh", ""))
			var ward := ""
			if ovh != "":
				ward = str(DB.prayers.get(ovh, {}).get("protect", ovh)).left(3)
			var name := (str(f["name"]) + (" [BOT]" if bool(f.get("bot", false)) else "")).left(16)
			var line := "%-16s %3d [%s] pr %2d sp %3d %s" % [name, hp, bar, int(f.get("prayer", 0)), int(f.get("spec", 0)), ward]
			txt += "[code][color=#%s]%s[/color][/code]\n" % ["777777" if bool(f["dead"]) else "e8dcc0", line]
	_spec_panel.text = txt


## U1 training panel: drill name, goal, progress, the latest instructor note; live stats in the dummy room.
func _show_training(t: Dictionary) -> void:
	if t.is_empty():
		_training.visible = false
		return
	_training.visible = true
	var txt := "[center][b][color=#ff981f]%s[/color][/b]" % str(t.get("name", ""))
	if str(t.get("label", "")) != "":
		txt += "  [color=#%s](%s)[/color]" % ["7fd07f" if str(t["label"]) == "learning" else "ff8060", str(t["label"])]
	txt += "[/center]\n[color=#e8dcc0]%s[/color]\n" % str(t.get("desc", ""))
	if str(t.get("progress", "")) != "":
		txt += "[b]%s[/b]\n" % str(t["progress"])
	var d: Dictionary = t.get("dummy", {})
	if not d.is_empty():
		txt += "[b]%s[/b]  accuracy [b]%d%%[/b]   max hit [b]%d[/b]   expected [b]%.2f[/b] dmg/tick   last %d hits: [b]%.2f[/b] dmg/tick\n" % [str(d["style"]).capitalize(), int(round(float(d["accuracy"]) * 100.0)), int(d["max_hit"]), float(d["expected_dpt"]), int(d["hits"]), float(d["observed_dpt"])]
	if bool(t.get("callouts", false)):
		txt += "[color=#ffd23f]Call it: 8 melee   9 ranged   0 magic[/color]\n"
	if str(t.get("note", "")) != "":
		txt += "[i]%s[/i]" % str(t["note"])
	_training.text = txt


## Flashes the tick square once (called every snapshot = every game tick when the option is on).
func pulse_tick() -> void:
	if _tick_dot == null:
		return
	_tick_dot.color.a = 0.95
	var tw := create_tween()
	tw.tween_property(_tick_dot, "color:a", 0.0, 0.45)


func flash_center(text: String, sub: String = "", secs: float = 2.0) -> void:
	_center.text = text
	_center_sub.text = sub
	_center_timer = secs


func _process(delta: float) -> void:
	if _center_timer > 0.0:
		_center_timer -= delta
		if _center_timer <= 0.0 and str(snap.get("phase", "")) == "live" and not bool(me.get("dead", false)):
			_center.text = ""
			_center_sub.text = ""
	if _xp_accum > 0:
		_xp_timer += delta
		if _xp_timer > 0.5:
			popup_xp(_xp_accum)
			_xp_accum = 0
			_xp_timer = 0.0
	for c in _popups.get_children():
		if c is Label:
			var age := float(c.get_meta("age", 0.0)) + delta
			c.set_meta("age", age)
			c.position.y -= delta * 40.0
			c.modulate.a = clampf(1.6 - age, 0.0, 1.0)
			if age > 1.6:
				c.queue_free()
	for c in _killfeed.get_children():
		var age := float(c.get_meta("age", 0.0)) + delta
		c.set_meta("age", age)
		if age > 7.0:
			c.modulate.a = clampf(8.0 - age, 0.0, 1.0)
		if age > 8.0:
			c.queue_free()


func popup_xp(amount: int) -> void:
	var l := UITheme.label("+%d" % amount, 22, Color("ffd23f"))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	var vs := root.get_viewport_rect().size
	l.position = Vector2(vs.x / 2 + 40, vs.y / 2 - 60)
	_popups.add_child(l)


func hitmarker(screen_pos: Vector2) -> void:
	var l := UITheme.label("x", 26, Color.WHITE)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.position = screen_pos - Vector2(7, 18)
	l.set_meta("age", 1.1)
	_popups.add_child(l)


func set_hover(text: String, pos: Vector2) -> void:
	_hover.text = text
	_hover.position = pos + Vector2(18, 10)


func set_prompt(text: String) -> void:
	_prompt.text = text


func chat_line(bb: String) -> void:
	_chat.append_text(bb + "\n")


func feed(bb: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.custom_minimum_size = Vector2(460, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 16)
	l.text = bb
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", UITheme.box(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(l)
	_killfeed.add_child(bg)
	while _killfeed.get_child_count() > 6:
		_killfeed.get_child(0).free()


func _name_bb(fid: int) -> String:
	if not names.has(fid):
		return "?"
	var c := "ffff00" if fid == my_id else _color_hex(int(teams.get(fid, 0)))
	return "[color=#%s]%s[/color]" % [c, names[fid]]


func _on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"kill":
			var k := int(e["killer"])
			var v := int(e["victim"])
			var weapon := str(e.get("weapon", ""))
			if k == -1 or k == v:
				feed("%s [color=#aaaaaa]died[/color]" % _name_bb(v))
			else:
				feed("%s  [color=#e8dcc0][%s][/color]  %s" % [_name_bb(k), weapon, _name_bb(v)])
			if k == my_id and v != my_id:
				sfx.play("kill")
				_xp_accum += int(DB.levels["xp"].get("kill", 100))
				flash_center("", "You killed %s" % names.get(v, "?"), 1.5)
			if v == my_id:
				sfx.play("death")
		"msg":
			chat_line("[color=#000000]%s[/color]" % str(e["text"]))
		"chat":
			var team_c := "0000a0" if int(e.get("team", -1)) == my_team and not ffa else "a00000"
			chat_line("[color=#%s]%s:[/color] [color=#0000ff]%s[/color]" % [team_c, e["name"], e["text"]])
		"streak_ready":
			if int(e["id"]) == my_id:
				var sd: Dictionary = DB.streaks[str(e["reward"])]
				flash_center(str(sd["name"]) + " ready!", "Press %s to use" % sd["hotkey"], 3.0)
				sfx.play("streak")
		"streak_used":
			var sd: Dictionary = DB.streaks.get(str(e["reward"]), {})
			var who := int(e["id"])
			chat_line("%s used [color=#800000]%s[/color]." % [_name_bb(who), sd.get("name", "?")])
			if str(e["reward"]) == "meteor_strike":
				sfx.play("streak", 0.6, 0.8)
		"first_blood":
			feed("[color=#ff8040]First blood:[/color] %s" % _name_bb(int(e["id"])))
		"capture":
			feed("%s captured obelisk %s" % ["[color=#%s]%s[/color]" % [_color_hex(int(e["team"])), _team_name(int(e["team"]))], e["name"]])
			if int(e["team"]) == my_team:
				_xp_accum += 150
		"round_end":
			var w := int(e["winner"])
			flash_center("Round won!" if w == my_team else ("Round drawn" if w < 0 else "Round lost"), "", 3.0)
			if w == my_team:
				sfx.play("level_up", 0.6)
		"phase":
			if str(e["phase"]) == "live":
				flash_center("FIGHT!", "", 1.2)
				sfx.play("go")
		"splat":
			pass


func add_damage_xp(dmg: int) -> void:
	_xp_accum += dmg * int(DB.levels["xp"].get("per_damage", 4))


func show_scoreboard(on: bool) -> void:
	_scoreboard.visible = on
	if on:
		_fill_scoreboard()


func _fill_scoreboard() -> void:
	var rows := {}
	for f in snap.get("fighters", []):
		if str(f.get("npc", "")) != "":
			continue
		var t := int(f["team"]) if not ffa else 0
		if not rows.has(t):
			rows[t] = []
		rows[t].append(f)
	var txt := "[center][b]%s[/b][/center]\n" % DB.modes["modes"].get(str(snap.get("mode", "")), {}).get("name", "")
	var order: Array = rows.keys()
	order.sort_custom(func(a, b): return int(a) == my_team and int(b) != my_team)
	for t in order:
		var list: Array = rows[t]
		list.sort_custom(func(a, b): return int(a["kills"]) * 1000 + int(a["damage"]) > int(b["kills"]) * 1000 + int(b["damage"]))
		if not ffa:
			txt += "\n[color=#%s][b]%s[/b][/color]\n" % [_color_hex(int(t)), _team_name(int(t))]
		txt += "[code]%-14s %4s %4s %4s %6s %4s %4s[/code]\n" % ["Name", "K", "D", "A", "Dmg", "Obj", "CL"]
		for f in list:
			var line := "%-14s %4s %4d %4d %4d %6d %4d %4d" % [str(f["name"]).left(14), "BOT" if bool(f.get("bot", false)) else "", int(f["kills"]), int(f["deaths"]), int(f["assists"]), int(f["damage"]), int(f["obj"]), int(f["cl"])]
			if int(f["id"]) == my_id:
				txt += "[color=#ffff00][code]%s[/code][/color]\n" % line
			else:
				txt += "[code]%s[/code]\n" % line
	_scoreboard_body.text = txt
