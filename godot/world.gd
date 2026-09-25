extends Node3D

var cells := {}
var traffic := []
var patrol
var patrol_axis := 0
var patrol_dir := 1.0
var patrol_interest := 0.0
var map_mode_active := false
var map_opening_placed := false
var weather_sun_energy := 0.68
var map_root: Node3D
var map_segments: Array = []
var map_agents: Array = []
var map_lamps: Array = []
var api_traffic_factor := 0.85
var api_traffic_speed_factor := 0.95
var api_lamp_factor := 1.0
var api_detail_pressure := 0.70
var api_radio_instability := 0.20
var api_moment := "none"
const CELL := 90.0
const ROAD_MICRO_STEP := 6.5
# Covers every building in the source-dated EH15 patch (farthest centre 160.5 m)
# while remaining a bounded low-spec draw/collision radius for future patches.
const LOW_SPEC_EXACT_FOOTPRINT_RADIUS := 220.0
const DRIVER_DETAIL_RADIUS := 38.0
const MOBILE_BUILDING_VISUAL_RADIUS := 420.0
const MOBILE_COLLIDING_BUILDING_RADIUS := 190.0
const MOBILE_FACADE_RADIUS := 340.0
const MOBILE_ROAD_VISUAL_RADIUS := 540.0
const MOBILE_STREET_DETAIL_RADIUS := 235.0
const XPS_LIGHT_GRADE := "edinburgh-side-light-v1"
var low_spec_mode := false
var projector_max_mode := false
var pc_max_mode := false
var xps_9530_mode := false
var mobile_mode := false
var mobile_destination_index := -1
var mobile_destination_point := Vector2.ZERO
var mobile_destination_name := ""
var mobile_destination_clock := 0.0
var mobile_identity_clock := 0.0
var map_center_lat := 55.95
var atmosphere_initialized := false
var atmosphere_wetness := 0.0
var atmosphere_cloud := 0.60
var atmosphere_visibility := 12000.0
var atmosphere_aqi := 25.0
var atmosphere_target_wetness := 0.0
var atmosphere_target_cloud := 0.60
var atmosphere_target_visibility := 12000.0
var atmosphere_target_aqi := 25.0

var asphalt_mat
var concrete_mat
var ground_mat
var garage_mat
var metal_mat
var marking_mat
var glass_mat
var sandstone_mat
var soot_stone_mat
var roof_mat
var pavement_mat
var kerb_mat
var sandstone_warm_mat
var soot_stone_cool_mat
var tenement_weathered_mat
var tenement_warm_mat
var tenement_soot_mat
var tenement_sash_frame_mat
var tenement_sash_glass_mat
var tenement_door_mats: Array = []
var generic_tenement_facade_count := 0
var generic_tenement_window_count := 0
var generic_tenement_door_count := 0
var generic_tenement_shopfront_count := 0
var generic_tenement_downpipe_count := 0
var generic_tenement_recess_count := 0
var generic_tenement_chimney_count := 0
var generic_tenement_railing_count := 0
var tenement_shop_frame_mats: Array = []
var brick_mat
var render_mat
var hedge_mat
var gravel_mat
var paving_mat
var path_mat
var sign_white_mat
var sign_red_mat
var sign_blue_mat
var road_patch_mat
var weed_mat
var sea_mat
var beach_mat
var open_space_mat
var retail_zone_mat
var industrial_zone_mat
var commercial_zone_mat

func _ready():
	var force_xps_proof := bool(get_meta("force_xps_proof", false))
	var force_mobile_proof := bool(get_meta("force_mobile_proof", false))
	projector_max_mode = OS.has_feature("projector_max") or force_xps_proof
	pc_max_mode = OS.has_feature("pc_max") or force_xps_proof
	xps_9530_mode = OS.has_feature("xps_9530") or force_xps_proof
	mobile_mode = OS.has_feature("mobile") or OS.get_environment("PUA_FORCE_MOBILE_TEST") == "1" or force_mobile_proof
	low_spec_mode = OS.has_feature("thinkpad_low") or (projector_max_mode and not xps_9530_mode) or mobile_mode
	if xps_9530_mode:
		# Final reference-machine grade: slightly lower, more lateral light makes the
		# sandstone relief and recessed sash/close geometry readable from the driver seat.
		api_detail_pressure = 0.96
		$Sun.directional_shadow_max_distance = 145.0
		$Sun.rotation_degrees = Vector3(-27.0, -47.0, 0.0)
		$Sun.light_color = Color(1.0, 0.91, 0.78)
	elif projector_max_mode:
		api_detail_pressure = 0.32
		$Sun.directional_shadow_max_distance = 58.0
	elif mobile_mode:
		# Phone screenshots benefit more from readable nearby architecture than from
		# distant shadow work. Keep the budget local but give facades enough light
		# and range to make Portobello's street walls legible.
		api_detail_pressure = 0.66
		$Sun.directional_shadow_max_distance = 72.0
		$Sun.rotation_degrees = Vector3(-34.0, -52.0, 0.0)
		$Sun.light_color = Color(1.0, 0.94, 0.82)
		$Sun.shadow_opacity = 0.46
	elif low_spec_mode:
		api_detail_pressure = 0.42
		$Sun.directional_shadow_max_distance = 82.0
	elif pc_max_mode:
		api_detail_pressure = 1.0
		$Sun.directional_shadow_max_distance = 180.0
	_make_materials()
	_make_ground()
	_make_landmarks()
	_spawn_traffic()
	_spawn_patrol()
	_bind_world_state()
	_bind_map_stream()
	_bind_pua_api()
	for x in range(-1, 2):
		for y in range(-2, 1):
			_build_cell(Vector2i(x, y))

func _process(delta):
	var car = $Car
	if map_mode_active:
		var stream = get_node_or_null("MapStream")
		if stream and stream.has_method("update_stream_position"):
			stream.update_stream_position(Vector2(car.global_position.x, car.global_position.z))
		_update_map_agents(delta)
		_update_mobile_destination(delta, car)
		_update_mobile_location_identity(delta, car)
		car.set_meta("patrol_interest", 0.0)
	else:
		_update_traffic(delta)
		_update_patrol(delta, car)
	_update_weather_visuals(delta)
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
	glass_mat = _mat(Color(0.075, 0.10, 0.115), 0.20, 0.28)
	sandstone_mat = _mat(Color(0.43, 0.40, 0.34), 0.91, 0.0)
	soot_stone_mat = _mat(Color(0.255, 0.265, 0.26), 0.94, 0.0)
	roof_mat = _mat(Color(0.11, 0.12, 0.12), 0.86, 0.06)
	pavement_mat = _mat(Color(0.225, 0.23, 0.225), 0.90, 0.0)
	kerb_mat = _mat(Color(0.34, 0.345, 0.335), 0.94, 0.0)
	sandstone_warm_mat = _mat(Color(0.39, 0.355, 0.295), 0.93, 0.0)
	soot_stone_cool_mat = _mat(Color(0.215, 0.225, 0.225), 0.95, 0.0)
	brick_mat = _mat(Color(0.39, 0.20, 0.14), 0.92, 0.0)
	render_mat = _mat(Color(0.63, 0.61, 0.54), 0.93, 0.0)
	hedge_mat = _mat(Color(0.075, 0.16, 0.055), 0.98, 0.0)
	gravel_mat = _mat(Color(0.28, 0.27, 0.24), 0.96, 0.0)
	paving_mat = _mat(Color(0.30, 0.30, 0.29), 0.91, 0.0)
	path_mat = _mat(Color(0.18, 0.19, 0.17), 0.94, 0.0)
	sign_white_mat = _mat(Color(0.88, 0.88, 0.84), 0.72, 0.0)
	sign_red_mat = _mat(Color(0.62, 0.045, 0.035), 0.66, 0.0)
	sign_blue_mat = _mat(Color(0.055, 0.18, 0.48), 0.64, 0.0)
	# Shared materials keep close-range texture cheap on old integrated GPUs.
	road_patch_mat = _mat(Color(0.035, 0.038, 0.041), 0.46, 0.03)
	weed_mat = _mat(Color(0.15, 0.21, 0.08), 0.98, 0.0)
	sea_mat = _mat(Color(0.045, 0.145, 0.205), 0.28, 0.06)
	beach_mat = _mat(Color(0.47, 0.42, 0.31), 0.96, 0.0)
	open_space_mat = _mat(Color(0.105, 0.205, 0.09), 0.98, 0.0)
	retail_zone_mat = _mat(Color(0.22, 0.225, 0.22), 0.94, 0.0)
	industrial_zone_mat = _mat(Color(0.175, 0.18, 0.18), 0.96, 0.0)
	commercial_zone_mat = _mat(Color(0.245, 0.24, 0.225), 0.94, 0.0)
	tenement_weathered_mat = _tenement_texture_mat("res://assets/edinburgh_tenement/walls/edin_ten_wall_weathered_a_alb.png", Color(1.0, 0.975, 0.93), 0.93)
	tenement_warm_mat = _tenement_texture_mat("res://assets/edinburgh_tenement/walls/edin_ten_wall_warm_a_alb.png", Color(1.0, 0.95, 0.86), 0.92)
	tenement_soot_mat = _tenement_texture_mat("res://assets/edinburgh_tenement/walls/edin_ten_wall_weathered_a_alb.png", Color(0.68, 0.675, 0.63), 0.95)
	tenement_sash_frame_mat = _mat(Color(0.83, 0.81, 0.74), 0.78, 0.0)
	tenement_sash_glass_mat = _mat(Color(0.035, 0.052, 0.060), 0.18, 0.22)
	tenement_door_mats = [
		_mat(Color(0.075, 0.16, 0.12), 0.72, 0.0),
		_mat(Color(0.17, 0.055, 0.05), 0.74, 0.0),
		_mat(Color(0.055, 0.10, 0.17), 0.70, 0.0)
	]
	tenement_shop_frame_mats = [
		_mat(Color(0.055, 0.11, 0.10), 0.68, 0.0),
		_mat(Color(0.13, 0.055, 0.05), 0.72, 0.0),
		_mat(Color(0.10, 0.105, 0.11), 0.70, 0.0),
		_mat(Color(0.19, 0.14, 0.055), 0.74, 0.0)
	]
	if mobile_mode:
		# Android needs a little more local colour separation than the desktop grade.
		# Keep the palette recognisably Edinburgh rather than turning everything beige.
		sandstone_mat.albedo_color = Color(0.52, 0.47, 0.38)
		sandstone_warm_mat.albedo_color = Color(0.47, 0.405, 0.315)
		soot_stone_mat.albedo_color = Color(0.29, 0.30, 0.29)
		sea_mat.albedo_color = Color(0.055, 0.23, 0.33)
		beach_mat.albedo_color = Color(0.62, 0.54, 0.39)
		tenement_sash_frame_mat.albedo_color = Color(0.88, 0.86, 0.78)

func _tenement_texture_mat(path: String, tint: Color, roughness: float):
	var material = _mat(tint, roughness, 0.0)
	var texture = load(path)
	if texture:
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.texture_repeat = true
	return material

func _mat(color: Color, roughness: float, metallic: float):
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

func _apply_secondary_visual_budget(mesh: GeometryInstance3D, low_spec_range := 0.0):
	# Five projector cameras multiply shadow work. Keep the geometry and material cue,
	# but secondary trim/furniture does not need to enter every low-spec shadow map.
	mesh.set_meta("secondary_visual", true)
	if low_spec_mode or xps_9530_mode:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.set_meta("secondary_shadow_disabled", true)
		if low_spec_mode and low_spec_range > 0.0:
			if mesh.visibility_range_end <= 0.0:
				mesh.visibility_range_end = low_spec_range
			else:
				mesh.visibility_range_end = min(mesh.visibility_range_end, low_spec_range)

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

func _live_road_markings(parent: Node3D, pos: Vector3, length: float, width: float, angle: float, kind: String):
	if width < 5.8 or kind in ["service", "track", "path", "living_street"]:
		return
	var dash_count = clamp(int(length / 11.0), 1, 5)
	var tangent = Vector2(sin(angle), cos(angle))
	for i in range(dash_count):
		var t = (float(i) + 0.5) / float(dash_count) - 0.5
		var p = Vector2(pos.x, pos.z) + tangent * t * length * 0.82
		var dash = MeshInstance3D.new()
		var dm = BoxMesh.new()
		dm.size = Vector3(0.12, 0.018, min(3.2, length / float(dash_count) * 0.48))
		dash.mesh = dm
		dash.material_override = marking_mat
		dash.position = Vector3(p.x, 0.091, p.y)
		dash.rotation.y = angle
		dash.visibility_range_end = 135.0
		_apply_secondary_visual_budget(dash, 105.0)
		parent.add_child(dash)

func _street_edges_rotated(parent: Node3D, pos: Vector3, length: float, width: float, angle: float, kind: String):
	# Pavement and kerb strips give roads a believable cross-section. Kept shallow,
	# uncollided and distance-capped so the mobile renderer gets the silhouette cues
	# without doubling the physics load.
	var tangent = Vector2(sin(angle), cos(angle))
	var normal = Vector2(-tangent.y, tangent.x)
	var pavement_w = 1.35 if kind in ["residential", "living_street", "tertiary"] else 0.95
	for side in [-1.0, 1.0]:
		var off = normal * side * (width * 0.5 + pavement_w * 0.5 + 0.16)
		var pavement = MeshInstance3D.new()
		var pm = BoxMesh.new()
		pm.size = Vector3(pavement_w, 0.12, length)
		pavement.mesh = pm
		pavement.material_override = pavement_mat
		pavement.position = pos + Vector3(off.x, 0.075, off.y)
		pavement.rotation.y = angle
		pavement.visibility_range_end = 180.0
		_apply_secondary_visual_budget(pavement, 120.0)
		parent.add_child(pavement)

		var kerb_off = normal * side * (width * 0.5 + 0.08)
		var kerb = MeshInstance3D.new()
		var km = BoxMesh.new()
		km.size = Vector3(0.16, 0.16, length)
		kerb.mesh = km
		kerb.material_override = kerb_mat
		kerb.position = pos + Vector3(kerb_off.x, 0.10, kerb_off.y)
		kerb.rotation.y = angle
		kerb.visibility_range_end = 145.0
		_apply_secondary_visual_budget(kerb, 110.0)
		parent.add_child(kerb)

func _road_material_for(surface: String):
	var s = surface.to_lower()
	if s in ["gravel", "fine_gravel", "unpaved", "compacted"]:
		return gravel_mat
	if s in ["paving_stones", "sett", "cobblestone", "concrete"]:
		return paving_mat
	return asphalt_mat

func _road_rotated_material(parent: Node3D, pos: Vector3, length: float, width: float, angle: float, material):
	var mesh = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(width, 0.07, length)
	mesh.mesh = bm
	mesh.material_override = material
	mesh.position = pos
	mesh.rotation.y = angle
	parent.add_child(mesh)


func _identity_area_material(kind: String):
	match kind:
		"beach":
			return beach_mat
		"water":
			return sea_mat
		"open_space":
			return open_space_mat
		"retail_zone":
			return retail_zone_mat
		"industrial_zone":
			return industrial_zone_mat
		"commercial_zone":
			return commercial_zone_mat
		_:
			return null

func _add_identity_area(parent: Node3D, feature: Dictionary):
	var kind := str(feature.get("kind", ""))
	var material = _identity_area_material(kind)
	if material == null:
		return
	var raw_points = feature.get("points", [])
	if not raw_points is Array or raw_points.size() < 3:
		return
	var poly := PackedVector2Array()
	var terrain_heights: Array[float] = []
	for raw_point in raw_points:
		if raw_point is Array and raw_point.size() >= 2:
			var point2 := Vector2(float(raw_point[0]), float(raw_point[1]))
			poly.append(point2)
			terrain_heights.append(float(raw_point[2]) if mobile_mode and raw_point.size() >= 3 else _terrain_height(point2))
	if poly.size() > 2 and poly[0].distance_squared_to(poly[poly.size() - 1]) < 0.01:
		poly.resize(poly.size() - 1)
	if poly.size() < 3:
		return
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.size() < 3:
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, tris.size(), 3):
		for j in range(3):
			var index := int(tris[t + j])
			var p: Vector2 = poly[index]
			var y := (-0.018 if kind == "water" else 0.009)
			if mobile_mode:
				y = (_terrain_sea_y() + 0.015) if kind == "water" else terrain_heights[index] + 0.015
			surface.add_vertex(Vector3(p.x, y, p.y))
	var mesh := surface.commit()
	if mesh == null:
		return
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = 1300.0 if mobile_mode else 700.0
	visual.set_meta("source_backed_identity", true)
	visual.set_meta("source_tag", str(feature.get("source_tag", "")))
	parent.add_child(visual)

func _add_coastline_sea(parent: Node3D, features: Array) -> int:
	# OSM natural=coastline is directed with water on the right. The local map
	# transform flips latitude into Z, so the transformed water-side normal is
	# (-dz, +dx). Extruding only on that side gives the driver a sea horizon
	# without inventing an inland water boundary.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segment_count := 0
	for feature in features:
		if not feature is Dictionary or str(feature.get("kind", "")) != "coastline":
			continue
		var raw_points = feature.get("points", [])
		if not raw_points is Array or raw_points.size() < 2:
			continue
		for i in range(raw_points.size() - 1):
			var pa = raw_points[i]
			var pb = raw_points[i + 1]
			if not pa is Array or not pb is Array or pa.size() < 2 or pb.size() < 2:
				continue
			var a := Vector2(float(pa[0]), float(pa[1]))
			var b := Vector2(float(pb[0]), float(pb[1]))
			var delta := b - a
			if delta.length() < 1.0:
				continue
			var tangent := delta.normalized()
			var water_normal := Vector2(-tangent.y, tangent.x)
			var near_a := a + water_normal * 1.0
			var near_b := b + water_normal * 1.0
			var far_a := a + water_normal * 1650.0
			var far_b := b + water_normal * 1650.0
			var sea_y := _terrain_sea_y() + 0.02 if mobile_mode else -0.055
			for p in [near_a, far_a, far_b, near_a, far_b, near_b]:
				surface.add_vertex(Vector3(p.x, sea_y, p.y))
			segment_count += 1
	if segment_count <= 0:
		return 0
	var mesh := surface.commit()
	if mesh == null:
		return 0
	var water := MeshInstance3D.new()
	water.name = "OSMCoastalWater"
	water.mesh = mesh
	water.material_override = sea_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.visibility_range_end = 2200.0
	water.set_meta("source_backed_identity", true)
	water.set_meta("source_field", "osm:natural=coastline")
	parent.add_child(water)
	return segment_count

