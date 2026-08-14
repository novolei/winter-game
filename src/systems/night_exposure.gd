extends Node

## Autoload "NightExposure". GDD section 3, one rule and nothing else:
##
##   `NIGHTFALL = GO HOME` 是字面意义的死线。天黑后仍在野外，体温下降速率翻倍。
##
## Nightfall is a literal deadline. After dark, still out in the open, core
## temperature falls twice as fast. That single multiplier is what makes the
## seven-day structure a game rather than a countdown: it is why the daylight
## budget is worth planning around, why the walk home is a decision, and why
## GDD section 4's shrinking days get more frightening rather than merely
## shorter.
##
## Until this file existed, the nights were exactly as dangerous as the days,
## and core temperature had been tuned assuming they were not -- so every warmth
## figure the fuel economy was balanced against was optimistic by a factor of two
## after sundown.
##
## ---------------------------------------------------------------------------
## WHY IT IS ITS OWN FILE
## ---------------------------------------------------------------------------
## The mechanism is already built and this only joins two ends of it up:
## WorldClock publishes clock.night_started / clock.day_started on the EventBus,
## and SurvivalSystem takes modifiers by source. Nothing new is invented here and
## there is deliberately no second path.
##
## It is not in WorldClock because a clock that knows how cold it is outside is
## a clock with two jobs, and its 11 tests build it bare. It is not in
## SurvivalSystem because that file owns no rules -- every rate and every
## interlock is a .tres, and a hardcoded 2.0 in there would be the first
## exception. It is not in GameState because GameState owns the attempt
## boundary, and this is a thing that happens throughout the attempt.
##
## ---------------------------------------------------------------------------
## "OUTDOORS" -- THE INTERIOR SEAM
## ---------------------------------------------------------------------------
## GDD section 3 says 天黑后仍在野外: after dark AND outdoors. InteriorReveal
## publishes the player's threshold crossings through the EventBus, so the
## shelter half has one source and one honest default:
##
##     set_sheltered(false)   <- the default. Everyone is outdoors, always.
##
## `interior.entered` sets it true and `interior.exited` sets it false. Their
## payload is deliberately irrelevant here: InteriorReveal has already filtered
## the crossing to its registered occupant, and making this system interpret a
## building or scene node would couple the rule to the world that publishes it.
##
## Note what shelter is NOT: it is not warmth. Being indoors merely declines the
## doubling; it does not slow the ordinary drain, because GDD section 3 does not
## say it does. Warmth comes from the stove, on the recovery channel, and a house
## that quietly halved the drain as well would be a second uninvented mechanic.

const SOURCE := &"night"

const TARGET_STAT := &"core_temperature"

## Spelled out rather than preloaded off WorldClock, the same way MusicDirector
## spells them out. Systems never hold references to one another; deleting the
## clock has to leave this file compiling, and a preload would make the string
## constants a hard dependency on the one system this must not require.
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"
const EVENT_RUN_FINISHED := &"clock.run_finished"
const EVENT_RUN_RESET := &"game.run_reset"
const EVENT_INTERIOR_ENTERED := &"interior.entered"
const EVENT_INTERIOR_EXITED := &"interior.exited"

## GDD section 3's 翻倍 -- literally "doubled". Exported so it can be tuned
## against a played night rather than a derived one, but it is a quoted number
## from the design document and moving it is a design decision, not a knob.
@export var night_multiplier := 2.0

var _bus = null
var _survival = null
var _night := false
var _sheltered := false
var _subscribed := false

# --- lifecycle --------------------------------------------------------------

## Armed here, attached on the first frame -- NOT here.
##
## Autoloads are added to /root in the order project.godot lists them and each
## one's _ready() runs as it is added, so an autoload declared BELOW this line
## does not exist yet when this line runs. Subscribing from _ready() would make
## this file care where its own entry sits in a list nobody thinks about, and
## getting it wrong would leave the nights silently mild -- the exact failure it
## exists to fix. By the first frame every autoload is present.
func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	set_process(false)
	attach()

func _exit_tree() -> void:
	detach()

# --- wiring -----------------------------------------------------------------

