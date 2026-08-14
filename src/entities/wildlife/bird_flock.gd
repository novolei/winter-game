class_name BirdFlock
extends Node3D

## The birds of one species in the valley: how many, where they sit, when they
## arrive, and what makes them go. Which species, is data -- see
## `src/definitions/bird_species.gd`.
##
## ---------------------------------------------------------------------------
## THE OWNER'S ASK, IN FULL
## ---------------------------------------------------------------------------
##   乌鸦可以随机的出现，可以随机的停靠在电线杆或电线上，可以是一只或者多只，
##   但是只有白天才会有乌鸦出现，当玩家经过的时候，乌鸦可以随机朝不同天空方向
##   飞走并飞远消失。
##
## Randomly present; on the pole or the wires; one bird or several; **daylight
## only**; and when the player passes, away in different directions and gone.
##
## "Daylight only" is the crow's rule and is now `species.daylight_only`, because
## it is not every bird's: a rock dove roosts on the ledges it feeds from, is on
## the eave at dusk and still on it at dawn, and a valley whose only bird
## vanishes the moment the sun goes down is a valley that is obviously running a
## day/night switch.
##
## ---------------------------------------------------------------------------
## ASKING THE CLOCK, NOT ONLY LISTENING TO IT
## ---------------------------------------------------------------------------
## `WorldClock` publishes `clock.day_started` and `clock.night_started`, and a
## system that only subscribes to those **never learns the phase it was born
## into**. It would sit at whatever its member defaulted to until the first
## transition, which is up to a whole phase away -- so birds would either be
## missing for the whole of day one, or out all through the first night, and
## nothing would report it because both look like a tuning choice.
##
## This project has already paid for that defect once. So `attach()` does both:
## it subscribes AND it asks `is_night()` on the spot. The subscription keeps it
## right; the question makes it right to begin with.
##
## TWO FLAGS, NOT ONE, and they mean different things. `_night` is the RULE --
## "the wires must be empty" -- and is only ever set for a daylight-only species.
## `_dark` is the FACT, and is true after sunset for every species. Conflating
## them is how a field comes to mean two things, and both are asserted in both
## directions so a later tidy-up that folds them back together turns red.
##
## ---------------------------------------------------------------------------
## WHERE THE PERCHES COME FROM
## ---------------------------------------------------------------------------
## Not from here. Props declare their own -- see
## `src/entities/wildlife/perch_points.gd` -- and this asks the tree's `perches`
## group for whatever is currently on offer, every time a flock arrives. Add a
## pole and its perches come with it; move one and the birds move with it. There
## is no list of positions anywhere in this file, deliberately: the pole is
## settled onto procedural snow at `_ready()` and the wires are stretched between
## whatever the pole and the house settled at, so a written-down perch would be
## wrong before the first frame was drawn.
##
## Two flocks gather from the same group, which is what lets two species share a
## wire -- and which means two flocks that cannot see each other can hand out the
## same perch twice. At sixteen pixels, two birds in one place is a single
## wrong-shaped blob. A species that declares `avoids_occupied_perches` drops any
## perch somebody is standing on; that is deliberately NOT flock-versus-flock
## behaviour -- there is no signal, no subscription and no knowledge of another
## flock's existence; it is one bird declining to land on another, asked as a
## question about the PERCH.
##
## ---------------------------------------------------------------------------
## THE SCATTER IS THE POINT, AND IT HAS TO BE A BURST
## ---------------------------------------------------------------------------
## Two things separate a flock leaving from an object being deleted:
##
##   SPREAD    Every bird gets its own heading, drawn across `spread_degrees`
##             about the direction away from whatever startled it, with its own
##             climb. A row of birds all leaving on one bearing reads as one
##             sprite being translated.
##   STAGGER   They do not leave on the same frame. `stagger_seconds` between
##             them, ordered by how close each was to the disturbance, so it
##             ripples along the wire from the near end instead of firing at
##             once.
##
## ---------------------------------------------------------------------------
## AND THE WIND, WHICH IS THE THIRD THING THAT EMPTIES A WIRE
## ---------------------------------------------------------------------------
## `src/systems/wind_system.gd` sweeps the tree for anything publishing
## `set_wind()` / `set_wind_strength()` and pushes the weather into it. This node
## publishes both, so the flock is driven with no edit to that file, no
## subscription and no service lookup -- which is also why the wind arrives here
## and is passed DOWN to the birds rather than each bird finding it: a bird is
## built at runtime and the sweep runs on a two-second timer, so one that landed
## between sweeps would stand in a gale believing it was still.
##
## What the flock does with it, in one sentence each:
##
##   EVERY FRAME    every bird still on the wire is told the strength, and
##                  decides for itself whether to open its wings (`Bird.ride`).
##   ABOVE 0.75     the flock gives up and goes, DOWNWIND, through the same
##                  `scatter()` the man's approach uses. Not a second departure.
##   WHILE BLOWING  nothing lands. A bird does not settle on a wire in a gale,
##                  and a flock that landed into one would be flushed on the next
##                  frame -- five birds spawned and freed, over and over.
##
## A LEVEL, POLLED, NOT AN EVENT. `wind.gust_started` fires on the crossing of
## the profile's own threshold and never again as the gust builds, so a flock
## that refused the event at 0.30 would sit out the 0.83 peak behind it. The
## question a bird on a wire is answering is "is it bad NOW", and only the level
## answers that. The hysteresis below is this file's own, for the same reason
## `WindSystem._report()` has its own.
##
## ---------------------------------------------------------------------------
## AND THE EVENT NOTHING CONSUMES YET
## ---------------------------------------------------------------------------
## `wildlife.crows_scattered` is published whenever a flock goes up. Nothing
## subscribes today. It is here because birds bursting off a wire is the oldest
## warning there is, and Wave 5's threats approach the farmstead: the day a bear
## comes over the rise, the tell already exists and is already in the right
## place. One line now, a whole tell later.
##
## The event keeps its crow-shaped name because `crow_calls.gd` and
## `src/rendering/startle_shot.gd` both subscribe to it by that name, and a
## published event's name is a contract with things this file must not have to
## know about. The payload's `count` and `cause` were always the parts a listener
## reads.

