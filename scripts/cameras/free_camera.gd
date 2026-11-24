extends Camera3D

@export var speed: float = 13.0
@export var sensitivity: float = 0.0025
var manual_enabled := true
var walking := false
const Ground := preload("res://scripts/terrain/range_ground.gd")
var ground: Ground

func _unhandled_input(event: InputEvent) -> void:
	if not manual_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * sensitivity
		rotation.x = clampf(rotation.x - event.relative.y * sensitivity, -1.5, 1.5)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if walking or not manual_enabled or not get_window().has_focus():
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
	position += offset.normalized() * speed * multiplier * delta / Engine.time_scale
	position.x = clampf(position.x,-Ground.HALF_EXTENT,Ground.HALF_EXTENT)
	position.z = clampf(position.z,-Ground.HALF_EXTENT,Ground.HALF_EXTENT)
	var floor_height := 0.0 if ground == null else ground.height_at(position.x, position.z)
	position.y = clampf(position.y, floor_height+0.6,floor_height+Ground.MAX_ALTITUDE)
