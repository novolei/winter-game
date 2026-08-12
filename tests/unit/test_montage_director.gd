extends TestCase

## The montage director -- UI design document section 4.5. Camera moves, and the
## narration that stands in the world while they happen.
##
## advance() is public and carries every decision; _process only forwards to it.
## That is the same shape WorldClock, SurvivalSystem and Stove take, and it is
## what lets a whole montage be played out in a test with no SceneTree, no
## viewport and no frames -- including the long-delta case, which is the one a
## person watching it would never think to try.

const DirectorScript := preload("res://src/ui/montage_director.gd")
const UIFontsScript := preload("res://src/ui/ui_fonts.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")
const TOKENS_PATH := "res://data/ui/tokens.tres"

var _tokens: UITokens
var _fonts
var _director: MontageDirector = null
var _camera: Node3D = null
var _bus = null
var _events: Array = []

func before_each() -> void:
	_events = []
	_tokens = ResourceLoader.load(TOKENS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as UITokens
	_fonts = UIFontsScript.new()
	_fonts.build(_tokens)
	_bus = EventBusScript.new()
	for event in [&"montage.started", &"montage.shot_started", &"montage.finished"]:
		_bus.subscribe(event, func(payload): _events.append([event, payload]))
	_camera = Node3D.new()
	_director = DirectorScript.new()
	_director.set_camera(_camera)
	_director.set_fonts(_fonts)
	_director.set_tokens(_tokens)
	_director.set_event_bus(_bus)

func after_each() -> void:
	# Node is not reference counted (briefing constraint 2). The director owns
	# its inscriptions, so freeing it takes them too -- which is exactly the
	# ownership the leak test below is checking.
	if _director != null:
		_director.free()
		_director = null
	if _camera != null:
		_camera.free()
		_camera = null
	# UNSUBSCRIBE, AND NOT AS TIDINESS. The callbacks above are lambdas that read
	# `_events`, so each one captures `self` -- and the bus holds the lambda while
	# this object holds the bus. That is a reference cycle, and GDScript's
	# refcounting does not collect cycles: dropping the member alone left every
	# TestCase alive, and with it the whole UIFonts chain it had built. Measured
	# at 112 leaked FontVariation instances, seven per test, plus the TextLine
	# caches hanging off them.
	#
	# src/entities/player/player_controller.gd unsubscribes in _exit_tree() for
	# the same reason. Whatever subscribes has to unsubscribe.
	if _bus != null:
		# clear() first: the callbacks above are lambdas that read `_events`, so
		# each captures `self` while this object holds the bus. That is a
		# reference cycle, and GDScript's refcounting does not collect cycles --
		# dropping the member alone left every TestCase alive, and with it the
		# whole UIFonts chain it had built. Measured at 112 leaked FontVariation
		# instances, seven per test, plus the TextLine caches hanging off them.
		# src/entities/player/player_controller.gd unsubscribes in _exit_tree()
		# for the same reason: whatever subscribes has to unsubscribe.
		_bus.clear()
		# free() second, and this is the half that setting the member to null
		# cannot do. EVENT_BUS EXTENDS NODE -- it has to, to be an autoload -- and
		# Node is not reference counted (briefing constraint 2). Nulling the
		# reference orphans it; it does not free it. Sixteen of them survived to
		# exit, one per test, holding event_bus.gd at a reference count of 16.
		_bus.free()
		_bus = null

func _shot(duration: float, from: Vector3, to: Vector3, text := "") -> MontageShot:
	var shot := MontageShot.new()
	shot.duration = duration
	shot.camera_from = Transform3D(Basis.IDENTITY, from)
	shot.camera_to = Transform3D(Basis.IDENTITY, to)
	shot.text = text
	shot.text_transform = Transform3D(Basis.IDENTITY, Vector3(13.0, 2.0, -12.0))
	shot.text_start = 0.2
	# Linear, so the assertions below are about the director rather than about
	# an easing curve that is tested in its own file.
	shot.camera_ease = 0.0
	return shot

func _montage(shots: Array[MontageShot]) -> Montage:
	var montage := Montage.new()
	montage.id = &"test"
	montage.shots = shots
	return montage

# --- refusals ---------------------------------------------------------------

func test_it_refuses_nothing_to_play() -> void:
	assert_false(_director.play(null))
	assert_false(_director.is_playing())

## An empty montage would otherwise "finish" on the first frame, which is the
## shape of bug WorldClock.start() already had to be hardened against: a run that
## ends before it begins, announced as an ending.
func test_it_refuses_a_montage_with_no_shots() -> void:
	assert_false(_director.play(_montage([])))
	assert_false(_director.is_playing())

# --- the camera -------------------------------------------------------------

func test_playing_puts_the_camera_where_the_first_shot_opens() -> void:
	_director.play(_montage([_shot(4.0, Vector3(0, 0, 0), Vector3(0, 0, -8))]))
	assert_almost_eq(_camera.position.z, 0.0, 0.0001)

func test_the_camera_moves_across_the_shot() -> void:
	_director.play(_montage([_shot(4.0, Vector3(0, 0, 0), Vector3(0, 0, -8))]))
	_director.advance(2.0)
	assert_almost_eq(_camera.position.z, -4.0, 0.001, "halfway through a linear dolly")

func test_the_camera_arrives_where_the_shot_ends() -> void:
	_director.play(_montage([_shot(4.0, Vector3(0, 0, 0), Vector3(0, 0, -8))]))
	_director.advance(3.999)
	assert_almost_eq(_camera.position.z, -8.0, 0.01)

func test_crossing_a_cut_replaces_the_camera_rather_than_sliding_it() -> void:
	_director.play(_montage([
		_shot(2.0, Vector3(0, 0, 0), Vector3(0, 0, -4)),
		_shot(2.0, Vector3(50, 0, 0), Vector3(50, 0, -4)),
	]))
	_director.advance(2.1)
	assert_eq(_director.current_shot_index(), 1)
	assert_almost_eq(_camera.position.x, 50.0, 0.5,
		"the second shot must open at its own camera, not travel there from the first")

## A stalled frame, a debugger pause or a fast-forward can hand over a delta
## longer than a whole shot. Advancing by one shot per call would then let the
## montage fall behind real time for as long as the stall lasted.
func test_one_long_delta_can_cross_several_shots() -> void:
	_director.play(_montage([
		_shot(1.0, Vector3(0, 0, 0), Vector3(0, 0, -1)),
		_shot(1.0, Vector3(10, 0, 0), Vector3(10, 0, -1)),
		_shot(1.0, Vector3(20, 0, 0), Vector3(20, 0, -1)),
	]))
	_director.advance(2.5)
	assert_eq(_director.current_shot_index(), 2, "2.5 s in is the third shot")

func test_the_field_of_view_travels_with_the_shot() -> void:
	var shot := _shot(4.0, Vector3.ZERO, Vector3(0, 0, -8))
	shot.fov_from = 30.0
	shot.fov_to = 50.0
	var camera := Camera3D.new()
	_director.set_camera(camera)
	_director.play(_montage([shot]))
	assert_almost_eq(camera.fov, 30.0, 0.001)
	_director.advance(2.0)
	assert_almost_eq(camera.fov, 40.0, 0.01)
	camera.free()

# --- the narration ----------------------------------------------------------

func test_a_shot_with_no_text_writes_nothing() -> void:
	_director.play(_montage([_shot(4.0, Vector3.ZERO, Vector3(0, 0, -8))]))
	_director.advance(1.0)
	assert_true(_director.current_inscription() == null)

func test_the_line_appears_at_the_authored_moment_and_place() -> void:
	_director.play(_montage([_shot(6.0, Vector3.ZERO, Vector3(0, 0, -8), "长夜将尽")]))
	_director.advance(0.1)
	assert_true(_director.current_inscription() == null, "text_start is 0.2 s, so nothing yet")
	_director.advance(0.3)
	var line := _director.current_inscription()
	assert_not_null(line, "the line should have been written by 0.4 s")
	if line == null:
		return
	assert_eq(line.glyph_count(), 4)
	assert_almost_eq(line.position.x, 13.0, 0.001, "it stands where the shot puts it")
	assert_almost_eq(line.position.z, -12.0, 0.001)

## The inscription belongs to its shot. One left behind would go on standing in
## the valley through every later shot, and through the game after it.
func test_the_line_is_gone_when_its_shot_is() -> void:
	_director.play(_montage([
		_shot(3.0, Vector3.ZERO, Vector3(0, 0, -8), "长夜将尽"),
		_shot(3.0, Vector3(50, 0, 0), Vector3(50, 0, -8)),
	]))
	_director.advance(1.0)
	assert_not_null(_director.current_inscription())
	_director.advance(2.5)
	assert_eq(_director.current_shot_index(), 1)
	assert_true(_director.current_inscription() == null, "the first shot's line outlived its shot")
	assert_eq(_director.live_inscription_count(), 0, "an inscription was left in the scene")

func test_stopping_takes_the_line_with_it() -> void:
	_director.play(_montage([_shot(6.0, Vector3.ZERO, Vector3(0, 0, -8), "长夜将尽")]))
	_director.advance(1.0)
	assert_not_null(_director.current_inscription())
	_director.stop()
	assert_false(_director.is_playing())
	assert_eq(_director.live_inscription_count(), 0)

# --- the run ----------------------------------------------------------------

func test_it_finishes_after_the_last_shot() -> void:
	_director.play(_montage([_shot(2.0, Vector3.ZERO, Vector3(0, 0, -4))]))
	assert_true(_director.is_playing())
	_director.advance(2.5)
	assert_false(_director.is_playing())

func test_advancing_a_finished_montage_does_nothing() -> void:
	_director.play(_montage([_shot(1.0, Vector3.ZERO, Vector3(0, 0, -4))]))
	_director.advance(5.0)
	var index := _director.current_shot_index()
	_director.advance(5.0)
	assert_eq(_director.current_shot_index(), index)
	assert_false(_director.is_playing())

func test_it_announces_the_beginning_each_cut_and_the_end() -> void:
	_director.play(_montage([
		_shot(1.0, Vector3.ZERO, Vector3(0, 0, -1)),
		_shot(1.0, Vector3(10, 0, 0), Vector3(10, 0, -1)),
	]))
	_director.advance(2.5)
	var names: Array = []
	for entry in _events:
		names.append(entry[0])
	assert_true(names.has(&"montage.started"), "no montage.started")
	assert_true(names.has(&"montage.finished"), "no montage.finished")
	assert_eq(names.count(&"montage.shot_started"), 2, "one announcement per shot, no more")

## Whoever wants to skip needs to know how far along it is, and a progress that
## went backwards or past 1 would drive a skip prompt wrong.
func test_progress_runs_from_zero_to_one_and_never_backwards() -> void:
	_director.play(_montage([
		_shot(2.0, Vector3.ZERO, Vector3(0, 0, -4)),
		_shot(2.0, Vector3(10, 0, 0), Vector3(10, 0, -4)),
	]))
	var previous := -1.0
	for i in range(40):
		_director.advance(0.1)
		var p: float = _director.progress()
		assert_true(p >= previous - 0.0001, "progress fell from %.3f to %.3f" % [previous, p])
		assert_true(p <= 1.0001, "progress reached %.3f" % p)
		previous = p
	assert_almost_eq(previous, 1.0, 0.001)
