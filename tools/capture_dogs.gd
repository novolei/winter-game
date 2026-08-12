extends Node

## Photographs the three dogs in the real scene, at the game's own framing.
##
##   Godot_console.exe --path <project> res://tools/capture_dogs.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/dogs
##
## Writes, per breed:
##   <out>-<breed>-idle.png    on all four feet, at the tight stop
##   <out>-<breed>-lie.png     the rescue scene's opening pose, in the snow
##   <out>-<breed>-growl.png   the warning
##   <out>-<breed>-wide.png    the same lying dog at the widest stop, which is
##                             where "can you even see it" is answered
##
## ---------------------------------------------------------------------------
## WHY THIS INSTANCES `main.tscn` INSTEAD OF BUILDING A STAGE
## ---------------------------------------------------------------------------
## The Blender renders in `tools/blender/render_dogs.py` answer "is the pose
## right"; they are Cycles under a plain sun and the game looks nothing like
## them. The question this file answers is different and cannot be answered
## anywhere else: **does a dark navy dog read against this palette's snow, at the
## size this camera draws it.** That needs the real terrain, the real two-band
## cel light and the real camera stops, so it instances the real scene, exactly
## as `capture_pigeons.gd` and `capture_crows.gd` do.
##
## Nothing here writes to `scenes/main.tscn`. It is instanced and read.
##
## ---------------------------------------------------------------------------
## THE DOG IS SETTLED ONTO THE SNOW, NOT DROPPED AT y = 0
## ---------------------------------------------------------------------------
## The terrain is procedural noise and the snow lies on top of it, so no height
## can be written down. `SnowField.surface_height_at()` is what the farmstead
## uses to settle a building and it is what places the dog. A dog photographed at
## y = 0 is a dog buried to the knee in a drift, and that reads as a modelling
## fault rather than as a placement one.

const OUT_DEFAULT := "user://dogs"

## Art Bible rule 1's stops, in metres of world height. The tight one for the
## pose, the widest for legibility.
const TIGHT_STOP := 10.5
const WIDE_STOP := 17.0

## Where in the valley. Open snow west of the farmstead, so the dog is against
## the ground rather than against a wall -- a silhouette test with a building
## behind it is a test of the building.
const SPOT := Vector2(2.0, 6.0)
const LOOK_HEIGHT := 1.2

## Long enough for the world's `_ready()` chain to have run: the terrain built,
## the snow settled, the lighting director's first preset applied.
const SETTLE_SECONDS := 1.5

const SHOTS := [
	[&"idle", 0.35, TIGHT_STOP, "on all four feet"],
	[&"lie", 0.10, TIGHT_STOP, "the rescue scene's opening pose"],
	[&"growl", 0.30, TIGHT_STOP, "the warning"],
	[&"lie", 0.10, WIDE_STOP, "the same dog at the widest stop"],
]

## ---------------------------------------------------------------------------
## THE WORST-CASE WARM FRAME, WHICH THE AMENDMENT ASKS FOR BY NAME
## ---------------------------------------------------------------------------
## Rule 12's amendment (`a0f7d8c`) says the 0.5% warm quota is not waived and
## must be RE-MEASURED rather than assumed, because the dog moves and shares the
## budget with the scarf, the windows and the truck.
##
## So: after dark, at the farmhouse, with the stove lit and the interior showing
## warm through the openings, the player and his scarf in frame, and the golden
## retriever -- the warm one -- standing beside him. That is the frame the
## amendment names, and MEASURED it is over the quota **with the dog and
## without it**: see the wave report.
const WORST_SPOT := Vector2(14.2, -4.6)
const WORST_HEIGHT := 1.0
## TWO framings, and the pair is the point.
##
## 10.5 m is Art Bible rule 1's tightest real stop and is the number any verdict
## about the quota has to be based on. 6.5 m is tighter than the game ever gets
## and is a stress reading: warm share scales with the subject's screen area, so
## it says how much headroom there is rather than whether the rule is met.
##
## Reporting only the 6.5 would have been a breach invented by the instrument.
const WORST_STOPS := [10.5, 6.5]

var _out := OUT_DEFAULT
var _camera: Camera3D = null
var _dog: Dog = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--out":
			_out = args[index + 1]
	await _run()
	get_tree().quit()


