class_name StartleShot
extends Node

## The camera, for the two seconds after the crows go up.
##
## ---------------------------------------------------------------------------
## WHAT WAS ASKED FOR
## ---------------------------------------------------------------------------
##   摄像机也可以给一个从玩家头部看上去的摄像机特写，直到乌鸦盘旋后飞离…
##   你可以把自己想象成一个导演，来策划这场每一次都不一样的乌鸦被惊飞的
##   电影化镜头的特写
##
## A look-up from the player's head, held until the flock has wheeled and gone,
## and DIFFERENT EVERY TIME.
##
## ---------------------------------------------------------------------------
## THE FENCE THIS LIVES INSIDE
## ---------------------------------------------------------------------------
## Art Bible rule 1 is "永不旋转，只跟随" -- the camera never rotates. That rule is
## the reason the world stays readable and the reason two figures at different
## depths draw the same size. This shot is its ONLY approved exception, granted
## by the Director on five conditions, all required. Each one is a line of code
## here and is named where it is implemented:
##
##   1. SHORT             two or three seconds        `shot_seconds_min/max`
##   2. NEVER TAKES       yields if the player stops   `_the_player_has_other_ideas`
##      CONTROL           or changes direction
##   3. LEANS, NEVER      eased in and eased out       `_curve`, and the fact that
##      CUTS              from the game framing        nothing here writes `rotation`
##   4. RETURNS EXACTLY   bit for bit                  `CameraRig.set_lean(ZERO)`
##   5. RARE              a chance and a cooldown      `chance`, `cooldown_seconds`
##
## Condition 4 is the one that decides the whole shape of this file. The shot
## never writes the camera's pitch, yaw or size; it writes an OFFSET on each,
## and the offsets return to zero. `CameraRig.base_rotation()` is recomputed from
## the exports rather than snapshotted, and the framing goes through the rig's
## `ModifierStack` under this file's own `source_id`, so removing it leaves the
## player's chosen stop exactly as he left it. Nothing here can strand a value.
##
## ---------------------------------------------------------------------------
## "EVERY TIME DIFFERENT" IS PROCEDURAL, NOT A SHELF OF SHOTS
## ---------------------------------------------------------------------------
## The ruling lists the axes, and they are the axes because a canned sequence
## played at random is seen through in three viewings:
##
##   鸟的数量                  CrowFlock draws 1..5
##   盘旋的方向与圈数           CrowFlock draws one direction per burst and a rate
##                            per bird -- see `wheel_rate_min`
##   决定航向前犹豫多久         CrowFlock draws each bird's hesitation
##   镜头推进的紧密程度         `push_min/max` here
##   哪几声叫、在什么时刻       CrowCalls draws the schedule
##
## and this file adds three of its own: how long the shot runs, how far it tilts,
## and how far round it swings. Every one is a draw from a bounded range, so the
## variation is continuous rather than a menu.
##
## ---------------------------------------------------------------------------
## THE COMPOSITION, WHICH IS THE REASON A LOOK-UP IS WORTH HAVING
## ---------------------------------------------------------------------------
## This game is dark shapes on bright snow. The startle is the one moment it
## inverts: dark birds on a bright sky. That is the whole argument for pointing
## the camera up, so the shot is framed for it -- the tilt is large enough to put
## the horizon low and the yaw is aimed at the flock rather than at the player's
## heading, so what fills the frame behind the birds is sky and not roof or hill.
##
## ---------------------------------------------------------------------------
## ORTHOGRAPHIC, AND THE PERSPECTIVE THAT WAS NOT SHIPPED
## ---------------------------------------------------------------------------
## The ruling permits blending to perspective for this moment, because a parallel
## projection looking up has no convergence and less drama -- on condition that
## the switch still satisfies rules 3 and 4, and it says outright that if the
## switch reads as abrupt it is the perspective that should go, not the lean.
##
## `Camera3D.projection` is a hard enum. There is no blend, and the only way to
## make the change invisible is to enter perspective at a lens long enough to be
## indistinguishable from parallel (about 3 degrees, which needs the camera two
## hundred metres out) and then widen it while hauling the boom in to hold the
## subject size -- a dolly zoom. It works, and it is a second moving part on the
## far plane, the shadow range and the lens effect parented to the camera, for a
## code path that runs a few times an hour.
##
## Shipped orthographic. The tilt and the push carry the drama; the convergence
## does not arrive. Stated here rather than left to be discovered.

const EVENT_SCATTERED := &"wildlife.crows_scattered"

