class_name CharacterModel
extends Node3D
## A player character built from the generated assets (ASSETS.md section 6): the shared rigid-segment base
## body, gear parts attached to bones, team colour through the palette shader, and an AnimationTree
## (locomotion state machine + one-shot actions + death).
## The model faces +Z (glTF front), so a parent rotation of atan2(dir.x, dir.z) faces it along dir.

const BASE_BODY := "res://assets/models/characters/base_body.glb"
const ANIM_LIBRARY := "res://assets/animations/character.res"
const GEAR_DIR := "res://assets/models/gear/"
const VISUALS := "res://data/art/gear_visuals.json"
const ANIM_SETS := "res://data/art/anim_sets.json"
const PALETTE_JSON := "res://assets/palette/palette.json"
const PALETTE_PNG := "res://assets/palette/palette.png"

## Game equipment slot -> gear-part slot prefix used in model files.
const SLOT_PREFIX := {"head": "helm", "body": "armour_body", "legs": "armour_legs", "feet": "boots",
	"hands": "gloves", "weapon": "weapon", "shield": "offhand", "cape": "cape"}
const HIDES := {
	"armour_body": ["chest", "spine", "upperarm_L", "upperarm_R", "forearm_L", "forearm_R"],
	"armour_legs": ["hips", "thigh_L", "thigh_R", "shin_L", "shin_R"],
	"boots": ["foot_L", "foot_R"],
	"gloves": ["hand_L", "hand_R"],
}
const XFADE := 0.15

static var _base_scene: PackedScene
static var _anim_lib: AnimationLibrary
static var _gear_scenes: Dictionary = {}
static var _visuals: Dictionary = {}
static var _sets: Dictionary = {}
static var _palette_img: Image
static var _palette_cells: Dictionary = {}

var body: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var tree: AnimationTree
var team_color: Color = Color(0.6, 0.6, 0.6)
var weapon_set: Dictionary = {}
var stance: String = "unarmed"
var dead: bool = false

var _attach: Dictionary = {}       ## bone -> BoneAttachment3D
var _body_parts: Dictionary = {}   ## bone -> MeshInstance3D (base body segment)
var _equipped: Dictionary = {}     ## game slot -> {"id", "nodes": [MeshInstance3D], "hides": [bones]}
var _recolor: Color = Color(1, 1, 1, 0)
var _loco_state: String = "idle"
var _loco: AnimationNodeStateMachine
var _action: AnimationNodeAnimation
var _flash: float = 0.0
var _hidden: Dictionary = {}       ## body bones covered by gear
var _merged: MeshInstance3D        ## all visible parts merged into one rigidly skinned mesh (one draw call)
static var _part_arrays: Dictionary = {}


# ---------------------------------------------------------------- static data

static func load_shared() -> void:
	if _base_scene != null:
		return
	_base_scene = load(BASE_BODY)
	if ResourceLoader.exists(ANIM_LIBRARY):
		_anim_lib = load(ANIM_LIBRARY)
	_visuals = _json(VISUALS).get("items", {})
	_sets = _json(ANIM_SETS)
	_palette_cells = _json(PALETTE_JSON).get("swatches", {})
	var tex: Texture2D = load(PALETTE_PNG)
	if tex != null:
		_palette_img = tex.get_image()


static func available() -> bool:
	return ResourceLoader.exists(BASE_BODY)


static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## Colour of a palette swatch as painted in palette.png (so repainting the PNG restyles teams too).
static func swatch(name: String, fallback: Color = Color.MAGENTA) -> Color:
	load_shared()
	if _palette_img == null or not _palette_cells.has(name):
		return fallback
	var c: Array = _palette_cells[name]
	return _palette_img.get_pixel(int(c[0]) * 8 + 4, int(c[1]) * 8 + 4)


static func visual(item_id: String) -> Dictionary:
	load_shared()
	return _visuals.get(item_id, {})


static func anim_sets() -> Dictionary:
	load_shared()
	return _sets


## Weapon set for an item: by item id (uniques), then weapon_type, else unarmed.
static func set_for_item(item: Dictionary) -> Dictionary:
	var sets: Dictionary = anim_sets().get("sets", {})
	var id := str(item.get("id", ""))
	if sets.has(id):
		return sets[id]
	var wt := str(item.get("weapon_type", ""))
	if sets.has(wt):
		return sets[wt]
	return sets.get("unarmed", {})


