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
	for panel_index in range(5):
		var panel_image = bay.viewports[panel_index].get_texture().get_image()
		if panel_image == null or panel_image.is_empty():
			push_error("PUA_PROJECTOR_RENDER_FAIL empty panel %d" % panel_index)
			quit(2)
			return
		var panel_error = panel_image.save_png("/tmp/pua-projector-panel-%d.png" % panel_index)
		if panel_error != OK:
			push_error("PUA_PROJECTOR_RENDER_FAIL panel %d save error %d" % [panel_index, panel_error])
			quit(2)
			return
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
