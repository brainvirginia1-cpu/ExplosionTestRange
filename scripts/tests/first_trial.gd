extends SceneTree

const MAIN := preload("res://scenes/main/range.tscn")
const RangeScene := preload("res://scripts/core/range.gd")
const Catalog := preload("res://scripts/explosions/yield_catalog.gd")
const Layout := preload("res://scripts/editor/range_layout.gd")
const Target := preload("res://scripts/destruction/range_target.gd")
const EditorControls := preload("res://scripts/ui/editor_controls.gd")
const AcousticEvent := preload("res://scripts/audio/acoustic_event.gd")
const Device := preload("res://scripts/devices/trial_device.gd")
const Director := preload("res://scripts/cameras/camera_director.gd")
const Propagation := preload("res://scripts/core/propagation.gd")
const MENU := preload("res://scenes/menus/main_menu.tscn")

var _capture := false
var _failed := false

func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_exercise")

func _exercise() -> void:
	root.size = Vector2i(1280, 720)
	var scene := MAIN.instantiate() as RangeScene
	root.add_child(scene)
	await process_frame
	scene.layout.defaults()
	scene.set_power(100.0)
	scene.reset_trial()

	_expect(scene.wall.sections.size() == 15, "intact wall contains 15 panels")
	var initial_children := scene.get_child_count()
	var selected := Vector3(2.5, 0.0, 0.0)
	_click(scene.camera.unproject_position(selected))
	await physics_frame
	await physics_frame
	await process_frame
	_expect(scene.point.distance_to(selected) < 0.12, "left click projects to the dirt surface")
	if _capture:
		await _save("01-ready")

	_press(KEY_SPACE)
	await process_frame
	if not _expect(is_instance_valid(scene.effect), "Space launches trial"):
		quit(1)
		return
	var effect := scene.effect
	_expect(not scene.wall.fractured, "wall is intact before the front reaches it")
	var cue := effect.get_node("AcousticEvent") as AcousticEvent
	_expect(not cue.playing, "visual burst precedes the spatial audio")
	var expected_delay := cue.global_position.distance_to(scene.camera.global_position) / 343.0
	await _wait_age(effect, expected_delay + 0.035)
	_expect(cue.playing and absf(cue.arrival_time - expected_delay) <= 0.019,
		"spatial sound arrives when the acoustic front reaches the camera")
	_press(KEY_SPACE)
	_expect(scene.effect == effect, "a second launch cannot create a concurrent effect")
	if _capture:
		await _wait_age(effect, 0.11)
		await _save("02-flash")
		await _wait_age(effect, 0.34)
		await _save("03-fire")
	await _wait_age(effect, 0.85)
	_expect(_has_physics_debris(scene.wall) and scene.wall.sections.any(func(body: RigidBody3D) -> bool: return body.freeze),
		"a moderate wave removes individual panels while anchors hold")
	if _capture:
		await _save("04-front")
		await _wait_age(effect, 2.05)
		await _save("05-smoke")

	await effect.tree_exited
	await process_frame
	_expect(scene.effect == null, "completed effect and its children are released")
	_press(KEY_R)
	await process_frame
	_expect(not scene.wall.fractured and scene.wall.sections.size() == 15, "R restores the wall")
	_expect(scene.point.distance_to(selected) < 0.12, "reset preserves the chosen test point")

	for cycle in range(20):
		scene.run_trial()
		scene.reset_trial()
		await process_frame
		_expect(scene.get_child_count() == initial_children, "reset releases temporary nodes on run %d" % (cycle + 1))

	var distant_point := Vector3(16.0, 0.0, -2.0)
	_click(scene.camera.unproject_position(distant_point))
	await physics_frame
	await physics_frame
	await process_frame
	_expect(scene.point.distance_to(distant_point) < 0.12, "different ground point can be selected")
	var launch := scene.find_child("RunTrial", true, false) as Button
	_click(launch.get_global_rect().get_center())
	if not _expect(is_instance_valid(scene.effect), "HUD button launches trial"):
		quit(1)
		return
	await _wait_age(scene.effect, 1.3)
	_expect(not scene.wall.fractured, "wall outside the game impact range is unchanged")
	var reset := scene.find_child("ResetTrial", true, false) as Button
	_click(reset.get_global_rect().get_center())
	_expect(scene.effect == null, "HUD button cancels the active trial")

	await _exercise_extended(scene)
	await _exercise_land_and_delivery(scene)
	await _exercise_effect_scale(scene)
	scene.queue_free()
	await process_frame
	await _exercise_menu()

	# Let the audio thread retire the stopped playback before process exit.
	var audio_cleanup_deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < audio_cleanup_deadline:
		await process_frame

	if not _failed:
		print("PASS: VFX anchors and dust, visible crater topology, physical debris at every distance, 343 m/s propagation, ground ignition, replay, editor and menu")
	quit(1 if _failed else 0)

