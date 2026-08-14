extends Node

## Things that hang and things that stand, moved by the wind with real dynamics.
##
## Drives every `Node3D` in one group by tilting it about its own origin. Two
## instances ship, configured differently and sharing every line of code:
##
##   * `wind_swing`    -- the tyre swing. Hangs, long period, lightly damped.
##   * `wind_branches` -- the bare trees. Stands, short period, buffeted.
##
## ---------------------------------------------------------------------------
## WHY THIS IS AN INTEGRATOR AND NOT A SINE
## ---------------------------------------------------------------------------
## A sine scaled by wind strength has NO MEMORY. It is exactly in phase with the
## wind at every instant, so it reads as a value being applied to an object
## rather than as an object being pushed by air. Everything that makes a
## pendulum convincing is memory:
##
##   * it ARRIVES LATE. The wind rises and the tyre is still where it was.
##   * it OVERSHOOTS. A step of wind carries it past where that wind can hold it.
##   * it RINGS DOWN. The gust passes and the tyre is still swinging.
##
## So the wind enters as a FORCE and the angle comes out of an integration:
##
##     theta'' = w0^2 * (drive - sin(theta)) - 2 * zeta * w0 * theta'
##
## `drive` is the horizontal aerodynamic force over the weight, which makes the
## equilibrium `asin(drive)` -- bounded by construction, no clamp needed for the
## steady state, and small-angle-free so a gale cannot send it over the top.
##
## `w0` is `sqrt(g / L)` for a hanging thing, so the PERIOD IS THE ROPE LENGTH
## rather than a number somebody picked: 1.74 m of rope to the middle of the tyre
## gives 2.65 s, and that is why the swing looks like a swing.
##
## ---------------------------------------------------------------------------
## BARE BRANCHES DO NOT SWAY. THEY ARE STIFF, AND THEY WHIP.
## ---------------------------------------------------------------------------
## A gentle continuous sway reads as summer foliage in a breeze, and it will look
## wrong in a way that is hard to name. Frozen wood is stiff: it stands still,
## and when a gust crosses it snaps over and rings down in under a second.
##
## Two things produce that here, and neither is an animation:
##
##   1. THE FORCE IS SCALED BY STRENGTH, so in a lull -- 0.06 on the valley
##      profile -- the drive is a fortieth of full and the tree is motionless.
##   2. THE FORCE IS BUFFETED. Real branches whip because the air is turbulent at
##      a far smaller scale than the gust envelope, so `buffet` modulates the
##      drive at a few hertz, per tree, out of phase with every other tree.
##
## The buffet IS a pair of sines -- but it is the FORCING, not the output. What
## reaches the transform is the integrator's response to it, which lags it,
## overshoots it and rings after it stops. That difference is the whole point of
## the paragraph above.
##
## ---------------------------------------------------------------------------
## WHAT THIS CANNOT DO
## ---------------------------------------------------------------------------
## It tilts a WHOLE NODE about its origin. For a tree standing on its own origin
## that gives displacement proportional to height -- the crown moves, the base
## does not, which is most of the read -- but it cannot make a thin outer twig
## move further than a thick limb at the same height. That needs per-vertex
## displacement in the tree's material, which on these split-vertex models cracks
## every hard edge (see DEFERRED W2-6) and means opening the cel shader. Not
## taken; the cost is an art-pipeline change and the remaining gain is small at
## this camera.

## The group this instance drives.
@export var group: StringName = &"wind_swing"

## TRUE for a thing that hangs from its origin -- a tyre on a rope -- and FALSE
## for a thing that stands on it. Both tilt about the origin; only the sign of
## the useful direction differs, because the mass is below the pivot in one case
## and above it in the other.
@export var hangs := true

## The natural period, in seconds. ZERO means DERIVE IT, which is what a hanging
## thing should do: the period of a pendulum is a fact about its rope, and a
## number typed here would be a second, quieter copy of the model's geometry.
@export var period_seconds := 0.0

## Where the mass sits on a hanging thing, as a fraction of the distance from the
## origin to its lowest point. A tyre on a rope is nearly all tyre and the tyre
## is at the bottom, so this is high. Only used when `period_seconds` is 0.
@export var mass_fraction := 0.81

## Fallback length when a node has no measurable extent, in metres.
@export var fallback_length := 1.74

## The damping ratio. Below 1 it oscillates; the smaller it is the longer it
## rings. A tyre on a rope rings for a good ten seconds, which is what makes it
## still be moving after the gust that started it has gone -- the single most
## convincing thing about it. Frozen wood does not: it takes one swing back and
## stops.
@export var damping_ratio := 0.10

## How far the wind can hold it over at a strength of 1.0, in degrees. This is
## the STEADY angle, not the peak: the overshoot on a rising gust goes past it,
## which is the point.
@export var drive_degrees := 13.0

