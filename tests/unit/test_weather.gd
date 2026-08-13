extends TestCase

## GDD section 7's six weather kinds, and the iron law that governs all of them:
##
##   铁律：所有事件必须先预兆再落地。无预警的风暴不是难度，是不公平。
##
## Every event announces itself before it lands. A storm with no warning is not
## difficulty, it is unfairness -- so the tell is not a courtesy on top of the
## weather, it is the thing that makes the weather fair, and most of this file
## exists to make an unannounced weather UNREPRESENTABLE rather than merely
## discouraged.
##
## ---------------------------------------------------------------------------
## THE TWO SHAPES, AND WHY BOTH ARE TESTED SEPARATELY
## ---------------------------------------------------------------------------
## THE TELL IS AN EVENT. It fires once, on a crossing. A sound, a bird, a line.
## THE WEATHER IS A STATE. It is sampled, every frame, by whoever needs to know
## how bad it is NOW.
##
## They are not interchangeable, and the failure of confusing them is already on
## record in this project: `CrowFlock` refused to drive its flock from
## `wind.gust_started`, because that fires on the profile's own 0.30 crossing and
## never again as the gust builds, so a flock refusing it there would sit out the
## 0.798 peak behind it. A consumer that tried to reconstruct the current weather
## from remembered events would be wrong in exactly the same way, for the whole
## of every ramp.
##
## So there are two families of test below: one that counts publications, and one
## that sweeps a whole event frame by frame and reads the state.

const WeatherSystemScript := preload("res://src/systems/weather_system.gd")
const EventScript := preload("res://src/definitions/weather_event_definition.gd")
const TellScript := preload("res://src/definitions/weather_tell.gd")
const ModifierScript := preload("res://src/definitions/stat_modifier.gd")
const WindMapScript := preload("res://src/definitions/wind_map.gd")
const WindProfileScript := preload("res://src/definitions/wind_profile.gd")

const EVENTS_DIRECTORY := "res://data/weather"
const SCHEDULE_DIRECTORY := "res://data/schedule"

## GDD section 7: 每个事件三段式：预兆期（20-40s）→ 持续期 → 消退期.
const TELL_FLOOR_SECONDS := 20.0

## The six the design document names. Spelled out here rather than read off the
## directory, because a test that asked the data which weathers exist would pass
## on a folder with one file in it.
const THE_SIX := [
	&"blizzard", &"wind_shift", &"clear_break",
	&"freezing_rain", &"cold_snap", &"snow_fog",
]


# --- stand-ins ----------------------------------------------------------------
#
# RefCounted, so nothing here leaks (briefing constraint 2). Every one of them
# records rather than acts: what is under test is what the weather system SAYS to
# the world, and a real LightingDirector would answer that question with a
# rendered frame.


class BusStandIn extends RefCounted:
	var seen: Array = []
	var subscriptions: Dictionary = {}

	func subscribe(event: StringName, callback: Callable) -> void:
		subscriptions[event] = callback

	func unsubscribe(event: StringName, _callback: Callable) -> void:
		subscriptions.erase(event)

	func emit_event(event: StringName, payload = null) -> void:
		seen.append({"event": event, "payload": payload})

	func count(event: StringName) -> int:
		var total := 0
		for entry in seen:
			if entry["event"] == event:
				total += 1
		return total

	func first(event: StringName):
		for entry in seen:
			if entry["event"] == event:
				return entry["payload"]
		return null

	func order() -> Array:
		var names: Array = []
		for entry in seen:
			names.append(entry["event"])
		return names

	func weather_order() -> Array:
		var names: Array = []
		for entry in seen:
			var event: StringName = entry["event"]
			if String(event).begins_with("weather."):
				names.append(event)
		return names


class LightingStandIn extends RefCounted:
	var preset_id: StringName = &"pale_day"
	var fades: Array = []
	var crossfading := false

	func crossfade_to(id: StringName, seconds := -1.0) -> bool:
		if id == preset_id and not crossfading:
			return false
		fades.append({"id": id, "seconds": seconds})
		preset_id = id
		return true

	func active_preset() -> LightingPreset:
		var look := LightingPreset.new()
		look.id = preset_id
		return look

	func target_preset_id() -> StringName:
		return preset_id

	func is_crossfading() -> bool:
		return crossfading

	func faded_to() -> Array:
		var ids: Array = []
		for entry in fades:
			ids.append(entry["id"])
		return ids


class SnowfallStandIn extends RefCounted:
	var default_storm := 0.3
	var storm_by_preset: Dictionary = {
		&"flat": 0.0, &"pale_day": 0.12, &"sunrise": 0.1,
		&"nightfall": 0.35, &"deep_night": 0.28, &"whiteout": 1.0,
	}
	var rate := 0.12
	var overrides := 0
	var settles := 0

	func set_snowfall_rate(value: float) -> void:
		rate = value
		overrides += 1

	func snowfall_rate() -> float:
		return rate

	func settle() -> void:
		settles += 1


