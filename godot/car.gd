extends CharacterBody3D

@export var acceleration := 21.5
@export var reverse_acceleration := 11.0
@export var braking := 34.0
@export var drag := 6.2
@export var max_speed := 34.0
@export var steer_rate := 1.75

var speed := 0.0
var steer_smoothed := 0.0
var touch_origin := Vector2.ZERO
var touch_now := Vector2.ZERO
var touching := false
var look_touching := false
var look_last := Vector2.ZERO
var mouse_looking := false
var camera_yaw := 0.0
var camera_pitch := 0.0
var camera_idle := 0.0
var impact_kick := 0.0
var speed_camera_pulse := 0.0
var suspension_pitch := 0.0
var suspension_heave := 0.0
var distance_driven := 0.0
var on_road := true
var persist_timer := 0.0
var camera_lag := Vector3.ZERO
var camera_look_ahead := 0.0
var previous_position := Vector3.ZERO
var motion_drive_enabled := false
var motion_center_angle := 0.0
var motion_steer := 0.0
var motion_sensor_live := false
var assisted_target_speed := 17.5
var wheel_spin := 0.0
var steering_velocity := 0.0
var lateral_load := 0.0
var terrain_pitch := 0.0
const MOBILE_RECOVER_RECT := Rect2(18.0, 42.0, 118.0, 46.0)
const MOBILE_BUILDING_CELL := 36.0
const MOBILE_CAR_RADIUS := 1.05
const DRIVE_ROAD_CELL := 48.0
var mobile_building_cells := {}
var mobile_collision_footprint_count := 0
var drive_road_cells := {}
var drive_road_segments: Array = []


func _ready():
	_build_visual_shell()
	_load_state()
	previous_position = global_position

func _source_terrain_enabled() -> bool:
	return OS.has_feature("mobile") 		or OS.get_environment("PUA_FORCE_MOBILE_TEST") == "1" 		or (OS.has_feature("thinkpad_low") and not OS.has_feature("projector_max")) 		or OS.get_environment("PUA_FORCE_THINKPAD_TEST") == "1"

func set_drive_surface_segments(segments: Array):
	drive_road_cells.clear()
	drive_road_segments = segments.duplicate(true)
	for segment_index in range(drive_road_segments.size()):
		var segment = drive_road_segments[segment_index]
		if not segment is Array or segment.size() < 4:
			continue
		var kind := str(segment[3]).to_lower()
		if kind in ["track", "path", "footway", "cycleway"]:
			continue
		var a := Vector2(float(segment[0][0]), float(segment[0][1]))
		var b := Vector2(float(segment[1][0]), float(segment[1][1]))
		var margin := maxf(2.0, float(segment[2]) * 0.5 + 1.5)
		var min_cell := Vector2i(floori((minf(a.x, b.x) - margin) / DRIVE_ROAD_CELL), floori((minf(a.y, b.y) - margin) / DRIVE_ROAD_CELL))
		var max_cell := Vector2i(floori((maxf(a.x, b.x) + margin) / DRIVE_ROAD_CELL), floori((maxf(a.y, b.y) + margin) / DRIVE_ROAD_CELL))
		for cx in range(min_cell.x, max_cell.x + 1):
			for cz in range(min_cell.y, max_cell.y + 1):
				var key := Vector2i(cx, cz)
				if not drive_road_cells.has(key):
					drive_road_cells[key] = []
				drive_road_cells[key].append(segment_index)
	set_meta("drive_surface_segment_count", drive_road_segments.size())
	set_meta("drive_surface_cell_count", drive_road_cells.size())

func _drive_segments_near(point: Vector2) -> Array:
	if drive_road_cells.is_empty():
		return drive_road_segments if not drive_road_segments.is_empty() else get_meta("map_road_segments", [])
	var cell := Vector2i(floori(point.x / DRIVE_ROAD_CELL), floori(point.y / DRIVE_ROAD_CELL))
	var result: Array = []
	var seen := {}
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for segment_index in drive_road_cells.get(cell + Vector2i(dx, dz), []):
				if seen.has(segment_index):
					continue
				seen[segment_index] = true
				result.append(drive_road_segments[int(segment_index)])
	return result

