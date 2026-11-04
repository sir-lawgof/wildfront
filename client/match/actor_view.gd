class_name ActorView
extends Node3D
## Placeholder low-poly character built from primitives. Gear is readable at a glance
## (GDD 4/10): body colour = armour type and tier, weapon shape = weapon type, and the
## overhead prayer icon floats above the head. Smooths movement between ticks.

var fid: int = 0
var team: int = 0
var is_me: bool = false
var is_npc: bool = false
var pub: Dictionary = {}
var _eq: Dictionary = {}
var _kit: String = ""
var _trail: Array = []
var _rig: Node3D
var _parts: Dictionary = {}
var _weapon_node: Node3D
var _offhand_node: Node3D
var _cape_node: Node3D
var _helm_node: Node3D
var _ring_mat: StandardMaterial3D
var _overhead: Sprite3D
var _name_lbl: Label3D
var _hp_bg: Sprite3D
var _hp_fg: Sprite3D
var _ice: MeshInstance3D
var _shield_bubble: MeshInstance3D
var _splats: Array = []
var _splat_slot: int = 0
var _attack_anim: float = 0.0
var _attack_style: String = ""
var _death_anim: float = -1.0
var _facing: float = 0.0
var _face_target: Vector3 = Vector3.INF
var _walk_phase: float = 0.0
var _last_pos: Vector3
var _model: CharacterModel        ## generated rigid-segment character (ASSETS.md); null -> primitive fallback
var _dead_time: float = -1.0

const SKIN := Color("d9a679")
const HP_W := 60


func setup(info: Dictionary, my_team: int, me: bool, ffa: bool) -> void:
	fid = int(info["id"])
	team = int(info["team"])
	is_me = me
	is_npc = str(info.get("npc", "")) != ""
	_rig = Node3D.new()
	add_child(_rig)
	if is_npc:
		_build_guardian()
	elif CharacterModel.available():
		_model = CharacterModel.new()
		_rig.add_child(_model)
		_model.set_team_color(UITheme.team_color(team, my_team, ffa))
	else:
		_build_body()
	# Team ring under the feet.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.36
	tm.outer_radius = 0.46
	ring.mesh = tm
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.03
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color("ffd23f") if me else UITheme.team_color(team, my_team, ffa)
	ring.material_override = _ring_mat
	add_child(ring)
	# Name, HP bar and overhead icon.
	_name_lbl = Label3D.new()
	_name_lbl.text = str(info["name"])
	_name_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_lbl.no_depth_test = true
	_name_lbl.font_size = 34
	_name_lbl.outline_size = 8
	_name_lbl.modulate = Color("ffff00") if me else UITheme.team_color(team, my_team, ffa).lightened(0.35)
	_name_lbl.position.y = 2.55 if not is_npc else 3.2
	_name_lbl.pixel_size = 0.006
	add_child(_name_lbl)
	_hp_bg = _bar_sprite(Color("c01818"), 0)
	_hp_fg = _bar_sprite(Color("18c018"), 1)
	_overhead = Sprite3D.new()
	_overhead.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead.no_depth_test = true
	_overhead.pixel_size = 0.022
	_overhead.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_overhead.position.y = 3.05 if not is_npc else 3.7
	_overhead.render_priority = 5
	add_child(_overhead)
	_ice = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 1.1, 0.9)
	_ice.mesh = bm
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(0.6, 0.9, 1.0, 0.45)
	im.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.metallic = 0.5
	im.roughness = 0.05
	_ice.material_override = im
	_ice.position.y = 0.55
	_ice.visible = false
	add_child(_ice)
	_shield_bubble = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 2.4
	_shield_bubble.mesh = sm
	var shm := StandardMaterial3D.new()
	shm.albedo_color = Color(1.0, 0.95, 0.5, 0.18)
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_bubble.material_override = shm
	_shield_bubble.position.y = 1.1
	_shield_bubble.visible = false
	add_child(_shield_bubble)
	position = WorldView.tile_to_world(info["pos"])
	_last_pos = position


