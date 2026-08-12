extends TestCase

## How fast a man crosses a snowfield, and why that number and not another.
##
## The owner's ruling is the whole specification: 整体的速度需要受到地形的坡度和
## 雪的厚度影响 ... 不管是行走还是奔跑只受到雪深度和地形坡度的影响，但是整体的
## 速度设计需要符合现实世界的理解和定义. Two terrain inputs, one for the walk and
## the run alike, and a scale that answers to the real world.
##
## ---------------------------------------------------------------------------
## THE REAL-WORLD ANCHOR, because "符合现实世界" has to be checkable
## ---------------------------------------------------------------------------
## Metres per second, so the table can be compared against without conversion:
##
##     stroll                1.1
##     ordinary walking      1.3 - 1.4
##     brisk walking         1.6
##     jogging               2.5 - 3.0
##     a fit person's run    3.5 - 4.5
##     a brief sprint        6   - 8
##
## The run shipped at 5.4 m/s. That is a 3:05/km pace -- inside elite marathon
## speed -- for a cold, burdened man in winter clothing crossing a snowfield, and
## it is the single reason clear ground felt wrong.
##
## ---------------------------------------------------------------------------
## TOBLER, AND WHY IT IS NOT AN INVENTED CURVE
## ---------------------------------------------------------------------------
## Tobler's hiking function is the accepted empirical model of walking speed
## against grade:
##
##     W = 6 exp(-3.5 |S + 0.05|)   km/h,   S = rise / run
##
## It is computed here from the paper's own constants rather than read off the
## implementation, so these tests can disagree with the code.
##
## The reason to reach for it rather than invent something is checkable and is
## checked below: at S = 0 it gives 5.04 km/h = 1.40 m/s, and this project had
## already chosen walk_speed = 1.35 for a completely unrelated reason -- it is the
## ground speed at which the walk cycle plays at rate 1, so the feet plant instead
## of skating. Two independent derivations landing within 4% of each other is the
## strongest evidence available that the scale is right.
##
## Its shape is correct gameplay for free: the peak is at a slight DOWNHILL
## (-5%), and it falls away in both directions, so a steep descent costs as much
## as a climb. A player reads that as careful footing and it needs no tutorial.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const SnowFieldScript := preload("res://src/systems/snow_field.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")

## Tobler's hiking function in km/h, from the paper. Not from the code under
## test -- a test that called slope_factor() to compute its own expectation would
## agree with any curve at all.
static func tobler_kmh(grade: float) -> float:
	return 6.0 * exp(-3.5 * absf(grade + 0.05))


## The same, normalised so level ground is exactly 1. This is what the speed
## model multiplies by.
static func tobler_factor(grade: float) -> float:
	return tobler_kmh(grade) / tobler_kmh(0.0)


var _player: PlayerController = null
var _field: SnowField = null
var _survival = null


func after_each() -> void:
	# Node is not reference counted (briefing constraint 2).
	if _player != null:
		_player.free()
		_player = null
	if _field != null:
		_field.free()
		_field = null
	if _survival != null:
		_survival.free()
		_survival = null


func _build() -> PlayerController:
	_player = PlayerControllerScript.new()
	return _player


# ---------------------------------------------------------------------------
# The scale
# ---------------------------------------------------------------------------

## The reported defect, as a test. Anything in the jogging band is a man; 5.4 is
## an athlete and 6+ is a sprinter.
func test_the_run_is_a_jog_and_not_a_sprint() -> void:
	var player := _build()
	assert_true(
		player.run_speed >= 3.0 and player.run_speed <= 3.5,
		"the run is %.2f m/s (%d:%02d /km); a cold burdened man in winter clothing "
			% [
				player.run_speed,
				int(1000.0 / player.run_speed) / 60,
				int(1000.0 / player.run_speed) % 60,
			]
			+ "crossing a snowfield belongs in the 3.0-3.5 jogging band"
	)


