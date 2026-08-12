extends TestCase

## 切记突变 -- the snow must never pop, and this file is where that stops being
## an intention and becomes a property.
##
## The owner has asked for it twice, in two different contexts, and the brief
## for this task says a test that asserts continuity across a transition is
## worth more than a test that asserts any particular depth. So almost nothing
## here checks a value. What it checks is that no input can put a STEP in the
## picture -- not a weather event, not a day rolling over, not a debug hotkey
## cutting the lighting on one frame, not a Wave 3 weather system that writes
## its output instead of easing it.
##
## Two claims, and they are different claims:
##
##   THE VALUE cannot step, because it is an integral. One frame moves it by
##   rate * delta and nothing else can reach it.
##   THE SLOPE cannot step either, because the rate is itself slew-limited. This
##   is the one a design would be likeliest to skip, and the one that decides
##   whether a weather cut reads as weather or as a glitch: a value that is
##   merely continuous can still turn a corner, and a corner in something moving
##   this slowly is visible as a lurch.
##
## The second half of the file is the shader's arithmetic, mirrored in GDScript
## and asserted against CelPainter's constants -- because the place a pop would
## actually appear is not in the scalar at all. It is on a ROOF PLANE, which has
## one world normal across the whole of it and would therefore flip from bare to
## white in a single frame under a bare normal.y threshold, however smoothly the
## scalar moved. See test_a_flat_plane_whitens_across_minutes_rather_than_at_once.

const AccumulationScript := preload("res://src/systems/snow_accumulation.gd")
const CelPainterScript := preload("res://src/rendering/cel_painter.gd")
const PALETTE_PATH := "res://data/palette/color_bible.tres"

const FRAME := 1.0 / 60.0

var _snow: SnowAccumulation
var _sky: WeatherStandIn


## A Snowfall in the only two respects this reads one. RefCounted, so it frees
## itself (briefing section 2.2).
class WeatherStandIn extends RefCounted:
	var snowfall := 0.0
	var wind := 0.0

	func snowfall_rate() -> float:
		return snowfall

	func wind_strength() -> float:
		return wind


func before_each() -> void:
	_sky = WeatherStandIn.new()
	_snow = AccumulationScript.new()
	_snow.set_snowfall_source(_sky)


## Node is not reference counted (briefing section 2.2).
func after_each() -> void:
	if _snow != null:
		_snow.free()
		_snow = null
	_sky = null


## Runs the model for `seconds` at a fixed frame time, returning the trace of
## covers and rates. Fixed rather than real, so the assertions below are about
## the model and never about how busy the machine was.
func _run(seconds: float) -> Dictionary:
	var covers := PackedFloat32Array()
	var rates := PackedFloat32Array()
	var steps := int(seconds / FRAME)
	for _step in range(steps):
		_snow.advance(FRAME)
		covers.append(_snow.cover())
		rates.append(_snow.rate())
	return {"cover": covers, "rate": rates}


func _largest_jump(values: PackedFloat32Array) -> float:
	var worst := 0.0
	for index in range(1, values.size()):
		worst = maxf(worst, absf(values[index] - values[index - 1]))
	return worst


# ---------------------------------------------------------------------------
# The value cannot step
# ---------------------------------------------------------------------------


## THE TEST THE TASK IS JUDGED ON. A weather event does not set the snow depth,
## it changes the rate at which the depth moves.
##
## The two weathers here are the real ones: PALE DAY's 0.12 and WHITEOUT's 1.0,
## from Snowfall.storm_by_preset. Their equilibria are 0.375 and 0.833, so a
## design that assigned a depth from a state would move the world by 0.46 on the
## frame the storm arrives. This asserts that the frame it arrives on moves
## nothing at all, and that the ten seconds after it move less than a twentieth.
func test_a_weather_event_moves_the_rate_and_not_the_depth() -> void:
	_sky.snowfall = 0.12
	_snow.settle()
	var before := _snow.cover()

	# The cut. Not a fade: this is the debug hotkey, the capture harness, and
	# whatever Wave 3's weather system does on its worst frame.
	_sky.snowfall = 1.0
	_snow.advance(FRAME)
	assert_almost_eq(
		_snow.cover(), before, 0.0005,
		"the frame the storm landed on moved the snow itself, so the depth is being "
		+ "assigned from the weather rather than integrated from it"
	)

	var trace := _run(10.0)
	var covers: PackedFloat32Array = trace["cover"]
	var after_ten: float = covers[covers.size() - 1]
	# A tenth of the whole range, against a journey of about 0.46. Ten seconds
	# into the worst weather in the game the world has barely begun to change.
	assert_true(
		absf(after_ten - before) < 0.10,
		"ten seconds after the storm the cover had already moved %.3f -- it is meant to "
			% absf(after_ten - before)
			+ "walk there over minutes"
	)
	assert_true(
		_largest_jump(trace["cover"]) < 0.0006,
		"the largest single frame moved the cover by %.5f" % _largest_jump(trace["cover"])
	)