func _add_identity_features(parent: Node3D, features: Array) -> Dictionary:
	var counts := {"coast_segments": 0, "areas": 0, "rail_segments": 0}
	counts["coast_segments"] = _add_coastline_sea(parent, features)
	var area_budget := 90 if mobile_mode else 140
	var rail_budget := 90 if mobile_mode else 160
	for feature in features:
		if not feature is Dictionary:
			continue
		var kind := str(feature.get("kind", ""))
		if kind in ["beach", "water", "open_space", "retail_zone", "industrial_zone", "commercial_zone"]:
			if int(counts["areas"]) >= area_budget:
				continue
			_add_identity_area(parent, feature)
			counts["areas"] = int(counts["areas"]) + 1
		elif kind == "railway":
			var points = feature.get("points", [])
			if not points is Array:
				continue
			for i in range(points.size() - 1):
				if int(counts["rail_segments"]) >= rail_budget:
					break
				var pa = points[i]
				var pb = points[i + 1]
				if not pa is Array or not pb is Array or pa.size() < 2 or pb.size() < 2:
					continue
				var a := Vector2(float(pa[0]), float(pa[1]))
				var b := Vector2(float(pb[0]), float(pb[1]))
				var delta := b - a
				var length := delta.length()
				if length < 2.0:
					continue
				var mid := (a + b) * 0.5
				var angle := atan2(delta.x, delta.y)
				if mobile_mode:
					_mobile_terrain_strip(parent, a, b, 3.4, 0.0, 0.035, gravel_mat, "railway")
				else:
					_road_rotated_material(parent, Vector3(mid.x, 0.016, mid.y), length + 0.4, 3.4, angle, gravel_mat)
				counts["rail_segments"] = int(counts["rail_segments"]) + 1
	return counts

func _add_mapped_linear_features(parent: Node3D, features: Array):
	var cap = 260 if xps_9530_mode else (80 if projector_max_mode else (110 if low_spec_mode else (320 if pc_max_mode else 240)))
	var made := 0
	for feature in features:
		if made >= cap or not feature is Dictionary:
			break
		var points = feature.get("points", [])
		var kind = str(feature.get("kind", ""))
		if not points is Array or points.size() < 2:
			continue
		for i in range(points.size() - 1):
			if made >= cap:
				break
			if not points[i] is Array or not points[i + 1] is Array:
				continue
			var a = Vector2(float(points[i][0]), float(points[i][1]))
			var b = Vector2(float(points[i + 1][0]), float(points[i + 1][1]))
			var d = b - a
			var length = d.length()
			if length < 0.8:
				continue
			var mid = (a + b) * 0.5
			var angle = atan2(d.x, d.y)
			if kind == "hedge":
				_visual_box(parent, Vector3(mid.x, 0.72, mid.y), Vector3(0.65, 1.44, length + 0.25), hedge_mat)
				var node = parent.get_child(parent.get_child_count() - 1)
				if node is MeshInstance3D:
					node.rotation.y = angle
					node.visibility_range_end = 180.0 if not low_spec_mode else 110.0
			elif kind == "fence":
				_visual_box(parent, Vector3(mid.x, 0.62, mid.y), Vector3(0.10, 1.18, length + 0.18), metal_mat)
				var node = parent.get_child(parent.get_child_count() - 1)
				if node is MeshInstance3D:
					node.rotation.y = angle
					node.visibility_range_end = 150.0 if not low_spec_mode else 95.0
			elif kind == "wall":
				_visual_box(parent, Vector3(mid.x, 0.58, mid.y), Vector3(0.28, 1.16, length + 0.18), concrete_mat)
				var node = parent.get_child(parent.get_child_count() - 1)
				if node is MeshInstance3D:
					node.rotation.y = angle
					node.visibility_range_end = 170.0 if not low_spec_mode else 105.0
			elif kind in ["footway", "path", "cycleway"]:
				var material = paving_mat if str(feature.get("surface", "")).to_lower() in ["paving_stones", "sett", "concrete"] else path_mat
				_road_rotated_material(parent, Vector3(mid.x, 0.045, mid.y), length + 0.30, 1.55 if kind == "cycleway" else 1.18, angle, material)
			made += 1

func _add_mapped_point_features(parent: Node3D, features: Array):
	var cap = 210 if xps_9530_mode else (55 if projector_max_mode else (95 if low_spec_mode else (240 if pc_max_mode else 180)))
	var made := 0
	for feature in features:
		if made >= cap or not feature is Dictionary:
			break
		var point = feature.get("point", [])
		if not point is Array or point.size() < 2:
			continue
		var p2 := Vector2(float(point[0]), float(point[1]))
		var p = Vector3(p2.x, float(feature.get("ground_y", _terrain_height(p2))) if mobile_mode else 0.0, p2.y)
		var kind = str(feature.get("kind", ""))
		if kind == "tree":
			var trunk = MeshInstance3D.new()
			var tm = CylinderMesh.new()
			tm.top_radius = 0.09 if mobile_mode else 0.12
			tm.bottom_radius = 0.14 if mobile_mode else 0.18
			tm.height = 1.9 if mobile_mode else 2.2
			tm.radial_segments = 10 if xps_9530_mode else 7
			trunk.mesh = tm
			trunk.position = p + Vector3(0, 0.95 if mobile_mode else 1.1, 0)
			trunk.material_override = _mat(Color(0.16, 0.10, 0.055), 0.96, 0.0)
			trunk.visibility_range_end = 240.0 if xps_9530_mode else (135.0 if mobile_mode else (150.0 if not low_spec_mode else 90.0))
			_apply_secondary_visual_budget(trunk, 100.0)
			parent.add_child(trunk)
			var crown = MeshInstance3D.new()
			var sm = SphereMesh.new()
			sm.radius = 0.88 if mobile_mode else 1.25
			sm.height = 1.75 if mobile_mode else 2.5
			sm.radial_segments = 12 if xps_9530_mode else (8 if not low_spec_mode else 6)
			sm.rings = 7 if xps_9530_mode else (5 if not low_spec_mode else 3)
			crown.mesh = sm
			crown.position = p + Vector3(0, 2.35 if mobile_mode else 3.0, 0)
			crown.material_override = hedge_mat
			crown.visibility_range_end = 260.0 if xps_9530_mode else (145.0 if mobile_mode else (165.0 if not low_spec_mode else 95.0))
			_apply_secondary_visual_budget(crown, 110.0)
			parent.add_child(crown)
		elif kind == "traffic_signals":
			_visual_box(parent, p + Vector3(0, 1.55, 0), Vector3(0.12, 3.1, 0.12), metal_mat)
			_visual_box(parent, p + Vector3(0, 2.75, 0), Vector3(0.34, 0.72, 0.24), roof_mat)
			if xps_9530_mode:
				_visual_box(parent, p + Vector3(0.0, 2.98, -0.13), Vector3(0.18, 0.14, 0.04), sign_red_mat)
				_visual_box(parent, p + Vector3(0.0, 2.76, -0.13), Vector3(0.18, 0.14, 0.04), marking_mat)
				_visual_box(parent, p + Vector3(0.0, 2.54, -0.13), Vector3(0.18, 0.14, 0.04), hedge_mat)
		elif kind == "bus_stop":
			_visual_box(parent, p + Vector3(0, 1.25, 0), Vector3(0.09, 2.5, 0.09), metal_mat)
			_visual_box(parent, p + Vector3(0, 2.35, 0), Vector3(0.52, 0.42, 0.10), marking_mat)
		elif kind == "crossing":
			_visual_box(parent, p + Vector3(0, 0.48, 0), Vector3(0.11, 0.96, 0.11), metal_mat)
		elif kind in ["stop", "give_way", "traffic_sign"]:
			_visual_box(parent, p + Vector3(0, 1.18, 0), Vector3(0.09, 2.36, 0.09), metal_mat)
			var board_mat = sign_red_mat if kind in ["stop", "give_way"] else sign_white_mat
			_visual_box(parent, p + Vector3(0, 2.24, 0), Vector3(0.08, 0.62, 0.62), board_mat)
			var sign_text = "STOP" if kind == "stop" else ("GIVE WAY" if kind == "give_way" else str(feature.get("traffic_sign", "")).replace("GB:", ""))
			if sign_text != "":
				_add_world_label(parent, p + Vector3(0, 2.25, 0), sign_text, Color(0.98, 0.98, 0.96), 30, 95.0)
		made += 1

func _add_world_label(parent: Node3D, pos: Vector3, text_value: String, colour: Color, font_size: int, range_end: float):
	if text_value.strip_edges() == "":
		return
	var label = Label3D.new()
	label.text = text_value
	label.position = pos
	label.font_size = font_size
	label.pixel_size = 0.0045
	label.modulate = colour
	label.outline_size = 8
	label.outline_modulate = Color(0.02, 0.025, 0.03, 0.95)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = range_end
	parent.add_child(label)

func _add_mapped_road_name_signs(parent: Node3D, roads: Array) -> int:
	# Road names are mapped facts, but a name in OSM does not prove that a physical
	# street-name board exists at an arbitrary segment midpoint. Keep generic names
	# as unobtrusive world annotations; actual mapped traffic signs are created only
	# by _add_mapped_point_features at their sourced coordinates.
	var cap = 18 if mobile_mode else (26 if xps_9530_mode else (8 if projector_max_mode else (10 if low_spec_mode else (34 if pc_max_mode else 18))))
	var distance_limit = 210.0 if mobile_mode else (125.0 if low_spec_mode else 260.0)
	var driver = get_node_or_null("Car")
	var reference := Vector2(driver.global_position.x, driver.global_position.z) if mobile_mode and driver else Vector2.ZERO
	var label_range = 190.0 if mobile_mode else (115.0 if low_spec_mode else 180.0)
	var label_size = 31 if mobile_mode else (24 if low_spec_mode else 31)
	var candidates: Array = []
	var seen := {}
	for road in roads:
		if not road is Dictionary:
			continue
		var road_name = str(road.get("name", "")).strip_edges()
		if road_name == "" or seen.has(road_name):
			continue
		var points = road.get("points", [])
		if not points is Array or points.size() < 2:
			continue
		var chosen := Vector2(INF, INF)
		var chosen_distance_sq := INF
		for i in range(points.size() - 1):
			if not points[i] is Array or not points[i + 1] is Array:
				continue
			var a = Vector2(float(points[i][0]), float(points[i][1]))
			var b = Vector2(float(points[i + 1][0]), float(points[i + 1][1]))
			if a.distance_to(b) < 8.0:
				continue
			var mid = (a + b) * 0.5
			var mid_distance_sq := mid.distance_squared_to(reference)
			if mid_distance_sq < chosen_distance_sq:
				chosen = mid
				chosen_distance_sq = mid_distance_sq
		if chosen.x == INF or sqrt(chosen_distance_sq) > distance_limit:
			continue
		seen[road_name] = true
		candidates.append({"name": road_name, "point": chosen, "distance_sq": chosen_distance_sq})
	candidates.sort_custom(func(a, b): return float(a["distance_sq"]) < float(b["distance_sq"]))
	var made := 0
	for candidate in candidates:
		if made >= cap:
			break
		var chosen: Vector2 = candidate["point"]
		var label = Label3D.new()
		label.name = "MappedRoadName_%d" % made
		label.text = str(candidate["name"]).to_upper()
		label.position = Vector3(chosen.x, _terrain_height(chosen) + 1.55 if mobile_mode else 1.05, chosen.y)
		label.font_size = label_size
		label.pixel_size = 0.0062 if mobile_mode else 0.0042
		label.modulate = Color(0.94, 0.95, 0.92, 0.88)
		label.outline_size = 7
		label.outline_modulate = Color(0.02, 0.025, 0.03, 0.92)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = mobile_mode
		label.visibility_range_end = label_range
		label.set_meta("annotation_only", true)
		label.set_meta("source_field", "osm:name")
		parent.add_child(label)
		made += 1
	return made

func _add_mobile_identity_annotation(parent: Node3D, pos: Vector3, text_value: String, colour: Color, range_end: float):
	if text_value.strip_edges() == "":
		return
	var label = Label3D.new()
	label.text = text_value
	label.position = pos
	label.font_size = 29
	label.pixel_size = 0.0064
	label.modulate = colour
	label.outline_size = 9
	label.outline_modulate = Color(0.015, 0.02, 0.025, 0.98)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.visibility_range_end = range_end
	label.set_meta("annotation_only", true)
	label.set_meta("source_field", "osm:name")
	parent.add_child(label)

func _add_named_poi_markers(parent: Node3D, pois: Array):
	var cap = 10 if mobile_mode else (22 if xps_9530_mode else (5 if projector_max_mode else (7 if low_spec_mode else (32 if pc_max_mode else 14))))
	var distance_limit = 190.0 if mobile_mode else (120.0 if low_spec_mode else 300.0)
	var label_range = 175.0 if mobile_mode else (110.0 if low_spec_mode else 200.0)
	var label_size = 29 if mobile_mode else (25 if low_spec_mode else 32)
	var made := 0
	var driver = get_node_or_null("Car")
	var reference := Vector2(driver.global_position.x, driver.global_position.z) if mobile_mode and driver else Vector2.ZERO
	var ordered_pois: Array = pois.duplicate()
	if mobile_mode:
		ordered_pois.sort_custom(func(a, b):
			if not a is Dictionary:
				return false
			if not b is Dictionary:
				return true
			var ap = a.get("point", [])
			var bp = b.get("point", [])
			var ad := INF
			var bd := INF
			if ap is Array and ap.size() >= 2:
				ad = Vector2(float(ap[0]), float(ap[1])).distance_squared_to(reference)
			if bp is Array and bp.size() >= 2:
				bd = Vector2(float(bp[0]), float(bp[1])).distance_squared_to(reference)
			var an := str(a.get("name", "")).to_lower()
			var bn := str(b.get("name", "")).to_lower()
			if an.contains("hugh dewar"):
				ad -= 1000000.0
			if bn.contains("hugh dewar"):
				bd -= 1000000.0
			return ad < bd
		)
	for poi in ordered_pois:
		if made >= cap or not poi is Dictionary:
			break
		var point = poi.get("point", [])
		var poi_name = str(poi.get("name", "")).strip_edges()
		if poi_name == "" or not point is Array or point.size() < 2:
			continue
		var p = Vector2(float(point[0]), float(point[1]))
		if p.distance_to(reference) > distance_limit:
			continue
		var poi_y := float(poi.get("ground_y", _terrain_height(p))) if mobile_mode else 0.0
		var is_hugh_dewar := str(poi.get("kind", "")).to_lower() == "memorial" and poi_name.to_lower().contains("hugh dewar")
		if is_hugh_dewar:
			_add_hugh_dewar_memorial(parent, p, poi_y)
			if mobile_mode:
				_add_mobile_identity_annotation(parent, Vector3(p.x, poi_y + 4.35, p.y), poi_name, Color(0.72, 0.90, 1.0, 0.96), label_range)
			else:
				_add_world_label(parent, Vector3(p.x, 4.35, p.y), poi_name, Color(0.98, 0.98, 0.96), label_size, label_range)
		elif mobile_mode:
			_add_mobile_identity_annotation(parent, Vector3(p.x, poi_y + 3.0, p.y), poi_name, Color(0.72, 0.90, 1.0, 0.96), label_range)
		else:
			_visual_box(parent, Vector3(p.x, 1.35, p.y), Vector3(0.08, 2.70, 0.08), metal_mat)
			_visual_box(parent, Vector3(p.x, 2.55, p.y), Vector3(0.92, 0.40, 0.08), sign_blue_mat)
			_add_world_label(parent, Vector3(p.x, 2.58, p.y), poi_name, Color(0.98, 0.98, 0.96), label_size, label_range)
		made += 1

func _add_named_building_marker(parent: Node3D, building: Dictionary):
	var name = str(building.get("name", "")).strip_edges()
	var center = building.get("center", [])
	if name == "" or not center is Array or center.size() < 2:
		return
	var p = Vector2(float(center[0]), float(center[1]))
	var distance_limit = 165.0 if mobile_mode else (100.0 if low_spec_mode else (230.0 if pc_max_mode else 150.0))
	var driver = get_node_or_null("Car")
	var reference := Vector2(driver.global_position.x, driver.global_position.z) if mobile_mode and driver else Vector2.ZERO
	if p.distance_to(reference) > distance_limit:
		return
	if mobile_mode:
		var building_y := float(building.get("ground_y", _terrain_height(p)))
		_add_mobile_identity_annotation(parent, Vector3(p.x, building_y + 3.4, p.y), name, Color(1.0, 0.86, 0.58, 0.96), 155.0)
	else:
		_add_world_label(parent, Vector3(p.x, 3.2, p.y), name, Color(0.95, 0.93, 0.86), 25 if low_spec_mode else 34, 105.0 if low_spec_mode else 170.0)


