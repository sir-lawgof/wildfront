extends Control
## Dev-only asset viewer (ASSETS.md section 10). Shows a model, a gear item, or a full character with chosen
## gear, with an animation picker, using the in-game lighting (WorldView) and camera angle.
##
## Interactive:  godot --path . res://tools/dev/asset_viewer.tscn
## Screenshots:  godot --path . res://tools/dev/asset_viewer.tscn -- --shots <id,id,...> [--sheet] [--anims a,b|all]
##               [--loadout melee:1] [--out art/previews]
## ids: "base_body", "char:<style>:<tier>" (preset loadout), any gear item id, or any model id (props/fx).
## Godot can't render with --headless, so screenshot mode opens a window that closes itself.

const PANEL := 384
const INGAME_FOV := 42.0
const INGAME_PITCH := 62.0
const INGAME_DIST := 20.0
const GAME_W := 1600
const GAME_H := 900

var vp: SubViewport
var world: Node3D
var cam: Camera3D
var subject: Node3D
var subject_kind := ""
var character: CharacterModel
var out_dir := "res://art/previews"

var _yaw := 0.6
var _pitch := 18.0
var _dist := 4.0
var _center := Vector3(0, 0.9, 0)
var _ingame := false
var _list: ItemList
var _anim_pick: OptionButton
var _ids: Array[String] = []
var _drag := false


func _ready() -> void:
	DB.ensure_loaded()
	CharacterModel.load_shared()
	_build_world()
	var args := OS.get_cmdline_user_args()
	if "--shots" in args or "--icons" in args:
		_run_shots(args)
	else:
		_build_ui()
		show_subject("base_body")


# ---------------------------------------------------------------- world

func _build_world() -> void:
	var cont := SubViewportContainer.new()
	# Interactive: the view fills the window. Screenshot mode: the viewport keeps the exact size we set.
	cont.stretch = not ("--shots" in OS.get_cmdline_user_args() or "--icons" in OS.get_cmdline_user_args())
	cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cont)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(PANEL, PANEL)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	cont.add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	var map := MapGrid.from_json(DB.maps["frostgate_ruins"])
	var wv := WorldView.new()
	world.add_child(wv)
	wv._lighting(map.theme)
	# Floor with a tile grid for scale (1 tile = 1 unit).
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var a := Color.html(str(map.theme.get("floor", "#777777")))
	var b := Color.html(str(map.theme.get("floor2", "#707070")))
	for y in 64:
		for x in 64:
			var c := a if ((x / 8) + (y / 8)) % 2 == 0 else b
			if x % 8 == 0 or y % 8 == 0:
				c = c.darkened(0.08)
			img.set_pixel(x, y, c)
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = ImageTexture.create_from_image(img)
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fm.uv1_scale = Vector3(2, 2, 1)
	fm.roughness = 1.0
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(16, 16)
	floor_mi.mesh = pm
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	cam.make_current()


func clear_subject() -> void:
	if subject != null:
		subject.queue_free()
	subject = null
	character = null


func show_subject(id: String, loadout: Array = []) -> void:
	clear_subject()
	subject_kind = ""
	if id == "base_body" or id.begins_with("char:"):
		character = CharacterModel.new()
		character.set_team_color(CharacterModel.swatch("team.blue", Color("2f6fd6")))
		world.add_child(character)
		var eq := _preset(id.substr(5)) if id.begins_with("char:") else {}
		for it in loadout:
			var slot := str(DB.item(str(it)).get("slot", ""))
			if slot != "":
				eq[slot] = str(it)
		character.apply_equipment(eq)
		subject = character
		subject_kind = "character"
	elif not CharacterModel.visual(id).is_empty():
		var ps := CharacterModel.gear_scene(str(CharacterModel.visual(id).get("model", id)))
		if ps != null:
			subject = ps.instantiate()
			world.add_child(subject)
			subject_kind = "gear"
	else:
		for cat in ["props", "fx", "characters", "gear"]:
			var p := "res://assets/models/%s/%s.glb" % [cat, id]
			if ResourceLoader.exists(p):
				subject = (load(p) as PackedScene).instantiate()
				world.add_child(subject)
				subject_kind = "model"
				break
	if subject == null:
		push_warning("asset viewer: nothing called '%s'" % id)
		return
	_frame()
	if _anim_pick != null:
		_fill_anims()


## Preset loadouts "melee:3", "ranged:1", "magic:7" from gear_visuals families.
func _preset(spec: String) -> Dictionary:
	var parts := spec.split(":")
	var style := parts[0]
	var tier := int(parts[1]) if parts.size() > 1 else 1
	var fams: Dictionary = {
		"melee": {"head": "plate_helm", "body": "plate_body", "legs": "plate_legs", "feet": "plate_boots",
			"shield": "kiteshield", "weapon": "scimitar"},
		"ranged": {"head": "hide_coif", "body": "hide_body", "legs": "hide_chaps", "feet": "hide_boots",
			"hands": "hide_vambraces", "weapon": "shortbow"},
		"magic": {"head": "robe_hat", "body": "robe_top", "legs": "robe_bottom", "feet": "robe_boots",
			"hands": "robe_gloves", "weapon": "staff"},
	}.get(style, {})
	var eq := {}
	var vis: Dictionary = CharacterModel._visuals
	for slot in fams:
		for id in vis:
			var v: Dictionary = vis[id]
			if str(v.get("family", "")) == str(fams[slot]) and int(v.get("tier", 0)) == tier and not v.has("variant"):
				eq[slot] = id
				break
	return eq