const EVENT_SCATTERED := &"wildlife.crows_scattered"
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"

## Why a flock went up. Part of the payload rather than three events, because a
## listener that wants "something is out there" wants one subscription -- and
## because a listener that wants "something is out there" must be able to tell
## the wind from a bear, which is exactly what this field is for.
const CAUSE_PLAYER := &"player"
const CAUSE_NIGHTFALL := &"nightfall"
const CAUSE_GUST := &"gust"

## How near another bird has to be, by default, for a perch to count as taken.
## A perched dove is 0.30 m long and the wire spacings in `scenes/main.tscn` are
## 2.2 m to 3.0 m, so this only ever fires on two birds sent to the SAME perch
## rather than to neighbouring ones. A species may name its own.
const OCCUPIED_WITHIN_M := 0.35

## Which bird. Seeds `fewest`, `most` and `flush_radius_m`, decides what
## nightfall does, and is handed to every bird the flock hatches.
##
## A flock with none hatches plain `Bird`s with no body, which is what a test
## exercising the timeline alone wants.
@export var species: BirdSpecies = null: set = set_species

## One bird or several -- the owner's words. The upper bound is what the wires
## can carry without the farmyard reading as a rookery. Seeded from the species.
@export var fewest := 1
@export var most := 5

## How close whoever is being watched has to get. Eight metres is inside the
## tight framing stop's 10.5 m of world, so the flush happens on screen rather
## than somewhere off the edge of it. Seeded from the species.
@export var flush_radius_m := 8.0

## How long after the last bird has gone before another flock may arrive, and
## how long after arriving before they may be flushed again -- the second is what
## stops a player standing under the wire from spawning a bird a second.
@export var quiet_min_seconds := 40.0
@export var quiet_max_seconds := 110.0

## THE RETURN, after HE put them up.
##
##   白天的时候乌鸦会被玩家惊飞，飞起盘旋一段时间后乌鸦还会回到随机的一个可以落脚的地方
##
## Shorter than the ordinary quiet, and it is a different thing: an ordinary
## quiet is "no birds just now", and this is the SAME disturbance resolving. A
## flock that never came back would mean the player empties the valley on day one
## and the wires are bare for the remaining six.
##
## Twenty to thirty-six seconds, strictly inside the ordinary quiet's floor. Long
## enough that it is not a bounce -- he will usually have walked on, and the
## arrival is a thing that happens behind him rather than a thing he caused twice.
## Short enough that a single afternoon's walk past the pole and back finds the
## wire occupied again, which is what makes the valley read as recovering rather
## than as depleting.
##
## Only after a PLAYER startle. Nightfall means they are gone until morning (and
## `_night` blocks landing anyway) and a gust means they are waiting out the wind
## (and `_blowing` blocks it), so neither wants this timer.
@export var return_min_seconds := 20.0
@export var return_max_seconds := 36.0

## Where a returning flock enters from: how far out, and how high above the perch
## it is coming back to. Far enough to be off the widest framing stop when it
## appears, so birds fly INTO the picture rather than appearing in it.
@export var arrival_distance_m := 30.0
@export var arrival_height_m := 7.0

## The very first flock does not arrive on frame one. A world that is already
## populated the instant it appears reads as a set being dressed.
@export var first_arrival_seconds := 6.0

