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
const VECTOR_MAP_SIZE := 228
const VECTOR_MAP_HALF_EXTENT_M := 240.0

var _map_stream: Node
var _request: HTTPRequest
var _root: Node3D
var _tile_queue: Array[Vector2i] = []
var _pending := Vector2i(-1, -1)
var _center_lat := 0.0
var _center_lon := 0.0
var _signature := ""
var _loaded_tile_count := 0
var _overlay_root: Control
var _overlay_map: TextureRect
var _overlay_marker: ColorRect
var _overlay_title: Label
var _overlay_street: Label
var _overlay_coords: Label
var _tile_textures := {}
var _overlay_tile := Vector2i(-1, -1)
var _packaged_overlay_texture: ImageTexture
var _packaged_overlay_road_count := 0
var _using_packaged_overlay := false
var _overlay_user_visible := true
var _location_clock := 0.0
var _last_postcode := "EH15 2BZ"

func _ready():
	_root = Node3D.new()
	_root.name = "OSMMapGround"
	add_child(_root)
	if OS.has_feature("pc_max") or OS.has_feature("projector_max"):
		_build_live_map_overlay()
	set_process(OS.has_feature("pc_max") or OS.has_feature("projector_max"))
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
	_last_postcode = str(map_data.get("start_postcode", _last_postcode))
	_build_packaged_vector_overlay(map_data)
	_on_location_ready(
		float(map_data.get("center_lat", 0.0)),
		float(map_data.get("center_lon", 0.0)),
		_last_postcode
	)
	_update_location_text(true)

func _on_location_ready(latitude: float, longitude: float, _postcode: String = ""):
	_center_lat = latitude
	_center_lon = longitude
	_last_postcode = _postcode if _postcode != "" else _last_postcode
	if _overlay_title:
		_overlay_title.text = "OSM · %s  [M]" % _last_postcode
	if abs(_center_lat) < 0.001 and abs(_center_lon) < 0.001:
		return
	# Android uses source-backed vector geometry plus terrain. Never place a flat
	# slippy-map plane into the 3D world: once the car descends below that fixed Y,
	# the two-sided raster becomes an enormous ceiling and can black out the sky.
	if OS.has_feature("mobile") or OS.get_environment("PUA_FORCE_MOBILE_TEST") == "1":
		_clear_tiles()
		var mobile_car = get_node_or_null("../Car")
		if mobile_car:
			mobile_car.set_meta("osm_ground_tiles_loaded", 0)
			mobile_car.set_meta("osm_ground_mode", "vector_terrain_only")
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
	_tile_textures.clear()
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
		"User-Agent: ProceedUntilApprehended/0.76 (personal Godot prototype; cached OSM context)"
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

	var tile_texture = ImageTexture.create_from_image(image)
	_tile_textures["%d:%d" % [tile.x, tile.y]] = tile_texture
	var material = StandardMaterial3D.new()
	material.albedo_texture = tile_texture
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


func _build_live_map_overlay():
	if _overlay_root != null:
		return
	var layer = CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_overlay_root = Control.new()
	_overlay_root.size = Vector2(252, 330)
	layer.add_child(_overlay_root)
	var back = ColorRect.new()
	back.size = _overlay_root.size
	back.color = Color(0.015, 0.02, 0.025, 0.88)
	_overlay_root.add_child(back)
	_overlay_title = Label.new()
	_overlay_title.position = Vector2(12, 8)
	_overlay_title.size = Vector2(228, 22)
	_overlay_title.text = "OSM · EH15 2BZ  [M]"
	_overlay_title.add_theme_font_size_override("font_size", 14)
	_overlay_root.add_child(_overlay_title)
	_overlay_map = TextureRect.new()
	_overlay_map.position = Vector2(12, 34)
	_overlay_map.size = Vector2(228, 228)
	_overlay_map.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay_root.add_child(_overlay_map)
	_overlay_marker = ColorRect.new()
	_overlay_marker.size = Vector2(8, 8)
	_overlay_marker.color = Color(1.0, 0.25, 0.12, 1.0)
	_overlay_root.add_child(_overlay_marker)
	_overlay_street = Label.new()
	_overlay_street.position = Vector2(12, 264)
	_overlay_street.size = Vector2(228, 20)
	_overlay_street.text = "NEAREST MAPPED ROAD"
	_overlay_street.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_overlay_street.add_theme_font_size_override("font_size", 13)
	_overlay_root.add_child(_overlay_street)
	_overlay_coords = Label.new()
	_overlay_coords.position = Vector2(12, 284)
	_overlay_coords.size = Vector2(228, 20)
	_overlay_coords.text = "POSTCODE CENTROID · NOT SURVEYED"
	_overlay_coords.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_overlay_coords.add_theme_font_size_override("font_size", 9)
	_overlay_root.add_child(_overlay_coords)
	var credit = Label.new()
	credit.position = Vector2(12, 307)
	credit.size = Vector2(228, 18)
	credit.text = "© OpenStreetMap contributors"
	credit.add_theme_font_size_override("font_size", 10)
	_overlay_root.add_child(credit)

