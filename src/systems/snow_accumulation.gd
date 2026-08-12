class_name SnowAccumulation
extends Node

## How much snow has settled on everything in the world that faces the sky.
##
## One number, in 0..1, read by the two cel shaders. Roof planes, branches,
## crossarms, window sills, the truck's bonnet and the baked road all move
## together because they are all reading the same scalar -- there is no
## per-object state anywhere in this feature and nothing to author.
##
## ---------------------------------------------------------------------------
## 切记突变 -- THE REQUIREMENT THIS FILE EXISTS TO MAKE IMPOSSIBLE
## ---------------------------------------------------------------------------
## The owner has asked twice, in two different contexts, that the snow must
## never pop. Not "should be tuned so that it does not pop" -- must not be able
## to. So `cover()` is never assigned from a state. It is an INTEGRAL:
##
##     cover += rate * delta
##
## and `rate` is itself slew-limited toward whatever the weather is asking for:
##
##     rate -> target_rate(), at no more than rate_slew per second
##
## Two integrators in series, and the consequences are guarantees rather than
## intentions -- tests/unit/test_snow_accumulation.gd asserts each of them:
##
##   * The COVER cannot step. Whatever happens to the weather, one frame moves
##     it by at most rate * delta, and the rate is bounded.
##   * The cover's SLOPE cannot step either. A weather event that CUTS rather
##     than fades -- an Art Bible section 4.2 hotkey, tools/capture_frame.gd
##     snapping a preset at the shutter, a Wave 3 weather system that writes its
##     output instead of easing it -- moves the target rate instantly and moves
##     nothing on screen instantly.
##   * The day rolling over is not a special case and needs no code for it. It
##     moves `_night`, which moves the target rate, which the two integrators
##     absorb exactly like everything else.
##
## A design that assigned a depth from the weather and then tuned an ease onto
## it would look identical on a good day and pop on the first frame nobody
## tested. This one has no assignment to pop from -- see settle() for the single
## exception, which happens before the first frame is drawn.
##
## ---------------------------------------------------------------------------
## THE MODEL
## ---------------------------------------------------------------------------
##     gain = snowfall / settle_seconds
##     shed = day_or_night / shed_seconds  +  wind / scour_seconds
##     rate = gain * (1 - cover)  -  shed * cover
##
## Three things worth saying about that middle line.
##
## `gain` is multiplied by (1 - cover), so a surface that is already white
## cannot catch more. That is not decoration: it puts the equilibrium at
## gain / (gain + shed), which is strictly inside 0..1 for every weather there
## is. The clamp in advance() is therefore unreachable, and the cover is smooth
## EVERYWHERE rather than smooth-except-at-saturation. Without it a blizzard
## parks the value on the clamp, and the moment it comes off the clamp is a
## corner in the curve.
##
## `shed` is proportional to the cover, which is what makes this a first-order
## filter on the weather rather than a ratchet: at every weather there is an
## equilibrium, and the cover always walks toward it, from either side, on a
## time constant of 1 / (gain + shed). That is the "缓慢" -- minutes, not
## frames, and never a destination it arrives at abruptly.
##
## Nothing here melts. It is well below freezing in this game and snow on a roof
## at -20 does not thaw in the sun; what takes it off is consolidation, sliding
## and wind. So the sun is not an input and `世界时间` reaches the snow through
## the one thing that honestly changes overnight -- how much of what fell stays.

## THE WEATHER, as this reads it. Both are HOOKS in the vocabulary TrackMask and
## Snowfall already share: 0 clear .. 1 heavy, and 0 dead still .. 1 full gale.
const SNOWFALL_SERVICE := &"snowfall"
const REGISTRY_NAME := &"snow_accumulation"

## Spelled out rather than preloaded off WorldClock, the same way
## LightingDirector and MusicDirector spell them out: systems never hold
## references to one another.
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"

## Seconds of the heaviest snowfall it would take to lay a full cover if none of
## it ever came off again. Together with shed_seconds this fixes both how deep
## the snow gets at a given weather and how long it takes to get there, so the
## two are a pair and were tuned as one.
##
## 90 s against a shed of 420 gives a time constant of 74 s in a blizzard and
## four and a half minutes in the light snow of days 1-2. Measured on the model:
## the heaviest snowfall there is takes about 170 s to lay nine tenths of its
## cover. Minutes of game time in every case, which is what 缓慢 has to mean
## against a daylight phase that is ten minutes long.
@export var settle_seconds := 90.0

