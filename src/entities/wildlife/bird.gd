class_name Bird
extends Node3D

## One bird. Sits on a thin thing; when something comes too close it goes; and
## it comes back. Which bird it is, is data -- see `src/definitions/bird_species.gd`.
##
## ---------------------------------------------------------------------------
## WHAT IS HERE AND WHAT IS NOT
## ---------------------------------------------------------------------------
## This is one bird's own timeline and nothing else. It does not know what the
## time of day is, how many other birds there are, where the player is, or that
## an event gets published when a flock scatters -- all of that is
## `src/entities/wildlife/bird_flock.gd`, and the split is what lets a single
## bird's departure be tested a frame at a time with no world around it.
##
## `advance()` is public and carries all the logic, the same shape `WorldClock`,
## `SurvivalSystem` and `Stove` are written in: a whole departure can be played
## out in a test in one call with no running SceneTree.
##
## **It has no `_process`, and that is deliberate.** The flock drives every bird
## from its own tick, because it has to notice the frame one becomes GONE in
## order to free it. A `_process` here as well would advance each bird twice per
## frame -- every speed, every duration and every distance in this file silently
## doubled, on a bird that is on screen for two seconds and moving fast enough
## that nobody would catch it by eye.
##
## ---------------------------------------------------------------------------
## THIS FILE USED TO BE `crow.gd`, AND THE RENAME IS THE WHOLE POINT
## ---------------------------------------------------------------------------
## `.superpowers/sdd/wave3/task-w3-pigeon-report.md` §4.3 measured what it cost
## to add a second bird by extending the first: 209 lines, of which most were a
## near-copy of `_build_rig()` and `_play()`. The reason was a language fact --
## **GDScript will not let a subclass redeclare a parent's constant** -- so a
## bird differing only in model, colour and facing could not say so, because
## those three lived in `const MODEL`, a `static func palette_tone()` and
## `const MODEL_YAW`. Every method that read them had to be overridden.
##
## Nothing in the eight hundred lines below is about crows. It is what any bird
## that sits on a thin thing and leaves it does. So the identity moved out into
## a `BirdSpecies` resource and this became `Bird`; `Crow` and `Pigeon` are now
## six lines each, and the tenth animal is a `.tres`.
##
## ---------------------------------------------------------------------------
## THE DEPARTURE, WHICH IS FOUR THINGS AND NOT ONE
## ---------------------------------------------------------------------------
##   WAIT      Still on the wire, playing `look`. This is the bird's share of the
##             flock's stagger -- see bird_flock.gd's `stagger_seconds`. A row of
##             birds that all leave on the same frame reads as one object being
##             deleted; a fifth of a second between them reads as a ripple down
##             the wire, which is what actually happens.
##   LAUNCH    `take_off`, and THE BEAT THE OWNER ASKED FOR. It is two halves: a
##             crouch with the feet still closed on the wire, and then the body
##             RISING STRAIGHT UP with no forward speed at all. See `_lift_off()`
##             -- a bird that translates away from a wire is a decal being slid;
##             a bird that gathers, beats and comes up off the wire before it
##             goes anywhere is a bird.
##   WHEEL     `fly`, milling. The heading turns steadily about the vertical, so
##             the bird flies an arc rather than a line, and it does this for a
##             drawn number of seconds before it commits to anywhere. Crows do
##             not leave on a heading; they burst, mill, and THEN commit, and the
##             hesitation is what separates a flock from five particles with
##             velocities.
##   BEAT      `fly`, committed: the heading stops turning and the bird swings
##             onto its departure line and gathers cruise speed.
##   GLIDE     `glide`, at speed. A bird that flapped all the way to the horizon
##             would read as a wind-up toy. A species with no glide take -- the
##             rock dove flaps the whole way, which is true of the bird and is
##             all the pack authored -- simply points `glide` at `fly`.
##
## ---------------------------------------------------------------------------
## THE RETURN, WHICH IS WHAT MAKES THE VALLEY A PLACE AND NOT A SET OF PROPS
## ---------------------------------------------------------------------------
##   白天的时候乌鸦会被玩家惊飞，飞起盘旋一段时间后乌鸦还会回到随机的一个可以落脚的地方
##
## A flock that leaves and never comes back means the wires are bare from day one
## onward: the player disturbs the valley once and it stays disturbed. Being able
## to disturb something that then settles back is the difference between a world
## and a set of one-shot props.
##
##   INBOUND   `fly`, coming in from outside the frame on a curving line -- the
##             same `_mill` the departure uses, so the arrival circles once
##             before it commits, exactly as the departure hesitates before it
##             does. It aims at a point ABOVE the perch, not at the perch: a bird
##             flies to over the wire and then comes down onto it.
##   LANDING   `land`, and this is the beat nobody bothers with. See `land_flare`:
##             the take is a flare with the wings out, then a drop, then a settle,
##             and the code's own descent is timed so the feet touch the wire on
##             the frame the take's own body drops.
##
## Then PERCHED, gripping whatever it landed on -- which is drawn fresh, so a
## flock does not reassemble in the arrangement it left. That would read as a
## rewind.
##
## THE CAMERA DOES NOT COME BACK FOR THIS, deliberately. The startle earns its
## lean because it is a surprise; a landing does not, and a second camera move
## inside a minute would spend the exception the Art Bible granted. The return
## happens in the ordinary framing and the player may well miss it. Something
## happening whether or not he is watching is the point.
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
## would be stretched by it. Measured at 0.0000 m of drift against the 0.1051 m
## a once-sampled perch shows through the same squall.
##
## `ride()` costs one transform read and, on the frames where nothing moved, one
## comparison and nothing else -- which is most frames of most days, since the
## sway is zero at a strength of zero. The write is what is worth avoiding: it
## dirties this node and the whole rig under it.
##
## THE BIRD REACTS AS WELL AS TRACKS, and that is the half worth having. A bird
## on a wire that is moving under it opens its wings for balance, and above a
## harder threshold still it gives up and leaves, which is `BirdFlock`'s decision
## and uses the departure that already exists.
##
## ---------------------------------------------------------------------------
## THE COLOUR, AND THE ONE PLACE IT IS NOT THE WORLD'S RULE
## ---------------------------------------------------------------------------
## Read from the palette through `species.tone()` and never written here
## (briefing constraint 6). Art Bible rule 7's near-black for the crow, one step
## in for the dove -- a bird at this framing is a shape against snow and nothing
## else, so two species differ by VALUE rather than by hue.
##
## The one departure from the world's shading is `snow_receptivity`. Every solid
## in this game accumulates snow on its upward faces across the seven days, and a
## bird's back is an upward face -- so by day six the flock would be white, which
## is the silhouette this whole choice exists to protect, gone.
##
## That refusal goes through `CelPainter.material_for(lit, bare)`, whose `bare`
## flag is part of its CACHE KEY. The roof planes, the wires and every tree in
## the wood are all `PAL_STRUCT_4` and only some of them refuse snow, so they
## have to be two materials. Writing `snow_receptivity` onto the material
## afterwards -- which this file did first -- is precisely the defect that key
## exists to prevent: it was safe only because the bird kept a private painter,
## and the day anybody handed the flock the world's painter through
## `set_painter()` -- which exists, and is public -- every tree sharing the
## colour would have stopped taking snow, silently, in a way no gate could see.

