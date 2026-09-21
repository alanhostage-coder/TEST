extends Node3D

# PUA perceptual renderer: spend geometry where the driver can perceive it.
@export var near_radius_m := 65.0
@export var mid_radius_m := 180.0
@export var rear_keep_radius_m := 30.0
@export var update_interval_s := 0.12
@export var max_near_details := 48
@export var max_mid_details := 140

var viewer: Camera3D
var accum := 0.0
var candidates: Array[Node3D] = []

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
	var near_used := 0
	var mid_used := 0
	for n in candidates:
		if not is_instance_valid(n):
			continue
		var offset := n.global_position - viewer.global_position
		var distance := offset.length()
		var ahead := offset.normalized().dot(forward) if distance > 0.01 else 1.0
		var keep := false
		if distance <= rear_keep_radius_m:
			keep = true
		elif ahead > -0.15 and distance <= near_radius_m and near_used < max_near_details:
			keep = true
			near_used += 1
		elif ahead > 0.15 and distance <= mid_radius_m and mid_used < max_mid_details:
			keep = true
			mid_used += 1
		n.visible = keep
