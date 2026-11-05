class_name EnvironmentBuilder
extends Node3D
## Renders an EnvLayout (docs/ENVIRONMENT.md section 3): generated ground, water + rims, MultiMesh-instanced
## environment modules, outer skirt terrain, backdrop, sky, fog, lighting, obelisks and ambient particles.
## Client-side presentation only; no game rules here.

const ENV_MAT := "res://assets/materials/env.tres"
const WATER_SHADER := "res://assets/materials/water.gdshader"
const SKY_SHADER := "res://assets/materials/sky.gdshader"
const PALETTE_JSON := "res://assets/palette/palette_env.json"
const PALETTE_PNG := "res://assets/palette/palette_env.png"

static var _cells: Dictionary = {}
static var _img: Image
static var _meshes: Dictionary = {}

var layout: EnvLayout
var obelisk_nodes: Array = []      ## [{crystal: StandardMaterial3D, ring: StandardMaterial3D}] like WorldView
var _tinted: Array = []            ## [{node: GeometryInstance3D, team: int}]
var _crystals: Array = []
var _weather: GPUParticles3D
var _t: float = 0.0


# ---------------------------------------------------------------- palette

static func _load_palette() -> void:
	if not _cells.is_empty():
		return
	var f := FileAccess.open(PALETTE_JSON, FileAccess.READ)
	_cells = (JSON.parse_string(f.get_as_text()) as Dictionary).get("swatches", {})
	_img = (load(PALETTE_PNG) as Texture2D).get_image()


static func uv(name: String) -> Vector2:
	_load_palette()
	var c: Array = _cells.get(name, [15, 15])
	return Vector2((float(c[0]) + 0.5) / 16.0, (float(c[1]) + 0.5) / 16.0)


static func color(name: String) -> Color:
	_load_palette()
	var c: Array = _cells.get(name, [15, 15])
	return _img.get_pixel(int(c[0]) * 8 + 4, int(c[1]) * 8 + 4)


func sw(suffix: String) -> String:
	return "%s.%s" % [layout.kit, suffix]


static func module_mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		var p := "res://assets/models/env/%s.glb" % id
		var mesh: Mesh = null
		if ResourceLoader.exists(p):
			var inst := (load(p) as PackedScene).instantiate()
			var mi := inst.find_children("*", "MeshInstance3D", true, false)
			if not mi.is_empty():
				mesh = (mi[0] as MeshInstance3D).mesh
			inst.free()
		_meshes[id] = mesh
	return _meshes[id]


# ---------------------------------------------------------------- build

func build(m: MapGrid, raw: Dictionary, show_grid: bool, show_objectives: bool) -> void:
	layout = EnvLayout.build(m, raw)
	_build_ground(show_grid)
	_build_water()
	_build_modules(show_objectives)
	_build_skirt()
	_build_sky_and_light()
	_build_weather()
	if show_objectives:
		_build_obelisks()


func _env_instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = load(ENV_MAT)
	add_child(mi)
	return mi


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: Vector2, col: Color) -> void:
	# a-b-c-d counter-clockwise seen from the front; Godot's front faces are clockwise, so emit a-c-b, a-d-c.
	for v in [a, c, b, a, d, c]:
		st.set_color(col)
		st.set_uv(u)
		st.add_vertex(v)


func _box(st: SurfaceTool, c: Vector3, size: Vector3, u: Vector2, col: Color) -> void:
	var h := size * 0.5
	var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z),
		c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	var faces := [[4, 7, 6, 5], [0, 1, 2, 3], [3, 2, 6, 7], [1, 0, 4, 5], [2, 1, 5, 6], [0, 3, 7, 4]]
	for f in faces:
		_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], u, col)


