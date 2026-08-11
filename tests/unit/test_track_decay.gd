extends TestCase

## Footprints must fade, and the fading is a mechanic rather than a polish item.
##
## GDD section 8: the bear and the scavenger read the SAME track mask the terrain
## shader does, so what the snow remembers is what the threats can follow.
##
##   风大 -> 足迹速消 -> 你安全; 风停 -> 足迹留存 -> 你被跟上。
##
## The 寒流 event makes the air very still, and that stillness is what leaves a
## clear path in the snow behind you -- silence is both the omen of danger and
## its cause. None of that is true unless prints actually decay, and unless wind
## and snowfall are what set the pace. That is what this file pins.
##
## The decay belongs to the MASK, not to the player. Nothing here stamps through
## the player at all, and one test below stamps a print nowhere near him and
## requires it to fade identically -- so that when the bear starts walking in a
## later wave, its tracks fade with no change to this system.

const TrackMaskScript := preload("res://src/systems/track_mask.gd")

var _mask: TrackMask


func before_each() -> void:
	# build_at() rather than adding to the tree: _ready() would also register the
	# mask in ServiceRegistry and subscribe it to EventBus (briefing trap 1).
	_mask = TrackMaskScript.new()
	_mask.build_at(Vector3.ZERO)


func after_each() -> void:
	# Node is not reference counted (briefing section 2.2).
	_mask.free()
	_mask = null


## Runs `seconds` of weather over the mask in `step`-sized slices, the way the
## tree would. Small slices on purpose: decay() sweeps a bounded number of tiles
## per call, and a test that handed it one enormous delta would be testing a path
## the game never takes.
func _age(seconds: float, step := 0.5) -> void:
	var slices := int(ceilf(seconds / step))
	for _slice in range(slices):
		_mask.decay(step)


## The radius, in metres, of the furthest mark still left around `centre` --
## the print's actual footprint on the ground rather than its depth.
func _spread(centre: Vector3, limit := 1.2) -> float:
	var furthest := 0.0
	var reach := int(limit / TrackMaskScript.CELL_M)
	for step in range(reach):
		var distance := float(step) * TrackMaskScript.CELL_M
		if _mask.value_at(centre + Vector3(distance, 0.0, 0.0)) > 0.0:
			furthest = distance
	return furthest


## ---------------------------------------------------------------------------
## It fades at all
## ---------------------------------------------------------------------------


## The gap this file exists to close. The mask's own comment said "the wind will
## erase this one" and nothing ever did: a print made on day 1 was still there on
## day 7, at full depth.
func test_a_print_left_alone_is_filled_in_and_gone() -> void:
	_mask.stamp(Vector3(4.0, 0.0, 3.0), 0.28, 1.0)
	assert_almost_eq(_mask.value_at(Vector3(4.0, 0.0, 3.0)), 1.0, 0.02)
	_age(_mask.decay_still_seconds * 1.15)
	assert_almost_eq(
		_mask.value_at(Vector3(4.0, 0.0, 3.0)),
		0.0,
		0.001
	)


## ...but not so fast that a man cannot see his own last step. A trail that
## evaporates behind the walker reads as a rendering fault, not as weather.
func test_a_print_is_still_there_moments_later() -> void:
	_mask.stamp(Vector3.ZERO, 0.28, 1.0)
	_age(4.0)
	assert_true(
		_mask.value_at(Vector3.ZERO) > 0.85,
		"four seconds took the print from full depth to %f; it should barely have moved"
			% _mask.value_at(Vector3.ZERO)
	)


