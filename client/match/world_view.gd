class_name WorldView
extends Node3D
## Builds placeholder 3D geometry for a MapGrid: checkered tile floor, stone walls,
## pillars, water, obelisks, plus lighting and sky. Tile (x, y) maps to world (x+0.5, 0, y+0.5).

var map: MapGrid
var obelisk_nodes: Array = []
var _meteor_marks: Dictionary = {}


static func tile_to_world(p: Vector2i, h: float = 0.0) -> Vector3:
	return Vector3(p.x + 0.5, h, p.y + 0.5)


func build(m: MapGrid, show_grid: bool, show_objectives: bool = true) -> void:
	map = m
	var th := m.theme
	var floor_a := Color.html(str(th.get("floor", "#777777")))
	var floor_b := Color.html(str(th.get("floor2", "#707070")))
	# Floor: one plane with a tile-checker texture so the grid is readable, like OSRS.
	var img := Image.create(m.w * 4, m.h * 4, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(m.id)
	for y in range(m.h):
		for x in range(m.w):
			var c := floor_a if (x + y) % 2 == 0 else floor_b
			c = c.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.03)
			for yy in range(4):
				for xx in range(4):
					var cc := c
					if show_grid and (xx == 0 or yy == 0):
						cc = c.darkened(0.08)
					img.set_pixel(x * 4 + xx, y * 4 + yy, cc)
	var tex := ImageTexture.create_from_image(img)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(m.w, m.h)
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = tex
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fm.roughness = 1.0
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = fm
	floor_node.position = Vector3(m.w / 2.0, 0, m.h / 2.0)
	add_child(floor_node)
	# Outer ground so the arena doesn't float in the void.
	var outer := MeshInstance3D.new()
	var om := PlaneMesh.new()
	om.size = Vector2(m.w * 4, m.h * 4)
	outer.mesh = om
	var omat := StandardMaterial3D.new()
	omat.albedo_color = floor_b.darkened(0.35)
	outer.material_override = omat
	outer.position = Vector3(m.w / 2.0, -0.02, m.h / 2.0)
	add_child(outer)

	var wall_col := Color.html(str(th.get("wall", "#888888")))
	var pillar_col := Color.html(str(th.get("pillar", "#999999")))
	var water_col := Color.html(str(th.get("water", "#336699")))
	var wall_mat := _mat(wall_col)
	var pillar_mat := _mat(pillar_col)
	var cap_mat := _mat(wall_col.lightened(0.15))
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(water_col, 0.85)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.metallic = 0.3
	water_mat.roughness = 0.15
	for f in m.features:
		var r: Rect2i = f["rect"]
		var kind := str(f["kind"])
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		match kind:
			"wall":
				var hgt := 1.5
				bm.size = Vector3(r.size.x, hgt, r.size.y)
				mi.material_override = wall_mat
				mi.position = Vector3(r.position.x + r.size.x / 2.0, hgt / 2.0, r.position.y + r.size.y / 2.0)
				# Crenellation-ish cap for readability from above.
				var cap := MeshInstance3D.new()
				var cm := BoxMesh.new()
				cm.size = Vector3(r.size.x + 0.1, 0.15, r.size.y + 0.1)
				cap.mesh = cm
				cap.material_override = cap_mat
				cap.position = Vector3(0, hgt / 2.0 + 0.07, 0)
				mi.add_child(cap)
			"pillar":
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.38
				cyl.bottom_radius = 0.45
				cyl.height = 2.1
				cyl.radial_segments = 8
				mi.mesh = cyl
				mi.material_override = pillar_mat
				mi.position = Vector3(r.position.x + 0.5, 1.05, r.position.y + 0.5)
				add_child(mi)
				continue
			"water":
				bm.size = Vector3(r.size.x, 0.1, r.size.y)
				mi.material_override = water_mat
				mi.position = Vector3(r.position.x + r.size.x / 2.0, -0.02, r.position.y + r.size.y / 2.0)
		mi.mesh = bm
		add_child(mi)
	for i in range(m.obelisks.size() if show_objectives else 0):
		var p: Vector2i = m.obelisks[i]
		var ob := Node3D.new()
		ob.position = tile_to_world(p)
		var base := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.6, 2.4, 0.6)
		base.mesh = pm
		base.material_override = _mat(Color("2a2a33"))
		base.position.y = 1.2
		ob.add_child(base)
		var crystal := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.28
		sm.height = 0.56
		crystal.mesh = sm
		var cmat := _mat(Color(0.8, 0.8, 0.8))
		cmat.emission_enabled = true
		cmat.emission = Color(0.8, 0.8, 0.8)
		crystal.material_override = cmat
		crystal.position.y = 2.7
		ob.add_child(crystal)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.3
		tm.outer_radius = 1.5
		ring.mesh = tm
		var rmat := _mat(Color(0.8, 0.8, 0.8, 0.6))
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = rmat
		ring.position.y = 0.03
		ring.scale = Vector3(1, 0.1, 1)
		ob.add_child(ring)
		var lbl := Label3D.new()
		lbl.text = ["A", "B", "C", "D", "E"][i % 5]
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 64
		lbl.outline_size = 12
		lbl.position.y = 3.4
		lbl.no_depth_test = true
		ob.add_child(lbl)
		add_child(ob)
		obelisk_nodes.append({"crystal": cmat, "ring": rmat})
	_lighting(th)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _lighting(th: Dictionary) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	var sky_col := Color.html(str(th.get("sky", "#a0b8d0")))
	psm.sky_top_color = sky_col.darkened(0.25)
	psm.sky_horizon_color = sky_col
	psm.ground_horizon_color = sky_col.darkened(0.2)
	psm.ground_bottom_color = sky_col.darkened(0.5)
	sky.sky_material = psm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color.html(str(th.get("fog", "#c0c8d0")))
	e.fog_density = 0.004
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func update_objectives(objs: Array, my_team: int) -> void:
	for i in range(mini(objs.size(), obelisk_nodes.size())):
		var o: Dictionary = objs[i]
		var owner := int(o["owner"])
		var c := Color(0.85, 0.85, 0.85)
		if owner >= 0:
			c = UITheme.team_color(owner, my_team)
		var nd: Dictionary = obelisk_nodes[i]
		var cm: StandardMaterial3D = nd["crystal"]
		cm.albedo_color = c
		cm.emission = c
		var rm: StandardMaterial3D = nd["ring"]
		var rc := c
		if int(o["cap_team"]) >= 0:
			rc = UITheme.team_color(int(o["cap_team"]), my_team).lerp(Color.WHITE, 0.3)
		rm.albedo_color = Color(rc, 0.7)


func show_meteors(meteors: Array) -> void:
	var seen := {}
	for m in meteors:
		var key := "%d_%d_%d" % [int(m["x"]), int(m["y"]), int(m["land"])]
		seen[key] = true
		if _meteor_marks.has(key):
			continue
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var sz := float(m["size"])
		pm.size = Vector2(sz, sz)
		mi.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.2, 0.1, 0.45)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		mi.position = Vector3(int(m["x"]) + 0.5, 0.05, int(m["y"]) + 0.5)
		add_child(mi)
		_meteor_marks[key] = mi
	for k in _meteor_marks.keys():
		if not seen.has(k):
			(_meteor_marks[k] as Node).queue_free()
			_meteor_marks.erase(k)
