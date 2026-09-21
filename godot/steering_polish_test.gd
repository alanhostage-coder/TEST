extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world = load("res://world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var car = world.get_node("Car")
	car.set_physics_process(false)
	car.speed = 0.0
	car.steering_velocity = 0.0
	car.steer_smoothed = 0.0
	car._apply_steering_input(1.0, 0.1)
	var low_speed_step: float = car.steering_velocity
	car.speed = car.max_speed
	car.steering_velocity = 0.0
	car.steer_smoothed = 0.0
	car._apply_steering_input(1.0, 0.1)
	var high_speed_step: float = car.steering_velocity
	assert(low_speed_step > high_speed_step, "low-speed steering must remain more responsive")
	assert(high_speed_step > 0.25 and high_speed_step < 0.40, "high-speed slew left its stable range")
	car.steering_velocity = -1.0
	car.steer_smoothed = -1.0
	car._apply_steering_input(1.0, 0.1)
	assert(car.steering_velocity < 0.0, "full steering reversal must not cross centre in one high-speed frame")
	car.recover_to_road()
	assert(is_zero_approx(car.steering_velocity) and is_zero_approx(car.steer_smoothed), "recovery must clear steering memory")
	print("PUA_STEERING_POLISH_OK low=%.2f high=%.2f" % [low_speed_step, high_speed_step])
	quit(0)
