extends Resource

@export var display_yield: String = "100 кг"
@export var tier: int = 0
@export var visual_scale: float = 1.0
@export var light_energy: float = 10.0
@export var sound_range: float = 280.0
@export var audio_pitch: float = 1.0
var audio_variant := 1
var audio_level_db := -4.0
var audio_unit := 30.0
var dust_height := 0.75
var heat_duration := 0.65
var presentation_height := 0.0
var cloud_linger := 1.0
var ground_dust := 0.0
var thermonuclear_visual := false
var smoke_height := 6.0
var visual_growth := 0.0
@export_range(0.1, 120.0) var lifetime: float = 8.0
@export_range(1.0, 500.0) var fire_radius: float = 4.4
@export_range(1.0, 2500.0) var front_radius: float = 28.0
@export_range(0.01, 8.0) var front_duration: float = 28.0 / 343.0
@export_range(1.0, 2500.0) var target_radius: float = 14.0

func cloud_lifetime() -> float:
	return lifetime * cloud_linger
