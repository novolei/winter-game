extends Node

## THE SIX WEATHERS, AND THE WARNING EVERY ONE OF THEM GIVES FIRST.
##
## GDD section 7 is a two-layer design, and both layers are here:
##
##   编排层  the day's budget and its forced beats -- day 7 is always the storm.
##           Authored in `data/schedule/day_NN.tres`, read through `WorldClock`.
##   事件层  which weather is drawn, and when. Authored in `data/weather/*.tres`,
##           one `WeatherEventDefinition` per kind, scanned by type.
##
## and above both of them its iron law, which is the reason this file is shaped
## the way it is:
##
##   铁律：所有事件必须先预兆再落地。天空就是天气预报 UI——玩家读天色决定
##   "再往前走一段"还是"现在掉头"。无预警的风暴不是难度，是不公平。
##
## The sky IS the forecast UI, because this game has no HUD. A storm with no
## warning is not difficulty, it is unfairness.
##
## ---------------------------------------------------------------------------
## THE TELL IS AN EVENT. THE WEATHER IS A STATE. BOTH EXIST, AND BOTH ARE NEEDED.
## ---------------------------------------------------------------------------
## This is the single most important thing to understand before consuming any of
## it, and getting it backwards is a defect this project has already paid for
## once from the other direction.
##
## `CrowFlock`'s header records why it refused to drive its flock from
## `wind.gust_started`: that event fires on the profile's own 0.30 crossing and
## NEVER AGAIN as the gust builds, so a flock refusing it there would sit out the
## 0.798 peak behind it. An event saying "something began" cannot answer "how
## strong is it now".
##
## So this file publishes both, deliberately, and they are not interchangeable:
##
##   SUBSCRIBE for the moments.  `weather.tell_started` fires once, on the
##     crossing, carrying the sound to play, how long there is to play it, and
##     whether the birds went up. `weather.arrived` / `fading` / `cleared` are
##     the other three crossings. A sound, a bird, a line of dialogue.
##
##   POLL for the weather.  `ServiceRegistry.get_service(&"weather")` answers
##     `phase()`, `tell_progress()`, `seconds_until_arrival()`, `intensity()`
##     and `visibility()` -- all continuous, all correct on every frame of every
##     ramp, none of them requiring the caller to have been listening earlier.
##
## A consumer that reconstructed the current weather from remembered events
## would be rebuilding this state machine out of its own transitions, and would
## be wrong for the whole of every arrival. Do not.
##
## ---------------------------------------------------------------------------
## NOTHING HERE POPS
## ---------------------------------------------------------------------------
## The owner has twice insisted: 切记不能突变. Every value this system applies is
## a lerp from WHATEVER WAS APPLIED ON THE LAST FRAME OF THE PREVIOUS PHASE
## toward the new phase's target -- `_hold_snow` / `_hold_wind`, captured at each
## transition. That makes continuity structural rather than a property of the
## numbers: a tell that stops the snow dead hands 0.0 to the arrival ramp, which
## climbs from 0.0, and no ordering of the data can put a step in.
##
## `test_the_intensity_never_steps_across_a_whole_event` sweeps a full arc at
## 20 Hz and fails on any frame that moves more than a few per cent.
##
## ---------------------------------------------------------------------------
## THE FOUR HOOKS, AND THE ONE THAT IS NOT USED
## ---------------------------------------------------------------------------
## Everything below lands on something that already existed:
##
##   LIGHT  `LightingDirector.crossfade_to(id, seconds)`. Not permanent; the next
##          phase change fades away from it by itself.
##   AIR    `WindSystem.set_map()` and `set_gale_multiplier()`.
##   SNOW   `Snowfall.set_snowfall_rate()`.
##   BODY   `SurvivalSystem.push_modifier()` / `remove_source()`.
##   LIFE   `CrowFlock.scatter(cause)`.
##
## `WindSystem.set_profile()` IS DELIBERATELY NEVER CALLED, and that is the one
## decision in this file worth arguing about. It looks like the obvious hook --
## its own comment says a weather task should use it -- and it SNAPS: it adopts
## the new profile immediately and re-settles the model at the same clock, so
## forcing a still night to a gale steps the strength by about half its range in
## one frame. It also latches `_overridden` for ever, which would stop the wind
## following the sky for the rest of the run and make this file responsible for
## reproducing the whole preset-to-profile mapping.
##
## `set_map()` does neither. It only clears the wind's memory of which sky it
## last resolved, so the next frame re-resolves through the new map and
## CROSSFADES over `WindSystem.profile_response_seconds`. Same one call, no step,
## no override -- and it is what makes 风向突变 expressible at all, since a
## heading lives on a profile and a profile is what a map hands over.
##
## `src/systems/wind_system.gd` was not edited to make this work.

