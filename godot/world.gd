extends Node3D

var cells := {}
var traffic := []
var patrol
var patrol_axis := 0
var patrol_dir := 1.0
var patrol_interest := 0.0
var map_mode_active := false
var weather_sun_energy := 0.68
var map_root: Node3D
var map_segments: Array = []
var map_agents: Array = []
const CELL := 90.0

var asphalt_mat
var concrete_mat
var ground_mat
var garage_mat
var metal_mat
var marking_mat

func _ready():
	_make_materials()
	_make_ground()
	_make_landmarks()
	_spawn_traffic()
	_spawn_patrol()
	_bind_world_state()
	_bind_map_stream()
	for x in range(-1, 2):
		for y in range(-2, 1):
			_build_cell(Vector2i(x, y))

func _process(delta):
	var car = $Car
	if map_mode_active:
		_update_map_agents(delta)
		car.set_meta("patrol_interest", 0.0)
	else:
		_update_traffic(delta)
		_update_patrol(delta, car)
	_update_atmosphere(car)
	if not map_mode_active:
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
	marking_mat = _mat(Color(0.72, 0.70, 0.62), 0.74, 0.0)

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

func _road_rotated(parent: Node3D, pos: Vector3, length: float, width: float, angle: float):
	var mesh = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(width, 0.07, length)
	mesh.mesh = bm
	mesh.material_override = asphalt_mat
	mesh.position = pos
	mesh.rotation.y = angle
	parent.add_child(mesh)

func _visual_box(parent: Node3D, pos: Vector3, size: Vector3, material):
	var mesh = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material
	mesh.position = pos
	parent.add_child(mesh)

func _road_detail(parent: Node3D, seed: int):
	for k in range(-3, 4):
		_visual_box(parent, Vector3(0, 0.075, float(k) * 12.0), Vector3(0.18, 0.025, 5.0), marking_mat)
		_visual_box(parent, Vector3(float(k) * 12.0, 0.08, 0), Vector3(5.0, 0.025, 0.18), marking_mat)
	for corner in [Vector3(-10, 2.8, -10), Vector3(10, 2.8, -10), Vector3(-10, 2.8, 10), Vector3(10, 2.8, 10)]:
		_visual_box(parent, corner, Vector3(0.16, 5.6, 0.16), metal_mat)
	if seed % 3 == 0:
		var turn = -1.0 if seed % 2 == 0 else 1.0
		_road_rotated(parent, Vector3(22.0 * turn, 0.035, 22.0), 42.0, 6.5, turn * PI / 4.0)

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
	_road_detail(root, seed)
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
		var car = AnimatableBody3D.new()
		car.name = "Traffic_%02d" % i
		var mesh = MeshInstance3D.new()
		var body = BoxMesh.new()
		body.size = Vector3(1.8, 0.78, 4.0)
		mesh.mesh = body
		var shade = 0.12 + float((i * 17) % 30) / 100.0
		mesh.material_override = _mat(Color(shade, shade * 0.95, shade * 0.9), 0.46, 0.18)
		car.add_child(mesh)
		var collision = CollisionShape3D.new()
		var collision_shape = BoxShape3D.new()
		collision_shape.size = Vector3(1.8, 0.78, 4.0)
		collision.shape = collision_shape
		car.add_child(collision)
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

func _spawn_patrol():
	patrol = AnimatableBody3D.new()
	patrol.name = "Patrol"
	var mesh = MeshInstance3D.new()
	var body = BoxMesh.new()
	body.size = Vector3(1.92, 0.82, 4.3)
	mesh.mesh = body
	mesh.material_override = _mat(Color(0.055, 0.075, 0.095), 0.38, 0.42)
	patrol.add_child(mesh)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.92, 0.82, 4.3)
	collision.shape = shape
	patrol.add_child(collision)
	_visual_box(patrol, Vector3(-0.34, 0.57, 0), Vector3(0.55, 0.12, 0.22), _mat(Color(0.72, 0.05, 0.04), 0.25, 0.15))
	patrol.get_child(patrol.get_child_count() - 1).name = "BarRed"
	_visual_box(patrol, Vector3(0.34, 0.57, 0), Vector3(0.55, 0.12, 0.22), _mat(Color(0.05, 0.14, 0.78), 0.25, 0.15))
	patrol.get_child(patrol.get_child_count() - 1).name = "BarBlue"
	patrol.position = Vector3(3.2, 0.45, -135.0)
	patrol.rotation.y = PI
	add_child(patrol)

