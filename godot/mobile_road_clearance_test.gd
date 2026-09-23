extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var file=FileAccess.open("res://patches/eh15_full/manifest.json",FileAccess.READ)
	if file==null:
		push_error("MOBILE_ROAD_CLEARANCE_FAIL manifest missing")
		quit(2)
		return
	var m=JSON.parse_string(file.get_as_text())
	if not m is Dictionary:
		push_error("MOBILE_ROAD_CLEARANCE_FAIL manifest invalid")
		quit(2)
		return
	if str(m.get("road_conflict_policy",""))!="offline_nonservice_corridor_cull_v1":
		push_error("MOBILE_ROAD_CLEARANCE_FAIL offline policy missing")
		quit(2)
		return
	if int(m.get("road_conflict_culled",-1)) < 0:
		push_error("MOBILE_ROAD_CLEARANCE_FAIL cull count missing")
		quit(2)
		return
	print("MOBILE_ROAD_CLEARANCE_OK culled=%d" % int(m.get("road_conflict_culled",0)))
	quit(0)