func _subject_aabb() -> AABB:
	var box := AABB()
	var first := true
	for n in subject.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var g := vi.global_transform * vi.get_aabb()
		box = g if first else box.merge(g)
		first = false
	if character != null:
		box = box.merge(AABB(Vector3(-0.45, 0, -0.45), Vector3(0.9, 1.9, 0.9)))
	return box


func _frame() -> void:
	var box := _subject_aabb()
	_center = box.get_center()
	var r := maxf(0.25, box.size.length() * 0.5)
	_dist = r / sin(deg_to_rad(cam.fov * 0.5)) * 1.05
	_place_camera()


func _place_camera() -> void:
	if _ingame:
		cam.fov = INGAME_FOV
		var pr := deg_to_rad(INGAME_PITCH)
		var off := Vector3(sin(_yaw) * cos(pr), sin(pr), cos(_yaw) * cos(pr)) * INGAME_DIST
		var focus := Vector3(_center.x, 0.0, _center.z)
		cam.look_at_from_position(focus + off, focus, Vector3.UP)
		return
	cam.fov = 30.0
	var p := deg_to_rad(_pitch)
	var off2 := Vector3(sin(_yaw) * cos(p), sin(p), cos(_yaw) * cos(p)) * _dist
	cam.look_at_from_position(_center + off2, _center, Vector3.UP)


# ---------------------------------------------------------------- interactive UI

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.custom_minimum_size = Vector2(300, 860)
	add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var lbl := Label.new()
	lbl.text = "Asset viewer — drag to orbit, wheel to zoom"
	vb.add_child(lbl)
	_anim_pick = OptionButton.new()
	_anim_pick.item_selected.connect(func(i: int) -> void:
		if character != null:
			var clip := _anim_pick.get_item_text(i)
			character.tree.active = false
			character.anim.play(clip))
	vb.add_child(_anim_pick)
	var ig := CheckBox.new()
	ig.text = "In-game camera"
	ig.toggled.connect(func(on: bool) -> void:
		_ingame = on
		_place_camera())
	vb.add_child(ig)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_list)
	_ids = ["base_body"]
	for s in ["melee", "ranged", "magic"]:
		for t in range(1, 8):
			_ids.append("char:%s:%d" % [s, t])
	var gear: Array = CharacterModel._visuals.keys()
	gear.sort()
	for id in gear:
		_ids.append(str(id))
	for id in _ids:
		_list.add_item(id)
	_list.item_selected.connect(func(i: int) -> void: show_subject(_ids[i]))
	vp.size = Vector2i(GAME_W, GAME_H)


func _fill_anims() -> void:
	_anim_pick.clear()
	if character == null or character.anim == null:
		return
	var names: Array = character.anim.get_animation_list()
	names.sort()
	for n in names:
		_anim_pick.add_item(str(n))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist *= 0.9
			_place_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist *= 1.1
			_place_camera()
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.01
		_pitch = clampf(_pitch + mm.relative.y * 0.3, -10.0, 85.0)
		_place_camera()


# ---------------------------------------------------------------- screenshot mode

func _arg(args: PackedStringArray, name: String, def: String = "") -> String:
	var i := args.find(name)
	return args[i + 1] if i != -1 and i + 1 < args.size() else def