enum State {
	PERCHED,
	WAITING,
	LAUNCHING,
	WHEELING,
	BEATING,
	GLIDING,
	GONE,
	## Coming back. See "THE RETURN" in this file's header.
	INBOUND,
	LANDING,
}

## Which bird this is. Everything below that differs between species is seeded
## from it -- see `set_species()`.
##
## Assigned before the node enters the tree: `Crow._init()` does it for a bird
## built directly, and `BirdFlock._build_bird()` does it for one the flock
## hatches. A `Bird` with none has no body and no takes, and its timeline still
## runs, which is what lets the state machine be tested with no asset at all.
@export var species: BirdSpecies = null: set = set_species

## How long the launch take runs. Seeded from the species: `Rav_TakeOff` is 29
## frames at 30 fps; `Dove_Idle to Fly` is nine at 24.
@export var launch_seconds := 29.0 / 30.0

## How much of the launch the feet are still closed on the wire.
##
## The take opens with the bird gathering -- head down, legs folding -- and only
## then drives up. Lifting from frame one would be a bird levitating out of a
## crouch it has not finished. A third of 0.93 s is 0.31 s of gather, which is
## also long enough for the wings to have opened, and the wings-out silhouette is
## about three times the perched one (measured in W3's gust frames). So the
## moment the bird actually leaves the wire is the moment it is most legible,
## which is the whole reason this beat is worth animating at all.
@export var crouch_fraction := 0.34

