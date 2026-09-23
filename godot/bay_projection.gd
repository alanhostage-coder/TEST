extends Control

# PARKVIEW BAY MODE
# Five shared-world cameras feed independently warpable quads: three bay panels
# plus two separate wall windows. The defaults are explicitly an unmeasured
# starting layout; calibration supplies the real closed-shutter extents.
const CAL_PATH := "user://parkview_bay_calibration.cfg"
const CAL_BACKUP_PATH := "user://parkview_bay_calibration.previous.cfg"
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
const XPS_9530_RENDER_SCALE := 0.86
# Static perceptual allocation for the seated driver. Keep the old 0.86 uniform
# scale as the pixel-budget baseline, spend more on the forward centre pane, and
# recover that cost from the two far peripheral wall panes.
const XPS_9530_SURFACE_RENDER_SCALES := [0.86, 0.96, 0.86, 0.60, 0.60]
const CORNER_PICK_RADIUS := 82.0
const MIN_VIEWPORT_WIDTH := 64.0
const MIN_VIEWPORT_HEIGHT := 180.0
const MIN_CALIBRATION_AREA_RATIO := 0.22
const MIN_CALIBRATION_EDGE_RATIO := 0.15
const DRIVER_CHROME_HOLD_SECONDS := 6.0
const DRIVER_CHROME_FADE_SECONDS := 1.25
const DRIVER_CHROME_MOUSE_WAKE_DISTANCE := 3.0
const CALIBRATION_GUIDE_DIVISIONS := 4
const CALIBRATION_SURFACE_COLOURS := [
	Color(1.00, 0.55, 0.16, 0.96),
	Color(0.20, 0.86, 1.00, 0.96),
	Color(0.74, 1.00, 0.32, 0.96),
	Color(1.00, 0.34, 0.72, 0.96),
	Color(0.64, 0.48, 1.00, 0.96)
]

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
var restore_button: Button
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
var xps_9530_mode := false
var black_mask: ColorRect
var shared_cab_transform := Transform3D.IDENTITY
var driver_chrome_idle := 0.0
var driver_chrome_alpha := 1.0