## The other half of the same claim, in the other direction: a storm ending is
## as much a transition as a storm arriving, and a model that only guards one of
## them guards neither.
func test_a_storm_ending_is_as_gradual_as_a_storm_arriving() -> void:
	_sky.snowfall = 1.0
	_snow.settle()
	var before := _snow.cover()
	_sky.snowfall = 0.0
	_snow.advance(FRAME)
	assert_almost_eq(
		_snow.cover(), before, 0.0005, "the snow came off the moment the sky cleared"
	)
	var trace := _run(30.0)
	assert_true(
		_largest_jump(trace["cover"]) < 0.0006,
		"the largest single frame moved the cover by %.5f" % _largest_jump(trace["cover"])
	)
	assert_true(
		_snow.cover() < before, "thirty seconds of clear sky took nothing off at all"
	)


## The day rolling over is the other transition the brief names, and it arrives
## by a different route -- an EventBus event rather than a weather reading. It
## must not be a special case, and the point of the model is that it is not one:
## the night moves how much settled snow sheds, which moves the rate, which the
## same two integrators absorb.
func test_the_day_rolling_over_does_not_step_the_snow() -> void:
	_sky.snowfall = 0.28
	_snow.settle()
	_run(2.0)
	var before := _snow.cover()

	_snow._on_night_started(4)
	_snow.advance(FRAME)
	assert_almost_eq(
		_snow.cover(), before, 0.0005, "nightfall moved the snow on the frame it landed"
	)
	var night := _run(20.0)
	assert_true(
		_largest_jump(night["cover"]) < 0.0006,
		"nightfall stepped the snow by %.5f on one frame" % _largest_jump(night["cover"])
	)

	# ...and back again at dawn, which is the same boundary crossed the other
	# way and is where an asymmetric guard would show up.
	var dawn_before := _snow.cover()
	_snow._on_day_started(5)
	_snow.advance(FRAME)
	assert_almost_eq(_snow.cover(), dawn_before, 0.0005, "dawn moved the snow on the frame it landed")
	var day := _run(20.0)
	assert_true(
		_largest_jump(day["cover"]) < 0.0006,
		"dawn stepped the snow by %.5f on one frame" % _largest_jump(day["cover"])
	)


# ---------------------------------------------------------------------------
# The slope cannot step either
# ---------------------------------------------------------------------------


## The claim a merely-continuous value would fail. If the rate followed the
## weather outright, the cover would still be continuous -- and it would turn a
## visible corner on the frame the storm arrived. The slew limiter is what makes
## that impossible, and this is the assertion that the limiter is actually in
## the path rather than merely declared.
func test_the_rate_itself_cannot_step_across_a_weather_cut() -> void:
	_sky.snowfall = 0.12
	_snow.settle()
	_run(3.0)
	_sky.snowfall = 1.0
	var trace := _run(20.0)
	var ceiling := _snow.rate_slew * FRAME * 1.0001
	assert_true(
		_largest_jump(trace["rate"]) <= ceiling,
		"the rate moved %.6f in one frame against a slew ceiling of %.6f, so a weather cut "
			% [_largest_jump(trace["rate"]), ceiling]
			+ "puts a corner in the curve"
	)
	assert_true(
		_snow.rate() > 0.0, "twenty seconds into a blizzard the snow is not accumulating at all"
	)


