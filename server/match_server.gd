class_name MatchServer
extends Node
## Runs MatchServerCore on a fixed 600 ms clock and broadcasts a snapshot each tick.
## The client (MatchView) only talks to it through the "link" interface below, which
## RemoteLink also implements, so the same client code works locally and over LAN:
##   signal ticked(snapshot), signal summary_ready(summary)
##   begin(), submit(intent), change_class(def, levels), request_summary(forfeit),
##   tick_progress(), running

signal ticked(snapshot: Dictionary)
signal tick_completed              ## after every tick (NetSession forwards snapshots to peers)
signal summary_ready(summary: Dictionary)

var core := MatchServerCore.new()
var cfg: Dictionary = {}
var running: bool = false
var _acc: float = 0.0
var tick_len: float = 0.6


func begin() -> void:
	start(cfg)


func start(p_cfg: Dictionary) -> void:
	cfg = p_cfg
	core.setup(cfg)
	tick_len = float(DB.rule("tick_seconds", 0.6))
	running = true
	_acc = 0.0
	ticked.emit(_snap())
	tick_completed.emit()


## The local view: the player's own, or a spectator view when nobody local is playing (watch-only match).
func _snap() -> Dictionary:
	return core.sim.snapshot(core.player_id, core.player_id == -1)


func _process(delta: float) -> void:
	if not running:
		return
	_acc += delta
	var guard := 0
	while _acc >= tick_len and guard < 3:
		_acc -= tick_len
		guard += 1
		core.tick()
		ticked.emit(_snap())
		tick_completed.emit()
		if core.sim.phase == "over":
			running = false
			break


## 0..1 progress through the current tick, for smoothing movement on the client.
func tick_progress() -> float:
	return clampf(_acc / tick_len, 0.0, 1.0)


func submit(intent: Dictionary) -> void:
	core.submit(core.player_id, intent)


func change_class(class_def: Dictionary, levels: Dictionary) -> void:
	core.change_class(core.player_id, class_def, levels)


func request_summary(forfeit: bool) -> void:
	running = false
	var s := core.summary(forfeit, -1, core.player_id == -1)
	if core.training == null and core.sim.live_ticks > 0:
		s["replay_path"] = Replay.save(core.replay_data())  # U8: keep the last 10
	summary_ready.emit.call_deferred(s)