func set_mobile_collision_geometry(buildings: Array):
	mobile_building_cells.clear()
	mobile_collision_footprint_count = 0
	for building in buildings:
		if not building is Dictionary:
			continue
		var footprint = building.get("footprint", [])
		if not footprint is Array or footprint.size() < 3:
			continue
		var poly := PackedVector2Array()
		var min_p := Vector2(INF, INF)
		var max_p := Vector2(-INF, -INF)
		for raw in footprint:
			if raw is Array and raw.size() >= 2:
				var p := Vector2(float(raw[0]), float(raw[1]))
				poly.append(p)
				min_p.x = minf(min_p.x, p.x)
				min_p.y = minf(min_p.y, p.y)
				max_p.x = maxf(max_p.x, p.x)
				max_p.y = maxf(max_p.y, p.y)
		if poly.size() < 3:
			continue
		if poly[0].distance_squared_to(poly[poly.size() - 1]) < 0.01:
			poly.resize(poly.size() - 1)
		if poly.size() < 3:
			continue
		var min_cell := Vector2i(floori((min_p.x - MOBILE_CAR_RADIUS) / MOBILE_BUILDING_CELL), floori((min_p.y - MOBILE_CAR_RADIUS) / MOBILE_BUILDING_CELL))
		var max_cell := Vector2i(floori((max_p.x + MOBILE_CAR_RADIUS) / MOBILE_BUILDING_CELL), floori((max_p.y + MOBILE_CAR_RADIUS) / MOBILE_BUILDING_CELL))
		for cx in range(min_cell.x, max_cell.x + 1):
			for cz in range(min_cell.y, max_cell.y + 1):
				var key := Vector2i(cx, cz)
				if not mobile_building_cells.has(key):
					mobile_building_cells[key] = []
				mobile_building_cells[key].append(poly)
		mobile_collision_footprint_count += 1
	set_meta("mobile_collision_footprint_count", mobile_collision_footprint_count)

func _candidate_mobile_polygons(from: Vector2, to: Vector2) -> Array:
	var min_x := minf(from.x, to.x) - MOBILE_CAR_RADIUS
	var max_x := maxf(from.x, to.x) + MOBILE_CAR_RADIUS
	var min_z := minf(from.y, to.y) - MOBILE_CAR_RADIUS
	var max_z := maxf(from.y, to.y) + MOBILE_CAR_RADIUS
	var min_cell := Vector2i(floori(min_x / MOBILE_BUILDING_CELL), floori(min_z / MOBILE_BUILDING_CELL))
	var max_cell := Vector2i(floori(max_x / MOBILE_BUILDING_CELL), floori(max_z / MOBILE_BUILDING_CELL))
	var found: Array = []
	var seen := {}
	for cx in range(min_cell.x, max_cell.x + 1):
		for cz in range(min_cell.y, max_cell.y + 1):
			var key := Vector2i(cx, cz)
			for poly in mobile_building_cells.get(key, []):
				var poly_id: int = hash(poly)
				if seen.has(poly_id):
					continue
				seen[poly_id] = true
				found.append(poly)
	return found

func _mobile_motion_hits_building(from: Vector2, to: Vector2) -> bool:
	if mobile_building_cells.is_empty():
		return false
	for poly in _candidate_mobile_polygons(from, to):
		if Geometry2D.is_point_in_polygon(to, poly):
			return true
		for i in range(poly.size()):
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % poly.size()]
			if Geometry2D.segment_intersects_segment(from, to, a, b) != null:
				return true
			if _point_segment_distance(to, a, b) <= MOBILE_CAR_RADIUS:
				return true
	return false

