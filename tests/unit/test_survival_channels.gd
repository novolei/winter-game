extends TestCase

## The other end of the survival system's published contract.
##
## SurvivalSystem publishes seven behaviour channels out of res://data/stats --
## the localised half of GDD section 5, kept out of GDScript so that "tired men
## walk slower" is a row in a .tres rather than a branch in the player
## controller. Four of them now have a consumer, and these are the tests that
## say so:
##
##   locomotion:run_speed       -> PlayerController.run_ceiling(), and so can_run()
##   locomotion:run_snow_limit  -> PlayerController.run_snow_ceiling(), and so
##                                 can_run()
##   breath:rate                -> BreathFog, through PlayerController
##
## ---------------------------------------------------------------------------
## THE BODY GATES; IT DOES NOT SCALE
## ---------------------------------------------------------------------------
## `locomotion:speed` and `locomotion:snow_cost` were both plain multipliers and
## both are GONE, by the owner's ruling that only snow depth and terrain slope
## scale movement speed. The GDD's requirements survive as capabilities instead:
##
##   疲劳高 -> 移速下降、雪深惩罚加剧   becomes "a tired man loses the run in half
##                                     the snow depth a fresh man manages"
##   归零 -> 无法奔跑                   unchanged; it was already a gate
##   足部冻伤 -> 移速永久下降           becomes "sore feet cannot carry a run
##                                     through a drift, ruined feet cannot carry
##                                     one at all"
##
## The four tests below that used to assert a multiply now assert the gate. That
## is a design change and not a weakening -- each one is named for what it now
## checks, and test_the_body_never_scales_the_number_only_gates_the_run is the
## new one that pins the rule itself.
##
## ignition:speed, aim:steadiness and vision:focus are still published and still
## unconsumed: there is no fire-lighting action, no weapon and no
## post-processing for them to modulate, and inventing one of each would mean two
## of each later.
##
## ---------------------------------------------------------------------------
## THE TRAP
## ---------------------------------------------------------------------------
## EVERY survival stat is a RESERVE: 1.0 is healthy, 0.0 is dead. So "how cold am
## I" is 1.0 - fraction_of(&"core_temperature"), NOT the fraction. Written the
## obvious way round, a man in perfect health breathes like a man about to die
## and stands like one too -- and it would look deliberate, because there is no
## HUD to contradict it. test_a_healthy_man_is_not_read_as_freezing is that
## mistake as a test.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const BreathFogScript := preload("res://src/entities/player/breath_fog.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")

var _player: PlayerController = null
var _breath: BreathFog = null
var _survival = null

func after_each() -> void:
	# All four extend Node, which is not reference counted (briefing
	# constraint 2). The player is freed last: it owns nothing here, but a fog
	# handed to it must not outlive the reference.
	if _breath != null:
		_breath.free()
		_breath = null
	if _player != null:
		_player.free()
		_player = null
	if _survival != null:
		_survival.free()
		_survival = null

# --- helpers ---------------------------------------------------------------

## A body running the SHIPPED survival model. These tests are about the wiring,
## but the numbers they read back are the authored ones, so a tuning pass that
## broke the sign of an interlock would fail here too.
func _build_body():
	_survival = SurvivalSystemScript.new()
	_survival.load_from_directory()
	_survival.start()
	return _survival

func _build_player(with_body := true) -> PlayerController:
	_player = PlayerControllerScript.new()
	if with_body:
		_player.set_survival_system(_build_body())
	return _player

## Drops a stat by ADDING to its drain. A MULTIPLY cannot move frostbite, whose
## base decay is zero by design -- it is a function of exposure, not of time --
## so the harness has to add rather than scale. There is no setter on the
## survival model, deliberately, and a test does not get one either.
func _drop_to(stat_id: StringName, value: float) -> void:
	_survival.push_modifier(stat_id, &"test_drop", Modifier.Operation.ADD, 0.05)
	var guard := 0
	while _survival.value_of(stat_id) > value and not _survival.is_dead() and guard < 20000:
		_survival.advance(0.25)
		guard += 1
	_survival.remove_source(&"test_drop")

# --- locomotion -------------------------------------------------------------