## A boot pocket in deep snow survives a breeze that erases a scuff on a scoured
## crest. The mask already carries depth, so the trail tells the truth about the
## terrain for nothing.
##
## Measured rather than predicted. An earlier version of this test asserted a
## depth at a fixed moment, computed as though the fill were the only thing
## happening -- and it was wrong, because slumping takes a deep print noticeably
## faster than subtraction alone (see decay_still_seconds). The claim being made
## is about which one outlives which, so that is what is measured.
func test_a_deeper_print_outlives_a_shallower_one() -> void:
	var deep := Vector3(-6.0, 0.0, 2.0)
	var scuff := Vector3(6.0, 0.0, 2.0)
	_mask.stamp(deep, 0.28, 0.95)
	_mask.stamp(scuff, 0.28, 0.30)

	var elapsed := 0.0
	var deep_life := 0.0
	var scuff_life := 0.0
	while elapsed < _mask.decay_still_seconds * 3.0:
		_mask.decay(0.5)
		elapsed += 0.5
		if deep_life <= 0.0 and _mask.value_at(deep) <= 0.0:
			deep_life = elapsed
		if scuff_life <= 0.0 and _mask.value_at(scuff) <= 0.0:
			scuff_life = elapsed
		if deep_life > 0.0 and scuff_life > 0.0:
			break

	assert_true(scuff_life > 0.0, "the scuff never went away at all")
	assert_true(
		deep_life > scuff_life * 1.8,
		"the deep print lasted %.1f s and the scuff %.1f: three times the depth "
			% [deep_life, scuff_life]
			+ "bought it almost nothing, and the trail no longer tells the truth "
			+ "about the snow it was made in"
	)


## ---------------------------------------------------------------------------
## The mechanic: wind, snowfall, and the stillness that gets you killed
## ---------------------------------------------------------------------------


## 风大 -> 足迹速消 -> 你安全; 风停 -> 足迹留存 -> 你被跟上。Both halves, in one
## test, because the mechanic is the CONTRAST and either half alone is just a
## number.
func test_wind_erases_the_trail_and_stillness_leaves_it_for_the_bear() -> void:
	var here := Vector3(2.0, 0.0, -2.0)
	var span: float = _mask.decay_gale_seconds * 1.2

	_mask.set_wind_strength(1.0)
	_mask.stamp(here, 0.28, 1.0)
	_age(span)
	assert_almost_eq(
		_mask.value_at(here),
		0.0,
		0.001
	)

	# The 寒流 event: the air goes still, and the path you leave stays.
	_mask.build_at(Vector3.ZERO)
	_mask.set_wind_strength(0.0)
	_mask.stamp(here, 0.28, 1.0)
	_age(span)
	assert_true(
		_mask.value_at(here) > 0.5,
		"in dead-still air the same print is down to %f after %.0f s: there is nothing "
			% [_mask.value_at(here), span]
			+ "left for the bear to follow and the 寒流 event has no teeth"
	)


## Snow falling fills a print in from above, the way wind fills it in from the
## side. A separate hook because they are separate weather.
func test_snowfall_fills_a_print_in_faster_than_clear_skies() -> void:
	var here := Vector3(-3.0, 0.0, 8.0)
	var span: float = _mask.decay_snowfall_seconds * 0.6

	_mask.set_snowfall_rate(1.0)
	_mask.stamp(here, 0.28, 1.0)
	_age(span)
	var snowed_on: float = _mask.value_at(here)

	_mask.build_at(Vector3.ZERO)
	_mask.set_snowfall_rate(0.0)
	_mask.stamp(here, 0.28, 1.0)
	_age(span)
	assert_true(
		_mask.value_at(here) > snowed_on + 0.2,
		"heavy snow left the print at %f and clear skies at %f: snowfall is doing "
			% [snowed_on, _mask.value_at(here)]
			+ "nothing"
	)


## The hooks are hooks: src/systems/wind_system.gd and weather_system.gd are Wave
## 3 and do not exist yet. What must NOT happen is decay sitting inert until they
## turn up -- a system that does nothing until a later wave is a system nobody
## can judge.
func test_the_weather_hooks_default_to_still_air_and_clear_skies() -> void:
	assert_almost_eq(_mask.wind_strength(), 0.0)
	assert_almost_eq(_mask.snowfall_rate(), 0.0)
	assert_true(
		_mask.fill_rate() > 0.0,
		"with no weather driving it the mask fills prints in at %f a second: the "
			% _mask.fill_rate()
			+ "decay is inert until Wave 3, which is exactly what was asked against"
	)
	# And they are clamped, so a bad number out of a system that does not exist
	# yet cannot make the snow behave impossibly.
	_mask.set_wind_strength(9.0)
	_mask.set_snowfall_rate(-4.0)
	assert_almost_eq(_mask.wind_strength(), 1.0)
	assert_almost_eq(_mask.snowfall_rate(), 0.0)


