class_name MatchView
extends Node3D
## Client side of a match. Renders snapshots from the MatchServer and turns clicks and
## hotkeys into intents. It never changes game state itself (GDD 11).

signal finished(summary: Dictionary)

var profile: Profile
var sfx: Sfx
var server: Node  ## MatchServer (local/host) or RemoteLink (LAN client)
var map: MapGrid
var world: WorldView
var hud: Hud
var camera: Camera3D
var actors: Dictionary = {}
var snap: Dictionary = {}
var my_id: int = -1
var my_team: int = 0
var ffa: bool = false
var config: Dictionary = {}

var cam_yaw: float = 0.0
var cam_pitch: float = 62.0
var cam_dist: float = 17.0
var _cam_focus: Vector3 = Vector3.ZERO
var _dragging: bool = false
var spell_target: String = ""
var streak_target: String = ""
var _projectiles: Array = []
## Presentation timing (ASSETS.md 9): seconds until an attacker's clip reaches its impact/release frame.
var _melee_delay: Dictionary = {}   ## target id -> delay for this tick's melee hitsplats
var _launch_delay: Dictionary = {}  ## attacker id -> delay before its projectile leaves
var _perf_log: bool = "--perf" in OS.get_cmdline_user_args()
var _perf_t: float = 0.0
var _over_timer: float = -1.0
var _prev_prayers: Array = []
var _popup: PopupMenu
var _popup_actions: Array = []
var _done: bool = false


func start(cfg: Dictionary, p: Profile, s: Sfx, link: Node = null) -> void:
	profile = p
	sfx = s
	config = cfg
	map = MapGrid.from_json(DB.maps[str(cfg["map"])])
	world = WorldView.new()
	add_child(world)
	world.build(map, bool(profile.setting("show_tile_grid")), str(DB.modes["modes"][str(cfg["mode"])].get("type", "")) == "domination",
		profile.setting("placeholder_map_art") == true)
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.far = 300.0
	add_child(camera)
	camera.make_current()
	_popup = PopupMenu.new()
	_popup.theme = UITheme.get_theme()
	_popup.id_pressed.connect(_on_popup)
	add_child(_popup)
	if link == null:
		var local := MatchServer.new()
		local.cfg = cfg
		add_child(local)
		server = local
	else:
		server = link
	server.ticked.connect(_on_tick)
	server.summary_ready.connect(_on_summary)
	server.begin()


# ================================================================ snapshots

func _on_tick(s: Dictionary) -> void:
	snap = s
	var me: Dictionary = s.get("me", {})
	if hud == null:
		my_id = int(me.get("id", -1))
		my_team = int(me.get("team", 0))
		ffa = str(s.get("mode_type", "")) == "ffa"
		world.set_viewer_team(my_team, ffa)
		hud = Hud.new()
		add_child(hud)
		hud.setup(profile, sfx, s, map)
		hud.intent.connect(_send)
		hud.spell_target_mode.connect(func(sid): _begin_spell_target(sid))
		hud.leave_requested.connect(_leave)
		hud.class_change.connect(_on_class_change)
		hud.streak_requested.connect(_use_streak)
		var mypos: Vector2i = me.get("pos", Vector2i(map.w / 2, map.h / 2))
		_cam_focus = WorldView.tile_to_world(mypos)
		cam_yaw = 0.0 if my_team == 0 else PI
	_sync_actors(s)
	_melee_delay.clear()
	_launch_delay.clear()
	for e in s.get("events", []):
		_on_event(e)
	if OS.get_cmdline_user_args().has("--autofight"):
		_dev_autofight(s)
	if OS.get_cmdline_user_args().has("--trace") and int(s["tick"]) % 50 == 0:
		print("[trace] tick %d phase %s scores %s me hp %s actors %d" % [int(s["tick"]), s["phase"], str(s["scores"]), str(me.get("hp", "-")), actors.size()])
	var prs: Array = me.get("prayers", [])
	if prs.size() > _prev_prayers.size():
		sfx.play("prayer_on", 0.5)
	elif prs.size() < _prev_prayers.size():
		sfx.play("prayer_off", 0.5)
	_prev_prayers = prs.duplicate()
	if bool(profile.setting("tick_sound")):
		sfx.play("tick", 0.35)
	if str(s.get("phase", "")) == "pre" and int(s.get("phase_ticks", 0)) % 2 == 0 and int(s.get("phase_ticks", 0)) <= 8:
		sfx.play("countdown", 0.5)
	hud.update(s)
	world.update_objectives(s.get("objectives", []), my_team)
	world.show_meteors(s.get("meteors", []), int(s.get("tick", 0)))
	world.show_traps(s.get("traps", []))
	if str(s.get("phase", "")) == "over" and _over_timer < 0.0:
		_over_timer = 3.5
		var w := int(s.get("result", {}).get("winner", -1))
		var mine := my_team
		hud.flash_center("VICTORY" if w == mine else ("DRAW" if w < 0 else "DEFEAT"), "Match over", 10.0)
		sfx.play("level_up" if w == mine else "death")


