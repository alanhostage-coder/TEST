extends CharacterBody3D

@export var acceleration := 16.0
@export var reverse_acceleration := 8.0
@export var drag := 5.5
@export var max_speed := 31.0
@export var steer_rate := 1.55
var speed := 0.0
var steer_smoothed := 0.0

func _physics_process(delta):
	var throttle = Input.get_action_strength("throttle") - Input.get_action_strength("brake")
	var steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	steer_smoothed = move_toward(steer_smoothed, steer, delta * 3.2)
	if abs(throttle) > 0.01:
		speed = move_toward(speed, (max_speed if throttle > 0 else -max_speed * 0.34), delta * (acceleration if throttle > 0 else reverse_acceleration))
	else:
		speed = move_toward(speed, 0.0, delta * drag)
	var steer_authority = clamp(abs(speed) / 7.0, 0.18, 1.0)
	rotate_y(-steer_smoothed * steer_rate * steer_authority * delta * sign(speed if abs(speed) > 0.1 else 1.0))
	velocity = -global_transform.basis.z * speed
	move_and_slide()
	_update_camera(delta)

func _update_camera(delta):
	var rig=$CameraRig
	var target_x = steer_smoothed * 1.1
	rig.position.x = lerp(rig.position.x, target_x, 1.0-exp(-delta*3.0))
	rig.position.z = lerp(rig.position.z, 7.8 + clamp(abs(speed)*0.045,0.0,1.3), 1.0-exp(-delta*2.0))