## One mesh for the whole arena floor: a flat quad per tile (y = 0), coloured by the ground layers.
func _build_ground(show_grid: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m := layout.map
	for y in m.h:
		for x in m.w:
			var t := Vector2i(x, y)
			if not layout.ground.has(t):
				continue
			var j := 0.965 + 0.07 * fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)
			_quad(st, Vector3(x, 0, y), Vector3(x, 0, y + 1), Vector3(x + 1, 0, y + 1), Vector3(x + 1, 0, y),
				uv(sw(str(layout.ground[t]))), Color(j, j, j))
	# Mire boardwalks: flat planks (<= 0.05 tall) on walkable tiles.
	for t in layout.boardwalk:
		var tile: Vector2i = t
		var horizontal := (tile.x + tile.y) % 2 == 0
		for k in 3:
			var off := -0.33 + k * 0.33
			var c := Vector3(tile.x + 0.5 + (0.0 if horizontal else off), 0.02, tile.y + 0.5 + (off if horizontal else 0.0))
			var size := Vector3(0.96, 0.04, 0.28) if horizontal else Vector3(0.28, 0.04, 0.96)
			_box(st, c, size, uv(sw("path")), Color(0.95 + 0.05 * k, 0.95 + 0.05 * k, 0.95 + 0.05 * k))
	st.generate_normals()
	var mi := _env_instance(st.commit())
	mi.set_instance_shader_parameter("ground", 1.0)
	mi.set_instance_shader_parameter("cutout", 0.0)
	mi.set_instance_shader_parameter("grid_strength", 1.0 if show_grid else 0.0)


## Water surface (y = -0.05, shore factor in vertex colour) and rims on every edge touching a walkable tile.
func _build_water() -> void:
	if layout.water.is_empty():
		return
	var m := layout.map
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim_sw: String = {"frost": "frost.ice", "ember": "ember.wall_light", "mire": "mire.shore",
		"castle": "castle.pillar"}.get(layout.kit, sw("shore"))
	for t in layout.water:
		var tile: Vector2i = t
		var corners := [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]
		var pts: Array = []
		var cols: Array = []
		for c in corners:
			var shore := 0.0
			for dy in [-1, 0]:
				for dx in [-1, 0]:
					var n: Vector2i = tile + c + Vector2i(dx, dy)
					if not layout.water.has(n) and m.in_bounds(n.x, n.y) and m.walkable_v(n):
						shore = 1.0
			pts.append(Vector3(tile.x + c.x, -0.05, tile.y + c.y))
			cols.append(Color(shore, 0, 0))
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(cols[i])
			st.add_vertex(pts[i])
		for d in EnvLayout.DIRS4:
			var n: Vector2i = tile + d
			if layout.water.has(n) or not m.in_bounds(n.x, n.y) or not m.walkable_v(n):
				continue
			var c := EnvLayout.tile_center(tile, 0.04) + Vector3(d.x, 0, d.y) * 0.43
			var size := Vector3(0.14, 0.14, 1.0) if d.x != 0 else Vector3(1.0, 0.14, 0.14)
			_box(rim, c, size, uv(rim_sw), Color(0.92, 0.92, 0.92))
	for t in layout.boardwalk:  # boardwalk posts stand in the water next to the planks
		for d in EnvLayout.DIRS4:
			var n: Vector2i = (t as Vector2i) + d
			if layout.water.has(n) and ((n.x + n.y) % 3 == 0):
				_box(rim, EnvLayout.tile_center(n, 0.15) - Vector3(d.x, 0, d.y) * 0.38, Vector3(0.1, 0.4, 0.1),
					uv("mire.wood"), Color(0.8, 0.8, 0.8))
	st.generate_normals()
	var wm := MeshInstance3D.new()
	wm.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load(WATER_SHADER)
	mat.set_shader_parameter("shallow", color(sw("water_shallow")))
	mat.set_shader_parameter("deep", color(sw("water_deep")))
	mat.set_shader_parameter("foam", color("common.cloth_white"))
	mat.set_shader_parameter("ice", 1.0 if layout.kit == "frost" else 0.0)
	mat.set_shader_parameter("murk", 1.0 if layout.kit == "mire" else 0.0)
	wm.material_override = mat
	add_child(wm)
	rim.generate_normals()
	var ri := _env_instance(rim.commit())
	ri.set_instance_shader_parameter("cutout", 0.0)


