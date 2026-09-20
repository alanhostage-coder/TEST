extends Node

# Collision guardian for the chase camera.
#
# Car owns the actual chase framing, manual look, bend preview and FOV. Earlier
# versions also drove those values here from _process(), while Car drove them from
# _physics_process(). The two systems therefore overwrote the same transform every
# frame and produced timing-dependent camera movement. This director now has one
# job: retract the already-framed camera when mapped geometry gets between the car
# and the desired camera position, then release it smoothly when the view clears.
var car: CharacterBody3D
var rig: Node3D
var camera: Camera3D
var safe_distance := 8.0
var bound := false

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
		if rig:
			safe_distance = max(2.8, rig.position.z)
			bound = true

func _process(delta):
	if not car or not is_instance_valid(car):
		bound = false
		_bind_scene()
		return
	if not rig or not is_instance_valid(rig) or not camera or not is_instance_valid(camera):
		bound = false
		_bind_scene()
		return

	# Car has already chosen the desired chase position. Preserve it exactly unless
	# a solid object occludes the line from the upper chassis to the camera.
	var desired_distance = max(2.8, rig.position.z)
	var pivot = car.global_position + Vector3.UP * 1.48
	var desired_world = camera.global_position
	var ray = desired_world - pivot
	var ray_length = ray.length()
	if ray_length < 0.1:
		return

	var query = PhysicsRayQueryParameters3D.create(pivot, desired_world)
	query.exclude = [car.get_rid()]
	query.collide_with_areas = false
	var hit = car.get_world_3d().direct_space_state.intersect_ray(query)
	var collision_distance = desired_distance
	if not hit.is_empty():
		var hit_position: Vector3 = hit.get("position", desired_world)
		# Convert distance along the sight ray back into the rig's local chase
		# distance. The clearance keeps the near plane out of walls and buildings.
		var visible_fraction = clamp((pivot.distance_to(hit_position) - 0.55) / ray_length, 0.0, 1.0)
		collision_distance = clamp(desired_distance * visible_fraction, 2.8, desired_distance)

	# Retract quickly to prevent clipping, but release slowly so passing a lamp post
	# or building corner cannot snap the camera backwards and forwards.
	var retracting = collision_distance < safe_distance
	var response = 16.0 if retracting else 3.2
	safe_distance = lerp(safe_distance, collision_distance, 1.0 - exp(-delta * response))
	if safe_distance < desired_distance - 0.01:
		rig.position.z = safe_distance

	# These are safety bounds only. Car remains the sole owner of dynamic FOV.
	camera.near = 0.12
	camera.far = 1150.0
