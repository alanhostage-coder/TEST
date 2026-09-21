extends Node3D

# Experimental Gaussian-splat visual layer. Geographic/driving truth remains OSM.
# This node deliberately does nothing unless the GDGS addon and a labelled splat
# asset are present. It never substitutes a demo capture for EH15 geography.
const SPLAT_PATH := "res://splat_assets/eh15_2bz.sog"
const META_PATH := "res://splat_assets/eh15_2bz.json"
const EXPECTED_PATCH := "EH15 2BZ"
const EXPECTED_LAT := 55.951507
const EXPECTED_LON := -3.107122

var splat_node: Node = null
var splat_meta: Dictionary = {}
var viewer: Node3D = null
var active_distance_m := 180.0
var hysteresis_m := 20.0
var fade_band_m := 30.0

func _ready() -> void:
	if not OS.has_feature("gaussian_splat"):
		return
	if not FileAccess.file_exists(SPLAT_PATH):
		print("PUA_SPLAT_DISABLED: no EH15 splat asset; OSM geometry remains authoritative")
		return
	if not _metadata_is_safe():
		push_warning("PUA_SPLAT_DISABLED: missing or invalid EH15 provenance/alignment metadata")
		return
	if not ClassDB.class_exists("GaussianSplatNode"):
		push_warning("PUA_SPLAT_DISABLED: GDGS GaussianSplatNode unavailable")
		return
	var resource = load(SPLAT_PATH)
	if resource == null:
		push_warning("PUA_SPLAT_DISABLED: failed to import " + SPLAT_PATH)
		return
	splat_node = ClassDB.instantiate("GaussianSplatNode")
	if splat_node == null:
		push_warning("PUA_SPLAT_DISABLED: could not instantiate GaussianSplatNode")
		return
	splat_node.set("gaussian", resource)
	_apply_alignment_from_metadata(splat_node)
	add_child(splat_node)
	viewer = get_viewport().get_camera_3d()
	set_process(viewer != null)
	print("PUA_SPLAT_ACTIVE: ", SPLAT_PATH)


func _metadata_is_safe() -> bool:
	if not FileAccess.file_exists(META_PATH):
		return false
	var f = FileAccess.open(META_PATH, FileAccess.READ)
	if f == null:
		return false
	var meta = JSON.parse_string(f.get_as_text())
	if not meta is Dictionary:
		return false
	if str(meta.get("postcode", "")).to_upper() != EXPECTED_PATCH:
		return false
	if str(meta.get("licence", "")).strip_edges() == "":
		return false
	if str(meta.get("source", "")).strip_edges() == "":
		return false
	if str(meta.get("capture_date", "")).strip_edges() == "":
		return false
	if not str(meta.get("capture_quality", "")) in ["draft", "verified"]:
		return false
	if not str(meta.get("alignment_status", "")) in ["estimated", "surveyed"]:
		return false
	var lat = float(meta.get("origin_lat", 0.0))
	var lon = float(meta.get("origin_lon", 0.0))
	if abs(lat - EXPECTED_LAT) > 0.01 or abs(lon - EXPECTED_LON) > 0.02:
		return false
	splat_meta = meta
	return true

func _apply_alignment_from_metadata(node: Node) -> void:
	if not node is Node3D or splat_meta.is_empty():
		return
	var n := node as Node3D
	var offset = splat_meta.get("local_offset_m", [0.0, 0.0, 0.0])
	if offset is Array and offset.size() >= 3:
		n.position = Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
	var rotation = splat_meta.get("rotation_degrees", [0.0, 0.0, 0.0])
	if rotation is Array and rotation.size() >= 3:
		n.rotation_degrees = Vector3(float(rotation[0]), float(rotation[1]), float(rotation[2]))
	var uniform_scale := clamp(float(splat_meta.get("uniform_scale", 1.0)), 0.01, 100.0)
	n.scale = Vector3.ONE * uniform_scale
	active_distance_m = clamp(float(splat_meta.get("active_distance_m", 180.0)), 25.0, 1000.0)
	hysteresis_m = clamp(float(splat_meta.get("hysteresis_m", 20.0)), 5.0, 100.0)
	fade_band_m = clamp(float(splat_meta.get("fade_band_m", 30.0)), 5.0, 150.0)



func _process(_delta: float) -> void:
	if splat_node == null or not splat_node is Node3D:
		return
	if viewer == null or not is_instance_valid(viewer):
		viewer = get_viewport().get_camera_3d()
		if viewer == null:
			return
	var splat_3d := splat_node as Node3D
	var distance := viewer.global_position.distance_to(splat_3d.global_position)
	if splat_3d.visible and distance > active_distance_m + hysteresis_m:
		splat_3d.visible = false
	elif not splat_3d.visible and distance < active_distance_m - hysteresis_m:
		splat_3d.visible = true