## The same, across the day boundary, and across a wind that arrives instantly.
## Three different inputs, one guarantee, and it holds for all of them because
## none of them can reach anything but the target rate.
func test_no_input_at_all_can_step_the_rate() -> void:
	_sky.snowfall = 0.35
	_snow.settle()
	var worst := 0.0
	for episode in range(4):
		match episode:
			0:
				_sky.snowfall = 1.0
			1:
				_snow._on_night_started(3)
			2:
				_sky.wind = 1.0
			3:
				_snow._on_day_started(4)
				_sky.snowfall = 0.0
				_sky.wind = 0.0
		var trace := _run(6.0)
		worst = maxf(worst, _largest_jump(trace["rate"]))
	var ceiling := _snow.rate_slew * FRAME * 1.0001
	assert_true(
		worst <= ceiling,
		"some input stepped the rate by %.6f against a ceiling of %.6f" % [worst, ceiling]
	)


# ---------------------------------------------------------------------------
# The model itself
# ---------------------------------------------------------------------------


## The clamp in advance() must be unreachable, and this is why the gain carries
## a (1 - cover) rather than being a flat rate. A model that saturates parks the
## value on the clamp, and the moment it comes off the clamp is a corner -- so
## "unreachable" is a continuity claim, not a tidiness one.
func test_the_equilibrium_is_always_strictly_inside_the_range() -> void:
	var offenders := PackedStringArray()
	for snowfall in [0.0, 0.1, 0.12, 0.28, 0.35, 0.5, 1.0]:
		for wind in [0.0, 0.5, 1.0]:
			for night in [false, true]:
				_sky.snowfall = snowfall
				_sky.wind = wind
				if night:
					_snow._on_night_started(1)
				else:
					_snow._on_day_started(1)
				_snow.settle()
				var equilibrium := _snow.equilibrium()
				if equilibrium < 0.0 or equilibrium >= 1.0:
					offenders.append(
						"snow %.2f wind %.2f night %s -> %.4f" % [snowfall, wind, night, equilibrium]
					)
	assert_eq(
		offenders.size(), 0,
		"the cover can reach its clamp at: %s" % ", ".join(offenders)
	)


## What "缓慢" has to mean in a game whose daylight phase is ten minutes long:
## the cover crosses most of its range in minutes, not in seconds and not in
## hours. Measured rather than asserted from the constants, so a change to the
## model that happens to leave the constants alone still trips it.
func test_the_cover_takes_minutes_to_cross_its_range() -> void:
	_sky.snowfall = 0.0
	_snow.settle()
	var from := _snow.cover()
	_sky.snowfall = 1.0
	# One step first, so the sky has actually been read before the destination
	# is asked for -- equilibrium() reports where the weather it currently knows
	# about is taking the cover, and it does not know yet.
	_snow.advance(0.1)
	var target := _snow.equilibrium()
	var elapsed := 0.1
	# Stepped at a tenth of a second rather than a frame: this runs for minutes
	# of simulated time and the integrator does not care, but the test's own cost
	# does. The continuity claims above are the ones that need a frame.
	while elapsed < 1200.0 and _snow.cover() < from + (target - from) * 0.9:
		_snow.advance(0.1)
		elapsed += 0.1
	assert_true(
		elapsed > 120.0,
		"the heaviest snowfall there is laid nine tenths of its cover in %.0f s, which is not "
			% elapsed
			+ "an accumulation, it is an event"
	)
	assert_true(
		elapsed < 600.0,
		"the heaviest snowfall there is took %.0f s to lay nine tenths of its cover, which is "
			% elapsed
			+ "longer than the whole of day 1's daylight -- nobody would see it happen"
	)


## 世界时间, as the brief asks for it: the night is what changes overnight.
## Colder, no sun on the pitch, no thaw-freeze -- more of what fell stays.
func test_a_night_holds_more_snow_than_the_day_it_follows() -> void:
	_sky.snowfall = 0.28
	_snow._on_day_started(4)
	_snow.settle()
	var by_day := _snow.equilibrium()
	_snow._on_night_started(4)
	var by_night := _snow.equilibrium()
	assert_true(
		by_night > by_day,
		"the night holds %.3f against the day's %.3f, so the clock reaches the snow the "
			% [by_night, by_day]
			+ "wrong way round or not at all"
	)