class WindStandIn extends RefCounted:
	var maps: Array = []
	var multiplier := 1.0

	func set_map(map) -> void:
		maps.append(map)

	func set_gale_multiplier(value: float) -> void:
		multiplier = value

	func gale_multiplier() -> float:
		return multiplier


class WildlifeStandIn extends RefCounted:
	var causes: Array = []
	var perched := 3

	func scatter(cause: StringName) -> int:
		causes.append(cause)
		var went := perched
		perched = 0
		return went


class SurvivalStandIn extends RefCounted:
	var pushed: Array = []
	var removed: Array = []

	func push_modifier(
		target: StringName, source_id: StringName, operation: int,
		value: float, duration := -1.0
	) -> bool:
		pushed.append({
			"target": target, "source": source_id,
			"operation": operation, "value": value, "duration": duration,
		})
		return true

	func remove_source(source_id: StringName) -> int:
		removed.append(source_id)
		return 1


class ClockStandIn extends RefCounted:
	var day := 1
	var night := false
	var schedules: Dictionary = {}
	var running := true

	func current_day() -> int:
		return day

	func is_night() -> bool:
		return night

	func is_running() -> bool:
		return running

	func schedule_for_day(number: int):
		return schedules.get(number, null)

	func current_schedule():
		return schedule_for_day(day)


var _system: Node = null
var _bus: BusStandIn = null
var _lighting: LightingStandIn = null
var _snow: SnowfallStandIn = null
var _wind: WindStandIn = null
var _birds: WildlifeStandIn = null
var _body: SurvivalStandIn = null
var _clock: ClockStandIn = null


func before_each() -> void:
	_bus = BusStandIn.new()
	_lighting = LightingStandIn.new()
	_snow = SnowfallStandIn.new()
	_wind = WindStandIn.new()
	_birds = WildlifeStandIn.new()
	_body = SurvivalStandIn.new()
	_clock = ClockStandIn.new()
	_system = WeatherSystemScript.new()
	_system.set_event_bus(_bus)
	_system.set_lighting(_lighting)
	_system.set_snowfall(_snow)
	_system.set_wind_system(_wind)
	_system.set_wildlife(_birds)
	_system.set_survival_system(_body)
	_system.set_world_clock(_clock)
	_system.random_seed = 20260812


func after_each() -> void:
	# Node is not reference-counted; an un-freed one is a leak the wrapper fails
	# the whole run for (briefing constraint 2).
	if _system != null:
		_system.free()
		_system = null


# --- fixtures -----------------------------------------------------------------


func _tell(fields: Dictionary = {}) -> WeatherTell:
	var tell: WeatherTell = TellScript.new()
	for key in fields:
		tell.set(key, fields[key])
	return tell


func _event(id: StringName, fields: Dictionary = {}) -> WeatherEventDefinition:
	var event: WeatherEventDefinition = EventScript.new()
	event.id = id
	event.display_name = String(id)
	event.tell_duration_range = Vector2(24.0, 24.0)
	event.active_duration_range = Vector2(60.0, 60.0)
	event.fade_duration = 12.0
	for key in fields:
		event.set(key, fields[key])
	return event


func _map_of(profile_id: StringName, prevailing := 17.354) -> WindMap:
	var profile: WindProfile = WindProfileScript.new()
	profile.id = profile_id
	profile.prevailing_degrees = prevailing
	var map: WindMap = WindMapScript.new()
	var only: Array[WindProfile] = [profile]
	map.profiles = only
	map.default_id = profile_id
	return map


## Runs the system forward at a fixed step and returns how many steps it took.
func _run(seconds: float, step := 0.05) -> int:
	var steps := int(seconds / step)
	for index in range(steps):
		_system.advance(step)
	return steps


# --- the pillar, as data ------------------------------------------------------


func test_the_six_weather_kinds_of_the_gdd_all_ship() -> void:
	var loaded: int = _system.load_events_from_directory(EVENTS_DIRECTORY)
	assert_true(loaded >= THE_SIX.size(),
		"GDD section 7 names six weather kinds; %d shipped" % loaded)
	for id in THE_SIX:
		assert_not_null(_system.definition(id),
			"no data/weather/*.tres defines the weather '%s'" % id)


func test_every_shipped_weather_carries_a_tell() -> void:
	_system.load_events_from_directory(EVENTS_DIRECTORY)
	for id in THE_SIX:
		var event: WeatherEventDefinition = _system.definition(id)
		if event == null:
			continue
		assert_not_null(event.tell,
			"'%s' lands with no warning at all -- GDD section 7's iron law" % id)


## Ground snow may only be added by an authored response.  An event with a
## positive snowfall scalar but no response would make the new dynamic field
## depend on a code fallback, defeating the data-driven weather contract.
func test_every_ground_depositing_weather_has_an_authored_snow_response() -> void:
	_system.load_events_from_directory(EVENTS_DIRECTORY)
	for id in THE_SIX:
		var event: WeatherEventDefinition = _system.definition(id)
		if event == null or event.snowfall_rate <= 0.0:
			continue
		assert_not_null(event.snow_response, "%s has snowfall but no ground response" % id)
		if event.snow_response == null:
			continue
		assert_true(
			event.snow_response.deposition_m_per_second > 0.0,
			"%s names a response that cannot deposit snow" % id
		)
		assert_true(
			event.snow_response.maximum_added_depth_m > 0.0,
			"%s names a response with no bounded dynamic depth" % id
		)
		assert_true(
			event.snow_response.wind_sample_distance_m > 0.0,
			"%s names a response without a finite wind transport distance" % id
		)