## A hard ceiling, in degrees, on where the transform is allowed to go. Not part
## of the physics -- the equilibrium is bounded already -- but a gale arriving on
## one frame plus a low frame rate should never be able to put a tyre over the
## branch it hangs from.
@export var max_degrees := 24.0

## Turbulence. `buffet_gain` modulates the drive by +/- this fraction, at roughly
## `buffet_hz`, with a per-node phase. Zero for the tyre: a tyre is heavy and
## slow and averages the turbulence out. See the header for why the trees need
## it and why it is not an animation.
@export var buffet_gain := 0.0
@export var buffet_hz := 2.3

const GRAVITY := 9.81

## The largest `w0 * delta` a single integration step may take. Above about this
## a semi-implicit Euler starts to gain energy, and a tree that slowly winds
## itself up is a bug that only shows on a slow machine.
const MAX_STEP_PRODUCT := 0.25
const MAX_SUBSTEPS := 8

var _wind := Vector3.ZERO
var _strength := 0.0
var _clock := 0.0
## instance id -> [angle_x, rate_x, angle_z, rate_z]
var _state: Dictionary = {}
## instance id -> the basis the node was authored with, before any tilt.
var _rest: Dictionary = {}
## instance id -> the natural frequency derived from its own geometry.
var _omega: Dictionary = {}


## THE WIND HOOKS, in the vocabulary every other consumer speaks, so `WindSystem`
## finds this with no special case. Only the DIRECTION of the vector is used --
## the force is this file's own, because how hard a branch bends is a fact about
## the branch and not about how hard a snowflake is being pushed.
func set_wind(velocity: Vector3) -> void:
	_wind = velocity


func set_wind_strength(strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)


func wind_strength() -> float:
	return _strength


## Add a short, physical shove to a hanging member already owned by this
## integrator.  Wind and contact therefore share the same restoring force,
## damping and derived rope period; an impact rings down instead of resetting
## the wind motion or starting a separate animation.
func apply_impulse(member: Node3D, world_impulse: Vector3) -> void:
	if member == null or not is_instance_valid(member):
		return
	_ensure_member(member)
	var push := world_impulse
	var parent := member.get_parent() as Node3D
	if parent != null:
		# Unit subjects are deliberately not inserted into a SceneTree. Reading a
		# global basis there produces an engine error, while the local basis is the
		# same frame needed for this conversion in that isolated case.
		var parent_basis := parent.global_basis if parent.is_inside_tree() else parent.basis
		push = parent_basis.inverse() * push
	push.y = 0.0
	if push.length_squared() < 0.000001:
		return
	var state: Array = _state[member.get_instance_id()]
	# Rates are radians per second. The ceiling is generous enough for a firm
	# body bump but keeps an accidental repeated overlap from looping the tire.
	state[1] = clampf(state[1] + push.x, -1.8, 1.8)
	state[3] = clampf(state[3] + push.z, -1.8, 1.8)


# --- the physics, all of it pure --------------------------------------------

## One step of the driven damped pendulum. Takes and returns `[angle, rate]` so
## the whole of it is testable with no tree and no node.
##
## Semi-implicit Euler -- rate first, then angle from the NEW rate. Explicit
## Euler on an oscillator gains energy every cycle and a tyre swing that slowly
## builds to a full loop is not a thing anybody would guess at from the symptom.
static func step(
	angle: float, rate: float, drive: float, omega: float, zeta: float, delta: float
) -> Array:
	if delta <= 0.0 or omega <= 0.0:
		return [angle, rate]
	var substeps := clampi(int(ceil(omega * delta / MAX_STEP_PRODUCT)), 1, MAX_SUBSTEPS)
	var h := delta / float(substeps)
	for i in substeps:
		# `sin(angle)`, not `angle`: the small-angle form has no bound, and this
		# one makes the equilibrium exactly asin(drive) at any drive a gale can
		# produce.
		var accel := omega * omega * (drive - sin(angle)) - 2.0 * zeta * omega * rate
		rate += accel * h
		angle += rate * h
	return [angle, rate]


## Where a drive of this size holds it, in radians. The equilibrium, not the peak.
static func equilibrium(drive: float) -> float:
	return asin(clampf(drive, -1.0, 1.0))


## Turbulence: two incommensurate components in -1 .. 1, with a per-node phase so
## no two trees are hit by the same eddy.
static func buffet(t: float, hz: float, phase: float) -> float:
	var w := TAU * maxf(hz, 0.01)
	return 0.62 * sin(w * t + phase) + 0.38 * sin(w * 1.79 * t + phase * 2.7)


## A stable, distinct phase for a node, in radians.
static func phase_for(instance_id: int) -> float:
	return fposmod(float(instance_id) * 0.6180339887, 1.0) * TAU


