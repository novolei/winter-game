extends Node

## DELIVERED stroke contrast for the interface face at section 2.2's Body rung,
## measured in the real scene, at the size the game really ships.
##
##   Godot_console.exe --path <project> res://tools/measure_type_weight.tscn \
##       --resolution 1920x1080 -- --element note|prompt \
##       [--preset pale_day] [--offset 8,0] [--night] [--weight 500] \
##       [--out D:/somewhere/shot.png]
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS BESIDE capture_threshold_note
## ---------------------------------------------------------------------------
## That harness settled the INK, and its numbers were right: on lit snow the
## note's mark is a flat 8.55 : 1. It also recorded, in its own section 10, that
## the SENTENCE never reaches that value -- 2.03 : 1 at the stroke core.
##
## The reason is not the colour. A stroke thinner than one pixel never receives
## the full ink value: every pixel of it is a blend of ink and the snow behind,
## and the blend is what the player's eye is given. So NOMINAL contrast (what the
## colour would be worth if a stroke covered a pixel) and DELIVERED contrast
## (what the pixels actually carry) are two different numbers, and only the
## second one is legibility.
##
## This instrument reports the second. It is deliberately a separate file: the
## ink harness answers "is this colour separable from that ground", and reading a
## type-weight verdict out of it is exactly the shape of failure this project
## records as 正确的测量，回答错误的问题.
##
## ---------------------------------------------------------------------------
## THE THREE NUMBERS, AND WHY THE MIDDLE ONE IS THE VERDICT
## ---------------------------------------------------------------------------
##   peak       the single strongest ink pixel. One outlier; it says whether the
##              face can reach its own colour at all, not whether it reads.
##   core       the 10th percentile of ink pixels by strength -- the value the
##              strongest tenth of the strokes clears. THIS IS THE VERDICT.
##   covered    the share of ink pixels that reach the ink's own value within
##              COVERAGE_EPSILON. Zero means no pixel of this text is ever the
##              colour it was authored in, which is the finding this tool was
##              built to make visible.
##
## `nominal` is printed beside them: the contrast the same ink would deliver at
## full coverage over this ground. The gap between `nominal` and `core` is the
## whole defect, and quoting `nominal` as the element's contrast is the mistake.
##
## ---------------------------------------------------------------------------
## SIZE: THE CAPTURE RESOLUTION IS PART OF THE MEASUREMENT
## ---------------------------------------------------------------------------
## Design pixels scale off the canvas short edge and the canvas is then scaled to
## the window, and the two cancel only when the window is 16:9. At 1920x1080 a
## Body 17 glyph is rasterised at 17 device pixels -- the shipped size. At
## 1600x1000 the same glyph is 15.7, which is a different and slightly worse
## specimen. Run this at 16:9 unless you mean not to; the header line prints the
## size it actually got so a report cannot quietly be of another size.
##
## ---------------------------------------------------------------------------
## `--weight` OVERRIDES THE TOKEN BEFORE THE FONTS ARE BUILT
## ---------------------------------------------------------------------------
## UILayer loads res://data/ui/tokens.tres in _ready() and ResourceLoader caches
## by path, so the instance it gets is the instance this node mutates in
## _enter_tree() -- which runs first, because _enter_tree is top-down and _ready
## is bottom-up. That is the whole trick, and it is why a sweep runs the shipped
## build path at every weight instead of a rebuilt copy of it.

const DEFAULT_OUTPUT := "user://type_weight.png"

## A pixel counts as ink when the shot moved this far from the plate, in relative
## luminance. Same constant, and same reason, as capture_threshold_note.
const INK_DELTA := 0.02

## How close to the ink's own value a pixel has to land to count as fully
## covered. 2% of the luminance range: below the render's own quantisation at
## eight bits and far below anything a partial coverage produces.
const COVERAGE_EPSILON := 0.02


