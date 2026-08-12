extends Node

## Photographs the crows in the real scene, at the three framing stops and
## across a departure, and MEASURES how big a crow actually is on screen.
##
##   Godot_console.exe --path <project> res://tools/capture_crows.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/crows
##
## Writes:
##   <out>-stop-10.5.png / -13.5 / -17.0   a flock perched, at each framing stop
##   <out>-away-0..5.png                   the burst, every 0.35 s from the flush
##   <out>-solo.png                        one bird, close, to judge the model
##
## and prints, for every stop, the crow's height **in pixels of the saved PNG**.
##
## THAT NUMBER IS THE POINT OF THIS FILE. The Art Bible's own note on the three
## stops says in as many words that screen share must be measured on a rendered
## frame and never computed from model dimensions -- the Director got it wrong by
## 26% doing the arithmetic, because a hooded, hunched man does not project his
## own height. A crow is a fifth of his size and perched on a wire eight metres
## up; guessing whether it reads is not available.
##
## The measurement is `Camera3D.unproject_position()` on the corners of the
## bird's own mesh AABB, taken through the same camera that renders the shot and
## then scaled from the viewport's canvas rect into window pixels -- briefing
## trap 10: under `canvas_items` stretch, `get_visible_rect()` is 10-25% off from
## what lands in the PNG, and the PNG is what a person looks at.

const OUT_DEFAULT := "user://crows"

## Art Bible rule 1's three stops, in metres of world height. Read off the rig
## rather than written here would be better, but the rig's list is an @export and
## a capture that silently followed an edit to it would stop being comparable
## with the frames already in the report.
const STOPS := [10.5, 13.5, 17.0]

## Where the camera looks. The power pole stands at (6.8, ?, 13.055) in
## scenes/main.tscn and the service drop runs from it to the farmhouse eave, so
## this is the one place in the valley where a pole and three wires are in the
## same frame.
const LOOK_AT := Vector2(5.6, 12.0)

## How high the rig sits. It normally rides a metre above the player, and a
## crow perched on a crossarm is eight metres up -- at the tight stop the top
## of the pole is then above the frame edge. Raising the rig is a translation
## and nothing else: the pitch, the yaw and the orthographic size are the
## game's own, so the crow is photographed at exactly the size the game draws
## it at, which is the only number this file exists to produce.
const LOOK_HEIGHT := 4.6

## Perches further than this from LOOK_AT are not offered to the capture, so
## five birds drawn at random out of the valley's twenty-four land in the
## frame instead of behind the camera. The perches themselves are the ones the
## props declared -- this filters the list, it does not invent one.
const NEAR_M := 11.0

## Long enough for Farmstead._ready() to have settled the pole onto the snow and
## strung the wires, which is what the perches are derived from.
const SETTLE_SECONDS := 1.2

## Frames of the departure, and how far apart.
const AWAY_SHOTS := 8
const AWAY_STEP := 0.45

var _out := OUT_DEFAULT
var _flock: CrowFlock = null
var _camera: Camera3D = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--out":
			_out = args[index + 1]
	await _run()
	get_tree().quit()


func _run() -> void:
	_camera = get_node_or_null("Main/CameraRig/Camera3D") as Camera3D
	_flock = get_node_or_null("Main/Crows") as CrowFlock
	if _camera == null or _flock == null:
		push_error("capture_crows: expected Main/CameraRig/Camera3D and Main/Crows")
		return

	# Deterministic, and arriving at once rather than on the game's own schedule:
	# a capture that waited out `first_arrival_seconds` and then drew a random
	# count would produce a different picture every run and nothing to compare.
	_flock.random_seed = 20260812
	_flock.first_arrival_seconds = 0.0
	_flock.fewest = 5
	_flock.most = 5
	# Nobody to be frightened of, so the flock sits still until this file says
	# otherwise.
	_flock.flush_radius_m = 0.0

	_aim()
	await _wait(SETTLE_SECONDS)
	_report_perches()
	_flock.set_perches(_near_perches())
	# Not by waiting out the quiet timer: see CrowFlock.arrive_now().
	print("capture_crows: %d birds landed" % _flock.land_now())
	await _wait(0.4)

	for stop in STOPS:
		_frame_at(stop)
		await _wait(0.25)
		_aim()
		await RenderingServer.frame_post_draw
		_measure(stop)
		_save("%s-stop-%.1f.png" % [_out, stop])

	# The departure, at the tight stop where it is largest.
	_frame_at(STOPS[0])
	await _wait(0.25)
	_aim()
	_flock.scatter(CrowFlock.CAUSE_PLAYER)
	for shot in range(AWAY_SHOTS):
		await _wait(AWAY_STEP)
		_aim()
		await RenderingServer.frame_post_draw
		_save("%s-away-%d.png" % [_out, shot])
		print("capture_crows: away %d  t=%.2fs  aloft=%d  %s" % [
			shot, float(shot + 1) * AWAY_STEP, _flock.crow_count(), _headings()])


