extends Camera3D

const MIN_FOV := 10.0

@export var speed: float = 13.0
@export var sensitivity: float = 0.0025
var manual_enabled := true
var walking := false
const Ground := preload("res://scripts/terrain/range_ground.gd")
var ground: Ground
@onready var _normal_fov := fov
@onready var _target_fov := fov

func _unhandled_input(event: InputEvent) -> void:
	if not manual_enabled:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var steps: float = event.factor if event.factor > 0.0 else 1.0
				var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				_target_fov = clampf(_target_fov*pow(0.82,direction*steps),MIN_FOV,_normal_fov)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look_speed := sensitivity*fov/_normal_fov
		rotation.y -= event.relative.x * look_speed
		rotation.x = clampf(rotation.x - event.relative.y * look_speed, -1.5, 1.5)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if not manual_enabled:
		return
	var real_delta := delta/Engine.time_scale
	fov = lerpf(fov,_target_fov,1.0-exp(-real_delta*16.0))
	if absf(fov-_target_fov) < 0.01:
		fov = _target_fov
	if walking or not get_window().has_focus():
		return
	var movement := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var multiplier := 6.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	var altitude := maxf(0.0,position.y-Ground.base_height(position.x,position.z))
	multiplier *= 1.0+altitude*0.014
	if Input.is_physical_key_pressed(KEY_SHIFT):
		multiplier += 18.0*smoothstep(120.0,1900.0,altitude)
	var offset := (basis.x * movement.x + Vector3.UP * movement.y + basis.z * movement.z)
	position += offset.normalized() * speed * multiplier * real_delta
	position.x = clampf(position.x,-Ground.HALF_EXTENT,Ground.HALF_EXTENT)
	position.z = clampf(position.z,-Ground.HALF_EXTENT,Ground.HALF_EXTENT)
	var floor_height := 0.0 if ground == null else ground.height_at(position.x, position.z)
	position.y = clampf(position.y, floor_height+0.6,floor_height+Ground.MAX_ALTITUDE)
