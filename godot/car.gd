extends CharacterBody3D

@export var acceleration := 19.0
@export var reverse_acceleration := 11.0
@export var braking := 30.0
@export var drag := 5.5
@export var max_speed := 34.0
@export var steer_rate := 1.75

var speed := 0.0
var steer_smoothed := 0.0
var touch_origin := Vector2.ZERO
var touch_now := Vector2.ZERO
var touching := false
var look_touching := false
var look_last := Vector2.ZERO
var camera_yaw := 0.0
var camera_pitch := 0.0
var camera_idle := 0.0
var impact_kick := 0.0
var distance_driven := 0.0
var on_road := true
var persist_timer := 0.0
var camera_lag := Vector3.ZERO
var camera_look_ahead := 0.0
var previous_position := Vector3.ZERO

func _ready():
	_load_state()
	previous_position = global_position

func _exit_tree():
	_save_state()

func _input(event):
	var screen_size = get_viewport().get_visible_rect().size
	var screen_width = screen_size.x
	if event is InputEventScreenTouch and event.position.x < 145.0 and event.position.y < 100.0:
		return
	if event is InputEventScreenDrag and event.position.x < 145.0 and event.position.y < 100.0:
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
	if touching:
		var touch_delta = (touch_now - touch_origin) / 120.0
		input_steer = clamp(touch_delta.x, -1.0, 1.0)
		input_throttle = clamp(-touch_delta.y, -1.0, 1.0)

	on_road = _is_near_road()
	steer_smoothed = move_toward(steer_smoothed, input_steer, delta * 4.2)
	var speed_limit = max_speed if on_road else max_speed * 0.72
	var reversing_limit = speed_limit * 0.38
	var target_speed = 0.0
	var rate = drag * (1.0 if on_road else 1.38)
	if input_throttle > 0.04:
		if speed < -0.7: target_speed = 0.0; rate = braking
		else: target_speed = speed_limit; rate = acceleration
	elif input_throttle < -0.04:
		if speed > 0.7: target_speed = 0.0; rate = braking
		else: target_speed = -reversing_limit; rate = reverse_acceleration
	speed = move_toward(speed, target_speed, delta * rate)
	var speed_ratio = clamp(abs(speed) / max_speed, 0.0, 1.0)
	var steering_at_speed = lerp(1.0, 0.56, speed_ratio)
	var steering_authority = clamp(abs(speed) / 6.0, 0.22, 1.0)
	var travel_sign = sign(speed) if abs(speed) > 0.1 else 1.0
	rotate_y(-steer_smoothed * steer_rate * steering_at_speed * steering_authority * delta * travel_sign)
	var desired_velocity = -global_transform.basis.z * speed
	var wetness = clamp(float(get_meta("world_wetness", 0.0)), 0.0, 1.0)
	var grip = (lerp(10.5, 7.2, wetness)) if on_road else lerp(5.4, 4.1, wetness)
	velocity = velocity.lerp(desired_velocity, 1.0 - exp(-delta * grip))
	var before = global_position
	move_and_slide()
	distance_driven += before.distance_to(global_position)
	if is_on_wall():
		impact_kick = min(1.0, impact_kick + abs(speed) / 22.0)
		speed *= 0.32
		velocity *= 0.38
	impact_kick = move_toward(impact_kick, 0.0, delta * 2.8)
	_update_visuals(delta, speed_ratio)
	_update_camera(delta, speed_ratio)
	previous_position = global_position
	persist_timer += delta
	if persist_timer >= 5.0:
		persist_timer = 0.0
		_save_state()

func _is_near_road() -> bool:
	var segments = get_meta("map_road_segments", [])
	if segments is Array and not segments.is_empty():
		var p = Vector2(global_position.x, global_position.z)
		for segment in segments:
			if not segment is Array or segment.size() < 3: continue
			var a = Vector2(float(segment[0][0]), float(segment[0][1]))
			var b = Vector2(float(segment[1][0]), float(segment[1][1]))
			var width = float(segment[2])
			if _point_segment_distance(p, a, b) < width * 0.5 + 2.4:
				return true
		return false
	var local_x = abs(fposmod(global_position.x + 45.0, 90.0) - 45.0)
	var local_z = abs(fposmod(global_position.z + 45.0, 90.0) - 45.0)
	return local_x < 8.5 or local_z < 8.5

