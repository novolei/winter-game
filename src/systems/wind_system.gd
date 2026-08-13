extends Node

## THE SOURCE. Everything else in this project that takes a wind was built to be
## driven and nothing produced one.
##
## `TrackMask`, `Snowfall` and its three layers, `SnowAccumulation`, `BreathFog`
## and `SnowLoad` all carry a `set_wind()` or a `set_wind_strength()`, all of
## them tested, every one of them inert. This file is the other end.
##
## ---------------------------------------------------------------------------
## THE ONE THING THAT DECIDES WHETHER THIS WORKS
## ---------------------------------------------------------------------------
## Wind is invisible. It is only ever seen in what it moves -- so a wind system
## that computes a perfect vector and drives nothing visible is a wind system the
## player cannot feel, which was the complaint.
##
## And the half of that which is easy to get wrong: **a CONSTANT wind reads as NO
## wind.** A steady sideways force stops being perceived within a few seconds,
## because perception is of change. What a player calls "windy" is gusts, lulls,
## and a squall crossing the valley and passing. So the gust structure is the
## design and the strength is a consequence: `WindProfile.base_strength` is 0.06,
## and the wind is nonetheless legible, because it moves.
##
## `tests/unit/test_wind.gd::test_the_strength_is_never_constant` is that claim
## as a property. It was written first and it failed first, against a producer
## that returned a perfectly reasonable constant.
##
## ---------------------------------------------------------------------------
## THE MODEL, AND WHY IT IS PURE FUNCTIONS OF TIME
## ---------------------------------------------------------------------------
##     strength(t) = base + gust_depth * gust(t) + squall_gain * squall(t)
##     heading(t)  = prevailing + wander(t) + veer * (gust(t) - 0.5) * 2
##
##   * `gust(t)` is three sine octaves at incommensurate periods, raised to
##     `gust_sharpness` so the lulls are long and the gusts brief. A single sine
##     reads as a machine; the exponent is what makes an arrival an event.
##   * `squall(t)` is episodic: time is cut into slots of `squall_interval_seconds`
##     and each slot's squall starts at a hashed offset inside it. Deterministic,
##     so it is a pure function of t and can be swept in a test, and unpredictable,
##     so it is not a metronome.
##   * the heading VEERS with the gust. A gust that arrives from the same quarter
##     as the lull it interrupts reads as a volume knob rather than as weather,
##     and the correlation costs one term.
##
## Everything above is static and takes `t`, so the whole model is testable with
## no tree, no camera and no frame -- and a capture tool can sample the future.
##
## ---------------------------------------------------------------------------
## WHAT THE CONSUMERS DISAGREED ABOUT
## ---------------------------------------------------------------------------
## They were written months apart against a producer that did not exist, and they
## do not agree. Reconciled here, and each one is recorded rather than papered
## over:
##
##   1. TWO VOCABULARIES. `set_wind(Vector3)` -- SnowfallLayer, BreathFog,
##      SnowLoad -- and `set_wind_strength(float)`, 0..1 -- Snowfall, TrackMask,
##      SnowAccumulation. Both are driven; neither is converted into the other,
##      because they are genuinely different questions.
##   2. THE VECTOR IS NAMED WRONG, CONSISTENTLY. The parameter is `velocity` in
##      all three files and the producer-side helper is `Snowfall.wind_velocity()`
##      -- and every one of the three adds it straight into a
##      `ParticleProcessMaterial.gravity`, which is an ACCELERATION in m/s^2. The
##      unit is agreed; only the word is wrong. Kept, because renaming three
##      shipped hooks to fix a word is a bigger change than saying so here.
##   3. ONLY ONE OF THEM CARRIED A MAGNITUDE. `Snowfall.gale_wind`, at
##      |(1.6, 0, 0.5)| = 1.6763. `WindProfile.gale_metres` is that figure
##      exactly, and a test pins the two together.
##   4. THE SNOWFALL'S DIRECTION WAS A CONSTANT. `gale_wind` is a vector, so the
##      snow could only ever blow one way. The heading is written into it every
##      frame -- magnitude preserved -- which is the only way a varying direction
##      reaches the three snow layers without editing their director.
##   5. ONE CONSUMER'S HOOK HAS A SIDE EFFECT NOBODY WOULD EXPECT.
##      `SnowAccumulation.set_wind_strength()` raises a permanent `_overridden`
##      flag that ALSO stops it reading the SNOWFALL RATE off the sky -- one flag,
##      two facts, and only one of them is the wind's to take. See
##      `_is_fed_by_the_sky()`.
##
## ---------------------------------------------------------------------------
## AUDIO IS NOT HERE, AND THAT IS WHY THE EVENTS ARE
## ---------------------------------------------------------------------------
## Ambient wind sound belongs to Wave 3's audio task. Nothing here plays
## anything. What is here is the seven events an audio system needs so that it
## can be a SUBSCRIBER rather than a rewrite: the onset and the end of a gust, of
## a lull, and of a squall, plus a change of quarter.
##
## The lull is not decoration. GDD section 7 makes still air its own weather
## (寒流's tell is 空气变得极静) and section 9's whole scare is the world going
## quiet -- an audio system needs the onset of the silence as much as the onset
## of the noise. GDD section 8 hangs the bear's nose on the heading, and section
## 6 blows a beacon out when the wind passes a threshold: both read the same
## events.
##
## A continuous value -- an ambient bed's amplitude -- should be POLLED, not
## subscribed: `ServiceRegistry.get_service(&"wind").strength()`. Publishing a
## float sixty times a second is not an event.

