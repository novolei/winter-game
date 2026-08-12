extends TestCase

## 极光. Two halves, tested as two halves:
##
##   THE GROUND CAST, which is what the player actually sees at the framings the
##     game uses, and which is a HUE ROTATION that must be arithmetically
##     incapable of brightening or darkening anything. That is the whole safety
##     argument for putting a colour outside the twelve on the snow, so most of
##     the tests below are on that algebra rather than on a picture.
##
##   THE CURTAIN, which nobody can see yet -- the camera never looks up, and
##     under a parallel projection a sky shader can only ever produce one flat
##     colour anyway. Its shape is judged by capture; what is testable here is
##     that the six presets' gradient still reaches the sky material, that the
##     stars do, and that the aurora's own parameters land where the shader reads
##     them.

const AuroraScript := preload("res://src/systems/aurora_system.gd")
const AuroraDefinitionScript := preload("res://src/definitions/aurora_definition.gd")
const LightingDirectorScript := preload("res://src/rendering/lighting_director.gd")
const LightingPresetScript := preload("res://src/definitions/lighting_preset.gd")
const CameraRigScript := preload("res://src/rendering/camera_rig.gd")

const SHIPPED_PATH := "res://data/aurora/boreal_curtain.tres"
const SKY_SHADER_PATH := "res://assets/shaders/aurora_sky.gdshader"

## The generator's own table, duplicated here on purpose. See
## test_the_shipped_aurora_is_pinned_field_by_field.
const SHIPPED_RISE := 34.0
const SHIPPED_FALL := 42.0
const SHIPPED_CHANCE := 0.20
const SHIPPED_SPAN := 55.0
const SHIPPED_BASE_ELEVATION := 6.0
const SHIPPED_TOP_ELEVATION := 32.0
const SHIPPED_CAST_STRENGTH := 0.60
const SHIPPED_FILL_SHARE := 0.55
const SHIPPED_RAY_FREQUENCY := 5.4

var _nodes: Array[Node] = []


func after_each() -> void:
	# Node is not reference-counted; an un-freed one is a leaked ObjectDB
	# instance and a WARNING at exit, which fails the run (briefing section 2.2).
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _system(definitions: Array, seed_value := 12345):
	var system = AuroraScript.new()
	_nodes.append(system)
	system.load_definitions(definitions)
	system.random_seed = seed_value
	system.set_event_bus(null)
	# `attach()` is what seeds the generator, and a bare system never gets a
	# frame. Seeded directly so a draw is reproducible without a tree.
	system.set("_rng", _seeded(seed_value))
	return system


func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## A definition built in code rather than loaded, so a test can vary one field
## without touching the shipped data.
##
## `allowed_night_presets` is EMPTY here and not empty in the shipped data. That
## is not laziness: with no clock in the fixture there is no schedule to name a
## night's look, so a fixture that carried the shipped list would be refused by
## the gate rather than by the thing each test is about.
## `test_a_night_that_is_not_dark_enough_is_refused` stands a schedule up and
## exercises that gate on its own.
func _definition(id := &"test_aurora") -> AuroraDefinition:
	var definition: AuroraDefinition = AuroraDefinitionScript.new()
	definition.id = id
	definition.display_name = "TEST"
	definition.chance_per_night = 1.0
	definition.once_per_run = true
	definition.allowed_night_presets = [] as Array[StringName]
	definition.requires_clear_weather = false
	definition.start_window = Vector2(0.2, 0.2)
	definition.rise_seconds = 10.0
	definition.hold_seconds = Vector2(20.0, 20.0)
	definition.fall_seconds = 10.0
	definition.bearing_degrees = Vector2(35.0, 35.0)
	definition.band_colors = [Color(0.3, 0.9, 0.6), Color(0.2, 0.7, 0.6), Color(0.1, 0.5, 0.6)] as Array[Color]
	definition.ground_cast_color = Color(0.5, 0.84, 0.75)
	definition.ground_cast_strength = 0.3
	return definition


# ---------------------------------------------------------------------------
# THE ALGEBRA: a light that cannot change how bright anything is
# ---------------------------------------------------------------------------
#
# Every one of these is the same claim from a different side, and together they
# are the reason a teal outside the 12-colour table is allowed onto the snow:
# the cast reaches only the LIT cel band, and it is a pure hue rotation, so it
# cannot take the shade band off-palette, cannot dim the frame the exposure was
# tuned for, and cannot push anything across the glow's 0.95 threshold. "No bloom
# on the snow" is structural rather than a value someone kept an eye on.