## The regression test. The terrain speed model was here first and the channels
## MULTIPLY INTO IT; they do not replace it. A healthy man gets exactly the
## terrain model and nothing else.
##
## Restated when the model was rebuilt around Tobler's hiking function -- the
## shape it asserted (an absolute wade_speed, lerped to from the run) no longer
## exists. What it is defending has not changed: with a healthy body the
## channels must be invisible. tests/unit/test_locomotion.gd owns the terrain
## model's own numbers.
func test_a_healthy_body_moves_exactly_as_it_did_before() -> void:
	var player := _build_player()
	var bare := PlayerController.new()
	for wade in [0.0, 0.5, 1.0]:
		for gait in [0.0, 1.0]:
			assert_almost_eq(
				player.top_speed_at(wade, 0.0, gait),
				bare.top_speed_at(wade, 0.0, gait),
				0.0001,
				"a healthy man at wade %.1f, gait %.0f moves at %f where a body with no "
					% [wade, gait, player.top_speed_at(wade, 0.0, gait)]
					+ "survival model at all moves at %f" % bare.top_speed_at(wade, 0.0, gait)
			)
	bare.free()
	var half: float = player.top_speed_at(0.5)
	assert_true(
		half < player.top_speed_at(0.0) and half > player.top_speed_at(1.0),
		"half a drift reads %f, outside the two speeds it should sit between" % half
	)

func test_a_body_with_no_survival_model_at_all_still_walks() -> void:
	var player := _build_player(false)
	assert_almost_eq(player.top_speed_at(0.0), player.walk_speed, 0.0001)
	assert_almost_eq(player.top_speed_at(0.0, 0.0, 1.0), player.run_speed, 0.0001)
	assert_almost_eq(
		player.top_speed_at(1.0),
		player.walk_speed * player.terrain_factor(1.0, 0.0),
		0.0001
	)

## GDD section 5: 疲劳高 -> 移速下降. Restated as the gate it now is.
##
## What this used to assert -- `tired == fresh * 0.85` -- was the multiply, and
## the multiply is gone. The requirement it was defending has not been dropped:
## a tired man is genuinely worse at moving. He is worse at it by losing the RUN,
## which is a thing the player can notice happening.
func test_fatigue_takes_the_run_away_rather_than_scaling_the_walk() -> void:
	var player := _build_player()
	var fresh_walk: float = player.top_speed_at(0.0, 0.0, 0.0)
	var fresh_run: float = player.top_speed_at(0.0, 0.0, 1.0)
	_drop_to(&"fatigue", 0.25)
	assert_almost_eq(
		player.top_speed_at(0.0, 0.0, 0.0),
		fresh_walk,
		0.0001,
		"a tired man's WALK was scaled to %f from %f; the body must gate, not scale"
			% [player.top_speed_at(0.0, 0.0, 0.0), fresh_walk]
	)
	assert_almost_eq(
		player.top_speed_at(0.0, 0.0, 1.0),
		fresh_run,
		0.0001,
		"a tired man's RUN was scaled rather than taken away"
	)
	# ...and he has still lost something real: the snow he can run through.
	assert_true(
		player.run_snow_ceiling() < player.run_snow_limit - 0.0001,
		"fatigue at a quarter of a bar costs him nothing at all: the run still "
			+ "reaches a wade factor of %f" % player.run_snow_ceiling()
	)

## ...and 雪深惩罚加剧, which is the half that is easy to leave out. It is not
## enough that a tired man has lost something: the thing he loses has to be
## SNOW-DEPENDENT, or the GDD's "the snow penalty worsens" is dead data.
##
## Where it used to scale the wade factor, it now moves the depth at which the
## run goes. Same requirement, stated as a capability.
func test_a_tired_man_loses_the_run_in_shallower_snow() -> void:
	var player := _build_player()
	var fresh_limit: float = player.run_snow_ceiling()
	assert_true(fresh_limit > 0.0, "a fresh man cannot run in any snow at all")
	# A depth a fresh man runs through, chosen from his own limit rather than
	# typed in, so retuning run_snow_limit does not silently gut this test.
	var wade := fresh_limit * 0.75
	assert_true(player.can_run(wade), "a fresh man cannot run at wade %f" % wade)

	_drop_to(&"fatigue", 0.25)
	assert_false(
		player.can_run(wade),
		"a tired man still runs through wade %f, so GDD 5's 雪深惩罚加剧 is dead data"
			% wade
	)
	assert_true(
		player.can_run(0.0),
		"a tired man cannot run on bare ground either; that is 无法奔跑, which "
			+ "belongs at an EMPTY bar and not a quarter-full one"
	)

