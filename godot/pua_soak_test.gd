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
	world_state.set_weather_mode("RAIN")
	if float(world_state.state.get("rain", 0.0)) < 2.0:
		_fail("rain override failed")
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
