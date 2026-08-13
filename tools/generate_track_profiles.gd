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
	profile.sole_definition_dust = 0.92
	profile.sole_definition_shallow = 0.96
	profile.sole_definition_medium = 0.70
	profile.sole_definition_deep = 0.30
	profile.dust_length_scale = 0.80
	profile.dust_width_scale = 1.08
	# A compact pressure floor and a soft shoulder keep the boot depression
	# legible without turning it into a hard-edged decal.
	profile.dust_core = 0.58
	profile.dust_break = 0.03
	profile.dust_irregularity_scale = 0.20
	# A dusting is still a planted boot. The former .18/.25 endpoint reduced the
	# production caller's weakest bite to two 5--7% mask dots and removed its
	# waist entirely. Neutral endpoint geometry restores the complete three-lobe
	# sole while preserving the restrained heel/forefoot load difference. At the
	# caller's 0.154..0.22 strength range this yields approximately .137..194 at
	# the heel and .154..220 at the forefoot before the 0.16 m visual response.
	profile.dust_waist_influence = 1.0
	profile.dust_lobe_length_scale = 1.0
	profile.dust_heel_weight = 0.88
	profile.dust_forefoot_weight = 1.0
	profile.dust_readability_gain = 1.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/tracks"))
	var error := ResourceSaver.save(profile, OUTPUT_PATH)
	if error != OK:
		push_error("generate_track_profiles: failed to save %s (%d)" % [OUTPUT_PATH, error])
		quit(1)
		return
	print("generate_track_profiles: wrote %s" % OUTPUT_PATH)
	quit()
