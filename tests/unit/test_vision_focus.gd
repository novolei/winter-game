extends TestCase

## 口渴's 画面轻微失焦 -- GDD section 5's one readout that was authored and had
## nobody listening.
##
## `vision:focus` has been published in data/stats/thirst.tres since the survival
## channels landed (MULTIPLY 0.85 below 0.30) and had ZERO consumers: a grep for
## it found the generator that writes it and the test that asserts it is written,
## and nothing that reads it. A channel nothing reads is not a readout, it is a
## number in a file -- and with no HUD there was no other way for a player to
## learn he was drying out.
##
## ---------------------------------------------------------------------------
## THE CONSTANT IS TESTED AGAINST THE CHANNEL, NOT AGAINST ITSELF
## ---------------------------------------------------------------------------
## The briefing's rule: "如果这个数字改了另一个数字就得跟着改，那它不是常量，是一条
## 应该被测试表达出来的关系." The blur is exactly that kind of number. It is not
## free to be any value -- it has to be the value that makes the picture lose as
## much detail as the channel says the eye has lost:
##
##     vision:focus 0.85  ->  the frame keeps 85% of its high-frequency energy
##
## So the tests below assert the RELATIONSHIP -- blur_for() inverts the measured
## response of the engine's own depth-of-field pass -- rather than asserting that
## some float equals some other float. Change the channel in thirst.tres and the
## blur follows without anyone remembering to move it; change the calibration and
## a test says which measurement is now stale.
##
## ---------------------------------------------------------------------------
## WHY THERE IS NO SHADER HERE
## ---------------------------------------------------------------------------
## A .gdshader compiles inside the frame that draws it, and this suite never
## draws a frame -- a broken shader is a registered open class of false PASS on
## this project. So the defocus is the engine's own CameraAttributesPractical
## depth of field, which is a property assignment: a headless test can set it,
## read it back, and be telling the truth about what the game will do.

const VisionFocusScript := preload("res://src/rendering/vision_focus.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")
const CameraRigScript := preload("res://src/rendering/camera_rig.gd")

var _focus = null
var _camera: Camera3D = null
var _survival = null
var _built: Array[Node] = []


func after_each() -> void:
	# All of these extend Node, which is not reference counted (briefing
	# constraint 2). The rig is freed first and takes its Camera3D -- and the
	# VisionFocus hanging off it -- with it.
	for node in _built:
		if is_instance_valid(node):
			node.free()
	_built.clear()
	if _focus != null:
		_focus.free()
		_focus = null
	if _camera != null:
		_camera.free()
		_camera = null
	if _survival != null:
		_survival.free()
		_survival = null


func _build() -> void:
	_focus = VisionFocusScript.new()
	_camera = Camera3D.new()
	_focus.set_camera(_camera)


func _body() -> Object:
	_survival = SurvivalSystemScript.new()
	_survival.load_from_directory()
	_survival.start()
	return _survival


## Drops a stat by ADDING to its drain and integrating -- the model has no
## setter, deliberately, so "why did this move" always has an answer in data.
func _drop_to(body, stat_id: StringName, fraction: float) -> void:
	body.push_modifier(stat_id, &"test", Modifier.Operation.ADD, 0.05)
	var guard := 0
	while body.fraction_of(stat_id) > fraction and not body.is_dead() and guard < 40000:
		body.advance(0.25)
		guard += 1
	body.remove_source(&"test")


# --- the relationship ---------------------------------------------------------

func test_a_whole_eye_is_not_blurred_at_all() -> void:
	_build()
	assert_eq(_focus.blur_for(1.0), 0.0,
		"a man with vision:focus 1.0 has nothing wrong with his eyes and the "
		+ "picture must be untouched -- a floor of 'always slightly blurred' "
		+ "would be a permanent cost paid by every player for a stat most of "
		+ "them never drop")


func test_the_blur_delivers_exactly_the_detail_loss_the_channel_names() -> void:
	_build()
	# The inverse of the measured response. If blur_for() and detail_kept_at()
	# disagree, the shipped constant is not delivering what the data file says.
	for focus in [1.0, 0.95, 0.9, 0.85, 0.8, 0.7, 0.6]:
		assert_almost_eq(_focus.detail_kept_at(_focus.blur_for(focus)), focus, 0.001,
			"vision:focus %.2f has to cost %.0f%% of the picture's detail" % [
				focus, 100.0 * (1.0 - focus),
			])