## The rule itself, as one test. Whatever the body is doing to itself, the number
## the terrain produces must be untouched -- 只受到雪深度和地形坡度的影响.
##
## Swept over a wrecked body rather than a healthy one, because a healthy body
## passes this vacuously: every channel is 1 and any multiply would be invisible.
func test_the_body_never_scales_the_number_only_gates_the_run() -> void:
	var player := _build_player()
	var bare := PlayerController.new()
	_drop_to(&"fatigue", 0.01)
	_drop_to(&"frostbite_feet", 0.15)
	for wade in [0.0, 0.5, 1.0]:
		for grade in [-0.2, 0.0, 0.3]:
			assert_almost_eq(
				player.top_speed_at(wade, grade, 0.0),
				bare.top_speed_at(wade, grade, 0.0),
				0.0001,
				"an exhausted, frostbitten man walks at %f where an untouched body "
					% player.top_speed_at(wade, grade, 0.0)
					+ "walks at %f (wade %.1f, grade %+.2f)"
						% [bare.top_speed_at(wade, grade, 0.0), wade, grade]
			)
	bare.free()
	# ...and he has lost the run entirely, which is the whole of what the body
	# is allowed to do.
	assert_false(player.can_run(0.0), "a wrecked body can still be promoted to a run")

## 归零后果: 无法奔跑. locomotion:run_speed goes to zero -- and that has to leave
## a man who cannot RUN, not a man who cannot MOVE. A body pinned at zero speed
## by an empty stat is a soft lock with no message.
func test_an_exhausted_man_can_still_walk_but_cannot_run() -> void:
	var player := _build_player()
	_drop_to(&"fatigue", 0.01)
	var spent: float = player.top_speed_at(0.0, 0.0, 1.0)
	assert_true(spent > 0.0, "an exhausted man cannot move at all: %f m/s" % spent)
	# Exactly his walk, and no longer "a bit under it": the 0.85 that used to
	# shave the number is gone, because the body gates rather than scales.
	assert_almost_eq(
		spent,
		player.walk_speed,
		0.0001,
		"an exhausted man asked for a run manages %f, which is neither his walk "
			% spent
			+ "(%f) nor nothing" % player.walk_speed
	)
	assert_false(player.can_run(0.0), "an exhausted man can still be promoted to a run")

## However the channels stack, deeper snow must never be faster than clear
## ground. It is not obvious that it cannot: the top speed on clear ground falls
## with exhaustion while the wade speed does not, so a naive lerp between them
## inverts, and a man who sprints into drifts to get away is a bug nobody would
## think to look for.
func test_deep_snow_is_never_faster_than_clear_ground() -> void:
	var player := _build_player()
	_drop_to(&"fatigue", 0.01)
	var previous: float = player.top_speed_at(0.0)
	for step in range(1, 11):
		var wade := float(step) / 10.0
		var here: float = player.top_speed_at(wade)
		assert_true(
			here <= previous + 0.0001,
			"at wade %.1f he moves at %f, faster than the %f he managed in shallower snow"
				% [wade, here, previous]
		)
		previous = here

## 足部冻伤 -> 移速永久下降. The same gates from a different stat, which is the
## point of there being channels at all -- nothing in the player controller knows
## the word "frostbite".
##
## Two stages, so worse feet are genuinely worse: sore feet cannot carry a run
## through a drift, ruined feet cannot carry one at all.
func test_frostbitten_feet_take_the_run_away_rather_than_the_speed() -> void:
	var player := _build_player()
	var whole: float = player.top_speed_at(0.0)
	var whole_limit: float = player.run_snow_ceiling()

	_drop_to(&"frostbite_feet", 0.4)
	assert_almost_eq(
		player.top_speed_at(0.0),
		whole,
		0.0001,
		"ruined feet scaled the walk to %f from %f" % [player.top_speed_at(0.0), whole]
	)
	assert_true(
		player.run_snow_ceiling() < whole_limit - 0.0001,
		"sore feet cost nothing: the run still reaches wade %f" % player.run_snow_ceiling()
	)
	assert_true(player.can_run(0.0), "sore feet already took the run away entirely")

	_drop_to(&"frostbite_feet", 0.15)
	assert_false(player.can_run(0.0), "ruined feet still leave him a run on bare ground")
	assert_almost_eq(
		player.top_speed_at(0.0),
		whole,
		0.0001,
		"ruined feet scaled the walk; 移速永久下降 is the lost RUN, not a smaller number"
	)

