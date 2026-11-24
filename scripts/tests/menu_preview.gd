extends SceneTree
const Settings := preload("res://scripts/core/game_settings.gd")
const Preview := preload("res://scripts/ui/menu_preview.gd")
const Menu := preload("res://scenes/menus/main_menu.tscn")

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var menu = Menu.instantiate()
	root.add_child(menu)
	current_scene = menu
	var values := Settings.DEFAULTS.duplicate()
	values["effect_quality"] = 0
	Settings.apply(values,root)
	root.size = Vector2i(1280,720)
	var preview: Preview
	for child in menu.find_children("*","SubViewportContainer",true,false):
		if child is Preview:
			preview = child
	assert(preview != null and preview._burst != null)
	preview.apply_graphics(values)
	await rendered(8)
	assert(menu._menu_actions.get_child_count() == 3)
	assert(is_equal_approx(preview._burst.age,Preview.SNAPSHOT_TIME) and preview._burst._audio == null)
	assert(preview._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	var native := preview._viewport.get_texture().get_image()
	menu._menu_actions.get_child(1).pressed.emit()
	await rendered(3)
	assert(menu._overlay.visible)
	assert(menu._overlay._center.get_global_rect().end.x < preview.get_global_rect().position.x)
	values["glow"] = false
	values["cloud_shadows"] = false
	values["effect_quality"] = 1
	values["render_scale"] = 0
	preview.apply_graphics(values)
	await rendered(8)
	assert(not preview._stage.get_node("Environment").environment.glow_enabled)
	assert(is_equal_approx(preview._viewport.scaling_3d_scale,0.67))
	assert(preview._burst._volume._atlas.size.x == 7680)
	var no_shadows := preview._viewport.get_texture().get_image()
	assert(native.get_width() > 350 and native.get_height() > 290)
	var sum := 0.0
	for x in range(24,native.get_width()-20,8):
		for y in range(25,native.get_height()-20,8):
			sum += absf(native.get_pixel(x,y).get_luminance()-no_shadows.get_pixel(x,y).get_luminance())
	assert(sum > 0.5)
	values["language"] = "en"
	Settings.apply(values,root)
	assert(TranslationServer.translate("Графика") == "Graphics" and TranslationServer.translate("Наземный") == "Surface")
	menu._overlay.close()
	menu._menu_actions.get_child(0).pressed.emit()
	await scene_changed
	var scene = current_scene
	Settings.apply(values,root)
	root.size = Vector2i(1280,720)
	await rendered(4)
	assert(scene._hud._title.text.contains("Mushroom cloud") and scene._hud._title.text.contains("Mt"))
	assert(scene._hud._altitude.text.begins_with("Altitude "))
	assert(scene._hud.power_control._class.text.begins_with("Yield"))
	assert(scene.targets.size() == 100)
	scene.set_power(50000)
	scene.run_trial()
	assert(scene.effect != null)
	scene.reset_trial()
	print("PASS preview redraw, graphics leaves time frozen, three actions, languages and English gameplay")
	var scene_after_test := current_scene
	scene_after_test.queue_free()
	await process_frame
	quit()

func rendered(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
