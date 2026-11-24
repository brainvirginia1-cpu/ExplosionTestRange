extends RefCounted

const Target := preload("res://scripts/destruction/range_target.gd")
const Ground := preload("res://scripts/terrain/range_ground.gd")
const LIMIT := Ground.PLAYABLE_HALF_EXTENT - 5.0
const CAPACITY := 150
const SAVE_PATH := "user://range_layout.json"

class Placement:
	var kind: int
	var location: Vector3
	var yaw: float

	func _init(type: int, point: Vector3, rotation: float = 0.0) -> void:
		kind = type
		location = point
		yaw = rotation

var items: Array[Placement] = []
var craters: Array[Vector4] = []

func snapshot() -> RefCounted:
	var result: RefCounted = get_script().new()
	for item in items:
		result.items.append(Placement.new(item.kind, item.location, item.yaw))
	result.craters.assign(craters)
	return result

func defaults() -> void:
	craters.clear()
	items.assign([
		Placement.new(Target.Kind.WALL, Vector3(-5.1, 0.0, -5.2), 0.10),
		Placement.new(Target.Kind.CONTAINER, Vector3(2.0, 0.0, -15.0), 0.14),
		Placement.new(Target.Kind.SHELTER, Vector3(-14.0, 0.0, -10.0), 0.31),
		Placement.new(Target.Kind.DRUM, Vector3(-2.6, 0.0, -3.5)),
		Placement.new(Target.Kind.DRUM, Vector3(6.0, 0.0, -10.0)),
		Placement.new(Target.Kind.BRICK, Vector3(-14.0, 0.0, -27.0), -0.22),
		Placement.new(Target.Kind.PIPES, Vector3(13.0, 0.0, -21.0), 0.16),
		Placement.new(Target.Kind.CRATES, Vector3(19.0, 0.0, -13.0), -0.11),
		Placement.new(Target.Kind.TOWER, Vector3(29.0, 0.0, -37.0), 0.32),
		Placement.new(Target.Kind.BARRIER, Vector3(-7.0, 0.0, -24.0), -0.08),
		Placement.new(Target.Kind.SIGN, Vector3(-8.3, 0.0, 3.0), 0.279),
		Placement.new(Target.Kind.SIGN, Vector3(-8.3, 0.0, -19.0), 0.279)
	])

func append(kind: int, location: Vector3, yaw: float = 0.0) -> bool:
	if items.size() >= CAPACITY or not can_place(kind, location, yaw):
		return false
	items.append(Placement.new(kind, location, yaw))
	return true

func can_place(kind: int, location: Vector3, yaw: float, ignore: int = -1) -> bool:
	if kind < 0 or kind >= Target.NAMES.size() or location.y < 0.0 or location.y > 12.0:
		return false
	var bounds: Vector3 = Target.DIMENSIONS[kind]
	var half := Vector2(bounds.x, bounds.z) * 0.5
	var x := Vector2(cos(yaw), -sin(yaw))
	var z := x.orthogonal()
	var centre := Vector2(location.x, location.z)
	if absf(centre.x) + absf(x.x) * half.x + absf(z.x) * half.y > LIMIT:
		return false
	if absf(centre.y) + absf(x.y) * half.x + absf(z.y) * half.y > LIMIT:
		return false
	for i in range(items.size()):
		if i == ignore:
			continue
		var existing := items[i]
		var other: Vector3 = Target.DIMENSIONS[existing.kind]
		if location.y >= existing.location.y + other.y or existing.location.y >= location.y + bounds.y:
			continue
		var ex := Vector2(cos(existing.yaw), -sin(existing.yaw))
		var ez := ex.orthogonal()
		var other_half := Vector2(other.x, other.z) * 0.5
		var delta := Vector2(existing.location.x, existing.location.z) - centre
		if _overlaps(delta, x, z, half, ex, ez, other_half):
			return false
	return true

