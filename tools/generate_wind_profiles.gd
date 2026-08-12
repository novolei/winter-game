extends SceneTree

## Generator for res://data/weather/wind_*.tres.
## Run: godot --headless --path <project> --script res://tools/generate_wind_profiles.gd
##
## Two files, and the second one is the point. `wind_valley` is the weather the
## game opens on; `wind_gale` is a whole different wind, and it exists to prove
## binding rule 4 rather than because anything drives it yet. Bringing the gale
## is `WindSystem.set_profile(load(".../wind_gale.tres"))` and no `.gd` change at
## all.
##
## Content `.tres` are generated rather than hand-authored (briefing constraint
## 7): typed-array and float serialisation are the engine's business, not a
## thing to write out by hand.

const OUT_DIR := "res://data/weather"

## ---------------------------------------------------------------------------
## THE VALLEY -- the wind the game has when nothing is happening
## ---------------------------------------------------------------------------
## Judged by what moves, not by the number. The whole tuning rests on one claim:
## a weak wind that gusts reads windier than a strong wind that does not. So the
## floor is nearly nothing (0.06), the gust adds a third, and the squall -- once
## in about a minute and a quarter -- takes it most of the way up.
##
## Heading and magnitude are Snowfall.gale_wind, kept exactly. See
## WindProfile.gale_metres for why that is a reconciliation rather than a choice.
const VALLEY := {
	"id": &"wind_valley",
	"display_name": "Valley wind",
	"prevailing_degrees": 17.354,
	"wander_degrees": 24.0,
	"wander_seconds": 47.0,
	"gust_veer_degrees": 13.0,
	"base_strength": 0.06,
	"gust_depth": 0.34,
	"gust_seconds": 9.0,
	"gust_sharpness": 2.2,
	"squall_gain": 0.44,
	"squall_seconds": 13.0,
	"squall_attack": 0.22,
	"squall_release": 0.46,
	"squall_interval_seconds": 76.0,
	"squall_interval_jitter": 0.55,
	"gale_metres": 1.6763055,
	"gust_threshold": 0.30,
	"gust_hysteresis": 0.09,
	"lull_threshold": 0.12,
	"lull_hysteresis": 0.05,
	"direction_report_degrees": 18.0,
}

## ---------------------------------------------------------------------------
## THE GALE -- day 7, and the proof that a weather event needs no code
## ---------------------------------------------------------------------------
## Not merely "the same wind, louder". The floor rises, the gusts come three
## times as often, the lulls almost close up (sharpness down to 1.4), squalls
## come four times as often and land near the top. That is what makes it a
## different weather rather than a different volume.
##
## The heading wanders further and veers harder, which is GDD section 7's
## 风向突变 becoming plausible inside ordinary weather rather than only as a
## scripted event.
const GALE := {
	"id": &"wind_gale",
	"display_name": "Gale",
	"prevailing_degrees": 17.354,
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
	"gale_metres": 1.6763055,
	"gust_threshold": 0.70,
	"gust_hysteresis": 0.09,
	"lull_threshold": 0.32,
	"lull_hysteresis": 0.05,
	"direction_report_degrees": 18.0,
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failed := false
	for spec in [VALLEY, GALE]:
		if not _write(spec):
			failed = true
	quit(1 if failed else 0)


func _write(spec: Dictionary) -> bool:
	var ProfileScript := load("res://src/definitions/wind_profile.gd")
	# Annotated, not `var x =`: an untyped local is a Variant, and a typed setter
	# handed what the compiler then produces aborts the function with no message
	# (briefing trap 4).
	var profile: WindProfile = ProfileScript.new()
	for key in spec:
		profile.set(key, spec[key])
	var path := "%s/%s.tres" % [OUT_DIR, spec["id"]]
	var error := ResourceSaver.save(profile, path)
	print("generate_wind_profiles: %s -> %d" % [path, error])
	return error == OK
