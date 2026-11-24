extends CanvasLayer

signal dismissed
signal main_menu_requested
signal settings_changed(values: Dictionary)

const Settings := preload("res://scripts/core/game_settings.gd")
const Terminal := preload("res://scripts/ui/terminal_theme.gd")

var _values := {}
var _pause_actions: VBoxContainer
var _continue: Button
var _settings: VBoxContainer
var _status: Label
var _tabs: TabContainer
var _pause_available := false
var dock: Control
var _center: CenterContainer

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = Settings.read()
	if dock == null:
		var scrim := ColorRect.new()
		scrim.color = Color("#120c06cf")
		add_child(scrim)
		scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_center = center
	add_child(center)
	if dock == null:
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		dock.item_rect_changed.connect(_align_dock)
		_align_dock.call_deferred()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.theme = Terminal.create()
	panel.add_theme_stylebox_override("panel", Terminal.box(Color("#18130dfd"), Terminal.ACCENT, 22, 20))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	_pause_actions = VBoxContainer.new()
	_pause_actions.custom_minimum_size.x = 320
	_pause_actions.add_theme_constant_override("separation", 10)
	column.add_child(_pause_actions)
	_label(_pause_actions, "ПАУЗА", 28)
	_continue = _button(_pause_actions, "Продолжить", close)
	_continue.theme_type_variation = &"TerminalPrimary"
	_button(_pause_actions, "Настройки", open_settings)
	_button(_pause_actions, "В главное меню", func() -> void: main_menu_requested.emit())
	_settings = VBoxContainer.new()
	_settings.custom_minimum_size.x = 455 if dock != null else 560
	_settings.add_theme_constant_override("separation", 10)
	column.add_child(_settings)
	_build_settings()
	if dock != null:
		_pause_actions.hide()
	hide()

func _align_dock() -> void:
	_center.position = dock.get_global_rect().position
	_center.size = dock.size

func open_pause() -> void:
	_pause_available = true
	_settings.hide()
	_pause_actions.show()
	show()
	_continue.grab_focus()

func open_settings() -> void:
	_pause_actions.hide()
	_settings.show()
	_status.text = ""
	show()
	if dock != null:
		_align_dock.call_deferred()
	_tabs.get_tab_bar().grab_focus()

func close() -> void:
	hide()
	_pause_available = false
	dismissed.emit()

func _back() -> void:
	if _pause_available and _settings.visible:
		open_pause()
	else:
		close()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_back()

func _build_settings() -> void:
	_label(_settings, "НАСТРОЙКИ", 27)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.y = 318 if dock != null else 390
	_settings.add_child(_tabs)
	var graphics := _tab(_tabs, "Графика")
	_heading(graphics, "Экран")
	_toggle(graphics, "fullscreen", "Полный экран")
	_toggle(graphics, "vsync", "Вертикальная синхронизация")
	_options(graphics, "frame_limit", "Лимит кадров", ["Без ограничения", "30", "60", "120", "144"])
	_options(graphics, "render_scale", "Масштаб 3D", ["67%", "80%", "100%", "125%", "150%"])
	_heading(graphics, "Сглаживание")
	var msaa_levels := ["Выкл.", "2×", "4×", "8×"]
	var max_msaa := Settings.max_msaa()
	_options(graphics, "msaa", "MSAA", msaa_levels.slice(0, max_msaa + 1))
	if max_msaa < Viewport.MSAA_8X:
		_label(graphics, "На этой видеокарте в Vulkan доступны режимы до 2×.", 14).modulate = Terminal.MUTED
	_toggle(graphics, "debanding", "Плавные цветовые переходы")
	_heading(graphics, "Освещение и эффекты")
	_options(graphics, "shadow_quality", "Дальность динамических теней",
		["Выкл.", "Ближние", "Стандартные", "Дальние"])
	_toggle(graphics, "cloud_shadows", "Тени от дыма взрыва")
	_toggle(graphics, "ao", "Контактное затенение (SSAO)")
	_toggle(graphics, "ssil", "Рассеянное освещение (SSIL)")
	_toggle(graphics, "glow", "Свечение")
	_options(graphics, "effect_quality", "Объёмные эффекты", ["4K", "8K", "12K"])
	_toggle(graphics, "adaptive_effects", "Снижать качество дыма при просадке кадров")
	if dock == null:
		var hint := _label(graphics, "Настройки объёмных эффектов действуют со следующего подрыва.", 14)
		hint.modulate = Terminal.MUTED
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toggle(graphics, "camera_kick", "Толчок камеры от ударной волны")
	var sound := _tab(_tabs, "Звук")
	_volume(sound, "volume", "Общая громкость")
	_volume(sound, "thunder_volume", "Раскаты грома")
	var language := _tab(_tabs, "Язык")
	_options(language, "language", "Язык", ["Русский", "English"])
	var footer := HBoxContainer.new()
	_settings.add_child(footer)
	_status = _label(footer, "", 14)
	_status.modulate = Terminal.ACCENT
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(footer, "Назад", _back)

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	return content

func _toggle(parent: Container, key: String, caption: String) -> void:
	var control := CheckButton.new()
	control.name = key
	control.text = caption
	control.button_pressed = _values[key]
	parent.add_child(control)
	control.toggled.connect(_update.bind(key))

func _options(parent: Container, key: String, caption: String, labels: Array) -> void:
	var row := _row(parent, caption)
	var control := OptionButton.new()
	control.name = key
	control.custom_minimum_size.x = 172
	for label: String in labels:
		control.add_item(label)
	control.select(Settings.LANGUAGES.find(_values[key]) if key == "language" else int(_values[key]))
	row.add_child(control)
	control.item_selected.connect(func(index: int) -> void:
		_update(Settings.LANGUAGES[index] if key == "language" else index, key))

func _volume(parent: Container, key: String, caption: String) -> void:
	var row := _row(parent, caption)
	var control := HSlider.new()
	control.name = key
	control.step = 0.01
	control.max_value = 1.0
	control.value = _values[key]
	control.custom_minimum_size = Vector2(120, 28)
	row.add_child(control)
	var percent := _label(row, "%d%%" % roundi(control.value * 100.0), 14)
	percent.custom_minimum_size.x = 44
	control.value_changed.connect(func(value: float) -> void:
		percent.text = "%d%%" % roundi(value * 100.0)
		_update(value, key))

func _update(value: Variant, key: String) -> void:
	_values[key] = value
	Settings.apply(_values, get_window())
	settings_changed.emit(_values)
	var result := Settings.save(_values)
	_status.text = "Сохранено" if result == OK else tr("Ошибка сохранения (%d)") % result

func _row(parent: Container, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := _label(row, caption)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row

func _heading(parent: Container, title: String) -> void:
	var label := _label(parent, title, 15)
	label.modulate = Terminal.ACCENT

func _label(parent: Container, text: String, size := 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Terminal.INK)
	parent.add_child(label)
	return label

func _button(parent: Container, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	return button
