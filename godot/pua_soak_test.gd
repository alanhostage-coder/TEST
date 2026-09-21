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
	print("PUA_SOAK_OK moved=%.2f traffic=%.2f lamps=%.2f moment=%s map=%s roads=%d buildings=%d surfaces=%d sources=%s" % [
		moved,
		float(directive.get("traffic_factor", 0.0)),
		float(directive.get("lamp_factor", 0.0)),
		str(directive.get("moment", "none")),
		str(map_stream.data.get("start_postcode", "")),
		map_stream.data.get("roads", []).size(),
		map_stream.data.get("buildings", []).size(),
		bay.surfaces.size(),
		JSON.stringify(snapshot.get("sources", {}))
	])
	get_tree().quit(0)

func _fail(reason: String):
	failed = true
	Input.action_release("throttle")
	push_error("PUA_SOAK_FAIL " + reason)
	get_tree().quit(2)