func _exercise_extended(scene: RangeScene) -> void:
	var controls := scene._hud.blast_picker
	_expect(controls.item_count == 3, "only the ground modes are available")
	var initial_power := scene.profile.fire_radius
	controls.item_selected.emit(Device.BlastMode.THERMOBARIC)
	_expect(scene.profile.fire_radius == initial_power and scene._blast_mode == Device.BlastMode.THERMOBARIC,
		"changing blast mode preserves power")
	scene._hud.power_control._slider.value = 0.0
	_expect(scene.profile.tier == 0 and scene._blast_mode == Device.BlastMode.THERMOBARIC,
		"changing power preserves blast mode")
	controls.item_selected.emit(Device.BlastMode.SURFACE)
	var camera := scene.camera
	var original_view := camera.global_transform
	for distance in [34.3, 171.5, 343.0]:
		camera.position = scene.point + Vector3(0, 0, distance)
		scene.run_trial()
		var current := scene.effect
		var cue := current.get_node("AcousticEvent") as AcousticEvent
		var delay: float = distance / AcousticEvent.SOUND_SPEED
		await _wait_age(current, delay - 0.035)
		_expect(cue.arrival_time < 0.0, "sound is pending at %.1f m before %.2f s" % [distance, delay])
		await _wait_age(current, delay + 0.035)
		if distance == 343.0:
			_expect(current.visual_radius() > current.profile.front_radius and current.visual_strength() > 0.0,
				"rendered front continues beyond the old boundary")
			_expect(cue.volume_db < current.profile.audio_level_db and cue.max_distance == 0.0,
				"distant audio plays with soft attenuation beyond its former cutoff")
		_expect(absf(cue.arrival_time - delay) < 0.019, "sound arrives at %.1f m around %.2f s" % [distance, delay])
		scene.reset_trial()
		await process_frame
	camera.global_transform = original_view

	for input in [50.0, 10000.0, 10000000.0, 1000000000.0, 50000000000.0]:
		scene.set_power(input)
		_expect(scene.profile.tier == Catalog.tier_for(input), "correct visual tier")
		_expect(absf(Catalog.from_slider(Catalog.normalized(input)) - input) < 1.0, "logarithmic scale round trip")
		scene.run_trial()
		var effect := scene.effect
		if _capture and input == Catalog.MAX_KG:
			camera.global_position = scene.point+Vector3(3900,1350,5200)
			camera.look_at(scene.point+Vector3.UP*1200)
			_press(KEY_T)
			_expect(is_equal_approx(Engine.time_scale, 0.25), "slow motion engages")
			await _wait_age(effect, 0.30)
			await _save("07-max-fire")
			_press(KEY_T)
			await _wait_age(effect, 2.1)
			await _save("12-wave-at-distance")
			await _wait_age(effect, 9.2)
			await _save("08-max-column")
			await _save("13-cinematic-cloud")
			camera.global_transform = original_view
		await _wait_age(effect, scene.profile.front_duration + 0.04)
		if input == Catalog.MAX_KG:
			_expect(scene.targets.all(func(target: Target) -> bool: return target.fractured),
				"wall, steel shelter, container and drums react to the strongest preset")
			var near := scene.targets[0]
			var far := scene.targets[2]
			_expect(near.last_hit_radius >= 0.0 and far.last_hit_radius > near.last_hit_radius,
				"near target is reached earlier")
		scene.reset_trial()
		await process_frame

	var editor := scene._hud.editor
	editor._toggle.button_pressed = true
	var target_count := scene.targets.size()
	var at := Vector3(7, 0, -5)
	_click(camera.unproject_position(at))
	await physics_frame
	await physics_frame
	_expect(scene.targets.size() == target_count + 1, "editor places a target from a viewport click")
	if _capture:
		await _save("06-editor")
	editor._tool.select(EditorControls.Tool.ROTATE)
	scene._edit_ground(at)
	_expect(is_equal_approx(scene.targets.back().rotation.y, deg_to_rad(15.0)), "editor rotates the placed target")
	var moved := Vector3(9, 0, -6)
	editor._tool.select(EditorControls.Tool.MOVE)
	scene._edit_ground(at)
	scene._edit_ground(moved)
	_expect(scene.targets.back().position.is_equal_approx(moved), "editor moves the target")
	editor._tool.select(EditorControls.Tool.DUPLICATE)
	scene._edit_ground(moved)
	scene._edit_ground(Vector3(10, 0, -12))
	_expect(scene.targets.size() == target_count + 2, "editor duplicates a target")
	editor._tool.select(EditorControls.Tool.HEIGHT)
	editor._height.value = 1.5
	scene._edit_ground(Vector3(10, 0, -12))
	_expect(is_equal_approx(scene.targets.back().position.y, 1.5), "editor changes placement height")
	_expect(not scene.layout.can_place(Target.Kind.WALL, moved, 0.0), "layout rejects overlapping placements")
	var test_layout := Layout.new()
	var verification_path := ProjectSettings.globalize_path("res://verification")
	DirAccess.make_dir_recursive_absolute(verification_path)
	var layout_path := "res://verification/roundtrip_%s.json" % ("render" if _capture else "headless")
	var save_result := scene.layout.save_to(layout_path)
	var load_result := test_layout.load_from(layout_path) if save_result == OK else ERR_CANT_OPEN
	_expect(save_result == OK and load_result == OK and test_layout.items.size() == target_count + 2
		and is_equal_approx(test_layout.items.back().location.y, 1.5)
		and is_equal_approx(test_layout.items.back().yaw, deg_to_rad(15.0)),
		"layout save and reload preserve target orientation and height (save %d, load %d)" % [save_result, load_result])
	editor._tool.select(EditorControls.Tool.REMOVE)
	scene._edit_ground(Vector3(10, 0, -12))
	_expect(scene.targets.size() == target_count + 1, "editor removes a target")
	editor._toggle.button_pressed = false

	# Keep the stability run on the dummy renderer to avoid GPU timing assumptions.
	if not _capture:
		scene.set_power(100.0)
		scene._place_charge(RangeScene.INITIAL_POINT)
		var normal_targets := scene.targets.size()
		for cycle in range(20):
			scene.run_trial()
			var active := scene.effect
			await active.tree_exited
			await process_frame
			_expect(not is_instance_valid(active) and scene.effect == null, "complete trial cleans up its effect (%d)" % cycle)
			scene.reset_trial()
			_expect(scene.targets.size() == normal_targets and not scene.wall.fractured, "complete trial restores targets (%d)" % cycle)
		scene.layout.items.clear()
		for index in range(100):
			var location := Vector3((index % 10 - 5) * 7.5 + (640.0 if index >= 50 else 0.0), 0.0, (floori(index / 10.0) - 5) * 4.0)
			_expect(scene.layout.append(Target.Kind.CONTAINER, location), "stress placement %d" % index)
		scene.reset_trial()
		scene.set_power(Catalog.MAX_KG)
		scene.run_trial()
		var remote := scene.targets[50]
		var remote_arrival := Propagation.travel_time(remote.global_position.distance_to(scene.point))
		await _wait_age(scene.effect, remote_arrival - 0.045)
		_expect(not remote.fractured, "remote container stays intact before the wave")
		await _wait_age(scene.effect, remote_arrival + 0.75)
		if _expect(_has_physics_debris(remote), "remote container creates colliding rigid bodies"):
			var first_piece: RigidBody3D = remote.sections.filter(func(body: RigidBody3D) -> bool: return not body.freeze)[0]
			var release_position := first_piece.global_position
			for i in range(14):
				await physics_frame
			_expect(release_position.distance_to(first_piece.global_position) > 0.12, "remote debris moves in the physics solver")
		await _wait_age(scene.effect, scene.profile.front_duration + 0.05)
		var bodies := 0
		for target in scene.targets:
			for section in target.sections:
				bodies += int(not section.freeze)
		_expect(scene.targets.size() == 100 and scene.targets.all(
			func(target: Target) -> bool: return _has_physics_debris(target)),
			"all 100 targets produce real physics debris, including 50 beyond 600 m")
		_expect(bodies >= 100 and bodies < 100*remote.sections.size(), "the outer assemblies retain anchored parts")
		scene.reset_trial()
		_expect(scene.targets.size() == 100 and scene.targets.all(
			func(target: Target) -> bool: return not target.fractured), "reset restores the saved test arrangement")