## The walk is animation-locked and must stay where it is: it is the ground speed
## at which the walk cycle covers ground at rate 1. That it also agrees with
## Tobler is the corroboration, not the cause.
func test_the_walk_is_toblers_level_ground_pace() -> void:
	var player := _build()
	var tobler := tobler_kmh(0.0) / 3.6
	assert_almost_eq(
		player.walk_speed,
		tobler,
		tobler * 0.05,
		"the walk is %.3f m/s against Tobler's %.3f on the level -- more than 5%% apart, "
			% [player.walk_speed, tobler]
			+ "so the two derivations no longer corroborate each other"
	)


## The animation defect hiding inside the old number. The run clip covers 4.6 m/s
## of ground at rate 1 (anim_run_speed, measured off the take), so a run faster
## than that plays the legs over rate 1 and the feet skate. At 5.4 the pace scale
## was 1.17.
func test_the_run_stays_inside_what_the_run_clip_covers() -> void:
	var player := _build()
	assert_true(
		player.run_speed <= player.anim_run_speed,
		"the run is %.2f m/s against a clip that covers %.2f, so the pace scale is %.2f "
			% [player.run_speed, player.anim_run_speed, player.run_speed / player.anim_run_speed]
			+ "and the legs spin faster than they carry him"
	)


# ---------------------------------------------------------------------------
# Slope -- Tobler's hiking function
# ---------------------------------------------------------------------------

func test_level_ground_is_exactly_one() -> void:
	assert_almost_eq(
		PlayerControllerScript.slope_factor(0.0),
		1.0,
		0.0001,
		"level ground does not leave the authored speed alone"
	)


## The claim "this is Tobler" made checkable. Every grade the shipped terrain can
## produce, against the paper's own curve.
func test_the_slope_term_is_toblers_hiking_function() -> void:
	for grade in [-0.35, -0.25, -0.15, -0.10, -0.05, 0.0, 0.05, 0.10, 0.15, 0.25, 0.35]:
		assert_almost_eq(
			PlayerControllerScript.slope_factor(grade),
			tobler_factor(grade),
			0.0005,
			"at grade %+.2f the model gives %.4f where Tobler gives %.4f"
				% [
					grade,
					PlayerControllerScript.slope_factor(grade),
					tobler_factor(grade),
				]
		)


## Tobler's peak is at a 5% DESCENT, not on the level. This is the part that is
## free gameplay: the fastest ground in the game is a gentle downhill.
func test_the_fastest_ground_is_a_gentle_descent() -> void:
	var peak: float = PlayerControllerScript.slope_factor(-0.05)
	assert_true(
		peak > PlayerControllerScript.slope_factor(0.0),
		"a gentle descent (%.4f) is no faster than the level (%.4f)"
			% [peak, PlayerControllerScript.slope_factor(0.0)]
	)
	assert_true(
		peak > PlayerControllerScript.slope_factor(-0.15),
		"a gentle descent is no faster than a steeper one, so there is no peak at all"
	)
	assert_true(
		peak < 1.25,
		"a gentle descent gives a %.0f%% boost, which is a speed pickup rather than a gradient"
			% ((peak - 1.0) * 100.0)
	)


## The half that is easy to leave out: a steep DESCENT is slow too. A model that
## only punished climbing would let a player fall down every bank at full speed.
func test_a_steep_descent_costs_as_much_as_the_matching_climb() -> void:
	for offset in [0.10, 0.20, 0.30]:
		assert_almost_eq(
			PlayerControllerScript.slope_factor(-0.05 + offset),
			PlayerControllerScript.slope_factor(-0.05 - offset),
			0.0005,
			"%+.2f either side of the -0.05 peak is not symmetric: %.4f against %.4f"
				% [
					offset,
					PlayerControllerScript.slope_factor(-0.05 + offset),
					PlayerControllerScript.slope_factor(-0.05 - offset),
				]
		)
	assert_true(
		PlayerControllerScript.slope_factor(-0.30) < 0.7,
		"a 30%% descent costs nothing worth feeling"
	)


