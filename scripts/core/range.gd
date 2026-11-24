extends Node3D

const Propagation := preload("res://scripts/core/propagation.gd")
const Ground := preload("res://scripts/terrain/range_ground.gd")
const Backdrop := preload("res://scripts/terrain/backdrop.gd")
const Device := preload("res://scripts/devices/trial_device.gd")
const Director := preload("res://scripts/cameras/camera_director.gd")
const Scenario := preload("res://scripts/editor/scenarios.gd")
const Controls := preload("res://scripts/core/control_bindings.gd")
const Settings := preload("res://scripts/core/game_settings.gd")
const Record := preload("res://scripts/core/trial_record.gd")
const Burst := preload("res://scripts/explosions/burst.gd")
const Target := preload("res://scripts/destruction/range_target.gd")
const WaveTargets := preload("res://scripts/destruction/wave_targets.gd")
const Layout := preload("res://scripts/editor/range_layout.gd")
const HUD := preload("res://scripts/ui/range_hud.gd")
const SettingsOverlay := preload("res://scripts/ui/settings_overlay.gd")
const EditorControls := preload("res://scripts/ui/editor_controls.gd")
const Catalog := preload("res://scripts/explosions/yield_catalog.gd")
const CHARGE := preload("res://assets/models/charge.glb")
const FRONT := preload("res://assets/shaders/front.gdshader")
const INITIAL_POINT := Vector3(0.0, 0.0, 1.3)

@onready var camera: Director.FreeCamera = $Camera
@onready var ground: Ground = $Ground
@onready var landscape: Backdrop = $Backdrop
const Weather := preload("res://scripts/terrain/weather.gd")
var weather: Weather

func _conditions() -> Vector4i:
	var c := _hud.conditions
	return Vector4i(c[0].selected,c[1].selected,_hud.wind_speed.selected,0)

func _restore_conditions(value: Vector4i, direction: int = 0) -> void:
	for i in 2:
		_hud.conditions[i].select(clampi(value[i],0,_hud.conditions[i].item_count-1))
	_hud.wind_speed.select(clampi(value.z,0,HUD.WIND_SPEEDS.size()-1))
	_hud.wind_direction.select(clampi(direction,0,_hud.wind_direction.item_count-1))
	_update_weather()

func _wind() -> Vector2:
	return Vector2.RIGHT.rotated(float(_hud.wind_direction.selected)*TAU/8.0)*HUD.WIND_SPEEDS[_hud.wind_speed.selected]

func _update_weather() -> void:
	var state := _conditions()
	ground.surface_material().set_shader_parameter("wetness",float(state.y))
	_hud.wind_direction.visible = state.z > 0
	weather.apply(_wind(),state.y==1,state.x==1,$Environment.environment,$Sun)

var preview_only := false
var profile := Catalog.make_profile(100.0)
var point := INITIAL_POINT
var wall: Target
var effect: Burst
var layout := Layout.new()
var targets: Array[Target] = []
var _waves: WaveTargets
var _hud: HUD
var _device: Node3D
var _marker: MeshInstance3D
var _target_root: Node3D
var _preview: MeshInstance3D
var _preview_material: StandardMaterial3D
var _editor_selection := -1
var _has_run := false
var _pending_click := false
var _click_position := Vector2.ZERO
var _front_passed_camera := false
var _shake := 0.0
var _shake_phase := 0.0
var _director: Director
const WalkingObserver := preload("res://scripts/cameras/walking_observer.gd")
var _walker: WalkingObserver
var _walk_wave_passed := false
var _kind: int = Device.Kind.GROUND
var _blast_mode := Device.BlastMode.SURFACE
var _heave_radius := 0.0
var _heave_amplitude := 0.0
var _heave_tick := -1
var _deep_heave := false
var _power := 100.0
var _last_seed := -1
var _record: Record
var _replaying := false
var _before_replay: Record
var _trial_done := false
var _trial_time := 0.0
var _shake_enabled := false
var _effect_quality := 1
var _adaptive_effects := true
var _dynamic_shadows := true
var _pause_menu: SettingsOverlay
var _was_paused := false