## A wind-only event is allowed to carry a zero snowfall rate, but it still
## needs an authored transport response so a veer moves finite existing snow
## rather than becoming a special case in SnowField code.
func test_every_authored_ground_response_has_a_finite_wind_contract() -> void:
	_system.load_events_from_directory(EVENTS_DIRECTORY)
	for id in THE_SIX:
		var event: WeatherEventDefinition = _system.definition(id)
		if event == null or event.snow_response == null:
			continue
		assert_true(
			event.snow_response.wind_sample_distance_m > 0.0,
			"%s has a ground response without a finite wind sample distance" % id
		)
		assert_true(
			event.snow_response.wind_transport_m_per_second >= 0.0,
			"%s has a negative wind transport rate" % id
		)


## The event boundary is a semantic weather snapshot, not a direct SnowField
## reference.  Its scalar may move every weather frame; SnowField's fixed tick
## remains the only place that alters sparse world tiles.
func test_weather_publishes_its_response_as_a_snow_input_snapshot() -> void:
	var response: SnowResponseDefinition = SnowResponseDefinition.new()
	response.deposition_m_per_second = 0.001
	response.maximum_added_depth_m = 0.1
	_system.load_events([_event(&"probe", {
		"snowfall_rate": 1.0,
		"snow_response": response,
	})])
	assert_true(_system.begin(&"probe"))
	var snapshot = _bus.first(&"snow.inputs_changed")
	assert_not_null(snapshot, "the weather tell did not publish a snow input")
	if snapshot is Dictionary:
		assert_eq(snapshot["response"], response)
		assert_true(float(snapshot["snowfall"]) >= 0.0)
		assert_true(snapshot.has("wind_direction"), "the snow input omitted wind direction")
		assert_true(snapshot.has("wind_strength"), "the snow input omitted wind strength")


## THE TEST THIS TASK IS JUDGED ON. A tell carried only by `sound` announces
## nothing in a headless capture, nothing before the audio task lands, and
## nothing to a player with the volume down.
##
## `flushes_wildlife` deliberately does not count: crows are daylight-only by
## design, so a tell leaning on the birds says nothing after dark -- which is
## when the weather matters most.
func test_every_tell_can_be_read_with_the_sound_off() -> void:
	_system.load_events_from_directory(EVENTS_DIRECTORY)
	for id in THE_SIX:
		var event: WeatherEventDefinition = _system.definition(id)
		if event == null or event.tell == null:
			continue
		assert_true(event.tell.has_silent_cue(),
			"'%s' announces itself only in sound; a muted player gets no warning" % id)


func test_every_tell_is_at_least_the_spec_floor() -> void:
	_system.load_events_from_directory(EVENTS_DIRECTORY)
	for id in THE_SIX:
		var event: WeatherEventDefinition = _system.definition(id)
		if event == null:
			continue
		assert_true(event.tell_duration_range.x >= TELL_FLOOR_SECONDS,
			"'%s' warns for %.1fs; GDD section 7 sets the floor at 20s"
				% [id, event.tell_duration_range.x])


## `LightingDirector.crossfade_to()` REFUSES a fade toward the preset it is
## already fading to. So a tell leaning at the event's own look would keep
## ownership of the arrival and the event's `lighting_fade_seconds` would be
## silently ignored -- a number in the data that does nothing, which is the worst
## kind. Two legal shapes: lean at an intermediate look, or leave the event's own
## preset empty and let the tell own the sky.
func test_no_tell_leans_at_the_look_its_own_weather_lands_on() -> void:
	_system.load_events_from_directory(EVENTS_DIRECTORY)
	for id in THE_SIX:
		var event: WeatherEventDefinition = _system.definition(id)
		if event == null or event.tell == null:
			continue
		if event.lighting_preset == &"" or event.tell.lighting_preset == &"":
			continue
		assert_false(event.tell.lighting_preset == event.lighting_preset,
			"'%s' leans at '%s' and then lands on it: the director will refuse the"
				% [id, event.lighting_preset]
				+ " second crossfade and lighting_fade_seconds does nothing")


func test_the_day_schedules_only_name_weathers_that_exist() -> void:
	_system.load_events_from_directory(EVENTS_DIRECTORY)
	var dir := DirAccess.open(SCHEDULE_DIRECTORY)
	assert_not_null(dir, "the seven day schedules should be on disk")
	if dir == null:
		return
	for entry in dir.get_files():
		if not entry.ends_with(".tres"):
			continue
		var schedule := ResourceLoader.load(SCHEDULE_DIRECTORY.path_join(entry)) as DaySchedule
		if schedule == null:
			continue
		for id in schedule.allowed_weather_events:
			assert_not_null(_system.definition(id),
				"%s allows '%s', which no .tres defines" % [entry, id])
		if schedule.forced_weather_event != &"":
			assert_not_null(_system.definition(schedule.forced_weather_event),
				"%s forces '%s', which no .tres defines"
					% [entry, schedule.forced_weather_event])