## Tobler goes to zero and a player pinned at zero is a soft lock with no message
## -- the same failure the exhaustion gate exists to avoid.
func test_a_slope_never_stops_him_dead() -> void:
	var floor_factor: float = PlayerControllerScript.SLOPE_FLOOR
	for grade in [-2.0, -1.0, 1.0, 2.0]:
		var factor: float = PlayerControllerScript.slope_factor(grade)
		assert_true(
			factor >= floor_factor - 0.0001,
			"at grade %+.1f the slope factor is %.4f, under the floor %.2f"
				% [grade, factor, floor_factor]
		)
	assert_true(
		floor_factor > 0.0 and floor_factor < 0.5,
		"the floor is %.2f, which is either a soft lock or no slope model at all"
			% floor_factor
	)


## The owner's rule covers both gaits: 不管是行走还是奔跑. A slope model that only
## touched the walk would let a player outrun every hill.
##
## Stated as the two gaits losing the SAME FRACTION rather than as a specific
## number, so it keeps testing what it is for at any terrain_severity.
func test_slope_scales_the_run_as_well_as_the_walk() -> void:
	var player := _build()
	var grade := 0.25
	var walking: float = player.top_speed_at(0.0, grade, 0.0) / player.top_speed_at(0.0, 0.0, 0.0)
	var running: float = player.top_speed_at(0.0, grade, 1.0) / player.top_speed_at(0.0, 0.0, 1.0)
	assert_almost_eq(
		running,
		walking,
		0.0001,
		"a 0.25 climb costs the walk %.1f%% and the run %.1f%%"
			% [(1.0 - walking) * 100.0, (1.0 - running) * 100.0]
	)
	assert_true(
		walking < 0.99,
		"a 0.25 climb costs the walk nothing at all"
	)


# ---------------------------------------------------------------------------
# Which way the ground runs under HIM
# ---------------------------------------------------------------------------

## Traversing a bank sideways is level ground underfoot. Reading the terrain's
## raw steepest slope instead would slow a player who is not climbing anything.
func test_crossing_a_slope_sideways_is_level_ground() -> void:
	var uphill := Vector2(0.4, 0.0)
	assert_almost_eq(
		PlayerControllerScript.grade_along(uphill, Vector3(0.0, 0.0, 1.0)),
		0.0,
		0.0001,
		"walking along the contour reads as a grade"
	)


func test_climbing_is_positive_and_descending_is_negative() -> void:
	# surface_gradient_at points UPHILL and its length is tan(slope).
	var uphill := Vector2(0.4, 0.0)
	assert_almost_eq(
		PlayerControllerScript.grade_along(uphill, Vector3(1.0, 0.0, 0.0)),
		0.4,
		0.0001,
		"walking straight up a 0.4 grade does not read as +0.4"
	)
	assert_almost_eq(
		PlayerControllerScript.grade_along(uphill, Vector3(-1.0, 0.0, 0.0)),
		-0.4,
		0.0001,
		"walking straight down a 0.4 grade does not read as -0.4"
	)


func test_a_man_standing_still_is_on_no_grade_at_all() -> void:
	assert_almost_eq(
		PlayerControllerScript.grade_along(Vector2(0.6, -0.3), Vector3.ZERO),
		0.0,
		0.0001,
		"a heading of nothing produced a grade"
	)


# ---------------------------------------------------------------------------
# Snow, and how the two compose
# ---------------------------------------------------------------------------

func test_deeper_snow_is_always_slower() -> void:
	var player := _build()
	for gait in [0.0, 1.0]:
		var previous: float = player.top_speed_at(0.0, 0.0, gait)
		for step in range(1, 11):
			var here: float = player.top_speed_at(float(step) / 10.0, 0.0, gait)
			assert_true(
				here <= previous + 0.0001,
				"at gait %.0f, wade %.1f gives %.3f -- faster than the shallower %.3f"
					% [gait, float(step) / 10.0, here, previous]
			)
			previous = here