## The wind hook, in the same vocabulary TrackMask decays footprints with:
## 风大 strips an exposed surface as surely as it fills a hollow.
func test_wind_takes_settled_snow_off_again() -> void:
	_sky.snowfall = 0.35
	_snow.settle()
	var still := _snow.equilibrium()
	_sky.wind = 1.0
	_snow.advance(FRAME)
	assert_true(
		_snow.equilibrium() < still,
		"a full gale left the equilibrium at %.3f against dead air's %.3f" % [
			_snow.equilibrium(), still
		]
	)


## The run opens on the weather day 1 actually has. A world that whitened over
## the first three minutes of play would be the feature working perfectly and
## reading as the world assembling itself.
func test_the_first_frame_opens_on_the_weather_the_day_has() -> void:
	_sky.snowfall = 0.12
	_snow.settle()
	assert_almost_eq(
		_snow.cover(), _snow.equilibrium(), 0.0001,
		"the world does not start at the cover its weather asks for"
	)
	assert_almost_eq(_snow.rate(), 0.0, 0.0001, "it starts already moving")


## A weather system taking the wheel must take it completely -- two things
## easing the same number in opposite directions is worse than either.
func test_a_weather_system_taking_over_stops_the_sky_being_read() -> void:
	_sky.snowfall = 0.12
	_snow.settle()
	_snow.set_snowfall_rate(0.9)
	_sky.snowfall = 0.0
	_snow.advance(FRAME)
	assert_almost_eq(
		_snow.snowfall_rate(), 0.9, 0.0001,
		"Snowfall took the weather back off the system that had claimed it"
	)


# ---------------------------------------------------------------------------
# Where a pop would actually appear: the shader
# ---------------------------------------------------------------------------
# assets/shaders/cel_flat.gdshader, mirrored. The scalar being smooth is worth
# nothing if the surface reading it flips, and a roof plane is exactly the shape
# that would: one world normal across the whole of it.


## How much snow lies on a surface, given its world normal's Y, the value the
## noise happens to take there (-1..1), and the world cover.
func _lying(normal_y: float, noise: float, cover: float) -> float:
	var topness := normal_y + noise * CelPainterScript.SNOW_NOISE_STRENGTH
	var line: float = lerpf(
		CelPainterScript.SNOW_BARE_THRESHOLD, CelPainterScript.SNOW_FULL_THRESHOLD, cover
	)
	return smoothstep(
		line - CelPainterScript.SNOW_EDGE_SOFTNESS,
		line + CelPainterScript.SNOW_EDGE_SOFTNESS,
		topness
	)


## The cover a plane of this pitch first takes a fleck of snow at, and the cover
## at which the last of it goes white. -1 for either if it never happens inside
## the range -- which is a real answer and not a failure; see the steep-pitch
## test below.
func _whitening_range(normal_y: float) -> Vector2:
	var first := -1.0
	var full := -1.0
	var cover := 0.0
	while cover <= 1.0:
		# The most and the least snowy point on a plane of this pitch, which
		# between them is the whole plane once the noise has been over it.
		if first < 0.0 and _lying(normal_y, 1.0, cover) > 0.001:
			first = cover
		if full < 0.0 and _lying(normal_y, -1.0, cover) > 0.999:
			full = cover
		cover += 0.002
	return Vector2(first, full)


