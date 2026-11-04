class_name EnvLayout
extends RefCounted
## Turns a map's gameplay data into environment dressing (docs/ENVIRONMENT.md sections 1, 2, 4).
## Pure data (no nodes): EnvironmentBuilder renders it, tests/test_environment.gd checks it.
## The golden rule: gameplay data owns the map. Every blocking tile gets exactly the pieces that fill it,
## decoration on walkable tiles is flat, and all randomness is seeded from the map id.

const MODULES_PATH := "res://data/art/env_modules.json"
const KIT_BY_MAP := {"frostgate_ruins": "frost", "ember_outpost": "ember", "mirewatch_keep": "mire",
	"castle_courtyard": "castle"}
## Classification thresholds (section 2): lines are 1 wide, 2x2 is a small block, 2xN a rampart, 3x3+ a structure.
const STRUCTURE_MIN := 3
const DECOR_CHANCE := 0.045
const FACE_CHANCE := 0.3
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static var _modules: Dictionary = {}

var map: MapGrid
var raw: Dictionary
var kit: String = "frost"
## {id, xf: Transform3D, role, tiles: Array[Vector2i], blocking: bool, tint: int (-1 none, else team index)}
var placements: Array = []
var ground: Dictionary = {}       ## Vector2i -> swatch suffix ("ground_a", "path", ...)
var water: Dictionary = {}        ## Vector2i -> true
var spawn_tiles: Dictionary = {}
var capture_tiles: Dictionary = {}
var path_tiles: Dictionary = {}
var boardwalk: Dictionary = {}    ## mire: walkable tiles that get flat planks
var lights: Array = []            ## Vector3 positions of the few OmniLights (obelisks)
var embers: Array = []            ## Vector3 brazier positions (ember particles)
var team_side: Array = [Vector2.ZERO, Vector2.ZERO]  ## spawn centroids per team

var _occupied: Dictionary = {}
var _wallish: Dictionary = {}


static func modules() -> Dictionary:
	if _modules.is_empty():
		var f := FileAccess.open(MODULES_PATH, FileAccess.READ)
		if f != null:
			_modules = (JSON.parse_string(f.get_as_text()) as Dictionary).get("modules", {})
	return _modules


static func build(m: MapGrid, raw_json: Dictionary, capture_radius: int = 1) -> EnvLayout:
	var l := EnvLayout.new()
	l.map = m
	l.raw = raw_json
	var dressing: Dictionary = raw_json.get("dressing", {})
	l.kit = str(dressing.get("kit", KIT_BY_MAP.get(m.id, "frost")))
	l._collect_markers(capture_radius)
	l._classify()
	l._paths()
	l._ground_layers()
	l._decor()
	l._outside()
	return l


# ---------------------------------------------------------------- helpers

