extends RefCounted

signal distant_collapse(location: Vector3)
signal target_hit(location: Vector3)

const Target := preload("res://scripts/destruction/range_target.gd")
const DETAILED_FRAGMENT_ALLOWANCE := 140
const DETAIL_DISTANCE := 390.0

class Arrival:
	var target: Target
	var distance: float

var _arrivals: Array[Arrival] = []
var _index := 0
var _detailed_fragments := 0
var _origin: Vector3
var _reach: float
var _intensity: float

func prepare(targets: Array[Target], origin: Vector3, reach: float, intensity: float) -> void:
	_origin = origin
	_reach = reach
	_intensity = intensity
	for target in targets:
		var offset := target.global_position - origin
		var distance := offset.length()
		if distance > reach:
			continue
		var arrival := Arrival.new()
		arrival.target = target
		arrival.distance = distance
		_arrivals.append(arrival)
	_arrivals.sort_custom(func(a: Arrival, b: Arrival) -> bool: return a.distance < b.distance)

func advance(radius: float) -> void:
	while _index < _arrivals.size() and _arrivals[_index].distance <= radius:
		var arrival := _arrivals[_index]
		_index += 1
		var progress := arrival.distance/_reach
		# Hold most of the gameplay force across the range. Fade continuously at its edge.
		var attenuation := 1.0-0.17*smoothstep(0.22,0.88,progress)
		var edge := 1.0-smoothstep(0.91,1.0,progress)
		var intensity := _intensity*2.80*attenuation*edge
		if intensity <= 0.0:
			continue
		var detailed := arrival.distance <= DETAIL_DISTANCE and _detailed_fragments < DETAILED_FRAGMENT_ALLOWANCE
		var fragments := arrival.target.receive_front(_origin, intensity, radius, detailed, progress)
		if detailed:
			_detailed_fragments += fragments
		target_hit.emit(arrival.target.global_position)
		if arrival.distance > DETAIL_DISTANCE and fragments > 0:
			distant_collapse.emit(arrival.target.global_position)
