class_name RemoteLink
extends Node
## Client-side stand-in for MatchServer when playing on someone else's LAN host.
## Same interface as MatchServer; snapshots arrive by RPC through NetSession.

signal ticked(snapshot: Dictionary)
signal summary_ready(summary: Dictionary)

var net: NetSession
var running: bool = true
var _first: Dictionary = {}
var _last_tick_time: float = 0.0
var _summary: Dictionary = {}
var _want_summary: bool = false


func setup(p_net: NetSession, first: Dictionary) -> void:
	net = p_net
	_first = first


func begin() -> void:
	_last_tick_time = Time.get_ticks_msec() / 1000.0
	ticked.emit(_first)


func on_snapshot(s: Dictionary) -> void:
	_last_tick_time = Time.get_ticks_msec() / 1000.0
	if str(s.get("phase", "")) == "over":
		running = false
	ticked.emit(s)


func on_summary(s: Dictionary) -> void:
	_summary = s
	if _want_summary:
		summary_ready.emit(_summary)


func tick_progress() -> float:
	return clampf((Time.get_ticks_msec() / 1000.0 - _last_tick_time) / 0.6, 0.0, 1.0)


func submit(intent: Dictionary) -> void:
	net.send_intent_to_host(intent)


func change_class(class_def: Dictionary, levels: Dictionary) -> void:
	net.send_class_to_host(class_def, levels)


func request_summary(forfeit: bool) -> void:
	running = false
	_want_summary = true
	if not _summary.is_empty():
		summary_ready.emit(_summary)
	elif forfeit:
		net.send_leave_to_host()


## Host vanished: finish with an empty summary so the client returns to the menu.
func host_lost() -> void:
	running = false
	_summary = {"mode_name": "Disconnected", "map": "", "rows": [], "scores": [0, 0], "won": false, "forfeit": true, "winner": -1}
	_want_summary = true
	summary_ready.emit(_summary)
