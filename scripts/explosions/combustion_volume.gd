extends MeshInstance3D

const Profile := preload("res://scripts/explosions/explosion_profile.gd")
const VOLUME := preload("res://assets/shaders/combustion_volume.gdshader")
const Propagation := preload("res://scripts/core/propagation.gd")
const CLOUD_TRAVEL_SPEED := Propagation.SPEED * 0.90
const TURBULENCE := preload("res://data/presets/burst_volume_noise.tres")

const Device := preload("res://scripts/devices/trial_device.gd")
var wind := Vector2.ZERO
var effect_quality := 1
var adaptive_quality := true
var blast_mode := Device.BlastMode.SURFACE
var ignition_delay := 0.0
var conditions := Vector4i.ZERO
var profile: Profile
const FIELD := preload("res://assets/shaders/procedural_explosion_field.gdshader")
const CLOUD_2K := Vector4(96,21,2016,480)
const CLOUD_UHD := Vector4(192,20,3840,2160)
const CLOUD_8K := Vector4(312,24,7680,4320)
const CLOUD_12K := Vector4(384,30,11520,6480)
const CLOUD_LAYOUTS := [CLOUD_2K,CLOUD_UHD,CLOUD_8K,CLOUD_12K]
var sun_direction := Vector3(-0.61,0.73,0.30)
var _atlas: SubViewport
var _field: ColorRect
var _render_quality: int
var _frame_budget := 1.0/60.0
var _mean_frame_time := 1.0/60.0
var _over_budget_time := 0.0
var _density := ShaderMaterial.new()
var _variation: Vector3
var seed: int
var _material := ShaderMaterial.new()
var _origin: Vector3
var floor_at_origin := INF
var terrain_craters: PackedVector4Array
var terrain_heave := Vector4.ZERO
var occlusion_material: ShaderMaterial

func _ready() -> void:
	name = "CombustionVolume"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mesh = box
	_origin = global_position
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shader = VOLUME
	_material.render_priority = 2
	_material.set_shader_parameter("turbulence", TURBULENCE)
	var random := RandomNumberGenerator.new()
	random.seed = seed
	_variation = Vector3(random.randf(),random.randf(),random.randf())
	_atlas = SubViewport.new()
	_atlas.disable_3d = true
	_atlas.use_hdr_2d = true
	_atlas.transparent_bg = true
	_atlas.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_atlas)
	_field = ColorRect.new()
	_density.shader = FIELD
	_density.set_shader_parameter("turbulence",TURBULENCE)
	_density.set_shader_parameter("variation",_variation)
	_density.set_shader_parameter("thermonuclear",float(profile.thermonuclear_visual))
	_field.material = _density
	_atlas.add_child(_field)
	set_effect_quality(effect_quality)
	var target_fps := 60.0
	if Engine.max_fps > 0:
		target_fps = minf(target_fps,Engine.max_fps)
	if DisplayServer.get_name() != "headless":
		var refresh := DisplayServer.screen_get_refresh_rate(get_window().current_screen)
		if refresh > 0.0:
			target_fps = minf(target_fps,refresh)
	_frame_budget = 1.0/target_fps
	_mean_frame_time = _frame_budget
	_material.set_shader_parameter("field",_atlas.get_texture())
	var crater_count := terrain_craters.size()
	terrain_craters.resize(16)
	_density.set_shader_parameter("terrain_craters",terrain_craters)
	_density.set_shader_parameter("terrain_crater_count",crater_count)
	if occlusion_material != null:
		occlusion_material.set_shader_parameter("cloud_field",_atlas.get_texture())
		occlusion_material.set_shader_parameter("sun_direction",sun_direction.normalized())
	_material.set_shader_parameter("sun_direction",sun_direction.normalized())
	_material.set_shader_parameter("variation",_variation)
	_material.set_shader_parameter("thermonuclear",float(profile.thermonuclear_visual))
	material_override = _material
	hide()

func set_effect_quality(quality: int) -> void:
	effect_quality = quality
	_configure_atlas(clampi(quality+1,1,CLOUD_LAYOUTS.size()-1))

func _configure_atlas(quality: int) -> void:
	_render_quality = quality
	var layout: Vector4 = CLOUD_LAYOUTS[quality]
	# The unused bottom rows never store voxels.
	layout.w = ceilf(layout.x/layout.y)*layout.x
	_atlas.size = Vector2i(int(layout.z),int(layout.w))
	_field.size = _atlas.size
	_density.set_shader_parameter("cloud_layout",layout)
	_material.set_shader_parameter("cloud_layout",layout)
	if occlusion_material != null:
		occlusion_material.set_shader_parameter("cloud_layout",layout)