## The burst. See the header.
@export var spread_degrees := 80.0
@export var stagger_seconds := 0.14
@export var climb_min_degrees := 18.0
@export var climb_max_degrees := 45.0

## The wind at which the flock gives up, and the weaker wind at which it will
## consider landing again.
##
## MEASURED over an hour of each shipped profile rather than chosen. At 0.75 on /
## 0.62 off:
##
##   wind_calm   (flat, sunrise)  ... never. Peak strength is 0.387.
##   wind_valley (pale_day)       ... 24 times an hour -- a few an afternoon.
##   wind_rising (nightfall)      ...  9 times an hour.
##   wind_gale   (whiteout)       ... held 26 per cent of the time; no bird sits.
##
## Lower and it stops being an event: every squall in the valley profile reaches
## 0.62, so anything under about 0.72 takes essentially every flock and the man
## never gets to flush one. Higher and `wind_rising` stops reaching it at all.
@export var gust_scatter_strength := 0.75
@export var gust_release_strength := 0.62

## THE MILL, which is the beat that sells a burst.
##
## Crows do not leave on a heading. They come off the wire, wheel while they
## decide, and only then commit -- and the hesitation is the difference between a
## flock and five particles that were each given a velocity. So every bird is
## handed a turn rate and a duration, and flies an arc for that long before it
## straightens onto the bearing the fan gave it.
##
## THE SIGN IS DRAWN ONCE PER BURST, not once per bird. Birds mill together; a
## flock with three going clockwise and two anticlockwise is a collision, not a
## wheel. The MAGNITUDE is jittered per bird by `wheel_jitter`, which is what
## keeps it from reading as a rigid formation.
##
## The rate bounds are a radius decision in disguise: the arc a bird traces is
## `mill_speed / rate`, so at Bird's 5 m/s these are wheels 1.9 m to 3.8 m
## across, against 10.5 m of frame height at the tight stop. Tighter than 1.9 m
## and it is a barrel roll; wider than about 4 m and the bird leaves the frame
## before the circle closes and the wheel never reads at all.
@export var wheel_rate_min := 1.3
@export var wheel_rate_max := 2.7
@export var wheel_jitter := 0.2

## How long each bird hesitates before committing. THE "决定航向前犹豫多久" axis.
##
## Bounded above by the shot: the Art Bible's ruling gives the startle close-up
## two or three seconds, and a launch is 0.93 s of that, so a mill that ran
## longer than about 1.7 s would still be undecided when the camera has already
## gone home.
@export var wheel_seconds_min := 0.75
@export var wheel_seconds_max := 1.70

## The fan a wind-blown flock leaves on, against `spread_degrees` for a flock
## leaving something on the ground. Narrower on purpose: birds startled by a
## thing run away from the thing in every direction, and birds beaten off a wire
## all go the same way, because the wind decided and not they. The flock
## streaming off in one line IS the cue.
@export var gust_spread_degrees := 44.0

## Deterministic when non-zero, which is what a capture and a test both need. In
## the game it is left at zero and seeded from the clock, so two runs are not the
## same afternoon.
@export var random_seed := 0

## Off, and no bird ever arrives. The switch a capture or a lighting pass flips
## without having to delete the node.
@export var enabled := true

var _bus = null
var _clock = null
var _registry = null
var _watched: Node3D = null
var _birds: Array[Bird] = []
var _perches: Array = []
var _explicit_perches := false
## The RULE: the wires must be empty. Only ever set for a daylight-only species.
var _night := false
## The FACT: the sun is down. True after sunset for every species.
var _dark := false
var _quiet := 0.0
var _settled := 0.0
var _subscribed := false
var _painter: CelPainter = null
var _rng := RandomNumberGenerator.new()
var _hatched := 0
var _wind_strength := 0.0
var _wind := Vector3.ZERO
## Latched: true from the frame the wind passed `gust_scatter_strength` until it
## falls back below `gust_release_strength`.
var _blowing := false
## What emptied the wire last. Decides how long before they come back -- see
## `return_min_seconds`.
var _last_cause: StringName = CAUSE_NIGHTFALL


func _ready() -> void:
	_quiet = first_arrival_seconds
	# AFTER WHATEVER MOVES THE THINGS THE BIRDS ARE STANDING ON. `_process` runs
	# in tree order at equal priority, and `Crows` sits above `Wind` in
	# scenes/main.tscn, so a bird gripping a wire was reading the position the
	# span held LAST frame -- one frame of lag, measured at 7.9 mm of trailing
	# through a squall against the 105 mm the bug itself was worth. Sub-pixel at
	# the tight stop, and free to remove: this is a number, not a scene edit, so
	# it cannot be undone by the editor resaving `main.tscn`.
	process_priority = 10
	attach()


func _exit_tree() -> void:
	detach()


