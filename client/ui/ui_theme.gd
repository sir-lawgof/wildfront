class_name UITheme
extends RefCounted
## OSRS-flavoured UI theme built in code: brown stone panels, orange/yellow text.

const GOLD := Color("ff981f")
const YELLOW := Color("ffff00")
const CREAM := Color("e8dcc0")
const PANEL := Color("3e3529")
const PANEL_DARK := Color("2a241c")
const PANEL_LIGHT := Color("5a4d3b")
const BORDER := Color("1a160f")
const BLUE := Color("4aa3ff")
const RED := Color("ff4040")
const GREEN := Color("3fd13f")
const CB_BLUE := Color("3a8fff")
const CB_ORANGE := Color("ff9a1f")

static var _theme: Theme
static var colorblind: bool = false


static func team_color(team: int, my_team: int, ffa: bool = false) -> Color:
	var ally := CB_BLUE if colorblind else BLUE
	var enemy := CB_ORANGE if colorblind else RED
	if ffa:
		return enemy
	return ally if team == my_team else enemy


static func box(bg: Color, border: Color = BORDER, width: int = 2, radius: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_stylebox("panel", "Panel", box(PANEL))
	t.set_stylebox("panel", "PanelContainer", box(PANEL))
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT))
	t.set_stylebox("hover", "Button", box(PANEL_LIGHT.lightened(0.15), GOLD))
	t.set_stylebox("pressed", "Button", box(PANEL_DARK, GOLD))
	t.set_stylebox("disabled", "Button", box(PANEL_DARK.darkened(0.2)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", GOLD)
	t.set_color("font_hover_color", "Button", YELLOW)
	t.set_color("font_pressed_color", "Button", YELLOW)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.45, 0.38))
	t.set_stylebox("normal", "LineEdit", box(PANEL_DARK))
	t.set_stylebox("focus", "LineEdit", box(PANEL_DARK, GOLD))
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_stylebox("normal", "OptionButton", box(PANEL_LIGHT))
	t.set_stylebox("hover", "OptionButton", box(PANEL_LIGHT.lightened(0.15), GOLD))
	t.set_stylebox("pressed", "OptionButton", box(PANEL_DARK, GOLD))
	t.set_color("font_color", "OptionButton", GOLD)
	t.set_stylebox("panel", "PopupMenu", box(PANEL_DARK, GOLD))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", YELLOW)
	t.set_stylebox("hover", "PopupMenu", box(PANEL_LIGHT, PANEL_LIGHT, 0, 0))
	t.set_stylebox("panel", "TooltipPanel", box(Color("fffbd8"), BORDER, 1))
	t.set_color("font_color", "TooltipLabel", Color.BLACK)
	t.set_stylebox("background", "ProgressBar", box(PANEL_DARK))
	t.set_stylebox("fill", "ProgressBar", box(GREEN.darkened(0.2), GREEN.darkened(0.4), 1))
	t.set_stylebox("panel", "TabContainer", box(PANEL))
	t.set_stylebox("tab_selected", "TabContainer", box(PANEL_LIGHT, GOLD))
	t.set_stylebox("tab_unselected", "TabContainer", box(PANEL_DARK))
	t.set_stylebox("tab_hovered", "TabContainer", box(PANEL_LIGHT))
	t.set_color("font_selected_color", "TabContainer", YELLOW)
	t.set_color("font_unselected_color", "TabContainer", GOLD)
	t.set_color("font_hovered_color", "TabContainer", YELLOW)
	t.set_color("default_color", "RichTextLabel", CREAM)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", CREAM)
	t.set_color("font_hover_color", "CheckBox", YELLOW)
	t.set_color("font_pressed_color", "CheckBox", CREAM)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t


static func label(text: String, size: int = 16, color: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	return b


static func style_color(style: String) -> Color:
	return {"melee": Color("e04a3a"), "ranged": Color("4fbf4f"), "magic": Color("4f8fff"), "combat": Color("ffd23f"), "split": Color("e8dcc0")}.get(style, CREAM)
