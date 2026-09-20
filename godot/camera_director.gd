extends Node

# Original chase-camera director. It sits above the car's basic camera motion and
# adds world-aware framing without taking control away from the player.
var car: CharacterBody3D
var rig: Node3D
var camera: Camera3D
var safe_distance := 8.0
var shoulder_bias := 0.0
var vertical_memory := 0.0

func _ready():
	car = get_node_or_null("../Car")
	if car:
		rig = car.get_node_or_null("CameraRig")
		camera = car.get_node_or_null("CameraRig/Camera3D")

func _process(delta):
	if not car or not rig or not camera:
		return
	var speed_ratio = clamp(abs(float(car.speed)) / max(float(car.max_speed), 1.0), 0.0, 1.0)
	var steer = float(car.steer_smoothed)
	var desired_distance = 7.9 + speed_ratio * 4.0
	var desired_height = 2.30 + speed_ratio * 0.72

	# Shoulder framing opens the view into a bend. The effect is intentionally
	# restrained at walking speed and strongest on fast estate/coastal roads.
	var shoulder_target = -steer * (0.35 + speed_ratio * 0.72)
	shoulder_bias = lerp(shoulder_bias, shoulder_target, 1.0 - exp(-delta * 2.8))

	# Camera obstruction test: pull toward the car when a wall/building is behind
	# it, then ease back out. This is what makes narrow garages and tenement edges
	# usable instead of letting the camera live inside geometry.
	var pivot = car.global_position + Vector3.UP * (1.55 + speed_ratio * 0.20)
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

	# Preserve the car script's hand-authored yaw/free-look, but refine distance,
	# shoulder composition and pitch after it has run.
	rig.position.z = safe_distance
	rig.position.x += shoulder_bias * (1.0 - exp(-delta * 5.0))
	vertical_memory = lerp(vertical_memory, desired_height, 1.0 - exp(-delta * 2.0))
	rig.position.y = lerp(rig.position.y, vertical_memory, 1.0 - exp(-delta * 4.0))

	# A slightly narrower stationary lens gives the car and nearby architecture
	# weight; speed progressively opens peripheral vision without fisheye distortion.
	var target_fov = 58.5 + speed_ratio * 13.5
	camera.fov = lerp(camera.fov, target_fov, 1.0 - exp(-delta * 2.2))
	camera.near = 0.12
	camera.far = 900.0