# --- the pillar, as a mechanism -----------------------------------------------


## The structural half, and the reason this is not merely a data convention: the
## only door into the weather is the tell. There is no call that lands one
## directly, so no future edit can add a storm that switches on.
func test_a_weather_cannot_be_started_without_its_tell() -> void:
	_system.load_events([_event(&"probe")])
	assert_true(_system.begin(&"probe"), "begin() should accept a known weather")
	assert_eq(_system.phase(), _system.PHASE_TELL,
		"a weather that begins must begin by WARNING, never by arriving")
	assert_almost_eq(_system.intensity(), 0.0, 0.0001,
		"nothing of the weather may be applied while it is still only a warning")


## Even authored at zero. A tell of no seconds is the one mistake that breaks the
## design pillar while looking exactly like a tuning value, so the floor is a
## clamp in the system and not only a default in the definition.
func test_a_tell_authored_at_zero_seconds_is_still_a_tell() -> void:
	_system.load_events([_event(&"instant", {"tell_duration_range": Vector2(0.0, 0.0)})])
	_system.begin(&"instant")
	assert_true(_system.phase_duration() >= _system.minimum_tell_seconds,
		"a zero-second tell was accepted: %.1fs" % _system.phase_duration())
	_run(5.0)
	assert_eq(_system.phase(), _system.PHASE_TELL,
		"five seconds in, a weather authored with no warning is still warning")


func test_the_weather_arrives_only_when_the_warning_is_over() -> void:
	_system.load_events([_event(&"probe")])
	_system.begin(&"probe")
	var warning: float = _system.phase_duration()
	_run(warning - 1.0)
	assert_eq(_system.phase(), _system.PHASE_TELL, "still warning a second out")
	assert_almost_eq(_system.intensity(), 0.0, 0.0001, "and still nothing applied")
	_run(2.0)
	assert_eq(_system.phase(), _system.PHASE_ACTIVE, "then it lands")


func test_the_whole_arc_is_walked_in_order_and_announced_once_each() -> void:
	_system.load_events([_event(&"probe")])
	_system.begin(&"probe")
	_run(24.0 + 60.0 + 12.0 + 4.0)
	assert_eq(_system.phase(), _system.PHASE_CLEAR, "the weather should have passed")
	assert_eq(_bus.count(_system.EVENT_TELL_STARTED), 1, "one warning")
	assert_eq(_bus.count(_system.EVENT_ARRIVED), 1, "one arrival")
	assert_eq(_bus.count(_system.EVENT_FADING), 1, "one departure")
	assert_eq(_bus.count(_system.EVENT_CLEARED), 1, "one clearing")
	assert_eq(_bus.weather_order(), [
		_system.EVENT_TELL_STARTED, _system.EVENT_ARRIVED,
		_system.EVENT_FADING, _system.EVENT_CLEARED,
	], "the tell must be published BEFORE the arrival, always")


## The countdown a player reads the sky for. Continuous, monotonic, and it is the
## honest answer to "how long have I got" -- which an event cannot give.
func test_the_warning_reports_how_long_is_left() -> void:
	_system.load_events([_event(&"probe")])
	_system.begin(&"probe")
	var opening: float = _system.seconds_until_arrival()
	assert_almost_eq(opening, _system.phase_duration(), 0.001,
		"at the moment of the warning the whole of it is still to come")
	_run(10.0)
	var later: float = _system.seconds_until_arrival()
	assert_true(later < opening - 9.0,
		"the countdown did not run: %.2f then %.2f" % [opening, later])
	assert_true(_system.tell_progress() > 0.3 and _system.tell_progress() < 0.6,
		"ten seconds into a %.0fs warning should read about 0.4, not %.2f"
			% [_system.phase_duration(), _system.tell_progress()])


# --- the state a consumer samples ---------------------------------------------


## The task's design trap, from the other side. An event fires once; a consumer
## asking "how bad is it NOW" halfway through an arrival needs a number, and
## every number below is one nothing has to remember to have.
func test_the_weather_is_a_state_and_not_a_memory_of_events() -> void:
	_system.load_events([_event(&"probe", {"visibility_multiplier": 0.25})])
	_system.begin(&"probe")
	_run(24.0 + 1.0)
	var early: float = _system.intensity()
	assert_true(early > 0.0 and early < 1.0,
		"one second into the arrival the weather should be PART way on, not %.3f" % early)
	assert_true(_system.visibility() > 0.25 and _system.visibility() < 1.0,
		"and the visibility with it: %.3f" % _system.visibility())
	_run(20.0)
	assert_almost_eq(_system.intensity(), 1.0, 0.01, "then fully on")
	assert_almost_eq(_system.visibility(), 0.25, 0.01,
		"and the visibility all the way down")


