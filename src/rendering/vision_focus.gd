class_name VisionFocus
extends Node

## 口渴's 画面轻微失焦 -- GDD section 5, and the one readout in it that was
## authored and had nobody listening.
##
## `vision:focus` is published by data/stats/thirst.tres (MULTIPLY 0.85 below
## 0.30) and, until this file, had ZERO consumers: a grep found the generator
## that writes the channel and the test that asserts it is written, and nothing
## that reads it. With no HUD, a player had no way whatever to learn he was
## drying out -- the stat's entire existence was a number in a file.
##
## ---------------------------------------------------------------------------
## WHY THIS IS NOT A SHADER, AND THAT IS NOT A COMPROMISE
## ---------------------------------------------------------------------------
## A .gdshader compiles inside the frame that draws it. This project's suite
## never draws a frame, so a broken shader is invisible to it -- a registered
## open class of false PASS here. A full-screen blur written as a shader would
## therefore ship untested by construction.
##
## The engine's own depth of field needs no shader. It is three property
## assignments on a CameraAttributesPractical, which a headless test can set,
## read back, and be telling the truth about.
##
## ---------------------------------------------------------------------------
## WHY THE BLUR IS UNIFORM, WHICH IS THE OPPOSITE OF WHAT DEPTH OF FIELD IS FOR
## ---------------------------------------------------------------------------
## The obvious configuration -- focus on the man, defocus the background -- is
## the wrong one here, and not by a little.
##
## This frame ALREADY has a depth-graded softening: the air perspective in the
## lighting director's fog, which the Art Bible builds the sense of distance on.
## A second effect that also softens with distance does not read as an eye. It
## reads as the weather closing in, which is a thing this game says with actual
## weather, and it would make 口渴 indistinguishable from a squall.
##
## A dry eye does not defocus the background. It defocuses EVERYTHING, including
## whatever you are looking at. So the far ramp is put at the near plane with a
## short transition: every visible surface is past it, every surface carries the
## same circle of confusion, and the softness belongs to the viewer rather than
## to the air.
##
## Measured across three windows of the real frame -- the figure, a cel band
## boundary, and the far ridge -- as detail kept:
##
##     dof_blur_amount   figure   cel band   far ridge   spread
##          0.0020        91.3%     89.5%      87.3%      4.0 points
##          0.0100        54.7%     46.1%      42.0%     12.7 points
##          0.0200        28.6%     20.2%      13.6%     15.0 points
##
## A convenient consequence, and the reason this is one choice rather than two
## constraints traded off against each other: THE AMOUNTS THAT ARE UNIFORM ARE
## THE SMALL ONES. The shipped blur sits at the top of that table, where the
## picture softens almost evenly; six times it is visibly a distance fade again.
## "Slight" and "not a second aerial perspective" turn out to be the same
## instruction.
##
## ---------------------------------------------------------------------------
## AND WHY IT ARRIVES LATE
## ---------------------------------------------------------------------------
## The briefing separates a CUE ("the world is like this now", credible because
## it lags) from a TELL ("something is coming", credible because it is
## monotonic). This is a cue, and it has the failure mode cues have: the channel
## STEPS from 1.00 to 0.85 on the single frame thirst crosses 0.30, and a picture
## that snaps out of focus in one frame does not read as an eye at all -- it
## reads as the renderer having hiccuped. So the blur is eased toward the
## channel with a real time constant, and both directions use the same one.

## ---------------------------------------------------------------------------
## THE CALIBRATION
## ---------------------------------------------------------------------------
## How much high-frequency detail one unit of `dof_blur_amount` costs the frame,
## MEASURED rather than chosen. tools/capture_vision_focus.gd sweeps the amount
## through the real scene from the game's own camera and reports the mean
## absolute Laplacian of luminance as a percentage of the sharp frame:
##
##     dof_blur_amount   detail kept
##          0.0000          100.0%     (and 99.8% with the attributes attached
##          0.0020           88.4%      but the amount at zero, against 100.0%
##          0.0040           77.4%      with no CameraAttributes on the camera
##          0.0060           66.7%      at all -- so attaching one is free and
##          0.0080           55.9%      regrades nothing. The four sampled
##          0.0100           45.4%      palette hexes are identical across the
##                                      whole sweep.)
##
## Least squares through those five points and the origin gives
##
##     kept = 1 - 55.1 * amount
##
## and the residual is under one point everywhere on the range. The response is
## very slightly convex -- the per-point ratios run 58.0 down to 54.6 -- so the
## fit is an approximation and is stated as one rather than rounded into a law.
##
## THIS CONSTANT IS A RELATIONSHIP, NOT A NUMBER, and the briefing's rule about
## those is why it is written as a response curve to be inverted rather than as
## a blur value someone liked the look of: "如果这个数字改了另一个数字就得跟着改，
## 那它不是常量，是一条应该被测试表达出来的关系."
##
## The relationship is: the picture loses exactly as much detail as the channel
## says the eye has lost. `vision:focus 0.85` means the frame keeps 85% of its
## detail -- so if someone edits thirst.tres to 0.70, the blur follows on its own
## and nobody has to remember a second file. tests/unit/test_vision_focus.gd
## asserts the round trip rather than any particular float.
##
## The one caveat, recorded because it is invisible otherwise: the engine's blur
## radius is in PIXELS, so this curve was measured at 1600x1000 and a very
## different resolution will move it. It is a calibration of a look, not a law.
const DETAIL_LOST_PER_BLUR := 55.1

