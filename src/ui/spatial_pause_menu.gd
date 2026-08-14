class_name SpatialPauseMenu
extends Node3D

## Camera-tracked spatial copy for the pause surface.
##
## The labels are real Label3D geometry at the gameplay world's depth,
## reprojected to the authored left-hand composition while the pause camera
## moves, so their screen relationship stays intentional without turning them
## back into Canvas text.
##
## OWNER RULING 2026-08-14: world geometry must NEVER occlude the words --
## only the falling snow may cross them. So the copy opts OUT of the depth
## buffer (no_depth_test): opaque scenery cannot win against it, while the
## snowflakes -- transparent, camera-near, sorted after it in the transparent
## pass -- still drift across the letters exactly as weather should.

const BASE_FONT_SIZE := 64
const SURFACE_LIFT_METRES := 1.5
const FOREGROUND_SURFACE_DEPTH_METRES := 3.2

## 焦点下划线与菱形的响应速率：18/s，约 0.16s 落定——快到跟手，慢到不跳。
const LINE_RESPONSE := 18.0

## 焦点三重反馈（设计规范 2.2）：字重 +100、上浮 -2px、其余降到 UNFOCUSED_ALPHA。
## 第四重是唯一的一点暖：琥珀细线与滑动的焦点菱形。
## 所有者 2026-08-14：未激活项不再换浅灰色——同奶白、低半档透明度。反差由
## 菱形、下划线与字重承担，而不是把别的字掐灭。
const FOCUS_WEIGHT_STEP := 100
const FOCUS_LIFT_PIXELS := -2.0
const UNFOCUSED_ALPHA := 0.85
const PULSE_SCALE := 0.03
const PULSE_RESPONSE := 12.0

## 焦点菱形：6px 方块旋转 45°，停在焦点项左侧 16px 处，焦点移动时滑过去。
const FOCUS_DIAMOND := &"focus_diamond"
const DIAMOND_SIZE_PIXELS := 6.0
const DIAMOND_LEAD_PIXELS := 16.0
const DIAMOND_RESPONSE := 18.0

## 右下重影：1px、45% 冷黑——把字从雪上托起；小字号副文本也靠它站稳。
const SHADOW_OFFSET_PIXELS := 1.0
const SHADOW_STRENGTH := 0.45
const SHADOW_SETBACK_METRES := 0.02

## ≤6px，反向追随，指数平滑。相机不动——相机一动画面就"晕"（设计规范 2.5）。
const POINTER_PARALLAX_PIXELS := 6.0
const POINTER_RESPONSE := 4.0

const STATUS := &"status"
const CAPTION := &"caption"
const TIME := &"time"
const CONTINUE := &"continue"
const EXIT := &"exit"
const QUESTION := &"question"
const CONSEQUENCE := &"consequence"
const RETURN := &"return"
const CONFIRM := &"confirm"
const HINT := &"hint"
const CONTEXT_LINE := &"context_line"
const SETTINGS := &"settings"
const SETTINGS_HEADING := &"settings_heading"
const STATE_MENU := &"menu"
const STATE_SETTINGS := &"settings"
const STATE_CONFIRM := &"confirm"
const CATALOG_PATH := "res://data/ui/accessibility_settings.tres"
const TRACK_WIDTH := 96.0     # 设计像素，设置行轨道
const TICK_WIDTH := 1.25
const TICK_HEIGHT := 5.0
const MARKER_WIDTH := 2.5
const MARKER_HEIGHT := 9.0

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _camera: Camera3D = null
var _labels: Dictionary = {}
var _label_fonts: Dictionary = {}
var _label_colours: Dictionary = {}
var _label_sizes: Dictionary = {}
var _targets: Dictionary = {}
var _label_tilts: Dictionary = {}

var _lines: Dictionary = {}
var _line_materials: Dictionary = {}
var _line_lefts: Dictionary = {}
var _line_y: Dictionary = {}
var _line_widths: Dictionary = {}
var _line_heights: Dictionary = {}
var _line_amounts: Dictionary = {}
var _line_targets: Dictionary = {}

var _ornaments: Dictionary = {}
var _ornament_materials: Dictionary = {}
var _ornament_positions: Dictionary = {}
var _ornament_sizes: Dictionary = {}
var _ornament_tilts: Dictionary = {}

var _compact := false
var _alpha := 1.0
var _focus: StringName = CONTINUE
var _depth := 1.0

var _catalog: AccessibilityCatalog = null
var _row_settings: Array = []                 # AccessibilitySetting
var _row_ids: Array[StringName] = []          # 名称 label id
var _row_value_ids: Array[StringName] = []    # 值 label id
var _row_fractions: Dictionary = {}           # id -> 0..1
var _tracks: Dictionary = {}                  # id -> MeshInstance3D（轨道/游标/刻度共用）
var _track_materials: Dictionary = {}         # id -> StandardMaterial3D
var _track_layouts: Dictionary = {}           # id -> Rect2（屏幕像素）
var _state: StringName = STATE_MENU
var _frame_scale := 1.0

var _envelope_alpha: Dictionary = {}    # id -> 0..1 乘子（默认 1）
var _envelope_offset: Dictionary = {}   # id -> y 像素偏移（默认 0）

