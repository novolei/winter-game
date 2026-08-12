class_name ThresholdNote
extends Control

## UI design document section 5.2's 阈值浮现: 24px icon + 52px 短弧 + 一行 Body 17
## 文案, in the left breathing border, for as long as it takes to read and then
## gone.
##
## ---------------------------------------------------------------------------
## THE WORDS ARE THE POINT, AND THEY ARE NOT IN THIS FILE
## ---------------------------------------------------------------------------
## Section 5.2: 说后果，不说数字. Every line the player reads comes out of
## data/ui/threshold_copy.tres, which tests/unit/test_ui_threshold_copy.gd holds
## against every ThresholdEffect the stat files really author. A threshold with
## no row surfaces as SILENCE, and silence is indistinguishable from a threshold
## that has not been reached -- which is why that gate exists and why no copy is
## written here.
##
## ---------------------------------------------------------------------------
## THE SHORT ARC IS THE SAME ELEMENT SECTION 6.1'S RING WILL BE MADE OF
## ---------------------------------------------------------------------------
## It is a VitalStroke with a bow on it, at a different length and a different
## orientation from the ring Tab draws around the character. That is not thrift.
## A player who meets a reading here and then asks for it on Tab has to recognise
## the same thing, and two implementations of "a survival value as a stroke"
## would be two sets of thresholds waiting to disagree.
##
## ---------------------------------------------------------------------------
## THE ICON AND THE WORDS ARE NOT FROSTED, AND THAT IS DELIBERATE
## ---------------------------------------------------------------------------
## A CanvasItem carries ONE material, so anything drawn on this node would go
## through the frost shader with the arc. The arc is therefore a child with the
## material on it, and the icon and the line are drawn here, unshaded. Ice made
## of glyphs would be unreadable at Body 17, and the one thing section 5.2 asks
## of this element is that it be read.

const VitalStrokeScript := preload("res://src/ui/vital_stroke.gd")

const ICON_DIRECTORY := "res://assets/ui/icons"

## Section 5.2's composition, in design pixels.
const ICON_DESIGN_PX := 24.0
const ARC_DESIGN_PX := 52.0
const GAP_DESIGN_PX := 8.0

## The sagitta of the 短弧. Shallow: an arc this short with a deep bow reads as a
## bracket rather than as a segment of the ring the player meets on Tab.
const ARC_BOW_DESIGN_PX := 7.0

## Section 2.2's ladder: Body is 17 design px, and its CJK letter spacing is
## +0.08em. 字距是「空灵」的真正来源，比字号重要 -- so it is applied rather than
## being the first thing dropped.
const BODY_DESIGN_PX := 17.0
const BODY_TRACKING_EM := 0.08

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _row: VitalReadout = null
var _text := ""
var _state := VitalTone.State.STEADY

var _arc: VitalStroke = null
var _icon: Texture2D = null
var _body: FontVariation = null
var _viewport := Vector2(1920.0, 1080.0)
var _elapsed := 0.0


## `text` may be empty. Section 5.2's 恢复 row specifies only the arc collapsing
## and the warm mark walking back from the end -- no copy -- and that is the
## right reading rather than an omission: a reserve coming back needs no words
## because the body is already saying it, and 手指不听使唤了 printed at the moment
## the fingers came back would be exactly wrong.
func build(
	tokens: UITokens,
	fonts: UIFonts,
	row: VitalReadout,
	text: String,
	fraction: float,
	depleted: bool,
	recovering: bool
) -> bool:
	_tokens = tokens
	_fonts = fonts
	_row = row
	_text = text
	_state = VitalTone.state_for(fraction, depleted)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_arc = VitalStrokeScript.new()
	_arc.name = "Arc"
	# Its own seed, so the note's ice is not a copy of the margin reading's.
	if not _arc.build(tokens, row, 11.0 + float(row.order if row != null else 0) * 2.9):
		_arc.free()
		_arc = null
		return false
	_arc.set_reading(fraction, depleted, recovering)
	# Born already frosted, and more so the worse the news is. A note lives about
	# three and a half seconds and rime accumulates over nine, so anything that
	# started bare would stay bare for its whole life.
	_arc.set_rime_now(_rime_for_state())
	add_child(_arc)

	_icon = _load_icon()
	_body = _build_body_font()
	return true


func is_ready() -> bool:
	return _arc != null


func stat() -> StringName:
	return &"" if _row == null else _row.stat


func text() -> String:
	return _text


func state() -> int:
	return _state


func arc() -> VitalStroke:
	return _arc