## How far the bird rises off the wire during the second half of the launch.
##
## THE TAKE'S OWN NUMBER, not a chosen one: `Rav_TakeOff`'s CG bone climbs
## 0.3009 m across its 29 frames. The take table flattens that root track to a
## single key -- the code owns the trajectory or the take does, never both -- so
## this is where the animator's climb comes back, driven by the file that owns
## every metre.
##
## Vertical ONLY, deliberately. The take also travels 0.3656 m forward and that
## part is NOT restored here: the owner's note is that the beat to sell is the
## body rising *before* it has any forward speed. The forward push arrives with
## the wheel, one state later.
@export var launch_climb_m := 0.30

## Metres per second: milling, and committed.
##
## `mill_speed` is deliberately well under cruise. A bird that leaves the wire at
## cruise cannot turn tightly enough to read as circling -- the wheel radius is
## speed over turn rate, so at 12 m/s and 2 rad/s it is a six-metre arc that
## looks like a wide bank rather than a mill. At 5 m/s it is under three metres,
## which at the tight framing stop's 10.5 m of frame is a shape the eye reads as
## a circle.
@export var mill_speed := 5.0
@export var cruise_speed := 12.0
@export var acceleration := 9.0

## How long the wings work after it commits, before it sets them. Two seconds is
## about the time it takes to clear the farmyard.
@export var beat_seconds := 2.0

## ---------------------------------------------------------------------------
## The return
## ---------------------------------------------------------------------------

## How high above the perch a returning bird aims before it comes down. A bird
## flies to over the wire and then lands on it; one that flew AT the wire would
## arrive along it, which is a collision course with the thing it means to stand
## on.
@export var hover_m := 2.6

## How close to that hover point it has to get before the landing take starts.
@export var flare_distance_m := 3.4

## How long the landing take runs. `Rav_Land` is 67 frames at 30 fps.
@export var land_seconds := 67.0 / 30.0

## How long an inbound bird is allowed to spend looking for its perch before it
## simply commits. A bird whose steering overshot and is circling forever would
## be one that never lands and never leaves.
@export var inbound_limit_seconds := 9.0

## WHERE IN THE LANDING TAKE THE FEET TOUCH. Seeded from the species, and
## measured off the take rather than chosen -- see `BirdSpecies.land_flare`.
@export var land_flare := 0.58

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
@export var balance_on := 0.45
@export var balance_off := 0.36

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
## The mill. `_departure` is where it will end up; `_heading` is where it is
## pointed right now, which during the wheel is turning at `_wheel_rate` rad/s
## for `_wheel_seconds`. Both zero means no wheel at all and the bird goes
## straight out, which is what every caller that does not ask for one gets.
var _departure := Vector3(0.0, 0.4, -1.0).normalized()
var _wheel_rate := 0.0
var _wheel_seconds := 0.0
var _wheeled := 0.0
## The return. The perch it is coming back to, held as the DECLARATION it came
## out of -- so a wire that sways while the bird is on its way in is still the
## wire it lands on.
var _target: Dictionary = {}
var _land_from := Vector3.ZERO
var _landed_for := 0.0
var _inbound_for := 0.0