## The composition requirement, stated the way the owner stated it: deep snow on
## a climb has to be worse than either alone. Multiplication gives that; adding
## the two penalties, or taking the worse of the two, would not.
func test_deep_snow_on_a_climb_is_worse_than_either_alone() -> void:
	var player := _build()
	var flat_bare: float = player.top_speed_at(0.0, 0.0, 0.0)
	var flat_deep: float = player.top_speed_at(1.0, 0.0, 0.0)
	var bare_climb: float = player.top_speed_at(0.0, 0.25, 0.0)
	var deep_climb: float = player.top_speed_at(1.0, 0.25, 0.0)
	assert_true(
		deep_climb < flat_deep - 0.0001,
		"a climb through a drift (%.3f) costs nothing over the flat drift (%.3f)"
			% [deep_climb, flat_deep]
	)
	assert_true(
		deep_climb < bare_climb - 0.0001,
		"a climb through a drift (%.3f) costs nothing over the bare climb (%.3f)"
			% [deep_climb, bare_climb]
	)
	# The RAW model -- before terrain_severity compresses it -- composes as a
	# product, so the two penalties compound rather than one masking the other.
	# Asserted on the factors rather than on the shipped speed, because a lerp
	# toward 1 does not preserve a product; this is the claim the compression is
	# not allowed to destroy, and test_compression_keeps_every_relationship_it
	# _softens is the other half of it.
	var snow: float = player.snow_factor(1.0)
	var slope: float = PlayerControllerScript.slope_factor(0.25)
	assert_almost_eq(
		player.snow_factor(1.0) * slope,
		snow * slope,
		0.0001,
		"snow_factor() is not stable between calls"
	)
	assert_true(
		snow * slope < minf(snow, slope) - 0.0001,
		"the raw terrain terms do not compound: %.4f x %.4f is not below both"
			% [snow, slope]
	)


## 只受到雪深度和地形坡度的影响. With nothing else acting on the body, the whole
## model is the gait times the terrain, and this pins that exactly -- including
## that terrain_severity is applied ONCE to the product rather than to each term.
func test_snow_and_slope_are_the_whole_terrain_model() -> void:
	var player := _build()
	for wade in [0.0, 0.35, 1.0]:
		for grade in [-0.2, 0.0, 0.3]:
			var raw: float = player.snow_factor(wade) * PlayerControllerScript.slope_factor(grade)
			assert_almost_eq(
				player.terrain_factor(wade, grade),
				lerpf(1.0, raw, player.terrain_severity),
				0.0001,
				"the terrain factor at wade %.2f grade %+.2f is not the compressed product"
					% [wade, grade]
			)
			for gait in [0.0, 0.5, 1.0]:
				var expected: float = (
					lerpf(player.walk_speed, player.run_speed, gait)
					* player.terrain_factor(wade, grade)
				)
				assert_almost_eq(
					player.top_speed_at(wade, grade, gait),
					expected,
					0.0001,
					"wade %.2f grade %+.2f gait %.1f gives %.4f, not the product %.4f"
						% [wade, grade, gait, player.top_speed_at(wade, grade, gait), expected]
				)


## Compressing the amplitude must not turn the terrain off. Every relationship
## the model builds has to survive the lerp, or the compression has eaten the
## feature rather than softened it.
func test_compression_keeps_every_relationship_it_softens() -> void:
	var player := _build()
	assert_true(
		player.terrain_severity > 0.0 and player.terrain_severity < 1.0,
		"terrain_severity is %.2f, which is either raw Tobler or no terrain at all"
			% player.terrain_severity
	)
	assert_almost_eq(
		player.terrain_factor(0.0, 0.0), 1.0, 0.0001, "bare level ground is not left alone"
	)
	assert_true(
		player.terrain_factor(1.0, 0.0) < player.terrain_factor(0.5, 0.0),
		"deep snow is no longer slower than half a drift"
	)
	assert_true(
		player.terrain_factor(0.0, 0.25) < player.terrain_factor(0.0, 0.0),
		"a climb is no longer slower than the level"
	)
	assert_true(
		player.terrain_factor(0.0, -0.05) > player.terrain_factor(0.0, 0.0),
		"the gentle-descent peak did not survive the compression"
	)
	# ...and the worst the game can do to him is a slowing, not a wall.
	var worst: float = player.terrain_factor(1.0, 1.0)
	assert_true(
		worst > 0.4 and worst < 0.6,
		"the deepest snow on the steepest climb leaves %.0f%% of his pace; the owner asked "
			% (worst * 100.0)
			+ "to feel the trend, not to be stuck"
	)


