extends TestCase

## 饥饿's single-frame reading: a retargeted, baked, standing hunch.
##
## ---------------------------------------------------------------------------
## WHAT THESE TESTS ARE FOR, WHICH IS NOT THE ARITHMETIC
## ---------------------------------------------------------------------------
## The channel, the remap and the ease are the easy half and they are tested
## below, but none of them is what could go wrong here. What could go wrong is
## that a POSTURE crossed two rigs and arrived as something else -- and this
## project has been burned three times by taking a filename or a delivery as
## evidence of contents, most recently by a take called `Limping_Walk_inplace`
## that measures as symmetric as an ordinary walk.
##
## So the load-bearing test is `test_the_hunch_that_arrived_is_the_hunch_that_
## was_measured`: it stands the shipping model up, plays the shipping take out of
## the shipping library, and measures the angle off the SKELETON. The first bake
## of this take passed every other assertion in this file and delivered a 10.5
## degree hunch against the source's 34.9, because the two rigs' spine bones are
## at different heights up the body -- every joint angle correct to a tenth of a
## degree and the silhouette wrong. Nothing but a measurement of the result would
## have caught it.
##
## ---------------------------------------------------------------------------
## AND THE OTHER LOAD-BEARING ONE IS ABOUT THE FILTER
## ---------------------------------------------------------------------------
## `hunch` is the only filtered blend in the tree. A filter that names a bone
## which is not a track in the take filters NOTHING, silently, and the readout
## then behaves like the unfiltered version -- which was measured erasing the
## cold stand outright. So the filter's paths are checked against the take's own
## tracks rather than against a list written twice.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")

## Measured on the donor take by tools/measure_hand_gesture.gd and reproduced by
## tools/retarget_hunch.gd on the bake. The source's ABSOLUTE lean is 34.9
## degrees; 8.1 of that is its own neutral idle's slouch, so what a retarget can
## carry is the 26.8 degree difference. Both ends are stated here so a future
## reader can see which number this file is holding and why.
const SOURCE_ABSOLUTE_LEAN := 34.9
const SOURCE_NEUTRAL_LEAN := 8.1
const CARRIED_LEAN := SOURCE_ABSOLUTE_LEAN - SOURCE_NEUTRAL_LEAN

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


func _build(with_body := true) -> PlayerController:
	_player = PlayerControllerScript.new()
	if with_body:
		_survival = SurvivalSystemScript.new()
		_survival.load_from_directory()
		_survival.start()
		_player.set_survival_system(_survival)
	return _player


func _drop_to(stat_id: StringName, value: float) -> void:
	_survival.push_modifier(stat_id, &"test_drop", Modifier.Operation.ADD, 0.05)
	var guard := 0
	while _survival.value_of(stat_id) > value and not _survival.is_dead() and guard < 20000:
		_survival.advance(0.25)
		guard += 1
	_survival.remove_source(&"test_drop")


# --- the take itself ----------------------------------------------------------

func test_the_bake_is_on_disk_and_is_an_animation() -> void:
	assert_true(
		ResourceLoader.exists(WandererAnimations.HUNCH_PATH),
		"%s is missing -- re-run tools/retarget_hunch.gd" % WandererAnimations.HUNCH_PATH
	)
	var take = ResourceLoader.load(WandererAnimations.HUNCH_PATH)
	assert_true(take is Animation, "%s did not load as an Animation" % WandererAnimations.HUNCH_PATH)


## The bake has to be the same shape as the takes it will be blended against, or
## the blend is between two different sets of tracks and the bones one of them
## omits drift toward their rest as its weight rises.
func test_the_bake_carries_the_same_tracks_the_model_s_own_takes_do() -> void:
	var library := WandererAnimations.build()
	var hunched := library.get_animation(WandererAnimations.IDLE_HUNCHED)
	var idle := library.get_animation(WandererAnimations.IDLE)
	assert_not_null(hunched, "the library has no %s" % WandererAnimations.IDLE_HUNCHED)
	assert_not_null(idle, "the library has no %s" % WandererAnimations.IDLE)
	if hunched == null or idle == null:
		return
	assert_eq(
		hunched.get_track_count(), idle.get_track_count(),
		"the hunch and the neutral idle must carry the same tracks to be blended"
	)
	var idle_paths := {}
	for track in range(idle.get_track_count()):
		idle_paths["%s/%d" % [idle.track_get_path(track), idle.track_get_type(track)]] = true
	for track in range(hunched.get_track_count()):
		var key := "%s/%d" % [hunched.track_get_path(track), hunched.track_get_type(track)]
		assert_true(idle_paths.has(key), "the hunch carries %s and the idle does not" % key)


