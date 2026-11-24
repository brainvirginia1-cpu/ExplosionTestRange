extends CanvasLayer

signal atmosphere_changed
signal injuries_requested
var conditions: Array[OptionButton] = []
var wind_speed := OptionButton.new()
var wind_direction := OptionButton.new()
const WIND_SPEEDS := [0.0, 5.0, 13.0, 24.0]

signal run_requested
signal reset_requested
signal speed_selected(index: int)
signal blast_selected(mode: int)
signal power_changed(kg: float)
const Device := preload("res://scripts/devices/trial_device.gd")
const BLAST_NAMES := ["Наземный","Термобарический","Подземный"]

const EditorControls := preload("res://scripts/ui/editor_controls.gd")

const YieldControls := preload("res://scripts/ui/yield_controls.gd")

var editor: EditorControls
const SPEEDS := [0.0, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0]
var _slow: OptionButton
var blast_picker := OptionButton.new()
var power_control: YieldControls
var depth_control: HSlider
var _depth_row: VBoxContainer
var _result: Label
var device_title: String
var _title: Label
var _flash: ColorRect
var _coordinates: Label
var _altitude: Label
var _observer: Label
var _injury_card: PanelContainer
var _injury_button: Button
var _injury_labels: Array[Label] = []
var _injury_bars: Array[ProgressBar] = []
var _injury_summary: Label
var _acoustics: Label
var _status: Label
var _run: Button
var _reset: Button
const Terminal := preload("res://scripts/ui/terminal_theme.gd")