## Where the blur stops getting worse.
##
## GDD section 5 makes 口渴 a nuisance -- 疲劳无法恢复 -- and not a death. Nothing
## upstream clamps the channel, so a later stat stacking a second multiply onto
## `vision:focus` could hand this a very small number, and without a ceiling the
## screen would go to porridge. 0.010 is the point the sweep above reaches 45%
## detail, which is already far past 轻微.
const MAX_BLUR := 0.010

## Where the far ramp begins, in metres from the lens, and how long it is.
##
## Both as close to the near plane (0.05) as they go. The SnowLens flakes live
## 0.7 to 3.7 m in front of the camera, so a ramp anywhere out in the scene would
## leave the nearest flakes sharp while the world behind them softened -- the
## exact depth-graded look this configuration exists to avoid, and the most
## visible possible place for it.
const FAR_DISTANCE := 0.06
const FAR_TRANSITION := 0.01

## How fast the eye clouds and clears, as a fraction of the remaining gap closed
## per second. Frame-rate independent -- what is fixed is the fraction per
## SECOND, not the fraction per frame.
##
## 0.4 is a time constant of two and a half seconds. Long enough that the
## threshold's step never appears as a step; short enough that a man who drinks
## can see again while he is still standing at the stove.
@export var settle_rate := 0.4

const CHANNEL := &"vision:focus"

var _camera: Camera3D = null
var _survival = null
var _attributes: CameraAttributesPractical = null
var _blur := 0.0


func _ready() -> void:
	_resolve()
	settle_now()


func _process(delta: float) -> void:
	_resolve()
	advance(delta)


## Everything the depth of field pass needs except the amount.
##
## Static and public so the capture harness configures the camera the SAME way
## this node does. A calibration measured against a different configuration
## would be a calibration of something the game never draws, and the numbers
## would look every bit as convincing.
static func configure(attributes: CameraAttributesPractical) -> void:
	if attributes == null:
		return
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = FAR_DISTANCE
	attributes.dof_blur_far_transition = FAR_TRANSITION
	# Near blur would defocus by depth from the other side, re-introducing the
	# gradient the far ramp was flattened to remove.
	attributes.dof_blur_near_enabled = false


# --- the arithmetic, pure ------------------------------------------------------

## The blur that costs the picture exactly as much detail as the eye has lost.
static func blur_for(focus: float) -> float:
	var lost := clampf(1.0 - focus, 0.0, 1.0)
	return minf(lost / DETAIL_LOST_PER_BLUR, MAX_BLUR)


## The inverse: what a given blur leaves. The two together are what the test
## asserts, so neither can drift without the other being caught.
static func detail_kept_at(blur_amount: float) -> float:
	return clampf(1.0 - blur_amount * DETAIL_LOST_PER_BLUR, 0.0, 1.0)


# --- wiring --------------------------------------------------------------------

func set_camera(camera: Camera3D) -> void:
	_camera = camera


func set_survival_system(system) -> void:
	_survival = system


func has_camera() -> bool:
	return _camera != null


func has_survival_system() -> bool:
	return _survival != null


## get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is a
## node under /root and never enters the engine's singleton registry (briefing
## trap 3). Written the plausible-looking way this file would read the base value
## for ever and the picture would never change, with no HUD to contradict it.
func _resolve() -> void:
	if _survival == null and is_inside_tree():
		_survival = get_node_or_null("/root/SurvivalSystem")


# --- the ease ------------------------------------------------------------------

## Where the blur is heading: the channel, right now, with no lag.
func target() -> float:
	if _survival == null:
		return blur_for(1.0)
	return blur_for(_survival.channel_value(CHANNEL, 1.0))


## Where it actually is, which differs from the target only while it is easing.
func blur() -> float:
	return _blur


func advance(delta: float) -> void:
	if delta > 0.0:
		# Exponential smoothing. The fraction of the gap closed per second is what
		# is fixed, so the ease is the same at 30 fps and at 240.
		_blur = lerpf(_blur, target(), 1.0 - exp(-settle_rate * maxf(delta, 0.0)))
	_apply()


## Straight to wherever the channel says, with no ease at all. For a capture
## harness and for _ready(): a run that begins with a thirsty man should not open
## on a sharp frame that then clouds over for no reason he can see.
func settle_now() -> void:
	_blur = target()
	_apply()


## The one place the camera is written.
##
## A whole eye gets `attributes = null` rather than an attributes object holding
## zero. The depth of field pass is a full-screen compute pass every frame it is
## enabled, and 口渴 is full for most of most runs -- a game that always pays for
## it would be paying for a readout that is almost never showing.
func _apply() -> void:
	if _camera == null:
		return
	if _blur <= 0.0:
		if _camera.attributes == _attributes:
			_camera.attributes = null
		return
	if _attributes == null:
		_attributes = CameraAttributesPractical.new()
		configure(_attributes)
	_attributes.dof_blur_amount = _blur
	if _camera.attributes != _attributes:
		_camera.attributes = _attributes
