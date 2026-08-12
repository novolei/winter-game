extends TestCase

## The wind, and the one thing that decides whether it succeeds.
##
## ---------------------------------------------------------------------------
## A CONSTANT WIND READS AS NO WIND
## ---------------------------------------------------------------------------
## Wind is invisible; the player only ever sees what it moves. A steady sideways
## force therefore becomes imperceptible within seconds, because nothing about it
## changes -- which is exactly the complaint this task exists to answer. So the
## first block below does not check that the wind is STRONG. It checks that it
## VARIES: that a lull and a gust both occur inside a playable stretch of time,
## that the spread between them is large, and that no single value is ever a good
## summary of the minute around it.
##
## Those are the tests that were written first and failed first, against a
## producer that returned a perfectly good constant.
##
## ---------------------------------------------------------------------------
## AND THE SECOND BLOCK IS THE RECONCILIATION
## ---------------------------------------------------------------------------
## Six consumers were built months apart against a producer that did not exist,
## and they do not agree with each other:
##
##   * `set_wind(Vector3)`        -- SnowfallLayer, BreathFog, SnowLoad
##   * `set_wind_strength(float)` -- Snowfall, TrackMask, SnowAccumulation
##
## and the vector one is named `velocity` in all three files while every one of
## them adds it into a `ParticleProcessMaterial.gravity`, which is an
## acceleration. The magnitude existed in exactly one place, `Snowfall.gale_wind`.
## `test_the_vocabulary_is_pinned_to_the_snowfall_that_already_had_one` is what
## stops those two drifting apart now that a second file names the same figure.

const WindScript := preload("res://src/systems/wind_system.gd")
const SpindriftScript := preload("res://src/rendering/spindrift.gd")
const SwayScript := preload("res://src/rendering/wind_sway.gd")
const SnowfallScript := preload("res://src/rendering/snowfall.gd")

const VALLEY_PATH := "res://data/weather/wind_valley.tres"
const GALE_PATH := "res://data/weather/wind_gale.tres"
const MAP_PATH := "res://data/weather/wind_map.tres"

const FRAME := 1.0 / 60.0

## Long enough that a squall has to have happened -- the valley profile puts one
## on a jittered 76 s schedule -- and short enough to be a stretch of play rather
## than a statistic.
const FOUR_MINUTES := 240.0


## Everything a strength consumer is, in this system's eyes.
class StrengthConsumer extends RefCounted:
	var pushed := 0
	var last := -1.0

	func set_wind_strength(strength: float) -> void:
		pushed += 1
		last = strength

	func wind_strength() -> float:
		return last


## ...and everything a velocity consumer is.
class VelocityConsumer extends RefCounted:
	var pushed := 0
	var last := Vector3.ZERO

	func set_wind(velocity: Vector3) -> void:
		pushed += 1
		last = velocity


## A consumer that already has a driver: it takes its weather from the sky, and
## the wind reaches it through the sky rather than from here. SnowAccumulation is
## the live instance -- see WindSystem._is_fed_by_the_sky().
class SkyFedConsumer extends StrengthConsumer:
	var sky_wind := 0.0

	func set_snowfall_source(_source) -> void:
		pass

	func wind_strength() -> float:
		return sky_wind


## Every Node this file allocates, freed in after_each. `Node` is not
## reference-counted (briefing section 2.2) and WindSystem, Snowfall and
## Spindrift are all Nodes, so an un-freed subject is a leak the wrapper fails
## the whole run on.
var _allocated: Array[Node] = []


func after_each() -> void:
	for node in _allocated:
		if is_instance_valid(node):
			node.free()
	_allocated.clear()


func _keep(node: Node) -> Node:
	_allocated.append(node)
	return node


func _valley() -> WindProfile:
	return load(VALLEY_PATH)


func _map() -> WindMap:
	return load(MAP_PATH)


func _every_profile_path() -> Array:
	var paths := []
	for profile in _map().profiles:
		paths.append(profile.resource_path)
	return paths


## The mean strength of a profile over four minutes.
func _mean(profile: WindProfile) -> float:
	var values := _sample(profile, FOUR_MINUTES, 0.25)
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


func _system() -> Node:
	var wind := WindScript.new()
	wind.set_profile(_valley())
	return _keep(wind)


## A system that has NOT been handed a profile, so the sky is still allowed to
## choose one. `set_profile()` claims ownership for good -- see
## `test_a_weather_system_that_takes_the_wheel_keeps_it` -- so a test about the
## sky choosing cannot use `_system()`.
func _bare_system() -> Node:
	var wind := WindScript.new()
	wind.set_map(_map())
	return _keep(wind)


## Samples the strength once a second for `seconds`, without a tree.
func _sample(profile: WindProfile, seconds: float, step := 1.0) -> Array:
	var values := []
	var t := 0.0
	while t <= seconds:
		values.append(WindScript.strength_at(profile, t))
		t += step
	return values


# --- the wind must vary ------------------------------------------------------

## THE HEADLINE PROPERTY. A wind whose strength never changes is a wind the
## player cannot feel, however large the number is.
func test_the_strength_is_never_constant() -> void:
	var values := _sample(_valley(), FOUR_MINUTES, 0.5)
	var low: float = values[0]
	var high: float = values[0]
	for v in values:
		low = minf(low, v)
		high = maxf(high, v)
	assert_true(
		high - low > 0.30,
		"a wind that varies by %.3f over four minutes is a constant with rounding" % (high - low)
	)


## ...and it must vary on the timescale a player is standing there for. A wind
## that takes ten minutes to change is a constant for the length of an errand.
func test_a_gust_and_a_lull_both_arrive_inside_a_minute() -> void:
	var profile := _valley()
	var values := _sample(profile, 60.0, 0.25)
	var low: float = values[0]
	var high: float = values[0]
	for v in values:
		low = minf(low, v)
		high = maxf(high, v)
	assert_true(low <= profile.lull_threshold, "no lull inside a minute: floor was %.3f" % low)
	# Judged against the GUST STRUCTURE, not against the squall schedule: a
	# strong ordinary gust is `base + gust_depth`, and this asks for four fifths
	# of one. Written against `gust_threshold` first, and that was a worse test --
	# it passed only because a squall happened to fall inside the first minute,
	# so it was measuring the squall's hashed start time rather than the gusts.
	var strong_gust := profile.base_strength + profile.gust_depth * 0.8
	assert_true(high >= strong_gust, "no gust inside a minute: peak was %.3f" % high)
	# ...and the announcing threshold has to sit where ordinary gusts can reach
	# it, or `wind.gust_started` only ever fires on squalls and duplicates
	# `wind.squall_started`.
	assert_true(
		profile.gust_threshold < profile.base_strength + profile.gust_depth,
		"gust_threshold %.2f is above the gust ceiling %.2f -- only a squall can announce a gust"
			% [profile.gust_threshold, profile.base_strength + profile.gust_depth]
	)


