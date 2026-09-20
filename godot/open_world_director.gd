extends Node

# Original ambient-world layer for PUA. It reads the road geometry already cached
# by MapStream and adds cheap, deterministic roadside life without missions or scores.
const MAX_PARKED := 28
const MAX_ROAMERS := 9
const MAX_PUDDLES := 30
const MAX_SITUATIONS := 7
const MAX_ROAD_CLUTTER := 36
const SITUATION_RADIUS := 145.0
const REBUILD_INTERVAL := 3.0

var world: Node3D
var car: Node3D
var root: Node3D
var built_signature := ""
var clock := 0.0
var vapour_clock := 0.0
var vapour_nodes: Array = []
var situation_root: Node3D
var situation_signature := ""
var active_situations: Array = []
var low_spec_mode := false

func _ready():
	low_spec_mode = OS.has_feature("thinkpad_low")
	call_deferred("_bind_scene")

func _bind_scene():
	var scene = get_tree().current_scene
	if not scene:
		return
	world = scene as Node3D
	if world:
		car = world.get_node_or_null("Car")
		if not root:
			root = Node3D.new()
			root.name = "OpenWorldLife"
			world.add_child(root)

func _process(delta):
	if not world or not is_instance_valid(world) or not car or not is_instance_valid(car):
		_bind_scene()
		return
	clock += delta
	vapour_clock += delta
	if clock >= REBUILD_INTERVAL:
		clock = 0.0
		_try_build_from_live_roads()
	_update_vapour(delta)
	_update_situations(delta)

func _try_build_from_live_roads():
	if not car.has_meta("map_road_segments"):
		return
	var segments = car.get_meta("map_road_segments", [])
	if not segments is Array or segments.size() < 3:
		return
	var signature = "%s:%s" % [segments.size(), int(car.get_meta("pua_api_world_seed", 1))]
	if signature == built_signature:
		return
	built_signature = signature
	_clear_root()
	_build_parked_life(segments)
	_build_roaming_life(segments)
	_build_wet_ground_memory(segments)
	_build_industrial_vapour(segments)
	_build_situations(segments)
	_build_road_clutter(segments)

func _clear_root():
	vapour_nodes.clear()
	for child in root.get_children():
		child.queue_free()

func _build_parked_life(segments: Array):
	var made := 0
	for i in range(segments.size()):
		if made >= (12 if low_spec_mode else MAX_PARKED):
			break
		if i % 4 != 1:
			continue
		var seg = segments[i]
		if not seg is Array or seg.size() < 3:
			continue
		var a = Vector2(float(seg[0][0]), float(seg[0][1]))
		var b = Vector2(float(seg[1][0]), float(seg[1][1]))
		var d = b - a
		if d.length() < 14.0:
			continue
		var tangent = d.normalized()
		var normal = Vector2(-tangent.y, tangent.x)
		var side = -1.0 if i % 3 == 0 else 1.0
		var road_width = float(seg[2])
		var t = 0.28 + float((i * 37) % 44) / 100.0
		var p = a.lerp(b, t) + normal * side * (road_width * 0.5 + 1.35)
		var vehicle = _make_parked_vehicle(i)
		vehicle.position = Vector3(p.x, 0.43, p.y)
		vehicle.rotation.y = atan2(-tangent.x, -tangent.y) + (PI if side < 0.0 else 0.0)
		root.add_child(vehicle)
		made += 1


