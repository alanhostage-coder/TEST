extends Control

@onready var car = get_node("../Car")

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta):
	queue_redraw()

func _draw():
	if car == null:
		return
	var radio_strength = float(car.get_meta("radio_signal", 0.0))
	draw_rect(Rect2(24, 24, 110, 5), Color(0.0, 0.0, 0.0, 0.35))
	draw_rect(Rect2(24, 24, 110.0 * radio_strength, 5), Color(0.86, 0.52, 0.24, 0.72))
	if car.touching:
		draw_circle(car.touch_origin, 58.0, Color(1.0, 1.0, 1.0, 0.13), false, 3.0)
		draw_circle(car.touch_now, 22.0, Color(1.0, 1.0, 1.0, 0.28), false, 3.0)
