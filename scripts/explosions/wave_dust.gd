extends MultiMeshInstance3D

const DUST_SHADER := preload("res://assets/shaders/wave_dust.gdshader")
var crest_height := 2.0
var wind := Vector2.ZERO
var sun_direction := Vector3(-0.61,0.73,0.30)
var limit := 45.0
var class_index := 0
var variation_seed := 91831
var floor_height: Callable
var _segments: int
var _material := ShaderMaterial.new()
var _directions: Array[Vector2] = []
var _variation: PackedFloat32Array = []

func _ready() -> void:
	_segments = 36 + class_index * 8
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.instance_count = _segments*2
	var proxy := BoxMesh.new()
	proxy.size = Vector3.ONE*2.0
	batch.mesh = proxy
	batch.custom_aabb = AABB(Vector3(-limit * 1.16, -crest_height * 2.0, -limit * 1.16),
		Vector3(limit * 2.32, crest_height * 12.0 + 170.0, limit * 2.32))
	multimesh = batch
	_material.shader = DUST_SHADER
	_material.set_shader_parameter("turbulence", preload("res://data/presets/burst_volume_noise.tres"))
	_material.set_shader_parameter("sun_direction",sun_direction.normalized())
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var random := RandomNumberGenerator.new()
	random.seed = variation_seed
	for i in range(_segments):
		var azimuth := TAU * (i + random.randf_range(-0.31, 0.31)) / _segments
		_directions.append(Vector2(cos(azimuth), sin(azimuth)))
		var weight := random.randf_range(0.50, 1.0)
		_variation.append(weight)
		batch.set_instance_custom_data(i, Color(random.randf(), weight, 0.0, 1.0))
		batch.set_instance_custom_data(_segments+i, Color(random.randf(), weight, 1.0, 1.0))
	hide()

func advance(age: float, crest: float, strength: float, flash_light: float) -> void:
	var visible_dust := crest > 0.9 and strength > 0.002
	if not visible_dust:
		hide()
		return
	show()
	var wake_strength := lerpf(1.58,2.45,float(class_index)/6.0)
	var opacity := smoothstep(0.9, minf(limit * 0.34, 14.0), crest) * pow(strength,0.82) * wake_strength
	var height := crest_height * 1.23 * (0.35 + 0.65 * smoothstep(0.0, limit * 0.6, crest)) * (1.0 + (1.0-strength) * 0.64)
	var spacing := TAU * crest / _segments
	var drift := wind*minf(age*0.28,1.0+crest*0.005)
	var extent := crest + spacing * 2.0 + drift.length()*2.0
	custom_aabb = AABB(Vector3(-extent,-height*2.0-170.0,-extent),
		Vector3(extent*2.0,height*12.0+340.0,extent*2.0))
	var depth := minf(maxf(0.45,height*1.38),maxf(0.52,spacing*0.72))
	var radius := maxf(0.0,crest-maxf(depth*0.79,spacing*0.45))
	var parent_origin := global_position
	_material.set_shader_parameter("phase", age)
	_material.set_shader_parameter("fade", opacity)
	_material.set_shader_parameter("flash_light",flash_light)
	for i in range(_segments):
		var direction := _directions[i]
		var weight := _variation[i]
		var distance := maxf(0.0, radius - weight * spacing * 0.28)
		var offset := direction * distance + drift*(0.65+weight*0.65)
		var at := parent_origin + Vector3(offset.x, 0.0, offset.y)
		var ground_y: float = floor_height.call(at.x, at.z) if floor_height.is_valid() else parent_origin.y
		var outward := Vector3(direction.x,0.0,direction.y)
		var orientation := Basis(Vector3.UP.cross(outward),Vector3.UP,outward)
		var size := Vector3(maxf(0.5,spacing*(0.54+weight*0.45)),height*(0.51+weight*0.77),
			depth*(0.83+weight*0.27))
		var origin := Vector3(offset.x,ground_y-parent_origin.y+size.y*0.39,offset.y)
		multimesh.set_instance_transform(i,Transform3D(orientation*Basis.from_scale(size),origin))
		var wake_distance := maxf(0.0,distance-maxf(depth*1.32,spacing*0.54))
		var wake_offset := direction.rotated(0.035)*wake_distance+drift*1.35
		var wake_at := parent_origin + Vector3(wake_offset.x,0.0,wake_offset.y)
		var wake_floor: float = floor_height.call(wake_at.x,wake_at.z) if floor_height.is_valid() else parent_origin.y
		var wake_size := Vector3(size.x*1.29,size.y*(0.38+0.23*weight),size.z*1.42)
		var wake_origin := Vector3(wake_offset.x,wake_floor-parent_origin.y+wake_size.y*0.26,wake_offset.y)
		multimesh.set_instance_transform(_segments+i,Transform3D(orientation*Basis.from_scale(wake_size),wake_origin))

func set_air_reach(origin: Vector3, radius: float) -> void:
	_material.set_shader_parameter("air_reach",Vector4(origin.x,origin.y,origin.z,radius))
