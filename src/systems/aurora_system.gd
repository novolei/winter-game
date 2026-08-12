extends Node

## 极光 -- the rare night the sky puts on a curtain.
##
## ---------------------------------------------------------------------------
## THE PROBLEM THIS SYSTEM IS SHAPED AROUND: THE CAMERA NEVER LOOKS UP
## ---------------------------------------------------------------------------
## The rig is a fixed orthographic 45-degree three-quarter view of the ground.
## The sky is not on screen at any framing the game uses -- LightingDirector says
## so in as many words -- and under a PARALLEL projection every view ray is the
## same direction, so a sky shader can only ever produce one flat colour however
## far the camera is tipped. A curtain that lived only in the sky would be a
## feature nobody would ever see.
##
## So the Director's ruling, and the shape of this file:
##
##   THE AURORA ANNOUNCES ITSELF ON THE GROUND. An aurora does not merely sit in
##   the sky, it LIGHTS THE WORLD BENEATH IT -- in the reference frame the snow,
##   the trunks and the wreckage are all washed teal. So the snow shifts toward
##   the aurora's colour at the ordinary game framing, with no camera move at
##   all, and THAT is what the player notices. The curtain in the sky is the
##   payoff for the moment he does look up.
##
## Tell on the ground, payoff in the sky -- the same structure the weather system
## is built with, and it is what makes 惊喜地瞥见 possible at all: he looks up
## BECAUSE the snow went green.
##
## ---------------------------------------------------------------------------
## HOW THE CAST REACHES THE PICTURE, AND WHY IT CANNOT BREAK ANYTHING
## ---------------------------------------------------------------------------
## Through `LightingDirector.set_world_light_overlay()`, which composes onto the
## channel SUNRISE's amber already uses:
##
##   the world's LIT cel band is multiplied by a luminance-normalised colour.
##
## Normalised means it is a pure HUE ROTATION -- it cannot brighten the snow, it
## cannot darken it, and it therefore cannot push anything past the glow's 0.95
## threshold, which is the "no bloom on the snow" restraint written twice already
## for the snowfall and the interior. It reaches the LIT band only, so the shade
## band stays exactly the palette colour it was chosen as (Art Bible section 4.1)
## and the two-band discipline is untouched. Engine trap 7 is not in play: no cel
## shader was edited, and nothing new is written into ALBEDO.
##
## The character takes a share of the same rotation on his ambient fill. He is
## the one stock PBR material in the game and the world's cel shaders read
## nothing from a light but its shadow term, so a cast that greened the snow and
## left him alone would move half the picture -- `LightingPreset`'s header is the
## long version of that hazard.
##
## ---------------------------------------------------------------------------
## SUBSCRIBE FOR THE MOMENTS, POLL FOR THE STATE
## ---------------------------------------------------------------------------
## The same split `WeatherSystem` and `CrowFlock` both had to learn:
##
##   `aurora.began` / `aurora.faded` fire once, on the crossings, and carry where
##     to look. A sound, a line, a camera cue.
##   `strength()`, `phase()`, `bearing_degrees()`, `elevation_degrees()` and
##     `look_direction()` are continuous and correct on every frame of every
##     ramp, and require nobody to have been listening earlier.
##
## `look_direction()` is THE SEAM FOR THE LOOK-UP. Nothing in this file moves a
## camera and nothing in it references one: when the crow-startle lean lands
## under the Art Bible rule 1 exception, an upward cue subscribes to
## `aurora.began` and aims at the vector this publishes. Note what the lean will
## have to do that the crow close-up does not -- see `look_direction()`.

const SERVICE := &"aurora"
const DEFINITIONS_DIRECTORY := "res://data/aurora"

const PHASE_CLEAR := &"clear"
const PHASE_WAITING := &"waiting"
const PHASE_RISE := &"rise"
const PHASE_HOLD := &"hold"
const PHASE_FALL := &"fall"

const EVENT_BEGAN := &"aurora.began"
const EVENT_FADED := &"aurora.faded"

## Spelled out rather than preloaded off WorldClock, the same way MusicDirector,
## NightExposure and WeatherSystem spell them out. Deleting the clock has to
## leave this file compiling.
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"
const EVENT_RUN_FINISHED := &"clock.run_finished"

## Off, and no aurora is ever drawn. What a lighting pass or a capture of
## something else flips rather than deleting the node.
@export var enabled := true

@export var definitions_directory := DEFINITIONS_DIRECTORY

