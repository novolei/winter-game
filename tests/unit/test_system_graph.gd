extends TestCase

## THE SIXTH FALSE-PASS CLASS: 1,317 tests, each correct, none of which ever met
## each other.
##
## ---------------------------------------------------------------------------
## THE BUG THAT MADE THIS FILE
## ---------------------------------------------------------------------------
## `WeatherSystem`'s injector for the wind was called `set_wind()`.
##
## `WindSystem._collect()` sweeps the WHOLE TREE for any node publishing
## `set_wind()` or `set_wind_strength()` and pushes the weather into it. That
## duck-typed discovery is how a consumer gets driven with no wiring, and it is
## the pattern this codebase uses everywhere -- tree sweeps, `has_method()`
## guards, services resolved by name. It means a METHOD NAME is a project-wide
## contract.
##
## So on the first frame of the real scene the sweep found the injector and
## handed it a `Vector3`, replacing the weather system's reference to the wind
## with the wind's own velocity vector. Every call after that failed:
##
##     SCRIPT ERROR: Invalid call. Nonexistent function 'has_method' in base 'Vector3'.
##
## **All 37 of that system's unit tests passed.** Nothing in the suite built a
## `WindSystem` that swept a tree, so both systems were correct in isolation and
## disagreed the moment they shared one. It was found by running a capture.
##
## The five false-PASS classes `tools/run_tests.sh` already guards against are
## all single tests deceiving themselves. This one is different in kind, and the
## pattern it exploits -- two systems agreeing by name rather than by type -- is
## the pattern the whole architecture is built on.
##
## ---------------------------------------------------------------------------
## WHAT THIS FILE IS, AND WHAT IT DELIBERATELY IS NOT
## ---------------------------------------------------------------------------
## It is NOT a second suite that runs everything together. That would be slow,
## flaky, and it would rot. It is the smallest graph that can reproduce the
## failure, plus a short list of assertions on the values that actually travel
## between systems -- the ones where a type or a unit could disagree.
##
## THE PRIMARY ASSERTION IS THE CONSOLE. `tools/run_tests.sh` already fails the
## run on any `SCRIPT ERROR`, `ERROR:`, `WARNING:`, `Parse Error`, leak or
## resource still in use. So a test that boots the real systems and ticks them
## turns a wiring fault into console dirt with nobody having to have predicted
## it. That reuses a gate which has already caught five classes rather than
## inventing a sixth mechanism -- and it is the only kind of assertion that can
## catch a fault nobody thought of.
##
## ---------------------------------------------------------------------------
## HOW IT TICKS, SAID PLAINLY
## ---------------------------------------------------------------------------
## The whole suite runs inside ONE `_process()` call of the runner's SceneTree
## (see `tests/framework/test_runner.gd`), so the engine cannot tick anything
## for us mid-test. `_step()` therefore walks the graph in tree order, sorted by
## `process_priority`, and calls `_process(delta)` itself.
##
## That is an emulation, and here is exactly how faithful it is:
##
##   FAITHFUL   tree order, process_priority, per-frame delta, `_ready()` (real
##              -- `add_child()` on a live tree fires it synchronously), service
##              registration, EventBus dispatch, and the tree sweeps, which walk
##              the real `/root`.
##   NOT        `_physics_process`, input, rendering, `set_process(false)`, and
##              anything that needs a frame boundary to happen between two
##              calls.
##
## The bug this exists for lived in `_process` and in a tree sweep, which is the
## faithful half. Anything that needs a real frame boundary is out of scope and
## should say so rather than be faked.
##
## ---------------------------------------------------------------------------
## THE GAP THIS DOES NOT CLOSE, MEASURED AND NAMED
## ---------------------------------------------------------------------------
## **Shaders are compiled by the rendering server on a later frame, and the whole
## suite lives inside one.** So a `.gdshader` that does not compile is invisible
## to this graph, to the console gate, and to every test in the project.
##
## That is not hypothetical. A throwaway probe that built this same graph and
## ticked past the first frame printed, once per build:
##
##     SHADER ERROR: Using 'return' in the 'sky' processor function is incorrect.
##     ERROR: Shader compilation failed.
##
## and the suite -- with this file in it -- was clean, because the runner quits
## inside frame one. A bare `ProceduralSkyMaterial` built the same way is silent,
## so it is a project shader and not the engine.
##
## `RenderingServer.force_draw()` would close it: one synchronous frame, and a
## broken shader becomes console dirt like everything else. It is NOT done here,
## deliberately, because the first thing it would do is turn another agent's
## in-flight shader into this file's red suite. It is a gate change and belongs
## to whoever owns the gate. See the report for this task.