const SERVICE := &"wind"
const PROFILE_PATH := "res://data/weather/wind_valley.tres"
const MAP_PATH := "res://data/weather/wind_map.tres"
const LIGHTING_SERVICE := &"lighting"

## The group `Snowfall` publishes its layers in. Spelled out rather than read off
## `SnowfallLayer.GROUP`, so this file holds no reference to that one: deleting
## the snowfall has to leave this compiling. Skipped in the sweep because those
## layers already have a driver, and two writers to one property is the defect
## this whole file exists to avoid making six of.
const SNOWFALL_LAYER_GROUP := &"snowfall_layer"

const EVENT_GUST_STARTED := &"wind.gust_started"
const EVENT_GUST_ENDED := &"wind.gust_ended"
const EVENT_LULL_STARTED := &"wind.lull_started"
const EVENT_LULL_ENDED := &"wind.lull_ended"
const EVENT_SQUALL_STARTED := &"wind.squall_started"
const EVENT_SQUALL_ENDED := &"wind.squall_ended"
const EVENT_DIRECTION_SHIFTED := &"wind.direction_shifted"

## Which wind blows under which sky. Five profiles, mapped onto the six lighting
## presets, because a whiteout is not a pale day with more snow -- see
## `src/definitions/wind_map.gd` for the whole of that argument and for why
## `deep_night` gets the calmest wind in the game.
@export var map_path := MAP_PATH

## The wind used when there is no map and no lighting to ask. Also what
## `--profile` on the capture tool loads.
@export var profile_path := PROFILE_PATH

## How long the wind takes to become a different wind when the sky changes, as a
## time constant. Matched to `Snowfall.rate_response_seconds` and to the lighting
## crossfade, because all three are showing the SAME weather and they must not
## disagree about when it happened.
##
## The crossfade is on the OUTPUT, not on the parameters: both profiles are pure
## functions of the same `t`, so the outgoing wind goes on gusting its own way
## while the incoming one takes over. Interpolating the parameters instead would
## have produced a third wind nobody authored, for six seconds, every dusk.
@export var profile_response_seconds := 6.0

## Multiplies the clock the model is sampled against. For tools only --
## `tools/capture_gust.gd` needs a squall inside a few seconds of capture, and
## waiting seventy-six of them for one is not a capture, it is an outage.
@export var time_scale := 1.0

## How long a consumer that has its own driver may go on disagreeing with us
## before we stop believing in its driver and push it directly. See
## `_is_fed_by_the_sky()`.
@export var passthrough_grace_seconds := 0.75

