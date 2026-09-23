extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var world_script = load("res://world.gd")
	if world_script == null:
		push_error("MOBILE_FIRST_IMPRESSION_FAIL world script")
		quit(2)
		return
	var world = world_script.new()
	var building := {
		"center": [0.0, 0.0],
		"size": [10.0, 10.0],
		"footprint": [[-5.0,-5.0],[5.0,-5.0],[5.0,5.0],[-5.0,5.0]]
	}
	var inside := world._building_footprint_clearance(Vector2.ZERO, building)
	var outside := world._building_footprint_clearance(Vector2(12.0, 0.0), building)
	if inside > 0.01:
		push_error("MOBILE_FIRST_IMPRESSION_FAIL inside clearance " + str(inside))
		quit(2)
		return
	if absf(outside - 7.0) > 0.05:
		push_error("MOBILE_FIRST_IMPRESSION_FAIL outside clearance " + str(outside))
		quit(2)
		return
	if world.MOBILE_BUILDING_VISUAL_RADIUS > 450.0:
		push_error("MOBILE_FIRST_IMPRESSION_FAIL mobile visual radius " + str(world.MOBILE_BUILDING_VISUAL_RADIUS))
		quit(2)
		return
	print("MOBILE_FIRST_IMPRESSION_OK clearance=%s/%s radius=%s" % [inside, outside, world.MOBILE_BUILDING_VISUAL_RADIUS])
	quit(0)
