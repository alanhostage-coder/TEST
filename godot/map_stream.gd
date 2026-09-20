extends Node

signal map_ready(data)

# Low-bandwidth OSM slice centred on Leith/Forth. Geometry is simplified locally
# and cached, so the live service is a seed rather than a runtime dependency.
const OVERPASS_URL := "https://overpass-api.de/api/interpreter"
const CACHE_PATH := "user://pua_map_stream.json"
const CACHE_MAX_AGE_SECONDS := 604800
const CENTER_LAT := 55.9777
const CENTER_LON := -3.1712
const HALF_LAT := 0.0060
const HALF_LON := 0.0100
const MIN_POINT_GAP_METERS := 14.0
const MAX_ROADS := 110
const MAX_BUILDINGS := 140

var data := {
	"source": "offline",
	"center_lat": CENTER_LAT,
	"center_lon": CENTER_LON,
	"roads": [],
	"buildings": [],
	"updated_unix": 0
}

var _request: HTTPRequest

func _ready():
	var cache_fresh = _load_cache()
	if data["roads"].size() > 0 or data["buildings"].size() > 0:
		map_ready.emit(data)
	if not cache_fresh:
		_fetch_osm()

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
	var south = CENTER_LAT - HALF_LAT
	var west = CENTER_LON - HALF_LON
	var north = CENTER_LAT + HALF_LAT
	var east = CENTER_LON + HALF_LON
	var bbox = "%.6f,%.6f,%.6f,%.6f" % [south, west, north, east]
	var query = "[out:json][timeout:15];(way[highway~\\\"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street|service|track)$\\\"](%s);way[building](%s););out tags geom qt;" % [bbox, bbox]
	var url = OVERPASS_URL + "?data=" + query.uri_encode()
	var headers = PackedStringArray([
		"Accept: application/json",
		"User-Agent: ProceedUntilApprehended/0.32 (Godot Android; cached OSM geometry)"
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
	for element in elements:
		if not element is Dictionary:
			continue
		var tags = element.get("tags", {})
		var geometry = element.get("geometry", [])
		if not tags is Dictionary or not geometry is Array or geometry.size() < 2:
			continue
		if tags.has("highway") and roads.size() < MAX_ROADS:
			var points = _geometry_to_points(geometry, MIN_POINT_GAP_METERS)
			if points.size() >= 2:
				roads.append({
					"kind": str(tags.get("highway", "road")),
					"name": str(tags.get("name", "")),
					"width": _road_width(str(tags.get("highway", ""))),
					"points": points
				})
		elif tags.has("building") and buildings.size() < MAX_BUILDINGS:
			var building = _building_from_geometry(tags, geometry)
			if not building.is_empty():
				buildings.append(building)
	data = {
		"source": "live",
		"center_lat": CENTER_LAT,
		"center_lon": CENTER_LON,
		"roads": roads,
		"buildings": buildings,
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
		var p = _lat_lon_to_local(float(entry.get("lat", CENTER_LAT)), float(entry.get("lon", CENTER_LON)))
		if points.is_empty() or last.distance_to(p) >= min_gap:
			points.append([p.x, p.y])
			last = p
	if geometry.size() > 1:
		var tail_entry = geometry[geometry.size() - 1]
		if tail_entry is Dictionary:
			var tail = _lat_lon_to_local(float(tail_entry.get("lat", CENTER_LAT)), float(tail_entry.get("lon", CENTER_LON)))
			if points.is_empty() or Vector2(float(points[-1][0]), float(points[-1][1])).distance_to(tail) > 2.0:
				points.append([tail.x, tail.y])
	return points

func _building_from_geometry(tags: Dictionary, geometry: Array) -> Dictionary:
	var min_x = INF
	var max_x = -INF
	var min_z = INF
	var max_z = -INF
	for entry in geometry:
		if not entry is Dictionary:
			continue
		var p = _lat_lon_to_local(float(entry.get("lat", CENTER_LAT)), float(entry.get("lon", CENTER_LON)))
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
	return {
		"center": [(min_x + max_x) * 0.5, (min_z + max_z) * 0.5],
		"size": [sx, sz],
		"height": height,
		"kind": str(tags.get("building", "yes"))
	}

func _lat_lon_to_local(lat: float, lon: float) -> Vector2:
	var meters_per_lon = 111320.0 * cos(deg_to_rad(CENTER_LAT))
	var x = (lon - CENTER_LON) * meters_per_lon
	var z = -(lat - CENTER_LAT) * 111320.0
	return Vector2(x, z)

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