func test_a_unit_tint_has_luminance_one_at_every_strength() -> void:
	var colours := [
		Color(0.5, 0.84, 0.75), Color(1.0, 0.2, 0.1),
		Color(0.05, 0.05, 0.9), Color(0.34, 0.89, 0.61),
	]
	for colour in colours:
		for step in range(0, 11):
			var strength := float(step) / 10.0
			var tint := LightingDirectorScript.unit_tint(colour, strength)
			assert_almost_eq(
				LightingDirectorScript.luminance(tint), 1.0, 0.0005,
				"unit_tint(%s, %.1f) must have luminance 1" % [colour.to_html(false), strength]
			)


func test_composing_with_white_is_the_identity() -> void:
	# The six presets have to be exactly where they were on every frame in which
	# no overlay is running, which is nearly all of them.
	var base := LightingDirectorScript.unit_tint(Color(1.0, 0.698, 0.341), 0.42)
	var composed := LightingDirectorScript.compose_tint(base, Color.WHITE)
	assert_almost_eq(composed.r, base.r, 0.0005, "red must be untouched")
	assert_almost_eq(composed.g, base.g, 0.0005, "green must be untouched")
	assert_almost_eq(composed.b, base.b, 0.0005, "blue must be untouched")


func test_composing_two_rotations_is_still_a_rotation() -> void:
	# The product of two unit-luminance colours is NOT unit luminance. This is the
	# one place brightness could have leaked into a channel that carries none.
	var sunrise := LightingDirectorScript.unit_tint(Color(1.0, 0.698, 0.341), 0.42)
	var aurora := LightingDirectorScript.unit_tint(Color(0.5, 0.84, 0.75), 1.0)
	var raw := Color(sunrise.r * aurora.r, sunrise.g * aurora.g, sunrise.b * aurora.b)
	assert_false(
		absf(LightingDirectorScript.luminance(raw) - 1.0) < 0.0005,
		"the bare product is expected to drift off unit luminance -- if it does not, "
		+ "this test is no longer proving that compose_tint's renormalisation is load-bearing"
	)
	var composed := LightingDirectorScript.compose_tint(sunrise, aurora)
	assert_almost_eq(
		LightingDirectorScript.luminance(composed), 1.0, 0.0005,
		"...and composing them must put it back"
	)


func test_rotating_a_hue_keeps_the_fills_own_brightness() -> void:
	# The character's ambient. It has a luminance of its own and the overlay has
	# no business moving it: a man who got brighter when the sky went green would
	# read as a rendering fault, and there is no HUD to say otherwise.
	var fill := Color(0.859451, 0.90086275, 0.9510588)
	var before := LightingDirectorScript.luminance(fill)
	for strength in [0.0, 0.25, 0.55, 1.0]:
		var tint := LightingDirectorScript.unit_tint(Color(0.5, 0.84, 0.75), strength)
		var rotated := LightingDirectorScript.rotate_hue(fill, tint)
		assert_almost_eq(
			LightingDirectorScript.luminance(rotated), before, 0.0005,
			"the fill's luminance must survive a rotation at strength %.2f" % strength
		)


func test_the_cast_actually_moves_the_hue() -> void:
	# The other half of the pair above: a rotation that changed nothing would pass
	# every luminance assertion in this file and put no aurora on the snow.
	var tint := LightingDirectorScript.unit_tint(Color(0.5, 0.84, 0.75), SHIPPED_CAST_STRENGTH)
	assert_true(tint.g > tint.r, "the cast must push green above red")
	assert_true(tint.b > tint.r, "...and blue above red -- it is a teal, not a green")
	assert_true(
		tint.r < 0.93,
		"and it must move far enough to be seen: red was %.3f of white" % tint.r
	)


# ---------------------------------------------------------------------------
# RARITY
# ---------------------------------------------------------------------------