const SERVICE := &"weather"
const EVENTS_DIRECTORY := "res://data/weather"

## Where the wind goes back to when a weather has passed. Duplicated from
## `WindSystem.MAP_PATH` rather than reached for, because systems do not hold
## references to one another -- and pinned equal to it by
## `test_the_default_wind_map_is_the_one_the_wind_system_boots_on`, so the
## duplicate cannot drift.
const DEFAULT_WIND_MAP_PATH := "res://data/weather/wind_map.tres"

const PHASE_CLEAR := &"clear"
const PHASE_TELL := &"tell"
const PHASE_ACTIVE := &"active"
const PHASE_FADE := &"fade"

const EVENT_TELL_STARTED := &"weather.tell_started"
const EVENT_ARRIVED := &"weather.arrived"
const EVENT_FADING := &"weather.fading"
const EVENT_CLEARED := &"weather.cleared"
const EVENT_SNOW_INPUTS_CHANGED := &"snow.inputs_changed"

## Spelled out rather than preloaded off WorldClock, the same way MusicDirector
## and NightExposure spell them out. Deleting the clock has to leave this file
## compiling.
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"
const EVENT_RUN_FINISHED := &"clock.run_finished"
const EVENT_RUN_RESET := &"game.run_reset"
const RUN_SEED_SERVICE := &"run_seed"

## What `CrowFlock.scatter()` is told took the birds. Its own constants name the
## player, nightfall and a gust; the weather is a fourth cause and is passed as a
## plain name rather than by editing that file, which `scatter()`'s signature
## allows by design.
const CAUSE_WEATHER := &"weather"

## Off, and no weather is ever drawn. What a capture or a lighting pass flips
## rather than deleting the node -- and what a tool forcing its own snowfall
## needs, since a running weather would overwrite it on the next frame.
@export var enabled := true

## GDD section 7's floor, enforced as a CLAMP and not only as a default on the
## definition. A tell of zero seconds is the one authoring mistake that breaks
## the design pillar outright while looking exactly like an ordinary tuning
## value, so no `.tres` is allowed to get under this.
@export var minimum_tell_seconds := 20.0

## How long the weather takes to come fully on once it has landed. Matched to
## `Snowfall.rate_response_seconds` and `WindSystem.profile_response_seconds`,
## because all three are showing the same front arriving and they must not
## disagree about when it got here.
@export var arrival_seconds := 6.0

## How many weathers may be drawn per phase, on top of the day's forced beat.
@export var events_per_phase := 1

## Seconds from the start of a phase to its first weather, and between weathers
## after that. The floor is generous on purpose: a storm that lands in the first
## few seconds of a day gives the player nothing to have planned around.
@export var first_gap_seconds := Vector2(45.0, 110.0)
@export var gap_seconds := Vector2(90.0, 200.0)

## Deterministic when non-zero, which is what a capture and a test both need. In
## the game it is left at zero and seeded from the clock, so two runs are not the
## same week.
@export var random_seed := 0

@export var events_directory := EVENTS_DIRECTORY
@export var default_wind_map_path := DEFAULT_WIND_MAP_PATH

var _events: Dictionary = {}
var _order: Array[StringName] = []

var _phase: StringName = PHASE_CLEAR
var _event: WeatherEventDefinition = null
var _phase_elapsed := 0.0
var _phase_duration := 0.0
var _active_seconds := 0.0

## What is applied RIGHT NOW, and what it was on the last frame of the previous
## phase. The second is the whole of why nothing steps -- see the header.
var _applied_snow := 0.0
var _applied_wind := 1.0
var _hold_snow := 0.0
var _hold_wind := 1.0
var _intensity := 0.0

## One-way doors, taken lazily. `Snowfall.set_snowfall_rate()` latches a
## permanent override on the sky, so an event with no opinion about the snow must
## never open it -- see `_take_the_snowfall()`.
var _owns_snow := false
var _owns_wind_bite := false
## Whether a map other than the default is currently handed to the wind, and
## whether the light was moved, so that clearing restores only what was taken.
var _handed_map = null
var _touched_light := false
## The look the day was wearing when the warning began. What the sky goes back
## to, and what the ambient snowfall rate is computed from while a weather is
## painting the sky something else.
var _preset_before: StringName = &""

var _queue: Array[StringName] = []
var _next_in := 0.0