## ---------------------------------------------------------------------------
## A FRESHLY SEEDED RandomNumberGenerator IS NOT RANDOM YET
## ---------------------------------------------------------------------------
## MEASURED on 4.7.1, six seeds chosen to be far apart (3, 41, 4711, 20260812,
## 31337, 9001), first six `randf()` from each:
##
##   draw #1  0.4995  0.7676  0.2199  0.0745  0.5181  0.5574   spread
##   draw #2  0.7149  0.3765  0.4632  0.5112  0.2706  0.5143   spread
##   draw #3  0.3371  0.3090  0.0094  0.0214  0.7392  0.9827   spread
##   draw #4  0.2396  0.1004  0.1787  0.1662  0.1978  0.0931   <-- ALL IN 0.09..0.24
##   draw #5  0.8476  0.2219  0.3913  0.4240  0.1052  0.3865   spread
##
## Six independent uniforms all landing in the bottom quarter is a one-in-four-
## thousand coincidence, so it is not one. The fourth draw after `seed = N` is
## systematically low.
##
## It cost this file a real defect, and the defect is the shape that survives
## review: `_push` is the fourth thing drawn, so the camera pushed to 0.814..0.836
## of the framing EVERY TIME out of a declared range of 0.80..0.95 -- the shot
## still worked, still varied in three of its four axes, and the fourth simply
## had a quarter of the range it said it had. Nothing errors. The only symptom is
## a variation axis that is narrower than its own exports claim, which reads as a
## tuning choice.
##
## Hashing the seed and discarding a few draws fixes it; measured again after,
## the fourth draw runs 0.2490..0.8471 across the same six seeds. This is why
## `_seed_rng()` exists rather than a bare assignment, and it is worth knowing for
## anything else in this project that draws a small fixed number of values
## immediately after seeding.
const RNG_WARMUP := 8

## This file's name on the framing stack. Removing by source is how the push
## comes off, and it is precise: nothing else can be removed by accident and
## nothing of this file's can be left behind.
const SOURCE := &"startle_shot"

## The ruling's condition 1. Two or three seconds -- 再长就不是"注意到"，而是
## "被打断". Drawn per shot, because the length is itself one of the axes.
@export var shot_seconds_min := 2.0
@export var shot_seconds_max := 3.0

## The ruling's condition 5. A flock is already rare -- forty to a hundred and
## ten seconds of quiet between them, and the man has to walk under the wire --
## so this is the rarity ON TOP of that: roughly half the startles get a shot,
## and never two within the cooldown.
@export var chance := 0.55
@export var cooldown_seconds := 100.0

## How far the camera tilts up, in degrees, added to the rig's own 45 down.
##
## The floor is set by the horizon: below about eighteen degrees the frame is
## still mostly ground and the birds are dark shapes on snow, which is the
## composition the rest of the game already has. The ceiling is set by the
## player -- past about thirty-four the rig has swung far enough that he is
## leaving the bottom of the frame, and a shot he is not in stops being a look-up
## from his head.
@export var tilt_min_degrees := 19.0
@export var tilt_max_degrees := 33.0

## How far round it swings, toward the flock. Small: a yaw is the part of a lean
## that most easily reads as the world turning rather than the camera looking,
## and rule 1 exists to stop the world turning.
##
## THE CAP IS DRAWN PER SHOT, between `swing_least_share` of this and all of it.
## A fixed cap is not a variation axis: measured across three captures, the flock
## sat further round than thirteen degrees every time, so the swing saturated at
## exactly -13.0 in all three and one of the four axes this file owns was a
## constant wearing a range's clothes. Found by reading the numbers the capture
## printed rather than by looking at the frames, where it is invisible.
@export var swing_max_degrees := 13.0
@export var swing_least_share := 0.35

## How high the aim point rises off the player's head, in metres.
##
## THE PART A ROTATION CANNOT DO. The rig turns about its own origin and its
## origin is the player, so tilting alone pins him at the centre of the frame and
## sends the birds -- eight metres up a pole -- off the top. See
## `CameraRig._aim_offset`.
##
## BOTH ENDS MEASURED ON THE FRAME, and they are a real trade against each other.
## At 5.2 m with a 29-degree tilt the man is half out of the bottom of the picture
## -- a look-up from his head that does not contain his head is a look-up from
## nowhere. At 3.2 m he is comfortably in it and the birds have gone small and
## high, near the top edge, which is the composition this shot exists to avoid.
## 3.6..5.4 puts him in the lower third and the flock in the middle.
@export var rise_min_m := 3.6
@export var rise_max_m := 5.4