## THE REALISM CLAIM, kept checkable after the compression.
##
## 0.42 m of unpacked snow is knee-deep postholing, which published figures put
## at 1-2 km/h. The RAW model says exactly that and is asserted here. What ships
## is faster on purpose -- see PlayerController.terrain_severity: Tobler describes
## hours of hiking and this player crosses the valley in a minute.
func test_the_raw_model_still_says_what_the_real_world_says() -> void:
	var player := _build()
	var raw: float = player.walk_speed * player.snow_factor(1.0)
	assert_true(
		raw * 3.6 > 1.0 and raw * 3.6 < 2.0,
		"the raw model wades 0.42 m of snow at %.2f km/h; knee-deep postholing is 1-2 km/h"
			% (raw * 3.6)
	)
	# ...and what ships is a clear trend rather than a struggle.
	var shipped: float = player.top_speed_at(1.0, 0.0, 0.0)
	assert_true(
		shipped < player.walk_speed * 0.75,
		"wading a full drift costs only %.0f%% of the clear-ground walk, which is not a "
			% ((1.0 - shipped / player.walk_speed) * 100.0)
			+ "trend a player would notice"
	)
	assert_true(
		shipped > player.walk_speed * 0.45,
		"wading a full drift leaves %.2f m/s, which is the struggle the owner asked to lose"
			% shipped
	)


# ---------------------------------------------------------------------------
# The run as a capability, not a number
# ---------------------------------------------------------------------------

## GDD section 5's control table: 奔跑（仅浅雪与道路上可用）. Past wading depth you
## cannot lift your feet clear of the snow -- the furrow exists because of that --
## so there is no run to be had.
func test_deep_snow_takes_the_run_away_rather_than_slowing_it() -> void:
	var player := _build()
	assert_true(player.can_run(0.0), "he cannot run on bare ground")
	assert_false(player.can_run(1.0), "he can run through a full drift")


## The load-bearing behaviour, and the whole reason SnowField carries a packed
## layer: a path you have beaten flat lets you run again.
func test_a_path_beaten_flat_gives_the_run_back() -> void:
	var player := _build()
	_field = SnowFieldScript.new()
	_field.build_at(Vector3.ZERO)

	var drift := Vector3.ZERO
	var found := false
	for iz in range(-60, 61):
		for ix in range(-60, 61):
			var here := Vector3(float(ix) * 0.5, 0.0, float(iz) * 0.5)
			if _field.wade_factor(here) >= 0.999:
				drift = here
				found = true
				break
		if found:
			break
	assert_true(found, "the shipped field has no snow deep enough to stop a run anywhere")
	if not found:
		return

	assert_false(player.can_run(_field.wade_factor(drift)), "fresh drift already allows a run")
	# A dozen passes, which is about what a path takes -- one boot is 0.09.
	for _pass in range(20):
		_field.pack_at(drift, 0.34, 0.09)
	assert_true(
		player.can_run(_field.wade_factor(drift)),
		"twenty passes over the same spot left a wade factor of %.3f, still too deep to run"
			% _field.wade_factor(drift)
	)


## 疲劳归零后果: 无法奔跑. A capability gate, not a speed scaler -- a body pinned at
## zero by an empty bar is a soft lock with no message.
func test_an_exhausted_man_cannot_be_promoted_to_a_run() -> void:
	var player := _build()
	_survival = SurvivalSystemScript.new()
	_survival.load_from_directory()
	_survival.start()
	player.set_survival_system(_survival)
	assert_true(player.can_run(0.0), "a fresh man cannot run")

	_survival.push_modifier(&"fatigue", &"test_drop", Modifier.Operation.ADD, 0.05)
	var guard := 0
	while _survival.value_of(&"fatigue") > 0.01 and not _survival.is_dead() and guard < 20000:
		_survival.advance(0.25)
		guard += 1
	_survival.remove_source(&"test_drop")

	assert_false(player.can_run(0.0), "an exhausted man can still be promoted to a run")
	assert_true(
		player.top_speed_at(0.0, 0.0, 0.0) > 0.0,
		"an exhausted man cannot move at all, which is a soft lock rather than a penalty"
	)


