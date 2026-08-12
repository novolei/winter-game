class_name Crow
extends Node3D

## One bird. Sits on a wire; when something comes too close it goes.
##
## ---------------------------------------------------------------------------
## WHAT IS HERE AND WHAT IS NOT
## ---------------------------------------------------------------------------
## This is one crow's own timeline and nothing else. It does not know what the
## time of day is, how many other birds there are, where the player is, or that
## an event gets published when a flock scatters -- all of that is
## `src/entities/wildlife/crow_flock.gd`, and the split is what lets a single
## bird's departure be tested a frame at a time with no world around it.
##
## `advance()` is public and carries all the logic, the same shape `WorldClock`,
## `SurvivalSystem` and `Stove` are written in: a whole departure can be played
## out in a test in one call with no running SceneTree.
##
## **It has no `_process`, and that is deliberate.** The flock drives every bird
## from its own tick, because it has to notice the frame one becomes GONE in
## order to free it. A `_process` here as well would advance each crow twice per
## frame -- every speed, every duration and every distance in this file silently
## doubled, on a bird that is on screen for two seconds and moving fast enough
## that nobody would catch it by eye.
##
## ---------------------------------------------------------------------------
## THE DEPARTURE, WHICH IS FOUR THINGS AND NOT ONE
## ---------------------------------------------------------------------------
##   WAIT      Still on the wire, playing `look`. This is the crow's share of the
##             flock's stagger -- see crow_flock.gd's `stagger_seconds`. A row of
##             birds that all leave on the same frame reads as one object being
##             deleted; a fifth of a second between them reads as a ripple down
##             the wire, which is what actually happens.
##   LAUNCH    `take_off`, which is 29 frames just under a second. The bird holds
##             its perch through it -- the take was flattened to one root key by
##             CrowAnimations precisely so that this file decides when it leaves,
##             and it leaves at the end of the launch rather than at the start of
##             it.
##   BEAT      `fly`, accelerating along the heading. Wings working, which is
##             what a bird does when it is getting out.
##   GLIDE     `glide`, at speed. A bird that flapped all the way to the horizon
##             would read as a wind-up toy.
##
## Then it is GONE, and the flock frees it. Nothing fades: the camera is
## ORTHOGRAPHIC (Art Bible rule 1), so a bird flying away does not shrink -- it
## has to actually leave the frame, which is why `vanish_distance_m` is tens of
## metres rather than the handful a perspective camera would need.
##
## ---------------------------------------------------------------------------
## THE COLOUR, AND THE ONE PLACE IT IS NOT THE WORLD'S RULE
## ---------------------------------------------------------------------------
## Black, from the palette's darkest structure tone -- the same value Art Bible
## rule 7 gives the trees, because a crow at this framing is the same kind of
## object: a shape against snow and nothing else. The delivered pack ships six
## material variants, two of them near-white and one with a yellow beak; rule 12
## reserves warm for windows, fire, beacon, truck and scarf, and a leucistic bird
## on a snowfield is not a bird at all.
##
## The one departure from the world's shading is `snow_receptivity`. Every solid
## in this game accumulates snow on its upward faces across the seven days, and a
## crow's back is an upward face -- so by day six the flock would be white, which
## is the silhouette this whole choice exists to protect, gone. The bird is
## therefore painted by its OWN CelPainter instance (materials are cached per
## painter) so setting the receptivity to zero on it cannot reach the trees and
## roofs that share its colour.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const MODEL := preload("res://assets/models/characters/crow/crow.fbx")

## Which of the twelve. Structure, darkest -- rule 7's near-black.
const PALETTE_FAMILY := "structure"
const PALETTE_INDEX := 3

## The rig arrives facing Godot's own forward, so nothing is turned here.
##
## MEASURED, and worth writing down because the obvious reading of the data is
## the wrong one. `Rav_TakeOff`'s root track drives the CG bone +Z as the bird
## climbs, which says "the model flies +Z" -- and it does not. Godot's importer
## gives the Skeleton3D node a half-turn of its own, so bone space and model
## space disagree about Z, and a rotation applied on the strength of the track
## values would have the bird leaving tail first at eight pixels, where nobody
## would see it and everybody would believe it.
##
## The pose is the evidence, not the track: with the perch take applied, BeakTop
## sits at z = -0.151 and Tail Center at z = +0.111 in this node's own space. The
## beak is at negative Z, which is where `look_at()` points.
const MODEL_YAW := 0.0

