extends Node

## Photographs the pigeons in the real scene and MEASURES how big one is on
## screen, the same way `tools/capture_crows.gd` does for the crows.
##
##   Godot_console.exe --path <project> res://tools/capture_pigeons.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/pigeons
##
## Writes:
##   <out>-stop-10.5.png / -13.5 / -17.0   a flock on the wire, at each stop
##   <out>-eave.png                        the same flock on the farmhouse eave
##   <out>-night.png                       on the wire after dark, which the
##                                         crows can never be photographed doing
##   <out>-gust.png                        the balance pose, which is the weakest
##                                         thing in the delivery and is therefore
##                                         the one worth looking at
##   <out>-away-0..5.png                   the burst
##
## THE CAMERA IS THE CROW CAPTURE'S CAMERA, deliberately -- same LOOK_AT, same
## height, same three stops -- so the pigeon frames can be laid beside the crow
## frames already in `.superpowers/sdd/wave2/crows/` and the two birds compared
## at the size the game actually draws them. Changing the framing would make the
## comparison worthless, which is the briefing's own rule about proving two
## captures are the same shot before comparing them.

const OUT_DEFAULT := "user://pigeons"

## Art Bible rule 1's three stops, in metres of world height.
const STOPS := [10.5, 13.5, 17.0]

## Where the camera looks for the wire shots: the one place in the valley where
## the pole and three wires are in the same frame.
const LOOK_AT := Vector2(5.6, 12.0)
const LOOK_HEIGHT := 4.6

## And for the eave: the farmhouse stands at (13, 0, -12) and its wing eave runs
## along the model's own +z face.
const EAVE_LOOK_AT := Vector2(11.6, -8.4)
const EAVE_HEIGHT := 3.4

const NEAR_M := 8.0
const EAVE_NEAR_M := 6.0

## Long enough for Farmstead._ready() to have settled the pole onto the snow and
## strung the wires, which is what the perches are derived from.
const SETTLE_SECONDS := 1.2

const AWAY_SHOTS := 6
const AWAY_STEP := 0.40

var _out := OUT_DEFAULT
var _flock: PigeonFlock = null
var _camera: Camera3D = null
## Every perch the valley declares, snapshotted once before anything is handed
## to the flock. `CrowFlock.set_perches()` latches `_explicit_perches`, so from
## the first call `available_perches()` answers with whatever it was last given
## -- and a second filter run against that answer narrows a list that has already
## been narrowed. Measured: the eave shot came back with nought perches and
## photographed the wire flock where it stood.
var _declared: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--out":
			_out = args[index + 1]
	await _run()
	get_tree().quit()


