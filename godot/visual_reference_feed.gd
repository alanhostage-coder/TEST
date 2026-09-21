extends Node

signal references_changed(references)

# Public-photo evidence layer for recognisable-place work. It records nearby
# geotagged Wikimedia Commons files and their licence metadata; it does not claim
# those images are geometry and does not automatically turn them into splats.
const COMMONS_API := "https://commons.wikimedia.org/w/api.php"
const CACHE_PATH := "user://pua_commons_references.json"
const REFRESH_SECONDS := 21600.0
const SEARCH_RADIUS_M := 1000
const MAX_RESULTS := 12

var references: Array = []
var _request: HTTPRequest
var _refresh_clock := 0.0
var _lat := 55.951507
var _lon := -3.107122

func _ready():
	_load_cache()
	call_deferred("_bind_map_stream")

func _process(delta):
	_refresh_clock += delta
	if _refresh_clock >= REFRESH_SECONDS:
		_refresh_clock = 0.0
		_fetch()

func _bind_map_stream():
	var map_stream = get_node_or_null("../MapStream")
	if not map_stream:
		return
	if map_stream.has_signal("location_ready"):
		map_stream.location_ready.connect(_on_location_ready)
	_lat = float(map_stream.get("center_lat"))
	_lon = float(map_stream.get("center_lon"))
	if DisplayServer.get_name() != "headless":
		_fetch()

func _on_location_ready(latitude: float, longitude: float, _postcode: String):
	_lat = latitude
	_lon = longitude
	if DisplayServer.get_name() != "headless":
		_fetch()

func _fetch():
	if _request:
		return
	_request = HTTPRequest.new()
	_request.timeout = 10.0
	add_child(_request)
	_request.request_completed.connect(_on_completed)
	var coord = ("%.6f|%.6f" % [_lat, _lon]).uri_encode()
	var url = COMMONS_API + "?action=query&format=json&generator=geosearch&ggsprimary=all&ggsnamespace=6&ggsradius=%d&ggscoord=%s&ggslimit=%d&prop=coordinates%%7Cimageinfo&iiprop=url%%7Cextmetadata" % [SEARCH_RADIUS_M, coord, MAX_RESULTS]
	var headers = PackedStringArray(["User-Agent: ProceedUntilApprehended/0.76 (Wikimedia Commons reference metadata)"])
	var err = _request.request(url, headers)
	if err != OK:
		_request.queue_free()
		_request = null

func _on_completed(result: int, response_code: int, _headers, body: PackedByteArray):
	if _request:
		_request.queue_free()
		_request = null
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var query = parsed.get("query", {})
	if not query is Dictionary:
		return
	var pages = query.get("pages", {})
	if not pages is Dictionary:
		return
	var next_refs: Array = []
	for page in pages.values():
		if not page is Dictionary:
			continue
		var info_list = page.get("imageinfo", [])
		if not info_list is Array or info_list.is_empty() or not info_list[0] is Dictionary:
			continue
		var info: Dictionary = info_list[0]
		var ext = info.get("extmetadata", {})
		if not ext is Dictionary:
			ext = {}
		var coords = page.get("coordinates", [])
		var lat = _lat
		var lon = _lon
		if coords is Array and not coords.is_empty() and coords[0] is Dictionary:
			lat = float(coords[0].get("lat", lat))
			lon = float(coords[0].get("lon", lon))
		next_refs.append({
			"title": str(page.get("title", "")),
			"url": str(info.get("descriptionurl", info.get("url", ""))),
			"image_url": str(info.get("url", "")),
			"lat": lat,
			"lon": lon,
			"artist": _meta_value(ext, "Artist"),
			"licence": _meta_value(ext, "LicenseShortName"),
			"licence_url": _meta_value(ext, "LicenseUrl"),
			"credit": _meta_value(ext, "Credit"),
			"date": _meta_value(ext, "DateTimeOriginal"),
			"source_provider": "Wikimedia Commons",
			"use": "visual_reference_only_until_alignment_and_rights_verified"
		})
	references = next_refs
	_save_cache()
	references_changed.emit(references)

func _meta_value(ext: Dictionary, key: String) -> String:
	var item = ext.get(key, {})
	if item is Dictionary:
		return str(item.get("value", "")).strip_edges()
	return ""

func _save_cache():
	var f = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"references": references, "updated_unix": int(Time.get_unix_time_from_system())}))

func _load_cache():
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var f = FileAccess.open(CACHE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and parsed.get("references", []) is Array:
		references = parsed.get("references", [])
