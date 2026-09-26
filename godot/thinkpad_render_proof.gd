extends SceneTree

const OUTPUT_DIR := "/tmp/pua-thinkpad-proof"
const MAP_READY_FRAMES := 360

func _initialize() -> void:
	OS.set_environment("PUA_FORCE_THINKPAD_TEST", "1")
	call_deferred("run")

func _finish(code: int) -> void:
	OS.set_environment("PUA_FORCE_THINKPAD_TEST", "")
	quit(code)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	root.size = Vector2i(960, 540)
	var world = load("res://world.tscn").instantiate()
	world.set_meta("force_thinkpad_proof", true)
	root.add_child(world)
	current_scene = world
	var car = world.get_node("Car")
	for _i in range(MAP_READY_FRAMES):
		await process_frame
		if int(car.get_meta("map_road_count", 0)) > 0 and int(car.get_meta("map_building_count", 0)) > 0:
			break
	if int(car.get_meta("map_road_count", 0)) <= 0:
		push_error("PUA_THINKPAD_RENDER_FAIL map not ready")
		_finish(2)
		return
	var stream = world.get_node("MapStream")
	if not stream.terrain_available():
		push_error("PUA_THINKPAD_RENDER_FAIL terrain unavailable")
		_finish(2)
		return
	if not world.thinkpad_mode or not world.source_terrain_mode:
		push_error("PUA_THINKPAD_RENDER_FAIL ThinkPad terrain mode inactive")
		_finish(2)
		return

	var world_state = world.get_node("WorldState")
	world_state.set_weather_mode("CLEAR")
	world.atmosphere_wetness = world.atmosphere_target_wetness
	world.atmosphere_cloud = world.atmosphere_target_cloud
	world.atmosphere_visibility = world.atmosphere_target_visibility
	world.atmosphere_aqi = world.atmosphere_target_aqi
	world._apply_weather_visuals()
	world.get_node("BayProjection")._set_mode(0)
	var hud = world.get_node("HUD")
	hud.visible = true

	for _settle in range(12):
		await physics_frame
		await process_frame
	if absf(car.global_position.y) > 120.0:
		push_error("PUA_THINKPAD_RENDER_FAIL opening car Y runaway %.2f" % car.global_position.y)
		_finish(2)
		return
	_capture("opening")

	var targets := [
		{"slug":"pitville-street", "point":Vector2(90.624,-147.343), "road_point":Vector2(22.157,12.011), "road_a":Vector2(22.157,12.011), "road_b":Vector2(57.111,-67.939), "focus":false},
		{"slug":"hugh-dewar-fountain", "point":Vector2(56.157,65.189), "road_point":Vector2(48.031,83.938), "road_a":Vector2(39.497,80.239), "road_b":Vector2(98.907,105.988), "focus":true},
		{"slug":"bellfield-community-hub", "point":Vector2(-91.668,-76.972), "road_point":Vector2(-61.955,-64.140), "road_a":Vector2(-77.872,-27.285), "road_b":Vector2(-35.483,-125.435), "focus":true},
		{"slug":"st-marks-church", "point":Vector2(-110.398,90.453), "road_point":Vector2(-90.023,99.054), "road_a":Vector2(-65.244,40.354), "road_b":Vector2(-101.108,125.313), "focus":true}
	]
	for target in targets:
		var point: Vector2 = target["point"]
		var road_a: Vector2 = target["road_a"]
		var road_b: Vector2 = target["road_b"]
		var road_direction := (road_b - road_a).normalized()
		var road_point: Vector2 = target["road_point"]
		var target_direction := (point - road_point).normalized()
		if road_direction.dot(target_direction) < 0.0:
			road_direction = -road_direction
		car.global_position = Vector3(road_point.x, world._terrain_height(road_point) + 0.58, road_point.y)
		car.rotation.y = atan2(-road_direction.x, -road_direction.y)
		car.speed = 0.0
		car.velocity = Vector3.ZERO
		car.steer_smoothed = 0.0
		car.steering_velocity = 0.0
		car.lateral_load = 0.0
		car.camera_yaw = 0.0
		car.camera_pitch = 0.0
		car.camera_idle = 0.0
		car.camera_lag = Vector3.ZERO
		car.previous_position = car.global_position
		if bool(target.get("focus", false)):
			var focus_direction := (point - road_point).normalized()
			if focus_direction.length() > 0.5:
				var focus_heading := atan2(-focus_direction.x, -focus_direction.y)
				car.camera_yaw = clampf(wrapf(focus_heading - car.rotation.y, -PI, PI), -1.05, 1.05)
				car.look_touching = true
		for _frame in range(14):
			await physics_frame
			await process_frame
		_capture(str(target["slug"]))
		car.look_touching = false

	print("PUA_THINKPAD_RENDER_OK captures=5 opening_y=%.2f roads=%d buildings=%d road_cells=%d" % [
		car.global_position.y,
		int(car.get_meta("map_road_count", 0)),
		int(car.get_meta("map_building_count", 0)),
		int(car.get_meta("drive_surface_cell_count", 0))
	])
	_finish(0)

func _capture(slug: String) -> void:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png("%s/%s.png" % [OUTPUT_DIR, slug]) != OK:
		push_error("PUA_THINKPAD_RENDER_FAIL save " + slug)