func _rng(salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(map.id + "/" + salt)
	return r


static func tile_center(t: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(t.x + 0.5, y, t.y + 0.5)


func _has(id: String) -> bool:
	return modules().has(id)


func _place(id: String, xf: Transform3D, role: String, tiles: Array, blocking: bool, tint: int = -1) -> void:
	if not _has(id):
		push_warning("environment module '%s' is missing (run python tools/build_assets.py)" % id)
		return
	placements.append({"id": id, "xf": xf, "role": role, "tiles": tiles, "blocking": blocking, "tint": tint})


static func rot(angle_deg: float, pos: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(angle_deg)), pos)


## Rotation that turns a module's front (+Z in Godot = Blender -Y) toward a grid direction.
static func face_angle(d: Vector2i) -> float:
	return rad_to_deg(atan2(float(d.x), float(d.y)))


func _rect_tiles(r: Rect2i) -> Array:
	var out: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


func _mirror(r: Rect2i) -> Rect2i:
	return Rect2i(map.w - r.position.x - r.size.x, map.h - r.position.y - r.size.y, r.size.x, r.size.y)


func _style_for(r: Rect2i) -> String:
	for s in (raw.get("dressing", {}) as Dictionary).get("styles", []):
		var a: Array = s["rect"]
		var sr := Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
		if sr == r or _mirror(sr) == r:
			return str(s["style"])
	return "wall"


func team_of(p: Vector2) -> int:
	return 0 if p.distance_to(team_side[0]) <= p.distance_to(team_side[1]) else 1


# ---------------------------------------------------------------- markers

func _collect_markers(radius: int) -> void:
	for team in 2:
		var c := Vector2.ZERO
		for s in map.spawns[team]:
			spawn_tiles[s] = true
			c += Vector2(s)
		if not (map.spawns[team] as Array).is_empty():
			c /= float((map.spawns[team] as Array).size())
		team_side[team] = c
	for s in map.ffa_spawns:
		spawn_tiles[s] = true
	for o in map.obelisks:
		var ob: Vector2i = o
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				capture_tiles[ob + Vector2i(dx, dy)] = true


# ---------------------------------------------------------------- blockers (section 2)

func _classify() -> void:
	var rects: Array = []
	for i in map.features.size():
		var f: Dictionary = map.features[i]
		var r: Rect2i = f["rect"]
		match str(f["kind"]):
			"water":
				for t in _rect_tiles(r):
					water[t] = true
				_water_decor(r)
			"pillar":
				rects.append({"r": r, "cls": "pillar"})
			"wall":
				if i < 4:
					continue  # the automatic border ring, handled below
				var lo := mini(r.size.x, r.size.y)
				var hi := maxi(r.size.x, r.size.y)
				var cls := "line"
				if lo >= STRUCTURE_MIN:
					cls = "structure"
				elif lo == 2 and hi == 2:
					cls = "block"
				elif lo == 2:
					cls = "rampart"
				rects.append({"r": r, "cls": cls})
				for t in _rect_tiles(r):
					_wallish[t] = true
	for x in map.w:
		_wallish[Vector2i(x, 0)] = true
		_wallish[Vector2i(x, map.h - 1)] = true
	for y in map.h:
		_wallish[Vector2i(0, y)] = true
		_wallish[Vector2i(map.w - 1, y)] = true
	_border()
	for cls in ["structure", "rampart", "block", "pillar", "line"]:
		for e in rects:
			if e["cls"] == cls:
				call("_" + cls, e["r"])


func _claim(tiles: Array) -> Array:
	var out: Array = []
	for t in tiles:
		if not _occupied.has(t):
			_occupied[t] = true
			out.append(t)
	return out


func _border() -> void:
	var r := _rng("border")
	for x in map.w:
		for y in map.h:
			var t := Vector2i(x, y)
			if x != 0 and y != 0 and x != map.w - 1 and y != map.h - 1:
				continue
			if not _claim([t]).size():
				continue
			var corner := (x == 0 or x == map.w - 1) and (y == 0 or y == map.h - 1)
			var ang := 0.0
			if y == 0:
				ang = 0.0
			elif y == map.h - 1:
				ang = 180.0
			elif x == 0:
				ang = 90.0
			else:
				ang = -90.0
			var id := "env_%s_border_corner" % kit
			if not corner:
				var roll := r.randf()
				id = "env_%s_border_%s" % [kit, "gate" if roll < 0.05 else ("straight_v1" if roll < 0.55 else "straight_v2")]
			_place(id, rot(ang, tile_center(t)), "border", [t], true)


func _structure(rect: Rect2i) -> void:
	var tiles := _claim(_rect_tiles(rect))
	var wide := rect.size.x >= rect.size.y
	var id := "env_%s_structure_%dx%d" % [kit, maxi(rect.size.x, rect.size.y), mini(rect.size.x, rect.size.y)]
	var c := Vector3(rect.position.x + rect.size.x / 2.0, 0.0, rect.position.y + rect.size.y / 2.0)
	var r := _rng("st%s" % rect)
	var ang := (0.0 if wide else 90.0) + (180.0 if r.randf() < 0.5 else 0.0)
	_place(id, rot(ang, c), "structure", tiles, true)


func _block(rect: Rect2i) -> void:
	var tiles := _claim(_rect_tiles(rect))
	var r := _rng("bl%s" % rect)
	var n := 0
	for v in range(1, 10):
		if _has("env_%s_block_v%d" % [kit, v]):
			n = v
	var c := Vector3(rect.position.x + 1.0, 0.0, rect.position.y + 1.0)
	_place("env_%s_block_v%d" % [kit, r.randi_range(1, maxi(1, n))], rot(90.0 * r.randi_range(0, 3), c), "block", tiles, true)


func _pillar(rect: Rect2i) -> void:
	var t := rect.position
	if _claim([t]).is_empty():
		return
	var r := _rng("pi%s" % t)
	_place("env_%s_pillar_v%d" % [kit, r.randi_range(1, 3)], rot(90.0 * r.randi_range(0, 3), tile_center(t)), "pillar", [t], true)


func _rampart(rect: Rect2i) -> void:
	var horizontal := rect.size.x > rect.size.y
	var length := maxi(rect.size.x, rect.size.y)
	var r := _rng("ra%s" % rect)
	var along := Vector2i(1, 0) if horizontal else Vector2i(0, 1)
	var across := Vector2i(0, 1) if horizontal else Vector2i(1, 0)
	var banner_slot := [r.randi_range(0, length - 1), r.randi_range(0, length - 1)]
	for i in length:
		var a := rect.position + along * i
		var b := a + across
		var tiles := _claim([a, b])
		if tiles.is_empty():
			continue
		var c := (tile_center(a) + tile_center(b)) * 0.5
		var id := "env_%s_rampart_mid_v%d" % [kit, r.randi_range(1, 2)]
		var ang := (0.0 if horizontal else 90.0) + (180.0 if r.randf() < 0.5 else 0.0)
		if i == length - 1:
			id = "env_%s_rampart_end" % kit
			ang = 0.0 if horizontal else -90.0
		elif i == 0:
			id = "env_%s_rampart_end" % kit
			ang = 180.0 if horizontal else 90.0
		_place(id, rot(ang, c), "rampart", tiles, true)
		for side in 2:
			var t := a if side == 0 else b
			var out_dir := -across if side == 0 else across
			if not map.walkable_v(t + out_dir):
				continue
			if i % 3 == 1:
				_place("env_%s_rampart_buttress" % kit, rot(face_angle(out_dir), tile_center(t)), "face", [t], true)
			elif i == banner_slot[side] and _has("env_%s_face_banner" % kit):
				_place("env_%s_face_banner" % kit, rot(face_angle(out_dir), tile_center(t)), "face", [t], true,
					team_of(Vector2(t)))


func _line(rect: Rect2i) -> void:
	var style := _style_for(rect)
	var r := _rng("li%s" % rect)
	var faces: Array = []
	for id in modules():
		if str(id).begins_with("env_%s_face_" % kit):
			faces.append(id)
	faces.sort()
	var wall_h := 1.6
	for t in _rect_tiles(rect):
		if _occupied.has(t):
			continue
		_occupied[t] = true
		var conn: Array[Vector2i] = []
		for d in DIRS4:
			if _wallish.has(t + d):
				conn.append(d)
		var kind := "join"
		var ang := 0.0
		if conn.size() == 2 and conn[0] == -conn[1]:
			kind = "straight"
			ang = (0.0 if conn[0].y == 0 else 90.0) + (180.0 if r.randf() < 0.5 else 0.0)
		elif conn.size() == 1:
			kind = "end"
			ang = rad_to_deg(atan2(float(conn[0].y), float(-conn[0].x)))
		var id := "env_%s_%s_%s" % [kit, style, kind]
		if kind == "straight":
			id += "_v%d" % r.randi_range(1, 2)
		_place(id, rot(ang, tile_center(t)), "wall", [t], true)
		var aabb: Array = (modules().get(id, {}) as Dictionary).get("aabb", [0, 0, 0, 0, wall_h, 0])
		wall_h = float(aabb[4])
		if style != "wall":
			continue
		for d in DIRS4:
			if conn.has(d) or not map.in_bounds(t.x + d.x, t.y + d.y) or not map.walkable_v(t + d):
				continue
			if r.randf() < FACE_CHANCE and not faces.is_empty():
				var fid: String = faces[r.randi_range(0, faces.size() - 1)]
				var tint := team_of(Vector2(t)) if fid.ends_with("banner") else -1
				_place(fid, rot(face_angle(d), tile_center(t)), "face", [t], true, tint)
		if kit == "ember" and r.randf() < 0.12 and embers.size() < 6:
			var top := tile_center(t, wall_h)
			_place("env_common_brazier", rot(0.0, top), "wall_top", [t], false)
			embers.append(top + Vector3(0, 0.4, 0))


# ---------------------------------------------------------------- water decoration (inside water tiles only)

func _water_decor(rect: Rect2i) -> void:
	var r := _rng("wa%s" % rect)
	var c := Vector3(rect.position.x + rect.size.x / 2.0, 0.0, rect.position.y + rect.size.y / 2.0)
	match kit:
		"ember":
			_place("env_ember_water_well_frame", rot(0.0 if rect.size.x >= rect.size.y else 90.0, c), "water_decor",
				_rect_tiles(rect), false)
			return
		"castle":
			if rect.size.x >= 2 and rect.size.y >= 2:
				var ct := Vector2i(int(c.x), int(c.z))
				_place("env_castle_water_fountain", rot(0.0, tile_center(ct)), "water_decor", [ct], false)
	for t in _rect_tiles(rect):
		var edge := false
		for d in DIRS4:
			var n: Vector2i = t + d
			if map.in_bounds(n.x, n.y) and map.walkable_v(n):
				edge = true
		var roll := r.randf()
		var id := ""
		match kit:
			"frost":
				if edge and roll < 0.18:
					id = "env_frost_water_ice_shards"
				elif roll < 0.08:
					id = "env_frost_water_ice_chunk"
			"mire":
				if edge and roll < 0.4:
					id = "env_mire_water_reeds"
				elif not edge and roll < 0.12:
					id = "env_mire_water_lily"
				elif roll < 0.15:
					id = "env_mire_water_log"
			"castle":
				if not edge and roll < 0.1:
					id = "env_castle_water_lily"
		if id != "":
			_place(id, rot(90.0 * r.randi_range(0, 3), tile_center(t)), "water_decor", [t], false)


# ---------------------------------------------------------------- ground (section 4)

func _paths() -> void:
	var points: Array[Vector2i] = []
	for team in 2:
		if not (map.spawns[team] as Array).is_empty():
			points.append(map.nearest_walkable(Vector2i(team_side[team].round())))
	for o in map.obelisks:
		points.append(map.nearest_walkable(o))
	points.append(map.nearest_walkable(Vector2i(map.w / 2, map.h / 2)))
	for i in points.size():
		for j in range(i + 1, points.size()):
			for t in map.find_path(points[i], [points[j]]):
				path_tiles[t] = true
			path_tiles[points[i]] = true
	if kit == "ember":  # a wider packed-dirt road
		var wide := path_tiles.duplicate()
		for t in path_tiles:
			for d in DIRS4:
				var n: Vector2i = t + d
				if map.in_bounds(n.x, n.y) and map.walkable_v(n):
					wide[n] = true
		path_tiles = wide


func _near(t: Vector2i, tiles: Dictionary, diag: bool) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if (dx == 0 and dy == 0) or (not diag and dx != 0 and dy != 0):
				continue
			if tiles.has(t + Vector2i(dx, dy)):
				return true
	return false


func _ground_layers() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = hash(map.id)
	noise.frequency = 0.07
	var blockers := {}
	for y in map.h:
		for x in map.w:
			if map.blocks_los(x, y):
				blockers[Vector2i(x, y)] = true
	var center := Vector2(map.w / 2.0, map.h / 2.0)
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			if water.has(t):
				continue
			var s := "ground_a" if (x + y) % 2 == 0 else "ground_b"
			if noise.get_noise_2d(x, y) > 0.28:
				s = "detail"
			if _near(t, blockers, true) and map.walkable(x, y):
				s = "edging"
			if _near(t, water, true) and map.walkable(x, y):
				s = "shore"
			if spawn_tiles.has(t):
				s = "spawn"
			for o in map.obelisks:
				if MapGrid.chebyshev(t, o) <= 2:
					s = "plaza"
			if kit == "frost" and Vector2(t).distance_to(center) < 6.0 and s.begins_with("ground"):
				s = "plaza"  # frozen flagstones in the central courtyard
			if path_tiles.has(t) and s != "plaza" and s != "spawn":
				s = "path"
			ground[t] = s
			if kit == "mire" and map.walkable(x, y) and (_near(t, water, false) or (path_tiles.has(t) and _water_within(t, 4))):
				boardwalk[t] = true


func _water_within(t: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if water.has(t + Vector2i(dx, dy)):
				return true
	return false


# ---------------------------------------------------------------- flat decoration (section 1 rule 3)

func _decor() -> void:
	var r := _rng("decor")
	var ids: Array = []
	for id in modules():
		if str(id).begins_with("env_%s_decor_" % kit):
			ids.append(id)
	ids.sort()
	if ids.is_empty():
		return
	for y in map.h:
		for x in map.w:
			var t := Vector2i(x, y)
			if not map.walkable(x, y) or spawn_tiles.has(t) or capture_tiles.has(t) or path_tiles.has(t) or boardwalk.has(t):
				continue
			if r.randf() >= DECOR_CHANCE:
				continue
			var id: String = ids[r.randi_range(0, ids.size() - 1)]
			var off := Vector3(r.randf_range(-0.12, 0.12), 0.0, r.randf_range(-0.12, 0.12))
			_place(id, rot(r.randf_range(0.0, 360.0), tile_center(t) + off), "decor", [t], false)
	for o in map.obelisks:
		_place("env_%s_obelisk_base" % kit, rot(0.0, tile_center(o)), "marker_base", [o], false)
		_place("env_common_crystal", rot(0.0, tile_center(o)), "marker", [o], false)
		if lights.size() < 4:
			lights.append(tile_center(o, 2.3))


# ---------------------------------------------------------------- outside the border (section 6)

## Height of the outer skirt (0 at the border, rising with distance; never inside the map).
func skirt_height(x: float, z: float) -> float:
	var dx := maxf(maxf(-x, x - map.w), 0.0)
	var dz := maxf(maxf(-z, z - map.h), 0.0)
	var d := maxf(dx, dz)
	if d <= 0.0:
		return 0.0
	var amp: float = {"frost": 4.0, "ember": 2.5, "mire": 0.6, "castle": 2.2}.get(kit, 2.0)
	var n := sin(x * 0.21 + map.w) * cos(z * 0.17) * 0.5 + sin(x * 0.07 - z * 0.09) * 0.5
	return clampf((d - 1.5) / 10.0, 0.0, 1.0) * amp * (0.6 + 0.4 * n) - (0.15 if kit == "mire" else 0.0) * clampf(d / 3.0, 0.0, 1.0)


func _outside() -> void:
	var r := _rng("skirt")
	var ids: Array = []
	for id in modules():
		if str(id).begins_with("env_%s_scatter_" % kit):
			ids.append(id)
	ids.sort()
	var margin := 30
	var step := 5
	for gz in range(-margin, map.h + margin, step):
		for gx in range(-margin, map.w + margin, step):
			var x := gx + r.randf_range(0.0, step)
			var z := gz + r.randf_range(0.0, step)
			var dx := maxf(maxf(-x, x - map.w), 0.0)
			var dz := maxf(maxf(-z, z - map.h), 0.0)
			var d := maxf(dx, dz)
			if d < 3.0 or ids.is_empty():
				continue
			if r.randf() > clampf(0.2 + d / 40.0, 0.0, 0.55):
				continue
			var id: String = ids[r.randi_range(0, ids.size() - 1)]
			var s := r.randf_range(0.8, 1.35)
			var xf := Transform3D(Basis(Vector3.UP, r.randf_range(0.0, TAU)).scaled(Vector3(s, s, s)),
				Vector3(x, skirt_height(x, z), z))
			_place(id, xf, "scatter", [], false)
	var c := Vector3(map.w / 2.0, 0.0, map.h / 2.0)
	var radius := maxf(map.w, map.h) * 0.5 + 75.0
	for i in 10:
		var a := TAU * i / 10.0 + r.randf_range(-0.1, 0.1)
		var p := c + Vector3(sin(a), 0.0, cos(a)) * (radius + r.randf_range(-8.0, 12.0))
		var look := c - p
		var xf := Transform3D(Basis(Vector3.UP, atan2(look.x, look.z)).scaled(Vector3.ONE * r.randf_range(1.0, 1.5)), p + Vector3(0, -1.0, 0))
		_place("env_%s_backdrop_range" % kit, xf, "backdrop", [], false)
	if bool((raw.get("dressing", {}) as Dictionary).get("castles", false)):
		for team in 2:
			var side: Vector2 = team_side[team]
			var z := -16.0 if side.y < map.h / 2.0 else map.h + 16.0
			_place("env_%s_backdrop_keep" % kit, rot(0.0 if z < 0 else 180.0, Vector3(map.w / 2.0, 0.0, z)), "backdrop",
				[], false, team)


# ---------------------------------------------------------------- queries (builder, tests)

## World-space bounds of a placement, from the module metadata.
static func world_aabb(p: Dictionary) -> AABB:
	var a: Array = (modules().get(str(p["id"]), {}) as Dictionary).get("aabb", [0, 0, 0, 0, 0, 0])
	var box := AABB(Vector3(float(a[0]), float(a[1]), float(a[2])),
		Vector3(float(a[3]) - float(a[0]), float(a[4]) - float(a[1]), float(a[5]) - float(a[2])))
	return (p["xf"] as Transform3D) * box


func blocked_los_tiles() -> Dictionary:
	var out := {}
	for y in map.h:
		for x in map.w:
			if map.blocks_los(x, y):
				out[Vector2i(x, y)] = true
	return out
