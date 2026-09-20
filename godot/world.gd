extends Node3D

var cells := {}
var traffic := []
const CELL := 90.0

var asphalt_mat
var concrete_mat
var ground_mat
var garage_mat
var metal_mat

func _ready():
	_make_materials()
	_make_ground()
	_make_landmarks()
	_spawn_traffic()
	for x in range(-1, 2):
		for y in range(-2, 1):
			_build_cell(Vector2i(x, y))

func _process(delta):
	var car = $Car
	_update_traffic(delta)
	_update_atmosphere(car)
	var c = Vector2i(floor(car.global_position.x / CELL), floor(car.global_position.z / CELL))
	for x in range(c.x - 2, c.x + 3):
		for y in range(c.y - 2, c.y + 3):
			_build_cell(Vector2i(x, y))
	_trim_cells(c)

func _make_materials():
	asphalt_mat = _mat(Color(0.055, 0.06, 0.065), 0.34, 0.05)
	concrete_mat = _mat(Color(0.30, 0.31, 0.32), 0.86, 0.0)
	ground_mat = _mat(Color(0.16, 0.18, 0.14), 0.95, 0.0)
	garage_mat = _mat(Color(0.24, 0.25, 0.25), 0.72, 0.02)
	metal_mat = _mat(Color(0.17, 0.19, 0.20), 0.48, 0.32)

func _mat(color: Color, roughness: float, metallic: float):
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

func _box(parent: Node3D, pos: Vector3, size: Vector3, material = null):
	var body = StaticBody3D.new()
	var mesh = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material if material != null else concrete_mat
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.position = pos
	body.add_child(mesh)
	body.add_child(col)
	parent.add_child(body)
	return body

func _road(parent: Node3D, pos: Vector3, size: Vector3):
	var mesh = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = asphalt_mat
	mesh.position = pos
	parent.add_child(mesh)

func _build_cell(c: Vector2i):
	if cells.has(c):
		return
	var root = Node3D.new()
	root.name = "cell_%s_%s" % [c.x, c.y]
	add_child(root)
	root.position = Vector3(c.x * CELL, 0, c.y * CELL)
	cells[c] = root
	var seed = abs(c.x * 92821 + c.y * 68917)
	_road(root, Vector3(0, 0.02, 0), Vector3(15, 0.08, CELL))
	_road(root, Vector3(0, 0.025, 0), Vector3(CELL, 0.08, 15))
	for i in range(8):
		var side = -1.0 if i % 2 == 0 else 1.0
		var along = -34.0 + float((seed + i * 19) % 68)
		var w = 10.0 + float((seed + i * 7) % 12)
		var d = 8.0 + float((seed + i * 11) % 13)
		var h = 4.0 + float((seed + i * 3) % 6)
		var x = side * (24.0 + float((seed + i * 5) % 10))
		var tone = 0.24 + float((seed + i * 13) % 10) * 0.009
		var building_mat = _mat(Color(tone, tone * 1.01, tone * 1.02), 0.88, 0.0)
		_box(root, Vector3(x, h / 2.0, along), Vector3(w, h, d), building_mat)
	if seed % 3 == 0:
		_box(root, Vector3(27, 1.6, -25), Vector3(20, 3.2, 9), garage_mat)
	if seed % 4 == 0:
		_box(root, Vector3(-31, 10, 29), Vector3(0.8, 20, 0.8), metal_mat)

func _trim_cells(center: Vector2i):
	var remove := []
	for key in cells.keys():
		if abs(key.x - center.x) > 3 or abs(key.y - center.y) > 3:
			remove.append(key)
	for key in remove:
		var node = cells[key]
		cells.erase(key)
		node.queue_free()

func _make_ground():
	var ground = StaticBody3D.new()
	ground.name = "Ground"
	var mesh = MeshInstance3D.new()
	var plane = BoxMesh.new()
	plane.size = Vector3(1400, 0.4, 1400)
	mesh.mesh = plane
	mesh.material_override = ground_mat
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(1400, 0.4, 1400)
	col.shape = shape
	ground.position = Vector3(0, -0.24, 0)
	ground.add_child(mesh)
	ground.add_child(col)
	add_child(ground)

