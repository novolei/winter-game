class_name ExitMenu
extends CanvasLayer

## The pause surface is composed like a quiet part of the valley rather than a
## card laid over it. The world remains the largest shape; type, hairlines and
## empty space carry the interaction. This follows UI design document section
## 4.3 and borrows Monument Valley's useful principle: navigation belongs to the
## picture's spatial composition, not to a generic application window.

const TOKENS_PATH := "res://data/ui/tokens.tres"
const SETTINGS_PATH := "res://data/ui/accessibility_settings.tres"
const STATE_MENU := &"menu"
const STATE_SETTINGS := &"settings"
const STATE_CONFIRM := &"confirm"
const LAYER_ORDER := 90
const CONFIRM_GUARD_MSEC := 180
const QUIT_SOUND_SECONDS := 0.12
const CAMERA_SERVICE_KEY := &"camera_rig"
const CAMERA_MODIFIER_SOURCE := &"pause_cinematic"
## A quiet aerial pause tableau. The ordinary -45/-35 three-quarter view opens
## by 1.85x, pitches eleven degrees further down and swings fifteen degrees
## across the valley. The player becomes the warm anchor inside a readable
## piece of landscape instead of a stiff close-up subject. Camera-local offset
## leaves the left field to the spatial copy and settles the figure low-right.
const CINEMATIC_FRAME_FACTOR := 1.85
const CINEMATIC_LEAN := Vector3(-0.191986, 0.261799, 0.0)
const CINEMATIC_COMPOSITION_OFFSET := Vector2(-2.4, 1.15)
const CINEMATIC_BOOM_FACTOR := 1.08
# At the 744x392 development window, the strict 1080p ratio would make Title 34
# only twelve device pixels. The menu is a decision surface, so it keeps an
# accessibility floor while the world-oriented breath UI continues to scale
# strictly. This still leaves more than half of the compact frame untouched.
const MIN_FRAME_SCALE := 0.78
const MAX_FRAME_SCALE := 1.25
const MIN_HIT_HEIGHT := 44.0
const DAY_GLYPHS := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _audio: UIAudio = null
var _clock = null
var _spatial: SpatialPauseMenu = null
var _camera_rig = null
var _camera_modifier: Modifier = null

var _root: Control = null
var _world_treatment: ColorRect = null
var _content: Control = null
var _context: VBoxContainer = null
var _context_line: ColorRect = null
var _status_label: Label = null
var _remaining_caption: Label = null
var _remaining_value: Label = null
var _state_slot: Control = null
var _menu_panel: VBoxContainer = null
var _settings_panel: VBoxContainer = null
var _confirm_panel: VBoxContainer = null
var _confirmation_label: Label = null
var _hint_label: Label = null

var _continue_button: Button = null
var _settings_button: Button = null
var _exit_button: Button = null
var _confirm_button: Button = null
var _cancel_button: Button = null
var _choice_lines: Dictionary = {}
var _choice_line_widths: Dictionary = {}
var _settings_catalog: AccessibilityCatalog = null
var _settings_row_buttons: Array[Button] = []
# Parallel to _settings_row_buttons: the entry each row adjusts. Rows are built
# from the catalog but must never re-index it -- null catalog slots are skipped
# at build time, so a row index is not an entries index.
var _settings_row_settings: Array[AccessibilitySetting] = []
var _settings_focus_index := 0
var _state: StringName = STATE_MENU
var _ui_layer = null

var _quit_action: Callable
var _animation: Tween = null
var _transition: Tween = null
var _frame_scale := 1.0
var _content_home := Vector2.ZERO
var _paused_by_menu := false
var _quit_accepted := false
var _is_open := false
var _confirmation_started_msec := 0
var _camera_factor := 1.0
var _camera_base_lean := Vector3.ZERO
var _camera_base_composition := Vector2.ZERO
var _camera_base_boom_factor := 1.0
var _camera_pose_captured := false
var _spatial_mode := false

var _choreography = null   # PauseChoreography，打开/关闭期间持有


func _ready() -> void:
	if _root == null:
		build()
	if _clock == null:
		_clock = get_node_or_null("/root/WorldClock")
	_resolve_camera_presentation()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()