func _ready() -> void:
	_build_rig()
	_play(BirdSpecies.PERCH)


## Adopt a species: take its beat lengths, its balance thresholds and its flare.
##
## THE SETTER RATHER THAN `_ready()`, and the difference matters. `_ready()`
## builds the rig and starts a take, so a launch already running at the crow's
## 0.933 s would have to be corrected mid-flight. Seeding here means every number
## is right before the first take plays, and a test or a capture that wants one
## bird to differ can still write over any of them afterwards, because this runs
## at assignment and nothing re-reads the species later.
##
## The species itself is never written to. `ResourceLoader` hands every caller
## the same instance (briefing trap 6), so a bird that tuned its own species
## would tune every bird of that species, including ones already in the air.
func set_species(value: BirdSpecies) -> void:
	species = value
	if value == null:
		return
	launch_seconds = value.launch_seconds
	crouch_fraction = value.crouch_fraction
	launch_climb_m = value.launch_climb_m
	land_seconds = value.land_seconds
	land_flare = value.land_flare
	mill_speed = value.mill_speed
	cruise_speed = value.cruise_speed
	balance_on = value.balance_on
	balance_off = value.balance_off


## The bird's own painter, or one the flock hands it so a whole wire shares one
## material. Safe to hand the world's, now that the snow refusal goes through the
## painter's own bare key rather than being written onto a shared material -- see
## the header.
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


## Wings out, holding on. See `balance_on`.
func is_balancing() -> bool:
	return _balancing


## Milling -- off the wire and not yet committed to anywhere.
func is_wheeling() -> bool:
	return _state == State.WHEELING


## Off the wire entirely, whatever it is doing up there.
func is_flying() -> bool:
	return _is_flying()


## Whether its feet are still closed on something. True through the stagger and
## through the CROUCH at the start of the launch, and false from the moment the
## rise begins -- which is a different question from `is_on_the_wire()`, and the
## difference is the whole of the take-off beat.
func has_feet_down() -> bool:
	return _feet_down()


## Where it will end up, once it has finished making up its mind. The flock
## decides it; `heading()` is where the bird is pointed right now, which during
## the mill is somewhere else entirely.
func departure() -> Vector3:
	return _departure


## Radians a second, signed, and for how long. Reported so a test can assert the
## mill rather than watch for it.
func wheel_rate() -> float:
	return _wheel_rate


func wheel_seconds() -> float:
	return _wheel_seconds


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
	_play(BirdSpecies.PERCH)


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


## Go, in `heading`, `delay` seconds from now -- milling for `wheel_seconds`
## first, turning at `wheel_rate` radians a second (signed: the sign is which way
## round it circles).
##
## Both wheel arguments default to zero, which is no mill at all: the bird leaves
## the launch already pointed at `heading` and flies straight out. Every caller
## that does not ask for a wheel therefore gets exactly the departure this file
## shipped before, which is what keeps the mill a decision the FLOCK makes rather
## than something every test has to opt out of.
##
## Refuses a bird that is already leaving: a second call would restart the
## departure and the bird would drop back onto a wire it is no longer near.
func scatter(heading: Vector3, delay := 0.0, wheel_rate := 0.0, wheel_seconds := 0.0) -> bool:
	if _state != State.PERCHED:
		return false
	_departure = _normalised(heading, Vector3(0.0, 0.5, -1.0).normalized())
	_heading = _departure
	_wheel_rate = wheel_rate if is_finite(wheel_rate) else 0.0
	_wheel_seconds = maxf(wheel_seconds, 0.0) if is_finite(wheel_seconds) else 0.0
	_wheeled = 0.0
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
	_play(BirdSpecies.LOOK)
	return true