## Deterministic when non-zero, which is what a capture and a test both need. In
## the game it is left at zero and seeded from the clock, so two runs are not the
## same week.
@export var random_seed := 0

## How long a night is taken to be when the clock cannot say -- a bare test, or a
## scene with no WorldClock. Day 1's night, so the fallback is a real number from
## the schedule rather than a round one.
@export var fallback_night_seconds := 300.0

## How far into the night the wait for clear weather is abandoned, as a fraction
## of the night. Past this there is not enough night left for the whole arc, and
## an aurora cut off by sunrise is worse than one that never came.
@export var give_up_fraction := 0.62

## HOW MUCH THE CAST BREATHES, and how slowly.
##
## The curtain in the sky breathes on its own, per band, inside the shader. This
## is the shared swell underneath all three of them, and it is also what the
## ground rides -- so the snow's colour drifts rather than sitting at a constant
## teal, which is the difference between light from a living sky and a filter.
##
## THE TWO PERIODS ARE IN THE GOLDEN RATIO SQUARED, AND THAT IS THE WHOLE OF
## "IT NEVER REPEATS".
##
## 0.097129 / 0.0371 = 2.618034 = phi + 1, whose continued fraction is all ones
## and is therefore the hardest number in mathematics to approximate with a
## fraction. Two sines at that ratio have no common period at all, and no NEAR
## period either until far past any session -- which is what
## `test_the_breath_has_no_period_a_session_could_contain` searches for and fails
## to find.
##
## The first pass shipped 0.0413 / 0.1069, a ratio of 2.5884, and that test found
## it repeating to within a fiftieth of its own range every 121.5 seconds. Two
## minutes is well inside the time a player stands and watches, so it would have
## read as a loop. The ratio is not decoration.
##
## The two weights are near-equal for the same reason: with one term dominant, a
## mismatch in the quiet one is cheap and the figure gets close to repeating on
## the loud one's period alone. They also sum to exactly 0.5, so the breath spans
## precisely [1 - depth, 1] and the clamp below never has to act.
@export var breath_depth := 0.22
@export var breath_slow_hz := 0.0371
@export var breath_fast_hz := 0.097129

## HOW FAR THE PUSHED TINT MUST MOVE BEFORE THE WORLD IS REPAINTED.
##
## `LightingDirector._write()` walks every cel material in the game to restamp
## them, which is the right cost for a crossfade that runs eight seconds twice a
## day and the wrong one for an aurora that holds for two minutes. The breath is
## slow, so an epsilon here turns sixty repaints a second into a handful -- and
## during the hold, when the swell is near its turning point, into none at all.
##
## Small enough to be invisible: 1/255 is 0.0039, and this is a third of it.
@export var tint_epsilon := 0.0013

var _definitions: Dictionary = {}
var _order: Array[StringName] = []

var _phase: StringName = PHASE_CLEAR
var _showing: AuroraDefinition = null
var _elapsed := 0.0
var _hold_seconds := 0.0
var _envelope := 0.0
var _glow := 0.0
var _breath_clock := 0.0

## The night's own bookkeeping: the draw, when it is due, and when to give up.
var _armed: AuroraDefinition = null
var _due_in := 0.0
var _give_up_in := 0.0
var _shown_this_run := false

## What was drawn for this showing, published for the look-up seam.
var _bearing_degrees := 0.0

var _bus = null
var _lighting = null
var _weather = null
var _clock = null
var _subscribed := false
var _pushed := Color.WHITE
var _pushed_strength := -1.0
var _rng := RandomNumberGenerator.new()


# --- lifecycle ----------------------------------------------------------------


## Armed here, attached on the first frame -- NOT here. `LightingDirector` is a
## sibling in `scenes/main.tscn` and a node's `_ready()` runs before its later
## siblings', so resolving the services now would find some of them unregistered.
## `WeatherSystem`, `SnowAccumulation` and `WindSystem` all wait for the same
## reason.
func _ready() -> void:
	if _definitions.is_empty():
		load_from_directory(definitions_directory)
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


func set_weather_system(value) -> void:
	_weather = value


func set_world_clock(value) -> void:
	_clock = value


func has_event_bus() -> bool:
	return _bus != null


