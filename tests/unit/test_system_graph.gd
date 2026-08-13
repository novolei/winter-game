extends TestCase

## THE SIXTH FALSE-PASS CLASS: 1,317 tests, each correct, none of which ever met
## each other.
##
## ---------------------------------------------------------------------------
## THE BUG THAT MADE THIS FILE
## ---------------------------------------------------------------------------
## `WeatherSystem`'s injector for the wind was called `set_wind()`.
##
## At the time, `WindSystem._collect()` swept the WHOLE TREE for any node
## publishing `set_wind()` or `set_wind_strength()` and pushed the weather into
## it. A method name was accidentally being treated as consent.
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
## The production contract is now explicit: only nodes in `wind_consumer` are
## driven. A hook without that group is harmless, and the focused wind test
## proves both the registered and unregistered halves of the rule.
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
##              registration, EventBus dispatch, and SceneTree group discovery.
##   NOT        `_physics_process`, input, rendering, `set_process(false)`, and
##              anything that needs a frame boundary to happen between two
##              calls.
##
## The historical bug lived in `_process` and group discovery now runs in that
## same faithful half. Anything that needs a real frame boundary is out of scope and
## should say so rather than be faked.
##
## ---------------------------------------------------------------------------
## THE SHADER GAP THIS FILE ONCE OWNED -- NOW CLOSED, AND FOR A DIFFERENT REASON
## ---------------------------------------------------------------------------
## This header used to record that shaders are compiled on a later frame, that
## the suite lives inside the first one, and that `RenderingServer.force_draw()`
## would close it. **The first claim was measured again on 4.7.1 and is wrong,
## and the third does not follow.**
##
## A shader is compiled SYNCHRONOUSLY when its resource loads --
## `Shader.set_code()` -> `RenderingServer.shader_set_code()`, which parses and
## fails loudly even under the dummy driver. No frame is involved. Re-breaking
## `aurora_sky.gdshader` with the historical fault turned the suite RED at HEAD
## with no framework change at all, because this file's own `_lighting_director()`
## loads it. `force_draw()` runs silently headless and adds nothing.
##
## What was actually invisible: a shader NO TEST LOADS is never handed to the
## rendering server, so it is never parsed. Two of the nine were in that state,
## and `assets/shaders/chimney_smoke.gdshader` was proven dead with the suite
## still reporting 1842 passed, 0 failed, console clean.
##
## `tests/art/test_shader_compiles.gd` now loads every project shader, which is
## what closes it. The full measurement is in
## `.superpowers/sdd/wave3/task-w3-shader-gate-report.md`.

const EventBusScript := preload("res://src/core/event_bus.gd")
const WorldClockScript := preload("res://src/systems/world_clock.gd")
const TrackMaskScript := preload("res://src/systems/track_mask.gd")
const SnowAccumulationScript := preload("res://src/systems/snow_accumulation.gd")
const LightingDirectorScript := preload("res://src/rendering/lighting_director.gd")
const SnowfallScript := preload("res://src/rendering/snowfall.gd")
const WindSystemScript := preload("res://src/systems/wind_system.gd")
const WeatherSystemScript := preload("res://src/systems/weather_system.gd")

## For the static, project-wide half of the vocabulary rule below.
const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

## Services the graph registers in the LIVE ServiceRegistry, because that is how
## the game resolves them and a stand-in registry would not be this test. Cleared
## in `after_each` whatever happens, so no later test inherits them.
const GRAPH_SERVICES: Array[StringName] = [
	&"track_mask", &"snow_accumulation", &"lighting", &"snowfall", &"wind", &"weather",
]

## ---------------------------------------------------------------------------
## THE VOCABULARY INVENTORIES
## ---------------------------------------------------------------------------
## These lists record WHO IMPLEMENTS each inter-system vocabulary, by script
## path. They keep the shared terms auditable, but for wind a method name no
## longer authorises delivery: the scene's `wind_consumer` group does.
##
## Adding a line here must still be deliberate: an injector and a setter should
## not silently share a name without the distinction being documented.

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

