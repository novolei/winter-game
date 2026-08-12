extends TestCase

## The two survival stats that had no reading at all, and what the body now does
## about them.
##
## GDD section 9's premise is that there is no HUD, so every stat has to be
## legible off the world. Three of the five already were -- 体温 through the
## breath, the shiver idle and the screen frost, 疲劳 through the walk's own
## pace, 口渴 through vision:focus -- and two were not:
##
##   饥饿   nothing. The stat's entire expression was a multiply on another
##          stat's drain, so a starving man looked exactly like a fed one.
##   冻伤   its CONSEQUENCES existed -- the run gates on ruined feet, ignition
##          and aim gate on ruined hands -- but nothing on screen said so.
##
## ---------------------------------------------------------------------------
## WHY THE HUNGER TESTS ARE ABOUT THE RHYTHM AND NOT ABOUT A SPEED
## ---------------------------------------------------------------------------
## The standing ruling is that the terrain SCALES movement and the body only
## GATES it (see tools/generate_stats.gd, and
## test_the_body_never_scales_the_number_only_gates_the_run). Hunger obeys it by
## reaching `locomotion:rhythm` -- how much of the terrain's own penalty a man
## who keeps going wins back -- rather than any speed. The consequence that makes
## it a gate rather than a scaler is structural and is the first thing tested
## below: the relief is bounded by the penalty, so where the terrain costs
## nothing there is nothing for hunger to take.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")

## The wade factor of a full drift and of half of one. Named so the tables below
## read as ground rather than as numbers.
const DRIFT := 1.0
const HALF_DRIFT := 0.5
const BARE := 0.0

var _player: PlayerController = null
var _survival = null


func after_each() -> void:
	# Both extend Node, which is not reference counted (briefing constraint 2).
	if _player != null:
		_player.free()
		_player = null
	if _survival != null:
		_survival.free()
		_survival = null


# --- harness ------------------------------------------------------------------

## A body running the SHIPPED survival model, so these read back the authored
## numbers and a tuning pass that inverted an interlock fails here too.
func _build(with_body := true) -> PlayerController:
	_player = PlayerControllerScript.new()
	if with_body:
		_survival = SurvivalSystemScript.new()
		_survival.load_from_directory()
		_survival.start()
		_player.set_survival_system(_survival)
	return _player


## Drops a stat by ADDING to its drain and integrating, which is the only way in:
## there is no setter on the survival model, deliberately, and a test does not
## get one either. A MULTIPLY cannot move frostbite at all, whose base decay is
## zero by design.
func _drop_to(stat_id: StringName, value: float) -> void:
	_survival.push_modifier(stat_id, &"test_drop", Modifier.Operation.ADD, 0.05)
	var guard := 0
	while _survival.value_of(stat_id) > value and not _survival.is_dead() and guard < 20000:
		_survival.advance(0.25)
		guard += 1
	_survival.remove_source(&"test_drop")


## The top speed of a man fully in his stride against this ground. `momentum` is
## in penalty depth, so the depth of the ground's own effort is "as far into his
## stride as this ground allows".
func _settled_speed(player: PlayerController, wade: float, grade := 0.0) -> float:
	return player.top_speed_at(wade, grade, 0.0, player.terrain_effort(wade, grade))


# --- 饥饿: the rhythm ----------------------------------------------------------

## The rule the whole design rests on. If this fails, hunger has become the
## silent everywhere-slowdown that the locomotion rework existed to delete.
func test_hunger_cannot_slow_a_man_on_ground_that_costs_him_nothing() -> void:
	var player := _build()
	var bare := PlayerControllerScript.new()
	_drop_to(&"hunger", 0.01)
	for grade in [0.0, -0.05]:
		assert_almost_eq(
			_settled_speed(player, BARE, grade),
			_settled_speed(bare, BARE, grade),
			0.0001,
			"a starving man crosses bare ground at grade %+.2f at %f where a body "
				% [grade, _settled_speed(player, BARE, grade)]
				+ "with no survival model at all crosses it at %f"
					% _settled_speed(bare, BARE, grade)
		)
	bare.free()


