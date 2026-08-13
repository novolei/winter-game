extends Node

## Screenshot AND contrast harness for UI design document section 5.2's threshold
## note. Runs the real main scene, forces a lighting preset, publishes a real
## `survival.threshold_crossed`, renders a frame, writes a PNG -- and measures
## what the ink is worth against the ground it actually landed on.
##
##   Godot_console.exe --path <project> res://tools/capture_threshold_note.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/shot.png \
##       [--preset pale_day] [--stat core_temperature] [--threshold 0.5] \
##       [--fraction 0.5] [--depleted] [--night] [--seconds 2] \
##       [--offset 8,0] [--ink-ground 0.0]
##
## It writes two files: the frame, and `<out>-element.png` -- the note alone at
## 3x with a margin of the ground round it.
##
## `--offset dx,dz` walks the man before the shutter, which is the only way to
## change the ground under an element that keeps a fixed place on the screen.
## `--ink-ground` overrides what the lighting told the note, so the counterfactual
## can be photographed with the same instrument as the shipped thing.
##
## ---------------------------------------------------------------------------
## TWO FRAMES OF THE SAME SHOT, AND THAT IS THE WHOLE MEASUREMENT
## ---------------------------------------------------------------------------
## A plate is taken with nothing surfaced, the note is then surfaced, and a
## second frame is taken. Every pixel that changed is ink; the plate at those
## same pixels is the ground. So the contrast reported here is the ink against
## the ground it is really standing on, not against an average of the frame and
## not against a number somebody wrote down for a different element.
##
## `Engine.time_scale` is zeroed before the plate, because two frames of a
## snowing valley are not the same shot and the briefing has already cost this
## project a round on exactly that (「在比较两帧之前，先证明它们是同一个镜头」).
##
## ---------------------------------------------------------------------------
## THE READING IS DICTATED, THE ELEMENT IS NOT
## ---------------------------------------------------------------------------
## SurvivalSystem deliberately has no value setter -- a value moves by drain,
## recovery or restore(), so "why did my temperature jump" always has an answer
## in data. A harness that wants a CRITICAL note therefore cannot push the model,
## so it injects a stub body into the surfacing's VitalReadings instead.
##
## Everything downstream of that is the shipped path: the real EventBus, the real
## ThresholdSurfacing, the real ThresholdNote, the real Engraved, the real
## UILayer envelope. Only the number is dictated.

const DEFAULT_OUTPUT := "user://threshold_note.png"
const Evidence := preload("res://tools/ui_evidence.gd")

## A pixel counts as ink when the shot moved this far from the plate, in
## relative luminance. Above the render's own frame-to-frame noise and well
## below anything a stroke does.
const INK_DELTA := 0.02


## The body the note reads, so a state can be photographed without inventing a
## value inside the model. See the header.
class StubBody:
	extends RefCounted

	var stat := &""
	var fraction := 1.0
	var depleted := false
	var net := 0.0

	func has_stat(id: StringName) -> bool:
		return id == stat

	func fraction_of(id: StringName) -> float:
		return fraction if id == stat else 1.0

	func is_depleted(id: StringName) -> bool:
		return depleted and id == stat

	func net_rate_of(_id: StringName) -> float:
		return net


var _out := DEFAULT_OUTPUT
var _preset := ""
var _stat := &"core_temperature"
var _threshold := 0.5
var _fraction := 0.5
var _depleted := false
var _night := false
var _seconds := 2.0
var _offset := Vector3.ZERO
var _ink_ground := -1.0
var _verify := false
var _elapsed := 0.0
var _done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _string_arg(args, "--out", DEFAULT_OUTPUT)
	_preset = _string_arg(args, "--preset", "")
	_stat = StringName(_string_arg(args, "--stat", str(_stat)))
	_threshold = float(_string_arg(args, "--threshold", str(_threshold)))
	_fraction = float(_string_arg(args, "--fraction", str(_fraction)))
	_seconds = float(_string_arg(args, "--seconds", str(_seconds)))
	_ink_ground = float(_string_arg(args, "--ink-ground", "-1"))
	# The note stands in a fixed place on the SCREEN, so the only way to change
	# the ground under it is to change the shot. Walking the man moves the
	# following camera with him, which is how the shade band gets under it.
	var move := _string_arg(args, "--offset", "")
	if move != "":
		var parts := move.split(",")
		if parts.size() == 2:
			_offset = Vector3(float(parts[0]), 0.0, float(parts[1]))
	for arg in args:
		if arg == "--night":
			_night = true
		if arg == "--depleted":
			_depleted = true
		if arg == "--verify":
			_verify = true