## ---------------------------------------------------------------------------
## THE SAME INVENTORY, WIDENED FROM THE GRAPH TO THE PROJECT
## ---------------------------------------------------------------------------
## The three lists above govern the SEVEN systems this file boots. The source
## inventory includes the rest, so a shared hook remains visible even when no
## graph test instantiates its owner.
##
## That is not a hypothetical either. This defect has now fired TWICE -- once on
## `WeatherSystem`, which this graph was built to catch, and once on the ambience
## director, which is NOT in this graph and which the graph therefore did not
## catch. The gate built after the first occurrence did not stop the second.
##
## So the lists below are read against the SOURCE, not against the tree: every
## `.gd` under `res://src` that DECLARES one of these hooks must be named here.
## A static scan sees a script whether or not any test ever instantiates it,
## which is the only way to cover the systems this graph does not build.
##
## What it cannot see, said plainly: a hook inherited from a base class rather
## than declared, and a method installed at runtime. Inheriting from a script on
## this list is a deliberate act by somebody who read it; installing a driven
## hook at runtime is not something this project does anywhere.
##
## ADDING A LINE HERE IS A PERSON DECIDING. It documents the shared vocabulary;
## adding a `wind_consumer` group is the separate act that enables delivery.

## Every script under `res://src` that declares `set_wind()` or
## `set_wind_strength()`; only registered scene instances are driven.
const PROJECT_WIND_CONSUMERS := [
	"res://src/entities/player/breath_fog.gd",
	"res://src/entities/snow_load.gd",
	"res://src/entities/wildlife/bird_flock.gd",
	"res://src/rendering/chimney_smoke.gd",
	"res://src/rendering/snowfall.gd",
	"res://src/rendering/snowfall_layer.gd",
	"res://src/rendering/spindrift.gd",
	"res://src/rendering/wind_pendulum.gd",
	"res://src/rendering/wind_sway.gd",
	"res://src/systems/snow_accumulation.gd",
	"res://src/systems/track_mask.gd",
]

## Every script under `res://src` that declares `set_snowfall_rate()`.
const PROJECT_SNOWFALL_CONSUMERS := [
	"res://src/entities/snow_load.gd",
	"res://src/rendering/snowfall.gd",
	"res://src/rendering/snowfall_layer.gd",
	"res://src/systems/snow_accumulation.gd",
	"res://src/systems/track_mask.gd",
]

## Every script under `res://src` that declares BOTH wildlife hooks and so looks
## like a flock to `WeatherSystem._find_wildlife()`. `bird.gd` and
## `src/ui/breath.gd` each declare `scatter()` alone -- the sweep needs both, so
## neither is picked up, and neither belongs here.
const PROJECT_WILDLIFE_CONSUMERS := [
	"res://src/entities/wildlife/bird_flock.gd",
]

## Where the static scan looks. `res://tests` is deliberately out: a test double
## declaring `set_snowfall_rate()` is the point of the double, and no sweep can
## reach it.
const VOCABULARY_SCAN_ROOT := "res://src"

## The floor for how many declarations the scan must find, for the same reason
## `test_runner.gd` has MINIMUM_TESTS: every assertion below judges a
## declaration it found, and none of them can see one the scan stopped
## returning. Sixteen wind hooks, five snowfall hooks and one flock at the time
## of writing.
const MINIMUM_VOCABULARY_DECLARATIONS := 20

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
## that is a child of the LIVE `/root`. It must be live because WindSystem reads
## SceneTree's group registry, not an arbitrary unattached object graph.
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
	# Group membership is the wind contract. A hook alone is deliberately not
	# enough: WeatherSystem and AmbienceDirector both once collided with it.
	for consumer in [_mask, _accumulation, _snowfall]:
		consumer.add_to_group(WindSystemScript.CONSUMER_GROUP)

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
	# Idle first, so all registered consumers have received several real graph
	# frames before the weather begins.
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
## A hook name is shared vocabulary between systems that never mention each
## other. The inventory keeps those shared terms intentional; explicit group
## membership, tested in `test_wind.gd`, decides whether WindSystem delivers.
##
## Re-introducing the original bug -- renaming `WeatherSystem.set_wind_system()`
## back to `set_wind()` -- turns this red with the offending script named, which
## is the whole point: the failure says what to fix rather than only that
## something is wrong.
func test_system_vocabulary_is_documented() -> void:
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
					"%s answers %s() but is absent from the wind vocabulary inventory"
						% [path, hook])
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
		"the graph found %d hook(s), which is too few to have"
			% checked + " checked anything -- did the graph fail to build?")