func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var denom = ab.length_squared()
	if denom < 0.001: return p.distance_to(a)
	var t = clamp((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _update_visuals(delta, speed_ratio):
	var body_roll = -steer_smoothed * speed_ratio * 0.045
	$Body.rotation.z = lerp_angle($Body.rotation.z, body_roll, 1.0 - exp(-delta * 6.0))
	$Roof.rotation.z = lerp_angle($Roof.rotation.z, body_roll, 1.0 - exp(-delta * 6.0))
	var wheel_steer = steer_smoothed * 0.34
	$WheelFL.rotation.y = lerp_angle($WheelFL.rotation.y, wheel_steer, 1.0 - exp(-delta * 9.0))
	$WheelFR.rotation.y = lerp_angle($WheelFR.rotation.y, wheel_steer, 1.0 - exp(-delta * 9.0))

func _update_camera(delta, speed_ratio):
	var rig = $CameraRig
	var world_motion = (global_position - previous_position) / max(delta, 0.001)
	var local_motion = global_transform.basis.inverse() * world_motion
	var lag_target = Vector3(clamp(-local_motion.x * 0.060, -1.5, 1.5), 0.0, clamp(local_motion.z * 0.038, -0.8, 0.8))
	camera_lag = camera_lag.lerp(lag_target, 1.0 - exp(-delta * 2.2))
	if look_touching:
		camera_idle = 0.0
	else:
		camera_idle += delta
		if camera_idle > 0.65:
			camera_yaw = lerp(camera_yaw, 0.0, 1.0 - exp(-delta * 1.55))
			camera_pitch = lerp(camera_pitch, 0.0, 1.0 - exp(-delta * 1.8))

	# Cinematic road-reading: at speed the camera subtly opens into the bend before
	# the car gets there, while retaining manual right-side free look.
	var bend_preview = -steer_smoothed * speed_ratio * 0.24
	camera_look_ahead = lerp(camera_look_ahead, bend_preview, 1.0 - exp(-delta * 2.5))
	var shake = sin(Time.get_ticks_msec() * 0.04) * impact_kick * 0.14
	var lateral = steer_smoothed * 1.28 + camera_lag.x
	var chase_height = 2.35 + speed_ratio * 0.62 + shake
	var chase_distance = 7.7 + speed_ratio * 3.7 + camera_lag.z
	rig.position.x = lerp(rig.position.x, lateral, 1.0 - exp(-delta * 3.0))
	rig.position.y = lerp(rig.position.y, chase_height, 1.0 - exp(-delta * 2.2))
	rig.position.z = lerp(rig.position.z, chase_distance, 1.0 - exp(-delta * 1.7))
	rig.rotation.x = lerp_angle(rig.rotation.x, deg_to_rad(-4.8 + speed_ratio * 0.8) + camera_pitch, 1.0 - exp(-delta * 3.0))
	rig.rotation.y = lerp_angle(rig.rotation.y, camera_yaw + camera_look_ahead - camera_lag.x * 0.025, 1.0 - exp(-delta * 3.1))
	rig.rotation.z = lerp_angle(rig.rotation.z, -steer_smoothed * speed_ratio * 0.012, 1.0 - exp(-delta * 4.0))
	$CameraRig/Camera3D.fov = lerp($CameraRig/Camera3D.fov, 60.0 + speed_ratio * 13.0, 1.0 - exp(-delta * 1.65))

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
	if saved_position is Vector3: global_position = saved_position
	rotation.y = float(cfg.get_value("car", "rotation_y", rotation.y))
	distance_driven = float(cfg.get_value("car", "distance", 0.0))