func _string_arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed >= _seconds:
		_done = true
		_capture()


func _capture() -> void:
	var clock := get_node_or_null("/root/WorldClock")
	var bus := get_node_or_null("/root/EventBus")
	var surfacing := get_node_or_null("Main/UI/ThresholdSurfacing")
	var layer := get_node_or_null("Main/UI")
	if surfacing == null or layer == null or bus == null:
		push_error("capture_threshold_note: there is no ThresholdSurfacing in the scene")
		get_tree().quit(1)
		return

	if clock != null and _night and not clock.is_night():
		clock.advance(clock.phase_duration() - clock.phase_elapsed() + 0.01)

	if _preset != "":
		# Snapped at the shutter, not at startup: WorldClock announces day 1 on the
		# first frame and sets the director crossfading to that day's own preset,
		# so a look forced in _ready() is faded away before the shot.
		var lighting := get_node_or_null("Main/Lighting")
		if lighting == null or not lighting.apply_preset(StringName(_preset)):
			push_error("capture_threshold_note: no lighting preset '%s'" % _preset)

	if _offset != Vector3.ZERO:
		var player := get_node_or_null("Main/Player")
		if player != null:
			player.global_position += _offset

	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()

	# Everything the scene animates by itself stops here, so the plate and the
	# shot are the same shot. See the header.
	Engine.time_scale = 0.0
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var plate := get_viewport().get_texture().get_image()

	var body := StubBody.new()
	body.stat = _stat
	body.fraction = _fraction
	body.depleted = _depleted
	surfacing.readings().set_model(body)

	bus.emit_event(&"survival.threshold_crossed", {
		"stat": _stat,
		"threshold": _threshold,
		"comparison": "below",
		"active": true,
		"value": _fraction,
		"targets": [],
	})
	# One step clears the stagger for the first note (delay 0) and hands it to the
	# layer, which is what gives it its position and its envelope.
	surfacing.advance(0.02)
	var note = null
	for child in layer.get_children():
		if child is Control and str(child.name).begins_with("Note_"):
			note = child
	if note == null:
		push_error("capture_threshold_note: the crossing surfaced nothing")
		get_tree().quit(1)
		return
	# Overrides what the lighting told the note, so the counterfactual can be
	# photographed with the same instrument as the real thing: `--ink-ground 0`
	# forces section 5.2's own `ink/primary` onto any frame, which is what this
	# element looked like before UIInk existed.
	if _ink_ground >= 0.0:
		note.set_ground(_ink_ground)
	note.finish_growth()

	var tokens = layer.tokens()
	var steps := int(ceil(tokens.bloom_seconds / 0.02)) + 4
	for _step in range(steps):
		layer.advance(0.02)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()

	var canvas: Vector2 = get_viewport().get_visible_rect().size
	print("capture_threshold_note: %s, preset %s, fraction %.2f%s, state %d, reading \"%s\"" % [
		_stat, _preset if _preset != "" else "(scene default)", _fraction,
		", depleted" if _depleted else "", note.state(), note.text()])
	print("  element %.0f x %.0f px at %.0f, %.0f in a %.0f x %.0f canvas" % [
		note.size.x, note.size.y, note.position.x, note.position.y, canvas.x, canvas.y])
	# The ESTIMATE the ink was chosen from, printed beside the ground the frame
	# really has, because the gap between the two is the thing worth knowing.
	print("  ground_for(preset) estimated %.4f -> ink %s" % [
		note.ground(), note.ink().to_html(false)])

	var whole: Dictionary = Evidence.measure_delivered_ink(
		plate, shot, canvas, Rect2(note.position, note.size))
	print(Evidence.describe("  whole element (graphic)", whole, Evidence.GRAPHIC_CORE_MIN_CONTRAST))
	var occupancy: Dictionary = Evidence.boundary_occupancy(Rect2(note.position, note.size), canvas)
	var anchored := Evidence.is_anchored_to_edge(
		Rect2(note.position, note.size), canvas, tokens.edge_pixels(canvas), &"left")
	var occupancy_pass := bool(occupancy.get("inside_frame", false)) \
		and float(occupancy.get("frame_fraction", 1.0)) <= Evidence.TRANSIENT_MAX_FRAME_OCCUPANCY and anchored
	print("  boundary: %.3f%% frame, %s, left-anchor %s — %s" % [
		float(occupancy.get("frame_fraction", 1.0)) * 100.0,
		"in frame" if bool(occupancy.get("inside_frame", false)) else "CLIPPED",
		"PASS" if anchored else "FAIL", "PASS" if occupancy_pass else "FAIL"])
	# AND THE SENTENCE ON ITS OWN, because the sentence is the element. 说后果，
	# 不说数字 -- the icon says which reading and the arc says how far gone, but a
	# player who cannot read 手指不听使唤了 has been told nothing. A number averaged
	# over a 24 px icon, a 2 px stroke and a line of Body 17 answers a question
	# nobody asked.
	var pad: float = tokens.design_px(VitalStroke.PAD_DESIGN_PX, canvas)
	var words_x: float = (
		tokens.design_px(ThresholdNote.ICON_DESIGN_PX, canvas)
		+ tokens.design_px(ThresholdNote.GAP_DESIGN_PX, canvas) * 2.0
		+ tokens.design_px(ThresholdNote.ARC_DESIGN_PX, canvas) + pad * 2.0)
	if note.size.x > words_x:
		var sentence: Dictionary = Evidence.measure_delivered_ink(plate, shot, canvas, Rect2(
			note.position + Vector2(words_x, 0.0), Vector2(note.size.x - words_x, note.size.y)))
		print(Evidence.describe("  the sentence alone (body)", sentence, Evidence.BODY_CORE_MIN_CONTRAST))
		if _verify and (not bool(whole.get("ok", false))
			or float(whole.get("core_contrast", 0.0)) < Evidence.GRAPHIC_CORE_MIN_CONTRAST
			or not bool(sentence.get("ok", false))
			or float(sentence.get("core_contrast", 0.0)) < Evidence.BODY_CORE_MIN_CONTRAST
			or not occupancy_pass):
			Engine.time_scale = 1.0
			push_error("capture_threshold_note: UI evidence gate failed")
			get_tree().quit(1)
			return

	var error := shot.save_png(_out)
	if error != OK:
		push_error("capture_threshold_note: could not write %s (error %d)" % [_out, error])
	else:
		print("capture_threshold_note: wrote ", ProjectSettings.globalize_path(_out))
	# The element on its own, 3x and nearest-neighbour, beside the whole frame.
	# A note 134 canvas px wide is 8% of the picture, and a reviewer looking at
	# the frame is not looking at the thing being reviewed.
	_save_element(shot, canvas, Rect2(note.position, note.size))
	Engine.time_scale = 1.0
	get_tree().quit()


