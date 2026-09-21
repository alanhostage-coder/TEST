extends Node3D

# Experimental Gaussian-splat visual layer. Geographic/driving truth remains OSM.
# This node deliberately does nothing unless the GDGS addon and a labelled splat
# asset are present. It never substitutes a demo capture for EH15 geography.
const SPLAT_PATH := "res://splat_assets/eh15_2bz.sog"

var splat_node: Node = null

func _ready() -> void:
	if not OS.has_feature("gaussian_splat"):
		return
	if not FileAccess.file_exists(SPLAT_PATH):
		print("PUA_SPLAT_DISABLED: no EH15 splat asset; OSM geometry remains authoritative")
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
