extends Control

# PARKVIEW BAY MODE
# Three shared-world cameras turn the closed canted shutters into a wide forward view.
# Starting physical estimate from the photographed bay and comparable Pittville sash drawings.
const BAY_WIDTH_M := 2.90
const BAY_HEIGHT_M := 2.30
const LEFT_WIDTH_M := 0.78
const CENTRE_WIDTH_M := 1.34
const RIGHT_WIDTH_M := 0.78
const SIDE_YAW_DEG := 32.0
const RENDER_SCALE := 0.72

var mode := 0 # 0 normal, 1 cab, 2 calibration
var car: Node3D
var source_camera: Camera3D
var viewports: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var panels: Array[TextureRect] = []
var button: Button
var title: Label

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	car = get_node_or_null("../Car")
	if car:
		source_camera = car.get_node_or_null("CameraRig/Camera3D")
	_build_button()
	_build_views()
	_set_mode(0)

func _build_button():
	button = Button.new()
	button.text = "BAY"
	button.position = Vector2(18, 45)
	button.size = Vector2(112, 42)
	button.modulate = Color(1, 1, 1, 0.78)
	button.pressed.connect(_cycle_mode)
	add_child(button)
	title = Label.new()
	title.position = Vector2(145, 54)
	title.text = ""
	title.modulate = Color(1, 1, 1, 0.58)
	add_child(title)

func _build_views():
	var ratios = [LEFT_WIDTH_M / BAY_WIDTH_M, CENTRE_WIDTH_M / BAY_WIDTH_M, RIGHT_WIDTH_M / BAY_WIDTH_M]
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
		var panel = TextureRect.new()
		panel.name = "Panel%d" % i
		panel.texture = viewport.get_texture()
		panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		panel.stretch_mode = TextureRect.STRETCH_SCALE
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		panels.append(panel)
	_rescale_panels()

func _notification(what):
	if what == NOTIFICATION_RESIZED and not panels.is_empty():
		_rescale_panels()

func _rescale_panels():
	var size = get_viewport_rect().size
	if size.x < 2.0 or size.y < 2.0:
		return
	var ratios = [LEFT_WIDTH_M / BAY_WIDTH_M, CENTRE_WIDTH_M / BAY_WIDTH_M, RIGHT_WIDTH_M / BAY_WIDTH_M]
	var x := 0.0
	for i in range(3):
		var w = size.x * ratios[i]
		panels[i].position = Vector2(x, 0)
		panels[i].size = Vector2(w + 1.0, size.y)
		viewports[i].size = Vector2i(max(160, int(w * RENDER_SCALE)), max(240, int(size.y * RENDER_SCALE)))
		x += w

func _cycle_mode():
	_set_mode((mode + 1) % 3)

func _set_mode(value: int):
	mode = value
	var active = mode > 0
	for panel in panels:
		panel.visible = active
	if source_camera:
		source_camera.current = not active
	if mode == 0:
		button.text = "BAY"
		title.text = ""
	elif mode == 1:
		button.text = "CAB"
		title.text = "PARKVIEW BAY · OUTWARD VIEW"
	else:
		button.text = "CAL"
		title.text = "PARKVIEW BAY · %.2fm × %.2fm · 3 PLANE CAL" % [BAY_WIDTH_M, BAY_HEIGHT_M]
	queue_redraw()

func _process(_delta):
	if mode == 0 or not car:
		return
	var cab_transform = car.global_transform
	# Put the virtual eye just ahead of the vehicle body: windscreen/front-cab viewpoint.
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
	var left_x = size.x * LEFT_WIDTH_M / BAY_WIDTH_M
	var right_x = size.x * (LEFT_WIDTH_M + CENTRE_WIDTH_M) / BAY_WIDTH_M
	var line = Color(1.0, 0.72, 0.28, 0.82)
	var faint = Color(1.0, 1.0, 1.0, 0.22)
	draw_line(Vector2(left_x, 0), Vector2(left_x, size.y), line, 3.0)
	draw_line(Vector2(right_x, 0), Vector2(right_x, size.y), line, 3.0)
	for i in range(1, 10):
		var x = size.x * float(i) / 10.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), faint, 1.0)
	for j in range(1, 8):
		var y = size.y * float(j) / 8.0
		draw_line(Vector2(0, y), Vector2(size.x, y), faint, 1.0)
	draw_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), line, 2.0)
	draw_circle(size * 0.5, 8.0, line, false, 2.0)