## The ruling's "镜头推进的紧密程度" axis, as a multiplier on the player's chosen
## framing stop. Under a parallel projection this is the ONLY control over
## apparent size -- the boom does nothing -- so the push is a smaller frame.
##
## Modest on purpose, and this is a composition decision rather than a taste one:
## the birds climb out of the frame during the shot, so a hard push-in buys
## closeness for half a second and then has nothing in it.
@export var push_min := 0.80
@export var push_max := 0.95

## Fractions of the shot: lean in, hold, lean out. The hold is what makes it a
## shot rather than a wobble.
@export var lean_in_fraction := 0.34
@export var hold_fraction := 0.30

## How much the player has to do to take the camera back. Condition 2: 他若停下
## 或改变方向，镜头让位.
##
## `stop_speed_mps` is below a walk in deep snow, so it means stopped rather than
## slowed. `turn_degrees` is generous -- a man walking a line wanders by ten or
## fifteen degrees and did not mean anything by it.
@export var stop_speed_mps := 0.35
@export var turn_degrees := 38.0

## How long the shot ignores condition 2 at its very top. `advance()` is first
## called on the frame after the shot begins, so there is no displacement to read
## yet -- without this the stop test fires on frame one, every time, and the shot
## never happens at all. Short enough that a man who stops the instant the birds
## go up still gets the camera back inside a fifth of a second.
@export var settle_seconds := 0.14

## Off, and the camera never leans. What a capture of anything else flips.
@export var enabled := true

## Deterministic when non-zero, which a capture needs and the game does not.
@export var random_seed := 0

var _bus = null
var _registry = null
var _rig: CameraRig = null
var _player: Node3D = null
var _rng := RandomNumberGenerator.new()
var _subscribed := false

## The shot in flight.
var _running := false
var _elapsed := 0.0
var _seconds := 0.0
var _tilt := 0.0
var _swing := 0.0
var _rise := 0.0
var _push := 1.0
var _released := false
var _release_from := 0.0
var _release_at := 0.0
## What `_apply` last wrote. The release eases down from this, not from one.
var _applied := 0.0
var _cooldown := 0.0
var _modifier: Modifier = null

## What the player was doing when it started, and where he was last frame. The
## direction is derived from movement rather than read off the controller, so
## this file has no opinion about what a player is.
var _watch_from := Vector3.ZERO
var _watch_heading := Vector3.ZERO
var _watched_yet := false
var _watch_speed := -1.0
var _settling := 0.0
## The stop and the base the player had chosen. A notch mid-shot is intent, and
## intent takes the camera back.
var _stop_at_start := 0.0
var _index_at_start := 0


func _ready() -> void:
	# AFTER the rig, whatever else is in the tree. `CameraRig._process` eases the
	# follow and `_tick_framing` expires modifiers; a shot that wrote its offsets
	# after that ran would be a frame behind for its whole length, which over two
	# seconds of easing is a visible stutter at the two ends.
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
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_SCATTERED, _on_scattered)
	_subscribed = true


## Seeded and then shaken out. See RNG_WARMUP -- this is not superstition, it is
## the difference between a push that varies across 0.80..0.95 and one that
## varies across 0.81..0.84.
func _seed_rng() -> void:
	_rng.seed = hash(random_seed) if random_seed != 0 else int(Time.get_ticks_usec())
	for _discard in range(RNG_WARMUP):
		_rng.randf()


func detach() -> void:
	# A rig left mid-lean because this node was pulled out of the tree would keep
	# the tilt forever, and nothing else in the game knows how to put it back.
	_put_it_back()
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_SCATTERED, _on_scattered)
	_subscribed = false


func is_running() -> bool:
	return _running


## Seconds until another shot may fire. Public so rarity can be asserted rather
## than waited for.
func cooldown_left() -> float:
	return _cooldown


## Where the shot is through its own length, 0..1.
func progress() -> float:
	return 0.0 if _seconds <= 0.0 else clampf(_elapsed / _seconds, 0.0, 1.0)


## Whether the player has already taken it back.
func has_yielded() -> bool:
	return _released


func _process(delta: float) -> void:
	advance(delta)