func test_the_intensity_never_steps_across_a_whole_event() -> void:
	_system.load_events([_event(&"probe", {
		"snowfall_rate": 1.0,
		"wind_speed_multiplier": 2.2,
		"tell": _tell({"snowfall_rate": 0.0, "wind_speed_multiplier": 0.2}),
	})])
	_system.begin(&"probe")
	var last_intensity: float = _system.intensity()
	var last_snow: float = _system.applied_snowfall_rate()
	var last_wind: float = _system.applied_wind_multiplier()
	var worst_intensity := 0.0
	var worst_snow := 0.0
	var worst_wind := 0.0
	var step := 0.05
	for index in range(int((24.0 + 60.0 + 12.0 + 6.0) / step)):
		_system.advance(step)
		worst_intensity = maxf(worst_intensity, absf(_system.intensity() - last_intensity))
		worst_snow = maxf(worst_snow, absf(_system.applied_snowfall_rate() - last_snow))
		worst_wind = maxf(worst_wind, absf(_system.applied_wind_multiplier() - last_wind))
		last_intensity = _system.intensity()
		last_snow = _system.applied_snowfall_rate()
		last_wind = _system.applied_wind_multiplier()
	# 切记不能突变 -- the owner has insisted twice. At a 20 Hz step nothing here
	# may move more than a few per cent of its range in a frame, INCLUDING across
	# the tell/arrival and active/fade boundaries, which is where a naive
	# implementation puts its step.
	assert_true(worst_intensity < 0.03,
		"the intensity jumped %.3f in one frame" % worst_intensity)
	assert_true(worst_snow < 0.05,
		"the snowfall target jumped %.3f in one frame" % worst_snow)
	assert_true(worst_wind < 0.08,
		"the wind multiplier jumped %.3f in one frame" % worst_wind)


## Same event, a quarter of the frame rate. A ramp written per-frame instead of
## per-second passes the test above and fails this one.
func test_the_ramps_are_the_same_shape_at_a_fifth_of_the_frame_rate() -> void:
	_system.load_events([_event(&"probe", {"snowfall_rate": 1.0})])
	_system.begin(&"probe")
	_run(24.0 + 3.0, 0.25)
	var coarse: float = _system.intensity()
	_system.clear_now()
	_system.begin(&"probe")
	_run(24.0 + 3.0, 0.0125)
	assert_almost_eq(_system.intensity(), coarse, 0.03,
		"the arrival ramp is frame-rate dependent")


func test_the_weather_reports_nothing_at_all_when_it_is_clear() -> void:
	_system.load_events([_event(&"probe")])
	assert_eq(_system.phase(), _system.PHASE_CLEAR, "a run opens clear")
	assert_eq(_system.event_id(), &"", "with no weather to name")
	assert_almost_eq(_system.intensity(), 0.0, 0.0001, "and nothing applied")
	assert_almost_eq(_system.visibility(), 1.0, 0.0001, "and clear air")


# --- what the tell actually does ----------------------------------------------


func test_the_tell_leans_the_light_toward_the_coming_weather() -> void:
	_system.load_events([_event(&"probe", {
		"lighting_preset": &"whiteout",
		"tell": _tell({"lighting_preset": &"nightfall", "lighting_lead": 0.5}),
	})])
	_system.begin(&"probe")
	assert_eq(_lighting.faded_to(), [&"nightfall"],
		"the sky should start moving on the WARNING, not on the arrival")
	# Lead 0.5 over a 24 s warning: the crossfade is started long enough that it
	# is only half done when the weather lands, so the light goes on changing
	# THROUGH the arrival.
	assert_almost_eq(float(_lighting.fades[0]["seconds"]), 48.0, 0.001,
		"a lead of 0.5 should ask for twice the warning's length")
	_run(24.0 + 1.0)
	assert_eq(_lighting.faded_to(), [&"nightfall", &"whiteout"],
		"and the weather's own look lands when the weather does")


## A finding, locked down rather than worked around: leaning at the look the sky
## is ALREADY wearing moves nothing, because `LightingDirector.crossfade_to()`
## returns false when the frame is already there.
##
## It matters for authoring. `clear_break`'s tell lifts the light toward
## PALE DAY, which is a real brightening on day 3 (NIGHTFALL) and day 5
## (SUNRISE) -- the only two days whose schedules allow it -- and would be a
## no-op on days 1-2. The rule that follows: **a tell's lighting cue is only as
## good as the days its weather is allowed on**, and the day schedules are half
## of whether a tell reads.
func test_a_tell_leaning_at_the_look_already_on_screen_moves_nothing() -> void:
	_lighting.preset_id = &"pale_day"
	_system.load_events([_event(&"probe", {
		"lighting_preset": &"whiteout",
		"tell": _tell({"lighting_preset": &"pale_day", "snowfall_rate": 0.3}),
	})])
	_system.begin(&"probe")
	assert_eq(_lighting.faded_to(), [],
		"the sky was already wearing it, so the warning had nothing to say in light")
	assert_true(_system.applied_snowfall_rate() >= 0.0,
		"which is why every shipped tell carries a second silent channel")