func _make_landmarks():
	var dock = Node3D.new()
	dock.name = "DockEdge"
	dock.position = Vector3(135, 0, -165)
	add_child(dock)
	_box(dock, Vector3(0, 4, 0), Vector3(44, 8, 18), concrete_mat)
	_box(dock, Vector3(17, 13, -2), Vector3(3, 26, 3), metal_mat)
	_box(dock, Vector3(-14, 2.5, 18), Vector3(24, 5, 12), garage_mat)

	var court = Node3D.new()
	court.name = "GarageCourt"
	court.position = Vector3(-115, 0, -80)
	add_child(court)
	for x in [-22.0, -11.0, 0.0, 11.0, 22.0]:
		_box(court, Vector3(x, 2.0, -18), Vector3(9, 4, 7), garage_mat)
	var garage_light = OmniLight3D.new()
	garage_light.name = "GarageLight"
	garage_light.position = Vector3(0, 4.2, -8)
	garage_light.light_color = Color(1.0, 0.63, 0.30)
	garage_light.light_energy = 2.2
	garage_light.omni_range = 22.0
	garage_light.shadow_enabled = false
	court.add_child(garage_light)

	var mast = Node3D.new()
	mast.name = "Transmitter"
	mast.position = Vector3(185, 0, 110)
	add_child(mast)
	_box(mast, Vector3(0, 24, 0), Vector3(1.2, 48, 1.2), metal_mat)
	_box(mast, Vector3(0, 45, 0), Vector3(9, 0.5, 0.5), metal_mat)
	var beacon = OmniLight3D.new()
	beacon.name = "Beacon"
	beacon.position = Vector3(0, 47, 0)
	beacon.light_color = Color(1.0, 0.12, 0.06)
	beacon.light_energy = 2.6
	beacon.omni_range = 10.0
	beacon.shadow_enabled = false
	mast.add_child(beacon)

func _spawn_traffic():
	for i in range(14):
		var car = Node3D.new()
		car.name = "Traffic_%02d" % i
		var mesh = MeshInstance3D.new()
		var body = BoxMesh.new()
		body.size = Vector3(1.8, 0.78, 4.0)
		mesh.mesh = body
		var shade = 0.12 + float((i * 17) % 30) / 100.0
		mesh.material_override = _mat(Color(shade, shade * 0.95, shade * 0.9), 0.46, 0.18)
		car.add_child(mesh)
		add_child(car)
		var axis = i % 2
		var direction = -1.0 if i % 3 == 0 else 1.0
		var road_index = int(i / 2) - 3
		var lane = -3.2 if direction < 0.0 else 3.2
		if axis == 0:
			car.position = Vector3(road_index * CELL + lane, 0.45, -300.0 + float((i * 53) % 600))
			car.rotation.y = 0.0 if direction < 0.0 else PI
		else:
			car.position = Vector3(-300.0 + float((i * 61) % 600), 0.45, road_index * CELL + lane)
			car.rotation.y = -PI / 2.0 if direction > 0.0 else PI / 2.0
		traffic.append({"node": car, "axis": axis, "direction": direction, "speed": 8.5 + float((i * 7) % 8)})

func _update_traffic(delta):
	for t in traffic:
		var node = t["node"]
		var direction = t["direction"]
		var speed = t["speed"]
		if t["axis"] == 0:
			node.position.z += direction * speed * delta
			if node.position.z > 360.0:
				node.position.z = -360.0
			elif node.position.z < -360.0:
				node.position.z = 360.0
		else:
			node.position.x += direction * speed * delta
			if node.position.x > 360.0:
				node.position.x = -360.0
			elif node.position.x < -360.0:
				node.position.x = 360.0

func _update_atmosphere(car):
	var mast = Vector3(185, 0, 110)
	var distance = car.global_position.distance_to(mast)
	var radio_strength = clamp(1.0 - distance / 430.0, 0.0, 1.0)
	car.set_meta("radio_signal", radio_strength)
	$Sun.light_energy = 0.60 + radio_strength * 0.10
	var beacon = get_node_or_null("Transmitter/Beacon")
	if beacon:
		beacon.light_energy = 1.4 + 1.6 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))
