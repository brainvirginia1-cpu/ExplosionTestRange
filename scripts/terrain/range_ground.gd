extends StaticBody3D

const HALF_EXTENT := 100000.0
const PLAYABLE_HALF_EXTENT := HALF_EXTENT
const MAX_ALTITUDE := 100000.0
const CURVATURE_RADIUS := 6371000.0
const TILE := 128.0
const TILE_HALF := TILE*0.5
const LAST_TILE := 781
const CAPACITY := 16
const RADIUS_LIMIT := 160.0
const TERRAIN_SHADER := preload("res://assets/shaders/soil.gdshader")

class Tile:
	var visual: MeshInstance3D
	var collision: CollisionShape3D

var craters: Array[Vector4] = []
var _tiles: Dictionary[Vector2i, Tile] = {}
var _anchors: Dictionary[Vector2i, bool] = {}
var _focus_tile := Vector2i(10000,10000)
var _dirty: Dictionary = {}
var _surface := ShaderMaterial.new()
var _heave := Vector4.ZERO
var _heave_tiles: Dictionary[Vector2i, bool] = {}

func _ready() -> void:
	_surface.shader = TERRAIN_SHADER
	stream_near(Vector3.ZERO)
	clear_wave()

static func base_height(x: float, z: float) -> float:
	var squared := x*x+z*z
	return -squared/(CURVATURE_RADIUS+sqrt(maxf(0.0,CURVATURE_RADIUS*CURVATURE_RADIUS-squared)))

func ray_to_surface(origin: Vector3, direction: Vector3) -> Vector3:
	var linear := origin.dot(direction)+CURVATURE_RADIUS*direction.y
	var constant := origin.x*origin.x+origin.y*origin.y+origin.z*origin.z+2.0*CURVATURE_RADIUS*origin.y
	var discriminant := linear*linear-constant
	if linear >= 0.0 or discriminant < 0.0:
		return Vector3.INF
	var distance := constant/(-linear+sqrt(discriminant))
	if distance <= 0.0:
		return Vector3.INF
	var point := origin+direction*distance
	if maxf(absf(point.x),absf(point.z)) > HALF_EXTENT:
		return Vector3.INF
	point.y = height_at(point.x,point.z)
	return point

static func _tile_key(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(floori(x/TILE),-LAST_TILE-1,LAST_TILE),clampi(floori(z/TILE),-LAST_TILE-1,LAST_TILE))

func _include_region(out: Dictionary[Vector2i, bool], x: float, z: float, radius: float) -> void:
	var low := _tile_key(x-radius,z-radius)
	var high := _tile_key(x+radius,z+radius)
	for row in range(low.y,high.y+1):
		for column in range(low.x,high.x+1):
			out[Vector2i(column,row)] = true

func keep_sites(points: PackedVector3Array) -> void:
	_anchors.clear()
	for point in points:
		_include_region(_anchors,point.x,point.z,TILE)
	_refresh_stream()

func stream_near(point: Vector3) -> void:
	var key := _tile_key(point.x,point.z)
	if key == _focus_tile:
		return
	_focus_tile = key
	_refresh_stream()

func _refresh_stream() -> void:
	var wanted := _anchors.duplicate()
	wanted.merge(_dirty)
	wanted.merge(_heave_tiles)
	var center := (Vector2(_focus_tile)+Vector2(0.5,0.5))*TILE
	_include_region(wanted,center.x,center.y,TILE*2.0)
	for key in _tiles.keys():
		if wanted.has(key):
			continue
		var tile := _tiles[key]
		remove_child(tile.visual)
		remove_child(tile.collision)
		tile.visual.queue_free()
		tile.collision.queue_free()
		_tiles.erase(key)
	for key in wanted:
		if not _tiles.has(key):
			_create_tile(key)

func _create_tile(key: Vector2i) -> void:
	var tile := Tile.new()
	var center := Vector2(key)*TILE+Vector2(TILE_HALF,TILE_HALF)
	tile.visual = MeshInstance3D.new()
	tile.visual.material_override = _surface
	tile.visual.position = Vector3(center.x,base_height(center.x,center.y),center.y)
	tile.visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tile.collision = CollisionShape3D.new()
	add_child(tile.visual)
	add_child(tile.collision)
	_tiles[key] = tile
	_rebuild_tile(key,_dirty.has(key) or _heave_tiles.has(key))

func add_crater(center: Vector3, radius: float, depth: float) -> void:
	var staged := craters.duplicate()
	if staged.size() >= CAPACITY:
		staged.pop_front()
	staged.append(Vector4(center.x, center.z, clampf(radius, 1.0, RADIUS_LIMIT), clampf(depth, 0.2, 36.0)))
	set_craters(staged)

