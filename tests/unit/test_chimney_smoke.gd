extends TestCase

## 袅袅炊烟, and the four things that separate smoke from a particle emitter
## pointed upward.
##
## ---------------------------------------------------------------------------
## WHAT IS TESTED HERE AND WHAT IS TESTED BY LOOKING
## ---------------------------------------------------------------------------
## The claims this effect stands on are properties of a MODEL -- buoyancy falls
## off, turbulence grows with age, the alpha never reaches a cliff, and above all
## the gust travels UP the column. Every one of those is arithmetic, so every one
## of them is checked here, against the real wind profile, with no renderer in
## the way.
##
## What is NOT checked here is whether it looks like smoke. That is what the
## three capture sequences beside the task report are for. The split matters: a
## test that asserted the shape of the column off a PNG would be testing the
## renderer, the tuning and the model at once, and would tell you which had
## broken exactly never.
##
## The model functions live on `ChimneySmoke` as statics and are mirrored by
## assets/shaders/chimney_smoke.gdshader line for line. That mirroring is a real
## cost and it is stated in the source rather than hidden; the tests below are
## what make it worth paying.

const SmokeScript := preload("res://src/rendering/chimney_smoke.gd")
const WindScript := preload("res://src/systems/wind_system.gd")

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const VALLEY_PATH := "res://data/weather/wind_valley.tres"
const FARMHOUSE_PATH := "res://assets/models/buildings/farmhouse/farmhouse.glb"

## LightingDirector's own figure, copied rather than read, for the reason
## test_wind.gd and test_snowfall.gd both give: standing a LightingDirector up to
## ask it costs an engine error that has nothing to do with the smoke.
const GLOW_HDR_THRESHOLD := 0.95

## The three stops CameraRig offers. Copied for the same reason -- and the widest
## is the one that decides whether this effect exists, because a wisp too thin to
## survive 17.0 has failed however good it looks at 10.5.
const FRAMING_STOPS := [10.5, 13.5, 17.0]

## The pixels that actually get saved to a PNG at this project's capture
## resolution. Briefing trap 10: `Window.size` is the one of the three "screen
## size" APIs that describes the picture; the canvas rect is 10% smaller and the
## render target 11% larger, and reasoning about legibility in either of those is
## how a floor engages at the wrong moment.
const CAPTURE_HEIGHT_PX := 800.0

var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _keep(node: Node) -> Node:
	_nodes.append(node)
	return node


func _smoke() -> ChimneySmoke:
	return _keep(SmokeScript.new()) as ChimneySmoke


# ---------------------------------------------------------------------------
# 1. THE GUST TRAVELS UP THE COLUMN
# ---------------------------------------------------------------------------
# The claim that separates smoke which RESPONDS to wind from smoke that is MADE
# OF wind history, and the reason the wind is applied as a per-particle drag
# rather than as a displacement of the emitter.


## The wind at the flue over `seconds`, sampled at `step`, as the metres a second
## `ChimneySmoke.set_wind()` would hand the shader.
func _weather(profile, from: float, seconds: float, step: float, gain: float) -> PackedVector2Array:
	var samples := PackedVector2Array()
	var t := from
	while t < from + seconds:
		var strength: float = WindScript.strength_at(profile, t)
		var heading: float = WindScript.heading_at(profile, t)
		var direction: Vector3 = WindScript.heading_vector(heading)
		var speed: float = profile.gale_metres * strength * gain
		samples.append(Vector2(direction.x, direction.z) * speed)
		t += step
	return samples


## Where the column bends hardest, as an AGE in seconds. The difference between
## adjacent offsets is the wind at the moment between their births, so the
## steepest stretch is the gust -- see `ChimneySmoke.column_offsets`.
func _kink_age(offsets: PackedVector2Array, step: float) -> float:
	var steepest := -1.0
	var at := 0
	# The two ends are skipped: the newest puffs have barely integrated anything
	# and the oldest have run past the top of the column.
	for i in range(1, offsets.size() - 1):
		var slope := (offsets[i - 1] - offsets[i]).length()
		if slope > steepest:
			steepest = slope
			at = i
	# Element i was born at i*step and the run ends at (n-1)*step.
	return float(offsets.size() - 1 - at) * step