## Holds the camera on the pole. Re-applied after every wait because the rig
## follows the player by default and a frame taken mid-ease is a frame of a
## different shot -- see the briefing's note on proving two captures are the same
## shot before comparing them.
func _aim() -> void:
	var rig := get_node_or_null("Main/CameraRig") as Node3D
	if rig == null:
		return
	# The rig only ever translates -- the frame is the same frame, aimed
	# somewhere else. It follows the player at 4.5 m/s in its own _process, so
	# this is re-applied immediately before every shutter rather than once.
	rig.global_position = Vector3(LOOK_AT.x, LOOK_HEIGHT, LOOK_AT.y)


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


## The crow's extent in pixels of the saved image.
##
## THE HULL IS THE POSED SKELETON, NOT THE MESH'S AABB. `MeshInstance3D.get_aabb()`
## on a skinned mesh returns the mesh's own bind-pose box and never moves: it
## reports the identical 0.96 x 0.57 x 0.29 for a crow folded on a wire and for
## one gliding with its wings out, which would make every number below a
## measurement of the bind pose rather than of the picture. The bone origins do
## move, and the rig has a bone in every wing feather and every tail feather, so
## their hull is within a centimetre of the silhouette.
##
## Window size, not the viewport's canvas rect: briefing trap 10. unproject works
## in canvas space, so the ratio between the two is applied before anything is
## reported.
func _measure(stop: float) -> void:
	var window := Vector2(DisplayServer.window_get_size())
	var canvas := get_viewport().get_visible_rect().size
	var scale := window.y / maxf(canvas.y, 1.0)
	var tallest := 0.0
	var widest := 0.0
	var metres := Vector3.ZERO
	for crow in _crows():
		for node in crow.find_children("*", "Skeleton3D", true, false):
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
	print("capture_crows: stop %.1f m -> crow %.1f x %.1f px in a %d px frame (%.2f%% of frame height); largest bird %s m" % [
		stop, widest, tallest, int(window.y), 100.0 * tallest / maxf(window.y, 1.0),
		metres.snapped(Vector3(0.001, 0.001, 0.001))])


func _report_perches() -> void:
	var perches := _flock.available_perches()
	print("capture_crows: %d perches on offer" % perches.size())
	for perch in perches:
		print("   at %s facing %s" % [perch["at"], perch["facing"]])


## The declared perches that are near enough to the camera to be in shot.
func _near_perches() -> Array:
	var spot := Vector3(LOOK_AT.x, 0.0, LOOK_AT.y)
	var near: Array = []
	for perch in _flock.available_perches():
		var at: Vector3 = perch["at"]
		if Vector2(at.x - spot.x, at.z - spot.z).length() <= NEAR_M:
			near.append(perch)
	print("capture_crows: %d of them within %.0f m of the camera" % [near.size(), NEAR_M])
	return near


func _headings() -> String:
	var parts := PackedStringArray()
	for crow in _crows():
		parts.append("%s" % [crow.where().snapped(Vector3(0.1, 0.1, 0.1))])
	return ", ".join(parts)


## The birds themselves. Filtered off the flock's own children rather than
## through find_children's type argument, which matches on class names and is
## one rename away from silently finding nothing.
func _crows() -> Array[Crow]:
	var found: Array[Crow] = []
	for child in _flock.get_children():
		if child is Crow:
			found.append(child as Crow)
	return found


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var directory := path.get_base_dir()
	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	image.save_png(path)
	print("capture_crows: wrote ", path)


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout
