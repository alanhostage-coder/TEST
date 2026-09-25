extends SceneTree

const OUTPUT_DIR := "/tmp/pua-mobile-proof"
const MAP_READY_FRAMES := 360

func _initialize() -> void:
	OS.set_environment("PUA_FORCE_MOBILE_TEST", "1")
	call_deferred("run")

func _finish(code: int) -> void:
	OS.set_environment("PUA_FORCE_MOBILE_TEST", "")
	quit(code)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var world = load("res://world.tscn").instantiate()
	world.set_meta("force_mobile_proof", true)
	root.add_child(world)
	current_scene = world

	var car = world.get_node("Car")
	for _i in range(MAP_READY_FRAMES):
		await process_frame
		if int(car.get_meta("map_road_count", 0)) > 0 and int(car.get_meta("map_building_count", 0)) > 0:
			break
	if int(car.get_meta("map_road_count", 0)) <= 0:
		push_error("PUA_MOBILE_RENDER_FAIL map not ready")
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
	hud.credit_clock = 999.0
	hud._update_parkview_credit(0.0)

	var targets := [
		# Pittville is captured from inside the street looking downhill towards the
		# coast, rather than backwards into the Abercorn/High Street junction.
		{"slug":"pitville-street", "point":Vector2(90.624,-147.343), "road_point":Vector2(22.157,12.011), "road_a":Vector2(22.157,12.011), "road_b":Vector2(57.111,-67.939), "focus":false},
		{"slug":"hugh-dewar-fountain", "point":Vector2(56.157,65.189), "road_point":Vector2(48.031,83.938), "road_a":Vector2(39.497,80.239), "road_b":Vector2(98.907,105.988), "focus":true},
		{"slug":"bellfield-community-hub", "point":Vector2(-91.668,-76.972), "road_point":Vector2(-61.955,-64.140), "road_a":Vector2(-77.872,-27.285), "road_b":Vector2(-35.483,-125.435), "focus":true},
		{"slug":"st-marks-church", "point":Vector2(-110.398,90.453), "road_point":Vector2(-90.023,99.054), "road_a":Vector2(-65.244,40.354), "road_b":Vector2(-101.108,125.313), "focus":true},
		{"slug":"twelve-triangles-high-street", "point":Vector2(-117.849,-2.438), "road_point":Vector2(-105.0,16.8), "road_a":Vector2(-98.278,19.971), "road_b":Vector2(-120.279,9.674), "focus":true}
	]
	for target in targets:
		var point: Vector2 = target["point"]
		# Move first so a streamed tile rebuild spends facade/detail budget around
		# the place we are about to photograph, not the previous stop.
		car.global_position = Vector3(point.x, world._terrain_height(point) + 0.58, point.y)
		var stream = world.get_node("MapStream")
		stream.update_stream_position(point)
		for _load in range(24):
			await process_frame
		var pose: Dictionary = {}
		if target.has("road_point") and target.has("road_a") and target.has("road_b"):
			var road_a: Vector2 = target["road_a"]
			var road_b: Vector2 = target["road_b"]
			var road_direction: Vector2 = (road_b - road_a).normalized()
			var road_point: Vector2 = target["road_point"]
			var target_direction: Vector2 = (point - road_point).normalized()
			if road_direction.dot(target_direction) < 0.0:
				road_direction = -road_direction
			pose = {
				"position": road_point,
				"heading": atan2(-road_direction.x, -road_direction.y)
			}
		else:
			pose = _road_pose_for_target(car, point)
		if pose.is_empty():
			push_error("PUA_MOBILE_RENDER_FAIL no road pose " + str(target["slug"]))
			_finish(2)
			return
		var p: Vector2 = pose["position"]
		car.global_position = Vector3(p.x, world._terrain_height(p) + 0.58, p.y)
		car.rotation.y = float(pose["heading"])
		car.speed = 0.0
		car.velocity = Vector3.ZERO
		car.steer_smoothed = 0.0
		car.steering_velocity = 0.0
		car.lateral_load = 0.0
		car.camera_yaw = 0.0
		car.look_touching = false
		if bool(target.get("focus", false)):
			var focus_direction: Vector2 = (point - p).normalized()
			if focus_direction.length() > 0.5:
				var focus_heading: float = atan2(-focus_direction.x, -focus_direction.y)
				car.camera_yaw = clampf(wrapf(focus_heading - car.rotation.y, -PI, PI), -1.45, 1.45)
				car.look_touching = true
		car.camera_pitch = 0.0
		car.camera_idle = 0.0
		car.camera_lag = Vector3.ZERO
		car.previous_position = car.global_position
		var director = root.get_node_or_null("OpenWorldDirector")
		if director:
			director.built_signature = ""
			director._try_build_from_live_roads()
		for _settle in range(18):
			await physics_frame
			await process_frame
		var image := root.get_texture().get_image()
		var path := "%s/%s.png" % [OUTPUT_DIR, str(target["slug"])]
		if image == null or image.is_empty() or image.save_png(path) != OK:
			push_error("PUA_MOBILE_RENDER_FAIL save " + str(target["slug"]))
			_finish(2)
			return
		car.look_touching = false
	print("PUA_MOBILE_RENDER_OK captures=5")
	_finish(0)

func _road_pose_for_target(car: Node, target: Vector2) -> Dictionary:
	var best_score := INF
	var best_distance := INF
	var best_projection := Vector2.ZERO
	var best_direction := Vector2.ZERO
	var best_t := 0.0
	var best_length := 0.0
	for segment in car.get_meta("map_road_segments", []):
		if not segment is Array or segment.size() < 2 or not segment[0] is Array or not segment[1] is Array:
			continue
		var a := Vector2(float(segment[0][0]), float(segment[0][1]))
		var b := Vector2(float(segment[1][0]), float(segment[1][1]))
		var d := b - a
		var length := d.length()
		if length < 2.0:
			continue
		var t := clampf((target-a).dot(d)/d.length_squared(),0.0,1.0)
		var projection := a + d*t
		var d2 := projection.distance_squared_to(target)
		var kind := str(segment[3]).to_lower() if segment.size() >= 4 else "road"
		var road_penalty := 0.0
		if kind == "service":
			road_penalty = 625.0
		elif kind in ["track", "path", "footway", "cycleway"]:
			road_penalty = 2500.0
		var score := d2 + road_penalty
		if score < best_score:
			best_score=score
			best_distance=d2
			best_projection=projection
			best_direction=d/length
			best_t=t
			best_length=length
	if best_length <= 0.0:
		return {}
	var direction := best_direction
	var road_position := best_projection
	var room_a := best_t*best_length
	var room_b := (1.0-best_t)*best_length
	if room_a >= room_b:
		road_position -= best_direction*minf(14.0,maxf(4.0,room_a*0.68))
	else:
		road_position += best_direction*minf(14.0,maxf(4.0,room_b*0.68))
		direction = -best_direction
	return {"position":road_position,"heading":atan2(-direction.x,-direction.y)}