# --- wiring ------------------------------------------------------------------


## Adopt a species: take how many sit together and how close he may get.
##
## In `_init()` for the two named flocks, and at scene-load time for a flock
## whose species comes out of the `.tscn`. Either way it lands before `_ready()`,
## so `attach()` and the first arrival already see the right numbers -- and a
## test that wants one flock to differ writes over any of them afterwards,
## because nothing re-reads the species later.
func set_species(value: BirdSpecies) -> void:
	species = value
	if value == null:
		return
	fewest = value.fewest
	most = value.most
	flush_radius_m = value.flush_radius_m


func set_event_bus(bus) -> void:
	_bus = bus


func set_world_clock(clock) -> void:
	_clock = clock


func set_service_registry(registry) -> void:
	_registry = registry


## Whoever the birds are frightened of. The player in the game; anything with a
## position in a test.
func set_watched(node: Node3D) -> void:
	_watched = node


# --- the wind hooks ------------------------------------------------------------
#
# The two names `WindSystem.drive()` calls. Duck-typed there rather than wired,
# so these are the whole of the contract and renaming either silently unplugs the
# flock from the weather -- which `test_crow_gust.gd` asserts by name.
#
# NOT `set_snowfall_source`: `WindSystem._is_fed_by_the_sky()` skips any consumer
# publishing that alongside `wind_strength()`, on the grounds that the sky is
# already feeding it, and a flock caught by that rule would never be driven.


func set_wind(velocity: Vector3) -> void:
	_wind = velocity


func set_wind_strength(strength: float) -> void:
	_wind_strength = clampf(strength, 0.0, 1.0)


func wind_strength() -> float:
	return _wind_strength


## Whether the wind is currently hard enough to keep the wires empty. Public so a
## test can assert the latch rather than infer it from the birds.
func is_blowing_them_off() -> bool:
	return _blowing


## Perches, given rather than gathered. What a test uses instead of building two
## poles, and what a capture uses to put a bird exactly where the camera is
## looking.
func set_perches(perches: Array) -> void:
	_perches = perches.duplicate()
	_explicit_perches = true


## Resolves whatever it was not given, starts listening, and **asks the clock
## what time it already is**. See the header: the question is not redundant with
## the subscription, it is the half that makes the first phase correct.
##
## `get_node_or_null`, NOT `Engine.get_singleton`: a project `[autoload]` entry is
## a node under `/root` and never enters the engine's singleton registry
## (briefing trap 3).
func attach() -> void:
	if is_inside_tree():
		if _bus == null:
			_bus = get_node_or_null("/root/EventBus")
		if _clock == null:
			_clock = get_node_or_null("/root/WorldClock")
		if _registry == null:
			_registry = get_node_or_null("/root/ServiceRegistry")
	# Hashed and shaken out rather than assigned. On 4.7.1 a freshly seeded
	# RandomNumberGenerator's FOURTH `randf()` lands in 0.09..0.24 whatever the
	# seed -- measured across six spread-out seeds, and written up in full in
	# `src/rendering/startle_shot.gd`. Here that draw is a climb angle rather than
	# anything load-bearing, but the cost of not doing it is a variation axis that
	# is quietly narrower than its own exports say.
	_rng.seed = hash(random_seed) if random_seed != 0 else int(Time.get_ticks_usec())
	for _discard in range(8):
		_rng.randf()
	ask_the_clock()
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.subscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_subscribed = true


func detach() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.unsubscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_subscribed = false


## The half of the day/night wiring that a subscription cannot do. Public so a
## test can prove it is what sets the opening state, rather than inferring it
## from a member's default.
##
## Both flags, and only one of them depends on the species. `_dark` would
## otherwise be wrong for everything up to the first sunset even for a flock that
## does not care about the rule.
func ask_the_clock() -> void:
	if _clock == null:
		return
	_dark = bool(_clock.is_night())
	_night = _dark and _daylight_only()


## Whether the RULE is in force: the wires must be empty. See the header.
func is_night() -> bool:
	return _night


## Whether the sun is down, which is a different question. True for a roosting
## species all night, while `is_night()` stays false.
func is_dark() -> bool:
	return _dark


## The birds currently out, in the order they landed. A copy, so a caller holding
## it across a frame cannot be surprised by the flock freeing one under it --
## which is what `_advance_birds` does the frame a bird passes `vanish_distance_m`.
func birds() -> Array[Bird]:
	return _birds.duplicate()


func bird_count() -> int:
	return _birds.size()


## The older names for the two above. `crow_calls.gd` and
## `src/rendering/startle_shot.gd` both call `crows()`, and neither is a file
## this refactor may touch -- so the names survive as one-line forwards rather
## than as a reason not to rename the class.
func crows() -> Array[Bird]:
	return birds()


func crow_count() -> int:
	return _birds.size()


