class_name StartleShot
extends Node

## The camera, for the two or three seconds the crows go up.
##
## ---------------------------------------------------------------------------
## WHAT WAS ASKED FOR, IN THE OWNER'S OWN WORDS
## ---------------------------------------------------------------------------
##   当乌鸦被惊飞的时候，默认的摄像机只要自动动画聚焦到乌鸦起飞的范围内就好了，
##   不要对玩家角色做任何的操作，动画播放完毕后自动恢复到摄像机原位置
##
## The camera animates to frame the take-off, holds, and animates home. **The
## player is never touched** -- no body turn, no control taken, no input blocked.
##
## AND THAT IS THE BETTER DESIGN, not a fallback. It fires on PROXIMITY, so it
## happens many times across seven days: anything that moved his body would be
## charming once and would feel like the game grabbing him by the tenth. Because
## he keeps agency the moment stays "something happened in the world" rather than
## "the game played me a clip" -- which is the grammar the GDD's third pillar,
## 沉默即叙事, asks for. And it can be MISSED, which is correct and is the same
## principle as the flock coming back to a wire he never looks at.
##
## ---------------------------------------------------------------------------
## THE FENCE, UNAMENDED
## ---------------------------------------------------------------------------
## Art Bible rule 1 is 永不旋转，只跟随 and this is its one approved exception. All
## five of the Director's conditions apply as written:
##
##   1. 短                two or three seconds       `shot_seconds_min/max`
##   2. 不夺取控制权       nothing here touches the   there is no call into the
##                        player at all              player in this file
##   3. 不切镜头，只倾斜    eased out and eased back   `_curve`, and the fact that
##                                                   nothing writes `rotation`
##   4. 精确回到原处       bit for bit                `CameraRig.set_lean(ZERO)`
##   5. 稀有              a cooldown                 `cooldown_seconds`
##
## Condition 4 decides the shape of this file. It never writes the camera's
## pitch, yaw or size; it writes OFFSETS, and offsets that return to exactly zero
## return the rig to `base_rotation()`, which is recomputed from the exports
## rather than restored from a snapshot. There is no remembered float to drift,
## and the push goes through `CameraRig`'s `ModifierStack` under this file's own
## source id, so the player's Shift+wheel stop stays the base and comes back
## untouched.
##
## ---------------------------------------------------------------------------
## SHIFT AND WIDEN -- DO NOT LOSE THE MAN
## ---------------------------------------------------------------------------
## He is free to keep walking, and most players will walk straight through the
## trigger without stopping. A camera that travelled off to watch the birds would
## leave him off-frame and walking into things he cannot see, which is a good
## shot and a bad game.
##
## So the move is a SHIFT AND A WIDEN rather than a journey. Three things happen
## together and each is bounded by the requirement that both stay in the picture:
##
##   the aim slides PART OF THE WAY toward the flock (`frame_share`, under a half)
##   the frame WIDENS (`widen_min/max`, always > 1) instead of pushing in
##   the pitch comes up off the isometric 45, which is what actually buys the
##   room: a world offset of `d` along the ground and `h` up projects to
##   `d*sin(p) + h*cos(p)` of frame height, so a shallower pitch spends less of
##   the frame on the ground between him and the birds
##
## `frames_both()` is the check, and `test_startle_shot.gd` walks him THROUGH the
## trigger at a walk without stopping and asserts he never leaves the picture --
## because that is what most players will do and it is not the case that is easy
## to get right.
##
## ---------------------------------------------------------------------------
## "每一次都不一样" IS PROCEDURAL, NOT A SHELF OF SHOTS
## ---------------------------------------------------------------------------
## A canned sequence played at random is seen through in three viewings. Every
## axis is a draw from a bounded range, so the variation is continuous:
##
##   鸟的数量                  CrowFlock draws 1..5
##   盘旋的方向与圈数           one direction per burst, a rate per bird
##   决定航向前犹豫多久         each bird's hesitation
##   镜头推进的紧密程度         `widen_min/max`
##   哪几声叫、在什么时刻       CrowCalls draws the schedule
##
## and this file adds three of its own: how long it runs, how far the pitch comes
## up, and how much of the frame is given to the birds against the man.
##
## ---------------------------------------------------------------------------
## ORTHOGRAPHIC, AND THE ONE THING THAT CANNOT BE HAD
## ---------------------------------------------------------------------------
## The ruling permits blending to perspective. Measured (see
## `.superpowers/sdd/wave3/startle/a-perspective.png`): matched to the parallel
## frame at the subject plane, a perspective camera loses the birds -- everything
## behind the subject converges away and the flock shrinks to nothing -- and it
## loses the aerial-perspective wash that makes them read dark against bright.
## `Camera3D.projection` is a hard enum with no blend either. So the projection
## stays parallel, and the ruling's own preference applies: drop the perspective
## rather than the no-cut rule.
##
## THE COMPOSITION NOTE ASKED FOR SKY BEHIND THEM, AND THAT CANNOT BE HAD HERE.
## Under a parallel projection every ray is parallel and pitched downward, so
## every one of them meets the ground plane: there is no horizon in an
## orthographic frame that looks below level. Measured at three pitches --
## 29, 14 and 8 degrees below level -- the sky filled 0.0, 0.1 and 0.0 per cent
## of the frame. Raising the pitch does not fix it; only looking ABOVE level
## would, and that loses the man entirely.
##
## What the shot has instead is distant snow washed by fog almost to sky value,
## and the pitch does buy that: the same instrument reports the upper half of the
## frame brightening by +7.2 and +13.2 per cent between the game framing and the
## peak of the move. Dark birds on a bright field, in the game's own palette,
## rather than dark birds on sky. Stated rather than tuned away.

