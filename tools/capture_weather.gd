extends Node

## WEATHER-ARRIVAL HARNESS: the tell, then the weather, in one sequence.
##
##   Godot_console.exe --path <project> --fixed-fps 60 --resolution 1280x800 \
##       res://tools/capture_weather.tscn -- \
##       --out D:/somewhere/blizzard --event blizzard --frames 20 --every 60
##
## ---------------------------------------------------------------------------
## WHY THE PLAYER DOES NOT MOVE
## ---------------------------------------------------------------------------
## The briefing's rule, already paid for once: pin the camera when the capture is
## about the world rather than about the walk. A following camera turns "the
## storm arrived" into "the storm arrived AND we are looking at different
## ground", and the two are then impossible to separate by eye. Standing still
## pins the rig for free.
##
## ---------------------------------------------------------------------------
## WHY IT RUNS IN REAL TIME AND IS NOT POKED
## ---------------------------------------------------------------------------
## Everything this sequence is about LAGS. The snowfall eases its rate over six
## seconds, the lighting crossfades over eight to sixty-six, the wind crossfades
## its profile over six, and the tyre swing is a real pendulum that is still
## going after the gust that started it. A capture that forced a state would show
## a picture the weather never actually produces -- the same argument
## `capture_gust.gd` makes for setting the wind's clock rather than its strength.
##
## So the whole arc is played, at 1x, from the frame the warning begins. The one
## thing that is short-circuited is the WAIT: `--event` starts the weather now
## rather than after a random gap of up to a hundred and ten seconds.
##
## `--tell` and `--active` shorten the two phases so that a whole arc fits in a
## sequence a reviewer will actually look at. They change the DURATIONS and
## nothing else -- every ramp, crossfade and lag runs exactly as shipped.
##
## Arguments:
##   --out <prefix>     writes <prefix>-00.png, -01.png, ...   (required)
##   --event <id>       which weather to bring on (default blizzard)
##   --frames N         how many PNGs (default 20)
##   --every N          frames between shots (default 60, i.e. one a second)
##   --settle N         frames to run before the warning begins (default 30)
##   --tell <seconds>   force the warning's length (default: as authored)
##   --active <seconds> force the weather's length (default: as authored)
##   --preset <id>      the look the day is wearing underneath (default pale_day)
##   --stand x,z        where to put the player (default: wherever he starts)
##   --seed N           the weather system's RNG seed (default 20260812)
##   --no-mist 1        diagnostic A/B: keep the weather but remove its local veil

var _out := ""
var _event := "blizzard"
var _frames := 20
var _every := 60
var _settle := 30
var _tell := -1.0
var _active := -1.0
var _preset := "pale_day"
var _stand := ""
var _seed := 20260812
var _no_mist := false
var _shot := 0
var _frame := 0
var _done := false
var _begun := false
var _tyre_rest := Vector3.INF


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_event = _arg(args, "--event", "blizzard")
	_frames = int(_arg(args, "--frames", "20"))
	_every = maxi(1, int(_arg(args, "--every", "60")))
	_settle = int(_arg(args, "--settle", "30"))
	_tell = float(_arg(args, "--tell", "-1"))
	_active = float(_arg(args, "--active", "-1"))
	_preset = _arg(args, "--preset", "pale_day")
	_stand = _arg(args, "--stand", "")
	_seed = int(_arg(args, "--seed", "20260812"))
	_no_mist = _arg(args, "--no-mist", "0") == "1"
	if _out == "":
		push_error("capture_weather: --out is required")
		get_tree().quit()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame == 1:
		_at_start()
		return
	if _frame < _settle:
		return
	if (_frame - _settle) % _every != 0:
		return
	if _shot >= _frames:
		_done = true
		get_tree().quit()
		return
	_capture()
	# SHOT 00 IS THE WORLD BEFORE THE WARNING, and the warning begins on the next
	# frame. Without it the sequence has nothing to be read against: a tell is a
	# CHANGE, and the birds are on the wire in exactly one frame of it.
	if not _begun:
		_begin()


func _at_start() -> void:
	if _stand != "":
		var parts := _stand.split(",")
		if parts.size() == 2:
			var body := get_node_or_null("Main/Player") as Node3D
			if body != null:
				body.global_position = Vector3(
					float(parts[0]), body.global_position.y, float(parts[1]))
	if _preset != "":
		var lighting := get_node_or_null("Main/Lighting")
		if lighting != null:
			lighting.apply_preset(StringName(_preset))
	var sky = _service(&"snowfall")
	if sky != null and sky.has_method("settle"):
		# The day's own weather, settled, so the sequence opens on the frame the
		# run opens on rather than on six seconds of the snow filling in.
		sky.settle()
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()
	# Birds on the wire before the warning, or there is nothing for the tell to
	# flush. `CrowFlock.arrive_now()` exists for exactly this: a capture cannot
	# wait out `first_arrival_seconds` and then photograph a random number of
	# birds, because two runs would not be the same picture.
	var crows := get_node_or_null("Main/Crows")
	if crows != null and crows.has_method("arrive_now"):
		crows.random_seed = _seed
		crows.land_now()
	var tyre := get_node_or_null("Main/Farmstead/TreeA/TireSwing") as Node3D
	if tyre != null:
		_tyre_rest = tyre.global_position


