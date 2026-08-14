extends SceneTree

## Generator for GDD section 7's six weather events, and for the four extra
## `WindMap`s they blow through.
##
##   godot --headless --path <project> --script res://tools/generate_weather_events.gd
##
## Content `.tres` are generated rather than hand-authored (briefing constraint
## 7): `Array[StatModifier]` and a nested `WeatherTell` are exactly the two
## shapes that hand-written typed-array syntax gets wrong in ways that take an
## afternoon to find.
##
## ---------------------------------------------------------------------------
## SIX KINDS, AND EVERY ONE OF THEM ANNOUNCES ITSELF
## ---------------------------------------------------------------------------
## GDD section 7's table, with its 预兆 column made into data rather than prose:
##
##   暴雪    blizzard       风声升高、地平线泛白   -> the sky bruises toward
##                                                   NIGHTFALL, the wind goes to
##                                                   the gale map, the snow
##                                                   thickens, the crows go up
##   风向突变 wind_shift     雪粒改向、风声移位     -> the wind DROPS first, then
##                                                   swings 155 degrees round
##   短暂放晴 clear_break    云隙、光转暖           -> the light lifts toward
##                                                   PALE DAY, the snow thins
##   冻雨    freezing_rain  落雪声变脆             -> a sound, plus the fall
##                                                   thickening under a
##                                                   NIGHTFALL sky
##   寒流    cold_snap      空气变得极静           -> the snow STOPS and the wind
##                                                   dies. No light change at
##                                                   all: nothing looks wrong,
##                                                   which is the horror
##   雪雾    snow_fog       远景糊化               -> the fog window closes
##                                                   toward NIGHTFALL, wind calm
##
## ---------------------------------------------------------------------------
## WHY THERE ARE FOUR MORE WIND MAPS
## ---------------------------------------------------------------------------
## `WindSystem.set_profile()` snaps -- it adopts immediately and re-settles the
## model at the same clock, so forcing a still night to a gale steps the strength
## by about 0.5 in one frame. `WindSystem.set_map()` does not: it clears the
## system's memory of which sky it last resolved, and the next frame re-resolves
## through the new map and CROSSFADES over six seconds. Same one call, no step.
##
## So a weather event brings its wind as a MAP. Each of these four holds exactly
## one profile and names it as the default, which makes `profile_for()` answer it
## for every sky -- "whatever the light is doing, this is the wind".
##
##   wind_map_gale    -> wind_gale     暴雪
##   wind_map_calm    -> wind_calm     短暂放晴, 雪雾, and the drop before 风向突变
##   wind_map_still   -> wind_still    寒流
##   wind_map_veered  -> wind_veered   风向突变
##
## `wind_veered` is `wind_valley` DUPLICATED and turned 155 degrees, rather than
## a fifth set of tuning numbers. The valley profile is the one the whole wind
## system was judged against; a direction event should change the direction and
## nothing else, and duplicating rather than re-typing means it cannot drift when
## somebody retunes the valley.

const OUT_DIR := "res://data/weather"
const VFX_OUT_DIR := "res://data/weather/vfx"
const FOG_OUT_DIR := "res://data/weather/fog"
const SNOW_RESPONSE_DIR := "res://data/snow/responses"

const VALLEY_PATH := "res://data/weather/wind_valley.tres"

## How far 风向突变 turns the wind. Not 180: GDD section 8 hangs the bear's nose
## on the heading and wants it reversed, and the crossfade is a lerp of the
## heading in DEGREES -- so 155 sweeps the snow visibly round through every
## quarter in between, where an exact reversal would too, but with no asymmetry
## to say which way it went.
const VEER_DEGREES := 155.0

## The four one-profile maps: file id -> the profile it answers with.
const MAPS := {
	"wind_map_gale": "wind_gale",
	"wind_map_calm": "wind_calm",
	"wind_map_still": "wind_still",
	"wind_map_veered": "wind_veered",
}