func _build_visual_shell():
	# Player car keeps primitive collision but gets a stronger silhouette and proper
	# glass/light separation. Extra geometry is visual only.
	var paint = StandardMaterial3D.new()
	paint.albedo_color = Color(0.075, 0.085, 0.095)
	paint.metallic = 0.58
	paint.roughness = 0.34
	var glass = StandardMaterial3D.new()
	glass.albedo_color = Color(0.035, 0.055, 0.068)
	glass.metallic = 0.20
	glass.roughness = 0.16
	var lamp = StandardMaterial3D.new()
	lamp.albedo_color = Color(0.95, 0.82, 0.58)
	lamp.roughness = 0.18
	var tail = StandardMaterial3D.new()
	tail.albedo_color = Color(0.64, 0.028, 0.018)
	tail.roughness = 0.22

	$Roof.material_override = glass
	_add_shell_box("RoofCap", Vector3(0, 0.84, 0.18), Vector3(1.48, 0.10, 1.58), paint)
	_add_shell_box("Hood", Vector3(0, 0.28, -1.52), Vector3(1.76, 0.18, 1.05), paint)
	_add_shell_box("Boot", Vector3(0, 0.30, 1.55), Vector3(1.74, 0.20, 0.78), paint)
	_add_shell_box("FrontBumper", Vector3(0, -0.02, -2.10), Vector3(1.84, 0.18, 0.16), paint)
	_add_shell_box("RearBumper", Vector3(0, -0.02, 2.10), Vector3(1.84, 0.18, 0.16), paint)
	for x in [-0.58, 0.58]:
		_add_shell_box("LampF", Vector3(x, 0.10, -2.125), Vector3(0.34, 0.16, 0.06), lamp)
		_add_shell_box("LampR", Vector3(x, 0.11, 2.125), Vector3(0.30, 0.15, 0.06), tail)

func _add_shell_box(prefix: String, pos: Vector3, size: Vector3, material: StandardMaterial3D):
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = prefix
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.material_override = material
	$Body.add_child(mesh_instance)

func _exit_tree():
	_save_state()

func _input(event):
	if OS.has_feature("mobile") and event is InputEventScreenTouch and event.pressed:
		if MOBILE_RECOVER_RECT.has_point(event.position) and not on_road and absf(speed) < 4.0:
			recover_to_road()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			recover_to_road()
		elif event.keycode == KEY_F11:
			var fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
	var screen_size = get_viewport().get_visible_rect().size
	var screen_width = screen_size.x
	if event is InputEventScreenTouch and event.position.x < 150.0 and event.position.y < 240.0:
		return
	if event is InputEventScreenDrag and event.position.x < 150.0 and event.position.y < 240.0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		mouse_looking = event.pressed
		camera_idle = 0.0
		return
	if event is InputEventMouseMotion and mouse_looking:
		camera_yaw = clamp(camera_yaw - event.relative.x * 0.0038, -1.25, 1.25)
		camera_pitch = clamp(camera_pitch - event.relative.y * 0.0030, -0.22, 0.28)
		camera_idle = 0.0
		return
	if event is InputEventScreenTouch:
		if event.position.x < screen_width * 0.58:
			touching = event.pressed
			touch_origin = event.position
			touch_now = event.position
		elif event.position.x > screen_width * 0.64:
			look_touching = event.pressed
			look_last = event.position
	elif event is InputEventScreenDrag:
		if touching and event.position.x < screen_width * 0.64:
			touch_now = event.position
		elif look_touching:
			var look_delta = event.position - look_last
			camera_yaw = clamp(camera_yaw - look_delta.x * 0.0045, -1.05, 1.05)
			camera_pitch = clamp(camera_pitch - look_delta.y * 0.0035, -0.18, 0.22)
			camera_idle = 0.0
			look_last = event.position

