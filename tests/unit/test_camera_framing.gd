extends TestCase

## Shift + wheel steps the frame through three stops, forever.
##
## THE ONE PROPERTY THIS FILE EXISTS TO PROTECT is that the stop the player
## chose is the BASE of a ModifierStack and not the number handed to the camera.
## Wave 4 wants the frame to pull in when he steps inside a building and push
## out during a whiteout, and there are only two ways to build that: stack on
## top of the player's choice, or overwrite it. The second one works perfectly
## on the day it ships and silently throws the player's setting away the first
## time a modifier is registered -- with nothing on screen to say so, because a
## camera at the wrong stop just looks like a camera at a stop. So the seam is
## built and tested now, while there is still nothing registered to notice.
##
## The motion is tested by stepping the Tween by hand rather than by waiting on
## it: `custom_step` is deterministic and the suite runs inside a single
## _process() pass, so nothing advances behind the assertions.

const CameraRigScript := preload("res://src/rendering/camera_rig.gd")
const ModifierScript := preload("res://src/core/modifier.gd")
const EventBusScript := preload("res://src/core/event_bus.gd")

## The Director's three stops, hardcoded here on purpose. Reading them off
## CameraRig.framing_stops would assert that the rig agrees with itself.
const TIGHT := 10.5
const MEDIUM := 13.5
const WIDE := 17.0

## The share of frame height a standing figure occupies at each stop, from the
## Director's table -- the reason the three stops are these three numbers and
## not others. See test_the_stops_are_the_screen_shares_the_director_measured.
const REFERENCE_FIGURE_M := 1.7
const SHARE_TIGHT := 0.114
const SHARE_MEDIUM := 0.089
const SHARE_WIDE := 0.071

var _built: Array[Node] = []


func after_each() -> void:
	# Node is not reference counted (briefing constraint 2). Freeing the rig
	# takes its Camera3D and its in-flight Tween with it -- CameraRig._exit_tree
	# kills the tween, so nothing is left pointing at a dead node.
	for node in _built:
		if is_instance_valid(node):
			node.free()
	_built.clear()


# --- helpers ----------------------------------------------------------------

## A rig outside the tree. Every framing move lands instantly, because
## create_tween() needs a tree -- which is what makes the cycling logic
## testable without one.
func _rig(start_index: int = -1) -> CameraRig:
	var rig: CameraRig = CameraRigScript.new()
	_built.append(rig)
	if start_index >= 0:
		rig.set_framing_index(start_index)
	return rig


## A rig in the tree, so create_tween() works and the motion can be stepped.
## Its _ready() runs the moment it is added: the suite runs from _process(),
## where add_child() fires _ready() immediately (briefing trap 1).
func _live_rig(with_camera := false, start_index: int = -1) -> CameraRig:
	var rig := _rig(start_index)
	if with_camera:
		var camera := Camera3D.new()
		camera.name = "Camera3D"
		rig.add_child(camera)
	Engine.get_main_loop().root.add_child(rig)
	return rig