static func gear_scene(model_id: String) -> PackedScene:
	if not _gear_scenes.has(model_id):
		var p := GEAR_DIR + model_id + ".glb"
		_gear_scenes[model_id] = load(p) if ResourceLoader.exists(p) else null
	return _gear_scenes[model_id]


# ---------------------------------------------------------------- setup

func _init() -> void:
	load_shared()
	body = _base_scene.instantiate()
	add_child(body)
	skeleton = body.find_child("Skeleton3D", true, false)
	anim = body.find_child("AnimationPlayer", true, false)
	for n in skeleton.find_children("*", "BoneAttachment3D", false, false):
		_attach[(n as BoneAttachment3D).bone_name] = n
	for n in body.find_children("body__*", "MeshInstance3D", true, false):
		_body_parts[str(n.name).trim_prefix("body__")] = n
	if _anim_lib != null and anim != null:
		if anim.has_animation_library(""):
			anim.remove_animation_library("")
		anim.add_animation_library("", _anim_lib)
	_build_tree()
	set_team_color(team_color)
	set_weapon({})
	merge()


func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	var root := AnimationNodeBlendTree.new()
	_loco = AnimationNodeStateMachine.new()
	for st in ["idle", "walk", "run"]:
		var a := AnimationNodeAnimation.new()
		a.animation = st
		_loco.add_node(st, a)
	for a_name in ["idle", "walk", "run"]:
		for b_name in ["idle", "walk", "run"]:
			if a_name != b_name:
				var tr := AnimationNodeStateMachineTransition.new()
				tr.xfade_time = XFADE
				_loco.add_transition(a_name, b_name, tr)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	_loco.add_transition("Start", "idle", start)
	root.add_node("loco", _loco, Vector2(0, 0))
	root.add_node("loco_speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	_action = AnimationNodeAnimation.new()
	_action.animation = "eat"
	root.add_node("action", _action, Vector2(200, 200))
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.06
	shot.fadeout_time = 0.14
	root.add_node("oneshot", shot, Vector2(400, 0))
	var death := AnimationNodeAnimation.new()
	death.animation = "death"
	root.add_node("death", death, Vector2(400, 200))
	var life := AnimationNodeTransition.new()
	life.add_input("alive")
	life.add_input("dead")
	life.xfade_time = 0.08
	root.add_node("life", life, Vector2(600, 0))
	root.connect_node("loco_speed", 0, "loco")
	root.connect_node("oneshot", 0, "loco_speed")
	root.connect_node("oneshot", 1, "action")
	root.connect_node("life", 0, "oneshot")
	root.connect_node("life", 1, "death")
	root.connect_node("output", 0, "life")
	tree.tree_root = root
	add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	tree.root_node = tree.get_path_to(body)  # clip tracks are relative to the imported scene root
	tree.active = true
	tree.set("parameters/loco_speed/scale", 1.0)
	tree.set("parameters/life/transition_request", "alive")


# ---------------------------------------------------------------- gear

## eq: game equipment dict (slot -> item id). Applies every visible slot.
func apply_equipment(eq: Dictionary, kit_color: String = "") -> void:
	for slot in SLOT_PREFIX:
		var id := str(eq.get(slot, ""))
		var cur: Dictionary = _equipped.get(slot, {})
		if str(cur.get("id", "")) != id:
			equip(slot, id)
	_recolor = Color.html(kit_color) if kit_color != "" else Color(1, 1, 1, 0)
	if kit_color != "":
		_recolor.a = 0.85
	set_weapon(DB.item(str(eq.get("weapon", ""))) if str(eq.get("weapon", "")) != "" else {})
	merge()


func equip(slot: String, item_id: String) -> void:
	unequip(slot)
	if item_id == "":
		return
	var vis := visual(item_id)
	if vis.is_empty():
		return
	var ps := gear_scene(str(vis.get("model", item_id)))
	if ps == null:
		return
	var inst: Node3D = ps.instantiate()
	var nodes: Array = []
	var hides: Array = []
	var skel_xf := _skeleton_xf()
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := str(mi.name)
		var i := nm.find("__")
		if i <= 0:
			continue
		var prefix := nm.substr(0, i)
		var bone := nm.substr(i + 2)
		var bi := skeleton.find_bone(bone)
		if bi == -1:
			continue
		var xf := _xf_in(mi, inst)
		var rest := skeleton.get_bone_global_rest(bi)
		var in_skel := skel_xf.affine_inverse() * xf
		if bone.begins_with("socket_"):
			in_skel = Transform3D(Basis(), rest.origin) * xf  # grip-relative parts snap to the socket
		mi.owner = null
		mi.get_parent().remove_child(mi)
		_attachment(bone).add_child(mi)
		mi.transform = rest.affine_inverse() * in_skel
		mi.set_instance_shader_parameter("team_color", team_color)
		nodes.append(mi)
		if HIDES.has(prefix):
			hides.append_array(HIDES[prefix])
	if bool(vis.get("full_helm", false)):
		hides.append("head")
	inst.free()
	_equipped[slot] = {"id": item_id, "nodes": nodes, "hides": hides}
	_refresh_hidden()


func unequip(slot: String) -> void:
	var cur: Dictionary = _equipped.get(slot, {})
	for n in cur.get("nodes", []):
		(n as Node).queue_free()
	_equipped.erase(slot)
	_refresh_hidden()


func equipped_id(slot: String) -> String:
	return str((_equipped.get(slot, {}) as Dictionary).get("id", ""))


func _refresh_hidden() -> void:
	var hidden := {}
	for slot in _equipped:
		for b in (_equipped[slot] as Dictionary).get("hides", []):
			hidden[b] = true
	_hidden = hidden
	for b in _body_parts:
		(_body_parts[b] as Node3D).visible = not hidden.has(b) and _merged == null


## Merge every visible part (body segments not covered by gear, plus gear) into one skinned mesh. Each vertex is
## weighted 100% to its part's bone, so it still moves exactly like rigid segments, but a character costs one
## draw call instead of ~25. Rebuilt whenever the equipment changes. Vertex alpha marks weapon parts (ornament
## kit recolour only touches those).
func merge() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var skin := Skin.new()
	var binds := {}
	for bone in _attach:
		var att: BoneAttachment3D = _attach[bone]
		var bi := skeleton.find_bone(str(bone))
		if bi == -1:
			continue
		var rest := skeleton.get_bone_global_rest(bi)
		for child in att.get_children():
			var mi := child as MeshInstance3D
			if mi == null or mi == _merged or mi.is_queued_for_deletion() or mi.mesh == null:
				continue
			var nm := str(mi.name)
			if nm.begins_with("body__") and _hidden.has(nm.trim_prefix("body__")):
				continue
			var a := _arrays_of(mi.mesh)
			var n: int = (a[0] as PackedVector3Array).size()
			if n == 0:
				continue
			if not binds.has(bi):
				binds[bi] = skin.get_bind_count()
				skin.add_bind(bi, rest.affine_inverse())
			var xf := rest * mi.transform
			verts.append_array(xf * (a[0] as PackedVector3Array))
			normals.append_array(Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * (a[1] as PackedVector3Array))
			uvs.append_array(a[2])
			var c := Color(1, 1, 1, 1.0 if nm.begins_with("weapon__") else 0.0)
			var b := int(binds[bi])
			var start := colors.size()
			colors.resize(start + n)
			bones.resize((start + n) * 4)
			weights.resize((start + n) * 4)
			for i in n:
				colors[start + i] = c
				bones[(start + i) * 4] = b
				weights[(start + i) * 4] = 1.0
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, load("res://assets/materials/palette.tres"))
	if _merged == null:
		_merged = MeshInstance3D.new()
		_merged.name = "merged"
		skeleton.add_child(_merged)
		_merged.skeleton = _merged.get_path_to(skeleton)
		_merged.custom_aabb = AABB(Vector3(-2.2, -0.5, -2.2), Vector3(4.4, 3.2, 4.4))
	_merged.mesh = mesh
	_merged.skin = skin
	_merged.set_instance_shader_parameter("team_color", team_color)
	_merged.set_instance_shader_parameter("recolor", _recolor)
	for bone in _attach:
		for child in (_attach[bone] as Node).get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = false