func _update_patrol(delta, car):
	if patrol == null:
		return
	var offset = car.global_position - patrol.global_position
	offset.y = 0.0
	if offset.length() < 68.0 and (abs(car.speed) > 25.0 or car.impact_kick > 0.45):
		patrol_interest = 12.0
	else:
		patrol_interest = max(0.0, patrol_interest - delta)

	var patrol_speed = 13.0 if patrol_interest > 0.0 else 8.0
	var axis_position = patrol.position.z if patrol_axis == 0 else patrol.position.x
	var near_crossing = abs(fposmod(axis_position + 45.0, 90.0) - 45.0) < 2.5

	if patrol_interest > 0.0:
		if patrol_axis == 0 and near_crossing and abs(offset.x) > 10.0:
			patrol_axis = 1
			patrol_dir = sign(offset.x)
			if patrol_dir == 0.0:
				patrol_dir = 1.0
			patrol.position.z = round(patrol.position.z / CELL) * CELL + (3.2 if patrol_dir > 0.0 else -3.2)
		elif patrol_axis == 1 and near_crossing and abs(offset.z) > 10.0:
			patrol_axis = 0
			patrol_dir = sign(offset.z)
			if patrol_dir == 0.0:
				patrol_dir = 1.0
			patrol.position.x = round(patrol.position.x / CELL) * CELL + (-3.2 if patrol_dir > 0.0 else 3.2)
		elif patrol_axis == 0 and abs(offset.z) > 2.0:
			patrol_dir = sign(offset.z)
		elif patrol_axis == 1 and abs(offset.x) > 2.0:
			patrol_dir = sign(offset.x)

	if patrol_axis == 0:
		patrol.position.z += patrol_dir * patrol_speed * delta
		patrol.rotation.y = PI if patrol_dir > 0.0 else 0.0
		if patrol.position.z > 420.0:
			patrol.position.z = -420.0
		elif patrol.position.z < -420.0:
			patrol.position.z = 420.0
	else:
		patrol.position.x += patrol_dir * patrol_speed * delta
		patrol.rotation.y = -PI / 2.0 if patrol_dir > 0.0 else PI / 2.0
		if patrol.position.x > 420.0:
			patrol.position.x = -420.0
		elif patrol.position.x < -420.0:
			patrol.position.x = 420.0

	var red = patrol.get_node_or_null("BarRed")
	var blue = patrol.get_node_or_null("BarBlue")
	if red and blue:
		if patrol_interest > 0.0:
			var flash = int(Time.get_ticks_msec() / 180) % 2 == 0
			red.visible = flash
			blue.visible = not flash
		else:
			red.visible = true
			blue.visible = true
	car.set_meta("patrol_interest", clamp(patrol_interest / 12.0, 0.0, 1.0))

func _update_atmosphere(car):
	var mast = Vector3(185, 0, 110)
	var distance = car.global_position.distance_to(mast)
	var radio_strength = clamp(1.0 - distance / 430.0, 0.0, 1.0)
	car.set_meta("radio_signal", radio_strength)
	$Sun.light_energy = weather_sun_energy * lerp(0.94, 1.06, radio_strength)
	var beacon = get_node_or_null("Transmitter/Beacon")
	if beacon:
		beacon.light_energy = 1.4 + 1.6 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))


func _bind_world_state():
	var world_state = get_node_or_null("WorldState")
	if world_state:
		world_state.changed.connect(_on_world_state_changed)
		_on_world_state_changed(world_state.state)

func _on_world_state_changed(state: Dictionary):
	var rain = clamp(float(state.get("rain", 0.0)) + float(state.get("precipitation", 0.0)), 0.0, 6.0)
	var wetness = clamp(rain / 2.5, 0.0, 1.0)
	var cloud = clamp(float(state.get("cloud", 60.0)) / 100.0, 0.0, 1.0)
	var visibility = clamp(float(state.get("visibility", 12000.0)), 800.0, 30000.0)
	var aqi = clamp(float(state.get("aqi", 25.0)), 0.0, 150.0)
	var wind = max(0.0, float(state.get("wind_speed", 12.0)))
	var wave = max(0.0, float(state.get("wave_height", 0.5)))
	asphalt_mat.roughness = lerp(0.34, 0.12, wetness)
	asphalt_mat.metallic = lerp(0.05, 0.18, wetness)
	weather_sun_energy = lerp(0.72, 0.34, cloud) * lerp(1.0, 0.84, wetness)
	$Sun.light_energy = weather_sun_energy
	var env = $WorldEnvironment.environment
	if env:
		env.fog_enabled = true
		var visibility_fog = clamp(1.0 - visibility / 22000.0, 0.0, 0.92)
		env.fog_density = 0.0045 + visibility_fog * 0.018 + clamp(aqi / 150.0, 0.0, 1.0) * 0.004
		env.fog_light_color = Color(0.39, 0.42, 0.42).lerp(Color(0.31, 0.34, 0.35), cloud)
	var car = get_node_or_null("Car")
	if car:
		car.set_meta("world_wetness", wetness)
		car.set_meta("world_wind_kph", wind)
		car.set_meta("world_wave_height", wave)
		car.set_meta("world_temperature", float(state.get("temperature", 8.0)))
		car.set_meta("world_data_source", state.get("source", "offline"))