func _run() -> void:
	_camera = get_node_or_null("Main/CameraRig/Camera3D") as Camera3D
	_flock = get_node_or_null("Main/Pigeons") as PigeonFlock
	var crows := get_node_or_null("Main/Crows") as CrowFlock
	if _camera == null or _flock == null:
		push_error("capture_pigeons: expected Main/CameraRig/Camera3D and Main/Pigeons")
		return
	# The crows are switched off for the capture. Not because they clash -- the
	# whole point of the perch group is that both flocks draw from it -- but
	# because a frame with a random number of crows in it is a different picture
	# every run, and these frames are evidence.
	if crows != null:
		crows.enabled = false

	_flock.random_seed = 20260812
	_flock.first_arrival_seconds = 0.0
	_flock.fewest = 5
	_flock.most = 5
	# Nobody to be frightened of, so the flock sits still until this file says
	# otherwise.
	_flock.flush_radius_m = 0.0

	_aim(LOOK_AT, LOOK_HEIGHT)
	await _wait(SETTLE_SECONDS)
	_declared = _flock.available_perches()
	_report_perches()

	# --- on the wire, at all three stops --------------------------------------
	_flock.set_perches(_perches_near(LOOK_AT, NEAR_M, PerchPoints.Kind.SPAN))
	print("capture_pigeons: %d birds landed on the wire" % _flock.land_now())
	await _wait(0.4)
	for stop in STOPS:
		_frame_at(stop)
		await _wait(0.25)
		_aim(LOOK_AT, LOOK_HEIGHT)
		await RenderingServer.frame_post_draw
		_measure(stop)
		_save("%s-stop-%.1f.png" % [_out, stop])

	# --- the balance pose ------------------------------------------------------
	# `Crow._balance()` opens the wings above 0.45 of wind. The dove has no
	# wings-out-on-the-perch take, so this is the substitution held on its last
	# frame -- and a still pose is exactly the kind of thing that has to be
	# LOOKED at rather than reasoned about.
	_frame_at(STOPS[0])
	await _wait(0.2)
	_aim(LOOK_AT, LOOK_HEIGHT)
	# The wind system sweeps the tree on its own two-second timer and pushes the
	# real weather into every consumer, so a strength written once is overwritten
	# before the shutter. Stopping that node is the honest way to hold a chosen
	# gust: the flock is still driven through the same `set_wind_strength()` door
	# the game uses, and nothing about the bird's own reaction is faked.
	var wind := get_node_or_null("Main/Wind") as Node
	if wind != null:
		wind.process_mode = Node.PROCESS_MODE_DISABLED
	_flock.set_wind_strength(0.60)
	await _wait(0.5)
	_flock.set_wind_strength(0.60)
	await _wait(0.2)
	_aim(LOOK_AT, LOOK_HEIGHT)
	await RenderingServer.frame_post_draw
	print("capture_pigeons: balancing = %s" % _balancing())
	_save("%s-gust.png" % _out)
	_flock.set_wind_strength(0.0)
	await _wait(0.4)
	if wind != null:
		wind.process_mode = Node.PROCESS_MODE_INHERIT

	# --- after dark ------------------------------------------------------------
	# Published on the bus rather than pushed into the clock, because that is the
	# path the game uses: the flock and the LightingDirector both subscribe, so
	# one event moves the sky and leaves the birds where they are. A crow flock
	# cannot be photographed doing this at all -- nightfall empties its wire.
	# WITH THE CLOCK'S OWN PAYLOAD. `WorldClock` emits the day number, and
	# `LightingDirector._on_night_started` does `int(payload)` on it -- a null
	# there is `Invalid call. Nonexistent 'int' constructor`, which is a script
	# error rather than a dark frame. Measured the first time this ran.
	var bus := get_node_or_null("/root/EventBus")
	var clock := get_node_or_null("/root/WorldClock")
	var day := int(clock.current_day()) if clock != null else 1
	if bus != null:
		bus.emit_event(&"clock.night_started", day)
	await _wait(9.0)
	_frame_at(STOPS[0])
	await _wait(0.3)
	_aim(LOOK_AT, LOOK_HEIGHT)
	await RenderingServer.frame_post_draw
	print("capture_pigeons: after nightfall -- dark=%s, perched=%d" % [_flock.is_dark(), _flock.perched_count()])
	_save("%s-night.png" % _out)
	if bus != null:
		bus.emit_event(&"clock.day_started", day)
	await _wait(9.0)

	# --- the eave, which is the declaration this task added --------------------
	# The wire flock is sent away first. `land_now()` adds to whatever is already
	# perched, so without this the eave frame carries ten birds and five of them
	# are somewhere else entirely.
	_flock.scatter(CrowFlock.CAUSE_NIGHTFALL)
	await _wait(4.0)
	_aim(EAVE_LOOK_AT, EAVE_HEIGHT)
	_flock.set_perches(_perches_near(EAVE_LOOK_AT, EAVE_NEAR_M, PerchPoints.Kind.RUN))
	print("capture_pigeons: %d birds landed on the eave" % _flock.land_now())
	_frame_at(STOPS[0])
	await _wait(0.4)
	_aim(EAVE_LOOK_AT, EAVE_HEIGHT)
	await RenderingServer.frame_post_draw
	_measure(-1.0)
	_save("%s-eave.png" % _out)

	# --- and the burst ---------------------------------------------------------
	_aim(LOOK_AT, LOOK_HEIGHT)
	_flock.set_perches(_perches_near(LOOK_AT, NEAR_M, PerchPoints.Kind.SPAN))
	_flock.land_now()
	await _wait(0.3)
	_aim(LOOK_AT, LOOK_HEIGHT)
	_flock.scatter(CrowFlock.CAUSE_PLAYER)
	for shot in range(AWAY_SHOTS):
		await _wait(AWAY_STEP)
		_aim(LOOK_AT, LOOK_HEIGHT)
		await RenderingServer.frame_post_draw
		_save("%s-away-%d.png" % [_out, shot])
		print("capture_pigeons: away %d  t=%.2fs  aloft=%d  %s" % [
			shot, float(shot + 1) * AWAY_STEP, _flock.crow_count(), _where_they_are()])


## Holds the camera. Re-applied before every shutter because the rig follows the
## player in its own `_process`, and a frame taken mid-ease is a frame of a
## different shot.
func _aim(look_at: Vector2, height: float) -> void:
	var rig := get_node_or_null("Main/CameraRig") as Node3D
	if rig == null:
		return
	rig.global_position = Vector3(look_at.x, height, look_at.y)


func _frame_at(ortho: float) -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null:
		return
	rig.orthographic_size = ortho
	rig.refresh_framing()
	var tween: Tween = rig.framing_tween()
	if tween != null and tween.is_valid():
		tween.kill()
	rig.apply_framed_size(rig.framing_target())