## The gate the shipped aurora actually runs behind: only a night the day
## schedule dresses in DEEP NIGHT. Nights 1 and 2 wear NIGHTFALL, which is a
## dusk and is too bright to hold a curtain; nights 6 and 7 are the storm.
##
## By the PRESET rather than by the night number, so a schedule edit that makes
## another night dark makes it eligible with no code change -- which is what the
## test below the fixture proves by moving only the schedule.
func test_a_night_that_is_not_dark_enough_is_refused() -> void:
	var definition := _definition()
	definition.allowed_night_presets = [&"deep_night"] as Array[StringName]

	var dark = _system([definition])
	dark.set_world_clock(_clock_wearing(&"deep_night"))
	assert_true(dark.plan_night(4, 420.0) != null, "a DEEP NIGHT night must be eligible")

	var dusk = _system([definition])
	dusk.set_world_clock(_clock_wearing(&"nightfall"))
	assert_true(dusk.plan_night(2, 420.0) == null, "a dusk must not carry one")

	var storm = _system([definition])
	storm.set_world_clock(_clock_wearing(&"whiteout"))
	assert_true(storm.plan_night(7, 660.0) == null, "and neither must the storm")


## The clock, as the aurora system consumes it: one duck-typed
## `schedule_for_day()` returning the real DaySchedule resource. A Resource frees
## itself, so there is nothing to clean up.
class ClockStub:
	extends RefCounted
	var schedule = null
	func schedule_for_day(_day: int):
		return schedule


func _clock_wearing(preset: StringName) -> ClockStub:
	var schedule = preload("res://src/definitions/day_schedule.gd").new()
	schedule.night_lighting_preset = preset
	var clock := ClockStub.new()
	clock.schedule = schedule
	return clock


func test_only_one_showing_per_run() -> void:
	var system = _system([_definition()])
	assert_true(system.plan_night(3, 420.0) != null, "the first night must be able to draw one")
	assert_true(system.has_shown_this_run() == false, "planning is not showing")
	system.begin(&"test_aurora")
	assert_true(system.has_shown_this_run(), "beginning one records it")
	system.clear_now()
	assert_true(system.plan_night(4, 420.0) == null, "a second night must be refused for the run")


func test_a_night_too_short_for_the_whole_arc_is_refused() -> void:
	var definition := _definition()
	# 10 rise + 20 hold + 10 fall = 40 s.
	var system = _system([definition])
	assert_true(system.plan_night(4, 39.0) == null, "a 39 s night cannot hold a 40 s arc")
	assert_true(system.plan_night(4, 41.0) != null, "a 41 s night can")


## THE RARITY, AS A MEASURED RATE RATHER THAN A NUMBER IN A FILE.
##
## The whole design claim is "rare enough to be a surprise, common enough to
## exist", and that is a property of the run and not of the constant. So: three
## eligible nights per run at the shipped chance, over two thousand runs.
##
## The band is deliberately wide -- this asserts the DECISION, not the RNG. If it
## fails, someone changed how often the sky puts on a curtain, and that is a
## conversation rather than a tuning value.
func test_an_aurora_lands_in_about_half_of_all_runs() -> void:
	var runs := 2000
	var seen := 0
	var definition := _definition()
	definition.chance_per_night = SHIPPED_CHANCE
	for run in range(runs):
		var system = AuroraScript.new()
		system.load_definitions([definition])
		system.set("_rng", _seeded(9000 + run))
		var hit := false
		for night in [3, 4, 5]:
			if system.plan_night(night, 420.0) != null:
				hit = true
				# One per run: record it the way a real showing would.
				system.set("_shown_this_run", true)
				system.set("_phase", &"clear")
		# Freed here rather than deferred: there is no assertion inside this loop
		# to abort it, and two thousand live Nodes waiting on after_each() is a
		# needless heap. Node is not reference-counted (briefing constraint 2).
		system.free()
		if hit:
			seen += 1
	var rate := float(seen) / float(runs)
	# 1 - 0.8^3 = 0.488.
	assert_true(
		rate > 0.42 and rate < 0.56,
		"an aurora should reach a little under half of all runs; measured %.3f over %d runs" % [rate, runs]
	)


func test_a_run_never_holds_two() -> void:
	var definition := _definition()
	definition.chance_per_night = 1.0
	for run in range(200):
		var system = AuroraScript.new()
		_nodes.append(system)
		system.load_definitions([definition])
		system.set("_rng", _seeded(4000 + run))
		var drawn := 0
		for night in [3, 4, 5]:
			if system.plan_night(night, 420.0) != null:
				drawn += 1
				system.set("_shown_this_run", true)
				system.set("_phase", &"clear")
		assert_eq(drawn, 1, "at a certainty of 1.0 a run must still draw exactly one")


# ---------------------------------------------------------------------------
# THE ARC
# ---------------------------------------------------------------------------

