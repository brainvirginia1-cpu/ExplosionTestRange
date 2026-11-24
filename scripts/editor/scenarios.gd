extends RefCounted

const Layout := preload("res://scripts/editor/range_layout.gd")
const Target := preload("res://scripts/destruction/range_target.gd")
const INITIAL_POWER := 1000000000.0
const STARTING_TARGETS := 100

static func configure(layout: Layout) -> void:
	layout.defaults()
	for line in range(5):
		for column in range(5):
			var location := Vector3(-480 + column * 225, 0.0, -165 - line * 155)
			layout.append(Target.Kind.SHELTER, location, -0.09)
			layout.append(Target.Kind.CONTAINER, location + Vector3(12, 0, 10))
			layout.append(Target.Kind.WALL, location + Vector3(-8, 0, 16), PI * 0.18)
			if column % 2 == 0:
				layout.append(Target.Kind.BRICK + (line + column) % 5, location + Vector3(-16, 0, -11), 0.23)
	# Keep the original distant layout and leave room for user placements.
	if layout.items.size() > STARTING_TARGETS:
		layout.items.resize(STARTING_TARGETS)