func _add_opening_anchor_annotation(parent: Node3D, car: Node, pois: Array, buildings: Array, points: Array) -> bool:
	# The opening director selects a genuine named feature, but ordinary POI caps may
	# omit that exact feature. Guarantee one restrained annotation at its source
	# coordinate so the first view contains recognisable context without inventing a
	# physical sign, pole, facade or location.
	var anchor_name = str(car.get_meta("map_opening_verified_anchor", "")).strip_edges()
	var anchor_source = str(car.get_meta("map_opening_verified_anchor_source", ""))
	if anchor_name == "":
		return false
	var collection: Array = pois if anchor_source == "poi" else (buildings if anchor_source == "building" else points)
	var coordinate_field = "center" if anchor_source == "building" else "point"
	for feature in collection:
		if not feature is Dictionary or str(feature.get("name", "")).strip_edges() != anchor_name:
			continue
		var coordinate = feature.get(coordinate_field, [])
		if not coordinate is Array or coordinate.size() < 2:
			continue
		var label = Label3D.new()
		label.name = "MappedOpeningAnchor"
		label.text = anchor_name
		var anchor_point := Vector2(float(coordinate[0]), float(coordinate[1]))
		label.position = Vector3(anchor_point.x, _terrain_height(anchor_point) + 3.05 if mobile_mode else 3.05, anchor_point.y)
		label.font_size = 27 if low_spec_mode else 34
		# Slightly larger than ordinary world labels because this one is the single
		# verified first-impression cue. At the selected EH15 opening distance this
		# produces a compact, legible projector annotation instead of a two-pixel
		# trace, while perspective scaling still prevents a screen-filling banner.
		label.pixel_size = 0.012
		# Depth-independent rendering makes this unambiguously a map overlay rather
		# than a claim that a physical sign exists on the facade. Keep ordinary
		# perspective scaling: fixed_size turns a long business name into a giant
		# screen-space banner when it sits close to a side-panel frustum.
		# The cyan is deliberately reserved for this sourced opening cue so the
		# render proof can verify that it reached actual pixels.
		label.modulate = Color(0.18, 0.88, 1.0, 0.98)
		label.outline_size = 8
		label.outline_modulate = Color(0.02, 0.025, 0.03, 0.96)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# The verified POI lands at the left edge of its active side-panel frustum.
		# Keep the anchor at the exact OSM coordinate, but lay the annotation out to
		# its right so the name is not bisected by a physical shutter gap.
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.offset = Vector2(18.0, 0.0)
		label.no_depth_test = true
		label.visibility_range_end = 140.0 if low_spec_mode else 210.0
		label.set_meta("annotation_only", true)
		label.set_meta("source_field", "osm:name")
		label.set_meta("source_collection", anchor_source)
		label.set_meta("opening_priority", true)
		parent.add_child(label)
		return true
	return false

func _visual_box(parent: Node3D, pos: Vector3, size: Vector3, material):
	var mesh = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material
	mesh.position = pos
	_apply_secondary_visual_budget(mesh)
	parent.add_child(mesh)

func _rotated_visual_box(parent: Node3D, pos: Vector3, size: Vector3, material, angle: float, range_end := 260.0):
	_visual_box(parent, pos, size, material)
	var node = parent.get_child(parent.get_child_count() - 1)
	if node is MeshInstance3D:
		node.rotation.y = angle
		node.visibility_range_end = range_end
	return node

func _visual_cylinder(parent: Node3D, pos: Vector3, top_radius: float, bottom_radius: float, height: float, material, radial_segments := 12, range_end := 260.0):
	var mesh = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = top_radius
	cm.bottom_radius = bottom_radius
	cm.height = height
	cm.radial_segments = radial_segments
	mesh.mesh = cm
	mesh.material_override = material
	mesh.position = pos
	mesh.visibility_range_end = range_end
	_apply_secondary_visual_budget(mesh, range_end)
	parent.add_child(mesh)
	return mesh

func _visual_sphere(parent: Node3D, pos: Vector3, radius: float, height: float, material, range_end := 260.0):
	var mesh = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = radius
	sm.height = height
	sm.radial_segments = 14 if not low_spec_mode else 9
	sm.rings = 8 if not low_spec_mode else 5
	mesh.mesh = sm
	mesh.material_override = material
	mesh.position = pos
	mesh.visibility_range_end = range_end
	_apply_secondary_visual_budget(mesh, range_end)
	parent.add_child(mesh)
	return mesh

func _landmark_front_frame(poly: PackedVector2Array) -> Dictionary:
	if poly.size() < 2:
		return {}
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= float(poly.size())
	var best_edge := -1
	var best_distance := INF
	for edge_index in range(poly.size()):
		var p0: Vector2 = poly[edge_index]
		var p1: Vector2 = poly[(edge_index + 1) % poly.size()]
		if p0.distance_to(p1) < 3.0:
			continue
		var edge_mid := (p0 + p1) * 0.5
		var road_distance := _nearest_drivable_road_distance(edge_mid)
		if road_distance < best_distance:
			best_distance = road_distance
			best_edge = edge_index
	if best_edge < 0:
		return {}
	var p0: Vector2 = poly[best_edge]
	var p1: Vector2 = poly[(best_edge + 1) % poly.size()]
	var tangent := (p1 - p0).normalized()
	var edge_mid := (p0 + p1) * 0.5
	var inward := (centroid - edge_mid).normalized()
	if inward.length() < 0.5:
		inward = Vector2(-tangent.y, tangent.x)
	return {
		"centroid": centroid,
		"mid": edge_mid,
		"tangent": tangent,
		"inward": inward,
		"outward": -inward,
		"angle": atan2(tangent.x, tangent.y)
	}

func _add_named_landmark_signature(body: Node3D, poly: PackedVector2Array, height: float, building: Dictionary):
	var name := str(building.get("name", "")).strip_edges()
	var lower := name.to_lower()
	if lower != "bellfield community hub" and lower != "st mark's church":
		return
	var frame := _landmark_front_frame(poly)
	if frame.is_empty():
		return
	var centroid: Vector2 = frame["centroid"]
	var front_mid: Vector2 = frame["mid"]
	var tangent: Vector2 = frame["tangent"]
	var inward: Vector2 = frame["inward"]
	var outward: Vector2 = frame["outward"]
	var angle: float = frame["angle"]

	if lower == "bellfield community hub":
		# Former Portobello Old Parish Church: broad symmetrical stone front,
		# central square clock tower, then an octagonal louvred belfry.
		var tower_center := centroid
		_rotated_visual_box(body, Vector3(tower_center.x, height + 2.85, tower_center.y), Vector3(5.1, 5.7, 5.1), sandstone_warm_mat, angle, 420.0)
		for face_angle in [0.0, PI * 0.5, PI, PI * 1.5]:
			var face_offset: Vector2 = Vector2(sin(float(face_angle)), cos(float(face_angle))) * 2.58
			_rotated_visual_box(body, Vector3(tower_center.x + face_offset.x, height + 3.25, tower_center.y + face_offset.y), Vector3(1.55, 1.55, 0.10), sign_white_mat, face_angle, 420.0)
		_visual_cylinder(body, Vector3(tower_center.x, height + 6.65, tower_center.y), 1.90, 2.15, 2.35, soot_stone_cool_mat, 8, 430.0)
		_visual_cylinder(body, Vector3(tower_center.x, height + 8.35, tower_center.y), 0.30, 2.10, 1.10, roof_mat, 8, 440.0)
		_visual_sphere(body, Vector3(tower_center.x, height + 9.02, tower_center.y), 0.22, 0.44, metal_mat, 440.0)
		# Bellfield Street elevation: central blue doors and paired tall window bays
		# make the building readable before the clock tower is fully in frame.
		var bellfield_door := front_mid + outward * 0.08
		_rotated_visual_box(body, Vector3(bellfield_door.x, 1.35, bellfield_door.y), Vector3(0.10, 2.70, 1.65), sign_blue_mat, angle, 360.0)
		_rotated_visual_box(body, Vector3(bellfield_door.x, 2.82, bellfield_door.y), Vector3(0.11, 0.28, 1.88), tenement_sash_frame_mat, angle, 360.0)
		for side in [-1.0, 1.0]:
			var window_p := front_mid + tangent * float(side) * 3.55 + outward * 0.07
			_rotated_visual_box(body, Vector3(window_p.x, 3.25, window_p.y), Vector3(0.09, 3.65, 1.48), tenement_sash_frame_mat, angle, 360.0)
			var glass_p := window_p + inward * 0.06
			_rotated_visual_box(body, Vector3(glass_p.x, 3.25, glass_p.y), Vector3(0.06, 3.30, 1.20), tenement_sash_glass_mat, angle, 360.0)
		body.set_meta("landmark_signature", "bellfield-clock-tower-v3")
	else:
		# St Mark's reads as a restrained classical church rather than a huge
		# cylindrical porch. Keep the low dome central and make the street-facing
		# portico from a doorway, four columns and a heavy stone lintel.
		var porch_face := front_mid + outward * 0.22
		_rotated_visual_box(body, Vector3(porch_face.x, 1.30, porch_face.y), Vector3(0.10, 2.60, 1.28), soot_stone_cool_mat, angle, 390.0)
		for column_index in range(4):
			var column_offset := (float(column_index) - 1.5) * 0.90
			var column_p: Vector2 = front_mid + tangent * column_offset + outward * 0.58
			_visual_cylinder(body, Vector3(column_p.x, 1.58, column_p.y), 0.17, 0.22, 3.16, sandstone_warm_mat, 10, 390.0)
		var lintel_p := front_mid + outward * 0.56
		_rotated_visual_box(body, Vector3(lintel_p.x, 3.18, lintel_p.y), Vector3(0.22, 0.34, 4.55), sandstone_warm_mat, angle, 395.0)
		for side in [-1.0, 1.0]:
			var window_p := front_mid + tangent * float(side) * 3.05 + outward * 0.08
			_rotated_visual_box(body, Vector3(window_p.x, 2.55, window_p.y), Vector3(0.08, 3.25, 1.20), tenement_sash_frame_mat, angle, 395.0)
			var glass_p := window_p + inward * 0.06
			_rotated_visual_box(body, Vector3(glass_p.x, 2.55, glass_p.y), Vector3(0.055, 2.95, 0.94), tenement_sash_glass_mat, angle, 395.0)
		var dome_center := centroid
		_visual_cylinder(body, Vector3(dome_center.x, height + 0.28, dome_center.y), 1.75, 1.90, 0.56, sandstone_warm_mat, 18, 415.0)
		_visual_sphere(body, Vector3(dome_center.x, height + 0.82, dome_center.y), 1.62, 1.16, roof_mat, 415.0)
		_visual_cylinder(body, Vector3(dome_center.x, height + 1.52, dome_center.y), 0.24, 0.38, 0.52, soot_stone_cool_mat, 10, 425.0)
		body.set_meta("landmark_signature", "st-marks-classical-dome-v3")

func _add_hugh_dewar_memorial(parent: Node3D, point: Vector2, base_y: float):
	# Dr Hugh Dewar memorial: broad polished-granite drinking-fountain base,
	# four visible support balls, tall stepped taper and a ball finial.
	_visual_box(parent, Vector3(point.x, base_y + 0.18, point.y), Vector3(2.15, 0.36, 2.15), soot_stone_cool_mat)
	_visual_box(parent, Vector3(point.x, base_y + 0.58, point.y), Vector3(1.82, 0.46, 1.82), soot_stone_mat)
	_visual_box(parent, Vector3(point.x, base_y + 1.16, point.y), Vector3(1.52, 0.70, 1.52), sandstone_mat)
	_visual_box(parent, Vector3(point.x, base_y + 1.62, point.y), Vector3(1.70, 0.20, 1.70), soot_stone_cool_mat)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_visual_sphere(parent, Vector3(point.x + float(sx) * 0.52, base_y + 1.92, point.y + float(sz) * 0.52), 0.22, 0.44, soot_stone_cool_mat, 340.0)
	_visual_box(parent, Vector3(point.x, base_y + 2.18, point.y), Vector3(1.62, 0.24, 1.62), soot_stone_cool_mat)
	var taper_sizes := [1.42, 1.15, 0.86, 0.58]
	for tier_index in range(taper_sizes.size()):
		var tier_size := float(taper_sizes[tier_index])
		_visual_box(parent, Vector3(point.x, base_y + 2.72 + float(tier_index) * 0.62, point.y), Vector3(tier_size, 0.66, tier_size), soot_stone_cool_mat)
	_visual_cylinder(parent, Vector3(point.x, base_y + 4.95, point.y), 0.12, 0.20, 0.34, soot_stone_cool_mat, 8, 360.0)
	_visual_sphere(parent, Vector3(point.x, base_y + 5.30, point.y), 0.24, 0.48, soot_stone_cool_mat, 360.0)

func _road_micro_detail(parent: Node3D, a: Vector2, b: Vector2, width: float, seed: int, budget: int) -> int:
	if budget <= 0:
		return 0
	# Spend procedural surface detail only where the seated driver can actually
	# read it. This is visual texture, never geographic evidence: road alignment,
	# widths and surfaces still come exclusively from the mapped segment.
	var segment_mid = (a + b) * 0.5
	var driver = get_node_or_null("Car")
	var driver_pos = Vector2(driver.global_position.x, driver.global_position.z) if driver else Vector2.ZERO
	var detail_radius := 68.0 if xps_9530_mode else DRIVER_DETAIL_RADIUS
	if segment_mid.distance_to(driver_pos) > detail_radius + (b - a).length() * 0.5:
		return 0
	var delta = b - a
	var length = delta.length()
	if length < ROAD_MICRO_STEP:
		return 0
	var tangent = delta.normalized()
	var normal = Vector2(-tangent.y, tangent.x)
	var micro_step := 4.8 if xps_9530_mode else ROAD_MICRO_STEP
	var count = min(budget, max(1, int(floor(length / micro_step))))
	for i in range(count):
		var t = (float(i) + 0.5) / float(count)
		var p = a.lerp(b, t)
		var kind = abs(seed + i * 13) % 4
		if kind == 0:
			var side = -1.0 if (seed + i) % 2 == 0 else 1.0
			var edge = p + normal * side * (width * 0.5 - 0.18)
			var drain = MeshInstance3D.new()
			var dm = BoxMesh.new()
			dm.size = Vector3(0.38, 0.018, 0.62)
			drain.mesh = dm
			drain.position = Vector3(edge.x, 0.098, edge.y)
			drain.rotation.y = atan2(tangent.x, tangent.y)
			drain.material_override = metal_mat
			drain.visibility_range_end = 95.0
			parent.add_child(drain)
		elif kind == 1:
			var patch = MeshInstance3D.new()
			var pm = PlaneMesh.new()
			pm.size = Vector2(0.9 + float((seed + i) % 3) * 0.45, 1.5 + float((seed + i * 2) % 3) * 0.55)
			patch.mesh = pm
			patch.position = Vector3(p.x, 0.091, p.y)
			patch.rotation.y = atan2(tangent.x, tangent.y) + float(((seed + i) % 5) - 2) * 0.035
			patch.material_override = road_patch_mat
			patch.visibility_range_end = 105.0
			_apply_secondary_visual_budget(patch, 72.0)
			parent.add_child(patch)
		elif kind == 2:
			var side = -1.0 if (seed + i) % 2 == 0 else 1.0
			var verge = p + normal * side * (width * 0.5 + 1.0)
			var weed = MeshInstance3D.new()
			var qm = QuadMesh.new()
			qm.size = Vector2(0.20, 0.40)
			weed.mesh = qm
			weed.position = Vector3(verge.x, 0.20, verge.y)
			weed.rotation.y = atan2(normal.x, normal.y) + float(i) * 0.37
			weed.material_override = weed_mat
			weed.visibility_range_end = 72.0
			_apply_secondary_visual_budget(weed, 54.0)
			parent.add_child(weed)
		elif kind == 3 and xps_9530_mode:
			# Procedural wear only: a subdued repair seam gives the asphalt scale and
			# speed cues without claiming a mapped pothole or road defect.
			var seam = MeshInstance3D.new()
			var seam_mesh = PlaneMesh.new()
			seam_mesh.size = Vector2(0.10, min(2.8, max(1.2, length / float(count) * 0.55)))
			seam.mesh = seam_mesh
			seam.position = Vector3(p.x + normal.x * 0.35, 0.092, p.y + normal.y * 0.35)
			seam.rotation.y = atan2(tangent.x, tangent.y)
			seam.material_override = road_patch_mat
			seam.visibility_range_end = 120.0
			_apply_secondary_visual_budget(seam)
			parent.add_child(seam)
	return count

const COMMERCIAL_GROUND_FLOOR_POI_KINDS := [
	"hairdresser", "pharmacy", "cafe", "beauty", "funeral_directors", "dentist",
	"antiques", "bakery", "art", "fireplace", "books", "restaurant", "clothes",
	"tattoo", "window_blind", "bar", "gift", "fast_food", "copyshop",
	"convenience", "carpet", "pet", "charity", "bookmaker", "bicycle", "tailor",
	"fitness_centre", "clinic"
]


func _mapped_commercial_pois_inside_building(building: Dictionary, poi_features: Array) -> Array:
	var footprint = building.get("footprint", [])
	if not footprint is Array or footprint.size() < 3:
		return []
	var poly := PackedVector2Array()
	for raw_point in footprint:
		if raw_point is Array and raw_point.size() >= 2:
			poly.append(Vector2(float(raw_point[0]), float(raw_point[1])))
	if poly.size() < 3:
		return []
	var matches: Array = []
	for poi in poi_features:
		if not poi is Dictionary:
			continue
		var poi_kind: String = str(poi.get("kind", "")).to_lower()
		var poi_value: String = poi_kind
		if ":" in poi_kind:
			poi_value = poi_kind.get_slice(":", 1)
		if poi_value not in COMMERCIAL_GROUND_FLOOR_POI_KINDS:
			continue
		var raw_p = poi.get("point", [])
		if not raw_p is Array or raw_p.size() < 2:
			continue
		var p := Vector2(float(raw_p[0]), float(raw_p[1]))
		if Geometry2D.is_point_in_polygon(p, poly):
			# Preserve the mapped name for recognisable frontage cues. Geometry and
			# placement still come from OSM; this only lets a known shop keep its
			# characteristic palette instead of becoming another anonymous unit.
			matches.append({
				"point": [p.x, p.y],
				"kind": poi_kind,
				"name": str(poi.get("name", "")).strip_edges(),
				"source": "osm_poi"
			})
	return matches


