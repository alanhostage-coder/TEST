extends SceneTree

func _initialize():
	OS.set_environment("PUA_FORCE_MOBILE_TEST", "1")
	call_deferred("run")

func _fail(reason: String):
	push_error("MOBILE_TERRAIN_SCENE_FAIL " + reason)
	OS.set_environment("PUA_FORCE_MOBILE_TEST", "")
	quit(2)

func run():
	var packed = load("res://world.tscn")
	if packed == null:
		_fail("world scene missing")
		return
	var world = packed.instantiate()
	root.add_child(world)
	await process_frame
	for i in range(6):
		await physics_frame
	var stream = world.get_node_or_null("MapStream")
	var car = world.get_node_or_null("Car")
	if stream == null or car == null:
		_fail("mobile world incomplete")
		return
	if not bool(world.mobile_mode):
		_fail("forced mobile mode inactive")
		return
	if world.map_root == null:
		_fail("map root missing")
		return
	var terrain = world.map_root.get_node_or_null("MobileEHTerrain")
	if terrain == null:
		_fail("terrain mesh missing")
		return
	var ground_y := float(stream.terrain_height_at(Vector2(car.global_position.x, car.global_position.z)))
	if absf(car.global_position.y - (ground_y + 0.58)) > 0.9:
		_fail("car not following terrain car_y=%.2f ground_y=%.2f" % [car.global_position.y, ground_y])
		return
	var strip_count := 0
	var stack: Array = [world.map_root]
	while not stack.is_empty():
		var node = stack.pop_back()
		if str(node.get_meta("mobile_terrain_strip", "")) == "road":
			strip_count += 1
		for child in node.get_children():
			stack.append(child)
	if strip_count < 12:
		_fail("terrain-following road strips missing count=%d" % strip_count)
		return
	print("MOBILE_TERRAIN_SCENE_OK car_y=%.2f ground_y=%.2f road_strips=%d" % [car.global_position.y, ground_y, strip_count])
	OS.set_environment("PUA_FORCE_MOBILE_TEST", "")
	quit(0)