## The body the note reads, so a state can be measured without inventing a value
## inside the model. SurvivalSystem has no value setter on purpose; see
## capture_threshold_note, which does this the same way for the same reason.
class StubBody:
	extends RefCounted

	var stat := &""
	var fraction := 1.0
	var depleted := false

	func has_stat(id: StringName) -> bool:
		return id == stat

	func fraction_of(id: StringName) -> float:
		return fraction if id == stat else 1.0

	func is_depleted(id: StringName) -> bool:
		return depleted and id == stat

	func net_rate_of(_id: StringName) -> float:
		return 0.0


var _out := DEFAULT_OUTPUT
var _element := "note"
var _preset := ""
var _stat := &"core_temperature"
var _fraction := 0.5
var _night := false
var _weight := 0
var _seconds := 2.0
var _offset := Vector3.ZERO
var _elapsed := 0.0
var _done := false

## THE OVERRIDDEN TOKENS ARE HELD, and that is not tidiness.
##
## ResourceLoader's cache is WEAK. Loading tokens.tres in _enter_tree(), writing
## a weight onto it and letting the local go out of scope frees the resource, and
## UILayer's load in _ready() then reads the file again and gets the authored
## value back. Nothing errors; the sweep simply reports the same numbers at every
## weight, which reads as "the weight axis does nothing" -- the exact wrong
## conclusion, arrived at by an instrument that was measuring correctly.
var _held_tokens: UITokens = null


## Args are read HERE and not in _ready(), because the token override has to land
## before UILayer builds its font chains. See the header.
func _enter_tree() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _string_arg(args, "--out", DEFAULT_OUTPUT)
	_element = _string_arg(args, "--element", _element)
	_preset = _string_arg(args, "--preset", "")
	_stat = StringName(_string_arg(args, "--stat", str(_stat)))
	_fraction = float(_string_arg(args, "--fraction", str(_fraction)))
	_seconds = float(_string_arg(args, "--seconds", str(_seconds)))
	_weight = int(_string_arg(args, "--weight", "0"))
	var move := _string_arg(args, "--offset", "")
	if move != "":
		var parts := move.split(",")
		if parts.size() == 2:
			_offset = Vector3(float(parts[0]), 0.0, float(parts[1]))
	for arg in args:
		if arg == "--night":
			_night = true

	if _weight > 0:
		_held_tokens = ResourceLoader.load("res://data/ui/tokens.tres") as UITokens
		var tokens := _held_tokens
		if tokens == null:
			push_error("measure_type_weight: no tokens to override")
			return
		# Written through set() and READ BACK, rather than assigned. A before/after
		# instrument has to run on the tree that predates the token it is measuring
		# the effect of, and a typed assignment to a property that does not exist
		# yet will not compile there. set() on a missing property does nothing and
		# says nothing, so the read-back is what turns that into a failed run
		# instead of a sweep whose every row is secretly the same weight.
		for field in [&"breath_cjk_weight", &"breath_latin_weight"]:
			tokens.set(field, _weight)
			if int(tokens.get(field)) != _weight:
				push_error("measure_type_weight: this tree has no %s to override" % field)


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
		_measure_element()


