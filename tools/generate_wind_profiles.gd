extends SceneTree

## Generator for res://data/weather/wind_*.tres and wind_map.tres.
## Run: godot --headless --path <project> --script res://tools/generate_wind_profiles.gd
##
## ---------------------------------------------------------------------------
## FIVE WINDS, ONE PER KIND OF WEATHER
## ---------------------------------------------------------------------------
## Not one wind at five volumes. A whiteout is not a pale day with more snow --
## GDD section 7's weather kinds differ from each other in wind and snow
## TOGETHER, and 寒流's entire tell is that the air goes still. So the profiles
## differ in their gust STRUCTURE, not only in their level: the still night's
## gusts are slow and shallow and it has no squalls at all, the gale's come three
## times as often with the lulls nearly closed up.
##
## Mapped onto the six lighting presets, which already carry the weather's
## identity -- `Snowfall.storm_by_preset` reads them for exactly the same reason.
##
##   flat, sunrise  -> calm     the technical look, and the twenty minutes of warm
##   pale_day       -> valley   day one; the wind the game opens on
##   nightfall      -> rising   the evening picking up
##   deep_night     -> still    GDD section 8's dangerous quiet
##   whiteout       -> gale     day seven
##
## `deep_night` being the CALMEST is a decision, not an omission: 风大 → 足迹速消
## → 你安全；风停 → 足迹留存 → 你被跟上. The night that leaves your trail intact
## is the night something follows it.
##
## Content `.tres` are generated rather than hand-authored (briefing constraint
## 7): typed-array serialisation is the engine's business, not a thing to write
## out by hand.

const OUT_DIR := "res://data/weather"

## Shared by every profile. The heading is `Snowfall.gale_wind`, art-directed
## against the camera's fixed -35 degree yaw so the snow crosses the frame from
## the left; the magnitude is that vector's length, kept exactly. See
## `WindProfile.gale_metres` for why that is a reconciliation and not a choice.
const PREVAILING := 17.354
const GALE_METRES := 1.6763055

## ---------------------------------------------------------------------------
## STILL -- deep_night. The dangerous one.
## ---------------------------------------------------------------------------
## Slow, shallow, no squalls. Mean around 0.05, so `TrackMask`'s gale term is
## effectively off and a footprint keeps most of the eighty seconds its still-air
## decay gives it. The tyre swing barely moves and the trees do not move at all,
## which is the point: the world going quiet is a thing the player should notice.
const STILL := {
	"id": &"wind_still",
	"display_name": "Still night",
	"presets": ["deep_night"],
	"wander_degrees": 14.0,
	"wander_seconds": 71.0,
	"gust_veer_degrees": 6.0,
	"base_strength": 0.02,
	"gust_depth": 0.09,
	"gust_seconds": 14.0,
	"gust_sharpness": 3.0,
	"squall_gain": 0.0,
	"squall_seconds": 13.0,
	"squall_interval_seconds": 200.0,
	"gust_threshold": 0.075,
	"lull_threshold": 0.030,
	"lull_hysteresis": 0.02,
}

## ---------------------------------------------------------------------------
## CALM -- flat and sunrise. The moving window.
## ---------------------------------------------------------------------------
## GDD section 7's 短暂放晴 is the twenty minutes a player spends travelling, so
## the weather gets out of the way. Occasional small squalls so it is not simply
## a quieter still.
const CALM := {
	"id": &"wind_calm",
	"display_name": "Calm",
	"presets": ["flat", "sunrise"],
	"wander_degrees": 20.0,
	"wander_seconds": 58.0,
	"gust_veer_degrees": 10.0,
	"base_strength": 0.04,
	"gust_depth": 0.18,
	"gust_seconds": 11.0,
	"gust_sharpness": 2.5,
	"squall_gain": 0.18,
	"squall_seconds": 11.0,
	"squall_interval_seconds": 110.0,
	"gust_threshold": 0.16,
	"lull_threshold": 0.055,
	"lull_hysteresis": 0.03,
}

