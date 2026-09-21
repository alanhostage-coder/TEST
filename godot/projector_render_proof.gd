extends SceneTree

const OUTPUT_PATH := "/tmp/pua-projector-proof.png"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world = load("res://world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for _frame in range(6):
		await process_frame
	var bay = world.get_node("BayProjection")
	if bay.layout_surface_count != 5:
		bay._toggle_layout()
	bay._set_mode(1)
	for _frame in range(8):
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("PUA_PROJECTOR_RENDER_FAIL empty viewport")
		quit(2)
		return
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("PUA_PROJECTOR_RENDER_FAIL save error %d" % error)
		quit(2)
		return
	print("PUA_PROJECTOR_RENDER_OK size=%dx%d surfaces=%d cameras=%d" % [
		image.get_width(),
		image.get_height(),
		bay.layout_surface_count,
		bay.get_active_view_cameras().size()
	])
	quit(0)
