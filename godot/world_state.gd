extends Node

signal changed(state)

# Edinburgh/Forth defaults keep the simulation useful offline.
const WEATHER_URL := "https://api.open-meteo.com/v1/forecast?latitude=55.951507&longitude=-3.107122&current=temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m,wind_gusts_10m,visibility&daily=sunrise,sunset&timezone=Europe%2FLondon&forecast_days=1"
const MARINE_URL := "https://marine-api.open-meteo.com/v1/marine?latitude=56.00&longitude=-3.10&current=wave_height,wave_direction,wave_period,sea_surface_temperature&timezone=Europe%2FLondon"
const AIR_URL := "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=55.951507&longitude=-3.107122&current=pm10,pm2_5,nitrogen_dioxide,european_aqi&timezone=Europe%2FLondon"
const CACHE_PATH := "user://pua_world_state_eh15_v2.json"
const REFRESH_SECONDS := 900.0

var state := {
	"source": "offline",
	"temperature": 8.0,
	"humidity": 82.0,
	"rain": 0.0,
	"precipitation": 0.0,
	"cloud": 72.0,
	"wind_speed": 18.0,
	"wind_direction": 240.0,
	"wind_gusts": 30.0,
	"visibility": 12000.0,
	"weather_code": 3,
	"wave_height": 0.7,
	"wave_direction": 250.0,
	"wave_period": 4.5,
	"sea_temperature": 10.0,
	"pm10": 12.0,
	"pm2_5": 7.0,
	"no2": 18.0,
	"aqi": 28.0,
	"updated_unix": 0
}

var _requests := {}
var _refresh_clock := 0.0
var weather_mode := "LIVE"
var live_state: Dictionary = {}

func set_weather_mode(mode: String):
	if mode not in ["LIVE", "CLEAR", "RAIN", "FOG"]:
		return
	weather_mode = mode
	_publish_weather()

func _publish_weather():
	state = live_state.duplicate(true)
	if weather_mode != "LIVE":
		state["source"] = "manual " + weather_mode.to_lower()
		state["rain"] = 4.0 if weather_mode == "RAIN" else 0.0
		state["precipitation"] = state["rain"]
		state["cloud"] = 5.0 if weather_mode == "CLEAR" else 95.0
		state["visibility"] = 220.0 if weather_mode == "FOG" else 16000.0
		state["weather_code"] = 61 if weather_mode == "RAIN" else (45 if weather_mode == "FOG" else 0)
	changed.emit(state)

func _unhandled_key_input(event):
	if event.pressed and not event.echo and event.keycode == KEY_F6:
		var modes = ["LIVE", "CLEAR", "RAIN", "FOG"]
		set_weather_mode(modes[(modes.find(weather_mode) + 1) % modes.size()])

func _ready():
	_load_cache()
	live_state = state.duplicate(true)
	_fetch_all()

func _process(delta):
	_refresh_clock += delta
	if _refresh_clock >= REFRESH_SECONDS:
		_refresh_clock = 0.0
		_fetch_all()

func _fetch_all():
	_fetch("weather", WEATHER_URL)
	_fetch("marine", MARINE_URL)
	_fetch("air", AIR_URL)

func _fetch(kind: String, url: String):
	if _requests.has(kind):
		return
	var request = HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	_requests[kind] = request
	request.request_completed.connect(_on_request_completed.bind(kind, request))
	var err = request.request(url)
	if err != OK:
		_requests.erase(kind)
		request.queue_free()

func _on_request_completed(result: int, response_code: int, _headers, body: PackedByteArray, kind: String, request: HTTPRequest):
	_requests.erase(kind)
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var current = parsed.get("current", {})
	if not current is Dictionary:
		return
	state = live_state.duplicate(true)
	if kind == "weather":
		_apply_weather(current)
	elif kind == "marine":
		_apply_marine(current)
	elif kind == "air":
		_apply_air(current)
	if kind == "weather":
		state["source"] = "live"
		state["updated_unix"] = int(Time.get_unix_time_from_system())
	live_state = state.duplicate(true)
	_save_cache()
	_publish_weather()

func _apply_weather(c: Dictionary):
	state["temperature"] = float(c.get("temperature_2m", state["temperature"]))
	state["humidity"] = float(c.get("relative_humidity_2m", state["humidity"]))
	state["rain"] = float(c.get("rain", state["rain"]))
	state["precipitation"] = float(c.get("precipitation", state["precipitation"]))
	state["cloud"] = float(c.get("cloud_cover", state["cloud"]))
	state["wind_speed"] = float(c.get("wind_speed_10m", state["wind_speed"]))
	state["wind_direction"] = float(c.get("wind_direction_10m", state["wind_direction"]))
	state["wind_gusts"] = float(c.get("wind_gusts_10m", state["wind_gusts"]))
	state["visibility"] = float(c.get("visibility", state["visibility"]))
	state["weather_code"] = int(c.get("weather_code", state["weather_code"]))

func _apply_marine(c: Dictionary):
	state["wave_height"] = float(c.get("wave_height", state["wave_height"]))
	state["wave_direction"] = float(c.get("wave_direction", state["wave_direction"]))
	state["wave_period"] = float(c.get("wave_period", state["wave_period"]))
	state["sea_temperature"] = float(c.get("sea_surface_temperature", state["sea_temperature"]))

func _apply_air(c: Dictionary):
	state["pm10"] = float(c.get("pm10", state["pm10"]))
	state["pm2_5"] = float(c.get("pm2_5", state["pm2_5"]))
	state["no2"] = float(c.get("nitrogen_dioxide", state["no2"]))
	state["aqi"] = float(c.get("european_aqi", state["aqi"]))

func _save_cache():
	var file = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(state))

func _load_cache():
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var file = FileAccess.open(CACHE_PATH, FileAccess.READ)
	if not file:
		return
	var cached = JSON.parse_string(file.get_as_text())
	if cached is Dictionary:
		for key in state.keys():
			if cached.has(key):
				state[key] = cached[key]
		state["source"] = "cache"