## The squall: a front that crosses the valley and passes. Distinguished from a
## gust by being both bigger and rarer, so this asserts the peak is well above
## anything the gust structure alone can reach.
func test_a_squall_arrives_and_passes() -> void:
	var profile := _valley()
	var gust_ceiling := profile.base_strength + profile.gust_depth
	var values := _sample(profile, FOUR_MINUTES, 0.25)
	var above := 0
	for v in values:
		if v > gust_ceiling + 0.05:
			above += 1
	assert_true(above > 0, "no squall in four minutes: nothing exceeded %.3f" % gust_ceiling)
	# ...and it PASSES. A squall that never ends is the weather, not an event.
	assert_true(
		float(above) / float(values.size()) < 0.5,
		"the squall is on for %.0f%% of the time, which makes it the weather" % (100.0 * above / values.size())
	)


## Lulls are longer than gusts, which is what `gust_sharpness` buys and what
## makes the arrival of a gust an event rather than a phase of a sine.
func test_lulls_outlast_gusts() -> void:
	var profile := _valley()
	var values := _sample(profile, FOUR_MINUTES, 0.25)
	var midpoint := profile.base_strength + profile.gust_depth * 0.5
	var above := 0
	for v in values:
		if v > midpoint:
			above += 1
	assert_true(
		float(above) / float(values.size()) < 0.42,
		"the wind is above its own midpoint %.0f%% of the time; gusts are not events" % (100.0 * above / values.size())
	)


func test_the_strength_stays_inside_zero_and_one() -> void:
	for profile_path in _every_profile_path():
		var profile: WindProfile = load(profile_path)
		var t := 0.0
		while t <= 600.0:
			var s := WindScript.strength_at(profile, t)
			assert_true(s >= 0.0 and s <= 1.0, "%s produced %.3f at t=%.1f" % [profile.id, s, t])
			t += 0.37
	# 0.37 rather than a round number on purpose: a step that divides the gust
	# period samples the same phase forever and proves nothing about the rest.


## Continuity. The strength is read straight into particle accelerations, and a
## step in it is a visible pop in every one of them at once.
func test_the_strength_never_steps() -> void:
	var profile := _valley()
	var t := 0.0
	var previous := WindScript.strength_at(profile, 0.0)
	while t <= FOUR_MINUTES:
		t += FRAME
		var now := WindScript.strength_at(profile, t)
		assert_true(
			absf(now - previous) < 0.02,
			"the wind stepped by %.4f at t=%.3f" % [absf(now - previous), t]
		)
		previous = now


# --- the heading -------------------------------------------------------------

func test_the_heading_wanders_but_stays_near_prevailing() -> void:
	var profile := _valley()
	var swing := 0.0
	var t := 0.0
	while t <= FOUR_MINUTES:
		var offset := WindScript.heading_at(profile, t) - profile.prevailing_degrees
		swing = maxf(swing, absf(offset))
		t += 0.5
	assert_true(swing > 8.0, "the heading only moved %.1f degrees; the snow blows one way forever" % swing)
	var ceiling := profile.wander_degrees + profile.gust_veer_degrees + 0.001
	assert_true(swing <= ceiling, "the heading swung %.1f degrees, past its own %.1f" % [swing, ceiling])


func test_the_heading_vector_is_unit_and_flat() -> void:
	for degrees in [0.0, 17.354, 90.0, 180.0, -73.5, 361.0]:
		var v: Vector3 = WindScript.heading_vector(degrees)
		assert_almost_eq(v.length(), 1.0, 0.0001)
		assert_almost_eq(v.y, 0.0, 0.0001)
	assert_almost_eq(WindScript.heading_vector(0.0).x, 1.0, 0.0001)
	assert_almost_eq(WindScript.heading_vector(90.0).z, 1.0, 0.0001)


# --- the vocabulary the consumers already spoke ------------------------------

## The reconciliation, pinned. `Snowfall.gale_wind` was the only place in the
## project that carried a wind MAGNITUDE, and the profile now names the same
## figure so three files can share one vocabulary. If either moves, this fails.
func test_the_vocabulary_is_pinned_to_the_snowfall_that_already_had_one() -> void:
	var sky = _keep(SnowfallScript.new())
	var authored: Vector3 = sky.gale_wind
	var profile := _valley()
	assert_almost_eq(profile.gale_metres, authored.length(), 0.0005)
	var prevailing: Vector3 = WindScript.heading_vector(profile.prevailing_degrees) * profile.gale_metres
	assert_almost_eq(prevailing.x, authored.x, 0.001)
	assert_almost_eq(prevailing.z, authored.z, 0.001)


func test_the_velocity_is_the_direction_at_the_strength() -> void:
	var wind := _system()
	wind.advance(4.0)
	var expected: Vector3 = wind.direction() * _valley().gale_metres * wind.strength()
	assert_almost_eq(wind.velocity().x, expected.x, 0.0001)
	assert_almost_eq(wind.velocity().z, expected.z, 0.0001)
	assert_almost_eq(wind.velocity().y, 0.0, 0.0001)


# --- driving the consumers ---------------------------------------------------

func test_a_strength_consumer_is_driven_every_frame() -> void:
	var wind := _system()
	var consumer := StrengthConsumer.new()
	wind.advance(3.0)
	wind.drive(consumer, FRAME)
	assert_eq(consumer.pushed, 1)
	assert_almost_eq(consumer.last, wind.strength(), 0.0001)
	wind.advance(FRAME)
	wind.drive(consumer, FRAME)
	assert_eq(consumer.pushed, 2)