## Come back, to `perch`, entering the world at `from`.
##
## `wheel_rate` and `wheel_seconds` are the same two numbers the departure takes
## and mean the same thing: the arrival curves in rather than flying a straight
## line at the wire. A bird that came in on a ruler would read as a projectile.
func approach(perch: Dictionary, from: Vector3, wheel_rate := 0.0, wheel_seconds := 0.0) -> bool:
	if not perch.has("at"):
		return false
	_target = perch.duplicate()
	_state = State.INBOUND
	_anchor = null
	_balancing = false
	_velocity = Vector3.ZERO
	_elapsed = 0.0
	_inbound_for = 0.0
	_landed_for = 0.0
	_wheel_rate = wheel_rate if is_finite(wheel_rate) else 0.0
	_wheel_seconds = maxf(wheel_seconds, 0.0) if is_finite(wheel_seconds) else 0.0
	_wheeled = 0.0
	_from = from
	_place(from)
	var toward := _hover_point() - from
	_heading = _normalised(toward, Vector3(0.0, 0.0, -1.0))
	_facing = _normalised(Vector3(toward.x, 0.0, toward.z), Vector3(0.0, 0.0, -1.0))
	_departure = _heading
	_aim(_facing)
	_velocity = _heading * mill_speed
	_play(BirdSpecies.FLY)
	return true


## Think better of it and leave, wherever it had got to. What a flock does when
## the man is still standing under the wire it was coming back to -- a bird that
## landed and burst on the next frame is a loop the player can see.
func give_up() -> bool:
	if _state != State.INBOUND and _state != State.LANDING:
		return false
	_target = {}
	_anchor = null
	_state = State.GLIDING
	_elapsed = 0.0
	_from = _where()
	var away := _normalised(Vector3(_facing.x, 0.0, _facing.z), Vector3(0.0, 0.0, -1.0))
	_heading = (away + Vector3.UP * 0.36).normalized()
	_departure = _heading
	_wheel_rate = 0.0
	_wheel_seconds = 0.0
	_play(BirdSpecies.GLIDE)
	return true


## On its way back, and not yet down.
func is_inbound() -> bool:
	return _state == State.INBOUND


## Flaring onto a perch.
func is_landing() -> bool:
	return _state == State.LANDING


## Where it is headed, or ZERO for a bird that is not coming back to anywhere.
func target_perch() -> Vector3:
	return _target.get("at", Vector3.ZERO) if not _target.is_empty() else Vector3.ZERO


## The perch resolved on THIS frame. A wire sways while a bird is on its way in,
## so a landing aimed at where the wire was when the flock decided to come back
## would put the bird beside it -- the same defect `ride()` exists to fix, one
## step earlier in the story.
func _perch_now() -> Vector3:
	var anchor := _target.get("anchor", null) as PerchPoints
	if anchor != null and is_instance_valid(anchor):
		return anchor.placement() * (_target.get("local", Vector3.ZERO) as Vector3)
	return _target.get("at", Vector3.ZERO)


func _hover_point() -> Vector3:
	return _perch_now() + Vector3.UP * hover_m


## One frame of coming in: curve, then steer at the hover point.
func _fly_in(delta: float) -> void:
	_inbound_for += delta
	if _wheeled < _wheel_seconds:
		_mill(delta)
	else:
		# Steer at the point above the perch, not at the perch.
		_heading = _normalised(_hover_point() - _where(), _heading)
	_travel(delta, mill_speed)


func _close_enough_to_flare() -> bool:
	if _wheeled < _wheel_seconds and _inbound_for < inbound_limit_seconds:
		return false
	return _where().distance_to(_hover_point()) <= flare_distance_m \
		or _inbound_for >= inbound_limit_seconds


