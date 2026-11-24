extends RefCounted

const Profile := preload("res://scripts/explosions/explosion_profile.gd")
const Propagation := preload("res://scripts/core/propagation.gd")
const BASE := preload("res://data/presets/local_100.tres")
const MIN_KG := 50.0
const MAX_KG := 100000000000.0
const THERMONUCLEAR_THRESHOLD := 25000000000.0
const THERMONUCLEAR_LABEL := "Термоядерный"
const BOUNDARIES := [50.0, 500.0, 10000.0, 1000000.0, 100000000.0, 1000000000.0, 10000000000.0]
const CLASSES := ["I", "II", "III", "IV", "V", "VI", "VII"]
const QUICK_VALUES := [50.0, 100.0, 500.0, 1000.0, 5000.0, 10000.0, 100000.0, 500000.0, 1000000.0,
	10000000.0, 50000000.0, 100000000.0, 500000000.0, 1000000000.0, 5000000000.0, 10000000000.0,
	25000000000.0, 50000000000.0, MAX_KG]
const UNITS := ["кг", "т", "кт", "Мт"]
const UNIT_FACTORS := [1.0, 1000.0, 1000000.0, 1000000000.0]
const ART_ANCHORS := [50.0, 100.0, 1000.0, 100000.0, 10000000.0, 1000000000.0, 50000000000.0, MAX_KG]
# Radius, lifetime and vertical scales are authored for the game's cameras.
const FIRE := [2.8, 4.4, 10.0, 36.0, 115.0, 265.0, 490.0, 595.0]
const FRONT := [19.0, 28.0, 73.0, 270.0, 660.0, 1480.0, 2400.0, 2400.0]
const TARGET := [9.0, 14.0, 30.0, 116.0, 408.0, 1030.0, 1740.0, 1740.0]
const LIFE := [64.0, 66.0, 70.0, 76.0, 91.0, 107.0, 128.0, 145.0]
const DUST := [0.42, 0.72, 2.05, 8.9, 25.0, 58.0, 102.0, 122.0]
const SMOKE := [3.6, 6.0, 14.0, 51.0, 170.0, 510.0, 900.0, 1100.0]
const HEAT := [0.36, 0.56, 0.79, 1.65, 2.75, 4.20, 6.4, 7.5]
const SOUND_FALLOFF := [22.0, 30.0, 44.0, 110.0, 250.0, 600.0, 1070.0, 1260.0]

const Device := preload("res://scripts/devices/trial_device.gd")
const CLOUD_HEIGHTS := [
	[20000000.0, 5200.0],
	[100000000.0, 8200.0],
	[500000000.0, 13200.0],
	[1000000000.0, 16300.0],
	[2000000000.0, 18100.0],
	[5000000000.0, 20500.0],
	[10000000000.0, 22800.0],
	[20000000000.0, 25200.0],
	[30000000000.0, 27000.0],
	[50000000000.0, 50000.0],
	[MAX_KG, 80000.0],
]

static func presentation_height(kg: float) -> float:
	var previous: Array = CLOUD_HEIGHTS[0]
	if kg < previous[0]:
		return 0.0
	if kg == previous[0]:
		return previous[1]
	for i in range(1, CLOUD_HEIGHTS.size()):
		var anchor: Array = CLOUD_HEIGHTS[i]
		if kg <= anchor[0]:
			var progress := inverse_lerp(log(previous[0]), log(anchor[0]), log(kg))
			return lerpf(previous[1], anchor[1], progress)
		previous = anchor
	return previous[1]

static func is_thermonuclear(kg: float, mode: int) -> bool:
	return kg > THERMONUCLEAR_THRESHOLD and mode == Device.BlastMode.SURFACE

static func apply_surface_presentation(profile: Profile, kg: float) -> void:
	profile.presentation_height = presentation_height(kg)
	if profile.presentation_height <= 0.0:
		return
	var scale := clampf(inverse_lerp(log(CLOUD_HEIGHTS[0][0]), log(MAX_KG), log(kg)), 0.0, 1.0)
	profile.ground_dust = lerpf(0.22, 1.0, scale)
	profile.cloud_linger = lerpf(1.8, 3.0, pow(scale, 0.58))

static func normalized(kg: float) -> float:
	return log(clampf(kg, MIN_KG, MAX_KG) / MIN_KG) / log(MAX_KG / MIN_KG)

static func from_slider(value: float) -> float:
	if value <= 0.0:
		return MIN_KG
	if value >= 1.0:
		return MAX_KG
	return roundf(MIN_KG * pow(MAX_KG / MIN_KG,value))

static func unit_index(kg: float) -> int:
	for i in range(UNIT_FACTORS.size() - 1, 0, -1):
		if kg >= UNIT_FACTORS[i]:
			return i
	return 0

static func label(kg: float) -> String:
	var index := unit_index(kg)
	var amount: float = kg / UNIT_FACTORS[index]
	var display := str(int(amount)) if amount == floorf(amount) else String.num(amount,3)
	return "%s %s" % [display,TranslationServer.translate(UNITS[index])]

static func tier_for(kg: float) -> int:
	for i in range(BOUNDARIES.size() - 1, 0, -1):
		if kg >= BOUNDARIES[i]:
			return i
	return 0

static func make_profile(kg: float) -> Profile:
	kg = clampf(kg, MIN_KG, MAX_KG)
	var profile := BASE.duplicate() as Profile
	var anchor := 0
	while anchor < ART_ANCHORS.size() - 2 and kg >= ART_ANCHORS[anchor + 1]:
		anchor += 1
	var progress := inverse_lerp(log(ART_ANCHORS[anchor]), log(ART_ANCHORS[anchor + 1]), log(kg))
	var growth := normalized(kg)
	profile.display_yield = label(kg)
	profile.tier = tier_for(kg)
	profile.visual_growth = growth
	profile.fire_radius = _interpolate(FIRE, anchor, progress)
	profile.front_radius = _interpolate(FRONT, anchor, progress)
	profile.target_radius = _interpolate(TARGET, anchor, progress)
	profile.front_duration = Propagation.travel_time(profile.front_radius)
	profile.lifetime = _interpolate(LIFE, anchor, progress)
	profile.dust_height = _interpolate(DUST, anchor, progress)
	profile.smoke_height = _interpolate(SMOKE, anchor, progress)
	profile.heat_duration = _interpolate(HEAT, anchor, progress)
	profile.light_energy = lerpf(8.0, 70.0, pow(growth, 1.02))
	profile.visual_scale = profile.fire_radius / 4.4
	profile.sound_range = _interpolate([220.0, 280.0, 440.0, 820.0, 1700.0, 3300.0, 4800.0, 5100.0], anchor, progress)
	profile.audio_unit = _interpolate(SOUND_FALLOFF, anchor, progress)
	profile.audio_variant = mini(anchor + int(progress >= 0.5), 6)
	profile.audio_level_db = lerpf(-1.3,3.3,growth)
	profile.audio_pitch = lerpf(1.022, 0.93, growth)
	return profile

static func _interpolate(values: Array, index: int, fraction: float) -> float:
	return exp(lerpf(log(values[index]), log(values[index + 1]), fraction))
