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
## `settle()` is the single exception and it happens before the first frame is
## drawn. Authoring the state the world OPENS in is not a pop: it is the world
## already being what it is when the player arrives.
##
## ---------------------------------------------------------------------------
## THE MODEL
## ---------------------------------------------------------------------------
##     gain = snowfall / settle_seconds
##     shed = creep + wind / scour_seconds + thaw / melt_seconds
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
## ---------------------------------------------------------------------------
## WHAT TAKES SNOW OFF A ROOF, which this file got wrong once
## ---------------------------------------------------------------------------
## The version that shipped in b9e1490 carried this paragraph:
##
##     "Nothing here melts. It is well below freezing in this game and snow on a
##      roof at -20 does not thaw in the sun."
##
## ...and then ran a 420 s decay unconditionally, which is a MELT RATE charged
## to a world that is never above freezing. The prose was right and the
## arithmetic did not match it. What that cost, measured in the shipped build
## rather than reasoned about:
##
##   * day 1 opened at cover 0.359 and held it, unmoving, for the whole 600 s of
##     daylight -- because settle() put the cover exactly at the equilibrium and
##     the equilibrium of a constant weather is constant
##   * at 0.359 the cel shader lays NO snow on the farmhouse roof (a 33.7 degree
##     pitch), none on a 45 degree pitch, and 7% of a flat top
##   * every daylight phase un-buried the world its night had buried: the cover
##     ran 0.36 -> 0.66 -> 0.39 -> 0.66 -> 0.62 -> 0.40 across the week, a
##     sawtooth rather than a winter
##
## The owner played it and reported no snow on the roofs, the car roof or the
## power poles. Every test in this file was green, and the capture harness
## showed accumulation working perfectly -- because the harness set its own
## weather and had never once photographed day 1.
##
## So the loss is now gated on the three things that actually remove snow, and
## the normal case in this game is the one where none of them is happening:
##
##   COLD AND STILL -> IT STAYS.   creep_seconds is a numerical tail longer
##                                 than a day: over one 15-minute game day more
##                                 than 99% of the blanket remains.
##   STRONG WIND    -> SCOUR.      ordinary valley air is below the exposure
##                                 threshold; only storm wind contributes.
##   ABOVE FREEZING -> MELT.       melt_seconds, on the thaw hook, which is 0
##                                 today and belongs to Wave 3.
##
## `creep_seconds` is not mathematically zero only because a shed that reaches
## zero puts the equilibrium exactly on the 1.0 clamp. Its roughly 28-hour time
## constant is not an authored visible melt or slide.

## THE WEATHER, as this reads it. Both are HOOKS in the vocabulary TrackMask and
## Snowfall already share: 0 clear .. 1 heavy, and 0 dead still .. 1 full gale.
const SNOWFALL_SERVICE := &"snowfall"
const REGISTRY_NAME := &"snow_accumulation"

## Ordinary valley air shifts loose flakes but does not peel an established
## winter blanket off every roof, bonnet and wire. Scouring begins only above
## this exposure threshold, then ramps across the remaining 0..1 range. The
## threshold is intentionally below the shipped gale profile and above the
## opening valley's sustained 0.04..0.38 band. A brief valley squall may cross
## it weakly, but not long or hard enough to reverse day one's settling; a real
## storm still strips snow while the clear break cannot reverse the whole farm.
const WIND_SCOUR_THRESHOLD := 0.42

## Spelled out rather than preloaded off WorldClock, the same way
## LightingDirector and MusicDirector spell them out: systems never hold
## references to one another.
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"

## HOW DEEP THE WORLD IS WHEN THE PLAYER ARRIVES.
##
## GDD day 1 is not the first day of winter. There is a metre of snow on the
## ground, the valley has been under it for weeks, and the roofs are carrying
## what fell before the run began. A model that can only ramp from wherever it
## starts needs its start authored, and this is it.
##
## 0.62 IS A NUMBER ABOUT THE PICTURE, not about the weather. Flat props still
## read it through the cel shader; modelled roofs mark their old planes bare and
## grow CelPainter's `snow_mass` geometry on a deliberately later curve. That
## separation keeps the world recognisably weeks into winter without making the
## roof look nearly finished on the first frame:
##
##     cover   roof mass   flat top   45 deg pitch   truck panel
##     0.359       0%          7%          0%             0%
##     0.550       3%         74%          1%             0%
##     0.620      16%         96%          5%             1%      <- opening
##     0.800      68%        100%         61%             7%
##     0.970     100%        100%        100%            25%
##
## At 0.62 the roof carries a young visible lip with most dark slate still
## reading through it, every flat top is snowy, and the week has the whole of
## 0.62..0.97 left to bury the roof in. Lower and the props open too bare;
## mapping the roof directly from zero made it open finished, which took Art
## Bible rule 10's ridge line with it on the first frame.
@export var opening_cover := 0.62

## Seconds of the heaviest snowfall it would take to lay a full cover on a bare
## world. Together with creep_seconds this fixes both how deep the snow gets at
## a given weather and how long it takes to get there, so the two are a pair and
## were tuned as one.
##
## 240 s against the nearly-zero cold tail gives a time constant of about four
## minutes in a blizzard and about half an hour in the light snow of days 1-2.
## Measured on the model:
## the heaviest snowfall there is takes about 520 s to lay nine tenths of its
## cover, which is inside a single daylight phase and nowhere near a frame.
@export var settle_seconds := 240.0

