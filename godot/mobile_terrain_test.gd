extends SceneTree

func _initialize():
	OS.set_environment("PUA_FORCE_MOBILE_TEST", "1")
	call_deferred("run")

func _fail(reason: String):
	push_error("MOBILE_TERRAIN_FAIL " + reason)
	OS.set_environment("PUA_FORCE_MOBILE_TEST", "")
	quit(2)

func run():
	var stream_script = load("res://map_stream.gd")
	if stream_script == null:
		_fail("map stream missing")
		return
	var stream = stream_script.new()
	root.add_child(stream)
	await process_frame
	if not stream.terrain_available():
		_fail("terrain profile unavailable")
		return
	var summary = stream.terrain_summary()
	if str(summary.get("source_tile", "")) != "N55W004":
		_fail("unexpected terrain source " + str(summary))
		return
	if float(summary.get("max_y_m", 0.0)) - float(summary.get("min_y_m", 0.0)) < 4.0:
		_fail("EH15 terrain is effectively flat")
		return
	var pittville_points: Array = []
	for road in stream.data.get("roads", []):
		if road is Dictionary and str(road.get("name", "")).strip_edges().to_lower() == "pittville street":
			var pts = road.get("points", [])
			if pts is Array:
				pittville_points.append_array(pts)
	if pittville_points.size() < 3:
		_fail("Pittville Street missing from active mobile tiles")
		return
	var min_y := INF
	var max_y := -INF
	var worst_error := 0.0
	for p in pittville_points:
		if not p is Array or p.size() < 3:
			continue
		var expected := float(p[2])
		var sampled := float(stream.terrain_height_at(Vector2(float(p[0]), float(p[1]))))
		min_y = minf(min_y, expected)
		max_y = maxf(max_y, expected)
		worst_error = maxf(worst_error, absf(expected - sampled))
	if max_y - min_y < 5.0:
		_fail("Pittville Street relief too small %.2f" % (max_y - min_y))
		return
	if worst_error > 0.75:
		_fail("terrain sampler disagrees with source points %.2f" % worst_error)
		return
	print("MOBILE_TERRAIN_OK pittville_relief=%.2f sampler_error=%.2f sea_y=%.2f" % [
		max_y - min_y, worst_error, float(stream.terrain_sea_level_y())
	])
	OS.set_environment("PUA_FORCE_MOBILE_TEST", "")
	quit(0)