## The time constant of settled snow leaving again: it consolidates, it slides
## off a pitch, it blows away. Proportional to how much of it there is, which is
## what gives every weather an equilibrium instead of a ceiling.
##
## The equilibrium cover is gain / (gain + shed), so with these two numbers and
## Snowfall's own table the seven days run roughly:
##
##     PALE DAY   0.12 snowfall -> 0.36 by day, 0.48 at night
##     DEEP NIGHT 0.28          -> 0.57        0.69
##     NIGHTFALL  0.35          -> 0.62        0.73
##     WHITEOUT   1.00          -> 0.82        0.89
##
## which is a world that visibly buries itself across the week and still moves
## every single phase, rather than one that pins at full on day 2 and stops.
##
## Day 1's night is 300 s against a night-time time constant of 362, so the
## cover crosses a little over half the way from its daylight value to its
## night one before dawn turns it around. It is never still and never arrives.
@export var shed_seconds := 420.0

## Wind strips an exposed surface as well as filling a footprint in -- the same
## 风大 TrackMask decays prints with, arriving here through the same hook. At
## rest this term is exactly zero and the snow sheds on shed_seconds alone.
@export var scour_seconds := 120.0

## How much less settled snow sheds at night. Colder, no sun on the pitch, no
## thaw-freeze cycle: more of what fell stays. This is the whole of `世界时间`
## in this file, and it reaches the snow through the RATE, never through the
## depth -- which is why a day rollover needs no code here at all.
@export var night_shed_factor := 0.6

## The ceiling on how fast the rate itself may change, per second. This is the
## second integrator, and it is the reason a weather CUT cannot even put a
## crease in the curve.
##
## The rate's whole plausible range is about 0.025 per second wide, so at 0.004
## it takes six seconds to cross all of it -- imperceptible beside a cover that
## takes minutes to move, and enough that no input, however abrupt, can put a
## corner in what is drawn.
@export var rate_slew := 0.004

## 0..1. Never assigned outside settle(); see the header.
var _cover := 0.0
var _rate := 0.0
var _snowfall := 0.0
var _wind := 0.0
var _night := false
var _settled := false
var _overridden := false

var _snow_sky = null
var _bus = null
var _subscribed := false


func _ready() -> void:
	var registry := _registry()
	if registry != null:
		registry.register(REGISTRY_NAME, self)
	_attach_bus()


func _exit_tree() -> void:
	_detach_bus()
	var registry := _registry()
	if registry != null and registry.get_service(REGISTRY_NAME) == self:
		registry.unregister(REGISTRY_NAME)


## Trap 3: an autoload is a node under /root, never an Engine singleton. And an
## absolute path asked for from outside the tree is an engine error rather than
## a null, which is why every caller here goes through this.
func _registry() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/ServiceRegistry")


# --- what is on the world right now -----------------------------------------

## 0 bare .. 1 as covered as this weather gets. The one number the shaders read.
func cover() -> float:
	return _cover


## How fast it is moving, in cover per second. Signed: negative while the snow
## is coming off again. Exposed because "is this thing continuous" is a question
## about the derivative, and a test that can only see the value has to infer it.
func rate() -> float:
	return _rate


## Where the cover is headed at the weather currently set, and the number the
## table in shed_seconds' comment is computed from. Never assigned to _cover --
## it exists so a test can state the equilibrium and so a tuner can read it.
func equilibrium() -> float:
	var gain := _gain()
	var shed := _shed()
	if gain + shed <= 0.0:
		return _cover
	return gain / (gain + shed)


func is_night() -> bool:
	return _night


func snowfall_rate() -> float:
	return _snowfall


func wind_strength() -> float:
	return _wind


# --- the hooks --------------------------------------------------------------

