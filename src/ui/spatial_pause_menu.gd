class_name SpatialPauseMenu
extends Node3D

## Camera-tracked spatial copy for the pause surface.
##
## The labels are real Label3D geometry at the gameplay world's depth. They are
## reprojected to the authored left-hand composition while the pause camera
## moves, so their screen relationship stays intentional without turning them
## back into Canvas text. Depth test remains enabled: a roof, character or drift
## between camera and type wins the depth buffer and occludes it naturally.

const BASE_FONT_SIZE := 64
const SURFACE_LIFT_METRES := 1.5
const FOREGROUND_SURFACE_DEPTH_METRES := 3.2
const LINE_RESPONSE := 12.0
const PAUSE_TREATMENT_COMPENSATION := 1.75

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


func setup(tokens: UITokens, fonts: UIFonts) -> void:
	_tokens = tokens
	_fonts = fonts
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _labels.is_empty():
		return
	# The world is predominantly pale snow, so spatial copy uses the charcoal
	# side of the shared palette. A snow edge is added in _make_label() for the
	# moments when real depth compositing carries a word across a dark structure.
	_make_label(STATUS, "第 一 日 · 昼", fonts.display, tokens.scrim_veil)
	_make_label(CAPTION, "天光尚余", fonts.interface, tokens.line_deep)
	_make_label(TIME, "00:00", fonts.instrument, tokens.scrim_veil)
	_make_label(CONTINUE, "继　续", fonts.display, tokens.scrim_veil)
	_make_label(EXIT, "退出游戏", fonts.display, tokens.line_deep)
	_make_label(QUESTION, "要离开这场长夜吗？", fonts.display, tokens.scrim_veil)
	_make_label(CONSEQUENCE, "当前进度可能不会保留。", fonts.interface, tokens.line_deep)
	_make_label(RETURN, "返　回", fonts.display, tokens.line_deep)
	_make_label(CONFIRM, "确　认", fonts.display, tokens.line_deep)
	_make_label(HINT, "ESC   返回风雪", fonts.interface, tokens.line_deep)
	_make_label(SETTINGS, "设　置", fonts.display, tokens.line_deep)
	_catalog = ResourceLoader.load(CATALOG_PATH) as AccessibilityCatalog
	if _catalog != null:
		for setting in _catalog.entries:
			var row_id := StringName("row_%s" % setting.id)
			var value_id := StringName("row_%s_value" % setting.id)
			_make_label(row_id, setting.label, fonts.interface, tokens.line_deep)
			_make_label(value_id, setting.format_value(setting.default_value),
				fonts.instrument, tokens.scrim_veil)
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

	for line_id in [CONTEXT_LINE, CONTINUE, SETTINGS, EXIT, RETURN, CONFIRM]:
		_make_line(line_id)
	_make_ornament(&"context_start", -0.785398)
	_make_ornament(&"context_end", 0.785398)
	_make_ornament(&"rail_upper", 0.0)
	_make_ornament(&"rail_lower", 0.0)
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
	var body_size := maxf(17.0 * frame_scale, 14.0)
	var time_size := maxf(20.0 * frame_scale, 15.0)
	var hint_size := maxf(14.0 * frame_scale, 12.0)
	for id in [STATUS, CONTINUE, SETTINGS, EXIT, QUESTION, RETURN, CONFIRM]:
		_label_sizes[id] = title_size
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
		_label_colours[choice] = _tokens.scrim_veil if focused else _tokens.line_deep
	for i in range(_row_ids.size()):
		var row_focused: bool = _row_ids[i] == id
		_label_colours[_row_ids[i]] = _tokens.scrim_veil if row_focused else _tokens.line_deep
		_label_colours[_row_value_ids[i]] = _tokens.scrim_veil if row_focused else _tokens.line_deep
	_apply_alpha()


func set_alpha(amount: float) -> void:
	_alpha = clampf(amount, 0.0, 1.0)
	_apply_alpha()


func alpha() -> float:
	return _alpha


func labels() -> Array[Label3D]:
	var result: Array[Label3D] = []
	for raw in _labels.values():
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
	label.no_depth_test = false
	label.double_sided = true
	label.shaded = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	label.outline_size = 4
	label.outline_modulate = _tokens.ink_primary
	add_child(label)
	_labels[id] = label
	_label_fonts[id] = font
	_label_colours[id] = colour
	_label_sizes[id] = 17.0
	_targets[id] = Vector2.ZERO
	_label_tilts[id] = Vector3.ZERO


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
	material.no_depth_test = false
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
	material.no_depth_test = false
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
	material.no_depth_test = false
	material.albedo_color = _tokens.line_hairline
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
		(_lines[id] as MeshInstance3D).visible = in_menu
	for id in [QUESTION, CONSEQUENCE, RETURN, CONFIRM]:
		(_labels[id] as Label3D).visible = in_confirm
	for id in [RETURN, CONFIRM]:
		(_lines[id] as MeshInstance3D).visible = in_confirm
	for id in _row_ids + _row_value_ids:
		(_labels[id] as Label3D).visible = in_settings
	for id in _tracks.keys():
		(_tracks[id] as MeshInstance3D).visible = in_settings
	(_labels[HINT] as Label3D).visible = not _compact