func test_the_envelope_runs_from_nothing_to_full_and_back() -> void:
	var system = _system([_definition()])
	assert_almost_eq(system.strength(), 0.0, 0.0001, "nothing before it starts")
	system.begin(&"test_aurora")
	assert_almost_eq(system.strength(), 0.0, 0.0001, "and nothing on the frame it opens")
	system.advance(10.0)
	assert_almost_eq(system.strength(), 1.0, 0.0001, "full at the end of the rise")
	system.advance(20.0)
	assert_almost_eq(system.strength(), 1.0, 0.0001, "and through the hold")
	system.advance(10.0)
	assert_almost_eq(system.strength(), 0.0, 0.0001, "and back to nothing")
	assert_false(system.is_showing(), "and it is over")


## NOTHING POPS. The owner's 切记不能突变, and the same sweep
## `test_the_intensity_never_steps_across_a_whole_event` runs against the
## weather. A hue shift across the whole frame is exactly the kind of change a
## step would betray.
func test_the_cast_never_steps_across_a_whole_showing() -> void:
	var system = _system([_definition()])
	system.begin(&"test_aurora")
	var previous := system.strength()
	var worst := 0.0
	for tick in range(1200):
		system.advance(0.05)
		var now := system.strength()
		worst = maxf(worst, absf(now - previous))
		previous = now
	# A 10 s smoothstep moves at most 1.5/10 per second at its steepest, so 0.05 s
	# can move 0.0075. Anything near a tenth is a cut.
	assert_true(
		worst < 0.02,
		"the envelope must never jump; the worst step in a whole showing was %.4f" % worst
	)


func test_an_interrupted_rise_falls_from_where_it_actually_is() -> void:
	var system = _system([_definition()])
	system.begin(&"test_aurora")
	system.advance(3.0)
	var reached := system.strength()
	assert_true(reached > 0.02 and reached < 0.5, "part-way up, got %.3f" % reached)
	# Daybreak, halfway through the rise.
	system._on_day_started(4)
	assert_almost_eq(
		system.strength(), reached, 0.0005,
		"the frame must not brighten on the tick it was told to stop"
	)
	system.advance(0.5)
	assert_true(system.strength() < reached, "...and it must be going down from there")


func test_weather_arriving_ends_the_showing() -> void:
	var definition := _definition()
	definition.requires_clear_weather = true
	var system = _system([definition])
	var weather := _fake_weather(&"clear")
	system.set_weather_system(weather)
	system.begin(&"test_aurora")
	system.advance(12.0)
	assert_eq(String(system.phase()), "hold", "it should be holding")
	weather.set("phase_value", &"tell")
	system.advance(0.1)
	assert_eq(String(system.phase()), "fall", "a warning in the sky must take it back")


func test_it_waits_for_the_weather_rather_than_losing_the_night() -> void:
	var definition := _definition()
	definition.requires_clear_weather = true
	definition.start_window = Vector2(0.05, 0.05)
	var system = _system([definition])
	var weather := _fake_weather(&"active")
	system.set_weather_system(weather)
	assert_true(system.plan_night(4, 400.0) != null, "the night is drawn")
	system.advance(30.0)
	assert_true(system.is_armed(), "it must still be waiting rather than cancelled")
	assert_false(system.is_showing(), "and nothing is in the sky")
	weather.set("phase_value", &"clear")
	system.advance(0.1)
	assert_true(system.is_showing(), "...and it opens the moment the sky clears")


func test_it_gives_up_when_the_night_has_got_away() -> void:
	var definition := _definition()
	definition.requires_clear_weather = true
	definition.start_window = Vector2(0.05, 0.05)
	var system = _system([definition])
	var weather := _fake_weather(&"active")
	system.set_weather_system(weather)
	system.plan_night(4, 400.0)
	# give_up_fraction is 0.62, so 248 s of a 400 s night.
	system.advance(260.0)
	assert_false(system.is_armed(), "past the deadline it must stop waiting")
	assert_false(system.is_showing(), "and it must not open with no night left to hold it")


## The weather, as the aurora system actually consumes it: one duck-typed
## `phase()`. An inner class rather than a file, because the runner discovers
## every `test_*.gd` under tests/ and fails any that yields no test methods --
## and RefCounted frees itself, so there is nothing to leak.
class WeatherStub:
	extends RefCounted
	var phase_value: StringName = &"clear"
	func phase() -> StringName:
		return phase_value


func _fake_weather(phase_value: StringName) -> WeatherStub:
	var stub := WeatherStub.new()
	stub.phase_value = phase_value
	return stub


# ---------------------------------------------------------------------------
# IT NEVER REPEATS
# ---------------------------------------------------------------------------