func _physics_process(delta):
	var input_throttle = Input.get_action_strength("throttle") - Input.get_action_strength("brake")
	var input_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var pads = Input.get_connected_joypads()
	var handbrake_pressed := Input.is_physical_key_pressed(KEY_SPACE)
	if not pads.is_empty():
		var pad = int(pads[0])
		var joy_steer = Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
		if abs(joy_steer) > 0.12:
			input_steer = joy_steer
		var trigger_r = clamp((Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) + 1.0) * 0.5, 0.0, 1.0)
		var trigger_l = clamp((Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT) + 1.0) * 0.5, 0.0, 1.0)
		if trigger_r > 0.05 or trigger_l > 0.05:
			input_throttle = trigger_r - trigger_l
		elif Input.is_joy_button_pressed(pad, JOY_BUTTON_A):
			input_throttle = 1.0
		elif Input.is_joy_button_pressed(pad, JOY_BUTTON_B):
			input_throttle = -1.0
		handbrake_pressed = handbrake_pressed or Input.is_joy_button_pressed(pad, JOY_BUTTON_X)
		var look_x = Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X)
		var look_y = Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y)
		if abs(look_x) > 0.16 or abs(look_y) > 0.16:
			camera_yaw = clamp(camera_yaw - look_x * delta * 1.8, -1.05, 1.05)
			camera_pitch = clamp(camera_pitch - look_y * delta * 1.25, -0.18, 0.22)
			camera_idle = 0.0
	if touching:
		var touch_delta = (touch_now - touch_origin) / 120.0
		input_steer = clamp(touch_delta.x, -1.0, 1.0)
		input_throttle = clamp(-touch_delta.y, -1.0, 1.0)

	on_road = _is_near_road()
	if motion_drive_enabled:
		_update_motion_steering(delta)
		if motion_sensor_live:
			input_steer = motion_steer
		var wetness_for_cruise = clamp(float(get_meta("world_wetness", 0.0)), 0.0, 1.0)
		var corner_load = abs(motion_steer)
		var cruise = assisted_target_speed * lerp(1.0, 0.60, corner_load) * lerp(1.0, 0.78, wetness_for_cruise)
		if not on_road:
			cruise *= 0.70
		# Assisted throttle/brake: keep the car moving, but slow itself for large
		# steering inputs, wet roads and off-road excursions.
		if speed < cruise - 0.8:
			input_throttle = 1.0
		elif speed > cruise + 1.5:
			input_throttle = -0.70
		else:
			input_throttle = 0.12
	# Rate-limit steering input before smoothing it. Keyboard/touch can jump from
	# full-left to full-right in one frame; letting that step reach the camera makes
	# the whole five-surface view yaw at once. The speed-sensitive slew keeps low-
	# speed manoeuvring lively while giving projector/high-speed driving a steadier
	# horizon without changing the mapped road geometry or vehicle speed model.
	var speed_for_steer = clamp(abs(speed) / max_speed, 0.0, 1.0)
	var steer_slew = lerp(7.5, 3.2, speed_for_steer)
	steering_velocity = move_toward(steering_velocity, input_steer, delta * steer_slew)
	var steer_response = 5.6 if abs(speed) < 15.0 else 4.5
	steer_smoothed = move_toward(steer_smoothed, steering_velocity, delta * steer_response)
	var speed_limit = max_speed if on_road else max_speed * 0.72
	var reversing_limit = speed_limit * 0.38
	var target_speed = 0.0
	var rate = drag * (1.0 if on_road else 1.38)
	if handbrake_pressed:
		target_speed = 0.0
		rate = braking * 1.35
	elif input_throttle > 0.04:
		if speed < -0.7: target_speed = 0.0; rate = braking
		else: target_speed = speed_limit * input_throttle; rate = acceleration * input_throttle
	elif input_throttle < -0.04:
		if speed > 0.7: target_speed = 0.0; rate = braking
		else: target_speed = reversing_limit * input_throttle; rate = reverse_acceleration * abs(input_throttle)
	speed = move_toward(speed, target_speed, delta * rate)
	var speed_ratio = clamp(abs(speed) / max_speed, 0.0, 1.0)
	var steering_at_speed = lerp(1.0, 0.48, speed_ratio)
	var steering_authority = clamp(abs(speed) / 6.0, 0.0, 1.0)
	var travel_sign = sign(speed) if abs(speed) > 0.1 else 1.0
	# Build a restrained lateral-load signal from actual steering and speed. It is
	# shared by chassis and camera below, so the visual response agrees with the
	# car's turn rather than layering unrelated shake on top.
	var lateral_target = steer_smoothed * speed_ratio * speed_ratio * travel_sign
	lateral_load = lerp(lateral_load, lateral_target, 1.0 - exp(-delta * 5.8))
	rotate_y(-steer_smoothed * steer_rate * steering_at_speed * steering_authority * delta * travel_sign)
	var desired_velocity = -global_transform.basis.z * speed
	var wetness = clamp(float(get_meta("world_wetness", 0.0)), 0.0, 1.0)
	var grip = (lerp(10.5, 7.2, wetness)) if on_road else lerp(5.4, 4.1, wetness)
	velocity = velocity.lerp(desired_velocity, 1.0 - exp(-delta * grip))
	var before = global_position
	move_and_slide()
	if _source_terrain_enabled():
		var before2 := Vector2(before.x, before.z)
		var after2 := Vector2(global_position.x, global_position.z)
		if _mobile_motion_hits_building(before2, after2):
			# Building collision is authoritative in plan view. A sloping foundation
			# can no longer become a tunnel just because its 3D mesh sits above the car.
			global_position.x = before.x
			global_position.z = before.z
			velocity.x = 0.0
			velocity.z = 0.0
			speed *= 0.12
			impact_kick = min(1.0, impact_kick + 0.35)
	_follow_mobile_terrain(delta)
	distance_driven += Vector2(before.x, before.z).distance_to(Vector2(global_position.x, global_position.z))
	if is_on_wall():
		impact_kick = min(1.0, impact_kick + abs(speed) / 22.0)
		speed *= 0.24
		velocity *= 0.30
		# Nudge away from collision surfaces to reduce sticky wall-lock on touch screens.
		if get_slide_collision_count() > 0:
			var hit_normal = get_slide_collision(0).get_normal()
			global_position += hit_normal * 0.08
	impact_kick = move_toward(impact_kick, 0.0, delta * 2.8)
	var longitudinal_g = clamp((speed - float(get_meta("previous_speed", speed))) / max(delta, 0.001) / 24.0, -1.0, 1.0)
	set_meta("previous_speed", speed)
	suspension_pitch = lerp(suspension_pitch, longitudinal_g * 0.022, 1.0 - exp(-delta * 7.0))
	suspension_heave = lerp(suspension_heave, abs(steer_smoothed) * speed_ratio * 0.018, 1.0 - exp(-delta * 5.0))
	_update_visuals(delta, speed_ratio)
	# A tiny speed-dependent chassis pulse gives fast roads texture without scripted events.
	speed_camera_pulse = lerp(speed_camera_pulse, speed_ratio * speed_ratio, 1.0 - exp(-delta * 2.0))
	_update_camera(delta, speed_ratio)
	previous_position = global_position
	persist_timer += delta
	if persist_timer >= 5.0:
		persist_timer = 0.0
		_save_state()


