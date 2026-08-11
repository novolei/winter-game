extends TestCase

## The other end of the survival system's published contract.
##
## SurvivalSystem publishes seven behaviour channels out of res://data/stats --
## the localised half of GDD section 5, kept out of GDScript so that "tired men
## walk slower" is a row in a .tres rather than a branch in the player
## controller. Four of them now have a consumer, and these are the tests that
## say so:
##
##   locomotion:speed      -> PlayerController.top_speed_at()
##   locomotion:run_speed  -> PlayerController.top_speed_at()
##   locomotion:snow_cost  -> PlayerController.top_speed_at()
##   breath:rate           -> BreathFog, through PlayerController
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
const RunBootScript := preload("res://src/systems/run_boot.gd")

var _player: PlayerController = null
var _breath: BreathFog = null
var _survival = null
var _boot = null

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
	if _boot != null:
		_boot.free()
		_boot = null

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

## The regression test. The snow-depth speed model was here first and the
## channels MULTIPLY INTO IT; they do not replace it. A healthy man moves exactly
## as he did before any of this existed.
func test_a_healthy_body_moves_exactly_as_it_did_before() -> void:
	var player := _build_player()
	assert_almost_eq(
		player.top_speed_at(0.0),
		player.run_speed,
		0.0001,
		"clear ground is no longer the authored run speed"
	)
	assert_almost_eq(
		player.top_speed_at(1.0),
		player.wade_speed,
		0.0001,
		"a full drift is no longer the authored wade speed"
	)
	var half: float = player.top_speed_at(0.5)
	assert_true(
		half < player.run_speed and half > player.wade_speed,
		"half a drift reads %f, outside the two speeds it should sit between" % half
	)

func test_a_body_with_no_survival_model_at_all_still_walks() -> void:
	var player := _build_player(false)
	assert_almost_eq(player.top_speed_at(0.0), player.run_speed, 0.0001)
	assert_almost_eq(player.top_speed_at(1.0), player.wade_speed, 0.0001)

## GDD section 5: 疲劳高 -> 移速下降. locomotion:speed is 0.85 below a third of
## the bar.
func test_fatigue_takes_speed_off_clear_ground() -> void:
	var player := _build_player()
	var fresh: float = player.top_speed_at(0.0)
	_drop_to(&"fatigue", 0.25)
	var tired: float = player.top_speed_at(0.0)
	assert_almost_eq(
		tired,
		fresh * 0.85,
		0.0001,
		"a tired man moves at %f against a fresh one's %f" % [tired, fresh]
	)

## ...and 雪深惩罚加剧, which is the half that is easy to leave out. It is not
## enough that a tired man is slower: he has to lose MORE in deep snow than on
## clear ground, or locomotion:snow_cost is dead data.
func test_fatigue_costs_more_in_deep_snow_than_on_clear_ground() -> void:
	var player := _build_player()
	var fresh_clear: float = player.top_speed_at(0.0)
	var fresh_deep: float = player.top_speed_at(0.5)
	_drop_to(&"fatigue", 0.25)
	var tired_clear: float = player.top_speed_at(0.0)
	var tired_deep: float = player.top_speed_at(0.5)
	var clear_ratio := tired_clear / fresh_clear
	var deep_ratio := tired_deep / fresh_deep
	assert_true(
		deep_ratio < clear_ratio - 0.02,
		"fatigue costs %.3f of the speed on clear ground and %.3f in half a drift; "
			% [1.0 - clear_ratio, 1.0 - deep_ratio]
			+ "GDD 5's 雪深惩罚加剧 says the drift must cost more"
	)

## 归零后果: 无法奔跑. locomotion:run_speed goes to zero -- and that has to leave
## a man who cannot RUN, not a man who cannot MOVE. A body pinned at zero speed
## by an empty stat is a soft lock with no message.
func test_an_exhausted_man_can_still_walk_but_cannot_run() -> void:
	var player := _build_player()
	_drop_to(&"fatigue", 0.01)
	var spent: float = player.top_speed_at(0.0)
	assert_true(spent > 0.0, "an exhausted man cannot move at all: %f m/s" % spent)
	assert_true(
		spent < player.walk_speed,
		"an exhausted man still manages %f, which is more than his own walk" % spent
	)
	assert_true(
		spent < player.run_speed * 0.35,
		"an exhausted man still runs at %f of his top speed" % (spent / player.run_speed)
	)

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

## 足部冻伤 -> 移速永久下降. The same channel from a different stat, which is the
## point of there being a channel at all.
func test_frostbitten_feet_cost_speed_through_the_same_channel() -> void:
	var player := _build_player()
	var whole: float = player.top_speed_at(0.0)
	_drop_to(&"frostbite_feet", 0.4)
	var ruined: float = player.top_speed_at(0.0)
	assert_true(
		ruined < whole,
		"ruined feet cost nothing: %f against %f" % [ruined, whole]
	)

# --- the readouts, and the trap ---------------------------------------------

## THE TRAP, stated the way it bites. Every stat is a reserve, so a full
## core_temperature is a WARM man and must read as chill 0.
func test_the_chill_readout_is_the_inverse_of_the_reserve() -> void:
	var player := _build_player()
	assert_almost_eq(
		player.body_chill(),
		0.0,
		0.001,
		"a man at full core temperature reads as %f cold; the readout is not inverted"
			% player.body_chill()
	)
	_drop_to(&"core_temperature", 0.25)
	assert_almost_eq(
		player.body_chill(),
		1.0 - _survival.fraction_of(&"core_temperature"),
		0.0001,
		"the chill readout is not 1 - the reserve"
	)
	assert_true(player.body_chill() > 0.7, "a man at a quarter of a bar barely reads as cold")

