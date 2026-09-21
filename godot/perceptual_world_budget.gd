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
@export var visibility_hysteresis_m := 14.0
@export var cone_hysteresis := 0.10
var previous_position := Vector3.ZERO
var predicted_focus := Vector3.ZERO

var viewer: Camera3D
var accum := 0.0
var candidates: Array[Node3D] = []
var candidate_cursor := 0
var cycle_near_used := 0
var cycle_mid_used := 0
var cycle_landmarks_used := 0
var candidate_sort_origin := Vector3.ZERO
@export var candidates_per_tick := 96
@export var candidate_refresh_s := 1.0
var candidate_refresh_accum := 0.0

func _ready() -> void:
	viewer = get_viewport().get_camera_3d()
	_refresh_candidates()
	set_process(true)

func _refresh_candidates() -> void:
	candidates.clear()
	for n in get_tree().get_nodes_in_group("pua_world_detail"):
		if n is Node3D and is_instance_valid(n):
			candidates.append(n)
	if is_instance_valid(viewer):
		candidate_sort_origin = viewer.global_position
	candidates.sort_custom(_candidate_before)
	candidate_cursor = 0
	_reset_cycle_budget()

func _candidate_before(a: Node3D, b: Node3D) -> bool:
	var a_landmark := a.is_in_group("pua_landmark")
	var b_landmark := b.is_in_group("pua_landmark")
	if a_landmark != b_landmark:
		return a_landmark
	var a_distance := a.global_position.distance_squared_to(candidate_sort_origin)
	var b_distance := b.global_position.distance_squared_to(candidate_sort_origin)
	if not is_equal_approx(a_distance, b_distance):
		return a_distance < b_distance
	return str(a.get_path()) < str(b.get_path())

func _reset_cycle_budget() -> void:
	cycle_near_used = 0
	cycle_mid_used = 0
	cycle_landmarks_used = 0

func _active_view_cameras() -> Array[Camera3D]:
	var active: Array[Camera3D] = []
	var bay = get_node_or_null("../BayProjection")
	if bay != null and bay.has_method("get_active_view_cameras"):
		var supplied_cameras = bay.get_active_view_cameras()
		for camera in supplied_cameras:
			if camera is Camera3D and is_instance_valid(camera):
				active.append(camera)
	if active.is_empty() and is_instance_valid(viewer):
		active.append(viewer)
	return active

func _process(delta: float) -> void:
	candidate_refresh_accum += delta
	if candidate_refresh_accum >= candidate_refresh_s:
		candidate_refresh_accum = 0.0
		_refresh_candidates()
	accum += delta
	if accum < update_interval_s:
		return
	accum = 0.0
	if viewer == null or not is_instance_valid(viewer):
		viewer = get_viewport().get_camera_3d()
		if viewer == null:
			return
	var active_cameras := _active_view_cameras()
	if active_cameras.is_empty():
		return
	var tracking_camera := active_cameras[0]
	var velocity := Vector3.ZERO
	if previous_position != Vector3.ZERO:
		velocity = (tracking_camera.global_position - previous_position) / max(update_interval_s, 0.001)
	previous_position = tracking_camera.global_position
	predicted_focus = tracking_camera.global_position - tracking_camera.global_transform.basis.z * min_forward_bias_m + velocity * speed_lookahead_s
	var total := candidates.size()
	if total == 0:
		return
	var work_count: int = min(candidates_per_tick, total)
	for i in range(work_count):
		var n := candidates[(candidate_cursor + i) % total]
		if not is_instance_valid(n):
			continue
		var distance := n.global_position.distance_to(tracking_camera.global_position)
		var predicted_distance := INF
		var ahead := -1.0
		for camera in active_cameras:
			var offset := n.global_position - camera.global_position
			var camera_distance := offset.length()
			var camera_forward := -camera.global_transform.basis.z
			var camera_ahead := offset.normalized().dot(camera_forward) if camera_distance > 0.01 else 1.0
			ahead = maxf(ahead, camera_ahead)
			var focus := camera.global_position + camera_forward * min_forward_bias_m + velocity * speed_lookahead_s
			predicted_distance = minf(predicted_distance, n.global_position.distance_to(focus))
		var keep := false
		var was_visible := n.visible
		var distance_slack := visibility_hysteresis_m if was_visible else 0.0
		var cone_slack := cone_hysteresis if was_visible else 0.0
		var landmark := n.is_in_group("pua_landmark")
		if landmark and distance <= landmark_radius_m + distance_slack and cycle_landmarks_used < max_landmarks:
			keep = true
			cycle_landmarks_used += 1
		elif distance <= rear_keep_radius_m + distance_slack:
			keep = true
		elif ahead > -0.15 - cone_slack and distance <= near_radius_m + distance_slack and cycle_near_used < max_near_details:
			keep = true
			cycle_near_used += 1
		elif ahead > 0.15 - cone_slack and min(distance, predicted_distance) <= mid_radius_m + distance_slack and cycle_mid_used < max_mid_details:
			keep = true
			cycle_mid_used += 1
		n.visible = keep
	candidate_cursor = (candidate_cursor + work_count) % total
	if candidate_cursor == 0:
		_reset_cycle_budget()
