extends Node

var world: Node
var elapsed := 0.0
var start_position := Vector3.ZERO
var failed := false

func _ready():
	Engine.time_scale = 2.0
	var packed = load("res://world.tscn")
	if packed == null:
		_fail("world scene missing")
		return
	world = packed.instantiate()
	add_child(world)
	var car = world.get_node_or_null("Car")
	if car == null:
		_fail("car missing")
		return
	start_position = car.global_position
	Input.action_press("throttle")

func _process(delta):
	if failed or world == null:
		return
	elapsed += delta
	if elapsed > 3.0:
		Input.action_release("throttle")
	if elapsed >= 8.0:
		_finish()

func _finish():
	var api = world.get_node_or_null("PUAAPI")
	var car = world.get_node_or_null("Car")
	var map_stream = world.get_node_or_null("MapStream")
	var bay = world.get_node_or_null("BayProjection")
	var world_state = world.get_node_or_null("WorldState")
	if api == null:
		_fail("PUAAPI missing")
		return
	if car == null:
		_fail("car missing at finish")
		return
	if map_stream == null or str(map_stream.data.get("start_postcode", "")) != "EH15 2BZ":
		_fail("EH15 map patch missing")
		return
	if abs(float(map_stream.data.get("center_lat", 0.0)) - 55.951507) > 0.000001 or abs(float(map_stream.data.get("center_lon", 0.0)) + 3.107122) > 0.000001:
		_fail("EH15 centroid regression")
		return
	if map_stream.data.get("roads", []).size() < 100 or map_stream.data.get("buildings", []).size() < 100:
		_fail("packaged OSM patch incomplete")
		return
	var furthest_building_center := 0.0
	for building in map_stream.data.get("buildings", []):
		var center = building.get("center", []) if building is Dictionary else []
		if not center is Array or center.size() < 2:
			_fail("packaged OSM building centre missing")
			return
		furthest_building_center = maxf(furthest_building_center, Vector2(float(center[0]), float(center[1])).length())
	if furthest_building_center > world.LOW_SPEC_EXACT_FOOTPRINT_RADIUS:
		_fail("packaged OSM footprint lies outside low-spec exact radius")
		return
	# Rebuild with the combined ThinkPad/projector profile so CI executes the
	# low-spec footprint radius and capped mapped-label paths, not only their
	# desktop equivalents.
	world.low_spec_mode = true
	world.projector_max_mode = true
	world._on_map_ready(map_stream.data)
	if int(car.get_meta("map_exact_building_count", -1)) != map_stream.data.get("buildings", []).size() or int(car.get_meta("map_fallback_building_count", -1)) != 0:
		_fail("projector profile did not use exact packaged OSM footprint geometry")
		return
	var road_annotation_count = int(car.get_meta("map_road_annotation_count", 0))
	if road_annotation_count <= 0:
		_fail("mapped road-name annotations missing")
		return
	var verified_annotations := 0
	for child in world.map_root.get_children():
		if str(child.name).begins_with("MappedRoadName_"):
			if not child is Label3D or not bool(child.get_meta("annotation_only", false)) or str(child.get_meta("source_field", "")) != "osm:name":
				_fail("road name rendered as unverified physical signage")
				return
			verified_annotations += 1
	if verified_annotations != road_annotation_count:
		_fail("mapped road-name annotation count mismatch")
		return
	var secondary_visual_count := 0
	var secondary_shadow_violations := 0
	var scan_stack: Array = [world.map_root]
	while not scan_stack.is_empty():
		var scan_node = scan_stack.pop_back()
		if scan_node is GeometryInstance3D and bool(scan_node.get_meta("secondary_visual", false)):
			secondary_visual_count += 1
			if scan_node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				secondary_shadow_violations += 1
		for scan_child in scan_node.get_children():
			scan_stack.append(scan_child)
	if secondary_visual_count < 10:
		_fail("low-spec secondary visual budget was not exercised")
		return
	if secondary_shadow_violations != 0:
		_fail("low-spec secondary meshes still cast projector shadows")
		return
	if str(car.get_meta("map_opening_policy", "")) != "verified-first-impression-v1":
		_fail("verified first-impression opening policy missing")
		return
	var opening_score = float(car.get_meta("map_opening_hook_score", -INF))
	var opening_branches = int(car.get_meta("map_opening_branch_count", 0))
	var opening_approach = float(car.get_meta("map_opening_approach_m", 0.0))
	var opening_roads = car.get_meta("map_opening_named_roads", [])
	if opening_score < 45.0 or opening_branches < 3 or opening_approach < 5.5 or opening_approach > 10.1:
		_fail("first-impression opening is not strong enough")
		return
	if not opening_roads is Array or opening_roads.size() < 2:
		_fail("first-impression opening lacks verified named-road context")
		return
	var source_road_names := {}
	for source_road in map_stream.data.get("roads", []):
		if source_road is Dictionary:
			var source_name = str(source_road.get("name", "")).strip_edges()
			if source_name != "":
				source_road_names[source_name] = true
	for opening_road in opening_roads:
		if not source_road_names.has(str(opening_road)):
			_fail("first-impression road name is not source-backed")
			return
	var opening_junction_raw = car.get_meta("map_spawn_junction", [])
	var opening_heading_raw = car.get_meta("map_spawn_heading", [])
	if not opening_junction_raw is Array or opening_junction_raw.size() < 2 or not opening_heading_raw is Array or opening_heading_raw.size() < 2:
		_fail("first-impression approach geometry missing")
		return
	var opening_junction = Vector2(float(opening_junction_raw[0]), float(opening_junction_raw[1]))
	var opening_spawn = Vector2(car.global_position.x, car.global_position.z)
	var opening_heading = Vector2(float(opening_heading_raw[0]), float(opening_heading_raw[1]))
	var to_opening_junction = opening_junction - opening_spawn
	if abs(to_opening_junction.length() - opening_approach) > 0.8 or opening_heading.length() < 0.95 or opening_heading.normalized().dot(to_opening_junction.normalized()) < 0.97:
		_fail("first-impression car is not approaching its verified junction")
		return
	var opening_anchor = str(car.get_meta("map_opening_verified_anchor", ""))
	var opening_anchor_source = str(car.get_meta("map_opening_verified_anchor_source", ""))
	if opening_anchor == "" or opening_anchor_source not in ["poi", "building", "point"]:
		_fail("first-impression opening lacks a verified forward anchor")
		return
	var anchor_verified := false
	var anchor_collection = map_stream.data.get("poi_features", []) if opening_anchor_source == "poi" else (map_stream.data.get("buildings", []) if opening_anchor_source == "building" else map_stream.data.get("point_features", []))
	for source_anchor in anchor_collection:
		if source_anchor is Dictionary and str(source_anchor.get("name", "")).strip_edges() == opening_anchor:
			anchor_verified = true
			break
	if not anchor_verified:
		_fail("first-impression forward anchor is not source-backed")
		return
	var nearest_origin_road = map_stream.nearest_named_road(Vector2.ZERO)
	if str(nearest_origin_road.get("name", "")) != "Pittville Street" or float(nearest_origin_road.get("distance_m", INF)) > 30.0:
		_fail("verified Pittville Street context missing near postcode centroid")
		return
	var origin_lat_lon = map_stream.local_to_lat_lon(Vector2.ZERO)
	if abs(origin_lat_lon.x - 55.951507) > 0.000001 or abs(origin_lat_lon.y + 3.107122) > 0.000001:
		_fail("local map coordinate conversion regressed")
		return
	if map_stream.map_source_date() != "2026-09-20":
		_fail("source date missing from packaged map")
		return
	if bay == null or bay.surfaces.size() != 5 or bay.cal_offsets_five.size() != 5:
		_fail("five-surface projector calibration missing")
		return
	if bay.layout_surface_count != 5:
		bay._toggle_layout()
	bay._set_mode(2)
	var active_surfaces := 0
	for surface in bay.surfaces:
		if surface.visible:
			active_surfaces += 1
	if bay.layout_surface_count != 5 or active_surfaces != 5 or bay.base_quads.size() != 5:
		_fail("five-surface calibration layout inactive")
		return
	bay._set_mode(0)
	if world_state == null or not world_state.has_method("set_weather_mode"):
		_fail("weather override controls missing")
		return
	world_state.set_weather_mode("FOG")
	if world_state.weather_mode != "FOG" or float(world_state.state.get("visibility", 99999.0)) > 1000.0:
		_fail("fog override failed")
		return
	var wetness_before_rain = float(world.atmosphere_wetness)
	world_state.set_weather_mode("RAIN")
	if float(world_state.state.get("rain", 0.0)) < 2.0:
		_fail("rain override failed")
		return
	if float(world.atmosphere_target_wetness) < 0.95:
		_fail("rain visual target missing")
		return
	if float(world.atmosphere_wetness) >= float(world.atmosphere_target_wetness):
		_fail("weather visuals snapped instead of transitioning")
		return
	world._update_weather_visuals(0.10)
	if float(world.atmosphere_wetness) <= wetness_before_rain or float(world.atmosphere_wetness) >= float(world.atmosphere_target_wetness):
		_fail("weather visual transition envelope regressed")
		return
	world_state.set_weather_mode("LIVE")
	if not api.has_method("get_snapshot") or not api.has_method("get_directive"):
		_fail("PUAAPI contract missing")
		return
	var snapshot = api.get_snapshot()
	var directive = api.get_directive()
	if not snapshot is Dictionary or snapshot.is_empty():
		_fail("PUAAPI snapshot empty")
		return
	for key in ["world_seed", "traffic_factor", "traffic_speed_factor", "lamp_factor", "surface_wetness"]:
		if not directive.has(key):
			_fail("directive missing " + key)
			return
	var moved = start_position.distance_to(car.global_position)
	print("PUA_SOAK_OK moved=%.2f traffic=%.2f lamps=%.2f moment=%s map=%s roads=%d buildings=%d exact=%d fallback=%d furthest=%.1fm nearest=%s distance=%.1fm surfaces=%d sources=%s" % [
		moved,
		float(directive.get("traffic_factor", 0.0)),
		float(directive.get("lamp_factor", 0.0)),
		str(directive.get("moment", "none")),
		str(map_stream.data.get("start_postcode", "")),
		map_stream.data.get("roads", []).size(),
		map_stream.data.get("buildings", []).size(),
		int(car.get_meta("map_exact_building_count", -1)),
		int(car.get_meta("map_fallback_building_count", -1)),
		furthest_building_center,
		str(nearest_origin_road.get("name", "")),
		float(nearest_origin_road.get("distance_m", 0.0)),
		bay.surfaces.size(),
		JSON.stringify(snapshot.get("sources", {}))
	])
	get_tree().quit(0)

func _fail(reason: String):
	failed = true
	Input.action_release("throttle")
	push_error("PUA_SOAK_FAIL " + reason)
	get_tree().quit(2)