# --- the readouts, and the trap ---------------------------------------------

## THE TRAP, stated the way it bites. Every stat is a reserve, so a full
## core_temperature is a WARM man and must read at the FLOOR, never at 1.
##
## The floor is the owner's call: the neutral idle read as stiff, so the shiver
## never fully switches off and a healthy man carries IDLE_CHILL_FLOOR of it.
## The readout is remapped onto [FLOOR, 1] rather than clamped, so the whole
## range of the stat still moves the body.
##
## What this test is actually defending has not changed: passing fraction_of()
## straight through gives a warm man chill 1.0, and that is still caught here by
## a mile.
func test_the_chill_readout_is_the_inverse_of_the_reserve() -> void:
	var player := _build_player()
	var floor_amount: float = player.IDLE_CHILL_FLOOR
	assert_almost_eq(
		player.body_chill(),
		floor_amount,
		0.001,
		"a man at full core temperature reads as %f cold, not the floor %f"
			% [player.body_chill(), floor_amount]
	)
	_drop_to(&"core_temperature", 0.25)
	var cold: float = 1.0 - _survival.fraction_of(&"core_temperature")
	assert_almost_eq(
		player.body_chill(),
		floor_amount + cold * (1.0 - floor_amount),
		0.0001,
		"the chill readout is not the reserve remapped onto [floor, 1]"
	)
	assert_true(player.body_chill() > 0.7, "a man at a quarter of a bar barely reads as cold")

## The floor must not flatten the readout. If it were a clamp rather than a
## remap, every temperature above the floor would collapse to one identical
## pose and the body would stop saying anything until the man was nearly dead.
func test_the_floor_does_not_flatten_the_readout() -> void:
	var player := _build_player()
	_drop_to(&"core_temperature", 0.9)
	var nearly_warm: float = player.body_chill()
	_drop_to(&"core_temperature", 0.5)
	var half: float = player.body_chill()
	_drop_to(&"core_temperature", 0.1)
	var nearly_gone: float = player.body_chill()
	assert_true(nearly_warm < half, "0.9 and 0.5 of a bar read the same: %f, %f" % [nearly_warm, half])
	assert_true(half < nearly_gone, "0.5 and 0.1 of a bar read the same: %f, %f" % [half, nearly_gone])
	assert_true(nearly_gone <= 1.0, "the readout ran past 1.0: %f" % nearly_gone)

## The same mistake from the other side, because this is the one that would ship:
## fraction_of() straight through looks perfectly reasonable and produces a
## healthy man who shivers and gasps from the first frame of the game.
func test_a_healthy_man_is_not_read_as_freezing() -> void:
	var player := _build_player()
	assert_true(
		_survival.fraction_of(&"core_temperature") > 0.9,
		"the body under test is not actually healthy"
	)
	# He carries the floor's worth of shiver by design -- nobody stands still in
	# this weather. What he must never do is read as a man about to die, which is
	# exactly what passing fraction_of() straight through would produce: 1.0 on
	# the first frame of the game, with no HUD on screen to contradict it.
	var reading: float = player.body_chill()
	assert_true(
		reading < player.IDLE_CHILL_FLOOR + 0.05,
		"a healthy man reads as %f cold, above the floor %f" % [reading, player.IDLE_CHILL_FLOOR]
	)
	# The second bound is a check on the CONSTANT rather than on the arithmetic:
	# whatever the floor is set to, it has to leave the readout somewhere to go.
	# It used to read `reading < 0.6`, which was the 0.45 floor plus a margin
	# written as an absolute -- so it failed the moment the floor was deliberately
	# raised to 0.65 on the evidence in IDLE_CHILL_FLOOR's comment, without any
	# property having actually broken. Stated as headroom it survives a retune and
	# still fails on an absurd one.
	assert_true(
		1.0 - reading >= 0.2,
		"a healthy man reads as %f cold, leaving only %.2f of range above him; the floor "
			% [reading, 1.0 - reading]
			+ "has eaten the readout, and with no HUD there is nothing else to show him freezing"
	)