## The other half of "it gates rather than scales": the FIRST step into a drift
## costs a starving man exactly what it costs a fed one. Only the recovery goes.
##
## This is also what keeps test_the_body_never_scales_the_number_only_gates_the_run
## true -- that test asks top_speed_at() at a cold start, which is this.
func test_the_first_step_into_a_drift_costs_a_starving_man_no_more() -> void:
	var player := _build()
	var bare := PlayerControllerScript.new()
	_drop_to(&"hunger", 0.01)
	for wade in [BARE, HALF_DRIFT, DRIFT]:
		for grade in [-0.2, 0.0, 0.3]:
			assert_almost_eq(
				player.top_speed_at(wade, grade, 0.0),
				bare.top_speed_at(wade, grade, 0.0),
				0.0001,
				"a starving man's first step at wade %.1f grade %+.2f is %f where "
					% [wade, grade, player.top_speed_at(wade, grade, 0.0)]
					+ "an untouched body's is %f" % bare.top_speed_at(wade, grade, 0.0)
			)
	bare.free()


## ...and what a player is supposed to see. Two men set off across the same
## drift; the fed one settles into it and pulls away, the starving one does not.
func test_a_starving_man_never_settles_into_a_drift() -> void:
	var player := _build()
	var fed := PlayerControllerScript.new()
	_drop_to(&"hunger", 0.01)
	var starved_speed := _settled_speed(player, DRIFT)
	var fed_speed := _settled_speed(fed, DRIFT)
	assert_true(
		starved_speed < fed_speed - 0.05,
		"a starving man settles into a full drift at %f and a fed one at %f, which "
			% [starved_speed, fed_speed]
			+ "is not a difference anybody could see"
	)
	# ...and he is left at the honest, unrelieved terrain speed. Never below it:
	# that is the line between a gate and the scaler this replaced.
	assert_almost_eq(
		starved_speed,
		player.walk_speed * player.terrain_factor(DRIFT, 0.0, 0.0),
		0.0001,
		"a starving man in a drift moves at %f, which is not the cold-start "
			% starved_speed
			+ "terrain speed of %f" % (player.walk_speed * player.terrain_factor(DRIFT, 0.0))
	)
	fed.free()


## The intermediate tier is authored and has to be visible as a middle. Two
## thresholds that produced the same body would be one threshold with a wasted
## row of data behind it.
func test_hunger_worsens_in_two_stages_rather_than_one() -> void:
	var player := _build()
	var fed := _settled_speed(player, DRIFT)
	_drop_to(&"hunger", 0.20)
	var hungry := _settled_speed(player, DRIFT)
	_drop_to(&"hunger", 0.01)
	var starving := _settled_speed(player, DRIFT)
	assert_true(
		fed > hungry and hungry > starving,
		"the three states settle into a drift at %f (fed), %f (hungry) and %f "
			% [fed, hungry, starving]
			+ "(starving), which is not a worsening"
	)


## Polarity, the trap this project has already paid for once: every stat is a
## RESERVE, so 1.0 is a FED man. Read the obvious way round, a man in perfect
## health would plod like a starving one from the first frame of the game, with
## no HUD to contradict him -- and it would read as art direction.
func test_a_fed_man_is_not_read_as_starving() -> void:
	var player := _build()
	assert_almost_eq(
		player.rhythm_ceiling(),
		player.momentum_relief,
		0.0001,
		"a man at full hunger has a rhythm ceiling of %f against the authored %f"
			% [player.rhythm_ceiling(), player.momentum_relief]
	)


func test_a_body_with_no_survival_model_keeps_its_authored_rhythm() -> void:
	var player := _build(false)
	assert_almost_eq(player.rhythm_ceiling(), player.momentum_relief, 0.0001)