func build() -> void:
	if _root != null:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = LAYER_ORDER
	_tokens = ResourceLoader.load(TOKENS_PATH) as UITokens
	_fonts = UIFonts.new()
	_fonts.build(_tokens)
	_audio = UIAudio.new()
	_audio.name = "Voice"
	add_child(_audio)
	_audio.load_map()
	_spatial = SpatialPauseMenu.new()
	_spatial.name = "SpatialPauseMenu"
	_spatial.setup(_tokens, _fonts)
	add_child(_spatial)
	if not _quit_action.is_valid():
		_quit_action = _quit_game

	_root = Control.new()
	_root.name = "ExitMenuRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_world_treatment = ColorRect.new()
	_world_treatment.name = "FrozenWorldTreatment"
	_world_treatment.mouse_filter = Control.MOUSE_FILTER_STOP
	_world_treatment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# This node is only the modal input shield. Pause must preserve the world's
	# authored palette, exposure and atmospheric colour exactly as rendered.
	var transparent_world := _tokens.ink_primary
	transparent_world.a = 0.0
	_world_treatment.color = transparent_world
	_root.add_child(_world_treatment)

	_content = Control.new()
	_content.name = "BreathRail"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)

	_build_context()
	_build_states()
	_build_hint()
	layout_for_viewport(Vector2(1920.0, 1080.0))

	visible = false
	_is_open = false
	_show_confirmation(false, false)


func _build_context() -> void:
	_context = VBoxContainer.new()
	_context.name = "NightContext"
	_context.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_context)

	_status_label = Label.new()
	_status_label.name = "DayAndPhase"
	_status_label.text = "第 一 日 · 昼"
	_status_label.add_theme_font_override("font", _fonts.display)
	_status_label.add_theme_color_override("font_color", _tokens.ink_primary)
	_context.add_child(_status_label)

	_context_line = ColorRect.new()
	_context_line.name = "ContextHairline"
	_context_line.color = _tokens.line_hairline
	_context_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_context_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_context.add_child(_context_line)

	var remaining := HBoxContainer.new()
	remaining.name = "Remaining"
	remaining.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_context.add_child(remaining)

	_remaining_caption = Label.new()
	_remaining_caption.name = "Caption"
	_remaining_caption.text = "天光尚余"
	_remaining_caption.add_theme_font_override("font", _fonts.interface)
	_remaining_caption.add_theme_color_override("font_color", _tokens.ink_secondary)
	remaining.add_child(_remaining_caption)

	_remaining_value = Label.new()
	_remaining_value.name = "Time"
	_remaining_value.text = "00:00"
	_remaining_value.add_theme_font_override("font", _fonts.instrument)
	_remaining_value.add_theme_color_override("font_color", _tokens.ink_primary)
	remaining.add_child(_remaining_value)


func _build_states() -> void:
	_state_slot = Control.new()
	_state_slot.name = "StateSlot"
	_state_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_state_slot)

	_menu_panel = VBoxContainer.new()
	_menu_panel.name = "PauseActions"
	_menu_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state_slot.add_child(_menu_panel)

	_continue_button = _make_choice("继　续", 104.0)
	_continue_button.name = "Continue"
	_continue_button.pressed.connect(continue_game)
	_menu_panel.add_child(_continue_button)

	_settings_button = _make_choice("设　置", 104.0)
	_settings_button.name = "Settings"
	_settings_button.pressed.connect(open_settings)
	_menu_panel.add_child(_settings_button)

	_exit_button = _make_choice("退出游戏", 144.0)
	_exit_button.name = "Exit"
	_exit_button.pressed.connect(request_exit)
	_menu_panel.add_child(_exit_button)

	_settings_panel = VBoxContainer.new()
	_settings_panel.name = "AccessibilitySettings"
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_panel.visible = false
	_state_slot.add_child(_settings_panel)

	var settings_heading := Label.new()
	settings_heading.name = "Heading"
	settings_heading.text = "设　置"
	settings_heading.add_theme_font_override("font", _fonts.display)
	settings_heading.add_theme_color_override("font_color", _tokens.ink_primary)
	_settings_panel.add_child(settings_heading)
	_build_settings_rows()

	_confirm_panel = VBoxContainer.new()
	_confirm_panel.name = "ExitConfirmation"
	_confirm_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state_slot.add_child(_confirm_panel)

	_confirmation_label = Label.new()
	_confirmation_label.name = "Question"
	_confirmation_label.text = "要离开这场长夜吗？"
	_confirmation_label.add_theme_font_override("font", _fonts.display)
	_confirmation_label.add_theme_color_override("font_color", _tokens.ink_primary)
	_confirm_panel.add_child(_confirmation_label)

	var detail := Label.new()
	detail.name = "Consequence"
	detail.text = "当前进度可能不会保留。"
	detail.add_theme_font_override("font", _fonts.interface)
	detail.add_theme_color_override("font_color", _tokens.ink_secondary)
	_confirm_panel.add_child(detail)

	var actions := HBoxContainer.new()
	actions.name = "ConfirmationActions"
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_confirm_panel.add_child(actions)

	_cancel_button = _make_choice("返　回", 104.0)
	_cancel_button.name = "Return"
	_cancel_button.pressed.connect(cancel_exit)
	actions.add_child(_cancel_button)

	_confirm_button = _make_choice("确　认", 104.0)
	_confirm_button.name = "ConfirmExit"
	_confirm_button.pressed.connect(confirm_exit)
	actions.add_child(_confirm_button)

	_continue_button.focus_neighbor_bottom = _continue_button.get_path_to(_settings_button)
	_settings_button.focus_neighbor_top = _settings_button.get_path_to(_continue_button)
	_settings_button.focus_neighbor_bottom = _settings_button.get_path_to(_exit_button)
	_exit_button.focus_neighbor_top = _exit_button.get_path_to(_settings_button)
	for i in range(_settings_row_buttons.size()):
		var row: Button = _settings_row_buttons[i]
		if i > 0:
			row.focus_neighbor_top = row.get_path_to(_settings_row_buttons[i - 1])
		if i + 1 < _settings_row_buttons.size():
			row.focus_neighbor_bottom = row.get_path_to(_settings_row_buttons[i + 1])