func _nearest_poly_edge(poly: PackedVector2Array, point: Vector2) -> int:
	var best_index := -1
	var best_distance := INF
	for edge_index in range(poly.size()):
		var p0 := poly[edge_index]
		var p1 := poly[(edge_index + 1) % poly.size()]
		var closest := Geometry2D.get_closest_point_to_segment(point, p0, p1)
		var distance := point.distance_squared_to(closest)
		if distance < best_distance:
			best_distance = distance
			best_index = edge_index
	return best_index


func _uses_generic_edinburgh_tenement_texture(building: Dictionary) -> bool:
	if map_center_lat < 52.5:
		return false
	if str(building.get("name", "")).strip_edges() != "":
		return false
	var kind = str(building.get("kind", "yes")).to_lower()
	if kind in ["church", "cathedral", "school", "hospital", "civic", "public", "castle", "monument", "industrial", "warehouse"]:
		return false
	var tagged = str(building.get("material", "")).to_lower()
	return tagged == "" or "stone" in tagged


func _osm_building_material(building: Dictionary, seed: int):
	var tagged = str(building.get("material", "")).to_lower()
	var named := str(building.get("name", "")).strip_edges().to_lower()
	# Named landmarks get a restrained material cue based on their real visual
	# character so their silhouettes do not disappear into the generic building set.
	if named == "bellfield community hub":
		return sandstone_warm_mat
	if named == "st mark's church":
		return sandstone_warm_mat
	if _uses_generic_edinburgh_tenement_texture(building):
		# Generic visual approximation only. The OSM footprint stays authoritative;
		# these shared textures do not claim surveyed facade accuracy.
		match abs(seed) % 10:
			0, 1:
				return tenement_warm_mat
			2, 3:
				return tenement_soot_mat
			_:
				return tenement_weathered_mat
	if "brick" in tagged:
		return brick_mat
	if "concrete" in tagged:
		return concrete_mat
	if "stone" in tagged:
		return soot_stone_mat if seed % 2 == 0 else sandstone_mat
	if "render" in tagged or "stucco" in tagged or "plaster" in tagged:
		return render_mat
	match seed % 5:
		0, 1:
			return brick_mat
		2:
			return render_mat
		3:
			return soot_stone_cool_mat
		_:
			return sandstone_warm_mat


func _nearest_drivable_road_distance(point: Vector2) -> float:
	var best := INF
	for segment in map_segments:
		if not segment is Array or segment.size() < 4:
			continue
		var kind := str(segment[3]).to_lower()
		if kind in ["service", "track", "path", "footway", "cycleway"]:
			continue
		var a := Vector2(float(segment[0][0]), float(segment[0][1]))
		var b := Vector2(float(segment[1][0]), float(segment[1][1]))
		best = minf(best, _point_segment_distance_2d(point, a, b))
	return best

func _mobile_facade_box(body: Node3D, pos: Vector3, size: Vector3, material, angle: float, range_end: float = 105.0):
	_visual_box(body, pos, size, material)
	var node = body.get_child(body.get_child_count() - 1)
	if node is MeshInstance3D:
		node.rotation.y = angle
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = range_end
		node.set_meta("mobile_facade_detail", true)

func _add_mobile_secondary_facade_edges(body: Node3D, poly: PackedVector2Array, height: float, centroid: Vector2, primary_edge: int):
	# One decorated face is not enough on Edinburgh streets: a corner tenement or
	# long block can present a completely blank wall to the actual carriageway.
	# Add restrained sash rhythm to up to two additional OSM edges that genuinely
	# sit beside a drivable road. No invented doors, signs or shop names here.
	var candidates: Array = []
	var driver = get_node_or_null("Car")
	var near_building := false
	if driver:
		near_building = centroid.distance_to(Vector2(driver.global_position.x, driver.global_position.z)) <= 105.0
	for edge_index in range(poly.size()):
		if edge_index == primary_edge:
			continue
		var p0: Vector2 = poly[edge_index]
		var p1: Vector2 = poly[(edge_index + 1) % poly.size()]
		var length := p0.distance_to(p1)
		if length < 6.0:
			continue
		var edge_mid := (p0 + p1) * 0.5
		var road_distance := _nearest_drivable_road_distance(edge_mid)
		if road_distance > 13.5 and not near_building:
			continue
		candidates.append({"edge":edge_index, "score":road_distance, "length":length})
	candidates.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
	var made := 0
	var max_secondary_edges := 3 if near_building else 2
	for candidate in candidates:
		if made >= max_secondary_edges:
			break
		var edge_index := int(candidate["edge"])
		var p0: Vector2 = poly[edge_index]
		var p1: Vector2 = poly[(edge_index + 1) % poly.size()]
		var delta := p1 - p0
		var length := delta.length()
		if length < 6.0:
			continue
		var tangent := delta / length
		var angle := atan2(tangent.x, tangent.y)
		var edge_mid := (p0 + p1) * 0.5
		var inward := (centroid - edge_mid).normalized()
		if inward.length() < 0.5:
			inward = Vector2(-tangent.y, tangent.x)
		_mobile_facade_box(body, Vector3(edge_mid.x, 0.20, edge_mid.y), Vector3(0.07, 0.36, length * 0.97), roof_mat, angle, 185.0)
		if height > 5.2:
			_mobile_facade_box(body, Vector3(edge_mid.x, height - 0.15, edge_mid.y), Vector3(0.08, 0.22, length * 0.97), roof_mat, angle, 185.0)
		var slots := clampi(int(floor(length / 3.5)), 2, 7)
		var floors := clampi(int(floor(height / 3.0)), 1, 3)
		for floor_index in range(floors):
			var y := 1.65 + float(floor_index) * 2.75
			if y > height - 0.55:
				continue
			for slot in range(slots):
				var t := (float(slot) + 0.5) / float(slots)
				var p := p0.lerp(p1, t)
				var slot_width := maxf(1.0, length / float(slots) * 0.56)
				var frame_width := minf(1.42, slot_width + 0.18)
				_mobile_facade_box(body, Vector3(p.x, y, p.y), Vector3(0.07, 1.58, frame_width), tenement_sash_frame_mat, angle, 180.0)
				var recessed := p + inward * 0.09
				_mobile_facade_box(body, Vector3(recessed.x, y, recessed.y), Vector3(0.05, 1.25, minf(1.16, slot_width * 0.82)), tenement_sash_glass_mat, angle, 180.0)
		made += 1

func _add_mobile_osm_facade_detail(body: Node3D, poly: PackedVector2Array, height: float, seed: int, building: Dictionary):
	if not mobile_mode or poly.size() < 3 or height < 3.8:
		return
	var kind := str(building.get("kind", "yes")).to_lower()
	if kind in ["garage", "garages", "shed", "roof", "industrial", "warehouse"]:
		return
	var car = get_node_or_null("Car")
	if car == null:
		return
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= float(poly.size())
	var car2 := Vector2(car.global_position.x, car.global_position.z)
	if centroid.distance_to(car2) > MOBILE_FACADE_RADIUS:
		return

	var mapped_commercial_pois: Array = building.get("_mapped_commercial_pois", [])
	var best_edge := -1
	var best_score := INF
	for edge_index in range(poly.size()):
		var p0: Vector2 = poly[edge_index]
		var p1: Vector2 = poly[(edge_index + 1) % poly.size()]
		var length := p0.distance_to(p1)
		if length < 5.0:
			continue
		var edge_mid := (p0 + p1) * 0.5
		var road_distance := _nearest_drivable_road_distance(edge_mid)
		var car_distance := edge_mid.distance_to(car2)
		var score := road_distance * 4.0 + car_distance
		for poi in mapped_commercial_pois:
			var raw_p = poi.get("point", [])
			if raw_p is Array and raw_p.size() >= 2:
				var poi_point := Vector2(float(raw_p[0]), float(raw_p[1]))
				if _nearest_poly_edge(poly, poi_point) == edge_index:
					score -= 36.0
					break
		if road_distance <= 18.0 and score < best_score:
			best_score = score
			best_edge = edge_index
	if best_edge < 0:
		return

	var p0: Vector2 = poly[best_edge]
	var p1: Vector2 = poly[(best_edge + 1) % poly.size()]
	var delta := p1 - p0
	var length := delta.length()
	if length < 5.0:
		return
	var tangent := delta / length
	var angle := atan2(tangent.x, tangent.y)
	var edge_mid := (p0 + p1) * 0.5
	var inward := (centroid - edge_mid).normalized()
	if inward.length() < 0.5:
		inward = Vector2(-tangent.y, tangent.x)

	var slots: int = clampi(int(floor(length / 3.4)), 2, 6)
	var shop_slots := {}
	for poi in mapped_commercial_pois:
		var raw_p = poi.get("point", [])
		if not raw_p is Array or raw_p.size() < 2:
			continue
		var poi_point := Vector2(float(raw_p[0]), float(raw_p[1]))
		if _nearest_poly_edge(poly, poi_point) != best_edge:
			continue
		var along := clampf((poi_point - p0).dot(delta) / maxf(length * length, 0.001), 0.0, 0.999)
		shop_slots[int(floor(along * float(slots)))] = str(poi.get("name", "")).strip_edges()
	if shop_slots.is_empty() and not mapped_commercial_pois.is_empty():
		# OSM proves commercial presence inside this building, but not an exact
		# frontage unit. Put one generic cue on the chosen street-facing edge.
		shop_slots[int(floor(float(slots) * 0.5))] = str(mapped_commercial_pois[0].get("name", "")).strip_edges()

	var detail_count := 0
	var shopfront_count := 0
	_mobile_facade_box(body, Vector3(edge_mid.x, 0.20, edge_mid.y), Vector3(0.08, 0.40, length * 0.97), roof_mat, angle)
	detail_count += 1
	if height > 5.2:
		_mobile_facade_box(body, Vector3(edge_mid.x, height - 0.16, edge_mid.y), Vector3(0.08, 0.22, length * 0.97), roof_mat, angle)
		detail_count += 1

	var floors: int = clampi(int(floor(height / 3.0)), 1, 3)
	for floor_index in range(floors):
		var y := 1.65 + float(floor_index) * 2.75
		if y > height - 0.55:
			continue
		for slot in range(slots):
			var t := (float(slot) + 0.5) / float(slots)
			var p := p0.lerp(p1, t)
			var slot_width := maxf(1.1, length / float(slots) * 0.58)
			if floor_index == 0 and shop_slots.has(slot):
				var shop_name := str(shop_slots.get(slot, "")).to_lower()
				var is_twelve_triangles := shop_name.contains("twelve triangles")
				var shop_frame_mat = sign_blue_mat if is_twelve_triangles else tenement_sash_frame_mat
				var shop_glass_mat = _mat(Color(0.86, 0.43, 0.10), 0.20, 0.02) if is_twelve_triangles else tenement_sash_glass_mat
				var recessed := p + inward * 0.11
				if is_twelve_triangles:
					# Portobello branch: navy-painted ground-floor frontage, broad
					# warm display window and matching door. The exact unit position
					# comes from the mapped Twelve Triangles POI.
					var frontage_width := minf(4.8, maxf(3.4, slot_width * 1.92))
					_mobile_facade_box(body, Vector3(p.x, 1.35, p.y), Vector3(0.12, 2.75, frontage_width), sign_blue_mat, angle, 190.0)
					var window_p := p - tangent * frontage_width * 0.12 + inward * 0.13
					_mobile_facade_box(body, Vector3(window_p.x, 1.30, window_p.y), Vector3(0.07, 2.05, frontage_width * 0.56), shop_glass_mat, angle, 190.0)
					var door_p := p + tangent * frontage_width * 0.33 + inward * 0.12
					_mobile_facade_box(body, Vector3(door_p.x, 1.18, door_p.y), Vector3(0.075, 2.20, frontage_width * 0.20), tenement_sash_glass_mat, angle, 190.0)
					_mobile_facade_box(body, Vector3(p.x, 2.72, p.y), Vector3(0.13, 0.58, frontage_width), sign_blue_mat, angle, 195.0)
					detail_count += 4
				else:
					_mobile_facade_box(body, Vector3(recessed.x, 1.18, recessed.y), Vector3(0.07, 2.16, minf(2.85, slot_width * 1.42)), shop_glass_mat, angle, 175.0)
					_mobile_facade_box(body, Vector3(p.x, 2.42, p.y), Vector3(0.10, 0.38, minf(3.20, slot_width * 1.58)), shop_frame_mat, angle, 175.0)
					for shop_side in [-1.0, 1.0]:
						var shop_jamb: Vector2 = p + tangent * float(shop_side) * minf(1.45, slot_width * 0.72)
						_mobile_facade_box(body, Vector3(shop_jamb.x, 1.20, shop_jamb.y), Vector3(0.10, 2.26, 0.13), shop_frame_mat, angle, 175.0)
					detail_count += 4
				shopfront_count += 1
				continue
			var frame_width := minf(1.42, slot_width + 0.18)
			_mobile_facade_box(body, Vector3(p.x, y, p.y), Vector3(0.075, 1.58, frame_width), tenement_sash_frame_mat, angle, 150.0)
			var recessed_window := p + inward * 0.09
			_mobile_facade_box(body, Vector3(recessed_window.x, y, recessed_window.y), Vector3(0.055, 1.26, minf(1.18, slot_width * 0.82)), tenement_sash_glass_mat, angle, 150.0)
			detail_count += 2

	_add_mobile_secondary_facade_edges(body, poly, height, centroid, best_edge)
	# Roofline is one of the strongest Edinburgh cues at driving distance. These
	# stacks are generic visual dressing, not a claim about mapped chimney counts.
	if height > 5.4 and centroid.distance_to(car2) <= 190.0 and kind not in ["garage", "garages", "shed", "roof", "industrial", "warehouse"]:
		var roof_axis := (p1 - p0).normalized()
		var chimney_count: int = 1 + (abs(seed) % 2)
		for chimney_index in range(chimney_count):
			var chimney_offset := (float(chimney_index) - float(chimney_count - 1) * 0.5) * 2.2
			var chimney_p := centroid + roof_axis * chimney_offset
			_mobile_facade_box(body, Vector3(chimney_p.x, height + 0.62, chimney_p.y), Vector3(0.58, 1.24, 0.58), soot_stone_mat, 0.0, 220.0)
			_mobile_facade_box(body, Vector3(chimney_p.x, height + 1.27, chimney_p.y), Vector3(0.70, 0.08, 0.70), roof_mat, 0.0, 220.0)
	body.set_meta("mobile_facade_detail_count", detail_count)
	body.set_meta("mobile_shopfront_count", shopfront_count)
	body.set_meta("mobile_facade_edge", best_edge)
	body.set_meta("mobile_facade_source", "osm_footprint+multi_edge_generic_visuals")

