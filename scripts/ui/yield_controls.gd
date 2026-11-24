extends VBoxContainer

signal yield_changed(kg: float)

const Catalog := preload("res://scripts/explosions/yield_catalog.gd")
const SAVE_PATH := "user://power_preset.cfg"
var kg := 100.0
var show_presets := true
var _saved := 0.0
var _slider: HSlider
var _entry: LineEdit
var _units: OptionButton
var _presets: OptionButton
var _class: Label
var _remember: Button
var _locked := false

func _ready() -> void:
	_class = Label.new()
	add_child(_class)
	_slider = HSlider.new()
	_slider.step = 0.0001
	_slider.max_value = 1.0
	_slider.custom_minimum_size.y = 22.0
	_slider.tooltip_text = "Логарифмическая шкала 50 кг — 100 Мт"
	add_child(_slider)
	var entry_row := HBoxContainer.new()
	add_child(entry_row)
	_entry = LineEdit.new()
	_entry.add_theme_constant_override("minimum_character_width",6)
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.tooltip_text = "Введите значение и нажмите Enter"
	entry_row.add_child(_entry)
	_units = OptionButton.new()
	for unit in Catalog.UNITS:
		_units.add_item(unit)
	entry_row.add_child(_units)
	var presets_row := HBoxContainer.new()
	presets_row.visible = show_presets
	add_child(presets_row)
	_presets = OptionButton.new()
	_presets.fit_to_longest_item = false
	_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	presets_row.add_child(_presets)
	_remember = Button.new()
	_remember.text = "Запомнить"
	_remember.add_theme_font_size_override("font_size",13)
	_remember.tooltip_text = "Сохранить мощность как пользовательский пресет"
	presets_row.add_child(_remember)
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var saved: Variant = config.get_value("preset", "kg", 0.0)
		if (saved is float or saved is int) and is_finite(float(saved)) and float(saved) >= Catalog.MIN_KG:
			_saved = clampf(float(saved), Catalog.MIN_KG, Catalog.MAX_KG)
	_rebuild_presets()
	_set_value(kg)
	_slider.value_changed.connect(func(value: float) -> void: _set_value(Catalog.from_slider(value)))
	_units.item_selected.connect(func(index: int) -> void:
		_entry.text = String.num(kg / Catalog.UNIT_FACTORS[index], 12))
	_entry.text_submitted.connect(func(_value: String) -> void:
		_commit_entry()
		_entry.release_focus())
	_entry.focus_exited.connect(_commit_entry)
	_presets.item_selected.connect(_choose_preset)
	_remember.pressed.connect(_save_preset)

func reflect_value(value: float) -> void:
	_set_value(value, false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_class.text = tr("Мощность  ·  класс %s") % Catalog.CLASSES[Catalog.tier_for(kg)]
		_rebuild_presets()

func set_locked(value: bool) -> void:
	_locked = value
	_slider.editable = not value
	_entry.editable = not value
	_units.disabled = value
	_presets.disabled = value
	_remember.disabled = value

func _set_value(value: float, notify: bool = true) -> void:
	if _locked and notify:
		return
	var bounded := clampf(roundf(value), Catalog.MIN_KG, Catalog.MAX_KG)
	var modified := bounded != kg
	kg = bounded
	var index := Catalog.unit_index(kg)
	_slider.set_value_no_signal(Catalog.normalized(kg))
	_entry.text = String.num(kg / Catalog.UNIT_FACTORS[index], 12)
	_units.select(index)
	_class.text = tr("Мощность  ·  класс %s") % Catalog.CLASSES[Catalog.tier_for(kg)]
	if modified and notify:
		yield_changed.emit(kg)

func _commit_entry() -> void:
	if _locked:
		return
	var raw := _entry.text.strip_edges().replace(",", ".")
	var value: float = raw.to_float() * Catalog.UNIT_FACTORS[_units.selected]
	_set_value(value if raw.is_valid_float() and is_finite(value) else kg)

func _rebuild_presets() -> void:
	_presets.clear()
	_presets.add_item("Пресеты")
	_presets.set_item_disabled(0, true)
	for value in Catalog.QUICK_VALUES:
		_presets.add_item(Catalog.label(value))
	if _saved >= Catalog.MIN_KG:
		_presets.add_item(tr("Мой пресет · ") + Catalog.label(_saved))
	_presets.select(0)

func _choose_preset(index: int) -> void:
	if index == 0:
		return
	_set_value(Catalog.QUICK_VALUES[index - 1] if index <= Catalog.QUICK_VALUES.size() else _saved)
	_presets.select(0)

func _save_preset() -> void:
	var config := ConfigFile.new()
	config.set_value("preset", "kg", kg)
	if config.save(SAVE_PATH) == OK:
		_saved = kg
		_remember.tooltip_text = tr("Сохранено: ") + Catalog.label(_saved)
		_rebuild_presets()
	else:
		_remember.tooltip_text = "Не удалось записать пресет"