func test_a_velocity_consumer_is_driven_in_metres_per_second_squared() -> void:
	var wind := _system()
	var consumer := VelocityConsumer.new()
	wind.advance(3.0)
	wind.drive(consumer, FRAME)
	assert_eq(consumer.pushed, 1)
	assert_almost_eq(consumer.last.x, wind.velocity().x, 0.0001)
	assert_almost_eq(consumer.last.z, wind.velocity().z, 0.0001)


## THE ONE CONSUMER THAT IS NOT PUSHED. SnowAccumulation's set_wind_strength()
## raises a permanent `_overridden` flag that ALSO stops it reading the snowfall
## rate off the sky -- one flag, two facts, and only one of them is the wind's to
## take. It already polls the sky's wind every frame, so the sky is the path.
func test_a_consumer_fed_by_the_sky_is_left_alone() -> void:
	var wind := _system()
	var consumer := SkyFedConsumer.new()
	wind.advance(3.0)
	# The sky has already passed it on, one frame late, which is what it looks
	# like in the running game.
	consumer.sky_wind = wind.strength()
	for i in 120:
		wind.drive(consumer, FRAME)
	assert_eq(consumer.pushed, 0)


## ...and the fallback, which is what makes leaving it alone safe. If the
## pass-through is ever cut -- somebody else takes the override, the sky is
## deleted -- the wind stops trusting it and drives it directly.
func test_a_sky_fed_consumer_the_sky_has_stopped_feeding_is_driven_anyway() -> void:
	var wind := _system()
	var consumer := SkyFedConsumer.new()
	# Somewhere the wind is unmistakably blowing, so "the sky says zero" is a
	# disagreement rather than a rounding difference.
	while wind.strength() < 0.3:
		wind.advance(0.25)
	consumer.sky_wind = 0.0
	var grace: float = wind.passthrough_grace_seconds
	var elapsed := 0.0
	while elapsed < grace * 0.9:
		wind.drive(consumer, FRAME)
		elapsed += FRAME
	assert_eq(consumer.pushed, 0)
	while elapsed < grace * 1.5:
		wind.drive(consumer, FRAME)
		elapsed += FRAME
	assert_true(consumer.pushed > 0, "the sky stopped feeding it and nothing noticed")


## REGRESSION. The sweep skips the system itself, and the obvious way to write
## that skip -- `continue` -- skipped the whole SUBTREE with it. Both visible
## cues are parented under the system, so both were silently never driven: the
## wind ran perfectly, every number was right, and nothing moved. Which is the
## exact failure this whole task exists to fix, arrived at from the other side.
func test_the_sweep_reaches_a_cue_parented_under_the_system_itself() -> void:
	var world := _keep(Node.new())
	var wind := _system()
	world.add_child(wind)
	var cue = SpindriftScript.new()
	wind.add_child(cue)
	wind.refresh_consumers(world)
	assert_eq(wind.consumer_count(), 1, "a cue under the wind system was not found")


func test_the_sweep_does_not_collect_the_system_itself() -> void:
	var world := _keep(Node.new())
	var wind := _system()
	world.add_child(wind)
	wind.refresh_consumers(world)
	assert_eq(wind.consumer_count(), 0)


# --- the events an audio system will subscribe to ----------------------------

## Wave 3's audio task must be able to be a SUBSCRIBER rather than a rewrite.
class BusSpy extends RefCounted:
	var seen := []

	func emit_event(event: StringName, payload = null) -> void:
		seen.append([event, payload])

	func count(event: StringName) -> int:
		var n := 0
		for entry in seen:
			if entry[0] == event:
				n += 1
		return n


func test_a_gust_publishes_once_on_the_way_up_and_once_on_the_way_down() -> void:
	var wind := _system()
	var spy := BusSpy.new()
	wind.set_event_bus(spy)
	var t := 0.0
	while t < FOUR_MINUTES:
		wind.advance(FRAME)
		t += FRAME
	var started := spy.count(WindScript.EVENT_GUST_STARTED)
	var ended := spy.count(WindScript.EVENT_GUST_ENDED)
	assert_true(started > 0, "four minutes of wind and not one gust was announced")
	# Hysteresis: every gust that started either ended or is still running, so
	# the two counts are equal or differ by exactly one.
	assert_true(
		absi(started - ended) <= 1,
		"%d gusts started and %d ended -- the threshold is chattering" % [started, ended]
	)


func test_a_lull_is_announced_too() -> void:
	var wind := _system()
	var spy := BusSpy.new()
	wind.set_event_bus(spy)
	var t := 0.0
	while t < FOUR_MINUTES:
		wind.advance(FRAME)
		t += FRAME
	assert_true(
		spy.count(WindScript.EVENT_LULL_STARTED) > 0,
		"the world never goes quiet, so nothing can use the quiet"
	)


func test_a_gust_payload_says_how_hard_and_which_way() -> void:
	var wind := _system()
	var spy := BusSpy.new()
	wind.set_event_bus(spy)
	var t := 0.0
	while t < FOUR_MINUTES:
		wind.advance(FRAME)
		t += FRAME
	for entry in spy.seen:
		if entry[0] != WindScript.EVENT_GUST_STARTED:
			continue
		var payload: Dictionary = entry[1]
		assert_true(payload.has("strength"))
		assert_true(payload.has("heading_degrees"))
		assert_true(payload.has("direction"))
		return
	assert_true(false, "no gust to inspect")


func test_the_heading_shift_is_published_for_the_bear_to_use() -> void:
	var wind := _system()
	var spy := BusSpy.new()
	wind.set_event_bus(spy)
	var t := 0.0
	while t < FOUR_MINUTES:
		wind.advance(FRAME)
		t += FRAME
	assert_true(
		spy.count(WindScript.EVENT_DIRECTION_SHIFTED) > 0,
		"the wind never reports a change of quarter, so nothing downwind can know"
	)


# --- adding a gale is adding a file ------------------------------------------