func _run_shots(args: PackedStringArray) -> void:
	out_dir = _arg(args, "--out", out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	if "--icons" in args:
		await _render_icons()
		get_tree().quit()
		return
	var ids := _arg(args, "--shots").split(",", false)
	var anims := _arg(args, "--anims")
	var loadout := _arg(args, "--loadout")
	for id in ids:
		await _shoot_asset(id)
		if "--sheet" in args:
			await _shoot_tier_sheet(id)
	if anims != "":
		var clips: Array = []
		show_subject("char:" + loadout if loadout != "" else "base_body")
		if anims == "all":
			clips = character.anim.get_animation_list()
		else:
			clips = Array(anims.split(",", false))
		for c in clips:
			await _shoot_anim_strip(str(c), loadout)
	get_tree().quit()


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> void:
	var p := ProjectSettings.globalize_path(out_dir.path_join(file))
	img.save_png(p)
	print("SHOT ", p)


func _view(yaw_deg: float, pitch_deg: float) -> Image:
	_ingame = false
	vp.size = Vector2i(PANEL, PANEL)
	_yaw = deg_to_rad(yaw_deg)
	_pitch = pitch_deg
	_frame()
	return await _grab()


## In-game camera at full game resolution, cropped around the subject and zoomed 1.5x (nearest) so
## readability at real size can be judged.
func _ingame_view(yaw_deg: float = 0.0) -> Image:
	_ingame = true
	vp.size = Vector2i(GAME_W, GAME_H)
	_yaw = deg_to_rad(yaw_deg)
	_frame()
	var img := await _grab()
	var sp := cam.unproject_position(_center)
	var crop := 256
	var r := Rect2i(int(sp.x) - crop / 2, int(sp.y) - crop / 2, crop, crop).intersection(Rect2i(0, 0, GAME_W, GAME_H))
	var out := img.get_region(r)
	out.resize(PANEL, PANEL, Image.INTERPOLATE_NEAREST)
	_ingame = false
	return out


func _row(images: Array, w: int = PANEL, h: int = PANEL) -> Image:
	var out := Image.create(w * images.size(), h, false, Image.FORMAT_RGBA8)
	for i in images.size():
		var im: Image = images[i]
		if im.get_width() != w or im.get_height() != h:
			im.resize(w, h, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	return out


func _stack(rows: Array) -> Image:
	var w := 0
	var h := 0
	for r in rows:
		w = maxi(w, (r as Image).get_width())
		h += (r as Image).get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.1, 0.1, 0.1))
	var y := 0
	for r in rows:
		var im: Image = r
		out.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(0, y))
		y += im.get_height()
	return out


static func greyscale(img: Image) -> Image:
	var g := img.duplicate() as Image
	for y in g.get_height():
		for x in g.get_width():
			var c := g.get_pixel(x, y)
			var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			g.set_pixel(x, y, Color(l, l, l, c.a))
	return g


## One image per asset: front, back, left side, three-quarter, in-game (crop). Gear is also shown worn.
func _shoot_asset(id: String) -> void:
	show_subject(id)
	if subject == null:
		print("FAIL no asset ", id)
		return
	var row := [await _view(0, 12), await _view(180, 12), await _view(90, 8), await _view(35, 24)]
	var rows := [_row(row)]
	if subject_kind == "gear":
		var slot := str(DB.item(id).get("slot", ""))
		var worn := [id]
		if slot == "weapon" or slot == "shield":
			worn = [id]
		show_subject("base_body", worn)
		rows.append(_row([await _view(0, 12), await _view(180, 12), await _view(90, 8), await _view(35, 24),
			await _ingame_view(0)]))
	else:
		rows[0] = _row(row + [await _ingame_view(0)])
	_save(_stack(rows), "%s.png" % id.replace(":", "_"))


## All tiers of an item family side by side (alone and worn), plus a greyscale copy.
func _shoot_tier_sheet(id: String) -> void:
	var v := CharacterModel.visual(id)
	var fam := str(v.get("family", ""))
	if fam == "" and id.begins_with("char:"):
		var style := id.split(":")[1]
		var ims: Array = []
		var ig: Array = []
		for t in range(1, 8):
			show_subject("char:%s:%d" % [style, t])
			ims.append(await _view(30, 14))
			ig.append(await _ingame_view(0))
		var sheet := _stack([_row(ims), _row(ig)])
		_save(sheet, "tiers_%s.png" % style)
		_save(greyscale(sheet), "tiers_%s_grey.png" % style)
		return
	if fam == "":
		return
	var by_tier := {}
	for other in CharacterModel._visuals:
		var ov: Dictionary = CharacterModel._visuals[other]
		if str(ov.get("family", "")) == fam and not ov.has("variant"):
			by_tier[int(ov.get("tier", 0))] = str(other)
	var tiers := by_tier.keys()
	tiers.sort()
	var alone: Array = []
	var worn: Array = []
	for t in tiers:
		show_subject(by_tier[t])
		alone.append(await _view(35, 20))
		show_subject("base_body", [by_tier[t]])
		worn.append(await _view(30, 14))
	var sheet2 := _stack([_row(alone), _row(worn)])
	_save(sheet2, "tiers_%s.png" % fam)
	_save(greyscale(sheet2), "tiers_%s_grey.png" % fam)


## Eight evenly spaced frames of a clip from a three-quarter side view (+ impact frame marked by order).
func _shoot_anim_strip(clip: String, loadout: String) -> void:
	if character == null or not character.anim.has_animation(clip):
		print("FAIL no clip ", clip)
		return
	var a := character.anim.get_animation(clip)
	var frames: Array = []
	_ingame = false
	vp.size = Vector2i(PANEL, PANEL)
	_yaw = deg_to_rad(65)
	_pitch = 10.0
	_center = Vector3(0, 0.95, 0)
	_dist = 1.35 / sin(deg_to_rad(15)) * 1.0
	_place_camera()
	for i in 8:
		var t := a.length * float(i) / 7.0
		character.pose_at(clip, t)
		frames.append(await _grab())
	var fname := "anim_%s%s.png" % [clip, ("_" + loadout.replace(":", "")) if loadout != "" else ""]
	_save(_row(frames, 256, 256), fname)


# ---------------------------------------------------------------- icons (A6)

func _render_icons() -> void:
	pass