func test_a_gust_travels_up_the_column() -> void:
	var profile = load(VALLEY_PATH)
	assert_not_null(profile, "the valley wind profile is what this is measured against")
	var smoke := _smoke()
	var step := 0.10

	# A stretch of the real valley weather containing the hardest gust in the
	# first minute. The model is a pure function of t, so this is found by
	# arithmetic rather than waited for -- the same trick capture_gust.gd uses.
	var peak := _hardest_gust(profile)
	assert_true(peak > 0.0, "no gust was found in the first minute of valley weather")

	# The column as it stands 1.5 s after that gust peaked, and again two seconds
	# later. Both windows END after the peak, so in both of them the gust is
	# already history -- which is the only way the question "where in the column
	# is it now" has an answer.
	var life: float = smoke.puff_life_seconds
	var early := _weather(profile, peak + 1.5 - life, life, step, smoke.wind_gain)
	var later := _weather(profile, peak + 3.5 - life, life, step, smoke.wind_gain)

	var kink_early := _kink_age(
		SmokeScript.column_offsets(early, step, smoke.coupling_seconds), step)
	var kink_later := _kink_age(
		SmokeScript.column_offsets(later, step, smoke.coupling_seconds), step)

	# THE CLAIM. The bend belongs to older smoke than it did, and older smoke is
	# higher smoke -- which the rise test below establishes separately.
	assert_true(
		kink_later > kink_early + 1.0,
		"the bend has to move to OLDER smoke as time passes, or the column merely "
			+ "swings as one; it sat at age %.2f s and then at %.2f s" % [kink_early, kink_later]
	)

	# ...and in metres, which is what a viewer actually sees. Reported whatever
	# happens, because "it climbed" is worth nothing without "by how much".
	var high_early := _height_at_age(smoke, kink_early)
	var high_later := _height_at_age(smoke, kink_later)
	assert_true(
		high_later > high_early + 0.4,
		"the bend climbed only from %.2f m to %.2f m in 2 s, which is not a "
			% [high_early, high_later] + "travelling kink, it is a wobble"
	)


func _height_at_age(smoke: ChimneySmoke, age_seconds: float) -> float:
	return SmokeScript.rise_after(
		age_seconds, 0.02, smoke.buoyancy, smoke.buoyancy_decay,
		smoke.rise_damping_seconds, smoke.exit_speed, smoke.puff_life_seconds)


## When the wind is hardest in the first minute of valley weather. The PEAK
## rather than the threshold crossing, because a gust that is still building when
## the window closes has no "where in the column is it" to measure.
func _hardest_gust(profile) -> float:
	var strongest := -1.0
	var at := -1.0
	var t := 0.0
	while t < 60.0:
		var now: float = WindScript.strength_at(profile, t)
		if now > strongest:
			strongest = now
			at = t
		t += 0.05
	return at if strongest >= profile.gust_threshold else -1.0


## The other half of the claim, and it has to hold on its own: a bend that moved
## to older smoke only climbs if older smoke is higher. It is not obvious --
## the buoyancy decays, so the rise could in principle stall or reverse.
func test_older_smoke_is_always_higher_smoke() -> void:
	var smoke := _smoke()
	var previous := -1.0
	var age := 0.0
	while age <= smoke.puff_life_seconds:
		var height := _height_at_age(smoke, age)
		assert_true(
			height > previous,
			"the column stopped climbing at age %.1f s (%.3f m, was %.3f m) -- "
				% [age, height, previous]
				+ "a puff that stalls or falls back turns the kink into a knot"
		)
		previous = height
		age += 0.25


# ---------------------------------------------------------------------------
# 2. BUOYANCY FALLS OFF
# ---------------------------------------------------------------------------


func test_the_lift_dies_away_rather_than_holding() -> void:
	var smoke := _smoke()
	var young := SmokeScript.buoyancy_at(0.10, smoke.buoyancy, smoke.buoyancy_decay)
	var old := SmokeScript.buoyancy_at(0.85, smoke.buoyancy, smoke.buoyancy_decay)
	assert_true(
		old < young * 0.25,
		"smoke leaves the flue hot and cools; a lift of %.3f at the end against "
			% old + "%.3f at the start is a jet, not a hearth" % young
	)