# ---------------------------------------------------------------------------
# Auto-run
# ---------------------------------------------------------------------------

## The default the owner asked to be picked. Stated as a range so tuning it in
## play does not fail the suite, but a default outside it is not an auto-run --
## under half a second it fires on every step and over two it never fires.
func test_the_auto_run_threshold_has_a_sensible_default() -> void:
	var player := _build()
	assert_true(
		player.auto_run_delay >= 0.6 and player.auto_run_delay <= 2.0,
		"the auto-run threshold defaults to %.2f s" % player.auto_run_delay
	)


## 自动奔跑可以开放阈值给用户设置. Registered under a documented name with a range,
## so the settings screen binds a slider to something that already exists.
func test_the_threshold_is_exposed_as_a_user_setting() -> void:
	var player := _build()
	var name: String = PlayerControllerScript.AUTO_RUN_SETTING
	var existed := ProjectSettings.has_setting(name)
	var before = ProjectSettings.get_setting(name) if existed else null

	player.register_settings()
	assert_true(ProjectSettings.has_setting(name), "%s is not registered" % name)
	assert_almost_eq(
		float(ProjectSettings.get_setting(name)),
		player.auto_run_delay,
		0.0001,
		"the registered setting does not carry the controller's own default"
	)

	# A user's value wins over the authored one.
	ProjectSettings.set_setting(name, 0.4)
	player.auto_run_delay = 99.0
	player.register_settings()
	assert_almost_eq(
		player.auto_run_delay,
		0.4,
		0.0001,
		"the controller ignored the setting and kept its own %.2f" % player.auto_run_delay
	)

	# Global state, shared with every later test: put it back exactly.
	if existed:
		ProjectSettings.set_setting(name, before)
	else:
		ProjectSettings.set_setting(name, null)


func test_walking_becomes_a_run_only_after_the_threshold() -> void:
	var player := _build()
	var north := Vector3(0.0, 0.0, -1.0)
	var elapsed := 0.0
	# Just short of the threshold: still walking, and not part-way there either.
	while elapsed < player.auto_run_delay - 0.05:
		player.advance_gait(1.0 / 60.0, north, 0.0)
		elapsed += 1.0 / 60.0
	assert_true(
		player.run_blend() < 0.02,
		"he was %.2f of the way into a run %.2f s before the %.2f s threshold"
			% [player.run_blend(), player.auto_run_delay - elapsed, player.auto_run_delay]
	)
	# ...and a second later he is running.
	for _tick in range(60):
		player.advance_gait(1.0 / 60.0, north, 0.0)
	assert_true(
		player.run_blend() > 0.9,
		"a second past the threshold he is only %.2f of the way into a run" % player.run_blend()
	)


## Eased, not stepped. The blend must spend real time in the middle -- a body
## that snaps from walk to run at a threshold is worse than no auto-run at all.
func test_the_promotion_is_eased_rather_than_a_step() -> void:
	var player := _build()
	var north := Vector3(0.0, 0.0, -1.0)
	var partway := 0
	for _tick in range(240):
		player.advance_gait(1.0 / 60.0, north, 0.0)
		if player.run_blend() > 0.05 and player.run_blend() < 0.95:
			partway += 1
	assert_true(
		partway >= 12,
		"the blend was between 0.05 and 0.95 for %d ticks (%.2f s); that is a step change"
			% [partway, float(partway) / 60.0]
	)
	assert_true(
		partway <= 120,
		"the blend took %.2f s to cross; a promotion that slow reads as drifting"
			% (float(partway) / 60.0)
	)


func test_stopping_drops_him_back_to_a_walk() -> void:
	var player := _build()
	var north := Vector3(0.0, 0.0, -1.0)
	for _tick in range(240):
		player.advance_gait(1.0 / 60.0, north, 0.0)
	assert_true(player.run_blend() > 0.9, "he never got into a run to drop out of")
	for _tick in range(60):
		player.advance_gait(1.0 / 60.0, Vector3.ZERO, 0.0)
	assert_true(
		player.run_blend() < 0.05,
		"a second after he stopped he is still %.2f in a run" % player.run_blend()
	)
	# ...and setting off again has to earn it back.
	player.advance_gait(1.0 / 60.0, north, 0.0)
	assert_true(
		player.run_blend() < 0.05,
		"the first step of a new walk went straight back into a run"
	)