var _focus_lift: Dictionary = {}   # id -> 像素
var _row_pulses: Dictionary = {}   # setting_id -> 0..1

var _pointer_target := Vector2.ZERO
var _pointer_current := Vector2.ZERO

var _diamond_current := Vector2.ZERO
var _diamond_target := Vector2.ZERO
var _diamond_ready := false

var _shadows: Dictionary = {}
var _font_display_bold: Font = null
var _font_interface_bold: Font = null
var _font_title: Font = null
var _measured: Dictionary = {}   # id -> 字宽（BASE_FONT_SIZE 下），_set_text 时失效


func setup(tokens: UITokens, fonts: UIFonts) -> void:
	_tokens = tokens
	_fonts = fonts
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _labels.is_empty():
		return
	# 奶白加粗（所有者 2026-08-13）：暂停面的字比设计规范抬两级字重，焦点
	# 再抬一级。不要描边——每个字在右下放一枚深色重影，当作它在雾里的影子。
	_font_display_bold = fonts.display_at(tokens.display_latin_weight + 200,
		tokens.display_cjk_weight + 200)
	_font_interface_bold = fonts.interface_at(tokens.interface_latin_weight + 200,
		tokens.interface_cjk_weight + 200)
	# 标题再抬一级：日标题是这块面板的锚，字重 +300。
	_font_title = fonts.display_at(tokens.display_latin_weight + 300,
		tokens.display_cjk_weight + 300)
	_make_label(STATUS, "第 一 日 · 昼", _font_title, tokens.pause_ink_bright)
	_make_label(CAPTION, "天光尚余", _font_interface_bold, tokens.pause_ink_dim)
	_make_label(TIME, "00:00", fonts.instrument, tokens.pause_ink_bright)
	_make_label(CONTINUE, "继　续", _font_display_bold, tokens.pause_ink_bright)
	_make_label(EXIT, "退出游戏", _font_display_bold, tokens.pause_ink_bright)
	_make_label(QUESTION, "要离开这场长夜吗？", _font_display_bold, tokens.pause_ink_bright)
	_make_label(CONSEQUENCE, "当前进度可能不会保留。", _font_interface_bold, tokens.pause_ink_dim)
	_make_label(RETURN, "返　回", _font_display_bold, tokens.pause_ink_bright)
	_make_label(CONFIRM, "确　认", _font_display_bold, tokens.pause_ink_bright)
	_make_label(HINT, "ESC   返回风雪", _font_interface_bold, tokens.pause_ink_dim)
	_make_label(SETTINGS, "设　置", _font_display_bold, tokens.pause_ink_bright)
	_make_label(SETTINGS_HEADING, "设　置", _font_display_bold, tokens.pause_ink_bright)
	_catalog = ResourceLoader.load(CATALOG_PATH) as AccessibilityCatalog
	if _catalog != null:
		for setting in _catalog.entries:
			var row_id := StringName("row_%s" % setting.id)
			var value_id := StringName("row_%s_value" % setting.id)
			_make_label(row_id, setting.label, _font_interface_bold, tokens.pause_ink_dim)
			_make_label(value_id, setting.format_value(setting.default_value),
				fonts.instrument, tokens.pause_ink_bright)
			_row_settings.append(setting)
			_row_ids.append(row_id)
			_row_value_ids.append(value_id)
			_row_fractions[setting.id] = setting.fraction_of(setting.default_value)
			_make_track(row_id)
			_make_track(value_id)  # 游标挂在 value id 上
			for tick in range(setting.tick_count()):
				_make_track(StringName("%s_tick_%d" % [row_id, tick]))
	# Manual camera tracking lets the typography stay legible while retaining a
	# real Y-axis turn. Each semantic group shares an angle, so the surface feels
	# architectural rather than like ten unrelated floating stickers.
	_set_group_tilt([STATUS, CAPTION, TIME], Vector3(0.0, -0.122173, -0.02618))
	_set_group_tilt([CONTINUE, SETTINGS, EXIT], Vector3(0.0, -0.087266, 0.017453))
	_set_group_tilt([QUESTION, CONSEQUENCE], Vector3(0.0, -0.10472, -0.017453))
	_set_group_tilt([RETURN, CONFIRM], Vector3(0.0, -0.087266, 0.017453))
	_set_group_tilt([HINT], Vector3(0.0, -0.069813, -0.017453))
	_set_group_tilt(_row_ids + _row_value_ids, Vector3(0.0, -0.10472, -0.017453))
	_set_group_tilt([SETTINGS_HEADING], Vector3(0.0, -0.10472, -0.017453))

	for line_id in [CONTEXT_LINE, CONTINUE, SETTINGS, EXIT, RETURN, CONFIRM]:
		_make_line(line_id)
	_make_ornament(&"context_start", -0.785398)
	_make_ornament(&"context_end", 0.785398)
	_make_ornament(&"rail_upper", 0.0)
	_make_ornament(&"rail_lower", 0.0)
	# 焦点菱形：一枚琥珀小方块，45° 立起，在菜单项之间滑动。
	_make_ornament(FOCUS_DIAMOND, 0.785398)
	_line_amounts[CONTEXT_LINE] = 1.0
	_line_targets[CONTEXT_LINE] = 1.0
	set_state(STATE_MENU)
	set_focus(CONTINUE)
	visible = false