## WCAG relative luminance. The number every contrast figure in this project's
## reports is built on, so it is written once and the same way here.
static func _luminance(colour: Color) -> float:
	var channels := [colour.r, colour.g, colour.b]
	var linear := []
	for value in channels:
		var c: float = clampf(value, 0.0, 1.0)
		linear.append(c / 12.92 if c <= 0.03928 else pow((c + 0.055) / 1.055, 2.4))
	return 0.2126 * float(linear[0]) + 0.7152 * float(linear[1]) + 0.0722 * float(linear[2])


static func _contrast(a: float, b: float) -> float:
	var high := maxf(a, b)
	var low := minf(a, b)
	return (high + 0.05) / (low + 0.05)


## Everything that changed between the plate and the shot is ink; the plate at
## those pixels is the ground.
##
## The element's rect is in CANVAS space and the image is the render target,
## which under `canvas_items` stretch are two different sizes (briefing trap 10).
## The rect is scaled rather than assumed.
func _measure(plate: Image, shot: Image, canvas: Vector2, rect: Rect2) -> void:
	var image_size := shot.get_size()
	var scale := Vector2(float(image_size.x) / canvas.x, float(image_size.y) / canvas.y)
	var from := Vector2i(
		int(floor(rect.position.x * scale.x)), int(floor(rect.position.y * scale.y)))
	var to := Vector2i(
		int(ceil((rect.position.x + rect.size.x) * scale.x)),
		int(ceil((rect.position.y + rect.size.y) * scale.y)))
	from.x = maxi(from.x, 0)
	from.y = maxi(from.y, 0)
	to.x = mini(to.x, image_size.x)
	to.y = mini(to.y, image_size.y)

	var ground_all: Array[float] = []
	var ink: Array[float] = []
	var ground_under_ink: Array[float] = []
	var ink_colours: Array[Color] = []
	for y in range(from.y, to.y):
		for x in range(from.x, to.x):
			var was := plate.get_pixel(x, y)
			var now := shot.get_pixel(x, y)
			var was_l := _luminance(was)
			ground_all.append(was_l)
			if absf(_luminance(now) - was_l) > INK_DELTA:
				ink.append(_luminance(now))
				ink_colours.append(now)
				ground_under_ink.append(was_l)

	if ground_all.is_empty():
		push_error("capture_threshold_note: the element's rect fell outside the frame")
		return
	ground_all.sort()
	var ground := ground_all[ground_all.size() / 2]
	print("  ground under the note: median luminance %.4f (%s), %d px sampled, range %.4f..%.4f" % [
		ground, plate.get_pixel((from.x + to.x) / 2, (from.y + to.y) / 2).to_html(false),
		ground_all.size(), ground_all[0], ground_all[ground_all.size() - 1]])

	if ink.is_empty():
		print("  NO INK FOUND -- nothing in the note's rect changed by more than %.3f" % INK_DELTA)
		return

	# The extreme pixel, which is the convention every other contrast figure in
	# this project's reports uses, and the core of the strokes beside it: one
	# outlier is not a legibility measurement on its own.
	#
	# WHICH END IS THE EXTREME IS ASKED OF THE INK, not of a threshold on the
	# ground. Reading it off a constant put the wrong end of the distribution in a
	# report once already: at dusk the ground sat just under the constant while
	# the ink was the DARK one, so the brightest antialiased fringe was reported
	# as the stroke and a 3.78 : 1 element was written down as 1.07 : 1.
	var sorted_ink := ink.duplicate()
	sorted_ink.sort()
	var dark_ink: bool = sorted_ink[sorted_ink.size() / 2] < ground
	var extreme: float = sorted_ink[0] if dark_ink else sorted_ink[sorted_ink.size() - 1]
	var core_at := int(float(sorted_ink.size() - 1) * (0.10 if dark_ink else 0.90))
	var core: float = sorted_ink[core_at]
	var extreme_colour := ink_colours[0]
	for index in range(ink.size()):
		if is_equal_approx(ink[index], extreme):
			extreme_colour = ink_colours[index]
			break

	ground_under_ink.sort()
	var local_ground: float = ground_under_ink[ground_under_ink.size() / 2]

	print("  ink: %d px, extreme %s luminance %.4f, core (%s pct) luminance %.4f" % [
		ink.size(), extreme_colour.to_html(false), extreme,
		"10th" if dark_ink else "90th", core])
	print("  CONTRAST vs the ground it stands on (%.4f): extreme %.2f : 1, core %.2f : 1" % [
		local_ground, _contrast(extreme, local_ground), _contrast(core, local_ground)])