func _build_settings_rows() -> void:
	_settings_catalog = ResourceLoader.load(SETTINGS_PATH) as AccessibilityCatalog
	if _settings_catalog == null:
		return
	for entry in _settings_catalog.entries:
		if entry == null:
			continue
		var row := _make_choice(_settings_row_text(entry), 264.0)
		row.name = String(entry.id).to_pascal_case()
		var index := _settings_row_buttons.size()
		row.pressed.connect(_adjust_setting_at.bind(index, 1))
		row.focus_entered.connect(_set_settings_focus_index.bind(index))
		_settings_panel.add_child(row)
		_settings_row_buttons.append(row)
		_settings_row_settings.append(entry)


func _build_hint() -> void:
	_hint_label = Label.new()
	_hint_label.name = "KeyboardHint"
	_hint_label.text = "ESC   返回风雪"
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_override("font", _fonts.interface)
	_hint_label.add_theme_color_override("font_color", _tokens.ink_secondary)
	_content.add_child(_hint_label)


func _make_choice(text_value: String, underline_design_width: float) -> Button:
	var button := Button.new()
	button.text = text_value
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _fonts.display)
	# The authored muted ink works for transient words standing on controlled
	# plates. This menu deliberately has no plate; the real 720p capture showed
	# its anti-aliased strokes disappearing into the paused snow. Secondary is
	# still subordinate to focus/primary, but survives the world treatment.
	button.add_theme_color_override("font_color", _tokens.ink_secondary)
	button.add_theme_color_override("font_hover_color", _tokens.ink_primary)
	button.add_theme_color_override("font_focus_color", _tokens.ink_primary)
	button.add_theme_color_override("font_pressed_color", _tokens.ink_primary)
	button.add_theme_color_override("font_hover_pressed_color", _tokens.ink_primary)
	for state in ["normal", "hover", "focus", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())

	var line := ColorRect.new()
	line.name = "FocusHairline"
	line.color = _tokens.line_hairline
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchor(SIDE_TOP, 1.0)
	line.set_anchor(SIDE_BOTTOM, 1.0)
	line.offset_top = -5.0
	line.offset_bottom = -4.0
	line.scale.x = 0.0
	button.add_child(line)
	_choice_lines[button] = line
	_choice_line_widths[button] = underline_design_width

	button.focus_entered.connect(_on_choice_focus_entered.bind(button))
	button.focus_exited.connect(_on_choice_focus_exited.bind(button))
	button.mouse_entered.connect(_on_choice_mouse_entered.bind(button))
	button.mouse_exited.connect(_on_choice_mouse_exited.bind(button))
	return button


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		handle_cancel()
		get_viewport().set_input_as_handled()
	elif is_adjusting() and event.is_action_pressed("ui_left"):
		adjust_focused(-1)
		get_viewport().set_input_as_handled()
	elif is_adjusting() and event.is_action_pressed("ui_right"):
		adjust_focused(1)
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _is_open:
		close(true)
	else:
		open()


func open() -> void:
	if _root == null:
		build()
	if _is_open:
		return
	if _clock == null and is_inside_tree():
		_clock = get_node_or_null("/root/WorldClock")
	_resolve_camera_presentation()
	refresh_context()
	_quit_accepted = false
	_is_open = true
	visible = true
	_show_confirmation(false, false)
	_pause_game()
	_prepare_camera_push()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_focus(_continue_button)
	_play(&"ui.bloom")
	_animate_open()


func continue_game() -> void:
	if not _is_open:
		return
	_play(&"ui.confirm")
	close(false)


func close(play_back_sound := false) -> void:
	if not _is_open:
		return
	_is_open = false
	if play_back_sound:
		_play(&"ui.back")
	if not is_inside_tree():
		_finish_close()
		return
	_kill_animation()
	_kill_transition()
	_choreography = PauseChoreography.closing(_tokens, _cascade_ids())
	_animation = create_tween()
	_animation.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_animation.tween_method(_apply_choreography, 0.0,
		_choreography.total_seconds(), _choreography.total_seconds())
	_animation.parallel().tween_method(_set_cinematic_factor, _camera_factor, 1.0,
		_choreography.total_seconds())
	_animation.chain().tween_callback(_finish_close)