## Static environment pieces are merged into chunk meshes (a 4 x 4 grid of solid chunks that cast shadows, a
## 4 x 4 grid of shadowless flat-decor chunks, and 4 shadowless quadrants outside the border), so a map costs a
## few draw calls and the chunks the camera can't see are culled. The per-piece brightness variation is baked into vertex colours while merging.
## Banners that take the friend/foe tint stay as small MultiMeshes (one per team).
func _build_modules(show_objectives: bool) -> void:
	var m := layout.map
	var chunks: Dictionary = {}   ## chunk key -> {verts, normals, uvs, colors}
	var tinted: Dictionary = {}   ## "id|team" -> [Transform3D]
	for p in layout.placements:
		var role := str(p["role"])
		if role == "marker" or (role == "marker_base" and not show_objectives):
			continue  # crystals are individual nodes (owner colour, bobbing)
		if int(p["tint"]) >= 0:
			var key := "%s|%d" % [p["id"], int(p["tint"])]
			if not tinted.has(key):
				tinted[key] = []
			(tinted[key] as Array).append(p["xf"])
			continue
		var xf: Transform3D = p["xf"]
		# Quadrant chunks so the parts the camera can't see are culled: solid pieces (cast shadows), flat
		# decoration and everything outside the border (no shadows).
		var quad := "%d%d" % [int(xf.origin.x >= m.w / 2.0), int(xf.origin.z >= m.h / 2.0)]
		var cell := "%d_%d" % [clampi(int(xf.origin.x * 4.0 / m.w), 0, 3), clampi(int(xf.origin.z * 4.0 / m.h), 0, 3)]
		var chunk := "flat" + cell
		if role in ["wall", "face", "rampart", "pillar", "block", "structure", "border", "wall_top", "marker_base"]:
			chunk = "solid" + cell
		elif role in ["scatter", "backdrop"]:
			chunk = "outside" + quad
		_append(chunks, chunk, str(p["id"]), xf)
	for key in chunks:
		var c: Dictionary = chunks[key]
		if (c["verts"] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = c["verts"]
		arr[Mesh.ARRAY_NORMAL] = c["normals"]
		arr[Mesh.ARRAY_TEX_UV] = c["uvs"]
		arr[Mesh.ARRAY_COLOR] = c["colors"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := _env_instance(mesh)
		mi.name = "env_" + str(key)
		mi.set_instance_shader_parameter("vary", 0.0)  # variation is already baked per piece
		if not str(key).begins_with("solid"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for key in tinted:
		var parts := str(key).split("|")
		var mesh := module_mesh(parts[0])
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var xfs: Array = tinted[key]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		_tinted.append({"node": mmi, "team": int(parts[1])})
	set_viewer_team(0, false)


static var _arrays: Dictionary = {}


## Unindexed triangle arrays of a module (cached), with AO colours.
static func module_arrays(id: String) -> Array:
	if not _arrays.has(id):
		var mesh := module_mesh(id)
		var out: Array = []
		if mesh != null:
			var v := PackedVector3Array()
			var n := PackedVector3Array()
			var u := PackedVector2Array()
			var c := PackedColorArray()
			for s in mesh.get_surface_count():
				var a := mesh.surface_get_arrays(s)
				var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var sn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
				var su: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
				var sc: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				if idx.is_empty():
					idx.resize(sv.size())
					for i in sv.size():
						idx[i] = i
				for i in idx:
					v.append(sv[i])
					n.append(sn[i])
					u.append(su[i])
					c.append(sc[i] if not sc.is_empty() else Color.WHITE)
			out = [v, n, u, c]
		_arrays[id] = out
	return _arrays[id]


func _append(chunks: Dictionary, chunk: String, id: String, xf: Transform3D) -> void:
	var a := module_arrays(id)
	if a.is_empty():
		return
	if not chunks.has(chunk):
		chunks[chunk] = {"verts": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(),
			"colors": PackedColorArray()}
	# Packed arrays are values in GDScript: take each one out, append, and store it back.
	var c: Dictionary = chunks[chunk]
	var verts: PackedVector3Array = c["verts"]
	verts.append_array(xf * (a[0] as PackedVector3Array))
	c["verts"] = verts
	var normals: PackedVector3Array = c["normals"]
	normals.append_array(Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * (a[1] as PackedVector3Array))
	c["normals"] = normals
	var uvs: PackedVector2Array = c["uvs"]
	uvs.append_array(a[2])
	c["uvs"] = uvs
	var k := 1.0 + (fposmod(sin(floor(xf.origin.x * 2.0) * 12.9898 + floor(xf.origin.z * 2.0) * 78.233) * 43758.5453, 1.0) * 2.0 - 1.0) * 0.05
	var cols: PackedColorArray = (a[3] as PackedColorArray).duplicate()
	for i in cols.size():
		cols[i] = Color(cols[i].r * k, cols[i].g * k, cols[i].b * k, cols[i].a)
	var all_cols: PackedColorArray = c["colors"]
	all_cols.append_array(cols)
	c["colors"] = all_cols


## Friend/foe tint for banners (same rule as rings and names: allies blue, enemies red).
func set_viewer_team(my_team: int, ffa: bool) -> void:
	for e in _tinted:
		(e["node"] as GeometryInstance3D).set_instance_shader_parameter("banner_color",
			UITheme.team_color(int(e["team"]), my_team, ffa))


## Outer skirt: a ring of terrain from the border out to ~40 tiles (flat-shaded, never walkable).
func _build_skirt() -> void:
	var m := layout.map
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var step := 2
	var margin := 42
	for gz in range(-margin, m.h + margin, step):
		for gx in range(-margin, m.w + margin, step):
			if gx >= 0 and gz >= 0 and gx + step <= m.w and gz + step <= m.h:
				continue
			var x0 := float(gx)
			var z0 := float(gz)
			var x1 := x0 + step
			var z1 := z0 + step
			var a := Vector3(x0, layout.skirt_height(x0, z0) - 0.01, z0)
			var b := Vector3(x0, layout.skirt_height(x0, z1) - 0.01, z1)
			var c := Vector3(x1, layout.skirt_height(x1, z1) - 0.01, z1)
			var d := Vector3(x1, layout.skirt_height(x1, z0) - 0.01, z0)
			var detail := fposmod(sin(gx * 3.1 + gz * 1.7) * 91.7, 1.0) < 0.3
			var u := uv(sw("skirt_detail" if detail else "skirt"))
			var j := 0.95 + 0.1 * fposmod(sin(gx * 7.3 + gz * 3.9) * 17.1, 1.0)
			_quad(st, a, b, c, d, u, Color(j, j, j))
	st.generate_normals()
	var mi := _env_instance(st.commit())
	mi.set_instance_shader_parameter("cutout", 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_sky_and_light() -> void:
	var th := layout.map.theme
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load(SKY_SHADER)
	var horizon := Color.html(str(th.get("sky_horizon", th.get("sky", "#a0b8d0"))))
	sm.set_shader_parameter("top_color", Color.html(str(th.get("sky_top", "#7f9fbf"))))
	sm.set_shader_parameter("horizon_color", horizon)
	sm.set_shader_parameter("ground_color", Color.html(str(th.get("sky_ground", "#8a9098"))))
	sm.set_shader_parameter("cloud_color", Color.html(str(th.get("cloud", "#eef2f6"))))
	sm.set_shader_parameter("sun_color", Color.html(str(th.get("sun_color", "#fff2dc"))))
	sm.set_shader_parameter("cloud_cover", float(th.get("cloud_cover", 0.4)))
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = float(th.get("ambient_energy", 0.9))
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color.html(str(th.get("fog_color", th.get("fog", "#c0c8d0"))))
	e.fog_density = float(th.get("fog_density", 0.004))
	e.fog_sky_affect = 0.35
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(float(th.get("sun_pitch", -50.0)), float(th.get("sun_yaw", -35.0)), 0)
	sun.light_energy = float(th.get("sun_energy", 1.1))
	sun.light_color = Color.html(str(th.get("sun_color", "#ffffff")))
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # one pass: crisp enough at game zoom
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)


func _build_obelisks() -> void:
	var crystal_mesh := module_mesh("env_common_crystal")
	for o in layout.map.obelisks:
		var root := Node3D.new()
		root.position = EnvLayout.tile_center(o)
		add_child(root)
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.85, 0.85, 0.85)
		cm.emission_enabled = true
		cm.emission = Color(0.85, 0.85, 0.85)
		cm.emission_energy_multiplier = 1.4
		var crystal := MeshInstance3D.new()
		crystal.mesh = crystal_mesh
		crystal.material_override = cm
		root.add_child(crystal)
		_crystals.append(crystal)
		# capture ring decal: a flat glowing ring showing the capture radius (radius 1 = 3x3 tiles)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.42
		tm.outer_radius = 1.52
		tm.rings = 24
		tm.ring_segments = 4
		ring.mesh = tm
		ring.scale = Vector3(1, 0.05, 1)
		ring.position.y = 0.03
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(0.85, 0.85, 0.85, 0.6)
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		var lbl := Label3D.new()
		lbl.text = ["A", "B", "C", "D", "E"][obelisk_nodes.size() % 5]
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 64
		lbl.outline_size = 12
		lbl.position.y = 3.2
		lbl.no_depth_test = true
		root.add_child(lbl)
		obelisk_nodes.append({"crystal": cm, "ring": rm})
	for p in layout.lights:
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = 4.0
		l.light_energy = 0.8
		l.light_color = Color(0.85, 0.9, 1.0)
		l.shadow_enabled = false
		add_child(l)


## Weather particles that follow the camera focus (snow, sand, fireflies, leaves) plus brazier embers.
func _build_weather() -> void:
	var kind := str(layout.map.theme.get("weather", ""))
	if kind != "":
		_weather = _particles(kind, 320 if kind == "snow" else 160, Vector3(22, 6, 22))
		add_child(_weather)
	for p in layout.embers.slice(0, 4):
		var e := _particles("embers", 12, Vector3(0.2, 0.1, 0.2))
		e.position = p
		add_child(e)


func _particles(kind: String, amount: int, extents: Vector3) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = amount
	gp.local_coords = false
	gp.lifetime = 6.0
	gp.visibility_aabb = AABB(-extents * 2.0, extents * 4.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	var c := Color.WHITE
	match kind:
		"snow":
			quad.size = Vector2(0.07, 0.07)
			pm.direction = Vector3(0.2, -1, 0.1)
			pm.spread = 15.0
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.1
			pm.gravity = Vector3(0, -0.2, 0)
			c = Color(1, 1, 1, 0.9)
			gp.position.y = 6.0
		"sand":
			quad.size = Vector2(0.05, 0.05)
			pm.direction = Vector3(1, 0.05, 0.3)
			pm.spread = 10.0
			pm.initial_velocity_min = 1.5
			pm.initial_velocity_max = 2.6
			pm.gravity = Vector3.ZERO
			c = Color(0.85, 0.72, 0.5, 0.7)
			pm.emission_box_extents = Vector3(extents.x, 0.6, extents.z)
			gp.position.y = 0.6
		"fireflies":
			quad.size = Vector2(0.07, 0.07)
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 180.0
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.3
			pm.gravity = Vector3.ZERO
			c = Color(0.85, 1.0, 0.45, 0.95)
			pm.emission_box_extents = Vector3(extents.x, 1.2, extents.z)
			gp.position.y = 1.2
		"leaves":
			quad.size = Vector2(0.09, 0.06)
			pm.direction = Vector3(1, -0.4, 0.4)
			pm.spread = 30.0
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.2
			pm.gravity = Vector3(0, -0.15, 0)
			c = Color(0.55, 0.65, 0.25, 0.9)
			gp.amount = 50
			gp.position.y = 5.0
		"embers":
			quad.size = Vector2(0.05, 0.05)
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 20.0
			pm.initial_velocity_min = 0.5
			pm.initial_velocity_max = 0.9
			pm.gravity = Vector3(0, 0.1, 0)
			c = Color(1.0, 0.6, 0.2, 1.0)
			gp.lifetime = 2.0
	pm.color = c
	mat.emission_enabled = kind in ["fireflies", "embers"]
	mat.emission = c
	quad.material = mat
	gp.process_material = pm
	gp.draw_pass_1 = quad
	return gp


## Keep weather particles around the camera focus.
func follow(focus: Vector3) -> void:
	if _weather != null:
		_weather.position.x = focus.x
		_weather.position.z = focus.z


func _process(delta: float) -> void:
	_t += delta
	for nd in obelisk_nodes:  # the capture ring pulses while someone is capturing
		var rm: StandardMaterial3D = nd["ring"]
		if bool(nd.get("capturing", false)):
			rm.albedo_color.a = 0.45 + 0.4 * (0.5 + 0.5 * sin(_t * 7.0))
	for i in _crystals.size():
		(_crystals[i] as Node3D).position.y = sin(_t * 1.6 + i) * 0.08
		(_crystals[i] as Node3D).rotation.y = _t * 0.6