## The channel is a fraction and multiplying it must not be able to leave the
## range. A rhythm above 1 would carry a man PAST the flat-shallow-snow ceiling
## that terrain_factor()'s whole structure exists to guarantee.
func test_the_rhythm_channel_stays_a_fraction() -> void:
	var player := _build()
	for value in [-3.0, 0.0, 0.5, 4.0]:
		_survival.remove_source(&"test_rhythm")
		_survival.push_modifier(
			&"locomotion:rhythm", &"test_rhythm", Modifier.Operation.MULTIPLY, value
		)
		var ceiling: float = player.rhythm_ceiling()
		assert_true(
			ceiling >= 0.0 and ceiling <= 1.0,
			"a multiply of %f puts the rhythm ceiling at %f" % [value, ceiling]
		)
	_survival.remove_source(&"test_rhythm")


## However the channel is driven, deeper snow must never come out faster than
## shallow snow. It is not obvious that it cannot: the relief is added to the
## base, so a rhythm that grew with the penalty could in principle overtake.
func test_deep_snow_is_never_faster_than_clear_ground_however_hungry_he_is() -> void:
	var player := _build()
	for hunger in [1.0, 0.2, 0.01]:
		if hunger < 1.0:
			_drop_to(&"hunger", hunger)
		var previous := _settled_speed(player, 0.0)
		for step in range(1, 11):
			var wade := float(step) / 10.0
			var here := _settled_speed(player, wade)
			assert_true(
				here <= previous + 0.0001,
				"at hunger %.2f, wade %.1f gives %f against %f in shallower snow"
					% [hunger, wade, here, previous]
			)
			previous = here


# --- 足部冻伤: the guarded walk -------------------------------------------------

## The take, before anything is wired to it. A name is the supplier's intent and
## not the contents (briefing trap 15), and this library has already shipped one
## take under a name that describes a different motion.
func _library() -> AnimationLibrary:
	return WandererAnimations.build()


func test_the_guarded_walk_take_is_present_and_loops() -> void:
	var library := _library()
	assert_true(
		library.has_animation(WandererAnimations.WALK_GUARDED),
		"the merged library holds no take called %s" % WandererAnimations.WALK_GUARDED
	)
	if not library.has_animation(WandererAnimations.WALK_GUARDED):
		return
	var take := library.get_animation(WandererAnimations.WALK_GUARDED)
	assert_eq(
		take.loop_mode, Animation.LOOP_LINEAR,
		"the guarded walk has to loop: it is a locomotion cycle, not a gesture"
	)


## The take is THREE cycles in one clip, and the whole graph depends on knowing
## that. Treating its length as its period would step three strides per stride.
##
## Asserted as a RELATIONSHIP rather than against a written-down period: the
## per-cycle length has to be close to the ordinary walk's, because a walking man
## at a walking man's cadence is what a gait cycle is. A re-export at a different
## length keeps passing; a wrong cycle count does not.
func test_the_guarded_walk_is_three_cycles_and_not_one() -> void:
	var library := _library()
	if not library.has_animation(WandererAnimations.WALK_GUARDED):
		return
	var whole: float = library.get_animation(WandererAnimations.WALK_GUARDED).length
	var walk: float = library.get_animation(WandererAnimations.WALK).length
	var cycle := whole / float(WandererAnimations.WALK_GUARDED_CYCLES)
	assert_true(
		whole > walk * 2.0,
		"the guarded walk is %.4f s against the walk's %.4f -- if it is now one "
			% [whole, walk]
			+ "cycle, WALK_GUARDED_CYCLES is stale"
	)
	assert_true(
		cycle > walk * 0.7 and cycle < walk * 1.6,
		"one cycle of the guarded walk works out at %.4f s against the walk's "
			% cycle
			+ "%.4f, which is not a walking cadence -- the cycle count is wrong"
				% walk
	)


