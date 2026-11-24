extends Node3D

signal front_advanced(radius: float)
signal finished
signal ignited

const Device := preload("res://scripts/devices/trial_device.gd")
const Profile := preload("res://scripts/explosions/explosion_profile.gd")
const CombustionVolume := preload("res://scripts/explosions/combustion_volume.gd")
const FLASH := preload("res://assets/shaders/flash.gdshader")
const HEAT_SHIMMER := preload("res://assets/shaders/heat_shimmer.gdshader")
const AIR_FRONT := preload("res://assets/shaders/atmospheric_shell.gdshader")
const Propagation := preload("res://scripts/core/propagation.gd")
const LargePlume := preload("res://scripts/explosions/large_plume.gd")
const AcousticEvent := preload("res://scripts/audio/acoustic_event.gd")
const WaveDust := preload("res://scripts/explosions/wave_dust.gd")
const GRIT := preload("res://assets/sounds/burst_grit_tail.wav")
const THUNDER := [
	preload("res://assets/sounds/burst_thunder_tail.wav"),
	preload("res://assets/sounds/burst_thunder_tail_2.wav"),
]
const THERMAL_ROAR := preload("res://assets/sounds/burst_thermal_tail.wav")
const AUDIO := [
	preload("res://assets/sounds/range_burst_0.wav"),
	preload("res://assets/sounds/range_burst.wav"),
	preload("res://assets/sounds/range_burst_2.wav"),
	preload("res://assets/sounds/range_burst_3.wav"),
	preload("res://assets/sounds/range_burst_4.wav"),
	preload("res://assets/sounds/range_burst_5.wav"),
	preload("res://assets/sounds/range_burst_6.wav"),
]

var wind := Vector2.ZERO
var effect_quality := 1
var adaptive_effects := true
var frozen_age := -1.0
var _light_shadows := true
var sun_direction := Vector3(-0.61,0.73,0.30)
var blast_mode := Device.BlastMode.SURFACE
var ignition_delay := 0.0
var sound_depth := 0.0
var contained := false
var _ejected := false
var conditions := Vector4i.ZERO
var profile: Profile
var seed := 4207
var floor_height: Callable
var terrain_craters: PackedVector4Array
var occlusion_material: ShaderMaterial
var dust_front: WaveDust
var age := 0.0
var front_radius := 0.0
# The rendering front keeps travelling after the gameplay event has finished propagating.
func visual_radius() -> float:
	return maxf(0.0,age-ignition_delay)*Propagation.SPEED

func visual_strength() -> float:
	var travel := visual_radius() / profile.front_radius
	return (1.0 - smoothstep(0.8, 1.0, age / profile.lifetime)) / (1.0 + travel * travel)

var _volume: CombustionVolume
var _audio: AcousticEvent
var _light: OmniLight3D
var _flash: MeshInstance3D
var _haze: MeshInstance3D
var _air_front: MeshInstance3D
var _plume: LargePlume
var _quad := QuadMesh.new()

func set_light_shadows(enabled: bool) -> void:
	_light_shadows = enabled
	if is_instance_valid(_light):
		_light.shadow_enabled = enabled