## One fixed-budget air signature per weather. These do not replace snowfall,
## wind or fog; they only describe the small residual cue that makes two events
## with similar light and snow read differently at a glance.
const VFX_PROFILES := {
	&"blizzard": {
		"tell_density": 0.12, "active_density": 0.42,
		"mark_size": Vector2(0.05, 0.115), "scale_range": Vector2(0.42, 1.45),
		"spread_degrees": 24.0, "speed_range": Vector2(1.6, 3.4),
		"downward_bias": 0.42, "wind_influence": 1.35,
		"fall_acceleration": 0.28, "opacity": 0.28,
		"velocity_aligned": false, "emission_randomness": 0.55,
		"turbulence_influence_range": Vector2(0.65, 1.45),
		"turbulence_scale": 0.85, "turbulence_drift": 0.18,
		"damping_range": Vector2(0.45, 1.10),
		"angular_velocity_range": Vector2(-70.0, 70.0),
		"angular_velocity_end_multiplier": 0.03,
		"rock_amplitude_range": Vector2(15.0, 30.0),
		"rock_frequency_range": Vector2(0.32, 0.78), "rock_end_multiplier": 0.42,
		"flutter_amplitude_range": Vector2(4.0, 10.0),
		"flutter_frequency_range": Vector2(1.25, 2.65),
		"flip_probability": 0.20, "flip_duration_range": Vector2(0.22, 0.36),
		"flip_edge_scale": 0.20,
	},
	&"wind_shift": {
		"tell_density": 0.0, "active_density": 0.14,
		"mark_size": Vector2(0.045, 0.105), "scale_range": Vector2(0.48, 1.35),
		"spread_degrees": 18.0, "speed_range": Vector2(2.2, 4.0),
		"downward_bias": 0.28, "wind_influence": 1.65,
		"fall_acceleration": 0.18, "opacity": 0.24,
		"velocity_aligned": false, "emission_randomness": 0.50,
		"turbulence_influence_range": Vector2(0.55, 1.20),
		"turbulence_scale": 0.70, "turbulence_drift": 0.22,
		"damping_range": Vector2(0.70, 1.40),
		"angular_velocity_range": Vector2(-85.0, 85.0),
		"angular_velocity_end_multiplier": 0.04,
		"rock_amplitude_range": Vector2(12.0, 26.0),
		"rock_frequency_range": Vector2(0.40, 0.95), "rock_end_multiplier": 0.38,
		"flutter_amplitude_range": Vector2(4.0, 9.0),
		"flutter_frequency_range": Vector2(1.60, 3.00),
		"flip_probability": 0.16, "flip_duration_range": Vector2(0.18, 0.30),
		"flip_edge_scale": 0.22,
	},
	&"clear_break": {
		"tell_density": 0.0, "active_density": 0.0,
		"mark_size": Vector2(0.025, 0.1), "scale_range": Vector2(0.8, 1.2),
		"spread_degrees": 4.0, "speed_range": Vector2(0.5, 1.0),
		"downward_bias": 0.8, "wind_influence": 0.2,
		"fall_acceleration": 0.1, "opacity": 0.2, "velocity_aligned": false,
	},
	&"freezing_rain": {
		"tell_density": 0.25, "active_density": 0.82,
		"mark_size": Vector2(0.014, 0.34), "scale_range": Vector2(0.75, 1.25),
		"spread_degrees": 3.0, "speed_range": Vector2(7.0, 10.0),
		"downward_bias": 1.0, "wind_influence": 0.35,
		"fall_acceleration": 1.2, "opacity": 0.5,
		"velocity_aligned": true, "emission_randomness": 0.18,
		"damping_range": Vector2(0.08, 0.18),
	},
	&"cold_snap": {
		"tell_density": 0.04, "active_density": 0.09,
		"mark_size": Vector2(0.03, 0.055), "scale_range": Vector2(0.45, 1.45),
		"spread_degrees": 28.0, "speed_range": Vector2(0.12, 0.3),
		"downward_bias": 0.18, "wind_influence": 0.08,
		"fall_acceleration": 0.02, "opacity": 0.38,
		"velocity_aligned": false, "emission_randomness": 0.65,
		"turbulence_influence_range": Vector2(0.04, 0.12),
		"turbulence_scale": 1.40, "turbulence_drift": 0.04,
		"damping_range": Vector2(0.15, 0.35),
		"angular_velocity_range": Vector2(-18.0, 18.0),
		"angular_velocity_end_multiplier": 0.15,
		"rock_amplitude_range": Vector2(5.0, 12.0),
		"rock_frequency_range": Vector2(0.15, 0.35), "rock_end_multiplier": 0.70,
		"flutter_amplitude_range": Vector2(1.0, 3.0),
		"flutter_frequency_range": Vector2(0.50, 1.00),
		"flip_probability": 0.03, "flip_duration_range": Vector2(0.45, 0.65),
		"flip_edge_scale": 0.35,
	},
	&"snow_fog": {
		"tell_density": 0.12, "active_density": 0.30,
		"mark_size": Vector2(0.048, 0.088), "scale_range": Vector2(0.5, 1.5),
		"spread_degrees": 30.0, "speed_range": Vector2(0.35, 0.9),
		"downward_bias": 0.55, "wind_influence": 0.20,
		"fall_acceleration": 0.08, "opacity": 0.20,
		"velocity_aligned": false, "emission_randomness": 0.60,
		"turbulence_influence_range": Vector2(0.18, 0.45),
		"turbulence_scale": 1.40, "turbulence_drift": 0.06,
		"damping_range": Vector2(0.20, 0.50),
		"angular_velocity_range": Vector2(-28.0, 28.0),
		"angular_velocity_end_multiplier": 0.10,
		"rock_amplitude_range": Vector2(8.0, 18.0),
		"rock_frequency_range": Vector2(0.18, 0.42), "rock_end_multiplier": 0.62,
		"flutter_amplitude_range": Vector2(2.0, 5.0),
		"flutter_frequency_range": Vector2(0.70, 1.25),
		"flip_probability": 0.08, "flip_duration_range": Vector2(0.35, 0.55),
		"flip_edge_scale": 0.28,
	},
}

