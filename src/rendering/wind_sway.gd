extends Node

## The wires moving in a gust. Art Bible rule 11, made to happen.
##
## ---------------------------------------------------------------------------
## WHY THE WIRES AND NOT SOMETHING BIGGER
## ---------------------------------------------------------------------------
## Rule 11: the snow itself is almost untextured, and the whole "detail" of the
## picture comes from a handful of LINES -- tyre tracks, footprint chains, plough
## furrows, and the wires crossing the frame. Those lines carry the entire detail
## budget, so a line that moves is the cheapest wind the picture can be given:
## three `global_position` writes a frame, no shader, no new geometry, no import.
##
## ---------------------------------------------------------------------------
## WHAT A STRAIGHT SEGMENT CANNOT DO, SAID OUT LOUD
## ---------------------------------------------------------------------------
## A real span swings like a pendulum about the line joining its two anchors, and
## the displacement is largest at midspan and zero at the ends. `power_wire.glb`
## is ONE METRE OF STRAIGHT WIRE, stretched along its own -Z by
## `Farmstead._span()`; it has no midspan vertices to displace. Rotating a
## straight segment about its own chord is geometrically a no-op, so the swing
## this asset can honestly show is exactly none.
##
## So the motion here is a small rigid TRANSLATION across the wind, and the whole
## span moves together. What that buys and what it costs:
##
##   * BUYS: coherent motion along the entire visible length of the line, which
##     is what the eye actually reads at this camera distance. A long thin line
##     moving as one is legible at two or three pixels.
##   * COSTS: the anchors move too, by the same amount. Held to 0.14 m at full
##     gale -- about eight pixels at the gameplay framing, against a wire that is
##     itself seven centimetres thick -- so it stays inside "the wire is thick"
##     rather than reading as a wire that has come off its pole.
##
## The alternative -- rotating about one anchor, so that end stays pinned --
## concentrates the whole error at the OTHER end instead, which for two of the
## three spans is the eave of the house. Spreading a small error over both ends
## beats hiding all of it at one.
##
## A bent asset with midspan geometry would let this be done properly. That is an
## art-pipeline change and it is not this task.
##
## ---------------------------------------------------------------------------
## HOW IT IS WIRED
## ---------------------------------------------------------------------------
## By GROUP, so this file holds no reference to the farmstead and the farmstead
## holds none to this. Anything that should move in the wind joins `wind_sway`;
## `Farmstead._span()` is the only joiner today.
##
## The wind arrives through the same two hooks every other consumer publishes --
## `set_wind()` and `set_wind_strength()` -- so `WindSystem` finds this the same
## way it finds the breath and the snow, with no special case.

## Where a thing that should move in the wind publishes itself.
const GROUP := &"wind_sway"

## The fundamental period of the swing, in seconds. A span the length of these
## is a slow pendulum; anything under about a second reads as a vibrating string
## rather than as a wire in weather.
const SWAY_SECONDS := 1.9

## How much of the swing is the second, incommensurate component. Present so
## three wires strung from one pole never return to the same relative pose --
## with a single sine they beat together and the three read as one object.
const SECOND_HARMONIC := 0.28

## The vertical bob, as a fraction of the horizontal swing. Small: a wire that
## rises and falls as much as it swings reads as a skipping rope. Enough that the
## motion is not a flat slide.
const VERTICAL_FRACTION := 0.30

## How far a span moves across the wind at full gale, in metres. See the header
## for why it is this small and what it is traded against.
@export var sway_metres := 0.14

## The exponent the strength is raised to. Below 1 so an ordinary gust still
## shows: at 0.5 a strength of 0.35 gives 59 per cent of full amplitude rather
## than 35, and the difference is whether anything moves on a normal day.
@export var response := 0.50

var _wind := Vector3.ZERO
var _strength := 0.0
## The scene's own clock for this effect, in seconds. See _process().
var _clock := 0.0
## instance id -> the position the node was placed at, before any sway.
var _rest: Dictionary = {}