## THE SAME RULE AGAINST THE WHOLE PROJECT, AND THE REASON IT HAD TO BE WIDENED.
##
## The test above can only judge nodes this file builds. The full source
## inventory sees every declaration under `res://src`, whether or not a test
## instantiates it, including the ambience injector involved in the second
## historical collision.
##
## Adding `func set_wind(system)` to a script outside PROJECT_WIND_CONSUMERS
## turns this red with the script named.
func test_project_vocabulary_is_documented() -> void:
	var scripts := _project_scripts()
	var found := 0
	for path in scripts:
		var code := FileAccess.get_file_as_string(path)
		for hook in WIND_VOCABULARY:
			if not _declares(code, hook):
				continue
			found += 1
			assert_true(PROJECT_WIND_CONSUMERS.has(path),
				"%s declares %s() but is absent from the wind vocabulary inventory"
					% [path, hook])
		for hook in SNOWFALL_VOCABULARY:
			if not _declares(code, hook):
				continue
			found += 1
			assert_true(PROJECT_SNOWFALL_CONSUMERS.has(path),
				"%s declares %s(), so the sky will drive it" % [path, hook])
		var flock := true
		for hook in WILDLIFE_VOCABULARY:
			if not _declares(code, hook):
				flock = false
				break
		if flock:
			found += 1
			assert_true(PROJECT_WILDLIFE_CONSUMERS.has(path),
				"%s declares every wildlife hook, so it looks like a flock to WeatherSystem's tell" % path)
	assert_true(found >= MINIMUM_VOCABULARY_DECLARATIONS,
		("the scan found %d declaration(s) across %d script(s) under %s, expected at least %d --"
			% [found, scripts.size(), VOCABULARY_SCAN_ROOT, MINIMUM_VOCABULARY_DECLARATIONS])
			+ " a scan that stopped seeing the source passes over everything")


## The two scopes cannot drift apart. Anything the graph names as a consumer is
## by definition a script that declares the hook, so it must also be on the
## project-wide list -- otherwise the widened rule would contradict the narrow
## one and whichever ran second would look like the bug.
func test_the_graph_allowlists_are_a_subset_of_the_project_allowlists() -> void:
	for path in WIND_CONSUMERS:
		assert_true(PROJECT_WIND_CONSUMERS.has(path),
			"%s is a graph wind consumer but is missing from PROJECT_WIND_CONSUMERS" % path)
	for path in SNOWFALL_CONSUMERS:
		assert_true(PROJECT_SNOWFALL_CONSUMERS.has(path),
			"%s is a graph snowfall consumer but is missing from PROJECT_SNOWFALL_CONSUMERS" % path)
	for path in WILDLIFE_CONSUMERS:
		assert_true(PROJECT_WILDLIFE_CONSUMERS.has(path),
			"%s is a graph wildlife consumer but is missing from PROJECT_WILDLIFE_CONSUMERS" % path)
	# Anti-vacuity: three empty lists would satisfy every loop above.
	assert_true(WIND_CONSUMERS.size() + SNOWFALL_CONSUMERS.size() >= 6,
		"the graph allowlists have shrunk to nothing, so this comparison proves nothing")


## Every `.gd` under the scan root. `AssetScanner` is reused rather than a second
## walk written here, so the two cannot disagree about what a folder contains.
## `.gdshader` and `.gd.uid` do not end in `.gd`, so neither is swept in.
func _project_scripts() -> Array[String]:
	var found: Array[String] = []
	for path in AssetScannerScript.find_files(VOCABULARY_SCAN_ROOT, [".gd"] as Array[String]):
		found.append(path)
	found.sort()
	return found


## True when `code` declares `hook` as a method of its own.
##
## Anchored at the start of the statement, so a CALL to the hook -- and the whole
## point of these vocabularies is that other systems call them -- is not mistaken
## for a declaration.
func _declares(code: String, hook: String) -> bool:
	for raw_line in code.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("func %s(" % hook) or line.begins_with("static func %s(" % hook):
			return true
	return false


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