func _ready() -> void:
	landscape.material_override = ground.surface_material()
	landscape.set_instance_shader_parameter("distant_ground",true)
	var options := Settings.read()
	$Environment.environment = $Environment.environment.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	apply_graphics(options)
	if preview_only:
		camera.manual_enabled = false
		camera.global_position = Vector3(430, 330, 810)
		camera.look_at(Vector3(280, 14, -910))
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	Settings.apply(options, get_window())
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera.ground = ground
	_director = Director.new()
	_director.camera = camera
	add_child(_director)
	_device = CHARGE.instantiate() as Node3D
	add_child(_device)
	_marker = _ground_plane(FRONT, 3.6)
	var material := _marker.material_override as ShaderMaterial
	material.set_shader_parameter("marker", true)
	material.set_shader_parameter("width", 0.028)
	_preview = MeshInstance3D.new()
	_preview.mesh = BoxMesh.new()
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_material = StandardMaterial3D.new()
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview.material_override = _preview_material
	_preview.hide()
	add_child(_preview)

	_hud = HUD.new()
	_hud.device_title = "TR-01   /   %s" % profile.display_yield
	add_child(_hud)
	weather = Weather.new()
	add_child(weather)
	_hud.atmosphere_changed.connect(_update_weather)
	_update_weather()
	_hud.injuries_requested.connect(_toggle_injuries)
	_hud.run_requested.connect(run_trial)
	_hud.reset_requested.connect(reset_trial)
	_hud.editor.save_requested.connect(_save_map)
	_hud.editor.load_requested.connect(_load_map)
	_hud.editor.mode_changed.connect(_editor_toggled)
	_hud.editor.tool_changed.connect(_clear_editor_selection)
	_hud.speed_selected.connect(_set_speed)
	_walker = WalkingObserver.new()
	_walker.camera = camera
	_walker.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_walker)
	_director.mode_changed.connect(_on_camera_mode)
	_hud.blast_selected.connect(set_blast_mode)
	_hud.power_changed.connect(set_power)
	_pause_menu = SettingsOverlay.new()
	add_child(_pause_menu)
	_pause_menu.settings_changed.connect(apply_graphics)
	_pause_menu.dismissed.connect(_resume_from_menu)
	_pause_menu.main_menu_requested.connect(_go_to_menu)
	Scenario.configure(layout)
	set_power(Scenario.INITIAL_POWER)
	_place_charge(INITIAL_POINT)
	reset_trial()

func apply_graphics(options: Dictionary) -> void:
	$Environment.environment.glow_enabled = options["glow"]
	$Environment.environment.ssao_enabled = options["ao"]
	$Environment.environment.ssil_enabled = options["ssil"]
	$Occlusion.visible = options["cloud_shadows"]
	var shadow_quality: int = options["shadow_quality"]
	_dynamic_shadows = shadow_quality > 0
	$Sun.shadow_enabled = _dynamic_shadows
	$Sun.directional_shadow_max_distance = [160.0, 160.0, 420.0, 900.0][shadow_quality]
	if is_instance_valid(effect):
		effect.set_light_shadows(_dynamic_shadows)
	_effect_quality = options["effect_quality"]
	_adaptive_effects = options["adaptive_effects"]
	_shake_enabled = options["camera_kick"]
	if not _shake_enabled:
		_shake = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0

func _input(event: InputEvent) -> void:
	if preview_only or not event is InputEventKey or not event.pressed or event.echo:
		return
	if Controls.action_for(event) != "pause":
		return
	get_viewport().set_input_as_handled()
	_was_paused = get_tree().paused
	get_tree().paused = true
	_pending_click = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	_pause_menu.open_pause()

func _resume_from_menu() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = _was_paused
	_hud.show()