func _bar_sprite(c: Color, prio: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = Icons.white()
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, HP_W, 7)
	s.centered = false
	s.offset = Vector2(-HP_W / 2.0, 0)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.modulate = c
	s.pixel_size = 0.012
	s.render_priority = prio + 2
	s.position.y = 2.3 if not is_npc else 3.0
	s.visible = false
	add_child(s)
	return s


func _mat(c: Color, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.6 if metal > 0 else 0.9
	return m


func _box(size: Vector3, pos: Vector3, c: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	(parent if parent != null else _rig).add_child(mi)
	return mi


func _build_body() -> void:
	_parts["leg_l"] = _box(Vector3(0.2, 0.75, 0.22), Vector3(-0.12, 0.375, 0), Color("5a4a3a"))
	_parts["leg_r"] = _box(Vector3(0.2, 0.75, 0.22), Vector3(0.12, 0.375, 0), Color("5a4a3a"))
	_parts["foot_l"] = _box(Vector3(0.22, 0.12, 0.3), Vector3(-0.12, 0.06, 0.04), Color("3a2a1a"))
	_parts["foot_r"] = _box(Vector3(0.22, 0.12, 0.3), Vector3(0.12, 0.06, 0.04), Color("3a2a1a"))
	_parts["torso"] = _box(Vector3(0.52, 0.62, 0.3), Vector3(0, 1.06, 0), Color("6a5a4a"))
	var arm_l := Node3D.new()
	arm_l.position = Vector3(-0.34, 1.32, 0)
	_rig.add_child(arm_l)
	var arm_r := Node3D.new()
	arm_r.position = Vector3(0.34, 1.32, 0)
	_rig.add_child(arm_r)
	_parts["arm_l"] = arm_l
	_parts["arm_r"] = arm_r
	_parts["sleeve_l"] = _box(Vector3(0.16, 0.58, 0.18), Vector3(0, -0.27, 0), Color("6a5a4a"), arm_l)
	_parts["sleeve_r"] = _box(Vector3(0.16, 0.58, 0.18), Vector3(0, -0.27, 0), Color("6a5a4a"), arm_r)
	_parts["hand_l"] = _box(Vector3(0.15, 0.13, 0.15), Vector3(0, -0.6, 0), SKIN, arm_l)
	_parts["hand_r"] = _box(Vector3(0.15, 0.13, 0.15), Vector3(0, -0.6, 0), SKIN, arm_r)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.19
	sm.height = 0.38
	head.mesh = sm
	head.material_override = _mat(SKIN)
	head.position = Vector3(0, 1.58, 0)
	_rig.add_child(head)
	_parts["head"] = head


func _build_guardian() -> void:
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.55
	cm.height = 2.4
	body.mesh = cm
	var m := _mat(Color("d8b440"), 0.6)
	m.emission_enabled = true
	m.emission = Color("6a5010")
	body.material_override = m
	body.position.y = 1.5
	_rig.add_child(body)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	orb.mesh = sm
	var om := _mat(Color("7fb3ff"))
	om.emission_enabled = true
	om.emission = Color("7fb3ff")
	orb.material_override = om
	orb.position = Vector3(0, 2.9, 0)
	_rig.add_child(orb)


# ---------------------------------------------------------------- gear visuals

func _item_color(id: String, fallback: Color) -> Color:
	if id == "":
		return fallback
	var it := DB.item(id)
	var c := Color.html(str(it.get("color", "#888888")))
	match str(it.get("armour_class", "")):
		"hide":
			c = Color("6b4a2b").lerp(c, 0.45)
		"robe":
			c = Color("3a2f6b").lerp(c, 0.4)
	return c


func _set_color(part: String, c: Color, metal: float = 0.0) -> void:
	if _parts.has(part):
		var mi: MeshInstance3D = _parts[part]
		var m := mi.material_override as StandardMaterial3D
		m.albedo_color = c
		m.metallic = metal
		m.roughness = 0.5 if metal > 0.0 else 0.9


func _metal_of(id: String) -> float:
	return 0.55 if str(DB.item(id).get("armour_class", "")) == "plate" else 0.0


func _apply_gear(eq: Dictionary) -> void:
	if is_npc:
		return
	_eq = eq.duplicate()
	if _model != null:
		_model.apply_equipment(eq, _kit)
		return
	var body := str(eq.get("body", ""))
	var legs := str(eq.get("legs", ""))
	var feet := str(eq.get("feet", ""))
	var hands := str(eq.get("hands", ""))
	_set_color("torso", _item_color(body, Color("8a7a60")), _metal_of(body))
	_set_color("sleeve_l", _item_color(body, Color("8a7a60")), _metal_of(body))
	_set_color("sleeve_r", _item_color(body, Color("8a7a60")), _metal_of(body))
	_set_color("leg_l", _item_color(legs, Color("5a4a3a")), _metal_of(legs))
	_set_color("leg_r", _item_color(legs, Color("5a4a3a")), _metal_of(legs))
	_set_color("foot_l", _item_color(feet, Color("3a2a1a")), _metal_of(feet))
	_set_color("foot_r", _item_color(feet, Color("3a2a1a")), _metal_of(feet))
	_set_color("hand_l", _item_color(hands, SKIN))
	_set_color("hand_r", _item_color(hands, SKIN))
	# Helm
	if _helm_node:
		_helm_node.queue_free()
		_helm_node = null
	var head_id := str(eq.get("head", ""))
	if head_id != "":
		var it := DB.item(head_id)
		var c := _item_color(head_id, Color.GRAY)
		_helm_node = MeshInstance3D.new()
		match str(it.get("armour_class", "")):
			"robe":
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.26
				cone.height = 0.55
				_helm_node.mesh = cone
				_helm_node.position = Vector3(0, 1.85, 0)
				_helm_node.rotation_degrees.x = -8
			"plate":
				var bm := BoxMesh.new()
				bm.size = Vector3(0.42, 0.44, 0.42)
				_helm_node.mesh = bm
				_helm_node.position = Vector3(0, 1.6, 0)
			_:
				var sm := SphereMesh.new()
				sm.radius = 0.23
				sm.height = 0.4
				_helm_node.mesh = sm
				_helm_node.position = Vector3(0, 1.64, -0.02)
		_helm_node.material_override = _mat(c, _metal_of(head_id))
		_rig.add_child(_helm_node)
	# Cape
	if _cape_node:
		_cape_node.queue_free()
		_cape_node = null
	var cape := str(eq.get("cape", ""))
	if cape != "":
		_cape_node = _box(Vector3(0.48, 0.9, 0.05), Vector3(0, 0.95, -0.2), _item_color(cape, Color.RED))
	# Weapon (right hand) and off-hand (left).
	if _weapon_node:
		_weapon_node.queue_free()
		_weapon_node = null
	var wid := str(eq.get("weapon", ""))
	if wid != "":
		_weapon_node = _make_weapon(DB.item(wid))
		(_parts["arm_r"] as Node3D).add_child(_weapon_node)
	if _offhand_node:
		_offhand_node.queue_free()
		_offhand_node = null
	var sid := str(eq.get("shield", ""))
	if sid != "":
		_offhand_node = _make_offhand(DB.item(sid))
		(_parts["arm_l"] as Node3D).add_child(_offhand_node)


func _make_weapon(it: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, -0.62, 0.05)
	var c := Color.html(str(it.get("color", "#aaaaaa")))
	if _kit != "":
		c = Color.html(_kit)  # ornament kit recolour (GDD 9)
	var wood := Color("6b4a2b")
	match str(it.get("mesh", "sword")):
		"dagger", "knife":
			_box(Vector3(0.05, 0.08, 0.35), Vector3(0, 0, 0.2), c, root)
		"scimitar":
			var b := _box(Vector3(0.05, 0.1, 0.75), Vector3(0, 0.05, 0.4), c, root)
			b.rotation_degrees.x = -12
		"sword":
			_box(Vector3(0.05, 0.1, 0.85), Vector3(0, 0, 0.45), c, root)
			_box(Vector3(0.25, 0.05, 0.05), Vector3(0, 0, 0.04), Color("555555"), root)
		"greatsword":
			_box(Vector3(0.07, 0.18, 1.3), Vector3(0, 0, 0.7), c, root)
			_box(Vector3(0.4, 0.06, 0.07), Vector3(0, 0, 0.05), Color("8a7020"), root)
		"axe":
			_box(Vector3(0.05, 0.05, 0.8), Vector3(0, 0, 0.35), wood, root)
			_box(Vector3(0.05, 0.35, 0.22), Vector3(0, 0.15, 0.68), c, root)
		"hammer":
			_box(Vector3(0.05, 0.05, 0.8), Vector3(0, 0, 0.35), wood, root)
			_box(Vector3(0.22, 0.22, 0.32), Vector3(0, 0, 0.75), c, root)
		"maul":
			_box(Vector3(0.06, 0.06, 1.1), Vector3(0, 0, 0.5), wood, root)
			_box(Vector3(0.32, 0.32, 0.45), Vector3(0, 0, 1.05), c, root)
		"bow", "longbow":
			var h := 1.3 if str(it.get("mesh", "")) == "longbow" else 1.0
			var bow := _box(Vector3(0.05, h, 0.06), Vector3(0, 0.05, 0.12), c, root)
			bow.rotation_degrees.x = 0
			_box(Vector3(0.01, h, 0.01), Vector3(0, 0.05, 0.02), Color("eeeeee"), root)
		"crossbow":
			_box(Vector3(0.08, 0.08, 0.6), Vector3(0, 0, 0.3), wood, root)
			_box(Vector3(0.6, 0.06, 0.06), Vector3(0, 0, 0.5), c, root)
		"staff":
			var cyl := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.035
			cm.bottom_radius = 0.035
			cm.height = 1.5
			cyl.mesh = cm
			cyl.material_override = _mat(wood)
			cyl.position = Vector3(0, 0.3, 0.05)
			root.add_child(cyl)
			var orb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.11
			sm.height = 0.22
			orb.mesh = sm
			var om := _mat(c)
			om.emission_enabled = true
			om.emission = c * 0.6
			orb.material_override = om
			orb.position = Vector3(0, 1.08, 0.05)
			root.add_child(orb)
		"wand":
			_box(Vector3(0.04, 0.04, 0.45), Vector3(0, 0, 0.22), wood, root)
			var orb2 := _box(Vector3(0.09, 0.09, 0.09), Vector3(0, 0, 0.47), c, root)
			(orb2.material_override as StandardMaterial3D).emission_enabled = true
			(orb2.material_override as StandardMaterial3D).emission = c * 0.6
		"whip":
			_box(Vector3(0.04, 0.04, 0.2), Vector3(0, 0, 0.1), Color("222222"), root)
			var lash := _box(Vector3(0.025, 0.025, 0.9), Vector3(0, -0.2, 0.55), c, root)
			lash.rotation_degrees.x = 25
		"claws":
			for k in range(3):
				_box(Vector3(0.02, 0.02, 0.28), Vector3(-0.05 + k * 0.05, 0, 0.18), c, root)
		"javelin":
			_box(Vector3(0.03, 0.03, 1.1), Vector3(0, 0.1, 0.3), wood, root)
			_box(Vector3(0.06, 0.06, 0.15), Vector3(0, 0.1, 0.9), c, root)
		_:
			pass
	return root


func _make_offhand(it: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(-0.06, -0.4, 0.05)
	var c := Color.html(str(it.get("color", "#aaaaaa")))
	var nm := str(it.get("name", "")).to_lower()
	if nm.contains("tome"):
		_box(Vector3(0.08, 0.3, 0.24), Vector3(0, 0, 0.1), c, root)
	elif nm.contains("defender"):
		_box(Vector3(0.06, 0.4, 0.3), Vector3(-0.05, 0, 0.12), c, root)
	elif nm.contains("buckler"):
		_box(Vector3(0.05, 0.42, 0.42), Vector3(-0.05, 0, 0.08), c, root)
	else:
		var s := _box(Vector3(0.06, 0.75, 0.5), Vector3(-0.06, 0.05, 0.08), c, root)
		(s.material_override as StandardMaterial3D).metallic = 0.5
	return root


# ---------------------------------------------------------------- per-tick updates

func apply(info: Dictionary) -> void:
	var was_dead := bool(pub.get("dead", false))
	pub = info
	team = int(info["team"])
	var trail: Array = info.get("trail", [info["pos"]])
	_trail = []
	for t in trail:
		_trail.append(WorldView.tile_to_world(t))
	if _trail.is_empty():
		_trail = [WorldView.tile_to_world(info["pos"])]
	if not is_npc and (info.get("eq", {}) != _eq or str(info.get("kit", "")) != _kit):
		_kit = str(info.get("kit", ""))
		_apply_gear(info["eq"])
	var ovh := str(info.get("ovh", ""))
	_overhead.texture = Icons.overhead(ovh) if ovh != "" else null
	_ice.visible = bool(info.get("frozen", false)) and not bool(info.get("dead", false))
	if _model != null:
		# Tiles covered this tick -> tiles per second (walk = 1 tile/tick, run = 2).
		_model.set_locomotion(float(maxi(0, _trail.size() - 1)) / 0.6, bool(info.get("frozen", false)))
	_shield_bubble.visible = bool(info.get("shield", false)) and not bool(info.get("dead", false))
	var dead := bool(info.get("dead", false))
	if _model != null:
		if dead and not was_dead:
			_model.set_dead(true)
			_dead_time = 0.0
		elif not dead and was_dead:
			_dead_time = -1.0
			visible = true
			position = _trail[-1]
			_last_pos = position
			_model.set_dead(false)
	elif dead and not was_dead:
		_death_anim = 0.0
	elif not dead and was_dead:
		_death_anim = -1.0
		_rig.rotation = Vector3.ZERO
		_rig.position = Vector3.ZERO
		visible = true
		position = _trail[-1]
	var hp := int(info.get("hp", 99))
	var mx := maxi(1, int(info.get("max_hp", 99)))
	var show_bar := hp < mx and not dead
	_hp_bg.visible = show_bar
	_hp_fg.visible = show_bar
	_hp_fg.region_rect = Rect2(0, 0, maxf(0.0, HP_W * clampf(float(hp) / mx, 0.0, 1.0)), 7)
	var tgt := int(info.get("target", -1))
	if tgt == -1:
		_face_target = Vector3.INF


func face(world_pos: Vector3) -> void:
	_face_target = world_pos


## Starts the attack clip on the tick the server reports. Returns seconds until the clip's impact/release
## frame, so the match view can line the hitsplat or projectile up with it.
func play_attack(style: String, target_pos: Vector3, spec: bool = false, spell: String = "") -> float:
	_face_target = target_pos
	if _model != null:
		var cast := ""
		if style == "magic":
			cast = "area" if spell != "" and int((DB.spells.get(spell, {}) as Dictionary).get("area", 0)) > 1 else "projectile"
		var info := _model.attack_clip(spec, cast)
		return _model.play_action(str(info.get("clip", "attack_stab")))
	_attack_anim = 1.0
	_attack_style = style
	return 0.0


## Eating / drinking / blocking / flinching one-shots.
func play_action(clip: String) -> void:
	if _model != null and not bool(pub.get("dead", false)):
		_model.play_action(clip)


func hit_flash() -> void:
	if _model != null:
		_model.flash(0.5)


func add_splat(amount: int, kind: String) -> void:
	var root := Node3D.new()
	var offsets := [Vector2(0, 0), Vector2(-0.35, 0.3), Vector2(0.35, 0.3), Vector2(0, 0.6)]
	var o: Vector2 = offsets[_splat_slot % offsets.size()]
	_splat_slot += 1
	root.position = Vector3(o.x, 1.2 + o.y, 0)
	var spr := Sprite3D.new()
	spr.texture = Icons.splat(kind)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.no_depth_test = true
	spr.pixel_size = 0.024
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.render_priority = 10
	root.add_child(spr)
	var lbl := Label3D.new()
	lbl.text = str(amount)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 40
	lbl.outline_size = 10
	lbl.pixel_size = 0.008
	lbl.render_priority = 11
	lbl.outline_render_priority = 10
	root.add_child(lbl)
	add_child(root)
	_splats.append({"node": root, "t": 0.0})


func _process(delta: float) -> void:
	# Hitsplats: hold then fade (OSRS style, they don't fly away).
	for s in _splats.duplicate():
		s["t"] = float(s["t"]) + delta
		var nd: Node3D = s["node"]
		if float(s["t"]) > 1.1:
			nd.queue_free()
			_splats.erase(s)
		elif float(s["t"]) > 0.8:
			nd.scale = Vector3.ONE * (1.0 - (float(s["t"]) - 0.8) / 0.3)
	if _splats.is_empty():
		_splat_slot = 0
	if _dead_time >= 0.0:
		_dead_time += delta
		if _dead_time > 3.0:
			visible = false
		return
	# Death: topple and sink.
	if _death_anim >= 0.0:
		_death_anim += delta
		_rig.rotation.x = -minf(_death_anim * 3.0, 1.5)
		if _death_anim > 1.2:
			visible = false
		return
	# Attack swing.
	if _attack_anim > 0.0 and _parts.has("arm_r"):
		_attack_anim = maxf(0.0, _attack_anim - delta * 3.5)
		var arm: Node3D = _parts["arm_r"]
		var k := sin((1.0 - _attack_anim) * PI)
		match _attack_style:
			"melee":
				arm.rotation.x = -k * 1.6
			"ranged":
				arm.rotation.x = -1.4
				(_parts["arm_l"] as Node3D).rotation.x = -1.4 * k
			_:
				arm.rotation.x = -k * 2.2
		if _attack_anim <= 0.0:
			arm.rotation.x = 0.0
			(_parts["arm_l"] as Node3D).rotation.x = 0.0


## Called every frame by the match view with progress (0..1) through the current tick.
func interpolate(progress: float) -> void:
	if _death_anim >= 0.0 or _dead_time >= 0.0 or _trail.is_empty():
		return
	var n := _trail.size()
	var p: Vector3
	if n == 1:
		p = _trail[0]
	else:
		var f := progress * (n - 1)
		var i := mini(int(f), n - 2)
		p = (_trail[i] as Vector3).lerp(_trail[i + 1], f - i)
	var moved := p - _last_pos
	position = p
	_last_pos = p
	if moved.length() > 0.001:
		_facing = atan2(moved.x, moved.z)
		_walk_phase += moved.length() * 6.0
	elif _face_target != Vector3.INF:
		var d := _face_target - position
		if d.length() > 0.1:
			_facing = atan2(d.x, d.z)
	_rig.rotation.y = lerp_angle(_rig.rotation.y, _facing, 0.35)
	if _model != null:
		return
	# Simple walk cycle.
	if _parts.has("leg_l"):
		var sw := sin(_walk_phase) * (0.5 if moved.length() > 0.001 else 0.0)
		(_parts["leg_l"] as Node3D).rotation.x = sw
		(_parts["leg_r"] as Node3D).rotation.x = -sw
		if _attack_anim <= 0.0:
			(_parts["arm_l"] as Node3D).rotation.x = -sw * 0.6
			(_parts["arm_r"] as Node3D).rotation.x = sw * 0.6