var _bus = null
var _lighting = null
var _snow = null
var _wind = null
var _wildlife = null
var _survival = null
var _clock = null
var _sky_table: Dictionary = {}
var _sky_default := 0.0
var _default_map: WindMap = null
var _subscribed := false
var _rng := RandomNumberGenerator.new()
var _run_seed := 0


# --- lifecycle ----------------------------------------------------------------


## Armed here, attached on the first frame -- NOT here. `LightingDirector` and
## `Snowfall` are siblings in `scenes/main.tscn` and a node's `_ready()` runs
## before its later siblings', so resolving them now would find services that
## have not registered. `SnowAccumulation` and `WindSystem` both wait for the
## same reason.
func _ready() -> void:
	if _events.is_empty():
		load_events_from_directory(events_directory)
	set_process(true)


func _exit_tree() -> void:
	detach()
	var registry := _registry()
	if registry != null and registry.get_service(SERVICE) == self:
		registry.unregister(SERVICE)


## Trap 3: a project autoload is a node under /root, never an engine singleton.
## And an absolute path asked for from outside the tree is an engine ERROR rather
## than a null, which is why every caller goes through this.
func _registry() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/ServiceRegistry")


func _process(delta: float) -> void:
	if not _subscribed:
		attach()
	advance(delta)


# --- wiring -------------------------------------------------------------------


func set_event_bus(bus) -> void:
	if _subscribed:
		detach()
	_bus = bus


func set_lighting(value) -> void:
	_lighting = value


## The sky's own preset-to-rate table and its fallback, read ONCE here rather
## than probed every frame. `Snowfall` publishes both as plain exported members
## with no accessor, and `sky_snowfall_rate()` runs on every frame of every
## weather -- walking a property list sixty times a second to ask a question
## whose answer never changes is the kind of cost that never shows up in a
## profile because it is spread over everything.
func set_snowfall(value) -> void:
	_snow = value
	_sky_table = {}
	_sky_default = 0.0
	if value == null:
		return
	for entry in value.get_property_list():
		match String(entry["name"]):
			"storm_by_preset":
				# Dictionaries are references in GDScript, so this tracks a live
				# edit to the sky's table rather than freezing a copy of it.
				_sky_table = value.storm_by_preset
			"default_storm":
				_sky_default = float(value.default_storm)


## `set_wind_system`, NOT `set_wind`, AND THE NAME IS LOAD-BEARING.
##
## `WindSystem` sweeps the whole tree for any node publishing `set_wind()` or
## `set_wind_strength()` and pushes the weather into it -- that duck-typed
## discovery is how a consumer gets driven with no wiring, and it means a METHOD
## NAME is a project-wide contract. A `set_wind()` here was found by that sweep
## on the first frame and handed a `Vector3`, which replaced this system's
## reference to the wind with the wind's own velocity vector. Every subsequent
## call then failed with "Nonexistent function 'has_method' in base 'Vector3'".
##
## THE UNIT SUITE COULD NOT SEE IT. Nothing in a test builds a `WindSystem` that
## sweeps a tree, so all 37 tests passed against a system that broke on the first
## frame of the real scene. It was found by running the capture -- which is the
## briefing's own rule arriving from a new direction: when a number is supposed
## to describe the picture, check it against the picture.
func set_wind_system(value) -> void:
	_wind = value


## The flock. Injected by a test or a capture; swept out of the tree otherwise --
## see `_find_wildlife()`.
func set_wildlife(value) -> void:
	_wildlife = value


func set_survival_system(value) -> void:
	_survival = value


func set_world_clock(value) -> void:
	_clock = value


func set_default_wind_map(map) -> void:
	_default_map = map


func has_event_bus() -> bool:
	return _bus != null


## Resolves whatever it was not given, starts listening, and **asks the clock
## what day it already is**.
##
## The question is not redundant with the subscription, and `CrowFlock` paid for
## learning that: a system that only subscribes never learns the phase it was
## BORN into, and would sit inert until the first transition -- up to a whole
## phase away, looking exactly like a design choice rather than a bug.
func attach() -> void:
	if is_inside_tree():
		if _bus == null:
			_bus = get_node_or_null("/root/EventBus")
		if _clock == null:
			_clock = get_node_or_null("/root/WorldClock")
		if _survival == null:
			_survival = get_node_or_null("/root/SurvivalSystem")
		var registry := _registry()
		if registry != null:
			registry.register(SERVICE, self)
			if _lighting == null:
				_lighting = registry.get_service(&"lighting")
			if _snow == null:
				# Through the setter, not the member: it is what caches the sky's
				# rate table, and assigning past it leaves every ambient rate at
				# zero for the whole run.
				set_snowfall(registry.get_service(&"snowfall"))
			if _wind == null:
				_wind = registry.get_service(&"wind")
		if _wildlife == null:
			_wildlife = _find_wildlife(get_tree().get_root() if get_tree() != null else null)
	if _default_map == null:
		_default_map = load(default_wind_map_path) as WindMap
	var seed := random_seed
	if seed == 0:
		seed = _registered_run_seed()
	set_run_seed(seed)
	ask_the_clock()
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.subscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_bus.subscribe(EVENT_RUN_FINISHED, _on_run_finished)
	_bus.subscribe(EVENT_RUN_RESET, _on_run_reset)
	_subscribed = true