## The element alone, 3x, nearest-neighbour, written beside the frame as
## `<out>-element.png`. Margin included so the note is seen against the ground it
## is standing on rather than floating on a crop of itself.
const ELEMENT_ZOOM := 3
const ELEMENT_MARGIN_PX := 12


func _save_element(shot: Image, canvas: Vector2, rect: Rect2) -> void:
	var image_size := shot.get_size()
	var scale := Vector2(float(image_size.x) / canvas.x, float(image_size.y) / canvas.y)
	var from := Vector2i(
		int(floor(rect.position.x * scale.x)) - ELEMENT_MARGIN_PX,
		int(floor(rect.position.y * scale.y)) - ELEMENT_MARGIN_PX)
	var to := Vector2i(
		int(ceil((rect.position.x + rect.size.x) * scale.x)) + ELEMENT_MARGIN_PX,
		int(ceil((rect.position.y + rect.size.y) * scale.y)) + ELEMENT_MARGIN_PX)
	from.x = maxi(from.x, 0)
	from.y = maxi(from.y, 0)
	to.x = mini(to.x, image_size.x)
	to.y = mini(to.y, image_size.y)
	var crop := shot.get_region(Rect2i(from, to - from))
	# NEAREST, so the reader sees the pixels that were rendered rather than a
	# resampler's opinion of them.
	crop.resize(crop.get_width() * ELEMENT_ZOOM, crop.get_height() * ELEMENT_ZOOM,
		Image.INTERPOLATE_NEAREST)
	var path := _out.replace(".png", "-element.png")
	if crop.save_png(path) == OK:
		print("capture_threshold_note: wrote ", ProjectSettings.globalize_path(path))
