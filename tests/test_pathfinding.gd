extends TestCase
## BFS pathfinding and line of sight (GDD 2 Movement).


func test_straight_path() -> void:
	var m := MapGrid.create_empty(10, 10)
	var p := m.find_path(Vector2i(1, 1), [Vector2i(5, 1)])
	eq(p.size(), 4, "4 steps")
	eq(p[-1], Vector2i(5, 1), "ends at goal")


func test_diagonal_path_is_short() -> void:
	var m := MapGrid.create_empty(10, 10)
	var p := m.find_path(Vector2i(1, 1), [Vector2i(5, 5)])
	eq(p.size(), 4, "diagonals cost one step")


func test_path_around_wall() -> void:
	var m := MapGrid.create_empty(10, 10)
	for y in range(0, 8):
		m.set_blocked(4, y)
	var p := m.find_path(Vector2i(1, 1), [Vector2i(7, 1)])
	check(not p.is_empty(), "found a path")
	eq(p[-1], Vector2i(7, 1), "reaches goal")
	for t in p:
		check(m.walkable_v(t), "path tile walkable %s" % t)


func test_no_corner_cutting() -> void:
	var m := MapGrid.create_empty(5, 5)
	m.set_blocked(2, 1)
	check(not m.can_step(Vector2i(1, 1), Vector2i(1, 1)) or m.walkable(2, 1), "can't cut past blocked corner")
	check(not m.can_step(Vector2i(1, 2), Vector2i(1, -1)), "diagonal past wall blocked")


func test_unreachable_goes_to_nearest() -> void:
	var m := MapGrid.create_empty(10, 10)
	# Box in (8,8).
	for d in [Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(9, 8), Vector2i(8, 9), Vector2i(9, 9)]:
		m.set_blocked(d.x, d.y)
	var p := m.find_path(Vector2i(1, 1), [Vector2i(8, 8)])
	check(not p.is_empty(), "walks somewhere")
	check(MapGrid.chebyshev(p[-1], Vector2i(8, 8)) == 2, "ends next to the box, got %s" % p[-1])


func test_line_of_sight() -> void:
	var m := MapGrid.create_empty(10, 10)
	check(m.has_los(Vector2i(1, 5), Vector2i(8, 5)), "open LOS")
	m.set_blocked(5, 5)
	check(not m.has_los(Vector2i(1, 5), Vector2i(8, 5)), "pillar blocks LOS")
	check(m.has_los(Vector2i(1, 1), Vector2i(8, 1)), "other row still clear")
	var w := MapGrid.create_empty(10, 10)
	w.set_blocked(5, 5, false)  # water: blocks movement, not sight
	check(w.has_los(Vector2i(1, 5), Vector2i(8, 5)), "water doesn't block LOS")


func test_maps_load_and_spawns_walkable() -> void:
	for id in DB.maps:
		var m := MapGrid.from_json(DB.maps[id])
		check(not m.spawns[0].is_empty() and m.spawns[0].size() == m.spawns[1].size(), "%s team spawns" % id)
		for team in [0, 1]:
			for s in m.spawns[team]:
				check(m.walkable_v(s), "%s spawn %s walkable" % [id, s])
		for s in m.ffa_spawns:
			check(m.walkable_v(s), "%s ffa spawn %s walkable" % [id, s])
		for o in m.obelisks:
			check(m.walkable_v(o), "%s obelisk %s walkable" % [id, o])
		# Both team spawn areas are connected.
		var p := m.find_path(m.spawns[0][0], [m.spawns[1][0]])
		check(not p.is_empty() and p[-1] == m.spawns[1][0], "%s spawns connected" % id)