func detach() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.unsubscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_bus.unsubscribe(EVENT_RUN_FINISHED, _on_run_finished)
	_bus.unsubscribe(EVENT_RUN_RESET, _on_run_reset)
	_subscribed = false


## Explicit non-zero random_seed remains the capture/test override. Ordinary
## play receives GameState's generic replay seed through ServiceRegistry on the
## first attempt and through game.run_reset on every later one.
func set_run_seed(value: int) -> void:
	_run_seed = value
	if _run_seed == 0:
		_run_seed = int(Time.get_ticks_usec() % 2147483646) + 1
	_rng.seed = _run_seed


func current_run_seed() -> int:
	return _run_seed


func _registered_run_seed() -> int:
	var registry := _registry()
	if registry == null:
		return 0
	var owner: Object = registry.get_service(RUN_SEED_SERVICE)
	if owner == null or not owner.has_method("current_run_seed"):
		return 0
	return int(owner.current_run_seed())


## The half of the day/night wiring a subscription cannot do. See `attach()`.
func ask_the_clock() -> void:
	if _clock == null or not _clock.has_method("is_running"):
		return
	if not _clock.is_running():
		return
	plan_phase(int(_clock.current_day()), bool(_clock.is_night()))


## Every node in the tree that publishes a flock's two hooks. Duck-typed rather
## than found by class or by path, which is this project's standing convention
## and here also means `src/entities/wildlife/` was not edited to be driven.
func _find_wildlife(node: Node):
	if node == null:
		return null
	for child in node.get_children():
		if child.has_method("scatter") and child.has_method("available_perches"):
			return child
		var found = _find_wildlife(child)
		if found != null:
			return found
	return null


# --- the catalogue ------------------------------------------------------------


## Scans a directory for `WeatherEventDefinition`s. BY TYPE, not by filename, so
## the wind profiles and maps that share `data/weather/` are skipped and adding a
## weather is dropping one `.tres` in -- binding rule 4, with nothing to register
## it in and no list anywhere in `src/` naming any of the six.
func load_events_from_directory(directory_path := EVENTS_DIRECTORY) -> int:
	_events.clear()
	_order.clear()
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return 0
	var file_names := dir.get_files()
	# Sorted, so a run is reproducible: the draw below is seeded, and a seeded
	# draw over a directory listing in arbitrary order is not.
	file_names.sort()
	for entry in file_names:
		var file_name := entry
		# An exported build serves data/*.tres as *.tres.remap.
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource := ResourceLoader.load(directory_path.path_join(file_name))
		if resource is WeatherEventDefinition and (resource as WeatherEventDefinition).id != &"":
			var definition := resource as WeatherEventDefinition
			_events[definition.id] = definition
			_order.append(definition.id)
	return _order.size()


func load_events(definitions: Array) -> void:
	_events.clear()
	_order.clear()
	for definition in definitions:
		if definition is WeatherEventDefinition and (definition as WeatherEventDefinition).id != &"":
			_events[definition.id] = definition
			_order.append(definition.id)


func event_ids() -> Array[StringName]:
	return _order.duplicate()


func definition(id: StringName) -> WeatherEventDefinition:
	return _events.get(id, null)


# --- the state a consumer samples ---------------------------------------------


func phase() -> StringName:
	return _phase


func active_event() -> WeatherEventDefinition:
	return _event


func event_id() -> StringName:
	return _event.id if _event != null else &""


func is_telling() -> bool:
	return _phase == PHASE_TELL


## How far through the WARNING, 0 .. 1. Zero outside the warning: once the
## weather is here the warning is over, and a value that stayed at 1 would make
## "is it still warning" a comparison rather than a reading.
func tell_progress() -> float:
	if _phase != PHASE_TELL or _phase_duration <= 0.0:
		return 0.0
	return clampf(_phase_elapsed / _phase_duration, 0.0, 1.0)