## THE WEATHER HOOKS, in the vocabulary TrackMask and Snowfall already use.
##
## Calling either one takes this off the Snowfall it otherwise reads, for good:
## two things easing the same number in opposite directions is worse than
## either. src/systems/weather_system.gd is Wave 3 and this is where it connects.
func set_snowfall_rate(rate_0_to_1: float) -> void:
	_overridden = true
	_snowfall = clampf(rate_0_to_1, 0.0, 1.0)


func set_wind_strength(strength: float) -> void:
	_overridden = true
	_wind = clampf(strength, 0.0, 1.0)


## Injected by a test, or by whoever wires the scene. Resolved from the
## ServiceRegistry otherwise, the same way Snowfall.set_lighting() works.
func set_snowfall_source(source) -> void:
	_snow_sky = source


func set_event_bus(bus) -> void:
	_detach_bus()
	_bus = bus
	_attach_bus()


# --- the model --------------------------------------------------------------

## Snow arriving, per second, before anything is subtracted.
func _gain() -> float:
	if settle_seconds <= 0.0:
		return 0.0
	return _snowfall / settle_seconds


## Snow leaving, per second, PER UNIT OF COVER -- so the loss term is
## _shed() * cover and a bare surface loses nothing.
func _shed() -> float:
	var shed := 0.0
	if shed_seconds > 0.0:
		shed = (night_shed_factor if _night else 1.0) / shed_seconds
	if scour_seconds > 0.0:
		shed += _wind / scour_seconds
	return shed


## The speed the weather is asking the cover to move at. The weather sets THIS,
## never the cover -- see the header.
func target_rate() -> float:
	return _gain() * (1.0 - _cover) - _shed() * _cover


## One frame. Public and carrying all the logic so the whole model can be driven
## without a SceneTree, which is how the continuity tests step it.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	_read_weather()
	var step := maxf(rate_slew, 0.0) * delta
	var wanted := target_rate()
	# Slew-limited, not eased: an ease has no bound on how fast it can move on
	# the first frame of a change, and a bound is what the guarantee needs.
	_rate = clampf(wanted, _rate - step, _rate + step)
	# The clamp is unreachable by construction -- see the header on why the gain
	# carries (1 - cover). It is here because "unreachable" should be defended
	# rather than trusted, not because anything is expected to hit it.
	_cover = clampf(_cover + _rate * delta, 0.0, 1.0)


## THE ONE ASSIGNMENT, and it happens before the first frame is drawn.
##
## Same call and same reasoning as Snowfall.settle(): the run opens on the
## weather day 1 actually has, rather than on a bare world that whitens over the
## first three minutes of play. A world assembling itself in front of the player
## reads as a bug, and it is the only reading of this feature that would.
##
## Fired from the first _process rather than from _ready(), because Snowfall is
## a sibling further down scenes/main.tscn and a node's _ready() runs before its
## later siblings' do -- settling in _ready() would read a sky that has not
## resolved its own rate yet and start from zero anyway. RunBoot arms itself the
## same way and for the same reason.
func settle() -> void:
	_settled = true
	_read_weather()
	_cover = equilibrium()
	_rate = 0.0


func _process(delta: float) -> void:
	if not _settled:
		settle()
		return
	advance(delta)


## The sky, if a weather system has not taken the wheel. Guarded on the method
## rather than the type so a stand-in, or a Snowfall that has not registered
## itself yet, is a quiet no-op instead of a crash on the first frame.
func _read_weather() -> void:
	if _overridden:
		return
	if _snow_sky == null:
		var registry := _registry()
		if registry != null:
			_snow_sky = registry.get_service(SNOWFALL_SERVICE)
	if _snow_sky == null:
		return
	if _snow_sky.has_method("snowfall_rate"):
		_snowfall = clampf(_snow_sky.snowfall_rate(), 0.0, 1.0)
	if _snow_sky.has_method("wind_strength"):
		_wind = clampf(_snow_sky.wind_strength(), 0.0, 1.0)


# --- the clock --------------------------------------------------------------

func _attach_bus() -> void:
	if _bus == null and is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.subscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_subscribed = true


func _detach_bus() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.unsubscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_subscribed = false


# EventBus always calls back with exactly one argument, so the day number is
# named even where it is dropped.
func _on_day_started(_payload) -> void:
	_night = false


func _on_night_started(_payload) -> void:
	_night = true