func set_camera(camera: Camera3D) -> void:
	_camera = camera
	if _camera == null:
		return
	# The rig's Camera3D sits at the end of a 90 m orthographic boom. Bringing
	# the text slightly toward the lens from the rig origin puts it on the
	# valley's depth plane without z-fighting the snow beneath it.
	_depth = minf(maxf(absf(_camera.position.z) - SURFACE_LIFT_METRES, 1.0),
		FOREGROUND_SURFACE_DEPTH_METRES)
	_update_projection()


func has_camera() -> bool:
	return _camera != null


func set_context(status: String, caption: String, time_text: String) -> void:
	_set_text(STATUS, status)
	_set_text(CAPTION, caption)
	_set_text(TIME, time_text)


func layout(content: Rect2, frame_scale: float, compact: bool, state_y: float) -> void:
	_compact = compact
	_frame_scale = frame_scale
	var title_size := maxf(34.0 * frame_scale, 22.0)
	var body_size := maxf(15.0 * frame_scale, 12.0)
	var time_size := maxf(20.0 * frame_scale, 15.0)
	var hint_size := maxf(14.0 * frame_scale, 12.0)
	for id in [STATUS, CONTINUE, SETTINGS, EXIT, QUESTION, RETURN, CONFIRM]:
		_label_sizes[id] = title_size
	# The day line anchors the composition; everything else steps down from it.
	_label_sizes[STATUS] = maxf(42.0 * frame_scale, 26.0)
	for id in [CAPTION, CONSEQUENCE]:
		_label_sizes[id] = body_size
	_label_sizes[TIME] = time_size
	_label_sizes[HINT] = hint_size

	var left := content.position.x
	var top := content.position.y
	_targets[STATUS] = Vector2(left, top + 18.0 * frame_scale)
	_targets[CAPTION] = Vector2(left, top + 72.0 * frame_scale)
	_targets[TIME] = Vector2(left + 112.0 * frame_scale, top + 72.0 * frame_scale)

	var actions_top := top + state_y
	# The settings heading sits just above its rows: smaller than the 42px day
	# line, larger than the 15px rows, so the subpage reads as a titled page.
	_targets[SETTINGS_HEADING] = Vector2(left, actions_top - 44.0 * frame_scale)
	_label_sizes[SETTINGS_HEADING] = maxf(24.0 * frame_scale, 16.0)
	_set_ornament_layout(&"context_start",
		Vector2(left - 4.0 * frame_scale, top + 54.0 * frame_scale),
		Vector2(8.0, 1.25) * frame_scale)
	_set_ornament_layout(&"context_end",
		Vector2(left + 268.0 * frame_scale, top + 54.0 * frame_scale),
		Vector2(8.0, 1.25) * frame_scale)
	_set_ornament_layout(&"rail_upper",
		Vector2(left - 10.0 * frame_scale, actions_top + 18.0 * frame_scale),
		Vector2(1.25, 14.0) * frame_scale)
	_set_ornament_layout(&"rail_lower",
		Vector2(left - 10.0 * frame_scale, actions_top + 72.0 * frame_scale),
		Vector2(1.25, 14.0) * frame_scale)
	_targets[CONTINUE] = Vector2(left, actions_top + 20.0 * frame_scale)
	_targets[SETTINGS] = Vector2(left, actions_top + 70.0 * frame_scale)
	_targets[EXIT] = Vector2(left, actions_top + 120.0 * frame_scale)
	_targets[QUESTION] = Vector2(left, actions_top + 16.0 * frame_scale)
	_targets[CONSEQUENCE] = Vector2(left, actions_top + 54.0 * frame_scale)
	_targets[RETURN] = Vector2(left, actions_top + 100.0 * frame_scale)
	_targets[CONFIRM] = Vector2(left + 128.0 * frame_scale, actions_top + 100.0 * frame_scale)
	for i in range(_row_settings.size()):
		var row_top := actions_top + (16.0 + 52.0 * i) * frame_scale
		var row_id: StringName = _row_ids[i]
		var value_id: StringName = _row_value_ids[i]
		_targets[row_id] = Vector2(left, row_top)
		_targets[value_id] = Vector2(left + 148.0 * frame_scale, row_top)
		_label_sizes[row_id] = body_size
		_label_sizes[value_id] = body_size
		var track_y := row_top + 30.0 * frame_scale
		_track_layouts[row_id] = Rect2(left + 148.0 * frame_scale, track_y,
			TRACK_WIDTH * frame_scale, maxf(frame_scale, 1.0))
		var setting: AccessibilitySetting = _row_settings[i]
		var fraction: float = _row_fractions[setting.id]
		_track_layouts[value_id] = Rect2(
			left + (148.0 + TRACK_WIDTH * fraction) * frame_scale - MARKER_WIDTH * 0.5 * frame_scale,
			track_y - (MARKER_HEIGHT - 1.0) * 0.5 * frame_scale,
			MARKER_WIDTH * frame_scale, MARKER_HEIGHT * frame_scale)
		for tick in range(setting.tick_count()):
			var tick_fraction := float(tick) / float(maxi(setting.tick_count() - 1, 1))
			_track_layouts[StringName("%s_tick_%d" % [row_id, tick])] = Rect2(
				left + (148.0 + TRACK_WIDTH * tick_fraction) * frame_scale - TICK_WIDTH * 0.5 * frame_scale,
				track_y - (TICK_HEIGHT - 1.0) * 0.5 * frame_scale,
				TICK_WIDTH * frame_scale, TICK_HEIGHT * frame_scale)
	_targets[HINT] = Vector2(left, top + 400.0 * frame_scale)

	_set_line_layout(CONTEXT_LINE, left, top + 54.0 * frame_scale,
		264.0 * frame_scale, maxf(frame_scale, 1.0))
	_set_choice_line(CONTINUE, 104.0 * frame_scale)
	_set_choice_line(SETTINGS, 104.0 * frame_scale)
	_set_choice_line(EXIT, 144.0 * frame_scale)
	_set_choice_line(RETURN, 104.0 * frame_scale)
	_set_choice_line(CONFIRM, 104.0 * frame_scale)
	_ornament_sizes[FOCUS_DIAMOND] = Vector2(DIAMOND_SIZE_PIXELS, DIAMOND_SIZE_PIXELS) * frame_scale
	_update_diamond_target(false)
	_apply_state_visibility()
	_update_projection()