func _apply_alpha() -> void:
	if _tokens == null:
		return
	for id in _labels.keys():
		var label := _labels[id] as Label3D
		var fill: Color = _label_colours[id]
		# Keep the charcoal fill dark over snow. The paired snow edge below is the
		# second contrast channel when a depth-composited word crosses scenery.
		fill.a *= _alpha
		label.modulate = fill
		var outline := _tokens.ink_primary
		outline.a *= _alpha
		label.outline_modulate = outline
	for id in _line_materials.keys():
		var material := _line_materials[id] as StandardMaterial3D
		var colour := _tokens.line_hairline
		colour.r *= PAUSE_TREATMENT_COMPENSATION
		colour.g *= PAUSE_TREATMENT_COMPENSATION
		colour.b *= PAUSE_TREATMENT_COMPENSATION
		colour.a *= _alpha
		material.albedo_color = colour
	for id in _ornament_materials.keys():
		var ornament_material := _ornament_materials[id] as StandardMaterial3D
		var ornament_colour := _tokens.line_hairline
		ornament_colour.r *= PAUSE_TREATMENT_COMPENSATION
		ornament_colour.g *= PAUSE_TREATMENT_COMPENSATION
		ornament_colour.b *= PAUSE_TREATMENT_COMPENSATION
		ornament_colour.a *= _tokens.opacity_steps[1] * _alpha
		ornament_material.albedo_color = ornament_colour
	for id in _track_materials.keys():
		var track_material := _track_materials[id] as StandardMaterial3D
		var track_colour := _tokens.line_hairline
		track_colour.r *= PAUSE_TREATMENT_COMPENSATION
		track_colour.g *= PAUSE_TREATMENT_COMPENSATION
		track_colour.b *= PAUSE_TREATMENT_COMPENSATION
		track_colour.a *= _alpha
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
		var measured := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, BASE_FONT_SIZE).x
		label.width = maxi(int(ceilf(measured)), 1)
		label.pixel_size = world_per_pixel * screen_size / float(BASE_FONT_SIZE)
		# Label3D's LEFT alignment treats its origin as the left edge of the text
		# box. Adding half the measured width here was a double-centering error and
		# separated the visible glyphs from their accessible Canvas hit targets.
		var label_transform := label.global_transform
		label_transform.origin = _camera.project_position(_targets[id] as Vector2, _depth)
		label_transform.basis = _camera.global_transform.basis.orthonormalized() \
			* Basis.from_euler(_label_tilts[id] as Vector3)
		label.global_transform = label_transform

	for id in _lines.keys():
		var amount := clampf(float(_line_amounts.get(id, 0.0)), 0.0, 1.0)
		var screen_width := float(_line_widths[id]) * amount
		var center := Vector2(float(_line_lefts[id]) + screen_width * 0.5, float(_line_y[id]))
		var line := _lines[id] as MeshInstance3D
		var quad := line.mesh as QuadMesh
		quad.size = Vector2(maxf(screen_width * world_per_pixel, 0.001),
			maxf(float(_line_heights[id]) * world_per_pixel, 0.001))
		var transform := line.global_transform
		transform.origin = _camera.project_position(center, _depth - 0.01)
		var tilt: Vector3 = _label_tilts.get(id,
			_label_tilts.get(STATUS, Vector3.ZERO)) as Vector3
		transform.basis = _camera.global_transform.basis.orthonormalized() \
			* Basis.from_euler(tilt)
		line.global_transform = transform

	for id in _ornaments.keys():
		var ornament := _ornaments[id] as MeshInstance3D
		var quad := ornament.mesh as QuadMesh
		quad.size = (_ornament_sizes[id] as Vector2) * world_per_pixel
		var transform := ornament.global_transform
		transform.origin = _camera.project_position(
			_ornament_positions[id] as Vector2, _depth + 0.04)
		transform.basis = _camera.global_transform.basis.orthonormalized() \
			* Basis.from_euler(_ornament_tilts[id] as Vector3)
		ornament.global_transform = transform

	for id in _tracks.keys():
		var track := _tracks[id] as MeshInstance3D
		if not track.visible:
			continue
		var rect := _track_layouts[id] as Rect2
		var track_quad := track.mesh as QuadMesh
		track_quad.size = Vector2(maxf(rect.size.x * world_per_pixel, 0.001),
			maxf(rect.size.y * world_per_pixel, 0.001))
		var track_transform := track.global_transform
		track_transform.origin = _camera.project_position(rect.get_center(), _depth - 0.01)
		track_transform.basis = _camera.global_transform.basis.orthonormalized() \
			* Basis.from_euler(_label_tilts.get(QUESTION, Vector3.ZERO) as Vector3)
		track.global_transform = track_transform


func _world_per_pixel(viewport_height: float) -> float:
	if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return _camera.size / viewport_height
	return 2.0 * _depth * tan(deg_to_rad(_camera.fov) * 0.5) / viewport_height