## Middle-distance world-space veils. The shared renderer never checks an event
## id: an event either references one of these resources or leaves the field
## null. These densities only act inside the camera-gated local window; each
## profile's peak is also enforced by the shader as a last safety rail.
const FOG_PROFILES := {
	&"blizzard": {
		"tell_density": 0.00400, "active_density": 0.02800,
		"peak_density": 0.05200,
		"macro_scale_m": Vector3(15.0, 6.0, 9.0),
		"detail_scale_m": Vector3(5.0, 2.5, 3.2),
		"detail_weight": 0.28, "noise_contrast": 0.42,
		"wind_advection_multiplier": 0.12,
		"max_advection_speed_mps": 0.80, "wind_response_per_second": 2.40,
		"near_clear_depth_m": 76.0, "near_full_depth_m": 88.0,
		"far_fade_start_m": 112.0, "far_fade_end_m": 128.0,
	},
	&"snow_fog": {
		"tell_density": 0.00300, "active_density": 0.01900,
		"peak_density": 0.03400,
		"macro_scale_m": Vector3(17.0, 7.0, 11.0),
		"detail_scale_m": Vector3(6.0, 3.5, 4.5),
		"detail_weight": 0.24, "noise_contrast": 0.32,
		"wind_advection_multiplier": 0.08,
		"max_advection_speed_mps": 0.42, "wind_response_per_second": 1.40,
		"near_clear_depth_m": 76.0, "near_full_depth_m": 88.0,
		"far_fade_start_m": 112.0, "far_fade_end_m": 128.0,
	},
}