## The bird's extent in pixels of the saved image.
##
## THE HULL IS THE POSED SKELETON, NOT THE MESH'S AABB, for the reason
## `capture_crows.gd` records at length and this task then measured again from
## the other direction: `Mesh.get_aabb()` on a skinned mesh never moves, and on
## the four Blender-exported characters in this project it is not even the right
## size -- it returns a box in the skin's bind space, a hundredth of life size.
## Bone origins are the only instrument that is right for both.
##
## Window size, not the viewport's canvas rect: briefing trap 10.
func _measure(stop: float) -> void:
	var window := Vector2(DisplayServer.window_get_size())
	var canvas := get_viewport().get_visible_rect().size
	var scale := window.y / maxf(canvas.y, 1.0)
	var tallest := 0.0
	var widest := 0.0
	var metres := Vector3.ZERO
	for bird in _birds():
		for node in bird.find_children("*", "Skeleton3D", true, false):
			var skeleton := node as Skeleton3D
			var low := Vector2(INF, INF)
			var high := Vector2(-INF, -INF)
			var world_low := Vector3(INF, INF, INF)
			var world_high := Vector3(-INF, -INF, -INF)
			for bone in range(skeleton.get_bone_count()):
				var at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
				world_low = world_low.min(at)
				world_high = world_high.max(at)
				var on_screen := _camera.unproject_position(at)
				low = low.min(on_screen)
				high = high.max(on_screen)
			tallest = maxf(tallest, (high.y - low.y) * scale)
			widest = maxf(widest, (high.x - low.x) * scale)
			metres = metres.max(world_high - world_low)
	# Where each bird landed IN THE SAVED IMAGE. A frame is evidence only if you
	# can find the subject in it, and at seventeen pixels on a snowfield you
	# cannot do that by looking -- the eave shot was cropped three times against
	# the wrong part of the roof before this line existed.
	for bird in _birds():
		var on_screen := _camera.unproject_position(bird.where()) * scale
		print("   bird at %s -> %d, %d px" % [
			bird.where().snapped(Vector3(0.01, 0.01, 0.01)), int(on_screen.x), int(on_screen.y)])
	print("capture_pigeons: stop %.1f m -> pigeon %.1f x %.1f px in a %d px frame (%.2f%% of frame height); largest bird %s m" % [
		stop, widest, tallest, int(window.y), 100.0 * tallest / maxf(window.y, 1.0),
		metres.snapped(Vector3(0.001, 0.001, 0.001))])


func _report_perches() -> void:
	print("capture_pigeons: %d perches on offer across the valley" % _declared.size())
	for perch in _declared:
		print("   at %s facing %s  from %s" % [
			perch["at"], perch["facing"],
			(perch["anchor"] as Node).get_parent().name if perch.has("anchor") else "?"])


## The declared perches near `spot`, of one kind.
##
## THE KIND FILTER IS THE DIFFERENCE BETWEEN A PICTURE AND A GUESS. The pole's
## crossarm is inside the wire shot's radius, and the crow report already found
## that a bird on the crossarm is the hardest place in the valley to pick one out
## -- three insulators sit there that are the same colour and roughly the same
## size. The brief asks for the bird ON A WIRE, so the wire shot takes spans and
## the eave shot takes runs, rather than whichever five the shuffle happened to
## draw.
func _perches_near(spot: Vector2, radius: float, kind: int) -> Array:
	var near: Array = []
	for perch in _declared:
		var at: Vector3 = perch["at"]
		var anchor := perch.get("anchor", null) as PerchPoints
		if anchor == null or int(anchor.kind) != kind:
			continue
		if Vector2(at.x - spot.x, at.z - spot.y).length() <= radius:
			near.append(perch)
	print("capture_pigeons: %d perches of kind %d within %.0f m of (%.1f, %.1f)" % [
		near.size(), kind, radius, spot.x, spot.y])
	return near


func _balancing() -> String:
	var parts := PackedStringArray()
	for bird in _birds():
		parts.append("%s" % bird.is_balancing())
	return ", ".join(parts)


func _where_they_are() -> String:
	var parts := PackedStringArray()
	for bird in _birds():
		parts.append("%s" % [bird.where().snapped(Vector3(0.1, 0.1, 0.1))])
	return ", ".join(parts)


## The birds themselves, off the flock's own children rather than through
## find_children's type argument, which matches class names and is one rename
## away from silently finding nothing.
func _birds() -> Array[Bird]:
	var found: Array[Bird] = []
	for child in _flock.get_children():
		if child is Bird:
			found.append(child as Bird)
	return found


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("capture_pigeons: wrote %s" % path)