func handle_cancel() -> void:
	if not _is_open:
		open()
	elif is_adjusting():
		close_settings()
	elif is_confirming():
		cancel_exit()
	else:
		close(true)


func open_settings() -> void:
	if not _is_open or _quit_accepted or _state != STATE_MENU or _settings_panel == null:
		return
	_play(&"ui.confirm")
	_show_settings(true, is_inside_tree())


func close_settings() -> void:
	if not is_adjusting():
		return
	_play(&"ui.back")
	_show_settings(false, is_inside_tree())


func request_exit() -> void:
	if not _is_open or _quit_accepted or _state != STATE_MENU:
		return
	_play(&"ui.confirm")
	_confirmation_started_msec = Time.get_ticks_msec()
	_show_confirmation(true, true)
	_focus(_cancel_button)


func cancel_exit() -> void:
	if not _is_open or not is_confirming():
		return
	_play(&"ui.back")
	_show_confirmation(false, true)
	_focus(_exit_button)


func confirm_exit() -> void:
	if not _is_open or not is_confirming() or _quit_accepted:
		return
	if is_inside_tree() and Time.get_ticks_msec() - _confirmation_started_msec < CONFIRM_GUARD_MSEC:
		return
	_quit_accepted = true
	_play(&"ui.confirm")
	if is_inside_tree():
		get_tree().create_timer(QUIT_SOUND_SECONDS, true).timeout.connect(_quit_action.call,
			CONNECT_ONE_SHOT)
	else:
		_quit_action.call()


func set_quit_action(action: Callable) -> void:
	_quit_action = action


func set_clock(clock) -> void:
	_clock = clock


func refresh_context() -> void:
	if _status_label == null:
		return
	var day := 1
	var night := false
	var remaining := 0.0
	if _clock != null:
		if _clock.has_method("current_day"):
			day = int(_clock.current_day())
		if _clock.has_method("is_night"):
			night = bool(_clock.is_night())
		if _clock.has_method("phase_duration") and _clock.has_method("phase_elapsed"):
			remaining = maxf(float(_clock.phase_duration()) - float(_clock.phase_elapsed()), 0.0)
	_status_label.text = "第 %s 日 · %s" % [_day_word(day), "夜" if night else "昼"]
	_remaining_caption.text = "长夜尚余" if night else "天光尚余"
	var whole_seconds := maxi(int(ceilf(remaining)), 0)
	_remaining_value.text = "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]
	if _spatial != null:
		_spatial.set_context(_status_label.text, _remaining_caption.text, _remaining_value.text)


func layout_for_viewport(viewport_size: Vector2) -> void:
	if _content == null or _tokens == null:
		return
	_frame_scale = clampf(_tokens.scale_for(viewport_size), MIN_FRAME_SCALE, MAX_FRAME_SCALE)
	var compact := viewport_size.y < 540.0
	var design_height := 320.0 if compact else 420.0
	var width := 384.0 * _frame_scale
	var height := design_height * _frame_scale
	var edge := safe_edge(viewport_size)
	var top := maxf((viewport_size.y - height) * 0.5, edge)
	_content.position = Vector2(edge, top)
	_content.size = Vector2(width, height)
	_content_home = _content.position

	var context_height := (88.0 if compact else 104.0) * _frame_scale
	_context.position = Vector2.ZERO
	_context.size = Vector2(width, context_height)
	_context.add_theme_constant_override("separation", maxi(int(roundf(10.0 * _frame_scale)), 4))
	_status_label.add_theme_font_size_override("font_size", maxi(int(roundf(42.0 * _frame_scale)), 26))
	_context_line.custom_minimum_size = Vector2(264.0 * _frame_scale, maxf(roundf(_frame_scale), 1.0))
	var remaining_row := _remaining_caption.get_parent() as HBoxContainer
	remaining_row.add_theme_constant_override("separation", maxi(int(roundf(16.0 * _frame_scale)), 8))
	_remaining_caption.add_theme_font_size_override("font_size", maxi(int(roundf(15.0 * _frame_scale)), 12))
	_remaining_value.add_theme_font_size_override("font_size", maxi(int(roundf(20.0 * _frame_scale)), 15))

	var state_y := (104.0 if compact else 144.0) * _frame_scale
	_state_slot.position = Vector2(0.0, state_y)
	_state_slot.size = Vector2(width, (164.0 if compact else 192.0) * _frame_scale)
	_menu_panel.add_theme_constant_override("separation", maxi(int(roundf(8.0 * _frame_scale)), 6))
	_settings_panel.add_theme_constant_override("separation", maxi(int(roundf(4.0 * _frame_scale)), 2))
	_confirm_panel.add_theme_constant_override("separation", maxi(int(roundf(12.0 * _frame_scale)), 8))
	_confirmation_label.add_theme_font_size_override("font_size", maxi(int(roundf(34.0 * _frame_scale)), 22))
	var consequence := _confirmation_label.get_parent().get_node("Consequence") as Label
	consequence.add_theme_font_size_override("font_size", maxi(int(roundf(17.0 * _frame_scale)), 14))
	var confirmation_actions := _cancel_button.get_parent() as HBoxContainer
	confirmation_actions.add_theme_constant_override("separation", maxi(int(roundf(64.0 * _frame_scale)), 32))

	var hit_height := maxf(56.0 * _frame_scale, MIN_HIT_HEIGHT)
	for button in _choice_lines.keys():
		button.custom_minimum_size = Vector2(112.0 * _frame_scale, hit_height)
		button.add_theme_font_size_override("font_size", maxi(int(roundf(34.0 * _frame_scale)), 22))
		var line: ColorRect = _choice_lines[button]
		line.offset_right = float(_choice_line_widths[button]) * _frame_scale
		line.offset_top = -maxf(5.0 * _frame_scale, 4.0)
		line.offset_bottom = line.offset_top + maxf(roundf(_frame_scale), 1.0)

	_hint_label.visible = not compact
	_hint_label.position = Vector2(0.0, 392.0 * _frame_scale)
	_hint_label.size = Vector2(width, 24.0 * _frame_scale)
	_hint_label.add_theme_font_size_override("font_size", maxi(int(roundf(14.0 * _frame_scale)), 12))
	if _spatial != null:
		_spatial.layout(Rect2(_content.position, _content.size), _frame_scale, compact, state_y)