func _exercise_land_and_delivery(scene: RangeScene) -> void:
	scene.layout.defaults()
	scene.reset_trial()
	var camera := scene.camera
	var original := camera.global_transform
	scene._place_charge(Vector3.ZERO)
	var crater_point := scene.point
	scene.set_power(Catalog.MAX_KG)
	scene.layout.append(Target.Kind.DRUM, Vector3(343.0, 0.0, 0.0))
	scene.reset_trial()
	camera.position = crater_point + Vector3(343.0, 0.0, 0.0)
	scene.run_trial()
	var event := scene.effect
	var cue := event.get_node("AcousticEvent") as AcousticEvent
	await _wait_age(event, 0.48)
	_expect(absf(event.front_radius - event.age * Propagation.SPEED) <= 0.025, "wave radius grows by 343 world units per second")
	_expect(not scene.targets.back().fractured and cue.arrival_time < 0.0, "wave and sound have not reached one-second checkpoint")
	await _wait_age(event, 1.06)
	_expect(absf(cue.arrival_time - 1.0) <= 0.019, "audio arrives at 343 m in one second")
	_expect(scene.targets.back().last_hit_radius >= 0.0 and absf(scene.targets.back().last_hit_radius - 343.0) <= 5.75,
		"wave reaches the 343 m ground target in the same simulation tick")
	_expect(scene.ground.height_at(0.0, 0.0) < -20.0, "maximum crater has geometric depth")
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 50, 0), Vector3(0, -80, 0), 1)
	var hit := scene.ground.get_world_3d().direct_space_state.intersect_ray(ray)
	_expect(not hit.is_empty() and hit["position"].y < -20.0, "physics ray hits crater floor")
	var file := "res://verification/crater_%s.json" % ("render" if _capture else "headless")
	scene.layout.craters.assign(scene.ground.craters)
	var loaded := Layout.new()
	var saved := scene.layout.save_to(file)
	_expect(saved == OK and loaded.load_from(file) == OK and loaded.craters.size() == 1
		and loaded.craters[0].is_equal_approx(scene.ground.craters[0]), "save and reload preserves terrain deformation")
	scene.layout.craters.clear()
	scene.reset_trial()
	_expect(absf(scene.ground.height_at(0.0, 0.0)) < 0.001, "reset without a saved crater restores terrain")
	scene.layout.defaults()
	scene.reset_trial()
	scene.set_power(100.0)
	camera.global_transform = original
	scene._place_charge(RangeScene.INITIAL_POINT)

	scene.set_blast_mode(Device.BlastMode.THERMOBARIC)
	scene.run_trial()
	var ground_burst := scene.effect
	_expect(is_instance_valid(ground_burst) and ground_burst.global_position.distance_to(scene.point) < 0.05,
		"the thermobaric effect starts on the ground")
	if is_instance_valid(ground_burst):
		_expect(ground_burst.ignition_delay > 0.0 and ground_burst.visual_radius() == 0.0,
			"ground preparation precedes the front")
	scene.reset_trial()
	scene.set_blast_mode(Device.BlastMode.SURFACE)
	scene._director.select(Director.Mode.FREE)
	camera.global_transform = original
	scene.set_device(Device.Kind.SPECIAL)
	scene.run_trial()
	var special := scene.effect
	if not _expect(is_instance_valid(special), "special device starts a ground burst"):
		return
	scene._set_speed(0)
	var frozen := special.age
	for i in range(5):
		await process_frame
	_expect(paused and is_equal_approx(special.age, frozen), "pause stops the shock and burst simulation")
	for index in range(1, RangeScene.HUD.SPEEDS.size()):
		scene._set_speed(index)
		var initial_age := special.age
		await process_frame
		await process_frame
		_expect(not paused and is_equal_approx(Engine.time_scale, RangeScene.HUD.SPEEDS[index])
			and special.age > initial_age, "time scale %d advances simulation" % index)
	scene._set_speed(5)
	_press(KEY_V)
	_expect(camera.walking and scene._director.mode == Director.Mode.WALK, "V enters walking mode")
	_press(KEY_B)
	_expect(scene._walker.third_person, "B switches the walking view to third person")
	_press(KEY_V)
	_expect(not camera.walking and scene._director.mode == Director.Mode.FREE, "V returns to free camera")
	await special.tree_exited
	await process_frame
	_expect(scene._trial_done and scene._hud._result.visible, "result is available in telemetry on completion")
	if _capture:
		await _save("11-crater-result")
	scene.replay_trial()
	_expect(scene._replaying and is_instance_valid(scene.effect) and scene._kind == Device.Kind.SPECIAL
		and scene.effect.seed == scene._record.seed, "replay reconstructs the recorded device, terrain and seed")
	scene.reset_trial()
	_expect(not scene._replaying, "reset returns from the replay to the editable layout")

