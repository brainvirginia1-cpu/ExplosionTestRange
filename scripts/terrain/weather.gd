extends Node3D

var drops := GPUParticles3D.new()
var wind_setting := Vector2.ZERO
var _rain := false
var _night := false
var _sun: DirectionalLight3D
var _altitude := 0.0
var elapsed := 0.0
var motion := ParticleProcessMaterial.new()

func _ready() -> void:
	drops.amount=2200
	drops.lifetime=1.3
	drops.preprocess=1.3
	drops.local_coords=false
	drops.visibility_aabb=AABB(Vector3(-34,-36,-34),Vector3(68,72,68))
	motion.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents=Vector3(21,2,21)
	motion.gravity=Vector3(0,-13,0)
	motion.initial_velocity_min=20
	motion.initial_velocity_max=24
	motion.spread=2
	motion.particle_flag_align_y=true
	drops.process_material=motion
	var streak:=BoxMesh.new()
	streak.size=Vector3(0.021,0.42,0.021)
	var material:=StandardMaterial3D.new()
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(0.77,0.78,0.79,0.45)
	streak.material=material
	drops.draw_pass_1=streak
	drops.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.emitting=false
	add_child(drops)

func apply(wind: Vector2, rain: bool, night: bool, env: Environment, sun: DirectionalLight3D) -> void:
	wind_setting=wind
	_rain=rain
	_night=night
	_sun=sun
	RenderingServer.global_shader_parameter_set(&"weather_sun", sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"weather_state",Vector2(float(rain),float(night)))
	drops.emitting=rain
	motion.direction=Vector3(wind.x,-21.0,wind.y).normalized()
	sun.light_energy=(0.14 if night else 1.35)*(0.52 if rain else 1.0)
	env.ambient_light_energy=0.15 if night else (0.43 if rain else 0.55)
	update_altitude(_altitude,env)
	var sky:=env.sky.sky_material as ShaderMaterial
	sky.set_shader_parameter("night",float(night))
	sky.set_shader_parameter("rain",float(rain))

func update_altitude(meters: float, environment: Environment) -> void:
	_altitude = meters
	var high_air := smoothstep(650.0,11600.0,meters)
	environment.ambient_light_color = Color("#d1d1d1").lerp(Color(0.65,0.75,0.9),high_air)
	if is_instance_valid(_sun):
		_sun.light_color = Color("#c2c2c2").lerp(Color("#acc3e8"),high_air) if _night else Color("#ffdaaf")
	drops.emitting = _rain and meters < 7800.0

func _process(delta: float) -> void:
	if drops.emitting:
		elapsed+=delta
		if wind_setting != Vector2.ZERO:
			var gust := wind_setting*(0.94+0.09*sin(elapsed*1.25))
			motion.direction=Vector3(gust.x,-21.0,gust.y).normalized()
		var camera:=get_viewport().get_camera_3d()
		if camera:
			global_position=camera.global_position+Vector3.UP*14.0
