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
	# A compact pressure floor and a longer soft shoulder describe each lobe as
	# a shallow dent while letting the shoulder return to untouched snow before
	# it can join the heel to the forefoot.
	profile.dust_core = 0.58
	profile.dust_break = 0.03
	profile.dust_irregularity_scale = 0.20
	# The reference read is two shallow contacts, not a miniature shoe mould:
	# the heel takes less load, the forefoot takes more, and untouched powder
	# remains between them. At the shipped 0.22 dust strength and 0.16 m terrain
	# response these weights and the camera-scale gain resolve to about 13 mm
	# and 17 mm respectively after the dust band's restrained 8% blend back
	# toward the generic pocket.
	profile.dust_waist_influence = 0.0
	profile.dust_lobe_length_scale = 0.82
	profile.dust_heel_weight = 0.18
	profile.dust_forefoot_weight = 0.25
	# This does not deepen the shared terrain response. It amplifies only the
	# two pressure contacts as `scuff` reaches the dust endpoint, so deep prints,
	# body impacts and furrows remain untouched and no extra texture read exists.
	profile.dust_readability_gain = 1.55
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/tracks"))
	var error := ResourceSaver.save(profile, OUTPUT_PATH)
	if error != OK:
		push_error("generate_track_profiles: failed to save %s (%d)" % [OUTPUT_PATH, error])
		quit(1)
		return
	print("generate_track_profiles: wrote %s" % OUTPUT_PATH)
	quit()