## Binding rule 4, as a test. Nothing in `src/` knows what a gale is.
func test_a_different_profile_is_a_different_weather_with_no_code() -> void:
	var valley := _sample(_valley(), FOUR_MINUTES, 0.25)
	var gale := _sample(load(GALE_PATH), FOUR_MINUTES, 0.25)
	var valley_mean := 0.0
	for v in valley:
		valley_mean += v
	valley_mean /= float(valley.size())
	var gale_mean := 0.0
	for v in gale:
		gale_mean += v
	gale_mean /= float(gale.size())
	assert_true(
		gale_mean > valley_mean * 1.8,
		"the gale averages %.3f against the valley's %.3f, which is the same weather" % [gale_mean, valley_mean]
	)
	# ...and it is not merely louder. A gale gusts more OFTEN, which is a
	# different fact and the one that makes it read as a different wind.
	assert_true(_crossings(gale, 0.6) > _crossings(valley, 0.6) * 2)


## How many times a sampled series crosses a level going up.
func _crossings(values: Array, level: float) -> int:
	var n := 0
	var was_above := false
	for v in values:
		var above: bool = v > level
		if above and not was_above:
			n += 1
		was_above = above
	return n


## THE SHIPPED FILE SAYS WHAT THE GENERATOR SAYS, field by field.
##
## Needed because of something `ResourceSaver` does that is easy to miss: it
## OMITS any value equal to the script's default. The valley profile's numbers
## are the definition's defaults, so `data/weather/wind_valley.tres` is two lines
## long -- `id` and `display_name` -- and every other figure in it is inherited
## from `wind_profile.gd` at load time.
##
## That is fine until somebody retunes a default in the definition believing they
## are changing a fallback, and silently changes THE WEATHER THE GAME SHIPS WITH
## instead. Nothing in the file would show it and nothing else would fail. This
## does.
func test_the_shipped_profiles_say_what_the_generator_says() -> void:
	var Generator := load("res://tools/generate_wind_profiles.gd")
	for spec in Generator.ALL:
		var path := "res://data/weather/%s.tres" % spec["id"]
		var profile: WindProfile = load(path)
		assert_not_null(profile, path)
		if profile == null:
			continue
		for key in spec:
			var wanted = spec[key]
			var found = profile.get(key)
			if key == "presets":
				# Array[StringName] against the generator's plain strings.
				assert_eq(profile.presets.size(), (wanted as Array).size(), path)
				for preset in wanted:
					assert_true(
						profile.presets.has(StringName(preset)),
						"%s does not claim %s" % [path, preset]
					)
				continue
			if wanted is float:
				assert_almost_eq(
					float(found), float(wanted), 0.00001,
					"%s.%s is %s, the generator says %s" % [path, key, found, wanted]
				)
			else:
				assert_eq(found, wanted, "%s.%s" % [path, key])


func test_both_profiles_load_and_name_themselves() -> void:
	for path in _every_profile_path():
		var profile: WindProfile = load(path)
		assert_not_null(profile, path)
		assert_true(profile.id != &"", "%s has no id" % path)
		assert_true(profile.gale_metres > 0.0)
		assert_true(profile.gust_seconds > 0.0)
		assert_true(profile.lull_threshold < profile.gust_threshold)


# --- spindrift: the cue that actually reads ----------------------------------

## Loose snow streaming along the ground, and the whole of its value is that it
## is NOT THERE in a lull. A spindrift that is always on is a ground fog.
func test_spindrift_is_silent_below_its_onset() -> void:
	assert_almost_eq(SpindriftScript.stream_ratio(0.0, 0.28), 0.0, 0.0001)
	assert_almost_eq(SpindriftScript.stream_ratio(0.27, 0.28), 0.0, 0.0001)
	assert_true(SpindriftScript.stream_ratio(0.5, 0.28) > 0.0)
	assert_almost_eq(SpindriftScript.stream_ratio(1.0, 0.28), 1.0, 0.0001)


func test_spindrift_streams_along_the_wind_and_stays_low() -> void:
	var drift = _keep(SpindriftScript.new())
	drift.set_wind(Vector3(1.2, 0.0, 0.4))
	drift.set_wind_strength(0.8)
	var travel: Vector3 = drift.stream_velocity()
	assert_true(travel.length() > 0.0)
	assert_almost_eq(travel.normalized().y, 0.0, 0.02)
	assert_almost_eq(
		travel.normalized().x, Vector3(1.2, 0.0, 0.4).normalized().x, 0.001
	)


## The same gate `test_snowfall.gd` holds the falling flake to, and the spindrift
## needs it more: there are three times as many streaks as there are flakes in a
## layer, and this one was deliberately taken WHITER than the flake to make it
## read against snow. Glow belongs to the fire, the windows and the beacons.
##
## GLOW_HDR_THRESHOLD is LightingDirector's own figure, copied rather than read,
## for the reason test_snowfall.gd gives: building a LightingDirector to ask it
## costs an engine error that has nothing to do with the wind.
const GLOW_HDR_THRESHOLD := 0.95


func test_the_spindrift_stays_under_the_bloom_threshold() -> void:
	var drift = _keep(SpindriftScript.new())
	var snow: Color = (load("res://data/palette/color_bible.tres") as ColorBible).snow_tones[0]
	var albedo := Color(
		lerpf(snow.r, 1.0, drift.streak_whiteness),
		lerpf(snow.g, 1.0, drift.streak_whiteness),
		lerpf(snow.b, 1.0, drift.streak_whiteness),
		drift.streak_alpha
	)
	var linear := albedo.srgb_to_linear()
	var peak: float = maxf(maxf(linear.r, linear.g), linear.b) * albedo.a
	assert_true(
		peak < GLOW_HDR_THRESHOLD,
		"the spindrift peaks at %f against a bloom threshold of %f" % [peak, GLOW_HDR_THRESHOLD]
	)
	# ...and it may not be warm. Rule 12 lists where warmth is allowed and blown
	# snow is not on the list.
	assert_true(
		albedo.b >= albedo.g and albedo.g >= albedo.r,
		"the spindrift is warm at (%f, %f, %f)" % [albedo.r, albedo.g, albedo.b]
	)