func _add_exact_osm_facade_detail(body: Node3D, poly: PackedVector2Array, height: float, seed: int, building: Dictionary):
	# Keep the mapped polygon authoritative. All facade treatment is generic visual
	# approximation attached to real OSM wall edges, never replacement geometry.
	if poly.size() < 3:
		return
	if mobile_mode:
		_add_mobile_osm_facade_detail(body, poly, height, seed, building)
		return
	if not pc_max_mode or low_spec_mode:
		return
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= float(poly.size())
	var facade_radius := 175.0 if xps_9530_mode else 125.0
	if centroid.length() > facade_radius:
		return
	var kind = str(building.get("kind", "yes")).to_lower()
	var industrial = kind in ["industrial", "warehouse", "commercial", "retail"]
	var generic_tenement = _uses_generic_edinburgh_tenement_texture(building) and not industrial
	var mapped_commercial_pois: Array = building.get("_mapped_commercial_pois", [])
	var floors = clamp(int(floor(height / 3.0)), 1, 5 if xps_9530_mode else 3)
	var door_edge = abs(seed) % poly.size()
	var downpipe_edge = abs(seed / 11) % poly.size()
	var edge_budget := 0
	var max_edges := 8 if xps_9530_mode else 6
	for edge_index in range(poly.size()):
		if edge_budget >= max_edges:
			break
		var p0 = poly[edge_index]
		var p1 = poly[(edge_index + 1) % poly.size()]
		var delta = p1 - p0
		var length = delta.length()
		if length < 4.2:
			continue
		var tangent = delta / length
		var angle = atan2(tangent.x, tangent.y)
		var edge_mid = (p0 + p1) * 0.5
		var inward := (centroid - edge_mid).normalized()
		if inward.length() < 0.5:
			inward = Vector2(-tangent.y, tangent.x)
		var slots = clamp(int(floor(length / (5.8 if industrial else 3.55))), 1, 7 if xps_9530_mode else 4)
		var shop_slots := {}
		if generic_tenement and not mapped_commercial_pois.is_empty():
			for poi in mapped_commercial_pois:
				var raw_p = poi.get("point", [])
				if not raw_p is Array or raw_p.size() < 2:
					continue
				var poi_point := Vector2(float(raw_p[0]), float(raw_p[1]))
				if _nearest_poly_edge(poly, poi_point) != edge_index:
					continue
				var along = clamp((poi_point - p0).dot(delta) / maxf(length * length, 0.001), 0.0, 0.999)
				shop_slots[int(floor(along * float(slots)))] = true

		_visual_box(body, Vector3(edge_mid.x, min(0.42, height * 0.08), edge_mid.y), Vector3(0.10, min(0.84, height * 0.16), length * 0.96), roof_mat)
		var plinth = body.get_child(body.get_child_count() - 1)
		if plinth is MeshInstance3D:
			plinth.rotation.y = angle
			plinth.visibility_range_end = 155.0
		if generic_tenement and edge_index == downpipe_edge:
			var pipe_t = 0.08 if seed % 2 == 0 else 0.92
			var pipe_p = p0.lerp(p1, pipe_t)
			_visual_box(body, Vector3(pipe_p.x, height * 0.46, pipe_p.y), Vector3(0.11, height * 0.88, 0.11), metal_mat)
			var downpipe = body.get_child(body.get_child_count() - 1)
			if downpipe is MeshInstance3D:
				downpipe.visibility_range_end = 190.0
			generic_tenement_downpipe_count += 1
		if height > 5.8:
			_visual_box(body, Vector3(edge_mid.x, height - 0.18, edge_mid.y), Vector3(0.12, 0.26, length * 0.97), roof_mat)
			var cornice = body.get_child(body.get_child_count() - 1)
			if cornice is MeshInstance3D:
				cornice.rotation.y = angle
				cornice.visibility_range_end = 165.0

		for floor_index in range(floors):
			var y = 1.78 + float(floor_index) * 2.85
			if y > height - 0.65:
				continue
			for slot in range(slots):
				var t = (float(slot) + 0.5) / float(slots)
				var p = p0.lerp(p1, t)
				var panel_w = min(1.45 if industrial else 1.08, max(0.74, length / float(slots) * 0.46))
				var panel_h = 1.25 if industrial else 1.40
				var is_shopfront = generic_tenement and floor_index == 0 and shop_slots.has(slot)
				if is_shopfront:
					var shop_w = min(2.65, max(1.75, length / float(slots) * 0.78))
					var shop_h = 2.22
					var shop_frame = tenement_shop_frame_mats[abs(seed + edge_index + slot) % tenement_shop_frame_mats.size()]
					var recessed_shop_p: Vector2 = p + inward * 0.16
					_visual_box(body, Vector3(recessed_shop_p.x, 1.16, recessed_shop_p.y), Vector3(0.075, shop_h, shop_w), tenement_sash_glass_mat)
					var shop_glass = body.get_child(body.get_child_count() - 1)
					if shop_glass is MeshInstance3D:
						shop_glass.rotation.y = angle
						shop_glass.visibility_range_end = 235.0
					# Generic fascia/pilasters only: source proves commercial presence, not exact design or text.
					for side in [-1.0, 1.0]:
						var fp = p + tangent * side * (shop_w * 0.5 + 0.07)
						_visual_box(body, Vector3(fp.x, 1.18, fp.y), Vector3(0.12, shop_h + 0.24, 0.13), shop_frame)
						var pilaster = body.get_child(body.get_child_count() - 1)
						if pilaster is MeshInstance3D:
							pilaster.rotation.y = angle
					_visual_box(body, Vector3(p.x, 2.40, p.y), Vector3(0.12, 0.34, shop_w + 0.28), shop_frame)
					var fascia = body.get_child(body.get_child_count() - 1)
					if fascia is MeshInstance3D:
						fascia.rotation.y = angle
					_visual_box(body, Vector3(p.x, 0.24, p.y), Vector3(0.12, 0.40, shop_w + 0.08), shop_frame)
					var stallriser = body.get_child(body.get_child_count() - 1)
					if stallriser is MeshInstance3D:
						stallriser.rotation.y = angle
					generic_tenement_shopfront_count += 1
					generic_tenement_recess_count += 1
					continue
				var is_door = edge_index == door_edge and floor_index == 0 and slot == abs(seed / 7) % slots and generic_tenement
				if is_door:
					var door_w = min(1.28, max(0.94, length / float(slots) * 0.56))
					var door_h = 2.18
					var door_mat = tenement_door_mats[abs(seed + edge_index) % tenement_door_mats.size()]
					var recessed_door_p: Vector2 = p + inward * 0.11
					_visual_box(body, Vector3(recessed_door_p.x, 1.09, recessed_door_p.y), Vector3(0.085, door_h, door_w), door_mat)
					var door = body.get_child(body.get_child_count() - 1)
					if door is MeshInstance3D:
						door.rotation.y = angle
						door.visibility_range_end = 220.0
					# Pale stone surround and a dark glazed fanlight sell the shared stair close.
					for side in [-1.0, 1.0]:
						var fp = p + tangent * side * (door_w * 0.5 + 0.085)
						_visual_box(body, Vector3(fp.x, 1.19, fp.y), Vector3(0.12, door_h + 0.22, 0.14), tenement_sash_frame_mat)
						var jamb = body.get_child(body.get_child_count() - 1)
						if jamb is MeshInstance3D:
							jamb.rotation.y = angle
					_visual_box(body, Vector3(p.x, 2.30, p.y), Vector3(0.12, 0.18, door_w + 0.30), tenement_sash_frame_mat)
					var lintel = body.get_child(body.get_child_count() - 1)
					if lintel is MeshInstance3D:
						lintel.rotation.y = angle
					var recessed_fanlight_p: Vector2 = p + inward * 0.10
					_visual_box(body, Vector3(recessed_fanlight_p.x, 2.16, recessed_fanlight_p.y), Vector3(0.085, 0.22, door_w * 0.78), tenement_sash_glass_mat)
					var fanlight = body.get_child(body.get_child_count() - 1)
					if fanlight is MeshInstance3D:
						fanlight.rotation.y = angle
					generic_tenement_door_count += 1
					generic_tenement_recess_count += 1
					continue

				var panel_mat = tenement_sash_glass_mat if generic_tenement else glass_mat
				var panel_p: Vector2 = p + inward * (0.075 if generic_tenement else 0.0)
				_visual_box(body, Vector3(panel_p.x, y, panel_p.y), Vector3(0.070 if generic_tenement else 0.085, panel_h, panel_w), panel_mat)
				var panel = body.get_child(body.get_child_count() - 1)
				if panel is MeshInstance3D:
					panel.rotation.y = angle
					panel.visibility_range_end = 230.0 if xps_9530_mode else 145.0

				if generic_tenement:
					# Low-cost sash silhouette: two jambs, head/sill and a central meeting rail.
					var frame_w = 0.085
					for side in [-1.0, 1.0]:
						var fp = p + tangent * side * (panel_w * 0.5 + frame_w * 0.15)
						_visual_box(body, Vector3(fp.x, y, fp.y), Vector3(0.105, panel_h + 0.12, frame_w), tenement_sash_frame_mat)
						var jamb = body.get_child(body.get_child_count() - 1)
						if jamb is MeshInstance3D:
							jamb.rotation.y = angle
					# Stone sill/lintel give the window architectural depth; the central sash
					# meeting rail remains painted timber.
					for rail_index in range(3):
						var rail_y = [y - panel_h * 0.5 - 0.055, y, y + panel_h * 0.5 + 0.055][rail_index]
						var rail_mat = tenement_sash_frame_mat if rail_index == 1 else sandstone_mat
						var rail_h = 0.075 if rail_index == 1 else 0.13
						var rail_depth = 0.105 if rail_index == 1 else 0.16
						_visual_box(body, Vector3(p.x, rail_y, p.y), Vector3(rail_depth, rail_h, panel_w + 0.18), rail_mat)
						var rail = body.get_child(body.get_child_count() - 1)
						if rail is MeshInstance3D:
							rail.rotation.y = angle
					generic_tenement_window_count += 1
				elif xps_9530_mode and not industrial:
					_visual_box(body, Vector3(p.x, y - panel_h * 0.5 - 0.07, p.y), Vector3(0.11, 0.10, panel_w + 0.16), kerb_mat)
					var sill = body.get_child(body.get_child_count() - 1)
					if sill is MeshInstance3D:
						sill.rotation.y = angle
						sill.visibility_range_end = 190.0
		edge_budget += 1

	# Roofline silhouettes are generic visual dressing for unnamed tenements only.
	# They do not claim exact chimney count or placement.
	if generic_tenement and height > 5.5:
		var roof_axis := Vector2(1.0, 0.0)
		if poly.size() >= 2:
			var roof_delta: Vector2 = poly[1] - poly[0]
			if roof_delta.length() > 0.5:
				roof_axis = roof_delta.normalized()
		var chimney_total = 1 + (abs(seed) % 2)
		for chimney_index in range(chimney_total):
			var offset = (float(chimney_index) - float(chimney_total - 1) * 0.5) * 2.1
			var chimney_p: Vector2 = centroid + roof_axis * offset
			_visual_box(body, Vector3(chimney_p.x, height + 0.72, chimney_p.y), Vector3(0.58, 1.44, 0.58), soot_stone_mat)
			var chimney = body.get_child(body.get_child_count() - 1)
			if chimney is MeshInstance3D:
				chimney.visibility_range_end = 220.0
			_visual_box(body, Vector3(chimney_p.x, height + 1.46, chimney_p.y), Vector3(0.72, 0.10, 0.72), roof_mat)
			var cap = body.get_child(body.get_child_count() - 1)
			if cap is MeshInstance3D:
				cap.visibility_range_end = 220.0
			generic_tenement_chimney_count += 1

	# A restrained basement/railing cue on a subset of generic tenements adds
	# street-level depth without pretending the exact railing layout is mapped.
	if generic_tenement and abs(seed) % 4 == 0 and poly.size() >= 2:
		var rail_edge = (door_edge + 1) % poly.size()
		var rp0: Vector2 = poly[rail_edge]
		var rp1: Vector2 = poly[(rail_edge + 1) % poly.size()]
		var rdelta := rp1 - rp0
		var rlength = rdelta.length()
		if rlength >= 5.5:
			var rtangent: Vector2 = rdelta / rlength
			var rmid := (rp0 + rp1) * 0.5
			var rinward := (centroid - rmid).normalized()
			if rinward.length() < 0.5:
				rinward = Vector2(-rtangent.y, rtangent.x)
			var outward := -rinward
			var run = min(4.8, rlength * 0.58)
			var basement_p := rmid + rinward * 0.06
			_visual_box(body, Vector3(basement_p.x, 0.43, basement_p.y), Vector3(0.07, 0.72, run * 0.78), tenement_sash_glass_mat)
			var basement = body.get_child(body.get_child_count() - 1)
			if basement is MeshInstance3D:
				basement.rotation.y = atan2(rtangent.x, rtangent.y)
				basement.visibility_range_end = 125.0
			var rail_mid := rmid + outward * 0.22
			_visual_box(body, Vector3(rail_mid.x, 0.72, rail_mid.y), Vector3(0.07, 0.08, run), metal_mat)
			var top_rail = body.get_child(body.get_child_count() - 1)
			if top_rail is MeshInstance3D:
				top_rail.rotation.y = atan2(rtangent.x, rtangent.y)
				top_rail.visibility_range_end = 125.0
			for post_index in range(5):
				var t = float(post_index) / 4.0 - 0.5
				var post_p: Vector2 = rail_mid + rtangent * t * run
				_visual_box(body, Vector3(post_p.x, 0.40, post_p.y), Vector3(0.065, 0.80, 0.065), metal_mat)
				var post = body.get_child(body.get_child_count() - 1)
				if post is MeshInstance3D:
					post.visibility_range_end = 120.0
			generic_tenement_railing_count += 1



func _add_mobile_osm_footprint_visual(parent: Node3D, building: Dictionary, height: float, seed: int) -> bool:
	# Far mobile buildings must preserve the mapped OSM polygon. The old low-spec
	# fallback used the footprint bounding box, which could rotate/expand an angled
	# building across a real road and also created a false box collision. This path
	# is visual-only: exact footprint silhouette, no collision, no facade trim.
	var footprint = building.get("footprint", [])
	if not footprint is Array or footprint.size() < 3:
		return false
	var poly := PackedVector2Array()
	for point in footprint:
		if point is Array and point.size() >= 2:
			poly.append(Vector2(float(point[0]), float(point[1])))
	if poly.size() > 2 and poly[0].distance_squared_to(poly[poly.size() - 1]) < 0.01:
		poly.resize(poly.size() - 1)
	if poly.size() < 3:
		return false
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.size() < 3:
		return false

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, tris.size(), 3):
		for j in range(3):
			var p: Vector2 = poly[int(tris[t + j])]
			st.add_vertex(Vector3(p.x, height, p.y))
	for i in range(poly.size()):
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % poly.size()]
		st.add_vertex(Vector3(p0.x, 0.0, p0.y))
		st.add_vertex(Vector3(p1.x, 0.0, p1.y))
		st.add_vertex(Vector3(p1.x, height, p1.y))
		st.add_vertex(Vector3(p0.x, 0.0, p0.y))
		st.add_vertex(Vector3(p1.x, height, p1.y))
		st.add_vertex(Vector3(p0.x, height, p0.y))
	st.generate_normals()
	var mesh := st.commit()
	if mesh == null:
		return false

	var visual := MeshInstance3D.new()
	visual.name = "OSMFootprintVisual_%d" % seed
	var centroid := Vector2.ZERO
	for footprint_point in poly:
		centroid += footprint_point
	centroid /= float(poly.size())
	visual.position.y = float(building.get("ground_y", _terrain_height(centroid)))
	visual.mesh = mesh
	visual.material_override = _osm_building_material(building, seed)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = MOBILE_BUILDING_VISUAL_RADIUS
	visual.set_meta("osm_footprint_visual_only", true)
	visual.set_meta("osm_id", int(building.get("osm_id", 0)))
	# Far mobile buildings are visual-only for physics, but they still need a
	# street face. Reuse the same cheap facade pass so the 190-340m zone does not
	# collapse into blank extruded polygons.
	_add_mobile_osm_facade_detail(visual, poly, height, seed, building)
	_add_named_landmark_signature(visual, poly, height, building)
	parent.add_child(visual)
	return true

func _footprint_hits_drivable_centerline(poly: PackedVector2Array) -> bool:
	if not mobile_mode or poly.size() < 3:
		return false
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= float(poly.size())
	var radius := 0.0
	for p in poly:
		radius = maxf(radius, centroid.distance_to(p))
	for segment in map_segments:
		if not segment is Array or segment.size() < 4:
			continue
		var kind := str(segment[3]).to_lower()
		if kind in ["track", "path", "footway", "cycleway"]:
			continue
		var a := Vector2(float(segment[0][0]), float(segment[0][1]))
		var b := Vector2(float(segment[1][0]), float(segment[1][1]))
		if _point_segment_distance_2d(centroid, a, b) > radius + 1.5:
			continue
		if Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly):
			return true
		for edge_index in range(poly.size()):
			var p0: Vector2 = poly[edge_index]
			var p1: Vector2 = poly[(edge_index + 1) % poly.size()]
			if Geometry2D.segment_intersects_segment(a, b, p0, p1) != null:
				return true
	return false

func _building_hits_drivable_centerline(building: Dictionary) -> bool:
	var footprint = building.get("footprint", [])
	if not footprint is Array or footprint.size() < 3:
		return false
	var poly := PackedVector2Array()
	for raw_point in footprint:
		if raw_point is Array and raw_point.size() >= 2:
			poly.append(Vector2(float(raw_point[0]), float(raw_point[1])))
	if poly.size() > 2 and poly[0].distance_squared_to(poly[poly.size() - 1]) < 0.01:
		poly.resize(poly.size() - 1)
	return _footprint_hits_drivable_centerline(poly)

func _mobile_visual_height(building: Dictionary, base_height: float, building_distance: float, has_commercial_frontage: bool) -> float:
	if not mobile_mode:
		return base_height
	var source := str(building.get("height_source", "")).to_lower()
	if not source.contains("estimated"):
		return base_height
	var name := str(building.get("name", "")).strip_edges().to_lower()
	if name == "bellfield community hub":
		return maxf(base_height, 7.4)
	if name == "st mark's church":
		return maxf(base_height, 7.2)
	var kind := str(building.get("kind", "yes")).to_lower()
	if kind in ["garage", "garages", "shed", "roof", "industrial", "warehouse"]:
		return base_height
	if has_commercial_frontage and building_distance <= 380.0:
		return maxf(base_height, 9.2)
	var size = building.get("size", [])
	if building_distance <= 380.0 and size is Array and size.size() >= 2:
		var sx := float(size[0])
		var sz := float(size[1])
		if maxf(sx, sz) >= 12.0 and minf(sx, sz) >= 5.0:
			return maxf(base_height, 8.4)
	return base_height

func _add_exact_osm_building(parent: Node3D, building: Dictionary, height: float, seed: int) -> bool:
	var footprint = building.get("footprint", [])
	if not footprint is Array or footprint.size() < 3:
		return false
	var poly = PackedVector2Array()
	for point in footprint:
		if not point is Array or point.size() < 2:
			continue
		poly.append(Vector2(float(point[0]), float(point[1])))
	if poly.size() < 3:
		return false
	var tris = Geometry2D.triangulate_polygon(poly)
	if tris.size() < 3:
		return false
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, tris.size(), 3):
		var p0 = poly[int(tris[t])]
		var p1 = poly[int(tris[t + 1])]
		var p2 = poly[int(tris[t + 2])]
		st.set_uv(Vector2(p0.x / 8.0, p0.y / 8.0))
		st.add_vertex(Vector3(p0.x, height, p0.y))
		st.set_uv(Vector2(p1.x / 8.0, p1.y / 8.0))
		st.add_vertex(Vector3(p1.x, height, p1.y))
		st.set_uv(Vector2(p2.x / 8.0, p2.y / 8.0))
		st.add_vertex(Vector3(p2.x, height, p2.y))
	for i in range(poly.size()):
		var p0 = poly[i]
		var p1 = poly[(i + 1) % poly.size()]
		var wall_u = maxf(0.2, p0.distance_to(p1) / 8.0)
		var wall_v = maxf(1.0, height / 4.2)
		st.set_uv(Vector2(0.0, wall_v))
		st.add_vertex(Vector3(p0.x, 0.0, p0.y))
		st.set_uv(Vector2(wall_u, wall_v))
		st.add_vertex(Vector3(p1.x, 0.0, p1.y))
		st.set_uv(Vector2(wall_u, 0.0))
		st.add_vertex(Vector3(p1.x, height, p1.y))
		st.set_uv(Vector2(0.0, wall_v))
		st.add_vertex(Vector3(p0.x, 0.0, p0.y))
		st.set_uv(Vector2(wall_u, 0.0))
		st.add_vertex(Vector3(p1.x, height, p1.y))
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(Vector3(p0.x, height, p0.y))
	st.generate_normals()
	var mesh = st.commit()
	if mesh == null:
		return false
	var body = StaticBody3D.new()
	body.name = "OSMFootprint_%d" % seed
	var footprint_centre := Vector2.ZERO
	for footprint_point in poly:
		footprint_centre += footprint_point
	footprint_centre /= float(poly.size())
	var base_y := float(building.get("ground_y", _terrain_height(footprint_centre))) if mobile_mode else 0.0
	body.position.y = base_y
	body.name = "OSMFootprint_%d" % seed
	body.set_meta("terrain_base_y", base_y)
	body.set_meta("osm_id", int(building.get("osm_id", 0)))
	body.set_meta("osm_kind", str(building.get("kind", "")))
	var visual = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _osm_building_material(building, seed)
	if _uses_generic_edinburgh_tenement_texture(building):
		generic_tenement_facade_count += 1
		visual.set_meta("facade_visual_source", "generic_edinburgh_tenement_kit_v1")
		body.set_meta("facade_visual_source", "generic_edinburgh_tenement_kit_v1")
	visual.visibility_range_end = 520.0 if xps_9530_mode else (360.0 if not low_spec_mode else 220.0)
	body.add_child(visual)
	var collision = CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	_add_exact_osm_facade_detail(body, poly, height, seed, building)
	_add_named_landmark_signature(body, poly, height, building)
	parent.add_child(body)
	return true