func _ready() -> void:
	assert(profile != null)
	_quad.size = Vector2(2.0, 2.0)
	_volume = CombustionVolume.new()
	_volume.profile = profile
	_volume.wind = wind
	_volume.effect_quality = effect_quality
	_volume.adaptive_quality = adaptive_effects
	_volume.sun_direction = sun_direction
	_volume.conditions = conditions
	_volume.terrain_craters = terrain_craters
	_volume.occlusion_material = occlusion_material
	if floor_height.is_valid():
		_volume.floor_at_origin = floor_height.call(global_position.x,global_position.z)
	_volume.seed = seed
	_volume.ignition_delay = ignition_delay
	_volume.blast_mode = blast_mode
	add_child(_volume)
	if profile.tier >= 4:
		_plume = LargePlume.new()
		_plume.wind = wind
		_plume.scope = profile.fire_radius * 1.85
		add_child(_plume)
	if not contained:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 48
		sphere.rings = 24
		_air_front = _surface(sphere, AIR_FRONT)
		var material := _air_front.material_override as ShaderMaterial
		material.render_priority = 4
		material.set_shader_parameter("turbulence", CombustionVolume.TURBULENCE)
		var ground_y: float = floor_height.call(global_position.x, global_position.z) if floor_height.is_valid() else global_position.y
		material.set_shader_parameter("ground_level", ground_y)

	_light = OmniLight3D.new()
	_light.position.y = clampf(profile.fire_radius*0.018,0.04,0.35)
	_light.omni_range = 14.0 + profile.fire_radius * 9.0
	_light.omni_attenuation = 1.0
	_light.shadow_enabled = _light_shadows
	_light.light_specular = 0.72
	add_child(_light)
	_flash = _surface(_quad, FLASH)
	_flash.material_override.render_priority = 3
	var flash_material := _flash.material_override as ShaderMaterial
	flash_material.set_shader_parameter("thermonuclear",float(profile.thermonuclear_visual))
	_flash.position.y = _light.position.y
	if profile.tier < 4:
		_haze = _surface(_quad, HEAT_SHIMMER)
		_haze.material_override.render_priority = -2
		(_haze.material_override as ShaderMaterial).set_shader_parameter("turbulence", CombustionVolume.TURBULENCE)
		_haze.position.y = profile.fire_radius*0.69
	dust_front = WaveDust.new()
	dust_front.class_index = profile.tier
	dust_front.variation_seed = seed
	dust_front.wind = wind
	dust_front.sun_direction = sun_direction
	dust_front.limit = profile.front_radius
	dust_front.crest_height = profile.dust_height*(1.0+profile.ground_dust*0.65)
	dust_front.floor_height = floor_height
	add_child(dust_front)

	if frozen_age >= 0.0:
		set_process(false)
		_ejected = true
		age = frozen_age
		_update_visuals()
		return

	_audio = AcousticEvent.new()
	_audio.name = "AcousticEvent"
	_audio.travel_time = -ignition_delay
	_audio.position.y = -sound_depth
	var sound_style := 0
	match blast_mode:
		Device.BlastMode.THERMOBARIC: sound_style = 1
		Device.BlastMode.UNDERGROUND: sound_style = 3
	_audio.stream = AUDIO[profile.audio_variant] if sound_style==0 else load("res://assets/sounds/style_%d_%d.wav" % [sound_style,profile.audio_variant])
	_audio.roll_stream = load("res://assets/sounds/roll_%d_%d.wav" % [sound_style,profile.audio_variant])
	_audio.unit_size = profile.audio_unit
	_audio.soft_range = profile.sound_range * [1.0,1.15,0.88,0.75][sound_style]
	var pitch_variation := lerpf(0.986,1.014,float(posmod(seed,1024))/1023.0)
	_audio.pitch_scale = profile.audio_pitch*pitch_variation
	_audio.volume_db = profile.audio_level_db + [0.0,0.65,-1.15,-5.5][sound_style]
	if contained:
		_audio.volume_db -= 16.0
		_audio.pitch_scale *= 0.75
	if blast_mode == Device.BlastMode.THERMOBARIC:
		_audio.add_layer(THERMAL_ROAR,-5.5)
	if not contained:
		_audio.add_layer(GRIT,lerpf(-9.0,-16.0,profile.visual_growth))
	if profile.visual_growth > 0.18:
		var thunder_gain := lerpf(-16.0,-3.0,profile.visual_growth)
		_audio.add_layer(THUNDER[posmod(seed,THUNDER.size())],thunder_gain,&"Thunder")
	add_child(_audio)

	_update_visuals()

func refresh_preview(quality: int) -> void:
	if frozen_age < 0.0:
		return
	if quality != effect_quality:
		effect_quality = quality
		_volume.set_effect_quality(quality)
	_update_visuals()

func distant_dust(at: Vector3) -> void:
	if _plume != null:
		_plume.remote_dust(at, age)

func sound_arrival() -> float:
	return _audio.arrival_time if _audio != null else -1.0

func cancel() -> void:
	RenderingServer.global_shader_parameter_set(&"weather_flash_gain",0.0)
	set_process(false)
	if is_instance_valid(_volume):
		_volume.clear_shadow()
	if _audio != null:
		_audio.cancel()