const EventBusScript := preload("res://src/core/event_bus.gd")
const WorldClockScript := preload("res://src/systems/world_clock.gd")
const TrackMaskScript := preload("res://src/systems/track_mask.gd")
const SnowAccumulationScript := preload("res://src/systems/snow_accumulation.gd")
const LightingDirectorScript := preload("res://src/rendering/lighting_director.gd")
const SnowfallScript := preload("res://src/rendering/snowfall.gd")
const WindSystemScript := preload("res://src/systems/wind_system.gd")
const WeatherSystemScript := preload("res://src/systems/weather_system.gd")

## Services the graph registers in the LIVE ServiceRegistry, because that is how
## the game resolves them and a stand-in registry would not be this test. Cleared
## in `after_each` whatever happens, so no later test inherits them.
const GRAPH_SERVICES: Array[StringName] = [
	&"track_mask", &"snow_accumulation", &"lighting", &"snowfall", &"wind", &"weather",
]

## ---------------------------------------------------------------------------
## THE VOCABULARY ALLOWLISTS -- the general form of the bug
## ---------------------------------------------------------------------------
## A hook name in this project is a contract between systems that never mention
## each other. These lists say WHO IS ALLOWED TO ANSWER each vocabulary, by
## script path, and `test_no_system_answers_a_vocabulary_it_did_not_mean_to`
## fails any node in the graph that answers one without being on the list.
##
## Adding a line here must be a deliberate act. That is the whole mechanism: an
## injector, a setter or a debug helper that happens to pick a name another
## system sweeps for goes red until somebody confirms it meant to.

## `WindSystem.drive()` pushes into these: `set_wind(Vector3)` -- an
## acceleration in m/s^2 -- and `set_wind_strength(float)` -- 0..1.
const WIND_VOCABULARY := ["set_wind", "set_wind_strength"]
const WIND_CONSUMERS := [
	"res://src/rendering/snowfall.gd",
	"res://src/systems/track_mask.gd",
	"res://src/systems/snow_accumulation.gd",
]

## `Snowfall._tell_the_ground()` and `WeatherSystem._drive()` push into this.
const SNOWFALL_VOCABULARY := ["set_snowfall_rate"]
const SNOWFALL_CONSUMERS := [
	"res://src/rendering/snowfall.gd",
	"res://src/systems/track_mask.gd",
	# Its own override hook, not a driven one -- `WindSystem` deliberately leaves
	# this system alone (see `_is_fed_by_the_sky`). Listed because the rule is
	# "who speaks this vocabulary", and the answer being three rather than two is
	# a fact worth having written down.
	"res://src/systems/snow_accumulation.gd",
]

## `WeatherSystem._find_wildlife()` sweeps for a node answering BOTH of these.
## Nothing in this graph is a flock, so the expected answer is nobody.
const WILDLIFE_VOCABULARY := ["scatter", "available_perches"]
const WILDLIFE_CONSUMERS: Array[String] = []

var _root: Node = null
var _bus: Node = null
var _clock: Node = null
var _mask: Node = null
var _accumulation: Node = null
var _lighting: Node = null
var _snowfall: Node = null
var _wind: Node = null
var _weather: Node = null


# --- building the graph -------------------------------------------------------


## The real systems, in `scenes/main.tscn`'s own order, under a throwaway root
## that is a child of the LIVE `/root` -- which it must be, because
## `WindSystem._rescan()` sweeps from `get_tree().get_root()` and a graph parked
## anywhere else would never be found by the very mechanism under test.
func before_each() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.get_root() == null:
		return
	_root = Node.new()
	_root.name = "SystemGraph"
	tree.get_root().add_child(_root)

	# A PRIVATE EventBus, injected into everything that will take one. The live
	# `/root/EventBus` would work and would be more faithful, but this graph
	# fires `clock.night_started`, and the real MusicDirector, NightExposure and
	# OccluderFader autoloads are subscribed to the live bus -- moving their
	# state from here would be this test breaking other tests, which is worse
	# than the small loss of fidelity.
	_bus = EventBusScript.new()
	_bus.name = "GraphBus"
	_root.add_child(_bus)

	_clock = _system(WorldClockScript, "WorldClock")
	_mask = _system(TrackMaskScript, "TrackMask")
	_accumulation = _system(SnowAccumulationScript, "SnowAccumulation")
	_lighting = _lighting_director()
	_snowfall = _system(SnowfallScript, "Snowfall")
	_wind = _system(WindSystemScript, "Wind")
	_weather = _system(WeatherSystemScript, "Weather")

	# The graph's OWN clock, handed over before the first tick. `attach()` would
	# otherwise resolve the live `/root/WorldClock` autoload, and this test would
	# be planning weather against whatever day the real run happens to be on.
	_weather.set_world_clock(_clock)

	_clock.load_schedules_from_directory()
	_clock.start()