func _run() -> void:
	_camera = get_node_or_null("Main/CameraRig/Camera3D") as Camera3D
	var world := get_node_or_null("Main") as Node3D
	if _camera == null or world == null:
		push_error("capture_dogs: expected Main/CameraRig/Camera3D")
		return

	# The birds are switched off. Not because they clash, but because a frame
	# with a random number of birds in it is a different picture every run, and
	# these frames are evidence (briefing: prove two captures are the same shot).
	for name in ["Crows", "Pigeons"]:
		var flock := get_node_or_null("Main/%s" % name)
		if flock != null:
			flock.set("enabled", false)

	await _wait(SETTLE_SECONDS)
	var ground := _ground_at(SPOT)
	print("capture_dogs: snow surface at (%.1f, %.1f) is y = %.3f" % [SPOT.x, SPOT.y, ground])

	for breed in DogAnimations.BREEDS:
		if _dog != null:
			_dog.queue_free()
			await _wait(0.1)
		_dog = Dog.new()
		_dog.breed = breed
		world.add_child(_dog)
		_dog.global_position = Vector3(SPOT.x, ground, SPOT.y)
		# Facing across the frame rather than at the camera, so the silhouette
		# under test is the animal's profile -- which is the one a player reads at
		# fifty pixels.
		_dog.rotation.y = deg_to_rad(-115.0)
		await _wait(0.2)

		for shot in SHOTS:
			var state: StringName = shot[0]
			var played := _dog.play(state)
			var player := _dog.player()
			if played == &"" or player == null:
				print("capture_dogs: %s cannot play %s" % [breed, state])
				continue
			player.seek(player.get_animation("%s/%s" % [DogAnimations.LIBRARY, played]).length * float(shot[1]), true)
			_frame_at(float(shot[2]))
			await _wait(0.3)
			_aim(SPOT, LOOK_HEIGHT)
			player.seek(player.get_animation("%s/%s" % [DogAnimations.LIBRARY, played]).length * float(shot[1]), true)
			await RenderingServer.frame_post_draw
			var suffix := "wide" if float(shot[2]) == WIDE_STOP else String(state)
			_measure(breed, state, float(shot[2]))
			_save("%s-%s-%s.png" % [_out, breed, suffix])

	await _worst_case(world, ground)
	if _dog != null:
		_dog.queue_free()


## After dark, stove lit, player and the largest dog together, framed tighter
## than gameplay ever is. See WORST_SPOT.
func _worst_case(world: Node3D, ground: float) -> void:
	var bus := get_node_or_null("/root/EventBus")
	var clock := get_node_or_null("/root/WorldClock")
	var stove := get_node_or_null("Main/Farmhouse/Stove")
	var player := get_node_or_null("Main/Player") as Node3D
	if stove != null and stove.has_method("light"):
		stove.call("add_fuel_seconds", 600.0)
		stove.call("light")
	if bus != null:
		# Through the bus, which is the path the game uses: the lighting director
		# and everything else subscribe, so one event moves the whole world.
		# WITH the clock's own payload -- `_on_night_started` does `int(payload)`
		# and a null there is a script error rather than a dark frame.
		bus.call("emit_event", &"clock.night_started", int(clock.call("current_day")) if clock != null else 1)
	await _wait(9.0)

	var here := Vector3(WORST_SPOT.x, ground, WORST_SPOT.y)
	if player != null:
		player.global_position = here
	# The GOLDEN retriever, because it is the warm one and this frame exists to
	# measure the warm quota. The first version put the great dane here and then
	# repainted it, which measured a navy dog against a navy dog.
	_swap_dog(world, DogAnimations.GOLDEN_RETRIEVER, ground)
	# Beside the man, not on top of him: a companion's distance, and close enough
	# that both are in the same tight frame.
	_dog.global_position = here + Vector3(0.9, 0.0, 0.35)
	_dog.rotation.y = deg_to_rad(-115.0)
	print("capture_dogs: worst case -- stove lit=%s, dog %s beside the player at %s" % [
		stove.call("is_lit") if stove != null and stove.has_method("is_lit") else "?",
		_dog.breed, str(here.snapped(Vector3(0.1, 0.1, 0.1)))])
	for stop in WORST_STOPS:
		_hold(DogAnimations.IDLE, 0.35)
		_frame_at(float(stop))
		await _wait(0.5)
		_aim(WORST_SPOT, WORST_HEIGHT)
		_hold(DogAnimations.IDLE, 0.35)
		await RenderingServer.frame_post_draw
		_measure(_dog.breed, &"idle", float(stop))
		_save("%s-worst-%.0f-warm.png" % [_out, float(stop) * 10.0])

		# And the same frame with NO dog in it, so the animal's own contribution
		# to rule 12's budget is a DIFFERENCE rather than a total. Repainting it
		# navy was the first version and it measured nothing: the warm count is
		# the silhouette, and a navy dog occludes as much warm snow as a gold one.
		_dog.visible = false
		await _wait(0.2)
		_aim(WORST_SPOT, WORST_HEIGHT)
		await RenderingServer.frame_post_draw
		_save("%s-worst-%.0f-control.png" % [_out, float(stop) * 10.0])
		_dog.visible = true
		await _wait(0.2)


func _swap_dog(world: Node3D, breed: StringName, ground: float) -> void:
	if _dog != null:
		_dog.queue_free()
		_dog = null
	_dog = Dog.new()
	_dog.breed = breed
	world.add_child(_dog)
	_dog.global_position = Vector3(SPOT.x, ground, SPOT.y)
	_dog.rotation.y = deg_to_rad(-115.0)


