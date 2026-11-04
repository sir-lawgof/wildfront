class_name Minimap
extends Control
## Minimap (GDD 10): teammates as blue dots, known enemies as red dots. Enemies show
## when a teammate can see them, when they attack (CoD "red dot"), or during a
## Scrying Orb. Click to walk there.

signal walk_to(tile: Vector2i)

var map: MapGrid
var tex: ImageTexture
var snap: Dictionary = {}
var my_id: int = -1
var my_team: int = 0
var ffa: bool = false
var cam_yaw: float = 0.0
var recent_attackers: Dictionary = {}  ## id -> tick


func setup(m: MapGrid, px: int) -> void:
	map = m
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var img := Image.create(m.w, m.h, false, Image.FORMAT_RGBA8)
	var th := m.theme
	var floor_c := Color.html(str(th.get("floor", "#777777"))).darkened(0.25)
	for y in range(m.h):
		for x in range(m.w):
			var f := m.flags[y * m.w + x]
			var c := floor_c
			if f & MapGrid.BLOCK_LOS:
				c = Color(0.95, 0.95, 0.95)
			elif f & MapGrid.BLOCK_MOVE:
				c = Color("2f5f9f")
			img.set_pixel(x, y, c)
	tex = ImageTexture.create_from_image(img)


func update_snap(s: Dictionary, tick: int) -> void:
	snap = s
	for e in s.get("events", []):
		if str(e.get("type", "")) == "attack":
			recent_attackers[int(e["id"])] = tick
	queue_redraw()


func _to_px(p: Vector2) -> Vector2:
	return Vector2(p.x / map.w * size.x, p.y / map.h * size.y)


func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var t := Vector2i(int(event.position.x / size.x * map.w), int(event.position.y / size.y * map.h))
		walk_to.emit(t)
		accept_event()


func _visible_enemy(f: Dictionary, allies: Array, tick: int) -> bool:
	if bool(snap.get("reveal", false)):
		return true
	if tick - int(recent_attackers.get(int(f["id"]), -100)) <= 3:
		return true
	var rng := int(DB.rule("minimap_reveal_range", 14))
	for a in allies:
		var ap: Vector2i = a["pos"]
		var fp: Vector2i = f["pos"]
		if MapGrid.chebyshev(ap, fp) <= rng and map.has_los(ap, fp):
			return true
	return false


func _draw() -> void:
	if map == null:
		return
	draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), Color("1a160f"))
	draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color("5a4d3b"), false, 2.0)
	var tick := int(snap.get("tick", 0))
	var allies: Array = []
	var me: Dictionary = {}
	for f in snap.get("fighters", []):
		if bool(f["dead"]):
			continue
		if int(f["id"]) == my_id:
			me = f
		if not ffa and int(f["team"]) == my_team or int(f["id"]) == my_id:
			allies.append(f)
	# Objectives.
	var i := 0
	for o in snap.get("objectives", []):
		var p := _to_px(Vector2(o["pos"]) + Vector2(0.5, 0.5))
		var owner := int(o["owner"])
		var c := Color(0.9, 0.9, 0.9) if owner < 0 else UITheme.team_color(owner, my_team)
		draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), c)
		draw_string(get_theme_default_font(), p + Vector2(-4, 5), str(o.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
		i += 1
	for t in snap.get("traps", []):
		var tp := _to_px(Vector2(t) + Vector2(0.5, 0.5))
		draw_rect(Rect2(tp - Vector2(3, 3), Vector2(6, 6)), Color("c8a040"))
	for m in snap.get("meteors", []):
		var mp := _to_px(Vector2(int(m["x"]), int(m["y"])) + Vector2(0.5, 0.5))
		var half := float(m["size"]) / 2.0 / map.w * size.x
		draw_rect(Rect2(mp - Vector2(half, half), Vector2(half, half) * 2), Color(1, 0.2, 0.1, 0.5))
	for f in snap.get("fighters", []):
		if bool(f["dead"]):
			continue
		var fid := int(f["id"])
		var p := _to_px(Vector2(f["pos"]) + Vector2(0.5, 0.5))
		if fid == my_id:
			continue
		var ally := not ffa and int(f["team"]) == my_team
		if ally:
			draw_circle(p, 3.5, Color.BLACK)
			draw_circle(p, 2.6, UITheme.team_color(my_team, my_team))
		elif _visible_enemy(f, allies, tick):
			draw_circle(p, 3.5, Color.BLACK)
			draw_circle(p, 2.6, UITheme.team_color(int(f["team"]) + 1, my_team) if ffa else UITheme.team_color(int(f["team"]), my_team))
	if not me.is_empty():
		var mp := _to_px(Vector2(me["pos"]) + Vector2(0.5, 0.5))
		draw_rect(Rect2(mp - Vector2(2.5, 2.5), Vector2(5, 5)), Color.WHITE)
		# Camera direction wedge.
		var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
		draw_line(mp, mp + fwd * 14, Color(1, 1, 1, 0.6), 1.5)
	draw_string(get_theme_default_font(), Vector2(size.x / 2 - 4, 12), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffff00"))
