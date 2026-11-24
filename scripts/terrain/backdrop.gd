extends MeshInstance3D

const Ground := preload("res://scripts/terrain/range_ground.gd")

func _ready() -> void:
	var coordinates := PackedFloat64Array()
	for i in range(-50,51):
		coordinates.append(i*2000.0)
	for i in range(1,43):
		var distance := 100000.0+i*i*820.0
		coordinates.append(-distance)
		coordinates.append(distance)
	coordinates.sort()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in coordinates:
		for x in coordinates:
			surface.set_normal(Vector3(x/Ground.CURVATURE_RADIUS,1.0,z/Ground.CURVATURE_RADIUS).normalized())
			surface.add_vertex(Vector3(x,height_at(x,z)-0.55,z))
	var side := coordinates.size()
	for z in side-1:
		for x in side-1:
			var a := z*side+x
			var b := a+side
			for index: int in [a,a+1,b,a+1,b+1,b]:
				surface.add_index(index)
	mesh = surface.commit()

func height_at(x: float, z: float) -> float:
	return Ground.base_height(x,z)