## The sway is a compromise -- a rigid segment translated, so its anchors move
## with it -- and the compromise is only acceptable while it is SMALL. This is the
## bound that stops it being quietly raised until a wire visibly leaves its pole.
func test_the_wire_amplitude_stays_inside_what_a_rigid_span_can_get_away_with() -> void:
	var sway = _keep(SwayScript.new())
	assert_true(
		sway.sway_metres <= 0.18,
		"a sway of %.3f m is about ten pixels at the gameplay framing, and the "
			% sway.sway_metres + "anchors move with it -- see wind_sway.gd's header"
	)
	assert_true(sway.sway_metres > 0.0)


func test_spindrift_carries_no_colour_of_its_own() -> void:
	var source := FileAccess.get_file_as_string("res://src/rendering/spindrift.gd")
	assert_false(source.contains("Color(0x"), "spindrift.gd writes a hex colour")
	assert_true(
		source.contains("color_bible.tres"),
		"spindrift.gd does not read the palette"
	)


# --- the wires ---------------------------------------------------------------

## Art Bible rule 11: the picture's whole detail budget is carried by a few
## lines, and the wires across the frame are one of them. A line that moves in a
## gust is wind made visible for the price of one translation.
const SPAN := Vector3(0.0, 0.0, -1.0)
const CROSSWIND := Vector3(1.0, 0.0, 0.0)
const AMPLITUDE := 0.10
const RESPONSE := 0.55


## The widest this span gets over `seconds`, sampled at 20 Hz. Sampled rather
## than evaluated at one instant, because every one of these is a claim about a
## swing and a single instant of a swing proves nothing.
func _widest(axis: Vector3, wind: Vector3, strength: float, phase: float, seconds := 20.0) -> float:
	var widest := 0.0
	var t := 0.0
	while t < seconds:
		var offset: Vector3 = SwayScript.offset_for(
			axis, wind, strength, phase, AMPLITUDE, RESPONSE, t
		)
		widest = maxf(widest, offset.length())
		t += 0.05
	return widest


## Dead still air leaves the wires exactly where they were strung. The whole
## value of a moving wire is the contrast with a still one.
func test_a_wire_does_not_move_in_still_air() -> void:
	assert_almost_eq(_widest(SPAN, CROSSWIND, 0.0, 3.7), 0.0, 0.0001)
	assert_almost_eq(_widest(SPAN, Vector3.ZERO, 1.0, 3.7), 0.0, 0.0001)


## A wind blowing ALONG a wire barely moves it, and one blowing ACROSS moves it
## most. That is free -- it is one projection -- and it is the difference between
## a wire that sways and three wires sliding sideways in step.
func test_a_wire_answers_the_crosswind_and_not_the_headwind() -> void:
	var along := _widest(SPAN, SPAN, 1.0, 3.7)
	var across := _widest(SPAN, CROSSWIND, 1.0, 3.7)
	assert_true(across > 0.0, "a full gale straight across the span moved it not at all")
	assert_true(
		along < across * 0.05,
		"a headwind moved the span %.4f m against a crosswind's %.4f m" % [along, across]
	)


## The sway is bounded. A wire that leaves its own pole is worse than a still one.
func test_the_sway_never_leaves_the_pole() -> void:
	var widest := _widest(SPAN, CROSSWIND, 1.0, 3.7, 60.0)
	assert_true(
		widest <= AMPLITUDE * 1.15,
		"the wire swung %.3f m against an amplitude of %.3f" % [widest, AMPLITUDE]
	)


## An ordinary gust still moves it. A sway that only shows in a full gale is a
## sway nobody sees, because a full gale is day 7.
func test_an_ordinary_gust_still_moves_the_wire() -> void:
	var gusting := _widest(SPAN, CROSSWIND, 0.35, 3.7)
	assert_true(
		gusting > AMPLITUDE * 0.4,
		"a gust of 0.35 moved the wire %.4f m, which is nothing at this camera" % gusting
	)


## Three wires strung from the same pole must not move as one object.
func test_two_wires_do_not_swing_in_lockstep() -> void:
	var apart := 0.0
	var t := 0.0
	while t < 20.0:
		var a: Vector3 = SwayScript.offset_for(SPAN, CROSSWIND, 1.0, 2.1, AMPLITUDE, RESPONSE, t)
		var b: Vector3 = SwayScript.offset_for(SPAN, CROSSWIND, 1.0, 5.9, AMPLITUDE, RESPONSE, t)
		apart = maxf(apart, (a - b).length())
		t += 0.05
	assert_true(apart > AMPLITUDE * 0.5, "two spans never got %.3f m apart" % apart)


func test_two_spans_get_different_phases() -> void:
	var seen: Dictionary = {}
	for id in [1000, 1001, 1002, 74311, 74312]:
		var phase: float = SwayScript.phase_for(id)
		assert_true(phase >= 0.0 and phase <= TAU)
		seen[snappedf(phase, 0.0001)] = true
	assert_eq(seen.size(), 5)


# --- the pendulums: the tyre, and the frozen trees ---------------------------
#
# THE PROPERTY THAT MATTERS HERE IS MEMORY.
#
# A sine scaled by wind strength is exactly in phase with the wind at every
# instant, and reads as a value being applied to an object rather than as an
# object being pushed by air. Everything convincing about a pendulum is the ways
# it FAILS to track its forcing: it arrives late, it goes past, and it is still
# going after the gust has gone. Each of those is a test below, and not one of
# them can pass for a sine.

const PendulumScript := preload("res://src/rendering/wind_pendulum.gd")
const FarmsteadScript := preload("res://src/entities/farmstead.gd")

## The tyre: 1.74 m of rope to the middle of the tyre.
const ROPE_M := 1.74
const TYRE_ZETA := 0.10


func _tyre_omega() -> float:
	return sqrt(PendulumScript.GRAVITY / ROPE_M)


## Runs the integrator against a constant drive and returns the angle every step.
func _swing(drive: float, omega: float, zeta: float, seconds: float, step := FRAME) -> Array:
	var angles := []
	var angle := 0.0
	var rate := 0.0
	var t := 0.0
	while t < seconds:
		var next: Array = PendulumScript.step(angle, rate, drive, omega, zeta, step)
		angle = next[0]
		rate = next[1]
		angles.append(angle)
		t += step
	return angles


func _peak(angles: Array) -> float:
	var peak := 0.0
	for angle in angles:
		peak = maxf(peak, absf(angle))
	return peak


