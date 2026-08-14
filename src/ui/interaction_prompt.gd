class_name InteractionPrompt
extends Control

## A world-anchored interaction offer: one key ring and one specific action.
##
## This is deliberately one self-drawn Control.  The prompt owns no panel and no
## child Labels, so the valley remains its background and a focus change cannot
## leave a stale child behind.  InteractionDirector owns which offer is focused;
## this node only lays out, draws, and projects that offer.

## UI design section 5.1, in design pixels authored against a 1080 short edge.
const RING_RADIUS_DESIGN_PX := 22.0
const RING_GROOVE_DESIGN_PX := 1.0
const RING_STROKE_DESIGN_PX := 2.0
const GAP_DESIGN_PX := 8.0
const KEY_DESIGN_PX := 15.0
const COPY_DESIGN_PX := 22.0
const COPY_LINE_HEIGHT := 1.25
const ARC_POINTS := 48
const GUIDE_LENGTH_DESIGN_PX := 112.0
const GUIDE_GAP_DESIGN_PX := 8.0
const GUIDE_STROKE_DESIGN_PX := 1.0
const RING_ACCENT_HALO_DESIGN_PX := 5.0

## The full hairline remains under a nearly complete action stroke.  Its small
## lower opening keeps the mark an authored arc rather than a button outline.
const ARC_GAP_RADIANS := 0.34

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _key_font: Font = null
var _copy_font: Font = null

var _key := ""
var _copy := ""
var _viewport := Vector2(1920.0, 1080.0)
var _ground := UIInk.UNKNOWN_GROUND

var _world_anchor := Vector3.ZERO
var _screen_anchor := Vector2.ZERO
var _has_screen_anchor := false
var _hold_progress := 1.0
var _guide_line := false
var _stroke_scale := 1.0
var _accent_color := Color.TRANSPARENT
var _has_accent_color := false
var _guide_color := Color.TRANSPARENT
var _has_guide_color := false


## Builds the immutable content of one focused offer.  Rebuilding is supported:
## the director may reuse one prompt when focus moves instead of allocating a new
## CanvasItem for every Area3D boundary crossing.
func build(
	tokens: UITokens,
	fonts: UIFonts,
	key: String,
	verb: String,
	label := ""
) -> bool:
	_tokens = tokens
	_fonts = fonts
	_key = key.strip_edges()
	var action := verb.strip_edges()
	var subject := String(label).strip_edges()
	_copy = action if subject == "" else "%s · %s" % [action, subject]
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE

	_key_font = null
	_copy_font = null
	if _tokens == null or _fonts == null or _key == "" or action == "":
		queue_redraw()
		return false
	_key_font = _fonts.instrument
	_copy_font = _fonts.interface_at(
		_tokens.breath_latin_weight,
		_tokens.breath_cjk_weight
	)
	if _key_font == null or _copy_font == null:
		queue_redraw()
		return false
	layout_for(_viewport)
	return true


func is_ready() -> bool:
	return _tokens != null and _key_font != null and _copy_font != null \
		and _key != "" and _copy != ""


func key_text() -> String:
	return _key


func copy_text() -> String:
	return _copy


## The brightness behind the prompt, sampled by its owner when focus changes.
## UIInk chooses between existing palette entries; this class never makes one.
func set_ground(value: float) -> void:
	if not is_finite(value):
		return
	_ground = clampf(value, 0.0, 1.0)
	queue_redraw()


func ground() -> float:
	return _ground


## UI document section 4.2's stroke-bold aid: every stroke this prompt draws
## doubles. Refused values leave the current scale alone.
func set_stroke_scale(scale: float) -> void:
	if not is_finite(scale) or scale <= 0.0:
		return
	_stroke_scale = scale
	queue_redraw()


func stroke_scale() -> float:
	return _stroke_scale


## Zero-to-one completion shown by the authored action stroke. Tap offers leave
## this at one; hold offers set it to zero and advance it without rebuilding.
func set_hold_progress(value: float) -> void:
	if not is_finite(value):
		return
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, _hold_progress):
		return
	_hold_progress = next
	queue_redraw()


func hold_progress() -> float:
	return _hold_progress


## A guided prompt treats the projected world point as the bottom of a thin
## leader, with the key ring and its copy sitting above that point.
func set_guide_line(enabled: bool) -> void:
	if enabled == _guide_line:
		return
	_guide_line = enabled
	layout_for(_viewport)


func guide_line_enabled() -> bool:
	return _guide_line


## A local interaction accent may colour the charge and leader without changing
## E, the action copy, or any ordinary prompt. Pigeon feeding supplies this from
## its presentation Resource; transparent means the usual adaptive UI ink.
func set_accent_color(value: Color) -> void:
	if not is_finite(value.r) or not is_finite(value.g) \
			or not is_finite(value.b) or not is_finite(value.a):
		return
	_accent_color = value
	_has_accent_color = value.a > 0.0
	queue_redraw()