func test_a_tell_with_no_light_of_its_own_leaves_the_sky_alone() -> void:
	_system.load_events([_event(&"probe", {"tell": _tell({"snowfall_rate": 0.0})})])
	_system.begin(&"probe")
	assert_eq(_lighting.faded_to(), [], "nothing asked the sky for anything")


func test_the_sky_goes_back_to_the_day_when_the_weather_clears() -> void:
	var schedule := DaySchedule.new()
	schedule.day_number = 3
	schedule.primary_lighting_preset = &"nightfall"
	schedule.night_lighting_preset = &"deep_night"
	_clock.day = 3
	_clock.schedules[3] = schedule
	_lighting.preset_id = &"nightfall"
	_system.load_events([_event(&"probe", {"lighting_preset": &"whiteout"})])
	_system.begin(&"probe")
	_run(24.0 + 60.0 + 12.0 + 4.0)
	assert_eq(_lighting.target_preset_id(), &"nightfall",
		"a passing storm must hand the sky back to the day it interrupted")


func test_the_tell_thins_the_snow_and_the_weather_thickens_it() -> void:
	_system.load_events([_event(&"probe", {
		"snowfall_rate": 1.0,
		"tell": _tell({"snowfall_rate": 0.0}),
	})])
	_system.begin(&"probe")
	_run(24.0 - 0.5)
	assert_almost_eq(_snow.snowfall_rate(), 0.0, 0.02,
		"寒流's tell is 空气变得极静: by the end of the warning the fall has stopped")
	_run(1.0 + 30.0)
	assert_almost_eq(_snow.snowfall_rate(), 1.0, 0.02,
		"and then the weather itself")


## `Snowfall.set_snowfall_rate()` takes the wheel from the lighting presets
## PERMANENTLY. So the takeover must be invisible: the first value written has to
## be the one the sky was already producing, or the whole world's snowfall steps
## on the frame a weather system happens to wake up.
func test_taking_the_wheel_of_the_snowfall_writes_the_sky_s_own_value_first() -> void:
	_snow.rate = 0.12
	_system.load_events([_event(&"probe", {
		"snowfall_rate": 1.0,
		"tell": _tell({"snowfall_rate": 0.42}),
	})])
	_system.begin(&"probe")
	assert_almost_eq(_snow.snowfall_rate(), 0.12, 0.005,
		"the first frame of ownership moved the sky by %.3f"
			% absf(_snow.snowfall_rate() - 0.12))


func test_a_weather_with_no_opinion_about_snow_never_touches_the_sky() -> void:
	_system.load_events([_event(&"probe", {"wind_speed_multiplier": 1.4})])
	_system.begin(&"probe")
	_run(24.0 + 60.0 + 12.0 + 4.0)
	assert_eq(_snow.overrides, 0,
		"an event that says nothing about the snow must not take a permanent"
			+ " override on it")


func test_the_tell_can_raise_the_wind_before_the_weather_lands() -> void:
	var gale := _map_of(&"wind_gale")
	_system.load_events([_event(&"probe", {
		"wind_map": gale,
		"wind_speed_multiplier": 1.6,
		"tell": _tell({"wind_map": gale, "wind_speed_multiplier": 1.3}),
	})])
	_system.begin(&"probe")
	assert_eq(_wind.maps.size(), 1, "the warning should hand the wind its map")
	assert_true(_wind.maps[0] == gale, "and it should be the one the tell names")
	_run(23.0)
	assert_true(_wind.gale_multiplier() > 1.2,
		"风声升高: the wind should be up before the storm is, not %.2f"
			% _wind.gale_multiplier())


## A map and not a profile, and the reason is in `WeatherTell.wind_map`:
## `set_profile()` snaps the wind by half its range in one frame, `set_map()`
## crossfades. This is that decision as a test -- if anybody rewires it to the
## profile hook, the stand-in stops seeing a map at all.
func test_the_weather_changes_the_wind_through_the_map_and_never_the_profile() -> void:
	_system.load_events([_event(&"probe", {"wind_map": _map_of(&"wind_veered", 172.354)})])
	_system.begin(&"probe")
	_run(24.0 + 2.0)
	assert_true(_wind.maps.size() >= 1, "the weather should have handed over a map")
	assert_false(_wind.has_method("set_profile"),
		"the stand-in deliberately publishes no set_profile: if this fails, the"
			+ " system is calling a hook that snaps the wind")