# --- the six ------------------------------------------------------------------
#
# Keys map to WeatherEventDefinition / WeatherTell properties by name, so a field
# added to either definition is authorable here with no code below changing.

const BLIZZARD := {
	"id": &"blizzard",
	"display_name": "Blizzard",
	"vfx_profile": &"blizzard",
	"fog_profile": &"blizzard",
	"tell_duration_range": Vector2(24.0, 36.0),
	"active_duration_range": Vector2(150.0, 240.0),
	"fade_duration": 20.0,
	"lighting_preset": &"whiteout",
	"lighting_fade_seconds": 10.0,
	"wind_map": "wind_map_gale",
	"wind_speed_multiplier": 1.6,
	"snowfall_rate": 1.0,
	"visibility_multiplier": 0.25,
	"extinguishes_beacons": true,
	"min_beacons_extinguished": 1,
	# 体温↓↓ -- the drain doubles, on top of NightExposure's own doubling after
	# dark. Two multiplies on one channel is 4x in a night blizzard, which is
	# GDD section 4's day 7 and is meant to be survivable only indoors.
	"stats": [[&"core_temperature", Modifier.Operation.MULTIPLY, 2.0]],
	"tell": {
		"sound": &"weather_tell_blizzard",
		# NIGHTFALL and not WHITEOUT: the director refuses to restart a crossfade
		# toward the preset it is already fading to, so a tell that leaned at
		# WHITEOUT would own the arrival as well and `lighting_fade_seconds`
		# above would be silently ignored. Leaning at the intermediate look is
		# also just what the sky does -- it goes flat and grey before it goes
		# white.
		"lighting_preset": &"nightfall",
		"lighting_lead": 0.5,
		"wind_map": "wind_map_gale",
		"wind_speed_multiplier": 1.3,
		"snowfall_rate": 0.42,
		"flushes_wildlife": true,
	},
}

const WIND_SHIFT := {
	"id": &"wind_shift",
	"display_name": "Wind shift",
	"vfx_profile": &"wind_shift",
	"tell_duration_range": Vector2(20.0, 30.0),
	"active_duration_range": Vector2(90.0, 160.0),
	"fade_duration": 12.0,
	"wind_map": "wind_map_veered",
	"wind_speed_multiplier": 1.15,
	"tell": {
		"sound": &"weather_tell_wind_shift",
		# THE WIND DROPS BEFORE IT TURNS, and that is the cue. The spindrift
		# switches off below 0.28, the tyre coasts to a stop and the snow falls
		# straight -- three things going quiet at once, which is far more legible
		# than a heading nudging a few degrees. Then it comes back from the other
		# side.
		"wind_map": "wind_map_calm",
		"wind_speed_multiplier": 0.55,
		"flushes_wildlife": true,
	},
}

const CLEAR_BREAK := {
	"id": &"clear_break",
	"display_name": "Clear break",
	"vfx_profile": &"clear_break",
	"tell_duration_range": Vector2(20.0, 30.0),
	"active_duration_range": Vector2(120.0, 200.0),
	"fade_duration": 25.0,
	"lighting_preset": &"sunrise",
	"lighting_fade_seconds": 12.0,
	"wind_map": "wind_map_calm",
	"wind_speed_multiplier": 0.6,
	"snowfall_rate": 0.02,
	"visibility_multiplier": 1.4,
	# 体温回升. Halving the DRAIN rather than pushing a recovery: recovery is
	# what a stove does, and a weather that warmed a man in the open would be a
	# second heat source nobody placed.
	"stats": [[&"core_temperature", Modifier.Operation.MULTIPLY, 0.55]],
	"tell": {
		"sound": &"weather_tell_clear_break",
		"lighting_preset": &"pale_day",
		"lighting_lead": 0.5,
		"snowfall_rate": 0.05,
		"wind_speed_multiplier": 0.8,
		# THE CROWS STAY. Birds do not flee good weather, and a flock bursting
		# off the wire ahead of a clear spell would be telling the player exactly
		# the wrong thing -- the one cue in the game that says "something is
		# coming" spent on the one event that is a relief.
		"flushes_wildlife": false,
	},
}

