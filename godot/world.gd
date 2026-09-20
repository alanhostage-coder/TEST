extends Node3D
# First greybeard slice: actual persistent 3D places, not screen-space scenery.
var cells := {}
const CELL := 90.0

func _ready():
	_build_cell(Vector2i(0,0))
	_build_cell(Vector2i(0,-1))
	_build_cell(Vector2i(1,-1))

func _process(_delta):
	var car=$Car
	var c=Vector2i(floor(car.global_position.x/CELL),floor(car.global_position.z/CELL))
	for x in range(c.x-1,c.x+2):
		for y in range(c.y-1,c.y+2):
			_build_cell(Vector2i(x,y))

func _build_cell(c:Vector2i):
	if cells.has(c): return
	cells[c]=true
	var root=Node3D.new(); root.name="cell_%s_%s"%[c.x,c.y]; add_child(root)
	root.position=Vector3(c.x*CELL,0,c.y*CELL)
	# Deterministic estate/yard masses make revisits spatially consistent.
	var seed=abs(c.x*92821+c.y*68917)
	for i in range(5):
		var m=MeshInstance3D.new()
		var box=BoxMesh.new(); box.size=Vector3(10+(seed+i*7)%14,5+(seed+i*3)%7,8+(seed+i*11)%16)
		m.mesh=box
		m.position=Vector3(-34+(seed+i*23)%68,box.size.y/2,-34+(seed+i*31)%68)
		root.add_child(m)
