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
var _film: MontageFilm = null
var _attributes: CameraAttributesPractical = null

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
	_clear_film()

## The film goes with the montage. Left behind it would grade the game.
func _clear_film() -> void:
	if _film == null:
		return
	remove_child(_film)
	_film.free()
	_film = null

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
	_pull_focus()
	if _film != null:
		_film.apply(current_shot().grade if current_shot() != null else null, _elapsed)

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
		_apply_grade(shot.grade)
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
	# The shot's own weight, not section 2.2's screen weight -- see
	# MontageShot.text_weight_cjk for why type standing in the valley needs mass
	# that type on a scrim does not.
	var face: Font = _fonts.display_at(shot.text_weight_latin, shot.text_weight_cjk)
	var emission: float = shot.grade.text_emission if shot.grade != null else 1.0
	line.compose(shot.text, face, _tokens, shot.text_font_size, shot.text_pixel_size, emission)
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

## Puts the far blur just behind the line, every frame.
##
## THE FOCUS IS MEASURED, NOT AUTHORED. The camera is moving in every shot that
## carries a line, so any authored focus distance is wrong on the second frame --
## and wrong in the direction that softens the words, which are the one thing in
## the picture that has to stay sharp.
func _pull_focus() -> void:
	if _attributes == null or _camera == null:
		return
	var shot := current_shot()
	if shot == null or shot.grade == null or not shot.grade.dof_enabled:
		return
	var focus := _camera.global_position.distance_to(shot.text_transform.origin) 		if _camera.is_inside_tree() else _camera.position.distance_to(shot.text_transform.origin)
	_attributes.dof_blur_far_distance = maxf(focus + shot.grade.focus_padding, 0.1)

## Camera3D.environment and Camera3D.attributes are OVERRIDES: they last exactly
## as long as the montage camera does, and the world's own environment resumes
## when it goes. Nothing has to be restored, so nothing can be restored wrongly.
func _apply_grade(grade: MontageGrade) -> void:
	if grade == null or _camera == null:
		return

	if _attributes == null:
		_attributes = CameraAttributesPractical.new()
	_attributes.dof_blur_far_enabled = grade.dof_enabled
	_attributes.dof_blur_far_transition = grade.dof_far_transition
	_attributes.dof_blur_near_enabled = grade.dof_near_enabled
	_attributes.dof_blur_near_distance = grade.dof_near_distance
	_attributes.dof_blur_near_transition = grade.dof_near_transition
	_attributes.dof_blur_amount = grade.dof_amount
	if _camera is Camera3D:
		(_camera as Camera3D).attributes = _attributes

	if _camera is Camera3D:
		var environment := _montage_environment()
		environment.fog_enabled = grade.fog_enabled
		environment.fog_light_color = grade.fog_colour
		environment.fog_density = grade.fog_density
		environment.fog_aerial_perspective = grade.fog_aerial_perspective
		environment.fog_sky_affect = grade.fog_sky_affect
		environment.fog_height = grade.fog_height
		environment.fog_height_density = grade.fog_height_density
		environment.glow_enabled = grade.glow_enabled
		environment.glow_bloom = grade.glow_bloom
		environment.glow_hdr_threshold = grade.glow_hdr_threshold
		environment.glow_strength = grade.glow_strength
		environment.glow_intensity = grade.glow_intensity
		(_camera as Camera3D).environment = environment

	if _film == null and is_inside_tree():
		_film = MontageFilm.new()
		_film.name = "Film"
		add_child(_film)
		_film.build()

## The montage's environment, built from the world's own so the sky, the ambient
## and the tonemap all survive -- this grade ADDS air and glow, it does not
## replace the look the lighting director spent six presets establishing.
func _montage_environment() -> Environment:
	if _camera is Camera3D and (_camera as Camera3D).environment != null:
		return (_camera as Camera3D).environment
	var world := _find_world_environment(get_tree().root if is_inside_tree() else null)
	if world != null and world.environment != null:
		return world.environment.duplicate() as Environment
	return Environment.new()

func _find_world_environment(node: Node) -> WorldEnvironment:
	if node == null:
		return null
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child in node.get_children():
		var found := _find_world_environment(child)
		if found != null:
			return found
	return null

func _finish() -> void:
	_clear_inscription()
	_clear_film()
	_playing = false
	_emit(EVENT_FINISHED, _montage.id if _montage != null else &"")

func _emit(event: StringName, payload) -> void:
	if _bus != null:
		_bus.emit_event(event, payload)
