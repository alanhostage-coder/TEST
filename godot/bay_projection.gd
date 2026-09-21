extends Control

# PARKVIEW BAY MODE
# Five shared-world cameras feed independently warpable quads: three bay panels
# plus two separate wall windows. The defaults are explicitly an unmeasured
# starting layout; calibration supplies the real closed-shutter extents.
const CAL_PATH := "user://parkview_bay_calibration.cfg"
const MAX_SURFACES := 5
const SURFACE_NAMES := ["BAY LEFT", "BAY CENTRE", "BAY RIGHT", "WALL NEAR", "WALL FAR"]
# Normalised screen-space starter rectangles. These preserve unequal panels and
# black wall/frame gaps without claiming physical measurements.
const THREE_RECTS := [
	Rect2(0.020, 0.035, 0.225, 0.930),
	Rect2(0.270, 0.035, 0.460, 0.930),
	Rect2(0.755, 0.035, 0.225, 0.930)
]
const FIVE_RECTS := [
	Rect2(0.015, 0.060, 0.165, 0.880),
	Rect2(0.195, 0.035, 0.330, 0.930),
	Rect2(0.540, 0.060, 0.165, 0.880),
	Rect2(0.755, 0.095, 0.095, 0.810),
	Rect2(0.885, 0.095, 0.095, 0.810)
]
const CAB_VERTICAL_FOV_DEG := 54.0
const CAB_PITCH_DEG := -3.2
const RENDER_SCALE := 0.72
const LOW_SPEC_RENDER_SCALE := 0.42
const PROJECTOR_MAX_RENDER_SCALE := 0.48
const PC_MAX_RENDER_SCALE := 0.88
const CORNER_PICK_RADIUS := 82.0

var mode := 0 # 0 normal, 1 cab, 2 calibration
var car: Node3D
var source_camera: Camera3D
var viewports: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var surfaces: Array[Polygon2D] = []
var base_quads: Array = []
var cal_offsets_three: Array = []
var cal_offsets_five: Array = []
var active_plane := -1
var active_corner := -1
var selected_surface := 0
var layout_surface_count := 3
var camera_yaws: Array = []
var camera_yaw_adjust_three := [0.0, 0.0, 0.0]
var camera_yaw_adjust_five := [0.0, 0.0, 0.0, 0.0, 0.0]
# Screen order is physical left, centre, right. Godot yaw sign is opposite the
# intuitive screen direction for this vehicle basis, so keep the mapping explicit.
const BAY_VIEW_YAW_SIGN := -1.0
var button: Button
var save_button: Button
var reset_button: Button
var drive_button: Button
var centre_button: Button
var cal_button: Button
var layout_button: Button
var surface_button: Button
var yaw_left_button: Button
var yaw_right_button: Button
var drive_enabled := false
var title: Label
var interior_parts: Array = []
var steering_ring: Line2D
var projector_max_mode := false
var pc_max_mode := false
var black_mask: ColorRect

func _ready():
	projector_max_mode = OS.has_feature("projector_max")
	pc_max_mode = OS.has_feature("pc_max")
	layout_surface_count = 5 if projector_max_mode else 3
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	car = get_node_or_null("../Car")
	if car:
		source_camera = car.get_node_or_null("CameraRig/Camera3D")
	_reset_all_offsets()
	_load_calibration()
	_build_buttons()
	_build_views()
	_set_mode(1 if projector_max_mode else 0)

