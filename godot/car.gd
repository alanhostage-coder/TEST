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
var impact_kick := 0.0
var distance_driven := 0.0
var on_road := true
var persist_timer := 0.0
var camera_lag := Vector3.ZERO
var previous_position := Vector3.ZERO

func _ready():
	_load_state()
	previous_position = global_position

func _exit_tree():
	_save_state()

func _input(event):
	if event is InputEventScreenTouch and event.position.x < get_viewport().get_visible_rect().size.x * 0.58:
		touching = event.pressed
		touch_origin = event.position
		touch_now = event.position
	elif event is InputEventScreenDrag and touching:
		touch_now = event.position

func _physics_process(delta):
	var input_throttle = Input.get_action_strength("throttle") - Input.get_action_strength("brake")
	var input_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	if touching:
		var touch_delta = (touch_now - touch_origin) / 120.0
		input_steer = clamp(touch_delta.x, -1.0, 1.0)
		input_throttle = clamp(-touch_delta.y, -1.0, 1.0)

	on_road = _is_near_road()
	steer_smoothed = move_toward(steer_smoothed, input_steer, delta * 4.2)
	var speed_limit = max_speed if on_road else max_speed * 0.50
	var reversing_limit = speed_limit * 0.38
	var target_speed = 0.0
	var rate = drag * (1.0 if on_road else 1.8)
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
	var grip = 10.5 if on_road else 4.2
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
	var local_x = abs(fposmod(global_position.x + 45.0, 90.0) - 45.0)
	var local_z = abs(fposmod(global_position.z + 45.0, 90.0) - 45.0)
	return local_x < 8.5 or local_z < 8.5

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
	var lag_target = Vector3(clamp(-local_motion.x * 0.055, -1.35, 1.35), 0.0, clamp(local_motion.z * 0.035, -0.7, 0.7))
	camera_lag = camera_lag.lerp(lag_target, 1.0 - exp(-delta * 2.4))
	var shake = sin(Time.get_ticks_msec() * 0.04) * impact_kick * 0.16
	var lateral = steer_smoothed * 1.15 + camera_lag.x
	rig.position.x = lerp(rig.position.x, lateral, 1.0 - exp(-delta * 3.2))
	rig.position.y = lerp(rig.position.y, 2.72 + speed_ratio * 0.48 + shake, 1.0 - exp(-delta * 2.3))
	rig.position.z = lerp(rig.position.z, 7.85 + speed_ratio * 2.55 + camera_lag.z, 1.0 - exp(-delta * 1.9))
	rig.rotation.x = lerp_angle(rig.rotation.x, deg_to_rad(-7.5 + speed_ratio * 1.5), 1.0 - exp(-delta * 2.6))
	rig.rotation.y = lerp_angle(rig.rotation.y, -steer_smoothed * 0.11 - camera_lag.x * 0.025, 1.0 - exp(-delta * 2.6))
	rig.rotation.z = lerp_angle(rig.rotation.z, -steer_smoothed * speed_ratio * 0.018, 1.0 - exp(-delta * 4.0))
	$CameraRig/Camera3D.fov = lerp($CameraRig/Camera3D.fov, 64.0 + speed_ratio * 9.0, 1.0 - exp(-delta * 1.8))

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