func is_open() -> bool:
	return _is_open


func is_confirming() -> bool:
	return _state == STATE_CONFIRM


func is_adjusting() -> bool:
	return _state == STATE_SETTINGS


func state() -> StringName:
	return _state


func continue_button() -> Button:
	return _continue_button


func settings_button() -> Button:
	return _settings_button


func exit_button() -> Button:
	return _exit_button


func confirm_button() -> Button:
	return _confirm_button


func cancel_button() -> Button:
	return _cancel_button


func settings_row_buttons() -> Array[Button]:
	return _settings_row_buttons


func adjust_focused(direction: int) -> bool:
	if direction == 0:
		return false
	return _adjust_setting_at(_settings_focus_index, direction)


func world_treatment() -> ColorRect:
	return _world_treatment


func audio() -> UIAudio:
	return _audio


func spatial_labels() -> Array[Label3D]:
	return [] if _spatial == null else _spatial.labels()


func spatial_ornaments() -> Array[MeshInstance3D]:
	return [] if _spatial == null else _spatial.ornaments()


func spatial_copy_has_tilt() -> bool:
	return _spatial != null and _spatial.has_authored_tilt()


func cinematic_factor() -> float:
	return _camera_factor


func set_camera_rig(rig) -> void:
	_camera_rig = rig
	if _spatial == null or _camera_rig == null or not _camera_rig.has_method("camera"):
		return
	var camera := _camera_rig.camera() as Camera3D
	if camera != null:
		_spatial.set_camera(camera)
		_enable_spatial_mode()


func status_text() -> String:
	return "" if _status_label == null else _status_label.text


func remaining_text() -> String:
	return "" if _remaining_value == null else _remaining_value.text


func confirmation_title() -> String:
	return "" if _confirmation_label == null else _confirmation_label.text


func content_rect() -> Rect2:
	return Rect2() if _content == null else Rect2(_content.position, _content.size)


func safe_edge(viewport_size: Vector2) -> float:
	return 0.0 if _tokens == null else _tokens.edge_pixels(viewport_size)


func _show_confirmation(show: bool, animate: bool) -> void:
	_state = STATE_CONFIRM if show else STATE_MENU
	if _menu_panel != null:
		_menu_panel.visible = not show
	if _settings_panel != null:
		_settings_panel.visible = false
	if _confirm_panel != null:
		_confirm_panel.visible = show
	if _hint_label != null:
		_hint_label.text = "ESC   返回暂停" if show else "ESC   返回风雪"
	if _spatial != null:
		_spatial.set_state(STATE_CONFIRM if show else STATE_MENU)
	if animate and is_inside_tree():
		_kill_transition()
		_choreography = PauseChoreography.opening(_tokens, _cascade_ids())
		_apply_choreography(0.0)
		_transition = create_tween()
		_transition.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_transition.tween_method(_apply_choreography, 0.0,
			_choreography.total_seconds(), _choreography.total_seconds())
	else:
		_choreography = PauseChoreography.opening(_tokens, _cascade_ids())
		_apply_choreography(_choreography.total_seconds())


