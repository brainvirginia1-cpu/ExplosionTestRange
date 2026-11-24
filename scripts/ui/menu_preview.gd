extends SubViewportContainer

const Settings := preload("res://scripts/core/game_settings.gd")
const Catalog := preload("res://scripts/explosions/yield_catalog.gd")
const Burst := preload("res://scripts/explosions/burst.gd")
const SNAPSHOT_TIME := 5.8

var _viewport: SubViewport
var _stage: Node3D
var _burst: Burst
var _refresh_pending := false
var _generation := 0
var _graphics := {}

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	if DisplayServer.get_name() == "headless":
		return
	var map := load("res://scenes/main/range.tscn") as PackedScene
	_stage = map.instantiate() as Node3D
	_stage.preview_only = true
	_viewport.add_child(_stage)
	var camera: Camera3D = _stage.get_node("Camera")
	camera.position = Vector3(1090,430,1870)
	camera.look_at(Vector3(0,540,0))
	var sun := _stage.get_node("Sun") as DirectionalLight3D
	RenderingServer.global_shader_parameter_set(&"weather_state",Vector2.ZERO)
	RenderingServer.global_shader_parameter_set(&"weather_sun",sun.global_basis.z.normalized())
	_add_prop(preload("res://assets/models/container.glb"),Vector3(430,0,710),-0.22,10.0)
	_add_prop(preload("res://assets/models/shelter.glb"),Vector3(580,0,835),0.31,9.0)
	_add_prop(preload("res://assets/models/signal_tower.glb"),Vector3(507,0,886),0.40,7.0)
	var initial := Settings.read()
	_burst = Burst.new()
	_burst.profile = Catalog.make_profile(1000000000.0)
	Catalog.apply_surface_presentation(_burst.profile,1000000000.0)
	_burst.frozen_age = SNAPSHOT_TIME
	_burst.adaptive_effects = false
	_burst.effect_quality = initial["effect_quality"]
	_burst.sun_direction = sun.global_basis.z
	_burst.floor_height = _stage._sample_land
	_burst.occlusion_material = _stage.get_node("Occlusion").material_override
	_stage.add_child(_burst)
	resized.connect(_queue_refresh)
	apply_graphics(initial)

func _add_prop(model: PackedScene, position_on_range: Vector3, yaw: float, size_factor: float) -> void:
	var prop := model.instantiate() as Node3D
	prop.position = position_on_range
	prop.rotation.y = yaw
	prop.scale = Vector3.ONE*size_factor
	_stage.add_child(prop)

func apply_graphics(values: Dictionary) -> void:
	if not is_instance_valid(_burst):
		return
	var visual_values := ["render_scale","msaa","debanding","shadow_quality","cloud_shadows","ao","ssil","glow","effect_quality"]
	if not visual_values.any(func(key: String) -> bool: return _graphics.get(key) != values[key]):
		return
	_graphics = values.duplicate()
	Settings.apply_viewport(values,_viewport)
	_stage.apply_graphics(values)
	_burst.set_light_shadows(values["shadow_quality"] > 0)
	_burst.refresh_preview(values["effect_quality"])
	_queue_refresh()

func _queue_refresh() -> void:
	_generation += 1
	if not _refresh_pending:
		_render_frames.call_deferred()
		_refresh_pending = true

func _render_frames() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var generation := _generation
	for frame in 3:
		await RenderingServer.frame_post_draw
		if generation != _generation:
			_render_frames.call_deferred()
			return
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_refresh_pending = false

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"weather_flash_gain",0.0)