func _measure_element() -> void:
	var layer := get_node_or_null("Main/UI")
	if layer == null:
		push_error("measure_type_weight: there is no UI layer in the scene")
		get_tree().quit(1)
		return
	var clock := get_node_or_null("/root/WorldClock")

	if clock != null and _night and not clock.is_night():
		clock.advance(clock.phase_duration() - clock.phase_elapsed() + 0.01)

	if _preset != "":
		# Snapped at the shutter, not at startup: WorldClock announces day 1 on the
		# first frame and sets the director crossfading to that day's own preset, so
		# a look forced earlier is faded away before the shot.
		var lighting := get_node_or_null("Main/Lighting")
		if lighting == null or not lighting.apply_preset(StringName(_preset)):
			push_error("measure_type_weight: no lighting preset '%s'" % _preset)

	if _offset != Vector3.ZERO:
		var player := get_node_or_null("Main/Player")
		if player != null:
			player.global_position += _offset

	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()

	# Everything the scene animates by itself stops here, so the plate and the shot
	# are the same shot. The briefing has already cost this project a round on two
	# captures that were not.
	Engine.time_scale = 0.0
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var plate := get_viewport().get_texture().get_image()

	var built := _surface_prompt(layer) if _element == "prompt" else _surface_note(layer)
	var element = built[0]
	if element == null:
		get_tree().quit(1)
		return
	var text_rect: Rect2 = built[1]
	var nominal_ink: Color = built[2]
	var specimens: Array = built[3]
	var text: String = element.text()

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()

	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var tokens = layer.tokens()
	var body_canvas_px: float = tokens.design_px(ThresholdNote.BODY_DESIGN_PX, canvas)
	var device := Vector2(shot.get_size())
	var body_device_px := body_canvas_px * (device.x / canvas.x)

	print("measure_type_weight: %s, preset %s, weight %s, reading \"%s\"" % [
		_element, _preset if _preset != "" else "(scene default)",
		str(_weight) if _weight > 0 else "(as shipped)", text])
	print("  Body 17 rasterised at %.2f DEVICE px (canvas %.2f px; canvas %.0fx%.0f, frame %.0fx%.0f)" % [
		body_device_px, body_canvas_px, canvas.x, canvas.y, device.x, device.y])
	print("  element %.0f x %.0f px at %.0f, %.0f; text box %.1f x %.1f at %.1f, %.1f" % [
		element.size.x, element.size.y, element.position.x, element.position.y,
		text_rect.size.x, text_rect.size.y, text_rect.position.x, text_rect.position.y])
	_print_face(element, tokens)

	_report(plate, shot, canvas, text_rect, nominal_ink, specimens)

	if shot.save_png(_out) != OK:
		push_error("measure_type_weight: could not write %s" % _out)
	else:
		print("measure_type_weight: wrote ", ProjectSettings.globalize_path(_out))
	_save_element(shot, canvas, text_rect)
	Engine.time_scale = 1.0
	get_tree().quit()


# --- surfacing ----------------------------------------------------------------

## One group of glyphs the ink-gap split is expected to find, left to right.
##
## The opacity belongs HERE and not in the measurement, because two groups on one
## baseline are not always drawn at the same strength: the time prompt puts its
## phase word on section 2.1's 72% rung and its day number at full. A nominal
## figure computed at one alpha for both is wrong for one of them, and it is wrong
## in the flattering direction for the weaker one.
class Specimen:
	extends RefCounted

	var label := ""
	var alpha := 1.0

	func _init(name: String, opacity: float) -> void:
		label = name
		alpha = opacity


## Returns [element, text rect in canvas space, the ink, the specimens in it].
func _surface_note(layer: Node) -> Array:
	var surfacing := get_node_or_null("Main/UI/ThresholdSurfacing")
	var bus := get_node_or_null("/root/EventBus")
	if surfacing == null or bus == null:
		push_error("measure_type_weight: there is no ThresholdSurfacing in the scene")
		return [null, Rect2(), Color.MAGENTA, []]

	var body := StubBody.new()
	body.stat = _stat
	body.fraction = _fraction
	surfacing.readings().set_model(body)
	bus.emit_event(&"survival.threshold_crossed", {
		"stat": _stat, "threshold": 0.5, "comparison": "below",
		"active": true, "value": _fraction, "targets": [],
	})
	surfacing.advance(0.02)

	var note = null
	for child in layer.get_children():
		if child is Control and str(child.name).begins_with("Note_"):
			note = child
	if note == null:
		push_error("measure_type_weight: the crossing surfaced nothing")
		return [null, Rect2(), Color.MAGENTA, []]
	note.finish_growth()

	var tokens = layer.tokens()
	var steps := int(ceil(tokens.bloom_seconds / 0.02)) + 4
	for _step in range(steps):
		layer.advance(0.02)

	# The sentence's own box: everything to the right of the icon, the gap, the arc
	# and its padding. Built from ThresholdNote's own constants so it cannot drift
	# from the layout it is measuring.
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var pad: float = tokens.design_px(VitalStroke.PAD_DESIGN_PX, canvas)
	var words_x: float = (
		tokens.design_px(ThresholdNote.ICON_DESIGN_PX, canvas)
		+ tokens.design_px(ThresholdNote.GAP_DESIGN_PX, canvas) * 2.0
		+ tokens.design_px(ThresholdNote.ARC_DESIGN_PX, canvas) + pad * 2.0)
	return [note, Rect2(
		note.position + Vector2(words_x, 0.0),
		Vector2(maxf(note.size.x - words_x, 1.0), note.size.y)
	), note.words_ink(), [Specimen.new("the sentence (interface, CJK)", 1.0)]]


