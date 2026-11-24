extends RefCounted

const INK := Color("#ffd89c")
const MUTED := Color("#b99870")
const ACCENT := Color("#ffb95e")
const AMBER_DARK := Color("#171006")
const PANEL := Color("#17140ef7")
const SURFACE := Color("#241b11")
const EDGE := Color("#684928")
const DISABLED := Color("#968366")

static func create(font_size := 16) -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Liberation Mono", "Courier New"])
	theme.default_font = font
	theme.default_font_size = font_size
	theme.set_color("font_color", "Label", INK)
	theme.set_stylebox("panel", "PanelContainer", box(PANEL, EDGE, 10, 9))
	for type in ["Button", "OptionButton", "CheckButton", "LineEdit"]:
		theme.set_color("font_color", type, INK)
		theme.set_color("font_hover_color", type, ACCENT)
		theme.set_color("font_focus_color", type, INK)
		theme.set_color("font_pressed_color", type, ACCENT)
		theme.set_color("font_disabled_color", type, DISABLED)
		theme.set_stylebox("normal", type, box(SURFACE, EDGE, 9, 5))
		theme.set_stylebox("hover", type, box(Color("#382719"), ACCENT, 9, 5))
		theme.set_stylebox("pressed", type, box(Color("#3f2c19"), ACCENT, 9, 5))
		theme.set_stylebox("disabled", type, box(Color("#1a1510"), Color("#43321e"), 9, 5))
		theme.set_stylebox("focus", type, outline(ACCENT))
	theme.set_color("font_uneditable_color", "LineEdit", DISABLED)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color("#805628"))
	theme.set_type_variation("TerminalPrimary", "Button")
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		theme.set_color(state, "TerminalPrimary", AMBER_DARK)
	theme.set_stylebox("normal", "TerminalPrimary", box(ACCENT, INK, 9, 5))
	theme.set_stylebox("hover", "TerminalPrimary", box(INK, INK, 9, 5))
	theme.set_stylebox("pressed", "TerminalPrimary", box(Color("#c68740"), INK, 9, 5))
	var focus := outline(Color("#fff0ca"))
	focus.set_expand_margin_all(2)
	theme.set_stylebox("focus", "TerminalPrimary", focus)
	theme.set_stylebox("panel", "PopupMenu", box(PANEL, EDGE, 8, 7))
	theme.set_stylebox("hover", "PopupMenu", box(Color("#3f2c19"), EDGE, 3, 2))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", ACCENT)
	theme.set_color("font_disabled_color", "PopupMenu", DISABLED)
	theme.set_stylebox("panel", "TabContainer", box(Color("#15110c"), EDGE))
	for style: String in ["tab_selected", "tab_hovered", "tab_unselected"]:
		var active := style == "tab_selected"
		theme.set_stylebox(style, "TabContainer", box(Color("#3f2c19") if active else SURFACE,
			ACCENT if active else EDGE, 14, 7))
	theme.set_color("font_selected_color", "TabContainer", ACCENT)
	theme.set_color("font_unselected_color", "TabContainer", MUTED)
	theme.set_stylebox("background", "ProgressBar", box(Color("#272016"), EDGE))
	theme.set_stylebox("fill", "ProgressBar", box(ACCENT, ACCENT))
	theme.set_stylebox("slider", "HSlider", box(Color("#272016"), EDGE, 0, 2))
	theme.set_stylebox("grabber_area", "HSlider", box(Color("#8a5b2a"), EDGE))
	theme.set_stylebox("grabber_area_highlight", "HSlider", box(Color("#a16c32"), EDGE))
	theme.set_icon("grabber", "HSlider", _block(Vector2i(9,16), ACCENT))
	theme.set_icon("grabber_highlight", "HSlider", _block(Vector2i(9,16), INK))
	theme.set_icon("grabber_disabled", "HSlider", _block(Vector2i(9,16), DISABLED))
	theme.set_stylebox("scroll", "VScrollBar", box(AMBER_DARK, EDGE, 4, 0))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(state, "VScrollBar", box(Color("#9c6a35"), EDGE, 4, 0))
	for type in ["CheckButton", "CheckBox"]:
		for state in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
			theme.set_icon(state, type, _checkbox(state.begins_with("checked"), state.ends_with("disabled")))
	theme.set_icon("arrow", "OptionButton", _arrow())
	for direction: String in ["up", "down"]:
		for state: String in ["", "_hover", "_pressed", "_disabled"]:
			var color := DISABLED if state == "_disabled" else (ACCENT if state.is_empty() else INK)
			theme.set_icon(direction+state, "SpinBox", _arrow(direction == "up", color))
	theme.set_stylebox("panel", "TooltipPanel", box(PANEL, EDGE, 7, 5))
	theme.set_color("font_color", "TooltipLabel", INK)
	return theme

static func box(fill: Color, border: Color, padding_x := 0, padding_y := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = padding_x
	style.content_margin_right = padding_x
	style.content_margin_top = padding_y
	style.content_margin_bottom = padding_y
	return style

static func outline(color: Color) -> StyleBoxFlat:
	var style := box(Color.TRANSPARENT, color)
	style.draw_center = false
	return style

static func _block(dimensions: Vector2i, color: Color) -> ImageTexture:
	var icon := Image.create_empty(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	icon.fill(color)
	return ImageTexture.create_from_image(icon)

static func _checkbox(checked: bool, disabled: bool) -> ImageTexture:
	var icon := Image.create_empty(15, 15, false, Image.FORMAT_RGBA8)
	var color := DISABLED if disabled else ACCENT
	icon.fill(color)
	icon.fill_rect(Rect2i(1,1,13,13), AMBER_DARK)
	if checked:
		icon.fill_rect(Rect2i(4,4,7,7), color)
	return ImageTexture.create_from_image(icon)

static func _arrow(up := false, color := ACCENT) -> ImageTexture:
	var icon := Image.create_empty(11, 7, false, Image.FORMAT_RGBA8)
	for row in 4:
		icon.fill_rect(Rect2i(row+1,5-row if up else row+1,9-row*2,1), color)
	return ImageTexture.create_from_image(icon)