## The honest answer to "how long have I got" -- the number a player is reading
## the sky for, and the one an event cannot give.
func seconds_until_arrival() -> float:
	if _phase != PHASE_TELL:
		return 0.0
	return maxf(_phase_duration - _phase_elapsed, 0.0)


## HOW MUCH OF THE WEATHER IS ON, 0 .. 1. Zero through the whole warning -- a
## tell is a warning and not a weakened storm -- then smoothstepped up over
## `arrival_seconds`, held, and smoothstepped back down across the fade.
func intensity() -> float:
	return _intensity


## How far the frame can be seen through, relative to clear air. Continuous, so a
## route decision taken mid-arrival gets the value that is actually on screen.
func visibility() -> float:
	if _event == null:
		return 1.0
	return lerpf(1.0, _event.visibility_multiplier, _intensity)


func phase_elapsed() -> float:
	return _phase_elapsed


func phase_duration() -> float:
	return _phase_duration


func applied_snowfall_rate() -> float:
	return _applied_snow


func applied_wind_multiplier() -> float:
	return _applied_wind


## What it would be snowing if no weather were happening -- computed from the
## DAY'S OWN look and not from whatever the sky is currently wearing, or a
## blizzard would fade back toward the blizzard's own rate.
func sky_snowfall_rate() -> float:
	if _snow == null:
		return 0.0
	var id := _sky_preset_id()
	if id == &"":
		return _sky_default
	# Tried both ways round, for the same reason `Snowfall._storm_for()` does: a
	# Dictionary authored in a script has StringName keys and one edited in the
	# inspector may have String ones, and the lookup silently falling through to
	# the default is exactly the failure that reads as a tuning problem.
	if _sky_table.has(id):
		return float(_sky_table[id])
	if _sky_table.has(String(id)):
		return float(_sky_table[String(id)])
	return _sky_default


## The look the day is wearing underneath the weather.
func _sky_preset_id() -> StringName:
	if _clock != null and _clock.has_method("current_schedule"):
		var schedule = _clock.current_schedule()
		if schedule != null:
			# Annotated rather than inferred: `_clock` is untyped by design (this
			# file holds no reference to WorldClock's type), so the compiler
			# cannot type the expression and `:=` is a parse error here.
			var night: bool = _clock.has_method("is_night") and bool(_clock.is_night())
			var wanted: StringName = schedule.night_lighting_preset if night \
				else schedule.primary_lighting_preset
			if wanted != &"":
				return wanted
	if _phase != PHASE_CLEAR and _preset_before != &"":
		return _preset_before
	if _lighting != null and _lighting.has_method("active_preset"):
		var look = _lighting.active_preset()
		if look != null:
			return look.id
	return &""


# --- the orchestration --------------------------------------------------------


# EventBus calls back with exactly one argument, always -- even when the payload
# is null. A handler declaring none is a runtime error at dispatch time, not a
# parse error, so the day number is named even where it is only forwarded.
func _on_day_started(payload) -> void:
	plan_phase(int(payload), false)


func _on_night_started(payload) -> void:
	plan_phase(int(payload), true)


func _on_run_finished(_payload) -> void:
	_queue.clear()
	clear_now()


func _on_run_reset(payload) -> void:
	_queue.clear()
	_next_in = 0.0
	clear_now()
	var seed := random_seed
	if seed == 0 and payload is Dictionary:
		seed = int(payload.get("seed", 0))
	if seed == 0:
		seed = _registered_run_seed()
	set_run_seed(seed)


## Draws the phase's weather from the day's budget. Returns how many are queued.
##
## GDD section 7's 编排层: the forced beat is not a draw and cannot be missed --
## day 7 produces its blizzard whatever the random number generator thinks --
## and everything else is sampled from `allowed_weather_events` without
## replacement, so a phase never gets the same weather twice.
##
## A weather already running is left alone. A front does not stop because the sun
## went down, and cutting one short at a phase boundary would be the one place
## the seven-day structure showed through the weather.
func plan_phase(day: int, night: bool) -> int:
	_queue.clear()
	_next_in = _rng.randf_range(first_gap_seconds.x, first_gap_seconds.y)
	var schedule = _schedule_for(day)
	if schedule == null:
		return 0
	# The forced beat lands in the DAYLIGHT phase: it is the day's headline and
	# the player should be out in it, not asleep through it.
	if not night and schedule.forced_weather_event != &"" \
			and _events.has(schedule.forced_weather_event):
		_queue.append(schedule.forced_weather_event)
	var pool: Array[StringName] = []
	for id in schedule.allowed_weather_events:
		if _events.has(id) and not _queue.has(id):
			pool.append(id)
	var wanted := mini(events_per_phase, pool.size())
	for index in range(wanted):
		var pick := _rng.randi_range(0, pool.size() - 1)
		_queue.append(pool[pick])
		pool.remove_at(pick)
	return _queue.size()


