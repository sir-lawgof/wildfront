class_name Orb
extends Control
## OSRS-style status orb (HP, prayer, run energy, special attack). Clickable.

signal clicked

var value: float = 0.0
var max_value: float = 100.0
var fill_color: Color = Color.RED
var icon_text: String = ""
var active: bool = false
var label_text: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(84, 40)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_value(v: float, mx: float, txt: String = "") -> void:
	if v == value and mx == max_value and txt == label_text:
		return
	value = v
	max_value = mx
	label_text = txt
	queue_redraw()


func set_active(a: bool) -> void:
	if a != active:
		active = a
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()


func _draw() -> void:
	var r := 17.0
	var c := Vector2(size.x - r - 2, size.y / 2.0)
	# Number plate to the left of the orb.
	draw_rect(Rect2(0, c.y - 11, size.x - r * 2 - 2, 22), Color(0.1, 0.08, 0.05, 0.85))
	var f := get_theme_default_font()
	var frac := clampf(value / maxf(max_value, 1.0), 0.0, 1.0)
	var num_col := Color("00ff00").lerp(Color("ff0000"), 1.0 - frac) if frac < 1.0 else Color("00ff00")
	var txt := label_text if label_text != "" else str(int(value))
	draw_string(f, Vector2(4, c.y + 6), txt, HORIZONTAL_ALIGNMENT_RIGHT, size.x - r * 2 - 10, 16, num_col)
	# Orb body.
	draw_circle(c, r + 2, Color("1a160f"))
	draw_circle(c, r, Color(0.12, 0.12, 0.12))
	# Fill from the bottom.
	var top := c.y + r - 2.0 * r * frac
	var pts := PackedVector2Array()
	for i in range(33):
		var a := PI * 0.5 + TAU * i / 32.0
		var p := c + Vector2(cos(a), sin(a)) * r
		pts.append(Vector2(p.x, maxf(p.y, top)))
	draw_colored_polygon(pts, fill_color.darkened(0.15 if not active else -0.2))
	if active:
		draw_arc(c, r + 1, 0, TAU, 32, Color("ffff66"), 2.0)
	draw_string(f, c + Vector2(-5, 6), icon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9))
