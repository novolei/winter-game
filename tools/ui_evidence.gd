## Shared measurements for real UI capture harnesses.
##
## A design token tells a Control what it was asked to draw. This file answers
## what the player was actually delivered after fonts, antialiasing, the world
## behind the Control, and the render target have all had their say. It is kept
## under tools because it reads rendered Images, rather than changing runtime UI.
extends RefCounted

## A changed pixel must clear both capture noise and a one-pixel antialias fringe
## before it is considered authored ink.
const INK_DELTA := 0.02

## P2 readability targets from the approved UI direction. These are intentionally
## higher than the current deep-night baseline; `--verify` is opt-in until the
## readability implementation job changes the delivered picture.
const BODY_CORE_MIN_CONTRAST := 4.5
const GRAPHIC_CORE_MIN_CONTRAST := 3.0

## A transient breath-layer element may occupy at most one percent of the frame.
## This protects the central world without requiring a temporary note to fit
## entirely inside its narrow anchor margin.
const TRANSIENT_MAX_FRAME_OCCUPANCY := 0.01

## A front-of-UI weather layer may obscure no more than this share of key ink for
## more than a quarter second. The current scene has no such layer; the helper is
## here so that a future compositor change is measured rather than asserted by eye.
const MAX_KEY_INK_OCCLUSION := 0.10
const MAX_KEY_INK_OCCLUSION_SECONDS := 0.25


static func luminance(colour: Color) -> float:
	var channels := [colour.r, colour.g, colour.b]
	var linear: Array[float] = []
	for value in channels:
		var channel: float = clampf(value, 0.0, 1.0)
		linear.append(channel / 12.92 if channel <= 0.03928 else pow((channel + 0.055) / 1.055, 2.4))
	return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


static func contrast(a: float, b: float) -> float:
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


## Diff a frozen world plate and a frame with one UI element. `rect` is in the
## canvas coordinate space; Image pixels may differ under canvas_items stretch.
## The returned core is the 10th percentile for dark ink and 90th for light ink,
## avoiding a single ideal pixel or a fringe pixel masquerading as readable text.
static func measure_delivered_ink(
	plate: Image, shot: Image, canvas: Vector2, rect: Rect2
) -> Dictionary:
	if plate == null or shot == null or canvas.x <= 0.0 or canvas.y <= 0.0:
		return {"ok": false, "reason": "missing plate, shot, or canvas"}
	if plate.get_size() != shot.get_size():
		return {"ok": false, "reason": "plate and shot image sizes differ"}
	var bounds := canvas_rect_in_image(shot.get_size(), canvas, rect)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return {"ok": false, "reason": "element rect falls outside the frame"}

	var grounds: Array[float] = []
	var ground_under_ink: Array[float] = []
	var ink: Array[float] = []
	var ink_colours: Array[Color] = []
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var before := plate.get_pixel(x, y)
			var after := shot.get_pixel(x, y)
			var before_l := luminance(before)
			grounds.append(before_l)
			if absf(luminance(after) - before_l) > INK_DELTA:
				ink.append(luminance(after))
				ink_colours.append(after)
				ground_under_ink.append(before_l)
	if grounds.is_empty():
		return {"ok": false, "reason": "no ground pixels sampled"}
	grounds.sort()
	if ink.is_empty():
		return {
			"ok": false,
			"reason": "no delivered ink changed beyond the delta",
			"ground_median": grounds[grounds.size() / 2],
			"bounds": bounds,
		}

	ink.sort()
	ground_under_ink.sort()
	var local_ground: float = ground_under_ink[ground_under_ink.size() / 2]
	var dark_ink := ink[ink.size() / 2] < local_ground
	var core_index := int(float(ink.size() - 1) * (0.10 if dark_ink else 0.90))
	var extreme_index := 0 if dark_ink else ink.size() - 1
	return {
		"ok": true,
		"bounds": bounds,
		"ground_median": grounds[grounds.size() / 2],
		"local_ground": local_ground,
		"ink_pixels": ink.size(),
		"dark_ink": dark_ink,
		"core_luminance": ink[core_index],
		"extreme_luminance": ink[extreme_index],
		"core_contrast": contrast(ink[core_index], local_ground),
		"extreme_contrast": contrast(ink[extreme_index], local_ground),
		"extreme_colour": ink_colours[0],
	}