func _build_packaged_vector_overlay(map_data: Dictionary):
	# Raster tiles are useful live context, but a projector must retain meaningful
	# geography on a cold offline start. Draw a north-up fallback from the exact
	# packaged OSM road polylines; live tiles replace it when they arrive.
	if _overlay_map == null:
		return
	var roads = map_data.get("roads", [])
	if not roads is Array or roads.is_empty():
		return
	var image = Image.create(VECTOR_MAP_SIZE, VECTOR_MAP_SIZE, false, Image.FORMAT_RGB8)
	image.fill(Color(0.025, 0.035, 0.040))
	_packaged_overlay_road_count = 0
	for road in roads:
		if not road is Dictionary:
			continue
		var points = road.get("points", [])
		if not points is Array or points.size() < 2:
			continue
		var kind = str(road.get("kind", ""))
		var major = kind in ["motorway", "trunk", "primary", "secondary", "tertiary"]
		var colour = Color(0.82, 0.72, 0.50) if major else Color(0.46, 0.53, 0.55)
		var thickness = 3 if major else 2
		for point_index in range(points.size() - 1):
			var a_raw = points[point_index]
			var b_raw = points[point_index + 1]
			if not a_raw is Array or not b_raw is Array or a_raw.size() < 2 or b_raw.size() < 2:
				continue
			var a = _local_to_vector_pixel(Vector2(float(a_raw[0]), float(a_raw[1])))
			var b = _local_to_vector_pixel(Vector2(float(b_raw[0]), float(b_raw[1])))
			_draw_vector_line(image, a, b, colour, thickness)
		_packaged_overlay_road_count += 1
	_packaged_overlay_texture = ImageTexture.create_from_image(image)
	_overlay_map.texture = _packaged_overlay_texture
	_using_packaged_overlay = true
	var car = get_node_or_null("../Car")
	if car:
		car.set_meta("osm_overlay_fallback_roads", _packaged_overlay_road_count)

func _local_to_vector_pixel(local: Vector2) -> Vector2i:
	var normalised = Vector2(
		0.5 + local.x / (VECTOR_MAP_HALF_EXTENT_M * 2.0),
		0.5 + local.y / (VECTOR_MAP_HALF_EXTENT_M * 2.0)
	)
	return Vector2i(roundi(normalised.x * (VECTOR_MAP_SIZE - 1)), roundi(normalised.y * (VECTOR_MAP_SIZE - 1)))

func _draw_vector_line(image: Image, from: Vector2i, to: Vector2i, colour: Color, thickness: int):
	# Integer interpolation is enough at 228 px and runs only when map data changes.
	# It avoids a second viewport or shader on low-spec projector builds.
	var delta = to - from
	var steps = maxi(abs(delta.x), abs(delta.y))
	if steps <= 0:
		return
	var radius = int(thickness / 2)
	for step in range(steps + 1):
		var t = float(step) / float(steps)
		var p = Vector2i(roundi(lerp(float(from.x), float(to.x), t)), roundi(lerp(float(from.y), float(to.y), t)))
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				var pixel = p + Vector2i(ox, oy)
				if pixel.x >= 0 and pixel.y >= 0 and pixel.x < image.get_width() and pixel.y < image.get_height():
					image.set_pixelv(pixel, colour)

func _unhandled_key_input(event):
	if event.pressed and not event.echo and event.keycode == KEY_M and _overlay_root:
		_overlay_user_visible = not _overlay_user_visible
		get_viewport().set_input_as_handled()

