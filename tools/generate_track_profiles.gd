extends SceneTree

## Generates the shipped footprint profiles.  Run with:
##
##   Godot --headless --path <project> --script res://tools/generate_track_profiles.gd

const OUTPUT_PATH := "res://data/tracks/human_winter_boot.tres"
const TrackProfileScript := preload("res://src/definitions/track_profile_definition.gd")


func _initialize() -> void:
	var profile: TrackProfileDefinition = TrackProfileScript.new()
	profile.profile_id = &"human_winter_boot"
	profile.subjects = [&"player"]
	profile.heel_centre_x = -0.48
	profile.heel_half_length = 0.40
	profile.heel_half_width = 0.70
	profile.waist_centre_x = -0.05
	profile.waist_half_length = 0.40
	profile.waist_half_width = 0.52
	profile.forefoot_centre_x = 0.44
	profile.forefoot_half_length = 0.58
	profile.forefoot_half_width = 1.0
	profile.heel_weight = 0.88
	profile.forefoot_weight = 1.0
	profile.weight_transition_from_x = -0.30
	profile.weight_transition_to_x = 0.28
	profile.shallow_wade = 0.33
	profile.medium_wade = 0.72
	profile.sole_definition_dust = 0.78
	profile.sole_definition_shallow = 0.85
	profile.sole_definition_medium = 0.70
	profile.sole_definition_deep = 0.30
	profile.dust_length_scale = 1.03
	profile.dust_width_scale = 0.96
	profile.dust_core = 0.58
	profile.dust_break = 0.16
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/tracks"))
	var error := ResourceSaver.save(profile, OUTPUT_PATH)
	if error != OK:
		push_error("generate_track_profiles: failed to save %s (%d)" % [OUTPUT_PATH, error])
		quit(1)
		return
	print("generate_track_profiles: wrote %s" % OUTPUT_PATH)
	quit()