func adjust_quality(frame_time: float) -> void:
	if not adaptive_quality or _render_quality == 0:
		return
	var sample := minf(frame_time,0.10)
	_mean_frame_time = lerpf(_mean_frame_time,sample,1.0-exp(-sample/0.14))
	if _mean_frame_time <= _frame_budget*1.20:
		_over_budget_time = 0.0
		return
	_over_budget_time += sample
	if _over_budget_time < 0.32:
		return
	# Only step down within a trial so detail doesn't jump back and forth.
	var drop := 2 if _mean_frame_time > _frame_budget*2.20 else 1
	_configure_atlas(maxi(0,_render_quality-drop))
	_mean_frame_time = _frame_budget
	_over_budget_time = 0.0

func clear_shadow() -> void:
	if occlusion_material != null:
		occlusion_material.set_shader_parameter("cloud_strength",0.0)
		occlusion_material.set_shader_parameter("cloud_field",null)

func advance(age: float, eye_distance: float) -> void:
	if age <= 0.0 or age >= profile.cloud_lifetime():
		hide()
		return
	var thermal := blast_mode == Device.BlastMode.THERMOBARIC
	var underground := blast_mode == Device.BlastMode.UNDERGROUND
	var heat_age := maxf(0.0,age-ignition_delay)
	var motion_time := profile.heat_duration*lerpf(2.10,3.28,profile.visual_growth)
	var transition := 1.0-exp(-heat_age/motion_time)
	var forming_time := profile.lifetime*0.72
	var motion_age := minf(heat_age,forming_time)+maxf(heat_age-forming_time,0.0)/profile.cloud_linger
	var phase := 3.2*transition+8.8*motion_age/(profile.lifetime-ignition_delay)
	var spray := smoothstep(0.0,ignition_delay,age) if thermal else 0.0
	var ignition := smoothstep(0.0,0.09,heat_age) if thermal else 0.0
	var thermal_formation := 0.0
	var thermal_lift := 1.0-exp(-heat_age/(3.5+profile.heat_duration*1.7)) if thermal else 0.0
	_density.set_shader_parameter("precursor",spray*(1.0-ignition))
	_density.set_shader_parameter("ignited",smoothstep(0.0,0.20,heat_age) if ignition_delay > 0.0 else 1.0)
	_density.set_shader_parameter("burst_kind",blast_mode)
	if profile.thermonuclear_visual:
		var expansion := 1.0-exp(-heat_age/0.73)
		var presence := smoothstep(0.0,0.10,heat_age)*(1.0-smoothstep(1.75,4.2,heat_age))
		var core_heat := exp(-heat_age/1.12)
		_density.set_shader_parameter("ignition_form",Vector3(expansion,presence,core_heat))
	if thermal:
		var opening_time := maxf(0.22,profile.fire_radius*0.90/CLOUD_TRAVEL_SPEED)
		thermal_formation = smoothstep(0.0,opening_time,heat_age)
		var glow := exp(-heat_age/(0.55+profile.heat_duration*0.93))
		_density.set_shader_parameter("thermal_shape",Vector4(spray,ignition,glow,thermal_lift))
		_density.set_shader_parameter("thermal_formation",thermal_formation)
		_density.set_shader_parameter("thermal_direction",Device.SPREAD_DIRECTION)
	var life := age/profile.lifetime
	var cloud_life := age/profile.cloud_lifetime()
	_density.set_shader_parameter("age",phase)
	_density.set_shader_parameter("elapsed_fraction",cloud_life)
	_material.set_shader_parameter("elapsed_fraction",cloud_life)
	_material.set_shader_parameter("flash_light",exp(-heat_age/(profile.heat_duration*0.62)) if age>=ignition_delay else 0.0)

	var style := profile.visual_growth
	var crown := 0.0 if thermal else smoothstep(0.34,0.97,style)*(0.24 if underground else 1.0)
	var lift := log(1.0 + phase)
	var spread := 1.0 - exp(-phase * 3.0)
	var unit := profile.fire_radius / 15.0 * lerpf(1.25,2.05,style)
	var width := (4.0+25.0*spread+10.0*lift)*unit*lerpf(0.97,1.03,_variation.x)
	var top := (5.0+22.0*spread+27.0*lift)*unit
	if thermal:
		# Keep the same footprint through spray, ignition and the cooling plume.
		var initial_width := lerpf(5.0,27.0,spray)*unit
		var expansion := 1.0+0.28*thermal_formation+0.72*thermal_lift
		width = initial_width*expansion*lerpf(0.97,1.03,_variation.x)
		top = width
	elif underground:
		top *= 0.54
	if not thermal:
		top *= lerpf(0.73,1.26,style)*lerpf(0.97,1.03,_variation.y)
	if profile.presentation_height > 0.0 and blast_mode == Device.BlastMode.SURFACE:
		var climb := smoothstep(0.025,0.72,life)
		top = lerpf(top,profile.presentation_height/0.83,climb)
		width = lerpf(width,profile.presentation_height*0.43*lerpf(0.96,1.04,_variation.x),climb)
	# Integrate the wind from rest and measure mixing against the cloud's original size.
	var travel := age-1.1*(1.0-exp(-age/1.1))
	var displacement := wind*travel
	var cloud_size := maxf(12.0,profile.fire_radius*4.8)
	var exposure := displacement.length()/cloud_size
	var mixing := exposure*lerpf(0.50,0.29,style)
	var survival := exp(-mixing)*(1.0-smoothstep(3.4,5.4,mixing))
	# Limit screen opacity as well as local density: long sightlines can otherwise
	# leave a white ribbon even after the smoke has been diluted.
	var opacity := maxf(survival,1.0-smoothstep(0.18,profile.heat_duration*1.7,heat_age))
	visible = opacity > 0.001
	if not visible:
		if occlusion_material != null:
			occlusion_material.set_shader_parameter("cloud_strength",0.0)
		return
	var spread_amount := (1.0-exp(-exposure*0.65))*exp(-mixing*0.40)
	var wind_spread := Vector2(1.0+0.94*spread_amount,1.0+0.39*spread_amount)
	var direction := wind.normalized().abs()
	var envelope := Vector2.ONE*wind_spread.y+direction*(wind_spread.x-wind_spread.y)
	var shifted := displacement*0.52
	var half_span := envelope*width+displacement.abs()*0.59
	var dust_depth := maxf(0.70,profile.dust_height*(2.75 if profile.thermonuclear_visual else 2.4))
	if profile.ground_dust > 0.0:
		var spread_progress := smoothstep(0.0,16.0,heat_age)*(1.0-0.45*exp(-heat_age/34.0))
		var dust_radius := minf(width*0.89,profile.fire_radius*lerpf(7.0,18.0,profile.ground_dust)*spread_progress)
		var settling := 1.0-smoothstep(0.14,0.76,cloud_life)
		var dust_opacity := lerpf(0.65,2.40,profile.ground_dust)*settling*smoothstep(0.30,3.0,heat_age)
		dust_opacity *= 1.0-float(conditions.y)*0.58
		_density.set_shader_parameter("ground_dust",Vector2(dust_radius/(2.0*width),dust_opacity))
		dust_depth = maxf(dust_depth*(1.0+0.95*profile.ground_dust),top*0.012*profile.ground_dust)
	var low_y := _origin.y-2.0*unit
	if thermal:
		low_y = _origin.y-width
		if is_finite(floor_at_origin):
			low_y = minf(low_y,floor_at_origin-dust_depth*0.40)
	elif is_finite(floor_at_origin):
		low_y = minf(low_y,floor_at_origin-dust_depth*0.38)
	# Scale the entire envelope about the source, including wind drift and its corners.
	var far_corner := Vector3(half_span.x+absf(shifted.x),
		maxf(top,absf(low_y-_origin.y)),half_span.y+absf(shifted.y))
	var spread_age := age if thermal else heat_age
	# The aerosol also changes shape at ignition, so reserve extra room for that motion.
	var travel_speed := CLOUD_TRAVEL_SPEED*(0.93 if thermal else 1.0)
	var reach := travel_speed*spread_age
	if reach <= 0.0:
		hide()
		return
	var ratio := reach/maxf(far_corner.length(),0.001)
	# Ease out of the speed limit as the volume approaches its authored size.
	var travel_scale := ratio if ratio <= 0.88 else 1.0-pow(maxf(1.12-ratio,0.0),2.0)/0.48
	shifted *= travel_scale
	half_span *= travel_scale
	displacement *= travel_scale
	width *= travel_scale
	top *= travel_scale
	low_y = lerpf(_origin.y,low_y,travel_scale)
	dust_depth *= travel_scale
	var box_min := Vector3(_origin.x+shifted.x-half_span.x,low_y,_origin.z+shifted.y-half_span.y)
	var box_max := _origin + Vector3(shifted.x+half_span.x,top,shifted.y+half_span.y)
	global_position = (box_max + box_min)*0.5
	scale = box_max-box_min
	var ground_level := (_origin.y-box_min.y)/scale.y
	_density.set_shader_parameter("terrain_rect",Vector4(box_min.x,box_min.z,scale.x,scale.z))
	_density.set_shader_parameter("terrain_vertical",Vector3(box_min.y,scale.y,dust_depth))
	if thermal:
		var floor_y := floor_at_origin if is_finite(floor_at_origin) else low_y
		var floor_level := (floor_y-low_y)/scale.y
		_density.set_shader_parameter("thermal_floor",floor_level)
		_density.set_shader_parameter("thermal_vertical_ratio",scale.y/(width*2.0))
	_density.set_shader_parameter("terrain_heave",terrain_heave)
	if occlusion_material != null:
		var shadow_age := smoothstep(0.10,0.85,heat_age)*(1.0-smoothstep(0.63,1.0,cloud_life))
		occlusion_material.set_shader_parameter("cloud_min",box_min)
		occlusion_material.set_shader_parameter("cloud_max",box_max)
		occlusion_material.set_shader_parameter("cloud_strength",shadow_age*opacity*(0.52 if conditions.x == 1 else (0.80 if conditions.y == 1 else 0.94)))
	var wind_frame := Vector4(shifted.x/(2.0*width),shifted.y/(2.0*width),
		half_span.x/width,half_span.y/width)
	for material: ShaderMaterial in [_density,_material]:
		material.set_shader_parameter("wind_drift",displacement/(2.0*width))
		material.set_shader_parameter("wind_ground",ground_level)
		material.set_shader_parameter("wind_frame",wind_frame)
		material.set_shader_parameter("wind_spread",wind_spread)
	var dilution := exp(-mixing*0.55)/(wind_spread.x*wind_spread.y)
	_density.set_shader_parameter("wind_dilution",dilution)
	_density.set_shader_parameter("wind_erosion",1.0-exp(-mixing*0.65))
	_material.set_shader_parameter("wind_visibility",opacity)
	var mushroom := profile.presentation_height > 0.0 and blast_mode == Device.BlastMode.SURFACE
	var fire := 0.0
	var cap_fire := 0.0
	if mushroom:
		fire = smoothstep(0.0,0.36,heat_age)*exp(-heat_age/(3.2*profile.heat_duration))
		fire *= 1.0-smoothstep(0.30,0.63,life)
		cap_fire = smoothstep(0.72,2.50,phase)*(1.0-smoothstep(0.29,0.57,life))
		cap_fire *= exp(-heat_age/(5.4*profile.heat_duration))
	var flame_height := clampf(profile.fire_radius*2.4/scale.y,0.075,0.30)
	_density.set_shader_parameter("crown",maxf(crown,0.91) if mushroom else crown)
	_density.set_shader_parameter("ground_level",ground_level)
	_density.set_shader_parameter("flame_height",flame_height)
	_density.set_shader_parameter("mature_fire",fire)
	_density.set_shader_parameter("cap_fire",cap_fire)
	_density.set_shader_parameter("mushroom",float(mushroom))
	_material.set_shader_parameter("ground_light",fire)
	_material.set_shader_parameter("ground_level",ground_level)
	_material.set_shader_parameter("flame_height",flame_height)
	_material.set_shader_parameter("cap_fire",cap_fire)
	_atlas.render_target_update_mode = SubViewport.UPDATE_ONCE
	var steps := 76 if eye_distance > width*2.7 else 64
	if fire + cap_fire > 0.004:
		steps = 88 if eye_distance > width*2.7 else 104
	if get_viewport().get_texture().get_height() >= 1440:
		steps += 20
	_material.set_shader_parameter("steps",steps+(_render_quality-1)*12)

	_material.set_shader_parameter("age", phase)
	_material.set_shader_parameter("weather", Vector3(0.0,float(conditions.y),float(conditions.x)))
	_material.set_shader_parameter("bounds_min", box_min)
	_material.set_shader_parameter("bounds_max", box_max)
	_material.set_shader_parameter("world_scale",lerpf(unit,maxf(unit,width/39.0),0.80))
	_material.set_shader_parameter("discharge", _discharge(age, phase, crown))
	_material.set_shader_parameter("dust_weight", lerpf(1.85,0.94,style)*(2.3 if underground else 1.0))
	_material.set_shader_parameter("heat_gain", lerpf(0.74,1.17,style)*(0.23 if underground else (1.47 if thermal else 1.0)))

func _discharge(seconds: float, phase: float, maturity: float) -> Vector3:
	if profile.tier < 4 or phase < 0.70 or phase > 9.0:
		return Vector3.ZERO
	var cycle := seconds / 2.75
	var index := floori(cycle)
	var variation := fposmod(sin(index*71.35+float(posmod(seed,997)))*437.53, 1.0)
	var t := (cycle-index)*2.75 - 0.21 - variation*0.52
	if t < 0.0 or t > 0.73:
		return Vector3.ZERO
	var first := smoothstep(0.0,0.035,t)*exp(-maxf(0.0,t-0.035)*10.0)
	var echo := smoothstep(0.22,0.26,t)*exp(-maxf(0.0,t-0.26)*15.0)
	var strength := (first + echo*0.62)*maturity*smoothstep(0.70,1.25,phase)*(1.0-smoothstep(6.3,9.0,phase))
	return Vector3(strength, index*2.39996+variation, variation)
