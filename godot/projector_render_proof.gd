extends SceneTree

const OUTPUT_PATH := "/tmp/pua-projector-proof.png"
const CONTINUITY_PATH := "/tmp/pua-projector-continuity.png"
const CALIBRATION_PATH := "/tmp/pua-projector-calibration.png"
const LAPTOP_MAX_HD_PATH := "/tmp/pua-xps-laptop-max-hd.png"
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
	# CI runs without export feature tags, so explicitly exercise the same offline
	# OSM panel that the XPS executable creates. Feed it the packaged snapshot we
	# just validated so live/cache timing cannot change the proof.
	var osm_overlay = world.get_node("OSMGroundTiles")
	osm_overlay._build_live_map_overlay()
	osm_overlay._build_packaged_vector_overlay(packaged)
	osm_overlay._map_stream = map_stream
	osm_overlay._center_lat = float(packaged.get("center_lat", 0.0))
	osm_overlay._center_lon = float(packaged.get("center_lon", 0.0))
	osm_overlay._last_postcode = str(packaged.get("start_postcode", "EH15 2BZ"))
	osm_overlay._update_location_text(true)
	osm_overlay._process(0.3)
	await process_frame
	var expected_overlay_x = maxf(8.0, world.get_viewport().get_visible_rect().size.x - osm_overlay._overlay_root.size.x - 14.0)
	if osm_overlay._packaged_overlay_road_count != packaged.get("roads", []).size():
		push_error("PUA_PROJECTOR_RENDER_FAIL packaged OSM road count %d/%d" % [osm_overlay._packaged_overlay_road_count, packaged.get("roads", []).size()])
		quit(2)
		return
	if osm_overlay._packaged_overlay_texture == null or osm_overlay._overlay_map.texture != osm_overlay._packaged_overlay_texture:
		push_error("PUA_PROJECTOR_RENDER_FAIL packaged OSM texture missing")
		quit(2)
		return
	if not osm_overlay._overlay_marker.visible:
		push_error("PUA_PROJECTOR_RENDER_FAIL packaged OSM car marker hidden at %s" % world.get_node("Car").global_position)
		quit(2)
		return
	if absf(osm_overlay._overlay_root.position.x - expected_overlay_x) > 1.0:
		push_error("PUA_PROJECTOR_RENDER_FAIL packaged OSM position %.1f expected %.1f viewport %.1f" % [osm_overlay._overlay_root.position.x, expected_overlay_x, world.get_viewport().get_visible_rect().size.x])
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
	var bay_destination_size: Vector2 = bay.get_viewport_rect().size
	for panel_index in range(5):
		var rect: Rect2 = bay.FIVE_RECTS[panel_index]
		var destination_size := Vector2(
			bay_destination_size.x * rect.size.x,
			bay_destination_size.y * rect.size.y
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
	# The normal proof represents the settled driving view, not the brief operator
	# controls shown on entry. Fail the release if the projector chrome cannot
	# retire cleanly after its documented idle envelope.
	bay._update_driver_chrome(bay.DRIVER_CHROME_HOLD_SECONDS + bay.DRIVER_CHROME_FADE_SECONDS)
	if bay.button.visible or bay.cal_button.visible or bay.layout_button.visible \
	or bay.drive_button.visible or bay.centre_button.visible or bay.title.visible:
		push_error("PUA_PROJECTOR_RENDER_FAIL idle driver chrome remained visible")
		quit(2)
		return
	var hud = world.get_node("HUD")
	if hud.z_index <= bay.steering_ring.z_index or hud.z_index >= bay.button.z_index:
		push_error("PUA_PROJECTOR_RENDER_FAIL HUD layer %d must sit between cockpit %d and controls %d" % [hud.z_index, bay.steering_ring.z_index, bay.button.z_index])
		quit(2)
		return
	var driver_focus_rect: Rect2 = hud._driver_focus_rect(world.get_viewport().get_visible_rect().size)
	var forward_quad: PackedVector2Array = bay.surfaces[1].polygon
	var expected_driver_focus_x: float = (forward_quad[0].x + forward_quad[1].x + forward_quad[2].x + forward_quad[3].x) * 0.25
	if absf(driver_focus_rect.get_center().x - expected_driver_focus_x) > 0.01:
		push_error("PUA_PROJECTOR_RENDER_FAIL HUD focus %.2f expected calibrated forward pane %.2f" % [driver_focus_rect.get_center().x, expected_driver_focus_x])
		quit(2)
		return
	hud.credit_clock = hud.PROJECTOR_CREDIT_HOLD_SECONDS + hud.PROJECTOR_CREDIT_FADE_SECONDS
	hud._update_parkview_credit(0.0)
	if hud.parkview_credit.visible:
		push_error("PUA_PROJECTOR_RENDER_FAIL opening credit did not retire")
		quit(2)
		return
	hud._update_projector_hint(hud.PROJECTOR_HINT_HOLD_SECONDS + hud.PROJECTOR_HINT_FADE_SECONDS)
	if not is_zero_approx(hud.projector_hint_alpha):
		push_error("PUA_PROJECTOR_RENDER_FAIL idle control hint remained visible")
		quit(2)
		return
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

	# Capture the operator-facing optical aid separately. Its warped quarter-grid,
	# centre target and named corners are what make physical shutter alignment
	# repeatable; they must never be inferred from the clean driving frame.
	bay._set_mode(2)
	bay.selected_surface = 1
	bay._update_calibration_controls()
	bay.queue_redraw()
	await process_frame
	await process_frame
	var calibration := root.get_texture().get_image()
	if calibration == null or calibration.is_empty() or calibration.save_png(CALIBRATION_PATH) != OK:
		push_error("PUA_PROJECTOR_RENDER_FAIL calibration guide frame save error")
		quit(2)
		return
	bay._set_mode(1)
	await process_frame

	# Capture the ordinary single-camera 1920x1080 laptop view from the same
	# source-backed world. This is evidence for the Max-HD laptop presentation,
	# not a crop of the five-surface composite.
	bay._set_mode(0)
	hud.visible = true
	for _frame in range(4):
		await process_frame
	var laptop_max_hd := root.get_texture().get_image()
	if laptop_max_hd == null or laptop_max_hd.is_empty() or laptop_max_hd.save_png(LAPTOP_MAX_HD_PATH) != OK:
		push_error("PUA_PROJECTOR_RENDER_FAIL laptop max-hd frame save error")
		quit(2)
		return
	bay._set_mode(1)
	bay._update_driver_chrome(bay.DRIVER_CHROME_HOLD_SECONDS + bay.DRIVER_CHROME_FADE_SECONDS)
	await process_frame

	# Keep the normal gameplay frame above, then remove interface chrome for a
	# second image whose sole job is exposing cross-surface geometry and seams.
	hud.visible = false
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
	var opening_anchor_label = world.map_root.get_node_or_null("MappedOpeningAnchor")
	if opening_anchor_label == null \
	or not opening_anchor_label is Label3D \
	or str(opening_anchor_label.text) != str(car.get_meta("map_opening_verified_anchor", "")) \
	or not bool(opening_anchor_label.get_meta("annotation_only", false)) \
	or str(opening_anchor_label.get_meta("source_field", "")) != "osm:name":
		push_error("PUA_PROJECTOR_RENDER_FAIL verified opening anchor annotation missing")
		quit(2)
		return
	var manifest := {
		"proof_profile": "deterministic-clear-five-surface-v1",
		"weather": str(world_state.state.get("source", "unknown")),
		"map_source": str(car.get_meta("map_data_source", "offline")),
		"roads": int(car.get_meta("map_road_count", 0)),
		"buildings": int(car.get_meta("map_building_count", 0)),
		"exact_buildings": int(car.get_meta("map_exact_building_count", 0)),
		"generic_tenement_facades": int(car.get_meta("generic_tenement_facade_count", 0)),
		"opening_policy": str(car.get_meta("map_opening_policy", "")),
		"opening_anchor": str(car.get_meta("map_opening_verified_anchor", "")),
		"opening_anchor_annotation": str(opening_anchor_label.text),
		"opening_anchor_annotation_source": str(opening_anchor_label.get_meta("source_collection", "")),
		"surface_count": bay.layout_surface_count,
		"camera_count": bay.cameras.size(),
		"composite_size": [composite.get_width(), composite.get_height()],
		"laptop_max_hd_size": [laptop_max_hd.get_width(), laptop_max_hd.get_height()],
		"packaged_patch_timestamp": str(packaged.get("source_timestamp_utc", "")),
		"packaged_roads": packaged.get("roads", []).size(),
		"packaged_overlay_roads": osm_overlay._packaged_overlay_road_count,
		"packaged_overlay_position": [osm_overlay._overlay_root.position.x, osm_overlay._overlay_root.position.y],
		"packaged_overlay_expected_x": expected_overlay_x,
		"packaged_overlay_marker_visible": osm_overlay._overlay_marker.visible,
		"packaged_buildings": packaged.get("buildings", []).size(),
		"panel_render_sizes": panel_render_sizes,
		"max_panel_aspect_error": max_panel_aspect_error,
		"projector_1024_aspect_error": projector_1024_aspect_error,
		"legacy_yaw_normalised": true,
		"idle_driver_chrome_hidden": true,
		"driver_focus_x": driver_focus_rect.get_center().x,
		"driver_focus_expected_x": expected_driver_focus_x,
		"opening_credit_retired": true,
		"idle_control_hint_hidden": true,
		"calibration_guide_proof": true,
		"calibration_guide_divisions": bay.CALIBRATION_GUIDE_DIVISIONS,
		"hud_z_index": hud.z_index,
		"cockpit_z_index": bay.steering_ring.z_index,
		"control_z_index": bay.button.z_index,
		"xps_profile_exercised": true,
		"xps_panel_render_scales": xps_scales,
		"xps_panel_render_sizes": xps_panel_sizes,
		"xps_pixel_budget_ratio": xps_pixel_budget_ratio,
		"xps_visual_density_policy": "mapped-detail-priority-v1"
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