## Dev/test helper: the local player attacks the nearest enemy (used for screenshots).
func _dev_autofight(s: Dictionary) -> void:
	var me: Dictionary = s.get("me", {})
	if me.is_empty() or bool(me.get("dead", false)) or int(me.get("target", -1)) != -1:
		return
	var best := -1
	var best_d := 9999
	for f in s.get("fighters", []):
		if bool(f["dead"]) or int(f["id"]) == my_id or (not ffa and int(f["team"]) == my_team):
			continue
		var d := MapGrid.chebyshev(f["pos"], me["pos"])
		if d < best_d:
			best_d = d
			best = int(f["id"])
	if best != -1:
		_send({"type": "attack", "target": best})
		_send({"type": "prayer", "id": "ward_blades"}) if not (me.get("prayers", []) as Array).has("ward_blades") else null


func _sync_actors(s: Dictionary) -> void:
	var seen := {}
	for f in s.get("fighters", []):
		var fid := int(f["id"])
		seen[fid] = true
		var a: ActorView = actors.get(fid)
		if a == null:
			a = ActorView.new()
			add_child(a)
			a.setup(f, my_team, fid == my_id, ffa)
			actors[fid] = a
		a.apply(f)
		var tgt := int(f.get("target", -1))
		if tgt != -1 and actors.has(tgt):
			a.face((actors[tgt] as ActorView).position)
	for fid in actors.keys():
		if not seen.has(fid):
			(actors[fid] as Node).queue_free()
			actors.erase(fid)


func _on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"attack":
			var a: ActorView = actors.get(int(e["id"]))
			var t: ActorView = actors.get(int(e["target"]))
			if a and t:
				var impact := a.play_attack(str(e["style"]), t.position, bool(e.get("spec", false)), str(e.get("spell", "")))
				if str(e["style"]) == "melee":
					_melee_delay[int(e["target"])] = impact
				else:
					_launch_delay[int(e["id"])] = impact
				var st := str(e["style"])
				var near := a.position.distance_to(_cam_focus) < 25.0
				if near:
					sfx.play("melee" if st == "melee" else ("arrow" if st == "ranged" else "cast"), 0.45 if int(e["id"]) != my_id else 0.8)
		"projectile":
			_spawn_projectile(e)
		"splat":
			var t: ActorView = actors.get(int(e["target"]))
			if t:
				var kind := str(e.get("kind", "hit"))
				var delay := float(_melee_delay.get(int(e["target"]), 0.0)) if str(e.get("style", "")) == "melee" else 0.0
				if delay > 0.01:
					get_tree().create_timer(delay).timeout.connect(_show_splat.bind(int(e["target"]), int(e["amount"]), kind))
				else:
					_show_splat(int(e["target"]), int(e["amount"]), kind)
				if int(e["target"]) == my_id or t.position.distance_to(_cam_focus) < 14.0:
					sfx.play("hit" if kind == "hit" else ("block" if kind == "block" else "drink"), 0.6)
		"splash":
			var t: ActorView = actors.get(int(e["target"]))
			if t and t.position.distance_to(_cam_focus) < 20.0:
				sfx.play("splash", 0.5)
		"fx":
			match str(e.get("fx", "")):
				"freeze":
					sfx.play("freeze", 0.7)
				"spec":
					sfx.play("spec", 0.6 if int(e["id"]) != my_id else 1.0)
				"meteor_impact":
					sfx.play("meteor", 0.9)
				"rebuke_hit":
					sfx.play("block", 1.0, 0.6)
		"consume":
			var eater: ActorView = actors.get(int(e["id"]))
			if eater:
				var food := str(DB.item(str(e["item"])).get("kind", "")) == "food"
				eater.play_action("eat" if food else "drink")
			if int(e["id"]) == my_id:
				var it := DB.item(str(e["item"]))
				sfx.play("eat" if str(it.get("kind", "")) == "food" else "drink", 0.7)


