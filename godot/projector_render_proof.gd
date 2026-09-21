extends SceneTree

const OUTPUT_PATH := "/tmp/pua-projector-proof.png"
const CONTINUITY_PATH := "/tmp/pua-projector-continuity.png"
const MANIFEST_PATH := "/tmp/pua-projector-proof.json"
const MAP_READY_FRAME_BUDGET := 240
const EXPECTED_PACKAGED_PATCH_TIMESTAMP := "2026-09-20T22:47:11Z"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world = load("res://world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var map_ready := false
	for _frame in range(MAP_READY_FRAME_BUDGET):
		await process_frame
		if _verified_map_ready(world):
			map_ready = true
			break
	if not map_ready:
		push_error("PUA_PROJECTOR_RENDER_FAIL verified EH15 map did not become ready")
		quit(2)
		return

	# A proof image must be comparable between runs. Live weather remains the game
	# default, but the evidence capture uses the explicit CLEAR override and snaps
	# only this test scene to its target instead of photographing a transition.
	var world_state = world.get_node("WorldState")
	world_state.set_weather_mode("CLEAR")
	world.atmosphere_wetness = world.atmosphere_target_wetness
	world.atmosphere_cloud = world.atmosphere_target_cloud
	world.atmosphere_visibility = world.atmosphere_target_visibility
	world.atmosphere_aqi = world.atmosphere_target_aqi
	world._apply_weather_visuals()
	var bay = world.get_node("BayProjection")
	# Projector release must remain geographically useful without internet.
	# Exercise the bundled source-dated map itself, not merely a live/cache refresh.
	var map_stream = world.get_node("MapStream")
	if not map_stream._load_packaged_patch():
		push_error("PUA_PROJECTOR_RENDER_FAIL packaged map patch unavailable")
		quit(2)
		return
	var packaged = map_stream.data
	if str(packaged.get("source_timestamp_utc", "")) != EXPECTED_PACKAGED_PATCH_TIMESTAMP \
	or packaged.get("roads", []).is_empty() \
	or packaged.get("buildings", []).is_empty():
		push_error("PUA_PROJECTOR_RENDER_FAIL packaged map provenance/geometry invalid")
		quit(2)
		return
	var legacy_yaw := [deg_to_rad(-8.0), deg_to_rad(3.0), deg_to_rad(11.0), deg_to_rad(-4.0), deg_to_rad(6.0)]
	bay._normalise_panorama_yaw(legacy_yaw, 1)
	for yaw in legacy_yaw:
		if abs(float(yaw) - deg_to_rad(3.0)) > 0.00001:
			push_error("PUA_PROJECTOR_RENDER_FAIL legacy yaw migration broke panorama continuity")
			quit(2)
			return
	var projector_1024_aspect_error := _projector_profile_aspect_error(bay, Vector2(1024, 576))
	if projector_1024_aspect_error > 0.01:
		push_error("PUA_PROJECTOR_RENDER_FAIL low-res surface aspect drift %.5f" % projector_1024_aspect_error)
		quit(2)
		return
	if bay.layout_surface_count != 5:
		bay._toggle_layout()
	# Exercise the exact XPS projector allocation even though this proof runs in the
	# CI editor rather than an exported feature-tagged executable.
	bay.projector_max_mode = true
	bay.pc_max_mode = true
	bay.xps_9530_mode = true
	bay.layout_surface_count = 5
	bay._rescale_surfaces()
	var xps_uniform_pixels := 0
	var xps_actual_pixels := 0
	var xps_scales: Array = []
	var xps_panel_sizes: Array = []
	for panel_index in range(5):
		var rect: Rect2 = bay.FIVE_RECTS[panel_index]
		var destination_size := Vector2(
			root.size.x * rect.size.x,
			root.size.y * rect.size.y
		)
		var uniform_size: Vector2i = bay.viewport_size_for_surface(destination_size, bay.XPS_9530_RENDER_SCALE)
		var actual_size: Vector2i = bay.viewports[panel_index].size
		xps_uniform_pixels += uniform_size.x * uniform_size.y
		xps_actual_pixels += actual_size.x * actual_size.y
		xps_scales.append(bay.render_scale_for_surface(panel_index))
		xps_panel_sizes.append([actual_size.x, actual_size.y])
	var xps_pixel_budget_ratio: float = float(xps_actual_pixels) / maxf(1.0, float(xps_uniform_pixels))
	if xps_pixel_budget_ratio < 0.95 or xps_pixel_budget_ratio > 1.02:
		push_error("PUA_PROJECTOR_RENDER_FAIL XPS perceptual pixel budget drift %.4f" % xps_pixel_budget_ratio)
		quit(2)
		return
	if float(xps_scales[1]) <= bay.XPS_9530_RENDER_SCALE or float(xps_scales[3]) >= bay.XPS_9530_RENDER_SCALE:
		push_error("PUA_PROJECTOR_RENDER_FAIL XPS centre/peripheral allocation missing")
		quit(2)
		return
	bay._set_mode(1)
	for _frame in range(8):
		await process_frame
	var panel_render_sizes: Array = []
	var max_panel_aspect_error := 0.0
	for panel_index in range(5):
		var panel_size: Vector2i = bay.viewports[panel_index].size
		var quad: PackedVector2Array = bay.base_quads[panel_index]
		var quad_width = quad[0].distance_to(quad[1])
		var quad_height = quad[0].distance_to(quad[3])
		var quad_aspect = quad_width / max(1.0, quad_height)
		var render_aspect = float(panel_size.x) / max(1.0, float(panel_size.y))
		var aspect_error = abs(render_aspect / quad_aspect - 1.0)
		max_panel_aspect_error = max(max_panel_aspect_error, aspect_error)
		panel_render_sizes.append([panel_size.x, panel_size.y])
		if aspect_error > 0.03:
			push_error("PUA_PROJECTOR_RENDER_FAIL panel %d aspect drift render=%.4f quad=%.4f" % [panel_index, render_aspect, quad_aspect])
			quit(2)
			return
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
	var composite := root.get_texture().get_image()
	if composite == null or composite.is_empty():
		push_error("PUA_PROJECTOR_RENDER_FAIL empty composite")
		quit(2)
		return
	var error := composite.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("PUA_PROJECTOR_RENDER_FAIL save error %d" % error)
		quit(2)
		return

	# Keep the normal gameplay frame above, then remove interface chrome for a
	# second image whose sole job is exposing cross-surface geometry and seams.
	world.get_node("HUD").visible = false
	for control in [bay.button, bay.cal_button, bay.layout_button, bay.drive_button, bay.centre_button, bay.title]:
		control.visible = false
	await process_frame
	await process_frame
	var continuity := root.get_texture().get_image()
	if continuity == null or continuity.is_empty() or continuity.save_png(CONTINUITY_PATH) != OK:
		push_error("PUA_PROJECTOR_RENDER_FAIL continuity frame save error")
		quit(2)
		return

	var car = world.get_node("Car")
	var manifest := {
		"proof_profile": "deterministic-clear-five-surface-v1",
		"weather": str(world_state.state.get("source", "unknown")),
		"map_source": str(car.get_meta("map_data_source", "offline")),
		"roads": int(car.get_meta("map_road_count", 0)),
		"buildings": int(car.get_meta("map_building_count", 0)),
		"exact_buildings": int(car.get_meta("map_exact_building_count", 0)),
		"opening_policy": str(car.get_meta("map_opening_policy", "")),
		"opening_anchor": str(car.get_meta("map_opening_verified_anchor", "")),
		"surface_count": bay.layout_surface_count,
		"camera_count": bay.cameras.size(),
		"composite_size": [composite.get_width(), composite.get_height()],
		"packaged_patch_timestamp": str(packaged.get("source_timestamp_utc", "")),
		"packaged_roads": packaged.get("roads", []).size(),
		"packaged_buildings": packaged.get("buildings", []).size(),
		"panel_render_sizes": panel_render_sizes,
		"max_panel_aspect_error": max_panel_aspect_error,
		"projector_1024_aspect_error": projector_1024_aspect_error,
		"legacy_yaw_normalised": true,
		"xps_profile_exercised": true,
		"xps_panel_render_scales": xps_scales,
		"xps_panel_render_sizes": xps_panel_sizes,
		"xps_pixel_budget_ratio": xps_pixel_budget_ratio
	}
	var manifest_file = FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if manifest_file == null:
		push_error("PUA_PROJECTOR_RENDER_FAIL manifest open error")
		quit(2)
		return
	manifest_file.store_string(JSON.stringify(manifest, "  "))
	manifest_file.close()

	print("PUA_PROJECTOR_RENDER_OK size=%dx%d surfaces=%d cameras=%d map_source=%s roads=%d buildings=%d anchor=%s" % [
		composite.get_width(),
		composite.get_height(),
		bay.layout_surface_count,
		bay.cameras.size(),
		manifest.map_source,
		manifest.roads,
		manifest.buildings,
		manifest.opening_anchor
	])
	quit(0)


func _projector_profile_aspect_error(bay: Node, screen_size: Vector2) -> float:
	var worst := 0.0
	for rect in bay.FIVE_RECTS:
		var surface_size := Vector2(screen_size.x * rect.size.x, screen_size.y * rect.size.y)
		var viewport_size: Vector2i = bay.viewport_size_for_surface(surface_size, bay.PROJECTOR_MAX_RENDER_SCALE)
		var destination_aspect: float = surface_size.x / max(1.0, surface_size.y)
		var viewport_aspect: float = float(viewport_size.x) / max(1.0, float(viewport_size.y))
		worst = max(worst, abs(destination_aspect - viewport_aspect))
	return worst


func _verified_map_ready(world: Node) -> bool:
	var car = world.get_node_or_null("Car")
	if car == null:
		return false
	var roads = int(car.get_meta("map_road_count", 0))
	var buildings = int(car.get_meta("map_building_count", 0))
	var exact_buildings = int(car.get_meta("map_exact_building_count", 0))
	return roads > 0 \
		and buildings > 0 \
		and exact_buildings == buildings \
		and str(car.get_meta("map_data_source", "offline")) != "offline" \
		and str(car.get_meta("map_opening_policy", "")) == "verified-first-impression-v1" \
		and str(car.get_meta("map_opening_verified_anchor", "")) != ""