func test_the_hunch_loops_because_it_is_an_idle() -> void:
	var library := WandererAnimations.build()
	var hunched := library.get_animation(WandererAnimations.IDLE_HUNCHED)
	assert_not_null(hunched)
	if hunched == null:
		return
	assert_eq(hunched.loop_mode, Animation.LOOP_LINEAR, "a stand that stops is not a stand")
	# The donor take is 1.7 s. Asserted because a take that arrived trimmed, or
	# padded with the whole preceding timeline, is briefing trap 15.2 and imports
	# without a word.
	assert_almost_eq(hunched.length, 1.7, 0.02, "the donor take is 1.700 s long")


## THE ONE THAT MATTERS. Measured off the skeleton, through the shipping library,
## on the shipping model.
func test_the_hunch_that_arrived_is_the_hunch_that_was_measured() -> void:
	var leans := _leans_of([
		WandererAnimations.IDLE, WandererAnimations.IDLE_COLD, WandererAnimations.IDLE_HUNCHED,
	])
	if leans.is_empty():
		assert_true(false, "could not stand the model up to measure it")
		return
	var neutral: float = leans[WandererAnimations.IDLE]
	var cold: float = leans[WandererAnimations.IDLE_COLD]
	var hunched: float = leans[WandererAnimations.IDLE_HUNCHED]
	# The wanderer's own two idles, as the scale everything else is read against.
	assert_true(neutral < 5.0, "the neutral idle should stand up straight, reads %.1f deg" % neutral)
	assert_true(
		cold > 8.0 and cold < 22.0,
		"the cold huddle should tuck a little, reads %.1f deg" % cold
	)
	# ...and the transferred posture, against the number the donor take holds.
	# Three degrees of tolerance: the two rigs' spines are different lengths and
	# the transfer is of orientation, so the hips-to-head angle is a consequence
	# rather than a copied value.
	assert_almost_eq(
		hunched - neutral, CARRIED_LEAN, 3.0,
		"the donor take bends %.1f deg further than its own neutral stand; this one bends %.1f"
			% [CARRIED_LEAN, hunched - neutral]
	)
	# And the reason the readout is worth having at all: it has to be a long way
	# clear of the posture 体温 already owns, or the two readings are one.
	assert_true(
		hunched - cold > 10.0,
		"the hunger stand must not be mistakable for the cold huddle: %.1f against %.1f deg"
			% [hunched, cold]
	)


## The lean of each named take, in degrees off the body's own up axis, keyed by
## take name.
##
## Stands the real model up, which allocates a Node -- so it is built, measured
## and freed inside one call and nothing escapes (briefing constraint 2).
func _leans_of(takes: Array) -> Dictionary:
	var found := {}
	var scene := ResourceLoader.load(WandererAnimations.MODEL_PATH) as PackedScene
	if scene == null:
		return found
	var model := scene.instantiate() as Node3D
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(model)
	var player := _first(model, "AnimationPlayer") as AnimationPlayer
	var skeleton := _first(model, "Skeleton3D") as Skeleton3D
	if player == null or skeleton == null:
		model.free()
		return found
	if player.has_animation_library(&""):
		player.remove_animation_library(&"")
	player.add_animation_library(&"", WandererAnimations.build())
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var hips := skeleton.find_bone("Hips")
	var head := skeleton.find_bone("Head")
	# The body's own up, off the rest pose, not the world's: this rig's
	# hips-to-head line already leans about ten degrees back at rest, so measuring
	# against world Y would report every take as bent.
	var up := (skeleton.get_bone_global_rest(head).origin
		- skeleton.get_bone_global_rest(hips).origin).normalized()
	for take in takes:
		if not player.has_animation(take):
			continue
		var length := player.get_animation(take).length
		var total := 0.0
		var count := 12
		for step in range(count):
			player.play(take)
			player.seek(length * float(step) / float(count), true)
			player.advance(0.0)
			var offset := (skeleton.get_bone_global_pose(head).origin
				- skeleton.get_bone_global_pose(hips).origin)
			var along := offset.dot(up)
			total += rad_to_deg(atan2((offset - up * along).length(), along))
		found[take] = total / float(count)
	model.free()
	return found


