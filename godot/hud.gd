extends Control

@onready var car = get_node("../Car")
@onready var parkview_credit = get_node_or_null("ParkviewCredit")
@onready var map_credit = get_node_or_null("MapCredit")
@onready var human_credit = get_node_or_null("HumanCredit")
var credit_clock := 0.0
const HUD_Z_INDEX := 20
const DEFAULT_CREDIT_HOLD_SECONDS := 6.0
const DEFAULT_CREDIT_FADE_SECONDS := 2.0
const PROJECTOR_CREDIT_HOLD_SECONDS := 2.5
const PROJECTOR_CREDIT_FADE_SECONDS := 0.75
const FRAME_SAMPLE_CAPACITY := 120
const HITCH_THRESHOLD_MS := 33.333
var frame_samples := PackedFloat32Array()
var frame_sample_index := 0
var frame_sample_count := 0
var frame_stats_clock := 0.0
var average_frame_ms := 0.0
var p95_frame_ms := 0.0
var worst_frame_ms := 0.0
var frame_hitch_count := 0
var performance_visible := false

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The instruments are painted onto the cockpit, so they must sit above its
	# z=12/14 dash and wheel while remaining below the z=40 calibration controls.
	z_index = HUD_Z_INDEX
	_reset_frame_stats()

func _process(delta: float):
	var unscaled_delta: float = delta / maxf(Engine.time_scale, 0.001)
	_record_frame_time_ms(unscaled_delta * 1000.0)
	frame_stats_clock += unscaled_delta
	if frame_stats_clock >= 0.5:
		frame_stats_clock = fmod(frame_stats_clock, 0.5)
		_refresh_frame_stats()
	var calibration_active := _projector_calibration_active()
	if map_credit:
		map_credit.visible = not calibration_active
	if human_credit:
		human_credit.visible = not calibration_active
	_update_parkview_credit(delta)
	queue_redraw()

func _driver_focus_rect(viewport_size: Vector2) -> Rect2:
	var fallback := Rect2(Vector2.ZERO, viewport_size)
	var bay = get_node_or_null("../BayProjection")
	if bay == null or int(bay.mode) != 1 or int(bay.layout_surface_count) < 3 or bay.surfaces.size() < 2:
		return fallback
	var forward_quad: PackedVector2Array = bay.surfaces[1].polygon
	if forward_quad.size() != 4:
		return fallback
	var minimum := forward_quad[0]
	var maximum := forward_quad[0]
	for point in forward_quad:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	if maximum.x - minimum.x < 2.0 or maximum.y - minimum.y < 2.0:
		return fallback
	return Rect2(minimum, maximum - minimum)

func _projector_driving_view_active() -> bool:
	var bay = get_node_or_null("../BayProjection")
	return bay != null and int(bay.mode) == 1

func _projector_calibration_active() -> bool:
	var bay = get_node_or_null("../BayProjection")
	return bay != null and int(bay.mode) == 2

func _credit_hold_seconds() -> float:
	return PROJECTOR_CREDIT_HOLD_SECONDS if _projector_driving_view_active() else DEFAULT_CREDIT_HOLD_SECONDS

func _credit_fade_seconds() -> float:
	return PROJECTOR_CREDIT_FADE_SECONDS if _projector_driving_view_active() else DEFAULT_CREDIT_FADE_SECONDS

func _update_parkview_credit(delta: float):
	if parkview_credit == null:
		return
	if _projector_calibration_active():
		parkview_credit.visible = false
		return
	credit_clock += delta / maxf(Engine.time_scale, 0.001)
	var viewport_size := get_viewport_rect().size
	var focus_rect := _driver_focus_rect(viewport_size)
	var credit_width := minf(440.0, maxf(260.0, focus_rect.size.x - 40.0))
	parkview_credit.anchor_left = 0.0
	parkview_credit.anchor_right = 0.0
	parkview_credit.anchor_top = 0.0
	parkview_credit.anchor_bottom = 0.0
	parkview_credit.position = Vector2(
		focus_rect.position.x + (focus_rect.size.x - credit_width) * 0.5,
		maxf(14.0, focus_rect.position.y + 18.0)
	)
	parkview_credit.size = Vector2(credit_width, 86.0)
	var hold_seconds := _credit_hold_seconds()
	var alpha := 1.0
	if credit_clock > hold_seconds:
		alpha = clampf(1.0 - (credit_clock - hold_seconds) / _credit_fade_seconds(), 0.0, 1.0)
	parkview_credit.modulate.a = alpha
	parkview_credit.visible = alpha > 0.01

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_toggle_performance_overlay()
		get_viewport().set_input_as_handled()

func _toggle_performance_overlay():
	performance_visible = not performance_visible
	if performance_visible:
		_refresh_frame_stats()
	queue_redraw()

func _reset_frame_stats():
	frame_samples = PackedFloat32Array()
	frame_samples.resize(FRAME_SAMPLE_CAPACITY)
	frame_sample_index = 0
	frame_sample_count = 0
	frame_stats_clock = 0.0
	average_frame_ms = 0.0
	p95_frame_ms = 0.0
	worst_frame_ms = 0.0
	frame_hitch_count = 0

func _record_frame_time_ms(frame_ms: float):
	frame_samples[frame_sample_index] = clampf(frame_ms, 0.0, 1000.0)
	frame_sample_index = (frame_sample_index + 1) % FRAME_SAMPLE_CAPACITY
	frame_sample_count = mini(frame_sample_count + 1, FRAME_SAMPLE_CAPACITY)

