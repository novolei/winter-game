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
## STANDING ON A WIRE THAT MOVES
## ---------------------------------------------------------------------------
## `src/rendering/wind_sway.gd` slides every span up to 0.14 m across the wind
## once a frame. A bird placed from a perch position sampled at landing is
## therefore wrong from the next frame onward, and at the tight framing stop --
## crow 26 px, wire a one-to-two-pixel stroke -- 0.14 m is a bird standing on
## nothing.
##
## So the bird holds the DECLARATION rather than the position: `grip()` keeps the
## `PerchPoints` that offered the perch and the place on it in that node's own
## basis, and `ride()` resolves the two afresh. It is not parented to the wire,
## because `Farmstead._span()` puts `scale.z = length` on the span and a child
## would be stretched by it.
##
## `ride()` costs one transform read and, on the frames where nothing moved, one
## comparison and nothing else -- which is most frames of most days, since the
## sway is zero at a strength of zero. The write is what is worth avoiding: it
## dirties this node and the whole rig under it.
##
## THE BIRD REACTS AS WELL AS TRACKS, and that is the half worth having. Wave 2
## imported `flap` (Malbers' `Rav_Fly_Stand` -- wings worked without leaving the
## perch) and never played it. A crow on a wire that is moving under it opens its
## wings for balance, and above a harder threshold still it gives up and leaves,
## which is `CrowFlock`'s decision and uses the departure that already exists.
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
## is the silhouette this whole choice exists to protect, gone.
##
## That refusal now goes through the mechanism the roof work built rather than
## through a private one. `CelPainter.material_for(lit, bare)` takes `bare` as
## part of its CACHE KEY -- the roof planes, the wires and every tree in the wood
## are all `PAL_STRUCT_4` and only some of them refuse snow, so they have to be
## two materials. Writing `snow_receptivity` onto the material afterwards, which
## is what this file did first, is precisely the defect that key exists to
## prevent: it was safe only because the bird kept a private painter, and the day
## anybody handed the flock the world's painter through `set_painter()` -- which
## exists, and is public -- every tree sharing `#131C30` would have stopped
## taking snow, silently, in a way no gate could see.
##
## The crow does not carry the `_BARE` slot NAME, because that name is written by
## `tools/blender/propkit.py` into a `.glb`'s material and the crow is an FBX
## from a third-party pack whose material is called `01 - Default`. The name is
## how a Blender-built prop asks; the argument is what it asks for.

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

## The wind at which a perched bird opens its wings for balance, and the weaker
## wind at which it settles again.
##
## MEASURED, not chosen. Swept over an hour of each shipped profile, a latch at
## 0.45 on / 0.36 off holds 10.8 per cent of the time on `wind_valley` -- the
## `pale_day` wind, and the only one a daylight bird lives in -- in stretches
## averaging 8.3 s. Long enough to read; rare enough to stay an event. On
## `wind_calm` (`flat` and `sunrise`) the wind never reaches 0.45 at all and the
## bird simply sits, which is what a still bright morning should look like.
##
## The band between them is the hysteresis, and it is not decoration: `_play()`
## restarts the take every call, so a strength jittering across one threshold
## would be a bird vibrating rather than a bird balancing.
const BALANCE_ON := 0.45
const BALANCE_OFF := 0.36

var _state: State = State.PERCHED
var _wait := 0.0
var _elapsed := 0.0
var _heading := Vector3(0.0, 0.4, -1.0).normalized()
var _velocity := Vector3.ZERO
var _from := Vector3.ZERO
var _facing := Vector3(0.0, 0.0, -1.0)
var _player: AnimationPlayer = null
var _painter: CelPainter = null
var _material: ShaderMaterial = null
## What it is standing on, where on it, and which way along it -- see `grip()`.
## Null for a bird placed straight onto a position, which is what a capture and
## most of the unit tests do.
var _anchor: PerchPoints = null
var _anchor_local := Vector3.ZERO
var _anchor_local_facing := Vector3(0.0, 0.0, -1.0)
var _anchor_seen := Transform3D()
var _balancing := false


func _ready() -> void:
	_build_rig()
	_play(CrowAnimations.PERCH)


## The bird's own painter, or one the flock hands it so a whole wire of crows
## shares one material. Safe to hand the world's, now that the snow refusal goes
## through the painter's own bare key rather than being written onto a shared
## material -- see the header.
func set_painter(painter: CelPainter) -> void:
	_painter = painter
	# Whatever was already resolved came from the previous painter.
	_material = null


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


## Which way its beak points. Flat, always -- a perched bird stands upright on a
## sloping wire rather than pointing its beak up the hill.
func facing() -> Vector3:
	return _facing


## Wings out, holding on. See BALANCE_ON.
func is_balancing() -> bool:
	return _balancing


## The declaration it is standing on, or null for a bird placed at a position.
func anchor() -> PerchPoints:
	return _anchor


## How far it has travelled since it left. For a test, and for the flock's own
## bookkeeping.
func travelled() -> float:
	return _where().distance_to(_from)


## Where the bird is, whether or not it is in a tree. Public because the flock
## measures distances against it and a flock under test is not in one either.
func where() -> Vector3:
	return _where()