func set_state(state: StringName) -> void:
	_state = state
	_set_text(HINT, "ESC   返回暂停" if state != STATE_MENU else "ESC   返回风雪")
	match state:
		STATE_CONFIRM:
			set_focus(RETURN)
		STATE_SETTINGS:
			set_focus(_row_ids[0] if not _row_ids.is_empty() else CONTINUE)
		_:
			set_focus(CONTINUE)
	_apply_state_visibility()


func row_label_ids() -> Array[StringName]:
	return _row_ids.duplicate()


func row_value_ids() -> Array[StringName]:
	return _row_value_ids.duplicate()


## Every track-quad id: each row's rail, the marker riding its value id, and
## its tick marks. The settings cascade breathes these with the row labels.
func track_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in _tracks.keys():
		ids.append(key)
	return ids


func track_quads() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for raw in _tracks.values():
		result.append(raw as MeshInstance3D)
	return result


## The menu pushed a new value: refresh the value word and slide the marker.
## Only the marker rect is recomputed -- a full layout() would reset every
## target on the surface for the sake of one 2.5 px quad.
func set_row_value(setting_id: StringName, formatted: String, fraction: float) -> void:
	var value_id := StringName("row_%s_value" % setting_id)
	_set_text(value_id, formatted)
	_row_fractions[setting_id] = clampf(fraction, 0.0, 1.0)
	var row_id := StringName("row_%s" % setting_id)
	var track_rect := _track_layouts.get(row_id, Rect2()) as Rect2
	var marker_width := MARKER_WIDTH * _frame_scale
	_track_layouts[value_id] = Rect2(
		track_rect.position.x + track_rect.size.x * _row_fractions[setting_id] - marker_width * 0.5,
		track_rect.position.y - (MARKER_HEIGHT - 1.0) * 0.5 * _frame_scale,
		marker_width, MARKER_HEIGHT * _frame_scale)
	_update_projection()


func set_focus(id: StringName) -> void:
	_focus = id
	for choice in [CONTINUE, SETTINGS, EXIT, RETURN, CONFIRM]:
		var focused: bool = choice == id
		_line_targets[choice] = 1.0 if focused else 0.0
		# 同奶白，不分亮暗——焦点由菱形、下划线、字重与上浮表达。
		_label_colours[choice] = _tokens.pause_ink_bright
	for i in range(_row_ids.size()):
		_label_colours[_row_ids[i]] = _tokens.pause_ink_bright
		_label_colours[_row_value_ids[i]] = _tokens.pause_ink_bright
	var focusables := [CONTINUE, SETTINGS, EXIT, RETURN, CONFIRM] + _row_ids
	for focusable in focusables:
		var focused_now: bool = focusable == _focus
		_focus_lift[focusable] = FOCUS_LIFT_PIXELS if focused_now else 0.0
		var label := _labels.get(focusable) as Label3D
		if label != null:
			label.font = _focused_font_for(focusable, focused_now)
		var shadow := _shadows.get(focusable) as Label3D
		if shadow != null and label != null:
			shadow.font = label.font
	_update_diamond_target(false)
	_apply_alpha()


## Where the diamond should sit: left of the focused line, centred on its cap
## height. `snap` is for layout/state changes, where sliding from a stale spot
## would read as a glitch rather than a ceremony.
func _update_diamond_target(snap: bool) -> void:
	var target := (_targets.get(_focus, Vector2.ZERO) as Vector2) + Vector2(
		-DIAMOND_LEAD_PIXELS * _frame_scale,
		float(_label_sizes.get(_focus, 17.0)) * 0.36)
	if snap or not _diamond_ready:
		_diamond_current = target
		_diamond_ready = true
	_ornament_positions[FOCUS_DIAMOND] = _diamond_current
	_diamond_target = target