## Constructed, wired, THEN added -- in that order, because `_ready()` fires
## synchronously on `add_child()` into a live tree, and a system that resolved
## its bus from `/root` before we could inject ours would join the live one.
func _system(script: Script, node_name: String) -> Node:
	var node: Node = script.new()
	node.name = node_name
	if node.has_method("set_event_bus"):
		node.set_event_bus(_bus)
	_root.add_child(node)
	return node


## The one node that is not a bare script: `LightingDirector` is a
## `WorldEnvironment` and aims a `Sun` child it looks up by name.
func _lighting_director() -> Node:
	var director: Node = LightingDirectorScript.new()
	director.name = "Lighting"
	# Off before _ready(), so nothing in a headless run can build the F1 panel.
	director.debug_controls_enabled = false
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	director.add_child(sun)
	director.set_event_bus(_bus)
	_root.add_child(director)
	return director


## `free()`, not `queue_free()`: a deferred free needs a frame boundary the
## runner never reaches, so the whole graph would be reported as leaked
## ObjectDB instances and the gate would fail the run. `free()` on the root
## descends, and every `_exit_tree()` runs -- which is what unregisters the
## services and unsubscribes from the bus.
func after_each() -> void:
	# Before anything is freed. `WeatherSystem` pushes its stat modifiers onto
	# the LIVE SurvivalSystem autoload -- which is correct, it is the real wiring
	# -- and `_exit_tree()` does not take them off. A blizzard's 2x temperature
	# drain left behind here would be inherited by every test that ran after this
	# file, which is the cross-test contamination this whole file exists to make
	# visible rather than to commit.
	if _weather != null and is_instance_valid(_weather):
		_weather.clear_now()
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null
	_bus = null
	_clock = null
	_mask = null
	_accumulation = null
	_lighting = null
	_snowfall = null
	_wind = null
	_weather = null
	# Belt and braces. Every system unregisters itself in `_exit_tree()`, but a
	# service left behind in the LIVE registry would be inherited by every test
	# that ran after this file -- the exact cross-test contamination the runner's
	# header warns about.
	var registry := _registry()
	if registry == null:
		return
	for service in GRAPH_SERVICES:
		if registry.has(service):
			registry.unregister(service)


func _registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.get_root() == null:
		return null
	return tree.get_root().get_node_or_null("ServiceRegistry")


# --- ticking ------------------------------------------------------------------


## Every node in the graph that has a `_process`, in tree order, sorted by
## `process_priority` -- which is the order the engine itself uses, and which
## `CrowFlock` already depends on (it sets priority 10 so it reads wire
## positions after whatever moved them).
func _process_order() -> Array:
	var found: Array = []
	_gather(_root, found)
	var indexed: Array = []
	for index in range(found.size()):
		indexed.append({"node": found[index], "index": index})
	indexed.sort_custom(func(a, b) -> bool:
		var pa: int = (a["node"] as Node).process_priority
		var pb: int = (b["node"] as Node).process_priority
		if pa != pb:
			return pa < pb
		# Stable: equal priority keeps tree order, which is what the engine does
		# and what a system relying on running after another depends on.
		return int(a["index"]) < int(b["index"]))
	var ordered: Array = []
	for entry in indexed:
		ordered.append(entry["node"])
	return ordered


func _gather(node: Node, into: Array) -> void:
	for child in node.get_children():
		if child.has_method("_process"):
			into.append(child)
		_gather(child, into)


func _step(frames: int, delta := 1.0 / 60.0) -> void:
	var ordered := _process_order()
	for frame in range(frames):
		for node in ordered:
			if is_instance_valid(node):
				node._process(delta)


## Every node in the graph, whether it processes or not.
func _all_nodes() -> Array:
	var found: Array = []
	_gather_all(_root, found)
	return found


func _gather_all(node: Node, into: Array) -> void:
	for child in node.get_children():
		into.append(child)
		_gather_all(child, into)


func _answers_all(node: Node, vocabulary: Array) -> bool:
	for name in vocabulary:
		if not node.has_method(name):
			return false
	return true


func _script_path(node: Node) -> String:
	var script := node.get_script() as Script
	return "" if script == null else script.resource_path


