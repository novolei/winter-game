class_name MontageDirector
extends Node3D

## Plays a Montage: camera moves, and the narration that stands in the world
## while they happen. UI design document sections 4.5 and 5.9.
##
## ---------------------------------------------------------------------------
## advance() IS PUBLIC AND CARRIES EVERYTHING
## ---------------------------------------------------------------------------
## _process only forwards to it -- the same shape WorldClock, SurvivalSystem and
## Stove take. A whole montage can then be played out in a test with no
## SceneTree, no viewport and no frames, which is what makes the long-delta case
## checkable at all: a stalled frame or a debugger pause hands over a delta
## longer than a whole shot, and nobody watching a montage would think to try it.
##
## ---------------------------------------------------------------------------
## THE DIRECTOR OWNS THE INSCRIPTIONS
## ---------------------------------------------------------------------------
## A line belongs to its shot. One left behind goes on standing in the valley
## through every later shot and through the game after it -- and being world
## geometry rather than an overlay, it would still be there when the player walks
## past. So the cut frees it, stop() frees it, and the director being freed
## frees it, because it is a child.
##
## ---------------------------------------------------------------------------
## WHY THE CAMERA IS INJECTED RATHER THAN OWNED
## ---------------------------------------------------------------------------
## The montage needs a PERSPECTIVE camera and the game's is orthographic (Art
## Bible rule 1) -- an orthographic dolly changes framing and nothing else, and
## spatial typography is made entirely of the perspective change. Whoever sets
## the montage up decides which camera that is, and a test hands over a bare
## Node3D. Anything with a transform will do; the field of view is only written
## when the target actually has one.

const EVENT_STARTED := &"montage.started"
const EVENT_SHOT_STARTED := &"montage.shot_started"
const EVENT_FINISHED := &"montage.finished"

var _montage: Montage = null
var _camera: Node3D = null
var _fonts = null
var _tokens: UITokens = null
var _bus = null

var _elapsed := 0.0
var _shot_index := -1
var _playing := false
var _inscription: Inscription = null
var _written := false

# --- wiring ------------------------------------------------------------------

func _ready() -> void:
	# get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is a
	# node under /root and never enters the engine's singleton registry (briefing
	# trap 3). A null bus is legal -- _emit() guards -- which is exactly why
	# getting this wrong would be silent.
	if _bus == null and is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")

func set_camera(camera: Node3D) -> void:
	_camera = camera

func set_fonts(fonts) -> void:
	_fonts = fonts

func set_tokens(tokens: UITokens) -> void:
	_tokens = tokens

func set_event_bus(bus) -> void:
	_bus = bus

# --- the run -----------------------------------------------------------------

## Begins a montage. Returns whether it actually began one.
##
## IT REFUSES AN EMPTY MONTAGE, and that guard is not politeness. A montage with
## no shots has a total of zero, so the first advance() would find itself past
## the end and fire EVENT_FINISHED -- an ending announced before anything began.
## WorldClock.start() had to be hardened against the identical shape, and there
## it silently ended the whole game on frame one.
func play(montage: Montage) -> bool:
	if montage == null or montage.shot_count() == 0:
		return false
	_montage = montage
	_elapsed = 0.0
	_shot_index = -1
	_playing = true
	_emit(EVENT_STARTED, montage.id)
	_enter_shot(0)
	_apply_camera(0.0)
	return true

func stop() -> void:
	_playing = false
	_clear_inscription()

func advance(delta: float) -> void:
	if not _playing or _montage == null:
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta

	var located := _montage.locate(_elapsed)
	var index: int = located[0]
	if index < 0:
		# Past the end. Walk whatever shots this delta skipped before finishing,
		# so no transition is lost on the way out.
		_enter_shots_up_to(_montage.shot_count() - 1)
		_finish()
		return
	if index != _shot_index:
		_enter_shots_up_to(index)
	_apply_camera(located[1])
	_drive_text(located[1])