## The display font for a focusable, re-weighted one step up while it holds
## focus. The pause surface's BASE is already two steps up from the design
## document (奶白加粗), so the comparison is against the bold variants.
## `_label_fonts` keeps the BASE font after the swap: measurement stays
## on the base chain (the VF variants share advance widths across the weight
## axis -- see the UIFonts doc-comment), so nothing here updates it.
func _focused_font_for(id: StringName, focused: bool) -> Font:
	var base := _label_fonts.get(id) as Font
	if not focused:
		return base
	if base == _font_display_bold:
		return _fonts.display_at(_tokens.display_latin_weight + 200 + FOCUS_WEIGHT_STEP,
			_tokens.display_cjk_weight + 200 + FOCUS_WEIGHT_STEP)
	if base == _font_interface_bold:
		return _fonts.interface_at(_tokens.interface_latin_weight + 200 + FOCUS_WEIGHT_STEP,
			_tokens.interface_cjk_weight + 200 + FOCUS_WEIGHT_STEP)
	return base  # instrument 是静态字重：值字用颜色与脉冲表达焦点


func set_alpha(amount: float) -> void:
	_alpha = clampf(amount, 0.0, 1.0)
	_apply_alpha()


func alpha() -> float:
	return _alpha


## The focused line's lift, in screen pixels (negative is up). Applied on top
## of the envelope offset in _update_projection.
func focus_lift_for(id: StringName) -> float:
	return float(_focus_lift.get(id, 0.0))


## A settings value just settled: start its value word's pulse at full.
func pulse_row_value(setting_id: StringName) -> void:
	_row_pulses[setting_id] = 1.0


func row_pulse(setting_id: StringName) -> float:
	return float(_row_pulses.get(setting_id, 0.0))


## The cursor in -1..1 viewport coordinates. The copy counter-follows it, so
## the surface reads as a plane with depth rather than a sticker on the glass.
func set_pointer_normalized(offset: Vector2) -> void:
	if not offset.is_finite():
		return
	_pointer_target = -Vector2(clampf(offset.x, -1.0, 1.0),
		clampf(offset.y, -1.0, 1.0)) * POINTER_PARALLAX_PIXELS


func pointer_offset() -> Vector2:
	return _pointer_current


## The cascade's handle on one line. Alpha multiplies every colour channel the
## line owns; offset shifts its projected home in screen pixels.
func set_line_envelope(id: StringName, alpha: float, y_offset: float) -> void:
	_envelope_alpha[id] = clampf(alpha, 0.0, 1.0)
	_envelope_offset[id] = y_offset
	_apply_alpha()
	_update_projection()


func reset_envelopes(ids: Array) -> void:
	for id in ids:
		_envelope_alpha[id] = 1.0
		_envelope_offset[id] = 0.0
	_apply_alpha()
	_update_projection()


func _envelope_alpha_for(id: StringName) -> float:
	if _envelope_alpha.has(id):
		return float(_envelope_alpha[id])
	# Tick quads carry ids like "row_x_tick_2" and are never cascaded on their
	# own -- they ride their row's envelope, blooming and drifting as one row.
	var key := String(id)
	var tick_pos := key.find("_tick_")
	if tick_pos > 0:
		return float(_envelope_alpha.get(StringName(key.substr(0, tick_pos)), 1.0))
	return 1.0


func _envelope_offset_for(id: StringName) -> float:
	if _envelope_offset.has(id):
		return float(_envelope_offset[id])
	var key := String(id)
	var tick_pos := key.find("_tick_")
	if tick_pos > 0:
		return float(_envelope_offset.get(StringName(key.substr(0, tick_pos)), 0.0))
	return 0.0


func labels() -> Array[Label3D]:
	var result: Array[Label3D] = []
	for raw in _labels.values():
		result.append(raw as Label3D)
	return result


func shadow_labels() -> Array[Label3D]:
	var result: Array[Label3D] = []
	for raw in _shadows.values():
		result.append(raw as Label3D)
	return result


func ornaments() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for raw in _ornaments.values():
		result.append(raw as MeshInstance3D)
	return result


func has_authored_tilt() -> bool:
	for raw in _label_tilts.values():
		if (raw as Vector3) != Vector3.ZERO:
			return true
	return false