func _bind_map_stream():
	var map_stream = get_node_or_null("MapStream")
	if map_stream:
		map_stream.map_ready.connect(_on_map_ready)
		if map_stream.data.get("roads", []).size() > 0 or map_stream.data.get("buildings", []).size() > 0:
			_on_map_ready(map_stream.data)

func _on_map_ready(map_data: Dictionary):
	var roads = map_data.get("roads", [])
	var buildings = map_data.get("buildings", [])
	if roads.is_empty() and buildings.is_empty():
		return
	map_mode_active = true
	for t in traffic:
		if t.has("node") and is_instance_valid(t["node"]):
			t["node"].visible = false
	if patrol and is_instance_valid(patrol):
		patrol.visible = false
	for key in cells.keys():
		var node = cells[key]
		if is_instance_valid(node):
			node.queue_free()
	cells.clear()
	if map_root and is_instance_valid(map_root):
		map_root.queue_free()
	map_root = Node3D.new()
	map_root.name = "OpenMapWorld"
	add_child(map_root)
	map_segments.clear()

	for road in roads:
		if not road is Dictionary:
			continue
		var points = road.get("points", [])
		var width = float(road.get("width", 5.0))
		var kind = str(road.get("kind", "road"))
		for i in range(points.size() - 1):
			if not points[i] is Array or not points[i + 1] is Array:
				continue
			if points[i].size() < 2 or points[i + 1].size() < 2:
				continue
			var a = Vector2(float(points[i][0]), float(points[i][1]))
			var b = Vector2(float(points[i + 1][0]), float(points[i + 1][1]))
			var road_delta = b - a
			var length = road_delta.length()
			if length < 2.0:
				continue
			var mid = (a + b) * 0.5
			var angle = atan2(road_delta.x, road_delta.y)
			_road_rotated(map_root, Vector3(mid.x, 0.035, mid.y), length + 1.0, width, angle)
			map_segments.append([[a.x, a.y], [b.x, b.y], width, kind])

	for building in buildings:
		if not building is Dictionary:
			continue
		var center = building.get("center", [])
		var size = building.get("size", [])
		if not center is Array or not size is Array or center.size() < 2 or size.size() < 2:
			continue
		var h = clamp(float(building.get("height", 6.0)), 3.0, 48.0)
		var sx = max(2.0, float(size[0]))
		var sz = max(2.0, float(size[1]))
		var tone_seed = fmod(abs(float(center[0]) * 0.013 + float(center[1]) * 0.021), 0.10)
		var tone = 0.22 + tone_seed
		var building_mat = _mat(Color(tone, tone * 1.015, tone * 1.025), 0.88, 0.0)
		_box(map_root, Vector3(float(center[0]), h * 0.5, float(center[1])), Vector3(sx, h, sz), building_mat)

	_add_map_furniture(map_root)
	_spawn_map_agents()

	var car = get_node_or_null("Car")
	if car:
		car.set_meta("map_data_source", map_data.get("source", "offline"))
		car.set_meta("map_road_count", roads.size())
		car.set_meta("map_building_count", buildings.size())
		car.set_meta("map_road_segments", map_segments)
		_snap_car_to_map_road(car, roads)


func _snap_car_to_map_road(car, roads: Array):
	var current = Vector2(car.global_position.x, car.global_position.z)
	var best = current
	var best_dist = INF
	for road in roads:
		if not road is Dictionary:
			continue
		var points = road.get("points", [])
		for point in points:
			if not point is Array or point.size() < 2:
				continue
			var p = Vector2(float(point[0]), float(point[1]))
			var d = current.distance_squared_to(p)
			if d < best_dist:
				best_dist = d
				best = p
	if best_dist < INF:
		car.global_position.x = best.x
		car.global_position.z = best.y
		car.global_position.y = max(car.global_position.y, 0.58)


