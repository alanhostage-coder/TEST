extends Control

# PARKVIEW BAY MODE
# Three shared-world cameras feed independently warpable quads so the image can
# be aligned to the real closed shutters rather than a flat rectangular screen.
const CAL_PATH := "user://parkview_bay_calibration.cfg"
const BAY_WIDTH_M := 2.90
const BAY_HEIGHT_M := 2.30
const LEFT_WIDTH_M := 0.78
const CENTRE_WIDTH_M := 1.34
const RIGHT_WIDTH_M := 0.78
const CAB_VERTICAL_FOV_DEG := 54.0
const CAB_PITCH_DEG := -3.2
const RENDER_SCALE := 0.72
const LOW_SPEC_RENDER_SCALE := 0.42
const PROJECTOR_MAX_RENDER_SCALE := 0.48
const CORNER_PICK_RADIUS := 82.0

var mode := 0 # 0 normal, 1 cab, 2 calibration
var car: Node3D
var source_camera: Camera3D
var viewports: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var surfaces: Array[Polygon2D] = []
var base_quads: Array = []
var cal_offsets: Array = []
var active_plane := -1
var active_corner := -1
var camera_yaws := [0.0, 0.0, 0.0]
var button: Button
var save_button: Button
var reset_button: Button
var drive_button: Button
var centre_button: Button
var cal_button: Button
var drive_enabled := false
var title: Label
var interior_parts: Array = []
var steering_ring: Line2D
var projector_max_mode := false

func _ready():
	projector_max_mode = OS.has_feature("projector_max")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	car = get_node_or_null("../Car")
	if car:
		source_camera = car.get_node_or_null("CameraRig/Camera3D")
	_reset_offsets(false)
	_load_calibration()
	_build_buttons()
	_build_views()
	_set_mode(1 if projector_max_mode else 0)

func _build_buttons():
	button = Button.new()
	button.text = "BAY WINDOW"
	button.position = Vector2(18, 45)
	button.size = Vector2(150, 46)
	button.modulate = Color(1, 1, 1, 0.80)
	button.pressed.connect(_cycle_mode)
	add_child(button)

	cal_button = Button.new()
	cal_button.text = "CAL"
	cal_button.position = Vector2(174, 45)
	cal_button.size = Vector2(62, 46)
	cal_button.modulate = Color(1, 1, 1, 0.58)
	cal_button.pressed.connect(_toggle_calibration)
	add_child(cal_button)

	save_button = Button.new()
	save_button.text = "SAVE"
	save_button.position = Vector2(18, 94)
	save_button.size = Vector2(112, 38)
	save_button.modulate = Color(1, 1, 1, 0.76)
	save_button.pressed.connect(_save_calibration)
	add_child(save_button)

	reset_button = Button.new()
	reset_button.text = "RESET"
	reset_button.position = Vector2(18, 138)
	reset_button.size = Vector2(112, 38)
	reset_button.modulate = Color(1, 1, 1, 0.66)
	reset_button.pressed.connect(_reset_calibration)
	add_child(reset_button)

	drive_button = Button.new()
	drive_button.text = "DRIVE"
	drive_button.position = Vector2(18, 94)
	drive_button.size = Vector2(112, 38)
	drive_button.modulate = Color(1, 1, 1, 0.82)
	drive_button.pressed.connect(_toggle_drive)
	add_child(drive_button)

	centre_button = Button.new()
	centre_button.text = "CENTRE"
	centre_button.position = Vector2(18, 138)
	centre_button.size = Vector2(112, 38)
	centre_button.modulate = Color(1, 1, 1, 0.72)
	centre_button.pressed.connect(_centre_wheel)
	add_child(centre_button)

	title = Label.new()
	title.position = Vector2(245, 54)
	title.text = ""
	title.modulate = Color(1, 1, 1, 0.62)
	add_child(title)

	for control in [button, cal_button, save_button, reset_button, drive_button, centre_button, title]:
		control.z_index = 40

func _build_views():
	for i in range(3):
		var viewport = SubViewport.new()
		viewport.name = "BayView%d" % i
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.handle_input_locally = false
		viewport.transparent_bg = false
		viewport.world_3d = get_viewport().world_3d
		add_child(viewport)

		var camera = Camera3D.new()
		camera.current = true
		camera.near = 0.12
		camera.far = 320.0 if projector_max_mode else (420.0 if OS.has_feature("thinkpad_low") else 900.0)
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = CAB_VERTICAL_FOV_DEG
		viewport.add_child(camera)
		viewports.append(viewport)
		cameras.append(camera)

		var surface = Polygon2D.new()
		surface.name = "ShutterPlane%d" % i
		surface.z_index = -20
		surface.texture = viewport.get_texture()
		surface.uv = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)])
		add_child(surface)
		surfaces.append(surface)
	_build_interior_overlay()
	_rescale_surfaces()