func queued_ids() -> Array[StringName]:
	return _queue.duplicate()


func seconds_to_next_event() -> float:
	return _next_in if _phase == PHASE_CLEAR and not _queue.is_empty() else -1.0


func _schedule_for(day: int):
	if _clock == null or not _clock.has_method("schedule_for_day"):
		return null
	return _clock.schedule_for_day(day)


# --- the arc ------------------------------------------------------------------


## THE ONLY DOOR INTO A WEATHER, AND IT OPENS ON THE WARNING.
##
## There is deliberately no call anywhere in this file that lands a weather
## directly. `_arrive()` is private and refuses anything that is not already
## telling, so the design pillar is a property of the code's shape rather than a
## convention somebody has to remember -- and no future edit can add a storm that
## switches on.
##
## Returns false for an unknown weather, and for one asked for while another is
## running: two at once would give the second no tell of its own.
func begin(id: StringName) -> bool:
	var found: WeatherEventDefinition = _events.get(id, null)
	if found == null or _phase != PHASE_CLEAR:
		return false
	_begin_tell(found)
	return true


## Ends whatever is happening at once, restoring everything that was taken. What
## the end of a run uses, and what a test uses between two sweeps.
func clear_now() -> void:
	if _event == null:
		_phase = PHASE_CLEAR
		return
	_finish()


func advance(delta: float) -> void:
	if not enabled or not is_finite(delta) or delta <= 0.0:
		return
	if _phase == PHASE_CLEAR:
		_tick_queue(delta)
	else:
		_tick_arc(delta)
	_drive()


func _tick_queue(delta: float) -> void:
	if _queue.is_empty():
		return
	_next_in -= delta
	if _next_in > 0.0:
		return
	var id: StringName = _queue.pop_front()
	_next_in = _rng.randf_range(gap_seconds.x, gap_seconds.y)
	var found: WeatherEventDefinition = _events.get(id, null)
	if found != null:
		_begin_tell(found)


func _tick_arc(delta: float) -> void:
	_phase_elapsed += delta
	match _phase:
		PHASE_TELL:
			if _phase_elapsed >= _phase_duration:
				_arrive()
		PHASE_ACTIVE:
			if _phase_elapsed >= _phase_duration:
				_begin_fade()
		PHASE_FADE:
			if _phase_elapsed >= _phase_duration:
				_finish()


func _begin_tell(event: WeatherEventDefinition) -> void:
	_event = event
	# Read BEFORE anything moves the sky, so the look the weather interrupted is
	# what it hands back and what the ambient snowfall rate is computed from.
	_preset_before = _current_preset_id()
	_phase = PHASE_TELL
	_phase_elapsed = 0.0
	# The floor is a clamp and not only a default: see `minimum_tell_seconds`.
	_phase_duration = maxf(
		_rng.randf_range(event.tell_duration_range.x, event.tell_duration_range.y),
		minimum_tell_seconds
	)
	_active_seconds = _rng.randf_range(
		event.active_duration_range.x, event.active_duration_range.y)
	_intensity = 0.0
	if event.changes_snowfall():
		_take_the_snowfall()
	if event.changes_wind_bite():
		_owns_wind_bite = true
	_hold_snow = _applied_snow
	_hold_wind = _applied_wind
	var tell := event.tell
	var birds := 0
	if tell != null:
		if tell.lighting_preset != &"":
			# The crossfade is started LONGER than the warning so that it is only
			# `lighting_lead` of the way there when the weather lands -- the light
			# still changing THROUGH the arrival, which is what makes a front read
			# as a thing passing over rather than a state being switched.
			_crossfade(tell.lighting_preset, _phase_duration / maxf(tell.lighting_lead, 0.05))
		if tell.wind_map != null:
			_hand_the_wind(tell.wind_map)
		if tell.flushes_wildlife:
			birds = _flush_wildlife()
	_drive()
	_publish(EVENT_TELL_STARTED, {
		"seconds": _phase_duration,
		"sound": tell.sound if tell != null else &"",
		"lighting_preset": tell.lighting_preset if tell != null else &"",
		# Crows are daylight-only by design, so this is 0 for every night tell.
		# Reported rather than assumed, so nobody reads an empty wire as a cue
		# that failed to fire.
		"birds": birds,
		# Whether the warning says anything a player can SEE. False would mean a
		# storm announced only in sound, which is the pillar broken -- and
		# `tests/unit/test_weather.gd` fails any shipped event that does it.
		"silent_cue": tell != null and tell.has_silent_cue(),
	})


