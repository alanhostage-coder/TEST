extends Node

# Original ambient-world layer for PUA. It reads the road geometry already cached
# by MapStream and adds cheap, deterministic roadside life without missions or scores.
const MAX_PARKED := 28
const MAX_ROAMERS := 9
const MAX_PUDDLES := 30
const REBUILD_INTERVAL := 3.0

var world: Node3D
var car: Node3D
var root: Node3D
var built_signature := ""
var clock := 0.0
var vapour_clock := 0.0
var vapour_nodes: Array = []

func _ready():
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

func _clear_root():
	vapour_nodes.clear()
	for child in root.get_children():
		child.queue_free()

func _build_parked_life(segments: Array):
	var made := 0
	for i in range(segments.size()):
		if made >= MAX_PARKED:
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
		if made >= MAX_ROAMERS:
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
	var body = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	var van = seed % 5 == 0
	mesh.size = Vector3(1.86, 1.34 if van else 0.78, 4.55 if van else 4.05)
	body.mesh = mesh
	var shade = 0.075 + float((seed * 19) % 23) / 100.0
	body.material_override = _material(Color(shade, shade * 0.97, shade * 0.91), 0.56, 0.14)
	body.position.y = 0.30 if van else 0.0
	vehicle.add_child(body)
	if not van:
		var cabin = MeshInstance3D.new()
		var cabin_mesh = BoxMesh.new()
		cabin_mesh.size = Vector3(1.52, 0.48, 1.78)
		cabin.mesh = cabin_mesh
		cabin.position = Vector3(0, 0.55, 0.12)
		cabin.material_override = _material(Color(0.045, 0.065, 0.075), 0.22, 0.22)
		vehicle.add_child(cabin)
	return vehicle

func _build_wet_ground_memory(segments: Array):
	var wetness = float(car.get_meta("world_wetness", 0.0))
	var count = int(lerp(8.0, float(MAX_PUDDLES), clamp(wetness, 0.0, 1.0)))
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
	var anchors = [Vector3(135, 8, -165), Vector3(185, 18, 110), Vector3(-115, 5, -80)]
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
