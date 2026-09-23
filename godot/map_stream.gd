extends Node

signal map_ready(data)
signal location_ready(latitude, longitude, postcode)

# Low-bandwidth OSM slice centred on a UK postcode. The postcode is resolved once,
# then the resulting road/building geometry is simplified and cached locally.
const OVERPASS_URL := "https://overpass-api.de/api/interpreter"
const START_POSTCODE := "EH15 2BZ"
const PATCH_PATH := "res://patches/eh15_2bz.json"
const EH15_FULL_MANIFEST_PATH := "res://patches/eh15_full/manifest.json"
const EH15_FULL_TILE_DIR := "res://patches/eh15_full"
const EH15_DESTINATIONS_PATH := "res://patches/eh15_full/destinations.json"
const MOBILE_STREAM_RADIUS_METERS := 650.0
const MOBILE_MAX_ACTIVE_TILES := 4
var CACHE_PATH := "user://pua_map_stream_eh15_2bz_v7_pc_max.json" if OS.has_feature("pc_max") else "user://pua_map_stream_eh15_2bz_v7.json"
const CACHE_MAX_AGE_SECONDS := 604800
# Quality-1 postcodes.io centroid verified 2026-09-20. This is an origin for
# local map coordinates, not a surveyed window, projector or vehicle position.
const FALLBACK_LAT := 55.951507
const FALLBACK_LON := -3.107122
var HALF_LAT := 0.0100 if OS.has_feature("pc_max") else 0.0060
var HALF_LON := 0.0160 if OS.has_feature("pc_max") else 0.0100
const MIN_POINT_GAP_METERS := 0.75
var MAX_ROADS := 420 if OS.has_feature("pc_max") else 220
var MAX_BUILDINGS := 720 if OS.has_feature("pc_max") else 320
var MAX_LINEAR_FEATURES := 520 if OS.has_feature("pc_max") else 260
var MAX_POINT_FEATURES := 520 if OS.has_feature("pc_max") else 260
var MAX_POI_FEATURES := 360 if OS.has_feature("pc_max") else 180

var center_lat := FALLBACK_LAT
var center_lon := FALLBACK_LON
var resolved_postcode := START_POSTCODE

var data := {
	"source": "offline",
	"start_postcode": START_POSTCODE,
	"center_lat": FALLBACK_LAT,
	"center_lon": FALLBACK_LON,
	"roads": [],
	"buildings": [],
	"linear_features": [],
	"point_features": [],
	"poi_features": [],
	"identity_features": [],
	"updated_unix": 0
}

var _request: HTTPRequest
var _named_road_segments: Array = []
var full_manifest: Dictionary = {}
var full_tiles: Array = []
var full_stream_enabled := false
var active_tile_signature := ""
var district_destinations: Array = []

func _ready():
	if (OS.has_feature("mobile") or OS.get_environment("PUA_FORCE_MOBILE_TEST") == "1") and _load_full_eh15_manifest():
		_load_district_destinations()
		_load_full_eh15_window(Vector2.ZERO, false)
		_rebuild_named_road_index()
		location_ready.emit(center_lat, center_lon, resolved_postcode)
		map_ready.emit(data)
		return
	var cache_fresh = _load_cache()
	if not cache_fresh:
		_load_packaged_patch()
	if data["roads"].size() > 0 or data["buildings"].size() > 0:
		center_lat = float(data.get("center_lat", FALLBACK_LAT))
		center_lon = float(data.get("center_lon", FALLBACK_LON))
		resolved_postcode = str(data.get("start_postcode", START_POSTCODE))
		_rebuild_named_road_index()
		location_ready.emit(center_lat, center_lon, resolved_postcode)
		map_ready.emit(data)
	# Headless validation must exercise the packaged, source-dated patch
	# deterministically. Playable builds still refresh from Overpass when online.
	if not cache_fresh and DisplayServer.get_name() != "headless":
		_fetch_osm()

func _load_full_eh15_manifest() -> bool:
	if not FileAccess.file_exists(EH15_FULL_MANIFEST_PATH):
		return false
	var file = FileAccess.open(EH15_FULL_MANIFEST_PATH, FileAccess.READ)
	if not file:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("patch_format", 0)) < 2:
		return false
	var tiles = parsed.get("tiles", [])
	if not tiles is Array or tiles.is_empty():
		return false
	full_manifest = parsed
	full_tiles = tiles
	full_stream_enabled = true
	center_lat = float(parsed.get("center_lat", FALLBACK_LAT))
	center_lon = float(parsed.get("center_lon", FALLBACK_LON))
	resolved_postcode = "EH15"
	return true

