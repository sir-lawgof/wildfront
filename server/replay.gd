class_name Replay
extends RefCounted
## U8 replays. The simulation is deterministic on its fixed tick, so a replay only stores the match setup (with
## the seed) and every human input by tick; bots replay themselves. Files use Godot's text format (var_to_str)
## so ints and vectors survive. The last KEEP replays are kept in user://replays/.

static var DIR := "user://replays"          ## tests point this somewhere else
static var EXPORT_DIR := "user://exports"
const KEEP := 10
const EXT := ".wfreplay"


## Re-runs a recording up to to_tick (-1 = the end). Returns the core, ready to keep ticking with step().
static func simulate(rec: Dictionary, to_tick: int = -1) -> MatchServerCore:
	var core := MatchServerCore.new()
	core.record = false
	core.setup((rec["cfg"] as Dictionary).duplicate(true))
	var by_tick := index(rec)
	var end := int(rec.get("ticks", 1 << 30)) if to_tick < 0 else to_tick
	while core.sim.tick < end and core.sim.phase != "over":
		step(core, by_tick)
	return core


## {tick: [[kind, a, b], ...]} for fast lookup while stepping.
static func index(rec: Dictionary) -> Dictionary:
	var by_tick := {}
	for it in rec.get("intents", []):
		var t := int(it[0])
		if not by_tick.has(t):
			by_tick[t] = []
		by_tick[t].append(["intent", int(it[1]), it[2]])
	for ev in rec.get("events", []):
		var t := int(ev[0])
		if not by_tick.has(t):
			by_tick[t] = []
		by_tick[t].append([str(ev[1]), int(ev[2]), null])
	return by_tick


## Applies this tick's recorded inputs and advances one tick.
static func step(core: MatchServerCore, by_tick: Dictionary) -> void:
	for e in by_tick.get(core.sim.tick, []):
		match str(e[0]):
			"intent":
				core.sim.queue_intent(int(e[1]), (e[2] as Dictionary).duplicate(true))
			"peer_left":
				core.peer_left(int(e[1]))
	core.tick()


## True when replaying reproduces the recorded final state exactly.
static func verify(rec: Dictionary) -> bool:
	var core := simulate(rec)
	return core.sim.tick == int(rec.get("ticks", -1)) and core.sim.state_hash() == int(rec.get("final_hash", 0))


static func save(rec: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var info: Dictionary = rec.get("info", {})
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := DIR.path_join("%s_%s%s" % [stamp, str(info.get("mode", "match")), EXT])
	var n := 1
	while FileAccess.file_exists(path):
		n += 1
		path = DIR.path_join("%s_%s_%d%s" % [stamp, str(info.get("mode", "match")), n, EXT])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(var_to_str(rec))
	f.close()
	_prune()
	return path


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v = str_to_var(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


## Newest first: [{path, date, info, ticks}].
static func list() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	var files := Array(dir.get_files()).filter(func(f): return str(f).ends_with(EXT))
	files.sort()
	files.reverse()
	for f in files:
		var rec := load_file(DIR.path_join(f))
		if rec.is_empty():
			continue
		out.append({"path": DIR.path_join(f), "date": str(rec.get("date", "")), "info": rec.get("info", {}), "ticks": int(rec.get("ticks", 0))})
	return out


static func _prune() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var files := Array(dir.get_files()).filter(func(f): return str(f).ends_with(EXT))
	files.sort()
	while files.size() > KEEP:
		DirAccess.remove_absolute(DIR.path_join(str(files.pop_front())))


## Copies a replay to user://exports/ (outside the rotating folder) and returns the new path.
static func export_file(path: String) -> String:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var dest := EXPORT_DIR.path_join(path.get_file())
	if DirAccess.copy_absolute(path, dest) != OK:
		return ""
	return dest