## How far a consumer's own reading may sit from ours and still count as fed. One
## frame of lag through the sky is at most about 0.013 at this model's slew, so
## this is generous by a factor of four and still far under the base strength.
@export var passthrough_tolerance := 0.05

## How often the tree is re-swept for consumers, in seconds. Consumers are found
## by the hooks they publish rather than by path or by type, so a system that
## grows a `set_wind()` next wave is driven with no edit here -- but a sweep every
## frame would be paying for that convenience sixty times a second.
@export var rescan_seconds := 2.0

var _profile: WindProfile = null
## The wind we are crossfading OUT of, and how far through. See
## `profile_response_seconds`.
var _previous: WindProfile = null
var _blend := 1.0
var _map: WindMap = null
var _lighting = null
## The look the current profile came from, so a change is noticed once.
var _seen_preset: StringName = &""
## True once a weather system has taken the wheel with `set_profile()`.
var _overridden := false
var _bus = null
var _elapsed := 0.0
var _strength := 0.0
var _heading := 0.0
var _gale_multiplier := 1.0

var _consumers: Array = []
var _since_scan := 0.0
## instance id -> seconds a sky-fed consumer has disagreed with us.
var _starved: Dictionary = {}

## Latches, so an event fires on a CROSSING rather than on every frame the
## strength happens to be over a line.
var _gusting := false
var _lulling := false
var _squalling := false
var _reported_heading := 0.0
var _settled := false


# --- the model, all of it pure ----------------------------------------------

## Three sine octaves at incommensurate periods, folded to 0 .. 1 and then raised
## to `sharpness`.
##
## The ratios 1 : 2.7 : 6.3 are irrational enough that the sum has no audible
## repeat over a session, and the weights 0.55 / 0.30 / 0.15 keep the slowest one
## in charge -- the fast octaves are the texture on a gust, not the gust.
##
## The EXPONENT is the part that matters. At 1.0 this is a sine and the wind is
## above its own midpoint half the time, which reads as a machine breathing. At
## 2.2 the lulls are long and the gusts are brief, and an arrival is an event.
static func gust_field(t: float, period: float, sharpness: float) -> float:
	var w := TAU / maxf(period, 0.001)
	var raw := 0.55 * sin(w * t) \
		+ 0.30 * sin(w * 2.7 * t + 1.7) \
		+ 0.15 * sin(w * 6.3 * t + 4.1)
	return pow(clampf(0.5 + 0.5 * raw, 0.0, 1.0), maxf(sharpness, 0.01))


## The slow swing of the heading, -1 .. 1, AND IT HAS MEMORY.
##
## ---------------------------------------------------------------------------
## THE COMPLAINT WAS 风的方向貌似比较固定, AND TAKEN LITERALLY IT IS FALSE
## ---------------------------------------------------------------------------
## Logged once a second through a blizzard the instantaneous heading covers a 91
## degree range and moves at up to 12 degrees a second. Nothing about it is fixed.
##
## What was fixed is its MEAN. This was two sines, both zero-mean, so every
## deviation from `prevailing_degrees` came back inside one period -- 47 s on the
## valley profile. And nine of the ten shipped profiles use the same
## `prevailing_degrees`. So anything a player integrates over more than a few
## seconds -- which is what "the wind comes from over there" is -- WAS a single
## constant for the whole game, and he was right about what he saw even though
## every instantaneous number said otherwise.
##
## The briefing's own rule names the defect exactly: a cue earns belief by having
## mass and arriving late, and a pure zero-mean function of `t` has neither. It
## cannot be late for anything, because it has no history to be late from.
##
## ---------------------------------------------------------------------------
## MEMORY WITHOUT STATE
## ---------------------------------------------------------------------------
## An Ornstein-Uhlenbeck drift is the obvious model and it would have cost this
## file the one property that makes the whole wind testable: `heading_at()` is a
## PURE FUNCTION OF t, so four minutes of weather sweep in a millisecond and a
## capture tool can photograph a squall instead of waiting for one. A stateful
## integrator answers only for the t it has already walked to.
##
## So: the same trick `squall_field()` already uses. Time is cut into slots, each
## slot draws an independent target from an integer hash, and the heading eases
## between consecutive targets. Memory comes from each target being an
## exponentially weighted sum of the last `WANDER_MEMORY` draws -- an AR(1)
## process evaluated in closed form. Correlated across minutes, unpredictable,
## bounded, and still answerable for any t in any order.
##
## The slot stream is offset off `squall_field()`'s, or the wind would swing to
## the same quarter every time a squall arrived -- one hash driving two facts.
static func wander_field(t: float, period: float) -> float:
	var span := maxf(period, 0.001)
	var slot := floori(t / span)
	# Smoothstepped rather than lerped, so the heading is C1 across a slot
	# boundary. It is read straight into particle directions and a corner in it
	# would be a visible flick in the snow, the spindrift and the breath at once.
	var ease := smoothstep(0.0, 1.0, t / span - float(slot))
	return lerpf(wander_target(slot), wander_target(slot + 1), ease)