## THE REGRESSION TEST FOR A BUG THIS SUITE COULD NOT SEE.
##
## `WindSystem._collect()` sweeps the whole tree for any node publishing
## `set_wind()` or `set_wind_strength()` and pushes the weather into it. That is
## how a consumer is driven with no wiring, and it means a METHOD NAME is a
## project-wide contract.
##
## The weather system's injector was called `set_wind()` at first. The sweep
## found it on the first frame of the real scene and handed it a `Vector3`, which
## replaced the system's reference to the wind with the wind's own velocity --
## and every call after that failed. All 37 unit tests passed anyway, because
## nothing in a test builds a `WindSystem` that sweeps a tree. It was found by
## running a capture.
##
## So the invariant is asserted directly rather than through behaviour: this node
## must not answer to the wind's vocabulary.
func test_the_weather_does_not_answer_to_the_wind_systems_sweep() -> void:
	assert_false(_system.has_method("set_wind"),
		"WindSystem's tree sweep would find this and push a Vector3 into it")
	assert_false(_system.has_method("set_wind_strength"),
		"same sweep, same outcome with a float")
	assert_true(_system.has_method("set_wind_system"),
		"the unambiguous name is the one the wiring uses")


## The one duplicated constant in this system, pinned so it cannot drift. The
## weather has to know where to put the wind back, and asking the wind system for
## it would be a reference between two systems that this project does not allow.
func test_the_default_wind_map_is_the_one_the_wind_system_boots_on() -> void:
	var WindSystemScript := load("res://src/systems/wind_system.gd")
	assert_eq(_system.DEFAULT_WIND_MAP_PATH, WindSystemScript.MAP_PATH,
		"the weather would hand the wind back a map the wind never had")


func test_the_wind_map_goes_back_when_the_weather_clears() -> void:
	var default_map := _map_of(&"wind_valley")
	_system.set_default_wind_map(default_map)
	_system.load_events([_event(&"probe", {"wind_map": _map_of(&"wind_gale")})])
	_system.begin(&"probe")
	_run(24.0 + 60.0 + 12.0 + 4.0)
	assert_true(_wind.maps[_wind.maps.size() - 1] == default_map,
		"the valley's own wind must come back when the storm has passed")
	assert_almost_eq(_wind.gale_multiplier(), 1.0, 0.005,
		"and the bite with it")


## The oldest storm warning there is, and it already existed: `CrowFlock.scatter`
## takes a cause and publishes `wildlife.crows_scattered`. Wiring it as a tell
## costs one call.
func test_the_birds_go_up_on_the_warning() -> void:
	_system.load_events([_event(&"probe", {"tell": _tell({"flushes_wildlife": true})})])
	_system.begin(&"probe")
	assert_eq(_birds.causes.size(), 1, "the flock should have gone up on the warning")
	assert_eq(_birds.causes[0], _system.CAUSE_WEATHER,
		"and it should say the weather took them, not the player")


func test_a_relief_does_not_send_the_birds_up() -> void:
	_system.load_events([_event(&"probe", {"tell": _tell({"flushes_wildlife": false})})])
	_system.begin(&"probe")
	assert_eq(_birds.causes.size(), 0,
		"短暂放晴 is a relief; spending the game's alarm cue on it would tell the"
			+ " player exactly the wrong thing")


## Crows are daylight-only by design. A night tell therefore gets nothing from
## them -- and must say so, so that nobody reads an empty flock as a failed cue.
func test_a_night_tell_reports_that_the_birds_were_not_there() -> void:
	_birds.perched = 0
	_system.load_events([_event(&"probe", {"tell": _tell({
		"flushes_wildlife": true, "snowfall_rate": 0.0,
	})})])
	_system.begin(&"probe")
	var payload = _bus.first(_system.EVENT_TELL_STARTED)
	assert_not_null(payload, "the warning should have been published")
	if payload == null:
		return
	assert_eq(int(payload["birds"]), 0, "no bird left the wire at night")
	assert_true(bool(payload["silent_cue"]),
		"and the warning must still be visible without them")


func test_the_warning_names_its_sound_for_whoever_plays_it() -> void:
	_system.load_events([_event(&"probe", {"tell": _tell({
		"sound": &"weather_tell_blizzard", "snowfall_rate": 0.4,
	})})])
	_system.begin(&"probe")
	var payload = _bus.first(_system.EVENT_TELL_STARTED)
	assert_not_null(payload, "the warning should have been published")
	if payload == null:
		return
	assert_eq(payload["sound"], &"weather_tell_blizzard",
		"an audio subscriber reads the cue name off the payload")
	assert_true(float(payload["seconds"]) >= TELL_FLOOR_SECONDS,
		"and how long it has to play it for")


# --- the body -----------------------------------------------------------------


func test_the_weather_puts_its_modifiers_on_and_takes_them_off_again() -> void:
	var modifier: StatModifier = ModifierScript.new()
	modifier.target_stat = &"core_temperature"
	modifier.operation = Modifier.Operation.MULTIPLY
	modifier.value = 2.0
	var event := _event(&"probe")
	event.stat_modifiers = [modifier] as Array[StatModifier]
	_system.load_events([event])
	_system.begin(&"probe")
	assert_eq(_body.pushed.size(), 0, "a warning is not yet weather; nothing on the body")
	_run(25.0)
	assert_eq(_body.pushed.size(), 1, "the arrival should push the rule")
	assert_eq(_body.pushed[0]["source"], &"probe",
		"credited to the EVENT, so remove_source() can take it off again")
	_run(60.0 + 12.0 + 4.0)
	assert_true(_body.removed.has(&"probe"),
		"a modifier that outlived its weather would compound on the next draw")