func _begin() -> void:
	_begun = true
	var weather = _service(&"weather")
	if weather == null:
		push_error("capture_weather: no weather service -- is Main/Weather in the scene?")
		get_tree().quit()
		return
	weather.random_seed = _seed
	# Nothing else may be drawn on top of the one being watched.
	weather.events_per_phase = 0
	var definition = weather.definition(StringName(_event))
	if definition == null:
		push_error("capture_weather: no weather '%s' in data/weather" % _event)
		get_tree().quit()
		return
	if _tell > 0.0:
		definition.tell_duration_range = Vector2(_tell, _tell)
		weather.minimum_tell_seconds = minf(weather.minimum_tell_seconds, _tell)
	if _active > 0.0:
		definition.active_duration_range = Vector2(_active, _active)
	if _no_mist:
		definition.fog_profile = null
	if not weather.begin(StringName(_event)):
		push_error("capture_weather: '%s' refused to begin" % _event)
		get_tree().quit()


func _service(name: StringName):
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(name)


## Every number that decides whether the sequence reads, printed beside the frame
## it belongs to. The briefing's rule: when a number is supposed to describe the
## picture, check it against the picture -- and a lag is a relationship between
## two columns over time, invisible in any single frame.
func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "%s-%02d.png" % [_out, _shot]
	image.save_png(path)
	var line := "capture_weather: %s" % path
	var weather = _service(&"weather")
	if weather != null:
		line += "  %-6s" % String(weather.phase())
		if weather.has_method("phase_elapsed") and weather.has_method("phase_duration"):
			line += " t=%.2f/%.2f" % [weather.phase_elapsed(), weather.phase_duration()]
		line += " tell=%.2f" % weather.tell_progress()
		line += " in=%5.1fs" % weather.seconds_until_arrival()
		line += " intensity=%.3f" % weather.intensity()
		line += " vis=%.2f" % weather.visibility()
	var sky = _service(&"snowfall")
	if sky != null:
		line += "  snow=%.3f" % sky.snowfall_rate()
	var wind = _service(&"wind")
	if wind != null:
		line += "  wind=%.3f" % wind.strength()
		line += "/%.2fx" % wind.gale_multiplier()
		line += " head=%6.1f" % wind.heading_degrees()
		var profile = wind.active_profile()
		if profile != null:
			line += " %-11s" % String(profile.id)
	var lighting := get_node_or_null("Main/Lighting")
	if lighting != null:
		var look = lighting.active_preset()
		if look != null:
			line += "  look=%-10s" % String(look.id)
		line += " exp=%.2f" % look.tonemap_exposure
		line += " depth_fog=%.2f" % look.fog_density
		var environment: Environment = lighting.environment
		if environment != null:
			line += " volume=%s/%.5f" % [
				str(environment.volumetric_fog_enabled),
				environment.volumetric_fog_density,
			]
	var drift := get_node_or_null("Main/Wind/Spindrift")
	if drift != null:
		line += "  spindrift=%.3f" % drift.amount_ratio
	var accent = _service(&"weather_vfx")
	if accent != null and accent.has_method("density"):
		line += " vfx=%.3f" % accent.density()
	var mist := get_node_or_null("Main/WeatherSnowFog")
	if mist != null and mist.has_method("density"):
		line += " mist=%s/%.5f" % [str(mist.visible), mist.density()]
		if mist.has_method("active_profile"):
			var mist_profile = mist.active_profile()
			if mist_profile != null:
				line += "/%.5f" % mist_profile.peak_density
		if mist.has_method("advection_offset"):
			var mist_offset: Vector3 = mist.advection_offset()
			line += " drift=(%.2f,%.2f)" % [mist_offset.x, mist_offset.z]
	var crows := get_node_or_null("Main/Crows")
	if crows != null and crows.has_method("perched_count"):
		# Perched over alive. The pair is the cue: 4/4 is a wire with birds on it,
		# 0/4 is a wire that has just emptied and four birds still climbing, 0/0 is
		# a sky they have gone from. One number could not say which.
		line += "  crows=%d/%d" % [crows.perched_count(), crows.crow_count()]
	var tyre := get_node_or_null("Main/Farmstead/TreeA/TireSwing") as Node3D
	if tyre != null:
		line += "  tyre=%5.2fdeg" % rad_to_deg(Vector2(tyre.rotation.z, tyre.rotation.x).length())
	print(line)
	_shot += 1