## Public and carrying everything; `_process` only forwards. A whole shot plays
## out in a test in one loop, with no viewport and no crows.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not _running:
		return
	_elapsed += delta
	if not _released and _the_player_has_other_ideas(delta):
		# NOT A CUT, AND THIS IS THE SUBTLE HALF OF CONDITION 3.
		#
		# Written first as "jump `_elapsed` into the lean-out phase", which is
		# wrong in the one case that matters: a man who stops half a second in has
		# a lean of about a third, and the start of the lean-out is where the
		# curve is ONE. The shot would have snapped UP to full tilt and then eased
		# down from there -- a cut, caused by the code whose whole job is not to
		# cut.
		#
		# So the release is its own ease, from wherever the shot had actually got
		# to, over the time the lean-out would have taken. It is monotone down
		# from the current value and it reaches exactly zero.
		_released = true
		_release_from = _applied
		_release_at = _elapsed
	_apply(_amount_now())
	if _is_over():
		_put_it_back()


## How much of the shot is applied right now, 0..1. Two curves, and which one is
## in force depends on whether the player took it back.
func _amount_now() -> float:
	if not _released:
		return _curve(progress())
	var through := (_elapsed - _release_at) / maxf(_release_seconds(), 0.001)
	return _release_from * smoothstep(0.0, 1.0, 1.0 - clampf(through, 0.0, 1.0))


func _release_seconds() -> float:
	return maxf(_lean_out_fraction() * _seconds, 0.12)


func _is_over() -> bool:
	if _released:
		return _elapsed >= _release_at + _release_seconds()
	return _elapsed >= _seconds


## Fire now, whatever the dice say. The one door in from outside, for a capture
## that cannot wait out a cooldown and a chance and still photograph the same
## shot twice.
func begin_now(aloft: Vector3) -> bool:
	return _begin(aloft)


func _on_scattered(payload) -> void:
	if not (payload is Dictionary):
		return
	var facts: Dictionary = payload
	# THE MAN ONLY. Nightfall empties the wires every day and a gust does it a few
	# times an afternoon; a camera that leaned for those would be leaning several
	# times an hour, which is condition 5 gone. It is also the wrong subject --
	# the shot is about him having startled something, not about the weather.
	if facts.get("cause", &"") != CrowFlock.CAUSE_PLAYER:
		return
	if _rng.randf() > chance:
		return
	_begin(facts.get("aloft", Vector3.ZERO))


func _begin(aloft: Vector3) -> bool:
	if not enabled or _running or _cooldown > 0.0:
		return false
	_resolve()
	if _rig == null:
		return false
	# Never over another lean. Two shots stacked would each try to restore the
	# framing and the second would restore it to the first one's tilt.
	if _rig.is_leaning():
		return false
	_seconds = _rng.randf_range(shot_seconds_min, shot_seconds_max)
	_tilt = deg_to_rad(_rng.randf_range(tilt_min_degrees, tilt_max_degrees))
	_rise = _rng.randf_range(rise_min_m, rise_max_m)
	_push = _rng.randf_range(push_min, push_max)
	_swing = _swing_toward(aloft)
	_elapsed = 0.0
	_released = false
	_release_from = 0.0
	_release_at = 0.0
	_applied = 0.0
	_running = true
	_watched_yet = false
	_watch_heading = Vector3.ZERO
	_watch_speed = -1.0
	_settling = settle_seconds
	_stop_at_start = _rig.framing_base()
	_index_at_start = _rig.framing_index()
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


## Which way to swing, and how far. Toward the birds, clamped -- the flock can be
## anywhere round the pole and a shot that swung to face it would be the world
## turning, which is the thing rule 1 forbids.
##
## The angle is measured in the rig's OWN frame: how far the flock sits to the
## left or right of where the camera is already pointed. A yaw offset is a
## rotation about the world's vertical, so a signed screen-space bearing is the
## only quantity that answers "swing which way".
func _swing_toward(aloft: Vector3) -> float:
	if _rig == null or aloft == Vector3.ZERO:
		return 0.0
	var here := _rig.global_position if _rig.is_inside_tree() else _rig.position
	var toward := aloft - here
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		return 0.0
	# The rig's own flat forward, which under `base_rotation()` is its -Z.
	var facing := Basis.from_euler(_rig.base_rotation()) * Vector3(0.0, 0.0, -1.0)
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return 0.0
	facing = facing.normalized()
	toward = toward.normalized()
	var across := facing.cross(toward).y
	var bearing := atan2(across, facing.dot(toward))
	var cap := deg_to_rad(swing_max_degrees) \
		* _rng.randf_range(clampf(swing_least_share, 0.05, 1.0), 1.0)
	return clampf(bearing, -cap, cap)