## Enters every shot between the current one and `target`, in order.
##
## ONE LONG DELTA MAY CROSS SEVERAL CUTS -- a stalled frame, a debugger pause, a
## fast-forward -- and jumping straight to the last of them would drop the
## announcements for the ones in between, taking their lighting presets with
## them. WorldClock.advance() loops through phase boundaries for exactly this
## reason and this matches it rather than inventing a second rule.
func _enter_shots_up_to(target: int) -> void:
	for index in range(_shot_index + 1, target + 1):
		_enter_shot(index)

func is_playing() -> bool:
	return _playing

func current_shot_index() -> int:
	return _shot_index

func current_shot() -> MontageShot:
	if _montage == null or _shot_index < 0 or _shot_index >= _montage.shot_count():
		return null
	return _montage.shots[_shot_index]

func current_inscription() -> Inscription:
	return _inscription

func elapsed() -> float:
	return _elapsed

## 0 .. 1 across the whole montage. What a skip prompt reads.
func progress() -> float:
	if _montage == null:
		return 0.0
	var total := _montage.total_seconds()
	if total <= 0.0:
		return 1.0
	return clampf(_elapsed / total, 0.0, 1.0)

## How many inscriptions this director currently has standing in the world. Zero
## outside a shot with text, always -- see the header.
func live_inscription_count() -> int:
	var count := 0
	for child in get_children():
		if child is Inscription:
			count += 1
	return count

func _process(delta: float) -> void:
	advance(delta)

# --- shots -------------------------------------------------------------------

func _enter_shot(index: int) -> void:
	_clear_inscription()
	_shot_index = index
	_written = false
	var shot := current_shot()
	if shot != null:
		_emit(EVENT_SHOT_STARTED, {"index": index, "preset": shot.lighting_preset})

func _apply_camera(local_time: float) -> void:
	var shot := current_shot()
	if shot == null or _camera == null:
		return
	_camera.transform = shot.camera_at(local_time)
	# Only when the target actually has one: a test hands over a bare Node3D, and
	# writing fov onto it would abort the caller.
	if _camera is Camera3D:
		(_camera as Camera3D).fov = shot.fov_at(local_time)

func _drive_text(local_time: float) -> void:
	var shot := current_shot()
	if shot == null or not shot.has_text():
		return
	if local_time < shot.text_start:
		return
	if not _written:
		_write(shot)
	if _inscription != null:
		_inscription.seek(local_time - shot.text_start)

func _write(shot: MontageShot) -> void:
	_written = true
	if _fonts == null or not _fonts.is_ready():
		# No typeface is a reason to say nothing, not a reason to say it in
		# whatever Godot's default face is -- that would read as a design choice.
		return
	var line := Inscription.new()
	add_child(line)
	line.transform = shot.text_transform
	line.compose(shot.text, _fonts.display, _tokens, shot.text_font_size, shot.text_pixel_size)
	line.scatter_along(shot.wind, shot.scatter_metres, shot.scatter_spin)
	line.seek(0.0)
	_inscription = line

func _clear_inscription() -> void:
	if _inscription == null:
		return
	# DETACHED AND FREED AT ONCE, not queue_free()'d, and the first attempt here
	# used queue_free() and leaked.
	#
	# An inscription is a Node3D holding one Label3D per glyph, and every Label3D
	# holds a shaped-text buffer and a font reference on the servers. queue_free()
	# defers the deletion to the end of the frame -- but a montage advanced by a
	# test, a fast-forward or a screenshot harness may never reach one, and the
	# whole line survives to exit as leaked RIDs:
	#
	#   15 RID allocations of type ShapedTextDataAdvanced were leaked at exit
	#
	# That is a dirty console and a failed run by this project's standard, and it
	# is invisible while the game is running normally, because a normal frame does
	# flush the queue. Freeing outright is also what makes live_inscription_count()
	# mean what it says on the same frame as the cut.
	remove_child(_inscription)
	_inscription.free()
	_inscription = null

func _finish() -> void:
	_clear_inscription()
	_playing = false
	_emit(EVENT_FINISHED, _montage.id if _montage != null else &"")

func _emit(event: StringName, payload) -> void:
	if _bus != null:
		_bus.emit_event(event, payload)