func _load_district_destinations():
	district_destinations.clear()
	if not FileAccess.file_exists(EH15_DESTINATIONS_PATH):
		return
	var file = FileAccess.open(EH15_DESTINATIONS_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var items = parsed.get("destinations", [])
		if items is Array:
			district_destinations = items

func get_district_destinations() -> Array:
	return district_destinations

func full_district_coverage() -> Dictionary:
	if not full_stream_enabled:
		return {}
	return {
		"postcode": "EH15",
		"coverage_bbox": full_manifest.get("coverage_bbox", []),
		"tile_count": full_tiles.size(),
		"raw_tile_totals": full_manifest.get("raw_tile_totals", {})
	}

func update_stream_position(local_position: Vector2):
	if full_stream_enabled:
		_load_full_eh15_window(local_position, true)

func _distance_sq_to_tile(tile: Dictionary, p: Vector2) -> float:
	var bounds = tile.get("local_bounds", [])
	if not bounds is Array or bounds.size() < 4:
		return INF
	var min_x = float(bounds[0])
	var min_z = float(bounds[1])
	var max_x = float(bounds[2])
	var max_z = float(bounds[3])
	var dx = maxf(maxf(min_x - p.x, 0.0), p.x - max_x)
	var dz = maxf(maxf(min_z - p.y, 0.0), p.y - max_z)
	return dx * dx + dz * dz

func _load_full_eh15_window(local_position: Vector2, emit_change: bool) -> bool:
	if not full_stream_enabled:
		return false
	var ranked: Array = []
	for raw_tile in full_tiles:
		if raw_tile is Dictionary:
			ranked.append({"tile": raw_tile, "d2": _distance_sq_to_tile(raw_tile, local_position)})
	ranked.sort_custom(func(a, b): return float(a["d2"]) < float(b["d2"]))
	var chosen: Array = []
	var radius_sq := MOBILE_STREAM_RADIUS_METERS * MOBILE_STREAM_RADIUS_METERS
	for item in ranked:
		if chosen.size() >= MOBILE_MAX_ACTIVE_TILES:
			break
		if float(item["d2"]) <= radius_sq or chosen.is_empty():
			chosen.append(item["tile"])
	var ids: Array = []
	for tile in chosen:
		ids.append(str(tile.get("id", "")))
	ids.sort()
	var signature := ",".join(ids)
	if signature == active_tile_signature and not data.get("roads", []).is_empty():
		return false

	var merged := {
		"roads": [],
		"buildings": [],
		"linear_features": [],
		"point_features": [],
		"poi_features": [],
		"identity_features": []
	}
	var seen := {
		"roads": {},
		"buildings": {},
		"linear_features": {},
		"point_features": {},
		"poi_features": {},
		"identity_features": {}
	}
	for tile in chosen:
		var filename := str(tile.get("file", ""))
		if filename == "":
			continue
		var path := "%s/%s" % [EH15_FULL_TILE_DIR, filename]
		if not FileAccess.file_exists(path):
			continue
		var tile_file = FileAccess.open(path, FileAccess.READ)
		if not tile_file:
			continue
		var tile_data = JSON.parse_string(tile_file.get_as_text())
		if not tile_data is Dictionary:
			continue
		for feature_key in merged.keys():
			var features = tile_data.get(feature_key, [])
			if not features is Array:
				continue
			var bucket: Array = merged[feature_key]
			var feature_seen: Dictionary = seen[feature_key]
			for feature in features:
				if not feature is Dictionary:
					continue
				var osm_id = int(feature.get("osm_id", 0))
				var unique_key = str(osm_id)
				if osm_id == 0:
					unique_key = "%s:%s:%s" % [str(feature.get("kind", "")), str(feature.get("name", "")), str(feature.get("point", feature.get("center", [])))]
				if feature_seen.has(unique_key):
					continue
				feature_seen[unique_key] = true
				bucket.append(feature)
			merged[feature_key] = bucket
			seen[feature_key] = feature_seen

	active_tile_signature = signature
	data = {
		"source": "packaged_osm_tiles",
		"source_name": "OpenStreetMap",
		"source_url": "https://www.openstreetmap.org/copyright",
		"license": "ODbL 1.0; © OpenStreetMap contributors",
		"source_timestamp_utc": str(full_manifest.get("source_timestamp_utc", "")),
		"start_postcode": "EH15",
		"center_lat": center_lat,
		"center_lon": center_lon,
		"roads": merged["roads"],
		"buildings": merged["buildings"],
		"linear_features": merged["linear_features"],
		"point_features": merged["point_features"],
		"poi_features": merged["poi_features"],
		"identity_features": merged["identity_features"],
		"active_tile_ids": ids,
		"full_tile_count": full_tiles.size(),
		"full_coverage_bbox": full_manifest.get("coverage_bbox", []),
		"full_raw_tile_totals": full_manifest.get("raw_tile_totals", {}),
		"updated_unix": int(Time.get_unix_time_from_system())
	}
	_rebuild_named_road_index()
	if emit_change:
		map_ready.emit(data)
	return true

func _load_packaged_patch() -> bool:
	if not FileAccess.file_exists(PATCH_PATH):
		return false
	var file = FileAccess.open(PATCH_PATH, FileAccess.READ)
	if not file:
		return false
	var packaged = JSON.parse_string(file.get_as_text())
	if not packaged is Dictionary:
		return false
	packaged = _hydrate_patch_parts(packaged)
	if str(packaged.get("start_postcode", "")).to_upper() != START_POSTCODE:
		return false
	if abs(float(packaged.get("center_lat", 0.0)) - FALLBACK_LAT) > 0.000001:
		return false
	if abs(float(packaged.get("center_lon", 0.0)) - FALLBACK_LON) > 0.000001:
		return false
	if packaged.get("roads", []).is_empty() or packaged.get("buildings", []).is_empty():
		return false
	data = packaged
	data["source"] = "packaged_osm_patch"
	center_lat = FALLBACK_LAT
	center_lon = FALLBACK_LON
	resolved_postcode = START_POSTCODE
	return true

func _hydrate_patch_parts(manifest: Dictionary) -> Dictionary:
	var parts = manifest.get("parts", {})
	if not parts is Dictionary:
		return manifest
	var hydrated = manifest.duplicate(true)
	for feature in ["roads", "buildings", "linear_features", "point_features", "poi_features"]:
		var items: Array = []
		var filenames = parts.get(feature, [])
		if not filenames is Array:
			continue
		for filename in filenames:
			var path = "res://patches/%s" % str(filename)
			if not FileAccess.file_exists(path):
				continue
			var part_file = FileAccess.open(path, FileAccess.READ)
			if not part_file:
				continue
			var part = JSON.parse_string(part_file.get_as_text())
			if part is Dictionary and str(part.get("patch_id", "")) == str(manifest.get("patch_id", "")) and str(part.get("feature", "")) == feature:
				items.append_array(part.get("items", []))
		hydrated[feature] = items
	return hydrated

func _load_cache() -> bool:
	if not FileAccess.file_exists(CACHE_PATH):
		return false
	var file = FileAccess.open(CACHE_PATH, FileAccess.READ)
	if not file:
		return false
	var cached = JSON.parse_string(file.get_as_text())
	if not cached is Dictionary:
		return false
	if not cached.has("roads") or not cached.has("buildings"):
		return false
	if str(cached.get("start_postcode", "")).to_upper() != START_POSTCODE:
		return false
	data = cached
	data["source"] = "cache"
	var age = int(Time.get_unix_time_from_system()) - int(data.get("updated_unix", 0))
	return age >= 0 and age < CACHE_MAX_AGE_SECONDS

func _fetch_osm():
	if _request:
		return
	_request = HTTPRequest.new()
	_request.timeout = 18.0
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)
	var south = center_lat - HALF_LAT
	var west = center_lon - HALF_LON
	var north = center_lat + HALF_LAT
	var east = center_lon + HALF_LON
	var bbox = "%.6f,%.6f,%.6f,%.6f" % [south, west, north, east]
	var query = '[out:json][timeout:15];(way[highway~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street|service|track)$"](%s);way[building](%s);way[barrier~"^(hedge|fence|wall)$"](%s);way[highway~"^(footway|path|cycleway)$"](%s);node[natural=tree](%s);node[highway~"^(traffic_signals|crossing|bus_stop|stop|give_way)$"](%s);node[traffic_sign](%s);node[amenity][name](%s);node[shop][name](%s);node[tourism][name](%s);node[leisure][name](%s);node[historic][name](%s);node[place][name](%s););out tags geom qt;' % [bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox]
	var url = OVERPASS_URL + "?data=" + query.uri_encode()
	var headers = PackedStringArray([
		"Accept: application/json",
		"User-Agent: ProceedUntilApprehended/0.76 (Godot; EH15 source-labelled cached OSM geometry)"
	])
	var err = _request.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_request.queue_free()
		_request = null