func _build_buttons():
	black_mask = ColorRect.new()
	black_mask.color = Color.BLACK
	black_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_mask.z_index = -30
	add_child(black_mask)

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

	layout_button = Button.new()
	layout_button.text = "LAYOUT: 5"
	layout_button.position = Vector2(242, 45)
	layout_button.size = Vector2(110, 46)
	layout_button.modulate = Color(1, 1, 1, 0.68)
	layout_button.pressed.connect(_toggle_layout)
	add_child(layout_button)

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

	surface_button = Button.new()
	surface_button.position = Vector2(136, 94)
	surface_button.size = Vector2(138, 38)
	surface_button.pressed.connect(_select_next_surface)
	add_child(surface_button)

	yaw_left_button = Button.new()
	yaw_left_button.text = "YAW −"
	yaw_left_button.position = Vector2(280, 94)
	yaw_left_button.size = Vector2(82, 38)
	yaw_left_button.pressed.connect(_nudge_yaw.bind(-1.0))
	add_child(yaw_left_button)

	yaw_right_button = Button.new()
	yaw_right_button.text = "YAW +"
	yaw_right_button.position = Vector2(368, 94)
	yaw_right_button.size = Vector2(82, 38)
	yaw_right_button.pressed.connect(_nudge_yaw.bind(1.0))
	add_child(yaw_right_button)

	title = Label.new()
	title.position = Vector2(460, 54)
	title.text = ""
	title.modulate = Color(1, 1, 1, 0.62)
	add_child(title)

	for control in [button, cal_button, layout_button, save_button, reset_button, drive_button, centre_button, surface_button, yaw_left_button, yaw_right_button, title]:
		control.z_index = 40