func _wheel(button: int, shift: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.shift_pressed = shift
	event.pressed = true
	return event


# --- the stops --------------------------------------------------------------

func test_there_are_three_stops_and_they_are_the_directors_numbers() -> void:
	var rig := _rig()
	assert_eq(rig.framing_stops.size(), 3, "three framings were specified")
	assert_almost_eq(rig.framing_stops[0], TIGHT, 0.0001, "the tight stop")
	assert_almost_eq(rig.framing_stops[1], MEDIUM, 0.0001, "the travel stop")
	assert_almost_eq(rig.framing_stops[2], WIDE, 0.0001, "the landscape stop")


## The stops are not chosen sizes, they are chosen *screen shares*: how much of
## the frame's height a standing figure fills. h*cos(pitch)/size, at the rig's
## own 45 degree pitch. Checked rather than trusted, which is what the Director
## published the percentages for.
func test_the_stops_are_the_screen_shares_the_director_measured() -> void:
	var rig := _rig()
	var projected := REFERENCE_FIGURE_M * cos(deg_to_rad(rig.pitch_degrees))
	assert_almost_eq(projected / rig.framing_stops[0], SHARE_TIGHT, 0.0005, "tight")
	assert_almost_eq(projected / rig.framing_stops[1], SHARE_MEDIUM, 0.0005, "medium")
	assert_almost_eq(projected / rig.framing_stops[2], SHARE_WIDE, 0.0005, "wide")


## The player-approved opening is the landscape stop. The tighter two stops
## remain authored choices, but a fresh game starts with the largest view.
func test_the_frame_opens_on_the_widest_authored_stop() -> void:
	var rig := _rig()
	assert_almost_eq(rig.orthographic_size, WIDE, 0.0001, "the authored opening frame")
	assert_eq(rig.framing_index(), 2, "and it is the widest stop, not a value between stops")


# --- cycling ----------------------------------------------------------------

func test_a_notch_out_takes_the_next_stop_out() -> void:
	var rig := _rig(0)
	rig.cycle_framing(1)
	assert_eq(rig.framing_index(), 1, "one notch out is the travel stop")
	assert_almost_eq(rig.framing_base(), MEDIUM, 0.0001, "and the base moved with it")
	rig.cycle_framing(1)
	assert_almost_eq(rig.framing_base(), WIDE, 0.0001, "two notches out is the landscape stop")


func test_past_the_widest_one_more_notch_returns_to_the_tightest() -> void:
	var rig := _rig(0)
	rig.cycle_framing(1)
	rig.cycle_framing(1)
	assert_almost_eq(rig.framing_base(), WIDE, 0.0001, "at the widest")
	rig.cycle_framing(1)
	assert_eq(rig.framing_index(), 0, "the notch past the widest wraps")
	assert_almost_eq(rig.framing_base(), TIGHT, 0.0001, "and lands on the tightest")


func test_past_the_tightest_one_more_notch_returns_to_the_widest() -> void:
	var rig := _rig(0)
	assert_almost_eq(rig.framing_base(), TIGHT, 0.0001, "starting at the tightest")
	rig.cycle_framing(-1)
	assert_eq(rig.framing_index(), 2, "the notch past the tightest wraps")
	assert_almost_eq(rig.framing_base(), WIDE, 0.0001, "and lands on the widest")


## "Wrapping around forever" is the requirement, so it is walked far enough that
## an off-by-one in the wrap would show up rather than cancel itself out.
func test_it_wraps_forever_in_both_directions() -> void:
	var rig := _rig(0)
	var out: Array[int] = []
	for _step in range(7):
		rig.cycle_framing(1)
		out.append(rig.framing_index())
	assert_eq(out, [1, 2, 0, 1, 2, 0, 1], "seven notches out")
	var back: Array[int] = []
	for _step in range(7):
		rig.cycle_framing(-1)
		back.append(rig.framing_index())
	assert_eq(back, [0, 2, 1, 0, 2, 1, 0], "seven notches back in")


# --- the input --------------------------------------------------------------

## The actions live in project.godot, NOT registered at runtime the way
## PlayerController registers its four movement keys -- so this asserts the
## project file, which is the thing that makes them rebindable.
func test_the_framing_actions_are_in_the_input_map() -> void:
	assert_true(
		InputMap.has_action(CameraRigScript.FRAMING_TIGHTER),
		"project.godot must define %s" % CameraRigScript.FRAMING_TIGHTER
	)
	assert_true(
		InputMap.has_action(CameraRigScript.FRAMING_WIDER),
		"project.godot must define %s" % CameraRigScript.FRAMING_WIDER
	)


func test_the_actions_are_shift_and_the_wheel() -> void:
	var wanted := {
		CameraRigScript.FRAMING_TIGHTER: MOUSE_BUTTON_WHEEL_UP,
		CameraRigScript.FRAMING_WIDER: MOUSE_BUTTON_WHEEL_DOWN,
	}
	for action in wanted:
		var events := InputMap.action_get_events(action)
		assert_eq(events.size(), 1, "%s is bound to exactly one event" % action)
		if events.size() != 1:
			continue
		var event := events[0] as InputEventMouseButton
		assert_not_null(event, "%s must be bound to a mouse button" % action)
		if event == null:
			continue
		assert_eq(event.button_index, wanted[action], "%s is on the wrong wheel direction" % action)
		assert_true(event.shift_pressed, "%s must require shift" % action)
		# -1 is ALL_DEVICES. A bound event with any other device id is compared
		# against the real mouse's and never matches, so the action is inert.
		assert_eq(event.device, -1, "%s must accept any device" % action)


func test_shift_and_the_wheel_move_the_frame() -> void:
	var rig := _rig(0)
	assert_true(
		rig.handle_framing_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, true)),
		"shift + wheel down must be taken"
	)
	assert_eq(rig.framing_index(), 1, "wheel down pulls the frame out")
	assert_true(
		rig.handle_framing_input(_wheel(MOUSE_BUTTON_WHEEL_UP, true)),
		"shift + wheel up must be taken"
	)
	assert_eq(rig.framing_index(), 0, "wheel up pushes the frame back in")