## With nothing driving him the authored default stands. BreathFog and the cold
## idle were tuned against chill = 1 for a reason -- everything so far happens
## outdoors in a wind -- and a scene with no survival model running must not
## quietly turn that off.
func test_with_no_survival_model_the_authored_default_stands() -> void:
	var player := _build_player(false)
	assert_almost_eq(player.body_chill(), player.chill, 0.0001)

## GDD section 9: 呼出白气的浓度 is a readout, and it has to be reading the body
## rather than a constant.
func test_the_breath_follows_the_body() -> void:
	var player := _build_player()
	_breath = BreathFogScript.new()
	# _ready() has not run: nothing has been added to the tree (briefing trap 1).
	_breath._ready()
	# The fog is built by _build_body(), which needs a scene tree. Handing it in
	# is what the controller does for itself in _build_breath().
	player.attach_breath(_breath)

	player.drive_readouts(0.0)
	_breath._process(0.0)
	var warm_life: float = _breath.lifetime

	_drop_to(&"core_temperature", 0.25)
	player.drive_readouts(0.0)
	_breath._process(0.0)
	assert_true(
		_breath.lifetime > warm_life,
		"a freezing man's breath lives %f s and a warm man's %f: the fog is not being "
			% [_breath.lifetime, warm_life]
			+ "driven by core temperature at all"
	)

## breath:rate is the channel GDD section 9's 呼吸变浅变快 lives in, and the
## shipped data puts it at 1.25 below half a bar of warmth. Asserted against the
## channel's own number rather than against 1.25, so the tuning owns the value
## and this owns the wiring.
func test_the_breath_rate_is_the_channels_own_number() -> void:
	var player := _build_player()
	_breath = BreathFogScript.new()
	_breath._ready()
	player.attach_breath(_breath)

	_drop_to(&"core_temperature", 0.4)
	var published: float = _survival.channel_value(&"breath:rate", 1.0)
	assert_true(
		published > 1.0,
		"the shipped stats publish breath:rate = %f at 0.4 of a bar; there is nothing "
			% published
			+ "here to test"
	)

	player.drive_readouts(0.0)
	var driven: float = _breath.puffs_per_second()

	# The control: the same fog, told the same thing about the body, with the
	# channel left at 1. Anything other than the channel's own factor between the
	# two means breath:rate is not reaching the emitter.
	var control := BreathFogScript.new()
	control._ready()
	control.set_chill(player.body_chill())
	control.set_exertion(0.0)
	assert_almost_eq(
		driven,
		control.puffs_per_second() * published,
		0.0001,
		"the fog is emitting %f puffs a second where breath:rate asks for %f"
			% [driven, control.puffs_per_second() * published]
	)
	control.free()

func test_the_breath_rate_scale_reaches_the_emitter() -> void:
	_breath = BreathFogScript.new()
	_breath._ready()
	_breath.set_chill(0.5)
	_breath.set_exertion(0.0)
	var plain: float = _breath.puffs_per_second()
	_breath.set_rate_scale(1.5)
	assert_almost_eq(
		_breath.puffs_per_second(),
		plain * 1.5,
		0.0001,
		"set_rate_scale() does not scale the rate"
	)
	assert_true(plain > 0.0, "the fog emits nothing at all to scale")

func test_an_unwired_fog_breathes_at_the_authored_rate() -> void:
	_breath = BreathFogScript.new()
	_breath._ready()
	_breath.set_chill(0.0)
	_breath.set_exertion(0.0)
	# density_warm feeds into the rate, so this is the authored resting rate for
	# a warm body and nothing else. A default scale of anything but 1 would move
	# it and every screenshot taken so far with it.
	assert_almost_eq(
		_breath.puffs_per_second(),
		_breath.puff_rate_rest * lerpf(0.7, 1.0, _breath.density_warm),
		0.0001,
		"the default rate scale is not 1"
	)