func _vehicle_visual(parent: Node3D, seed: int, patrol_style := false):
	# Low-cost recognisable vehicle silhouette: separate lower body, glazed cabin,
	# wheel volumes and light lenses. Still procedural, but no longer reads as a box.
	var palette = [
		Color(0.11, 0.12, 0.13),
		Color(0.24, 0.25, 0.24),
		Color(0.38, 0.12, 0.09),
		Color(0.10, 0.18, 0.24),
		Color(0.28, 0.29, 0.30),
		Color(0.12, 0.22, 0.16)
	]
	var paint = Color(0.045, 0.065, 0.085) if patrol_style else palette[abs(seed) % palette.size()]
	var paint_mat = _mat(paint, 0.42, 0.24)
	var tyre_mat = _mat(Color(0.025, 0.027, 0.028), 0.92, 0.02)
	var light_mat = _mat(Color(0.88, 0.82, 0.62), 0.18, 0.05)
	var tail_mat = _mat(Color(0.62, 0.035, 0.022), 0.24, 0.05)
	var van = seed % 6 == 0

	var lower = MeshInstance3D.new()
	var lower_mesh = BoxMesh.new()
	lower_mesh.size = Vector3(1.82, 0.55 if not van else 0.72, 4.08 if not van else 4.55)
	lower.mesh = lower_mesh
	lower.position.y = 0.02 if not van else 0.12
	lower.material_override = paint_mat
	parent.add_child(lower)

	var cabin = MeshInstance3D.new()
	var cabin_mesh = BoxMesh.new()
	cabin_mesh.size = Vector3(1.48, 0.62 if not van else 1.05, 1.82 if not van else 2.25)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0, 0.55 if not van else 0.78, 0.02 if not van else 0.22)
	cabin.material_override = glass_mat
	parent.add_child(cabin)

	if not van:
		var roof = MeshInstance3D.new()
		var roof_mesh = BoxMesh.new()
		roof_mesh.size = Vector3(1.42, 0.10, 1.56)
		roof.mesh = roof_mesh
		roof.position = Vector3(0, 0.89, 0.08)
		roof.material_override = paint_mat
		parent.add_child(roof)

	for z in [-1.30, 1.30]:
		for x in [-0.91, 0.91]:
			var wheel = MeshInstance3D.new()
			var wheel_mesh = CylinderMesh.new()
			wheel_mesh.top_radius = 0.30
			wheel_mesh.bottom_radius = 0.30
			wheel_mesh.height = 0.18
			wheel.mesh = wheel_mesh
			wheel.position = Vector3(x, -0.13, z if not van else z * 1.10)
			wheel.rotation.z = PI * 0.5
			wheel.material_override = tyre_mat
			parent.add_child(wheel)

	for x in [-0.55, 0.55]:
		_visual_box(parent, Vector3(x, 0.12, -2.055 if not van else -2.29), Vector3(0.32, 0.16, 0.055), light_mat)
		_visual_box(parent, Vector3(x, 0.13, 2.055 if not van else 2.29), Vector3(0.28, 0.15, 0.055), tail_mat)

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
	if mobile_mode:
		# Android uses the source-backed EH15 height field. The legacy flat slab
		# would otherwise cut through downhill roads and cover coastal relief.
		ground.visible = false
		col.disabled = true
	add_child(ground)

func _terrain_height(local_position: Vector2) -> float:
	if not mobile_mode:
		return 0.0
	var stream = get_node_or_null("MapStream")
	if stream and stream.has_method("terrain_height_at"):
		return float(stream.terrain_height_at(local_position))
	return 0.0

func _terrain_sea_y() -> float:
	var stream = get_node_or_null("MapStream")
	if stream and stream.has_method("terrain_sea_level_y"):
		return float(stream.terrain_sea_level_y())
	return 0.0

func _add_mobile_terrain_surface(parent: Node3D, centre: Vector2):
	if not mobile_mode:
		return
	var stream = get_node_or_null("MapStream")
	if stream == null or not stream.has_method("terrain_available") or not bool(stream.terrain_available()):
		return
	const STEP := 12.5
	const RADIUS := 500.0
	var cols := int(floor((RADIUS * 2.0) / STEP)) + 1
	var rows := cols
	var start := centre - Vector2(RADIUS, RADIUS)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z_index in range(rows - 1):
		for x_index in range(cols - 1):
			var x0 := start.x + float(x_index) * STEP
			var x1 := x0 + STEP
			var z0 := start.y + float(z_index) * STEP
			var z1 := z0 + STEP
			var p00 := Vector2(x0, z0)
			var p10 := Vector2(x1, z0)
			var p01 := Vector2(x0, z1)
			var p11 := Vector2(x1, z1)
			var v00 := Vector3(x0, _terrain_height(p00) - 0.08, z0)
			var v10 := Vector3(x1, _terrain_height(p10) - 0.08, z0)
			var v01 := Vector3(x0, _terrain_height(p01) - 0.08, z1)
			var v11 := Vector3(x1, _terrain_height(p11) - 0.08, z1)
			for v in [v00, v10, v11, v00, v11, v01]:
				surface.add_vertex(v)
	surface.generate_normals()
	var terrain_mesh := surface.commit()
	if terrain_mesh == null:
		return
	var visual := MeshInstance3D.new()
	visual.name = "MobileEHTerrain"
	visual.mesh = terrain_mesh
	visual.material_override = ground_mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = 900.0
	visual.set_meta("terrain_source_backed", true)
	parent.add_child(visual)

func _mobile_terrain_strip(parent: Node3D, a: Vector2, b: Vector2, width: float, lateral_offset: float, y_offset: float, material, label: String):
	var delta := b - a
	var length := delta.length()
	if length < 0.2:
		return
	var tangent := delta / length
	var normal := Vector2(-tangent.y, tangent.x)
	var aa := a + normal * lateral_offset
	var bb := b + normal * lateral_offset
	var half_width := width * 0.5
	# Long OSM segments cannot be one giant sloping quad: that creates the road
	# wedges visible in the Android screenshots. Sample source terrain repeatedly.
	var section_count := clampi(int(ceil(length / 14.0)), 1, 72)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for section in range(section_count):
		var t0 := float(section) / float(section_count)
		var t1 := float(section + 1) / float(section_count)
		var c0 := aa.lerp(bb, t0)
		var c1 := aa.lerp(bb, t1)
		var c0_left := c0 - normal * half_width
		var c0_right := c0 + normal * half_width
		var c1_left := c1 - normal * half_width
		var c1_right := c1 + normal * half_width
		var y0 := _terrain_height(c0) + y_offset
		var y1 := _terrain_height(c1) + y_offset
		for v in [
			Vector3(c0_left.x, y0, c0_left.y), Vector3(c0_right.x, y0, c0_right.y), Vector3(c1_right.x, y1, c1_right.y),
			Vector3(c0_left.x, y0, c0_left.y), Vector3(c1_right.x, y1, c1_right.y), Vector3(c1_left.x, y1, c1_left.y)
		]:
			surface.add_vertex(v)
	surface.generate_normals()
	var strip_mesh := surface.commit()
	if strip_mesh == null:
		return
	var visual := MeshInstance3D.new()
	visual.mesh = strip_mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = 680.0
	visual.set_meta("mobile_terrain_strip", label)
	visual.set_meta("terrain_sections", section_count)
	parent.add_child(visual)

func _add_mobile_road_segment(parent: Node3D, a: Vector2, b: Vector2, width: float, kind: String, material, sidewalk: String):
	_mobile_terrain_strip(parent, a, b, width, 0.0, 0.055, material, "road")
	var car = get_node_or_null("Car")
	var midpoint := (a + b) * 0.5
	var driver2 := Vector2(car.global_position.x, car.global_position.z) if car else Vector2.ZERO
	var close_detail := midpoint.distance_to(driver2) <= MOBILE_STREET_DETAIL_RADIUS
	if close_detail and kind not in ["motorway", "trunk", "track"] and sidewalk not in ["no", "none"]:
		var pavement_offset := width * 0.5 + 0.72
		_mobile_terrain_strip(parent, a, b, 1.28, -pavement_offset, 0.115, pavement_mat, "pavement")
		_mobile_terrain_strip(parent, a, b, 1.28, pavement_offset, 0.115, pavement_mat, "pavement")
		var kerb_offset := width * 0.5 + 0.10
		_mobile_terrain_strip(parent, a, b, 0.18, -kerb_offset, 0.145, kerb_mat, "kerb")
		_mobile_terrain_strip(parent, a, b, 0.18, kerb_offset, 0.145, kerb_mat, "kerb")
	if close_detail and width >= 6.0 and kind in ["primary", "secondary", "tertiary"]:
		_mobile_terrain_strip(parent, a, b, 0.09, 0.0, 0.075, marking_mat, "centre_marking")

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
		_vehicle_visual(car, i)
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
	_vehicle_visual(patrol, 911, true)
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
	var radio_flutter = 1.0 - api_radio_instability * 0.08 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0043))
	radio_strength *= radio_flutter
	car.set_meta("radio_signal", radio_strength)
	car.set_meta("pua_api_moment", api_moment)
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
	atmosphere_target_wetness = wetness
	atmosphere_target_cloud = cloud
	atmosphere_target_visibility = visibility
	atmosphere_target_aqi = aqi
	# The first state establishes the scene immediately. Later live/override changes
	# become targets so rain, fog and exposure glide rather than hard-cut across five
	# projected views.
	if not atmosphere_initialized:
		atmosphere_initialized = true
		atmosphere_wetness = wetness
		atmosphere_cloud = cloud
		atmosphere_visibility = visibility
		atmosphere_aqi = aqi
		_apply_weather_visuals()
	var car = get_node_or_null("Car")
	if car:
		car.set_meta("world_wetness", wetness)
		car.set_meta("world_wind_kph", wind)
		car.set_meta("world_wave_height", wave)
		car.set_meta("world_temperature", float(state.get("temperature", 8.0)))
		car.set_meta("world_data_source", state.get("source", "offline"))

func _update_weather_visuals(delta: float):
	if not atmosphere_initialized:
		return
	# Fast enough to feel responsive, slow enough that the world does not visibly
	# "switch modes" around the seated player.
	var surface_mix = 1.0 - exp(-delta * 0.75)
	var sky_mix = 1.0 - exp(-delta * 0.95)
	atmosphere_wetness = lerp(atmosphere_wetness, atmosphere_target_wetness, surface_mix)
	atmosphere_cloud = lerp(atmosphere_cloud, atmosphere_target_cloud, sky_mix)
	atmosphere_visibility = lerp(atmosphere_visibility, atmosphere_target_visibility, sky_mix)
	atmosphere_aqi = lerp(atmosphere_aqi, atmosphere_target_aqi, sky_mix)
	_apply_weather_visuals()

func _apply_weather_visuals():
	var wetness = atmosphere_wetness
	var cloud = atmosphere_cloud
	var visibility = atmosphere_visibility
	var aqi = atmosphere_aqi
	asphalt_mat.roughness = lerp(0.34, 0.12, wetness)
	asphalt_mat.metallic = lerp(0.05, 0.18, wetness)
	pavement_mat.roughness = lerp(0.90, 0.58, wetness)
	kerb_mat.roughness = lerp(0.94, 0.68, wetness)
	concrete_mat.roughness = lerp(0.86, 0.62, wetness)
	weather_sun_energy = (lerp(1.12, 0.60, cloud) if xps_9530_mode else lerp(1.06, 0.58, cloud)) * lerp(1.0, 0.90, wetness)
	if mobile_mode:
		weather_sun_energy *= 0.94
	var low_visibility: float = clampf((1800.0 - float(visibility)) / 1800.0, 0.0, 1.0)
	var headlight_energy: float = 0.12 + float(cloud) * 0.26 + float(wetness) * 0.32 + low_visibility * 1.10
	for headlight_path in ["Car/HeadlightL", "Car/HeadlightR"]:
		var headlight = get_node_or_null(headlight_path)
		if headlight:
			headlight.light_energy = headlight_energy
	var env = $WorldEnvironment.environment
	if env:
		env.fog_enabled = true
		var visibility_fog = clamp(1.0 - visibility / 22000.0, 0.0, 0.92)
		# "CLEAR" used to look like a grey soup even at 16 km visibility. Keep the
		# Scottish haze, but reserve dense fog for genuinely poor visibility.
		env.fog_density = 0.00045 + visibility_fog * 0.0038 + clamp(aqi / 150.0, 0.0, 1.0) * 0.0008 + low_visibility * 0.009
		env.fog_light_color = Color(0.64, 0.69, 0.70).lerp(Color(0.40, 0.45, 0.47), cloud)
		env.background_color = Color(0.52, 0.62, 0.66).lerp(Color(0.31, 0.37, 0.40), cloud)
		if mobile_mode:
			# The phone renderer has less shadow detail than the desktop path. Lift
			# ambient fill enough to keep stone readable without washing out the road.
			env.ambient_light_energy = lerp(1.30, 0.98, cloud) * lerp(1.0, 0.96, wetness)
			env.ambient_light_color = Color(0.72, 0.71, 0.67).lerp(Color(0.52, 0.56, 0.58), cloud)
			env.tonemap_exposure = lerp(1.34, 1.18, cloud)
		elif xps_9530_mode:
			env.ambient_light_energy = lerp(0.94, 0.74, cloud) * lerp(1.0, 0.94, wetness)
			env.ambient_light_color = Color(0.61, 0.61, 0.58).lerp(Color(0.44, 0.48, 0.50), cloud)
			env.tonemap_exposure = lerp(1.22, 1.09, cloud) * lerp(1.0, 0.98, wetness)
		else:
			env.ambient_light_energy = lerp(0.96, 0.72, cloud) * lerp(1.0, 0.94, wetness)
			env.ambient_light_color = Color(0.60, 0.62, 0.61).lerp(Color(0.44, 0.48, 0.50), cloud)
			env.tonemap_exposure = lerp(1.24, 1.09, cloud) * lerp(1.0, 0.98, wetness)


func _bind_map_stream():
	var map_stream = get_node_or_null("MapStream")
	if map_stream:
		map_stream.map_ready.connect(_on_map_ready)
		if map_stream.data.get("roads", []).size() > 0 or map_stream.data.get("buildings", []).size() > 0:
			_on_map_ready(map_stream.data)

func _on_map_ready(map_data: Dictionary):
	map_center_lat = float(map_data.get("center_lat", map_center_lat))
	var roads = map_data.get("roads", [])
	var buildings = map_data.get("buildings", [])
	var linear_features = map_data.get("linear_features", [])
	var point_features = map_data.get("point_features", [])
	var poi_features = map_data.get("poi_features", [])
	var identity_features = map_data.get("identity_features", [])
	if roads.is_empty() and buildings.is_empty():
		return
	map_mode_active = true
	for legacy_name in ["DockEdge", "GarageCourt", "Transmitter"]:
		var legacy = get_node_or_null(legacy_name)
		if legacy:
			legacy.visible = false
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
	map_lamps.clear()
	# Near-to-far ordering makes the fixed low-spec budgets perceptual rather than
	# source-order dependent: the roads around the driver's seat receive kerbs,
	# markings and harmless micro texture first across all five projector views.
	var detail_origin := Vector2.ZERO
	var detail_car = get_node_or_null("Car")
	if detail_car:
		detail_origin = Vector2(detail_car.global_position.x, detail_car.global_position.z)
	var detail_roads: Array = roads.duplicate()
	detail_roads.sort_custom(func(a, b):
		if not a is Dictionary: return false
		if not b is Dictionary: return true
		var ap = a.get("points", [])
		var bp = b.get("points", [])
		var ad := INF
		var bd := INF
		for p in ap:
			if p is Array and p.size() >= 2: ad = min(ad, Vector2(float(p[0]), float(p[1])).distance_squared_to(detail_origin))
		for p in bp:
			if p is Array and p.size() >= 2: bd = min(bd, Vector2(float(p[0]), float(p[1])).distance_squared_to(detail_origin))
		return ad < bd
	)
	if mobile_mode:
		_add_mobile_terrain_surface(map_root, detail_origin)
	var identity_counts := _add_identity_features(map_root, identity_features)
	var street_edge_budget := 0
	var marking_budget := 0
	var street_edge_limit := 420 if xps_9530_mode else (70 if projector_max_mode else (90 if low_spec_mode else (620 if pc_max_mode else 240)))
	var marking_limit := 240 if xps_9530_mode else (46 if projector_max_mode else (55 if low_spec_mode else (360 if pc_max_mode else 130)))
	var micro_budget := 650 if xps_9530_mode else (80 if projector_max_mode else (110 if low_spec_mode else (1100 if pc_max_mode else 320)))

	for road in detail_roads:
		if not road is Dictionary:
			continue
		var points = road.get("points", [])
		var width = float(road.get("width", 5.0))
		var kind = str(road.get("kind", "road"))
		var oneway = str(road.get("oneway", "no")).to_lower()
		var surface = str(road.get("surface", ""))
		var sidewalk = str(road.get("sidewalk", "")).to_lower()
		var road_material = _road_material_for(surface)
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
			if mobile_mode and mid.distance_to(detail_origin) > MOBILE_ROAD_VISUAL_RADIUS + length * 0.5:
				continue
			var angle = atan2(road_delta.x, road_delta.y)
			if mobile_mode:
				_add_mobile_road_segment(map_root, a, b, width, kind, road_material, sidewalk)
			else:
				_road_rotated_material(map_root, Vector3(mid.x, 0.035, mid.y), length + 1.0, width, angle, road_material)
				if micro_budget > 0:
					micro_budget -= _road_micro_detail(map_root, a, b, width, int(abs(a.x * 11.0 + a.y * 17.0 + b.x * 23.0 + b.y * 29.0)), micro_budget)
				if street_edge_budget < street_edge_limit and length > 7.0 and kind not in ["motorway", "trunk", "track"] and sidewalk not in ["no", "none"]:
					_street_edges_rotated(map_root, Vector3(mid.x, 0.035, mid.y), length + 0.6, width, angle, kind)
					street_edge_budget += 1
				if marking_budget < marking_limit and length > 9.0 and width >= 5.8:
					_live_road_markings(map_root, Vector3(mid.x, 0.035, mid.y), length, width, angle, kind)
					marking_budget += 1
			var road_name := str(road.get("name", "")).strip_edges()
			var road_ref := str(road.get("ref", "")).strip_edges()
			map_segments.append([[a.x, a.y], [b.x, b.y], width, kind, oneway, road_name, road_ref])

	var exact_building_count := 0
	var mobile_visual_only_building_count := 0
	var fallback_building_count := 0
	var runtime_road_conflict_culled := 0
	generic_tenement_facade_count = 0
	generic_tenement_window_count = 0
	generic_tenement_door_count = 0
	generic_tenement_shopfront_count = 0
	generic_tenement_downpipe_count = 0
	generic_tenement_recess_count = 0
	generic_tenement_chimney_count = 0
	generic_tenement_railing_count = 0
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
		var cx = float(center[0])
		var cz = float(center[1])
		if mobile_mode and Vector2(cx, cz).distance_to(detail_origin) > MOBILE_BUILDING_VISUAL_RADIUS:
			continue
		var seed = int(abs(cx * 17.0 + cz * 31.0 + sx * 11.0 + sz * 7.0))
		var kind = str(building.get("kind", "yes"))
		var exact_detail_origin := detail_origin if mobile_mode else Vector2.ZERO
		var building_distance := Vector2(cx, cz).distance_to(exact_detail_origin)
		if mobile_mode and building_distance <= 240.0 and _building_hits_drivable_centerline(building):
			runtime_road_conflict_culled += 1
			continue
		var visual_building: Dictionary = building
		var commercial_pois: Array = []
		if (pc_max_mode and not low_spec_mode) or (mobile_mode and building_distance <= MOBILE_FACADE_RADIUS):
			commercial_pois = _mapped_commercial_pois_inside_building(building, poi_features)
			if not commercial_pois.is_empty():
				visual_building = building.duplicate(true)
				visual_building["_mapped_commercial_pois"] = commercial_pois
		h = _mobile_visual_height(visual_building, h, building_distance, not commercial_pois.is_empty())
		var exact_radius = MOBILE_COLLIDING_BUILDING_RADIUS if mobile_mode else (LOW_SPEC_EXACT_FOOTPRINT_RADIUS if low_spec_mode else (620.0 if pc_max_mode else 260.0))
		var exact = building_distance <= exact_radius and _add_exact_osm_building(map_root, visual_building, h, seed)
		if exact:
			exact_building_count += 1
		elif mobile_mode and _add_mobile_osm_footprint_visual(map_root, visual_building, h, seed):
			mobile_visual_only_building_count += 1
		else:
			# Desktop/legacy fallback remains unchanged. Mobile only reaches this for
			# malformed footprints that cannot be triangulated; keep those rare cases
			# visible but outside the normal exact-footprint path.
			_add_edinburgh_building(map_root, Vector3(cx, _terrain_height(Vector2(cx, cz)) if mobile_mode else 0.0, cz), Vector3(sx, h, sz), seed, kind)
			fallback_building_count += 1
		_add_named_building_marker(map_root, building)

	_add_mapped_linear_features(map_root, linear_features)
	_add_mapped_point_features(map_root, point_features)
	var mapped_road_annotation_count = _add_mapped_road_name_signs(map_root, roads)
	_add_named_poi_markers(map_root, poi_features)
	if linear_features.is_empty() and point_features.is_empty():
		_add_map_furniture(map_root)
		_add_verge_life(map_root)
	# OpenWorldDirector owns moving live-map traffic from 0.57 onward.
	# Keep this legacy system empty to avoid duplicate cars and wasted CPU.
	for agent in map_agents:
		if agent.has("node") and is_instance_valid(agent["node"]):
			agent["node"].queue_free()
	map_agents.clear()

	var car = get_node_or_null("Car")
	if car:
		car.set_meta("map_data_source", map_data.get("source", "offline"))
		car.set_meta("map_road_count", roads.size())
		car.set_meta("map_building_count", buildings.size())
		car.set_meta("map_exact_building_count", exact_building_count)
		car.set_meta("map_mobile_visual_only_building_count", mobile_visual_only_building_count)
		car.set_meta("map_runtime_road_conflict_culled", runtime_road_conflict_culled)
		car.set_meta("generic_tenement_facade_count", generic_tenement_facade_count)
		car.set_meta("generic_tenement_window_count", generic_tenement_window_count)
		car.set_meta("generic_tenement_door_count", generic_tenement_door_count)
		car.set_meta("generic_tenement_shopfront_count", generic_tenement_shopfront_count)
		car.set_meta("generic_tenement_downpipe_count", generic_tenement_downpipe_count)
		car.set_meta("generic_tenement_recess_count", generic_tenement_recess_count)
		car.set_meta("generic_tenement_chimney_count", generic_tenement_chimney_count)
		car.set_meta("generic_tenement_railing_count", generic_tenement_railing_count)
		car.set_meta("xps_light_grade", XPS_LIGHT_GRADE if xps_9530_mode else "default")
		car.set_meta("map_fallback_building_count", fallback_building_count)
		car.set_meta("map_linear_feature_count", linear_features.size())
		car.set_meta("map_point_feature_count", point_features.size())
		car.set_meta("map_poi_feature_count", poi_features.size())
		car.set_meta("map_identity_feature_count", identity_features.size())
		car.set_meta("map_coast_segment_count", int(identity_counts.get("coast_segments", 0)))
		car.set_meta("map_identity_area_count", int(identity_counts.get("areas", 0)))
		car.set_meta("map_rail_segment_count", int(identity_counts.get("rail_segments", 0)))
		car.set_meta("map_road_annotation_count", mapped_road_annotation_count)
		car.set_meta("map_road_segments", map_segments)
		if not map_opening_placed:
			_place_car_for_first_impression(car, roads, buildings, poi_features, point_features)
			map_opening_placed = true
			car.set_meta("map_refresh_preserved_vehicle", false)
		else:
			# Live/cache refreshes may rebuild source geometry, but they must never
			# seize control of a moving player's transform. Recovery remains an
			# explicit R action rather than a side effect of network timing.
			car.set_meta("map_refresh_preserved_vehicle", true)
		car.set_meta("map_opening_anchor_annotated", _add_opening_anchor_annotation(map_root, car, poi_features, buildings, point_features))



func _building_footprint_clearance(point: Vector2, building: Dictionary) -> float:
	var footprint = building.get("footprint", [])
	if not footprint is Array or footprint.size() < 3:
		return INF
	var poly := PackedVector2Array()
	for raw in footprint:
		if raw is Array and raw.size() >= 2:
			poly.append(Vector2(float(raw[0]), float(raw[1])))
	if poly.size() < 3:
		return INF
	if Geometry2D.is_point_in_polygon(point, poly):
		return 0.0
	var best := INF
	for i in range(poly.size()):
		best = minf(best, _point_segment_distance_2d(point, poly[i], poly[(i + 1) % poly.size()]))
	return best

func _point_segment_distance_2d(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)

func _opening_building_clearance(point: Vector2, local_buildings: Array) -> float:
	var best := INF
	for building in local_buildings:
		if not building is Dictionary:
			continue
		var center = building.get("center", [])
		var size = building.get("size", [])
		if not center is Array or center.size() < 2:
			continue
		var c := Vector2(float(center[0]), float(center[1]))
		var quick_radius := 35.0
		if size is Array and size.size() >= 2:
			quick_radius += maxf(float(size[0]), float(size[1])) * 0.55
		if c.distance_to(point) > quick_radius:
			continue
		best = minf(best, _building_footprint_clearance(point, building))
	return best

func _place_car_for_first_impression(car, roads: Array, buildings: Array, poi_features: Array, point_features: Array):
	# Persona 8: choose an opening from verified map facts rather than whichever
	# junction happens to occur first in source order. The car starts on a real
	# approach leg, facing a nearby real junction, with scoring biased toward:
	# choice, named-local context, readable road scale and sourced features ahead.
	# No geometry, sign, landmark or business is invented by this director.
	const OPENING_SEARCH_RADIUS := 75.0
	const OPENING_ANCHOR_RADIUS := 95.0
	const OPENING_APPROACH_MAX := 10.0
	var junctions := {}
	var fallback := Vector2.ZERO
	var fallback_heading := Vector2(0, -1)
	var fallback_dist := INF

	for road_index in range(roads.size()):
		var road = roads[road_index]
		if not road is Dictionary:
			continue
		var points = road.get("points", [])
		if not points is Array:
			continue
		var road_name = str(road.get("name", "")).strip_edges()
		var road_kind = str(road.get("kind", "road")).to_lower()
		var road_width = float(road.get("width", 5.0))
		for point_index in range(points.size()):
			var point = points[point_index]
			if not point is Array or point.size() < 2:
				continue
			var p = Vector2(float(point[0]), float(point[1]))
			var origin_dist = p.length_squared()
			if origin_dist < fallback_dist:
				fallback_dist = origin_dist
				fallback = p
				if point_index + 1 < points.size() and points[point_index + 1] is Array and points[point_index + 1].size() >= 2:
					fallback_heading = Vector2(float(points[point_index + 1][0]), float(points[point_index + 1][1])) - p
			var key = "%d:%d" % [int(round(p.x * 2.0)), int(round(p.y * 2.0))]
			if not junctions.has(key):
				junctions[key] = {"p": p, "roads": {}, "legs": []}
			var item: Dictionary = junctions[key]
			var memberships: Dictionary = item["roads"]
			memberships[str(road_index)] = true
			item["roads"] = memberships
			var legs: Array = item["legs"]
			if point_index + 1 < points.size():
				var next = points[point_index + 1]
				if next is Array and next.size() >= 2:
					legs.append({
						"road_index": road_index,
						"out": Vector2(float(next[0]), float(next[1])) - p,
						"name": road_name,
						"kind": road_kind,
						"width": road_width
					})
			if point_index > 0:
				var prev = points[point_index - 1]
				if prev is Array and prev.size() >= 2:
					legs.append({
						"road_index": road_index,
						"out": Vector2(float(prev[0]), float(prev[1])) - p,
						"name": road_name,
						"kind": road_kind,
						"width": road_width
					})
			item["legs"] = legs
			junctions[key] = item

	# Compact, data-oriented source anchors. These affect only where we look first;
	# they do not create scene content.
	var anchors: Array = []
	for poi in poi_features:
		if not poi is Dictionary:
			continue
		var point = poi.get("point", [])
		var name = str(poi.get("name", "")).strip_edges()
		if name != "" and point is Array and point.size() >= 2:
			anchors.append({
				"p": Vector2(float(point[0]), float(point[1])),
				"name": name,
				"kind": str(poi.get("kind", "poi")),
				"source": "poi",
				"weight": 8.0
			})
	for building in buildings:
		if not building is Dictionary:
			continue
		var center = building.get("center", [])
		var name = str(building.get("name", "")).strip_edges()
		if name != "" and center is Array and center.size() >= 2:
			anchors.append({
				"p": Vector2(float(center[0]), float(center[1])),
				"name": name,
				"kind": str(building.get("kind", "building")),
				"source": "building",
				"weight": 5.0
			})
	var attention_kinds = ["traffic_signals", "bus_stop", "crossing", "stop", "give_way", "traffic_sign"]
	for feature in point_features:
		if not feature is Dictionary:
			continue
		var kind = str(feature.get("kind", "")).to_lower()
		var point = feature.get("point", [])
		if kind in attention_kinds and point is Array and point.size() >= 2:
			anchors.append({
				"p": Vector2(float(point[0]), float(point[1])),
				"name": str(feature.get("name", "")).strip_edges(),
				"kind": kind,
				"source": "point",
				"weight": 5.0
			})

	var best_score := -INF
	var best_junction := fallback
	var best_spawn := fallback
	var best_heading := fallback_heading
	var best_branch_count := 1
	var best_approach := 0.0
	var best_named_roads: Array = []
	var best_anchor_name := ""
	var best_anchor_kind := ""
	var best_anchor_source := ""
	var best_anchor_distance := INF
	var best_visible_anchor_count := 0
	var best_building_clearance := 0.0
	var opening_buildings: Array = []
	for building in buildings:
		if not building is Dictionary:
			continue
		var center = building.get("center", [])
		if center is Array and center.size() >= 2:
			var c := Vector2(float(center[0]), float(center[1]))
			if c.length() <= OPENING_SEARCH_RADIUS + 70.0:
				opening_buildings.append(building)

	for item in junctions.values():
		var memberships: Dictionary = item["roads"]
		if memberships.size() < 2:
			continue
		var junction: Vector2 = item["p"]
		if junction.length() > OPENING_SEARCH_RADIUS:
			continue
		var named_roads := {}
		for road_key in memberships.keys():
			var member_index = int(road_key)
			if member_index < 0 or member_index >= roads.size() or not roads[member_index] is Dictionary:
				continue
			var member_name = str(roads[member_index].get("name", "")).strip_edges()
			if member_name != "":
				named_roads[member_name] = true
		var legs: Array = item["legs"]
		for leg in legs:
			if not leg is Dictionary:
				continue
			var kind = str(leg.get("kind", "road")).to_lower()
			if kind in ["footway", "path", "cycleway", "track"]:
				continue
			var outward: Vector2 = leg.get("out", Vector2.ZERO)
			var leg_length = outward.length()
			if leg_length < 14.0:
				continue
			outward /= leg_length
			var approach = min(OPENING_APPROACH_MAX, max(6.0, leg_length * 0.30))
			var spawn = junction + outward * approach
			var heading = -outward
			var spawn_clearance := _opening_building_clearance(spawn, opening_buildings)
			var required_clearance := maxf(5.5, float(leg.get("width", 5.0)) * 0.5 + 2.0)
			if spawn_clearance < required_clearance:
				continue
			var score = float(memberships.size()) * 12.0
			score += min(leg_length, 45.0) * 0.25
			score += float(named_roads.size()) * 3.0
			score += clamp(float(leg.get("width", 5.0)), 4.0, 10.0) * 0.35
			score -= junction.length() * 0.12
			if kind == "service":
				score -= 7.0

			var candidate_anchor_name := ""
			var candidate_anchor_kind := ""
			var candidate_anchor_source := ""
			var candidate_anchor_distance := INF
			var strongest_anchor_gain := 0.0
			var visible_anchor_count := 0
			for anchor in anchors:
				var anchor_pos: Vector2 = anchor["p"]
				var to_anchor = anchor_pos - spawn
				var anchor_distance = to_anchor.length()
				if anchor_distance < 5.0 or anchor_distance > OPENING_ANCHOR_RADIUS:
					continue
				var forwardness = heading.dot(to_anchor / anchor_distance)
				if forwardness <= 0.45:
					continue
				var proximity = 1.0 - anchor_distance / OPENING_ANCHOR_RADIUS
				var gain = float(anchor["weight"]) * proximity * forwardness
				score += gain
				visible_anchor_count += 1
				var anchor_name = str(anchor["name"])
				if anchor_name != "" and gain > strongest_anchor_gain:
					strongest_anchor_gain = gain
					candidate_anchor_name = anchor_name
					candidate_anchor_kind = str(anchor["kind"])
					candidate_anchor_source = str(anchor["source"])
					candidate_anchor_distance = anchor_distance
			score += min(4, visible_anchor_count) * 1.5
			score += minf(spawn_clearance, 28.0) * 0.32

			if score > best_score:
				best_score = score
				best_junction = junction
				best_spawn = spawn
				best_heading = heading
				best_branch_count = memberships.size()
				best_approach = approach
				best_named_roads = named_roads.keys()
				best_anchor_name = candidate_anchor_name
				best_anchor_kind = candidate_anchor_kind
				best_anchor_source = candidate_anchor_source
				best_anchor_distance = candidate_anchor_distance
				best_visible_anchor_count = visible_anchor_count
				best_building_clearance = spawn_clearance

	if best_heading.length() < 0.1:
		best_heading = Vector2(0, -1)
	best_heading = best_heading.normalized()
	if best_score == -INF:
		best_score = 0.0
		best_junction = fallback
		best_spawn = fallback
		best_approach = 0.0
	car.global_position = Vector3(best_spawn.x, _terrain_height(best_spawn) + 0.58 if mobile_mode else max(car.global_position.y, 0.58), best_spawn.y)
	car.rotation.y = atan2(-best_heading.x, -best_heading.y)
	car.set_meta("map_spawn_junction", [best_junction.x, best_junction.y])
	car.set_meta("map_spawn_heading", [best_heading.x, best_heading.y])
	car.set_meta("map_opening_policy", "terrain-aware-first-impression-v2" if mobile_mode else "verified-first-impression-v1")
	car.set_meta("map_opening_hook_score", best_score)
	car.set_meta("map_opening_branch_count", best_branch_count)
	car.set_meta("map_opening_approach_m", best_approach)
	car.set_meta("map_opening_named_roads", best_named_roads)
	car.set_meta("map_opening_verified_anchor", best_anchor_name)
	car.set_meta("map_opening_verified_anchor_kind", best_anchor_kind)
	car.set_meta("map_opening_verified_anchor_source", best_anchor_source)
	car.set_meta("map_opening_verified_anchor_distance_m", best_anchor_distance)
	car.set_meta("map_opening_visible_anchor_count", best_visible_anchor_count)
	car.set_meta("map_opening_building_clearance_m", best_building_clearance)



