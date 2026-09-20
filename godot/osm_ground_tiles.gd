extends Node3D

# Recognisable geographic context beneath the procedural 3D world.
# OSM raster tiles are fetched serially, cached locally, and projected into the
# exact same local metre frame as MapStream's postcode-seeded geometry.
const TILE_URL := "https://tile.openstreetmap.org/%d/%d/%d.png"
const TILE_CACHE_DIR := "user://pua_osm_tiles"
const TILE_ZOOM := 16
const TILE_RADIUS_ANDROID := 2
const TILE_RADIUS_LOW_SPEC := 1
const TILE_Y := -0.028

var _map_stream: Node
var _request: HTTPRequest
var _root: Node3D
var _tile_queue: Array[Vector2i] = []
var _pending := Vector2i(-1, -1)
var _center_lat := 0.0
var _center_lon := 0.0
var _signature := ""
var _loaded_tile_count := 0

func _ready():
	_root = Node3D.new()
	_root.name = "OSMMapGround"
	add_child(_root)
	call_deferred("_bind_map_stream")

func _bind_map_stream():
	_map_stream = get_node_or_null("../MapStream")
	if not _map_stream:
		return
	if not _map_stream.map_ready.is_connected(_on_map_ready):
		_map_stream.map_ready.connect(_on_map_ready)
	if not _map_stream.location_ready.is_connected(_on_location_ready):
		_map_stream.location_ready.connect(_on_location_ready)
	var existing = _map_stream.get("data")
	if existing is Dictionary and (existing.get("roads", []).size() > 0 or existing.get("buildings", []).size() > 0):
		_on_map_ready(existing)

func _on_map_ready(map_data: Dictionary):
	_on_location_ready(
		float(map_data.get("center_lat", 0.0)),
		float(map_data.get("center_lon", 0.0)),
		str(map_data.get("start_postcode", ""))
	)

func _on_location_ready(latitude: float, longitude: float, _postcode: String = ""):
	_center_lat = latitude
	_center_lon = longitude
	if abs(_center_lat) < 0.001 and abs(_center_lon) < 0.001:
		return
	var sig = "%.6f:%.6f:%d" % [_center_lat, _center_lon, TILE_ZOOM]
	if sig == _signature:
		return
	_signature = sig
	_clear_tiles()
	_prepare_cache()
	_queue_context_tiles()
	# Start the recognisable map as soon as postcode coordinates resolve; do not
	# wait for the slower Overpass geometry request to finish first.
	if DisplayServer.get_name() != "headless":
		_fetch_next()
	var car = get_node_or_null("../Car")
	if car:
		car.set_meta("osm_ground_overlay", true)
		car.set_meta("osm_ground_source", "OpenStreetMap standard tiles")
		car.set_meta("osm_ground_zoom", TILE_ZOOM)
		car.set_meta("osm_ground_tiles_loaded", _loaded_tile_count)

func _clear_tiles():
	_tile_queue.clear()
	_pending = Vector2i(-1, -1)
	_loaded_tile_count = 0
	if _request and is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null
	for child in _root.get_children():
		child.queue_free()

func _prepare_cache():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TILE_CACHE_DIR))

