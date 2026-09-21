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
	for camera in bay.cameras:
		assert(camera.global_position.is_finite())
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