func _exit_tree() -> void:
	if not preview_only:
		RenderingServer.global_shader_parameter_set(&"weather_flash_gain",0.0)
		if get_tree() != null:
			get_tree().paused = false
		Engine.time_scale = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match Controls.action_for(event):
			"detonate":
				run_trial()
				get_viewport().set_input_as_handled()
			"reset":
				reset_trial()
				get_viewport().set_input_as_handled()
			"observer":
				_director.select(Director.Mode.FREE if camera.walking else Director.Mode.WALK)
				get_viewport().set_input_as_handled()
			"view":
				if camera.walking:
					_walker.third_person = not _walker.third_person
					get_viewport().set_input_as_handled()
			"injuries":
				_toggle_injuries()
				get_viewport().set_input_as_handled()
			"respawn":
				if camera.walking and _walker.health <= 0.0:
					_respawn_observer()
					get_viewport().set_input_as_handled()
			"replay":
				replay_trial()
				get_viewport().set_input_as_handled()
			"slow":
				_toggle_slow()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not _has_run and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			_click_position = event.position
			_pending_click = true
			get_viewport().set_input_as_handled()

func _toggle_injuries() -> void:
	if camera.walking:
		_hud.toggle_injuries()
		_hud.update_injuries(_walker)

func _on_camera_mode(mode: int) -> void:
	var walking := mode == Director.Mode.WALK
	if walking == camera.walking:
		return
	camera.walking = walking
	if walking:
		_walker.enter(ground)
		_walk_wave_passed = is_instance_valid(effect) and not effect.contained and effect.visual_radius() >= _walker.body_position().distance_to(effect.global_position)
	else:
		_walker.leave()
	_hud.observer_status(walking,_walker.health,_walker.third_person,_walker.injury_text(),_walker.reaction_text())

func _physics_process(_delta: float) -> void:
	ground.stream_near(camera.global_position)
	if _pending_click:
		_pending_click = false
		var clicked := _ground_point(_click_position)
		if clicked != Vector3.INF:
			if _hud.editor.active():
				_edit_ground(clicked)
			else:
				_place_charge(clicked)
	_update_preview()