## The Director's requirement, as a property rather than as a look: an aurora
## that loops is a texture on a plane.
##
## The breath is two sines whose frequencies are in an irrational ratio, so the
## combined figure has no period at all. This searches for one: for every
## candidate period up to ten minutes, at a resolution finer than the faster
## sine, is there any period the whole trace repeats on? There must not be.
func test_the_breath_has_no_period_a_session_could_contain() -> void:
	var system = _system([_definition()])
	var best_period := 0.0
	var best_error := INF
	var samples := 48
	# Every candidate period from 2 s to 300 s at a quarter-second resolution --
	# five minutes is longer than anyone stands still, and the faster of the two
	# sines has a 9.4 s period, so this samples each candidate many times over.
	for period_step in range(8, 1200):
		var period := float(period_step) * 0.25
		var error := 0.0
		for index in range(samples):
			var t := float(index) * 0.37
			error = maxf(error, absf(system.breath_at(t) - system.breath_at(t + period)))
		if error < best_error:
			best_error = error
			best_period = period
	assert_true(
		best_error > 0.01,
		"the breath repeats every %.1f s to within %.4f -- that is a loop, not weather"
			% [best_period, best_error]
	)


func test_the_breath_can_only_dim_never_brighten() -> void:
	var system = _system([_definition()])
	var low := INF
	var high := -INF
	for index in range(6000):
		var value: float = system.breath_at(float(index) * 0.13)
		low = minf(low, value)
		high = maxf(high, value)
	assert_true(high <= 1.0001, "the breath must never exceed the envelope, peaked at %.4f" % high)
	assert_true(
		low >= 1.0 - system.breath_depth - 0.0001,
		"...and must not go below the authored depth, bottomed at %.4f" % low
	)
	assert_true(high - low > 0.1, "and it must actually breathe, range was %.4f" % (high - low))


# ---------------------------------------------------------------------------
# THE SEAM FOR THE LOOK-UP
# ---------------------------------------------------------------------------

func test_the_published_direction_matches_the_published_angles() -> void:
	var system = _system([_definition()])
	system.begin(&"test_aurora")
	var direction: Vector3 = system.look_direction()
	assert_almost_eq(direction.length(), 1.0, 0.0005, "the seam must publish a unit vector")
	var bearing := rad_to_deg(atan2(direction.x, -direction.z))
	var elevation := rad_to_deg(asin(direction.y))
	assert_almost_eq(bearing, system.bearing_degrees(), 0.01, "bearing must agree with the vector")
	assert_almost_eq(elevation, system.elevation_degrees(), 0.01, "elevation must agree with the vector")
	assert_true(
		system.elevation_degrees() > 0.0,
		"and it must point ABOVE the horizon, which is the only reason a camera would lean"
	)


## THE COUPLING, WRITTEN DOWN -- the same shape test_aerial_perspective.gd uses
## for the fog window and the boom.
##
## The rig never rotates, so the direction the camera faces is a constant of the
## game: yaw -35 degrees is a world heading of +35. A curtain drawn outside that
## bracket would be behind the player, and an upward lean would find an empty
## sky. Read off CameraRig rather than duplicated, so moving the yaw fails here
## instead of silently aiming the aurora at nothing.
func test_the_curtain_hangs_where_the_camera_already_faces() -> void:
	var rig = CameraRigScript.new()
	_nodes.append(rig)
	var heading: float = -rig.yaw_degrees
	var shipped := load(SHIPPED_PATH) as AuroraDefinition
	assert_not_null(shipped, "the shipped aurora must load")
	assert_true(
		shipped.bearing_degrees.x <= heading and shipped.bearing_degrees.y >= heading,
		"the bearing range %s must bracket the camera's own heading of %.1f degrees"
			% [shipped.bearing_degrees, heading]
	)
	assert_true(
		shipped.bearing_degrees.y - shipped.bearing_degrees.x > 10.0,
		"...and it must still vary between showings, or every aurora is in the same place"
	)


func test_the_began_event_carries_everything_a_camera_cue_needs() -> void:
	var bus := preload("res://src/core/event_bus.gd").new()
	_nodes.append(bus)
	var system = _system([_definition()])
	var seen: Array = []
	var handler := func(payload): seen.append(payload)
	bus.subscribe(&"aurora.began", handler)
	system.set_event_bus(bus)
	system.begin(&"test_aurora")
	assert_eq(seen.size(), 1, "one aurora.began")
	var payload: Dictionary = seen[0]
	for key in ["id", "bearing_degrees", "elevation_degrees", "direction", "seconds", "rise_seconds"]:
		assert_true(payload.has(key), "the payload must carry '%s'" % key)
	assert_true(payload["direction"] is Vector3, "direction must be a world vector")
	bus.unsubscribe(&"aurora.began", handler)