# --- the boot test ------------------------------------------------------------


## THE ONE THAT WOULD HAVE CAUGHT IT, AND THE ONE WITH ALMOST NO ASSERTIONS.
##
## Boot the real graph, run a weather through its warning and its arrival, and
## let `tools/run_tests.sh` judge the console. The bug this file exists for
## printed a `SCRIPT ERROR` on every frame; nobody had to predict it, and nobody
## has to predict the next one either.
##
## The weather is deliberately part of it: the collision only reaches a call
## when a weather event is actually driving the wind, which is
## `WeatherSystem._hand_the_wind()` and `_drive()`, and both need an event
## running. A boot test that only idled would have been green.
func test_the_real_system_graph_boots_and_runs_a_weather_without_a_word_on_the_console() -> void:
	assert_not_null(_root, "the graph should have been built")
	if _root == null:
		return
	# Idle first, so the wind completes at least two sweeps (`rescan_seconds` is
	# 2.0) and has certainly seen every node in the tree.
	_step(150)
	assert_true(_wind.consumer_count() > 0,
		"the wind found nothing to drive, so this graph proves nothing")
	assert_true(_weather.begin(&"blizzard"),
		"the blizzard should be on disk and startable")
	# Through the warning, the arrival, and into the weather.
	_step(90, 0.5)
	assert_eq(_weather.phase(), _weather.PHASE_ACTIVE,
		"the weather should have landed by 45 simulated seconds")


# --- the general form of the bug ----------------------------------------------


## THE REGRESSION TEST, WRITTEN AS THE RULE RATHER THAN AS THE INSTANCE.
##
## A hook name is a contract between systems that never mention each other. Any
## node answering one of those vocabularies is going to be swept up and driven,
## whether it meant to be or not -- so every node that answers must be on the
## list of nodes that mean to.
##
## Re-introducing the original bug -- renaming `WeatherSystem.set_wind_system()`
## back to `set_wind()` -- turns this red with the offending script named, which
## is the whole point: the failure says what to fix rather than only that
## something is wrong.
func test_no_system_answers_a_vocabulary_it_did_not_mean_to() -> void:
	assert_not_null(_root, "the graph should have been built")
	if _root == null:
		return
	var checked := 0
	for node in _all_nodes():
		var path := _script_path(node)
		for hook in WIND_VOCABULARY:
			if node.has_method(hook):
				checked += 1
				assert_true(WIND_CONSUMERS.has(path),
					"%s answers %s(), so WindSystem's sweep will drive it. Rename it,"
						% [path, hook]
						+ " or add it to WIND_CONSUMERS and mean it.")
		for hook in SNOWFALL_VOCABULARY:
			if node.has_method(hook):
				checked += 1
				assert_true(SNOWFALL_CONSUMERS.has(path),
					"%s answers %s(), so the sky will drive it" % [path, hook])
		if _answers_all(node, WILDLIFE_VOCABULARY):
			checked += 1
			assert_true(WILDLIFE_CONSUMERS.has(path),
				"%s looks like a flock to WeatherSystem's tell" % path)
	assert_true(checked >= 3,
		"the sweep found %d hook(s) in the graph, which is too few to have"
			% checked + " checked anything -- did the graph fail to build?")


# --- the values that actually travel ------------------------------------------


## Wind -> the sky, the ground and the snow load model. Three consumers, two
## different vocabularies, one of which is a scalar and one a vector, which is
## exactly where a unit or a type can disagree without either side noticing.
func test_the_wind_reaches_the_snowfall_and_the_track_mask() -> void:
	if _root == null:
		return
	_step(150)
	var strength: float = _wind.strength()
	assert_true(strength > 0.0,
		"the wind is not blowing at all, so nothing below proves anything")
	assert_almost_eq(_snowfall.wind_strength(), strength, 0.001,
		"the sky is not being told how hard the wind is blowing")
	assert_almost_eq(_mask.wind_strength(), strength, 0.001,
		"the ground is not being told, so footprints will never scour")
	# The direction, too. `Snowfall.gale_wind` is the one property the wind
	# writes rather than calls a hook on, because a scalar cannot carry a
	# heading -- so it is the one most likely to be silently dropped.
	var heading: Vector3 = _wind.direction()
	var gale: Vector3 = _snowfall.gale_wind.normalized()
	assert_almost_eq(gale.dot(heading), 1.0, 0.01,
		"the snow is not blowing the way the wind is")