func _ground_point(screen_position: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+direction*360000.0,1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var location := ground.ray_to_surface(origin,direction) if hit.is_empty() else hit["position"] as Vector3
	if location == Vector3.INF or maxf(absf(location.x),absf(location.z)) > Layout.LIMIT:
		return Vector3.INF
	return location

func _process(delta: float) -> void:
	var position := camera.global_position
	var altitude := position.y-Ground.base_height(position.x,position.z)
	weather.update_altitude(altitude,$Environment.environment)
	_hud.altitude(altitude)
	if _has_run and not _trial_done and not get_tree().paused:
		_trial_time += delta
	var simulation_delta := 0.0 if get_tree().paused else delta
	_shake = move_toward(_shake, 0.0, simulation_delta * 1.18)
	_shake_phase += simulation_delta * 35.0
	camera.h_offset = sin(_shake_phase * 1.7) * _shake
	camera.v_offset = sin(_shake_phase * 2.11) * _shake * 0.57
	_hud.observer_status(camera.walking,_walker.health,_walker.third_person,_walker.injury_text(),_walker.reaction_text())
	_hud.update_injuries(_walker)
	var origin := effect.global_position if is_instance_valid(effect) else point
	var distance := camera.global_position.distance_to(origin)
	var arrival := effect.sound_arrival() if is_instance_valid(effect) else -1.0
	_hud.acoustic_distance(distance, Propagation.travel_time(distance), arrival)
	if not is_instance_valid(effect):
		return
	if _heave_radius > 0.0 and not get_tree().paused:
		_update_heave(effect.age)
	if not get_tree().paused:
		_update_observer_response(effect)
	var glare := _walker.glare if camera.walking else 0.0
	if effect.contained:
		if _shake_enabled and not get_tree().paused:
			var tremor := sin(effect.age*20.0)*exp(-effect.age*1.65)
			_shake = maxf(_shake,absf(tremor)*0.55*(1.0-smoothstep(0.0,_heave_radius*2.0,distance)))
		return
	var crest := effect.rendered_front_radius()
	var width := clampf(3.4 + crest * 0.046, 3.4, 96.0)
	ground.show_wave(origin, crest, profile.front_radius, 1.0-effect.rendered_front_impulse(), width)
	var pos := effect.global_position + Vector3.UP
	var viewport_rect := get_viewport().get_visible_rect().grow(115.0)
	var on_screen := not camera.is_position_behind(pos) and viewport_rect.has_point(camera.unproject_position(pos))
	var hot_age := effect.age-effect.ignition_delay
	var exposure := exp(-hot_age * 22.0 / (1.0 + profile.tier * 0.3)) * (0.27 + profile.tier * 0.032) if hot_age >= 0.0 else 0.0
	_hud.flash(maxf(glare,exposure if on_screen else 0.0))

func _update_observer_response(burst: Burst) -> void:
	if not camera.walking or _walk_wave_passed or _walker.health <= 0.0:
		return
	var relative := _walker.body_position()-burst.global_position
	var distance := relative.length()
	var direction := relative.slide(Vector3.UP).normalized()
	if direction.is_zero_approx():
		direction = camera.global_basis.z.slide(Vector3.UP).normalized()
	if burst.contained:
		var support := ground.height_at(_walker.position.x,_walker.position.z)
		if burst.age >= 0.24 and burst.age < 2.1 and distance < _heave_radius and absf(_walker.position.y-support) < 1.5:
			_walk_wave_passed = true
			var tremor := 1.0-smoothstep(_heave_radius*0.18,_heave_radius,distance)
			_walker.react_to_ground(tremor,_record.depth >= Device.SUBSIDENCE_EFFECT_AT,direction)
		return
	if burst.visual_radius() < distance:
		return
	_walk_wave_passed = true
	var strength := burst.visual_strength()
	var contact := 1.0-smoothstep(0.42,0.85,distance/profile.fire_radius)
	var severe := contact > 0.74 or (profile.tier >= 5 and strength*strength > 0.68)
	var exposed := true
	if burst.blast_mode == Device.BlastMode.THERMOBARIC:
		var source := burst.global_position+Vector3.UP*minf(14.0,profile.fire_radius*0.38)
		var sight := PhysicsRayQueryParameters3D.create(_walker.body_position(),source,3)
		exposed = get_world_3d().direct_space_state.intersect_ray(sight).is_empty()
	_walker.react_to_blast(burst.blast_mode,direction,strength,contact,profile.visual_growth,severe,exposed)
	if _shake_enabled:
		_shake = maxf(_shake,0.14*strength)

func set_power(kg: float) -> void:
	if _has_run or not is_finite(kg):
		return
	_power = clampf(roundf(kg), Catalog.MIN_KG, Catalog.MAX_KG)
	profile = Catalog.make_profile(_power)
	profile.thermonuclear_visual = Catalog.is_thermonuclear(_power,_blast_mode)
	if _blast_mode == Device.BlastMode.SURFACE:
		Catalog.apply_surface_presentation(profile, _power)
	_hud.reflect_power(_power)
	_director.scale_hint = profile.fire_radius * lerpf(1.25,2.05,profile.visual_growth)*1.8
	_update_device_caption()

func set_device(kind: int) -> void:
	if _has_run or kind < 0 or kind >= Device.Kind.size():
		return
	_kind = kind
	_device.scale = Vector3.ONE * (1.8 if kind == Device.Kind.SPECIAL else 1.0)
	_update_device_caption()

func set_blast_mode(mode: int) -> void:
	if _has_run or mode < 0 or mode >= HUD.BLAST_NAMES.size():
		return
	_blast_mode = mode
	_hud.reflect_blast(mode)
	set_power(_power)

func _update_device_caption() -> void:
	var caption: String = HUD.BLAST_NAMES[_blast_mode]
	if _blast_mode == Device.BlastMode.SURFACE and profile.presentation_height > 0.0:
		caption = Catalog.THERMONUCLEAR_LABEL if profile.thermonuclear_visual else "Наземный · гриб"
	_hud.set_caption("%s · %s" % [Catalog.label(_power), tr(caption)])

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_hud) and _hud.is_node_ready():
		_update_device_caption()