func _build_roaming_life(segments: Array):
	# Sparse deterministic moving traffic. No goals or scoring: it simply gives the
	# streamed road network a pulse while keeping mobile CPU/GPU cost predictable.
	var made := 0
	for i in range(0, segments.size(), 9):
		if made >= (4 if low_spec_mode else MAX_ROAMERS):
			break
		var seg = segments[i]
		if not seg is Array or seg.size() < 3:
			continue
		var a = Vector2(float(seg[0][0]), float(seg[0][1]))
		var b = Vector2(float(seg[1][0]), float(seg[1][1]))
		if a.distance_to(b) < 24.0:
			continue
		var vehicle = _make_parked_vehicle(100 + i)
		vehicle.name = "Roamer_%02d" % made
		root.add_child(vehicle)
		var tween = vehicle.create_tween().set_loops()
		var p0 = Vector3(a.x, 0.43, a.y)
		var p1 = Vector3(b.x, 0.43, b.y)
		vehicle.position = p0
		vehicle.look_at(p1, Vector3.UP)
		var seconds = clamp(a.distance_to(b) / (8.5 + float(i % 5)), 3.5, 13.0)
		tween.tween_property(vehicle, "position", p1, seconds).set_trans(Tween.TRANS_LINEAR)
		tween.tween_callback(func(): vehicle.look_at(p0, Vector3.UP))
		tween.tween_property(vehicle, "position", p0, seconds).set_trans(Tween.TRANS_LINEAR)
		tween.tween_callback(func(): vehicle.look_at(p1, Vector3.UP))
		made += 1

func _make_parked_vehicle(seed: int) -> Node3D:
	var vehicle = Node3D.new()
	vehicle.name = "Parked_%02d" % seed
	var van = seed % 5 == 0
	var shade = 0.075 + float((seed * 19) % 23) / 100.0
	var paint = _material(Color(shade, shade * 0.97, shade * 0.91), 0.50, 0.18)
	var glass = _material(Color(0.035, 0.055, 0.065), 0.18, 0.18)
	var tyre = _material(Color(0.022, 0.024, 0.025), 0.94, 0.01)

	var body = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(1.86, 0.66 if not van else 0.86, 4.10 if not van else 4.58)
	body.mesh = mesh
	body.material_override = paint
	body.position.y = 0.05 if not van else 0.18
	vehicle.add_child(body)

	var cabin = MeshInstance3D.new()
	var cabin_mesh = BoxMesh.new()
	cabin_mesh.size = Vector3(1.50, 0.58 if not van else 1.02, 1.72 if not van else 2.15)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0, 0.58 if not van else 0.84, 0.10 if not van else 0.22)
	cabin.material_override = glass
	cabin.visibility_range_end = 115.0
	vehicle.add_child(cabin)

	if not van:
		var roof = MeshInstance3D.new()
		var roof_mesh = BoxMesh.new()
		roof_mesh.size = Vector3(1.42, 0.09, 1.50)
		roof.mesh = roof_mesh
		roof.position = Vector3(0, 0.88, 0.12)
		roof.material_override = paint
		roof.visibility_range_end = 115.0
		vehicle.add_child(roof)

	for z in [-1.28, 1.28]:
		for x in [-0.92, 0.92]:
			var wheel = MeshInstance3D.new()
			var wheel_mesh = CylinderMesh.new()
			wheel_mesh.top_radius = 0.29
			wheel_mesh.bottom_radius = 0.29
			wheel_mesh.height = 0.17
			wheel.mesh = wheel_mesh
			wheel.position = Vector3(x, -0.12, z if not van else z * 1.12)
			wheel.rotation.z = PI * 0.5
			wheel.material_override = tyre
			wheel.visibility_range_end = 80.0
			vehicle.add_child(wheel)
	return vehicle

func _build_wet_ground_memory(segments: Array):
	var wetness = float(car.get_meta("world_wetness", 0.0))
	var puddle_cap = 12 if low_spec_mode else MAX_PUDDLES
	var count = int(lerp(4.0, float(puddle_cap), clamp(wetness, 0.0, 1.0)))
	for i in range(min(count, segments.size())):
		var seg = segments[(i * 7 + 3) % segments.size()]
		if not seg is Array or seg.size() < 2:
			continue
		var a = Vector2(float(seg[0][0]), float(seg[0][1]))
		var b = Vector2(float(seg[1][0]), float(seg[1][1]))
		if a.distance_to(b) < 9.0:
			continue
		var p = a.lerp(b, 0.18 + float((i * 31) % 64) / 100.0)
		var puddle = MeshInstance3D.new()
		var pm = PlaneMesh.new()
		pm.size = Vector2(1.4 + float(i % 4) * 0.8, 0.65 + float((i * 3) % 4) * 0.45)
		puddle.mesh = pm
		puddle.position = Vector3(p.x, 0.082, p.y)
		puddle.rotation.y = float(i * 47) * 0.0174533
		puddle.material_override = _material(Color(0.09, 0.105, 0.11, 0.68), 0.08, 0.42, true)
		root.add_child(puddle)

