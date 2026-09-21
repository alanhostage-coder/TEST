extends Node3D

# PUA perceptual renderer: spend geometry where the driver can perceive it.
@export var near_radius_m := 65.0
@export var mid_radius_m := 180.0
@export var rear_keep_radius_m := 30.0
@export var update_interval_s := 0.12
@export var max_near_details := 48
@export var max_mid_details := 140
@export var turn_lookahead_s := 1.4
@export var speed_lookahead_s := 2.2
@export var min_forward_bias_m := 18.0
@export var landmark_radius_m := 450.0
@export var max_landmarks := 12
var previous_position := Vector3.ZERO
var predicted_focus := Vector3.ZERO

var viewer: Camera3D
var accum := 0.0
var candidates: Array[Node3D] = []
var candidate_cursor := 0
@export var candidates_per_tick := 96

func _ready() -> void:
	viewer = get_viewport().get_camera_3d()
	for n in get_tree().get_nodes_in_group("pua_world_detail"):
		if n is Node3D:
			candidates.append(n)
	set_process(true)

func _process(delta: float) -> void:
	accum += delta
	if accum < update_interval_s:
		return
	accum = 0.0
	if viewer == null or not is_instance_valid(viewer):
		viewer = get_viewport().get_camera_3d()
		if viewer == null:
			return
	var forward := -viewer.global_transform.basis.z
	var velocity := Vector3.ZERO
	if previous_position != Vector3.ZERO:
		velocity = (viewer.global_position - previous_position) / max(update_interval_s, 0.001)
	previous_position = viewer.global_position
	var speed := velocity.length()
	predicted_focus = viewer.global_position + forward * min_forward_bias_m + velocity * speed_lookahead_s
	var near_used := 0
	var mid_used := 0
	var landmarks_used := 0
	var total := candidates.size()
	if total == 0:
		return
	var work_count := min(candidates_per_tick, total)
	for i in range(work_count):
		var n := candidates[(candidate_cursor + i) % total]
		if not is_instance_valid(n):
			continue
		var offset := n.global_position - viewer.global_position
		var distance := offset.length()
		var predicted_distance := n.global_position.distance_to(predicted_focus)
		var ahead := offset.normalized().dot(forward) if distance > 0.01 else 1.0
		var keep := false
		var landmark := n.is_in_group("pua_landmark")
		if landmark and distance <= landmark_radius_m and landmarks_used < max_landmarks:
			keep = true
			landmarks_used += 1
		elif distance <= rear_keep_radius_m:
			keep = true
		elif ahead > -0.15 and distance <= near_radius_m and near_used < max_near_details:
			keep = true
			near_used += 1
		elif ahead > 0.15 and min(distance, predicted_distance) <= mid_radius_m and mid_used < max_mid_details:
			keep = true
			mid_used += 1
		n.visible = keep
	candidate_cursor = (candidate_cursor + work_count) % total
