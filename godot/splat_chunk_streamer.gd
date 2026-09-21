extends Node3D

# Manages multiple geographically registered visual chunks without changing OSM truth.
@export var max_loaded_chunks := 3
@export var load_radius_m := 220.0
@export var unload_radius_m := 270.0

var viewer: Node3D = null
var chunks: Array[Node3D] = []

func _ready() -> void:
	viewer = get_viewport().get_camera_3d()
	for child in get_children():
		if child is Node3D:
			chunks.append(child)
	set_process(true)

func _process(_delta: float) -> void:
	if viewer == null or not is_instance_valid(viewer):
		viewer = get_viewport().get_camera_3d()
		if viewer == null:
			return
	var ranked: Array = []
	for chunk in chunks:
		var d := viewer.global_position.distance_to(chunk.global_position)
		ranked.append({"node": chunk, "distance": d})
	ranked.sort_custom(func(a, b): return a["distance"] < b["distance"])
	var visible_count := 0
	for item in ranked:
		var chunk: Node3D = item["node"]
		var distance: float = item["distance"]
		var should_show := distance <= load_radius_m and visible_count < max_loaded_chunks
		if chunk.visible and distance <= unload_radius_m and visible_count < max_loaded_chunks:
			should_show = true
		chunk.visible = should_show
		if should_show:
			visible_count += 1
