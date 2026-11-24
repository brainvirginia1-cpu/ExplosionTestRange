extends MeshInstance3D

const DUST := preload("res://assets/shaders/supercell.gdshader")
var width := 1.75
var variation := 0.0
var _life := 0.0
var _base: Vector3
var _material := ShaderMaterial.new()

func _ready() -> void:
	_base = position
	var billboard := QuadMesh.new()
	billboard.size = Vector2(2.0, 2.0)
	mesh = billboard
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shader = DUST
	_material.set_shader_parameter("seed", variation)
	_material.set_shader_parameter("form", 3)
	_material.set_shader_parameter("samples", 7)
	material_override = _material
	_process(0.0)

func _process(delta: float) -> void:
	_life += delta
	if _life > 1.6:
		queue_free()
		return
	var bloom := 0.29 + 0.83 * (1.0 - exp(-_life * 3.8))
	position = _base + Vector3(variation * 0.075 * _life, width * (0.25 + _life * 0.14), -0.16 * _life)
	scale = Vector3(1.0, 0.39 + _life * 0.116, 1.0) * width * bloom
	_material.set_shader_parameter("volume_radius", scale.x)
	_material.set_shader_parameter("life", _life)
	_material.set_shader_parameter("weight", 0.83 * smoothstep(0.0, 0.12, _life) * (1.0 - smoothstep(0.24, 1.6, _life)))
