extends TestCase
## Environment art never changes or contradicts gameplay (docs/ENVIRONMENT.md section 1).
## For every map: blocking pieces cover exactly the tiles MapGrid marks as line-of-sight blockers and don't
## overhang their tiles by more than 0.1; walls and pillars are tall enough to read as blockers; nothing taller
## than 0.25 sits on a walkable tile; no decoration on spawn or capture tiles; water pieces stay inside water
## and under 0.6; scatter and backdrop stay outside the arena; dressing is deterministic.

const OVERHANG := 0.1001
const FLAT := 0.2501


func _layouts() -> Array:
	var out: Array = []
	for id in DB.maps:
		var m := MapGrid.from_json(DB.maps[id])
		out.append(EnvLayout.build(m, DB.maps[id]))
	return out


func test_modules_exist() -> void:
	check(not EnvLayout.modules().is_empty(), "env_modules.json has modules (run python tools/build_assets.py)")
	for l in _layouts():
		var layout: EnvLayout = l
		for p in layout.placements:
			check(EnvLayout.modules().has(str(p["id"])), "%s: module %s exists" % [layout.map.id, p["id"]])


func test_blocking_pieces_match_blocked_tiles() -> void:
	for l in _layouts():
		var layout: EnvLayout = l
		var blocked := layout.blocked_los_tiles()
		var covered := {}
		for p in layout.placements:
			if not bool(p["blocking"]):
				continue
			for t in p["tiles"]:
				covered[t] = true
				check(blocked.has(t), "%s: %s sits on walkable tile %s" % [layout.map.id, p["id"], t])
		for t in blocked:
			check(covered.has(t), "%s: blocked tile %s has no environment piece" % [layout.map.id, t])


func test_footprints_stay_on_their_tiles() -> void:
	for l in _layouts():
		var layout: EnvLayout = l
		for p in layout.placements:
			if not bool(p["blocking"]) or (p["tiles"] as Array).is_empty():
				continue
			var lo := Vector2(1e9, 1e9)
			var hi := Vector2(-1e9, -1e9)
			for t in p["tiles"]:
				lo = Vector2(minf(lo.x, t.x), minf(lo.y, t.y))
				hi = Vector2(maxf(hi.x, t.x + 1), maxf(hi.y, t.y + 1))
			var box := EnvLayout.world_aabb(p)
			var ok := box.position.x >= lo.x - OVERHANG and box.position.z >= lo.y - OVERHANG \
				and box.end.x <= hi.x + OVERHANG and box.end.z <= hi.y + OVERHANG
			check(ok, "%s: %s overhangs its tiles %s..%s (bounds %s)" % [layout.map.id, p["id"], lo, hi, box])


func test_blockers_read_as_blockers() -> void:
	for l in _layouts():
		var layout: EnvLayout = l
		for p in layout.placements:
			if str(p["role"]) in ["wall", "pillar", "rampart", "block", "structure", "border"]:
				check(EnvLayout.world_aabb(p).end.y >= 1.4, "%s: %s is at least 1.4 tall" % [layout.map.id, p["id"]])


func test_walkable_tiles_only_get_flat_decor() -> void:
	for l in _layouts():
		var layout: EnvLayout = l
		var m := layout.map
		for p in layout.placements:
			var role := str(p["role"])
			if role in ["scatter", "backdrop"] or bool(p["blocking"]):
				continue
			var box := EnvLayout.world_aabb(p)
			for t in p["tiles"]:
				var tile: Vector2i = t
				if role == "water_decor":
					check(layout.water.has(tile), "%s: %s is inside water" % [m.id, p["id"]])
					check(box.end.y <= 0.6, "%s: %s is under 0.6 tall" % [m.id, p["id"]])
					continue
				if role == "wall_top":
					check(not m.walkable_v(tile), "%s: %s sits on a wall tile" % [m.id, p["id"]])
					continue
				if role == "marker":  # the obelisk crystal floats above head height, so it never hides feet
					check(box.position.y >= 1.5, "%s: obelisk crystal floats (min y %.2f)" % [m.id, box.position.y])
					continue
				check(box.end.y <= FLAT, "%s: %s on walkable tile %s is flat (%.2f)" % [m.id, p["id"], tile, box.end.y])
				if role == "decor":
					check(not layout.spawn_tiles.has(tile), "%s: decor on spawn tile %s" % [m.id, tile])
					check(not layout.capture_tiles.has(tile), "%s: decor on capture tile %s" % [m.id, tile])


func test_outside_pieces_stay_outside() -> void:
	for l in _layouts():
		var layout: EnvLayout = l
		var m := layout.map
		var arena := Rect2(0, 0, m.w, m.h)
		for p in layout.placements:
			if not str(p["role"]) in ["scatter", "backdrop"]:
				continue
			var o := (p["xf"] as Transform3D).origin
			check(not arena.grow(1.0).has_point(Vector2(o.x, o.z)), "%s: %s stays outside the arena" % [m.id, p["id"]])


func test_dressing_is_deterministic() -> void:
	var id := "frostgate_ruins"
	var a := EnvLayout.build(MapGrid.from_json(DB.maps[id]), DB.maps[id])
	var b := EnvLayout.build(MapGrid.from_json(DB.maps[id]), DB.maps[id])
	eq(a.placements.size(), b.placements.size(), "same number of pieces")
	var same := true
	for i in mini(a.placements.size(), b.placements.size()):
		if a.placements[i]["id"] != b.placements[i]["id"] or a.placements[i]["xf"] != b.placements[i]["xf"]:
			same = false
	check(same, "same pieces in the same places")