## Returns [element, the PHASE WORD's box in canvas space, its ink].
##
## The word and the day number share a baseline, and they are not the same
## specimen: the word is CJK in the interface face at section 2.1's 72% rung, the
## number is Latin in the instrument face at full strength. Averaging them would
## report a figure belonging to neither. The split is FOUND rather than
## recomputed -- the widest ink-free column run inside the label band is the space
## between them -- so this tool cannot disagree with the element's own metrics.
func _surface_prompt(layer: Node) -> Array:
	var prompt := get_node_or_null("Main/UI/TimePrompt")
	if prompt == null:
		push_error("measure_type_weight: there is no TimePrompt in the scene")
		return [null, Rect2(), Color.MAGENTA, []]
	var arc = prompt.surface_now()
	if arc == null:
		push_error("measure_type_weight: the prompt refused to surface")
		return [null, Rect2(), Color.MAGENTA, []]

	var tokens = layer.tokens()
	var steps := int(ceil(tokens.bloom_heavy_seconds / 0.02)) + 4
	for _step in range(steps):
		layer.advance(0.02)

	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var data := ResourceLoader.load("res://data/ui/time_prompt.tres") as TimePromptData
	var label_px: float = tokens.design_px(
		data.label_design_px if data != null else ThresholdNote.BODY_DESIGN_PX, canvas)
	var band := label_px * TimeArc.LINE_HEIGHT_RATIO
	return [arc, Rect2(
		arc.position + Vector2(0.0, arc.size.y - band),
		Vector2(arc.size.x, band)
	), arc.ink(), [
		Specimen.new("the phase word (interface, CJK)", TimeArc.OPACITY_WORD),
		Specimen.new("the day number (instrument, Latin)", 1.0),
	]]


## WHAT THE ELEMENT ACTUALLY GOT, asked of the text server rather than inferred
## from what was configured.
##
## This line is not diagnostics left in by accident. The whole reason this task
## existed is that a weight was set, stored, read back correctly, and never
## applied -- so an instrument that reports the weight it ASKED for would have
## agreed with the defect at every row of its own sweep. It reports the
## coordinates the RIDs carry, and the font's own default where a coordinate is
## absent, because Godot drops a coordinate that equals the default.
func _print_face(element, tokens) -> void:
	var asked := "?"
	if tokens != null:
		asked = "%s/%s" % [tokens.get(&"breath_latin_weight"), tokens.get(&"breath_cjk_weight")]
	var font: Font = element.get(&"_body")
	if font == null:
		font = element.get(&"_label_font")
	if font == null:
		print("  face: the element exposes no font to read")
		return
	var ts := TextServerManager.get_primary_interface()
	var got: Array[String] = []
	for rid in font.get_rids():
		var coords: Dictionary = ts.font_get_variation_coordinates(rid)
		var wght: int = int(coords.get(ts.name_to_tag("wght"), -1))
		if wght < 0:
			# Absent means "the font's own default", which is what will render.
			var axes: Dictionary = ts.font_supported_variation_list(rid)
			var axis: Vector3i = axes.get(ts.name_to_tag("wght"), Vector3i(-1, -1, -1))
			got.append("%d (default)" % axis.z if axis.z >= 0 else "static")
		else:
			got.append(str(wght))
	print("  face: asked %s, the %d rid(s) carry [%s], spacing_glyph %d" % [
		asked, font.get_rids().size(), ", ".join(got),
		font.get(&"spacing_glyph") if font.get(&"spacing_glyph") != null else 0])


# --- measurement ---------------------------------------------------------------