func _exercise_effect_scale(scene: RangeScene) -> void:
	var single := Catalog.make_profile(1000.0)
	var hundred := Catalog.make_profile(100000.0)
	_expect(hundred.fire_radius / single.fire_radius > 3.5, "one and one hundred tonnes have distinct fire radius")
	_expect(hundred.front_radius / single.front_radius > 3.5 and hundred.dust_height / single.dust_height > 4.0,
		"front range and airborne dust scale independently")
	_expect(hundred.smoke_height > single.smoke_height * 3.0 and hundred.heat_duration > single.heat_duration * 2.0,
		"smoke rise and cooling differ across the two presets")
	var previous := Catalog.make_profile(Catalog.MIN_KG)
	for kg in Catalog.QUICK_VALUES.slice(1):
		var profile := Catalog.make_profile(kg)
		_expect(profile.fire_radius > previous.fire_radius and profile.front_radius > previous.front_radius
			and profile.dust_height > previous.dust_height and profile.lifetime > previous.lifetime,
			"power progression stays strictly increasing at %s" % profile.display_yield)
		previous = profile

	_expect(scene.landscape.get_instance_shader_parameter("distant_ground") == true,
		"the curved backdrop uses crater and heave cutouts")
	_expect(scene.landscape.height_at(99000.0,99000.0) < -1000.0, "distant ground bends below the center")

	scene.layout.defaults()
	scene.reset_trial()
	scene.set_device(Device.Kind.GROUND)
	scene._director.select(Director.Mode.FREE)
	scene._place_charge(RangeScene.INITIAL_POINT)
	var camera := scene.camera
	var original := camera.global_transform
	camera.global_position = Vector3(67.0, 36.0, 108.0)
	camera.look_at(Vector3(0.0, 11.5, 0.0))
	for value in [1000.0, 100000.0]:
		scene.set_power(value)
		scene.run_trial()
		var burst := scene.effect
		await _wait_age(burst, 0.54)
		_expect(burst._volume.visible and burst._volume.mesh is BoxMesh and burst._volume.scale.x > burst.profile.fire_radius,
			"world-space combustion volume covers the evolving effect")
		var wake: Vector4 = burst._volume.material_override.get_shader_parameter("wake_shape")
		_expect(wake.x > 0.0 and wake.w > 0.0,
			"the shared volume contains a ground dust ring at %s" % burst.profile.display_yield)
		if _capture:
			await _save("14-scale-1t" if value == 1000.0 else "15-scale-100t")
		if value == 100000.0:
			await _wait_age(burst, 1.06)
			_expect(scene.targets.size() == 12 and scene.targets.all(func(target: Target) -> bool: return _has_physics_debris(target)),
				"all ten catalog types produce physics debris")
			var kinds := {}
			for target in scene.targets:
				kinds[target.kind] = target.sections.size()
			_expect(kinds.size() == 10 and kinds[Target.Kind.BRICK] > kinds[Target.Kind.BARRIER]
				and kinds[Target.Kind.CRATES] != kinds[Target.Kind.PIPES], "destruction geometry is authored per material")
			if _capture:
				await _wait_age(burst, 2.4)
				await _save("16-industrial-smoke")
				camera.global_position = scene.point + Vector3(34, 25, 41)
				camera.look_at(scene.point)
				await _wait_age(burst, 8.5)
				await _save("17-open-crater")
		scene.reset_trial()
	camera.global_transform = original