## Condition 2, in one question. He is walking and keeps walking: the camera
## stays. He stops, or he turns: it gives way.
##
## Movement is measured from POSITION rather than read off the controller. This
## file has no reference to a player class, no `velocity` property assumption and
## no service beyond "something with a position", which is what lets a test drive
## it with a bare Node3D.
##
## THE SPEED IS SMOOTHED AND THE ANSWER IS NOT. A raw per-frame displacement is
## noisy enough that a man walking steadily produces frames under any stop
## threshold you like -- and a shot that flickered out on one of those would be
## the camera stuttering rather than yielding. So the speed is an exponential
## average with a short time constant and the comparison is against that; the
## turn is compared against a smoothed heading for the same reason.
##
## `_settling` is the grace at the top of the shot. `advance()` is first called
## on the frame after `begin_now()`, so there is no displacement to read yet and
## an ungated stop test would yield instantly, every time, and the shot would
## never exist.
func _the_player_has_other_ideas(delta: float) -> bool:
	_resolve()
	if _rig == null:
		return true
	# A notch of the framing wheel is intent as much as a turn is.
	if _rig.framing_index() != _index_at_start or not is_equal_approx(_rig.framing_base(), _stop_at_start):
		return true
	if _player == null or not is_instance_valid(_player):
		return false
	var at: Vector3 = _player.global_position if _player.is_inside_tree() else _player.position
	if not _watched_yet:
		_watch_from = at
		_watched_yet = true
		_watch_speed = -1.0
		_settling = settle_seconds
		return false
	var step := at - _watch_from
	step.y = 0.0
	_watch_from = at
	# Metres a second, not metres a frame: `advance()` runs at whatever the frame
	# rate is, and a fixed per-frame distance would be a different speed threshold
	# on every machine.
	var speed := step.length() / maxf(delta, 0.00001)
	_watch_speed = speed if _watch_speed < 0.0 else lerpf(_watch_speed, speed, 0.25)
	_settling = maxf(_settling - delta, 0.0)
	if _settling > 0.0:
		return false
	if _watch_speed < stop_speed_mps:
		return true
	if step.length() < 0.00001:
		return false
	var heading := step / step.length()
	if _watch_heading == Vector3.ZERO:
		_watch_heading = heading
		return false
	if rad_to_deg(_watch_heading.angle_to(heading)) > turn_degrees:
		return true
	_watch_heading = _watch_heading.slerp(heading, 0.25).normalized()
	return false


## Ease in, hold, ease out. Returns how much of the shot is applied, 0..1.
##
## Condition 3 lives here. The value leaves zero and comes back to zero with a
## smoothstep at each end and a flat middle, so there is no frame at which the
## framing jumps -- which is the difference between a lean and a cut, and a cut
## in a game with a fixed isometric camera reads as a bug.
func _curve(through: float) -> float:
	var into := clampf(lean_in_fraction, 0.01, 0.9)
	var out_at := clampf(into + maxf(hold_fraction, 0.0), into + 0.01, 0.99)
	if through <= 0.0:
		return 0.0
	if through < into:
		return smoothstep(0.0, 1.0, through / into)
	if through < out_at:
		return 1.0
	return smoothstep(0.0, 1.0, 1.0 - (through - out_at) / maxf(1.0 - out_at, 0.001))


func _lean_out_fraction() -> float:
	var into := clampf(lean_in_fraction, 0.01, 0.9)
	var out_at := clampf(into + maxf(hold_fraction, 0.0), into + 0.01, 0.99)
	return 1.0 - out_at


func _apply(amount: float) -> void:
	if _rig == null:
		return
	_applied = amount
	_rig.set_lean(Vector3(_tilt * amount, _swing * amount, 0.0))
	_rig.set_aim_offset(Vector3(0.0, _rise * amount, 0.0))
	if _modifier != null:
		_modifier.value = lerpf(1.0, _push, amount)
		_rig.settle_framing()


## Condition 4. Everything this file touched goes back to the value it was given,
## by removal rather than by restoring a number -- so there is nothing to
## remember and nothing to get stale.
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
	_cooldown = cooldown_seconds


func _resolve() -> void:
	if _rig == null:
		_rig = _find_rig()
	if _player == null and _registry != null:
		_player = _registry.get_service(&"player") as Node3D


func _find_rig() -> CameraRig:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	for node in tree.current_scene.find_children("*", "Node3D", true, false):
		var rig := node as CameraRig
		if rig != null:
			return rig
	return null