## The same mistake from the other side, because this is the one that would ship:
## fraction_of() straight through looks perfectly reasonable and produces a
## healthy man who shivers and gasps from the first frame of the game.
func test_a_healthy_man_is_not_read_as_freezing() -> void:
	var player := _build_player()
	assert_true(
		_survival.fraction_of(&"core_temperature") > 0.9,
		"the body under test is not actually healthy"
	)
	assert_true(
		player.body_chill() < 0.1,
		"a healthy man reads as %f cold; passing fraction_of() straight through gives "
			% player.body_chill()
			+ "exactly this, and with no HUD it would look like art direction"
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

# --- starting the clock ------------------------------------------------------

## Nothing in the running game called SurvivalSystem.start(), so the model never
## ticked: the whole system was inert in play and green in the suite. RunBoot is
## the smallest honest fix until GameState exists.
func test_the_boot_starts_the_survival_clock() -> void:
	var body = _build_body()
	body.stop()
	assert_false(body.is_running(), "the model is running before anything started it")

	_boot = RunBootScript.new()
	_boot.set_survival_system(body)
	assert_true(_boot.begin_run(), "begin_run() reported that it did nothing")
	assert_true(body.is_running(), "the survival model is still not ticking")

## Idempotent, because GameState is going to arrive and call the same thing.
## Starting again would silently reset every stat to full -- a full heal, in a
## survival game, from a line nobody would look at twice.
func test_the_boot_does_not_restart_a_run_that_is_already_going() -> void:
	var body = _build_body()
	body.advance(600.0)
	var half_a_day: float = body.value_of(&"core_temperature")
	assert_true(half_a_day < 1.0, "the model did not advance at all")

	_boot = RunBootScript.new()
	_boot.set_survival_system(body)
	assert_false(_boot.begin_run(), "it started a run that was already running")
	assert_almost_eq(
		body.value_of(&"core_temperature"),
		half_a_day,
		0.0001,
		"begin_run() healed a man who was halfway through his first day"
	)

## Armed in _ready(), fired on the first frame, and then disarmed.
##
## Not done in _ready() because autoloads are added to /root in project.godot's
## own order and an entry declared below this one would not exist yet -- a line
## in the wrong place would leave the model inert with nothing to say so, which
## is the failure this file exists to fix. And it must stop trying afterwards, or
## it would restart the run every frame after a death.
func test_the_boot_fires_on_the_first_frame_and_then_stops_trying() -> void:
	var body = _build_body()
	body.stop()
	_boot = RunBootScript.new()
	_boot.set_survival_system(body)
	# _ready() has not run: nothing has been added to the tree (briefing trap 1).
	_boot._ready()
	assert_true(_boot.is_processing(), "the boot did not arm itself")
	_boot._process(0.0)
	assert_true(body.is_running(), "the first frame did not start the run")
	assert_false(_boot.is_processing(), "the boot goes on polling after its one job is done")

func test_a_boot_told_not_to_start_never_arms_itself() -> void:
	var body = _build_body()
	body.stop()
	_boot = RunBootScript.new()
	_boot.set_survival_system(body)
	_boot.auto_start = false
	_boot._ready()
	assert_false(_boot.is_processing(), "auto_start is off and it armed anyway")
	assert_false(body.is_running(), "the run started with auto_start off")

func test_a_boot_with_nothing_to_start_is_inert_rather_than_broken() -> void:
	_boot = RunBootScript.new()
	assert_false(_boot.begin_run(), "it claimed to start a survival model it does not have")

## Briefing trap 3: a project [autoload] is a node under /root and never an
## engine singleton, so the resolution has to be get_node_or_null("/root/...").
## Written the plausible-looking way -- Engine.get_singleton -- this file would
## start nothing, for ever, with no diagnostic.
func test_the_boot_resolves_the_autoloaded_system_from_root() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "the runner is a SceneTree, so a real /root must be reachable")
	if tree == null:
		# Return rather than fall through: dereferencing a null tree aborts the
		# method, and with one assertion already counted the runner's
		# zero-assertion guard would let it print PASS.
		return
	var live = tree.root.get_node_or_null("SurvivalSystem")
	assert_not_null(live, "the SurvivalSystem autoload must be present at /root/SurvivalSystem")
	if live == null:
		return
	var was_running: bool = live.is_running()

	var boot = RunBootScript.new()
	# Off before it enters the tree: _ready() is the code path under test, and
	# an auto-start would prove nothing about the resolution.
	boot.auto_start = false
	tree.root.add_child(boot)
	var started: bool = boot.begin_run()
	var running_after: bool = live.is_running()

	# Unwind before asserting, not after. The live autoload is global state
	# shared with every later test, and a Node left under /root leaks at exit
	# (briefing constraint 2). Assertions record rather than halt, so this is
	# safe to do first.
	if not was_running:
		live.stop()
	tree.root.remove_child(boot)
	boot.free()

	# Asserted on the model rather than on the return value, so this cannot pass
	# vacuously: whether the run was already going (the autoload line is in
	# project.godot and RunBoot did this at boot) or begin_run() started it here,
	# the live model must be ticking afterwards.
	assert_true(
		running_after,
		"_ready() did not find /root/SurvivalSystem, so begin_run() had nothing to start"
	)
	assert_true(
		started or was_running,
		"begin_run() declined a model that was not running"
	)