## Image rectangle corresponding to a canvas-space Control rectangle.
static func canvas_rect_in_image(image_size: Vector2i, canvas: Vector2, rect: Rect2) -> Rect2i:
	if image_size.x <= 0 or image_size.y <= 0 or canvas.x <= 0.0 or canvas.y <= 0.0:
		return Rect2i()
	var scale := Vector2(float(image_size.x) / canvas.x, float(image_size.y) / canvas.y)
	var low := Vector2i(
		int(floor(rect.position.x * scale.x)), int(floor(rect.position.y * scale.y)))
	var high := Vector2i(
		int(ceil(rect.end.x * scale.x)), int(ceil(rect.end.y * scale.y)))
	low.x = clampi(low.x, 0, image_size.x)
	low.y = clampi(low.y, 0, image_size.y)
	high.x = clampi(high.x, 0, image_size.x)
	high.y = clampi(high.y, 0, image_size.y)
	return Rect2i(low, high - low)


## The visual area and clipping status of a transient element. The frame share is
## deliberately based on the Control bounds, not changed pixels: invisible
## whitespace still reserves attention and can become visible in a later state.
static func boundary_occupancy(rect: Rect2, canvas: Vector2) -> Dictionary:
	if canvas.x <= 0.0 or canvas.y <= 0.0:
		return {"ok": false, "reason": "empty canvas"}
	var frame := Rect2(Vector2.ZERO, canvas)
	var area := maxf(rect.size.x, 0.0) * maxf(rect.size.y, 0.0)
	return {
		"ok": true,
		"inside_frame": frame.encloses(rect),
		"area_pixels": area,
		"frame_fraction": area / (canvas.x * canvas.y),
	}


## Anchor rather than containment: a breathing-border element can extend inward
## to be read, but its owning edge must remain in the intended outer band.
static func is_anchored_to_edge(rect: Rect2, canvas: Vector2, edge_pixels: float, edge: StringName) -> bool:
	if canvas.x <= 0.0 or canvas.y <= 0.0 or edge_pixels < 0.0:
		return false
	match edge:
		&"left": return rect.position.x >= -0.5 and rect.position.x <= edge_pixels + 0.5
		&"right": return rect.end.x <= canvas.x + 0.5 and rect.end.x >= canvas.x - edge_pixels - 0.5
		&"top": return rect.position.y >= -0.5 and rect.position.y <= edge_pixels + 0.5
		&"bottom": return rect.end.y <= canvas.y + 0.5 and rect.end.y >= canvas.y - edge_pixels - 0.5
	return false


## Fraction of previously delivered key-ink pixels that are altered by a front
## layer. `clear_ui` and `occluded_ui` must share the same frozen world plate.
static func key_ink_occlusion_fraction(
	plate: Image, clear_ui: Image, occluded_ui: Image, canvas: Vector2, rect: Rect2
) -> Dictionary:
	if plate == null or clear_ui == null or occluded_ui == null:
		return {"ok": false, "reason": "missing occlusion frame"}
	if plate.get_size() != clear_ui.get_size() or plate.get_size() != occluded_ui.get_size():
		return {"ok": false, "reason": "occlusion image sizes differ"}
	var bounds := canvas_rect_in_image(plate.get_size(), canvas, rect)
	var ink_count := 0
	var occluded := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var base := plate.get_pixel(x, y)
			var clear := clear_ui.get_pixel(x, y)
			if absf(luminance(clear) - luminance(base)) <= INK_DELTA:
				continue
			ink_count += 1
			var front := occluded_ui.get_pixel(x, y)
			if absf(luminance(front) - luminance(clear)) > INK_DELTA:
				occluded += 1
	if ink_count == 0:
		return {"ok": false, "reason": "no clear key ink to measure"}
	return {"ok": true, "ink_pixels": ink_count, "occluded_pixels": occluded,
		"fraction": float(occluded) / float(ink_count)}


## Whether samples over time violate the 10% budget continuously for over 250 ms.
static func exceeds_sustained_occlusion(
	samples: Array[float], step_seconds: float,
	budget := MAX_KEY_INK_OCCLUSION, maximum_seconds := MAX_KEY_INK_OCCLUSION_SECONDS
) -> bool:
	if step_seconds <= 0.0:
		return false
	var sustained := 0.0
	for sample in samples:
		if sample > budget:
			sustained += step_seconds
			if sustained > maximum_seconds:
				return true
		else:
			sustained = 0.0
	return false


static func describe(label: String, report: Dictionary, required_contrast := -1.0) -> String:
	if not bool(report.get("ok", false)):
		return "%s: MEASUREMENT FAILED — %s" % [label, str(report.get("reason", "unknown"))]
	var text := "%s: core %.2f:1, extreme %.2f:1, %d ink px over ground %.4f" % [
		label, float(report["core_contrast"]), float(report["extreme_contrast"]),
		int(report["ink_pixels"]), float(report["local_ground"])]
	if required_contrast >= 0.0:
		text += " — %s %.1f:1 gate" % [
			"PASS" if float(report["core_contrast"]) >= required_contrast else "FAIL", required_contrast]
	return text