func run_trial() -> void:
	if _has_run or _hud.editor.active():
		return
	_has_run = true
	_pending_click = false
	_front_passed_camera = false
	_walk_wave_passed = false
	_device.hide()
	_marker.hide()
	_trial_done = false
	_trial_time = 0.0
	_hud.result_actions()
	if not _replaying:
		_record = _make_record()
		_record.seed = int(randi())
		if _record.seed == _last_seed:
			_record.seed += 1
		_last_seed = _record.seed

	_impact(Vector3(point.x,ground.height_at(point.x,point.z),point.z))

func _impact(origin: Vector3) -> void:
	if camera.walking and _walker.health > 0.0 and profile.tier >= 4 and _record.blast_mode == Device.BlastMode.SURFACE:
		var observer := _walker.body_position()
		var glow := (1.0-smoothstep(0.18,0.85,observer.distance_to(origin)/profile.front_radius))
		if glow > 0.0:
			var flash_origin := origin+Vector3.UP*profile.fire_radius*0.48
			var ray := PhysicsRayQueryParameters3D.create(flash_origin,observer,3)
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				_walker.heat_burn(32.0*glow)
	var radius := clampf(2.5 + profile.fire_radius * 0.31, 2.7, Ground.RADIUS_LIMIT)
	var depth := clampf(0.74 + profile.fire_radius * 0.071, 0.6, 36.0)
	var underground := _record.blast_mode == Device.BlastMode.UNDERGROUND
	_deep_heave = underground and _record.depth >= Device.DEEP_EFFECT_AT
	if underground:
		_heave_radius = clampf(profile.fire_radius*1.45+_record.depth*0.50,10.0,Ground.RADIUS_LIMIT)
		_heave_amplitude = clampf(profile.fire_radius*0.20+2.0,2.0,16.0)*lerpf(1.0,0.55,clampf(_record.depth/120.0,0.0,1.0))
	elif _record.blast_mode == Device.BlastMode.SURFACE:
		ground.add_crater(point,radius,depth)
	_waves = WaveTargets.new()
	# Use the full extent of the game's shock front for structures.
	var reach := minf(profile.front_radius,_heave_radius*1.5) if _deep_heave else profile.front_radius
	var force := (0.62 if _deep_heave else 1.0)*(2.28+profile.tier*0.38)
	_waves.prepare(targets,origin,reach,force)
	effect = Burst.new()
	effect.process_mode = Node.PROCESS_MODE_PAUSABLE
	effect.seed = _record.seed
	effect.floor_height = _sample_land
	effect.profile = profile
	effect.wind = _wind()
	effect.effect_quality = _effect_quality
	effect.adaptive_effects = _adaptive_effects
	effect.set_light_shadows(_dynamic_shadows)
	effect.sun_direction = $Sun.global_basis.z
	effect.terrain_craters = PackedVector4Array(ground.craters)
	effect.occlusion_material = $Occlusion.material_override as ShaderMaterial
	effect.conditions = _conditions()
	effect.position = origin
	effect.blast_mode = _record.blast_mode
	effect.contained = _deep_heave
	if underground:
		effect.ignition_delay = 0.53
		effect.sound_depth = _record.depth
	elif _record.blast_mode == Device.BlastMode.THERMOBARIC:
		effect.ignition_delay = 0.66
	effect.front_advanced.connect(_on_front)
	effect.finished.connect(_on_finished)
	_waves.distant_collapse.connect(effect.distant_dust)
	if not _replaying:
		_waves.target_hit.connect(func(location: Vector3) -> void: _record.hits.append(location))
	add_child(effect)
	_hud.state("Распыление аэрозоля" if _record.blast_mode == Device.BlastMode.THERMOBARIC else "Испытание идёт",false,true)
	if _record.blast_mode == Device.BlastMode.THERMOBARIC:
		effect.ignited.connect(func() -> void: _hud.state("Испытание идёт",false,true))

