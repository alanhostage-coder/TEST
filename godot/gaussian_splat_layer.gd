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
	add_child(splat_node)
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
	if str(meta.get("alignment_status", "")) not in ["estimated", "surveyed"]:
		return false
	var lat = float(meta.get("origin_lat", 0.0))
	var lon = float(meta.get("origin_lon", 0.0))
	if abs(lat - EXPECTED_LAT) > 0.01 or abs(lon - EXPECTED_LON) > 0.02:
		return false
	return true