func test_a_pendulum_in_still_air_does_not_move() -> void:
	for angle in _swing(0.0, _tyre_omega(), TYRE_ZETA, 20.0):
		assert_almost_eq(angle, 0.0, 0.000001)


## IT ARRIVES LATE. A tenth of a period after the wind steps on, a real pendulum
## has barely begun to move; a sine would already be wherever the wind says.
func test_the_tyre_arrives_late() -> void:
	var omega := _tyre_omega()
	var drive := 0.22
	var period := TAU / omega
	var angles := _swing(drive, omega, TYRE_ZETA, period * 0.1)
	var settled: float = PendulumScript.equilibrium(drive)
	var reached: float = angles[angles.size() - 1]
	assert_true(
		reached < settled * 0.35,
		"a tenth of a period in, it was already %.1f percent of the way there -- that is a sine"
			% (100.0 * reached / settled)
	)


## IT GOES PAST. A step of wind carries it well beyond where that same wind can
## hold it, which is the half of the motion that says the thing has mass.
func test_the_tyre_overshoots_what_the_wind_can_hold() -> void:
	var drive := 0.22
	var angles := _swing(drive, _tyre_omega(), TYRE_ZETA, 12.0)
	var settled: float = PendulumScript.equilibrium(drive)
	var peak := _peak(angles)
	assert_true(
		peak > settled * 1.3,
		"it peaked at %.4f against a resting angle of %.4f -- no overshoot at all" % [peak, settled]
	)
	# ...and then settles where the wind asks, rather than ringing forever.
	assert_almost_eq(angles[angles.size() - 1], settled, 0.02)


## IT IS STILL GOING AFTERWARDS. The gust passes and the tyre does not stop with
## it. Lightly damped on purpose: this is the single most convincing thing the
## effect does, and it is free.
func test_the_tyre_goes_on_swinging_after_the_wind_drops() -> void:
	var omega := _tyre_omega()
	var angle := 0.0
	var rate := 0.0
	var t := 0.0
	# Four seconds of wind...
	while t < 4.0:
		var next: Array = PendulumScript.step(angle, rate, 0.22, omega, TYRE_ZETA, FRAME)
		angle = next[0]
		rate = next[1]
		t += FRAME
	# ...then nothing at all.
	var crossings := 0
	var was_positive: bool = angle > 0.0
	var widest_after := 0.0
	t = 0.0
	while t < 8.0:
		var next: Array = PendulumScript.step(angle, rate, 0.0, omega, TYRE_ZETA, FRAME)
		angle = next[0]
		rate = next[1]
		widest_after = maxf(widest_after, absf(angle))
		if (angle > 0.0) != was_positive:
			crossings += 1
			was_positive = angle > 0.0
		t += FRAME
	assert_true(crossings >= 3, "it stopped dead with the wind: %d crossings in 8 s" % crossings)
	assert_true(widest_after > 0.02, "nothing left to see: it only reached %.4f rad" % widest_after)


## Measures the damped period from an impulse, by zero crossings.
func _period_of(omega: float) -> float:
	var angle := 0.3
	var rate := 0.0
	var t := 0.0
	var first := -1.0
	var last := -1.0
	var crossings := 0
	var was_positive := true
	while t < 30.0:
		var next: Array = PendulumScript.step(angle, rate, 0.0, omega, TYRE_ZETA, FRAME)
		angle = next[0]
		rate = next[1]
		t += FRAME
		if (angle > 0.0) != was_positive:
			was_positive = angle > 0.0
			crossings += 1
			if first < 0.0:
				first = t
			last = t
	if crossings < 3:
		return 0.0
	# Two crossings to a full cycle.
	return 2.0 * (last - first) / float(crossings - 1)


## The period is a fact about the rope, not a number somebody picked.
func test_a_longer_rope_swings_slower() -> void:
	var short := _period_of(sqrt(PendulumScript.GRAVITY / 0.6))
	var long := _period_of(sqrt(PendulumScript.GRAVITY / 2.4))
	assert_true(long > short * 1.7, "0.6 m swung in %.2f s and 2.4 m in %.2f s" % [short, long])
	# TAU * sqrt(1.74 / 9.81) = 2.65 s, and lightly damped it is barely longer.
	var tyre := _period_of(_tyre_omega())
	assert_true(
		tyre > 2.5 and tyre < 2.9,
		"the tyre period came out at %.2f s against the 2.65 s its rope asks for" % tyre
	)


## No wind this game can produce puts the tyre over the branch it hangs from.
##
## Two separate guarantees, and it is worth keeping them apart. The RESTING angle
## is bounded by construction, because the restoring term is `sin(theta)` rather
## than a small-angle `theta` -- so `asin` caps it at a quarter turn whatever is
## asked. The TRANSIENT is not: an underdamped step response goes 73 per cent
## past its own equilibrium, every time, and that is the overshoot the whole
## effect is built on.
##
## So the number that matters is the SUM. At the shipped `drive_degrees` of 13
## the equilibrium is 13.0 degrees and the peak is 22.5, and `max_degrees` is set
## at 24 -- above the natural overshoot on purpose, so the clamp is a backstop for
## a pathological frame and never a thing that shapes the motion.
func test_no_wind_can_put_the_tyre_over_the_branch() -> void:
	var lean := sin(deg_to_rad(13.0))
	var peak := _peak(_swing(lean, _tyre_omega(), TYRE_ZETA, 30.0))
	assert_true(
		peak < deg_to_rad(24.0),
		"the tyre peaked at %.1f degrees against a ceiling of 24" % rad_to_deg(peak)
	)
	# ...and the clamp is a backstop rather than the shape of the motion: it must
	# sit ABOVE what the physics actually does, or the swing would flatten off at
	# the top of every gust and read as a mechanism.
	assert_true(
		peak > deg_to_rad(18.0),
		"the peak of %.1f degrees is so far under the 24 degree clamp that "
			% rad_to_deg(peak) + "drive_degrees and max_degrees have drifted apart"
	)
	# The resting angle is capped whatever is asked, which is what `asin` buys.
	for drive in [0.5, 1.0, 4.0, 40.0]:
		assert_true(absf(PendulumScript.equilibrium(drive)) <= PI * 0.5 + 0.0001)