func _exercise_menu() -> void:
	var menu := MENU.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	if _capture:
		await _save("09-main-menu")
	var actions: VBoxContainer = menu._menu_actions
	_expect(actions.get_child_count() == 3, "main menu offers range, settings and quit")
	var range_button := actions.get_child(0) as Button
	_click(range_button.get_global_rect().get_center())
	for i in range(7):
		if current_scene is RangeScene:
			break
		await process_frame
	_expect(current_scene is RangeScene and current_scene.targets.size() == 100,
		"main menu launches the original distant layout")
	if current_scene is RangeScene:
		var scene := current_scene as RangeScene
		_expect(scene.layout.append(Target.Kind.DRUM, Vector3(47, 0, 47)),
			"the full distant layout has room for custom placements")
		current_scene.queue_free()
		await process_frame

func _has_physics_debris(target: Target) -> bool:
	return not target.sections.is_empty() and target.sections.any(func(piece: RigidBody3D) -> bool:
		return not piece.freeze and piece.collision_layer != 0 and piece.collision_mask & 1 != 0)

func _wait_age(effect: Node3D, threshold: float) -> void:
	while is_instance_valid(effect) and effect.age < threshold:
		await process_frame

func _click(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.position = position
		button.global_position = position
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		Input.parse_input_event(button)
	Input.flush_buffered_events()

func _press(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func _save(stem: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://verification/%s.png" % stem
	var error := root.get_texture().get_image().save_png(path)
	_expect(error == OK, "capture written to " + path)

func _expect(condition: bool, description: String) -> bool:
	if not condition:
		_failed = true
		push_error("FAIL: " + description)
	return condition