func _mobile_terrain_height(point: Vector2) -> float:
	if not _source_terrain_enabled():
		return 0.0
	var stream = get_node_or_null("../MapStream")
	if stream and stream.has_method("terrain_height_at"):
		return float(stream.terrain_height_at(point))
	return 0.0

func _mobile_drive_surface_height(point: Vector2) -> float:
	var terrain_y := _mobile_terrain_height(point)
	var segments = _drive_segments_near(point)
	if not segments is Array or segments.is_empty():
		return terrain_y
	var best_distance := INF
	var best_projection := point
	var best_half_width := 0.0
	for segment in segments:
		if not segment is Array or segment.size() < 4:
			continue
		var kind := str(segment[3]).to_lower()
		if kind in ["track", "path", "footway", "cycleway"]:
			continue
		var a := Vector2(float(segment[0][0]), float(segment[0][1]))
		var b := Vector2(float(segment[1][0]), float(segment[1][1]))
		var ab := b - a
		var denom := ab.length_squared()
		if denom < 0.001:
			continue
		var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
		var projection := a + ab * t
		var distance := point.distance_to(projection)
		if distance < best_distance:
			best_distance = distance
			best_projection = projection
			best_half_width = maxf(1.5, float(segment[2]) * 0.5)
	if best_distance <= best_half_width + 0.70:
		# The rendered road ribbon is sampled on its centreline. Use the same height
		# for the car so terrain cross-slope cannot put the chassis underneath it.
		return _mobile_terrain_height(best_projection)
	return terrain_y