## Resolves whatever it was not given, starts listening, and asks the clock
## whether it is ALREADY night.
##
## The question is not redundant with the subscription, and `CrowFlock` and
## `WeatherSystem` each paid for learning that: a system that only subscribes
## never learns the phase it was born into and would sit inert until the first
## transition -- up to a whole phase away, looking exactly like a design choice.
func attach() -> void:
	if is_inside_tree():
		if _bus == null:
			_bus = get_node_or_null("/root/EventBus")
		if _clock == null:
			_clock = get_node_or_null("/root/WorldClock")
		var registry := _registry()
		if registry != null:
			registry.register(SERVICE, self)
			if _lighting == null:
				_lighting = registry.get_service(&"lighting")
			if _weather == null:
				_weather = registry.get_service(&"weather")
	_rng.seed = random_seed if random_seed != 0 else int(Time.get_ticks_usec())
	ask_the_clock()
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.subscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_bus.subscribe(EVENT_RUN_FINISHED, _on_run_finished)
	_subscribed = true


func detach() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.unsubscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_bus.unsubscribe(EVENT_RUN_FINISHED, _on_run_finished)
	_subscribed = false


## The half of the night wiring a subscription cannot do. See `attach()`.
func ask_the_clock() -> void:
	if _clock == null or not _clock.has_method("is_running"):
		return
	if not _clock.is_running() or not bool(_clock.is_night()):
		return
	# Whatever is left of a night already under way, rather than the whole of it:
	# a system woken halfway through the dark should not plan as though the dark
	# had just begun.
	plan_night(int(_clock.current_day()), _night_remaining())


# --- the catalogue ------------------------------------------------------------


## Scans a directory BY TYPE, so adding an aurora is dropping one `.tres` in and
## there is no list of ids anywhere in `src/` -- binding rule 4, the same shape
## `WeatherSystem.load_events_from_directory()` uses.
func load_from_directory(directory_path := DEFINITIONS_DIRECTORY) -> int:
	_definitions.clear()
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
		if resource is AuroraDefinition and (resource as AuroraDefinition).id != &"":
			var definition := resource as AuroraDefinition
			_definitions[definition.id] = definition
			_order.append(definition.id)
	return _order.size()


func load_definitions(definitions: Array) -> void:
	_definitions.clear()
	_order.clear()
	for definition in definitions:
		if definition is AuroraDefinition and (definition as AuroraDefinition).id != &"":
			_definitions[(definition as AuroraDefinition).id] = definition
			_order.append((definition as AuroraDefinition).id)


func definition_ids() -> Array[StringName]:
	return _order.duplicate()


func definition(id: StringName) -> AuroraDefinition:
	return _definitions.get(id, null)


# --- the state a consumer samples ---------------------------------------------


func phase() -> StringName:
	return _phase


func is_showing() -> bool:
	return _phase == PHASE_RISE or _phase == PHASE_HOLD or _phase == PHASE_FALL


func showing() -> AuroraDefinition:
	return _showing


func showing_id() -> StringName:
	return _showing.id if _showing != null else &""


## HOW MUCH AURORA THERE IS, 0 .. 1. The envelope alone -- smoothstepped up over
## `rise_seconds`, held at 1, smoothstepped back down over `fall_seconds`. This
## is the number a subscriber should weigh a cue against.
func strength() -> float:
	return _envelope


## ...and the same thing with the slow breath folded in, which is what the sky
## and the ground actually ride. Separate from `strength()` because they answer
## different questions: "how far through the showing is it" is not "how bright is
## it this second", and a cue that used the second would flicker.
func glow() -> float:
	return _glow


## Whether the night was drawn and the curtain is merely not up yet. The honest
## answer to "is anything going to happen tonight", which no event can give.
func is_armed() -> bool:
	return _phase == PHASE_WAITING


func seconds_until_start() -> float:
	return maxf(_due_in, 0.0) if _phase == PHASE_WAITING else -1.0


func has_shown_this_run() -> bool:
	return _shown_this_run


# --- the seam for the look-up -------------------------------------------------


## Which way the curtain hangs, as a world compass bearing in degrees measured
## from -Z toward +X -- the convention `CameraRig.yaw_degrees` uses. Drawn per
## showing from the definition's range, so a cue must READ this rather than
## assume a constant.
func bearing_degrees() -> float:
	return _bearing_degrees


## How far up the middle of it sits, in degrees of elevation. Between the
## definition's hem and its crown, which is where the mass of the curtain is.
func elevation_degrees() -> float:
	if _showing == null:
		return 0.0
	return lerpf(_showing.base_elevation_degrees, _showing.top_elevation_degrees, 0.45)