const FREEZING_RAIN := {
	"id": &"freezing_rain",
	"display_name": "Freezing rain",
	"vfx_profile": &"freezing_rain",
	"tell_duration_range": Vector2(22.0, 34.0),
	"active_duration_range": Vector2(100.0, 170.0),
	"fade_duration": 15.0,
	# EMPTY, and it is a shape rather than an omission: the tell below leans at
	# NIGHTFALL with a lead of 0.55, so the sky is still arriving well after the
	# sleet is. The tell owns the light for this one.
	"lighting_preset": &"",
	"snowfall_rate": 0.65,
	"wind_speed_multiplier": 1.1,
	"visibility_multiplier": 0.7,
	# 冻伤↑↑ -- both extremities, because the hands and the feet are separate
	# stats and a rule that hit one of them would read as a bug in the other.
	"stats": [
		[&"frostbite_hands", Modifier.Operation.MULTIPLY, 2.0],
		[&"frostbite_feet", Modifier.Operation.MULTIPLY, 2.0],
	],
	"tell": {
		# 落雪声变脆 -- the fall turning brittle is a SOUND, and it is the only
		# one of the six whose 预兆 column is purely audible. Which is exactly
		# why it also thickens the fall and leans the light: a tell that existed
		# only in a channel this project has not built yet would be no tell.
		"sound": &"weather_tell_freezing_rain",
		"lighting_preset": &"nightfall",
		"lighting_lead": 0.55,
		"snowfall_rate": 0.5,
		"wind_speed_multiplier": 1.1,
		"flushes_wildlife": true,
	},
}

const COLD_SNAP := {
	"id": &"cold_snap",
	"display_name": "Cold snap",
	"vfx_profile": &"cold_snap",
	"tell_duration_range": Vector2(26.0, 40.0),
	"active_duration_range": Vector2(150.0, 260.0),
	"fade_duration": 30.0,
	# NO LIGHT CHANGE, in either phase, and that is the design. GDD section 8:
	# 风大 → 足迹速消 → 你安全；风停 → 足迹留存 → 你被跟上. The frightening
	# weather in this game is the one where nothing looks wrong -- the sky is
	# unchanged, the air is clear, and the trail you are leaving now lasts eighty
	# seconds instead of twenty-six.
	"lighting_preset": &"",
	"wind_map": "wind_map_still",
	"wind_speed_multiplier": 0.25,
	"snowfall_rate": 0.03,
	"visibility_multiplier": 1.15,
	"stats": [[&"core_temperature", Modifier.Operation.MULTIPLY, 2.6]],
	"tell": {
		# 空气变得极静. The snow stops dead and the wind dies: no light, no
		# preset, nothing but the world going quiet. It is the most legible tell
		# of the six and it costs two numbers.
		"sound": &"weather_tell_cold_snap",
		"wind_map": "wind_map_still",
		"wind_speed_multiplier": 0.2,
		"snowfall_rate": 0.0,
		"flushes_wildlife": true,
	},
}