func _follow_mobile_terrain(delta: float):
	if not _source_terrain_enabled():
		terrain_pitch = lerp(terrain_pitch, 0.0, 1.0 - exp(-delta * 4.0))
		return
	var p := Vector2(global_position.x, global_position.z)
	var ground_y := _mobile_drive_surface_height(p)
	# 2.5D mobile physics: X/Z is driving and obstacle collision; Y is the single
	# authoritative road/terrain surface. No interpolation lag that can put the car
	# underground on a steep descent.
	global_position.y = ground_y + 0.58
	var forward := -global_transform.basis.z
	var forward2 := Vector2(forward.x, forward.z).normalized()
	if forward2.length() < 0.5:
		return
	var ahead_y := _mobile_drive_surface_height(p + forward2 * 5.0)
	var behind_y := _mobile_drive_surface_height(p - forward2 * 5.0)
	var target_pitch := atan2(ahead_y - behind_y, 10.0)
	terrain_pitch = lerp(terrain_pitch, target_pitch, 1.0 - exp(-delta * 5.0))
	set_meta("terrain_ground_y", ground_y)
	set_meta("terrain_pitch_deg", rad_to_deg(terrain_pitch))
	set_meta("mobile_surface_model", "2.5d_osm_corridor_v1")

func _is_near_road() -> bool:
	var p = Vector2(global_position.x, global_position.z)
	var segments = _drive_segments_near(p)
	if segments is Array and not segments.is_empty():
		for segment in segments:
			if not segment is Array or segment.size() < 3: continue
			var a = Vector2(float(segment[0][0]), float(segment[0][1]))
			var b = Vector2(float(segment[1][0]), float(segment[1][1]))
			var width = float(segment[2])
			var road_margin := 0.65 if OS.has_feature("mobile") else 2.4
			if _point_segment_distance(p, a, b) < width * 0.5 + road_margin:
				return true
		return false
	var local_x = abs(fposmod(global_position.x + 45.0, 90.0) - 45.0)
	var local_z = abs(fposmod(global_position.z + 45.0, 90.0) - 45.0)
	return local_x < 8.5 or local_z < 8.5

func recover_to_road():
	var p = Vector2(global_position.x, global_position.z)
	var best := INF
	var target := Vector2.ZERO
	var heading := 0.0
	for segment in get_meta("map_road_segments", []):
		if not segment is Array or segment.size() < 3:
			continue
		var a = Vector2(float(segment[0][0]), float(segment[0][1]))
		var b = Vector2(float(segment[1][0]), float(segment[1][1]))
		var d = b - a
		if d.length_squared() < 0.01:
			continue
		var point = a + d * clamp((p - a).dot(d) / d.length_squared(), 0.0, 1.0)
		if point.distance_squared_to(p) < best:
			best = point.distance_squared_to(p)
			target = point
			heading = atan2(-d.x, -d.y)
	global_position = Vector3(target.x, _mobile_drive_surface_height(target) + 0.58 if _source_terrain_enabled() else 0.58, target.y)
	rotation.y = heading
	speed = 0.0
	velocity = Vector3.ZERO
	steer_smoothed = 0.0
	steering_velocity = 0.0
	lateral_load = 0.0
	previous_position = global_position
	camera_lag = Vector3.ZERO

