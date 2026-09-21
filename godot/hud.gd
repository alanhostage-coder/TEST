extends Control

@onready var car = get_node("../Car")
@onready var parkview_credit = get_node_or_null("ParkviewCredit")
var credit_clock := 0.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta):
	credit_clock += delta
	if parkview_credit:
		var alpha = 1.0
		if credit_clock > 6.0:
			alpha = clamp(1.0 - (credit_clock - 6.0) / 2.0, 0.0, 1.0)
		parkview_credit.modulate.a = alpha
		parkview_credit.visible = alpha > 0.01
	queue_redraw()

func _draw():
	if car == null:
		return
	var radio_strength = float(car.get_meta("radio_signal", 0.0))
	var speed = abs(float(car.get("speed"))) * 3.6
	var road_state = "ROAD" if bool(car.get("on_road")) else "OFF-ROAD"
	var source = str(car.get_meta("map_data_source", "offline")).to_upper()
	var roads = int(car.get_meta("map_road_count", 0))
	var buildings = int(car.get_meta("map_building_count", 0))
	var font = ThemeDB.fallback_font
	var viewport_size = get_viewport_rect().size
	# Keep instruments clear of the bay calibration controls at the upper left.
	draw_set_transform(Vector2(viewport_size.x * 0.5 - 109.0, viewport_size.y - 154.0))
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
		draw_string(font, Vector2(viewport_size.x * 0.5 - 100, viewport_size.y - 119), "WEATHER: %s  [F6]" % str(weather.state.get("source", "offline")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.85, 0.7))
	if not OS.has_feature("mobile"):
		draw_string(font, Vector2(viewport_size.x * 0.5 - 210, viewport_size.y - 22), "WASD  DRIVE   SPACE  BRAKE   R  RECOVER   F11  FULLSCREEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.87, 0.87, 0.8))
	# Subtle sight marker keeps the eye aligned with the road at speed.
	var centre = viewport_size * 0.5
	draw_line(centre - Vector2(13, 0), centre - Vector2(4, 0), Color(1, 0.82, 0.55, 0.30), 1.0)
	draw_line(centre + Vector2(4, 0), centre + Vector2(13, 0), Color(1, 0.82, 0.55, 0.30), 1.0)
	draw_line(centre - Vector2(0, 13), centre - Vector2(0, 4), Color(1, 0.82, 0.55, 0.30), 1.0)
	draw_line(centre + Vector2(0, 4), centre + Vector2(0, 13), Color(1, 0.82, 0.55, 0.30), 1.0)
	draw_rect(Rect2(24, 24, 110, 5), Color(0.0, 0.0, 0.0, 0.35))
	draw_rect(Rect2(24, 24, 110.0 * radio_strength, 5), Color(0.86, 0.52, 0.24, 0.72))
	if car.touching:
		draw_circle(car.touch_origin, 58.0, Color(1.0, 1.0, 1.0, 0.13), false, 3.0)
		draw_circle(car.touch_now, 22.0, Color(1.0, 1.0, 1.0, 0.28), false, 3.0)
