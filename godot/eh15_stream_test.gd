# Android 0.79 recognisability gate: source-backed road identity + full EH15 streaming.
extends SceneTree

func _initialize():
	call_deferred("run")

func _fail(message: String):
	push_error("EH15_STREAM_FAIL " + message)
	quit(2)

func run():
	const MANIFEST := "res://patches/eh15_full/manifest.json"
	if not FileAccess.file_exists(MANIFEST):
		print("EH15_STREAM_SKIP pre-harvest commit")
		quit(0)
		return
	var stream_script = load("res://map_stream.gd")
	if stream_script == null:
		_fail("map stream script missing")
		return
	var stream = stream_script.new()
	root.add_child(stream)
	await process_frame
	if not stream._load_full_eh15_manifest():
		_fail("full EH15 manifest rejected")
		return
	stream._load_district_destinations()
	var manifest: Dictionary = stream.full_manifest
	if str(manifest.get("dedupe_policy", "")) != "osm_id+kind per tile":
		_fail("EH15 bundle is not deduped")
		return
	var totals_check = manifest.get("raw_tile_totals", {})
	if totals_check is Dictionary and int(totals_check.get("buildings", 999999)) >= 45000:
		_fail("EH15 building inventory still looks duplicated")
		return
	var tiles = manifest.get("tiles", [])
	if not tiles is Array or tiles.size() < 25:
		_fail("tile coverage too small")
		return
	var bbox = manifest.get("coverage_bbox", [])
	if not bbox is Array or bbox.size() < 4:
		_fail("coverage bbox missing")
		return
	if float(bbox[2]) - float(bbox[0]) < 0.055 or float(bbox[3]) - float(bbox[1]) < 0.090:
		_fail("coverage envelope does not span EH15")
		return
	var identity_totals = manifest.get("identity_kind_totals", {})
	if not identity_totals is Dictionary or int(identity_totals.get("coastline", 0)) < 1:
		_fail("source-backed coastline missing from EH15 manifest")
		return
	var destinations = stream.get_district_destinations()
	if not destinations is Array or destinations.size() < 20:
		_fail("source-backed destination set too small")
		return
	var identity = stream.mobile_location_identity(Vector2.ZERO)
	if not identity is Dictionary:
		_fail("mobile location identity missing")
		return
	var identity_road = identity.get("road", {})
	if not identity_road is Dictionary or str(identity_road.get("name", "")).strip_edges() == "":
		_fail("mobile location identity has no named road")
		return
	if int(identity_road.get("osm_id", 0)) <= 0:
		_fail("mobile location identity road lost OSM id")
		return
	if str(identity.get("source", "")) != "OpenStreetMap":
		_fail("mobile location identity provenance missing")
		return
	var best := {}
	for raw_tile in tiles:
		if not raw_tile is Dictionary:
			continue
		var filename := str(raw_tile.get("file", ""))
		if filename == "" or not FileAccess.file_exists("res://patches/eh15_full/" + filename):
			_fail("tile file missing " + filename)
			return
		var bounds = raw_tile.get("local_bounds", [])
		if not bounds is Array or bounds.size() < 4:
			continue
		var centre := Vector2(
			(float(bounds[0]) + float(bounds[2])) * 0.5,
			(float(bounds[1]) + float(bounds[3])) * 0.5
		)
		var counts = raw_tile.get("counts", {})
		var content_count := 0
		if counts is Dictionary:
			content_count = int(counts.get("roads", 0)) + int(counts.get("buildings", 0))
		var quadrant := "%d:%d" % [1 if centre.x >= 0.0 else -1, 1 if centre.y >= 0.0 else -1]
		if not best.has(quadrant) or content_count > int(best[quadrant].get("count", -1)):
			best[quadrant] = {"point": centre, "count": content_count}
	if best.size() < 4:
		_fail("EH15 coverage lacks four populated quadrants")
		return
	var coastal_point := Vector2(INF, INF)
	for raw_tile in tiles:
		if not raw_tile is Dictionary:
			continue
		var filename := str(raw_tile.get("file", ""))
		if filename == "":
			continue
		var tile_file = FileAccess.open("res://patches/eh15_full/" + filename, FileAccess.READ)
		if not tile_file:
			continue
		var tile_data = JSON.parse_string(tile_file.get_as_text())
		if not tile_data is Dictionary:
			continue
		for feature in tile_data.get("identity_features", []):
			if feature is Dictionary and str(feature.get("kind", "")) == "coastline":
				var coast_points = feature.get("points", [])
				if coast_points is Array and not coast_points.is_empty() and coast_points[0] is Array and coast_points[0].size() >= 2:
					coastal_point = Vector2(float(coast_points[0][0]), float(coast_points[0][1]))
					break
		if coastal_point.x != INF:
			break
	if coastal_point.x == INF:
		_fail("no runtime coastline coordinate found")
		return
	stream.active_tile_signature = ""
	stream._load_full_eh15_window(coastal_point, false)
	var streamed_coast := false
	for feature in stream.data.get("identity_features", []):
		if feature is Dictionary and str(feature.get("kind", "")) == "coastline":
			streamed_coast = true
			break
	if not streamed_coast:
		_fail("coastline does not survive mobile tile streaming")
		return

	var checked := 0
	for sample in best.values():
		var point: Vector2 = sample.get("point", Vector2.ZERO)
		stream.active_tile_signature = ""
		stream._load_full_eh15_window(point, false)
		var roads = stream.data.get("roads", [])
		var buildings = stream.data.get("buildings", [])
		var active_ids = stream.data.get("active_tile_ids", [])
		if not roads is Array or roads.is_empty() or not buildings is Array or buildings.is_empty():
			_fail("streamed district sample is empty")
			return
		if not active_ids is Array or active_ids.is_empty() or active_ids.size() > stream.MOBILE_MAX_ACTIVE_TILES:
			_fail("active tile budget violated")
			return
		if str(stream.data.get("source", "")) != "packaged_osm_tiles":
			_fail("stream source provenance missing")
			return
		var checked_source_ids := 0
		for feature in roads:
			if feature is Dictionary:
				checked_source_ids += 1
				if int(feature.get("osm_id", 0)) <= 0:
					_fail("streamed road lost OSM object id")
					return
				if checked_source_ids >= 24:
					break
		checked_source_ids = 0
		for feature in buildings:
			if feature is Dictionary:
				checked_source_ids += 1
				if int(feature.get("osm_id", 0)) <= 0:
					_fail("streamed building lost OSM object id")
					return
				if checked_source_ids >= 24:
					break
		checked += 1
	var totals = manifest.get("raw_tile_totals", {})
	print("EH15_STREAM_OK tiles=%d destinations=%d samples=%d roads=%s buildings=%s" % [
		tiles.size(), destinations.size(), checked,
		str(totals.get("roads", "?")) if totals is Dictionary else "?",
		str(totals.get("buildings", "?")) if totals is Dictionary else "?"
	])
	quit(0)
