extends Node3D
## Map screenshot mode (docs/ENVIRONMENT.md E1). For each map: top-down overview, the 4 corners at the default
## in-game camera, one low-angle (30 degree) view with a player behind a wall (checks the occlusion cut-out),
## one zoomed-out overview and a greyscale copy of a default-camera view. Saves art/previews/map_<id>.png.
##   godot --path . res://tools/dev/map_shots.tscn -- [--maps frostgate_ruins,ember_outpost] [--placeholder]
## Godot can't render with --headless, so a window opens and closes by itself.

const W := 640
const H := 360
const PITCH := 62.0
const DIST := 17.0

var vp: SubViewport
var cam: Camera3D
var world_root: Node3D


func _ready() -> void:
	DB.ensure_loaded()
	CharacterModel.load_shared()
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 400.0
	vp.add_child(cam)
	var args := OS.get_cmdline_user_args()
	var maps: Array = DB.maps.keys()
	var i := args.find("--maps")
	if i != -1 and i + 1 < args.size():
		maps = Array(args[i + 1].split(",", false))
	maps.sort()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/previews"))
	for id in maps:
		await _shoot_map(str(id), "--placeholder" in args)
	get_tree().quit()


func _grab() -> Image:
	for k in 4:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _view(focus: Vector3, yaw_deg: float, pitch_deg: float, dist: float) -> Image:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var p := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	cam.look_at_from_position(focus + off, focus, Vector3.UP)
	return await _grab()


func _character(team_color: Color, style: String, tier: int, pos: Vector3, yaw: float) -> CharacterModel:
	var c := CharacterModel.new()
	world_root.add_child(c)
	c.set_team_color(team_color)
	var eq := {}
	var fams: Dictionary = {"melee": {"head": "plate_helm", "body": "plate_body", "legs": "plate_legs", "feet": "plate_boots",
		"shield": "kiteshield", "weapon": "scimitar"}, "ranged": {"head": "hide_coif", "body": "hide_body",
		"legs": "hide_chaps", "feet": "hide_boots", "weapon": "shortbow"}, "magic": {"head": "robe_hat",
		"body": "robe_top", "legs": "robe_bottom", "feet": "robe_boots", "weapon": "staff"}}[style]
	for slot in fams:
		for id in CharacterModel._visuals:
			var v: Dictionary = CharacterModel._visuals[id]
			if str(v.get("family", "")) == str(fams[slot]) and int(v.get("tier", 0)) == tier and not v.has("variant"):
				eq[slot] = id
				break
	c.apply_equipment(eq)
	c.position = pos
	c.rotation.y = yaw
	return c


func _shoot_map(id: String, placeholder: bool) -> void:
	if world_root != null:
		world_root.queue_free()
		await get_tree().process_frame
	world_root = Node3D.new()
	vp.add_child(world_root)
	var m := MapGrid.from_json(DB.maps[id])
	var wv := WorldView.new()
	world_root.add_child(wv)
	wv.build(m, true, true, placeholder)
	var blue := UITheme.team_color(0, 0)
	var red := UITheme.team_color(1, 0)
	# Readability: a few players at each team's spawn.
	for team in 2:
		var sp: Array = m.spawns[team]
		for k in mini(3, sp.size()):
			var t: Vector2i = sp[k]
			_character(blue if team == 0 else red, ["melee", "ranged", "magic"][k], 1 + k * 3,
				EnvLayout.tile_center(t), PI if team == 0 else 0.0)
	# Cut-out check: the local player stands right behind a wall (camera on the wall's far side).
	var hidden := Vector2i(-1, -1)
	for y in range(2, m.h - 3):
		for x in range(2, m.w - 2):
			if m.walkable(x, y) and m.blocks_los(x, y + 1) and m.walkable(x, y + 2) and m.walkable(x, y + 3):
				hidden = Vector2i(x, y)
				break
		if hidden.x >= 0:
			break
	var me_pos := EnvLayout.tile_center(hidden)
	_character(blue, "melee", 4, me_pos, 0.0)
	RenderingServer.global_shader_parameter_set("player_pos", me_pos)
	var c := Vector3(m.w / 2.0, 0, m.h / 2.0)
	var panels: Array = []
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(m.w, m.h) * 0.62
	cam.look_at_from_position(c + Vector3(0, 120, 0.01), c, Vector3.UP)
	panels.append(await _grab())
	var a := float(m.spawns[0][0].x) + 0.5 if not (m.spawns[0] as Array).is_empty() else c.x
	var b := float(m.spawns[0][0].y) + 0.5 if not (m.spawns[0] as Array).is_empty() else c.z
	panels.append(await _view(Vector3(a, 0, b), 0.0, PITCH, DIST))
	panels.append(await _view(Vector3(10, 0, 10), 225.0, PITCH, DIST))
	panels.append(await _view(Vector3(m.w - 10, 0, m.h * 0.5), 90.0, PITCH, DIST))
	panels.append(await _view(Vector3(m.w * 0.3, 0, m.h - 12), 30.0, PITCH, DIST))
	panels.append(await _view(me_pos, 0.0, 30.0, 11.0))
	panels.append(await _view(c, 20.0, PITCH, 40.0))
	panels.append(_grey(panels[1]))
	var sheet := Image.create(W * 4, H * 2, false, Image.FORMAT_RGBA8)
	for i in panels.size():
		var im: Image = panels[i]
		sheet.blit_rect(im, Rect2i(0, 0, W, H), Vector2i((i % 4) * W, (i / 4) * H))
	var out := ProjectSettings.globalize_path("res://art/previews/map_%s%s.png" % [id, "_placeholder" if placeholder else ""])
	sheet.save_png(out)
	print("SHOT ", out)
	RenderingServer.global_shader_parameter_set("player_pos", Vector3(0, -1000, 0))


static func _grey(img: Image) -> Image:
	var g := img.duplicate() as Image
	for y in g.get_height():
		for x in g.get_width():
			var col := g.get_pixel(x, y)
			var l := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
			g.set_pixel(x, y, Color(l, l, l, 1.0))
	return g