## A hanging thing and a standing thing lean opposite ways for the same weather,
## because the mass is below the pivot in one case and above it in the other.
func test_a_hanging_thing_and_a_standing_tree_lean_opposite_ways() -> void:
	var hung: Basis = PendulumScript.tilt_basis(0.2, 0.0, true)
	var stood: Basis = PendulumScript.tilt_basis(0.2, 0.0, false)
	assert_true((hung * Vector3.DOWN).x > 0.05, "the tyre did not swing downwind")
	assert_true((stood * Vector3.UP).x > 0.05, "the tree did not lean downwind")


## Frozen wood is stiff. Still in a lull, moving in a gust -- and the contrast
## between the two is the cue, so the ratio is what this asserts.
func test_the_branches_are_still_in_a_lull_and_move_in_a_gust() -> void:
	var omega := TAU / 0.62
	var lean := sin(deg_to_rad(1.6))
	var lull := _peak(_swing(lean * 0.06, omega, 0.28, 6.0))
	var gust := _peak(_swing(lean * 0.60, omega, 0.28, 6.0))
	assert_true(
		gust > lull * 8.0,
		"a gust moved them %.5f rad against %.5f in a lull -- there is no contrast" % [gust, lull]
	)
	# ...and small. These are frozen branches, not palm fronds: 1.6 degrees holds
	# the crown of a 7 m tree inside 0.2 m and leaves the trunk visually still.
	assert_true(
		gust < deg_to_rad(2.6),
		"the trees bent %.2f degrees, which is foliage in a breeze" % rad_to_deg(gust)
	)


## Turbulence is what makes bare wood WHIP rather than sway, and it has to be
## per-tree: one eddy crossing eleven trees in step is a hedge, not a wood.
func test_no_two_trees_are_hit_by_the_same_eddy() -> void:
	var apart := 0.0
	var t := 0.0
	while t < 6.0:
		var a: float = PendulumScript.buffet(t, 2.3, PendulumScript.phase_for(74311))
		var b: float = PendulumScript.buffet(t, 2.3, PendulumScript.phase_for(90210))
		apart = maxf(apart, absf(a - b))
		t += 0.02
	assert_true(apart > 0.4, "two trees were never more than %.3f apart" % apart)


## An explicit integrator on an oscillator GAINS energy every cycle, and a tyre
## swing that slowly winds itself up to a full loop is not a thing anybody would
## guess at from the symptom. Checked at a deliberately cruel frame rate.
func test_the_integrator_does_not_wind_itself_up_at_a_low_frame_rate() -> void:
	for rate_hz in [60.0, 30.0, 15.0]:
		var angles := _swing(0.22, _tyre_omega(), TYRE_ZETA, 120.0, 1.0 / rate_hz)
		var settled: float = PendulumScript.equilibrium(0.22)
		var late: float = angles[angles.size() - 1]
		assert_true(
			absf(late - settled) < 0.05,
			"at %.0f fps it ended two minutes at %.4f against a resting %.4f"
				% [rate_hz, late, settled]
		)
	# ...and the same for the trees, which are the stiffest thing here and so the
	# hardest on the step size.
	var stiff := _swing(0.03, TAU / 0.62, 0.28, 120.0, 1.0 / 15.0)
	assert_true(_peak(stiff) < deg_to_rad(5.0), "the trees wound up at 15 fps")


## Measured off the model rather than authored: the tyre swing .glb is built with
## its origin at the hang point precisely so this is answerable.
func test_the_rope_length_is_measured_off_the_model() -> void:
	var hanger := _keep(Node3D.new()) as Node3D
	var tyre := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	tyre.mesh = box
	# Bottom of the box at -2.15, which is where the tyre swing model puts it.
	tyre.position = Vector3(0.0, -1.9, 0.0)
	hanger.add_child(tyre)
	assert_almost_eq(PendulumScript.hang_length(hanger, 0.81, 1.74), 2.15 * 0.81, 0.01)
	# Nothing hanging at all falls back rather than dividing by zero.
	var bare := _keep(Node3D.new()) as Node3D
	assert_almost_eq(PendulumScript.hang_length(bare, 0.81, 1.74), 1.74, 0.0001)


## A prop is classified by the ASSET it came from, not by its node name. TreeA to
## TreeJ is a convention and the eleventh tree will be called something else one
## day; assets/models/vegetation/ is what the thing IS.
func test_the_farmstead_sorts_its_props_by_the_asset_they_came_from() -> void:
	assert_eq(
		FarmsteadScript.wind_group_for("res://assets/models/vegetation/tree_bare_a.glb"),
		&"wind_branches"
	)
	assert_eq(
		FarmsteadScript.wind_group_for("res://assets/models/props/tire_swing.glb"),
		&"wind_swing"
	)
	for standing in [
		"res://assets/models/props/power_pole.glb",
		"res://assets/models/props/power_wire.glb",
		"res://assets/models/buildings/tool_shed/tool_shed.glb",
		"res://assets/models/props/pickup_truck.glb",
		"",
	]:
		assert_eq(FarmsteadScript.wind_group_for(standing), &"", standing)


# --- the wind belongs to the weather ----------------------------------------
#
# THE DEFECT THESE WERE WRITTEN FOR, and it was found by another agent rather
# than by me: the wind system shipped with ONE profile and drove it under every
# sky, so a whiteout and a pale day produced the same 0.11 .. 0.90.
#
# It was nobody's decision. It fell out of the wind and the snow accumulation
# being built in parallel, and it had a consequence neither of us would have
# designed: the load's accumulation scales with SNOWFALL and its scour scales
# with WIND, so an unchanging wind made the wind BITE HARDEST IN LIGHT SNOW.
#
# GDD section 7's weather kinds differ from each other in wind and snow TOGETHER
# -- 暴雪 is both, 寒流's whole tell is 空气变得极静, 雪雾 is snow with almost no
# wind -- so a model that cannot say "still and heavy" or "dry and blowing"
# cannot express four of the six.