func _process(delta: float) -> void:
	# The pulse decays even while hidden or camera-free: a settled value should
	# be quiet by the time the surface returns, not frozen mid-pulse.
	for setting_id in _row_pulses.keys():
		var current := float(_row_pulses[setting_id])
		if current <= 0.001:
			_row_pulses[setting_id] = 0.0
			continue
		_row_pulses[setting_id] = lerpf(current, 0.0, 1.0 - exp(-PULSE_RESPONSE * maxf(delta, 0.0)))
	if _camera != null:
		var viewport := _camera.get_viewport()
		if viewport != null:
			var mouse := viewport.get_mouse_position()
			var rect := viewport.get_visible_rect().size
			if rect.x > 0.0 and rect.y > 0.0:
				set_pointer_normalized(Vector2(
					mouse.x / rect.x * 2.0 - 1.0,
					mouse.y / rect.y * 2.0 - 1.0))
	# Parallax also settles while hidden or camera-free, for the same reason as
	# the pulse: the offset should be home by the time the surface returns.
	if _compact:
		_pointer_current = Vector2.ZERO
	else:
		_pointer_current = _pointer_current.lerp(_pointer_target,
			1.0 - exp(-POINTER_RESPONSE * maxf(delta, 0.0)))
	# The diamond settles while hidden too, same as the pulse and the parallax:
	# it should be home by the time the surface returns.
	if _diamond_ready:
		_diamond_current = _diamond_current.lerp(_diamond_target,
			1.0 - exp(-DIAMOND_RESPONSE * maxf(delta, 0.0)))
		_ornament_positions[FOCUS_DIAMOND] = _diamond_current
	if not visible or _camera == null:
		return
	for id in _line_amounts.keys():
		var current := float(_line_amounts[id])
		var target := float(_line_targets.get(id, 0.0))
		var blend := 1.0 - exp(-LINE_RESPONSE * maxf(delta, 0.0))
		_line_amounts[id] = lerpf(current, target, blend)
	_update_projection()


func _make_label(id: StringName, text_value: String, font: Font, colour: Color) -> void:
	var label := Label3D.new()
	label.name = String(id).to_pascal_case()
	label.text = text_value
	label.font = font
	label.font_size = BASE_FONT_SIZE
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# _update_projection performs the camera tracking manually. Godot billboard
	# mode would erase the authored Y rotation and flatten the whole composition.
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = true
	label.double_sided = true
	label.shaded = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	# 无描边。对比度由加粗字重与右下 1px 重影承担——重影是影子，不是边框。
	label.outline_size = 0
	add_child(label)
	_labels[id] = label
	_label_fonts[id] = font
	_label_colours[id] = colour
	_label_sizes[id] = 17.0
	_targets[id] = Vector2.ZERO
	_label_tilts[id] = Vector3.ZERO

	var shadow := Label3D.new()
	shadow.name = label.name + "Shadow"
	shadow.text = text_value
	shadow.font = font
	shadow.font_size = BASE_FONT_SIZE
	shadow.autowrap_mode = TextServer.AUTOWRAP_OFF
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	shadow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shadow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	shadow.no_depth_test = true
	shadow.double_sided = true
	shadow.shaded = false
	shadow.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	shadow.outline_size = 0
	shadow.modulate = _tokens.pause_scrim
	add_child(shadow)
	_shadows[id] = shadow


func _set_group_tilt(ids: Array, tilt: Vector3) -> void:
	for id in ids:
		_label_tilts[id] = tilt


func _make_line(id: StringName) -> void:
	var quad := QuadMesh.new()
	var line := MeshInstance3D.new()
	line.name = (String(id) + "_line").to_pascal_case()
	line.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_color = _tokens.line_hairline
	line.material_override = material
	add_child(line)
	_lines[id] = line
	_line_materials[id] = material
	_line_lefts[id] = 0.0
	_line_y[id] = 0.0
	_line_widths[id] = 1.0
	_line_heights[id] = 1.0
	_line_amounts[id] = 0.0
	_line_targets[id] = 0.0


func _make_track(id: StringName) -> void:
	var quad := MeshInstance3D.new()
	quad.name = String(id).to_pascal_case()
	quad.mesh = QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_color = _tokens.line_hairline
	quad.material_override = material
	add_child(quad)
	_tracks[id] = quad
	_track_materials[id] = material
	_track_layouts[id] = Rect2()


func _make_ornament(id: StringName, roll: float) -> void:
	var ornament := MeshInstance3D.new()
	ornament.name = String(id).to_pascal_case()
	ornament.mesh = QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_color = _tokens.line_hairline
	if id == FOCUS_DIAMOND:
		# 雪夜一点火：焦点菱形轻微自发光，在冷场里暖起来。保持 HDR 低位，
		# 是烛火不是霓虹。
		material.emission_enabled = true
		material.emission = _tokens.pause_ember
		material.emission_energy_multiplier = 1.5
	ornament.material_override = material
	add_child(ornament)
	_ornaments[id] = ornament
	_ornament_materials[id] = material
	_ornament_positions[id] = Vector2.ZERO
	_ornament_sizes[id] = Vector2.ONE
	_ornament_tilts[id] = Vector3(0.0, -0.10472, roll)


func _set_ornament_layout(id: StringName, position: Vector2, size: Vector2) -> void:
	_ornament_positions[id] = position
	_ornament_sizes[id] = size


func _set_text(id: StringName, value: String) -> void:
	var label := _labels.get(id) as Label3D
	if label != null:
		label.text = value
	var shadow := _shadows.get(id) as Label3D
	if shadow != null:
		shadow.text = value
	# 字宽缓存失效：文本变了才重测，而不是每帧每个字都测。
	_measured.erase(id)


func _set_choice_line(id: StringName, width: float) -> void:
	var target := _targets.get(id, Vector2.ZERO) as Vector2
	var size := float(_label_sizes.get(id, 17.0))
	_set_line_layout(id, target.x, target.y + size * 0.72, width, maxf(size / 34.0, 1.0))


