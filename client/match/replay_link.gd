class_name ReplayLink
extends Node
## U8 replay playback. Same interface as MatchServer / RemoteLink, so the normal MatchView renders it. Re-runs the
## recorded match on the shared simulation and shows a spectator view (everyone's HP, prayer and special energy).
## Controls: a bottom bar with play/pause, speed and a timeline scrubber. Seeking re-simulates from the start.

signal ticked(snapshot: Dictionary)
signal summary_ready(summary: Dictionary)

var rec: Dictionary = {}
var core: MatchServerCore
var running: bool = true
var paused: bool = false
var speed: float = 1.0
var _by_tick: Dictionary = {}
var _acc: float = 0.0
var _tick_len: float = 0.6
var _bar: CanvasLayer
var _slider: HSlider
var _time: Label
var _play_btn: Button
var _speed_btn: Button
var _dragging: bool = false


func setup(p_rec: Dictionary) -> void:
	rec = p_rec
	_by_tick = Replay.index(rec)


func begin() -> void:
	_tick_len = float(DB.rule("tick_seconds", 0.6))
	core = Replay.simulate(rec, 0)
	_build_bar()
	ticked.emit(_snap())


func _snap() -> Dictionary:
	return core.sim.snapshot(-1, true)


func _process(delta: float) -> void:
	if core == null:
		return
	_update_bar()
	if paused or not running:
		return
	_acc += delta * speed
	var guard := 0
	while _acc >= _tick_len and guard < 8:
		_acc -= _tick_len
		guard += 1
		if core.sim.tick >= int(rec.get("ticks", 0)) or core.sim.phase == "over":
			paused = true
			break
		Replay.step(core, _by_tick)
		ticked.emit(_snap())


## Jumps to a tick by re-simulating (fast: no rendering in between).
func seek(t: int) -> void:
	core = Replay.simulate(rec, clampi(t, 0, int(rec.get("ticks", 0))))
	_acc = 0.0
	ticked.emit(_snap())


func tick_progress() -> float:
	return 1.0 if paused else clampf(_acc / _tick_len, 0.0, 1.0)


func submit(_intent: Dictionary) -> void:
	pass


func change_class(_class_def: Dictionary, _levels: Dictionary) -> void:
	pass


func request_summary(_forfeit: bool) -> void:
	running = false
	if _bar != null:
		_bar.queue_free()
	summary_ready.emit.call_deferred({"replay_view": true})


# ---------------------------------------------------------------- controls

func _build_bar() -> void:
	_bar = CanvasLayer.new()
	_bar.layer = 20
	add_child(_bar)
	var panel := PanelContainer.new()
	panel.theme = UITheme.get_theme()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -64
	panel.offset_bottom = -12
	_bar.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	panel.add_child(hb)
	_play_btn = UITheme.button("Pause", func():
		paused = not paused
		if not paused and core.sim.tick >= int(rec.get("ticks", 0)):
			seek(0)
			paused = false)
	_play_btn.custom_minimum_size.x = 80
	hb.add_child(_play_btn)
	_speed_btn = UITheme.button("1x", func():
		speed = {1.0: 2.0, 2.0: 4.0, 4.0: 0.5, 0.5: 1.0}.get(speed, 1.0)
		_speed_btn.text = ("%sx" % str(speed)).replace(".0x", "x"))
	_speed_btn.custom_minimum_size.x = 56
	hb.add_child(_speed_btn)
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = maxi(1, int(rec.get("ticks", 1)))
	_slider.step = 1
	_slider.custom_minimum_size = Vector2(340, 24)
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.drag_started.connect(func(): _dragging = true)
	_slider.drag_ended.connect(func(_changed): _dragging = false; seek(int(_slider.value)))
	hb.add_child(_slider)
	_time = UITheme.label("", 14)
	_time.custom_minimum_size.x = 110
	hb.add_child(_time)
	var help := UITheme.label("F free cam  [ ] follow", 12, UITheme.CREAM)
	hb.add_child(help)


func _update_bar() -> void:
	if _slider == null:
		return
	var t := core.sim.tick
	if not _dragging:
		_slider.set_value_no_signal(t)
	var secs := int(t * _tick_len)
	var total := int(int(rec.get("ticks", 0)) * _tick_len)
	_time.text = "%d:%02d / %d:%02d" % [secs / 60, secs % 60, total / 60, total % 60]
	_play_btn.text = "Play" if paused else "Pause"
