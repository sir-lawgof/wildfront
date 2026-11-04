class_name MapGrid
extends RefCounted
## Tile grid with walkability, line of sight and OSRS-style BFS pathfinding (GDD 2 Movement).

const BLOCK_MOVE := 1
const BLOCK_LOS := 2

## OSRS checks neighbours in this order: W, E, S, N, SW, SE, NW, NE.
const DIRS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1),
]

var id: String = ""
var name: String = ""
var w: int = 0
var h: int = 0
var flags: PackedByteArray
var theme: Dictionary = {}
## Render info: [{rect: Rect2i, kind: "wall"|"pillar"|"water"}]
var features: Array = []
var spawns: Array = [[], []]       ## team 0 / team 1 spawn tiles (Array[Vector2i])
var ffa_spawns: Array = []
var obelisks: Array = []           ## Array[Vector2i]


static func create_empty(width: int, height: int) -> MapGrid:
	var m := MapGrid.new()
	m.w = width
	m.h = height
	m.flags = PackedByteArray()
	m.flags.resize(width * height)
	return m


static func from_json(d: Dictionary) -> MapGrid:
	var size: Array = d.get("size", [32, 32])
	var m := create_empty(int(size[0]), int(size[1]))
	m.id = str(d.get("id", "map"))
	m.name = str(d.get("name", m.id))
	m.theme = d.get("theme", {})
	var point := str(d.get("symmetry", "none")) == "point"
	# Border wall.
	m._add_rect(Rect2i(0, 0, m.w, 1), "wall")
	m._add_rect(Rect2i(0, m.h - 1, m.w, 1), "wall")
	m._add_rect(Rect2i(0, 1, 1, m.h - 2), "wall")
	m._add_rect(Rect2i(m.w - 1, 1, 1, m.h - 2), "wall")
	for kind in ["walls", "pillars", "water"]:
		for r in d.get(kind, []):
			var rect := Rect2i(int(r[0]), int(r[1]), 1, 1)
			if (r as Array).size() >= 4:
				rect = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
			var k: String = {"walls": "wall", "pillars": "pillar", "water": "water"}[kind]
			m._add_rect(rect, k)
			if point:
				var mr := m._mirror_rect(rect)
				if mr != rect:
					m._add_rect(mr, k)
	var sp: Dictionary = d.get("spawns", {})
	for p in sp.get("a", []):
		var v := Vector2i(int(p[0]), int(p[1]))
		m.spawns[0].append(v)
		if point:
			m.spawns[1].append(m._mirror_pt(v))
	for p in sp.get("b", []):
		m.spawns[1].append(Vector2i(int(p[0]), int(p[1])))
	for p in d.get("ffa_spawns", []):
		var v := Vector2i(int(p[0]), int(p[1]))
		m.ffa_spawns.append(v)
		if point:
			m.ffa_spawns.append(m._mirror_pt(v))
	for p in d.get("obelisks", []):
		var v := Vector2i(int(p[0]), int(p[1]))
		m.obelisks.append(v)
		if point:
			m.obelisks.append(m._mirror_pt(v))
	var uniq: Dictionary = d.get("unique", {})
	for p in uniq.get("obelisks", []):
		m.obelisks.append(Vector2i(int(p[0]), int(p[1])))
	return m


func _mirror_rect(r: Rect2i) -> Rect2i:
	return Rect2i(w - r.position.x - r.size.x, h - r.position.y - r.size.y, r.size.x, r.size.y)


func _mirror_pt(p: Vector2i) -> Vector2i:
	return Vector2i(w - 1 - p.x, h - 1 - p.y)


func _add_rect(r: Rect2i, kind: String) -> void:
	var f := BLOCK_MOVE
	if kind != "water":
		f |= BLOCK_LOS
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if in_bounds(x, y):
				flags[y * w + x] |= f
	features.append({"rect": r, "kind": kind})


func set_blocked(x: int, y: int, los: bool = true) -> void:
	flags[y * w + x] = BLOCK_MOVE | (BLOCK_LOS if los else 0)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func walkable(x: int, y: int) -> bool:
	return in_bounds(x, y) and (flags[y * w + x] & BLOCK_MOVE) == 0


func walkable_v(p: Vector2i) -> bool:
	return walkable(p.x, p.y)


func blocks_los(x: int, y: int) -> bool:
	return not in_bounds(x, y) or (flags[y * w + x] & BLOCK_LOS) != 0


## Can you step from a to the adjacent tile a+d? Diagonals may not cut corners.
func can_step(a: Vector2i, d: Vector2i) -> bool:
	var b := a + d
	if not walkable(b.x, b.y):
		return false
	if d.x != 0 and d.y != 0:
		return walkable(a.x + d.x, a.y) and walkable(a.x, a.y + d.y)
	return true


## Line of sight between tile centres. Any LOS-blocking tile strictly between the
## two endpoints blocks the shot (pillars, walls). Water does not.
func has_los(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return true
	var dx := b.x - a.x
	var dy := b.y - a.y
	var n := maxi(absi(dx), absi(dy)) * 4
	var last := a
	for i in range(1, n):
		var t := float(i) / float(n)
		var px := int(round(a.x + dx * t))
		var py := int(round(a.y + dy * t))
		var p := Vector2i(px, py)
		if p == last or p == a or p == b:
			continue
		last = p
		if blocks_los(px, py):
			return false
	return true


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## BFS path from start to the nearest of `goals`. If no goal is reachable, walks to
## the reachable tile closest to `goals[0]` (OSRS behaviour). Returned path excludes start.
func find_path(start: Vector2i, goals: Array, max_nodes: int = 6000) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if goals.is_empty() or not in_bounds(start.x, start.y):
		return result
	var goal_set := {}
	for g in goals:
		var gv: Vector2i = g
		if in_bounds(gv.x, gv.y):
			goal_set[gv.y * w + gv.x] = true
	var start_i := start.y * w + start.x
	if goal_set.has(start_i):
		return result
	var parent := PackedInt32Array()
	parent.resize(w * h)
	parent.fill(-1)
	parent[start_i] = start_i
	var queue := PackedInt32Array()
	queue.append(start_i)
	var head := 0
	var found := -1
	while head < queue.size() and head < max_nodes:
		var ci := queue[head]
		head += 1
		var c := Vector2i(ci % w, ci / w)
		for d in DIRS:
			if not can_step(c, d):
				continue
			var n := c + d
			var ni := n.y * w + n.x
			if parent[ni] != -1:
				continue
			parent[ni] = ci
			if goal_set.has(ni):
				found = ni
				break
			queue.append(ni)
		if found != -1:
			break
	if found == -1:
		# Nearest reachable tile to the primary goal (ties: shorter path, i.e. earlier in BFS order).
		var target: Vector2i = goals[0]
		var best := start_i
		var best_d := _dist2(start, target)
		for i in range(queue.size()):
			var qi := queue[i]
			var q := Vector2i(qi % w, qi / w)
			var d2 := _dist2(q, target)
			if d2 < best_d:
				best_d = d2
				best = qi
		found = best
	if found == start_i:
		return result
	var node := found
	while node != start_i:
		result.append(Vector2i(node % w, node / w))
		node = parent[node]
	result.reverse()
	return result


static func _dist2(a: Vector2i, b: Vector2i) -> int:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy


## Nearest walkable tile to p (spiral search), for spawning and trap placement.
func nearest_walkable(p: Vector2i) -> Vector2i:
	if walkable_v(p):
		return p
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := p + Vector2i(dx, dy)
				if walkable_v(q):
					return q
	return p