func perched_count() -> int:
	var perched := 0
	for bird in _birds:
		if bird.is_perched():
			perched += 1
	return perched


# --- the day ------------------------------------------------------------------


# EventBus calls back with exactly one argument, always -- even when the payload
# is null. A handler declaring none is a runtime error at dispatch time, not a
# parse error, so the unused day number is named and kept.
func _on_day_started(_payload) -> void:
	_dark = false
	_night = false


## Nightfall empties the wires FOR A DAYLIGHT-ONLY SPECIES, and it empties them
## by sending the birds up rather than by deleting them. A bird that vanished
## mid-frame because a phase boundary passed is the one thing on screen that
## would look like a bug.
##
## For a roosting species nightfall is noted and nothing else happens: no flush,
## and the arrival stays open. That is the whole of the difference between the
## crows and the pigeons, and it is one boolean in a `.tres`.
func _on_night_started(_payload) -> void:
	_dark = true
	if not _daylight_only():
		_night = false
		return
	_night = true
	scatter(CAUSE_NIGHTFALL)


func _daylight_only() -> bool:
	return species.daylight_only if species != null else true


# --- the tick -----------------------------------------------------------------


func _process(delta: float) -> void:
	advance(delta)


## Public and carrying all the logic; `_process` only forwards. A whole
## afternoon can then be played out in a test in one call.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_read_the_wind()
	_advance_birds(delta)
	if not enabled:
		return
	if _birds.is_empty():
		_quiet -= delta
		# `_blowing` here as well as in the scatter below: without it a flock
		# lands into a gale and is flushed on the next frame, forever.
		if not _night and not _blowing and _quiet <= 0.0 and not _anyone_near(_arrival_guard()):
			_arrive()
		return
	# HE IS STILL STANDING THERE. A flock that landed and burst on the next frame
	# is a loop the player can watch happen, and it reads as broken rather than as
	# skittish -- so birds still on their way in think better of it and go, and the
	# quiet timer starts again. Better a wire that stays empty while he loiters
	# under it than a wire that cycles.
	_call_off_the_landing()
	_settled += delta
	if _settled < stagger_seconds or perched_count() == 0:
		return
	# The man first. If he is under the wire in a gale, what took the birds is
	# still him -- he is the one a Wave 5 listener cares about, and a cue that
	# reported the weather instead would be reporting the wrong thing.
	if _anyone_near(flush_radius_m):
		scatter(CAUSE_PLAYER)
	elif _blowing:
		scatter(CAUSE_GUST)


## The gust latch. Hysteresis for the same reason `WindSystem._report()` has it:
## a strength sitting on the threshold would otherwise publish a storm of
## scatters, and one of the few things worse than a bird that does not react is a
## bird that reacts sixty times a second.
func _read_the_wind() -> void:
	if not _blowing and _wind_strength >= gust_scatter_strength:
		_blowing = true
	elif _blowing and _wind_strength <= gust_release_strength:
		_blowing = false


func _advance_birds(delta: float) -> void:
	var living: Array[Bird] = []
	for bird in _birds:
		# Ride BEFORE advancing: put the bird on the wire where the wire is this
		# frame, then let its own timeline decide whether it is still standing on
		# it. `ride()` returns immediately for a bird that is already flying.
		bird.ride(_wind_strength)
		bird.advance(delta)
		if bird.is_gone():
			# Removed from the tree before being freed, so a frame that runs
			# between the two cannot find it.
			if bird.get_parent() != null:
				bird.get_parent().remove_child(bird)
			bird.queue_free()
			continue
		living.append(bird)
	if living.size() != _birds.size() and living.is_empty():
		# THE RETURN IS SHORTER THAN THE QUIET, and which one applies is decided by
		# what emptied the wire. See `return_min_seconds`.
		_quiet = _rng.randf_range(return_min_seconds, return_max_seconds) \
			if _last_cause == CAUSE_PLAYER \
			else _rng.randf_range(quiet_min_seconds, quiet_max_seconds)
	_birds = living


## Any bird heading for a perch he is standing under turns round and leaves.
##
## THE QUESTION IS ABOUT THE PERCH, NOT ABOUT THE BIRD. Written first as
## `_anyone_near(_arrival_guard())`, which asks how close he is to the BIRDS --
## and an inbound bird is thirty metres out on its way in, so the answer was
## always no and the flock landed on his head anyway. What decides whether a
## landing is a bad idea is where the bird is trying to GO.
##
## Per bird, so a flock coming down on two different wires only calls off the
## half he is under. The rest carry on and land, which is what birds do.
func _call_off_the_landing() -> int:
	var watched := _watch()
	if watched == null:
		return 0
	var at := _disturbance()
	var gave_up := 0
	for bird in _birds:
		if not (bird.is_inbound() or bird.is_landing()):
			continue
		if _flat_gap(bird.target_perch(), at) > _arrival_guard():
			continue
		if bird.give_up():
			gave_up += 1
	if gave_up > 0:
		# Not a startle: nothing was startled. The wire simply stays empty a while
		# longer, and the ordinary quiet is the right length for that.
		_last_cause = CAUSE_NIGHTFALL
	return gave_up