static func _arrays_of(mesh: Mesh) -> Array:
	var key := mesh.get_instance_id()
	if not _part_arrays.has(key):
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var u := PackedVector2Array()
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var sn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var su: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				v.append_array(sv)
				n.append_array(sn)
				u.append_array(su)
				continue
			for i in idx:
				v.append(sv[i])
				n.append(sn[i])
				u.append(su[i])
		_part_arrays[key] = [v, n, u]
	return _part_arrays[key]


func _attachment(bone: String) -> BoneAttachment3D:
	if not _attach.has(bone):
		var a := BoneAttachment3D.new()
		a.name = bone
		a.bone_name = bone
		skeleton.add_child(a)
		_attach[bone] = a
	return _attach[bone]


func _skeleton_xf() -> Transform3D:
	return _xf_in(skeleton, body)


static func _xf_in(n: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func set_team_color(c: Color) -> void:
	team_color = c
	for n in body.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).set_instance_shader_parameter("team_color", c)


func _set_param_all(param: String, v: Variant) -> void:
	for n in body.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).set_instance_shader_parameter(param, v)


# ---------------------------------------------------------------- animation

func set_weapon(item: Dictionary) -> void:
	weapon_set = set_for_item(item)
	var st := str(weapon_set.get("stance", "unarmed"))
	if st == stance and _loco != null and (_loco.get_node("idle") as AnimationNodeAnimation).animation == StringName(str(weapon_set.get("idle", "idle"))):
		return
	stance = st
	for k in ["idle", "walk", "run"]:
		var clip := str(weapon_set.get(k, k))
		if anim != null and not anim.has_animation(clip):
			clip = k
		(_loco.get_node(k) as AnimationNodeAnimation).animation = clip