func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var denom = ab.length_squared()
	if denom < 0.001: return p.distance_to(a)
	var t = clamp((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _update_visuals(delta, speed_ratio):
	var body_roll = -lateral_load * 0.052
	var body_pitch = terrain_pitch - suspension_pitch * 0.65
	$Body.rotation.z = lerp_angle($Body.rotation.z, body_roll, 1.0 - exp(-delta * 6.0))
	$Body.rotation.x = lerp_angle($Body.rotation.x, body_pitch, 1.0 - exp(-delta * 7.0))
	$Roof.rotation.z = lerp_angle($Roof.rotation.z, body_roll, 1.0 - exp(-delta * 6.0))
	$Roof.rotation.x = lerp_angle($Roof.rotation.x, body_pitch, 1.0 - exp(-delta * 7.0))
	var wheel_steer = steer_smoothed * 0.34
	wheel_spin = fmod(wheel_spin + speed * delta / 0.36, TAU)
	$WheelFL.rotation.y = lerp_angle($WheelFL.rotation.y, wheel_steer, 1.0 - exp(-delta * 9.0))
	$WheelFR.rotation.y = lerp_angle($WheelFR.rotation.y, wheel_steer, 1.0 - exp(-delta * 9.0))
	for wheel in [$WheelFL, $WheelFR, $WheelRL, $WheelRR]:
		wheel.rotation.x = wheel_spin
		wheel.rotation.z = PI * 0.5

func _mobile_camera_clearance(lateral: float, height: float, distance: float) -> float:
	var space_state = get_world_3d().direct_space_state
	var ray_origin := global_position + Vector3(0.0, 1.30, 0.0)
	var desired_world := to_global(Vector3(lateral, height, distance))
	var query := PhysicsRayQueryParameters3D.create(ray_origin, desired_world)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		set_meta("mobile_camera_clearance_ratio", 1.0)
		return distance
	var hit_position: Vector3 = hit.get("position", desired_world)
	var total_distance := maxf(0.01, ray_origin.distance_to(desired_world))
	var clear_distance := maxf(0.0, ray_origin.distance_to(hit_position) - 0.42)
	# Do not enforce a large minimum here. If a wall is closer than the minimum,
	# forcing the camera back through that wall defeats the collision test.
	var ratio := clampf(clear_distance / total_distance, 0.05, 1.0)
	set_meta("mobile_camera_clearance_ratio", ratio)
	return maxf(0.85, distance * ratio)

func _update_camera(delta, speed_ratio):
	var rig = $CameraRig
	var world_motion = (global_position - previous_position) / max(delta, 0.001)
	var local_motion = global_transform.basis.inverse() * world_motion
	var lag_target = Vector3(clamp(-local_motion.x * 0.060, -1.5, 1.5), 0.0, clamp(local_motion.z * 0.038, -0.8, 0.8))
	camera_lag = camera_lag.lerp(lag_target, 1.0 - exp(-delta * 2.2))
	if look_touching or mouse_looking:
		camera_idle = 0.0
	else:
		camera_idle += delta
		if camera_idle > 0.65:
			camera_yaw = lerp(camera_yaw, 0.0, 1.0 - exp(-delta * 1.55))
			camera_pitch = lerp(camera_pitch, 0.0, 1.0 - exp(-delta * 1.8))

	# Cinematic road-reading: at speed the camera subtly opens into the bend before
	# the car gets there, while retaining manual right-side free look.
	var bend_preview = -steer_smoothed * speed_ratio * 0.20
	camera_look_ahead = lerp(camera_look_ahead, bend_preview, 1.0 - exp(-delta * 2.5))
	var shake = sin(Time.get_ticks_msec() * 0.04) * impact_kick * 0.14
	# Sim-rig pass: lateral camera travel is deliberately smaller than the chassis
	# response. The eye gets cornering load from a few millimetres of roll and a
	# stable horizon instead of the old exaggerated side-to-side chase-camera slide.
	var lateral = lateral_load * 0.72 + camera_lag.x * 0.55
	var mobile_runtime := OS.has_feature("mobile") or OS.get_environment("PUA_FORCE_MOBILE_TEST") == "1"
	var road_texture = sin(distance_driven * 0.72) * speed_camera_pulse * (0.018 if mobile_runtime else 0.035)
	var chase_height = (2.45 + speed_ratio * 0.30) if mobile_runtime else (2.35 + speed_ratio * 0.62)
	chase_height += shake + road_texture - suspension_heave
	var chase_distance = (6.25 + speed_ratio * 1.55) if mobile_runtime else (7.7 + speed_ratio * 3.7)
	chase_distance += camera_lag.z
	var camera_clearance_ratio := 1.0
	if mobile_runtime:
		chase_distance = _mobile_camera_clearance(lateral, chase_height, chase_distance)
		camera_clearance_ratio = float(get_meta("mobile_camera_clearance_ratio", 1.0))
		if camera_clearance_ratio < 0.58:
			# When there is no room for a conventional chase view, rise above the
			# rear bodywork instead of clipping backwards into the building.
			chase_height += (0.58 - camera_clearance_ratio) * 4.6
	rig.position.x = lerp(rig.position.x, lateral, 1.0 - exp(-delta * 4.0 if mobile_runtime else delta * 3.0))
	rig.position.y = lerp(rig.position.y, chase_height, 1.0 - exp(-delta * 3.2 if mobile_runtime else delta * 2.2))
	rig.position.z = lerp(rig.position.z, chase_distance, 1.0 - exp(-delta * 5.5 if mobile_runtime else delta * 1.7))
	var base_pitch_deg: float = (-3.45 + speed_ratio * 0.35) if mobile_runtime else (-4.8 + speed_ratio * 0.8)
	rig.rotation.x = lerp_angle(rig.rotation.x, deg_to_rad(base_pitch_deg) + camera_pitch + suspension_pitch, 1.0 - exp(-delta * 3.0))
	rig.rotation.y = lerp_angle(rig.rotation.y, camera_yaw + camera_look_ahead - camera_lag.x * 0.025, 1.0 - exp(-delta * 3.1))
	rig.rotation.z = lerp_angle(rig.rotation.z, -lateral_load * 0.006, 1.0 - exp(-delta * 4.8))
	var target_fov: float = (68.0 + speed_ratio * 4.5) if mobile_runtime else (60.0 + speed_ratio * 13.0)
	if mobile_runtime and camera_clearance_ratio < 0.58:
		target_fov += (0.58 - camera_clearance_ratio) * 8.0
	$CameraRig/Camera3D.fov = lerp($CameraRig/Camera3D.fov, target_fov, 1.0 - exp(-delta * 1.65))

func _save_state():
	var cfg = ConfigFile.new()
	cfg.set_value("car", "position", global_position)
	cfg.set_value("car", "rotation_y", rotation.y)
	cfg.set_value("car", "distance", distance_driven)
	cfg.save("user://pua_state.cfg")

func _load_state():
	var cfg = ConfigFile.new()
	if cfg.load("user://pua_state.cfg") != OK: return
	var saved_position = cfg.get_value("car", "position", global_position)
	if saved_position is Vector3:
		global_position = saved_position
		if _source_terrain_enabled():
			# X/Z may persist, but Y belongs to the current source-backed surface.
			global_position.y = 0.58
	rotation.y = float(cfg.get_value("car", "rotation_y", rotation.y))
	distance_driven = float(cfg.get_value("car", "distance", 0.0))

func set_motion_drive_enabled(enabled: bool):
	motion_drive_enabled = enabled
	if enabled:
		calibrate_motion_wheel()
	else:
		motion_steer = 0.0

func calibrate_motion_wheel():
	var accel = Input.get_accelerometer()
	if accel.length() > 1.0:
		motion_center_angle = atan2(accel.x, -accel.y)
		motion_sensor_live = true
	motion_steer = 0.0

func _update_motion_steering(delta: float):
	var accel = Input.get_accelerometer()
	motion_sensor_live = accel.length() > 1.0
	if not motion_sensor_live:
		motion_steer = move_toward(motion_steer, 0.0, delta * 2.0)
		return
	# Gravity gives an absolute steering-wheel angle while the phone is held
	# roughly upright. Calibration removes whatever landscape orientation the
	# user naturally chooses.
	var angle = atan2(accel.x, -accel.y)
	var relative = wrapf(angle - motion_center_angle, -PI, PI)
	var target = clamp(relative / deg_to_rad(38.0), -1.0, 1.0)
	var gyro = Input.get_gyroscope()
	# A little Z-axis gyro lead removes the sluggish feeling when the wheel is
	# turned quickly, while the accelerometer prevents long-term drift.
	target = clamp(target + gyro.z * 0.055, -1.0, 1.0)
	motion_steer = lerp(motion_steer, target, 1.0 - exp(-delta * 10.0))