## THE WIND HOOKS, in the vocabulary every other consumer already speaks. Only
## the DIRECTION of the vector is used here -- the amplitude is this file's own,
## because a wire's swing is set by its mass and its span, not by how hard a
## snowflake is being pushed.
func set_wind(velocity: Vector3) -> void:
	_wind = velocity


func set_wind_strength(strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)


func wind_strength() -> float:
	return _strength


## Two incommensurate components, in -1 .. 1. `phase` is the per-span seed; two
## spans with different seeds are never at the same point of the swing.
static func oscillation(t: float, phase: float) -> float:
	var w := TAU / SWAY_SECONDS
	return (1.0 - SECOND_HARMONIC) * sin(w * t + phase) \
		+ SECOND_HARMONIC * sin(w * 1.61803 * t + phase * 2.13)


## Where a span sits this instant, relative to where it was strung.
##
## `axis` is the span's own long axis and `wind` the direction the wind blows.
## The amplitude carries the CROSSWIND component of the wind and nothing else,
## which is free -- it is one projection -- and is the difference between three
## wires that sway and three wires that slide sideways in step. A wind blowing
## along a span does not move it, and that is right.
static func offset_for(
	axis: Vector3,
	wind: Vector3,
	strength: float,
	phase: float,
	amplitude_m: float,
	response_exponent: float,
	t: float
) -> Vector3:
	var held := clampf(strength, 0.0, 1.0)
	if held <= 0.0 or amplitude_m <= 0.0:
		return Vector3.ZERO
	var blow := wind
	if blow.length_squared() < 0.000001:
		return Vector3.ZERO
	blow = blow.normalized()
	var line := axis
	if line.length_squared() > 0.000001:
		line = line.normalized()
		# The component of the wind at right angles to the span. Its LENGTH is
		# the crosswind fraction, from 1 (dead across) to 0 (dead along), so
		# using the vector unnormalised gives that fraction for nothing.
		blow = blow - line * blow.dot(line)
	if blow.length_squared() < 0.000001:
		return Vector3.ZERO
	var amplitude := amplitude_m * pow(held, maxf(response_exponent, 0.01))
	var swing := oscillation(t, phase)
	var across := blow * (amplitude * swing)
	# The bob runs at twice the swing: a pendulum rises at both ends of its
	# travel, not at one.
	var lift := Vector3.UP * (amplitude * VERTICAL_FRACTION * sin(2.0 * (TAU / SWAY_SECONDS) * t + phase))
	return across + lift


## A stable, distinct phase for a node, in radians. Derived from the instance id
## so nothing has to be authored and no two spans share it.
static func phase_for(instance_id: int) -> float:
	return fposmod(float(instance_id) * 0.6180339887, 1.0) * TAU


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	if not is_inside_tree():
		return
	# ACCUMULATED DELTA, not `Time.get_ticks_msec()`. Written the wall-clock way
	# first, and that is wrong twice: the wires go on swinging while the game is
	# paused, and under `--fixed-fps` a capture's wall clock runs ahead of its
	# simulated one by however long each PNG took to write -- so a swing could
	# never be reproduced from a capture.
	_clock += delta
	for node in get_tree().get_nodes_in_group(GROUP):
		var member := node as Node3D
		if member == null or not is_instance_valid(member):
			continue
		var id := member.get_instance_id()
		if not _rest.has(id):
			_rest[id] = member.global_position
		var rest: Vector3 = _rest[id]
		# The span's long axis. `Farmstead._span()` aims the element's -Z at the
		# far anchor, which is what `look_at()` does, so -Z is the line.
		var axis := -member.global_basis.z
		member.global_position = rest + offset_for(
			axis, _wind, _strength, phase_for(id), sway_metres, response, _clock
		)
	# Nodes that have left the tree since we last looked: drop their rest
	# positions rather than growing a dictionary for the length of a run.
	if _rest.size() > 64:
		_forget_the_departed()


func _forget_the_departed() -> void:
	var live: Dictionary = {}
	for node in get_tree().get_nodes_in_group(GROUP):
		live[node.get_instance_id()] = true
	for id in _rest.keys():
		if not live.has(id):
			_rest.erase(id)