## The headline: two skies, two winds.
func test_a_whiteout_and_a_pale_day_do_not_get_the_same_wind() -> void:
	var map := _map()
	var day := map.profile_for(&"pale_day")
	var storm := map.profile_for(&"whiteout")
	assert_not_null(day)
	assert_not_null(storm)
	assert_true(day != storm, "the whiteout and the pale day share one profile")
	var day_mean := _mean(day)
	var storm_mean := _mean(storm)
	assert_true(
		storm_mean > day_mean * 2.0,
		"a whiteout averages %.3f against a pale day's %.3f" % [storm_mean, day_mean]
	)


## GDD section 8: 风大 → 足迹速消 → 你安全；风停 → 足迹留存 → 你被跟上. The night
## that leaves your trail intact is the night something follows it, so the
## calmest wind in the game belongs to the deepest dark -- by decision, and this
## is where the decision is written down.
func test_the_still_night_is_the_calmest_wind_in_the_game() -> void:
	var map := _map()
	var night := map.profile_for(&"deep_night")
	assert_not_null(night)
	var calmest := _mean(night)
	for profile in map.profiles:
		if profile == night:
			continue
		assert_true(
			_mean(profile) > calmest,
			"%s is calmer than the deep night" % profile.id
		)
	# ...and calm enough that TrackMask's gale term is effectively off: at this
	# strength a print keeps most of the eighty seconds its still-air decay gives.
	assert_true(calmest < 0.10, "the still night averages %.3f, which is a breeze" % calmest)


## Every look the lighting can present has a wind. A preset nothing claims falls
## back to the default, which is correct but silent, so this is the check that
## says the fallback is not doing the work.
func test_every_lighting_preset_has_a_wind_of_its_own() -> void:
	var map := _map()
	var claimed := map.claimed_presets()
	for preset in [&"flat", &"pale_day", &"sunrise", &"nightfall", &"deep_night", &"whiteout"]:
		assert_true(claimed.has(preset), "no wind claims the %s sky" % preset)
	# No look may be claimed twice: two profiles answering for one sky is a
	# lookup whose answer depends on array order.
	for preset in claimed:
		var claims := 0
		for profile in map.profiles:
			if profile.presets.has(preset):
				claims += 1
		assert_eq(claims, 1, "%s is claimed by %d profiles" % [preset, claims])


## The five winds are ordered, and the ordering is the design: still, calm,
## valley, rising, gale. A run walks up it as the week goes on.
func test_the_five_winds_are_in_the_order_the_week_needs() -> void:
	var map := _map()
	var previous := -1.0
	for id in [&"wind_still", &"wind_calm", &"wind_valley", &"wind_rising", &"wind_gale"]:
		var profile: WindProfile = map.by_id(id)
		assert_not_null(profile, id)
		if profile == null:
			continue
		var mean := _mean(profile)
		assert_true(mean > previous, "%s averages %.3f, under the one before it" % [id, mean])
		previous = mean


## ...and they differ in STRUCTURE, not only in level. A whiteout that was the
## valley wind with the volume up would still read as one weather.
func test_the_winds_differ_in_character_and_not_only_in_volume() -> void:
	var map := _map()
	var valley: WindProfile = map.by_id(&"wind_valley")
	var gale: WindProfile = map.by_id(&"wind_gale")
	var still: WindProfile = map.by_id(&"wind_still")
	# The gale gusts far more often than the valley...
	assert_true(gale.gust_seconds < valley.gust_seconds * 0.5)
	# ...with the lulls nearly closed up...
	assert_true(gale.gust_sharpness < valley.gust_sharpness * 0.75)
	# ...and the still night has no squalls at all, which is what makes it quiet
	# rather than merely weak.
	assert_almost_eq(still.squall_gain, 0.0, 0.0001)
	assert_true(still.gust_seconds > valley.gust_seconds)


## The sky changes over eight seconds and the snow over six. The wind must not
## be the one thing in the picture that steps.
func test_the_wind_crossfades_rather_than_cutting_when_the_sky_changes() -> void:
	var wind := _bare_system()
	var sky := SkyStandIn.new()
	sky.preset = PresetStandIn.new()
	sky.preset.id = &"pale_day"
	wind.set_lighting(sky)
	for i in 600:
		wind.advance(FRAME)
	var before: float = wind.strength()
	sky.preset.id = &"whiteout"
	var previous := before
	var biggest_step := 0.0
	# Forty seconds. The ease is exponential, so it approaches rather than
	# arrives: at one time constant it is 63 per cent through and at six it is
	# close enough that the crossfade releases the outgoing profile.
	for i in 2400:
		wind.advance(FRAME)
		var now: float = wind.strength()
		biggest_step = maxf(biggest_step, absf(now - previous))
		previous = now
	assert_true(
		biggest_step < 0.03,
		"the wind stepped by %.4f when the sky changed" % biggest_step
	)
	# ...and it did actually arrive, rather than easing so gently it never got
	# there. The gale's floor alone is 0.28.
	assert_eq(wind.active_profile().id, &"wind_gale")
	assert_almost_eq(wind.profile_blend(), 1.0, 0.001)


## A weather system taking the wheel keeps it. Two things easing the same number
## in opposite directions is worse than either -- the same rule `Snowfall` and
## `SnowAccumulation` already state for their own overrides.
func test_a_weather_system_that_takes_the_wheel_keeps_it() -> void:
	var wind := _bare_system()
	var sky := SkyStandIn.new()
	sky.preset = PresetStandIn.new()
	sky.preset.id = &"pale_day"
	wind.set_lighting(sky)
	wind.set_profile(load(GALE_PATH))
	sky.preset.id = &"deep_night"
	for i in 600:
		wind.advance(FRAME)
	assert_eq(wind.active_profile().id, &"wind_gale")


## A lighting director, in the one respect this reads one. RefCounted, so it
## frees itself (briefing section 2.2).
class PresetStandIn extends RefCounted:
	var id: StringName = &""


class SkyStandIn extends RefCounted:
	var preset: PresetStandIn = null

	func active_preset() -> PresetStandIn:
		return preset


## The map falls back rather than returning nothing when a sky names a look no
## profile claims -- a new preset must not stop the wind.
func test_an_unknown_sky_falls_back_instead_of_stopping_the_wind() -> void:
	var map := _map()
	var fallback: WindProfile = map.profile_for(&"eclipse")
	assert_not_null(fallback, "an unclaimed preset left the world with no wind at all")
	assert_eq(fallback.id, map.default_id)