## How many slots of history a heading carries, and how much of the previous slot
## survives into the next.
##
## 0.72 over 8 slots gives a correlation time of about 47 / (1 - 0.72) = 168 s on
## the valley profile: the wind settles into a quarter for two or three minutes at
## a time, which is long enough to be a fact about the afternoon rather than a
## wobble. Eight slots is where the weights have decayed to 0.07 and adding more
## changes nothing.
const WANDER_MEMORY := 8
const WANDER_RECALL := 0.72

## How much of the available swing an average slot uses. Under 1 because the
## weighted mean of several independent draws is far tamer than any one of them,
## and a walk that never reached its own bound would be a wander with the
## amplitude quietly divided by three. The clamp is not a safety net: saturating
## is the wind SETTLING into a quarter and holding there, which is the behaviour
## this whole change exists to produce.
const WANDER_REACH := 0.42

## The slot stream this walks on, moved off the squall's. Same hash, different
## place in it -- see `wander_field()`.
const WANDER_STREAM := 0x2E1B7


## Where the heading is drifting toward in slot `n`, -1 .. 1. Pure, and
## answerable for any slot in any order, which is what keeps `heading_at()` pure.
static func wander_target(slot: int) -> float:
	var total := 0.0
	var weight := 0.0
	var recall := 1.0
	for back in WANDER_MEMORY:
		total += recall * (slot_offset(slot - back + WANDER_STREAM) * 2.0 - 1.0)
		weight += recall
		recall *= WANDER_RECALL
	if weight <= 0.0:
		return 0.0
	return clampf(total / (weight * WANDER_REACH), -1.0, 1.0)


## The squall: a front that crosses the valley and passes.
##
## Time is cut into slots of `interval`, and slot n's squall begins at a hashed
## offset inside it. That makes this a PURE FUNCTION OF t -- so a test can sweep
## four minutes of weather in a millisecond and a capture tool can find the next
## squall instead of waiting for it -- while still being unpredictable to a
## player, which a metronome would not be.
##
## The envelope is smoothstepped at both ends, so the strength this feeds is C1
## and nothing downstream can pop. Attack is shorter than release on purpose: a
## squall hits and then lets go, and reversing that reads as a fade-in.
static func squall_field(
	t: float, interval: float, jitter: float, duration: float,
	attack: float, release: float
) -> float:
	if interval <= 0.0 or duration <= 0.0:
		return 0.0
	var strongest := 0.0
	var slot := floori(t / interval)
	# The previous slot as well, in case its squall is still passing. With the
	# shipped profiles it never is; the cost is one more evaluation and the
	# alternative is a bound that silently breaks when somebody retunes.
	for n in [slot - 1, slot]:
		var start := float(n) * interval + slot_offset(n) * interval * clampf(jitter, 0.0, 1.0)
		strongest = maxf(strongest, envelope((t - start) / duration, attack, release))
	return strongest


