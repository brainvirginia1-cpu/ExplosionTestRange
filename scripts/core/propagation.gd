extends RefCounted

const SPEED := 343.0

static func radius_at(seconds: float, maximum: float) -> float:
	return clampf(seconds * SPEED, 0.0, maximum)

static func travel_time(distance: float) -> float:
	return maxf(0.0, distance) / SPEED