## THE POP THAT WOULD SURVIVE EVERY TEST ABOVE. A roof plane has one normal, so
## a bare normal.y threshold covers the whole of it on the frame the line
## crosses that one value -- a perfectly smooth scalar producing a perfectly
## discontinuous picture. The noise is what stops it: every point on the plane
## gets its own line, so the boundary creeps across the roof instead of arriving.
##
## The span is in units of COVER, and it is a property of the mapping rather than
## of the pitch: 2 * (noise + softness) / (bare - full), which is 0.67 here. At
## the fastest weather in the game the cover crosses that in about two minutes,
## and at days 1-2's in the better part of ten.
func test_a_flat_plane_whitens_across_minutes_rather_than_at_once() -> void:
	var span := 2.0 * (CelPainterScript.SNOW_NOISE_STRENGTH + CelPainterScript.SNOW_EDGE_SOFTNESS) \
		/ (CelPainterScript.SNOW_BARE_THRESHOLD - CelPainterScript.SNOW_FULL_THRESHOLD)
	assert_true(
		span >= 0.25,
		"a surface goes from its first fleck to fully white over %.3f of cover, which at the "
			% span
			+ "fastest weather in the game is seconds -- it will pop"
	)
	# A flat top -- a branch, a crossarm, a sill, the truck's bonnet -- and the
	# farmhouse's main roof, which is a 33.7 degree pitch, so cos(33.7) = 0.832.
	# Both must complete inside the range the weather can actually reach.
	for normal_y in [1.0, 0.832]:
		var range := _whitening_range(normal_y)
		assert_true(
			range.x >= 0.0 and range.y >= 0.0,
			"a plane at normal.y %.3f never finishes whitening at all" % normal_y
		)
		assert_almost_eq(
			range.y - range.x, span, 0.01,
			"a plane at normal.y %.3f whitens over a different span than the mapping says"
				% normal_y
		)


## ...and a STEEP pitch never finishes, which is the behaviour and not a gap.
## Snow slides off a steep roof, so a plane much past 45 degrees keeps a dark
## share of itself through the worst weather in the game -- and the frame keeps
## the ridge line that Art Bible rule 10 makes the subject. The threshold cannot
## reach far enough down to bury it, and the arithmetic that guarantees that is
## the same arithmetic that keeps snow off a vertical wall.
func test_a_steep_pitch_keeps_some_of_itself_dark_through_any_weather() -> void:
	var steep := _whitening_range(0.6)
	assert_true(steep.x >= 0.0, "a 53 degree pitch takes no snow at all, ever")
	assert_true(
		steep.y < 0.0,
		"a 53 degree pitch goes completely white at cover %.3f -- a roof that steep sheds, "
			% steep.y
			+ "and burying it takes the ridge line with it"
	)


## Invariant one, from the shader's own comment: at cover 0 nothing anywhere is
## covered, whatever its normal. A world that ships with a fleck of snow it can
## never take off has no bare state to accumulate from, and the whole feature is
## about the difference between bare and covered.
func test_nothing_at_all_is_covered_before_any_snow_has_settled() -> void:
	assert_true(
		CelPainterScript.SNOW_BARE_THRESHOLD - CelPainterScript.SNOW_EDGE_SOFTNESS
			> 1.0 + CelPainterScript.SNOW_NOISE_STRENGTH,
		"the bare threshold is inside the reach of a perfectly flat surface plus the noise, "
		+ "so the world is never actually bare"
	)
	var offenders := PackedStringArray()
	for normal_y in [-1.0, -0.5, 0.0, 0.5, 0.832, 1.0]:
		for noise in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			if _lying(normal_y, noise, 0.0) > 0.0:
				offenders.append("normal.y %.2f noise %.2f" % [normal_y, noise])
	assert_eq(offenders.size(), 0, "snow lies on a bare world at: %s" % ", ".join(offenders))


## Invariant two: a vertical wall is never covered, at any cover at all. Style
## document section 18 is explicit -- 房屋墙体 不要用 -- and snow crawling down
## a wall in a storm is the single most obviously wrong thing this shader could
## produce.
func test_a_vertical_wall_is_never_covered_however_hard_it_snows() -> void:
	assert_true(
		CelPainterScript.SNOW_FULL_THRESHOLD - CelPainterScript.SNOW_EDGE_SOFTNESS
			> CelPainterScript.SNOW_NOISE_STRENGTH,
		"the full threshold is inside the noise's own reach, so a vertical wall takes snow"
	)
	var offenders := PackedStringArray()
	var cover := 0.0
	while cover <= 1.0:
		for noise in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			if _lying(0.0, noise, cover) > 0.0:
				offenders.append("cover %.2f noise %.2f" % [cover, noise])
		cover += 0.05
	assert_eq(offenders.size(), 0, "snow lies on a vertical wall at: %s" % ", ".join(offenders))


