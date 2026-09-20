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
	draw_rect(Rect2(24, 24, 110, 5), Color(0.0, 0.0, 0.0, 0.35))
	draw_rect(Rect2(24, 24, 110.0 * radio_strength, 5), Color(0.86, 0.52, 0.24, 0.72))
	if car.touching:
		draw_circle(car.touch_origin, 58.0, Color(1.0, 1.0, 1.0, 0.13), false, 3.0)
		draw_circle(car.touch_now, 22.0, Color(1.0, 1.0, 1.0, 0.28), false, 3.0)