## This file's name on the framing stack. Removing by source is how the push
## comes off: precise, and nothing of this file's can be left behind.
const SOURCE := &"startle_shot"

## ---------------------------------------------------------------------------
## A FRESHLY SEEDED RandomNumberGenerator IS NOT RANDOM YET
## ---------------------------------------------------------------------------
## MEASURED on 4.7.1, six seeds chosen to be far apart (3, 41, 4711, 20260812,
## 31337, 9001), first five `randf()` from each:
##
##   draw #1  0.4995  0.7676  0.2199  0.0745  0.5181  0.5574   spread
##   draw #2  0.7149  0.3765  0.4632  0.5112  0.2706  0.5143   spread
##   draw #3  0.3371  0.3090  0.0094  0.0214  0.7392  0.9827   spread
##   draw #4  0.2396  0.1004  0.1787  0.1662  0.1978  0.0931   <-- ALL IN 0.09..0.24
##   draw #5  0.8476  0.2219  0.3913  0.4240  0.1052  0.3865   spread
##
## Six independent uniforms all in the bottom quarter is a one-in-four-thousand
## coincidence, so it is not one: the fourth draw after `seed = N` is
## systematically low.
##
## It cost this file a real defect of exactly the shape that survives review. The
## push was the fourth thing drawn, so the camera pushed to 0.814..0.836 of the
## framing every time out of a declared 0.80..0.95 -- the shot still worked, three
## of its axes still varied, and the fourth quietly had a quarter of the range its
## own exports advertised. Nothing errors. Hashing the seed and discarding a few
## draws fixes it; measured again after, the fourth draw runs 0.2490..0.8471.
##
## Worth knowing for anything in this project that draws a small fixed number of
## values immediately after seeding.
const RNG_WARMUP := 8

## ---------------------------------------------------------------------------
## The trigger
## ---------------------------------------------------------------------------

## How close he has to get, flat, to a flock that is actually sitting there.
##
## MUST BE WIDER THAN `CrowFlock.flush_radius_m` (8 m), or the birds burst on
## their own before the camera has moved and the sequence is watching an empty
## wire. Twelve gives the dolly-in about two and a half seconds of his walk to
## complete in, at a metre and a half a second.
@export var trigger_radius_m := 12.0

## The ruling's 稀有. With a proximity trigger the COOLDOWN is what makes it rare
## rather than a coin flip -- a range trigger that sometimes does nothing is a
## feature he cannot find again, which is the opposite of what he asked for. A
## flock is already rare (40..110 s of quiet, and he has to walk to it), so this
## is the rarity on top of that.
@export var chance := 1.0
@export var cooldown_seconds := 100.0