# ---------------------------------------------------------------------------
# THE SHIPPED DATA
# ---------------------------------------------------------------------------

## ResourceSaver omits any value equal to the script's default, so most of
## data/aurora/boreal_curtain.tres is inherited from aurora_definition.gd at load
## time. Retune a default there believing it is a fallback and the shipped aurora
## changes with nothing in the file to show it -- exactly the defect
## tests/unit/test_wind.gd was extended to stop for the wind profiles.
##
## So the shipped values are pinned here, field by field, against the generator's
## own table.
func test_the_shipped_aurora_is_pinned_field_by_field() -> void:
	var shipped := load(SHIPPED_PATH) as AuroraDefinition
	assert_not_null(shipped, "the shipped aurora must load from %s" % SHIPPED_PATH)
	assert_eq(String(shipped.id), "boreal_curtain")
	assert_almost_eq(shipped.chance_per_night, SHIPPED_CHANCE, 0.0001)
	assert_true(shipped.once_per_run, "one per run")
	assert_eq(shipped.allowed_night_presets.size(), 1)
	assert_eq(String(shipped.allowed_night_presets[0]), "deep_night")
	assert_true(shipped.requires_clear_weather, "an aurora inside a storm is a green smear")
	assert_almost_eq(shipped.rise_seconds, SHIPPED_RISE, 0.0001)
	assert_almost_eq(shipped.fall_seconds, SHIPPED_FALL, 0.0001)
	assert_almost_eq(shipped.span_degrees, SHIPPED_SPAN, 0.0001)
	assert_almost_eq(shipped.base_elevation_degrees, SHIPPED_BASE_ELEVATION, 0.0001)
	assert_almost_eq(shipped.top_elevation_degrees, SHIPPED_TOP_ELEVATION, 0.0001)
	assert_almost_eq(shipped.ground_cast_strength, SHIPPED_CAST_STRENGTH, 0.0001)
	assert_almost_eq(shipped.character_fill_share, SHIPPED_FILL_SHARE, 0.0001)
	assert_almost_eq(shipped.ray_frequency, SHIPPED_RAY_FREQUENCY, 0.0001)
	assert_eq(shipped.band_colors.size(), 3, "three overlapping curtains, not one sheet")


## Art Bible section 4.1 and rule 12 both govern ALBEDO; sky, fog, ambient and
## light colour are atmosphere and are not bound by the twelve -- the Director's
## boundary against Docs/style optimization.md. This pins the OTHER half of that:
## the aurora's colours are indeed outside the table, deliberately, and the thing
## that makes it safe is that they never touch an albedo.
func test_the_aurora_is_atmosphere_and_says_so() -> void:
	var bible = load("res://data/palette/color_bible.tres")
	var shipped := load(SHIPPED_PATH) as AuroraDefinition
	assert_false(
		bible.contains(shipped.ground_cast_color),
		"the cast is deliberately outside the twelve -- if it is now inside them, "
		+ "someone has replaced an aurora with a palette tone"
	)
	for index in range(shipped.band_colors.size()):
		assert_false(
			bible.contains(shipped.band_colors[index]),
			"band %d is atmosphere, not albedo" % index
		)
	# ...and the safety argument, restated as arithmetic: whatever the colour is,
	# what reaches a shader has luminance 1.
	var tint := LightingDirectorScript.unit_tint(
		shipped.ground_cast_color, shipped.ground_cast_strength)
	assert_almost_eq(
		LightingDirectorScript.luminance(tint), 1.0, 0.0005,
		"and it can only ever rotate the hue"
	)


# ---------------------------------------------------------------------------
# THE SKY
# ---------------------------------------------------------------------------

func test_the_sky_shader_exists_and_is_a_sky_shader() -> void:
	assert_true(FileAccess.file_exists(SKY_SHADER_PATH), "the sky shader must be a file on disk")
	var code := FileAccess.get_file_as_string(SKY_SHADER_PATH)
	assert_true(code.begins_with("shader_type sky;"), "it must be a sky shader")
	# The three things the reference frame is made of, each of which is a
	# requirement rather than a flourish -- if one is deleted the shader still
	# compiles and still draws something green.
	assert_true(code.contains("aurora_ray_frequency"), "the vertical striations")
	assert_true(code.contains("star_field"), "the stars showing through it")
	assert_true(code.contains("aurora_color_c"), "the third overlapping curtain")


