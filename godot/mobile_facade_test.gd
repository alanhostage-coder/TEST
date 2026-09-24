extends SceneTree

func _initialize():
	OS.set_environment("PUA_FORCE_MOBILE_TEST","1")
	call_deferred("run")

func run():
	var packed=load("res://world.tscn")
	if packed==null:
		_fail("world scene missing")
		return
	var world=packed.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var map_root=world.map_root
	if map_root==null:
		_fail("map root missing")
		return
	var target=null
	var stack:Array=[map_root]
	while not stack.is_empty():
		var node=stack.pop_back()
		if int(node.get_meta("osm_id",0))==277435366:
			target=node
			break
		for child in node.get_children():
			stack.append(child)
	if target==null:
		_fail("field target OSM 277435366 not rendered")
		return
	var detail_count=int(target.get_meta("mobile_facade_detail_count",0))
	var shopfront_count=int(target.get_meta("mobile_shopfront_count",0))
	if detail_count < 4:
		_fail("field target still blank detail_count="+str(detail_count))
		return
	if shopfront_count < 1:
		_fail("field target lost mapped commercial cue")
		return
	if str(target.get_meta("osm_kind",""))!="apartments":
		_fail("field target kind changed")
		return
	print("MOBILE_FACADE_OK osm=277435366 detail=%d shopfronts=%d" % [detail_count,shopfront_count])
	OS.set_environment("PUA_FORCE_MOBILE_TEST","")
	quit(0)

func _fail(reason:String):
	push_error("MOBILE_FACADE_FAIL "+reason)
	OS.set_environment("PUA_FORCE_MOBILE_TEST","")
	quit(2)