func _build_interior_overlay():
	for part in interior_parts:
		if is_instance_valid(part):
			part.queue_free()
	interior_parts.clear()

	for name in ["Header", "APillarL", "APillarR", "Dash", "Binnacle"]:
		var poly = Polygon2D.new()
		poly.name = name
		poly.color = Color(0.035, 0.040, 0.043, 0.98) if name != "Binnacle" else Color(0.055, 0.060, 0.062, 0.98)
		poly.z_index = 12
		add_child(poly)
		interior_parts.append(poly)

	steering_ring = Line2D.new()
	steering_ring.name = "SteeringWheel"
	steering_ring.width = 11.0
	steering_ring.default_color = Color(0.055, 0.058, 0.060, 0.98)
	steering_ring.closed = true
	steering_ring.antialiased = true
	steering_ring.z_index = 14
	add_child(steering_ring)
	interior_parts.append(steering_ring)
	_layout_interior_overlay()

func _layout_interior_overlay():
	if interior_parts.size() < 6:
		return
	var size = get_viewport_rect().size
	if size.x < 2.0 or size.y < 2.0:
		return
	var w = size.x
	var h = size.y

	var header: Polygon2D = interior_parts[0]
	header.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.045), Vector2(0, h * 0.045)
	])

	var left: Polygon2D = interior_parts[1]
	left.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(w * 0.048, 0), Vector2(w * 0.115, h * 0.72), Vector2(w * 0.070, h * 0.77), Vector2(0, h * 0.71)
	])

	var right: Polygon2D = interior_parts[2]
	right.polygon = PackedVector2Array([
		Vector2(w, 0), Vector2(w * 0.952, 0), Vector2(w * 0.885, h * 0.72), Vector2(w * 0.930, h * 0.77), Vector2(w, h * 0.71)
	])

	var dash: Polygon2D = interior_parts[3]
	dash.polygon = PackedVector2Array([
		Vector2(0, h),
		Vector2(0, h * 0.84),
		Vector2(w * 0.16, h * 0.765),
		Vector2(w * 0.38, h * 0.735),
		Vector2(w * 0.60, h * 0.725),
		Vector2(w * 0.84, h * 0.765),
		Vector2(w, h * 0.84),
		Vector2(w, h)
	])

	var binnacle: Polygon2D = interior_parts[4]
	binnacle.polygon = PackedVector2Array([
		Vector2(w * 0.585, h * 0.755),
		Vector2(w * 0.745, h * 0.755),
		Vector2(w * 0.775, h * 0.825),
		Vector2(w * 0.565, h * 0.825)
	])

	var wheel = steering_ring
	var centre = Vector2(w * 0.68, h * 0.86)
	var radius = min(w, h) * 0.105
	var pts = PackedVector2Array()
	for i in range(32):
		var a = TAU * float(i) / 32.0
		pts.append(centre + Vector2(cos(a), sin(a)) * radius)
	wheel.points = pts

func _set_interior_visible(visible: bool):
	for part in interior_parts:
		if is_instance_valid(part):
			part.visible = visible

func _notification(what):
	if what == NOTIFICATION_RESIZED and not surfaces.is_empty():
		_rescale_surfaces()
		_layout_interior_overlay()

