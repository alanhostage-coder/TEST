extends Node

# Keeps the behavioural and visible road graph faithful to the postcode-seeded OSM source.
# World rendering intentionally budgets detail, but tiny OSM edges can be the exact mouth
# of a junction, service entrance or roundabout connection. Preserve those links cheaply.
var _scene: Node
var _car: Node3D
var _map_stream: Node
var _last_signature := ""
var _visual_signature := ""
var _short_link_root: Node3D

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_bind_scene")

func _process(_delta):
	if not is_instance_valid(_scene) or not is_instance_valid(_car) or not is_instance_valid(_map_stream):
		_bind_scene()
		return
	_apply_exact_topology()

func _bind_scene():
	_scene = get_tree().current_scene
	if not _scene:
		return
	_car = _scene.get_node_or_null("Car")
	_map_stream = _scene.get_node_or_null("MapStream")
	_last_signature = ""
	_visual_signature = ""
	_short_link_root = null
	_apply_exact_topology()

func _apply_exact_topology():
	if not _car or not _map_stream:
		return
	var map_data = _map_stream.get("data")
	if not map_data is Dictionary:
		return
	var roads = map_data.get("roads", [])
	if not roads is Array or roads.is_empty():
		return
	var signature = "%s:%s:%s" % [roads.size(), int(map_data.get("updated_unix", 0)), str(map_data.get("start_postcode", ""))]
	if signature == _last_signature:
		return
	var exact_segments: Array = []
	var shortest := INF
	for road in roads:
		if not road is Dictionary:
			continue
		var points = road.get("points", [])
		if not points is Array or points.size() < 2:
			continue
		var width = float(road.get("width", 5.0))
		var kind = str(road.get("kind", "road"))
		var oneway = str(road.get("oneway", "no")).to_lower()
		for i in range(points.size() - 1):
			var p0 = points[i]
			var p1 = points[i + 1]
			if not p0 is Array or not p1 is Array or p0.size() < 2 or p1.size() < 2:
				continue
			var a = Vector2(float(p0[0]), float(p0[1]))
			var b = Vector2(float(p1[0]), float(p1[1]))
			var length = a.distance_to(b)
			if length < 0.05:
				continue
			shortest = min(shortest, length)
			exact_segments.append([[a.x, a.y], [b.x, b.y], width, kind, oneway])
	if exact_segments.size() < 3:
		return
	_car.set_meta("map_road_segments", exact_segments)
	_car.set_meta("map_exact_topology", true)
	_car.set_meta("map_exact_segment_count", exact_segments.size())
	_car.set_meta("map_shortest_segment_m", shortest if shortest < INF else 0.0)
	_build_short_link_visuals(roads, signature)
	_last_signature = signature

func _build_short_link_visuals(roads: Array, signature: String):
	if signature == _visual_signature or not is_instance_valid(_scene):
		return
	if is_instance_valid(_short_link_root):
		_short_link_root.queue_free()
	_short_link_root = Node3D.new()
	_short_link_root.name = "ExactOSMShortLinks"
	_scene.add_child(_short_link_root)
	var asphalt = StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.055, 0.06, 0.065)
	asphalt.roughness = 0.34
	asphalt.metallic = 0.05
	var gravel = StandardMaterial3D.new()
	gravel.albedo_color = Color(0.28, 0.27, 0.24)
	gravel.roughness = 0.96
	var paving = StandardMaterial3D.new()
	paving.albedo_color = Color(0.30, 0.30, 0.29)
	paving.roughness = 0.91
	var made := 0
	# world.gd renders segments >=2 m. Fill only the exact missing interval, with no
	# kerbs, markings or clutter. This protects topology without decorative density.
	for road in roads:
		if not road is Dictionary:
			continue
		var points = road.get("points", [])
		if not points is Array or points.size() < 2:
			continue
		var width = max(1.2, float(road.get("width", 5.0)))
		var surface = str(road.get("surface", "")).to_lower()
		var material = asphalt
		if surface in ["gravel", "fine_gravel", "unpaved", "compacted"]:
			material = gravel
		elif surface in ["paving_stones", "sett", "cobblestone", "concrete"]:
			material = paving
		for i in range(points.size() - 1):
			var p0 = points[i]
			var p1 = points[i + 1]
			if not p0 is Array or not p1 is Array or p0.size() < 2 or p1.size() < 2:
				continue
			var a = Vector2(float(p0[0]), float(p0[1]))
			var b = Vector2(float(p1[0]), float(p1[1]))
			var delta = b - a
			var length = delta.length()
			if length < 0.05 or length >= 2.0:
				continue
			var mesh_instance = MeshInstance3D.new()
			var mesh = BoxMesh.new()
			mesh.size = Vector3(width, 0.068, length + 0.08)
			mesh_instance.mesh = mesh
			mesh_instance.material_override = material
			var mid = (a + b) * 0.5
			mesh_instance.position = Vector3(mid.x, 0.036, mid.y)
			mesh_instance.rotation.y = atan2(delta.x, delta.y)
			mesh_instance.visibility_range_end = 180.0
			_short_link_root.add_child(mesh_instance)
			made += 1
	_car.set_meta("map_exact_short_links_visible", made)
	_visual_signature = signature