func _start_landing() -> void:
	_state = State.LANDING
	_landed_for = 0.0
	_land_from = _where()
	_velocity = Vector3.ZERO
	_facing = _normalised(
		Vector3(_target.get("facing", _facing).x, 0.0, (_target.get("facing", _facing) as Vector3).z),
		_facing
	)
	_aim(_facing)
	_play(BirdSpecies.LAND)


## One frame of the flare. Eased in, so the bird arrives slowing rather than
## dropping at a constant rate, and it is ON the perch at `land_flare` -- the
## instant the take's own body comes down.
func _flare(delta: float) -> void:
	_landed_for += delta
	var touchdown := maxf(land_seconds * land_flare, 0.001)
	var through := clampf(_landed_for / touchdown, 0.0, 1.0)
	_place(_land_from.lerp(_perch_now(), smoothstep(0.0, 1.0, through)))
	if _landed_for < land_seconds:
		return
	# Down, and holding on. `grip` re-reads the declaration, so from here the bird
	# rides the wire like any other.
	grip(_target)
	_target = {}


## One frame of standing on something that is moving.
##
## Two jobs, both only while the bird is still on the wire: follow whatever it is
## gripping, and decide whether the wind is hard enough to need its wings out.
## Driven from `BirdFlock`, like `advance()`, and for the same reason -- see this
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
	# ONCE THE FEET ARE OFF, THE WIRE IS NOTHING TO DO WITH IT. `is_on_the_wire()`
	# stays true through the whole launch take because the bird is still standing
	# there for the first third of it -- but the last two thirds are the rise, and
	# a bird being pulled back down onto the wire it just left is the rise cancelled
	# every frame.
	if not _feet_down():
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


## Wings out to hold on, and down again when the gust passes. See `balance_on`
## for where the two numbers came from.
##
## PERCHED only. A bird in WAITING is playing `look` and one in LAUNCHING is
## playing `take_off`; starting a balance take over either would cut the
## departure's own animation off, and the departure is the thing anybody actually
## sees.
##
## A species with no wings-out-on-the-perch take points its `flap` role at
## whatever comes closest -- the dove has nothing that opens its wings with its
## feet closed, so it plays `take_off` unlooped and holds the last frame. That is
## a held pose rather than a beat, and it is written down rather than dressed up.
func _balance(wind_strength: float) -> void:
	if _state != State.PERCHED:
		return
	if not _balancing and wind_strength >= balance_on:
		_balancing = true
		_play(BirdSpecies.FLAP)
	elif _balancing and wind_strength <= balance_off:
		_balancing = false
		_play(BirdSpecies.PERCH)


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _state == State.PERCHED or _state == State.GONE:
		return
	_elapsed += delta
	match _state:
		State.WAITING:
			if _elapsed >= _wait:
				_state = State.LAUNCHING
				_elapsed = 0.0
				_play(BirdSpecies.TAKE_OFF)
		State.LAUNCHING:
			_lift_off(delta)
			if _elapsed >= launch_seconds:
				# The bird arrives at the wheel already climbing, and keeps that
				# climb. Overwriting `_velocity` here -- which this file did, with
				# `_facing * launch_speed` -- threw the rise away on the frame it
				# finished and put a horizontal step in its place, so the lift and
				# the flight were two motions with a seam rather than one arc.
				_state = State.WHEELING
				_elapsed = 0.0
				# It leaves pointed the way it was standing, climbing. Whatever the
				# flock decided is `_departure`, and it will not be pointed there
				# until the mill has run.
				_heading = _normalised(
					Vector3(_facing.x, 0.0, _facing.z).normalized() + Vector3.UP * 0.45,
					_departure
				)
				_play(BirdSpecies.FLY)
		State.WHEELING:
			_mill(delta)
			_travel(delta, mill_speed)
			if _wheeled >= _wheel_seconds:
				_state = State.BEATING
				_elapsed = 0.0
				# Committed. `_travel` swings the velocity onto it at `turn_rate`
				# rather than snapping, so the moment of deciding reads as the arc
				# opening out rather than as a corner.
				_heading = _departure
		State.BEATING:
			_travel(delta, cruise_speed)
			if _elapsed >= beat_seconds:
				_state = State.GLIDING
				_elapsed = 0.0
				_play(BirdSpecies.GLIDE)
		State.GLIDING:
			_travel(delta, cruise_speed)
		State.INBOUND:
			_fly_in(delta)
			if _close_enough_to_flare():
				_start_landing()
		State.LANDING:
			_flare(delta)
	# Only once it is actually flying AWAY. An inbound bird has travelled a long
	# way from where it entered and is not leaving; asking it the departure's
	# question would delete it on the approach.
	if _is_flying() and travelled() >= vanish_distance_m:
		_state = State.GONE