func _build_industrial_vapour(segments: Array):
	# Cheap found-photo atmosphere: translucent drifting cards around industrial edges.
	var anchors = [Vector3(135, 8, -165)] if low_spec_mode else [Vector3(135, 8, -165), Vector3(185, 18, 110), Vector3(-115, 5, -80)]
	for i in range(anchors.size()):
		for j in range(3):
			var vapour = MeshInstance3D.new()
			var quad = QuadMesh.new()
			quad.size = Vector2(5.5 + j * 2.0, 3.2 + j * 1.1)
			vapour.mesh = quad
			vapour.position = anchors[i] + Vector3(j * 2.3, j * 2.8, -j * 1.7)
			vapour.rotation.y = float(i) * 1.7 + float(j) * 0.55
			vapour.material_override = _material(Color(0.54, 0.55, 0.53, 0.075), 1.0, 0.0, true)
			root.add_child(vapour)
			vapour_nodes.append({"node": vapour, "phase": float(i * 3 + j), "base": vapour.position})

func _update_vapour(delta):
	if vapour_nodes.is_empty():
		return
	var wind = float(car.get_meta("world_wind_kph", 10.0)) if car else 10.0
	var drift = clamp(wind / 80.0, 0.05, 0.55)
	var t = Time.get_ticks_msec() * 0.001
	for item in vapour_nodes:
		var node = item.get("node")
		if not is_instance_valid(node):
			continue
		var phase = float(item.get("phase", 0.0))
		var base: Vector3 = item.get("base", Vector3.ZERO)
		node.position = base + Vector3(sin(t * 0.21 + phase) * 2.4, fmod(t * drift + phase * 1.7, 7.0), cos(t * 0.17 + phase) * 1.4)
		node.scale = Vector3.ONE * (0.82 + 0.18 * sin(t * 0.13 + phase))