## ---------------------------------------------------------------------------
## The move
## ---------------------------------------------------------------------------

## Two or three seconds, drawn per shot. Long enough for a launch (0.93 s) and
## most of a mill; longer and it stops being 注意到 and becomes 被打断.
@export var shot_seconds_min := 2.4
@export var shot_seconds_max := 3.2

## How far below level the camera comes up to, in degrees, against the rig's own
## 45. Shallower is what buys the room the frame needs: a world offset of `d`
## along the ground and `h` up projects to `d*sin(p) + h*cos(p)` of frame height,
## so a steep pitch spends the picture on the snow between him and the birds. Not
## so shallow that the world stops being readable -- he is still in this shot.
@export var look_pitch_min_degrees := 17.0
@export var look_pitch_max_degrees := 28.0

## How far the camera swings toward the birds, at most. PARTIAL on purpose: a
## swing that faced the flock squarely would put him off the back of the frame,
## and rule 1 exists to stop the world turning.
@export var swing_max_degrees := 34.0

## How much of the frame is given to the birds against the man: 0 stays on his
## head, 1 abandons him for the flock. Under a half, always -- see SHIFT AND
## WIDEN in the header.
@export var frame_share_min := 0.30
@export var frame_share_max := 0.48

## The frame WIDENS rather than pushing in, and is always greater than one. It
## has to hold him and a flock ten metres off and six metres up at the same time,
## and a push-in is precisely the thing that cannot.
@export var widen_min := 1.06
@export var widen_max := 1.28

## Fractions of the shot: move out, hold, move home. The hold is what makes it a
## shot rather than a wobble.
@export var dolly_in_fraction := 0.30
@export var hold_fraction := 0.36

## When the birds are told to go, as a fraction of the shot. Just after the frame
## has arrived: a burst that fired while the camera was still moving would be the
## thing worth seeing happening behind the move.
@export var burst_at := 0.34

## Off, and the camera never leans. What a capture of anything else flips.
@export var enabled := true

## Deterministic when non-zero, which a capture needs and the game does not.
@export var random_seed := 0

var _bus = null
var _registry = null
var _rig: CameraRig = null
var _player: Node3D = null
var _flock: CrowFlock = null
var _rng := RandomNumberGenerator.new()

## The shot in flight.
var _running := false
var _elapsed := 0.0
var _seconds := 0.0
var _tilt := 0.0
var _swing := 0.0
var _widen := 1.0
var _share := 0.5
var _burst_done := false
var _cooldown := 0.0
var _modifier: Modifier = null
var _applied := 0.0
## Where the camera is pointed, in world space, refreshed every frame.
var _looking_at := Vector3.ZERO
## WHERE THEY LEFT FROM, recorded once when the shot begins.
##
## 聚焦到乌鸦起飞的范围内 -- the area of the take-off, not the birds. That
## distinction is the whole difference between a shot and a chase: a camera that
## tracked the flock would follow it out of the valley at twelve metres a second,
## and by the second half of the move the man is nowhere near the picture. The
## take-off area does not move, so the frame stays put and the birds leave it,
## which is what the owner's 飞离 actually describes.
var _takeoff_at := Vector3.INF


func _ready() -> void:
	# BEFORE the rig. `CameraRig._process` eases the follow and expires framing
	# modifiers; a shot that wrote its offsets after that ran would be a frame
	# behind for its whole length, which over three seconds of easing is a visible
	# stutter at both ends.
	process_priority = -10
	attach()


func _exit_tree() -> void:
	detach()


func set_event_bus(bus) -> void:
	_bus = bus


func set_service_registry(registry) -> void:
	_registry = registry


func set_camera_rig(rig: CameraRig) -> void:
	_rig = rig


func set_crow_flock(flock: CrowFlock) -> void:
	_flock = flock


func set_watched(node: Node3D) -> void:
	_player = node


func attach() -> void:
	if is_inside_tree():
		if _bus == null:
			# A project autoload is a node under /root and never an engine
			# singleton -- briefing trap 3.
			_bus = get_node_or_null("/root/EventBus")
		if _registry == null:
			_registry = get_node_or_null("/root/ServiceRegistry")
	_seed_rng()