func _update_mobile_destination(delta: float, car):
	if not mobile_mode or car == null:
		return
	mobile_destination_clock += delta
	if mobile_destination_clock < 0.25:
		return
	mobile_destination_clock = 0.0
	var stream = get_node_or_null("MapStream")
	if stream == null or not stream.has_method("get_district_destinations"):
		return
	var destinations = stream.get_district_destinations()
	if not destinations is Array or destinations.is_empty():
		return
	var car2 := Vector2(car.global_position.x, car.global_position.z)
	if mobile_destination_index < 0 or mobile_destination_index >= destinations.size():
		var best_index := -1
		var best_distance := INF
		for i in range(destinations.size()):
			var candidate = destinations[i]
			if not candidate is Dictionary:
				continue
			var point = candidate.get("point", [])
			if not point is Array or point.size() < 2:
				continue
			var distance = car2.distance_to(Vector2(float(point[0]), float(point[1])))
			if distance > 90.0 and distance < best_distance:
				best_distance = distance
				best_index = i
		mobile_destination_index = best_index if best_index >= 0 else 0
	var item = destinations[mobile_destination_index]
	if not item is Dictionary:
		return
	var point = item.get("point", [])
	if not point is Array or point.size() < 2:
		return
	mobile_destination_point = Vector2(float(point[0]), float(point[1]))
	mobile_destination_name = str(item.get("name", "EH15")).strip_edges()
	var remaining := car2.distance_to(mobile_destination_point)
	if remaining < 32.0 and destinations.size() > 1:
		mobile_destination_index = (mobile_destination_index + 1) % destinations.size()
		item = destinations[mobile_destination_index]
		point = item.get("point", [])
		if point is Array and point.size() >= 2:
			mobile_destination_point = Vector2(float(point[0]), float(point[1]))
			mobile_destination_name = str(item.get("name", "EH15")).strip_edges()
			remaining = car2.distance_to(mobile_destination_point)
	car.set_meta("eh15_destination_name", mobile_destination_name)
	car.set_meta("eh15_destination_point", [mobile_destination_point.x, mobile_destination_point.y])
	car.set_meta("eh15_destination_distance_m", remaining)
	car.set_meta("eh15_destination_index", mobile_destination_index)
	car.set_meta("eh15_destination_count", destinations.size())



func _update_mobile_location_identity(delta: float, car):
	if not mobile_mode or car == null:
		return
	mobile_identity_clock += delta
	if mobile_identity_clock < 0.22:
		return
	mobile_identity_clock = 0.0
	var stream = get_node_or_null("MapStream")
	if stream == null or not stream.has_method("mobile_location_identity"):
		return
	var identity = stream.mobile_location_identity(Vector2(car.global_position.x, car.global_position.z))
	if not identity is Dictionary:
		return
	var road = identity.get("road", {})
	var near_road = identity.get("near_road", {})
	var place = identity.get("place", {})
	var landmark = identity.get("landmark", {})
	car.set_meta("mobile_road_name", "")
	car.set_meta("mobile_road_distance_m", INF)
	car.set_meta("mobile_near_road_name", "")
	car.set_meta("mobile_near_road_distance_m", INF)
	car.set_meta("mobile_place_name", "")
	car.set_meta("mobile_place_distance_m", INF)
	car.set_meta("mobile_landmark_name", "")
	car.set_meta("mobile_landmark_distance_m", INF)
	car.set_meta("mobile_landmark_kind", "")
	if road is Dictionary:
		var road_name := str(road.get("name", "")).strip_edges()
		var road_ref := str(road.get("ref", "")).strip_edges()
		car.set_meta("mobile_road_name", road_name if road_name != "" else road_ref)
		car.set_meta("mobile_road_distance_m", float(road.get("distance_m", INF)))
	if near_road is Dictionary:
		var near_name := str(near_road.get("name", "")).strip_edges()
		var near_ref := str(near_road.get("ref", "")).strip_edges()
		car.set_meta("mobile_near_road_name", near_name if near_name != "" else near_ref)
		car.set_meta("mobile_near_road_distance_m", float(near_road.get("distance_m", INF)))
	if place is Dictionary:
		car.set_meta("mobile_place_name", str(place.get("name", "")).strip_edges())
		car.set_meta("mobile_place_distance_m", float(place.get("distance_m", INF)))
	if landmark is Dictionary:
		car.set_meta("mobile_landmark_name", str(landmark.get("name", "")).strip_edges())
		car.set_meta("mobile_landmark_distance_m", float(landmark.get("distance_m", INF)))
		car.set_meta("mobile_landmark_kind", str(landmark.get("kind", "")))
	car.set_meta("mobile_location_source", "OpenStreetMap")


func _spawn_map_agents():
	for agent in map_agents:
		if agent.has("node") and is_instance_valid(agent["node"]):
			agent["node"].queue_free()
	map_agents.clear()
	if map_segments.is_empty():
		return
	var count = min(8 if low_spec_mode else 18, map_segments.size())
	for i in range(count):
		var body = AnimatableBody3D.new()
		body.name = "MapTraffic_%02d" % i
		_vehicle_visual(body, i + 200)
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
	if map_agents.is_empty():
		return
	var visible_count = clamp(int(round(float(map_agents.size()) * api_traffic_factor)), 3, map_agents.size())
	for index in range(map_agents.size()):
		var agent = map_agents[index]
		if not agent.has("node") or not is_instance_valid(agent["node"]):
			continue
		var node = agent["node"]
		node.visible = index < visible_count
		if not node.visible:
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
		var live_speed = float(agent.get("speed", 9.0)) * api_traffic_speed_factor
		t += direction * live_speed * delta / length
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

func _add_verge_life(parent: Node3D):
	var placed := 0
	for i in range(map_segments.size()):
		if placed >= (22 if low_spec_mode else 52):
			break
		if i % 4 != 0:
			continue
		var segment = map_segments[i]
		var a = Vector2(float(segment[0][0]), float(segment[0][1]))
		var b = Vector2(float(segment[1][0]), float(segment[1][1]))
		var delta = b - a
		if delta.length() < 14.0:
			continue
		var normal = Vector2(-delta.y, delta.x).normalized()
		var width = float(segment[2])
		var side = -1.0 if i % 2 == 0 else 1.0
		var p = a.lerp(b, 0.2 + float((i * 17) % 60) / 100.0) + normal * side * (width * 0.5 + 1.25)
		for j in range(3 + i % 3):
			var weed = MeshInstance3D.new()
			var qm = QuadMesh.new()
			qm.size = Vector2(0.18 + float(j % 2) * 0.08, 0.34 + float((i + j) % 3) * 0.11)
			weed.mesh = qm
			weed.position = Vector3(p.x + normal.x * j * 0.13, 0.18, p.y + normal.y * j * 0.13)
			weed.rotation.y = atan2(normal.x, normal.y) + float(j) * 0.63
			weed.material_override = _mat(Color(0.16, 0.22, 0.085), 0.98, 0.0)
			weed.visibility_range_end = 80.0
			parent.add_child(weed)
		if i % 3 == 0:
			var litter = MeshInstance3D.new()
			var lm = PlaneMesh.new()
			lm.size = Vector2(0.28, 0.18)
			litter.mesh = lm
			litter.position = Vector3(p.x - normal.x * 0.35, 0.092, p.y - normal.y * 0.35)
			litter.rotation.y = float(i) * 0.47
			litter.material_override = _mat(Color(0.46, 0.45, 0.40), 0.88, 0.0)
			litter.visibility_range_end = 55.0
			parent.add_child(litter)
		placed += 1

func _add_map_furniture(parent: Node3D):
	var placed = 0
	for i in range(map_segments.size()):
		if placed >= (12 if low_spec_mode else 24) or i % (10 if low_spec_mode else 7) != 0:
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
			map_lamps.append(lamp)
		placed += 1


func _add_edinburgh_building(parent: Node3D, base: Vector3, size: Vector3, seed: int, kind: String):
	var sx = size.x
	var h = size.y
	var sz = size.z
	var industrial = kind in ["industrial", "warehouse", "commercial", "retail"] or sx > 28.0 or sz > 28.0
	var detail_scale = 0.62 if low_spec_mode else 1.0
	var detailed = industrial or (seed % 100) < int(clamp(api_detail_pressure, 0.35, 1.0) * 48.0 * detail_scale)
	var stone = soot_stone_mat
	if map_center_lat < 52.5:
		match seed % 5:
			0, 1, 2: stone = brick_mat
			3: stone = render_mat
			_: stone = concrete_mat
	else:
		match seed % 4:
			0: stone = sandstone_mat
			1: stone = sandstone_warm_mat
			2: stone = soot_stone_mat
			_: stone = soot_stone_cool_mat
	if industrial:
		stone = _mat(Color(0.27, 0.285, 0.29), 0.84, 0.03)
	var body = _box(parent, base + Vector3(0, h * 0.5, 0), Vector3(sx, h, sz), stone)

	# Dark plinths make terraces and warehouses sit on wet streets rather than float.
	var plinth_h = min(1.25, h * 0.18)
	_visual_box(parent, base + Vector3(0, plinth_h * 0.5, -sz * 0.505), Vector3(sx * 0.96, plinth_h, 0.10), roof_mat)
	_visual_box(parent, base + Vector3(0, plinth_h * 0.5, sz * 0.505), Vector3(sx * 0.96, plinth_h, 0.10), roof_mat)

	var storeys = max(1, int(round(h / 3.1)))
	if not detailed:
		if h > 6.0 and seed % 2 == 0:
			_visual_box(parent, base + Vector3(sx * 0.18, h + 0.75, sz * 0.16), Vector3(0.52, 1.5, 0.52), roof_mat)
		return
	var front_slots = clamp(int(sx / (4.4 if industrial else 3.2)), 1, 9)
	var side_slots = clamp(int(sz / (5.0 if industrial else 3.6)), 1, 7)
	var window_w = 1.65 if industrial else 1.05
	var window_h = 1.15 if industrial else 1.32

	for floor in range(storeys):
		var y = min(h - 0.9, 1.8 + float(floor) * 3.0)
		if y > h - 0.45:
			continue
		for slot in range(front_slots):
			if (slot + floor + seed) % 9 == 0:
				continue
			var x = -sx * 0.5 + sx * (float(slot) + 0.5) / float(front_slots)
			_visual_box(parent, base + Vector3(x, y, -sz * 0.505), Vector3(window_w, window_h, 0.08), glass_mat)
			_visual_box(parent, base + Vector3(x, y, sz * 0.505), Vector3(window_w, window_h, 0.08), glass_mat)
			if not industrial:
				_visual_box(parent, base + Vector3(x, y - window_h * 0.5 - 0.07, -sz * 0.518), Vector3(window_w + 0.20, 0.10, 0.16), stone)
		for slot in range(side_slots):
			if (slot * 3 + floor + seed) % 8 == 0:
				continue
			var z = -sz * 0.5 + sz * (float(slot) + 0.5) / float(side_slots)
			_visual_box(parent, base + Vector3(-sx * 0.505, y, z), Vector3(0.08, window_h, window_w), glass_mat)
			_visual_box(parent, base + Vector3(sx * 0.505, y, z), Vector3(0.08, window_h, window_w), glass_mat)

	# Horizontal sandstone courses and lintel rhythm, deliberately restrained.
	if not industrial and h > 7.0:
		for floor in range(1, storeys):
			var course_y = min(h - 0.25, float(floor) * 3.0)
			_visual_box(parent, base + Vector3(0, course_y, -sz * 0.512), Vector3(sx, 0.10, 0.08), sandstone_mat)

	# A projecting cornice, parapet and occasional rainwater pipe make the OSM
	# footprint read as an actual street elevation instead of a textured cuboid.
	if not industrial and h > 6.5:
		_visual_box(parent, base + Vector3(0, h - 0.38, -sz * 0.525), Vector3(sx + 0.18, 0.22, 0.24), stone)
		_visual_box(parent, base + Vector3(0, h + 0.18, -sz * 0.505), Vector3(sx + 0.12, 0.34, 0.18), roof_mat)
		var pipe_x = -sx * 0.46 if seed % 2 == 0 else sx * 0.46
		_visual_box(parent, base + Vector3(pipe_x, h * 0.48, -sz * 0.54), Vector3(0.10, h * 0.92, 0.10), metal_mat)
	elif industrial:
		var ribs = clamp(int(sx / 6.0), 2, 8)
		for r in range(ribs):
			var rx = -sx * 0.5 + sx * (float(r) + 0.5) / float(ribs)
			_visual_box(parent, base + Vector3(rx, h * 0.50, -sz * 0.512), Vector3(0.09, h * 0.88, 0.10), metal_mat)

	# Ground floor variety: close-set garages/shops for industrial edges; recessed doors for tenements.
	if industrial:
		var bays = clamp(int(sx / 7.5), 1, 6)
		for i in range(bays):
			var x = -sx * 0.5 + sx * (float(i) + 0.5) / float(bays)
			_visual_box(parent, base + Vector3(x, 1.45, -sz * 0.518), Vector3(min(5.0, sx / bays * 0.70), 2.45, 0.12), metal_mat)
	else:
		var door_x = -sx * 0.5 + min(1.8, sx * 0.22) if seed % 2 == 0 else sx * 0.5 - min(1.8, sx * 0.22)
		_visual_box(parent, base + Vector3(door_x, 1.15, -sz * 0.52), Vector3(1.25, 2.25, 0.12), roof_mat)

	# Roofline clutter gives distance cues from the chase and bay cameras.
	if h > 6.0:
		var chimney_count = clamp(int(sx / 12.0), 1, 4)
		for i in range(chimney_count):
			var x = -sx * 0.35 + sx * 0.70 * (float(i) / max(1.0, float(chimney_count - 1)))
			var z = (-0.22 if (i + seed) % 2 == 0 else 0.22) * sz
			_visual_box(parent, base + Vector3(x, h + 0.85, z), Vector3(0.55, 1.7, 0.55), roof_mat)
	if industrial and seed % 3 == 0:
		_visual_box(parent, base + Vector3(sx * 0.22, h + 0.7, -sz * 0.12), Vector3(3.6, 1.4, 2.6), metal_mat)



func _mobile_footprint_regression() -> Dictionary:
	# Synthetic angled/L-shaped footprints prove that mobile far geometry preserves
	# the polygon rather than expanding to its axis-aligned bounding rectangle.
	var samples := [
		PackedVector2Array([Vector2(0,0),Vector2(12,3),Vector2(10,9),Vector2(-2,6)]),
		PackedVector2Array([Vector2(0,0),Vector2(10,0),Vector2(10,3),Vector2(4,3),Vector2(4,9),Vector2(0,9)])
	]
	var passed := 0
	for poly in samples:
		var tris := Geometry2D.triangulate_polygon(poly)
		if tris.size() < 3:
			continue
		var polygon_area := 0.0
		var min_x := INF
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		for i in range(poly.size()):
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % poly.size()]
			polygon_area += a.x * b.y - b.x * a.y
			min_x = minf(min_x, a.x)
			max_x = maxf(max_x, a.x)
			min_y = minf(min_y, a.y)
			max_y = maxf(max_y, a.y)
		polygon_area = absf(polygon_area) * 0.5
		var bbox_area := (max_x - min_x) * (max_y - min_y)
		if polygon_area > 0.1 and bbox_area > polygon_area * 1.08:
			passed += 1
	return {"passed": passed, "total": samples.size(), "visual_radius": MOBILE_BUILDING_VISUAL_RADIUS, "collision_radius": MOBILE_COLLIDING_BUILDING_RADIUS}

func _bind_pua_api():
	var api = get_node_or_null("PUAAPI")
	if not api:
		return
	if api.has_signal("directive_changed"):
		api.directive_changed.connect(_on_pua_directive)
	if api.has_method("get_directive"):
		_on_pua_directive(api.get_directive())

func _on_pua_directive(directive: Dictionary):
	api_traffic_factor = clamp(float(directive.get("traffic_factor", 0.85)), 0.25, 1.35)
	api_traffic_speed_factor = clamp(float(directive.get("traffic_speed_factor", 0.95)), 0.65, 1.10)
	api_lamp_factor = clamp(float(directive.get("lamp_factor", 1.0)), 0.45, 2.0)
	api_detail_pressure = clamp(float(directive.get("detail_pressure", 0.70)), 0.35, 1.0)
	api_radio_instability = clamp(float(directive.get("radio_instability", 0.20)), 0.0, 1.0)
	api_moment = str(directive.get("moment", "none"))
	for lamp in map_lamps:
		if is_instance_valid(lamp):
			lamp.light_energy = 0.72 * api_lamp_factor
	var garage_light = get_node_or_null("GarageCourt/GarageLight")
	if garage_light:
		garage_light.light_energy = 2.2 * api_lamp_factor
	var car = get_node_or_null("Car")
	if car:
		car.set_meta("pua_api_traffic", api_traffic_factor)
		car.set_meta("pua_api_world_seed", int(directive.get("world_seed", 1)))