func _process(delta):
	if _overlay_root == null or _overlay_map == null:
		return
	var bay = get_node_or_null("../BayProjection")
	var calibrating = bay != null and int(bay.get("mode")) == 2
	_overlay_root.visible = _overlay_user_visible and not calibrating
	if not _overlay_root.visible:
		return
	var view_size = get_viewport().get_visible_rect().size
	_overlay_root.position = Vector2(max(8.0, view_size.x - _overlay_root.size.x - 14.0), 14.0)
	var car = get_node_or_null("../Car")
	if car == null or abs(_center_lat) < 0.001:
		return
	var meters_per_lon = 111320.0 * cos(deg_to_rad(_center_lat))
	var lat = _center_lat - car.global_position.z / 111320.0
	var lon = _center_lon + car.global_position.x / meters_per_lon
	_location_clock += delta
	if _location_clock >= 0.25:
		_location_clock = 0.0
		_update_location_text()
	var tile_float = _lat_lon_to_tile_float(lat, lon)
	var tile = Vector2i(int(floor(tile_float.x)), int(floor(tile_float.y)))
	var key = "%d:%d" % [tile.x, tile.y]
	if _tile_textures.has(key):
		if tile != _overlay_tile:
			_overlay_tile = tile
			_overlay_map.texture = _tile_textures[key]
		_using_packaged_overlay = false
	elif _packaged_overlay_texture != null:
		_overlay_tile = Vector2i(-1, -1)
		_overlay_map.texture = _packaged_overlay_texture
		_using_packaged_overlay = true
	if _overlay_tile == tile:
		var frac = Vector2(tile_float.x - floor(tile_float.x), tile_float.y - floor(tile_float.y))
		_overlay_marker.position = _overlay_map.position + frac * _overlay_map.size - _overlay_marker.size * 0.5
		_overlay_marker.visible = true
	else:
		if _using_packaged_overlay:
			var fallback_pixel = _local_to_vector_pixel(Vector2(car.global_position.x, car.global_position.z))
			_overlay_marker.position = _overlay_map.position + Vector2(fallback_pixel) - _overlay_marker.size * 0.5
			_overlay_marker.visible = fallback_pixel.x >= 0 and fallback_pixel.y >= 0 and fallback_pixel.x < VECTOR_MAP_SIZE and fallback_pixel.y < VECTOR_MAP_SIZE
		else:
			_overlay_marker.visible = false

func _update_location_text(force: bool = false):
	if not _overlay_street or not _overlay_coords or not _map_stream:
		return
	if not force and _location_clock > 0.0:
		return
	var car = get_node_or_null("../Car")
	if not car:
		return
	var local_position = Vector2(car.global_position.x, car.global_position.z)
	var nearest = _map_stream.nearest_named_road(local_position) if _map_stream.has_method("nearest_named_road") else {}
	if nearest.is_empty():
		_overlay_street.text = "NO NAMED OSM ROAD IN PATCH"
	else:
		var road_name = str(nearest.get("name", "")).to_upper()
		var road_ref = str(nearest.get("ref", "")).to_upper()
		if road_name == "":
			road_name = road_ref
		elif road_ref != "":
			road_name += " · " + road_ref
		_overlay_street.text = "%s · %.0f m" % [road_name, float(nearest.get("distance_m", 0.0))]
	var lat_lon = _map_stream.local_to_lat_lon(local_position) if _map_stream.has_method("local_to_lat_lon") else Vector2(_center_lat, _center_lon)
	var source_date = _map_stream.map_source_date() if _map_stream.has_method("map_source_date") else "OFFLINE"
	_overlay_coords.text = "%s · %.5f, %.5f" % [source_date, lat_lon.x, lat_lon.y]

func _lat_lon_to_tile_float(lat_deg: float, lon_deg: float) -> Vector2:
	var n = pow(2.0, float(TILE_ZOOM))
	var lat_rad = deg_to_rad(clamp(lat_deg, -85.05112878, 85.05112878))
	var x = (lon_deg + 180.0) / 360.0 * n
	var merc = log(tan(lat_rad) + 1.0 / cos(lat_rad))
	var y = (1.0 - merc / PI) * 0.5 * n
	return Vector2(x, y)