## A numerical cold consolidation tail, not a visible gameplay loss. One global
## scalar cannot tell a steep roof slab from a flat truck bonnet or a cable, so
## charging every exposed top at the old 70-minute rate made them all lose snow
## in sync. At 100000 s, one whole 900 s game day retains more than 99% in still
## clear air, while the equilibrium remains strictly below the hard clamp.
##
@export var creep_seconds := 100000.0

## WIND STRIPS AN EXPOSED SURFACE -- the same 风大 TrackMask decays prints with,
## arriving here through the same hook. At rest this term is exactly zero and
## the snow keeps everything the creep leaves it.
##
## 900 s rather than the 120 it shipped at. Every other time constant in this
## file moved by an order of magnitude when the melt came out of the default
## case, and a scour left at 120 s would have made the wind the only thing in
## the model that mattered.
@export var scour_seconds := 900.0

## ABOVE FREEZING, OR NEAR SOMETHING BURNING: the snow melts. 300 s at a full
## thaw, so a warm spell takes a roof down about as fast as the heaviest
## snowfall built it.
##
## THIS IS THE TERM THE OLD MODEL APPLIED UNCONDITIONALLY. It is now gated on
## `thaw`, which is 0 for the whole of the game that exists today: there is no
## air temperature in this project (see src/entities/snow_load.gd, which reached
## the same conclusion and left its own air hook at zero), and inventing one
## here would mean two of them when Wave 3 brings the real one.
@export var melt_seconds := 300.0

## How much less settled snow creeps at night. Colder, no sun on the pitch, no
## thaw-freeze cycle: more of what fell stays. This is the whole of `世界时间`
## in this file, and it reaches the snow through the RATE, never through the
## depth -- which is why a day rollover needs no code here at all.
@export var night_creep_factor := 0.6

## The ceiling on how fast the rate itself may change, per second. This is the
## second integrator, and it is the reason a weather CUT cannot even put a
## crease in the curve.
##
## The rate's plausible range is now about 0.0044 per second wide in the weather
## the game actually has, so at 0.0008 it takes five and a half seconds to cross
## all of it -- imperceptible beside a cover that takes minutes to move, and
## enough that no input, however abrupt, can put a corner in what is drawn. It
## came down from 0.004 with the rest of the model: a slew ceiling ten times the
## largest rate there is bounds nothing.
@export var rate_slew := 0.0008

## 0..1. Never assigned outside settle(); see the header.
var _cover := 0.0
var _rate := 0.0
var _snowfall := 0.0
var _wind := 0.0
var _thaw := 0.0
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
## table in creep_seconds' comment is computed from. Never assigned to _cover --
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


func thaw() -> float:
	return _thaw


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


## THE THAW HOOK. 0 hard frost .. 1 above freezing, and it is the ONLY thing in
## this model that melts anything. Zero for the whole of the game that exists
## today; Wave 3's temperature owns it.
##
## Deliberately NOT read off Snowfall, and not an override: the sky knows how
## hard it is snowing and how hard it is blowing, and it has no opinion at all
## about how warm it is.
##
## Note what this cannot express. The scalar is one number for the whole world,
## so "near a heat source" -- a chimney thawing the ridge around it, a stove
## warming the roof it is under -- is a LOCAL fact and cannot live here. That
## needs per-object state, which this feature deliberately does not have, and it
## is a different feature.
func set_thaw(thaw_0_to_1: float) -> void:
	_thaw = clampf(thaw_0_to_1, 0.0, 1.0)


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
##
## Three terms: the cold tail is always tiny, wind contributes only above the
## exposure threshold, and thaw remains zero until a temperature source exists.
func _shed() -> float:
	var shed := 0.0
	if creep_seconds > 0.0:
		shed = (night_creep_factor if _night else 1.0) / creep_seconds
	if scour_seconds > 0.0:
		shed += wind_scour_exposure(_wind) / scour_seconds
	if melt_seconds > 0.0:
		shed += _thaw / melt_seconds
	return shed


## How much of the authored wind is strong enough to remove an established
## surface blanket. Public and pure so the boundary cannot regress unnoticed.
static func wind_scour_exposure(wind: float) -> float:
	var clamped := clampf(wind, 0.0, 1.0)
	if clamped <= WIND_SCOUR_THRESHOLD:
		return 0.0
	return (clamped - WIND_SCOUR_THRESHOLD) / (1.0 - WIND_SCOUR_THRESHOLD)


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
	# carries (1 - cover) and why the shed can never reach zero. It is here
	# because "unreachable" should be defended rather than trusted.
	_cover = clampf(_cover + _rate * delta, 0.0, 1.0)


## THE ONE ASSIGNMENT, and it happens before the first frame is drawn.
##
## The run opens on `opening_cover` -- the world the player walks into, which
## has had a winter in it already. NOT on the equilibrium of day 1's weather:
## the equilibrium says where the CURRENT sky is taking the snow and nothing at
## all about what fell before the run began, and day 1's sky is the lightest in
## the game. Opening there is what put the player in front of bare roofs.
##
## Fired from the first _process rather than from _ready(), because Snowfall is
## a sibling further down scenes/main.tscn and a node's _ready() runs before its
## later siblings' do -- settling in _ready() would read a sky that has not
## resolved its own rate yet. The weather read here no longer decides the depth,
## but it does decide the rate on the first frame, so the ordering still matters.
## RunBoot arms itself the same way and for the same reason.
func settle() -> void:
	_settled = true
	_read_weather()
	_cover = clampf(opening_cover, 0.0, 1.0)
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