## THE SEAM. A unit world vector pointing at the middle of the curtain -- what a
## camera lean aims along.
##
## Nothing here moves a camera and nothing here references one. When the
## crow-startle lean lands under the Art Bible rule 1 exception -- brief, not
## seizing control, leaning rather than cutting, returning exactly -- an upward
## cue subscribes to `aurora.began` and aims at this.
##
## ONE THING THE LEAN WILL HAVE TO DO THAT THE CROW CLOSE-UP DOES NOT, and it is
## a finding rather than a preference: **it must blend to PERSPECTIVE.** Under
## the shipped parallel projection every view ray is identical, so the sky is one
## flat colour at any pitch and there is literally nothing up there to see. The
## rule 1 ruling already permits the blend for exactly this reason
## (正交投影下向上仰视没有透视收敛) and attaches conditions 3 and 4 to it; for the
## aurora it is not an enhancement, it is the difference between a curtain and a
## coloured rectangle.
func look_direction() -> Vector3:
	var bearing := deg_to_rad(_bearing_degrees)
	var elevation := deg_to_rad(elevation_degrees())
	var flat := cos(elevation)
	return Vector3(sin(bearing) * flat, sin(elevation), -cos(bearing) * flat)


# --- the night ----------------------------------------------------------------


# EventBus calls back with exactly one argument, always -- even when the payload
# is null. A handler declaring none is a runtime error at dispatch time, not a
# parse error, so the day number is named even where it is only forwarded.
func _on_night_started(payload) -> void:
	plan_night(int(payload), _night_remaining())


func _on_day_started(_payload) -> void:
	_armed = null
	_begin_fall()


func _on_run_finished(_payload) -> void:
	_armed = null
	_shown_this_run = false
	clear_now()


## How long this night has left, from the clock if it will say and from the
## fallback otherwise.
func _night_remaining() -> float:
	if _clock == null:
		return fallback_night_seconds
	if not (_clock.has_method("phase_duration") and _clock.has_method("phase_elapsed")):
		return fallback_night_seconds
	return maxf(float(_clock.phase_duration()) - float(_clock.phase_elapsed()), 0.0)


## THE DRAW. Returns the aurora armed for tonight, or null.
##
## Public and taking the night's length as an argument so the whole rarity policy
## can be exercised without a clock, a tree or a night -- which is the only way to
## test something that is supposed to happen in one run out of two.
func plan_night(day: int, night_seconds: float) -> AuroraDefinition:
	_armed = null
	_due_in = 0.0
	_give_up_in = 0.0
	if not enabled or is_showing():
		return null
	var wanted := _preset_for_night(day)
	var length := night_seconds if night_seconds > 0.0 else fallback_night_seconds
	for id in _order:
		var candidate: AuroraDefinition = _definitions[id]
		if candidate.once_per_run and _shown_this_run:
			continue
		if not candidate.allows_night(wanted):
			continue
		# The whole arc has to fit inside what is left of the night, at the
		# shortest hold it could draw. An aurora the sunrise interrupts is worse
		# than one that never came.
		if candidate.total_seconds(candidate.hold_seconds.x) > length:
			continue
		if _rng.randf() >= clampf(candidate.chance_per_night, 0.0, 1.0):
			continue
		_armed = candidate
		var window := Vector2(
			clampf(candidate.start_window.x, 0.0, 1.0),
			clampf(candidate.start_window.y, 0.0, 1.0)
		)
		_due_in = length * _rng.randf_range(minf(window.x, window.y), maxf(window.x, window.y))
		_give_up_in = length * clampf(give_up_fraction, 0.0, 1.0)
		_phase = PHASE_WAITING
		return _armed
	return null


## Which look the day schedule names for this night. Read through the clock's own
## published accessor rather than by loading the schedule directory a second
## time, which is what `WeatherSystem._sky_preset_id()` does for the same fact.
func _preset_for_night(day: int) -> StringName:
	if _clock != null and _clock.has_method("schedule_for_day"):
		var schedule = _clock.schedule_for_day(day)
		if schedule != null:
			return schedule.night_lighting_preset
	if _clock != null and _clock.has_method("current_schedule"):
		var current = _clock.current_schedule()
		if current != null:
			return current.night_lighting_preset
	return &""