func _overlaps(delta: Vector2, x: Vector2, z: Vector2, half: Vector2,
		ex: Vector2, ez: Vector2, other: Vector2) -> bool:
	for axis: Vector2 in [x, z, ex, ez]:
		var reach := absf(x.dot(axis)) * half.x + absf(z.dot(axis)) * half.y
		reach += absf(ex.dot(axis)) * other.x + absf(ez.dot(axis)) * other.y
		if absf(delta.dot(axis)) >= reach - 0.03:
			return false
	return true

func nearest(location: Vector3) -> int:
	var selected := -1
	var best := INF
	for i in range(items.size()):
		var item := items[i]
		var local := (location - item.location).rotated(Vector3.UP, -item.yaw)
		var bounds: Vector3 = Target.DIMENSIONS[item.kind]
		var dx := absf(local.x) / (bounds.x * 0.5 + 0.95)
		var dz := absf(local.z) / (bounds.z * 0.5 + 0.95)
		var distance := dx * dx + dz * dz
		if dx <= 1.0 and dz <= 1.0 and distance < best:
			best = distance
			selected = i
	return selected

func save_to(path: String = SAVE_PATH) -> Error:
	var encoded: Array = []
	for item in items:
		encoded.append([item.kind, item.location.x, item.location.y, item.location.z, item.yaw])
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": 3, "objects": encoded, "craters": _encode_craters()}))
	var result := file.get_error()
	file.close()
	if result != OK:
		return result
	return DirAccess.rename_absolute(temporary, path)

func load_from(path: String = SAVE_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	if file.get_length() > 128 * 1024:
		file.close()
		return ERR_INVALID_DATA
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return ERR_PARSE_ERROR
	var version: Variant = parsed.get("version")
	if (not version is int and not version is float) or (float(version) < 1.0 or float(version) > 3.0 or floorf(version) != float(version)):
		return ERR_PARSE_ERROR
	var legacy := float(version) == 1.0
	var encoded: Variant = parsed.get("objects")
	if not encoded is Array or encoded.size() > CAPACITY:
		return ERR_INVALID_DATA
	var next: Array[Placement] = []
	for record: Variant in encoded:
		if not record is Array or record.size() != (4 if legacy else 5):
			return ERR_INVALID_DATA
		for value: Variant in record:
			if not (value is float or value is int) or not is_finite(float(value)):
				return ERR_INVALID_DATA
		if record[0] < 0 or record[0] >= Target.NAMES.size() or floorf(record[0]) != record[0]:
			return ERR_INVALID_DATA
		var height := 0.0 if legacy else float(record[2])
		var z := float(record[2] if legacy else record[3])
		var yaw := float(record[3] if legacy else record[4])
		if absf(record[1]) > LIMIT or absf(z) > LIMIT or height < 0.0 or height > 12.0:
			return ERR_INVALID_DATA
		next.append(Placement.new(int(record[0]), Vector3(record[1], height, z), wrapf(yaw, -PI, PI)))
	var terrain: Variant = parsed.get("craters", [])
	if not terrain is Array or terrain.size() > Ground.CAPACITY:
		return ERR_INVALID_DATA
	var next_craters: Array[Vector4] = []
	for record: Variant in terrain:
		if not record is Array or record.size() != 4:
			return ERR_INVALID_DATA
		for value: Variant in record:
			if not (value is float or value is int) or not is_finite(float(value)):
				return ERR_INVALID_DATA
		if absf(record[0]) > LIMIT or absf(record[1]) > LIMIT or record[2] < 1.0 or record[2] > Ground.RADIUS_LIMIT or record[3] < 0.2 or record[3] > 36.0:
			return ERR_INVALID_DATA
		next_craters.append(Vector4(record[0], record[1], record[2], record[3]))
	items = next
	craters = next_craters
	return OK

func _encode_craters() -> Array:
	var encoded: Array = []
	for record in craters:
		encoded.append([record.x, record.y, record.z, record.w])
	return encoded