func _show_settings(show: bool, animate: bool) -> void:
	_state = STATE_SETTINGS if show else STATE_MENU
	if _menu_panel != null:
		_menu_panel.visible = not show
	if _settings_panel != null:
		_settings_panel.visible = show
	if _confirm_panel != null:
		_confirm_panel.visible = false
	if _hint_label != null:
		_hint_label.text = "ESC   返回暂停" if show else "ESC   返回风雪"
	if show and not _settings_row_buttons.is_empty():
		_settings_focus_index = clampi(_settings_focus_index, 0,
			_settings_row_buttons.size() - 1)
	if _spatial != null:
		_spatial.set_state(STATE_SETTINGS if show else STATE_MENU)
	if animate and is_inside_tree():
		_kill_transition()
		_choreography = PauseChoreography.opening(_tokens, _cascade_ids())
		_apply_choreography(0.0)
		_transition = create_tween()
		_transition.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_transition.tween_method(_apply_choreography, 0.0,
			_choreography.total_seconds(), _choreography.total_seconds())
	else:
		_choreography = PauseChoreography.opening(_tokens, _cascade_ids())
		_apply_choreography(_choreography.total_seconds())
	if show and not _settings_row_buttons.is_empty():
		_focus(_settings_row_buttons[_settings_focus_index])
	elif not show:
		_focus(_settings_button)


func _set_settings_focus_index(index: int) -> void:
	_settings_focus_index = index


func _adjust_setting_at(index: int, direction: int) -> bool:
	if not is_adjusting() or direction == 0:
		return false
	if index < 0 or index >= _settings_row_settings.size():
		return false
	var entry := _settings_row_settings[index]
	var old_value := SettingsStore.value(entry.id, entry.default_value)
	var new_value := entry.stepped(old_value, direction)
	if is_equal_approx(old_value, new_value):
		# At a boundary the step refuses instead of wrapping -- a wall, not an
		# error.
		_play(&"ui.boundary")
		return false
	SettingsStore.store(entry.id, new_value)
	_apply_setting(entry, index)
	_play(&"ui.move")
	return true


func _apply_setting(entry: AccessibilitySetting, index: int) -> void:
	_settings_row_buttons[index].text = _settings_row_text(entry)
	match entry.id:
		&"prompt_hold", &"stroke_bold":
			_resolve_ui_layer()
			if _ui_layer != null:
				_ui_layer.apply_accessibility()
		# screen_shake: persisted only -- the shake system it gates has not
		# shipped yet (DEFERRED).
	if _spatial != null:
		_spatial.set_row_value(entry.id, entry.format_value(
			SettingsStore.value(entry.id, entry.default_value)),
			entry.fraction_of(SettingsStore.value(entry.id, entry.default_value)))
		_spatial.pulse_row_value(entry.id)


func _resolve_ui_layer() -> void:
	if _ui_layer != null or not is_inside_tree():
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null:
		_ui_layer = registry.get_service(UILayer.SERVICE_KEY)


func _settings_row_text(entry: AccessibilitySetting) -> String:
	var value := SettingsStore.value(entry.id, entry.default_value)
	return "%s　%s" % [entry.label, entry.format_value(value)]


## The lines the open cascade breathes in, in order. Spatial ids; the canvas
## fallback maps them in _cascade_canvas_line().
func _cascade_ids() -> Array[StringName]:
	var ids: Array[StringName] = [
		SpatialPauseMenu.STATUS, SpatialPauseMenu.CONTEXT_LINE,
		SpatialPauseMenu.CAPTION, SpatialPauseMenu.TIME,
	]
	if _state == STATE_SETTINGS:
		if _spatial != null:
			ids.append_array(_spatial.row_label_ids())
			ids.append_array(_spatial.track_ids())
	elif _state == STATE_CONFIRM:
		ids.append_array([SpatialPauseMenu.QUESTION, SpatialPauseMenu.CONSEQUENCE,
			SpatialPauseMenu.RETURN, SpatialPauseMenu.CONFIRM])
	else:
		ids.append_array([SpatialPauseMenu.CONTINUE, SpatialPauseMenu.SETTINGS,
			SpatialPauseMenu.EXIT])
	ids.append(SpatialPauseMenu.HINT)
	return ids


func _apply_choreography(t: float) -> void:
	if _choreography == null:
		return
	for i in range(_choreography.lines.size()):
		var id: StringName = _choreography.lines[i]
		var alpha: float = _choreography.alpha_at(i, t)
		var offset: float = _choreography.offset_at(i, t)
		if _spatial_mode and _spatial != null:
			_spatial.set_line_envelope(id, alpha * _spatial.alpha(), offset)
		else:
			_cascade_canvas_line(id, alpha, offset)


