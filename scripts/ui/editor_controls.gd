extends VBoxContainer

signal mode_changed
signal tool_changed
signal save_requested
signal load_requested

const Target := preload("res://scripts/destruction/range_target.gd")
enum Tool { ADD, ROTATE, REMOVE, MOVE, DUPLICATE, HEIGHT }

var _toggle: Button
var _options: VBoxContainer
var _tool: OptionButton
var _catalog: OptionButton
var _note: Label
var _height: SpinBox
var _snap: CheckButton

func _ready() -> void:
	_toggle = Button.new()
	_toggle.text = "Редактор полигона"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.toggle_mode = true
	add_child(_toggle)
	_options = VBoxContainer.new()
	add_child(_options)
	_options.hide()
	_tool = OptionButton.new()
	for title in ["Разместить", "Повернуть на 15°", "Удалить", "Переместить", "Дублировать", "Изменить высоту"]:
		_tool.add_item(title)
	_options.add_child(_tool)
	_catalog = OptionButton.new()
	for title in Target.NAMES:
		_catalog.add_item(title)
	_options.add_child(_catalog)
	var settings := HBoxContainer.new()
	_options.add_child(settings)
	_snap = CheckButton.new()
	_snap.text = "Сетка 1 м"
	_snap.button_pressed = true
	settings.add_child(_snap)
	_height = SpinBox.new()
	_height.custom_minimum_size.x = 88
	_height.max_value = 12.0
	_height.step = 0.25
	_height.suffix = tr("м")
	_height.tooltip_text = "Высота нового объекта или инструмента изменения высоты"
	settings.add_child(_height)
	var buttons := HBoxContainer.new()
	_options.add_child(buttons)
	var save := Button.new()
	save.text = "Сохранить"
	buttons.add_child(save)
	save.pressed.connect(func() -> void: save_requested.emit())
	var load_map := Button.new()
	load_map.text = "Загрузить"
	buttons.add_child(load_map)
	load_map.pressed.connect(func() -> void: load_requested.emit())
	_note = Label.new()
	_note.text = "ЛКМ по площадке"
	_options.add_child(_note)
	_tool.item_selected.connect(func(_index: int) -> void:
		_catalog.disabled = tool() != Tool.ADD
		tool_changed.emit())
	_toggle.toggled.connect(func(enabled: bool) -> void:
		_options.visible = enabled
		mode_changed.emit())

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_height):
		_height.suffix = tr("м")

func active() -> bool:
	return _toggle.button_pressed

func tool() -> int:
	return _tool.selected

func kind() -> int:
	return _catalog.selected

func height() -> float:
	return _height.value

func snap_enabled() -> bool:
	return _snap.button_pressed

func set_locked(lock: bool) -> void:
	_toggle.disabled = lock
	if lock:
		_toggle.set_pressed_no_signal(false)
		_options.hide()

func show_message(message: String) -> void:
	_note.text = message