func _update_heave(age: float) -> void:
	var tick := mini(36,floori(age*12.0))
	if _heave_tick == tick:
		return
	_heave_tick = tick
	var clock := float(tick)/12.0
	var rise := smoothstep(0.0,0.62,clock)
	var settle := smoothstep(0.68,2.95,clock)
	var deformation := rise-1.28*settle
	if _deep_heave:
		var shake := sin(clock*17.0)*sin(PI*clampf(clock/2.95,0.0,1.0))*0.24
		var resting := -0.82 if _record.depth >= Device.SUBSIDENCE_EFFECT_AT else 0.62
		deformation = resting*smoothstep(0.0,2.55,clock)+shake
	ground.heave_ground(point,_heave_radius,_heave_amplitude*deformation,
		smoothstep(0.18,1.30,clock))
	if is_instance_valid(effect._volume):
		effect._volume.terrain_heave = Vector4(point.x,point.z,_heave_radius,_heave_amplitude*deformation)
	for target in targets:
		var offset := target.position-point
		if target.last_hit_radius >= 0.0 or offset.slide(Vector3.UP).length() > _heave_radius:
			continue
		var x := target.position.x
		var z := target.position.z
		target.position.y = ground.height_at(x,z)
		var normal := Vector3(ground.height_at(x-1.0,z)-ground.height_at(x+1.0,z),2.0,
			ground.height_at(x,z-1.0)-ground.height_at(x,z+1.0)).normalized()
		var yaw := target.rotation.y
		var heading := Basis(Vector3.UP,yaw).z
		var right := normal.cross(heading).normalized()
		target.basis = Basis(right,normal,right.cross(normal))

func _respawn_observer() -> void:
	_walker.respawn(ground)
	if is_instance_valid(effect):
		_walk_wave_passed = effect.visual_radius() >= _walker.body_position().distance_to(effect.global_position)

func reset_trial() -> void:
	for tail in get_tree().get_nodes_in_group("range_audio_tails"):
		if tail.get_parent() == self:
			tail.cancel()
			remove_child(tail)
			tail.queue_free()
	_pending_click = false
	if is_instance_valid(effect):
		effect.cancel()
		remove_child(effect)
		effect.queue_free()
		effect = null
	_waves = null
	_has_run = false
	_trial_done = false
	_shake = 0.0
	ground.clear_wave()
	_hud.flash(0.0)
	_hud.state("Готов к испытанию", true, false)
	if _replaying:
		layout = _before_replay.configuration
		set_blast_mode(_before_replay.blast_mode)
		set_power(_before_replay.power)
		_hud.depth_control.value = _before_replay.depth
		set_device(_before_replay.device)
		_restore_conditions(_before_replay.conditions,_before_replay.wind_direction)
		_director.select(Director.Mode.FREE)
		camera.global_transform = _before_replay.camera_view
		_place_charge(_before_replay.point)
		_replaying = false
		_before_replay = null
	ground.clear_heave()
	_heave_radius = 0.0
	_heave_tick = -1
	_deep_heave = false
	ground.set_craters(layout.craters)
	if camera.walking and _walker.health <= 0.0:
		_respawn_observer()
	else:
		_walker.reset_injuries()
	_place_charge(point)
	_rebuild_targets()
	_device.show()
	_marker.visible = not _hud.editor.active()
	_hud.allow_launch(not _hud.editor.active())
	_hud.result_actions()

func _place_charge(location: Vector3) -> void:
	point = Vector3(location.x, ground.height_at(location.x, location.z), location.z)
	_director.focus = point
	_device.position = point
	_marker.position = point + Vector3.UP * 0.033
	_hud.coordinates(point)
	_keep_ground_sites()

func _on_front(radius: float) -> void:
	_waves.advance(radius)
	var distance := camera.global_position.distance_to(effect.global_position)
	if _shake_enabled and not effect.contained and not _front_passed_camera and distance <= radius:
		_front_passed_camera = true
		_shake = lerpf(0.46, 0.075, clampf(distance / profile.front_radius, 0.0, 1.0))