func detach() -> void:
	# A rig left mid-dolly because this node was pulled out of the tree would keep
	# turned forever, and nothing else in the game knows how to put it back.
	_put_it_back()


## Seeded and then shaken out. See RNG_WARMUP.
func _seed_rng() -> void:
	_rng.seed = hash(random_seed) if random_seed != 0 else int(Time.get_ticks_usec())
	for _discard in range(RNG_WARMUP):
		_rng.randf()


func is_running() -> bool:
	return _running


func cooldown_left() -> float:
	return _cooldown


func progress() -> float:
	return 0.0 if _seconds <= 0.0 else clampf(_elapsed / _seconds, 0.0, 1.0)


## Where the camera is aimed this frame. For a capture, and for a test that wants
## to assert the frame holds both him and the birds.
func looking_at() -> Vector3:
	return _looking_at


## Where a world point lands in the picture, in units of FRAME HEIGHT, with (0,0)
## at the centre. Vertically the frame runs -0.5..+0.5; horizontally it runs
## +/-0.5*aspect.
##
## Pure geometry off the rig's own angle and size, which is the only honest way
## to ask "is he still in shot": an orthographic camera projects a world offset
## onto its own right and up axes and divides by the frame height, and nothing
## about the boom or the distance enters into it.
func frame_position(at: Vector3) -> Vector2:
	if _rig == null:
		return Vector2.ZERO
	var basis := Basis.from_euler(_rig.rotation)
	var centre := _rig.global_position if _rig.is_inside_tree() else _rig.position
	var offset := at - centre
	var size := maxf(_rig.framed_size(), 0.001)
	return Vector2(offset.dot(basis.x), offset.dot(basis.y)) / size


## Are the man and the take-off area both in the picture? `aspect` is width over
## height -- 1.6 for this project's 1600x1000 captures. THE CHECK THAT STOPS THE
## SHOT ABANDONING HIM.
##
## Against the AREA rather than the birds, deliberately. They leave at twelve
## metres a second and are meant to; a check that required them in frame would be
## asserting that they never get away, which is the opposite of the feature.
func frames_both(aspect := 1.6) -> bool:
	if not frames_him(aspect):
		return false
	var area := _takeoff_at
	if area == Vector3.INF:
		return true
	return _inside(frame_position(area), aspect)


## Is HE in the picture? The one that has to be true on every single frame --
## `frames_both` cannot be, because the ordinary game framing does not contain a
## wire eight metres up and eight metres away and is not supposed to. Measured:
## at the opening frame the take-off area sits at 0.90 of frame height, which is
## simply what the isometric shot looks like before the move begins.
func frames_him(aspect := 1.6) -> bool:
	return _inside(frame_position(_where_he_is() + Vector3(0.0, 1.7, 0.0)), aspect)


## Where the birds left from, or INF before the shot has begun.
func takeoff_area() -> Vector3:
	return _takeoff_at


static func _inside(at: Vector2, aspect: float) -> bool:
	return absf(at.y) <= 0.5 and absf(at.x) <= 0.5 * aspect


func _process(delta: float) -> void:
	advance(delta)


## Public and carrying everything; `_process` only forwards. A whole sequence
## plays out in a test in one loop, with no viewport.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not _running:
		_look_for_a_flock()
		return
	_elapsed += delta
	_aim()
	_apply(_curve(progress()))
	_fire_the_burst()
	if _is_over():
		_put_it_back()


## THE PROXIMITY TRIGGER. A range check against a flock that is actually sitting
## there -- not a reaction to it having already gone, which would be watching the
## aftermath.
func _look_for_a_flock() -> void:
	if not enabled or _cooldown > 0.0:
		return
	_resolve()
	if _flock == null or _player == null or _rig == null:
		return
	if _flock.perched_count() <= 0:
		return
	# THE NEAREST BIRD, NOT THE MIDDLE OF THEM, and this is not a nicety.
	# `CrowFlock._anyone_near()` tests every crow individually, so a flock spread
	# along twenty metres of wire flushes itself as soon as ONE bird is inside its
	# eight metres -- while the centroid is still thirteen away. Measured on the
	# shipped scene: seed 4711 lands four birds down a long span, and a
	# centroid-based trigger lost the race every time. The camera opened on an
	# empty wire, or rather never opened at all, and the only symptom was a seed
	# that "just didn't fire".
	#
	# Same measure as the thing it has to beat, wider radius, so it always wins.
	if _nearest_perched() > trigger_radius_m:
		return
	if _rng.randf() > chance:
		# Not a retry every frame: a coin flipped sixty times a second is not a
		# coin. Whatever the answer, this flock has had its turn.
		_cooldown = cooldown_seconds
		return
	begin_now()