## A stable 0 .. 1 for an integer slot. An integer hash rather than a seeded RNG
## because it has to be answerable for any slot in any order -- a pure function of
## t cannot carry a stream position.
static func slot_offset(slot: int) -> float:
	var h := (slot * 374761393 + 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10007.0


## Attack, hold, release across u in 0 .. 1. Zero outside.
static func envelope(u: float, attack: float, release: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	var rise := clampf(attack, 0.001, 0.98)
	var fall := clampf(release, 0.001, 0.98)
	if rise + fall > 1.0:
		var squeeze := 1.0 / (rise + fall)
		rise *= squeeze
		fall *= squeeze
	if u < rise:
		return smoothstep(0.0, 1.0, u / rise)
	if u > 1.0 - fall:
		return smoothstep(0.0, 1.0, (1.0 - u) / fall)
	return 1.0


static func strength_at(profile: WindProfile, t: float) -> float:
	if profile == null:
		return 0.0
	var gust := gust_field(t, profile.gust_seconds, profile.gust_sharpness)
	var squall := squall_field(
		t,
		profile.squall_interval_seconds,
		profile.squall_interval_jitter,
		profile.squall_seconds,
		profile.squall_attack,
		profile.squall_release
	)
	return clampf(
		profile.base_strength + profile.gust_depth * gust + profile.squall_gain * squall,
		0.0,
		1.0
	)


## Degrees about +Y, 0 along +X. The direction the wind BLOWS TO -- see
## `WindProfile.prevailing_degrees` for why it is stated that way round.
static func heading_at(profile: WindProfile, t: float) -> float:
	if profile == null:
		return 0.0
	var gust := gust_field(t, profile.gust_seconds, profile.gust_sharpness)
	return profile.prevailing_degrees \
		+ profile.wander_degrees * wander_field(t, profile.wander_seconds) \
		+ profile.gust_veer_degrees * (gust * 2.0 - 1.0)


static func heading_vector(degrees: float) -> Vector3:
	var radians := deg_to_rad(degrees)
	return Vector3(cos(radians), 0.0, sin(radians))


# --- what the world can ask --------------------------------------------------

func strength() -> float:
	return _strength


## The wind now blowing, which is the incoming profile once a crossfade is over.
func active_profile() -> WindProfile:
	return _profile


## 1.0 when the wind is fully whichever profile the sky asks for.
func profile_blend() -> float:
	return _blend


func heading_degrees() -> float:
	return _heading


func direction() -> Vector3:
	return heading_vector(_heading)


## The wind in the vocabulary `set_wind()` takes: an acceleration, in m/s^2,
## despite every one of those hooks calling its parameter a velocity. See the
## header, point 2.
func velocity() -> Vector3:
	if _profile == null:
		return Vector3.ZERO
	return direction() * (_profile.gale_metres * _gale_multiplier) * _strength


func profile() -> WindProfile:
	return _profile


func set_map(map) -> void:
	_map = map
	_seen_preset = &""


func set_lighting(lighting) -> void:
	_lighting = lighting
	_seen_preset = &""


func elapsed() -> float:
	return _elapsed


# --- the hooks a weather system connects to ---------------------------------

## THE WEATHER HOOK. A different profile is a different wind, and adding one is
## adding a `.tres` -- binding rule 4. `src/systems/weather_system.gd` is the
## rest of Wave 3 and this is where it connects.
##
## The clock is NOT reset. A squall does not restart because the forecast
## changed, and resetting would put every profile change on the same phase of the
## same gust, which is the one way to make weather look scripted.
func set_profile(profile_resource) -> void:
	_overridden = true
	_adopt(profile_resource, true)


## Takes a new wind without claiming ownership -- what the sky change uses.
## `immediate` skips the crossfade, which only the first frame of a run wants.
func _adopt(profile_resource, immediate: bool) -> void:
	if profile_resource == null or profile_resource == _profile:
		return
	if _profile != null and not immediate:
		_previous = _profile
		_blend = 0.0
	else:
		_previous = null
		_blend = 1.0
	_profile = profile_resource
	if immediate:
		_settle()


## The wind the sky is asking for, or nothing if nobody can say. Resolved through
## the ServiceRegistry rather than by path, the same way `Snowfall.set_lighting()`
## does, and guarded on the METHOD rather than the type so a stand-in or a
## director that has not registered yet is a quiet no-op.
func _wanted_profile() -> WindProfile:
	if _overridden or _map == null:
		return null
	if _lighting == null:
		var registry := _registry()
		if registry != null:
			_lighting = registry.get_service(LIGHTING_SERVICE)
	if _lighting == null or not _lighting.has_method("active_preset"):
		return null
	var look = _lighting.active_preset()
	if look == null:
		return null
	if look.id == _seen_preset:
		return null
	_seen_preset = look.id
	return _map.profile_for(look.id)


## `WeatherEventDefinition.wind_speed_multiplier`, which already exists in the
## data and had nowhere to land. Scales what a strength of 1.0 means in metres
## rather than scaling the strength: an event that makes the wind BITE harder is
## a different thing from one that makes it blow more often, and the profile
## already owns the second.
func set_gale_multiplier(multiplier: float) -> void:
	_gale_multiplier = maxf(multiplier, 0.0)


func gale_multiplier() -> float:
	return _gale_multiplier


func set_event_bus(bus) -> void:
	_bus = bus


func has_event_bus() -> bool:
	return _bus != null


# --- lifecycle ---------------------------------------------------------------

func _ready() -> void:
	var registry := _registry()
	if registry != null:
		registry.register(SERVICE, self)
	if _map == null:
		_map = load(map_path)
	if _profile == null:
		# The sky is asked on the first frame rather than here: LightingDirector is
		# a sibling and a node's _ready() runs before its later siblings' do, so
		# resolving the look now would read a director that has not chosen one.
		# SnowAccumulation arms itself the same way and for the same reason.
		_profile = _map.default_profile() if _map != null else load(profile_path)
	if _bus == null and is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
	_settle()


func _exit_tree() -> void:
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


## The first frame of a run is already the weather, and the latches start where
## the weather already is -- so a run that opens mid-gust does not announce a
## gust starting that has been running since before the world existed.
func _settle() -> void:
	if _profile == null:
		return
	_previous = null
	_blend = 1.0
	_strength = strength_at(_profile, _elapsed)
	_heading = heading_at(_profile, _elapsed)
	_reported_heading = _heading
	_gusting = _strength >= _profile.gust_threshold
	_lulling = _strength <= _profile.lull_threshold
	_squalling = _squall_now() > 0.02
	_settled = true


## One step of the model. Public and carrying all of it, so the whole thing can
## be driven with no SceneTree -- which is how every test above drives it.
func advance(delta: float) -> void:
	if _profile == null:
		_profile = load(profile_path)
		if _profile == null:
			return
	if not _settled:
		_settle()
	_elapsed += maxf(delta, 0.0)
	# The sky first, so a look that changed this frame is already being crossfaded
	# toward rather than starting a frame late.
	var wanted := _wanted_profile()
	if wanted != null:
		_adopt(wanted, false)
	_advance_blend(delta)
	_strength = blended(strength_at(_previous, _elapsed), strength_at(_profile, _elapsed), _blend)
	_heading = blended(heading_at(_previous, _elapsed), heading_at(_profile, _elapsed), _blend)
	_report()


## Exponential ease, frame-rate independent: what is fixed is the fraction of the
## gap closed per second, not per frame. The same form `Snowfall` and `CameraRig`
## use, so the sky, the snow and the wind arrive together.
func _advance_blend(delta: float) -> void:
	if _previous == null or _blend >= 1.0:
		_blend = 1.0
		return
	if profile_response_seconds <= 0.0 or delta <= 0.0:
		_blend = 1.0
	else:
		_blend = clampf(_blend + (1.0 - _blend) * (1.0 - exp(-delta / profile_response_seconds)), 0.0, 1.0)
	# RELEASED at 0.995 rather than at 1.0, which an exponential never reaches.
	# The snap that costs is bounded by 0.005 times the gap between the two winds
	# -- under 0.005 even from the still night to the gale, against a model whose
	# ordinary frame-to-frame movement is 0.007. Invisible, and it is what stops a
	# run evaluating a profile it stopped using half a minute ago.
	if _blend > 0.995:
		_blend = 1.0
		_previous = null


## Between the outgoing wind and the incoming one. Static because it is the one
## place a crossfade could put a step in the picture, and a test should be able to
## say so without a tree.
static func blended(before: float, after: float, blend: float) -> float:
	if blend >= 1.0:
		return after
	return lerpf(before, after, clampf(blend, 0.0, 1.0))


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	advance(delta * maxf(time_scale, 0.0))
	_drive_everything(delta)


# --- telling everybody -------------------------------------------------------

## One consumer, one frame. Public and taking the consumer as an argument so the
## whole of what a frame does is testable against a stand-in, with no tree.
##
## Duck-typed on the hooks rather than on the types, which is this project's
## standing convention and here also a guarantee: a system that grows a
## `set_wind()` in a later wave is driven with no edit to this file.
func drive(consumer, delta: float) -> void:
	if consumer == null or not is_instance_valid(consumer):
		return

	if consumer.has_method("set_wind"):
		consumer.set_wind(velocity())

	# A consumer that republishes the wind onward as a vector needs the HEADING,
	# not just the strength -- and `Snowfall` is the one that does, for the three
	# snow layers. Its `gale_wind` is a direction times a magnitude; the magnitude
	# is the figure this system's own vocabulary was taken from, so only the
	# direction is written and the authored tuning is preserved exactly.
	#
	# This is the one place this file writes another system's property rather than
	# calling its hook, and it is because that system has no hook for a direction:
	# a scalar strength cannot carry one, and a snow layer whose slant never
	# changes is the constant this whole file exists not to be.
	if consumer.has_method("wind_velocity") and _profile != null:
		consumer.set(&"gale_wind", direction() * (_profile.gale_metres * _gale_multiplier))

	if not consumer.has_method("set_wind_strength"):
		return
	if _is_fed_by_the_sky(consumer) and _sky_is_feeding(consumer, delta):
		return
	consumer.set_wind_strength(_strength)


## True for a consumer that takes its weather from the sky and therefore already
## has the wind by another road.
##
## THE ONE RECONCILIATION THIS FILE MAKES, and it is worth the paragraph.
## `SnowAccumulation.set_wind_strength()` sets `_overridden`, and that flag does
## not only mean "somebody owns the wind" -- it means "stop reading the sky", so
## calling the wind hook silently freezes the SNOWFALL RATE as well. Two facts
## behind one flag, and only one of them is ours to take.
##
## It already polls `Snowfall.wind_strength()` every frame, so driving the sky
## drives the scour, with no override and no second writer. What the sky is
## handed here is exactly what its own hook would have been handed.
##
## Recognised by the injection hook it publishes rather than by its class, so
## this file holds no reference to it: a node that can be given a snowfall source
## is a node the sky feeds.
func _is_fed_by_the_sky(consumer) -> bool:
	return consumer.has_method("set_snowfall_source") and consumer.has_method("wind_strength")


## ...and this is what makes leaving it alone safe rather than merely hopeful. If
## the pass-through is ever cut -- somebody else takes the override, the sky is
## deleted, the registry never resolves -- the consumer stops matching us, and
## after `passthrough_grace_seconds` we stop believing in its driver and push it.
##
## The grace is needed because the sky is genuinely one frame behind: the
## accumulation reads the sky in its own `_process`, and node order decides which
## of them runs first. A tolerance alone would fire on that lag every frame.
func _sky_is_feeding(consumer, delta: float) -> bool:
	var id: int = consumer.get_instance_id()
	if absf(consumer.wind_strength() - _strength) <= passthrough_tolerance:
		_starved.erase(id)
		return true
	var starved := float(_starved.get(id, 0.0)) + maxf(delta, 0.0)
	_starved[id] = starved
	return starved < passthrough_grace_seconds


## Every node in the tree that publishes a wind hook, refreshed on a timer.
func _drive_everything(delta: float) -> void:
	if not is_inside_tree():
		return
	_since_scan += delta
	if _consumers.is_empty() or _since_scan >= rescan_seconds:
		_rescan()
	for consumer in _consumers:
		if is_instance_valid(consumer):
			drive(consumer, delta)


func _rescan() -> void:
	var tree := get_tree()
	refresh_consumers(null if tree == null else tree.get_root())


## Public and taking the root, so a test can sweep a tree it built by hand -- see
## `test_the_sweep_reaches_a_cue_parented_under_the_system_itself`, which is the
## regression test for the `_collect` note below.
func refresh_consumers(root: Node) -> void:
	_since_scan = 0.0
	_consumers.clear()
	if root != null:
		_collect(root)


## RECURSION IS UNCONDITIONAL, and the two `if`s below decide only whether a node
## is COLLECTED. Written the obvious way first -- `continue` on the skips -- and
## that skipped the whole subtree with it, so the two cues parented under this
## very node were never found and never driven. The wind ran perfectly and
## nothing moved, which is precisely the failure this task exists to fix, arrived
## at from the other direction.
func _collect(node: Node) -> void:
	for child in node.get_children():
		var collect := child != self
		# Snow layers are driven by their own director, which pushes them the
		# whole weather on the same frame. A second writer here would give them
		# this frame's wind against last frame's framing.
		if child.is_in_group(SNOWFALL_LAYER_GROUP):
			collect = false
		if collect and (child.has_method("set_wind") or child.has_method("set_wind_strength")):
			_consumers.append(child)
		_collect(child)


func consumer_count() -> int:
	return _consumers.size()


# --- what an audio system subscribes to --------------------------------------

func _squall_now() -> float:
	if _profile == null:
		return 0.0
	return squall_field(
		_elapsed,
		_profile.squall_interval_seconds,
		_profile.squall_interval_jitter,
		_profile.squall_seconds,
		_profile.squall_attack,
		_profile.squall_release
	)


## Crossings, not levels. Every latch below has hysteresis on it, because a
## strength hovering on a threshold would otherwise publish a storm of events --
## and for an audio system a chattering onset is worse than no onset at all.
func _report() -> void:
	if _bus == null or _profile == null:
		return

	if not _gusting and _strength >= _profile.gust_threshold:
		_gusting = true
		_publish(EVENT_GUST_STARTED)
	elif _gusting and _strength <= _profile.gust_threshold - _profile.gust_hysteresis:
		_gusting = false
		_publish(EVENT_GUST_ENDED)

	if not _lulling and _strength <= _profile.lull_threshold:
		_lulling = true
		_publish(EVENT_LULL_STARTED)
	elif _lulling and _strength >= _profile.lull_threshold + _profile.lull_hysteresis:
		_lulling = false
		_publish(EVENT_LULL_ENDED)

	var squall := _squall_now()
	if not _squalling and squall > 0.10:
		_squalling = true
		_publish(EVENT_SQUALL_STARTED)
	elif _squalling and squall <= 0.02:
		_squalling = false
		_publish(EVENT_SQUALL_ENDED)

	# The heading is reported in STEPS rather than continuously: what a consumer
	# downwind of it wants to know is that the quarter has changed, and a degree
	# and a half is not a change of quarter.
	if absf(_heading - _reported_heading) >= _profile.direction_report_degrees:
		var previous := _reported_heading
		_reported_heading = _heading
		_publish(EVENT_DIRECTION_SHIFTED, {"from_degrees": previous})


## One payload shape for all seven, so a subscriber can read any of them without
## knowing which arrived. EventBus's contract is exactly one argument -- see
## `src/core/event_bus.gd`.
func _publish(event: StringName, extra: Dictionary = {}) -> void:
	var payload := {
		"strength": _strength,
		"heading_degrees": _heading,
		"direction": direction(),
		"squall": _squall_now(),
		"at": _elapsed,
	}
	for key in extra:
		payload[key] = extra[key]
	_bus.emit_event(event, payload)