## And the consequence, which is what is actually seen: the climb SLOWS. A
## column that rises at a constant rate reads as a machine however the lift is
## described.
func test_the_climb_slows_as_the_smoke_cools() -> void:
	var smoke := _smoke()
	var life: float = smoke.puff_life_seconds
	var first := _height_at_age(smoke, life * 0.25)
	var mid := _height_at_age(smoke, life * 0.50) - first
	var last := _height_at_age(smoke, life) - _height_at_age(smoke, life * 0.75)
	assert_true(
		last < first * 0.85,
		"the last quarter of the climb covered %.2f m against the first quarter's "
			% last + "%.2f m -- that is a constant rise and it reads as a jet" % first
	)
	assert_true(mid > 0.0, "the middle of the climb went nowhere")


# ---------------------------------------------------------------------------
# 3. TURBULENCE GROWS WITH AGE, AND WITH THE WIND IT WAS BORN INTO
# ---------------------------------------------------------------------------


func test_the_break_up_arrives_with_age_rather_than_at_the_lip() -> void:
	var smoke := _smoke()
	var lip := SmokeScript.curl_gain_at(
		0.15, 0.0, smoke.curl_strength, smoke.curl_growth, smoke.curl_wind_gain)
	var old := SmokeScript.curl_gain_at(
		0.90, 0.0, smoke.curl_strength, smoke.curl_growth, smoke.curl_wind_gain)
	assert_true(
		lip < old * 0.15,
		"a puff at the lip is pushed %.3f against an old one's %.3f; if the young "
			% [lip, old] + "smoke is already broken up there is no ribbon to curl"
	)
	# Above 1 is what puts the knee up the column rather than at the flue.
	assert_true(
		smoke.curl_growth > 1.0,
		"curl_growth %.2f is linear or worse, so break-up starts at the mouth"
			% smoke.curl_growth
	)


func test_a_puff_born_in_a_gale_is_torn_harder_than_one_born_in_a_lull() -> void:
	var smoke := _smoke()
	var calm := SmokeScript.curl_gain_at(
		0.7, 0.0, smoke.curl_strength, smoke.curl_growth, smoke.curl_wind_gain)
	var gale := SmokeScript.curl_gain_at(
		0.7, 1.0, smoke.curl_strength, smoke.curl_growth, smoke.curl_wind_gain)
	assert_true(
		gale > calm * 2.5,
		"a puff born into a gale is pushed %.3f against a calm one's %.3f -- the "
			% [gale, calm] + "tearing is what makes a gust visible as a SEGMENT of "
			+ "the column rather than as the whole of it moving"
	)


# ---------------------------------------------------------------------------
# 4. IT DISSIPATES, IT DOES NOT END
# ---------------------------------------------------------------------------


func test_the_column_thins_away_instead_of_reaching_a_ceiling() -> void:
	var smoke := _smoke()
	var last := SmokeScript.alpha_at(
		1.0, 0.0, smoke.peak_alpha, smoke.alpha_in, smoke.alpha_hold, smoke.wind_thinning)
	assert_almost_eq(last, 0.0, 0.0001)

	# The tail has to meet zero with no slope. A linear fall still has an edge
	# where it lands, and at this camera the eye finds that edge and reads it as
	# the top of the column -- which is the ceiling this whole shape exists to
	# avoid. Sampled over the last twentieth of the life.
	var near_end := SmokeScript.alpha_at(
		0.95, 0.0, smoke.peak_alpha, smoke.alpha_in, smoke.alpha_hold, smoke.wind_thinning)
	assert_true(
		near_end < smoke.peak_alpha * 0.02,
		"alpha is still %.4f at 95%% of life against a peak of %.3f; the last "
			% [near_end, smoke.peak_alpha] + "puffs will pop out of existence in a row"
	)

	# ...and it emerges rather than appearing.
	var born := SmokeScript.alpha_at(
		0.0, 0.0, smoke.peak_alpha, smoke.alpha_in, smoke.alpha_hold, smoke.wind_thinning)
	assert_almost_eq(born, 0.0, 0.0001)


func test_a_puff_only_ever_grows() -> void:
	var smoke := _smoke()
	var previous := -1.0
	var age := 0.0
	while age <= 1.0:
		var size := SmokeScript.size_at(age, smoke.size_birth, smoke.size_death, smoke.size_bias)
		assert_true(
			size > previous,
			"the puff shrank at age %.2f (%.3f m against %.3f m) -- vapour "
				% [age, size, previous] + "disperses, and a shrinking puff reads as a "
				+ "spark going out"
		)
		previous = size
		age += 0.05