func _first(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var found := _first(child, type)
		if found != null:
			return found
	return null


# --- the graph ----------------------------------------------------------------

func test_the_hunger_stand_is_in_the_graph_downstream_of_the_chill() -> void:
	var graph := PlayerControllerScript.build_blend_tree()
	assert_true(graph.has_node("idle_hunched"), "the take is not in the tree")
	assert_true(graph.has_node("hunch"), "the blend that plays it is not in the tree")
	assert_eq(
		_feeding(graph, "hunch", 0), "chill", "the hunger stand has to sit on top of the cold one"
	)
	assert_eq(
		_feeding(graph, "hunch", 1), "idle_hunched", "the hunger stand's input 1 is the take"
	)
	assert_eq(
		_feeding(graph, "motion", 0), "hunch",
		"the standing branch has to reach `motion` through the hunch, not around it"
	)


## Which node feeds `input` of `node`.
##
## Read off the tree's own `node_connections`, which is a FLAT array of triples
## -- [into, which input, from] -- and is the only place the wiring is legible
## from GDScript: AnimationNodeBlendTree exposes connect_node() but no reader,
## so a graph whose nodes all exist and are all wired to the wrong things would
## otherwise pass every assertion this suite can make.
func _feeding(graph: AnimationNodeBlendTree, node: String, input: int) -> String:
	var connections = graph.get("node_connections")
	if not (connections is Array):
		return ""
	var flat: Array = connections
	for index in range(0, flat.size() - 2, 3):
		if String(flat[index]) == node and int(flat[index + 1]) == input:
			return String(flat[index + 2])
	return ""


## Every blend in this tree is synced deliberately; this one earns it by sitting
## at zero for most of most runs, which without sync freezes it at frame one.
func test_the_hunger_blend_is_synced_like_every_other_blend_here() -> void:
	var graph := PlayerControllerScript.build_blend_tree()
	var hunch := graph.get_node("hunch") as AnimationNodeBlend2
	assert_not_null(hunch)
	if hunch == null:
		return
	assert_true(hunch.sync, "an unsynced idle re-enters the mix at a stale frame")


## The filter is the thing standing between this readout and the one that erased
## 体温, so its paths are checked against the take's own tracks. A bone named
## wrongly here filters nothing at all, in silence.
func test_the_filter_names_bones_the_take_actually_animates() -> void:
	var graph := PlayerControllerScript.build_blend_tree()
	var hunch := graph.get_node("hunch") as AnimationNodeBlend2
	assert_not_null(hunch)
	if hunch == null:
		return
	assert_true(hunch.filter_enabled, "without this the filter paths are decoration")
	var library := WandererAnimations.build()
	var take := library.get_animation(WandererAnimations.IDLE_HUNCHED)
	if take == null:
		assert_true(false, "no baked take to check the filter against")
		return
	var tracks := {}
	for track in range(take.get_track_count()):
		tracks[String(take.track_get_path(track))] = true
	for bone in PlayerControllerScript.HUNCH_BONES:
		var path := "%s:%s" % [WandererAnimations.SKELETON_PATH, bone]
		assert_true(tracks.has(path), "the filter names %s and the take has no such track" % path)
		assert_true(
			hunch.is_path_filtered(NodePath(path)),
			"%s is in HUNCH_BONES and is not filtered on the blend" % path
		)


## The arms are excluded ON PURPOSE and it is the whole reason the cold readout
## survives, so the exclusion is asserted rather than left to the list's contents.
func test_the_filter_leaves_the_arms_and_the_legs_to_the_cold_readout() -> void:
	var graph := PlayerControllerScript.build_blend_tree()
	var hunch := graph.get_node("hunch") as AnimationNodeBlend2
	assert_not_null(hunch)
	if hunch == null:
		return
	for bone in [
		"Hips", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
		"RightShoulder", "RightArm", "RightForeArm", "RightHand",
		"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot",
	]:
		assert_false(
			hunch.is_path_filtered(
				NodePath("%s:%s" % [WandererAnimations.SKELETON_PATH, bone])
			),
			"%s is filtered, so the hunger stand would take it from the cold huddle" % bone
		)


# --- the channel, the remap and the ease --------------------------------------

func test_a_fed_man_stands_up_straight() -> void:
	var player := _build()
	assert_almost_eq(player.carriage_ceiling(), 1.0, 0.0001, "a fed man keeps his carriage")
	assert_almost_eq(player.hunch_target(), 0.0, 0.0001, "and no part of the stand is in him")


func test_a_body_with_no_survival_model_stands_up_straight() -> void:
	var player := _build(false)
	assert_almost_eq(player.carriage_ceiling(), 1.0, 0.0001)
	assert_almost_eq(player.hunch_target(), 0.0, 0.0001, "an unmodelled body is not a starving one")


## The two authored tiers, read back off the shipped `.tres` rather than typed in
## here, so a tuning pass that moved them fails this test rather than shipping a
## readout nobody notices.
func test_the_two_authored_tiers_land_above_the_floor() -> void:
	var player := _build()
	var floor_value: float = PlayerControllerScript.HUNGER_HUNCH_FLOOR
	_drop_to(&"hunger", 0.20)
	var first := player.hunch_target()
	assert_true(
		first >= floor_value,
		"the first tier has to be readable, and it lands at %.2f against a floor of %.2f"
			% [first, floor_value]
	)
	assert_true(first < 1.0, "the first tier is not the last word")
	_drop_to(&"hunger", 0.01)
	assert_almost_eq(
		player.hunch_target(), 1.0, 0.0001, "a man with nothing left is bent as far as the take goes"
	)


## The remap is the point of the floor: the tiers are stated in the data as 0.5
## and 0.0 of his carriage, and a raw 0.5 would put the first tier at 0.50, below
## where the stoop reads.
func test_the_tiers_are_remapped_onto_the_floor_rather_than_used_raw() -> void:
	var player := _build()
	_drop_to(&"hunger", 0.20)
	var floor_value: float = PlayerControllerScript.HUNGER_HUNCH_FLOOR
	var lost := 1.0 - player.carriage_ceiling()
	assert_almost_eq(
		player.hunch_target(), floor_value + lost * (1.0 - floor_value), 0.0001,
		"the target is the remap of what the channel says, and nothing else"
	)


func test_the_stand_eases_in_rather_than_snapping_at_the_threshold() -> void:
	var player := _build()
	_drop_to(&"hunger", 0.01)
	var target := player.hunch_target()
	var first := player.advance_hunch(1.0 / 60.0)
	assert_true(first > 0.0, "it has to start moving")
	assert_true(
		first < target * 0.5,
		"a threshold that is visible as a snap is the one thing a game with no HUD must not show"
	)
	# Thirty seconds. `hunch_rise` is 0.5, a two-second time constant, so ten
	# seconds leaves it at 0.993 -- an exponential ease never arrives and the
	# snap-to only fires inside 0.001.
	for _step in range(1800):
		player.advance_hunch(1.0 / 60.0)
	assert_almost_eq(player.hunch_blend(), target, 0.001, "and it has to arrive")


## Straightening up is faster than bending over, which is the opposite asymmetry
## from the feet and is deliberate: hunger is a tide and a meal is an event.
func test_he_straightens_up_faster_than_he_bent_over() -> void:
	var player := _build()
	assert_true(
		player.hunch_fall > player.hunch_rise,
		"a man stands up within seconds of eating and bends over across an afternoon"
	)


# --- the data -----------------------------------------------------------------

## The channel has to be published by the stat, or every test above passes with
## a readout nothing can ever reach -- which is exactly the state `vision:focus`
## was found in.
func test_hunger_publishes_the_channel_the_body_reads() -> void:
	var player := _build()
	assert_almost_eq(
		player.carriage_ceiling(), 1.0, 0.0001, "a full belly must not bend him"
	)
	_drop_to(&"hunger", 0.20)
	assert_true(
		player.carriage_ceiling() < 1.0,
		"data/stats/hunger.tres has to reach stand:carriage or the body cannot read it"
	)
	_drop_to(&"hunger", 0.01)
	assert_almost_eq(
		player.carriage_ceiling(), 0.0, 0.0001, "the second tier takes his carriage entirely"
	)


## The other four stats must NOT reach it. A readout that several stats drive is
## a readout that says nothing, which is the whole risk this posture was weighed
## against.
func test_nothing_but_hunger_touches_the_carriage() -> void:
	var player := _build()
	for stat in [&"core_temperature", &"thirst", &"fatigue", &"frostbite_hands", &"frostbite_feet"]:
		_drop_to(stat, 0.01)
		assert_almost_eq(
			player.carriage_ceiling(), 1.0, 0.0001,
			"%s moved stand:carriage, and only hunger may" % stat
		)
		_survival.restore(stat, 2.0)