## Whether the sky is free of weather right now. Polled rather than subscribed --
## `WeatherEventDefinition`'s header is emphatic about which of the two answers
## "how bad is it now" -- and duck-typed, so a scene with no weather node in it is
## a clear sky rather than a crash.
func weather_is_clear() -> bool:
	if _weather == null or not _weather.has_method("phase"):
		return true
	return StringName(_weather.phase()) == &"clear"


# --- the arc ------------------------------------------------------------------


## Brings one on now, skipping the draw and the wait. What a capture uses, and
## the only door that does not go through the rarity policy. Returns false for an
## unknown id, and for one asked for while another is showing.
func begin(id: StringName) -> bool:
	var found: AuroraDefinition = _definitions.get(id, null)
	if found == null or is_showing():
		return false
	_begin(found)
	return true


## Ends whatever is showing at once, handing the sky and the ground back. What
## the end of a run uses, and what a test uses between two sweeps.
func clear_now() -> void:
	_showing = null
	_phase = PHASE_CLEAR
	_elapsed = 0.0
	_envelope = 0.0
	_glow = 0.0
	_drive()


func advance(delta: float) -> void:
	if not enabled or not is_finite(delta) or delta <= 0.0:
		return
	# The breath runs on its own clock rather than on the showing's, so it does
	# not restart from the same phase every time -- which is most of why two
	# showings do not look like the same animation played twice.
	_breath_clock += delta
	match _phase:
		PHASE_CLEAR:
			pass
		PHASE_WAITING:
			_tick_wait(delta)
		_:
			_tick_arc(delta)
	_drive()


func _tick_wait(delta: float) -> void:
	_due_in -= delta
	_give_up_in -= delta
	if _give_up_in <= 0.0:
		# The night got away. Silent: nothing was promised to anybody, and a
		# push_warning here would fire from any test that runs a whole night.
		_armed = null
		_phase = PHASE_CLEAR
		return
	if _due_in > 0.0:
		return
	if _armed != null and _armed.requires_clear_weather and not weather_is_clear():
		# Wait for it to pass rather than cancelling. The sky is the game's
		# forecast UI and a curtain painted over a tell would lie about what is
		# coming; but a front that blows through in ninety seconds should not cost
		# the night.
		return
	var opening := _armed
	_armed = null
	if opening != null:
		_begin(opening)


## The overshoot is CARRIED ACROSS every boundary, the same way
## `WeatherSystem._tick_arc()` carries it. A phase that reset the clock to zero
## would swallow however much of the frame was left over -- invisible at 60 Hz
## and a real stall under a long step, which is exactly what a headless capture
## or a test that advances in whole seconds does.
func _tick_arc(delta: float) -> void:
	_elapsed += delta
	match _phase:
		PHASE_RISE:
			if _elapsed >= maxf(_showing.rise_seconds, 0.0):
				_phase = PHASE_HOLD
				_elapsed = maxf(_elapsed - maxf(_showing.rise_seconds, 0.0), 0.0)
		PHASE_HOLD:
			# A weather arriving takes the sky back. Not an interruption to be
			# apologised for: cloud coming in is what actually ends an aurora, and
			# the fade is the same length as any other.
			var over := _elapsed - _hold_seconds
			if _elapsed >= _hold_seconds or (_showing.requires_clear_weather and not weather_is_clear()):
				_begin_fall()
				if over > 0.0:
					_elapsed += over
		PHASE_FALL:
			if _elapsed >= maxf(_showing.fall_seconds, 0.01):
				_finish()


func _begin(definition: AuroraDefinition) -> void:
	_showing = definition
	_phase = PHASE_RISE
	_elapsed = 0.0
	_envelope = 0.0
	_glow = 0.0
	_hold_seconds = _rng.randf_range(
		minf(definition.hold_seconds.x, definition.hold_seconds.y),
		maxf(definition.hold_seconds.x, definition.hold_seconds.y)
	)
	_bearing_degrees = _rng.randf_range(
		minf(definition.bearing_degrees.x, definition.bearing_degrees.y),
		maxf(definition.bearing_degrees.x, definition.bearing_degrees.y)
	)
	_shown_this_run = true
	_push_curtain()
	_drive()
	_publish(EVENT_BEGAN, {
		"seconds": definition.total_seconds(_hold_seconds),
		"rise_seconds": definition.rise_seconds,
	})