func _ready() -> void:
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.theme = Terminal.create(14)
	add_child(canvas)

	var left := _card(canvas,Vector2.ZERO,Vector2(16,16),Vector2(232,0))
	var telemetry := _section(left,"Телеметрия")
	_title = _label(telemetry,device_title,17)
	_status = _label(telemetry,"",13,Terminal.ACCENT)
	_status.tooltip_text = "Y · Повтор последнего испытания"
	_coordinates = _label(telemetry,"",12,Terminal.MUTED)
	_altitude = _label(telemetry,"",12,Terminal.MUTED)
	_acoustics = _label(telemetry,"",13,Terminal.MUTED)
	_observer = _label(telemetry,"",13,Terminal.ACCENT)
	_observer.hide()
	_injury_button = _button(telemetry,"Травмы · H",false)
	_injury_button.pressed.connect(func() -> void: injuries_requested.emit())
	_injury_button.hide()
	_result = _label(telemetry,"",12,Terminal.MUTED)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.hide()

	var edit_section := _section(left,"Полигон")
	editor = EditorControls.new()
	edit_section.add_child(editor)

	var inspector := _card(canvas,Vector2(1,0),Vector2(-280,16),Vector2(264,0))
	var blast := _section(inspector,"Взрыв")
	blast_picker.focus_mode = Control.FOCUS_NONE
	blast_picker.tooltip_text = "Тип взрыва"
	for caption in BLAST_NAMES:
		blast_picker.add_item(caption)
	blast_picker.item_selected.connect(func(mode: int) -> void: blast_selected.emit(mode))
	blast.add_child(blast_picker)
	power_control = YieldControls.new()
	power_control.show_presets = false
	power_control.yield_changed.connect(func(kg: float) -> void: power_changed.emit(kg))
	blast.add_child(power_control)
	_depth_row = VBoxContainer.new()
	blast.add_child(_depth_row)
	depth_control = _measure(_depth_row,"Глубина",2.0,120.0,8.0)
	var depth_behavior := _label(_depth_row,"",12,Terminal.MUTED)
	depth_control.value_changed.connect(func(value: float) -> void: _describe_depth(depth_behavior,value))
	_describe_depth(depth_behavior,depth_control.value)
	reflect_blast(Device.BlastMode.SURFACE)

	var weather := _section(inspector,"Погода")
	var row := HBoxContainer.new()
	weather.add_child(row)
	for choices in [["День","Ночь"],["Сухо","Дождь"]]:
		var selector := OptionButton.new()
		selector.focus_mode = Control.FOCUS_NONE
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(selector)
		for choice in choices:
			selector.add_item(choice)
		conditions.append(selector)
		selector.item_selected.connect(func(_i: int) -> void: atmosphere_changed.emit())
	wind_speed.focus_mode = Control.FOCUS_NONE
	wind_speed.tooltip_text = "Скорость ветра"
	for caption in ["Штиль","Ветер · 5 м/с","Ветер · 13 м/с","Ветер · 24 м/с"]:
		wind_speed.add_item(caption)
	weather.add_child(wind_speed)
	wind_direction.focus_mode = Control.FOCUS_NONE
	wind_direction.tooltip_text = "Куда дует ветер"
	for caption in ["На восток","На юго-восток","На юг","На юго-запад","На запад","На северо-запад","На север","На северо-восток"]:
		wind_direction.add_item(caption)
	weather.add_child(wind_direction)
	wind_speed.item_selected.connect(func(_i: int) -> void: atmosphere_changed.emit())
	wind_direction.item_selected.connect(func(_i: int) -> void: atmosphere_changed.emit())

	var dock := _card(canvas,Vector2(0.5,1),Vector2(-159,-67),Vector2(318,51))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",6)
	dock.add_child(actions)
	_run = _button(actions,"Подрыв",true)
	_run.name = "RunTrial"
	_run.tooltip_text = "Запустить испытание · пробел"
	_run.pressed.connect(func() -> void: run_requested.emit())
	_reset = _button(actions,"Сброс",false)
	_reset.name = "ResetTrial"
	_reset.tooltip_text = "Восстановить полигон · R"
	_reset.pressed.connect(func() -> void: reset_requested.emit())
	_slow = OptionButton.new()
	_slow.focus_mode = Control.FOCUS_NONE
	_slow.tooltip_text = "Скорость симуляции · T переключает 1× и ¼×"
	for caption in ["Пауза","0,05×","0,1×","¼×","½×","1×","2×"]:
		_slow.add_item(caption)
	_slow.select(5)
	actions.add_child(_slow)
	_slow.item_selected.connect(func(index: int) -> void: speed_selected.emit(index))

	var injuries := _card(canvas,Vector2(0.5,0.5),Vector2(-152,-148),Vector2(304,296))
	_injury_card = injuries.get_parent() as PanelContainer
	_injury_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var title_row := HBoxContainer.new()
	injuries.add_child(title_row)
	var title := _label(title_row,"Состояние персонажа",16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Закрыть · H"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: injuries_requested.emit())
	title_row.add_child(close)
	_injury_summary = _label(injuries,"",13,Terminal.ACCENT)
	var grid := GridContainer.new()
	grid.columns = 2
	injuries.add_child(grid)
	for caption in ["Корпус","Голова","Левая нога","Левая рука","Правая нога","Правая рука"]:
		var region := VBoxContainer.new()
		region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		region.add_theme_constant_override("separation",3)
		grid.add_child(region)
		_label(region,caption,13,Terminal.MUTED)
		_injury_labels.append(_label(region,"",13))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(130,6)
		region.add_child(bar)
		_injury_bars.append(bar)
	_injury_card.hide()

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1.0, 0.80, 0.55, 0.0)
	canvas.add_child(_flash)

func toggle_injuries() -> void:
	_injury_card.visible = not _injury_card.visible

func update_injuries(player: Node) -> void:
	if not _injury_card.visible:
		return
	var overall := tr("Погиб") if player.health == 0.0 else tr("Здоровье %d%%") % ceili(player.health)
	var burns := tr(" · Ожоги") if player.burn_damage > 0.0 else ""
	var reaction := String(tr(player.reaction_text()))
	_injury_summary.text = overall+burns+("\n"+reaction if not reaction.is_empty() else "")
	for i in _injury_labels.size():
		var damage: float = player.region_damage(i)
		var missing: bool = player.region_missing(i)
		_injury_bars[i].value = 100.0 if missing else damage*100.0
		_injury_labels[i].text = "Утрачена" if missing else (tr("Травма %d%%") % ceili(damage*100.0) if damage > 0.0 else "В норме")