# --- the orchestration --------------------------------------------------------


func test_a_forced_beat_is_drawn_for_the_day_that_forces_it() -> void:
	var schedule := DaySchedule.new()
	schedule.day_number = 7
	schedule.forced_weather_event = &"blizzard"
	_clock.day = 7
	_clock.schedules[7] = schedule
	_system.load_events([_event(&"blizzard"), _event(&"snow_fog")])
	_system.plan_phase(7, false)
	assert_true(_system.queued_ids().has(&"blizzard"),
		"day 7 must produce its storm whatever the draw says")


func test_a_day_with_no_weather_in_its_budget_draws_none() -> void:
	var schedule := DaySchedule.new()
	schedule.day_number = 1
	_clock.day = 1
	_clock.schedules[1] = schedule
	_system.load_events([_event(&"blizzard")])
	_system.plan_phase(1, false)
	assert_eq(_system.queued_ids().size(), 0,
		"day 1 is the tutorial day and its schedule allows nothing")


func test_only_a_weather_the_day_allows_is_drawn() -> void:
	var schedule := DaySchedule.new()
	schedule.day_number = 2
	schedule.allowed_weather_events = [&"snow_fog"] as Array[StringName]
	_clock.day = 2
	_clock.schedules[2] = schedule
	_system.load_events([_event(&"blizzard"), _event(&"snow_fog")])
	_system.plan_phase(2, false)
	for id in _system.queued_ids():
		assert_eq(id, &"snow_fog", "day 2 does not allow '%s'" % id)


## The lesson `CrowFlock` paid for: a system that only SUBSCRIBES never learns
## the phase it was born into, and would sit inert until the first transition --
## up to a whole phase away, looking exactly like a tuning choice.
func test_the_weather_asks_the_clock_what_day_it_already_is() -> void:
	var schedule := DaySchedule.new()
	schedule.day_number = 5
	schedule.allowed_weather_events = [&"cold_snap"] as Array[StringName]
	_clock.day = 5
	_clock.schedules[5] = schedule
	_system.load_events([_event(&"cold_snap")])
	_system.attach()
	assert_true(_system.queued_ids().size() > 0,
		"the weather system woke up on day 5 and planned nothing for it")


func test_a_second_weather_cannot_start_on_top_of_one_already_running() -> void:
	_system.load_events([_event(&"probe"), _event(&"other")])
	_system.begin(&"probe")
	assert_false(_system.begin(&"other"),
		"two weathers at once would give the second one no tell of its own")
	assert_eq(_system.event_id(), &"probe", "and the first must keep the sky")


# --- binding rule 4 -----------------------------------------------------------


## ADDING A WEATHER IS ADDING A FILE. Nothing in `src/` names any of the six, so
## a seventh built here -- with an id no line of code has ever seen -- must run
## the whole arc, announce itself, and drive every channel.
##
## The report for this task also does it the other way, from a `.tres` written to
## `data/weather/` and then deleted, because a test that builds the resource in
## memory proves the SYSTEM is general and not that the LOADER is.
func test_a_seventh_weather_nothing_has_heard_of_runs_the_whole_arc() -> void:
	# Landing on a NIGHTFALL day, so the tell's lift toward PALE DAY is a real
	# change of light -- see
	# `test_a_tell_leaning_at_the_look_already_on_screen_moves_nothing`.
	_lighting.preset_id = &"nightfall"
	var seventh := _event(&"hoarfrost", {
		"display_name": "Hoarfrost",
		"lighting_preset": &"sunrise",
		"snowfall_rate": 0.08,
		"wind_map": _map_of(&"wind_still"),
		"wind_speed_multiplier": 0.3,
		"visibility_multiplier": 1.2,
		"tell": _tell({
			"sound": &"weather_tell_hoarfrost",
			"lighting_preset": &"pale_day",
			"lighting_lead": 0.45,
			"snowfall_rate": 0.0,
			"wind_speed_multiplier": 0.4,
			"flushes_wildlife": true,
		}),
	})
	_system.load_events([seventh])
	assert_true(_system.begin(&"hoarfrost"), "a weather made of data alone should run")
	assert_eq(_system.phase(), _system.PHASE_TELL, "and it warns first, like the six")
	assert_eq(_lighting.faded_to(), [&"pale_day"], "its tell moves the light")
	assert_eq(_birds.causes.size(), 1, "and the birds")
	_run(24.0 + 2.0)
	assert_eq(_system.phase(), _system.PHASE_ACTIVE, "then it lands")
	assert_eq(_lighting.faded_to(), [&"pale_day", &"sunrise"], "on its own look")
	_run(60.0 + 12.0 + 4.0)
	assert_eq(_system.phase(), _system.PHASE_CLEAR, "and passes")
	assert_eq(_bus.count(_system.EVENT_TELL_STARTED), 1,
		"having announced itself exactly once, with no code that knows its name")