# The first delta includes time before this event entered the scene.
var _first_update := true

func _process(delta: float) -> void:
	if _first_update:
		_first_update = false
		return
	age += delta
	var next_radius := minf(visual_radius(),profile.front_radius)
	if next_radius > front_radius:
		front_radius = next_radius
		front_advanced.emit(front_radius)
	if is_instance_valid(_volume) and _volume.visible:
		_volume.adjust_quality(delta / Engine.time_scale)
	_update_visuals()
	if age >= profile.cloud_lifetime():
		RenderingServer.global_shader_parameter_set(&"weather_flash_gain",0.0)
		set_process(false)
		hide()
		if is_instance_valid(_volume):
			_volume.clear_shadow()
		finished.emit()
		if _audio != null and _audio.is_active():
			add_to_group("range_audio_tails")
			_audio.tail_finished.connect(queue_free, CONNECT_ONE_SHOT)
		else:
			queue_free()

func _update_visuals() -> void:
	if contained:
		_light.hide()
		_flash.hide()
		return
	var hot_age := age-ignition_delay
	if hot_age >= 0.0 and not _ejected:
		_ejected = true
		ignited.emit()
		_spark_burst()
		_eject_soil()
	var flash_time := (0.29+profile.tier*0.059)*(1.19 if profile.thermonuclear_visual else 1.0)
	var flash := maxf(0.0,1.0-hot_age/flash_time) if hot_age >= 0.0 else 0.0
	var hot_time := maxf(0.0,hot_age)/profile.heat_duration
	var ignition := exp(-maxf(0.0,hot_age)/flash_time*2.6)
	var glow_duration: float = 1.65 if blast_mode == Device.BlastMode.THERMOBARIC else 1.0
	var afterglow := exp(-hot_time / glow_duration)
	var brightness := (2.8*ignition+0.88*afterglow) if hot_age >= 0.0 else 0.0
	if sound_depth > 0.0:
		brightness *= 0.27
		flash *= 0.38
	_light.light_energy = _light.omni_range * brightness
	var hot_color := Color("#fff7e6") if profile.thermonuclear_visual else Color("#ffedcf")
	_light.light_color = Color("#ff822f").lerp(hot_color,ignition)
	_light.position.y = _flash.position.y+profile.fire_radius*0.10*(1.0-afterglow)
	_light.visible = brightness > 0.002
	var emitter := _light.global_position
	RenderingServer.global_shader_parameter_set(&"weather_flash",Vector4(emitter.x,emitter.y,emitter.z,_light.omni_range))
	RenderingServer.global_shader_parameter_set(&"weather_flash_gain",brightness*0.74)
	_flash.visible = flash > 0.0
	_flash.scale = Vector3.ONE * (3.0 + maxf(0.0,hot_age)*16.0) * pow(profile.visual_scale, 0.89)
	var crest := visual_radius()
	var strength := visual_strength()
	dust_front.set_air_reach(global_position,crest)
	var dust_age := maxf(0.0,hot_age)
	var dust_crest := dust_age*CombustionVolume.CLOUD_TRAVEL_SPEED
	dust_front.advance(age, dust_crest, strength * (0.46 if conditions.y==1 else 1.0), (ignition+0.26*afterglow)*strength)
	_update_air_front(hot_age, crest, strength)
	(_flash.material_override as ShaderMaterial).set_shader_parameter("intensity", flash * flash)
	var camera := get_viewport().get_camera_3d()
	var observer_distance := 0.0 if camera == null else camera.global_position.distance_to(global_position)
	if _plume != null:
		_plume.update_plume(age, observer_distance)
	_volume.advance(age, observer_distance)
	if _haze != null:
		var shimmer := smoothstep(0.04,0.26,hot_age)*exp(-maxf(0.0,hot_age) / (profile.heat_duration * 1.75))
		_haze.visible = shimmer > 0.035 and observer_distance < profile.fire_radius * 24.0
		if _haze.visible:
			var material := _haze.material_override as ShaderMaterial
			material.set_shader_parameter("strength", shimmer)
			material.set_shader_parameter("elapsed", age)
			_haze.scale = Vector3(1.24, 1.16, 1.0) * profile.fire_radius

