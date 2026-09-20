extends Node

signal map_ready(data)

# Low-bandwidth OSM slice centred on a UK postcode. The postcode is resolved once,
# then the resulting road/building geometry is simplified and cached locally.
const OVERPASS_URL := "https://overpass-api.de/api/interpreter"
const POSTCODES_URL := "https://api.postcodes.io/postcodes/"
const START_POSTCODE := "RH15 2BZ"
const CACHE_PATH := "user://pua_map_stream_rh15_2bz_v3.json"
const CACHE_MAX_AGE_SECONDS := 604800
# Burgess Hill fallback only matters if postcode resolution is unavailable.
const FALLBACK_LAT := 50.9570
const FALLBACK_LON := -0.1320
const HALF_LAT := 0.0060
const HALF_LON := 0.0100
const MIN_POINT_GAP_METERS := 0.75
const MAX_ROADS := 220
const MAX_BUILDINGS := 320
const MAX_LINEAR_FEATURES := 260
const MAX_POINT_FEATURES := 220

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
	"updated_unix": 0
}

var _request: HTTPRequest
var _postcode_request: HTTPRequest

func _ready():
	var cache_fresh = _load_cache()
	if data["roads"].size() > 0 or data["buildings"].size() > 0:
		center_lat = float(data.get("center_lat", FALLBACK_LAT))
		center_lon = float(data.get("center_lon", FALLBACK_LON))
		resolved_postcode = str(data.get("start_postcode", START_POSTCODE))
		map_ready.emit(data)
	if not cache_fresh:
		_resolve_start_postcode()

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

func _resolve_start_postcode():
	if _postcode_request:
		return
	_postcode_request = HTTPRequest.new()
	_postcode_request.timeout = 10.0
	add_child(_postcode_request)
	_postcode_request.request_completed.connect(_on_postcode_resolved)
	var compact = START_POSTCODE.replace(" ", "").uri_encode()
	var headers = PackedStringArray([
		"Accept: application/json",
		"User-Agent: ProceedUntilApprehended/0.57 (Godot Android; postcode-seeded OSM)"
	])
	var err = _postcode_request.request(POSTCODES_URL + compact, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_postcode_request.queue_free()
		_postcode_request = null
		_fetch_osm()

func _on_postcode_resolved(result: int, response_code: int, _headers, body: PackedByteArray):
	if _postcode_request:
		_postcode_request.queue_free()
		_postcode_request = null
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary:
			var postcode_result = parsed.get("result", {})
			if postcode_result is Dictionary:
				var lat = float(postcode_result.get("latitude", FALLBACK_LAT))
				var lon = float(postcode_result.get("longitude", FALLBACK_LON))
				if lat > 40.0 and lat < 65.0 and lon > -12.0 and lon < 5.0:
					center_lat = lat
					center_lon = lon
					resolved_postcode = str(postcode_result.get("postcode", START_POSTCODE))
	_fetch_osm()

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
	var query = '[out:json][timeout:15];(way[highway~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street|service|track)$"](%s);way[building](%s);way[barrier~"^(hedge|fence|wall)$"](%s);way[highway~"^(footway|path|cycleway)$"](%s);node[natural=tree](%s);node[highway~"^(traffic_signals|crossing|bus_stop)$"](%s););out tags geom qt;' % [bbox, bbox, bbox, bbox, bbox, bbox]
	var url = OVERPASS_URL + "?data=" + query.uri_encode()
	var headers = PackedStringArray([
		"Accept: application/json",
		"User-Agent: ProceedUntilApprehended/0.57 (Godot Android; postcode-seeded cached OSM geometry)"
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
	for element in elements:
		if not element is Dictionary:
			continue
		var tags = element.get("tags", {})
		if not tags is Dictionary:
			continue
		var element_type = str(element.get("type", ""))
		if element_type == "node":
			if point_features.size() >= MAX_POINT_FEATURES:
				continue
			var point_kind := ""
			if str(tags.get("natural", "")) == "tree":
				point_kind = "tree"
			else:
				var highway = str(tags.get("highway", ""))
				if highway in ["traffic_signals", "crossing", "bus_stop"]:
					point_kind = highway
			if point_kind != "" and element.has("lat") and element.has("lon"):
				var p = _lat_lon_to_local(float(element.get("lat", center_lat)), float(element.get("lon", center_lon)))
				point_features.append({
					"kind": point_kind,
					"point": [p.x, p.y],
					"name": str(tags.get("name", "")),
					"crossing": str(tags.get("crossing", ""))
				})
			continue

		var geometry = element.get("geometry", [])
		if not geometry is Array or geometry.size() < 2:
			continue
		var highway_kind = str(tags.get("highway", ""))
		if highway_kind in ["motorway", "trunk", "primary", "secondary", "tertiary", "residential", "unclassified", "living_street", "service", "track"] and roads.size() < MAX_ROADS:
			var points = _geometry_to_points(geometry, MIN_POINT_GAP_METERS)
			if points.size() >= 2:
				roads.append({
					"kind": highway_kind,
					"name": str(tags.get("name", "")),
					"width": _road_width_from_tags(tags),
					"lanes": int(str(tags.get("lanes", "0")).to_int()),
					"oneway": str(tags.get("oneway", "no")),
					"surface": str(tags.get("surface", "")),
					"sidewalk": str(tags.get("sidewalk", "")),
					"lit": str(tags.get("lit", "")),
					"maxspeed": str(tags.get("maxspeed", "")),
					"points": points
				})
		elif tags.has("building") and buildings.size() < MAX_BUILDINGS:
			var building = _building_from_geometry(tags, geometry)
			if not building.is_empty():
				buildings.append(building)
		elif linear_features.size() < MAX_LINEAR_FEATURES:
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
	data = {
		"source": "live",
		"start_postcode": resolved_postcode,
		"center_lat": center_lat,
		"center_lon": center_lon,
		"roads": roads,
		"buildings": buildings,
		"linear_features": linear_features,
		"point_features": point_features,
		"updated_unix": int(Time.get_unix_time_from_system())
	}
	_save_cache()
	map_ready.emit(data)

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

func _building_from_geometry(tags: Dictionary, geometry: Array) -> Dictionary:
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
		height = 5.0 + fmod(sx + sz, 7.0)
	height = clamp(height, 3.0, 48.0)
	if footprint.size() > 2 and footprint[0] == footprint[-1]:
		footprint.pop_back()
	return {
		"center": [(min_x + max_x) * 0.5, (min_z + max_z) * 0.5],
		"size": [sx, sz],
		"footprint": footprint,
		"height": height,
		"levels": levels,
		"kind": str(tags.get("building", "yes")),
		"material": str(tags.get("building:material", "")),
		"roof_shape": str(tags.get("roof:shape", "")),
		"roof_material": str(tags.get("roof:material", ""))
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
