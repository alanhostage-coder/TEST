extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var world_script = load("res://world.gd")
	if world_script == null:
		push_error("MOBILE_ROAD_CLEARANCE_FAIL world script")
		quit(2)
		return
	var world = world_script.new()
	world.mobile_mode = true
	world.map_segments = [
		[[Vector2(-20.0,0.0).x, Vector2(-20.0,0.0).y], [Vector2(20.0,0.0).x, Vector2(20.0,0.0).y], 6.0, "secondary", "no"]
	]
	var blocking := {"footprint":[[-2.0,-2.0],[2.0,-2.0],[2.0,2.0],[-2.0,2.0]]}
	var roadside := {"footprint":[[-2.0,7.0],[2.0,7.0],[2.0,11.0],[-2.0,11.0]]}
	if not world._mobile_building_intrudes_drivable_road(blocking):
		push_error("MOBILE_ROAD_CLEARANCE_FAIL blocking building survived")
		quit(2)
		return
	if world._mobile_building_intrudes_drivable_road(roadside):
		push_error("MOBILE_ROAD_CLEARANCE_FAIL roadside building wrongly culled")
		quit(2)
		return
	print("MOBILE_ROAD_CLEARANCE_OK")
	quit(0)