## How long the node hangs below its own origin, in metres, from whatever mesh it
## carries. Measured rather than authored: the tyre swing's `.glb` is built with
## its origin at the hang point precisely so this is answerable.
## Walks LOCAL transforms rather than asking for `global_transform`. Two reasons,
## and the second one is the briefing's: a `global_transform` read on a node
## outside the tree is an engine ERROR line, not a null, so a unit test that
## measured a subject built with `new()` would print into a console that has to
## stay pristine.
static func hang_length(node: Node3D, fraction: float, fallback: float) -> float:
	var lowest := _lowest_point(node, Transform3D.IDENTITY)
	if lowest >= -0.01:
		return maxf(fallback, 0.01)
	return maxf(-lowest * clampf(fraction, 0.05, 1.0), 0.01)


static func _lowest_point(node: Node, into: Transform3D) -> float:
	var lowest := 0.0
	for child in node.get_children():
		var here := into
		if child is Node3D:
			here = into * (child as Node3D).transform
		if child is VisualInstance3D:
			var box: AABB = (child as VisualInstance3D).get_aabb()
			# Every corner, not just `position`: a mesh under a rotated child
			# reaches lower than its own minimum corner does once turned.
			for i in 8:
				lowest = minf(lowest, (here * box.get_endpoint(i)).y)
		lowest = minf(lowest, _lowest_point(child, here))
	return lowest


func _process(delta: float) -> void:
	if delta <= 0.0 or not is_inside_tree():
		return
	_clock += delta
	var ceiling := deg_to_rad(max_degrees)
	var lean := sin(deg_to_rad(drive_degrees))
	for node in get_tree().get_nodes_in_group(group):
		var member := node as Node3D
		if member == null or not is_instance_valid(member):
			continue
		_drive(member, delta, lean, ceiling)


func _drive(member: Node3D, delta: float, lean: float, ceiling: float) -> void:
	_ensure_member(member)
	var id := member.get_instance_id()
	var state: Array = _state[id]
	var rest: Basis = _rest[id]

	# THE WIND, IN THE PARENT'S FRAME. The tyre hangs under a tree that carries a
	# yaw of its own, and a tilt written into a node's local rotation is a tilt in
	# its parent's axes -- so a world-space wind applied without this conversion
	# swings the tyre fifteen degrees off the weather.
	var parent := member.get_parent() as Node3D
	var pull := _wind
	if parent != null:
		pull = parent.global_basis.inverse() * pull
	pull.y = 0.0
	if pull.length_squared() > 0.000001:
		pull = pull.normalized()

	var force := _strength
	if buffet_gain > 0.0:
		force *= 1.0 + buffet_gain * buffet(_clock, buffet_hz, phase_for(id))
	var omega := _omega_for(member)

	var next_x: Array = step(state[0], state[1], pull.x * lean * force, omega, damping_ratio, delta)
	var next_z: Array = step(state[2], state[3], pull.z * lean * force, omega, damping_ratio, delta)
	state[0] = clampf(next_x[0], -ceiling, ceiling)
	state[1] = next_x[1]
	state[2] = clampf(next_z[0], -ceiling, ceiling)
	state[3] = next_z[1]

	member.transform.basis = tilt_basis(state[0], state[2], hangs) * rest


func _ensure_member(member: Node3D) -> void:
	var id := member.get_instance_id()
	if _rest.has(id):
		return
	_rest[id] = member.transform.basis
	_state[id] = [0.0, 0.0, 0.0, 0.0]


## The tilt, as a basis, in the node's parent frame.
##
## A rotation about +Z carries a point BELOW the origin toward +X and a point
## ABOVE it toward -X, so a hanging thing and a standing thing want opposite
## signs for the same weather. That is the whole of `hangs`.
static func tilt_basis(angle_x: float, angle_z: float, hanging: bool) -> Basis:
	var sign := 1.0 if hanging else -1.0
	return Basis.from_euler(Vector3(-angle_z * sign, 0.0, angle_x * sign))


## Cached per node: a derived period means walking the node's meshes, and the
## rope does not get longer during a run.
func _omega_for(member: Node3D) -> float:
	if period_seconds > 0.0:
		return TAU / period_seconds
	var id := member.get_instance_id()
	if not _omega.has(id):
		_omega[id] = sqrt(GRAVITY / hang_length(member, mass_fraction, fallback_length))
	return _omega[id]


## What a node is currently tilted to, in radians, for a test or a probe.
func tilt_of(member: Node3D) -> Vector2:
	var id := member.get_instance_id()
	if not _state.has(id):
		return Vector2.ZERO
	var state: Array = _state[id]
	return Vector2(state[0], state[2])