## Play a take and hold it at a fixed fraction, so a frame is a chosen pose
## rather than whatever the clock had reached.
func _hold(state: StringName, where: float) -> void:
	if _dog == null:
		return
	var played := _dog.play(state)
	var player := _dog.player()
	if played == &"" or player == null:
		return
	player.seek(player.get_animation("%s/%s" % [DogAnimations.LIBRARY, played]).length * where, true)


## Where the snow surface is, the way the farmstead settles a building onto it.
func _ground_at(spot: Vector2) -> float:
	var snow := get_node_or_null("Main/SnowField")
	if snow == null or not snow.has_method("surface_height_at"):
		# By capability, not by name, and searching plain `Node` rather than
		# `Node3D` -- `SnowField` is a bare Node in `main.tscn` and the first
		# version of this looked for a Node3D, found nothing, and stood every dog
		# at y = 0 while saying so in a warning nobody would have read as "the
		# picture is wrong".
		for node in (get_node("Main") as Node).find_children("*", "Node", true, false):
			if node.has_method("surface_height_at"):
				snow = node
				break
	if snow == null or not snow.has_method("surface_height_at"):
		push_warning("capture_dogs: no SnowField to settle onto; standing the dog at y = 0")
		return 0.0
	return float(snow.surface_height_at(Vector3(spot.x, 0.0, spot.y)))


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


## The dog's extent in pixels of the SAVED image.
##
## The hull is the posed skeleton, not the mesh's AABB: `Mesh.get_aabb()` on a
## skinned mesh never moves and on these exports is a hundredth of life size.
## Window size rather than the viewport's canvas rect, per briefing trap 10 --
## under `canvas_items` stretch the two disagree by 10-25% and only the window is
## the picture.
func _measure(breed: StringName, state: StringName, stop: float) -> void:
	if _dog == null or _camera == null:
		return
	var window := Vector2(DisplayServer.window_get_size())
	var canvas := get_viewport().get_visible_rect().size
	var scale := window.y / maxf(canvas.y, 1.0)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var world_low := Vector3(INF, INF, INF)
	var world_high := Vector3(-INF, -INF, -INF)
	for node in _dog.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		for bone in range(skeleton.get_bone_count()):
			var at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			world_low = world_low.min(at)
			world_high = world_high.max(at)
			var on_screen := _camera.unproject_position(at)
			low = low.min(on_screen)
			high = high.max(on_screen)
	var centre := _camera.unproject_position(_dog.global_position) * scale
	# ---------------------------------------------------------------------
	# IS THE COAT ACTUALLY ON THE ANIMAL
	# ---------------------------------------------------------------------
	# The Director asked for this to be verified rather than assumed, and the
	# reason is that an unbound map is invisible from every angle except this
	# one: a `StandardMaterial3D` whose `albedo_texture` is null loads without
	# an error, renders the mesh, and renders it in ONE colour. So the frame is
	# asked how many colours the dog occupies. A coat has a body, a chest, paws,
	# a nose and an eye in it; a flat fill has one value and its two shade bands.
	var frame := get_viewport().get_texture().get_image()
	var found: Dictionary = {}
	var x0 := int(low.x * scale)
	var x1 := int(high.x * scale)
	var y0 := int(low.y * scale)
	var y1 := int(high.y * scale)
	for y in range(maxi(0, y0), mini(frame.get_height(), y1 + 1)):
		for x in range(maxi(0, x0), mini(frame.get_width(), x1 + 1)):
			var pixel := frame.get_pixel(x, y)
			# The snow behind it is blue; the dog is not. Everything the animal
			# is made of has more red than the field it stands on.
			if pixel.r - pixel.b > -0.10:
				found[pixel.to_html(false)] = int(found.get(pixel.to_html(false), 0)) + 1
	var ranked: Array = found.keys()
	ranked.sort_custom(func(a, b): return int(found[a]) > int(found[b]))
	var top := PackedStringArray()
	for key in ranked.slice(0, 5):
		top.append("%s x%d" % [key, int(found[key])])
	print("capture_dogs:    coat on screen -- %d distinct colours over the animal: %s" % [
		found.size(), ", ".join(top)])
	# One string literal, not two joined with `+`: `%` binds tighter than `+`, so
	# a split format applies the array to the second half only and Godot reports
	# "String formatting error: a number is required" from a line that looks
	# right. The frame still saves, which is how it survives a glance.
	print("capture_dogs: %-16s %-6s stop %.1f m -> %.0f x %.0f px in a %d px frame (%.2f%% of height); bone hull %s m; centre at %d, %d px" % [
		breed, state, stop, (high.x - low.x) * scale, (high.y - low.y) * scale, int(window.y),
		100.0 * (high.y - low.y) * scale / maxf(window.y, 1.0),
		(world_high - world_low).snapped(Vector3(0.001, 0.001, 0.001)), int(centre.x), int(centre.y)])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("capture_dogs: wrote %s" % path)
