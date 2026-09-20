extends CharacterBody3D
@export var acceleration:=19.0
@export var reverse_acceleration:=11.0
@export var drag:=6.0
@export var max_speed:=34.0
@export var steer_rate:=1.75
var speed:=0.0
var steer_smoothed:=0.0
var touch_origin:=Vector2.ZERO
var touch_now:=Vector2.ZERO
var touching:=false

func _input(e):
	if e is InputEventScreenTouch and e.position.x < get_viewport().get_visible_rect().size.x*0.58:
		touching=e.pressed
		touch_origin=e.position
		touch_now=e.position
	elif e is InputEventScreenDrag and touching:
		touch_now=e.position

func _physics_process(delta):
	var throttle=Input.get_action_strength("throttle")-Input.get_action_strength("brake")
	var steer=Input.get_action_strength("steer_right")-Input.get_action_strength("steer_left")
	if touching:
		var d=(touch_now-touch_origin)/120.0
		steer=clamp(d.x,-1.0,1.0)
		throttle=clamp(-d.y,-1.0,1.0)
	steer_smoothed=move_toward(steer_smoothed,steer,delta*4.0)
	var target=(max_speed if throttle>0 else -max_speed*0.38) if abs(throttle)>0.04 else 0.0
	var rate=(acceleration if throttle>0 else reverse_acceleration) if abs(throttle)>0.04 else drag
	speed=move_toward(speed,target,delta*rate)
	var authority=clamp(abs(speed)/7.0,0.2,1.0)
	rotate_y(-steer_smoothed*steer_rate*authority*delta*sign(speed if abs(speed)>0.1 else 1.0))
	velocity=-global_transform.basis.z*speed
	move_and_slide()
	if is_on_wall(): speed*=0.42
	_update_camera(delta)

func _update_camera(delta):
	var rig=$CameraRig
	rig.position.x=lerp(rig.position.x,steer_smoothed*1.35,1.0-exp(-delta*4.0))
	rig.position.y=lerp(rig.position.y,3.0+clamp(abs(speed)*0.018,0.0,0.55),1.0-exp(-delta*2.5))
	rig.position.z=lerp(rig.position.z,7.4+clamp(abs(speed)*0.06,0.0,2.0),1.0-exp(-delta*2.2))
	$CameraRig/Camera3D.fov=lerp($CameraRig/Camera3D.fov,66.0+clamp(abs(speed)*0.22,0.0,8.0),1.0-exp(-delta*2.0))