## Put it on a wire, facing along it.
##
## A position and nothing else, so the bird knows WHERE it is standing and not
## WHAT on. That is enough for a capture that wants a bird at a chosen spot, and
## it is not enough for a wire in a gust -- see `grip()`.
func perch_on(at: Vector3, facing: Vector3) -> void:
	_state = State.PERCHED
	_velocity = Vector3.ZERO
	_elapsed = 0.0
	_from = at
	_facing = _normalised(facing, Vector3(0.0, 0.0, -1.0))
	_anchor = null
	_balancing = false
	_place(at)
	_aim(_facing)
	_play(CrowAnimations.PERCH)


## Take hold of a perch a prop declared -- `{at, facing, anchor, local,
## local_facing}` out of `PerchPoints.perches()`.
##
## The bird keeps the DECLARATION and the place on it, not the world position, so
## `ride()` can put it back on the wire every frame the wind moves one. A
## dictionary with no `anchor` -- a capture's hand-made perch, a test's stand-in
## wire -- degrades to `perch_on()` and simply does not ride.
func grip(perch: Dictionary) -> void:
	perch_on(
		perch.get("at", Vector3.ZERO),
		perch.get("facing", Vector3(0.0, 0.0, -1.0))
	)
	var declaration := perch.get("anchor", null) as PerchPoints
	if declaration == null or not is_instance_valid(declaration):
		return
	_anchor = declaration
	_anchor_local = perch.get("local", Vector3.ZERO)
	_anchor_local_facing = _normalised(
		perch.get("local_facing", Vector3(0.0, 0.0, -1.0)), Vector3(0.0, 0.0, -1.0)
	)
	_anchor_seen = _anchor.placement()


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
	# Wings down and the flag cleared before the departure's own takes start, so
	# a bird that was balancing when it was told to go does not carry the balance
	# into its launch and does not have `look` cut off by the next gust reading.
	_balancing = false
	# The look is the tell. Even at nought delay it plays for the length of the
	# launch, because the launch take starts from a bird that has already noticed.
	_play(CrowAnimations.LOOK)
	return true


## One frame of standing on something that is moving.
##
## Two jobs, both only while the bird is still on the wire: follow whatever it is
## gripping, and decide whether the wind is hard enough to need its wings out.
## Driven from `CrowFlock`, like `advance()`, and for the same reason -- see this
## file's note on why there is no `_process` here.
func ride(wind_strength := 0.0) -> void:
	if not is_on_the_wire():
		return
	_follow_the_anchor()
	_balance(wind_strength)


## Put the bird back on the wire, if the wire has gone anywhere.
##
## THE COMPARISON IS THE POINT. Writing `global_position` dirties this node and
## the whole rig beneath it, so on a still day -- and `WireSway` returns exactly
## zero at a strength of zero, which is most of most days -- the cheap thing is
## to notice nothing moved and stop.
##
## The comparison is on the WHOLE transform, not on its origin. Written that way
## first, and it is wrong for the one case the re-aim exists for: turning a prop
## about its own origin leaves the origin exactly where it was while moving every
## perch on it, so an origin-only check skips the frame and the bird stays where
## the prop used to point.
func _follow_the_anchor() -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		return
	var now := _anchor.placement()
	if now.is_equal_approx(_anchor_seen):
		return
	var turned := not now.basis.is_equal_approx(_anchor_seen.basis)
	_anchor_seen = now
	_from = now * _anchor_local
	_place(_from)
	if not turned:
		return
	# Only when the prop actually turned. `WireSway` never rotates a span --
	# rotating a straight segment about its own chord is a no-op, which is why
	# that file settled on a rigid slide -- so in the shipped game this branch
	# does not run, and `test_a_wire_that_only_slides_does_not_turn_the_bird`
	# is the measurement rather than the claim. It is here because a perch that
	# followed a prop's position but not its heading would be a bird standing
	# sideways on a wire the day anything does turn one.
	var aimed := now.basis * _anchor_local_facing
	_facing = _normalised(Vector3(aimed.x, 0.0, aimed.z), _facing)
	_aim(_facing)


## Wings out to hold on, and down again when the gust passes. See BALANCE_ON for
## where the two numbers came from.
##
## PERCHED only. A bird in WAITING is playing `look` and one in LAUNCHING is
## playing `take_off`; starting a balance take over either would cut the
## departure's own animation off, and the departure is the thing anybody actually
## sees.
func _balance(wind_strength: float) -> void:
	if _state != State.PERCHED:
		return
	if not _balancing and wind_strength >= BALANCE_ON:
		_balancing = true
		_play(CrowAnimations.FLAP)
	elif _balancing and wind_strength <= BALANCE_OFF:
		_balancing = false
		_play(CrowAnimations.PERCH)


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


## The material this bird wears: the palette's darkest structure tone on the
## world's two-band cel shader, keyed BARE so no snow ever settles on it.
##
## `bare` goes through `material_for`'s cache key rather than being written onto
## the material afterwards -- see the header. That is what makes the crow safe to
## share a painter with the trees, which are the same colour and do take snow.
func material() -> ShaderMaterial:
	if _material != null:
		return _material
	if _painter == null:
		_painter = CelPainter.new()
	_material = _painter.material_for(palette_tone(), true)
	return _material


## Every surface onto that material. See the header.
func _paint(rig: Node3D) -> void:
	var material := material()
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