func _on_request_completed(result: int, response_code: int, _headers, body: PackedByteArray):
	if _request:
		_request.queue_free()
		_request = null
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var elements = parsed.get("elements", [])
	if not elements is Array:
		return
	var roads: Array = []
	var buildings: Array = []
	var linear_features: Array = []
	var point_features: Array = []
	var poi_features: Array = []
	for element in elements:
		if not element is Dictionary:
			continue
		var tags = element.get("tags", {})
		if not tags is Dictionary:
			continue
		var element_type = str(element.get("type", ""))
		if element_type == "node":
			if not element.has("lat") or not element.has("lon"):
				continue
			var p = _lat_lon_to_local(float(element.get("lat", center_lat)), float(element.get("lon", center_lon)))
			var point_kind := ""
			if str(tags.get("natural", "")) == "tree":
				point_kind = "tree"
			else:
				var highway = str(tags.get("highway", ""))
				if highway in ["traffic_signals", "crossing", "bus_stop", "stop", "give_way"]:
					point_kind = highway
				elif tags.has("traffic_sign"):
					point_kind = "traffic_sign"
			if point_kind != "":
				point_features.append({
					"kind": point_kind,
					"point": [p.x, p.y],
					"name": str(tags.get("name", "")),
					"crossing": str(tags.get("crossing", "")),
					"traffic_sign": str(tags.get("traffic_sign", "")),
					"ref": str(tags.get("ref", ""))
				})
			var poi_name = str(tags.get("name", "")).strip_edges()
			if poi_name != "":
				var poi_kind := ""
				for key in ["amenity", "shop", "tourism", "leisure", "historic", "place"]:
					if tags.has(key):
						poi_kind = str(tags.get(key, key))
						break
				if poi_kind != "":
					poi_features.append({
						"kind": poi_kind,
						"name": poi_name,
						"brand": str(tags.get("brand", "")),
						"operator": str(tags.get("operator", "")),
						"point": [p.x, p.y]
					})
			continue

		var geometry = element.get("geometry", [])
		if not geometry is Array or geometry.size() < 2:
			continue
		var highway_kind = str(tags.get("highway", ""))
		if highway_kind in ["motorway", "trunk", "primary", "secondary", "tertiary", "residential", "unclassified", "living_street", "service", "track"]:
			var points = _geometry_to_points(geometry, MIN_POINT_GAP_METERS)
			if points.size() >= 2:
				roads.append({
					"osm_id": int(element.get("id", 0)),
					"kind": highway_kind,
					"name": str(tags.get("name", "")),
					"width": _road_width_from_tags(tags),
					"width_source": _road_width_source_from_tags(tags),
					"lanes": int(str(tags.get("lanes", "0")).to_int()),
					"oneway": str(tags.get("oneway", "no")),
					"surface": str(tags.get("surface", "")),
					"sidewalk": str(tags.get("sidewalk", "")),
					"lit": str(tags.get("lit", "")),
					"maxspeed": str(tags.get("maxspeed", "")),
					"ref": str(tags.get("ref", "")),
					"points": points
				})
		elif tags.has("building"):
			var building = _building_from_geometry(tags, geometry, int(element.get("id", 0)))
			if not building.is_empty():
				buildings.append(building)
		else:
			var linear_kind := ""
			var barrier = str(tags.get("barrier", ""))
			if barrier in ["hedge", "fence", "wall"]:
				linear_kind = barrier
			elif highway_kind in ["footway", "path", "cycleway"]:
				linear_kind = highway_kind
			if linear_kind != "":
				var feature_points = _geometry_to_points(geometry, MIN_POINT_GAP_METERS)
				if feature_points.size() >= 2:
					linear_features.append({
						"kind": linear_kind,
						"surface": str(tags.get("surface", "")),
						"points": feature_points
					})
	roads.sort_custom(_line_feature_closer)
	buildings.sort_custom(_building_feature_closer)
	linear_features.sort_custom(_line_feature_closer)
	point_features.sort_custom(_point_feature_closer)
	poi_features.sort_custom(_point_feature_closer)
	roads.resize(min(roads.size(), MAX_ROADS))
	buildings.resize(min(buildings.size(), MAX_BUILDINGS))
	linear_features.resize(min(linear_features.size(), MAX_LINEAR_FEATURES))
	point_features.resize(min(point_features.size(), MAX_POINT_FEATURES))
	poi_features.resize(min(poi_features.size(), MAX_POI_FEATURES))
	data = {
		"source": "live",
		"source_name": "OpenStreetMap",
		"source_url": "https://www.openstreetmap.org/copyright",
		"license": "ODbL 1.0; © OpenStreetMap contributors",
		"start_postcode": resolved_postcode,
		"center_lat": center_lat,
		"center_lon": center_lon,
		"roads": roads,
		"buildings": buildings,
		"linear_features": linear_features,
		"point_features": point_features,
		"poi_features": poi_features,
		"updated_unix": int(Time.get_unix_time_from_system())
	}
	_rebuild_named_road_index()
	_save_cache()
	map_ready.emit(data)