func _show_splat(target: int, amount: int, kind: String) -> void:
	var t: ActorView = actors.get(target)
	if t == null:
		return
	t.add_splat(amount, kind)
	if kind == "block":
		t.play_action("block")
	elif kind == "hit" and amount > 0:
		t.hit_flash()


## Generated projectile model for arrows/bolts/knives (the attacker's ammo or weapon), or null.
func _projectile_model(a: ActorView, kind: String) -> Node3D:
	if not CharacterModel.available():
		return null
	var eq: Dictionary = a.pub.get("eq", {})
	var id := ""
	match kind:
		"arrow":
			id = str(eq.get("ammo", "")) if str(eq.get("ammo", "")).ends_with("arrows") else "bronze_arrows"
		"bolt":
			id = str(eq.get("ammo", "")) if str(eq.get("ammo", "")).ends_with("bolts") else "bronze_bolts"
		"knife":
			id = str(eq.get("weapon", ""))
	var v := CharacterModel.visual(id)
	if v.is_empty():
		return null
	var ps := CharacterModel.gear_scene(str(v.get("model", id)))
	return ps.instantiate() if ps != null else null


func _spawn_projectile(e: Dictionary) -> void:
	var a: ActorView = actors.get(int(e["from"]))
	var t: ActorView = actors.get(int(e["to"]))
	if a == null or t == null:
		return
	var kind := str(e.get("kind", "arrow"))
	var launch := float(_launch_delay.get(int(e["from"]), 0.0))
	var flight := maxf(0.15, (int(e["land"]) - int(e["start"])) * 0.6 - launch)
	var model := _projectile_model(a, kind) if kind in ["arrow", "bolt", "knife"] else null
	if model != null:
		model.visible = false
		add_child(model)
		_projectiles.append({"node": model, "from": a.position + Vector3(0, 1.2, 0), "target": int(e["to"]), "t": -launch,
			"dur": flight, "arc": kind in ["arrow", "knife"], "model": true})
		return
	var mi := MeshInstance3D.new()
	var c := Icons.family_color(kind)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	if kind in ["arrow", "bolt", "knife"]:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 0.6 if kind == "arrow" else 0.35)
		mi.mesh = bm
	else:
		var sm := SphereMesh.new()
		var big := kind in ["eruption", "storm", "guardian"]
		sm.radius = 0.22 if big else 0.14
		sm.height = sm.radius * 2
		mi.mesh = sm
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	add_child(mi)
	mi.visible = false
	_projectiles.append({"node": mi, "from": a.position + Vector3(0, 1.2, 0), "target": int(e["to"]), "t": -launch, "dur": flight, "arc": kind in ["arrow", "knife"]})