## WCAG relative luminance. Written the same way in every instrument in this
## project so two reports can be compared.
static func _luminance(colour: Color) -> float:
	var linear := []
	for value in [colour.r, colour.g, colour.b]:
		var c: float = clampf(value, 0.0, 1.0)
		linear.append(c / 12.92 if c <= 0.03928 else pow((c + 0.055) / 1.055, 2.4))
	return 0.2126 * float(linear[0]) + 0.7152 * float(linear[1]) + 0.0722 * float(linear[2])


static func _contrast(a: float, b: float) -> float:
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


## The element's rect is in CANVAS space and the image is the render target, which
## under `canvas_items` stretch are two different sizes (briefing trap 10). The
## rect is scaled rather than assumed.
func _to_image(canvas: Vector2, rect: Rect2, size: Vector2i) -> Rect2i:
	var scale := Vector2(float(size.x) / canvas.x, float(size.y) / canvas.y)
	var from := Vector2i(
		int(floor(rect.position.x * scale.x)), int(floor(rect.position.y * scale.y)))
	var to := Vector2i(
		int(ceil((rect.position.x + rect.size.x) * scale.x)),
		int(ceil((rect.position.y + rect.size.y) * scale.y)))
	from.x = maxi(from.x, 0)
	from.y = maxi(from.y, 0)
	to.x = mini(to.x, size.x)
	to.y = mini(to.y, size.y)
	return Rect2i(from, to - from)


func _report(
	plate: Image, shot: Image, canvas: Vector2, rect: Rect2,
	ink: Color, specimens: Array
) -> void:
	var box := _to_image(canvas, rect, shot.get_size())
	if box.size.x <= 0 or box.size.y <= 0:
		push_error("measure_type_weight: the text's rect fell outside the frame")
		return

	# Column occupancy first, so the phase word can be separated from the day
	# number by where the ink actually is. See _surface_prompt.
	var columns: Array[int] = []
	columns.resize(box.size.x)
	columns.fill(0)
	for y in range(box.position.y, box.position.y + box.size.y):
		for x in range(box.position.x, box.position.x + box.size.x):
			if absf(_luminance(shot.get_pixel(x, y)) - _luminance(plate.get_pixel(x, y))) > INK_DELTA:
				columns[x - box.position.x] += 1
	var runs := _split_columns(columns)
	# Said out loud rather than absorbed: if the split found a different number of
	# groups than the element is known to draw, every label and every opacity below
	# is attached to the wrong glyphs, and a wrong opacity flatters the weaker
	# specimen.
	if runs.size() != specimens.size():
		print("  WARNING: the ink split into %d group(s), %d expected -- labels below may be misassigned"
			% [runs.size(), specimens.size()])
	for index in range(runs.size()):
		var run: Vector2i = runs[index]
		var specimen: Specimen = specimens[mini(index, specimens.size() - 1)]
		print("  %s -- columns %d..%d at %.0f%% opacity:" % [
			specimen.label, run.x, run.y, specimen.alpha * 100.0])
		_measure(plate, shot, Rect2i(
			Vector2i(box.position.x + run.x, box.position.y),
			Vector2i(run.y - run.x + 1, box.size.y)), ink, specimen.alpha)


## The ink-free gaps inside the band, widest first, used to cut the band into the
## groups of glyphs that are actually separate specimens. A gap has to be at least
## MIN_GAP columns wide to count -- narrower ones are the spaces inside and
## between glyphs of one word.
const MIN_GAP := 4


func _split_columns(columns: Array[int]) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var start := -1
	var gap := 0
	for index in range(columns.size()):
		if columns[index] > 0:
			if start < 0:
				start = index
			elif gap >= MIN_GAP:
				runs.append(Vector2i(start, index - gap - 1))
				start = index
			gap = 0
		elif start >= 0:
			gap += 1
	if start >= 0:
		runs.append(Vector2i(start, columns.size() - 1 - gap))
	return runs