func _rebuild_named_road_index():
	_named_road_segments.clear()
	for road in data.get("roads", []):
		if not road is Dictionary:
			continue
		var name = str(road.get("name", "")).strip_edges()
		var ref = str(road.get("ref", "")).strip_edges()
		if name == "" and ref == "":
			continue
		var points = road.get("points", [])
		if not points is Array:
			continue
		for i in range(points.size() - 1):
			var p0 = points[i]
			var p1 = points[i + 1]
			if not p0 is Array or not p1 is Array or p0.size() < 2 or p1.size() < 2:
				continue
			var a = Vector2(float(p0[0]), float(p0[1]))
			var b = Vector2(float(p1[0]), float(p1[1]))
			if a.distance_squared_to(b) < 0.01:
				continue
			_named_road_segments.append({
				"a": a,
				"b": b,
				"name": name,
				"ref": ref,
				"osm_id": int(road.get("osm_id", 0))
			})

func nearest_named_road(local_position: Vector2) -> Dictionary:
	var best_distance := INF
	var best: Dictionary = {}
	for segment in _named_road_segments:
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var ab = b - a
		var denominator = ab.length_squared()
		if denominator < 0.001:
			continue
		var t = clamp((local_position - a).dot(ab) / denominator, 0.0, 1.0)
		var nearest = a + ab * t
		var distance = local_position.distance_to(nearest)
		if distance < best_distance:
			best_distance = distance
			best = {
				"name": str(segment["name"]),
				"ref": str(segment["ref"]),
				"osm_id": int(segment["osm_id"]),
				"distance_m": distance,
				"nearest_local": nearest
			}
	return best