func _build_views():
	for i in range(MAX_SURFACES):
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
		camera.far = 320.0 if projector_max_mode else (1100.0 if pc_max_mode else (420.0 if OS.has_feature("thinkpad_low") else 900.0))
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
	var rects = FIVE_RECTS if layout_surface_count == 5 else THREE_RECTS
	var offsets = cal_offsets_five if layout_surface_count == 5 else cal_offsets_three
	base_quads.clear()
	for i in range(MAX_SURFACES):
		if i >= layout_surface_count:
			base_quads.append(PackedVector2Array())
			surfaces[i].visible = false
			viewports[i].render_target_update_mode = SubViewport.UPDATE_DISABLED
			continue
		var rect: Rect2 = rects[i]
		var x = size.x * rect.position.x
		var y = size.y * rect.position.y
		var w = size.x * rect.size.x
		var h = size.y * rect.size.y
		var base = PackedVector2Array([
			Vector2(x, y),
			Vector2(x + w, y),
			Vector2(x + w, y + h),
			Vector2(x, y + h)
		])
		base_quads.append(base)
		var warped = PackedVector2Array()
		for corner in range(4):
			warped.append(base[corner] + offsets[i][corner] * size)
		surfaces[i].polygon = warped
		var scale = PROJECTOR_MAX_RENDER_SCALE if projector_max_mode else (PC_MAX_RENDER_SCALE if pc_max_mode else (LOW_SPEC_RENDER_SCALE if OS.has_feature("thinkpad_low") else RENDER_SCALE))
		viewports[i].size = Vector2i(max(112, int(w * scale)), max(180, int(h * scale)))
		var uv_size = Vector2(viewports[i].size.x, viewports[i].size.y)
		surfaces[i].uv = PackedVector2Array([Vector2.ZERO, Vector2(uv_size.x, 0), uv_size, Vector2(0, uv_size.y)])
		surfaces[i].visible = mode > 0
		viewports[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS if mode > 0 else SubViewport.UPDATE_DISABLED
	_update_camera_frustums()
	_layout_interior_overlay()
	queue_redraw()

func _cycle_mode():
	_set_mode(0 if mode == 1 else 1)

func _toggle_calibration():
	_set_mode(0 if mode == 2 else 2)

func _toggle_layout():
	layout_surface_count = 3 if layout_surface_count == 5 else 5
	selected_surface = min(selected_surface, layout_surface_count - 1)
	_rescale_surfaces()
	_update_calibration_controls()
	_save_calibration()

func _select_next_surface():
	selected_surface = (selected_surface + 1) % layout_surface_count
	_update_calibration_controls()
	queue_redraw()

func _nudge_yaw(amount_degrees: float):
	var adjustments = camera_yaw_adjust_five if layout_surface_count == 5 else camera_yaw_adjust_three
	adjustments[selected_surface] = clamp(float(adjustments[selected_surface]) + deg_to_rad(amount_degrees), deg_to_rad(-35.0), deg_to_rad(35.0))
	_update_camera_frustums()
	_update_calibration_controls()

func _update_calibration_controls():
	if not layout_button:
		return
	layout_button.text = "LAYOUT: %d" % layout_surface_count
	var adjustments = camera_yaw_adjust_five if layout_surface_count == 5 else camera_yaw_adjust_three
	var yaw_degrees = rad_to_deg(float(adjustments[selected_surface]))
	surface_button.text = "%d · %s" % [selected_surface + 1, SURFACE_NAMES[selected_surface]]
	surface_button.tooltip_text = "Select a shutter/window surface"
	yaw_left_button.tooltip_text = "Rotate selected view left by 1°"
	yaw_right_button.tooltip_text = "Rotate selected view right by 1°"
	if mode == 2:
		title.text = "UNMEASURED START · %s · YAW %+.0f° · DRAG CORNERS, THEN SAVE" % [SURFACE_NAMES[selected_surface], yaw_degrees]

func _set_mode(value: int):
	mode = value
	var active = mode > 0
	for i in range(surfaces.size()):
		var surface_active = active and i < layout_surface_count
		surfaces[i].visible = surface_active
		if i < viewports.size():
			viewports[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS if surface_active else SubViewport.UPDATE_DISABLED
	if black_mask:
		black_mask.visible = active
	_set_interior_visible(mode == 1)
	if source_camera:
		source_camera.current = not active
	if car:
		car.set_process_input(mode != 2)
		car.set_physics_process(mode != 2)
		var roof = car.get_node_or_null("Roof")
		if roof:
			roof.visible = mode == 0
	if mode != 1 and drive_enabled:
		drive_enabled = false
		if car and car.has_method("set_motion_drive_enabled"):
			car.set_motion_drive_enabled(false)
	save_button.visible = mode == 2
	reset_button.visible = mode == 2
	surface_button.visible = mode == 2
	yaw_left_button.visible = mode == 2
	yaw_right_button.visible = mode == 2
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
		title.text = "UNMEASURED START · DRAG CORNERS TO CLOSED SHUTTER EDGES"
	_update_calibration_controls()
	queue_redraw()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			_cycle_mode()
		elif event.keycode == KEY_F7:
			_toggle_layout()
			get_viewport().set_input_as_handled()
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_Y or event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_cycle_mode()
			get_viewport().set_input_as_handled()

func _input(event):
	if mode != 2:
		return
	if event is InputEventScreenTouch:
		if event.position.x < 455.0 and event.position.y < 145.0:
			return
		if event.pressed:
			_pick_corner(event.position)
		else:
			active_plane = -1
			active_corner = -1
	elif event is InputEventScreenDrag and active_plane >= 0 and active_corner >= 0:
		_drag_corner(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.x < 455.0 and event.position.y < 145.0:
			return
		if event.pressed:
			_pick_corner(event.position)
		else:
			active_plane = -1
			active_corner = -1
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and active_plane >= 0 and active_corner >= 0:
		_drag_corner(event.position)
		get_viewport().set_input_as_handled()

func _drag_corner(position: Vector2):
	if active_plane >= 0 and active_corner >= 0:
		var size = get_viewport_rect().size
		if size.x < 2.0 or size.y < 2.0:
			return
		var base: PackedVector2Array = base_quads[active_plane]
		var raw = (position - base[active_corner]) / size
		var offsets = cal_offsets_five if layout_surface_count == 5 else cal_offsets_three
		offsets[active_plane][active_corner] = Vector2(clamp(raw.x, -0.30, 0.30), clamp(raw.y, -0.30, 0.30))
		_rescale_surfaces()

func _pick_corner(pos: Vector2):
	var best_distance = CORNER_PICK_RADIUS
	active_plane = -1
	active_corner = -1
	for plane in range(layout_surface_count):
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
	for i in range(layout_surface_count):
		var t = cab_transform
		# The yaw centres are derived from each plane's horizontal FOV, so adjacent
		# views meet at the same ray instead of overlapping or leaving a jump.
		t.basis = Basis(Vector3.UP, camera_yaws[i] * BAY_VIEW_YAW_SIGN) * cab_transform.basis
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

	for plane in range(layout_surface_count):
		var poly: PackedVector2Array = surfaces[plane].polygon
		for edge in range(4):
			draw_line(poly[edge], poly[(edge + 1) % 4], line, 2.5)
		for corner in range(4):
			var selected = plane == active_plane and corner == active_corner
			draw_circle(poly[corner], 13.0 if selected else 9.0, Color(1.0, 0.52, 0.18, 1.0), false, 3.0)
		var label_position = poly[0] + Vector2(12, 24)
		draw_string(ThemeDB.fallback_font, label_position, "%d  %s" % [plane + 1, SURFACE_NAMES[plane]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.78, 0.38, 0.95))

func _blank_offsets(count: int) -> Array:
	var result: Array = []
	for _plane in range(count):
		result.append([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	return result

func _reset_all_offsets():
	cal_offsets_three = _blank_offsets(3)
	cal_offsets_five = _blank_offsets(5)

func _reset_offsets(save_after: bool):
	if layout_surface_count == 5:
		cal_offsets_five = _blank_offsets(5)
		camera_yaw_adjust_five = [0.0, 0.0, 0.0, 0.0, 0.0]
	else:
		cal_offsets_three = _blank_offsets(3)
		camera_yaw_adjust_three = [0.0, 0.0, 0.0]
	if not surfaces.is_empty():
		_rescale_surfaces()
	if save_after:
		_save_calibration()

func _reset_calibration():
	_reset_offsets(true)

func _save_calibration():
	var cfg = ConfigFile.new()
	cfg.set_value("layout", "surface_count", layout_surface_count)
	cfg.set_value("layout", "measurement_status", "unmeasured_until_user_calibrates_closed_shutters")
	cfg.set_value("bay", "vertical_fov_deg", CAB_VERTICAL_FOV_DEG)
	for plane in range(3):
		for corner in range(4):
			cfg.set_value("three_plane_%d" % plane, "corner_%d" % corner, cal_offsets_three[plane][corner])
		cfg.set_value("three_plane_%d" % plane, "yaw_adjust", camera_yaw_adjust_three[plane])
	for plane in range(5):
		for corner in range(4):
			cfg.set_value("five_plane_%d" % plane, "corner_%d" % corner, cal_offsets_five[plane][corner])
		cfg.set_value("five_plane_%d" % plane, "yaw_adjust", camera_yaw_adjust_five[plane])
	cfg.save(CAL_PATH)
	title.text = "%d-SURFACE CALIBRATION SAVED" % layout_surface_count

func _load_calibration():
	var cfg = ConfigFile.new()
	if cfg.load(CAL_PATH) != OK:
		return
	var saved_count = int(cfg.get_value("layout", "surface_count", layout_surface_count))
	if saved_count in [3, 5]:
		layout_surface_count = saved_count
	for plane in range(3):
		for corner in range(4):
			var legacy = cfg.get_value("plane_%d" % plane, "corner_%d" % corner, Vector2.ZERO)
			var saved = cfg.get_value("three_plane_%d" % plane, "corner_%d" % corner, legacy)
			if saved is Vector2:
				cal_offsets_three[plane][corner] = saved
		camera_yaw_adjust_three[plane] = float(cfg.get_value("three_plane_%d" % plane, "yaw_adjust", 0.0))
	for plane in range(5):
		for corner in range(4):
			var saved = cfg.get_value("five_plane_%d" % plane, "corner_%d" % corner, Vector2.ZERO)
			if saved is Vector2:
				cal_offsets_five[plane][corner] = saved
		camera_yaw_adjust_five[plane] = float(cfg.get_value("five_plane_%d" % plane, "yaw_adjust", 0.0))


func _horizontal_fov(vertical_deg: float, aspect: float) -> float:
	var vf = deg_to_rad(vertical_deg)
	return 2.0 * atan(tan(vf * 0.5) * max(0.05, aspect))

func _update_camera_frustums():
	if viewports.size() < layout_surface_count or cameras.size() < layout_surface_count:
		return
	var hfov: Array = []
	for i in range(layout_surface_count):
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
	if layout_surface_count == 5:
		camera_yaws.append(right_offset + (float(hfov[2]) + float(hfov[3])) * 0.5)
		camera_yaws.append(float(camera_yaws[3]) + (float(hfov[3]) + float(hfov[4])) * 0.5)
	var adjustments = camera_yaw_adjust_five if layout_surface_count == 5 else camera_yaw_adjust_three
	for i in range(layout_surface_count):
		camera_yaws[i] = float(camera_yaws[i]) + float(adjustments[i])


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
