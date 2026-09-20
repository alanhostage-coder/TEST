extends Node3D
# 0.26 district slice: persistent geometry and roads in world space.
var cells := {}
const CELL := 90.0

func _ready():
	_make_ground()
	_make_landmarks()
	for x in range(-1,2):
		for y in range(-2,1):
			_build_cell(Vector2i(x,y))

func _process(_delta):
	var car=$Car
	var c=Vector2i(floor(car.global_position.x/CELL),floor(car.global_position.z/CELL))
	for x in range(c.x-1,c.x+2):
		for y in range(c.y-1,c.y+2):
			_build_cell(Vector2i(x,y))

func _box(parent:Node3D, pos:Vector3, size:Vector3):
	var body=StaticBody3D.new()
	var mesh=MeshInstance3D.new(); var bm=BoxMesh.new(); bm.size=size; mesh.mesh=bm
	var col=CollisionShape3D.new(); var shape=BoxShape3D.new(); shape.size=size; col.shape=shape
	body.position=pos; body.add_child(mesh); body.add_child(col); parent.add_child(body)

func _road(parent:Node3D, pos:Vector3, size:Vector3):
	var mesh=MeshInstance3D.new(); var bm=BoxMesh.new(); bm.size=size; mesh.mesh=bm
	mesh.position=pos; parent.add_child(mesh)

func _build_cell(c:Vector2i):
	if cells.has(c): return
	cells[c]=true
	var root=Node3D.new(); root.name="cell_%s_%s"%[c.x,c.y]; add_child(root)
	root.position=Vector3(c.x*CELL,0,c.y*CELL)
	var seed=abs(c.x*92821+c.y*68917)
	# Cross-road topology means every streamed cell can be entered from four directions.
	_road(root,Vector3(0,0.02,0),Vector3(15,0.08,CELL))
	_road(root,Vector3(0,0.025,0),Vector3(CELL,0.08,15))
	# Estate / industrial masses leave navigable yards and sight-lines.
	for i in range(8):
		var side=-1.0 if i%2==0 else 1.0
		var along=-34.0+float((seed+i*19)%68)
		var w=10.0+float((seed+i*7)%12)
		var d=8.0+float((seed+i*11)%13)
		var h=4.0+float((seed+i*3)%6)
		var x=side*(24.0+float((seed+i*5)%10))
		_box(root,Vector3(x,h/2.0,along),Vector3(w,h,d))
	# A low garage block and transmitter are curiosity anchors, never objectives.
	if seed%3==0:
		_box(root,Vector3(27,1.6,-25),Vector3(20,3.2,9))
	if seed%4==0:
		_box(root,Vector3(-31,10,29),Vector3(0.8,20,0.8))

func _make_ground():
	var ground=StaticBody3D.new(); ground.name="Ground"
	var mesh=MeshInstance3D.new(); var plane=BoxMesh.new(); plane.size=Vector3(1200,0.4,1200); mesh.mesh=plane
	var col=CollisionShape3D.new(); var shape=BoxShape3D.new(); shape.size=Vector3(1200,0.4,1200); col.shape=shape
	ground.position=Vector3(0,-0.24,0); ground.add_child(mesh); ground.add_child(col); add_child(ground)

func _make_landmarks():
	# One memorable industrial edge, visible from several approaches.
	var dock=Node3D.new(); dock.name="DockEdge"; dock.position=Vector3(135,0,-165); add_child(dock)
	_box(dock,Vector3(0,4,0),Vector3(44,8,18))
	_box(dock,Vector3(17,13,-2),Vector3(3,26,3))
	_box(dock,Vector3(-14,2.5,18),Vector3(24,5,12))
	# Garage court: enough room to enter, turn around and leave.
	var court=Node3D.new(); court.name="GarageCourt"; court.position=Vector3(-115,0,-80); add_child(court)
	for x in [-22.0,-11.0,0.0,11.0,22.0]:
		_box(court,Vector3(x,2.0,-18),Vector3(9,4,7))
	# Tall transmitter gives orientation without a map marker.
	var mast=Node3D.new(); mast.name="Transmitter"; mast.position=Vector3(185,0,110); add_child(mast)
	_box(mast,Vector3(0,24,0),Vector3(1.2,48,1.2))
	_box(mast,Vector3(0,45,0),Vector3(9,0.5,0.5))