func _nearest_other_named_road(local_position: Vector2, excluded_name: String) -> Dictionary:
	var best_distance := INF
	var best: Dictionary = {}
	var seen := {}
	for segment in _named_road_segments:
		var name := str(segment.get("name", "")).strip_edges()
		if name == "" or name == excluded_name or seen.has(name):
			continue
		seen[name] = true
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var ab := b - a
		var denominator := ab.length_squared()
		if denominator < 0.001:
			continue
		var t := clampf((local_position - a).dot(ab) / denominator, 0.0, 1.0)
		var nearest := a + ab * t
		var distance := local_position.distance_to(nearest)
		if distance < best_distance:
			best_distance = distance
			best = {
				"name": name,
				"ref": str(segment.get("ref", "")),
				"osm_id": int(segment.get("osm_id", 0)),
				"distance_m": distance
			}
	return best

func _identity_feature_priority(kind: String, source_type: String) -> float:
	var k := kind.to_lower()
	if k.begins_with("historic:") or k.begins_with("tourism:attraction") or k.begins_with("tourism:artwork"):
		return 0.0
	if k.begins_with("amenity:library") or k.begins_with("amenity:school") or k.begins_with("amenity:social_centre") or k.begins_with("amenity:post_office"):
		return 35.0
	if k.begins_with("leisure:") or k.begins_with("tourism:information"):
		return 70.0
	if source_type == "building":
		return 115.0
	# Hotels, guest houses, takeaways and shops can still orient the player when
	# they are genuinely the closest named thing, but they should not beat a public
	# or historic landmark at a similar distance.
	return 180.0