func _set_line_layout(id: StringName, left: float, y: float, width: float, height: float) -> void:
	_line_lefts[id] = left
	_line_y[id] = y
	_line_widths[id] = width
	_line_heights[id] = height


func _apply_state_visibility() -> void:
	if _labels.is_empty():
		return
	var in_menu := _state == STATE_MENU
	var in_confirm := _state == STATE_CONFIRM
	var in_settings := _state == STATE_SETTINGS
	for id in [CONTINUE, SETTINGS, EXIT]:
		(_labels[id] as Label3D).visible = in_menu
		(_shadows[id] as Label3D).visible = in_menu
		(_lines[id] as MeshInstance3D).visible = in_menu
	for id in [QUESTION, CONSEQUENCE, RETURN, CONFIRM]:
		(_labels[id] as Label3D).visible = in_confirm
		(_shadows[id] as Label3D).visible = in_confirm
	for id in [RETURN, CONFIRM]:
		(_lines[id] as MeshInstance3D).visible = in_confirm
	for id in _row_ids + _row_value_ids:
		(_labels[id] as Label3D).visible = in_settings
		(_shadows[id] as Label3D).visible = in_settings
	(_labels[SETTINGS_HEADING] as Label3D).visible = in_settings
	(_shadows[SETTINGS_HEADING] as Label3D).visible = in_settings
	for id in _tracks.keys():
		(_tracks[id] as MeshInstance3D).visible = in_settings
	(_labels[HINT] as Label3D).visible = not _compact
	(_shadows[HINT] as Label3D).visible = not _compact


func _apply_alpha() -> void:
	if _tokens == null:
		return
	var focusables := [CONTINUE, SETTINGS, EXIT, RETURN, CONFIRM] + _row_ids
	for id in _labels.keys():
		var label := _labels[id] as Label3D
		var fill: Color = _label_colours[id]
		# The ice fill stays bright over the dimmed world. The paired cold-dark
		# edge below is the second contrast channel when a depth-composited word
		# crosses lit snow.
		fill.a *= _alpha * _envelope_alpha_for(id)
		# Unfocused choices recede to the quiet alpha. The confirm page is
		# exempt: its two buttons keep their colour contrast as the focus cue.
		if id in focusables and id != _focus and _state != STATE_CONFIRM:
			fill.a *= UNFOCUSED_ALPHA
		label.modulate = fill
		# 右下重影跟着正文的透明度走，永远比正文暗半步。
		var shadow := _shadows.get(id) as Label3D
		if shadow != null:
			var shadow_colour := _tokens.pause_scrim
			shadow_colour.a = fill.a * SHADOW_STRENGTH
			shadow.modulate = shadow_colour
	for id in _line_materials.keys():
		var material := _line_materials[id] as StandardMaterial3D
		# The one warm point: choice underlines carry the ember. The context
		# hairline under the day line stays cold.
		var colour := _tokens.pause_ember if id != CONTEXT_LINE else _tokens.pause_hairline
		colour.a *= _alpha * _envelope_alpha_for(id)
		material.albedo_color = colour
	for id in _ornament_materials.keys():
		var ornament_material := _ornament_materials[id] as StandardMaterial3D
		var ornament_colour := _tokens.pause_hairline
		var ornament_alpha := _tokens.opacity_steps[1] * _alpha
		if id == FOCUS_DIAMOND:
			# The diamond rides its focused line's envelope, so it blooms and
			# drifts with the word it marks instead of arriving on its own.
			ornament_colour = _tokens.pause_ember
			ornament_alpha = _alpha * _envelope_alpha_for(_focus)
		ornament_colour.a *= ornament_alpha
		ornament_material.albedo_color = ornament_colour
	for id in _track_materials.keys():
		var track_material := _track_materials[id] as StandardMaterial3D
		# The value marker is the ember; rail and ticks are a thin cold-dark
		# line -- mid-grey hairline washed out on snow, scrim at half holds.
		var track_colour := _tokens.pause_ember if id in _row_value_ids else _tokens.pause_scrim
		if not (id in _row_value_ids):
			track_colour.a *= 0.5
		track_colour.a *= _alpha * _envelope_alpha_for(id)
		track_material.albedo_color = track_colour


