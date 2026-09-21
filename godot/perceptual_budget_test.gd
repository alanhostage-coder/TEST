extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.current = true
	scene.add_child(camera)
	for i in range(30):
		var detail := Node3D.new()
		# Insert farthest first so the test catches OSM/source-order selection.
		detail.position = Vector3(float(i % 5), 0.0, -50.0 + float(i))
		detail.add_to_group("pua_world_detail")
		scene.add_child(detail)
	var budget = load("res://perceptual_world_budget.gd").new()
	budget.near_radius_m = 80.0
	budget.mid_radius_m = 0.0
	budget.rear_keep_radius_m = 0.0
	budget.max_near_details = 5
	budget.max_mid_details = 0
	budget.max_landmarks = 0
	budget.candidates_per_tick = 10
	budget.candidate_refresh_s = 10.0
	scene.add_child(budget)
	await process_frame
	budget._process(0.2)
	budget._process(0.2)
	budget._process(0.2)
	var visible_count := 0
	var furthest_visible := 0.0
	for detail in get_nodes_in_group("pua_world_detail"):
		if detail.visible:
			visible_count += 1
			furthest_visible = maxf(furthest_visible, detail.global_position.length())
	assert(visible_count == 5, "near-detail cap must cover the full candidate cycle")
	assert(furthest_visible < 28.0, "nearest perceptual details must win independent of source order")
	print("PUA_PERCEPTUAL_BUDGET_OK visible=%d candidates=%d furthest=%.1f" % [visible_count, budget.candidates.size(), furthest_visible])
	quit(0)