func _process(delta: float) -> void:
	if server == null:
		return
	var prog: float = server.tick_progress() if server.running else 1.0
	for a in actors.values():
		(a as ActorView).interpolate(prog)
	for p in _projectiles.duplicate():
		p["t"] = float(p["t"]) + delta
		var nd: Node3D = p["node"]
		if float(p["t"]) < 0.0:
			continue  # waiting for the attacker's release frame
		nd.visible = true
		var t: ActorView = actors.get(int(p["target"]))
		var k := clampf(float(p["t"]) / float(p["dur"]), 0.0, 1.0)
		if t == null or k >= 1.0:
			nd.queue_free()
			_projectiles.erase(p)
			continue
		var to := t.position + Vector3(0, 1.1, 0)
		var pos := (p["from"] as Vector3).lerp(to, k)
		if bool(p["arc"]):
			pos.y += sin(k * PI) * 1.0
		if pos.distance_to(nd.position) > 0.001 and nd.position != Vector3.ZERO:
			nd.look_at_from_position(pos, pos + (pos - nd.position), Vector3.UP, bool(p.get("model", false)))
		else:
			nd.position = pos
	_update_camera(delta)
	world.follow(_cam_focus)
	# Occlusion cut-out (env.gdshader): walls between the camera and the local player dither away.
	var me_view: ActorView = actors.get(my_id)
	var pp := me_view.position if me_view != null and me_view.visible else Vector3(0, -1000, 0)
	RenderingServer.global_shader_parameter_set("player_pos", pp)
	if _perf_log:
		_perf_t += delta
		if _perf_t >= 5.0:
			_perf_t = 0.0
			print("PERF fps=%d process_ms=%.1f draw_calls=%d primitives=%d objects=%d" % [Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
			var vp := get_viewport()
			print("PERF split: 3d=%d shadow=%d canvas_2d=%d" % [
				vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
				vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
				vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	_update_hover()
	if _over_timer > 0.0:
		_over_timer -= delta
		if _over_timer <= 0.0:
			_finish(false)


func _update_camera(delta: float) -> void:
	if Input.is_key_pressed(KEY_LEFT):
		cam_yaw += delta * 2.2
	if Input.is_key_pressed(KEY_RIGHT):
		cam_yaw -= delta * 2.2
	if Input.is_key_pressed(KEY_UP):
		cam_pitch = clampf(cam_pitch + delta * 40.0, 30.0, 85.0)
	if Input.is_key_pressed(KEY_DOWN):
		cam_pitch = clampf(cam_pitch - delta * 40.0, 30.0, 85.0)
	var me: ActorView = actors.get(my_id)
	if me != null:
		_cam_focus = _cam_focus.lerp(me.position, clampf(delta * 8.0, 0.0, 1.0))
	var pr := deg_to_rad(cam_pitch)
	var off := Vector3(sin(cam_yaw) * cos(pr), sin(pr), cos(cam_yaw) * cos(pr)) * cam_dist
	camera.position = _cam_focus + off
	camera.look_at(_cam_focus + Vector3(0, 0.8, 0), Vector3.UP)
	if hud:
		hud.minimap.cam_yaw = cam_yaw


# ================================================================ input

func _send(intent: Dictionary) -> void:
	server.submit(intent)


func _pick_actor(mouse: Vector2) -> ActorView:
	var best: ActorView = null
	var best_d := 38.0 * (17.0 / cam_dist)
	for a in actors.values():
		var av: ActorView = a
		if not av.visible or bool(av.pub.get("dead", false)):
			continue
		var wp := av.global_position + Vector3(0, 1.0, 0)
		if camera.is_position_behind(wp):
			continue
		var sp := camera.unproject_position(wp)
		var d := sp.distance_to(mouse)
		if d < best_d:
			best_d = d
			best = av
	return best


func _pick_tile(mouse: Vector2) -> Vector2i:
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.y) < 1e-4:
		return Vector2i(-1, -1)
	var t := -from.y / dir.y
	var hit := from + dir * t
	return Vector2i(int(floor(hit.x)), int(floor(hit.z)))


func _is_enemy(a: ActorView) -> bool:
	if a == null or a.fid == my_id:
		return false
	return ffa or a.team != my_team


func _unhandled_input(event: InputEvent) -> void:
	if hud == null or _done:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_dist = clampf(cam_dist - 1.2, 7.0, 34.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_dist = clampf(cam_dist + 1.2, 7.0, 34.0)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_left_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_right_click(mb.position)
	elif event is InputEventMouseMotion and _dragging:
		cam_yaw -= (event as InputEventMouseMotion).relative.x * 0.008
		cam_pitch = clampf(cam_pitch + (event as InputEventMouseMotion).relative.y * 0.2, 30.0, 85.0)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_TAB:
			hud.show_scoreboard(k.pressed)
			get_viewport().set_input_as_handled()
			return
		if not k.pressed or k.echo:
			return
		_hotkey(k.keycode)


func _left_click(pos: Vector2) -> void:
	if streak_target != "":
		var tile := _pick_tile(pos)
		if map.in_bounds(tile.x, tile.y):
			_send({"type": "streak", "id": streak_target, "x": tile.x, "y": tile.y})
		streak_target = ""
		hud.set_prompt("")
		return
	var a := _pick_actor(pos)
	if spell_target != "":
		if _is_enemy(a):
			_send({"type": "cast", "spell": spell_target, "target": a.fid})
		spell_target = ""
		hud.set_prompt("")
		return
	if _is_enemy(a):
		_send({"type": "attack", "target": a.fid})
		return
	var tile := _pick_tile(pos)
	if map.in_bounds(tile.x, tile.y):
		_send({"type": "move", "x": tile.x, "y": tile.y})
		_click_marker(tile)


func _click_marker(tile: Vector2i) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.8, 0.8)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 0, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = WorldView.tile_to_world(tile, 0.04)
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(0.2, 1, 0.2), 0.4)
	tw.tween_callback(mi.queue_free)


func _right_click(pos: Vector2) -> void:
	_popup.clear()
	_popup_actions.clear()
	var a := _pick_actor(pos)
	if a != null and a.fid != my_id:
		var nm := "%s (level-%d)" % [a.pub.get("name", "?"), int(a.pub.get("cl", 1))]
		if _is_enemy(a):
			_popup.add_item("Attack " + nm, _popup_actions.size())
			_popup_actions.append({"type": "attack", "target": a.fid})
			var me: Dictionary = snap.get("me", {})
			for sid in me.get("unlocked_spells", []):
				var sp: Dictionary = DB.spells[sid]
				if str(sp["book"]) == str(me.get("spellbook", "")) and int(sp["freeze"]) > 0:
					_popup.add_item("Cast %s -> %s" % [sp["name"], a.pub.get("name", "?")], _popup_actions.size())
					_popup_actions.append({"type": "cast", "spell": sid, "target": a.fid})
		else:
			_popup.add_item("Follow " + nm, _popup_actions.size())
			var p: Vector2i = a.pub["pos"]
			_popup_actions.append({"type": "move", "x": p.x, "y": p.y})
	var tile := _pick_tile(pos)
	if map.in_bounds(tile.x, tile.y):
		_popup.add_item("Walk here", _popup_actions.size())
		_popup_actions.append({"type": "move", "x": tile.x, "y": tile.y})
	_popup.add_item("Cancel", _popup_actions.size())
	_popup_actions.append({})
	_popup.position = Vector2i(get_viewport().get_mouse_position())
	_popup.popup()


func _on_popup(idx: int) -> void:
	if idx < _popup_actions.size() and not (_popup_actions[idx] as Dictionary).is_empty():
		_send(_popup_actions[idx])


func _update_hover() -> void:
	if hud == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var a := _pick_actor(mouse)
	var txt := ""
	if streak_target != "":
		txt = "Call %s here" % DB.streaks[streak_target]["name"]
	elif spell_target != "":
		txt = "Cast %s -> %s" % [DB.spells[spell_target]["name"], a.pub.get("name", "") if _is_enemy(a) else "..."]
	elif a != null and a.fid != my_id:
		var nm := "%s (level-%d)" % [a.pub.get("name", "?"), int(a.pub.get("cl", 1))]
		txt = ("Attack " + nm) if _is_enemy(a) else nm
	hud.set_hover(txt, mouse)


func _begin_spell_target(sid: String) -> void:
	spell_target = sid
	streak_target = ""
	hud.set_prompt("Choose a target for %s (Esc to cancel)" % DB.spells[sid]["name"])


func _use_streak(id: String) -> void:
	var me: Dictionary = snap.get("me", {})
	if not (me.get("streak_rewards", []) as Array).has(id):
		return
	if id == "meteor_strike":
		streak_target = id
		spell_target = ""
		hud.set_prompt("Click a tile for the Meteor Strike (Esc to cancel)")
	else:
		_send({"type": "streak", "id": id})


func _offensive_set() -> Array:
	var me: Dictionary = snap.get("me", {})
	var unl: Array = me.get("unlocked_prayers", [])
	var w := DB.item(str(me.get("equipment", {}).get("weapon", "")))
	var style := str(w.get("style", "melee"))
	var lists := {
		"melee": [["valor"], ["gallantry"], ["keen_focus_3", "brute_force_3"], ["keen_focus_2", "brute_force_2"], ["keen_focus_2", "brute_force_1"], ["keen_focus_1", "brute_force_1"], ["keen_focus_1"]],
		"ranged": [["precision"], ["sharp_sight_3"], ["sharp_sight_2"], ["sharp_sight_1"]],
		"magic": [["insight"], ["arcane_will_3"], ["arcane_will_2"], ["arcane_will_1"]],
	}
	for combo in lists.get(style, []):
		var ok := true
		for p in combo:
			if not unl.has(p):
				ok = false
		if ok:
			return combo
	return []


func _hotkey(code: int) -> void:
	var me: Dictionary = snap.get("me", {})
	match code:
		KEY_ESCAPE:
			if spell_target != "" or streak_target != "":
				spell_target = ""
				streak_target = ""
				hud.set_prompt("")
			else:
				hud.toggle_pause()
		KEY_F1:
			hud._show_tab("inventory")
		KEY_F2:
			hud._show_tab("equipment")
		KEY_F3:
			hud._show_tab("prayer")
		KEY_F4:
			hud._show_tab("magic")
		KEY_F5:
			hud._show_tab("combat")
		KEY_1:
			_send({"type": "prayer", "id": "ward_blades"})
		KEY_2:
			_send({"type": "prayer", "id": "ward_arrows"})
		KEY_3:
			_send({"type": "prayer", "id": "ward_spells"})
		KEY_4:
			var set_ := _offensive_set()
			var active: Array = me.get("prayers", [])
			var all_on := not set_.is_empty()
			for p in set_:
				if not active.has(p):
					all_on = false
			for p in set_:
				if all_on or not active.has(p):
					_send({"type": "prayer", "id": p})
		KEY_E:
			_send({"type": "spec"})
		KEY_Q:
			var inv: Array = me.get("inventory", [])
			var pick := -1
			for i in range(inv.size()):
				if inv[i] != null and str(DB.item(str(inv[i]["id"])).get("timer", "")) == "food":
					pick = i
					break
			if pick == -1:
				for i in range(inv.size()):
					if inv[i] != null and str(DB.item(str(inv[i]["id"])).get("timer", "")) == "combo":
						pick = i
						break
			if pick >= 0:
				_send({"type": "use", "slot": pick, "id": inv[pick]["id"]})
		KEY_Z, KEY_X, KEY_C:
			if bool(profile.setting("switch_hotkeys")):
				_send({"type": "switch_set", "style": {KEY_Z: "melee", KEY_X: "ranged", KEY_C: "magic"}[code]})
			else:
				hud.chat_line("Switch hotkeys are off (Options).")
		KEY_R:
			_send({"type": "run"})
		KEY_T:
			_send({"type": "rebuke"})
		KEY_Y:
			_send({"type": "trap"})
		KEY_5:
			_use_streak("scrying_orb")
		KEY_6:
			_use_streak("meteor_strike")
		KEY_7:
			_use_streak("guardian")
		KEY_8:
			_send({"type": "chat", "text": "Freeze them!"})
		KEY_9:
			_send({"type": "chat", "text": "Spec now!"})
		KEY_0:
			_send({"type": "chat", "text": "Falling back!"})
		KEY_SPACE:
			_send({"type": "ready"})


func _on_class_change(key: String) -> void:
	profile.data["selected_class"] = key
	profile.save()
	server.change_class(profile.class_def(key), profile.levels())


func _leave() -> void:
	_finish(true)


func _finish(forfeit: bool) -> void:
	if _done:
		return
	_done = true
	server.request_summary(forfeit)


func _on_summary(summary: Dictionary) -> void:
	_done = true
	finished.emit(summary)