func _refresh_frame_stats():
	if frame_sample_count <= 0:
		return
	var sorted := PackedFloat32Array()
	var total := 0.0
	frame_hitch_count = 0
	for i in range(frame_sample_count):
		var frame_ms := float(frame_samples[i])
		sorted.append(frame_ms)
		total += frame_ms
		if frame_ms > HITCH_THRESHOLD_MS:
			frame_hitch_count += 1
	sorted.sort()
	average_frame_ms = total / float(frame_sample_count)
	var p95_index := clampi(int(ceil(float(frame_sample_count) * 0.95)) - 1, 0, frame_sample_count - 1)
	p95_frame_ms = float(sorted[p95_index])
	worst_frame_ms = float(sorted[frame_sample_count - 1])

func _draw():
	if car == null or _projector_calibration_active():
		return
	var radio_strength = float(car.get_meta("radio_signal", 0.0))
	var speed = abs(float(car.get("speed"))) * 3.6
	var road_state = "ROAD" if bool(car.get("on_road")) else "OFF-ROAD"
	var source = str(car.get_meta("map_data_source", "offline")).to_upper()
	var roads = int(car.get_meta("map_road_count", 0))
	var buildings = int(car.get_meta("map_building_count", 0))
	var font = ThemeDB.fallback_font
	var viewport_size = get_viewport_rect().size
	var focus_rect := _driver_focus_rect(viewport_size)
	var focus_x := focus_rect.position.x + focus_rect.size.x * 0.5
	# Keep instruments clear of the bay calibration controls at the upper left.
	draw_set_transform(Vector2(focus_x - 109.0, viewport_size.y - 154.0))
	# A restrained instrument layer gives the driving view a readable centre of gravity
	# without covering the mapped scene. It scales from the PC projector canvas down to
	# the mobile viewport automatically.
	draw_rect(Rect2(22, 42, 174, 72), Color(0.015, 0.020, 0.024, 0.68), true)
	draw_line(Vector2(22, 42), Vector2(196, 42), Color(0.88, 0.49, 0.20, 0.82), 2.0)
	draw_string(font, Vector2(34, 72), "%03d" % int(speed), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.94, 0.91, 0.82, 0.96))
	draw_string(font, Vector2(105, 70), "KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.88, 0.49, 0.20, 0.90))
	draw_string(font, Vector2(34, 96), "%s  ·  %s" % [road_state, source], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.74, 0.78, 0.76, 0.82))
	draw_string(font, Vector2(34, 106), "%d ROADS  %d BUILDINGS" % [roads, buildings], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.62, 0.62, 0.75))
	draw_set_transform(Vector2.ZERO)
	var weather = get_node_or_null("../WorldState")
	if weather:
		draw_string(font, Vector2(focus_x - 100.0, viewport_size.y - 119), "WEATHER: %s  [F6]" % str(weather.state.get("source", "offline")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.85, 0.7))
	if not OS.has_feature("mobile"):
		var map_control = "   M  MAP" if OS.has_feature("pc_max") or OS.has_feature("projector_max") else ""
		draw_string(font, Vector2(viewport_size.x * 0.5 - 300, viewport_size.y - 22), "WASD  DRIVE   SPACE  BRAKE   R  RECOVER%s   F8  FRAME   F11  FULLSCREEN" % map_control, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.87, 0.87, 0.8))
	if performance_visible and frame_sample_count > 0:
		var panel_position := Vector2(viewport_size.x - 270.0, viewport_size.y - 112.0)
		var status := "60 FPS RANGE"
		var status_colour := Color(0.50, 0.86, 0.62, 0.94)
		if p95_frame_ms > 25.0:
			status = "HITCHING"
			status_colour = Color(1.0, 0.42, 0.30, 0.96)
		elif p95_frame_ms > 18.5:
			status = "FRAME PRESSURE"
			status_colour = Color(1.0, 0.72, 0.28, 0.96)
		draw_rect(Rect2(panel_position, Vector2(248, 64)), Color(0.010, 0.014, 0.018, 0.82), true)
		draw_line(panel_position, panel_position + Vector2(248, 0), status_colour, 2.0)
		draw_string(font, panel_position + Vector2(12, 23), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, status_colour)
		draw_string(font, panel_position + Vector2(12, 42), "AVG %.1f ms   P95 %.1f ms   MAX %.1f ms" % [average_frame_ms, p95_frame_ms, worst_frame_ms], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.88, 0.90, 0.88, 0.90))
		draw_string(font, panel_position + Vector2(12, 56), "%d FPS   %d HITCHES / %d FRAMES" % [int(round(1000.0 / maxf(average_frame_ms, 0.001))), frame_hitch_count, frame_sample_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.64, 0.70, 0.70, 0.84))
	# Subtle sight marker keeps the eye aligned with the road at speed.
	var centre := Vector2(focus_x, viewport_size.y * 0.5)
	draw_line(centre - Vector2(13, 0), centre - Vector2(4, 0), Color(1, 0.82, 0.55, 0.30), 1.0)
	draw_line(centre + Vector2(4, 0), centre + Vector2(13, 0), Color(1, 0.82, 0.55, 0.30), 1.0)
	draw_line(centre - Vector2(0, 13), centre - Vector2(0, 4), Color(1, 0.82, 0.55, 0.30), 1.0)
	draw_line(centre + Vector2(0, 4), centre + Vector2(0, 13), Color(1, 0.82, 0.55, 0.30), 1.0)
	draw_rect(Rect2(24, 24, 110, 5), Color(0.0, 0.0, 0.0, 0.35))
	draw_rect(Rect2(24, 24, 110.0 * radio_strength, 5), Color(0.86, 0.52, 0.24, 0.72))
	if car.touching:
		draw_circle(car.touch_origin, 58.0, Color(1.0, 1.0, 1.0, 0.13), false, 3.0)
		draw_circle(car.touch_now, 22.0, Color(1.0, 1.0, 1.0, 0.28), false, 3.0)