func mobile_location_identity(local_position: Vector2) -> Dictionary:
	var current_road := nearest_named_road(local_position)
	var current_name := str(current_road.get("name", "")).strip_edges()
	var nearby_road := _nearest_other_named_road(local_position, current_name)
	var nearest_place: Dictionary = {}
	var nearest_place_distance := INF
	var nearest_landmark: Dictionary = {}
	var best_landmark_score := INF

	for poi in data.get("poi_features", []):
		if not poi is Dictionary:
			continue
		var name := str(poi.get("name", "")).strip_edges()
		var point = poi.get("point", [])
		if name == "" or not point is Array or point.size() < 2:
			continue
		var p := Vector2(float(point[0]), float(point[1]))
		var distance := local_position.distance_to(p)
		var kind := str(poi.get("kind", ""))
		var lower_kind := kind.to_lower()
		if lower_kind.begins_with("place:") or lower_kind in ["suburb", "neighbourhood", "town", "village", "locality"]:
			if distance < nearest_place_distance:
				nearest_place_distance = distance
				nearest_place = {"name": name, "kind": kind, "distance_m": distance, "osm_id": int(poi.get("osm_id", 0))}
			continue
		if distance > 900.0:
			continue
		var score := distance + _identity_feature_priority(kind, "poi")
		if score < best_landmark_score:
			best_landmark_score = score
			nearest_landmark = {"name": name, "kind": kind, "distance_m": distance, "osm_id": int(poi.get("osm_id", 0)), "source_type": "poi"}

	for building in data.get("buildings", []):
		if not building is Dictionary:
			continue
		var name := str(building.get("name", "")).strip_edges()
		var center = building.get("center", [])
		if name == "" or not center is Array or center.size() < 2:
			continue
		var p := Vector2(float(center[0]), float(center[1]))
		var distance := local_position.distance_to(p)
		if distance > 700.0:
			continue
		var kind := str(building.get("kind", "building"))
		var score := distance + _identity_feature_priority(kind, "building")
		if score < best_landmark_score:
			best_landmark_score = score
			nearest_landmark = {"name": name, "kind": kind, "distance_m": distance, "osm_id": int(building.get("osm_id", 0)), "source_type": "building"}

	return {
		"road": current_road,
		"near_road": nearby_road,
		"place": nearest_place,
		"landmark": nearest_landmark,
		"source": "OpenStreetMap"
	}

func local_to_lat_lon(local_position: Vector2) -> Vector2:
	var meters_per_lon = 111320.0 * cos(deg_to_rad(center_lat))
	var latitude = center_lat - local_position.y / 111320.0
	var longitude = center_lon + local_position.x / max(1.0, meters_per_lon)
	return Vector2(latitude, longitude)

func map_source_date() -> String:
	var timestamp = str(data.get("source_timestamp_utc", ""))
	if timestamp.length() >= 10:
		return timestamp.substr(0, 10)
	var unix_time = int(data.get("updated_unix", 0))
	if unix_time > 0:
		var date = Time.get_date_dict_from_unix_time(unix_time)
		return "%04d-%02d-%02d" % [int(date.get("year", 0)), int(date.get("month", 0)), int(date.get("day", 0))]
	return "OFFLINE"

func _line_feature_closer(a: Dictionary, b: Dictionary) -> bool:
	return _line_feature_distance(a) < _line_feature_distance(b)

func _building_feature_closer(a: Dictionary, b: Dictionary) -> bool:
	var ac = a.get("center", [INF, INF])
	var bc = b.get("center", [INF, INF])
	return Vector2(float(ac[0]), float(ac[1])).length_squared() < Vector2(float(bc[0]), float(bc[1])).length_squared()

func _point_feature_closer(a: Dictionary, b: Dictionary) -> bool:
	var ap = a.get("point", [INF, INF])
	var bp = b.get("point", [INF, INF])
	return Vector2(float(ap[0]), float(ap[1])).length_squared() < Vector2(float(bp[0]), float(bp[1])).length_squared()

func _line_feature_distance(feature: Dictionary) -> float:
	var best = INF
	for point in feature.get("points", []):
		if point is Array and point.size() >= 2:
			best = min(best, Vector2(float(point[0]), float(point[1])).length_squared())
	return best