func test_a_sharp_change_of_direction_drops_him_back_to_a_walk() -> void:
	var player := _build()
	var north := Vector3(0.0, 0.0, -1.0)
	for _tick in range(240):
		player.advance_gait(1.0 / 60.0, north, 0.0)
	assert_true(player.run_blend() > 0.9, "he never got into a run to drop out of")
	# About-face.
	for _tick in range(30):
		player.advance_gait(1.0 / 60.0, -north, 0.0)
	assert_true(
		player.run_blend() < 0.5,
		"half a second after reversing he is still %.2f in a run" % player.run_blend()
	)


## ...but a curve is not a turn. A player rounding a building keeps the run, or
## the feature is unusable anywhere but a straight line.
func test_a_gentle_curve_keeps_the_run() -> void:
	var player := _build()
	var heading := Vector3(0.0, 0.0, -1.0)
	for _tick in range(240):
		player.advance_gait(1.0 / 60.0, heading, 0.0)
	assert_true(player.run_blend() > 0.9, "he never got into a run to keep")
	# 90 degrees over a second and a half, which is a corner taken at a jog.
	for _tick in range(90):
		heading = heading.rotated(Vector3.UP, deg_to_rad(1.0))
		player.advance_gait(1.0 / 60.0, heading, 0.0)
	assert_true(
		player.run_blend() > 0.9,
		"rounding a 90 degree corner over a second and a half dropped him to %.2f"
			% player.run_blend()
	)


func test_deep_snow_will_not_promote_him_however_long_he_walks() -> void:
	var player := _build()
	var north := Vector3(0.0, 0.0, -1.0)
	for _tick in range(600):
		player.advance_gait(1.0 / 60.0, north, 1.0)
	assert_true(
		player.run_blend() < 0.05,
		"ten seconds of wading a full drift promoted him to %.2f of a run" % player.run_blend()
	)


## Wading into a drift mid-run has to ease him down, not cut the speed.
func test_walking_into_a_drift_eases_the_run_off() -> void:
	var player := _build()
	var north := Vector3(0.0, 0.0, -1.0)
	for _tick in range(240):
		player.advance_gait(1.0 / 60.0, north, 0.0)
	var entered: float = player.run_blend()
	player.advance_gait(1.0 / 60.0, north, 1.0)
	var after: float = player.run_blend()
	assert_true(entered > 0.9, "he never got into a run")
	assert_true(after < entered, "the drift did not take the run off him at all")
	assert_true(
		entered - after < 0.25,
		"one tick in the drift took %.2f off the blend, which is a step and not an ease"
			% (entered - after)
	)


# ---------------------------------------------------------------------------
# The animation has to follow
# ---------------------------------------------------------------------------

## The regression the slower speeds would otherwise introduce. The idle-to-walk
## crossfade was tuned in absolute m/s against a 1.35 walk; a trudge at 0.4 m/s
## would sit part-way through it and the character would slide along half idling.
func test_the_walk_carries_him_at_every_speed_the_ground_allows() -> void:
	var player := _build()
	for wade in [0.0, 0.5, 1.0]:
		for grade in [0.0, 0.25, 0.45]:
			var speed: float = player.top_speed_at(wade, grade, 0.0)
			assert_almost_eq(
				player.motion_blend(speed, wade, grade),
				1.0,
				0.0001,
				"wading at %.3f m/s (wade %.1f, grade %+.2f) the walk only carries %.2f of him"
					% [speed, wade, grade, player.motion_blend(speed, wade, grade)]
			)


func test_standing_still_is_still_an_idle() -> void:
	var player := _build()
	assert_almost_eq(
		player.motion_blend(0.0, 0.0, 0.0),
		0.0,
		0.0001,
		"a man at a standstill is not idling"
	)
	assert_almost_eq(
		player.motion_blend(0.0, 1.0, 0.3),
		0.0,
		0.0001,
		"a man at a standstill in a drift is not idling"
	)
