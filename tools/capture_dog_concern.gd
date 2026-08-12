extends Node

## Photographs the dog's concern badge in the real scene, in daylight, on open
## snow -- which is the acceptance case and the hardest one.
##
##   Godot_console.exe --path <project> res://tools/capture_dog_concern.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/concern
##
## Writes:
##   <out>-stop105.png .. -stop170.png   the same badge at Art Bible rule 1's
##                                       three framing stops, which is where
##                                       "screen-constant" is proved or is not
##   <out>-glyph-<name>.png              every pictograph the survival model can
##                                       ask for, at the tight stop
##   <out>-fill-<pct>.png                one glyph at five levels
##   <out>-approach-<n>.png              the dog at four degrees of concern,
##                                       from a fixed camera
##   <out>-lie.png                       the same dog lying down, once the man
##                                       is well again
##
## ---------------------------------------------------------------------------
## WHY IT INSTANCES `main.tscn` AND NOTHING HERE WRITES TO IT
## ---------------------------------------------------------------------------
## The question is whether a dark navy glyph separates from THIS palette's snow
## under THIS project's two-band cel light at THIS camera's stops. A stage built
## here would answer a question about a stage. `capture_dogs.gd`,
## `capture_crows.gd` and `capture_pigeons.gd` all instance the real scene for
## the same reason, and none of them writes to it.
##
## ---------------------------------------------------------------------------
## THE CONTRAST IS MEASURED OFF THE SAVED FRAME, NOT COMPUTED
## ---------------------------------------------------------------------------
## The palette arithmetic in the readout's header predicts 9.65 : 1 for the
## filled tone against lit snow. That prediction goes through a cel shader, a
## tonemap and an unshaded sprite before it is a pixel, and this project has
## already shipped one colour that arrived on screen SQUARED because of the
## first of those (briefing trap 7). So the badge's own pixels and the snow
## beside them are read back out of the frame and the ratio is printed.

const OUT_DEFAULT := "user://concern"

const TIGHT_STOP := 10.5
const STOPS := [10.5, 13.5, 17.0]

## Open snow west of the farmstead. A legibility test with a building behind it
## is a test of the building.
const SPOT := Vector2(2.0, 6.0)
const LOOK_HEIGHT := 1.2
const SETTLE_SECONDS := 1.5

## Every reading the survival model carries, in the order the stat files load.
const GLYPH_FILL := 0.30

var _out := OUT_DEFAULT
var _camera: Camera3D = null
var _world: Node3D = null
var _dog: Dog = null
var _concern: DogConcern = null
var _model: _Body = null
var _ground := 0.0


## A survival model this tool can drive. `DogConcern` asks it exactly two
## questions, so the stand-in is exactly two answers -- and a capture that drove
## the real autoload would be photographing whatever the clock had reached.
class _Body:
	extends RefCounted
	var values := {}

	func stat_ids() -> Array[StringName]:
		var out: Array[StringName] = []
		for id in values:
			out.append(id)
		return out

	func fraction_of(stat_id: StringName) -> float:
		return float(values.get(stat_id, 1.0))


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--out":
			_out = args[index + 1]
	await _run()
	get_tree().quit()


func _run() -> void:
	_camera = get_node_or_null("Main/CameraRig/Camera3D") as Camera3D
	_world = get_node_or_null("Main") as Node3D
	if _camera == null or _world == null:
		push_error("capture_dog_concern: expected Main/CameraRig/Camera3D")
		return
	# A frame with a random number of birds in it is a different picture every
	# run, and these frames are evidence.
	for flock_name in ["Crows", "Pigeons"]:
		var flock := get_node_or_null("Main/%s" % flock_name)
		if flock != null:
			flock.set("enabled", false)

	await _wait(SETTLE_SECONDS)
	_ground = _ground_at(SPOT)
	print("capture_dog_concern: snow surface at (%.1f, %.1f) is y = %.3f" % [SPOT.x, SPOT.y, _ground])

	_model = _Body.new()
	for stat_id in _stat_ids_on_disk():
		_model.values[stat_id] = 1.0

	_dog = Dog.new()
	_dog.breed = DogAnimations.GOLDEN_RETRIEVER
	_world.add_child(_dog)
	_dog.global_position = Vector3(SPOT.x, _ground, SPOT.y)
	_dog.rotation.y = deg_to_rad(-115.0)
	_concern = DogConcern.new()
	_concern.set_survival_system(_model)
	_dog.add_child(_concern)
	await _wait(0.3)

	await _framing_stops()
	await _every_glyph()
	await _fill_ladder()
	await _approach()
	_dog.queue_free()