## Put a flock out now, whatever the quiet timer says. Returns how many landed.
##
## The one door into `_arrive()` from outside, and it exists for the same reason
## `advance()` is public: a capture cannot wait out `first_arrival_seconds` and
## then photograph a random number of birds, because two runs would not be the
## same picture and there would be nothing to compare.
func arrive_now() -> int:
	var before := _birds.size()
	_arrive()
	return _birds.size() - before


## Put a flock out and let it fly all the way in, however long that takes.
##
## For a test or a capture that wants birds ON the wire and does not want to
## photograph the approach. Returns how many are perched.
func land_now() -> int:
	_arrive()
	var frame := 1.0 / 60.0
	var left := 12.0
	while left > 0.0 and perched_count() < _birds.size():
		_advance_birds(frame)
		left -= frame
	_settled = 0.0
	return perched_count()


## A flock arrives. One to `most` birds, on perches drawn without replacement so
## two never land in the same place -- AND FLYING IN, rather than appearing
## already sitting there.
##
## The perches are drawn fresh every time, which is the owner's "回到随机的一个
## 可以落脚的地方": a flock does not reassemble in the arrangement it left, and
## it need not be the same size, because both would read as a rewind rather than
## as birds coming back.
func _arrive() -> void:
	var perches := available_perches()
	if perches.is_empty():
		# Nowhere to sit is not an error -- a level with no wires in it simply
		# has no birds -- but retrying every frame would be a gather per frame.
		_quiet = quiet_max_seconds
		return
	var wanted := mini(_rng.randi_range(maxi(fewest, 1), maxi(most, fewest)), perches.size())
	var order := _shuffled(perches.size())
	_settled = 0.0
	# One bearing for the flock, jittered per bird. They come in together, from
	# somewhere, rather than converging from every point of the compass.
	var entry := _rng.randf_range(0.0, TAU)
	var wheel_sign := 1.0 if _rng.randf() < 0.5 else -1.0
	for index in range(wanted):
		var perch: Dictionary = perches[order[index]]
		var bird := _build_bird()
		var bearing := entry + _rng.randf_range(-0.5, 0.5)
		var from: Vector3 = (perch["at"] as Vector3) \
			+ Vector3(cos(bearing), 0.0, sin(bearing)) * arrival_distance_m \
			+ Vector3.UP * arrival_height_m
		var rate := wheel_sign * _rng.randf_range(wheel_rate_min, wheel_rate_max) \
			* (1.0 + _rng.randf_range(-wheel_jitter, wheel_jitter))
		var circle := _rng.randf_range(wheel_seconds_min, wheel_seconds_max)
		# The perch travels with the bird as a DECLARATION, not as a position: a
		# wire that sways during the ten seconds of the approach is still the wire
		# the bird has to land on. `Bird.approach` resolves it every frame.
		bird.approach(perch, from, rate, circle)
		_birds.append(bird)


## Everything goes up. Returns how many actually left, so a caller can tell a
## flock that scattered from one that had already gone.
func scatter(cause: StringName) -> int:
	var perched: Array[Bird] = []
	for bird in _birds:
		if bird.is_perched():
			perched.append(bird)
	if perched.is_empty():
		return 0
	var centre := _disturbance()
	# Nearest first, so the burst travels along the wire away from whatever
	# caused it rather than starting at whichever end the array happens to hold.
	perched.sort_custom(func(a: Bird, b: Bird) -> bool:
		return a.where().distance_squared_to(centre) \
			< b.where().distance_squared_to(centre))
	# The wind decides the bearing when the wind is what took them; otherwise it
	# is whatever they are running from. Same burst either way -- one axis and
	# one spread, chosen rather than duplicated.
	var blown := cause == CAUSE_GUST and _downwind() != Vector3.ZERO
	var away := _downwind() if blown else _away_from(centre, perched)
	var spread := deg_to_rad(gust_spread_degrees if blown else spread_degrees)
	var middle := (float(perched.size()) - 1.0) * 0.5
	# One direction for the whole burst. See wheel_rate_min.
	var wheel_sign := 1.0 if _rng.randf() < 0.5 else -1.0
	var aloft := Vector3.ZERO
	for index in range(perched.size()):
		var bird := perched[index]
		aloft += bird.where()
		# Fanned across the spread by position in the burst and then jittered, so
		# the shape is a fan rather than a random spray -- and no two are within a
		# few degrees of each other, which is what a spray keeps producing.
		var fan := 0.0 if perched.size() == 1 \
			else (float(index) - middle) / middle * spread * 0.5
		var jitter := _rng.randf_range(-1.0, 1.0) * spread * 0.12
		var climb := deg_to_rad(_rng.randf_range(climb_min_degrees, climb_max_degrees))
		var rate := wheel_sign * _rng.randf_range(wheel_rate_min, wheel_rate_max) \
			* (1.0 + _rng.randf_range(-wheel_jitter, wheel_jitter))
		var mill := _rng.randf_range(wheel_seconds_min, wheel_seconds_max)
		bird.scatter(
			_heading(away, fan + jitter, climb),
			float(index) * stagger_seconds,
			rate,
			mill
		)
	aloft /= float(perched.size())
	_last_cause = cause
	_emit(EVENT_SCATTERED, {
		# WHERE THE FRIGHT WAS. The man, in the ordinary case.
		"position": centre,
		# WHERE THE BIRDS ARE, which is a different place and is the one a camera
		# wanting to look at them needs. Added rather than replacing `position`
		# because a Wave 5 listener asking "what is out there" wants the
		# disturbance and a shot wants the subject.
		"aloft": aloft,
		"count": perched.size(),
		"cause": cause,
	})
	return perched.size()


