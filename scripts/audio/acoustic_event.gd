extends AudioStreamPlayer3D

signal tail_finished

const Propagation := preload("res://scripts/core/propagation.gd")
const SOUND_SPEED := Propagation.SPEED # World units per game second, with one unit per metre.
var auto_free_if_inaudible := false
var soft_range := 0.0
var roll_stream: AudioStream
var _roll: AudioStreamPlayer3D
var _base_db := 0.0
var _layers: Array[AudioStreamPlayer3D] = []
var _layer_levels: Array[float] = []

func add_layer(audio: AudioStream, level_db: float, bus_name: StringName = &"Master") -> void:
	var layer := AudioStreamPlayer3D.new()
	layer.stream = audio
	layer.bus = bus_name
	layer.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	layer.pitch_scale = pitch_scale
	layer.volume_db = volume_db+level_db
	_layers.append(layer)
	_layer_levels.append(level_db)
	add_child(layer)

func is_active() -> bool:
	if arrival_time < 0.0 or playing or (_roll != null and _roll.playing):
		return true
	for layer in _layers:
		if layer.playing:
			return true
	return false

func _ready() -> void:
	_base_db = volume_db
	if roll_stream:
		attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		_roll = AudioStreamPlayer3D.new()
		_roll.stream = roll_stream
		_roll.pitch_scale = pitch_scale
		_roll.unit_size = unit_size
		_roll.attenuation_model = attenuation_model
		add_child(_roll)

var travel_time := 0.0
var arrival_time := -1.0

# The first delta includes time before this event entered the scene.
var _first_update := true

func _process(delta: float) -> void:
	if _first_update:
		_first_update = false
		return
	travel_time += delta
	if travel_time < 0.0:
		return
	var listener := get_viewport().get_camera_3d()
	var radius := travel_time * SOUND_SPEED
	if soft_range > 0.0 and listener != null:
		var distance := global_position.distance_to(listener.global_position)
		var ratio := distance / soft_range
		var rolloff := 1.0 / (1.0 + ratio * ratio)
		if _roll:
			var spatial_falloff := distance/(unit_size*4.8)
			rolloff = 1.0/sqrt((1.0+spatial_falloff*spatial_falloff)*(1.0+ratio*ratio))
		volume_db = _base_db + linear_to_db(maxf(0.00001, rolloff))
		if _roll:
			var blend := smoothstep(1.5,8.4,distance/unit_size)
			_roll.volume_db = volume_db + linear_to_db(maxf(0.00001,sqrt(blend))) - 1.5
			volume_db += linear_to_db(maxf(0.00001,sqrt(1.0-blend)))
		attenuation_filter_cutoff_hz = lerpf(3000.0,17000.0,1.0/(1.0+ratio))
		if _roll:
			_roll.attenuation_filter_cutoff_hz = attenuation_filter_cutoff_hz
		for i in _layers.size():
			_layers[i].volume_db = _base_db+_layer_levels[i]+linear_to_db(maxf(0.00001,rolloff))
			_layers[i].attenuation_filter_cutoff_hz = attenuation_filter_cutoff_hz
	if arrival_time >= 0.0:
		if not is_active():
			set_process(false)
			tail_finished.emit()
		return
	if max_distance > 0.0:
		radius = minf(radius, max_distance)
	if listener != null and global_position.distance_squared_to(listener.global_position) <= radius * radius:
		arrival_time = travel_time
		play()
		if _roll:
			_roll.play()
		for layer in _layers:
			layer.play()
		set_process(soft_range > 0.0 or not _layers.is_empty())
	elif max_distance > 0.0 and travel_time > max_distance / SOUND_SPEED:
		set_process(false)
		if auto_free_if_inaudible:
			queue_free()

func cancel() -> void:
	set_process(false)
	stop()
	if _roll:
		_roll.stop()
	for layer in _layers:
		layer.stop()
