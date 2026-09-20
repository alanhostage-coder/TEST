extends Node

signal changed(snapshot)
signal directive_changed(directive)
signal moment_started(moment)

# PUA API is the internal contract between the outside world and the simulation.
# External feeds are treated as seeds. The game caches them, derives stable
# directives, and continues to function when every network request fails.
const CACHE_PATH := "user://pua_api_state.json"
const RECOMPUTE_SECONDS := 8.0
const SAVE_SECONDS := 20.0
const MIN_MOMENT_SECONDS := 35.0
const MAX_MOMENT_SECONDS := 85.0

var snapshot: Dictionary = {}
var directive: Dictionary = {
	"world_seed": 1,
	"traffic_factor": 0.85,
	"traffic_speed_factor": 0.95,
	"lamp_factor": 1.0,
	"detail_pressure": 0.70,
	"radio_instability": 0.20,
	"surface_wetness": 0.0,
	"visibility_factor": 0.75,
	"moment": "none"
}
var session: Dictionary = {
	"launches": 0,
	"total_runtime_seconds": 0.0,
	"distance_observed": 0.0,
	"last_position": [0.0, 0.0, 0.0],
	"last_moment": "none",
	"moments_seen": 0
}

var _world_state: Node
var _map_stream: Node
var _car: Node3D
var _recompute_clock := 0.0
var _save_clock := 0.0
var _moment_clock := 0.0
var _moment_duration := 0.0
var _active_moment := "none"
var _active_moment_strength := 0.0
var _last_car_position := Vector3.ZERO

func _ready():
	_load_cache()
	session["launches"] = int(session.get("launches", 0)) + 1
	call_deferred("_bind_sources")
	_schedule_next_moment()

func _exit_tree():
	_capture_car()
	_save_cache()

func _bind_sources():
	_world_state = get_node_or_null("../WorldState")
	_map_stream = get_node_or_null("../MapStream")
	_car = get_node_or_null("../Car")
	if _world_state and _world_state.has_signal("changed"):
		_world_state.changed.connect(_on_external_change)
	if _map_stream and _map_stream.has_signal("map_ready"):
		_map_stream.map_ready.connect(_on_external_change)
	if _car:
		_last_car_position = _car.global_position
	_recompute()

func _process(delta):
	session["total_runtime_seconds"] = float(session.get("total_runtime_seconds", 0.0)) + delta
	_recompute_clock += delta
	_save_clock += delta
	_moment_clock += delta
	_capture_car()

	if _active_moment != "none":
		_moment_duration -= delta
		if _moment_duration <= 0.0:
			_active_moment = "none"
			_active_moment_strength = 0.0
			_schedule_next_moment()
			_recompute()
	elif _moment_clock >= float(session.get("next_moment_after", 55.0)):
		_start_moment()

	if _recompute_clock >= RECOMPUTE_SECONDS:
		_recompute_clock = 0.0
		_recompute()
	if _save_clock >= SAVE_SECONDS:
		_save_clock = 0.0
		_save_cache()

func _capture_car():
	if not _car:
		return
	var p = _car.global_position
	if _last_car_position != Vector3.ZERO:
		var step = _last_car_position.distance_to(p)
		if step < 150.0:
			session["distance_observed"] = float(session.get("distance_observed", 0.0)) + step
	_last_car_position = p
	session["last_position"] = [p.x, p.y, p.z]

func _on_external_change(_payload = null):
	_recompute()