func _ready():
	if OS.has_feature("mobile") or OS.get_environment("PUA_FORCE_MOBILE_TEST") == "1":
		# Projector calibration/render surfaces are desktop-only. Building five
		# hidden SubViewports on Android wastes GPU and exposes irrelevant controls.
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)
		set_process_input(false)
		return
	projector_max_mode = OS.has_feature("projector_max")
	pc_max_mode = OS.has_feature("pc_max")
	xps_9530_mode = OS.has_feature("xps_9530")
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

	restore_button = Button.new()
	restore_button.text = "RESTORE"
	restore_button.position = Vector2(136, 138)
	restore_button.size = Vector2(138, 38)
	restore_button.modulate = Color(1, 1, 1, 0.70)
	restore_button.tooltip_text = "Restore the calibration that existed before the last save or reset"
	restore_button.pressed.connect(_restore_calibration_backup)
	add_child(restore_button)

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
	yaw_left_button.text = "PAN −"
	yaw_left_button.position = Vector2(280, 94)
	yaw_left_button.size = Vector2(82, 38)
	yaw_left_button.pressed.connect(_nudge_yaw.bind(-1.0))
	add_child(yaw_left_button)

	yaw_right_button = Button.new()
	yaw_right_button.text = "PAN +"
	yaw_right_button.position = Vector2(368, 94)
	yaw_right_button.size = Vector2(82, 38)
	yaw_right_button.pressed.connect(_nudge_yaw.bind(1.0))
	add_child(yaw_right_button)

	title = Label.new()
	title.position = Vector2(460, 54)
	title.text = ""
	title.modulate = Color(1, 1, 1, 0.62)
	add_child(title)

	for control in [button, cal_button, layout_button, save_button, reset_button, restore_button, drive_button, centre_button, surface_button, yaw_left_button, yaw_right_button, title]:
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
		camera.far = 760.0 if xps_9530_mode else (320.0 if projector_max_mode else (1100.0 if pc_max_mode else (420.0 if OS.has_feature("thinkpad_low") else 900.0)))
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
		var scale = render_scale_for_surface(i)
		viewports[i].size = viewport_size_for_surface(Vector2(w, h), scale)
		var uv_size = Vector2(viewports[i].size.x, viewports[i].size.y)
		surfaces[i].uv = PackedVector2Array([Vector2.ZERO, Vector2(uv_size.x, 0), uv_size, Vector2(0, uv_size.y)])
		surfaces[i].visible = mode > 0
		viewports[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS if mode > 0 else SubViewport.UPDATE_DISABLED
	_update_camera_frustums()
	_layout_interior_overlay()
	queue_redraw()

func render_scale_for_surface(surface_index: int) -> float:
	if xps_9530_mode and layout_surface_count == 5:
		return float(XPS_9530_SURFACE_RENDER_SCALES[clamp(surface_index, 0, 4)])
	if projector_max_mode:
		return PROJECTOR_MAX_RENDER_SCALE
	if pc_max_mode:
		return PC_MAX_RENDER_SCALE
	if OS.has_feature("thinkpad_low"):
		return LOW_SPEC_RENDER_SCALE
	return RENDER_SCALE


func viewport_size_for_surface(surface_size: Vector2, render_scale: float) -> Vector2i:
	# Keep the render buffer at the same aspect ratio as the physical destination.
	# Independent width/height minimums distort narrow panes at low resolutions and
	# therefore change the camera horizontal FOV and panorama seam geometry.
	var target := Vector2(
		max(1.0, surface_size.x * render_scale),
		max(1.0, surface_size.y * render_scale)
	)
	var uniform_boost: float = max(
		1.0,
		max(MIN_VIEWPORT_WIDTH / target.x, MIN_VIEWPORT_HEIGHT / target.y)
	)
	return Vector2i(
		max(1, int(round(target.x * uniform_boost))),
		max(1, int(round(target.y * uniform_boost)))
	)


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
	# Keep the five views one contiguous panorama during optical calibration.
	# Independent yaw creates a duplicate or missing world wedge at a seam.
	var adjustments = camera_yaw_adjust_five if layout_surface_count == 5 else camera_yaw_adjust_three
	var delta := deg_to_rad(amount_degrees)
	for i in range(layout_surface_count):
		adjustments[i] = clamp(float(adjustments[i]) + delta, deg_to_rad(-35.0), deg_to_rad(35.0))
	_update_camera_frustums()
	_update_calibration_controls()

func _update_calibration_controls():
	if not layout_button:
		return
	layout_button.text = "LAYOUT: %d" % layout_surface_count
	var adjustments = camera_yaw_adjust_five if layout_surface_count == 5 else camera_yaw_adjust_three
	var yaw_degrees = rad_to_deg(float(adjustments[0]))
	surface_button.text = "%d · %s" % [selected_surface + 1, SURFACE_NAMES[selected_surface]]
	surface_button.tooltip_text = "Select a shutter/window surface"
	yaw_left_button.tooltip_text = "Rotate the entire contiguous panorama left by 1°"
	yaw_right_button.tooltip_text = "Rotate the entire contiguous panorama right by 1°"
	if mode == 2:
		title.text = "UNMEASURED START · %s · PAN %+.0f° · DRAG CORNERS, THEN SAVE" % [SURFACE_NAMES[selected_surface], yaw_degrees]

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
	restore_button.visible = mode == 2
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
		title.text = "XPS 15 9530 · FIVE-SURFACE DRIVER VIEW" if xps_9530_mode else ("PROJECTOR MAX · BAY WINDOW DRIVER VIEW" if projector_max_mode else "BAY WINDOW SIM · FORWARD DRIVER VIEW")
	else:
		button.text = "EXIT CAL"
		cal_button.text = "DONE"
		title.text = "UNMEASURED START · DRAG CORNERS TO CLOSED SHUTTER EDGES"
	_update_calibration_controls()
	_wake_driver_chrome()
	queue_redraw()

func _wake_driver_chrome():
	driver_chrome_idle = 0.0
	driver_chrome_alpha = 1.0
	_apply_driver_chrome_alpha()

func _update_driver_chrome(delta: float):
	if mode != 1:
		return
	driver_chrome_idle += delta / maxf(Engine.time_scale, 0.001)
	if driver_chrome_idle <= DRIVER_CHROME_HOLD_SECONDS:
		return
	var previous_alpha := driver_chrome_alpha
	driver_chrome_alpha = move_toward(driver_chrome_alpha, 0.0, delta / DRIVER_CHROME_FADE_SECONDS)
	if not is_equal_approx(previous_alpha, driver_chrome_alpha):
		_apply_driver_chrome_alpha()

func _apply_driver_chrome_alpha():
	var driving := mode == 1
	var chrome_visible := not driving or driver_chrome_alpha > 0.01
	button.visible = chrome_visible
	cal_button.visible = chrome_visible
	layout_button.visible = chrome_visible
	title.visible = chrome_visible
	drive_button.visible = driving and chrome_visible
	centre_button.visible = driving and chrome_visible
	var alpha := driver_chrome_alpha if driving else 1.0
	button.modulate.a = 0.80 * alpha
	cal_button.modulate.a = 0.58 * alpha
	layout_button.modulate.a = 0.68 * alpha
	drive_button.modulate.a = 0.82 * alpha
	centre_button.modulate.a = 0.72 * alpha
	title.modulate.a = 0.62 * alpha

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
	if mode == 1 and event is InputEventMouseMotion and event.relative.length() >= DRIVER_CHROME_MOUSE_WAKE_DISTANCE:
		_wake_driver_chrome()
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
		var proposed_offset := Vector2(clamp(raw.x, -0.30, 0.30), clamp(raw.y, -0.30, 0.30))
		var candidate := PackedVector2Array()
		for corner in range(4):
			var offset: Vector2 = proposed_offset if corner == active_corner else offsets[active_plane][corner]
			candidate.append(base[corner] + offset * size)
		if _is_safe_calibration_quad(candidate, base):
			offsets[active_plane][active_corner] = proposed_offset
			_rescale_surfaces()
			_update_calibration_controls()
		else:
			title.text = "CAL LIMIT · KEEP %s OPEN AND UNFOLDED" % SURFACE_NAMES[active_plane]


func _is_safe_calibration_quad(candidate: PackedVector2Array, base: PackedVector2Array) -> bool:
	# A projected rectangle can be strongly keystoned, but it must remain a convex
	# quadrilateral with the same winding as its source. Reject foldovers and tiny
	# slivers before they can be saved as an apparently missing shutter surface.
	if candidate.size() != 4 or base.size() != 4:
		return false
	for point in candidate:
		if not point.is_finite():
			return false
	var base_area := absf(_quad_signed_area(base))
	var candidate_area := absf(_quad_signed_area(candidate))
	if base_area < 1.0 or candidate_area < base_area * MIN_CALIBRATION_AREA_RATIO:
		return false
	if _quad_signed_area(candidate) * _quad_signed_area(base) <= 0.0:
		return false
	var winding := 0.0
	for i in range(4):
		var edge_a: Vector2 = candidate[(i + 1) % 4] - candidate[i]
		var edge_b: Vector2 = candidate[(i + 2) % 4] - candidate[(i + 1) % 4]
		var base_edge: Vector2 = base[(i + 1) % 4] - base[i]
		if edge_a.length() < base_edge.length() * MIN_CALIBRATION_EDGE_RATIO:
			return false
		var cross_z: float = edge_a.cross(edge_b)
		if absf(cross_z) < 0.001:
			return false
		var corner_winding := signf(cross_z)
		if winding == 0.0:
			winding = corner_winding
		elif corner_winding != winding:
			return false
	return true


func _quad_signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(points.size()):
		var next: Vector2 = points[(i + 1) % points.size()]
		area += points[i].x * next.y - next.x * points[i].y
	return area * 0.5

func _quad_point(points: PackedVector2Array, u: float, v: float) -> Vector2:
	# Bilinear surface coordinates keep the calibration mesh attached to a
	# keystoned quad instead of the unwarped 16:9 canvas.
	if points.size() != 4:
		return Vector2.ZERO
	var top := points[0].lerp(points[1], clampf(u, 0.0, 1.0))
	var bottom := points[3].lerp(points[2], clampf(u, 0.0, 1.0))
	return top.lerp(bottom, clampf(v, 0.0, 1.0))

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

func _process(delta: float):
	_update_driver_chrome(delta)
	if mode == 0 or not car:
		return
	if mode == 1 and steering_ring:
		steering_ring.rotation = clamp(float(car.get("steer_smoothed")) * 0.18, -0.18, 0.18)
	# Sample the vehicle pose once per rendered frame and derive every shutter view
	# from that immutable transform. No surface gets a later car/camera state than
	# its neighbour, which protects cross-panel object motion and horizon continuity.
	shared_cab_transform = car.global_transform
	# Right-hand-drive open-top seating position: the world should feel as if the
	# viewer is sitting in the car, not watching a bumper camera.
	shared_cab_transform.origin = car.to_global(Vector3(0.42, 1.22, -0.34))
	for i in range(layout_surface_count):
		var t = shared_cab_transform
		# The yaw centres are derived from each plane's horizontal FOV, so adjacent
		# views meet at the same ray instead of overlapping or leaving a jump.
		t.basis = Basis(Vector3.UP, camera_yaws[i] * BAY_VIEW_YAW_SIGN) * shared_cab_transform.basis
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
		var surface_colour: Color = CALIBRATION_SURFACE_COLOURS[plane]
		var guide_colour := Color(surface_colour.r, surface_colour.g, surface_colour.b, 0.48 if plane == selected_surface else 0.28)
		for division in range(1, CALIBRATION_GUIDE_DIVISIONS):
			var fraction := float(division) / float(CALIBRATION_GUIDE_DIVISIONS)
			draw_line(_quad_point(poly, fraction, 0.0), _quad_point(poly, fraction, 1.0), guide_colour, 1.5)
			draw_line(_quad_point(poly, 0.0, fraction), _quad_point(poly, 1.0, fraction), guide_colour, 1.5)
		for edge in range(4):
			draw_line(poly[edge], poly[(edge + 1) % 4], surface_colour, 3.5 if plane == selected_surface else 2.5)
		var centre := _quad_point(poly, 0.5, 0.5)
		draw_line(_quad_point(poly, 0.43, 0.5), _quad_point(poly, 0.57, 0.5), surface_colour, 3.0)
		draw_line(_quad_point(poly, 0.5, 0.43), _quad_point(poly, 0.5, 0.57), surface_colour, 3.0)
		draw_circle(centre, 9.0, surface_colour, false, 2.5)
		for corner in range(4):
			var selected = plane == active_plane and corner == active_corner
			draw_circle(poly[corner], 13.0 if selected else 9.0, surface_colour, false, 3.0)
			var corner_name: String = ["TL", "TR", "BR", "BL"][corner]
			var label_offset := Vector2(12.0 if corner in [0, 3] else -32.0, 22.0 if corner in [0, 1] else -12.0)
			draw_string(ThemeDB.fallback_font, poly[corner] + label_offset, corner_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, surface_colour)
		var label_position = poly[0] + Vector2(12, 24)
		draw_string(ThemeDB.fallback_font, label_position, "%d  %s" % [plane + 1, SURFACE_NAMES[plane]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, surface_colour)

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
	# Preserve the last known file before replacing it. RESET deliberately saves
	# its defaults, so this backup is the escape hatch for an accidental reset in
	# a dark projection room after a careful physical alignment.
	var previous = ConfigFile.new()
	if previous.load(CAL_PATH) == OK:
		previous.save(CAL_BACKUP_PATH)
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
	cfg.set_value("layout", "yaw_policy", "panorama_contiguous_v1")
	cfg.save(CAL_PATH)
	title.text = "%d-SURFACE CALIBRATION SAVED" % layout_surface_count

func _restore_calibration_backup():
	var backup = ConfigFile.new()
	if backup.load(CAL_BACKUP_PATH) != OK:
		title.text = "NO PREVIOUS CALIBRATION TO RESTORE"
		return
	if backup.save(CAL_PATH) != OK:
		title.text = "CALIBRATION RESTORE FAILED"
		return
	_reset_all_offsets()
	_load_calibration()
	_rescale_surfaces()
	_update_calibration_controls()
	title.text = "%d-SURFACE PREVIOUS CALIBRATION RESTORED" % layout_surface_count

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
	# Pre-contiguous calibration files stored independent pane yaw. Preserve the
	# centre view as the optical reference and migrate every pane to that yaw so a
	# legacy save cannot silently reopen panorama seams.
	_normalise_panorama_yaw(camera_yaw_adjust_three, 1)
	_normalise_panorama_yaw(camera_yaw_adjust_five, 1)


func _normalise_panorama_yaw(adjustments: Array, reference_index: int) -> void:
	if adjustments.is_empty():
		return
	var safe_index: int = clampi(reference_index, 0, adjustments.size() - 1)
	var reference_yaw: float = float(adjustments[safe_index])
	for i in range(adjustments.size()):
		adjustments[i] = reference_yaw


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
