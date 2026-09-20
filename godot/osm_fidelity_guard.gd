extends Node

# Keeps the behavioural road graph faithful to the postcode-seeded OSM source.
# World rendering may skip tiny segments for draw-call reasons, but traffic and
# junction logic should never lose those links: short OSM edges often encode the
# exact mouth of a junction, service entrance or roundabout connection.
var _scene: Node
var _car: Node3D
var _map_stream: Node
var _last_signature := ""

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
	_last_signature = signature