## Every perch on offer right now.
##
## Gathered fresh each time a flock arrives rather than cached: the wires are
## strung at `_ready()` from two other nodes' settled positions, and a level that
## grows a second pole later should grow perches with it.
##
## A species that declines an occupied perch is filtered here -- see the header.
func available_perches() -> Array:
	var offered: Array = _perches if _explicit_perches \
		else PerchPoints.gather(get_tree() if is_inside_tree() else null)
	if species == null or not species.avoids_occupied_perches:
		return offered
	return free_of(offered, _birds_on_their_perches(), species.occupied_within_m)


## `offered`, less every perch within `within` metres of a bird in `standing`.
##
## Static and public so the rule can be exercised without a scene tree, two
## flocks and a wire. The alternative -- asserting it through `available_perches`
## -- needs all three, and a test that expensive is a test that gets written once
## and never covers the edges.
static func free_of(offered: Array, standing: Array, within := OCCUPIED_WITHIN_M) -> Array:
	if standing.is_empty():
		return offered
	var free: Array = []
	for perch in offered:
		var at: Vector3 = perch.get("at", Vector3.ZERO)
		var taken := false
		for bird in standing:
			if at.distance_to(bird) <= within:
				taken = true
				break
		if not taken:
			free.append(perch)
	return free


## Where every bird currently standing on something is -- of ANY species, which
## is the point: a pigeon declining an occupied perch has to see the crows too.
##
## Asked of the whole tree by TYPE rather than through a group, so nothing has to
## join one. Run once per arrival, not once per frame.
func _birds_on_their_perches() -> Array:
	var found: Array = []
	# `get_tree()` on a node outside the tree is not merely null -- it prints
	# `Parameter "data.tree" is null`, and a run whose console is dirty is a
	# failed run (briefing section 2.1). A flock under test is never in a tree.
	if not is_inside_tree():
		return found
	var tree := get_tree()
	if tree == null or tree.get_root() == null:
		return found
	for node in tree.get_root().find_children("*", "Bird", true, false):
		var bird := node as Bird
		if bird == null or not bird.is_on_the_wire():
			continue
		found.append(bird.where())
	return found


# --- internals ----------------------------------------------------------------


## One bird, named, painted from the flock's shared painter, and handed the
## species.
##
## `_new_bird()` is the only thing a named flock overrides, and only so that
## `child is Crow` keeps answering for the things that ask it. A flock whose
## species comes out of a `.tscn` hatches plain `Bird`s and needs no subclass at
## all -- which is the whole of what this refactor bought.
func _build_bird() -> Bird:
	if _painter == null:
		_painter = CelPainter.new()
	var bird := _new_bird()
	if species != null:
		bird.species = species
	_hatched += 1
	bird.name = "%s%d" % [_species_name(), _hatched]
	bird.set_painter(_painter)
	add_child(bird)
	return bird


func _new_bird() -> Bird:
	return Bird.new()


## `Crow`, `Pigeon`, `WinterWren` -- whatever the species calls itself, in the
## shape a node name wants. Never with a space in it: `capitalize()` would turn
## `winter_wren` into `Winter Wren`, and a node name with a space in it is a
## NodePath that needs quoting everywhere it is used.
func _species_name() -> String:
	if species == null or species.species_name == "":
		return "Bird"
	return species.species_name.to_pascal_case()


