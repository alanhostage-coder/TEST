extends Node3D

# Manages multiple geographically registered visual chunks without changing OSM truth.
@export var max_loaded_chunks := 3
@export var load_radius_m := 220.0
@export var unload_radius_m := 270.0
@export var update_interval_s := 0.15
@export var preload_radius_m := 320.0
@export var max_preload_chunks := 5
@export var projector_max_loaded_chunks := 2
@export var thinkpad_max_loaded_chunks := 1
@export var thinkpad_load_radius_m := 140.0
var update_accum := 0.0

var viewer: Node3D = null
var chunks: Array[Node3D] = []
var last_visible_count := -1
var peak_visible_count := 0

func _ready() -> void:
	viewer = get_viewport().get_camera_3d()
	for child in get_children():
		if child is Node3D:
			chunks.append(child)
	set_process(true)

func _process(delta: float) -> void:
	update_accum += delta
	if update_accum < update_interval_s:
		return
	update_accum = 0.0
	if viewer == null or not is_instance_valid(viewer):
		viewer = get_viewport().get_camera_3d()
		if viewer == null:
			return
	var effective_max := max_loaded_chunks
	if OS.has_feature("projector_max"):
		effective_max = min(max_loaded_chunks, projector_max_loaded_chunks)
	if OS.has_feature("thinkpad_low"):
		effective_max = min(effective_max, thinkpad_max_loaded_chunks)
	var effective_load_radius := load_radius_m
	if OS.has_feature("thinkpad_low"):
		effective_load_radius = min(load_radius_m, thinkpad_load_radius_m)
	var ranked: Array = []
	for chunk in chunks:
		var d := viewer.global_position.distance_to(chunk.global_position)
		ranked.append({"node": chunk, "distance": d})
	ranked.sort_custom(func(a, b): return a["distance"] < b["distance"])
	var visible_count := 0
	var preload_count := 0
	for item in ranked:
		var chunk: Node3D = item["node"]
		var distance: float = item["distance"]
		if distance <= preload_radius_m and preload_count < max_preload_chunks:
			preload_count += 1
		var should_show := distance <= effective_load_radius and visible_count < effective_max
		if chunk.visible and distance <= unload_radius_m and visible_count < effective_max:
			should_show = true
		chunk.visible = should_show
		if should_show:
			visible_count += 1
	peak_visible_count = max(peak_visible_count, visible_count)
	if visible_count != last_visible_count:
		last_visible_count = visible_count
		print("PUA_SPLAT_STREAM: active_chunks=", visible_count, " total_chunks=", chunks.size(), " peak=", peak_visible_count)