## `SnowAccumulation` is the awkward one, and deliberately covered on its own.
## `WindSystem` REFUSES to call its wind hook, because that hook also latches
## "stop reading the sky" -- so the wind is delivered THROUGH `Snowfall`, and a
## watchdog pushes it directly if the sky ever stops passing it on. Two systems,
## one value, and a third arrangement in between them: nothing but a graph can
## check it.
func test_the_wind_reaches_the_accumulation_through_the_sky() -> void:
	if _root == null:
		return
	_step(200)
	assert_almost_eq(_accumulation.wind_strength(), _wind.strength(),
		_wind.passthrough_tolerance,
		"the snow load's wind has drifted from the wind's own")
	# ...and that it is still SKY-fed rather than overridden, which the number
	# above cannot tell you: a wind delivered directly would match just as well.
	# `SnowAccumulation.set_wind_strength()` latches a flag meaning BOTH
	# "somebody owns the wind" AND "stop reading the sky", so if the wind had
	# taken it, the snowfall rate below would be frozen. Move the sky and see.
	var before: float = _accumulation.snowfall_rate()
	_snowfall.set_snowfall_rate(0.9)
	_step(40, 0.5)
	assert_true(_accumulation.snowfall_rate() > before + 0.4,
		"the accumulation stopped reading the sky (%.3f -> %.3f): something took"
			% [before, _accumulation.snowfall_rate()]
			+ " its override, and that flag freezes the snowfall as well as the wind")


func test_the_snowfall_rate_reaches_the_track_mask_and_the_accumulation() -> void:
	if _root == null:
		return
	_step(150)
	var rate: float = _snowfall.snowfall_rate()
	assert_true(rate > 0.0, "day 1 should be snowing a little; it never is 0")
	assert_almost_eq(_mask.snowfall_rate(), rate, 0.001,
		"the ground is not being told how hard it is snowing, so prints will"
			+ " never fill in")
	assert_almost_eq(_accumulation.snowfall_rate(), rate, 0.02,
		"the snow load is not reading the sky")


## THE SPECIFIC REGRESSION, BLACK-BOX. With the original bug the weather's
## reference to the wind is a `Vector3`, `set_gale_multiplier()` is never
## reached, and this reads 1.0 -- no exception needed, no white-box peek at the
## weather's internals.
func test_a_weathers_wind_multiplier_reaches_the_wind_system() -> void:
	if _root == null:
		return
	_step(150)
	assert_almost_eq(_wind.gale_multiplier(), 1.0, 0.001,
		"nothing should be scaling the wind before a weather asks")
	assert_true(_weather.begin(&"blizzard"), "the blizzard should be startable")
	# Most of the way through the warning: the blizzard's tell raises the bite to
	# 1.3x before the storm is here at all.
	_step(50, 0.5)
	assert_true(_wind.gale_multiplier() > 1.15,
		"the weather's wind multiplier never reached the wind: %.3f"
			% _wind.gale_multiplier())
	assert_almost_eq(_weather.applied_wind_multiplier(), _wind.gale_multiplier(), 0.001,
		"the weather thinks it applied a different number from the one the wind has")


## Clock -> lighting -> the wind's profile and the sky's rate. The longest chain
## in the game and the one with the most systems that do not know each other:
## `WorldClock` publishes a phase change, `LightingDirector` crossfades to the
## day's night look, and `WindSystem` and `Snowfall` each notice the look changed
## and follow it. Nobody in that chain holds a reference to anybody else.
func test_the_clock_reaches_the_lighting_and_the_weather_follows_the_sky() -> void:
	if _root == null:
		return
	_step(30)
	var opening: StringName = _lighting.target_preset_id()
	assert_eq(opening, &"pale_day", "day 1 opens on PALE DAY")
	var daylight_wind: WindProfile = _wind.active_profile()
	assert_not_null(daylight_wind, "the wind should have a profile on day 1")
	# Straight to the end of day 1's daylight. `advance()` carries all the
	# clock's logic, so a phase boundary costs one call rather than 36,000 ticks.
	_clock.advance(_clock.phase_duration() + 1.0)
	assert_true(_clock.is_night(), "the clock should have crossed into night")
	# Long enough for the 8 s lighting crossfade and the 6 s wind crossfade.
	_step(60, 0.5)
	assert_eq(_lighting.target_preset_id(), &"nightfall",
		"the lighting did not follow the clock into day 1's night")
	assert_false(_wind.active_profile() == daylight_wind,
		"the wind is still blowing the daylight's profile after nightfall --"
			+ " a whiteout and a pale day sharing one wind is the defect"
			+ " data/weather/wind_map.tres exists to fix")
