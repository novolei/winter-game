class_name LightingPreset
extends Resource

## One of the six looks. Each is a dramatic beat as much as a light setup.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Key Light")
@export var sun_energy := 1.0
@export var sun_color := Color.WHITE
@export var sun_angle_degrees := 15.0
@export var shadows_enabled := true

@export_group("Ambient")
@export var ambient_color := Color(0.08, 0.11, 0.19)
@export var ambient_energy := 1.0

@export_group("Air")
@export var fog_enabled := true
@export var fog_density := 0.01
@export var glow_enabled := true
@export var glow_strength := 0.3

@export_group("Shading")
@export var cel_band_threshold := 0.5
@export var cel_band_softness := 0.05
@export var warm_accent_energy := 1.0