## speed in tiles per second (0 = standing). frozen stops locomotion clips entirely.
func set_locomotion(speed: float, frozen: bool = false) -> void:
	var cyc: Dictionary = anim_sets().get("cycle_tiles", {"walk": 1.2, "run": 2.0})
	var st := "idle"
	var k := 1.0
	if speed > 2.6:
		st = "run"
		k = speed * 0.8 / float(cyc.get("run", 2.0))
	elif speed > 0.05:
		st = "walk"
		k = speed * 1.0 / float(cyc.get("walk", 1.2))
	if frozen:
		st = "idle"
		k = 0.0
	tree.set("parameters/loco_speed/scale", k)
	if st != _loco_state:
		_loco_state = st
		var pb: AnimationNodeStateMachinePlayback = tree.get("parameters/loco/playback")
		if pb != null:
			pb.travel(st)


## Play a one-shot clip (attack, eat, block...). Returns the clip's impact time in seconds (0 if none).
func play_action(clip: String, speed: float = 1.0) -> float:
	if anim == null or not anim.has_animation(clip) or dead:
		return 0.0
	_action.animation = clip
	tree.set("parameters/oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return clip_impact(clip) / maxf(0.01, speed)


static func clip_impact(clip: String) -> float:
	var c: Dictionary = (anim_sets().get("clips", {}) as Dictionary).get(clip, {})
	return float(c.get("impact", 0.0)) if c.get("impact") != null else 0.0


## Attack clip + impact for the current weapon (spec = special attack variant; cast = "projectile"/"area").
func attack_clip(spec: bool = false, cast: String = "") -> Dictionary:
	if cast != "":
		return (anim_sets().get("casts", {}) as Dictionary).get(cast, {"clip": "cast_projectile", "impact": 0.42})
	if spec and weapon_set.has("spec"):
		return weapon_set["spec"]
	return weapon_set.get("attack", {"clip": "attack_stab", "impact": 0.36})


func set_dead(v: bool) -> void:
	if v == dead:
		return
	dead = v
	tree.set("parameters/life/transition_request", "dead" if v else "alive")
	if not v:
		_action.animation = "spawn"
		tree.set("parameters/oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _ready() -> void:
	var pb: AnimationNodeStateMachinePlayback = tree.get("parameters/loco/playback")
	if pb != null:
		pb.start(_loco_state)


func flash(amount: float = 0.6) -> void:
	_flash = amount


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		_set_param_all("flash", _flash)


## For tools: pose the skeleton at time t of a clip (no blending).
func pose_at(clip: String, t: float) -> void:
	tree.active = false
	anim.play(clip)
	anim.seek(t, true)
	anim.pause()