func _update_air_front(hot_age: float, radius: float, strength: float) -> void:
	var growth := profile.visual_growth
	var moisture := 1.0 if conditions.y == 1 else 0.82
	var vapor_time := 0.20 + 1.80 * pow(growth, 1.22)
	var progress := hot_age / vapor_time
	var onset := smoothstep(0.0, minf(0.085, vapor_time * 0.22), hot_age)
	var vapor := onset * (1.0 - smoothstep(0.16, 1.0, progress))
	vapor *= pow(strength, 0.62) * moisture * lerpf(0.66, 1.48, growth)
	var shimmer := onset * strength * lerpf(0.29, 0.70, growth)
	shimmer *= 1.0 - smoothstep(0.44, 1.0, progress)
	_air_front.visible = radius > 0.0 and progress < 1.0
	if not _air_front.visible:
		return
	# The proxy is slightly oversized; the shader renders the actual game front.
	_air_front.scale = Vector3.ONE * radius * 1.014
	var material := _air_front.material_override as ShaderMaterial
	material.set_shader_parameter("wave_radius", radius)
	material.set_shader_parameter("band_width", lerpf(0.19, 0.075, smoothstep(0.15, 1.0, progress)))
	material.set_shader_parameter("condensation", vapor)
	material.set_shader_parameter("shimmer", shimmer)
	material.set_shader_parameter("elapsed", hot_age)

func _surface(mesh: Mesh, shader: Shader) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = shader
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func _eject_soil() -> void:
	var gravel := GPUParticles3D.new()
	gravel.emitting = false
	gravel.one_shot = true
	gravel.lifetime = 1.58
	gravel.explosiveness = 0.96
	gravel.amount = 65 + profile.tier * 19
	gravel.visibility_aabb = AABB(Vector3(-120, -35, -120), Vector3(240, 145, 240))
	gravel.position.y = 0.62
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 64.0
	motion.initial_velocity_min = 4.4
	motion.initial_velocity_max = 10.0 + minf(profile.fire_radius * 0.31, 43.0)
	motion.gravity = Vector3.DOWN * 14.0
	motion.angular_velocity_min = -210.0
	motion.angular_velocity_max = 260.0
	motion.scale_min = 0.25
	motion.scale_max = 1.34 + minf(profile.visual_growth, 0.8)
	gravel.process_material = motion
	var stone := PrismMesh.new()
	stone.size = Vector3(0.17, 0.12, 0.21) * pow(maxf(profile.visual_scale, 1.0), 0.32)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#66472f")
	material.roughness = 0.96
	stone.material = material
	gravel.draw_pass_1 = stone
	add_child(gravel)
	gravel.emitting = true

func _spark_burst() -> void:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.amount = roundi((145 + profile.tier * 19) * (1.55 if blast_mode == Device.BlastMode.THERMOBARIC else 0.80))
	particles.lifetime = 1.83
	particles.one_shot = true
	particles.explosiveness = 0.97
	particles.randomness = 0.31
	particles.position.y = 0.8
	particles.visibility_aabb = AABB(Vector3(-24, -12, -24), Vector3(48, 36, 48))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 74.0
	process.initial_velocity_min = 6.0
	process.initial_velocity_max = 22.0 + profile.tier * 2.8
	process.particle_flag_align_y = true
	process.gravity = Vector3(wind.x*0.28,-12.0,wind.y*0.28)
	process.scale_min = 0.28
	process.scale_max = 1.0
	var ramp := GradientTexture1D.new()
	ramp.gradient = Gradient.new()
	ramp.gradient.set_color(0, Color(1.0, 0.77, 0.26))
	ramp.gradient.set_color(1, Color(0.26, 0.06, 0.0, 0.0))
	process.color_ramp = ramp
	particles.process_material = process
	var spark := BoxMesh.new()
	spark.size = Vector3(0.035, 0.19, 0.035)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(3.2, 2.8, 1.9)
	spark.material = material
	particles.draw_pass_1 = spark
	add_child(particles)
	particles.emitting = true