# ---------------------------------------------------------------------------
# 5. IT IS A RIBBON, NOT A CLOUD
# ---------------------------------------------------------------------------


func test_it_leaves_a_mouth_and_is_widened_by_age_rather_than_emitted_wide() -> void:
	var smoke := _smoke()
	assert_true(
		smoke.mouth_radius * 2.0 < smoke.size_birth,
		"the mouth is %.2f m across against a puff of %.2f m -- emitting wider "
			% [smoke.mouth_radius * 2.0, smoke.size_birth]
			+ "than the puff makes a cone at the lip, which is the plume this is not"
	)
	assert_true(
		smoke.size_death > smoke.size_birth * 4.0,
		"a puff only opens from %.2f m to %.2f m; the widening has to come from "
			% [smoke.size_birth, smoke.size_death] + "the life of the smoke, not from the flue"
	)


# ---------------------------------------------------------------------------
# 6. COLOUR -- COOL, PALE, AND UNDER THE BLOOM THRESHOLD
# ---------------------------------------------------------------------------


func test_the_smoke_is_cool_and_comes_out_of_the_palette() -> void:
	var bible := load(PALETTE_PATH) as ColorBible
	assert_not_null(bible, "the palette is where every colour in this project comes from")
	var smoke := _smoke()
	var colour := SmokeScript.smoke_colour(bible, smoke.smoke_tone_index, smoke.smoke_whiteness)
	# Art Bible rule 12 keeps warm pixels for windows, fire, beacon, truck and
	# the scarf. Smoke is on none of those lists, and at this framing a warm
	# column against a blue sky would be the brightest thing in the frame.
	assert_true(
		colour.b >= colour.g and colour.g >= colour.r,
		"the smoke is warm at (%.3f, %.3f, %.3f)" % [colour.r, colour.g, colour.b]
	)
	# ...and it is a shade DOWN from the breath fog, which takes the lightest
	# tone 42% to white because condensing breath really is nearly white. Wood
	# smoke sits off the sky it is seen against.
	assert_true(
		colour.r < 0.90 and colour.g < 0.95,
		"at (%.3f, %.3f, %.3f) this is a white card, not wood smoke"
			% [colour.r, colour.g, colour.b]
	)


func test_the_smoke_stays_under_the_bloom_threshold() -> void:
	var bible := load(PALETTE_PATH) as ColorBible
	var smoke := _smoke()
	var colour := SmokeScript.smoke_colour(bible, smoke.smoke_tone_index, smoke.smoke_whiteness)
	var linear := colour.srgb_to_linear()
	var peak: float = maxf(maxf(linear.r, linear.g), linear.b) * smoke.peak_alpha
	assert_true(
		peak < GLOW_HDR_THRESHOLD,
		"the smoke peaks at %f against a bloom threshold of %f -- bloom on smoke "
			% [peak, GLOW_HDR_THRESHOLD] + "reads cheap, which is why the snowfall was refused it"
	)


# ---------------------------------------------------------------------------
# 7. LEGIBILITY AT ALL THREE FRAMINGS
# ---------------------------------------------------------------------------


## A wisp too thin to survive the widest stop has failed, however good it looks
## at the tightest. The camera cycles 10.5 / 13.5 / 17.0 and the player chooses;
## this effect does not get to assume one of them.
func test_the_wisp_survives_the_widest_framing() -> void:
	var smoke := _smoke()
	for size in FRAMING_STOPS:
		var pixels_per_metre := CAPTURE_HEIGHT_PX / float(size)
		# At the lip: the ribbon is the puff plus the mouth it spread across.
		var base_px := (smoke.size_birth + smoke.mouth_radius * 2.0) * pixels_per_metre
		# Half way up, where the column is at its most readable.
		var mid_px := SmokeScript.size_at(
			0.5, smoke.size_birth, smoke.size_death, smoke.size_bias) * pixels_per_metre
		assert_true(
			base_px >= 10.0,
			"at orthographic_size %.1f the ribbon leaves the flue %.1f px across, "
				% [size, base_px] + "which is a hairline"
		)
		assert_true(
			mid_px >= 40.0,
			"at orthographic_size %.1f the column is only %.1f px across at half "
				% [size, mid_px] + "life -- nothing to read as a shape"
		)