## The whole reason the binding carries a modifier: a bare scroll has to keep
## doing whatever else it does, so the rig must neither act on it nor consume it.
func test_a_bare_wheel_is_left_alone() -> void:
	var rig := _rig(0)
	assert_false(
		rig.handle_framing_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, false)),
		"a bare wheel down must not be consumed"
	)
	assert_false(
		rig.handle_framing_input(_wheel(MOUSE_BUTTON_WHEEL_UP, false)),
		"a bare wheel up must not be consumed"
	)
	assert_eq(rig.framing_index(), 0, "and it must not have moved the frame")


func test_something_that_is_not_the_wheel_is_left_alone() -> void:
	var rig := _rig(0)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	assert_false(rig.handle_framing_input(key), "a movement key is not a framing notch")
	assert_eq(rig.framing_index(), 0, "and it must not have moved the frame")


# --- the modifier seam ------------------------------------------------------

## The requirement, stated as an assertion: the player's stop is the BASE.
func test_a_modifier_stacks_on_the_players_stop_instead_of_replacing_it() -> void:
	var rig := _rig(0)
	var pull_in: Modifier = ModifierScript.new()
	pull_in.source_id = &"interior"
	pull_in.operation = Modifier.Operation.ADD
	pull_in.value = -2.0
	rig.push_framing_modifier(pull_in)
	assert_almost_eq(rig.framing_base(), TIGHT, 0.0001, "the player's stop is untouched")
	assert_almost_eq(rig.framing_target(), TIGHT - 2.0, 0.0001, "and the frame is 2 m tighter")
	assert_almost_eq(rig.framed_size(), TIGHT - 2.0, 0.0001, "the camera went with it")


## The failure this whole design exists to prevent: with a modifier registered,
## the player's setting must still be the thing that decides.
func test_the_players_choice_keeps_working_while_a_modifier_is_registered() -> void:
	var rig := _rig(0)
	var whiteout: Modifier = ModifierScript.new()
	whiteout.source_id = &"whiteout"
	whiteout.operation = Modifier.Operation.MULTIPLY
	whiteout.value = 1.2
	rig.push_framing_modifier(whiteout)
	rig.cycle_framing(1)
	assert_almost_eq(rig.framing_base(), MEDIUM, 0.0001, "the notch still moves the base")
	assert_almost_eq(rig.framing_target(), MEDIUM * 1.2, 0.0001, "and the modifier rides on it")
	rig.cycle_framing(1)
	assert_almost_eq(rig.framing_target(), WIDE * 1.2, 0.0001, "and on the next stop too")