## The gradient the six presets were authored against, mirrored here in GDScript
## the way ChimneySmoke mirrors its own shader's arithmetic. The claim is that
## swapping ProceduralSkyMaterial for a custom shader moves none of the six: at
## the zenith the sky is still exactly the preset's zenith colour and at the
## horizon exactly its horizon colour, whatever the curve.
func test_the_gradient_still_ends_where_the_presets_put_it() -> void:
	var zenith := Color(0.11, 0.165, 0.271)
	var horizon := Color(0.2, 0.286, 0.431)
	for curve in [0.05, 0.15, 0.5, 1.0]:
		var top := _sky_gradient(1.0, zenith, horizon, curve)
		var edge := _sky_gradient(0.0, zenith, horizon, curve)
		assert_almost_eq(top.r, zenith.r, 0.001, "the zenith at curve %.2f" % curve)
		assert_almost_eq(top.b, zenith.b, 0.001, "the zenith at curve %.2f" % curve)
		assert_almost_eq(edge.r, horizon.r, 0.001, "the horizon at curve %.2f" % curve)
		assert_almost_eq(edge.b, horizon.b, 0.001, "the horizon at curve %.2f" % curve)
	# ...and it is monotone between them, which is what makes it a gradient rather
	# than a shape.
	var previous := -1.0
	for step in range(0, 21):
		var height := float(step) / 20.0
		var value := _sky_gradient(height, zenith, horizon, 0.15).b
		if previous >= 0.0:
			assert_true(value <= previous + 0.0005, "the gradient must not reverse")
		previous = value


## assets/shaders/aurora_sky.gdshader, lines for line.
func _sky_gradient(eye_y: float, zenith: Color, horizon: Color, curve: float) -> Color:
	var v_angle := acos(clampf(eye_y, -1.0, 1.0))
	var c := 1.0 - v_angle / (PI * 0.5)
	var t := clampf(1.0 - pow(1.0 - c, 1.0 / maxf(curve, 0.001)), 0.0, 1.0)
	return horizon.lerp(zenith, t)


## The preset's own sky and stars must actually reach the material. Built with a
## real node, because the material is created in _build_environment() and this is
## the wiring rather than the arithmetic.
func test_the_preset_reaches_the_sky_material() -> void:
	var director = LightingDirectorScript.new()
	_nodes.append(director)
	director.debug_controls_enabled = false
	director._ready()
	var look: LightingPreset = LightingPresetScript.new()
	look.id = &"probe"
	look.sky_zenith_color = Color(0.1, 0.2, 0.3)
	look.sky_horizon_color = Color(0.4, 0.5, 0.6)
	look.sky_curve = 0.27
	look.star_amount = 0.77
	director.apply_look(look)
	var material: ShaderMaterial = director.sky_material()
	assert_not_null(material, "the director must build a sky material")
	assert_not_null(material.shader, "...with the sky shader on it")
	assert_eq(material.shader.resource_path, SKY_SHADER_PATH)
	var top: Color = material.get_shader_parameter("sky_top_color")
	assert_almost_eq(top.b, 0.3, 0.0005, "the preset's zenith must reach the shader")
	assert_almost_eq(
		float(material.get_shader_parameter("sky_curve")), 0.27, 0.0005, "and its curve")
	assert_almost_eq(
		float(material.get_shader_parameter("star_amount")), 0.77, 0.0005, "and its stars")
	# THE DOUBLE-APPLY GUARD. The preset's sky energy belongs on the Environment's
	# background_energy_multiplier, where it lived under the stock material.
	# Setting it on the shader as well would square it.
	assert_almost_eq(
		float(material.get_shader_parameter("sky_energy")), 1.0, 0.0005,
		"the shader's own energy must stay at one"
	)


func test_the_stars_fade_in_over_a_crossfade() -> void:
	var dusk: LightingPreset = LightingPresetScript.new()
	dusk.id = &"dusk"
	dusk.star_amount = 0.0
	var night: LightingPreset = LightingPresetScript.new()
	night.id = &"night"
	night.star_amount = 1.0
	assert_almost_eq(
		LightingDirectorScript.blend(dusk, night, 0.5).star_amount, 0.5, 0.0005,
		"stars must come out over the dusk, not switch on at its midpoint"
	)