# ---------------------------------------------------------------------------
# 8. IT ONLY SMOKES WHEN THE FIRE IS LIT
# ---------------------------------------------------------------------------


func test_the_flue_goes_on_drawing_after_the_fire_dies() -> void:
	var smoke := _smoke()
	assert_true(
		smoke.ember_seconds > smoke.kindle_seconds,
		"the fade (%.1f s) is quicker than the build (%.1f s); a flue that has "
			% [smoke.ember_seconds, smoke.kindle_seconds]
			+ "been drawing for hours is hot and goes on drawing after the fire in it dies"
	)
	# A second of fading must leave most of the column standing, or the fire
	# going out reads as a light being switched off.
	var after := SmokeScript.draught_step(
		1.0, false, 1.0, smoke.kindle_seconds, smoke.ember_seconds)
	assert_true(
		after > 0.85,
		"one second after the fire died the column is already down to %.2f" % after
	)


func test_the_column_builds_rather_than_switching() -> void:
	var smoke := _smoke()
	var draught := 0.0
	var frames := 0
	while draught < 0.5 and frames < 6000:
		draught = SmokeScript.draught_step(
			draught, true, 1.0 / 60.0, smoke.kindle_seconds, smoke.ember_seconds)
		frames += 1
	assert_true(
		frames > 60,
		"the column reached half strength in %d frames -- that is a switch" % frames
	)
	# ...and it does get there.
	assert_true(draught >= 0.5, "the column never built at all")


## A beacon lit out in the valley must not make the farmhouse smoke. This is the
## rule that stops "is there a fire?" being answered by the wrong fire once wave
## 4 lights the chain.
func test_only_a_fire_under_this_flue_counts() -> void:
	var smoke := _smoke()
	var flue := Vector3(13.0, 8.55, -17.25)
	var stove := flue + Vector3(0.0, -8.10, -0.10)
	assert_true(
		SmokeScript.is_this_chimneys_fire(
			flue, stove, smoke.hearth_radius_m, smoke.hearth_drop_m),
		"the stove directly below the flue is this chimney's fire"
	)
	var beacon_in_the_valley := flue + Vector3(24.0, -8.10, 6.0)
	assert_false(
		SmokeScript.is_this_chimneys_fire(
			flue, beacon_in_the_valley, smoke.hearth_radius_m, smoke.hearth_drop_m),
		"a fire 24 m away made the farmhouse chimney smoke"
	)
	var bonfire_on_the_roof := flue + Vector3(0.0, 2.0, 0.0)
	assert_false(
		SmokeScript.is_this_chimneys_fire(
			flue, bonfire_on_the_roof, smoke.hearth_radius_m, smoke.hearth_drop_m),
		"a fire ABOVE the flue is not what the flue is drawing"
	)


# ---------------------------------------------------------------------------
# 9. WIRING -- the wind finds it, and the flue resolves
# ---------------------------------------------------------------------------


## `WindSystem` sweeps the tree for the hooks rather than for types or paths, so
## publishing both is the whole of being driven. This is the test that fails if
## somebody renames one of them.
func test_the_wind_system_can_find_it_with_no_special_case() -> void:
	var smoke := _smoke()
	assert_true(smoke.has_method("set_wind"), "WindSystem.drive() looks for set_wind")
	assert_true(
		smoke.has_method("set_wind_strength"),
		"WindSystem.drive() looks for set_wind_strength"
	)
	# And it must NOT look like a consumer that is fed by the sky, or the wind
	# system's pass-through logic will decline to drive it. See
	# WindSystem._is_fed_by_the_sky.
	assert_false(
		smoke.has_method("set_snowfall_source"),
		"a node with set_snowfall_source is taken to have another driver"
	)


func test_the_vector_is_flattened_and_converted_to_a_speed() -> void:
	var smoke := _smoke()
	smoke.set_wind(Vector3(1.6, 9.9, 0.5))
	var air := smoke.wind_metres_per_second()
	# Vertical wind is not a thing smoke should be given: the rise is the
	# buoyancy's job, and adding a vertical term would let the weather decide how
	# tall the column is.
	assert_almost_eq(air.y, 0.0, 0.0001)
	assert_almost_eq(air.x, 1.6 * smoke.wind_gain, 0.0001)
	assert_almost_eq(air.z, 0.5 * smoke.wind_gain, 0.0001)
	# The reconciliation, pinned: 1.68 m/s at a full gale bends the column by
	# about 50 degrees and no further, which is not "nearly flat".
	assert_true(
		smoke.wind_gain > 1.0,
		"wind_gain %.2f leaves the smoke in the shared acceleration vocabulary, "
			% smoke.wind_gain + "where a full gale cannot lay it over"
	)