func has_accent_color() -> bool:
	return _has_accent_color


func accent_color() -> Color:
	return _accent_color


## The leader is deliberately separate from the charge accent: feeding uses a
## quiet grey-black line under a bright green ring.
func set_guide_color(value: Color) -> void:
	for channel in [value.r, value.g, value.b, value.a]:
		if not is_finite(float(channel)):
			return
	_guide_color = value
	_has_guide_color = value.a > 0.0
	queue_redraw()


func has_guide_color() -> bool:
	return _has_guide_color


func guide_color() -> Color:
	return _guide_color


## Exposed as geometry evidence: the straight guide must still leave the visible
## air gap the owner requested below the ring.
func guide_gap_pixels() -> float:
	return _px(GUIDE_GAP_DESIGN_PX)


func guide_line_points() -> PackedVector2Array:
	if not is_ready() or not _guide_line:
		return PackedVector2Array()
	var diameter := _px(RING_RADIUS_DESIGN_PX * 2.0)
	var guide_height := _px(GUIDE_LENGTH_DESIGN_PX)
	var row_height := size.y - guide_height
	var centre := Vector2(diameter * 0.5, row_height * 0.5)
	var radius := maxf(
		_px(RING_RADIUS_DESIGN_PX) - _px(RING_STROKE_DESIGN_PX) * 0.5,
		1.0
	)
	return _guide_geometry(centre, radius)


## Sizes the horizontal key-ring + action composition for the current canvas.
## It does not choose its screen position: that belongs to the world anchor.
func layout_for(viewport_size: Vector2) -> Vector2:
	if _valid_viewport(viewport_size):
		_viewport = viewport_size
	if not is_ready():
		return size

	var diameter := _px(RING_RADIUS_DESIGN_PX * 2.0)
	var gap := _px(GAP_DESIGN_PX)
	var copy_px := _copy_px()
	var copy_height := maxf(
		_copy_font.get_height(copy_px),
		_px(COPY_DESIGN_PX) * COPY_LINE_HEIGHT
	)
	var copy_width := _copy_font.get_string_size(
		_copy, HORIZONTAL_ALIGNMENT_LEFT, -1.0, copy_px
	).x

	var row_height := maxf(diameter, copy_height)
	var guide_height := _px(GUIDE_LENGTH_DESIGN_PX) if _guide_line else 0.0
	var next_size := Vector2(diameter + gap + copy_width, row_height + guide_height)
	# Clear the previous minimum first so toggling a guide off can shrink a
	# prompt that was already laid out in guided mode.
	custom_minimum_size = Vector2.ZERO
	size = next_size
	custom_minimum_size = next_size
	pivot_offset = Vector2(diameter * 0.5, row_height * 0.5) \
		if _guide_line else size * 0.5
	if _has_screen_anchor:
		_place_at_screen_anchor()
	queue_redraw()
	return size


## The stable world point supplied by an interaction offer.  It is data, not a
## Node reference, so a prompt remains safe if the offering entity is freed.
func set_world_anchor(value: Vector3) -> void:
	if value.is_finite():
		_world_anchor = value


func world_anchor() -> Vector3:
	return _world_anchor


## Thin vocabulary aliases for callers whose offer payload says world_position.
func set_world_position(value: Vector3) -> void:
	set_world_anchor(value)


func world_position() -> Vector3:
	return world_anchor()


## Projects the stored anchor. Ordinary prompts centre on it; guided prompts
## put the leader's lower tip on it. False means the anchor cannot currently be
## drawn (no live camera, behind it, or off-canvas).
## The caller may invoke this as the fixed camera moves; no process loop lives in
## the prompt itself.
func project_world_anchor(
	camera: Camera3D,
	viewport_size := Vector2.ZERO
) -> bool:
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		_has_screen_anchor = false
		visible = false
		return false
	if camera.is_position_behind(_world_anchor):
		_has_screen_anchor = false
		visible = false
		return false

	var canvas := viewport_size
	if not _valid_viewport(canvas):
		var viewport := camera.get_viewport()
		if viewport != null:
			canvas = viewport.get_visible_rect().size
	if not _valid_viewport(canvas):
		_has_screen_anchor = false
		visible = false
		return false

	layout_for(canvas)
	var projected := camera.unproject_position(_world_anchor)
	if not is_finite(projected.x) or not is_finite(projected.y):
		_has_screen_anchor = false
		visible = false
		return false

	_screen_anchor = projected
	_has_screen_anchor = true
	_place_at_screen_anchor()
	visible = Rect2(Vector2.ZERO, canvas).has_point(projected)
	return visible


## The last successfully projected canvas point.  `has_screen_anchor()`
## distinguishes a real (0, 0) from an anchor that has not been projected yet.
func screen_anchor() -> Vector2:
	return _screen_anchor