func _arrive() -> void:
	if _phase != PHASE_TELL or _event == null:
		return
	_phase = PHASE_ACTIVE
	_phase_elapsed = maxf(_phase_elapsed - _phase_duration, 0.0)
	_phase_duration = _active_seconds
	_hold_snow = _applied_snow
	_hold_wind = _applied_wind
	if _event.lighting_preset != &"":
		_crossfade(_event.lighting_preset, _event.lighting_fade_seconds)
	if _event.wind_map != null:
		_hand_the_wind(_event.wind_map)
	_apply_modifiers()
	_drive()
	_publish(EVENT_ARRIVED, {
		"seconds": _phase_duration,
		"visibility": _event.visibility_multiplier,
		"extinguishes_beacons": _event.extinguishes_beacons,
		"min_beacons_extinguished": _event.min_beacons_extinguished,
	})


func _begin_fade() -> void:
	_phase = PHASE_FADE
	_phase_elapsed = maxf(_phase_elapsed - _phase_duration, 0.0)
	_phase_duration = maxf(_event.fade_duration, 0.01)
	_hold_snow = _applied_snow
	_hold_wind = _applied_wind
	# The sky and the wind are handed back at the START of the fade, not at its
	# end: both crossfade on their own clocks, and a storm whose light snapped
	# home the instant its last flake fell would be the one moment in the whole
	# arc that read as a switch.
	_restore_sky()
	_drive()
	_publish(EVENT_FADING, {"seconds": _phase_duration})


func _finish() -> void:
	var finished := _event
	if _survival != null and finished != null:
		_survival.remove_source(finished.id)
	_restore_sky()
	_phase = PHASE_CLEAR
	_event = null
	_phase_elapsed = 0.0
	_phase_duration = 0.0
	_intensity = 0.0
	_preset_before = &""
	_hold_snow = _applied_snow
	_hold_wind = _applied_wind
	_drive()
	if finished != null:
		_publish(EVENT_CLEARED, {"id": finished.id}, finished)


## Puts the sky and the wind back the way the day had them. Idempotent, and it
## only undoes what was actually taken -- an event that never moved the light
## must not crossfade anything when it leaves.
func _restore_sky() -> void:
	if _touched_light:
		var wanted := _sky_preset_id()
		if wanted != &"":
			_crossfade(wanted, -1.0)
		_touched_light = false
	if _handed_map != null and _default_map != null:
		_hand_the_wind(_default_map)
		_handed_map = null


# --- driving ------------------------------------------------------------------


## THE ONE PLACE ANYTHING IS APPLIED, and every value in it is a lerp from what
## the LAST frame of the previous phase held. See the header: that is what makes
## continuity structural rather than a property of the numbers.
func _drive() -> void:
	var sky := sky_snowfall_rate()
	match _phase:
		PHASE_CLEAR:
			_intensity = 0.0
			_applied_snow = sky
			_applied_wind = 1.0
		PHASE_TELL:
			var warned := smoothstep(0.0, 1.0, tell_progress())
			_intensity = 0.0
			_applied_snow = lerpf(_hold_snow, _tell_snow_target(sky), warned)
			_applied_wind = lerpf(_hold_wind, _tell_wind_target(), warned)
		PHASE_ACTIVE:
			var landing := smoothstep(
				0.0, 1.0, clampf(_phase_elapsed / maxf(arrival_seconds, 0.01), 0.0, 1.0))
			_intensity = landing
			_applied_snow = lerpf(_hold_snow, _event_snow_target(sky), landing)
			_applied_wind = lerpf(_hold_wind, _event.wind_speed_multiplier, landing)
		PHASE_FADE:
			var going := smoothstep(
				0.0, 1.0, clampf(_phase_elapsed / maxf(_phase_duration, 0.01), 0.0, 1.0))
			_intensity = 1.0 - going
			_applied_snow = lerpf(_hold_snow, sky, going)
			_applied_wind = lerpf(_hold_wind, 1.0, going)
	if _owns_snow and _snow != null:
		_snow.set_snowfall_rate(_applied_snow)
	if _owns_wind_bite and _wind != null and _wind.has_method("set_gale_multiplier"):
		_wind.set_gale_multiplier(_applied_wind)
	# SnowField receives a semantic weather snapshot, never a direct reference to
	# this system.  This can be published every weather frame because it changes
	# only one scalar; SnowField's own fixed tick decides when sparse ground tiles
	# are actually rewritten.
	var wind_direction := Vector3.ZERO
	var wind_strength := 0.0
	if _wind != null:
		if _wind.has_method("direction"):
			wind_direction = _wind.direction()
		if _wind.has_method("strength"):
			wind_strength = float(_wind.strength())
	_publish(EVENT_SNOW_INPUTS_CHANGED, {
		"response": _event.snow_response if _event != null else null,
		"snowfall": _applied_snow,
		"wind_direction": wind_direction,
		"wind_strength": wind_strength,
	})


