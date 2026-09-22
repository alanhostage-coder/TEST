extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var world = load("res://world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await process_frame
	var bay = world.get_node("BayProjection")
	assert(bay.surfaces.size() == 5)
	bay._set_mode(1)
	await process_frame
	assert(bay.black_mask.visible)
	# Projector controls should retire from the driver's view after a short idle,
	# then return immediately when the operator moves the mouse.
	bay._update_driver_chrome(bay.DRIVER_CHROME_HOLD_SECONDS + bay.DRIVER_CHROME_FADE_SECONDS)
	assert(not bay.button.visible)
	assert(not bay.title.visible)
	bay._wake_driver_chrome()
	assert(bay.button.visible)
	assert(bay.title.visible)
	assert(is_equal_approx(bay.driver_chrome_alpha, 1.0))
	bay._set_mode(2)
	assert(bay.button.visible)
	assert(bay.save_button.visible)
	assert(bay.restore_button.visible)
	bay._set_mode(1)
	for camera in bay.cameras:
		assert(camera.global_position.is_finite())
	var calibration_base := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)
	])
	var calibration_keystone := PackedVector2Array([
		Vector2(12, 8), Vector2(94, 2), Vector2(100, 96), Vector2(3, 90)
	])
	var calibration_foldover := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 100), Vector2(100, 0), Vector2(0, 100)
	])
	var calibration_sliver := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 5), Vector2(0, 5)
	])
	assert(bay._is_safe_calibration_quad(calibration_keystone, calibration_base))
	assert(not bay._is_safe_calibration_quad(calibration_foldover, calibration_base))
	assert(not bay._is_safe_calibration_quad(calibration_sliver, calibration_base))
	# A mistaken RESET must be recoverable after a physical shutter alignment.
	# RESET saves defaults, and that save must first preserve the prior file.
	bay.layout_surface_count = 5
	var calibrated_corner := Vector2(0.03, 0.04)
	bay.cal_offsets_five[0][0] = calibrated_corner
	bay._save_calibration()
	bay._reset_calibration()
	assert(bay.cal_offsets_five[0][0] == Vector2.ZERO)
	bay._restore_calibration_backup()
	assert(bay.layout_surface_count == 5)
	assert(bay.cal_offsets_five[0][0].is_equal_approx(calibrated_corner))
	bay._reset_offsets(false)
	# The physical XPS test needs real frame-pacing evidence rather than a visual
	# impression. Exercise the rolling average, percentile and hitch counter with
	# deterministic samples so the F8 panel cannot report decorative figures.
	var hud = world.get_node("HUD")
	assert(hud.z_index > bay.steering_ring.z_index)
	assert(hud.z_index < bay.button.z_index)
	var viewport_size: Vector2 = hud.get_viewport_rect().size
	var focus_rect: Rect2 = hud._driver_focus_rect(viewport_size)
	var forward_quad: PackedVector2Array = bay.surfaces[1].polygon
	var expected_focus_x: float = (forward_quad[0].x + forward_quad[1].x + forward_quad[2].x + forward_quad[3].x) * 0.25
	assert(absf(focus_rect.get_center().x - expected_focus_x) < 0.01)
	assert(absf(focus_rect.get_center().x - viewport_size.x * 0.5) > viewport_size.x * 0.05)
	assert(is_equal_approx(hud._credit_hold_seconds(), hud.PROJECTOR_CREDIT_HOLD_SECONDS))
	hud.credit_clock = hud.PROJECTOR_CREDIT_HOLD_SECONDS + hud.PROJECTOR_CREDIT_FADE_SECONDS
	hud._update_parkview_credit(0.0)
	assert(not hud.parkview_credit.visible)
	# The persistent keyboard legend is useful on entry but visually joins the
	# five physical surfaces. It must retire once learned and wake on input.
	hud._update_projector_hint(hud.PROJECTOR_HINT_HOLD_SECONDS + hud.PROJECTOR_HINT_FADE_SECONDS)
	assert(is_zero_approx(hud.projector_hint_alpha))
	var drive_event := InputEventKey.new()
	drive_event.keycode = KEY_W
	drive_event.pressed = true
	hud._unhandled_input(drive_event)
	assert(is_zero_approx(hud.projector_hint_alpha))
	var help_event := InputEventKey.new()
	help_event.keycode = KEY_F1
	help_event.pressed = true
	hud._unhandled_input(help_event)
	assert(is_equal_approx(hud.projector_hint_alpha, 1.0))
	bay._set_mode(2)
	hud._process(0.0)
	assert(not hud.map_credit.visible)
	assert(not hud.human_credit.visible)
	assert(not hud.parkview_credit.visible)
	bay._set_mode(1)
	hud._process(0.0)
	assert(hud.map_credit.visible)
	assert(hud.human_credit.visible)
	hud._reset_frame_stats()
	for _i in range(90):
		hud._record_frame_time_ms(16.0)
	for _i in range(10):
		hud._record_frame_time_ms(40.0)
	hud._refresh_frame_stats()
	assert(is_equal_approx(hud.average_frame_ms, 18.4))
	assert(is_equal_approx(hud.p95_frame_ms, 40.0))
	assert(is_equal_approx(hud.worst_frame_ms, 40.0))
	assert(hud.frame_hitch_count == 10)
	hud._toggle_performance_overlay()
	assert(hud.performance_visible)
	hud._toggle_performance_overlay()
	assert(not hud.performance_visible)
	hud._reset_frame_stats()
	var osm_overlay = world.get_node("OSMGroundTiles")
	osm_overlay._build_live_map_overlay()
	osm_overlay._bind_map_stream()
	await process_frame
	assert(osm_overlay._packaged_overlay_road_count > 0)
	assert(osm_overlay._packaged_overlay_road_count == osm_overlay._map_stream.data.get("roads", []).size())
	assert(osm_overlay._packaged_overlay_texture != null)
	assert(osm_overlay._overlay_map.texture == osm_overlay._packaged_overlay_texture)
	var car = world.get_node("Car")
	var saved_car_position = car.global_position
	car.global_position = Vector3.ZERO
	osm_overlay._update_location_text(true)
	osm_overlay._process(0.3)
	assert(osm_overlay._overlay_marker.visible)
	assert(int(car.get_meta("osm_overlay_fallback_roads", 0)) == osm_overlay._packaged_overlay_road_count)
	assert("PITTVILLE STREET" in osm_overlay._overlay_street.text)
	assert("2026-09-20" in osm_overlay._overlay_coords.text)
	car.global_position = saved_car_position
	bay._set_mode(2)
	osm_overlay._process(0.3)
	assert(not osm_overlay._overlay_root.visible)
	assert(not car.is_physics_processing())
	bay._set_mode(0)
	osm_overlay._process(0.3)
	assert(osm_overlay._overlay_root.visible)
	assert(car.is_physics_processing())
	var weather = world.get_node("WorldState")
	weather.set_weather_mode("RAIN")
	assert(weather.state.rain == 4.0)
	weather.set_weather_mode("FOG")
	assert(weather.state.visibility == 220.0)
	weather.set_weather_mode("LIVE")
	assert(weather.state.source == weather.live_state.source)
	print("PUA_PROJECTION_WEATHER_OK")
	world.queue_free()
	await process_frame
	quit()
