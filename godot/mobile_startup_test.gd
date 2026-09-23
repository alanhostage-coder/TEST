# 0.84 exact-data startup gate: boots forced mobile world against offline-cleaned EH15 tiles.
extends SceneTree

func _initialize():
	OS.set_environment("PUA_FORCE_MOBILE_TEST","1")
	call_deferred("run")

func run():
	var packed = load("res://world.tscn")
	if packed == null:
		_fail("world scene missing")
		return
	var world = packed.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var stream = world.get_node_or_null("MapStream")
	var car = world.get_node_or_null("Car")
	var bay = world.get_node_or_null("BayProjection")
	if not bool(world.mobile_mode):
		_fail("forced mobile mode inactive")
		return
	if stream == null or not bool(stream.full_stream_enabled):
		_fail("full EH15 mobile stream inactive")
		return
	if car == null:
		_fail("car missing")
		return
	if bay != null and bay.visible:
		_fail("projector UI still visible on mobile")
		return
	var active = stream.data.get("active_tile_ids", [])
	if not active is Array or active.is_empty() or active.size() > 4:
		_fail("mobile tile window invalid " + str(active))
		return
	var buildings = stream.data.get("buildings", [])
	if not buildings is Array or buildings.is_empty():
		_fail("mobile buildings missing")
		return
	print("MOBILE_STARTUP_OK tiles=%d buildings=%d pos=%s" % [active.size(), buildings.size(), str(car.global_position)])
	OS.set_environment("PUA_FORCE_MOBILE_TEST","")
	quit(0)

func _fail(reason: String):
	push_error("MOBILE_STARTUP_FAIL " + reason)
	OS.set_environment("PUA_FORCE_MOBILE_TEST","")
	quit(2)