func test_the_blur_is_monotonic_in_the_channel() -> void:
	_build()
	var previous := -1.0
	for focus in [1.0, 0.9, 0.8, 0.7, 0.6, 0.5]:
		var blur: float = _focus.blur_for(focus)
		assert_true(blur > previous,
			"a worse eye must never be a sharper picture; focus %.2f gave %.5f "
			% [focus, blur] + "against %.5f for the step before it" % previous)
		previous = blur


func test_a_ruined_eye_is_still_a_picture() -> void:
	_build()
	# Nothing upstream clamps the channel, so a future stat stacking two
	# multiplies could hand this a very small number. GDD section 5 makes 口渴 a
	# nuisance rather than a death, and a blind screen is not a nuisance.
	assert_true(_focus.blur_for(0.0) <= _focus.MAX_BLUR,
		"the blur must saturate: 口渴 does not blind anybody")
	assert_true(_focus.blur_for(-5.0) <= _focus.MAX_BLUR,
		"and a nonsense channel value must not produce a nonsense picture")


# --- the wiring ---------------------------------------------------------------

func test_a_slaked_man_gets_no_camera_attributes_at_all() -> void:
	_build()
	_focus.set_survival_system(_body())
	_focus.settle_now()
	assert_true(
		_camera.attributes == null or not _camera.attributes.dof_blur_far_enabled,
		"with nothing wrong with him the depth of field pass must be OFF rather "
		+ "than on at zero -- a post-process that always runs is a cost every "
		+ "frame of the game pays for a stat that is usually full")


func test_a_thirsty_man_gets_a_blurred_frame() -> void:
	_build()
	var body := _body()
	_drop_to(body, &"thirst", 0.20)
	_focus.set_survival_system(body)
	_focus.settle_now()
	assert_not_null(_camera.attributes,
		"below thirst 0.30 data/stats/thirst.tres multiplies vision:focus by "
		+ "0.85 and the camera has to have heard about it")
	if _camera.attributes == null:
		# Returning rather than reading through the null, so a regression here is
		# a clean FAIL and not a SCRIPT ERROR -- which on this project is a dirty
		# console and therefore a failed run whatever the summary line says.
		return
	assert_true(_camera.attributes is CameraAttributesPractical,
		"CameraAttributesPractical, not Physical: the Physical one derives its "
		+ "depth of field from a real aperture and focal length, neither of "
		+ "which an orthographic camera has")
	assert_true(_camera.attributes.dof_blur_far_enabled)
	assert_true(_camera.attributes.dof_blur_amount > 0.0,
		"a thirsty man's frame is blurred by more than nothing")


func test_the_frame_is_defocused_uniformly_and_not_by_depth() -> void:
	_build()
	var attributes := CameraAttributesPractical.new()
	_focus.configure(attributes)
	# The whole argument for this configuration in one assertion. A depth-GRADED
	# blur is a second aerial perspective -- this project already has one, in the
	# fog -- and would read as weather rather than as an eye. Putting the far
	# ramp at the near plane means every visible surface is past it and carries
	# the same circle of confusion, so the softness is the viewer's and not the
	# air's.
	assert_true(attributes.dof_blur_far_enabled)
	assert_true(attributes.dof_blur_far_distance <= 0.1,
		"the far ramp has to start at the near plane, not out in the scene")
	assert_true(attributes.dof_blur_far_transition <= 0.1,
		"and it has to be short, or the near ground is sharper than the far")
	assert_false(attributes.dof_blur_near_enabled,
		"near blur would defocus by depth from the other side and undo it")


func test_it_says_nothing_when_it_has_no_model() -> void:
	_build()
	_focus.settle_now()
	assert_eq(_focus.blur(), 0.0,
		"a VisionFocus with no survival system reports a whole eye rather than "
		+ "guessing, the way every other consumer on this project does")
	assert_true(_camera.attributes == null)