func _geometry_to_points(geometry: Array, min_gap: float) -> Array:
	var points: Array = []
	var last = Vector2(INF, INF)
	for entry in geometry:
		if not entry is Dictionary:
			continue
		var p = _lat_lon_to_local(float(entry.get("lat", center_lat)), float(entry.get("lon", center_lon)))
		if points.is_empty() or last.distance_to(p) >= min_gap:
			points.append([p.x, p.y])
			last = p
	if geometry.size() > 1:
		var tail_entry = geometry[geometry.size() - 1]
		if tail_entry is Dictionary:
			var tail = _lat_lon_to_local(float(tail_entry.get("lat", center_lat)), float(tail_entry.get("lon", center_lon)))
			if points.is_empty() or Vector2(float(points[-1][0]), float(points[-1][1])).distance_to(tail) > 2.0:
				points.append([tail.x, tail.y])
	return points

func _building_from_geometry(tags: Dictionary, geometry: Array, osm_id: int = 0) -> Dictionary:
	var min_x = INF
	var max_x = -INF
	var min_z = INF
	var max_z = -INF
	var footprint: Array = []
	for entry in geometry:
		if not entry is Dictionary:
			continue
		var p = _lat_lon_to_local(float(entry.get("lat", center_lat)), float(entry.get("lon", center_lon)))
		footprint.append([p.x, p.y])
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_z = min(min_z, p.y)
		max_z = max(max_z, p.y)
	if min_x == INF:
		return {}
	var sx = max_x - min_x
	var sz = max_z - min_z
	if sx < 2.0 or sz < 2.0 or sx > 120.0 or sz > 120.0:
		return {}
	var levels = float(str(tags.get("building:levels", "0")).to_float())
	var tagged_height = float(str(tags.get("height", "0")).to_float())
	var height = tagged_height if tagged_height > 1.5 else max(3.2, levels * 3.0)
	if height <= 3.2:
		height = 6.0
	height = clamp(height, 3.0, 48.0)
	if footprint.size() > 2 and footprint[0] == footprint[-1]:
		footprint.pop_back()
	return {
		"osm_id": osm_id,
		"center": [(min_x + max_x) * 0.5, (min_z + max_z) * 0.5],
		"size": [sx, sz],
		"footprint": footprint,
		"height": height,
		"footprint_source": "osm:way_geometry",
		"height_source": "osm:height" if tagged_height > 1.5 else ("estimated:osm_levels_x_3m" if levels > 0.0 else "estimated:no_osm_height_default"),
		"levels": levels,
		"kind": str(tags.get("building", "yes")),
		"material": str(tags.get("building:material", "")),
		"roof_shape": str(tags.get("roof:shape", "")),
		"roof_material": str(tags.get("roof:material", "")),
		"name": str(tags.get("name", "")),
		"addr_housenumber": str(tags.get("addr:housenumber", "")),
		"addr_street": str(tags.get("addr:street", "")),
		"amenity": str(tags.get("amenity", "")),
		"shop": str(tags.get("shop", ""))
	}

func _lat_lon_to_local(lat: float, lon: float) -> Vector2:
	var meters_per_lon = 111320.0 * cos(deg_to_rad(center_lat))
	var x = (lon - center_lon) * meters_per_lon
	var z = -(lat - center_lat) * 111320.0
	return Vector2(x, z)

func _road_width_from_tags(tags: Dictionary) -> float:
	var explicit = float(str(tags.get("width", "0")).to_float())
	if explicit > 2.0 and explicit < 30.0:
		return explicit
	var kind = str(tags.get("highway", ""))
	var lanes = int(str(tags.get("lanes", "0")).to_int())
	if lanes > 0:
		var lane_width = 3.15 if kind in ["primary", "secondary", "tertiary"] else 2.85
		return clamp(float(lanes) * lane_width, 3.0, 14.0)
	return _road_width(kind)

func _road_width_source_from_tags(tags: Dictionary) -> String:
	var explicit = float(str(tags.get("width", "0")).to_float())
	if explicit > 2.0 and explicit < 30.0:
		return "osm:width"
	var lanes = int(str(tags.get("lanes", "0")).to_int())
	if lanes > 0:
		return "estimated:osm_lanes_x_class_lane_width"
	return "estimated:highway_class_default"

func _road_width(kind: String) -> float:
	match kind:
		"motorway", "trunk":
			return 11.0
		"primary", "secondary":
			return 8.5
		"tertiary":
			return 7.0
		"residential", "unclassified", "living_street":
			return 6.0
		"service":
			return 4.5
		"track":
			return 3.4
		"cycleway", "footway", "path", "steps":
			return 2.0
		_:
			return 4.8

func _save_cache():
	var file = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