func _begin_fall() -> void:
	if _phase != PHASE_RISE and _phase != PHASE_HOLD:
		return
	# From wherever the envelope actually is, not from 1.0: an aurora cut short in
	# its rise must go down from the height it had reached, or the frame brightens
	# on the frame it was told to stop.
	_phase = PHASE_FALL
	_elapsed = (1.0 - _envelope) * maxf(_showing.fall_seconds, 0.01)


func _finish() -> void:
	var finished := _showing
	_showing = null
	_phase = PHASE_CLEAR
	_elapsed = 0.0
	_envelope = 0.0
	_glow = 0.0
	_drive()
	if finished != null:
		_publish(EVENT_FADED, {"id": finished.id}, finished)


# --- driving ------------------------------------------------------------------


## THE ONE PLACE ANYTHING IS APPLIED. Everything above only moves the clock.
func _drive() -> void:
	_envelope = _envelope_now()
	_glow = _envelope * _breath()
	_push_ground()
	_push_strength()


## The envelope, smoothstepped at both ends. Smoothstep rather than a straight
## ramp because its derivative is zero where it meets both the flat and the hold:
## a linear rise has a corner at the top, and at this exposure a corner in a
## whole-frame hue shift is visible as a click.
func _envelope_now() -> float:
	match _phase:
		PHASE_RISE:
			return smoothstep(0.0, 1.0, clampf(_elapsed / maxf(_showing.rise_seconds, 0.01), 0.0, 1.0))
		PHASE_HOLD:
			return 1.0
		PHASE_FALL:
			return 1.0 - smoothstep(0.0, 1.0, clampf(_elapsed / maxf(_showing.fall_seconds, 0.01), 0.0, 1.0))
		_:
			return 0.0


## The slow swell, as a pure function of the breath clock so it can be asserted
## without waiting minutes for it. Two sines whose periods are in an irrational
## ratio, so the figure has no period a session could contain.
func breath_at(seconds: float) -> float:
	var a := sin(seconds * TAU * breath_slow_hz)
	var b := sin(seconds * TAU * breath_fast_hz + 1.7)
	return clampf(1.0 - breath_depth * (0.5 - 0.28 * a - 0.22 * b), 0.0, 1.0)


func _breath() -> float:
	return breath_at(_breath_clock)


## The ground, and the character with it. Pushed only when the composed tint has
## actually moved -- see `tint_epsilon`, and note that this is what makes a
## two-minute hold cost nothing.
func _push_ground() -> void:
	if _lighting == null or not _lighting.has_method("set_world_light_overlay"):
		return
	var colour := _showing.ground_cast_color if _showing != null else Color.WHITE
	var world := 0.0
	var fill := 0.0
	if _showing != null:
		world = clampf(_showing.ground_cast_strength, 0.0, 1.0) * _glow
		fill = world * clampf(_showing.character_fill_share, 0.0, 1.0)
	if _pushed_strength >= 0.0 and _pushed == colour \
			and absf(world - _pushed_strength) < tint_epsilon:
		return
	_pushed = colour
	_pushed_strength = world
	_lighting.set_world_light_overlay(colour, world, fill)


## The sky's overall level. Cheap -- one uniform on one material, no walk -- so
## it goes every frame and the curtain's own breathing stays smooth even while
## the ground is holding still between repaints.
func _push_strength() -> void:
	if _lighting == null or not _lighting.has_method("set_aurora_strength"):
		return
	_lighting.set_aurora_strength(_glow)


## Everything about the curtain that does not change during a showing, pushed
## once when it opens.
func _push_curtain() -> void:
	if _lighting == null or _showing == null or not _lighting.has_method("set_aurora_curtain"):
		return
	_lighting.set_aurora_curtain(_showing, _bearing_degrees)


## One payload shape for both, so a subscriber can read either without knowing
## which arrived. EventBus's contract is exactly one argument -- see
## src/core/event_bus.gd.
func _publish(event: StringName, extra: Dictionary = {}, about: AuroraDefinition = null) -> void:
	if _bus == null:
		return
	var subject := about if about != null else _showing
	var payload := {
		"id": subject.id if subject != null else &"",
		"display_name": subject.display_name if subject != null else "",
		"phase": _phase,
		"strength": _envelope,
		# THE SEAM, in the payload as well as on the accessors, so a cue that only
		# ever subscribes never has to hold a reference to this system.
		"bearing_degrees": _bearing_degrees,
		"elevation_degrees": elevation_degrees(),
		"direction": look_direction(),
	}
	for key in extra:
		payload[key] = extra[key]
	_bus.emit_event(event, payload)