func _measure(plate: Image, shot: Image, box: Rect2i, ink: Color, alpha: float) -> void:
	var ink_l: Array[float] = []
	var ink_colours: Array[Color] = []
	var ground_under: Array[float] = []
	var full: Array[float] = []
	var ground_all: Array[float] = []
	for y in range(box.position.y, box.position.y + box.size.y):
		for x in range(box.position.x, box.position.x + box.size.x):
			var was := plate.get_pixel(x, y)
			var now := shot.get_pixel(x, y)
			var was_l := _luminance(was)
			ground_all.append(was_l)
			if absf(_luminance(now) - was_l) <= INK_DELTA:
				continue
			ink_l.append(_luminance(now))
			ink_colours.append(now)
			ground_under.append(was_l)
			# What this pixel WOULD read if the stroke covered it completely: the
			# authored ink composited over the ground that is really behind it.
			# Computed per pixel because the ground is snow and not a flat plate.
			full.append(_luminance(was.lerp(ink, alpha)))

	if ground_all.is_empty():
		push_error("measure_type_weight: empty box")
		return
	ground_all.sort()
	if ink_l.is_empty():
		print("    NO INK -- nothing changed by more than %.3f" % INK_DELTA)
		return

	var sorted := ink_l.duplicate()
	sorted.sort()
	# WHICH END IS THE STROKE IS ASKED OF THE INK, never of a threshold on the
	# ground: reading it off a constant put the brightest antialiased fringe in a
	# report as the stroke once already.
	var median_ground: float = ground_all[ground_all.size() / 2]
	var dark: bool = sorted[sorted.size() / 2] < median_ground
	var peak: float = sorted[0] if dark else sorted[sorted.size() - 1]
	var core: float = sorted[int(float(sorted.size() - 1) * (0.10 if dark else 0.90))]
	var peak_colour := ink_colours[0]
	for index in range(ink_l.size()):
		if is_equal_approx(ink_l[index], peak):
			peak_colour = ink_colours[index]
			break

	# Sorted as a COPY: `ground_under` stays parallel to `ink_l` and `full`, and a
	# sort in place would silently pair every ink pixel with somebody else's
	# ground.
	var ground_sorted := ground_under.duplicate()
	ground_sorted.sort()
	var local: float = ground_sorted[ground_sorted.size() / 2]
	var nominal := 0.0
	var covered := 0
	for index in range(full.size()):
		nominal += _contrast(full[index], ground_under[index])
		if absf(ink_l[index] - full[index]) <= COVERAGE_EPSILON:
			covered += 1
	nominal /= float(full.size())

	print("    ground %.4f (%s) | ink %d px, peak %s" % [
		local, plate.get_pixel(
			box.position.x + box.size.x / 2, box.position.y + box.size.y / 2
		).to_html(false), ink_l.size(), peak_colour.to_html(false)])
	print("    NOMINAL %.2f : 1  ->  DELIVERED peak %.2f : 1, core %.2f : 1, covered %d/%d (%.1f%%)" % [
		nominal, _contrast(peak, local), _contrast(core, local),
		covered, ink_l.size(), 100.0 * float(covered) / float(ink_l.size())])


# --- picture -------------------------------------------------------------------

const ELEMENT_ZOOM := 4
const ELEMENT_MARGIN_PX := 10


## The text alone, 4x and nearest-neighbour, with a margin of the ground round it.
## NEAREST so the reader sees the pixels that were rendered rather than a
## resampler's opinion of them -- the whole subject here is what one pixel of a
## stroke is worth.
func _save_element(shot: Image, canvas: Vector2, rect: Rect2) -> void:
	var box := _to_image(canvas, rect, shot.get_size())
	var from := Vector2i(
		maxi(box.position.x - ELEMENT_MARGIN_PX, 0),
		maxi(box.position.y - ELEMENT_MARGIN_PX, 0))
	var to := Vector2i(
		mini(box.position.x + box.size.x + ELEMENT_MARGIN_PX, shot.get_size().x),
		mini(box.position.y + box.size.y + ELEMENT_MARGIN_PX, shot.get_size().y))
	var crop := shot.get_region(Rect2i(from, to - from))
	crop.resize(crop.get_width() * ELEMENT_ZOOM, crop.get_height() * ELEMENT_ZOOM,
		Image.INTERPOLATE_NEAREST)
	var path := _out.replace(".png", "-text.png")
	if crop.save_png(path) == OK:
		print("measure_type_weight: wrote ", ProjectSettings.globalize_path(path))