## ...and the underside of everything, for the same reason and for free.
func test_snow_does_not_lie_on_a_downward_face() -> void:
	var offenders := PackedStringArray()
	var cover := 0.0
	while cover <= 1.0:
		if _lying(-1.0, 1.0, cover) > 0.0:
			offenders.append("cover %.2f" % cover)
		cover += 0.05
	assert_eq(offenders.size(), 0, "snow lies under a soffit at: %s" % ", ".join(offenders))


# ---------------------------------------------------------------------------
# The broadcast
# ---------------------------------------------------------------------------


## Rule 12's warm accents are the lit windows, the fire and the beacons, and a
## light with snow drawn over it is a light that has gone out. Exactly one of the
## twelve refuses snow, and it is not the whole warm family: the truck's red and
## the scarf's rust are paint, and snow on the truck's bonnet with its doors
## still red is what the reference shows.
func test_the_one_colour_that_is_a_light_takes_no_snow() -> void:
	var bible: ColorBible = load(PALETTE_PATH)
	var painter: CelPainter = CelPainterScript.new()
	var light: Color = bible.warm_tones[CelPainterScript.WARM_LIGHT_INDEX]
	assert_almost_eq(
		painter.receptivity_for(light), 0.0, 0.0001,
		"snow lies on #%s, which is the lit window" % light.to_html(false)
	)
	for index in range(bible.warm_tones.size()):
		if index == CelPainterScript.WARM_LIGHT_INDEX:
			continue
		var paint: float = painter.receptivity_for(bible.warm_tones[index])
		assert_true(
			paint > 0.0,
			"#%s is paint, not a light, and snow must lie on it at all"
				% bible.warm_tones[index].to_html(false)
		)
		assert_true(
			paint < 1.0,
			"#%s takes snow as readily as a roof does, so a full winter buries the truck and "
				% bible.warm_tones[index].to_html(false)
				+ "the frame loses its second visual centre -- Art Bible rule 12"
		)
		assert_almost_eq(paint, CelPainterScript.WARM_PAINT_RECEPTIVITY, 0.0001)
	for tone in bible.snow_tones + bible.structure_tones:
		assert_almost_eq(
			painter.receptivity_for(tone), 1.0, 0.0001,
			"#%s refuses snow" % tone.to_html(false)
		)


## Snow lying on a shed roof has to take the same two colours as the snow lying
## beside it, or the roof line announces itself as a different material. The
## ground lights snow_tones[0] and shades snow_tones[3]; so does this.
func test_settled_snow_takes_the_same_pair_the_ground_uses() -> void:
	var bible: ColorBible = load(PALETTE_PATH)
	var painter: CelPainter = CelPainterScript.new()
	var material := painter.material_for(bible.structure_tones[0])
	assert_eq(material.get_shader_parameter("snow_lit"), bible.snow_tones[0])
	assert_eq(material.get_shader_parameter("snow_shade"), bible.snow_tones[3])


## The two directions the broadcast has to work in, which are the same two
## set_world_shading() already has to: a surface standing in the world when the
## weather changes, and a surface built into a world the weather has already
## changed.
func test_the_cover_reaches_a_standing_surface_and_a_new_one() -> void:
	var bible: ColorBible = load(PALETTE_PATH)
	var painter: CelPainter = CelPainterScript.new()
	CelPainterScript.set_snow_cover(0.0)
	var standing := painter.material_for(bible.structure_tones[2])
	CelPainterScript.set_snow_cover(0.63)
	assert_almost_eq(
		float(standing.get_shader_parameter("snow_cover")), 0.63, 0.0001,
		"a surface already in the world never heard about the snow"
	)
	var arriving := painter.material_for(bible.snow_tones[4])
	assert_almost_eq(
		float(arriving.get_shader_parameter("snow_cover")), 0.63, 0.0001,
		"a surface built into a snowed-on world arrived bare"
	)
	CelPainterScript.set_snow_cover(0.0)
