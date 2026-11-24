extends RefCounted

const PATH := "user://range_settings.cfg"
const RENDER_SCALES := [0.67, 0.80, 1.0, 1.25, 1.50]
const FRAME_LIMITS := [0, 30, 60, 120, 144]
const LANGUAGES := ["ru", "en"]
const Controls := preload("res://scripts/core/control_bindings.gd")
const DEFAULTS := {
	"volume": 0.78, "thunder_volume": 1.0,
	"fullscreen": false, "vsync": true, "frame_limit": 0, "render_scale": 2,
	"msaa": 1, "debanding": false,
	"shadow_quality": 2, "cloud_shadows": true, "ao": true, "ssil": true, "glow": true,
	"effect_quality": 1, "adaptive_effects": true, "camera_kick": false,
	"language": "ru", "bindings": Controls.DEFAULTS,
}
const LEGACY_VISUALS := {
	"shadow_quality": 0, "cloud_shadows": false, "ao": false, "ssil": false, "glow": false,
}

static func read() -> Dictionary:
	var config := ConfigFile.new()
	var values := DEFAULTS.duplicate()
	if config.load(PATH) != OK:
		return values
	for key: String in values:
		var fallback: Variant = values[key]
		if config.get_value("settings", "visuals", true) == false:
			fallback = LEGACY_VISUALS.get(key, fallback)
		var saved: Variant = config.get_value("settings", key, fallback)
		if typeof(saved) == typeof(fallback):
			values[key] = saved
	for key in ["volume", "thunder_volume"]:
		values[key] = clampf(values[key], 0.0, 1.0) if is_finite(values[key]) else DEFAULTS[key]
	for item in [["frame_limit", FRAME_LIMITS.size()], ["render_scale", RENDER_SCALES.size()],
		["msaa", max_msaa() + 1], ["shadow_quality", 4], ["effect_quality", 3]]:
		values[item[0]] = clampi(values[item[0]], 0, item[1] - 1)
	if not values["language"] in LANGUAGES:
		values["language"] = DEFAULTS["language"]
	values["bindings"] = Controls.normalize(values["bindings"])
	return values

static func save(values: Dictionary) -> Error:
	var config := ConfigFile.new()
	for key: String in DEFAULTS:
		config.set_value("settings", key, values[key])
	return config.save(PATH)

static func apply(values: Dictionary, window: Window) -> void:
	Controls.apply(values["bindings"])
	if TranslationServer.get_locale() != values["language"]:
		TranslationServer.set_locale(values["language"])
	_apply_volume(&"Master", values["volume"])
	_apply_volume(&"Thunder", values["thunder_volume"])
	Engine.max_fps = FRAME_LIMITS[values["frame_limit"]]
	if DisplayServer.get_name() != "headless":
		var mode := Window.MODE_FULLSCREEN if values["fullscreen"] else Window.MODE_WINDOWED
		if window.mode != mode:
			window.mode = mode
		var sync := DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED
		if DisplayServer.window_get_vsync_mode(window.get_window_id()) != sync:
			DisplayServer.window_set_vsync_mode(sync, window.get_window_id())
	apply_viewport(values, window)

static func apply_viewport(values: Dictionary, viewport: Viewport) -> void:
	viewport.scaling_3d_scale = RENDER_SCALES[values["render_scale"]]
	viewport.msaa_3d = mini(values["msaa"], max_msaa())
	viewport.use_debanding = values["debanding"]

static func max_msaa() -> int:
	# RX 580's Vulkan driver can render the ground black at 4x/8x with shadows and SSAO/SSIL.
	if RenderingServer.get_current_rendering_driver_name() == "vulkan":
		if RenderingServer.get_video_adapter_name().contains("RX 580"):
			return Viewport.MSAA_2X
	return Viewport.MSAA_8X

static func _apply_volume(bus: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))
	AudioServer.set_bus_mute(index, volume <= 0.0)