func observer_status(active: bool, health: float, third_person: bool, injury: String, reaction: String) -> void:
	_observer.visible = active
	_injury_button.visible = active
	if not active:
		_injury_card.hide()
		return
	_observer.modulate = Color("#ff9382") if health <= 25.0 else Color.WHITE
	_observer.text = "Погиб · N возродиться" if health <= 0.0 else tr("Здоровье %d%% · B %s") % [ceili(health),tr("1-е лицо" if third_person else "3-е лицо")]
	if health > 0.0 and (not reaction.is_empty() or not injury.is_empty()):
		_observer.text = "%d%% · %s" % [ceili(health),tr(reaction if not reaction.is_empty() else injury)]
	_observer.tooltip_text = "Клавиши можно изменить в настройках управления."

func altitude(meters: float) -> void:
	_altitude.text = tr("Высота %.2f км") % (meters/1000.0) if meters >= 1000.0 else tr("Высота %.0f м") % meters

func coordinates(point: Vector3) -> void:
	_coordinates.text = tr("Точка   X %+.1f   /   Z %+.1f") % [point.x, point.z]

func acoustic_distance(distance: float, estimate: float, arrival: float) -> void:
	_acoustics.text = tr("%d м   ·   звук +%.2f с") % [roundi(distance), arrival if arrival >= 0.0 else estimate]

func set_caption(value: String) -> void:
	_title.text = value

func state(status: String, can_run: bool, can_reset: bool) -> void:
	_status.text = status
	_run.disabled = not can_run
	for selector in conditions:
		selector.disabled = not can_run
	_reset.disabled = not can_reset
	editor.set_locked(not can_run)
	wind_speed.disabled = not can_run
	wind_direction.disabled = not can_run
	blast_picker.disabled = not can_run
	power_control.set_locked(not can_run)
	depth_control.editable = can_run
	if can_run:
		_result.text = ""

func reflect_power(kg: float) -> void:
	power_control.reflect_value(kg)

func reflect_blast(mode: int) -> void:
	blast_picker.select(mode)
	_depth_row.visible = mode == Device.BlastMode.UNDERGROUND

func _describe_depth(label: Label, depth: float) -> void:
	if depth < Device.DEEP_EFFECT_AT:
		label.text = "Выброс на поверхность"
	elif depth < Device.SUBSIDENCE_EFFECT_AT:
		label.text = "Подземная тряска · подъём"
	else:
		label.text = "Подземная тряска · просадка"

func _measure(parent: VBoxContainer, caption: String, minimum: float, maximum: float, initial: float) -> HSlider:
	var title := _label(parent,tr("%s %d м") % [tr(caption),initial],13,Terminal.MUTED)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.value = initial
	slider.step = 1.0
	slider.custom_minimum_size.y = 19.0
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float) -> void: title.text = tr("%s %d м") % [tr(caption),value])
	parent.add_child(slider)
	return slider

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		depth_control.value_changed.emit(depth_control.value)

func result_actions(detail: String = "") -> void:
	_result.text = detail
	_result.visible = not detail.is_empty()

func allow_launch(enabled: bool) -> void:
	_run.disabled = not enabled

func reflect_speed(index: int) -> void:
	_slow.select(index)

func flash(strength: float) -> void:
	_flash.color.a = strength

func _section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var toggle := _button(parent,"[+] "+title.to_upper(),false)
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation",6)
	parent.add_child(contents)
	contents.hide()
	toggle.pressed.connect(func() -> void:
		contents.visible = not contents.visible
		toggle.text = ("[−] " if contents.visible else "[+] ")+title.to_upper()
		parent.get_parent().reset_size())
	return contents

func _card(parent: Control, anchor: Vector2, offset: Vector2, dimensions: Vector2) -> VBoxContainer:
	var card := PanelContainer.new()
	card.anchor_left = anchor.x
	card.anchor_right = anchor.x
	card.anchor_top = anchor.y
	card.anchor_bottom = anchor.y
	card.offset_left = offset.x
	card.offset_top = offset.y
	card.offset_right = offset.x + dimensions.x
	card.offset_bottom = offset.y + dimensions.y
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", Terminal.box(Terminal.PANEL,Terminal.EDGE,10,8))
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 6)
	card.add_child(content)
	return content

func _label(parent: Container, value: String, font_size: int, color: Color = Terminal.INK) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Container, title: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 14)
	if primary:
		button.theme_type_variation = &"TerminalPrimary"
	parent.add_child(button)
	return button
