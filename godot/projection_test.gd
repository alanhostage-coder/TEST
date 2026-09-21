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
	bay._set_mode(2)
	assert(not world.get_node("Car").is_physics_processing())
	bay._set_mode(0)
	assert(world.get_node("Car").is_physics_processing())
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