func _build_road_clutter(segments: Array):
	# Mundane scale cues do more for realism than expensive effects: drains, patched
	# asphalt, bollards and verge weeds are sparse, deterministic and cheap.
	var seed = abs(int(car.get_meta("pua_api_world_seed", 1)))
	var made := 0
	for i in range(segments.size()):
		if made >= (18 if low_spec_mode else MAX_ROAD_CLUTTER):
			break
		if (i + seed) % 5 != 0:
			continue
		var seg = segments[i]
		if not seg is Array or seg.size() < 3:
			continue
		var a = Vector2(float(seg[0][0]), float(seg[0][1]))
		var b = Vector2(float(seg[1][0]), float(seg[1][1]))
		var d = b - a
		if d.length() < 10.0:
			continue
		var tangent = d.normalized()
		var normal = Vector2(-tangent.y, tangent.x)
		var width = float(seg[2])
		var t = 0.16 + float((seed + i * 29) % 68) / 100.0
		var p = a.lerp(b, t)
		var kind = (seed + i * 7) % 4
		if kind == 0:
			var patch = MeshInstance3D.new()
			var pm = PlaneMesh.new()
			pm.size = Vector2(1.2 + float(i % 4) * 0.65, 2.1 + float((i + 2) % 5) * 0.7)
			patch.mesh = pm
			patch.position = Vector3(p.x, 0.086, p.y)
			patch.rotation.y = atan2(tangent.x, tangent.y) + float((i % 3) - 1) * 0.08
			patch.material_override = _material(Color(0.035, 0.039, 0.041), 0.43, 0.02)
			root.add_child(patch)
		elif kind == 1:
			var side = -1.0 if i % 2 == 0 else 1.0
			var edge = p + normal * side * (width * 0.5 - 0.22)
			var drain = MeshInstance3D.new()
			var dm = BoxMesh.new()
			dm.size = Vector3(0.42, 0.025, 0.72)
			drain.mesh = dm
			drain.position = Vector3(edge.x, 0.095, edge.y)
			drain.rotation.y = atan2(tangent.x, tangent.y)
			drain.material_override = _material(Color(0.055, 0.06, 0.06), 0.50, 0.55)
			root.add_child(drain)
		elif kind == 2:
			var side = -1.0 if i % 2 == 0 else 1.0
			var edge = p + normal * side * (width * 0.5 + 0.7)
			var bollard = MeshInstance3D.new()
			var bm = CylinderMesh.new()
			bm.top_radius = 0.08
			bm.bottom_radius = 0.11
			bm.height = 0.82
			bollard.mesh = bm
			bollard.position = Vector3(edge.x, 0.41, edge.y)
			bollard.material_override = _material(Color(0.16, 0.17, 0.17), 0.62, 0.20)
			root.add_child(bollard)
		else:
			var side = -1.0 if i % 2 == 0 else 1.0
			var edge = p + normal * side * (width * 0.5 + 0.45)
			for j in range(3):
				var weed = MeshInstance3D.new()
				var qm = QuadMesh.new()
				qm.size = Vector2(0.16 + j * 0.05, 0.30 + j * 0.09)
				weed.mesh = qm
				weed.position = Vector3(edge.x + normal.x * j * 0.12, 0.16, edge.y + normal.y * j * 0.12)
				weed.rotation.y = atan2(normal.x, normal.y) + j * 0.55
				weed.material_override = _material(Color(0.12, 0.16, 0.075), 0.95, 0.0)
				root.add_child(weed)
		made += 1

func _build_situations(segments: Array):
	# Unannounced world situations: things the player notices rather than activates.
	# Their selection is deterministic for the current PUA world seed, so returning
	# during the same world state feels consistent without becoming a mission system.
	active_situations.clear()
	if situation_root and is_instance_valid(situation_root):
		situation_root.queue_free()
	situation_root = Node3D.new()
	situation_root.name = "UnexplainedSituations"
	root.add_child(situation_root)
	var seed = abs(int(car.get_meta("pua_api_world_seed", 1)))
	var situation_cap = 4 if low_spec_mode else MAX_SITUATIONS
	var count = min(situation_cap, max(2 if low_spec_mode else 3, int(segments.size() / 18)))
	for n in range(count):
		var index = (seed + n * 37 + n * n * 11) % segments.size()
		var seg = segments[index]
		if not seg is Array or seg.size() < 3:
			continue
		var a = Vector2(float(seg[0][0]), float(seg[0][1]))
		var b = Vector2(float(seg[1][0]), float(seg[1][1]))
		var d = b - a
		if d.length() < 18.0:
			continue
		var tangent = d.normalized()
		var normal = Vector2(-tangent.y, tangent.x)
		var side = -1.0 if ((seed >> (n % 12)) & 1) == 0 else 1.0
		var road_width = float(seg[2])
		var p = a.lerp(b, 0.30 + float((seed + n * 19) % 40) / 100.0)
		p += normal * side * (road_width * 0.5 + 3.6)
		var node = Node3D.new()
		node.name = "Situation_%02d" % n
		node.position = Vector3(p.x, 0.0, p.y)
		node.rotation.y = atan2(-tangent.x, -tangent.y)
		situation_root.add_child(node)
		var kind = (seed + n * 5) % 4
		if kind == 0:
			_make_gathering(node, seed + n)
		elif kind == 1:
			_make_service_scene(node, seed + n)
		elif kind == 2:
			_make_abandoned_scene(node, seed + n)
		else:
			_make_light_scene(node, seed + n)
		active_situations.append({"node": node, "kind": kind, "phase": float((seed + n * 13) % 100) * 0.1})