## Sizes the note and puts the arc in it. Returns the size, because the caller
## stacks these and needs to know how tall this one came out.
func layout_for(viewport_size: Vector2) -> Vector2:
	_viewport = viewport_size
	if _tokens == null:
		return size
	var icon_px := _px(ICON_DESIGN_PX)
	var gap := _px(GAP_DESIGN_PX)
	var arc_px := _px(ARC_DESIGN_PX)
	var bow := _px(ARC_BOW_DESIGN_PX)
	var pad := _px(VitalStroke.PAD_DESIGN_PX)

	var arc_height := pad * 2.0 + bow
	var row_height := maxf(icon_px, arc_height)
	var text_width := _text_width()

	size = Vector2(
		icon_px + gap + (arc_px + pad * 2.0) + (gap + text_width if text_width > 0.0 else 0.0),
		row_height
	)
	pivot_offset = size * 0.5
	if _arc != null:
		_arc.place(
			Vector2(icon_px + gap, (row_height - arc_height) * 0.5),
			arc_px,
			_viewport,
			false,
			bow
		)
	queue_redraw()
	return size


func set_time_scale(scale: float) -> void:
	if _arc != null:
		_arc.set_time_scale(scale)


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta
	if _arc != null:
		_arc.advance(delta)
	queue_redraw()


func finish_growth() -> void:
	if _arc != null:
		_arc.finish_growth()
	queue_redraw()


## NO _process(). ThresholdSurfacing drives every live note from its own
## advance(). A note that also ticked itself would crystallise at double speed in
## the running game and at the authored speed everywhere it is measured.


func _draw() -> void:
	if _tokens == null:
		return
	var icon_px := _px(ICON_DESIGN_PX)
	var gap := _px(GAP_DESIGN_PX)
	var pad := _px(VitalStroke.PAD_DESIGN_PX)
	var arc_px := _px(ARC_DESIGN_PX)

	# Section 5.2: 恶化 -- 图标与弧 ink/primary, 文案 ink/secondary. 濒危 -- the lot
	# turns alarm/blood. Never warm: rule 3 gives warmth one meaning and "this is
	# urgent" is not it.
	var ink := VitalTone.colour_for(_tokens, _state)
	if _state == VitalTone.State.EMPTY:
		# Section 6.1's 已归零 -- 弧变成一段 1px 的空槽，不是红色，是空的 -- is about
		# the ARC. The icon is how the player knows WHICH reading has gone, so it
		# keeps its ink; an empty reading nobody can identify is not information.
		ink = _tokens.ink_primary
	if _icon != null:
		draw_texture_rect(
			_icon,
			Rect2(Vector2(0.0, (size.y - icon_px) * 0.5), Vector2(icon_px, icon_px)),
			false,
			ink
		)

	if _text == "" or _body == null:
		return
	var font_px := _text_px()
	var words := _tokens.ink_secondary
	if _state == VitalTone.State.ALARM or _state == VitalTone.State.CRITICAL:
		words = _tokens.alarm_blood
	var baseline := size.y * 0.5 + _body.get_ascent(int(font_px)) * 0.5
	draw_string(
		_body,
		Vector2(icon_px + gap + arc_px + pad * 2.0 + gap, baseline),
		_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		int(font_px),
		words
	)


# --- internals ---------------------------------------------------------------

## Emphasis by MATERIAL rather than by size or by warmth. Worse news is more
## thickly frozen, which is the same language the permanent readings speak when a
## threshold breaks under them -- rule 3 leaves cool value and weight, and this is
## weight.
func _rime_for_state() -> float:
	match _state:
		VitalTone.State.CRITICAL, VitalTone.State.EMPTY:
			return 1.0
		VitalTone.State.ALARM:
			return 0.78
	return 0.5


func _px(design_px: float) -> float:
	if _tokens == null:
		return design_px
	return _tokens.design_px(design_px, _viewport)


func _text_px() -> float:
	return maxf(_px(BODY_DESIGN_PX), 1.0)


func _text_width() -> float:
	if _text == "" or _body == null:
		return 0.0
	return _body.get_string_size(
		_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(_text_px())
	).x


## The interface chain with section 2.2's tracking on it.
##
## Wrapped in its own FontVariation rather than set on UIFonts.interface,
## because that object is shared by the whole interface and spacing is per-size:
## writing to it here would silently re-space the menus.
func _build_body_font() -> FontVariation:
	if _fonts == null or _fonts.interface == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = _fonts.interface
	variation.spacing_glyph = int(roundf(BODY_TRACKING_EM * BODY_DESIGN_PX))
	return variation


## Icons are named for the stat they belong to -- assets/ui/icons/hunger.png --
## so a new stat brings its own icon and no code learns its name (constraint 4).
## A missing file leaves the note without an icon rather than logging: a `load()`
## on a path that is not there prints three ERROR lines, and a dirty console is a
## failed run here.
func _load_icon() -> Texture2D:
	if _row == null or _row.stat == &"":
		return null
	var path := "%s/%s.png" % [ICON_DIRECTORY, _row.stat]
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D
