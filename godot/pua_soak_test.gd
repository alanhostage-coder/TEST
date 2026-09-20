extends Node

var world: Node
var elapsed := 0.0
var start_position := Vector3.ZERO
var failed := false

func _ready():
	Engine.time_scale = 2.0
	var packed = load("res://world.tscn")
	if packed == null:
		_fail("world scene missing")
		return
	world = packed.instantiate()
	add_child(world)
	var car = world.get_node_or_null("Car")
	if car == null:
		_fail("car missing")
		return
	start_position = car.global_position
	Input.action_press("throttle")

func _process(delta):
	if failed or world == null:
		return
	elapsed += delta
	if elapsed > 3.0:
		Input.action_release("throttle")
	if elapsed >= 8.0:
		_finish()

func _finish():
	var api = world.get_node_or_null("PUAAPI")
	var car = world.get_node_or_null("Car")
	if api == null:
		_fail("PUAAPI missing")
		return
	if car == null:
		_fail("car missing at finish")
		return
	if not api.has_method("get_snapshot") or not api.has_method("get_directive"):
		_fail("PUAAPI contract missing")
		return
	var snapshot = api.get_snapshot()
	var directive = api.get_directive()
	if not snapshot is Dictionary or snapshot.is_empty():
		_fail("PUAAPI snapshot empty")
		return
	for key in ["world_seed", "traffic_factor", "traffic_speed_factor", "lamp_factor", "surface_wetness"]:
		if not directive.has(key):
			_fail("directive missing " + key)
			return
	var moved = start_position.distance_to(car.global_position)
	print("PUA_SOAK_OK moved=%.2f traffic=%.2f lamps=%.2f moment=%s sources=%s" % [
		moved,
		float(directive.get("traffic_factor", 0.0)),
		float(directive.get("lamp_factor", 0.0)),
		str(directive.get("moment", "none")),
		JSON.stringify(snapshot.get("sources", {}))
	])
	get_tree().quit(0)

func _fail(reason: String):
	failed = true
	Input.action_release("throttle")
	push_error("PUA_SOAK_FAIL " + reason)
	get_tree().quit(2)