## Three steps, most explicit first, and this is the one that fails the day the
## Blender marker stops resolving -- a column that silently falls back to a
## hardcoded offset when the chimney moves is exactly the defect
## `flue_source()` exists to catch.
func test_the_flue_resolves_to_a_marker_when_there_is_one_and_says_when_there_is_not() -> void:
	var host := _keep(Node3D.new()) as Node3D
	var smoke := SmokeScript.new() as ChimneySmoke
	host.add_child(smoke)

	smoke._place()
	assert_eq(smoke.flue_source(), &"placeholder")
	assert_almost_eq(smoke.position.y, smoke.placeholder_offset.y, 0.0001)

	# Whatever the Blender pipeline calls it, a node with "flue" in its name
	# under the building is the rendezvous.
	var marker := Node3D.new()
	marker.name = "FH_Flue"
	marker.position = Vector3(0.0, 9.25, -5.25)
	host.add_child(marker)
	smoke._place()
	assert_eq(smoke.flue_source(), &"marker")
	assert_almost_eq(smoke.position.y, 9.25, 0.0001)


## The placeholder is a measurement off tools/blender/build_farmhouse.py, not a
## guess, and this is what catches it going stale: the flue mouth has to be
## inside the roof group the chimney is merged into, above the eaves, and within
## a chimney's width of the ridge line.
func test_the_placeholder_lands_on_the_chimney_that_is_actually_in_the_model() -> void:
	var packed := load(FARMHOUSE_PATH) as PackedScene
	assert_not_null(packed, "the farmhouse model is where the chimney is")
	var model := _keep(packed.instantiate())
	var roof := _find_mesh(model, "FH_Fade_Roof")
	assert_not_null(roof, "the chimney is merged into FH_Fade_Roof")
	var box: AABB = roof.mesh.get_aabb()
	var smoke := _smoke()
	var flue: Vector3 = smoke.placeholder_offset

	assert_true(
		box.has_point(Vector3(flue.x, box.position.y + box.size.y * 0.5, flue.z)),
		"the flue at (%.2f, %.2f) is not over the roof, which spans x %.2f..%.2f "
			% [flue.x, flue.z, box.position.x, box.end.x]
			+ "z %.2f..%.2f" % [box.position.z, box.end.z]
	)
	# At the top of the roof rather than part way up it: the cap is 8.55 and the
	# antenna, which is the only thing higher, reaches 8.85.
	assert_true(
		flue.y > box.end.y - 0.6 and flue.y < box.end.y,
		"the flue mouth at %.2f m is not at the top of a roof that ends at %.2f m"
			% [flue.y, box.end.y]
	)


func _find_mesh(root: Node, wanted: String) -> MeshInstance3D:
	if root.name == wanted and root is MeshInstance3D:
		return root
	for child in root.get_children():
		var found := _find_mesh(child, wanted)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# 10. WHAT WAVE 5 SUBSCRIBES TO
# ---------------------------------------------------------------------------


## Smoke reveals a position. GDD section 8's threats approach the farmstead and a
## column visible across the valley is exactly the kind of thing that should draw
## them -- so this is a subscription later rather than a rewrite.
func test_the_column_announces_itself() -> void:
	var smoke := _smoke()
	assert_true(smoke.has_method("column_position"))
	assert_true(smoke.has_method("column_strength"))
	assert_true(smoke.has_method("column_visible"))
	assert_eq(SmokeScript.EVENT_COLUMN_RAISED, &"smoke.column_raised")
	assert_eq(SmokeScript.EVENT_COLUMN_FADED, &"smoke.column_faded")
	# Crossings with hysteresis, never levels -- the same discipline WindSystem
	# applies to its seven, and for the same reason: a chattering onset is worse
	# for a subscriber than no onset at all.
	assert_false(smoke.column_visible(), "an unlit chimney has no column")