func test_it_survives_having_no_camera() -> void:
	_focus = VisionFocusScript.new()
	_focus.set_survival_system(_body())
	_focus.settle_now()
	# No assertion about the picture -- there is not one. The assertion is that
	# the two calls above did not abort, which is what a test in this suite can
	# say about a null guard.
	assert_eq(_focus.blur(), _focus.blur_for(1.0))


# --- the wire itself ----------------------------------------------------------

func test_the_rig_hangs_one_of_these_on_the_camera_it_owns() -> void:
	# THE WIRE, not the unit. Every assertion above this one would pass with the
	# consumer sitting in a file nobody instances -- which is precisely the state
	# `vision:focus` itself was in before this task, and precisely what briefing
	# trap 3 nearly shipped: the only path wiring a system to its collaborator,
	# silently never taken, invisible to a green suite.
	var rig: CameraRig = CameraRigScript.new()
	_built.append(rig)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	# _ready() runs the moment it is added, because the suite runs from
	# _process() (briefing trap 1).
	Engine.get_main_loop().root.add_child(rig)
	var focus := camera.get_node_or_null("VisionFocus")
	assert_not_null(focus,
		"CameraRig must build the consumer onto the camera it owns; without it "
		+ "口渴 is authored, tested, and never once drawn")
	if focus == null:
		return
	assert_true(focus is VisionFocus)
	assert_true(focus.has_camera(),
		"and it must be pointed at that camera, or it will resolve nothing and "
		+ "write nowhere")


func test_building_it_twice_leaves_one() -> void:
	var rig: CameraRig = CameraRigScript.new()
	_built.append(rig)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	Engine.get_main_loop().root.add_child(rig)
	# _ready() has run once. A rig removed and re-added runs it again, and two
	# depth-of-field consumers fighting over one camera would be a bug whose only
	# symptom is a blur that flickers.
	rig._ready()
	var found := 0
	for child in camera.get_children():
		if child is VisionFocus:
			found += 1
	assert_eq(found, 1, "exactly one VisionFocus on the camera, however often "
		+ "the rig is readied")


# --- the lag ------------------------------------------------------------------

func test_the_blur_arrives_late_because_it_is_a_cue_and_not_a_tell() -> void:
	_build()
	var body := _body()
	_drop_to(body, &"thirst", 0.20)
	_focus.set_survival_system(body)
	# NOT settled: the channel steps from 1.0 to 0.85 the instant thirst crosses
	# 0.30, and a picture that snaps out of focus on one frame reads as a bug.
	# The briefing's own rule -- "Building a cue? Give it mass, damping, a
	# period. Let it arrive late." -- is what this asserts.
	var settled: float = _focus.blur_for(body.channel_value(&"vision:focus", 1.0))
	_focus.advance(0.05)
	var early: float = _focus.blur()
	assert_true(early > 0.0, "it has to start moving")
	assert_true(early < settled * 0.5,
		"...and after a twentieth of a second it must be nowhere near arrived; "
		+ "got %.5f of an eventual %.5f" % [early, settled])
	for _step in range(400):
		_focus.advance(0.05)
	assert_almost_eq(_focus.blur(), settled, 0.00001,
		"and it must actually get there in the end")


func test_the_eye_clears_as_fast_as_it_clouded() -> void:
	_build()
	var body := _body()
	_drop_to(body, &"thirst", 0.20)
	_focus.set_survival_system(body)
	_focus.settle_now()
	var clouded: float = _focus.blur()
	assert_true(clouded > 0.0)
	# A drink puts the stat back above the threshold. The same ease carries it
	# home: one constant, both directions, so nothing can be tuned to look right
	# going one way and wrong coming back.
	body.push_modifier(&"thirst", &"drink", Modifier.Operation.ADD, -1.0)
	var guard := 0
	while body.fraction_of(&"thirst") < 0.5 and guard < 40000:
		body.advance(0.25)
		guard += 1
	body.remove_source(&"drink")
	for _step in range(400):
		_focus.advance(0.05)
	assert_almost_eq(_focus.blur(), 0.0, 0.00001,
		"a man who has drunk can see again")