func _on_finished() -> void:
	_hud.flash(0.0)
	var broken := 0
	var damaged := 0
	for target in targets:
		if target.fractured:
			broken += 1
		elif target.last_hit_radius >= 0.0:
			damaged += 1
	_hud.state(tr("Разрушено %d   ·   повреждено %d") % [broken, damaged], false, true)
	_trial_done = true
	ground.clear_wave()
	_hud.result_actions(tr("Уцелело %d · %.1f с") % [targets.size()-broken-damaged,_trial_time])
	effect = null
	_waves = null

func _ground_plane(shader: Shader, size_metres: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * size_metres
	instance.mesh = plane
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = shader
	instance.material_override = material
	add_child(instance)
	return instance

func _rebuild_targets() -> void:
	_keep_ground_sites()
	if is_instance_valid(_target_root):
		remove_child(_target_root)
		_target_root.queue_free()
	_target_root = Node3D.new()
	_target_root.name = "Targets"
	_target_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_target_root)
	targets.clear()
	wall = null
	for item in layout.items:
		_spawn_target(item)
	_clear_editor_selection()

func _spawn_target(item: Layout.Placement) -> void:
	var target := Target.new()
	target.kind = item.kind
	target.position = _world_placement(item.location)
	target.rotation.y = item.yaw
	_target_root.add_child(target)
	targets.append(target)
	if wall == null and target.kind == Target.Kind.WALL:
		wall = target

func _edit_ground(at: Vector3) -> void:
	var tool := _hud.editor.tool()
	var selected := layout.nearest(at)
	match tool:
		EditorControls.Tool.ADD:
			if not _append_target(_hud.editor.kind(), _placement_point(at, _hud.editor.height()), 0.0):
				return
		EditorControls.Tool.ROTATE:
			if selected < 0:
				return
			var item := layout.items[selected]
			var angle := wrapf(item.yaw + deg_to_rad(15.0), -PI, PI)
			if not _transform_item(selected, item.location, angle):
				return
		EditorControls.Tool.REMOVE:
			if selected < 0:
				return
			layout.items.remove_at(selected)
			_rebuild_targets()
		EditorControls.Tool.HEIGHT:
			if selected < 0:
				return
			var item := layout.items[selected]
			var location := Vector3(item.location.x, _hud.editor.height(), item.location.z)
			if not _transform_item(selected, location, item.yaw):
				return
		EditorControls.Tool.MOVE, EditorControls.Tool.DUPLICATE:
			if _editor_selection < 0:
				if selected >= 0:
					_editor_selection = selected
					_hud.editor.show_message("ЛКМ — новое место")
				return
			var item := layout.items[_editor_selection]
			var location := _placement_point(at, item.location.y)
			if tool == EditorControls.Tool.MOVE:
				if not _transform_item(_editor_selection, location, item.yaw):
					return
			elif not _append_target(item.kind, location, item.yaw):
				return
			_clear_editor_selection()
	_hud.editor.show_message(tr("Объекты  %d / %d") % [layout.items.size(), Layout.CAPACITY])

func _append_target(kind: int, location: Vector3, yaw: float) -> bool:
	if not layout.append(kind, location, yaw):
		_hud.editor.show_message("Место занято или за границей")
		return false
	_keep_ground_sites()
	_spawn_target(layout.items.back())
	return true

func _transform_item(index: int, location: Vector3, yaw: float) -> bool:
	var item := layout.items[index]
	if not layout.can_place(item.kind, location, yaw, index):
		_hud.editor.show_message("Место занято или за границей")
		return false
	item.location = location
	item.yaw = yaw
	_keep_ground_sites()
	targets[index].position = _world_placement(location)
	targets[index].rotation.y = yaw
	return true

func _sample_land(x: float, z: float) -> float:
	return ground.height_at(x,z)

func _keep_ground_sites() -> void:
	var sites := PackedVector3Array([point])
	for item in layout.items:
		sites.append(item.location)
	ground.keep_sites(sites)

func _world_placement(location: Vector3) -> Vector3:
	return location + Vector3.UP * ground.height_at(location.x, location.z)

func _placement_point(at: Vector3, height: float) -> Vector3:
	var result := at.snapped(Vector3.ONE) if _hud.editor.snap_enabled() else at
	result.y = height
	return result