func test_the_graph_carries_the_guarded_walk_on_its_own_rate_node() -> void:
	var graph := PlayerControllerScript.build_blend_tree()
	for name in ["walk_guarded", "guarded_rate", "footing"]:
		assert_true(graph.has_node(name), "the blend tree has no '%s' node" % name)
	if not graph.has_node("footing"):
		return
	assert_true(
		graph.get_node("guarded_rate") is AnimationNodeTimeScale,
		"guarded_rate must be a TimeScale: the take's cycle has to be carried onto "
			+ "the shared one, and use_custom_timeline does not work on this build"
	)
	# sync, for the reason every other blend in this tree has it: an input whose
	# weight reaches 0 stops advancing and re-enters at a stale phase, and two
	# locomotion cycles mixed pose by pose then straddle.
	assert_true(
		(graph.get_node("footing") as AnimationNodeBlend2).sync,
		"the footing blend is unsynced, so the guarded walk re-enters the mix at "
			+ "whatever frame it froze on"
	)


## The invariant that makes the feet plant, stated for all three locomotion
## takes: at the ground speed a clip was authored for, and with the graph mixed
## fully onto that clip, the clip plays at EXACTLY its authored rate.
##
## rate_node_scale * pace == 1. That is what "the feet plant" means arithmetically,
## and it is the one property that would break silently if a fourth clip were
## added without blending its stride into pace_for().
func test_every_locomotion_take_plays_at_its_own_rate_at_its_own_speed() -> void:
	var player := _build(false)
	var shared: float = player._cycle_period
	var cases := [
		["walk", player.anim_walk_speed, 0.0, 0.0, player._walk_period],
		["run", player.anim_run_speed, 1.0, 0.0, player._run_period],
		["guarded", player.anim_guarded_speed, 0.0, 1.0, player._guarded_period],
	]
	for row in cases:
		var pace: float = player.pace_for(float(row[1]), float(row[2]), float(row[3]))
		var clip_rate: float = float(row[4]) / maxf(shared, 0.0001) * pace
		assert_almost_eq(
			clip_rate, 1.0, 0.0001,
			"the %s take plays at %f of its authored rate at the %f m/s it was "
				% [row[0], clip_rate, float(row[1])]
				+ "authored for -- its feet skate"
		)


## ...and the rate never leaves what the guard allows. anim_max_pace exists so a
## sprint cannot spin the legs into a blur; the guarded walk is authored for a
## slower man than the walk, so it is the clip most likely to hit it.
func test_the_guarded_walk_stays_inside_the_pace_guard() -> void:
	var player := _build(false)
	var top: float = player.top_speed_at(0.0, -0.05, 0.0)
	var pace: float = player.pace_for(top, 0.0, 1.0)
	assert_true(
		pace <= player.anim_max_pace,
		"on the fastest ground in the game (%f m/s) the guarded walk wants a pace "
			% top
			+ "of %f against the guard's %f" % [pace, player.anim_max_pace]
	)


func test_sound_feet_show_nothing_at_all() -> void:
	var player := _build()
	assert_almost_eq(player.footing_ceiling(), 1.0, 0.0001)
	assert_almost_eq(player.footing_target(), 0.0, 0.0001)
	player.advance_footing(10.0)
	assert_almost_eq(
		player.footing_blend(), 0.0, 0.0001,
		"a healthy man is walking with %f of the guarded walk in him"
			% player.footing_blend()
	)


## The floor, and the reason for it: the two takes differ in POSTURE, so the
## blend is not a dial from one to the other. The first authored tier must land
## ABOVE the value at which the silhouette changes character, or a player who has
## just done real damage to his feet sees nothing until he does it twice.
func test_the_first_tier_of_frostbite_is_already_visible() -> void:
	var player := _build()
	_drop_to(&"frostbite_feet", 0.45)
	assert_true(
		player.footing_target() >= PlayerControllerScript.GUARDED_WALK_FLOOR,
		"sore feet ask for a blend of %f, below the %f at which the silhouette "
			% [player.footing_target(), PlayerControllerScript.GUARDED_WALK_FLOOR]
			+ "changes character -- the reading is invisible"
	)
	# ...and there is still range left above it, or the second tier says nothing.
	var sore: float = player.footing_target()
	_drop_to(&"frostbite_feet", 0.15)
	assert_true(
		player.footing_target() > sore + 0.1,
		"ruined feet ask for %f against sore feet's %f, which is not a worsening"
			% [player.footing_target(), sore]
	)
	assert_almost_eq(player.footing_target(), 1.0, 0.0001)