func _cascade_canvas_line(id: StringName, alpha: float, offset: float) -> void:
	# 非 spatial 模式（无相机）：Canvas 控件自己做级联。
	var control: Control = null
	match id:
		SpatialPauseMenu.STATUS: control = _status_label
		SpatialPauseMenu.CONTEXT_LINE: control = _context_line
		SpatialPauseMenu.CAPTION: control = _remaining_caption
		SpatialPauseMenu.TIME: control = _remaining_value
		SpatialPauseMenu.CONTINUE: control = _continue_button
		SpatialPauseMenu.SETTINGS: control = _settings_button
		SpatialPauseMenu.EXIT: control = _exit_button
		SpatialPauseMenu.QUESTION: control = _confirmation_label
		SpatialPauseMenu.HINT: control = _hint_label
	if control == null:
		return
	control.modulate.a = alpha
	# 位置由容器管理的控件只调透明度；自由定位的（hint）带位移。
	if control == _hint_label:
		control.position.y = 392.0 * _frame_scale + offset


func _animate_open() -> void:
	_set_cinematic_factor(CINEMATIC_FRAME_FACTOR)
	_content.modulate.a = 1.0
	_content.position = _content_home
	# The schedule exists in canvas mode too -- without a camera the Canvas
	# controls run the cascade themselves in _cascade_canvas_line().
	_choreography = PauseChoreography.opening(_tokens, _cascade_ids())
	if _spatial != null and _spatial.has_camera():
		_spatial.visible = true
		_spatial.set_alpha(1.0)
	if not is_inside_tree():
		# 无树（测试/截图具）：级联直接落终态。
		_apply_choreography(_choreography.total_seconds())
		return
	_kill_animation()
	_set_cinematic_factor(1.0)
	if _spatial != null and _spatial.has_camera():
		_spatial.set_alpha(1.0)
	_apply_choreography(0.0)
	_animation = create_tween()
	_animation.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_animation.tween_method(_apply_choreography, 0.0,
		_choreography.total_seconds(), _choreography.total_seconds())
	_animation.parallel().tween_method(_set_cinematic_factor, 1.0,
		CINEMATIC_FRAME_FACTOR, _choreography.total_seconds())


func _finish_close() -> void:
	if _is_open:
		return
	# Capture the ids the cascade was actually driving BEFORE the state reset
	# below swaps _cascade_ids() back to the menu set -- closing from settings
	# or confirmation must reset those rows' envelopes, not the menu's.
	var cascade_ids: Array[StringName] = []
	if _choreography != null:
		cascade_ids = _choreography.lines.duplicate()
	visible = false
	_show_confirmation(false, false)
	_set_cinematic_factor(1.0)
	_release_camera_push()
	_content.modulate.a = 1.0
	_content.position = _content_home
	_choreography = null
	if _spatial != null:
		if cascade_ids.is_empty():
			cascade_ids = _cascade_ids()
		_spatial.reset_envelopes(cascade_ids)
		_spatial.visible = false
		_spatial.set_alpha(1.0)
	_resume_game()


func _on_viewport_size_changed() -> void:
	if not is_inside_tree():
		return
	layout_for_viewport(get_viewport().get_visible_rect().size)


func _on_choice_focus_entered(button: Button) -> void:
	_set_choice_line(button, true)
	var row_index := _settings_row_buttons.find(button)
	if row_index >= 0:
		# Canvas 侧焦点行加粗一档（非 spatial 模式可见；spatial 侧由 set_focus 处理）。
		button.add_theme_font_override("font", _fonts.interface_at(
			_tokens.interface_latin_weight + 100, _tokens.interface_cjk_weight + 100))
	if _spatial != null:
		var focus_id := _spatial_choice_id(button)
		if row_index >= 0:
			focus_id = StringName("row_%s" % _settings_row_settings[row_index].id)
		_spatial.set_focus(focus_id)
	if _is_open:
		_play(&"ui.move")


func _on_choice_focus_exited(button: Button) -> void:
	if not button.is_hovered():
		_set_choice_line(button, false)
	button.add_theme_font_override("font", _fonts.display)


func _on_choice_mouse_entered(button: Button) -> void:
	if _is_open:
		button.grab_focus()
	_set_choice_line(button, true)


func _on_choice_mouse_exited(button: Button) -> void:
	if not button.has_focus():
		_set_choice_line(button, false)


func _set_choice_line(button: Button, active: bool) -> void:
	var line := _choice_lines.get(button) as ColorRect
	if line == null:
		return
	var target := 1.0 if active else 0.0
	if not is_inside_tree():
		line.scale.x = target
		return
	var tween := line.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(line, "scale:x", target, _tokens.bloom_seconds)


func _day_word(day: int) -> String:
	if day >= 0 and day < DAY_GLYPHS.size():
		return DAY_GLYPHS[day]
	return str(day)


func _play(cue_id: StringName) -> void:
	if _audio != null:
		_audio.play(cue_id)


func _pause_game() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree.paused:
		return
	tree.paused = true
	_paused_by_menu = true