enum State {
	PERCHED,
	WAITING,
	LAUNCHING,
	BEATING,
	GLIDING,
	GONE,
}

## How long the launch take holds the bird on its perch. `Rav_TakeOff` is 29
## frames at 30 fps.
@export var launch_seconds := 29.0 / 30.0

## How long the wings work before the bird sets them. Two seconds is about the
## time it takes to clear the farmyard.
@export var beat_seconds := 2.0

## Metres per second, off the wire and at cruise. A crow really does leave at
## about this, and at the tight framing's 10.5 m of world it crosses the picture
## in a little over a second -- which is the whole read: it is gone before you
## have decided what it was.
@export var launch_speed := 5.0
@export var cruise_speed := 12.0
@export var acceleration := 9.0

## How far it gets before it stops existing. Comfortably outside the widest
## framing stop, because an orthographic camera does not shrink it.
@export var vanish_distance_m := 55.0

## How fast it turns onto its heading once it is off the wire. A bird leaves in
## roughly the direction it was already pointing and swings onto its line; an
## instant snap to the heading reads as a teleport at this size.
@export var turn_rate := 4.0

var _state: State = State.PERCHED
var _wait := 0.0
var _elapsed := 0.0
var _heading := Vector3(0.0, 0.4, -1.0).normalized()
var _velocity := Vector3.ZERO
var _from := Vector3.ZERO
var _facing := Vector3(0.0, 0.0, -1.0)
var _player: AnimationPlayer = null
var _painter: CelPainter = null


func _ready() -> void:
	_build_rig()
	_play(CrowAnimations.PERCH)


## The bird's own painter, or one the flock hands it so a whole wire of crows
## shares one material. See the header for why it must not be the world's.
func set_painter(painter: CelPainter) -> void:
	_painter = painter


func state() -> State:
	return _state


func is_gone() -> bool:
	return _state == State.GONE


## Still on its perch AND not yet told to go.
##
## WAITING is deliberately NOT perched, and the distinction is not pedantry: a
## bird waiting out its share of the stagger is physically still on the wire, and
## a flock that counted it as perched would hand it a second heading on the very
## next frame -- which is a bird that has been told to leave twice, on two
## bearings, from a perch it is about to be fifty metres from. `is_on_the_wire()`
## is the other question, for anything that wants the picture rather than the
## intent.
func is_perched() -> bool:
	return _state == State.PERCHED


## Whether it is still standing on something. True through the stagger and the
## launch take, because it is.
func is_on_the_wire() -> bool:
	return _state == State.PERCHED or _state == State.WAITING or _state == State.LAUNCHING


## The bearing it was sent on. The flock decides it; this reports it, so the
## spread across a burst can be asserted rather than looked at.
func heading() -> Vector3:
	return _heading


## How far it has travelled since it left. For a test, and for the flock's own
## bookkeeping.
func travelled() -> float:
	return _where().distance_to(_from)


## Where the bird is, whether or not it is in a tree. Public because the flock
## measures distances against it and a flock under test is not in one either.
func where() -> Vector3:
	return _where()


## Put it on a wire, facing along it.
func perch_on(at: Vector3, facing: Vector3) -> void:
	_state = State.PERCHED
	_velocity = Vector3.ZERO
	_elapsed = 0.0
	_from = at
	_facing = _normalised(facing, Vector3(0.0, 0.0, -1.0))
	_place(at)
	_aim(_facing)
	_play(CrowAnimations.PERCH)


## Go, in `heading`, `delay` seconds from now.
##
## Refuses a bird that is already leaving: a second call would restart the
## departure and the crow would drop back onto a wire it is no longer near.
func scatter(heading: Vector3, delay := 0.0) -> bool:
	if _state != State.PERCHED:
		return false
	_heading = _normalised(heading, Vector3(0.0, 0.5, -1.0).normalized())
	_wait = maxf(delay, 0.0)
	_elapsed = 0.0
	_from = _where()
	_state = State.WAITING
	# The look is the tell. Even at nought delay it plays for the length of the
	# launch, because the launch take starts from a bird that has already noticed.
	_play(CrowAnimations.LOOK)
	return true


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _state == State.PERCHED or _state == State.GONE:
		return
	_elapsed += delta
	match _state:
		State.WAITING:
			if _elapsed >= _wait:
				_state = State.LAUNCHING
				_elapsed = 0.0
				_play(CrowAnimations.TAKE_OFF)
		State.LAUNCHING:
			if _elapsed >= launch_seconds:
				_state = State.BEATING
				_elapsed = 0.0
				_velocity = _facing * launch_speed
				_play(CrowAnimations.FLY)
		State.BEATING:
			_travel(delta)
			if _elapsed >= beat_seconds:
				_state = State.GLIDING
				_elapsed = 0.0
				_play(CrowAnimations.GLIDE)
		State.GLIDING:
			_travel(delta)
	# Only once it is actually flying. Asking a bird that is still on the wire how
	# far it has come is asking a question whose answer is always zero, and one
	# day somebody moves the perch and it stops being zero.
	if (_state == State.BEATING or _state == State.GLIDING) and travelled() >= vanish_distance_m:
		_state = State.GONE


