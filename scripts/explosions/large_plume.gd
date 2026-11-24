extends Node3D

const SHADER := preload("res://assets/shaders/supercell.gdshader")

class Layer:
	var mesh: MeshInstance3D
	var material: ShaderMaterial
	var offset: Vector3
	var motion: Vector3
	var dimensions: Vector3
	var delay: float
	var duration: float

var scope := 100.0
var wind := Vector2.ZERO
var _layers: Array[Layer] = []
var _billboard := QuadMesh.new()
var _remote_count := 0

func _ready() -> void:
	_billboard.size = Vector2(2.0, 2.0)

func update_plume(age: float, observer_distance: float) -> void:
	var quality_samples := 12 if observer_distance < scope * 3.7 else 7
	for layer in _layers:
		var local_age := age - layer.delay
		layer.mesh.visible = local_age > 0.0 and local_age < layer.duration
		if not layer.mesh.visible:
			continue
		var fill := 1.0 - exp(-local_age * 0.36)
		var drift := log(1.0 + local_age * 0.48)
		var travel := local_age-1.3*(1.0-exp(-local_age/1.3))
		layer.mesh.position = (layer.offset + layer.motion * drift) * scope + Vector3(wind.x,0,wind.y)*travel
		var onset := 1.0-exp(-local_age*6.0)
		layer.mesh.scale = layer.dimensions * scope * (0.17*onset + 0.93*fill + local_age*0.006)
		layer.material.set_shader_parameter("life", local_age)
		layer.material.set_shader_parameter("weight", smoothstep(0.0, 0.54, local_age) *
			(1.0 - smoothstep(0.42, 1.0, local_age / layer.duration)))
		layer.material.set_shader_parameter("samples", quality_samples)
		layer.material.set_shader_parameter("volume_radius", maxf(layer.mesh.scale.x, layer.mesh.scale.y))

func remote_dust(at: Vector3, age: float) -> void:
	if _remote_count >= 18:
		return
	_remote_count += 1
	var offset := (at - global_position) / scope
	_add(0, offset + Vector3.UP * (3.0 / scope), Vector3(5.0, 15.0, -3.0) / scope,
		Vector3(28.0, 21.0, 1.0) / scope, age, 11.0)

func _add(form: int, offset: Vector3, motion: Vector3, dimensions: Vector3, delay: float, duration: float) -> void:
	var layer := Layer.new()
	layer.mesh = MeshInstance3D.new()
	layer.mesh.mesh = _billboard
	layer.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.mesh.extra_cull_margin = scope
	layer.material = ShaderMaterial.new()
	layer.material.shader = SHADER
	layer.material.set_shader_parameter("form", form)
	layer.material.set_shader_parameter("seed", 0.25 + _layers.size() * 1.779)
	layer.mesh.material_override = layer.material
	layer.mesh.visible = false
	layer.offset = offset
	layer.motion = motion
	layer.dimensions = dimensions
	layer.delay = delay
	layer.duration = duration
	_layers.append(layer)
	add_child(layer.mesh)