func _resume_game() -> void:
	if is_inside_tree() and _paused_by_menu:
		get_tree().paused = false
	_paused_by_menu = false


func _focus(control: Control) -> void:
	if is_inside_tree() and control != null:
		control.grab_focus()


func _kill_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_animation = null


func _kill_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null


func _resolve_camera_presentation() -> void:
	if _camera_rig != null or not is_inside_tree():
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return
	set_camera_rig(registry.get_service(CAMERA_SERVICE_KEY))


func _enable_spatial_mode() -> void:
	if _spatial_mode:
		return
	_spatial_mode = true
	# Keep the Canvas controls alive as accessible hit targets and keyboard focus
	# owners, but move every visible glyph into the depth-tested 3D copy.
	for control in [_status_label, _context_line, _remaining_caption, _remaining_value,
			_confirmation_label, _hint_label]:
		if control != null:
			control.modulate.a = 0.0
	var consequence := _confirmation_label.get_parent().get_node_or_null("Consequence") as Label
	if consequence != null:
		consequence.modulate.a = 0.0
	var settings_heading := _settings_panel.get_node_or_null("Heading") as Label
	if settings_heading != null:
		settings_heading.modulate.a = 0.0
	var transparent := _tokens.ink_primary
	transparent.a = 0.0
	for button in _choice_lines.keys():
		for state in ["font_color", "font_hover_color", "font_focus_color",
				"font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(state, transparent)
		(_choice_lines[button] as ColorRect).visible = false


func _prepare_camera_push() -> void:
	if _camera_rig == null:
		return
	_camera_rig.remove_framing_modifiers(CAMERA_MODIFIER_SOURCE)
	_camera_base_lean = _camera_rig.lean() if _camera_rig.has_method("lean") else Vector3.ZERO
	_camera_base_composition = _camera_rig.composition_offset() \
		if _camera_rig.has_method("composition_offset") else Vector2.ZERO
	_camera_base_boom_factor = _camera_rig.boom_factor() \
		if _camera_rig.has_method("boom_factor") else 1.0
	_camera_pose_captured = true
	_camera_modifier = Modifier.new()
	_camera_modifier.source_id = CAMERA_MODIFIER_SOURCE
	_camera_modifier.operation = Modifier.Operation.MULTIPLY
	_camera_modifier.value = 1.0
	_camera_modifier.duration = -1.0
	_camera_rig.push_framing_modifier(_camera_modifier)


func _set_cinematic_factor(value: float) -> void:
	_camera_factor = clampf(value,
		minf(1.0, CINEMATIC_FRAME_FACTOR), maxf(1.0, CINEMATIC_FRAME_FACTOR))
	if _camera_rig == null or _camera_modifier == null:
		return
	_camera_modifier.value = _camera_factor
	_camera_rig.settle_framing()
	if not _camera_pose_captured:
		return
	var amount := clampf(inverse_lerp(1.0, CINEMATIC_FRAME_FACTOR, _camera_factor), 0.0, 1.0)
	if _camera_rig.has_method("set_lean"):
		_camera_rig.set_lean(_camera_base_lean + CINEMATIC_LEAN * amount)
	if _camera_rig.has_method("set_composition_offset"):
		_camera_rig.set_composition_offset(
			_camera_base_composition + CINEMATIC_COMPOSITION_OFFSET * amount)
	if _camera_rig.has_method("set_boom_factor"):
		_camera_rig.set_boom_factor(_camera_base_boom_factor \
			* lerpf(1.0, CINEMATIC_BOOM_FACTOR, amount))


func _release_camera_push() -> void:
	if _camera_rig != null and _camera_pose_captured:
		if _camera_rig.has_method("set_lean"):
			_camera_rig.set_lean(_camera_base_lean)
		if _camera_rig.has_method("set_composition_offset"):
			_camera_rig.set_composition_offset(_camera_base_composition)
		if _camera_rig.has_method("set_boom_factor"):
			_camera_rig.set_boom_factor(_camera_base_boom_factor)
	if _camera_rig != null:
		_camera_rig.remove_framing_modifiers(CAMERA_MODIFIER_SOURCE)
	_camera_modifier = null
	_camera_pose_captured = false


func _spatial_choice_id(button: Button) -> StringName:
	if button == _continue_button:
		return SpatialPauseMenu.CONTINUE
	if button == _settings_button:
		return SpatialPauseMenu.SETTINGS
	if button == _exit_button:
		return SpatialPauseMenu.EXIT
	if button == _cancel_button:
		return SpatialPauseMenu.RETURN
	return SpatialPauseMenu.CONFIRM


func _quit_game() -> void:
	if is_inside_tree():
		get_tree().quit()


func _exit_tree() -> void:
	_kill_animation()
	_kill_transition()
	_set_cinematic_factor(1.0)
	_release_camera_push()
	_resume_game()