func test_removing_the_source_gives_the_player_his_frame_back() -> void:
	var rig := _rig(0)
	var pull_in: Modifier = ModifierScript.new()
	pull_in.source_id = &"interior"
	pull_in.operation = Modifier.Operation.ADD
	pull_in.value = -2.0
	rig.push_framing_modifier(pull_in)
	assert_eq(rig.remove_framing_modifiers(&"interior"), 1, "one modifier came off")
	assert_almost_eq(rig.framed_size(), TIGHT, 0.0001, "and the frame returned to the player's stop")


func test_entering_an_interior_gently_tightens_without_replacing_the_players_stop() -> void:
	var rig := _rig(2)
	var bus = EventBusScript.new()
	_built.append(bus)
	rig.set_event_bus(bus)
	bus.emit_event(&"interior.entered", {"building": "Farmhouse"})
	assert_almost_eq(rig.framing_base(), WIDE, 0.0001,
		"the interior presentation overwrote the player's landscape stop")
	assert_true(rig.framing_target() < WIDE,
		"the open room stayed as small as it was in the travel frame")
	assert_true(rig.framing_target() > MEDIUM,
		"the interior crop discarded too much of the danger outside")


func test_leaving_an_interior_restores_the_players_exact_frame() -> void:
	var rig := _rig(1)
	var bus = EventBusScript.new()
	_built.append(bus)
	rig.set_event_bus(bus)
	bus.emit_event(&"interior.entered", {"building": "Farmhouse"})
	assert_true(rig.framing_target() < MEDIUM, "entering did not tighten the room")
	bus.emit_event(&"interior.exited", {"building": "Farmhouse"})
	assert_almost_eq(rig.framing_base(), MEDIUM, 0.0001,
		"leaving changed the player's chosen stop")
	assert_almost_eq(rig.framing_target(), MEDIUM, 0.0001,
		"the interior camera modifier survived outside")


## A modifier with a duration has to let go on its own, or the frame is stuck
## at whatever the last event asked for and the player's notch does nothing.
func test_a_timed_modifier_releases_the_frame_on_its_own() -> void:
	var rig := _live_rig(false, 0)
	var gust: Modifier = ModifierScript.new()
	gust.source_id = &"gust"
	gust.operation = Modifier.Operation.ADD
	gust.value = 3.0
	gust.duration = 0.5
	rig.push_framing_modifier(gust)
	assert_almost_eq(rig.framing_target(), TIGHT + 3.0, 0.0001, "the gust widened the frame")
	rig._process(0.6)
	assert_eq(rig.framing_modifiers().size(), 0, "the gust expired")
	assert_almost_eq(rig.framing_target(), TIGHT, 0.0001, "and the frame is the player's again")


# --- the motion -------------------------------------------------------------

func test_the_wrap_is_quicker_than_a_notch() -> void:
	var rig := _rig()
	var notch := rig.framing_duration(TIGHT, MEDIUM, false)
	var wrap := rig.framing_duration(WIDE, TIGHT, true)
	assert_true(notch > 0.0, "a notch is eased, not snapped; got %f" % notch)
	assert_true(wrap > 0.0, "the wrap is eased too, just harder; got %f" % wrap)
	assert_true(
		wrap < notch,
		"the wrap covers 1.6x in one step and must not swoop: %f vs the notch's %f" % [wrap, notch]
	)