func _spawn_map_agents():
	for agent in map_agents:
		if agent.has("node") and is_instance_valid(agent["node"]):
			agent["node"].queue_free()
	map_agents.clear()
	if map_segments.is_empty():
		return
	var count = min(18, map_segments.size())
	for i in range(count):
		var body = AnimatableBody3D.new()
		body.name = "MapTraffic_%02d" % i
		var mesh = MeshInstance3D.new()
		var car_mesh = BoxMesh.new()
		car_mesh.size = Vector3(1.78, 0.76, 3.9)
		mesh.mesh = car_mesh
		var shade = 0.10 + float((i * 23) % 34) / 100.0
		mesh.material_override = _mat(Color(shade, shade * 0.96, shade * 0.91), 0.44, 0.20)
		body.add_child(mesh)
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(1.78, 0.76, 3.9)
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		var seg_index = int((i * 17 + 5) % map_segments.size())
		var agent = {
			"node": body,
			"seg": seg_index,
			"t": fmod(0.13 + float(i) * 0.173, 0.94),
			"dir": -1.0 if i % 4 == 0 else 1.0,
			"speed": 7.0 + float((i * 7) % 9)
		}
		map_agents.append(agent)
		_place_map_agent(agent)

func _update_map_agents(delta):
	for agent in map_agents:
		if not agent.has("node") or not is_instance_valid(agent["node"]):
			continue
		var seg_index = int(agent.get("seg", 0))
		if seg_index < 0 or seg_index >= map_segments.size():
			continue
		var segment = map_segments[seg_index]
		var a = Vector2(float(segment[0][0]), float(segment[0][1]))
		var b = Vector2(float(segment[1][0]), float(segment[1][1]))
		var length = max(2.0, a.distance_to(b))
		var t = float(agent.get("t", 0.0))
		var direction = float(agent.get("dir", 1.0))
		t += direction * float(agent.get("speed", 9.0)) * delta / length
		if t >= 1.0:
			agent["t"] = 1.0
			_choose_next_map_segment(agent, b, seg_index)
		elif t <= 0.0:
			agent["t"] = 0.0
			_choose_next_map_segment(agent, a, seg_index)
		else:
			agent["t"] = t
		_place_map_agent(agent)

func _choose_next_map_segment(agent: Dictionary, junction: Vector2, current_index: int):
	var candidates: Array = []
	for i in range(map_segments.size()):
		if i == current_index:
			continue
		var seg = map_segments[i]
		var a = Vector2(float(seg[0][0]), float(seg[0][1]))
		var b = Vector2(float(seg[1][0]), float(seg[1][1]))
		if junction.distance_to(a) < 5.0:
			candidates.append([i, 1.0, 0.0])
		elif junction.distance_to(b) < 5.0:
			candidates.append([i, -1.0, 1.0])
	if candidates.is_empty():
		agent["dir"] = -float(agent.get("dir", 1.0))
		agent["t"] = clamp(float(agent.get("t", 0.0)), 0.02, 0.98)
		return
	var pick = candidates[int((Time.get_ticks_msec() / 173 + current_index * 7) % candidates.size())]
	agent["seg"] = int(pick[0])
	agent["dir"] = float(pick[1])
	agent["t"] = float(pick[2])

func _place_map_agent(agent: Dictionary):
	var seg_index = int(agent.get("seg", 0))
	if seg_index < 0 or seg_index >= map_segments.size():
		return
	var node = agent["node"]
	var segment = map_segments[seg_index]
	var a = Vector2(float(segment[0][0]), float(segment[0][1]))
	var b = Vector2(float(segment[1][0]), float(segment[1][1]))
	var t = clamp(float(agent.get("t", 0.0)), 0.0, 1.0)
	var p = a.lerp(b, t)
	var heading = (b - a).normalized() * float(agent.get("dir", 1.0))
	node.position = Vector3(p.x, 0.44, p.y)
	node.rotation.y = atan2(-heading.x, -heading.y)

func _add_map_furniture(parent: Node3D):
	var placed = 0
	for i in range(map_segments.size()):
		if placed >= 24 or i % 7 != 0:
			continue
		var segment = map_segments[i]
		var a = Vector2(float(segment[0][0]), float(segment[0][1]))
		var b = Vector2(float(segment[1][0]), float(segment[1][1]))
		var delta = b - a
		if delta.length() < 26.0:
			continue
		var width = float(segment[2])
		var normal = Vector2(-delta.y, delta.x).normalized()
		var side = -1.0 if placed % 2 == 0 else 1.0
		var p = (a + b) * 0.5 + normal * (width * 0.5 + 1.8) * side
		_visual_box(parent, Vector3(p.x, 2.8, p.y), Vector3(0.12, 5.6, 0.12), metal_mat)
		_visual_box(parent, Vector3(p.x, 5.55, p.y), Vector3(0.9, 0.12, 0.24), metal_mat)
		if placed % 3 == 0:
			var lamp = OmniLight3D.new()
			lamp.position = Vector3(p.x, 5.25, p.y)
			lamp.light_color = Color(1.0, 0.49, 0.20)
			lamp.light_energy = 0.72
			lamp.omni_range = 10.0
			lamp.shadow_enabled = false
			parent.add_child(lamp)
		placed += 1