func test_the_two_dark_looks_are_the_only_ones_with_stars() -> void:
	var expected := {
		"flat": 0.0, "pale_day": 0.0, "sunrise": 0.0,
		"nightfall": 0.25, "deep_night": 1.0, "whiteout": 0.0,
	}
	for id in expected:
		var preset := load("res://data/lighting/%s.tres" % id) as LightingPreset
		assert_not_null(preset, "%s must load" % id)
		assert_almost_eq(
			preset.star_amount, float(expected[id]), 0.0005,
			"%s must carry %.2f stars" % [id, float(expected[id])]
		)


# ---------------------------------------------------------------------------
# THE OVERLAY, END TO END THROUGH THE DIRECTOR
# ---------------------------------------------------------------------------

func test_the_overlay_reaches_the_world_and_the_character() -> void:
	var director = LightingDirectorScript.new()
	_nodes.append(director)
	director.debug_controls_enabled = false
	director._ready()
	var look: LightingPreset = LightingPresetScript.new()
	look.id = &"probe"
	look.ambient_color = Color(0.86, 0.90, 0.95)
	look.ambient_energy = 1.5
	director.apply_look(look)

	var before: Color = director.world_light_tint()
	assert_almost_eq(before.r, 1.0, 0.0005, "with no overlay the world tint is white")
	var fill_before: Color = director.environment.ambient_light_color
	var fill_luma := LightingDirectorScript.luminance(fill_before)

	director.set_world_light_overlay(Color(0.5, 0.84, 0.75), 0.30, 0.165)
	var after: Color = director.world_light_tint()
	assert_true(after.g > after.r, "the snow's lit band must go teal")
	assert_almost_eq(
		LightingDirectorScript.luminance(after), 1.0, 0.0005,
		"...and it must still be unable to change how bright anything is"
	)
	var fill_after: Color = director.environment.ambient_light_color
	assert_true(fill_after.g > fill_before.g, "the character's fill must follow the sky")
	assert_almost_eq(
		LightingDirectorScript.luminance(fill_after), fill_luma, 0.0005,
		"...without getting brighter"
	)
	assert_true(
		1.0 - after.r > (1.0 - fill_after.r / fill_before.r) * 0.5,
		"and he must take LESS of it than the snow does -- his coat is the frame's "
		+ "only blue-grey and has no business going teal"
	)

	director.set_world_light_overlay(Color.WHITE, 0.0, 0.0)
	assert_almost_eq(
		director.world_light_tint().r, before.r, 0.0005, "and it must come all the way back")
	assert_almost_eq(
		director.environment.ambient_light_color.g, fill_before.g, 0.0005,
		"...including the fill")


## The system drives the director through duck-typed calls only, so this is the
## join: an aurora running must actually turn the snow.
func test_a_running_aurora_turns_the_snow() -> void:
	var director = LightingDirectorScript.new()
	_nodes.append(director)
	director.debug_controls_enabled = false
	director._ready()
	director.apply_look(LightingPresetScript.new())
	var system = _system([_definition()])
	system.set_lighting(director)
	assert_almost_eq(director.world_light_tint().r, 1.0, 0.0005, "white before")
	system.begin(&"test_aurora")
	# Stepped at 60 Hz through the whole 40 s arc rather than in two big jumps,
	# because that is the path the game runs and because the epsilon guard on the
	# repaint only means anything against realistic deltas.
	var peak_tint := Color.WHITE
	var peak_sky := 0.0
	for tick in range(2700):
		system.advance(1.0 / 60.0)
		var now: Color = director.world_light_tint()
		if 1.0 - now.r > 1.0 - peak_tint.r:
			peak_tint = now
		peak_sky = maxf(peak_sky, float(director.sky_material().get_shader_parameter("aurora_strength")))
	assert_true(peak_tint.g > peak_tint.r + 0.02, "the snow must be measurably teal at the peak")
	assert_true(peak_tint.b > peak_tint.r, "...and teal rather than green")
	assert_true(peak_sky > 0.7, "and the sky must have carried the same showing, peaked at %.3f" % peak_sky)
	assert_false(system.is_showing(), "the showing must be over after its whole arc")
	assert_almost_eq(
		director.world_light_tint().r, 1.0, 0.0005, "and hand it all back when it is over")
	assert_almost_eq(
		float(director.sky_material().get_shader_parameter("aurora_strength")), 0.0, 0.0005,
		"...sky included")