func _clear_editor_selection() -> void:
	_editor_selection = -1
	_hud.editor.show_message("ЛКМ по площадке")

func _update_preview() -> void:
	_preview.hide()
	if not _hud.editor.active() or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	var tool := _hud.editor.tool()
	if tool != EditorControls.Tool.ADD and _editor_selection < 0:
		return
	var at := _ground_point(get_viewport().get_mouse_position())
	if at == Vector3.INF:
		return
	var kind := _hud.editor.kind()
	var yaw := 0.0
	var height := _hud.editor.height()
	if _editor_selection >= 0:
		var item := layout.items[_editor_selection]
		kind = item.kind
		height = item.location.y
		yaw = item.yaw
	var location := _placement_point(at, height)
	var ignore := _editor_selection if tool == EditorControls.Tool.MOVE else -1
	var has_space := tool == EditorControls.Tool.MOVE or layout.items.size() < Layout.CAPACITY
	var valid := has_space and layout.can_place(kind, location, yaw, ignore)
	var bounds: Vector3 = Target.DIMENSIONS[kind]
	(_preview.mesh as BoxMesh).size = bounds
	_preview.position = _world_placement(location) + Vector3.UP * bounds.y * 0.5
	_preview.rotation.y = yaw
	_preview_material.albedo_color = Color("#68ec9290") if valid else Color("#ff695e90")
	_preview.show()

func _editor_toggled() -> void:
	_pending_click = false
	_clear_editor_selection()
	_marker.visible = not _hud.editor.active()
	_hud.allow_launch(not _hud.editor.active())

func _save_map() -> void:
	var result := layout.save_to()
	_hud.editor.show_message("Полигон сохранён" if result == OK else tr("Ошибка записи (%d)") % result)

func _load_map() -> void:
	var result := layout.load_from()
	if result == OK:
		ground.set_craters(layout.craters)
		_place_charge(point)
		_rebuild_targets()
		_hud.editor.show_message("Полигон загружен")
	else:
		_hud.editor.show_message(tr("Ошибка загрузки (%d)") % result)

func _toggle_slow() -> void:
	_set_speed(3 if not get_tree().paused and is_equal_approx(Engine.time_scale, 1.0) else 5)

func _set_speed(index: int) -> void:
	var selected := clampi(index, 0, HUD.SPEEDS.size() - 1)
	var speed: float = HUD.SPEEDS[selected]
	get_tree().paused = speed == 0.0
	if speed > 0.0:
		Engine.time_scale = speed
	_hud.reflect_speed(selected)

func _go_to_menu() -> void:
	_set_speed(5)
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")

func _make_record() -> Record:
	var record := Record.new()
	record.point = point
	record.power = _power
	record.device = _kind
	record.blast_mode = _blast_mode
	record.depth = _hud.depth_control.value
	record.conditions = _conditions()
	record.wind_direction = _hud.wind_direction.selected
	record.camera_view = camera.global_transform
	record.configuration = layout.snapshot() as Layout
	return record

func replay_trial() -> void:
	if _record == null or _hud.editor.active():
		return
	if _has_run:
		reset_trial()
	_before_replay = _make_record()
	layout = _record.configuration.snapshot() as Layout
	ground.set_craters(layout.craters)
	_rebuild_targets()
	set_blast_mode(_record.blast_mode)
	set_power(_record.power)
	_hud.depth_control.value = _record.depth
	set_device(_record.device)
	_restore_conditions(_record.conditions,_record.wind_direction)
	_director.select(Director.Mode.FREE)
	camera.global_transform = _record.camera_view
	_place_charge(_record.point)
	_replaying = true
	run_trial()

func _save_current_land() -> void:
	if not _trial_done or _replaying:
		return
	var old := layout.craters
	layout.craters = ground.craters.duplicate()
	var result := layout.save_to()
	if result != OK:
		layout.craters = old
	_hud.result_actions("Полигон сохранён" if result == OK else tr("Ошибка записи (%d)") % result)