func _make_gathering(parent: Node3D, seed: int):
	var amount = 2 + seed % 3
	for i in range(amount):
		var vehicle = _make_parked_vehicle(seed + i * 17)
		vehicle.position = Vector3((float(i) - float(amount - 1) * 0.5) * 2.7, 0.43, -float(i % 2) * 2.2)
		vehicle.rotation.y = PI * 0.5 + float((i % 2) * 2 - 1) * 0.12
		parent.add_child(vehicle)
	var lamp = OmniLight3D.new()
	lamp.position = Vector3(0, 2.2, -1.0)
	lamp.light_color = Color(1.0, 0.48, 0.18)
	lamp.light_energy = 1.35
	lamp.omni_range = 13.0
	lamp.shadow_enabled = false
	parent.add_child(lamp)

func _make_service_scene(parent: Node3D, seed: int):
	var van = _make_parked_vehicle(seed * 3 + 5)
	van.position = Vector3(-1.8, 0.43, 0)
	van.rotation.y = PI * 0.5
	parent.add_child(van)
	for i in range(3):
		var marker = MeshInstance3D.new()
		var mesh = CylinderMesh.new()
		mesh.top_radius = 0.08
		mesh.bottom_radius = 0.28
		mesh.height = 0.65
		marker.mesh = mesh
		marker.position = Vector3(1.4 + i * 1.1, 0.33, -0.8 + i * 0.35)
		marker.material_override = _material(Color(0.78, 0.30, 0.045), 0.72, 0.0)
		parent.add_child(marker)

func _make_abandoned_scene(parent: Node3D, seed: int):
	var vehicle = _make_parked_vehicle(seed + 401)
	vehicle.position = Vector3(0, 0.43, 0)
	vehicle.rotation.y = PI * 0.5 + 0.22
	parent.add_child(vehicle)
	var beacon = OmniLight3D.new()
	beacon.position = Vector3(-0.72, 0.82, -0.3)
	beacon.light_color = Color(1.0, 0.22, 0.04)
	beacon.light_energy = 0.9
	beacon.omni_range = 7.0
	beacon.shadow_enabled = false
	parent.add_child(beacon)

func _make_light_scene(parent: Node3D, seed: int):
	var pole = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.13, 5.2, 0.13)
	pole.mesh = mesh
	pole.position.y = 2.6
	pole.material_override = _material(Color(0.16, 0.17, 0.17), 0.6, 0.45)
	parent.add_child(pole)
	var lamp = OmniLight3D.new()
	lamp.position = Vector3(0, 5.0, 0)
	lamp.light_color = Color(1.0, 0.38 + float(seed % 20) * 0.01, 0.13)
	lamp.light_energy = 2.0
	lamp.omni_range = 18.0
	lamp.shadow_enabled = false
	parent.add_child(lamp)

func _update_situations(delta: float):
	if active_situations.is_empty() or not car:
		return
	var t = Time.get_ticks_msec() * 0.001
	var nearest_kind := -1
	var nearest_distance := INF
	for item in active_situations:
		var node = item.get("node")
		if not is_instance_valid(node):
			continue
		var distance = car.global_position.distance_to(node.global_position)
		node.visible = distance < SITUATION_RADIUS
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_kind = int(item.get("kind", -1))
		if node.visible and int(item.get("kind", -1)) == 2:
			for child in node.get_children():
				if child is OmniLight3D:
					child.light_energy = 0.45 + 0.75 * (0.5 + 0.5 * sin(t * 4.3 + float(item.get("phase", 0.0))))
	car.set_meta("near_world_situation", nearest_kind if nearest_distance < 32.0 else -1)
	car.set_meta("world_situation_distance", nearest_distance)


func _material(color: Color, roughness: float, metallic: float, transparent := false) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
