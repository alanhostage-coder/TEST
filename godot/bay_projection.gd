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
const SIDE_YAW_DEG := 32.0
const RENDER_SCALE := 0.72
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
var button: Button
var save_button: Button
var reset_button: Button
var title: Label

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	car = get_node_or_null("../Car")
	if car:
		source_camera = car.get_node_or_null("CameraRig/Camera3D")
	_reset_offsets(false)
	_load_calibration()
	_build_buttons()
	_build_views()
	_set_mode(0)

func _build_buttons():
	button = Button.new()
	button.text = "BAY"
	button.position = Vector2(18, 45)
	button.size = Vector2(112, 42)
	button.modulate = Color(1, 1, 1, 0.80)
	button.pressed.connect(_cycle_mode)
	add_child(button)

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

	title = Label.new()
	title.position = Vector2(145, 54)
	title.text = ""
	title.modulate = Color(1, 1, 1, 0.62)
	add_child(title)

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
		camera.far = 900.0
		camera.fov = 63.0
		viewport.add_child(camera)
		viewports.append(viewport)
		cameras.append(camera)

		var surface = Polygon2D.new()
		surface.name = "ShutterPlane%d" % i
		surface.texture = viewport.get_texture()
		surface.uv = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		add_child(surface)
		surfaces.append(surface)
	_rescale_surfaces()

func _notification(what):
	if what == NOTIFICATION_RESIZED and not surfaces.is_empty():
		_rescale_surfaces()

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
		viewports[i].size = Vector2i(max(160, int(w * RENDER_SCALE)), max(240, int(size.y * RENDER_SCALE)))
		x += w
	queue_redraw()

func _cycle_mode():
	_set_mode((mode + 1) % 3)

func _set_mode(value: int):
	mode = value
	var active = mode > 0
	for surface in surfaces:
		surface.visible = active
	if source_camera:
		source_camera.current = not active
	if car:
		car.set_process_input(mode != 2)
	save_button.visible = mode == 2
	reset_button.visible = mode == 2
	active_plane = -1
	active_corner = -1
	if mode == 0:
		button.text = "BAY"
		title.text = ""
	elif mode == 1:
		button.text = "CAB"
		title.text = "PARKVIEW BAY · OUTWARD VIEW"
	else:
		button.text = "CAL"
		title.text = "DRAG CORNERS · SAVE WHEN LINES MEET SHUTTER EDGES"
	queue_redraw()

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
	var cab_transform = car.global_transform
	cab_transform.origin = car.to_global(Vector3(0.0, 1.42, -2.15))
	var yaws = [deg_to_rad(-SIDE_YAW_DEG), 0.0, deg_to_rad(SIDE_YAW_DEG)]
	for i in range(3):
		var t = cab_transform
		t.basis = Basis(Vector3.UP, yaws[i]) * cab_transform.basis
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
	cfg.set_value("bay", "side_yaw_deg", SIDE_YAW_DEG)
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