func has_screen_anchor() -> bool:
	return _has_screen_anchor


func _draw() -> void:
	if not is_ready():
		return
	var diameter := _px(RING_RADIUS_DESIGN_PX * 2.0)
	var guide_height := _px(GUIDE_LENGTH_DESIGN_PX) if _guide_line else 0.0
	var row_height := size.y - guide_height
	var centre := Vector2(diameter * 0.5, row_height * 0.5)
	var radius := maxf(
		_px(RING_RADIUS_DESIGN_PX) - _px(RING_STROKE_DESIGN_PX) * 0.5,
		1.0
	)
	var groove := _accent_color if _has_accent_color else _tokens.line_hairline
	if _tokens.opacity_steps.size() > 3:
		groove.a = _tokens.opacity_steps[3]
	draw_arc(
		centre, radius, 0.0, TAU, ARC_POINTS, groove,
		maxf(_px(RING_GROOVE_DESIGN_PX) * _stroke_scale, 1.0), true
	)
	var ink := UIInk.mark_for(_tokens, _ground)
	if _hold_progress > 0.0:
		var arc_start := -PI * 0.5 + ARC_GAP_RADIANS
		var arc_sweep := TAU - ARC_GAP_RADIANS * 2.0
		var action_colour := _accent_color if _has_accent_color else ink
		if _has_accent_color and _tokens.opacity_steps.size() > 4:
			var halo := action_colour
			halo.a *= _tokens.opacity_steps[4]
			draw_arc(
				centre,
				radius,
				arc_start,
				arc_start + arc_sweep * _hold_progress,
				maxi(int(ceilf(float(ARC_POINTS) * _hold_progress)), 2),
				halo,
				maxf(_px(RING_ACCENT_HALO_DESIGN_PX) * _stroke_scale, 1.0),
				true
			)
		draw_arc(
			centre,
			radius,
			arc_start,
			arc_start + arc_sweep * _hold_progress,
			maxi(int(ceilf(float(ARC_POINTS) * _hold_progress)), 2),
			action_colour,
			maxf(_px(RING_STROKE_DESIGN_PX) * _stroke_scale, 1.0),
			true
		)
	if _guide_line:
		var guide := _guide_color if _has_guide_color else ink
		_draw_guide(_guide_geometry(centre, radius), guide)

	var key_px := _key_px()
	var key_baseline := centre.y \
		+ (_key_font.get_ascent(key_px) - _key_font.get_descent(key_px)) * 0.5
	var key_width := _key_font.get_string_size(
		_key, HORIZONTAL_ALIGNMENT_LEFT, -1.0, key_px
	).x
	draw_string(
		_key_font,
		Vector2(centre.x - key_width * 0.5, key_baseline),
		_key,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		key_px,
		ink
	)

	var copy_px := _copy_px()
	var copy_baseline := row_height * 0.5 \
		+ (_copy_font.get_ascent(copy_px) - _copy_font.get_descent(copy_px)) * 0.5
	draw_string(
		_copy_font,
		Vector2(diameter + _px(GAP_DESIGN_PX), copy_baseline),
		_copy,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		copy_px,
		ink
	)


func _px(design_pixels: float) -> float:
	return design_pixels if _tokens == null else _tokens.design_px(design_pixels, _viewport)


func _key_px() -> int:
	return maxi(int(roundf(_px(KEY_DESIGN_PX))), 1)


func _copy_px() -> int:
	return maxi(int(roundf(_px(COPY_DESIGN_PX))), 1)


func _guide_geometry(centre: Vector2, radius: float) -> PackedVector2Array:
	var start := Vector2(
		centre.x,
		centre.y + radius + _px(GUIDE_GAP_DESIGN_PX)
	)
	var finish := Vector2(centre.x, size.y)
	return PackedVector2Array([start, finish])


func _draw_guide(
	points: PackedVector2Array,
	colour: Color
) -> void:
	if points.size() < 2:
		return
	# One crisp, opaque stroke. Its grey-black authored colour already keeps the
	# leader subordinate to the green ring; no transparency or halo is applied.
	draw_line(
		points[0],
		points[1],
		colour,
		maxf(_px(GUIDE_STROKE_DESIGN_PX) * _stroke_scale, 0.75),
		true
	)


func _place_at_screen_anchor() -> void:
	if _guide_line:
		position = Vector2(
			roundf(_screen_anchor.x - _px(RING_RADIUS_DESIGN_PX)),
			roundf(_screen_anchor.y - size.y)
		)
		return
	position = Vector2(
		roundf(_screen_anchor.x - size.x * 0.5),
		roundf(_screen_anchor.y - size.y * 0.5)
	)


static func _valid_viewport(value: Vector2) -> bool:
	return value.is_finite() and value.x > 0.0 and value.y > 0.0