## Ploughed furrows and old tyre tracks are TERRAIN, not tracks. Art Bible
## section 3 puts them there as the only texture an otherwise empty white field
## has, and the first gust must not take them with the footprints.
func test_the_baked_layer_never_decays() -> void:
	_mask.bake_stroke(Vector3(-20.0, 0.0, 0.0), Vector3(20.0, 0.0, 0.0), 0.2, 0.9)
	var before: float = _mask.static_value_at(Vector3.ZERO)
	assert_true(before > 0.5, "the furrow was not baked at all, got %f" % before)
	_mask.set_wind_strength(1.0)
	_mask.set_snowfall_rate(1.0)
	_age(_mask.decay_still_seconds * 2.0)
	assert_almost_eq(_mask.static_value_at(Vector3.ZERO), before, 0.001)


## ---------------------------------------------------------------------------
## It fills in rather than merely fading
## ---------------------------------------------------------------------------


## Snow fills a print from the edges inward: it gets shallower AND less defined.
## A print that kept its exact shape while its depth scaled toward zero would be
## a fade, and a fade of a boot print looks like a boot print behind glass.
func test_a_print_loses_its_edge_before_its_core() -> void:
	var here := Vector3(1.0, 0.0, 1.0)
	_mask.stamp(here, 0.4, 1.0)
	var core_before: float = _mask.value_at(here)
	var edge_before: float = _mask.value_at(here + Vector3(0.32, 0.0, 0.0))
	assert_true(edge_before > 0.1, "the sample point missed the print's edge entirely")

	_age(_mask.decay_still_seconds * 0.4)
	var core_after: float = _mask.value_at(here)
	var edge_after: float = _mask.value_at(here + Vector3(0.32, 0.0, 0.0))
	assert_true(core_after > 0.2, "the core vanished as fast as the rim, got %f" % core_after)
	assert_true(
		edge_after / maxf(core_after, 0.0001) < edge_before / core_before - 0.05,
		"the rim held %f of the core's depth and now holds %f: the print is fading "
			% [edge_before / core_before, edge_after / maxf(core_after, 0.0001)]
			+ "uniformly, not filling in from its edges"
	)


## The other half of the same claim, measured as a shape rather than as a ratio:
## the mark the print leaves on the ground gets SMALLER.
func test_a_filling_print_pulls_its_outline_in() -> void:
	var here := Vector3(-8.0, 0.0, -8.0)
	_mask.stamp(here, 0.4, 1.0)
	var spread_before := _spread(here)
	_age(_mask.decay_still_seconds * 0.5)
	var spread_after := _spread(here)
	assert_true(
		spread_after < spread_before - 0.04,
		"the print covered %.3f m of ground and still covers %.3f: it is getting "
			% [spread_before, spread_after]
			+ "fainter without getting smaller"
	)
	assert_true(spread_after > 0.0, "the print disappeared outright rather than filling in")


## ---------------------------------------------------------------------------
## It belongs to the mask
## ---------------------------------------------------------------------------


## The threats do not walk yet, but the mask is shared and the decay is a
## property of the mask. A print stamped 40 m from the player -- where a bear
## would leave one -- must fade exactly like his own, with nothing wired up.
func test_a_creature_s_print_fades_exactly_like_the_player_s() -> void:
	var his := Vector3(1.0, 0.0, 1.0)
	var bear := Vector3(-32.0, 0.0, 28.0)
	_mask.stamp(his, 0.28, 0.8)
	_mask.stamp(bear, 0.28, 0.8)
	_age(_mask.decay_still_seconds * 0.5)
	assert_almost_eq(_mask.value_at(bear), _mask.value_at(his), 0.01)
	assert_true(_mask.value_at(bear) > 0.0, "both prints vanished; the test proves nothing")


## A whole trail, spread across the mask, not just whichever print was stamped
## last. The sweep visits tiles in turn, and a bug in that rotation would leave
## one end of a trail permanently frozen -- which reads as a bug in the terrain,
## not in this file.
func test_every_print_in_a_trail_fades_not_just_the_newest() -> void:
	var trail := [
		Vector3(0.0, 0.0, 0.0),
		Vector3(18.0, 0.0, 4.0),
		Vector3(-14.0, 0.0, -22.0),
		Vector3(30.0, 0.0, -31.0),
		Vector3(-38.0, 0.0, 36.0),
	]
	for spot in trail:
		_mask.stamp(spot, 0.28, 0.9)
	_age(_mask.decay_still_seconds * 1.2)
	for spot in trail:
		assert_almost_eq(_mask.value_at(spot), 0.0, 0.001)


