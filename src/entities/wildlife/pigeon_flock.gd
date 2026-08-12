class_name PigeonFlock
extends CrowFlock

## The pigeons in the valley. Same wires, same eaves, and unlike the crows they
## are there after dark.
##
## ---------------------------------------------------------------------------
## WHAT IT INHERITS AND WHY
## ---------------------------------------------------------------------------
## Everything: the quiet timer, the arrival from off-frame, the fan, the
## stagger, the wind latch, the return after a startle, the perch gather, the
## published event. None of that is about crows either -- see the header of
## `src/entities/wildlife/pigeon.gd` -- and a second copy would be a second copy
## of every defect that file has already been debugged through.
##
## Three things are replaced, and only three.
##
## ---------------------------------------------------------------------------
## 1. NIGHT IS NOT A REASON TO EMPTY THE WIRE
## ---------------------------------------------------------------------------
## `CrowFlock` holds a `_night` flag that means, in the parent's own logic,
## exactly one thing: **the wires must be empty**. It blocks the arrival, and
## nightfall flushes whatever is up there.
##
## A rock dove roosts on the ledges it feeds from. It is on the eave at dusk and
## still on it at dawn, and a valley whose only bird vanishes the moment the sun
## goes down is a valley that is obviously running a day/night switch. So for
## this flock the parent's flag is held at false for the whole run, and the real
## clock phase is kept separately as `is_dark()` -- because `_night` is the
## parent's rule and `is_dark()` is the fact, and conflating them is how a field
## comes to mean two things.
##
## The subscription is untouched: `CrowFlock.attach()` binds `_on_day_started`
## and `_on_night_started` off `self`, and GDScript dispatches those to the
## overrides below. Nothing in the parent had to be told this class exists.
##
## ---------------------------------------------------------------------------
## 2. THE BIRD IT BUILDS
## ---------------------------------------------------------------------------
## `_build_crow()` returns a `Crow`, and a `Pigeon` IS one by inheritance, so the
## flock's own bookkeeping needs no change at all.
##
## ---------------------------------------------------------------------------
## 3. IT WILL NOT LAND ON A BIRD THAT IS ALREADY THERE
## ---------------------------------------------------------------------------
## Both flocks gather from the same `perches` group, which is what lets pigeons
## and crows share a wire -- and which means two flocks that cannot see each
## other can hand out the same perch twice. At sixteen pixels two birds in one
## place is a single wrong-shaped blob.
##
## `available_perches()` therefore drops any perch somebody is standing on. That
## is deliberately NOT flock-versus-flock behaviour -- there is no signal, no
## subscription and no knowledge of another flock's existence; it is one bird
## declining to land on another, asked as a question about the PERCH.
##
## **It only works in one direction, and that is a real limitation rather than a
## simplification.** The crows do not ask, because `CrowFlock` is another agent's
## file this task did not touch, so a crow can still come down on a pigeon. The
## fix when that file is quiet is the same override moved up into the parent, or
## better, a claim on the `PerchPoints` declaration itself -- the wire is the
## thing that knows who is standing on it.

## How near another bird has to be for a perch to count as taken.
##
## A perched dove is 0.30 m long and the wire spacings in `scenes/main.tscn` are
## 2.2 m to 3.0 m, so this only ever fires on two birds sent to the SAME perch
## rather than to neighbouring ones.
const OCCUPIED_WITHIN_M := 0.35

## Whether the sun is down. Not the parent's `_night`, which for this flock is
## the rule "the wires must be empty" and is always false -- see the header.
var _dark := false


## A flock of pigeons is bigger than a flock of crows and less easily moved.
##
## Both numbers are the bird rather than a preference: rock doves feed and roost
## in groups where a crow perches in ones and twos, and they are used to people,
## which is why a pigeon lets you walk under it and a crow does not. The flush
## radius is inside the crow's 8 m so the same walk past the pole puts the crows
## up first and the pigeons only if he keeps coming.
func _init() -> void:
	fewest = 2
	most = 6
	flush_radius_m = 5.0


## Whether the sun is down. The clock's own answer, kept because the inherited
## `is_night()` has been given a different job for this flock.
func is_dark() -> bool:
	return _dark


## Reads the clock without letting the answer empty the wires.
##
## The parent's version is the half of the day/night wiring a subscription cannot
## do -- it makes the FIRST phase correct rather than waiting for a transition
## that may be a whole phase away. That half still matters here even though the
## answer no longer gates anything, because `is_dark()` would otherwise be wrong
## for everything up to the first sunset.
func ask_the_clock() -> void:
	if _clock != null:
		_dark = bool(_clock.is_night())
	_night = false


func _on_day_started(_payload) -> void:
	_dark = false
	_night = false


## Nightfall is noted and nothing else happens. No flush, and the arrival stays
## open, which is the whole of the difference from the crows.
func _on_night_started(_payload) -> void:
	_dark = true
	_night = false


## Every perch on offer that nobody is standing on. See the header.
func available_perches() -> Array:
	return free_of(super(), _birds_on_their_perches())


## `offered`, less every perch within `OCCUPIED_WITHIN_M` of a bird in `standing`.
##
## Static and public so the rule can be exercised without a scene tree, two
## flocks and a wire. The alternative -- asserting it through `available_perches`
## -- needs all three, and a test that expensive is a test that gets written once
## and never covers the edges.
static func free_of(offered: Array, standing: Array) -> Array:
	if standing.is_empty():
		return offered
	var free: Array = []
	for perch in offered:
		var at: Vector3 = perch.get("at", Vector3.ZERO)
		var taken := false
		for bird in standing:
			if at.distance_to(bird) <= OCCUPIED_WITHIN_M:
				taken = true
				break
		if not taken:
			free.append(perch)
	return free


## Where every bird currently standing on something is.
##
## Asked of the whole tree by TYPE rather than through a group, because joining a
## group would mean editing `crow.gd` -- and asking for `Crow` finds the pigeons
## too, since a `Pigeon` is one. Run once per arrival, not once per frame.
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
	for node in tree.get_root().find_children("*", "Crow", true, false):
		var bird := node as Crow
		if bird == null or not bird.is_on_the_wire():
			continue
		found.append(bird.where())
	return found


func _build_crow() -> Crow:
	if _painter == null:
		_painter = CelPainter.new()
	var bird := Pigeon.new()
	_hatched += 1
	bird.name = "Pigeon%d" % _hatched
	bird.set_painter(_painter)
	add_child(bird)
	return bird