const SNOW_FOG := {
	"id": &"snow_fog",
	"display_name": "Snow fog",
	"vfx_profile": &"snow_fog",
	"fog_profile": &"snow_fog",
	"tell_duration_range": Vector2(20.0, 32.0),
	"active_duration_range": Vector2(120.0, 210.0),
	"fade_duration": 22.0,
	# As with the freezing rain: the tell owns the light, arriving late.
	"lighting_preset": &"",
	"wind_map": "wind_map_calm",
	"wind_speed_multiplier": 0.5,
	"snowfall_rate": 0.4,
	"visibility_multiplier": 0.45,
	# 体温影响轻 -- a little, and nothing like the blizzard's doubling.
	"stats": [[&"core_temperature", Modifier.Operation.MULTIPLY, 1.15]],
	"tell": {
		"sound": &"weather_tell_snow_fog",
		"lighting_preset": &"nightfall",
		"lighting_lead": 0.4,
		"wind_map": "wind_map_calm",
		"wind_speed_multiplier": 0.6,
		"snowfall_rate": 0.25,
		# A fog settles; it does not startle anything.
		"flushes_wildlife": false,
	},
}

const ALL := [BLIZZARD, WIND_SHIFT, CLEAR_BREAK, FREEZING_RAIN, COLD_SNAP, SNOW_FOG]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VFX_OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOG_OUT_DIR))
	var failed := not _write_veered()
	var vfx_profiles := _write_vfx_profiles()
	if vfx_profiles.size() != VFX_PROFILES.size():
		failed = true
	var fog_profiles := _write_fog_profiles()
	if fog_profiles.size() != FOG_PROFILES.size():
		failed = true
	var maps: Dictionary = {}
	for map_id in MAPS:
		var map := _write_map(map_id, MAPS[map_id])
		if map == null:
			failed = true
		else:
			maps[map_id] = map
	for spec in ALL:
		if not _write_event(spec, maps, vfx_profiles, fog_profiles):
			failed = true
	quit(1 if failed else 0)


## `wind_valley` turned 155 degrees. DUPLICATED rather than re-specified, so the
## one profile the whole wind system was tuned against stays the single source of
## every number except the heading.
func _write_veered() -> bool:
	var valley := load(VALLEY_PATH) as WindProfile
	if valley == null:
		push_error("generate_weather_events: %s missing -- run generate_wind_profiles first" % VALLEY_PATH)
		return false
	var veered: WindProfile = valley.duplicate()
	veered.id = &"wind_veered"
	veered.display_name = "Veered"
	# Emptied: this profile is never chosen by a sky, only by a weather event
	# naming the map that holds it. A preset left in the list would make it
	# compete with `wind_valley` inside the DEFAULT map, which is exactly the
	# "two writers" defect the wind system spent a page avoiding.
	veered.presets = [] as Array[StringName]
	veered.prevailing_degrees = valley.prevailing_degrees + VEER_DEGREES
	var path := "%s/wind_veered.tres" % OUT_DIR
	var error := ResourceSaver.save(veered, path)
	print("generate_weather_events: %s -> %d" % [path, error])
	return error == OK


## A map that answers one profile for every sky. `profile_for()` finds no preset
## match -- these profiles claim no presets, or claim only their own -- and falls
## through to `default_profile()`, which is the one named here.
func _write_map(map_id: String, profile_id: String) -> WindMap:
	var profile := load("%s/%s.tres" % [OUT_DIR, profile_id]) as WindProfile
	if profile == null:
		push_error("generate_weather_events: no profile %s" % profile_id)
		return null
	var MapScript := load("res://src/definitions/wind_map.gd")
	var map: WindMap = MapScript.new()
	# Annotated, not `var x = []`: an untyped local is a Variant and the typed
	# setter rejects what the compiler hands it, aborting the function with no
	# message at all (briefing trap 4).
	var only: Array[WindProfile] = [profile]
	map.profiles = only
	map.default_id = StringName(profile_id)
	var path := "%s/%s.tres" % [OUT_DIR, map_id]
	var error := ResourceSaver.save(map, path)
	print("generate_weather_events: %s -> %d" % [path, error])
	if error != OK:
		return null
	# Reloaded from disk so it carries a path, which is what makes the events
	# below reference it as an ext_resource instead of inlining a copy each.
	return load(path)