func set_event_bus(bus) -> void:
	if _subscribed:
		detach()
	_bus = bus

func set_survival_system(system) -> void:
	_survival = system
	_apply()

func has_event_bus() -> bool:
	return _bus != null

func has_survival_system() -> bool:
	return _survival != null

## Resolves whatever it was not given and starts listening. Idempotent: calling
## it twice leaves exactly one subscription, because EventBus.subscribe() is
## itself idempotent and the guard below keeps detach() honest about it.
##
## get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is a
## node under /root and never enters the engine's singleton registry (briefing
## trap 3). Written the plausible-looking way, this file would hear nothing for
## ever and the nights would be as mild as the days, with no HUD to contradict
## it and no test able to see it.
func attach() -> void:
	if is_inside_tree():
		if _bus == null:
			_bus = get_node_or_null("/root/EventBus")
		if _survival == null:
			_survival = get_node_or_null("/root/SurvivalSystem")
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_bus.subscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.subscribe(EVENT_RUN_FINISHED, _on_run_finished)
	_bus.subscribe(EVENT_RUN_RESET, _on_run_reset)
	_bus.subscribe(EVENT_INTERIOR_ENTERED, _on_interior_entered)
	_bus.subscribe(EVENT_INTERIOR_EXITED, _on_interior_exited)
	_subscribed = true

func detach() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_bus.unsubscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.unsubscribe(EVENT_RUN_FINISHED, _on_run_finished)
	_bus.unsubscribe(EVENT_RUN_RESET, _on_run_reset)
	_bus.unsubscribe(EVENT_INTERIOR_ENTERED, _on_interior_entered)
	_bus.unsubscribe(EVENT_INTERIOR_EXITED, _on_interior_exited)
	_subscribed = false

# --- the rule ---------------------------------------------------------------

## The shelter seam. See the header: false is the shipped default and the only
## value anything sets today.
func set_sheltered(value: bool) -> void:
	if value == _sheltered:
		return
	_sheltered = value
	_apply()

func is_sheltered() -> bool:
	return _sheltered

func is_night() -> bool:
	return _night

## Whether the doubling is currently on the body. The one readout worth having:
## "is it night" and "is the cold doubled" are different questions the moment
## anything can be sheltered.
func is_doubling() -> bool:
	return _night and not _sheltered

# EventBus calls back with exactly one argument, always -- even when the payload
# is null. A handler declaring none is a runtime error at dispatch time, not a
# parse error, so the unused day number is named and kept.
func _on_night_started(_payload) -> void:
	_night = true
	_apply()

func _on_day_started(_payload) -> void:
	_night = false
	_apply()

func _on_interior_entered(_payload) -> void:
	set_sheltered(true)

func _on_interior_exited(_payload) -> void:
	set_sheltered(false)

func _on_run_finished(_payload) -> void:
	_night = false
	_sheltered = false
	_apply()


func _on_run_reset(_payload) -> void:
	_night = false
	_sheltered = false
	_apply()

## Remove first, ALWAYS, then push if it should be there.
##
## Not an optimisation and not tidiness: re-pushing while the condition already
## held would stack a second copy of the same rule every time anything nudged
## it, and a MULTIPLY stack compounds -- 2x becomes 4x becomes 8x, looks correct
## for a few seconds, and then kills the player with no trace of why. Removing
## by source first makes that shape unrepresentable.
##
## It also means this is safe against SurvivalSystem.start(), which clears every
## stack: the clock restarts with the model, re-emits clock.day_started, and this
## reasserts from a known state rather than from a cached belief.
func _apply() -> void:
	if _survival == null:
		return
	_survival.remove_source(SOURCE)
	if not is_doubling():
		return
	# A bare target means the drain channel (SurvivalSystem canonicalises it).
	# The drain is what doubles: pushing a negative onto recovery instead would
	# let "you tire faster when dehydrated" scale a negative and warm the player
	# up, which is the sign error the two-stack split exists to forbid.
	_survival.push_modifier(TARGET_STAT, SOURCE, Modifier.Operation.MULTIPLY, night_multiplier)
