class_name InteractionReceipt
extends Control

## One short interaction result in the lower-left breathing border.
##
## The valley is the background. This Control draws one tinted glyph, one line
## of copy and an optional tabular amount; it owns no Label, TextureRect or
## panel child. InteractionResultSurfacing owns when it appears and UILayer owns
## its death.

const ICON_DIRECTORY := "res://assets/ui/icons"

const ICON_DESIGN_PX := 24.0
const COPY_DESIGN_PX := 22.0
const AMOUNT_DESIGN_PX := 14.0
const GAP_DESIGN_PX := 8.0
const AMOUNT_GAP_DESIGN_PX := 8.0
const LINE_HEIGHT := 1.25

## The amount is the changed part when one receipt is refreshed, so it blooms
## locally without replaying the whole UILayer entrance.
const UPDATE_BLOOM_SECONDS := 0.20

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _copy_font: Font = null
var _amount_font: Font = null
var _icon: Texture2D = null

var _key: StringName = &""
var _copy := ""
var _amount := ""
var _icon_id: StringName = &"interact"
var _rejected := false
var _viewport := Vector2(1920.0, 1080.0)
var _ground := UIInk.UNKNOWN_GROUND
var _update_elapsed := UPDATE_BLOOM_SECONDS

var _breath: Breath = null
var _breath_seconds := 0.0


func build(tokens: UITokens, fonts: UIFonts, spec: Dictionary) -> bool:
	_tokens = tokens
	_fonts = fonts
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_copy_font = null
	_amount_font = null
	if _tokens == null or _fonts == null:
		queue_redraw()
		return false
	_copy_font = _fonts.interface_at(
		_tokens.breath_latin_weight,
		_tokens.breath_cjk_weight
	)
	_amount_font = _fonts.instrument
	if _copy_font == null or _amount_font == null:
		queue_redraw()
		return false
	apply_spec(spec, false)
	return is_ready()


func apply_spec(spec: Dictionary, animate_update := true) -> void:
	_key = StringName(spec.get("key", _key))
	_copy = String(spec.get("copy", _copy)).strip_edges()
	_amount = String(spec.get("amount", _amount)).strip_edges()
	_icon_id = StringName(spec.get("icon_id", _icon_id))
	_rejected = bool(spec.get("rejected", _rejected))
	_icon = _load_icon(_icon_id)
	if animate_update:
		_update_elapsed = 0.0
	layout_for(_viewport)
	queue_redraw()


func is_ready() -> bool:
	return _tokens != null and _copy_font != null and _amount_font != null \
		and _key != &"" and _copy != ""


func receipt_key() -> StringName:
	return _key


func copy_text() -> String:
	return _copy


func amount_text() -> String:
	return _amount


func is_rejected() -> bool:
	return _rejected


func set_ground(value: float) -> void:
	if not is_finite(value):
		return
	_ground = clampf(value, 0.0, 1.0)
	queue_redraw()


func ground() -> float:
	return _ground


func set_envelope(breath: Breath, seconds: float) -> void:
	_breath = breath
	_breath_seconds = seconds
	queue_redraw()


func envelope() -> Breath:
	return _breath


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _update_elapsed >= UPDATE_BLOOM_SECONDS:
		return
	_update_elapsed = minf(_update_elapsed + delta, UPDATE_BLOOM_SECONDS)
	queue_redraw()


func layout_for(viewport_size: Vector2) -> Vector2:
	if _valid_viewport(viewport_size):
		_viewport = viewport_size
	if _tokens == null or _copy_font == null or _amount_font == null:
		return size
	var icon_px := _px(ICON_DESIGN_PX)
	var copy_px := _copy_px()
	var amount_px := _amount_px()
	var text_height := maxf(
		_copy_font.get_height(copy_px),
		_px(COPY_DESIGN_PX) * LINE_HEIGHT
	)
	var copy_width := _copy_font.get_string_size(
		_copy, HORIZONTAL_ALIGNMENT_LEFT, -1.0, copy_px
	).x
	var amount_width := 0.0
	if _amount != "":
		amount_width = _amount_font.get_string_size(
			_amount, HORIZONTAL_ALIGNMENT_LEFT, -1.0, amount_px
		).x
	size = Vector2(
		icon_px + _px(GAP_DESIGN_PX) + copy_width
			+ (_px(AMOUNT_GAP_DESIGN_PX) + amount_width if amount_width > 0.0 else 0.0),
		maxf(icon_px, text_height)
	)
	custom_minimum_size = size
	pivot_offset = size * 0.5
	queue_redraw()
	return size


func _draw() -> void:
	if not is_ready():
		return
	var ink := UIInk.mark_for(_tokens, _ground)
	if _rejected:
		ink = _tokens.alarm_blood if not UIInk.is_dark_ground(_ground) else ink
	var icon_px := _px(ICON_DESIGN_PX)
	var icon_rect := Rect2(Vector2(0.0, (size.y - icon_px) * 0.5), Vector2.ONE * icon_px)
	if _icon != null:
		draw_texture_rect(_icon, icon_rect, false, ink)
	else:
		var stroke := maxf(_px(2.0), 1.0)
		draw_arc(icon_rect.get_center(), icon_px * 0.38, 0.0, TAU, 32, ink, stroke, true)

	var copy_px := _copy_px()
	var copy_origin_x := icon_px + _px(GAP_DESIGN_PX)
	var copy_baseline := size.y * 0.5 \
		+ (_copy_font.get_ascent(copy_px) - _copy_font.get_descent(copy_px)) * 0.5
	draw_string(
		_copy_font,
		Vector2(copy_origin_x, copy_baseline),
		_copy,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		copy_px,
		ink
	)
	if _amount == "":
		return
	var copy_width := _copy_font.get_string_size(
		_copy, HORIZONTAL_ALIGNMENT_LEFT, -1.0, copy_px
	).x
	var amount_px := _amount_px()
	var amount_baseline := size.y * 0.5 \
		+ (_amount_font.get_ascent(amount_px) - _amount_font.get_descent(amount_px)) * 0.5
	var amount_ink := ink
	if _tokens.opacity_steps.size() > 1:
		amount_ink.a *= _tokens.opacity_steps[1]
	amount_ink.a *= _update_opacity()
	draw_string(
		_amount_font,
		Vector2(copy_origin_x + copy_width + _px(AMOUNT_GAP_DESIGN_PX), amount_baseline),
		_amount,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		amount_px,
		amount_ink
	)


func _update_opacity() -> float:
	if _update_elapsed >= UPDATE_BLOOM_SECONDS:
		return 1.0
	return clampf(_update_elapsed / maxf(UPDATE_BLOOM_SECONDS, 0.0001), 0.0, 1.0)


func _load_icon(id: StringName) -> Texture2D:
	var clean := String(id).strip_edges()
	if clean == "":
		return null
	var path := "%s/%s.png" % [ICON_DIRECTORY, clean]
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


func _px(design_pixels: float) -> float:
	return design_pixels if _tokens == null else _tokens.design_px(design_pixels, _viewport)


func _copy_px() -> int:
	return maxi(int(roundf(_px(COPY_DESIGN_PX))), 1)


func _amount_px() -> int:
	return maxi(int(roundf(_px(AMOUNT_DESIGN_PX))), 1)


static func _valid_viewport(value: Vector2) -> bool:
	return value.is_finite() and value.x > 0.0 and value.y > 0.0