## Whether the feet are still closed on something. True on the perch, true
## through the stagger, and true for the crouch at the start of the launch --
## which is the whole reason this is a method and not `_state == PERCHED`.
func _feet_down() -> bool:
	if _state == State.PERCHED or _state == State.WAITING:
		return true
	if _state == State.LAUNCHING:
		return _elapsed < launch_seconds * clampf(crouch_fraction, 0.0, 1.0)
	# The tail of the landing take, after the feet have touched: the bird is
	# standing on the wire folding itself up, and if the wind moves the wire it has
	# to go with it.
	if _state == State.LANDING:
		return _landed_for >= land_seconds * land_flare
	return false


## Off the wire and going somewhere ELSE. Deliberately not "in the air": an
## inbound bird is in the air and is the one thing here that must not be measured
## against `vanish_distance_m`.
func _is_flying() -> bool:
	return _state == State.WHEELING or _state == State.BEATING or _state == State.GLIDING


## THE BEAT THE OWNER ASKED FOR: the body coming up off the wire before it has
## any forward speed.
##
## The first `crouch_fraction` of the take is the gather and the bird does not
## move at all -- `_feet_down()` is true and `ride()` is still holding it on a
## wire that may be swaying. After that it rises, and only rises: no component of
## this is horizontal.
##
## The climb RAMPS rather than being constant, so the bird accelerates off the
## wire instead of stepping off it. Ramping from zero over the lift window `T` at
## a peak rate `v` covers `v*T/2`, so `v` is twice the height over the window --
## which is where `launch_climb_m` turns into a speed. The bird therefore hands
## the wheel a velocity that is already climbing at `v`, and nothing has to paper
## over a seam because there is not one.
func _lift_off(delta: float) -> void:
	if _feet_down():
		return
	var crouch := launch_seconds * clampf(crouch_fraction, 0.0, 1.0)
	var window := maxf(launch_seconds - crouch, 0.0001)
	var through := clampf((_elapsed - crouch) / window, 0.0, 1.0)
	var peak := 2.0 * launch_climb_m / window
	_velocity = Vector3.UP * (peak * through)
	_place(_where() + _velocity * delta)


## One frame of the mill: turn the heading about the vertical.
##
## The HEADING is what turns, not the velocity. `_travel` then chases the heading
## at `acceleration`, which is what bends the path into an arc instead of a
## polyline -- a bird whose velocity was rotated directly would trace a perfect
## circle, which is the one thing a wheeling flock never does.
func _mill(delta: float) -> void:
	if _wheel_seconds <= 0.0 or absf(_wheel_rate) < 0.0001:
		_wheeled = _wheel_seconds
		return
	var step := minf(delta, _wheel_seconds - _wheeled)
	_wheeled += delta
	_heading = _heading.rotated(Vector3.UP, _wheel_rate * step).normalized()