func set_craters(records: Array[Vector4]) -> void:
	if craters == records:
		return
	craters = records.duplicate()
	var dirty: Dictionary[Vector2i, bool] = {}
	for record in craters:
		_include_region(dirty,record.x,record.y,record.z*1.36)
	var rebuild := _dirty.duplicate()
	rebuild.merge(dirty)
	_dirty = dirty
	for key in rebuild:
		if _tiles.has(key):
			_rebuild_tile(key,dirty.has(key) or _heave_tiles.has(key))
	_refresh_stream()
	var packed := PackedVector4Array(craters)
	packed.resize(CAPACITY)
	_surface.set_shader_parameter("crater_count", craters.size())
	_surface.set_shader_parameter("craters", packed)

func heave_ground(center: Vector3, radius: float, amount: float, cracks: float) -> void:
	_heave = Vector4(center.x,center.z,radius,amount)
	if _heave_tiles.is_empty():
		_include_region(_heave_tiles,center.x,center.z,radius)
	for key in _heave_tiles:
		if _tiles.has(key):
			_rebuild_tile(key,true)
		else:
			_create_tile(key)
	_surface.set_shader_parameter("ground_split",Vector4(center.x,center.z,radius,cracks))

func clear_heave() -> void:
	_heave = Vector4.ZERO
	for key in _heave_tiles:
		if _tiles.has(key):
			_rebuild_tile(key,_dirty.has(key))
	_heave_tiles.clear()
	_surface.set_shader_parameter("ground_split",Vector4.ZERO)

func surface_material() -> ShaderMaterial:
	return _surface

func height_at(x: float, z: float) -> float:
	var height := base_height(x,z)
	for record in craters:
		var delta := Vector2(x - record.x, z - record.y)
		var angle := atan2(delta.y, delta.x)
		var boundary := 1.0 + sin(angle * 5.0) * 0.045 + cos(angle * 7.0) * 0.022
		var fraction := delta.length() / (record.z * boundary)
		if fraction >= 1.26:
			continue
		var floor_height := -record.w * pow(maxf(0.0, 1.0 - fraction * fraction), 1.22)
		var rim := exp(-pow((fraction - 0.94) * 10.0, 2.0)) * record.w * (0.14 + sin(angle * 9.0) * 0.043)
		height += floor_height + rim * (1.0 - smoothstep(1.07, 1.26, fraction))
	if _heave.z > 0.0:
		var offset := Vector2(x-_heave.x,z-_heave.y)
		var ratio := offset.length()/_heave.z
		var angle := offset.angle()
		var dome := 1.0-smoothstep(0.11,1.0,ratio)
		var ridges := sin(angle*7.0+ratio*6.0)*0.11*smoothstep(0.0,0.34,ratio)
		height += _heave.w*dome*(1.0+ridges)
	return height

func show_wave(at: Vector3, radius: float, maximum: float, progress: float, width: float) -> void:
	_surface.set_shader_parameter("shock", Vector4(at.x, at.z, radius, width))
	_surface.set_shader_parameter("shock_limit", maximum)
	_surface.set_shader_parameter("shock_elevation", at.y)
	_surface.set_shader_parameter("shock_progress", progress)

func clear_wave() -> void:
	_surface.set_shader_parameter("shock", Vector4.ZERO)
	_surface.set_shader_parameter("shock_limit", 0.0)

func _rebuild_tile(key: Vector2i, deformed: bool) -> void:
	var tile := _tiles[key]
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := tile.visual.position
	var xs := _axis_samples(center.x,false) if deformed else PackedFloat32Array([-TILE_HALF,0.0,TILE_HALF])
	var zs := _axis_samples(center.z,true) if deformed else PackedFloat32Array([-TILE_HALF,0.0,TILE_HALF])
	for z in zs:
		for x in xs:
			var px := center.x + x
			var pz := center.z + z
			var dx := height_at(px + 0.18, pz) - height_at(px - 0.18, pz)
			var dz := height_at(px, pz + 0.18) - height_at(px, pz - 0.18)
			sm.set_normal(Vector3(-dx, 0.36, -dz).normalized())
			sm.add_vertex(Vector3(x,height_at(px,pz)-center.y,z))
	for j in range(zs.size() - 1):
		for i in range(xs.size() - 1):
			var a := j * xs.size() + i
			var b := a + xs.size()
			sm.add_index(a)
			sm.add_index(a + 1)
			sm.add_index(b)
			sm.add_index(a + 1)
			sm.add_index(b + 1)
			sm.add_index(b)
	var patch := sm.commit()
	tile.visual.mesh = patch
	tile.collision.position = center
	tile.collision.shape = patch.create_trimesh_shape()

func _axis_samples(center: float, use_z: bool) -> PackedFloat32Array:
	var positions := {}
	for u in range(-64, 65, 8):
		positions[float(u)] = true
	var sample_regions := craters.duplicate()
	if _heave.z > 0.0:
		sample_regions.append(_heave)
	for record: Vector4 in sample_regions:
		var offset := (record.y if use_z else record.x) - center
		var spacing := clampf(record.z / 15.0, 0.24, 8.0)
		for i in range(-20, 21):
			var u := snappedf(offset + i * spacing, 0.015625)
			if u > -64.0 and u < 64.0:
				positions[u] = true
	var sorted := positions.keys()
	sorted.sort()
	return PackedFloat32Array(sorted)