func _rescale_surfaces():
	var size = get_viewport_rect().size
	if size.x < 2.0 or size.y < 2.0:
		return
	var ratios = [LEFT_WIDTH_M / BAY_WIDTH_M, CENTRE_WIDTH_M / BAY_WIDTH_M, RIGHT_WIDTH_M / BAY_WIDTH_M]
	base_quads.clear()
	var x := 0.0
	for i in range(3):
		var w = size.x * ratios[i]
		var base = PackedVector2Array([
			Vector2(x, 0),
			Vector2(x + w, 0),
			Vector2(x + w, size.y),
			Vector2(x, size.y)
		])
		base_quads.append(base)
		var warped = PackedVector2Array()
		for corner in range(4):
			warped.append(base[corner] + cal_offsets[i][corner] * size)
		surfaces[i].polygon = warped
		var scale = PROJECTOR_MAX_RENDER_SCALE if projector_max_mode else (LOW_SPEC_RENDER_SCALE if OS.has_feature("thinkpad_low") else RENDER_SCALE)
		viewports[i].size = Vector2i(max(144, int(w * scale)), max(180, int(size.y * scale)))
		var uv_size = Vector2(viewports[i].size.x, viewports[i].size.y)
		surfaces[i].uv = PackedVector2Array([Vector2.ZERO, Vector2(uv_size.x, 0), uv_size, Vector2(0, uv_size.y)])
		x += w
	_update_camera_frustums()
	_layout_interior_overlay()
	queue_redraw()

func _cycle_mode():
	_set_mode(0 if mode == 1 else 1)

func _toggle_calibration():
	_set_mode(0 if mode == 2 else 2)

func _set_mode(value: int):
	mode = value
	var active = mode > 0
	for i in range(surfaces.size()):
		surfaces[i].visible = active
		if i < viewports.size():
			viewports[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	_set_interior_visible(mode == 1)
	if source_camera:
		source_camera.current = not active
	if car:
		car.set_process_input(mode != 2)
		var roof = car.get_node_or_null("Roof")
		if roof:
			roof.visible = mode == 0
	if mode != 1 and drive_enabled:
		drive_enabled = false
		if car and car.has_method("set_motion_drive_enabled"):
			car.set_motion_drive_enabled(false)
	save_button.visible = mode == 2
	reset_button.visible = mode == 2
	drive_button.visible = mode == 1
	centre_button.visible = mode == 1
	active_plane = -1
	active_corner = -1
	if mode == 0:
		button.text = "BAY WINDOW"
		cal_button.text = "CAL"
		title.text = ""
	elif mode == 1:
		button.text = "PROJECTOR MAX" if projector_max_mode else "DRIVE VIEW"
		cal_button.text = "CAL"
		drive_button.text = "DRIVE"
		title.text = "PROJECTOR MAX · BAY WINDOW DRIVER VIEW" if projector_max_mode else "BAY WINDOW SIM · FORWARD DRIVER VIEW"
	else:
		button.text = "EXIT CAL"
		cal_button.text = "DONE"
		title.text = "DRAG CORNERS · SAVE WHEN LINES MEET SHUTTER EDGES"
	queue_redraw()

func _unhandled_input(event):
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_Y or event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_cycle_mode()
			get_viewport().set_input_as_handled()

func _input(event):
	if mode != 2:
		return
	if event is InputEventScreenTouch:
		if event.position.x < 145.0 and event.position.y < 190.0:
			return
		if event.pressed:
			_pick_corner(event.position)
		else:
			active_plane = -1
			active_corner = -1
	elif event is InputEventScreenDrag and active_plane >= 0 and active_corner >= 0:
		var size = get_viewport_rect().size
		if size.x < 2.0 or size.y < 2.0:
			return
		var base: PackedVector2Array = base_quads[active_plane]
		var raw = (event.position - base[active_corner]) / size
		cal_offsets[active_plane][active_corner] = Vector2(clamp(raw.x, -0.18, 0.18), clamp(raw.y, -0.18, 0.18))
		_rescale_surfaces()
		get_viewport().set_input_as_handled()

func _pick_corner(pos: Vector2):
	var best_distance = CORNER_PICK_RADIUS
	active_plane = -1
	active_corner = -1
	for plane in range(surfaces.size()):
		var poly: PackedVector2Array = surfaces[plane].polygon
		for corner in range(poly.size()):
			var distance = pos.distance_to(poly[corner])
			if distance < best_distance:
				best_distance = distance
				active_plane = plane
				active_corner = corner
	queue_redraw()

func _process(_delta):
	if mode == 0 or not car:
		return
	if mode == 1 and steering_ring:
		steering_ring.rotation = clamp(float(car.get("steer_smoothed")) * 0.18, -0.18, 0.18)
	var cab_transform = car.global_transform
	# Right-hand-drive open-top seating position: the world should feel as if the
	# viewer is sitting in the car, not watching a bumper camera.
	cab_transform.origin = car.to_global(Vector3(0.42, 1.22, -0.34))
	for i in range(3):
		var t = cab_transform
		# The yaw centres are derived from each plane's horizontal FOV, so adjacent
		# views meet at the same ray instead of overlapping or leaving a jump.
		t.basis = Basis(Vector3.UP, camera_yaws[i]) * cab_transform.basis
		t.basis = t.basis * Basis(Vector3.RIGHT, deg_to_rad(CAB_PITCH_DEG))
		cameras[i].global_transform = t
	queue_redraw()

func _draw():
	if mode != 2:
		return
	var size = get_viewport_rect().size
	var line = Color(1.0, 0.72, 0.28, 0.90)
	var faint = Color(1.0, 1.0, 1.0, 0.20)
	for i in range(1, 10):
		var x = size.x * float(i) / 10.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), faint, 1.0)
	for j in range(1, 8):
		var y = size.y * float(j) / 8.0
		draw_line(Vector2(0, y), Vector2(size.x, y), faint, 1.0)
	draw_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), line, 2.0)

	for plane in range(surfaces.size()):
		var poly: PackedVector2Array = surfaces[plane].polygon
		for edge in range(4):
			draw_line(poly[edge], poly[(edge + 1) % 4], line, 2.5)
		for corner in range(4):
			var selected = plane == active_plane and corner == active_corner
			draw_circle(poly[corner], 13.0 if selected else 9.0, Color(1.0, 0.52, 0.18, 1.0), false, 3.0)