## One frame of flight: swing onto the heading, gather speed, move.
##
## The turn is on the VELOCITY rather than on the node, so the bird's body always
## points where it is actually going. Aiming the node at the heading and letting
## the velocity catch up gives a bird flying sideways for the first half second,
## which at eight pixels reads as a glitch rather than as a bank.
func _travel(delta: float, speed_target: float) -> void:
	var wanted := _heading * speed_target
	_velocity = _velocity.move_toward(wanted, acceleration * delta)
	var speed := _velocity.length()
	if speed > 0.001:
		var aim := _velocity / speed
		_facing = _facing.slerp(aim, clampf(turn_rate * delta, 0.0, 1.0))
		_aim(_facing)
	_place(_where() + _velocity * delta)


# --- the body ---------------------------------------------------------------


## Instantiates the model, hangs the species' take library off its
## AnimationPlayer, and paints it.
##
## THIS IS THE METHOD THE OLD DESIGN COULD NOT SHARE. `Crow` named its model in a
## `const preload` and its facing in a `const`, and GDScript forbids a subclass
## redeclaring either -- so `Pigeon._build_rig()` was a near-copy of this
## differing in three identifiers. Every one of those three is now a field on
## `species`, and this method is the only one.
##
## Everything is guarded rather than assumed, because a bird under test is built
## with `.new()`, has no tree and never runs `_ready()`; the state machine above
## has to work with no body at all.
func _build_rig() -> void:
	if species == null:
		return
	var model := species.model()
	if model == null:
		return
	var rig := model.instantiate() as Node3D
	if rig == null:
		return
	rig.name = "Rig"
	if absf(species.model_yaw) > 0.0001:
		rig.rotate_y(species.model_yaw)
	add_child(rig)
	_paint(rig)
	for node in rig.find_children("*", "AnimationPlayer", true, false):
		_player = node as AnimationPlayer
		break
	if _player == null:
		return
	if _player.has_animation_library(species.library):
		_player.remove_animation_library(species.library)
	_player.add_animation_library(species.library, BirdAnimations.build(species))


## The material this bird wears: its species' palette tone on the world's
## two-band cel shader, keyed BARE so no snow ever settles on it.
##
## `bare` goes through `material_for`'s cache key rather than being written onto
## the material afterwards -- see the header. That is what makes a bird safe to
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
## constraint 6). Public so a gate can assert what it resolved to rather than
## trusting a comment.
##
## AN INSTANCE METHOD, WHICH IT HAD TO BECOME. `Crow.palette_tone()` was static,
## and a static does not dispatch through an instance -- so `Crow.material()`
## called the crow's tone even on a pigeon, and `Pigeon` had to override
## `material()` as well as the tone to get its own colour. That is two of the
## five overrides the second bird paid for, gone.
func palette_tone() -> Color:
	return species.tone() if species != null else Color(0.0, 0.0, 0.0)


## Play the take that this species uses for `role`.
##
## THE INDIRECTION IS THE FEATURE. The timeline asks for a MOTION -- "the perch
## take" -- and `species.roles` says what the delivery calls it. That is what
## replaced `Pigeon.TRANSLATION` and the `_play()` override that read it: a
## species whose glide is its flight cycle says so in one row of a `.tres`.
##
## Silent when the species has no take for the role, which is deliberate: a bird
## with no balance take should keep doing what it was doing, not fall back to
## something wrong.
func _play(role: StringName) -> void:
	if _player == null or species == null:
		return
	var take := species.take_for(role)
	if take == &"":
		return
	var name := "%s/%s" % [species.library, take]
	if not _player.has_animation(name):
		return
	# Cross-faded rather than cut. No take in either pack was authored to follow
	# another, so a hard switch pops -- most visibly between the perch's folded
	# wings and the launch's open ones.
	_player.play(name, 0.12)


# --- placement, without asserting a tree ------------------------------------


## `global_position` fails an engine assertion outside the tree and answers with
## the origin, so an unguarded read does not error -- it silently says the bird is
## standing at the world origin. A bird under test is never in a tree. Out of one
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