func _queue_context_tiles():
	var centre = _lat_lon_to_tile(_center_lat, _center_lon)
	var radius = TILE_RADIUS_LOW_SPEC if OS.has_feature("thinkpad_low") else TILE_RADIUS_ANDROID
	# Centre first, then expand in square rings. A fresh install therefore gets
	# the postcode-centre street map before spending time on peripheral tiles.
	for ring in range(radius + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if max(abs(dx), abs(dy)) != ring:
					continue
				var tile = Vector2i(centre.x + dx, centre.y + dy)
				var path = _cache_path(tile)
				if FileAccess.file_exists(path):
					var image = Image.load_from_file(path)
					if image and not image.is_empty():
						_add_tile(tile, image)
						continue
				_tile_queue.append(tile)

func _fetch_next():
	if _request or _tile_queue.is_empty():
		return
	_pending = _tile_queue.pop_front()
	_request = HTTPRequest.new()
	_request.timeout = 12.0
	add_child(_request)
	_request.request_completed.connect(_on_tile_received)
	var headers = PackedStringArray([
		"Accept: image/png",
		"User-Agent: ProceedUntilApprehended/0.66 (personal Godot prototype; cached OSM context)"
	])
	var err = _request.request(TILE_URL % [TILE_ZOOM, _pending.x, _pending.y], headers, HTTPClient.METHOD_GET)
	if err != OK:
		_request.queue_free()
		_request = null
		_fetch_next()

func _on_tile_received(result: int, response_code: int, _headers, body: PackedByteArray):
	var tile = _pending
	if _request:
		_request.queue_free()
	_request = null
	_pending = Vector2i(-1, -1)
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300 and body.size() > 128:
		var image = Image.new()
		if image.load_png_from_buffer(body) == OK and not image.is_empty():
			var file = FileAccess.open(_cache_path(tile), FileAccess.WRITE)
			if file:
				file.store_buffer(body)
			_add_tile(tile, image)
	_fetch_next()

func _cache_path(tile: Vector2i) -> String:
	return "%s/%d_%d_%d.png" % [TILE_CACHE_DIR, TILE_ZOOM, tile.x, tile.y]

func _lat_lon_to_tile(lat_deg: float, lon_deg: float) -> Vector2i:
	var n = pow(2.0, float(TILE_ZOOM))
	var lat_rad = deg_to_rad(clamp(lat_deg, -85.05112878, 85.05112878))
	var x = int(floor((lon_deg + 180.0) / 360.0 * n))
	var merc = log(tan(lat_rad) + 1.0 / cos(lat_rad))
	var y = int(floor((1.0 - merc / PI) * 0.5 * n))
	return Vector2i(x, y)

func _tile_lon(x: int) -> float:
	var n = pow(2.0, float(TILE_ZOOM))
	return float(x) / n * 360.0 - 180.0

func _tile_lat(y: int) -> float:
	var n = pow(2.0, float(TILE_ZOOM))
	var merc = PI * (1.0 - 2.0 * float(y) / n)
	return rad_to_deg(atan(sinh(merc)))

func _lat_lon_to_local(lat: float, lon: float) -> Vector2:
	var meters_per_lon = 111320.0 * cos(deg_to_rad(_center_lat))
	return Vector2((lon - _center_lon) * meters_per_lon, -(lat - _center_lat) * 111320.0)

func _add_tile(tile: Vector2i, image: Image):
	var west = _tile_lon(tile.x)
	var east = _tile_lon(tile.x + 1)
	var north = _tile_lat(tile.y)
	var south = _tile_lat(tile.y + 1)
	var nw = _lat_lon_to_local(north, west)
	var ne = _lat_lon_to_local(north, east)
	var sw = _lat_lon_to_local(south, west)
	var se = _lat_lon_to_local(south, east)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(nw.x, TILE_Y, nw.y))
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(sw.x, TILE_Y, sw.y))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(ne.x, TILE_Y, ne.y))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(ne.x, TILE_Y, ne.y))
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(sw.x, TILE_Y, sw.y))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(se.x, TILE_Y, se.y))
	st.generate_normals()
	var mesh = st.commit()
	if mesh == null:
		return

	var material = StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.albedo_color = Color(0.38, 0.40, 0.38, 1.0)
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var instance = MeshInstance3D.new()
	instance.name = "OSMTile_%d_%d" % [tile.x, tile.y]
	instance.mesh = mesh
	instance.material_override = material
	instance.visibility_range_end = 1200.0
	_root.add_child(instance)
	_loaded_tile_count += 1
	var car = get_node_or_null("../Car")
	if car:
		car.set_meta("osm_ground_tiles_loaded", _loaded_tile_count)
