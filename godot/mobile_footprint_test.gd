extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var world_script = load("res://world.gd")
	if world_script == null:
		push_error("MOBILE_FOOTPRINT_FAIL world script missing")
		quit(2)
		return
	var world = world_script.new()
	var result = world._mobile_footprint_regression()
	if int(result.get("passed",0)) != int(result.get("total",0)):
		push_error("MOBILE_FOOTPRINT_FAIL bounding-box regression " + str(result))
		quit(2)
		return
	if float(result.get("collision_radius",0.0)) >= float(result.get("visual_radius",0.0)):
		push_error("MOBILE_FOOTPRINT_FAIL no visual-only band " + str(result))
		quit(2)
		return
	print("MOBILE_FOOTPRINT_OK " + str(result))
	quit(0)