## The same badge at the three stops. If it is screen-constant these three are
## the same number of pixels; if it is not, this is where that shows.
func _framing_stops() -> void:
	_set_body(&"thirst", 0.10)
	for stop in STOPS:
		_frame_at(float(stop))
		await _wait(0.3)
		_aim(SPOT, LOOK_HEIGHT)
		_hold_badge()
		await RenderingServer.frame_post_draw
		_measure("stop %.1f m" % float(stop), _save("%s-stop%.0f.png" % [_out, float(stop) * 10.0]))


## Every pictograph the model can ask for. The point is which ones READ, and the
## only way to answer that is to look at all of them at the size they draw at.
func _every_glyph() -> void:
	_frame_at(TIGHT_STOP)
	await _wait(0.3)
	for stat_id in _model.values.keys():
		_set_body(stat_id, GLYPH_FILL)
		_aim(SPOT, LOOK_HEIGHT)
		_hold_badge()
		await RenderingServer.frame_post_draw
		_measure("%s at %.2f" % [stat_id, GLYPH_FILL], _save("%s-glyph-%s.png" % [_out, stat_id]))
	_set_body(&"thirst", 1.0)


## One reading at five levels, so the waterline can be seen moving rather than
## asserted to move.
func _fill_ladder() -> void:
	_frame_at(TIGHT_STOP)
	for level in [0.05, 0.15, 0.25, 0.35, 0.45]:
		_set_body(&"core_temperature", float(level))
		_aim(SPOT, LOOK_HEIGHT)
		_hold_badge()
		await RenderingServer.frame_post_draw
		_save("%s-fill-%02d.png" % [_out, int(round(float(level) * 100.0))])
	print("capture_dog_concern: fill ladder written at %.1f m" % TIGHT_STOP)
	_set_body(&"core_temperature", 1.0)


## THE BEHAVIOUR, which has to read with the badge off screen.
##
## The camera is pinned and the player is pinned; the ONLY thing that changes
## between the four frames is how bad the man is. Two captures are not a
## comparison unless they are the same shot.
func _approach() -> void:
	var man := get_node_or_null("Main/Player") as Node3D
	if man == null:
		print("capture_dog_concern: no Main/Player -- the approach needs somebody to approach")
		return
	# Apart. The first version stood the man exactly where the dog was, so the
	# HORIZONTAL distance was zero, `_walk()` had no direction to move along and
	# the dog held still through all four frames while every printed number
	# looked right. A capture that cannot fail is not evidence.
	man.global_position = Vector3(SPOT.x, _ground, SPOT.y)
	_dog.global_position = Vector3(SPOT.x + 6.5, _ground, SPOT.y + 1.0)
	_concern.set_dog(_dog)
	_concern.set_target(man)
	_concern.set_ground(_ground_provider())
	_frame_at(TIGHT_STOP)
	await _wait(0.3)
	var index := 0
	for fraction in [1.0, 0.6, 0.3, 0.0]:
		_set_body(&"core_temperature", _concern.onset() * float(fraction))
		# Walked, not teleported: the standoff is a place the dog arrives at.
		for _step in range(1500):
			_concern.advance(1.0 / 60.0)
		_aim(SPOT, LOOK_HEIGHT)
		await RenderingServer.frame_post_draw
		var gap := _dog.global_position.distance_to(man.global_position)
		print("capture_dog_concern: concern %.2f -> standoff %.2f m, measured %.2f m, whine every %.1f s, may lie down: %s"
			% [_concern.concern(), _concern.standoff_m(), gap, _concern.whine_period(),
				_concern.may_lie_down()])
		_save("%s-approach-%d.png" % [_out, index])
		index += 1
	# ...and the dog settles again only once the man does.
	_set_body(&"core_temperature", 1.0)
	_concern.advance(0.1)
	var settled := _concern.lie_down()
	_concern.advance(0.1)
	_aim(SPOT, LOOK_HEIGHT)
	await RenderingServer.frame_post_draw
	print("capture_dog_concern: with the man well again, lie_down() -> %s" % settled)
	_save("%s-lie.png" % _out)


func _set_body(stat_id: StringName, fraction: float) -> void:
	for key in _model.values:
		_model.values[key] = 1.0
	_model.values[stat_id] = fraction
	_concern.advance(1.0 / 60.0)


## Freezes the badge at the top of its hold, so the shutter never catches it
## mid-bloom -- a frame of an element halfway through arriving says nothing about
## whether the element is legible.
func _hold_badge() -> void:
	# One tick of the owner first, so the badge is re-anchored for the stop the
	# camera is on now -- its height changes with the framing, and so does the
	# clearance it needs over the animal's head.
	_concern.advance(1.0 / 60.0)
	var readout := _concern.readout()
	if readout == null or not readout.is_live():
		return
	var envelope := readout.breath()
	if envelope == null:
		return
	readout.advance(maxf(0.0, envelope.exit_begins() * 0.5 - readout.age()))


