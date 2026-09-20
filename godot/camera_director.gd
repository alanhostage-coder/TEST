extends Node

# Original velocity-aware chase-camera director. Kept separate from vehicle physics so
# touch driving remains stable while framing can react to speed, slides and braking.
var car: CharacterBody3D
var rig: Node3D
var camera: Camera3D
var safe_distance := 8.0
var shoulder_bias := 0.0
var vertical_memory := 0.0
var speed_memory := 0.0
var lookahead_memory := 0.0
var pitch_memory := 0.0
var yaw_memory := 0.0
var lateral_memory := 0.0
var heave_memory := 0.0
var last_position := Vector3.ZERO
var velocity_memory := Vector3.ZERO

func _ready():
	call_deferred("_bind_scene")

func _bind_scene():
	var scene = get_tree().current_scene
	if not scene:
		return
	car = scene.get_node_or_null("Car")
	if car:
		rig = car.get_node_or_null("CameraRig")
		camera = car.get_node_or_null("CameraRig/Camera3D")
		last_position = car.global_position

func _process(delta):
	if not car or not is_instance_valid(car):
		_bind_scene()
		return
	if not rig or not camera:
		return
	var speed_now = abs(float(car.speed))
	var speed_ratio = clamp(speed_now / max(float(car.max_speed), 1.0), 0.0, 1.0)
	var steer = float(car.steer_smoothed)
	var acceleration = (speed_now - speed_memory) / max(delta, 0.001)
	speed_memory = lerp(speed_memory, speed_now, 1.0 - exp(-delta * 7.0))

	var measured_velocity = (car.global_position - last_position) / max(delta, 0.001)
	last_position = car.global_position
	velocity_memory = velocity_memory.lerp(measured_velocity, 1.0 - exp(-delta * 4.8))
	var local_velocity = car.global_transform.basis.inverse() * velocity_memory
	var lateral_ratio = clamp(local_velocity.x / max(float(car.max_speed), 1.0), -1.0, 1.0)
	lateral_memory = lerp(lateral_memory, lateral_ratio, 1.0 - exp(-delta * 3.2))

	var braking_push = clamp(-acceleration / 28.0, 0.0, 1.0)
	var desired_distance = 7.9 + speed_ratio * 5.2 - braking_push * 0.72
	var desired_height = 2.16 + speed_ratio * 0.94 + braking_push * 0.18
	var lookahead_target = speed_ratio * 1.72 + abs(steer) * speed_ratio * 0.42
	lookahead_memory = lerp(lookahead_memory, lookahead_target, 1.0 - exp(-delta * 2.4))

	var shoulder_target = -steer * (0.38 + speed_ratio * 1.04) - lateral_memory * 0.82
	shoulder_bias = lerp(shoulder_bias, shoulder_target, 1.0 - exp(-delta * 3.0))
	var yaw_target = -steer * speed_ratio * 0.052 - lateral_memory * 0.075
	yaw_memory = lerp(yaw_memory, yaw_target, 1.0 - exp(-delta * 2.7))

	var pivot = car.global_position + Vector3.UP * (1.48 + speed_ratio * 0.24)
	var yaw = car.rotation.y + rig.rotation.y
	var back = Vector3(sin(yaw), 0.0, cos(yaw))
	var desired_world = pivot + back * desired_distance + Vector3.UP * desired_height
	var query = PhysicsRayQueryParameters3D.create(pivot, desired_world)
	query.exclude = [car.get_rid()]
	query.collide_with_areas = false
	var hit = car.get_world_3d().direct_space_state.intersect_ray(query)
	var collision_distance = desired_distance
	if not hit.is_empty():
		var hit_position: Vector3 = hit.get("position", desired_world)
		collision_distance = clamp(pivot.distance_to(hit_position) - 0.65, 2.8, desired_distance)
	var retract_rate = 14.0 if collision_distance < safe_distance else 2.6
	safe_distance = lerp(safe_distance, collision_distance, 1.0 - exp(-delta * retract_rate))

	rig.position.z = safe_distance
	rig.position.x = lerp(rig.position.x, shoulder_bias, 1.0 - exp(-delta * 5.0))
	vertical_memory = lerp(vertical_memory, desired_height, 1.0 - exp(-delta * 2.0))
	var suspension = float(car.get("suspension_heave"))
	heave_memory = lerp(heave_memory, clamp(suspension, -0.12, 0.12), 1.0 - exp(-delta * 6.0))
	rig.position.y = lerp(rig.position.y, vertical_memory + heave_memory * 0.35, 1.0 - exp(-delta * 4.0))
	var pitch_target = deg_to_rad(-1.15 - lookahead_memory * 0.78 + braking_push * 0.95)
	pitch_memory = lerp(pitch_memory, pitch_target, 1.0 - exp(-delta * 2.6))
	camera.rotation.x = lerp(camera.rotation.x, pitch_memory, 1.0 - exp(-delta * 3.0))
	camera.rotation.y = lerp(camera.rotation.y, yaw_memory, 1.0 - exp(-delta * 3.2))
	var target_fov = 56.8 + speed_ratio * 15.9 - braking_push * 1.35 + abs(lateral_memory) * 1.4
	camera.fov = lerp(camera.fov, target_fov, 1.0 - exp(-delta * 2.2))
	camera.near = 0.12
	camera.far = 1150.0