## ---------------------------------------------------------------------------
## VALLEY -- pale_day. The wind the game opens on.
## ---------------------------------------------------------------------------
## The tuning the whole system was judged against: floor nearly nothing, a gust
## adding a third, a squall once in about a minute and a quarter taking it most
## of the way up. A weak wind that gusts reads windier than a strong wind that
## does not, and this profile is the demonstration.
const VALLEY := {
	"id": &"wind_valley",
	"display_name": "Valley wind",
	"presets": ["pale_day"],
	"wander_degrees": 24.0,
	"wander_seconds": 47.0,
	"gust_veer_degrees": 13.0,
	"base_strength": 0.06,
	"gust_depth": 0.34,
	"gust_seconds": 9.0,
	"gust_sharpness": 2.2,
	"squall_gain": 0.44,
	"squall_seconds": 13.0,
	"squall_interval_seconds": 76.0,
	"gust_threshold": 0.30,
	"lull_threshold": 0.12,
}

## ---------------------------------------------------------------------------
## RISING -- nightfall. The deadline arriving.
## ---------------------------------------------------------------------------
## Between the valley and the gale, and faster than either at the top end: gusts
## every six and a half seconds and squalls every forty-eight. GDD section 4
## makes nightfall the literal deadline, and the weather turning is the tell.
const RISING := {
	"id": &"wind_rising",
	"display_name": "Rising",
	"presets": ["nightfall"],
	"wander_degrees": 31.0,
	"wander_seconds": 39.0,
	"gust_veer_degrees": 17.0,
	"base_strength": 0.13,
	"gust_depth": 0.30,
	"gust_seconds": 6.5,
	"gust_sharpness": 1.9,
	"squall_gain": 0.34,
	"squall_seconds": 11.0,
	"squall_interval_seconds": 48.0,
	"gust_threshold": 0.34,
	"lull_threshold": 0.17,
}

## ---------------------------------------------------------------------------
## GALE -- whiteout. Day seven.
## ---------------------------------------------------------------------------
## Not "the same wind, louder". The floor rises to a fifth of full, gusts come
## three times as often, and the lulls almost close up (sharpness 1.4). The
## heading wanders further and veers harder, which makes GDD section 7's 风向突变
## plausible inside ordinary weather rather than only as a scripted event.
const GALE := {
	"id": &"wind_gale",
	"display_name": "Gale",
	"presets": ["whiteout"],
	"wander_degrees": 38.0,
	"wander_seconds": 31.0,
	"gust_veer_degrees": 22.0,
	"base_strength": 0.28,
	"gust_depth": 0.40,
	"gust_seconds": 3.4,
	"gust_sharpness": 1.4,
	"squall_gain": 0.32,
	"squall_seconds": 9.0,
	"squall_attack": 0.14,
	"squall_release": 0.38,
	"squall_interval_seconds": 19.0,
	"squall_interval_jitter": 0.45,
	"gust_threshold": 0.70,
	"lull_threshold": 0.32,
}

const ALL := [STILL, CALM, VALLEY, RISING, GALE]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failed := false
	# Annotated, not `var x = []`: an untyped local is a Variant, and the typed
	# setter on WindMap.profiles rejects what the compiler then hands it, aborting
	# the function with no message at all (briefing trap 4).
	var written: Array[WindProfile] = []
	for spec in ALL:
		var profile := _write(spec)
		if profile == null:
			failed = true
		else:
			written.append(profile)
	if not _write_map(written):
		failed = true
	quit(1 if failed else 0)


func _write(spec: Dictionary) -> WindProfile:
	var ProfileScript := load("res://src/definitions/wind_profile.gd")
	var profile: WindProfile = ProfileScript.new()
	profile.prevailing_degrees = PREVAILING
	profile.gale_metres = GALE_METRES
	var presets: Array[StringName] = []
	for key in spec:
		if key == "presets":
			for preset in spec[key]:
				presets.append(StringName(preset))
			continue
		profile.set(key, spec[key])
	profile.presets = presets
	var path := "%s/%s.tres" % [OUT_DIR, spec["id"]]
	var error := ResourceSaver.save(profile, path)
	print("generate_wind_profiles: %s -> %d" % [path, error])
	if error != OK:
		return null
	# RELOADED FROM DISK, deliberately. The map has to reference these by PATH so
	# that saving it writes ext_resources rather than inlining five copies -- and
	# a resource only has a path once it has been saved and loaded back.
	return load(path)


func _write_map(profiles: Array[WindProfile]) -> bool:
	var MapScript := load("res://src/definitions/wind_map.gd")
	var map: WindMap = MapScript.new()
	map.profiles = profiles
	map.default_id = &"wind_valley"
	var path := "%s/wind_map.tres" % OUT_DIR
	var error := ResourceSaver.save(map, path)
	print("generate_wind_profiles: %s -> %d" % [path, error])
	return error == OK