## Reads the badge out of the frame it was just drawn into.
##
## Two versions of this were wrong before this one, and both were wrong in the
## direction that looks like a measurement.
##
## The first hunted for dark pixels across the whole frame and found the dog's
## shadow, a power line and a man in a navy coat -- it reported a badge 139 px
## tall at one stop and 75 at another, for something that is 44 px at both.
##
## The second took the same frame with the badge hidden and DIFFERENCED them. It
## is snowing in this scene, so two consecutive frames differ everywhere a flake
## moved, and the difference filled its box.
##
## What works is the boring one: a box the size of the badge, centred where the
## badge is projected, and a luminance floor. Lit snow measures 0.577 and the
## badge's own fill 0.10, so the floor sits in a gap five times wider than
## itself, and nothing else can be inside a box that small without overlapping
## the badge.
const BADGE_FLOOR := 0.20


func _measure(label: String, saved: String) -> Dictionary:
	var readout := _concern.readout()
	if readout == null or _camera == null:
		return {}
	var window := Vector2(DisplayServer.window_get_size())
	var canvas := get_viewport().get_visible_rect().size
	var scale := window.y / maxf(canvas.y, 1.0)
	# `DisplayServer.window_get_size()`, not the viewport rect: under this
	# project's `canvas_items` stretch the two disagree by 10-25% and only the
	# window matches the saved PNG (briefing trap 10).
	var predicted := readout.screen_height_px(_camera, window.y)
	var centre := _camera.unproject_position(readout.global_position) * scale
	# The SAVED PNG, not the viewport texture. Forward+ hands back a linear
	# buffer before the sRGB encode, so the same pixel measures 0.109 there and
	# 0.022 in the file -- a five-fold difference in exactly the quantity being
	# reported, with nothing to say which one is the picture. The file is the
	# picture (briefing: when a number describes the picture, check it against
	# the picture).
	var frame := Image.load_from_file(saved)
	if frame == null:
		return {}
	var reach := int(predicted * 0.62) + 2
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var darkest := 1.0
	var ground := 0.0
	var counted := 0
	for y in range(maxi(0, int(centre.y) - reach), mini(frame.get_height(), int(centre.y) + reach)):
		for x in range(maxi(0, int(centre.x) - reach), mini(frame.get_width(), int(centre.x) + reach)):
			var lum := _luminance(frame.get_pixel(x, y))
			if lum > BADGE_FLOOR:
				ground = maxf(ground, lum)
				continue
			darkest = minf(darkest, lum)
			counted += 1
			low = low.min(Vector2(x, y))
			high = high.max(Vector2(x, y))
	if counted == 0:
		print("capture_dog_concern: %-24s NOTHING BELOW THE FLOOR -- the badge drew nothing, or nothing dark" % label)
		return {}
	var contrast := (ground + 0.05) / (darkest + 0.05)
	print("capture_dog_concern: %-24s %.1f px tall predicted; its filled part measures %.0f x %.0f px in a %d px frame; darkest badge pixel %.4f against %.4f of snow beside it = %.2f : 1"
		% [label, predicted, high.x - low.x + 1.0, high.y - low.y + 1.0, int(window.y),
			darkest, ground, contrast])
	return {"px": predicted, "contrast": contrast}


func _luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)


func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


func _stat_ids_on_disk() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open("res://data/stats")
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for entry in names:
		if not entry.ends_with(".tres"):
			continue
		var definition := ResourceLoader.load("res://data/stats".path_join(entry)) as StatDefinition
		if definition != null and definition.id != &"":
			out.append(definition.id)
	return out


func _ground_provider():
	var snow := get_node_or_null("Main/SnowField")
	if snow != null and snow.has_method("surface_height_at"):
		return snow
	for node in (get_node("Main") as Node).find_children("*", "Node", true, false):
		if node.has_method("surface_height_at"):
			return node
	return null


func _ground_at(spot: Vector2) -> float:
	var snow = _ground_provider()
	if snow == null:
		push_warning("capture_dog_concern: no SnowField; standing the dog at y = 0")
		return 0.0
	return float(snow.surface_height_at(Vector3(spot.x, 0.0, spot.y)))


## Re-applied before every shutter: the rig follows the player in its own
## `_process`, and a frame taken mid-ease is a frame of a different shot.
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


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _save(path: String) -> String:
	get_viewport().get_texture().get_image().save_png(path)
	print("capture_dog_concern: wrote %s" % path)
	return path