## One frame of flight: swing onto the heading, gather speed, move.
##
## The turn is on the VELOCITY rather than on the node, so the bird's body always
## points where it is actually going. Aiming the node at the heading and letting
## the velocity catch up gives a crow flying sideways for the first half second,
## which at eight pixels reads as a glitch rather than as a bank.
func _travel(delta: float) -> void:
	var wanted := _heading * cruise_speed
	_velocity = _velocity.move_toward(wanted, acceleration * delta)
	var speed := _velocity.length()
	if speed > 0.001:
		var aim := _velocity / speed
		_facing = _facing.slerp(aim, clampf(turn_rate * delta, 0.0, 1.0))
		_aim(_facing)
	_place(_where() + _velocity * delta)


# --- the body ---------------------------------------------------------------


## Instantiates the model, hangs the take library off its AnimationPlayer, and
## paints it.
##
## Everything here is guarded rather than assumed, because a crow under test is
## built with `.new()`, has no tree and never runs `_ready()`; the state machine
## above has to work with no body at all.
func _build_rig() -> void:
	var rig := MODEL.instantiate() as Node3D
	if rig == null:
		return
	rig.name = "Rig"
	if absf(MODEL_YAW) > 0.0001:
		rig.rotate_y(MODEL_YAW)
	add_child(rig)
	_paint(rig)
	for node in rig.find_children("*", "AnimationPlayer", true, false):
		_player = node as AnimationPlayer
		break
	if _player == null:
		return
	if _player.has_animation_library(CrowAnimations.LIBRARY):
		_player.remove_animation_library(CrowAnimations.LIBRARY)
	_player.add_animation_library(CrowAnimations.LIBRARY, CrowAnimations.build())


## Every surface onto the world's two-band cel shader, in the palette's darkest
## structure tone, with the snow turned off. See the header.
func _paint(rig: Node3D) -> void:
	if _painter == null:
		_painter = CelPainter.new()
	var tone := palette_tone()
	var material := _painter.material_for(tone)
	material.set_shader_parameter("snow_receptivity", 0.0)
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var mesh := instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			instance.set_surface_override_material(surface, material)


## The bird's colour, read from the palette and never written here (briefing
## constraint 6). Public so the gate can assert what it resolved to rather than
## trusting a comment.
static func palette_tone() -> Color:
	var bible = load(PALETTE_PATH)
	if bible == null or bible.structure_tones.size() <= PALETTE_INDEX:
		return Color(0.0, 0.0, 0.0)
	return bible.structure_tones[PALETTE_INDEX]


func _play(take: StringName) -> void:
	if _player == null:
		return
	var name := "%s/%s" % [CrowAnimations.LIBRARY, take]
	if not _player.has_animation(name):
		return
	# Cross-faded rather than cut. The takes were sliced out of one long take and
	# none of them was authored to follow another, so a hard switch pops -- most
	# visibly between the perch's folded wings and the launch's open ones.
	_player.play(name, 0.12)


# --- placement, without asserting a tree ------------------------------------


## `global_position` fails an engine assertion outside the tree and answers with
## the origin, so an unguarded read does not error -- it silently says the bird is
## standing at the world origin. A crow under test is never in a tree. Out of one
## the local position IS the world position, there being no parent to compose
## with. Same reasoning as `Stove._origin_of`.
func _where() -> Vector3:
	return global_position if is_inside_tree() else position


func _place(at: Vector3) -> void:
	if is_inside_tree():
		global_position = at
	else:
		position = at


func _aim(direction: Vector3) -> void:
	if not is_inside_tree():
		return
	var flat := direction
	if absf(flat.normalized().dot(Vector3.UP)) > 0.999:
		return
	look_at(_where() + flat, Vector3.UP)


static func _normalised(direction: Vector3, fallback: Vector3) -> Vector3:
	if direction.length_squared() < 0.000001:
		return fallback
	return direction.normalized()
