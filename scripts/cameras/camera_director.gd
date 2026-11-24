extends Node

signal mode_changed(mode: int)

enum Mode { FREE, WIDE, STATION, ORBIT, WALK }
const FreeCamera := preload("res://scripts/cameras/free_camera.gd")

var camera: FreeCamera
var mode := Mode.FREE
var focus := Vector3.ZERO
var scale_hint := 5.0
var _saved_view := Transform3D.IDENTITY
var _custom_station: Transform3D
var _has_station := false
var _station_index := -1
var _orbit_angle := 0.0

func select(next: int) -> void:
	if next == Mode.STATION:
		_station_index = (_station_index + 1) % (4 if _has_station else 3)
	if mode == Mode.FREE and next != Mode.FREE:
		_saved_view = camera.global_transform
	var restore := mode != Mode.FREE and next == Mode.FREE
	mode = next
	camera.manual_enabled = mode == Mode.FREE or mode == Mode.WALK
	if restore:
		camera.global_transform = _saved_view
	elif mode != Mode.FREE:
		_update_view(0.0)
	mode_changed.emit(mode)

func remember_station() -> void:
	_custom_station = camera.global_transform
	_has_station = true
	_station_index = 2

func _process(delta: float) -> void:
	_update_view(delta)

func _update_view(delta: float) -> void:
	match mode:
		Mode.WIDE:
			var offset := maxf(160.0, scale_hint * 2.92)
			camera.global_position = focus + Vector3(0.62, 0.36, 0.91) * offset
			camera.look_at(focus + Vector3.UP * maxf(4.0, scale_hint * 0.82))
		Mode.STATION:
			if _station_index == 3:
				camera.global_transform = _custom_station
			else:
				var offsets := [Vector3(-95, 31, 95), Vector3(110, 57, -130), Vector3(-1510, 560, 1650)]
				camera.global_position = focus + offsets[_station_index]
				camera.look_at(focus + Vector3.UP * minf(scale_hint * 0.65, float(camera.global_position.distance_to(focus)) * 0.42))
		Mode.ORBIT:
			_orbit_angle += (delta / Engine.time_scale) * 0.28
			var radius := maxf(38.0, scale_hint * 1.53)
			camera.global_position = focus + Vector3(sin(_orbit_angle), 0.44, cos(_orbit_angle)) * radius
			camera.look_at(focus + Vector3.UP * maxf(2.6, scale_hint * 0.64))