func _update_projection() -> void:
	if _camera == null or not _camera.is_inside_tree():
		return
	# The pause shot physically travels down CameraRig's boom. Keeping the old
	# startup depth would leave the interface eighty metres behind the player;
	# recomputing it places the tracked surface just ahead of them at every frame
	# of the move and makes the final type genuinely inhabit their world.
	_depth = maxf(absf(_camera.position.z) - SURFACE_LIFT_METRES, 1.0)
	var viewport_size := _camera.get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return
	var world_per_pixel := _world_per_pixel(viewport_size.y)
	for id in _labels.keys():
		var label := _labels[id] as Label3D
		var screen_size := float(_label_sizes.get(id, 17.0))
		var font := _label_fonts[id] as Font
		# 字宽只随文本变化（同一字重轴上 advance 相同），缓存之——否则每帧
		# 每个字（含重影）都在字体服务器里重测一遍。
		var measured := float(_measured.get(id, -1.0))
		if measured < 0.0:
			measured = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, BASE_FONT_SIZE).x
			_measured[id] = measured
		var new_width := maxi(int(ceilf(measured)), 1)
		if label.width != new_width:
			label.width = new_width
		var pulse := 1.0
		var row_index := _row_value_ids.find(id)
		if row_index >= 0:
			var setting := _row_settings[row_index] as AccessibilitySetting
			pulse = 1.0 + PULSE_SCALE * float(_row_pulses.get(setting.id, 0.0))
		var new_pixel_size := world_per_pixel * screen_size / float(BASE_FONT_SIZE) * pulse
		# Writing an unchanged pixel_size still dirties the label's text mesh;
		# fifty glyphs re-shaping per frame reads as stutter. Guard the write.
		if absf(label.pixel_size - new_pixel_size) > 0.0000001:
			label.pixel_size = new_pixel_size
		# Label3D's LEFT alignment treats its origin as the left edge of the text
		# box. Adding half the measured width here was a double-centering error and
		# separated the visible glyphs from their accessible Canvas hit targets.
		var home := (_targets[id] as Vector2) + _pointer_current + Vector2(0.0,
			_envelope_offset_for(id) + float(_focus_lift.get(id, 0.0)))
		var label_transform := label.global_transform
		label_transform.origin = _camera.project_position(home, _depth)
		label_transform.basis = _camera.global_transform.basis.orthonormalized() \
			* Basis.from_euler(_label_tilts[id] as Vector3)
		label.global_transform = label_transform
		var shadow := _shadows.get(id) as Label3D
		if shadow != null:
			if shadow.width != label.width:
				shadow.width = label.width
			if absf(shadow.pixel_size - label.pixel_size) > 0.0000001:
				shadow.pixel_size = label.pixel_size
			var shadow_transform := shadow.global_transform
			shadow_transform.origin = _camera.project_position(home
				+ Vector2(SHADOW_OFFSET_PIXELS, SHADOW_OFFSET_PIXELS),
				_depth + SHADOW_SETBACK_METRES)
			shadow_transform.basis = label_transform.basis
			shadow.global_transform = shadow_transform

	for id in _lines.keys():
		var amount := clampf(float(_line_amounts.get(id, 0.0)), 0.0, 1.0)
		var screen_width := float(_line_widths[id]) * amount
		var center := Vector2(float(_line_lefts[id]) + screen_width * 0.5, float(_line_y[id]))
		var line := _lines[id] as MeshInstance3D
		var quad := line.mesh as QuadMesh
		var line_size := Vector2(maxf(screen_width * world_per_pixel, 0.001),
			maxf(float(_line_heights[id]) * world_per_pixel, 0.001))
		# QuadMesh.size re-tessellates; only pay for it when it actually moved.
		if quad.size != line_size:
			quad.size = line_size
		var transform := line.global_transform
		transform.origin = _camera.project_position(center + _pointer_current, _depth - 0.01)
		var tilt: Vector3 = _label_tilts.get(id,
			_label_tilts.get(STATUS, Vector3.ZERO)) as Vector3
		transform.basis = _camera.global_transform.basis.orthonormalized() \
			* Basis.from_euler(tilt)
		line.global_transform = transform

	for id in _ornaments.keys():
		var ornament := _ornaments[id] as MeshInstance3D
		var quad := ornament.mesh as QuadMesh
		var ornament_size := (_ornament_sizes[id] as Vector2) * world_per_pixel
		if quad.size != ornament_size:
			quad.size = ornament_size
		var ornament_position := (_ornament_positions[id] as Vector2) + _pointer_current
		if id == FOCUS_DIAMOND:
			# Rides the focused word's bloom offset and focus lift, so marker
			# and word arrive as one piece.
			ornament_position += Vector2(0.0, _envelope_offset_for(_focus)
				+ float(_focus_lift.get(_focus, 0.0)))
		var transform := ornament.global_transform
		transform.origin = _camera.project_position(ornament_position, _depth + 0.04)
		transform.basis = _camera.global_transform.basis.orthonormalized() \
			* Basis.from_euler(_ornament_tilts[id] as Vector3)
		ornament.global_transform = transform

	for id in _tracks.keys():
		var track := _tracks[id] as MeshInstance3D
		if not track.visible:
			continue
		var rect := _track_layouts[id] as Rect2
		var track_quad := track.mesh as QuadMesh
		var track_size := Vector2(maxf(rect.size.x * world_per_pixel, 0.001),
			maxf(rect.size.y * world_per_pixel, 0.001))
		if track_quad.size != track_size:
			track_quad.size = track_size
		var track_transform := track.global_transform
		track_transform.origin = _camera.project_position(
			rect.get_center() + _pointer_current, _depth - 0.01)
		track_transform.basis = _camera.global_transform.basis.orthonormalized() \
			* Basis.from_euler(_label_tilts.get(QUESTION, Vector3.ZERO) as Vector3)
		track.global_transform = track_transform


func _world_per_pixel(viewport_height: float) -> float:
	if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return _camera.size / viewport_height
	return 2.0 * _depth * tan(deg_to_rad(_camera.fov) * 0.5) / viewport_height