func _tell_snow_target(sky: float) -> float:
	var tell := _event.tell if _event != null else null
	return tell.snowfall_rate if tell != null and tell.changes_snowfall() else sky


func _tell_wind_target() -> float:
	var tell := _event.tell if _event != null else null
	return tell.wind_speed_multiplier if tell != null else 1.0


func _event_snow_target(sky: float) -> float:
	if _event == null or _event.snowfall_rate < 0.0:
		return sky
	return _event.snowfall_rate


## Opens the one-way door on the sky's rate, and opens it with the value the sky
## was ALREADY producing.
##
## `Snowfall.set_snowfall_rate()` latches a permanent override -- from that frame
## the sky stops reading the lighting presets for ever -- and its own
## `_lighting_cut()` fires once on the change, snapping the rate to whatever is
## handed over. Handing it its own current value makes the takeover invisible;
## handing it the weather's would step the snowfall of the whole world on the
## frame this system happened to wake up.
func _take_the_snowfall() -> void:
	if _owns_snow or _snow == null:
		return
	_owns_snow = true
	_applied_snow = sky_snowfall_rate()
	_hold_snow = _applied_snow
	_snow.set_snowfall_rate(_applied_snow)


func _crossfade(id: StringName, seconds: float) -> void:
	if _lighting == null or not _lighting.has_method("crossfade_to"):
		return
	_lighting.crossfade_to(id, seconds)
	_touched_light = true


func _hand_the_wind(map) -> void:
	if _wind == null or not _wind.has_method("set_map") or map == null:
		return
	if _handed_map == map:
		return
	_wind.set_map(map)
	_handed_map = map if map != _default_map else null


## The birds. `CrowFlock.scatter()` returns how many actually left, which is the
## direct answer to "did this cue land" -- zero at night, zero when the wire was
## already empty. Nothing here has to know why.
func _flush_wildlife() -> int:
	if _wildlife == null or not _wildlife.has_method("scatter"):
		return 0
	return int(_wildlife.scatter(CAUSE_WEATHER))


## Remove first, ALWAYS, then push. Not tidiness: a MULTIPLY re-pushed while the
## previous one was still on the stack compounds -- 2x becomes 4x becomes 8x,
## looks plausible for a minute, and then kills the player with nothing to trace
## it to. `NightExposure._apply()` is the same hazard written down.
##
## The source is the EVENT's id and never the modifier's own, so
## `remove_source(event.id)` is guaranteed to take every one of them off again.
func _apply_modifiers() -> void:
	if _survival == null or _event == null:
		return
	_survival.remove_source(_event.id)
	for modifier in _event.stat_modifiers:
		if modifier == null or modifier.target_stat == &"":
			continue
		_survival.push_modifier(
			modifier.target_stat,
			_event.id,
			modifier.operation,
			modifier.value,
			modifier.duration
		)


func _current_preset_id() -> StringName:
	if _lighting == null:
		return &""
	if _lighting.has_method("target_preset_id"):
		return _lighting.target_preset_id()
	if _lighting.has_method("active_preset"):
		var look = _lighting.active_preset()
		if look != null:
			return look.id
	return &""


## One payload shape for all four, so a subscriber can read any of them without
## knowing which arrived. EventBus's contract is exactly one argument -- see
## `src/core/event_bus.gd`.
func _publish(event: StringName, extra: Dictionary = {}, about: WeatherEventDefinition = null) -> void:
	if _bus == null:
		return
	var subject := about if about != null else _event
	var payload := {
		"id": subject.id if subject != null else &"",
		"display_name": subject.display_name if subject != null else "",
		"phase": _phase,
		"intensity": _intensity,
	}
	for key in extra:
		payload[key] = extra[key]
	_bus.emit_event(event, payload)