## The window scrolls whenever the walker strays 3 m from its centre, which at a
## run is twice a second, and every mark in it moves. A print must go on ageing
## across that at the same pace -- neither frozen, because its tile stopped being
## flagged, nor restarted, because the flag was rebuilt from nothing.
func test_a_print_keeps_ageing_across_a_recentre() -> void:
	var here := Vector3(1.0, 0.0, 1.0)
	_mask.stamp(here, 0.28, 1.0)
	_age(20.0)
	var undisturbed: float = _mask.value_at(here)
	assert_true(undisturbed < 1.0, "the print did not age at all before the window moved")

	# Far enough to be a real scroll, near enough that the print stays in frame.
	assert_true(_mask.follow(Vector3(9.0, 0.0, 7.0)), "the window did not move")
	assert_almost_eq(_mask.value_at(here), undisturbed, 0.01)

	_age(20.0)
	var after: float = _mask.value_at(here)
	assert_true(
		after < undisturbed - 0.1,
		"twenty seconds after the recentre the print is still at %f against %f "
			% [after, undisturbed]
			+ "before it: the scroll froze its decay"
	)
	# ...and it did not race either, which is what losing the banked time would do.
	assert_true(
		after > undisturbed - (1.0 - undisturbed) * 2.0,
		"the print aged %f in the twenty seconds after the scroll against %f in "
			% [undisturbed - after, 1.0 - undisturbed]
			+ "the twenty before it"
	)


## decay() says whether it changed anything, which is what lets flush() upload
## once instead of every frame -- and what lets a clean mask cost nothing.
func test_decay_reports_whether_the_snow_actually_changed() -> void:
	assert_false(_mask.decay(1.0), "an empty mask reported that it changed something")
	_mask.stamp(Vector3.ZERO, 0.28, 1.0)
	var moved := false
	for _slice in range(8):
		moved = moved or _mask.decay(0.5)
	assert_true(moved, "a fresh print sat through four seconds of weather untouched")
	_age(_mask.decay_still_seconds * 1.3)
	assert_false(
		_mask.decay(1.0),
		"the mask is clean but decay() is still finding work to do every frame"
	)


## ---------------------------------------------------------------------------
## Remaining life
## ---------------------------------------------------------------------------


## The Wave 0 spec reserves a channel for "remaining life". The mask is a
## single-channel R8 image, so the life is not stored -- it is DERIVED from the
## depth that is stored and the weather that is blowing. Same fact, no format
## change. This is what a tracking bear would ask the mask.
func test_remaining_life_falls_as_the_print_fills_in() -> void:
	var here := Vector3(5.0, 0.0, -5.0)
	_mask.stamp(here, 0.28, 1.0)
	var fresh: float = _mask.remaining_life_at(here)
	assert_almost_eq(fresh, _mask.decay_still_seconds, 2.0)
	_age(_mask.decay_still_seconds * 0.5)
	var older: float = _mask.remaining_life_at(here)
	assert_true(
		older < fresh * 0.75,
		"half the print's life went by and it still reports %.1f s left against %.1f"
			% [older, fresh]
	)
	assert_almost_eq(_mask.remaining_life_at(Vector3(60.0, 0.0, 60.0)), 0.0)


## Wind shortens the life of a print that has already been made, not merely of
## the next one. The bear's read of the ground has to change when the weather
## does.
func test_wind_shortens_the_life_of_a_print_already_in_the_snow() -> void:
	var here := Vector3(0.0, 0.0, 9.0)
	_mask.stamp(here, 0.28, 1.0)
	var still: float = _mask.remaining_life_at(here)
	_mask.set_wind_strength(1.0)
	assert_true(
		_mask.remaining_life_at(here) < still * 0.5,
		"the wind got up and the print's %.1f s of life became %.1f"
			% [still, _mask.remaining_life_at(here)]
	)