## Eased, not stepped. A body that snaps between two postures at a threshold
## makes the threshold visible, and a threshold is the one thing a game with no
## HUD must never show.
func test_the_guarded_walk_arrives_gradually() -> void:
	var player := _build()
	_drop_to(&"frostbite_feet", 0.15)
	var first: float = player.advance_footing(1.0 / 60.0)
	assert_true(
		first > 0.0 and first < 0.5,
		"one frame after his feet went he is already %f of the way into the "
			% first
			+ "guarded walk, which is a step change"
	)
	var guard := 0
	while player.footing_blend() < 0.999 and guard < 6000:
		player.advance_footing(1.0 / 60.0)
		guard += 1
	assert_true(guard < 6000, "the guarded walk never finished arriving")


# --- 手部冻伤: the hands come in -------------------------------------------------

func test_sound_hands_leave_the_stand_alone() -> void:
	var player := _build()
	assert_almost_eq(player.composure_ceiling(), 1.0, 0.0001)
	assert_almost_eq(
		player.stand_chill(), player.body_chill(), 0.0001,
		"a man with sound hands stands at %f where the cold alone says %f"
			% [player.stand_chill(), player.body_chill()]
	)


func test_ruined_hands_draw_a_warm_man_in() -> void:
	var player := _build()
	var warm: float = player.stand_chill()
	_drop_to(&"frostbite_hands", 0.15)
	assert_true(
		player.stand_chill() > warm + 0.1,
		"a warm man with ruined hands stands at %f against %f with sound ones, "
			% [player.stand_chill(), warm]
			+ "which is not something anybody could see"
	)
	assert_almost_eq(player.stand_chill(), 1.0, 0.0001)


## THE SPLIT. The stand and the breath were one number on purpose, and this is
## the case that forced them apart: a man's hands do not change how he breathes,
## and the vapour is the game's primary cold readout, so leaving them coupled
## would make the picture say "freezing" about a man who is merely damaged.
##
## The channel is pushed directly rather than reached through the stat, and that
## is not a shortcut: _drop_to() integrates the model, which drains core
## temperature on the way, so a test that dropped frostbite and then compared two
## breath values would be reading the CLOCK and calling it the hands. Pushing the
## channel moves exactly one thing.
func test_ruined_hands_do_not_thicken_the_breath() -> void:
	var player := _build()
	var breath: float = player.body_chill()
	_survival.push_modifier(
		&"stand:composure", &"test_hands", Modifier.Operation.MULTIPLY, 0.0
	)
	assert_almost_eq(
		player.composure_ceiling(), 0.0, 0.0001, "the channel did not take"
	)
	assert_almost_eq(
		player.body_chill(), breath, 0.0001,
		"ruined hands moved the breath's chill from %f to %f, and the man's core "
			% [breath, player.body_chill()]
			+ "temperature has not changed"
	)
	# ...while the stand, which is the readout that SHOULD hear them, has moved.
	assert_true(
		player.stand_chill() > player.body_chill() + 0.1,
		"the stand reads %f against the breath's %f, so the split bought nothing"
			% [player.stand_chill(), player.body_chill()]
	)
	_survival.remove_source(&"test_hands")


## Polarity again, from the other side: a man who IS freezing must not have his
## stand softened by having healthy hands. The stand takes the worse of the two.
func test_the_stand_takes_the_worse_of_the_cold_and_the_hands() -> void:
	var player := _build()
	_drop_to(&"core_temperature", 0.05)
	var frozen: float = player.body_chill()
	assert_true(frozen > 0.9, "a man at 0.05 core temperature reads %f" % frozen)
	assert_almost_eq(
		player.stand_chill(), frozen, 0.0001,
		"a freezing man with sound hands stands at %f rather than at his own %f"
			% [player.stand_chill(), frozen]
	)