func _recompute():
	var weather: Dictionary = {}
	var map_data: Dictionary = {}
	if _world_state:
		var weather_value = _world_state.get("state")
		if weather_value is Dictionary:
			weather = weather_value.duplicate(true)
	if _map_stream:
		var map_value = _map_stream.get("data")
		if map_value is Dictionary:
			map_data = map_value.duplicate(true)

	var now = Time.get_datetime_dict_from_system()
	var hour = int(now.get("hour", 12))
	var day_key = "%04d-%02d-%02d" % [int(now.get("year", 2026)), int(now.get("month", 1)), int(now.get("day", 1))]
	var rain = clamp(float(weather.get("rain", 0.0)) + float(weather.get("precipitation", 0.0)), 0.0, 8.0)
	var wetness = clamp(rain / 2.5, 0.0, 1.0)
	var cloud = clamp(float(weather.get("cloud", 65.0)) / 100.0, 0.0, 1.0)
	var wind = max(0.0, float(weather.get("wind_speed", 12.0)))
	var visibility = clamp(float(weather.get("visibility", 12000.0)) / 22000.0, 0.08, 1.0)
	var aqi = clamp(float(weather.get("aqi", 25.0)) / 100.0, 0.0, 1.0)
	var road_count = int(map_data.get("roads", []).size())
	var building_count = int(map_data.get("buildings", []).size())
	var centre = "%s:%s" % [str(map_data.get("center_lat", "55.97")), str(map_data.get("center_lon", "-3.17"))]
	var seed_text = "%s:%s:%s" % [centre, day_key, str(int(weather.get("weather_code", 3)))]
	var world_seed = abs(hash(seed_text))

	var commute = 0.0
	if hour >= 7 and hour <= 9:
		commute = 0.34
	elif hour >= 16 and hour <= 18:
		commute = 0.42
	elif hour >= 22 or hour <= 5:
		commute = -0.28
	var traffic_factor = clamp(0.78 + commute - wetness * 0.16, 0.34, 1.35)
	var speed_factor = clamp(1.02 - wetness * 0.20 - min(wind / 120.0, 0.12), 0.70, 1.08)
	var lamp_factor = 1.0
	if hour >= 18 or hour <= 7:
		lamp_factor = 1.45
	else:
		lamp_factor = 0.62 + cloud * 0.42
	var radio_instability = clamp(0.12 + wind / 95.0 + wetness * 0.28, 0.08, 0.92)
	var detail_pressure = clamp(0.55 + min(float(building_count) / 220.0, 0.35) + (1.0 - visibility) * 0.12, 0.45, 1.0)

	if _active_moment == "traffic_wave":
		traffic_factor = min(1.45, traffic_factor + 0.34 * _active_moment_strength)
	elif _active_moment == "quiet_patch":
		traffic_factor = max(0.26, traffic_factor - 0.44 * _active_moment_strength)
	elif _active_moment == "sodium_bloom":
		lamp_factor += 0.55 * _active_moment_strength
	elif _active_moment == "radio_bleed":
		radio_instability = min(1.0, radio_instability + 0.52 * _active_moment_strength)

	var new_directive = {
		"world_seed": world_seed,
		"traffic_factor": traffic_factor,
		"traffic_speed_factor": speed_factor,
		"lamp_factor": lamp_factor,
		"detail_pressure": detail_pressure,
		"radio_instability": radio_instability,
		"surface_wetness": wetness,
		"visibility_factor": visibility,
		"moment": _active_moment,
		"moment_strength": _active_moment_strength
	}

	var sources = {
		"weather": str(weather.get("source", "offline")),
		"map": str(map_data.get("source", "offline"))
	}
	snapshot = {
		"api": "PUA API 0.1",
		"updated_unix": int(Time.get_unix_time_from_system()),
		"sources": sources,
		"world": {
			"day_key": day_key,
			"hour": hour,
			"weather_code": int(weather.get("weather_code", 3)),
			"temperature": float(weather.get("temperature", 8.0)),
			"wind_speed": wind,
			"cloud": cloud,
			"aqi_ratio": aqi,
			"roads": road_count,
			"buildings": building_count
		},
		"directive": new_directive,
		"session": session.duplicate(true)
	}

	var changed_directive = JSON.stringify(new_directive) != JSON.stringify(directive)
	directive = new_directive
	changed.emit(snapshot)
	if changed_directive:
		directive_changed.emit(directive)

func _schedule_next_moment():
	_moment_clock = 0.0
	var base_seed = abs(int(directive.get("world_seed", 1))) + int(session.get("moments_seen", 0)) * 7919
	var span = MAX_MOMENT_SECONDS - MIN_MOMENT_SECONDS
	session["next_moment_after"] = MIN_MOMENT_SECONDS + float(base_seed % int(span + 1.0))

func _start_moment():
	var seed = abs(int(directive.get("world_seed", 1))) + int(session.get("moments_seen", 0)) * 3571
	var candidates = ["traffic_wave", "quiet_patch", "sodium_bloom", "radio_bleed"]
	_active_moment = candidates[seed % candidates.size()]
	_active_moment_strength = 0.55 + float((seed / 11) as int % 40) / 100.0
	_moment_duration = 18.0 + float((seed / 23) as int % 28)
	session["moments_seen"] = int(session.get("moments_seen", 0)) + 1
	session["last_moment"] = _active_moment
	_moment_clock = 0.0
	var event = {
		"type": _active_moment,
		"strength": _active_moment_strength,
		"duration": _moment_duration,
		"world_seed": int(directive.get("world_seed", 1))
	}
	moment_started.emit(event)
	_recompute()

func get_snapshot() -> Dictionary:
	return snapshot.duplicate(true)

func get_directive() -> Dictionary:
	return directive.duplicate(true)

func _save_cache():
	var payload = {
		"session": session,
		"directive": directive,
		"snapshot": snapshot
	}
	var file = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(payload))

func _load_cache():
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var file = FileAccess.open(CACHE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var saved_session = parsed.get("session", {})
	if saved_session is Dictionary:
		for key in saved_session.keys():
			session[key] = saved_session[key]
	var saved_directive = parsed.get("directive", {})
	if saved_directive is Dictionary:
		for key in saved_directive.keys():
			directive[key] = saved_directive[key]
