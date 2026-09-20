extends Node

# Original chase-camera director. Autoloaded so camera behaviour stays separate
# from vehicle physics and can keep evolving without destabilising touch driving.
var car: CharacterBody3D
var rig: Node3D
var camera: Camera3D
var safe_distance := 8.0
var shoulder_bias := 0.0
var vertical_memory := 0.0
var speed_memory := 0.0
var lookahead_memory := 0.0
var pitch_memory := 0.0

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

	# Long, low chase framing at speed makes the road ahead the subject rather than
	# pinning the vehicle to screen centre. Braking compresses the shot slightly.
	var braking_push = clamp(-acceleration / 28.0, 0.0, 1.0)
	var desired_distance = 7.7 + speed_ratio * 4.8 - braking_push * 0.65
	var desired_height = 2.22 + speed_ratio * 0.86 + braking_push * 0.16
	var lookahead_target = speed_ratio * 1.45 + abs(steer) * speed_ratio * 0.35
	lookahead_memory = lerp(lookahead_memory, lookahead_target, 1.0 - exp(-delta * 2.4))

	# Shoulder framing opens the view into a bend. Restrained at walking speed,
	# stronger on fast estate and coastal roads.
	var shoulder_target = -steer * (0.32 + speed_ratio * 0.92)
	shoulder_bias = lerp(shoulder_bias, shoulder_target, 1.0 - exp(-delta * 2.8))

	# Pull the lens toward the car before a wall, garage or tenement can swallow it.
	var pivot = car.global_position + Vector3.UP * (1.50 + speed_ratio * 0.22)
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
	var retract_rate = 13.0 if collision_distance < safe_distance else 2.4
	safe_distance = lerp(safe_distance, collision_distance, 1.0 - exp(-delta * retract_rate))

	# Preserve manual free-look while adding a tiny inertial pitch response. This
	# gives crests, hard stops and acceleration physical weight without camera shake.
	rig.position.z = safe_distance
	rig.position.x = lerp(rig.position.x, shoulder_bias, 1.0 - exp(-delta * 5.0))
	vertical_memory = lerp(vertical_memory, desired_height, 1.0 - exp(-delta * 2.0))
	rig.position.y = lerp(rig.position.y, vertical_memory, 1.0 - exp(-delta * 4.0))
	var pitch_target = deg_to_rad(-1.0 - lookahead_memory * 0.72 + braking_push * 0.9)
	pitch_memory = lerp(pitch_memory, pitch_target, 1.0 - exp(-delta * 2.6))
	camera.rotation.x = lerp(camera.rotation.x, pitch_memory, 1.0 - exp(-delta * 3.0))
	var target_fov = 57.5 + speed_ratio * 14.8 - braking_push * 1.2
	camera.fov = lerp(camera.fov, target_fov, 1.0 - exp(-delta * 2.2))
	camera.near = 0.12
	camera.far = 1050.0