func _reset_offsets(save_after: bool):
	cal_offsets = []
	for _plane in range(3):
		cal_offsets.append([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	if not surfaces.is_empty():
		_rescale_surfaces()
	if save_after:
		_save_calibration()

func _reset_calibration():
	_reset_offsets(true)

func _save_calibration():
	var cfg = ConfigFile.new()
	cfg.set_value("bay", "width_m", BAY_WIDTH_M)
	cfg.set_value("bay", "height_m", BAY_HEIGHT_M)
	cfg.set_value("bay", "vertical_fov_deg", CAB_VERTICAL_FOV_DEG)
	for plane in range(3):
		for corner in range(4):
			cfg.set_value("plane_%d" % plane, "corner_%d" % corner, cal_offsets[plane][corner])
	cfg.save(CAL_PATH)
	title.text = "PARKVIEW BAY · CALIBRATION SAVED"

func _load_calibration():
	var cfg = ConfigFile.new()
	if cfg.load(CAL_PATH) != OK:
		return
	for plane in range(3):
		for corner in range(4):
			var saved = cfg.get_value("plane_%d" % plane, "corner_%d" % corner, Vector2.ZERO)
			if saved is Vector2:
				cal_offsets[plane][corner] = saved


func _horizontal_fov(vertical_deg: float, aspect: float) -> float:
	var vf = deg_to_rad(vertical_deg)
	return 2.0 * atan(tan(vf * 0.5) * max(0.05, aspect))

func _update_camera_frustums():
	if viewports.size() < 3 or cameras.size() < 3:
		return
	var hfov: Array = []
	for i in range(3):
		var vp_size = viewports[i].size
		var aspect = float(vp_size.x) / max(1.0, float(vp_size.y))
		cameras[i].fov = CAB_VERTICAL_FOV_DEG
		hfov.append(_horizontal_fov(CAB_VERTICAL_FOV_DEG, aspect))
	# Centre-to-centre yaw is exactly half of the two neighbouring horizontal
	# fields of view. This makes the outer ray of one plane equal the inner ray
	# of the next, producing one continuous panorama before physical keystone.
	var left_offset = (float(hfov[0]) + float(hfov[1])) * 0.5
	var right_offset = (float(hfov[1]) + float(hfov[2])) * 0.5
	camera_yaws = [-left_offset, 0.0, right_offset]


func _toggle_drive():
	if mode != 1 or not car:
		return
	drive_enabled = not drive_enabled
	if car.has_method("set_motion_drive_enabled"):
		car.set_motion_drive_enabled(drive_enabled)
	drive_button.text = "DRIVING" if drive_enabled else "DRIVE"
	if drive_enabled:
		title.text = "TILT PHONE TO STEER · AUTO THROTTLE · CENTRE TO RECALIBRATE"
	else:
		title.text = "PARKVIEW BAY · OPEN-TOP DRIVER VIEW"

func _centre_wheel():
	if not car:
		return
	if car.has_method("calibrate_motion_wheel"):
		car.calibrate_motion_wheel()
	if drive_enabled:
		title.text = "STEERING CENTRED · TILT PHONE LIKE A WHEEL"