func test_a_notch_eases_rather_than_snapping() -> void:
	var rig := _live_rig(false, 0)
	rig.cycle_framing(1)
	assert_almost_eq(rig.framed_size(), TIGHT, 0.0001, "the frame must not jump on the keypress")
	var tween := rig.framing_tween()
	assert_not_null(tween, "a notch inside the tree must be animated")
	if tween == null:
		return
	tween.custom_step(rig.framing_notch_seconds * 0.5)
	var halfway := rig.framed_size()
	# Eased out: half the time is well past half the distance. A linear ramp
	# would sit at 12.0 exactly, so this is what tells the two apart.
	assert_true(
		halfway > TIGHT + 0.75 * (MEDIUM - TIGHT),
		"half the time should be most of the way there; got %f" % halfway
	)
	assert_true(halfway < MEDIUM, "but it must not have arrived early; got %f" % halfway)
	tween.custom_step(rig.framing_notch_seconds)
	assert_almost_eq(rig.framed_size(), MEDIUM, 0.0001, "and it lands on the stop")


## Two notches in quick succession must turn around from wherever the camera
## is, not snap to the endpoint and start again.
func test_a_second_notch_turns_around_from_where_the_camera_is() -> void:
	var rig := _live_rig(false, 0)
	rig.cycle_framing(1)
	var out := rig.framing_tween()
	assert_not_null(out, "the first notch is animated")
	if out == null:
		return
	out.custom_step(rig.framing_notch_seconds * 0.25)
	var caught := rig.framed_size()
	assert_true(caught > TIGHT and caught < MEDIUM, "caught mid-flight at %f" % caught)

	rig.cycle_framing(-1)
	var back := rig.framing_tween()
	assert_not_null(back, "the second notch is animated too")
	if back == null:
		return
	assert_almost_eq(
		rig.framed_size(), caught, 0.0001,
		"the reversal must begin where the frame actually is, not at the stop it was heading for"
	)
	back.custom_step(rig.framing_notch_seconds)
	assert_almost_eq(rig.framed_size(), TIGHT, 0.0001, "and it comes all the way home")


func test_the_camera_is_given_the_widest_default_frame_the_rig_resolved() -> void:
	var rig := _live_rig(true)
	var camera := rig.get_node_or_null("Camera3D") as Camera3D
	assert_not_null(camera, "the rig found its camera")
	if camera == null:
		return
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "still a parallel projection")
	assert_almost_eq(camera.size, WIDE, 0.0001, "the camera opens at the widest authored stop")
	rig.cycle_framing(-1)
	var tween := rig.framing_tween()
	if tween != null:
		tween.custom_step(rig.framing_notch_seconds * 2.0)
	assert_almost_eq(camera.size, MEDIUM, 0.0001, "and the notch reaches the projection")


func test_a_transient_composition_offset_moves_and_exactly_restores_the_camera() -> void:
	var rig := _live_rig(true)
	var camera := rig.camera()
	assert_not_null(camera, "the composed shot needs the rig's optical surface")
	if camera == null:
		return
	var authored := camera.position
	rig.set_composition_offset(Vector2(-1.25, 0.18))
	assert_eq(rig.composition_offset(), Vector2(-1.25, 0.18))
	assert_almost_eq(camera.position.x, -1.25, 0.0001,
		"the optical centre did not move laterally")
	assert_almost_eq(camera.position.y, 0.18, 0.0001,
		"the optical centre did not lift")
	rig.set_composition_offset(Vector2.ZERO)
	assert_eq(camera.position, authored,
		"zero composition offset did not restore the authored camera exactly")
	rig.set_boom_factor(0.18)
	assert_almost_eq(camera.position.z, rig.boom_length * 0.18, 0.0001,
		"the transient shot did not physically travel down the boom")
	rig.set_boom_factor(1.0)
	assert_eq(camera.position, authored,
		"restoring the boom factor did not return the optical surface exactly")


## A rig with no Camera3D under it is a legal state -- a test builds one, and so
## does any scene assembled in the wrong order. Cycling must not crash it.
func test_a_rig_with_no_camera_still_cycles() -> void:
	var rig := _rig(0)
	rig.cycle_framing(1)
	assert_almost_eq(rig.framed_size(), MEDIUM, 0.0001, "the framing state moves without a camera")
	assert_eq(rig.framing_index(), 1, "and the stop is remembered for when one arrives")