func _write_event(
		spec: Dictionary,
		maps: Dictionary,
		vfx_profiles: Dictionary,
		fog_profiles: Dictionary
) -> bool:
	var EventScript := load("res://src/definitions/weather_event_definition.gd")
	var event: WeatherEventDefinition = EventScript.new()
	for key in spec:
		match key:
			"tell":
				event.tell = _build_tell(spec[key], maps)
			"stats":
				event.stat_modifiers = _build_modifiers(spec["id"], spec[key])
			"wind_map":
				event.wind_map = maps.get(spec[key], null)
			"vfx_profile":
				event.vfx_profile = vfx_profiles.get(spec[key], null)
			"fog_profile":
				event.fog_profile = fog_profiles.get(spec[key], null)
			_:
				event.set(key, spec[key])
	# Snow responses are generated by their own data tool, but a later weather
	# regeneration must not silently sever those authored ground contracts. The
	# shared id convention also means a new event gains the link without another
	# branch in this generator.
	var response_path := "%s/%s.tres" % [SNOW_RESPONSE_DIR, spec["id"]]
	if ResourceLoader.exists(response_path):
		event.snow_response = load(response_path) as SnowResponseDefinition
	var path := "%s/event_%s.tres" % [OUT_DIR, spec["id"]]
	var error := ResourceSaver.save(event, path)
	print("generate_weather_events: %s -> %d" % [path, error])
	return error == OK


func _write_vfx_profiles() -> Dictionary:
	var VfxScript := load("res://src/definitions/weather_vfx_profile.gd")
	var built: Dictionary = {}
	for id in VFX_PROFILES:
		var profile: WeatherVfxProfile = VfxScript.new()
		profile.id = id
		for key in VFX_PROFILES[id]:
			profile.set(key, VFX_PROFILES[id][key])
		var path := "%s/%s.tres" % [VFX_OUT_DIR, id]
		var error := ResourceSaver.save(profile, path)
		print("generate_weather_events: %s -> %d" % [path, error])
		if error == OK:
			built[id] = load(path)
	return built


func _write_fog_profiles() -> Dictionary:
	var FogScript := load("res://src/definitions/weather_fog_profile.gd")
	var built: Dictionary = {}
	for id in FOG_PROFILES:
		var profile: WeatherFogProfile = FogScript.new()
		profile.id = id
		for key in FOG_PROFILES[id]:
			profile.set(key, FOG_PROFILES[id][key])
		var path := "%s/%s.tres" % [FOG_OUT_DIR, id]
		var error := ResourceSaver.save(profile, path)
		print("generate_weather_events: %s -> %d" % [path, error])
		if error == OK:
			built[id] = load(path)
	return built


func _build_tell(spec: Dictionary, maps: Dictionary) -> WeatherTell:
	var TellScript := load("res://src/definitions/weather_tell.gd")
	var tell: WeatherTell = TellScript.new()
	for key in spec:
		if key == "wind_map":
			tell.wind_map = maps.get(spec[key], null)
			continue
		tell.set(key, spec[key])
	return tell


## The source id is the EVENT's, always, and never the modifier's own. That is
## what makes `remove_source(event.id)` take every one of them off again when the
## weather clears -- and a MULTIPLY that outlived its weather would compound the
## next time the same event was drawn, look correct for a minute, and then kill
## the player with nothing to trace it to. `NightExposure._apply()` is the same
## hazard written down.
func _build_modifiers(event_id: StringName, rows: Array) -> Array[StatModifier]:
	var ModifierScript := load("res://src/definitions/stat_modifier.gd")
	var built: Array[StatModifier] = []
	for row in rows:
		var modifier: StatModifier = ModifierScript.new()
		modifier.target_stat = row[0]
		modifier.source_id = event_id
		modifier.operation = row[1]
		modifier.value = row[2]
		# Permanent until removed by source. A duration here would expire the
		# rule in the middle of the weather that asked for it.
		modifier.duration = -1.0
		built.append(modifier)
	return built
