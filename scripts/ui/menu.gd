extends Node

const Settings := preload("res://scripts/core/game_settings.gd")
const SettingsOverlay := preload("res://scripts/ui/settings_overlay.gd")
const Terminal := preload("res://scripts/ui/terminal_theme.gd")
const MenuPreview := preload("res://scripts/ui/menu_preview.gd")
const SCANLINES := preload("res://assets/shaders/terminal_scanlines.gdshader")
const MAP_PATH := "res://scenes/main/range.tscn"

var _menu_actions: VBoxContainer
var _overlay: SettingsOverlay

func _ready() -> void:
	Settings.apply(Settings.read(), get_window())
	var layer := CanvasLayer.new()
	add_child(layer)

	var background := ColorRect.new()
	background.color = Color("#150f09")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var surround := MarginContainer.new()
	surround.theme = Terminal.create()
	layer.add_child(surround)
	surround.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surround.add_theme_constant_override("margin_left", 50)
	surround.add_theme_constant_override("margin_right", 50)
	surround.add_theme_constant_override("margin_top", 40)
	surround.add_theme_constant_override("margin_bottom", 40)

	var enclosure := PanelContainer.new()
	var bezel := Terminal.box(Color("#2b2117"), Color("#755532"), 16, 14)
	bezel.shadow_color = Color("#060402c9")
	bezel.shadow_offset = Vector2(0.0,8.0)
	bezel.shadow_size = 15
	enclosure.add_theme_stylebox_override("panel", bezel)
	surround.add_child(enclosure)

	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", Terminal.box(Color("#100e0a"),Terminal.EDGE,26,19))
	enclosure.add_child(screen)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 15)
	screen.add_child(stack)

	var header := HBoxContainer.new()
	stack.add_child(header)
	var heading := _label(header,"■  КОНСОЛЬ УПРАВЛЕНИЯ",16,Terminal.ACCENT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(header,"TR-01",16,Terminal.MUTED)
	_rule(stack)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(body)
	var command := VBoxContainer.new()
	command.custom_minimum_size.x = 510
	command.alignment = BoxContainer.ALIGNMENT_CENTER
	command.add_theme_constant_override("separation", 17)
	body.add_child(command)
	_label(command,"ИСПЫТАТЕЛЬНЫЙ ПОЛИГОН",15,Terminal.ACCENT)
	var title := _label(command,"EXPLOSION\nTEST RANGE",56,Terminal.INK)
	title.add_theme_constant_override("line_spacing",-6)

	var commands_area := Control.new()
	commands_area.custom_minimum_size = Vector2(300, 150)
	commands_area.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	command.add_child(commands_area)
	_menu_actions = VBoxContainer.new()
	_menu_actions.add_theme_constant_override("separation", 9)
	commands_area.add_child(_menu_actions)
	_menu_actions.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var play := _command("Полигон", true)
	play.pressed.connect(_start)
	var open_settings := _command("Настройки", false)
	var leave := _command("Выход", false)
	leave.pressed.connect(func() -> void: get_tree().quit())

	var map := PanelContainer.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.add_theme_stylebox_override("panel", Terminal.box(Color("#17120b"),Terminal.EDGE,13,11))
	body.add_child(map)
	var map_column := VBoxContainer.new()
	map_column.add_theme_constant_override("separation", 8)
	map.add_child(map_column)
	var preview_header := HBoxContainer.new()
	map_column.add_child(preview_header)
	var preview_title := _label(preview_header,"ПРЕДПРОСМОТР ВЗРЫВА",15,Terminal.ACCENT)
	preview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(preview_header,"ПАУЗА",14,Terminal.MUTED)
	var preview := MenuPreview.new()
	preview.z_index = 1
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_column.add_child(preview)

	_rule(stack)
	var footer := HBoxContainer.new()
	stack.add_child(footer)
	var navigation := _label(footer,"↑ ↓  ВЫБОР",14,Terminal.MUTED)
	navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(footer,"ENTER  ВЫПОЛНИТЬ",14,Terminal.MUTED)

	var scanlines := ColorRect.new()
	var crt := ShaderMaterial.new()
	crt.shader = SCANLINES
	scanlines.material = crt
	scanlines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(scanlines)
	scanlines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_overlay = SettingsOverlay.new()
	_overlay.dock = command
	add_child(_overlay)
	_overlay.settings_changed.connect(preview.apply_graphics)
	_overlay.dismissed.connect(func() -> void:
		command.modulate.a = 1.0
		_menu_actions.show()
		open_settings.grab_focus())
	open_settings.pressed.connect(func() -> void:
		command.modulate.a = 0.0
		_menu_actions.hide()
		_overlay.open_settings())
	play.grab_focus()

func _start() -> void:
	get_tree().change_scene_to_file(MAP_PATH)

func _label(parent: Container, caption: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _rule(parent: Container) -> void:
	var line := ColorRect.new()
	line.color = Terminal.EDGE
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func _command(caption: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = caption
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size",18)
	if primary:
		button.theme_type_variation = &"TerminalPrimary"
	_menu_actions.add_child(button)
	return button