## A heading `yaw` radians off `away`, climbing at `climb`.
static func _heading(away: Vector3, yaw: float, climb: float) -> Vector3:
	var flat := Vector3(away.x, 0.0, away.z)
	if flat.length_squared() < 0.000001:
		flat = Vector3(0.0, 0.0, -1.0)
	flat = flat.normalized().rotated(Vector3.UP, yaw)
	return (flat * cos(climb) + Vector3.UP * sin(climb)).normalized()


## The way the wind is blowing, flat, or zero if nobody has told us.
##
## `WindSystem` pushes a velocity through `set_wind()`; its length is the
## vocabulary of whatever asked for it and is of no interest here, only its
## bearing. Zero is a real answer -- a scene with no wind system in it -- and the
## caller falls back to the ordinary burst rather than sending five birds due
## north because a default said so.
func _downwind() -> Vector3:
	var flat := Vector3(_wind.x, 0.0, _wind.z)
	if flat.length_squared() < 0.000001:
		return Vector3.ZERO
	return flat.normalized()


## Which way "away" is: from the disturbance toward the middle of the flock.
## With nothing to run from -- nightfall -- the birds still have to go somewhere,
## and the wire's own direction is the honest answer.
func _away_from(centre: Vector3, perched: Array[Bird]) -> Vector3:
	var middle := Vector3.ZERO
	for bird in perched:
		middle += bird.where()
	middle /= float(perched.size())
	var away := middle - centre
	away.y = 0.0
	if away.length_squared() < 0.01:
		return Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
	return away.normalized()


## Where the fright came from. The watched body if there is one, otherwise the
## flock's own middle -- which makes `_away_from` fall back to a random bearing,
## which is what nightfall wants.
func _disturbance() -> Vector3:
	var watched := _watch()
	if watched == null:
		var middle := Vector3.ZERO
		for bird in _birds:
			middle += bird.where()
		return middle / maxf(float(_birds.size()), 1.0)
	return watched.global_position if watched.is_inside_tree() else watched.position


## Is he under them?
##
## FLAT, and this was a real defect measured on the shipped scene. The comparison
## was a full 3D distance, and a bird is up a pole: the perches in `main.tscn`
## sit between 5.09 m and 8.66 m up, so a man walking directly underneath is
## already 4.19 m to 7.76 m away before he has moved an inch sideways. The
## remaining horizontal reach of an eight-metre radius is therefore
## `sqrt(8^2 - h^2)`, which is 6.8 m at the low end of the drop wire and
## **1.95 m** at the top of the pole -- so a flock on the high perches was
## essentially unflushable, and a man could walk right past under the wire with
## nothing happening.
##
## Nothing reports it, which is why it survived: birds landing on a low perch
## still burst, so the feature "works", and it is the SAME flock that sometimes
## does not. It reads as the birds not having noticed him. Found while capturing
## the startle shot -- one seed in three landed a flock high and no walk-through
## could set it off.
##
## `flush_radius_m`'s own comment says the number is chosen against the tight
## framing stop's 10.5 m of WORLD -- a horizontal quantity. This makes the
## comparison the one the number was chosen for.
func _anyone_near(radius: float) -> bool:
	var watched := _watch()
	if watched == null:
		return false
	var at := _disturbance()
	for bird in _birds:
		# Only birds actually standing on a flock perch belong to this shared
		# flush test. A species may also keep ground visitors in the same flock;
		# those own their closer, individual fear radius and must not launch a
		# distant wire flock merely because the player is near the ground bird.
		if not bird.is_perched():
			continue
		if _flat_gap(bird.where(), at) <= radius:
			return true
	if not _birds.is_empty():
		return false
	# Nothing is out yet, so the question is about the perches themselves.
	for perch in available_perches():
		if _flat_gap(perch["at"] as Vector3, at) <= radius:
			return true
	return false


static func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Birds do not land on a wire somebody is standing under. A little wider than
## the flush radius, or a player loitering by the pole would spawn a flock and
## flush it on the same frame, over and over.
func _arrival_guard() -> float:
	return flush_radius_m * 1.5


func _watch() -> Node3D:
	if _watched != null and is_instance_valid(_watched):
		return _watched
	if _registry == null:
		return null
	var found := _registry.get_service(&"player") as Node3D
	if found != null and found.is_inside_tree():
		return found
	return null


## Indices 0..n-1 in a random order, from this flock's own RNG so a seeded run
## is reproducible. `Array.shuffle()` uses the global RNG and would not be.
func _shuffled(count: int) -> Array:
	var order: Array = []
	for index in range(count):
		order.append(index)
	for index in range(count - 1, 0, -1):
		var swap := _rng.randi_range(0, index)
		var held = order[index]
		order[index] = order[swap]
		order[swap] = held
	return order


func _emit(event: StringName, payload) -> void:
	if _bus != null:
		_bus.emit_event(event, payload)
