extends Node

var camera: Camera3D
var active := false
var last_path := ""
var _old_fov := 56.0

func toggle() -> void:
	active = not active
	if active:
		_old_fov = camera.fov
	else:
		camera.fov = _old_fov

func zoom(steps: float) -> void:
	if active:
		camera.fov = clampf(camera.fov + steps * 4.0, 25.0, 92.0)

func capture(directory: String = "user://photos") -> void:
	if not active or DisplayServer.get_name() == "headless":
		return
	var folder := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return
	await RenderingServer.frame_post_draw
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := folder.path_join("range-%s-%d.png" % [stamp, Time.get_ticks_msec()])
	if camera.get_viewport().get_texture().get_image().save_png(path) == OK:
		last_path = path
