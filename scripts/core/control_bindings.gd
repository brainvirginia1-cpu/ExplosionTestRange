extends RefCounted

const DEFAULTS := {
	"forward": KEY_W, "backward": KEY_S, "left": KEY_A, "right": KEY_D,
	"ascend": KEY_E, "descend": KEY_Q, "sprint": KEY_SHIFT, "jump": KEY_J,
	"observer": KEY_V, "view": KEY_B, "injuries": KEY_H, "respawn": KEY_N,
	"detonate": KEY_SPACE, "reset": KEY_R, "slow": KEY_T, "replay": KEY_Y,
	"pause": KEY_ESCAPE,
}
const LABELS := {
	"forward": "Вперёд", "backward": "Назад по полигону", "left": "Влево", "right": "Вправо",
	"ascend": "Поднять камеру", "descend": "Опустить камеру", "sprint": "Ускориться", "jump": "Прыжок",
	"observer": "Режим наблюдателя", "view": "Вид от первого / третьего лица",
	"injuries": "Экран повреждений", "respawn": "Возродиться",
	"detonate": "Подрыв", "reset": "Сброс", "slow": "Переключить замедление", "replay": "Повторить испытание",
	"pause": "Открыть меню паузы",
}

static var _active := DEFAULTS.duplicate()

static func normalize(saved: Dictionary) -> Dictionary:
	var bindings := DEFAULTS.duplicate()
	var assigned := {}
	for action: String in DEFAULTS:
		var code: Variant = saved.get(action, DEFAULTS[action])
		if code is int and code > 0 and not OS.get_keycode_string(code).is_empty() and (code != KEY_ESCAPE or action == "pause"):
			if not assigned.has(code):
				bindings[action] = code
				assigned[code] = true
	if assigned.size() != DEFAULTS.size():
		return DEFAULTS.duplicate()
	return bindings

static func apply(bindings: Dictionary) -> void:
	_active = bindings.duplicate()

static func pressed(action: String) -> bool:
	return Input.is_physical_key_pressed(_active[action])

static func action_for(event: InputEventKey) -> String:
	var action: Variant = _active.find_key(event.physical_keycode)
	return action if action != null else ""

static func key_label(code: int) -> String:
	var layout_code := DisplayServer.keyboard_get_keycode_from_physical(code)
	return OS.get_keycode_string(layout_code if layout_code != KEY_NONE else code)