## Fire now, whatever the range and the dice say. The one door in from outside,
## for a capture that cannot wait out a cooldown and still photograph the same
## sequence twice.
func begin_now() -> bool:
	if not enabled or _running:
		return false
	_resolve()
	if _rig == null or _player == null:
		return false
	# Never over another lean. Two shots stacked would each try to restore the
	# framing and the second would restore it to the first one's angle.
	if _rig.is_leaning():
		return false
	_seconds = _rng.randf_range(shot_seconds_min, shot_seconds_max)
	_tilt = deg_to_rad(_rig.pitch_degrees
		- _rng.randf_range(look_pitch_min_degrees, look_pitch_max_degrees))
	_widen = _rng.randf_range(widen_min, widen_max)
	_share = _rng.randf_range(frame_share_min, frame_share_max)
	var perched := _perched_middle()
	_takeoff_at = perched if perched != Vector3.INF else _flock_middle()
	_elapsed = 0.0
	_applied = 0.0
	_burst_done = false
	_running = true
	_aim()
	_modifier = Modifier.new()
	_modifier.source_id = SOURCE
	_modifier.operation = Modifier.Operation.MULTIPLY
	# One, for now. The value is driven every frame by `_apply`, which is why the
	# rig is settled rather than tweened -- see `CameraRig.settle_framing()`.
	_modifier.value = 1.0
	_modifier.duration = -1.0
	_rig.push_framing_modifier(_modifier)
	_rig.settle_framing()
	return true


## Where the frame is pointed this instant: between his head and the flock, by
## `_share`. Recomputed every frame because the birds climb -- an aim fixed at
## the perch would watch them leave the top of the picture.
func _aim() -> void:
	var him := _where_he_is() + Vector3(0.0, 1.7, 0.0)
	var area := _takeoff_at
	if area == Vector3.INF:
		var perched := _perched_middle()
		area = perched if perched != Vector3.INF else him + Vector3(0.0, 6.0, 0.0)
	# LERPED FROM HIM, not fixed in the world. The aim is `share` of the way from
	# wherever he is NOW to where the birds left from, so it slides along with him
	# as he walks through -- a fixed world point would hold the frame still while
	# he walked out the side of it.
	_looking_at = him.lerp(area, _share)


## How far the rig turns toward the birds -- CAPPED, and that is the whole of
## "do not lose the man". Facing the flock squarely would put him off the back of
## the frame; a third of the way round brings them in while he stays in it.
##
## The rig's flat view direction is `Ry * -Z` = `(-sin y, 0, -cos y)`, so the yaw
## that points it along `w` is `atan2(-w.x, -w.z)`. Getting that sign wrong is the
## same class of mistake as the crow's own MODEL_YAW and looks just as convincing.
func _wanted_swing() -> float:
	var toward := _toward_the_birds()
	if toward == Vector3.ZERO:
		return 0.0
	var wanted := atan2(-toward.x, -toward.z)
	var cap := deg_to_rad(swing_max_degrees)
	return clampf(wrapf(wanted - _rig.base_rotation().y, -PI, PI), -cap, cap)


func _toward_the_birds() -> Vector3:
	var birds := _flock_middle()
	if birds == Vector3.INF:
		return Vector3.ZERO
	var flat := birds - _where_he_is()
	flat.y = 0.0
	if flat.length_squared() < 0.01:
		return Vector3.ZERO
	return flat.normalized()


## Tell the birds to go, once, just after the camera has arrived.
func _fire_the_burst() -> void:
	if _burst_done or _flock == null or not is_instance_valid(_flock):
		return
	if progress() < clampf(burst_at, 0.0, 1.0):
		return
	_burst_done = true
	# Returns 0 if his approach already flushed them, which is fine -- it is the
	# same departure either way and there is only ever one event.
	_flock.scatter(CrowFlock.CAUSE_PLAYER)


func _is_over() -> bool:
	return _elapsed >= _seconds


## Dolly in, hold, dolly out. A smoothstep at each end and a flat middle, so
## there is no frame at which the framing jumps -- which is the difference between
## a move and a cut, and a cut in a game with a fixed isometric camera reads as a
## bug or as a cutscene.
func _curve(through: float) -> float:
	var into := clampf(dolly_in_fraction, 0.01, 0.9)
	var out_at := clampf(into + maxf(hold_fraction, 0.0), into + 0.01, 0.99)
	if through <= 0.0:
		return 0.0
	if through < into:
		return smoothstep(0.0, 1.0, through / into)
	if through < out_at:
		return 1.0
	return smoothstep(0.0, 1.0, 1.0 - (through - out_at) / maxf(1.0 - out_at, 0.001))


func _apply(amount: float) -> void:
	if _rig == null:
		return
	_applied = amount
	_swing = _wanted_swing()
	_rig.set_lean(Vector3(_tilt * amount, _swing * amount, 0.0))
	var head := _where_he_is() + Vector3(0.0, _rig.target_height, 0.0)
	_rig.set_aim_offset((_looking_at - head) * amount)
	if _modifier != null:
		_modifier.value = lerpf(1.0, _widen, amount)
		_rig.settle_framing()


## Everything this file touched goes back to the value it was given, by REMOVAL
## rather than by restoring a number -- so there is nothing to remember and
## nothing to get stale.
func _put_it_back() -> void:
	_running = false
	_elapsed = 0.0
	if _rig != null and is_instance_valid(_rig):
		_rig.set_lean(Vector3.ZERO)
		_rig.set_aim_offset(Vector3.ZERO)
		if _modifier != null:
			_rig.remove_framing_modifiers(SOURCE)
			_rig.settle_framing()
	_modifier = null
	_takeoff_at = Vector3.INF
	_cooldown = cooldown_seconds


# --- who is who ------------------------------------------------------------------


func _resolve() -> void:
	if _rig == null:
		_rig = _find(&"CameraRig") as CameraRig
	if _flock == null:
		_flock = _find(&"CrowFlock") as CrowFlock
	if _player == null and _registry != null:
		_player = _registry.get_service(&"player") as Node3D


func _find(what: StringName) -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	for node in tree.current_scene.find_children("*", "Node3D", true, false):
		if node.get_script() != null and node.is_class("Node3D"):
			if (what == &"CameraRig" and node is CameraRig) \
					or (what == &"CrowFlock" and node is CrowFlock):
				return node
	return null


func _where_he_is() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return Vector3.ZERO
	return _player.global_position if _player.is_inside_tree() else _player.position


## How far the closest bird on the wire is, flat. INF for an empty wire.
func _nearest_perched() -> float:
	if _flock == null or not is_instance_valid(_flock):
		return INF
	var here := _where_he_is()
	var nearest := INF
	for crow in _flock.crows():
		if not crow.is_perched():
			continue
		nearest = minf(nearest, _flat_gap(crow.where(), here))
	return nearest


## The middle of whatever is on the wire. INF for an empty one, which is a real
## answer and not a zero.
func _perched_middle() -> Vector3:
	if _flock == null or not is_instance_valid(_flock):
		return Vector3.INF
	var middle := Vector3.ZERO
	var seen := 0
	for crow in _flock.crows():
		if not crow.is_perched():
			continue
		middle += crow.where()
		seen += 1
	return Vector3.INF if seen == 0 else middle / float(seen)


## The middle of the whole flock, perched or flying. What the camera watches once
## they have gone up.
func _flock_middle() -> Vector3:
	if _flock == null or not is_instance_valid(_flock):
		return Vector3.INF
	var middle := Vector3.ZERO
	var seen := 0
	for crow in _flock.crows():
		middle += crow.where()
		seen += 1
	return Vector3.INF if seen == 0 else middle / float(seen)


static func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
