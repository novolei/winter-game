extends TestCase

const ExitMenuScript := preload("res://src/ui/exit_menu.gd")
const UI_TOKENS: UITokens = preload("res://data/ui/tokens.tres")

var _menu = null
var _quit_calls := 0

class ClockStub extends RefCounted:
	func current_day() -> int:
		return 4

	func is_night() -> bool:
		return true

	func phase_duration() -> float:
		return 600.0

	func phase_elapsed() -> float:
		return 406.0

class CameraRigStub extends RefCounted:
	var current_lean := Vector3.ZERO
	var current_offset := Vector2.ZERO
	var current_boom_factor := 1.0
	var modifier = null

	func camera() -> Camera3D:
		return null

	func remove_framing_modifiers(_source: StringName) -> int:
		modifier = null
		return 1

	func push_framing_modifier(value) -> void:
		modifier = value

	func settle_framing() -> void:
		pass

	func set_lean(value: Vector3) -> void:
		current_lean = value

	func lean() -> Vector3:
		return current_lean

	func set_composition_offset(value: Vector2) -> void:
		current_offset = value

	func composition_offset() -> Vector2:
		return current_offset

	func set_boom_factor(value: float) -> void:
		current_boom_factor = value

	func boom_factor() -> float:
		return current_boom_factor

func before_each() -> void:
	_quit_calls = 0
	_menu = ExitMenuScript.new()
	_menu.set_quit_action(_record_quit)
	_menu.build()

func after_each() -> void:
	if _menu != null:
		_menu.free()
		_menu = null

func _record_quit() -> void:
	_quit_calls += 1

func test_menu_starts_closed() -> void:
	assert_false(_menu.is_open())
	assert_false(_menu.is_confirming())

func test_escape_opens_the_exit_menu() -> void:
	_menu.toggle()
	assert_true(_menu.is_open())
	assert_false(_menu.is_confirming())
	assert_eq(_menu.continue_button().text, "继　续")

func test_continue_is_the_primary_way_back_to_the_world() -> void:
	_menu.toggle()
	_menu.continue_game()
	assert_false(_menu.is_open())
	assert_eq(_quit_calls, 0)


func test_an_external_terminal_pause_cannot_open_a_false_continue_menu() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var was_paused := tree.paused
	tree.paused = false
	tree.root.add_child(_menu)
	tree.paused = true
	_menu.open()
	var opened: bool = _menu.is_open()
	tree.paused = was_paused
	assert_false(opened, "death pause exposed Continue back into a settled run")

func test_exit_button_requires_confirmation() -> void:
	_menu.toggle()
	_menu.request_exit()
	assert_true(_menu.is_open())
	assert_true(_menu.is_confirming())
	assert_eq(_quit_calls, 0, "the first exit click must never close the game")

func test_cancel_returns_to_the_first_menu() -> void:
	_menu.toggle()
	_menu.request_exit()
	_menu.cancel_exit()
	assert_true(_menu.is_open())
	assert_false(_menu.is_confirming())
	assert_eq(_quit_calls, 0)

func test_second_confirmation_quits_exactly_once() -> void:
	_menu.toggle()
	_menu.request_exit()
	_menu.confirm_exit()
	assert_eq(_quit_calls, 1)
	_menu.confirm_exit()
	assert_eq(_quit_calls, 1, "an already accepted confirmation fired twice")

func test_escape_from_confirmation_cancels_before_it_closes() -> void:
	_menu.toggle()
	_menu.request_exit()
	_menu.handle_cancel()
	assert_true(_menu.is_open())
	assert_false(_menu.is_confirming())
	_menu.handle_cancel()
	assert_false(_menu.is_open())

func test_buttons_use_the_projects_interface_font() -> void:
	assert_not_null(_menu.continue_button().get_theme_font("font"))
	assert_not_null(_menu.exit_button().get_theme_font("font"))
	assert_not_null(_menu.confirm_button().get_theme_font("font"))
	assert_not_null(_menu.cancel_button().get_theme_font("font"))

func test_pause_context_uses_the_live_clock_in_the_authored_format() -> void:
	_menu.set_clock(ClockStub.new())
	_menu.refresh_context()
	assert_eq(_menu.status_text(), "第 四 日 · 夜")
	assert_eq(_menu.remaining_text(), "03:14")

func test_pause_preserves_the_world_colour_without_a_center_card() -> void:
	assert_eq(_menu.world_treatment().material, null,
		"pause added a screen shader instead of preserving the authored world image")
	assert_almost_eq(_menu.world_treatment().color.a, 0.0, 0.0001,
		"the modal input shield tinted or dimmed the world")
	assert_eq(_count_card_panels(_menu), 0,
		"pause must remain part of the world, not a rectangular card over it")
	for button in [_menu.continue_button(), _menu.exit_button(),
			_menu.confirm_button(), _menu.cancel_button()]:
		assert_true(button.get_theme_stylebox("normal") is StyleBoxEmpty,
			"menu items must not bring the old rectangular button blocks back")

func test_pause_layout_protects_the_middle_of_the_world() -> void:
	for viewport_size in [Vector2(744.0, 392.0), Vector2(1920.0, 1080.0),
			Vector2(2560.0, 1080.0)]:
		_menu.layout_for_viewport(viewport_size)
		var rect: Rect2 = _menu.content_rect()
		assert_true(rect.position.x >= _menu.safe_edge(viewport_size) - 0.01)
		assert_true(rect.end.x <= viewport_size.x * 0.5,
			"the pause rail crossed the middle at %s: %s" % [viewport_size, rect])

func test_confirmation_uses_cold_ink_and_defaults_to_returning() -> void:
	_menu.toggle()
	_menu.request_exit()
	assert_eq(_menu.confirmation_title(), "要离开这场长夜吗？")
	assert_eq(_menu.confirm_button().get_theme_color("font_color"),
		_menu.cancel_button().get_theme_color("font_color"),
		"leaving is not heat or injury, so the dangerous option must not become warm/red")
	assert_eq(_menu.confirm_button().text, "确　认")
	assert_eq(_menu.cancel_button().text, "返　回")

func test_pause_menu_carries_the_authored_ui_voice() -> void:
	assert_not_null(_menu.audio())
	assert_true(_menu.audio().cue_count() > 0)

func test_pause_copy_is_spatial_type_that_world_geometry_cannot_occlude() -> void:
	var labels: Array[Label3D] = _menu.spatial_labels()
	assert_true(labels.size() >= 8, "day, time, actions and confirmation must all live in the world")
	for label in labels:
		# Owner ruling 2026-08-14: no roof, drift or wall may ever cover the
		# words. Only the falling snow -- transparent, camera-near, sorted after
		# the type -- still crosses it, exactly as weather should.
		assert_true(label.no_depth_test,
			"%s can be occluded by scenery; only snowflakes may cross the words" % label.name)
		assert_eq(label.billboard, BaseMaterial3D.BILLBOARD_DISABLED,
			"%s delegated tracking to billboard mode, which cannot carry spatial yaw" % label.name)
		assert_not_null(label.font, "%s fell back to a system font" % label.name)
	assert_true(_menu.spatial_copy_has_tilt(),
		"the tracked type is still a flat HUD plane rather than a spatial composition")

func test_spatial_copy_uses_cream_type_with_a_drop_shadow() -> void:
	# Owner ruling 2026-08-13: 奶白 bold type, NO outline -- the contrast comes
	# from the film dimming the world BEHIND the words, plus a dark ghost at
	# each word's lower right.
	var labels: Array[Label3D] = _menu.spatial_labels()
	for label in labels:
		assert_true(label.modulate.r >= UI_TOKENS.pause_ink_dim.r - 0.001,
			"%s fell below the dim tone -- pause type stays in the pause_* family" % label.name)
		assert_eq(label.outline_size, 0,
			"%s carries an outline; the pause face wears a shadow instead" % label.name)
	var shadows: Array[Label3D] = _menu.spatial_shadow_labels()
	assert_eq(shadows.size(), labels.size(),
		"every word needs exactly one shadow ghost at its lower right")
	for shadow in shadows:
		assert_true(shadow.modulate.r <= UI_TOKENS.pause_scrim.r + 0.001,
			"%s shadow must be the cold dark, not a second colour" % shadow.name)
		assert_eq(shadow.outline_size, 0)

func test_the_pause_surface_uses_only_minimal_unoccludable_ornaments() -> void:
	var ornaments: Array[MeshInstance3D] = _menu.spatial_ornaments()
	assert_true(ornaments.size() >= 2 and ornaments.size() <= 6,
		"the pause rail needs a few quiet terminals, not a decorative HUD system")
	for ornament in ornaments:
		assert_true(ornament.mesh is QuadMesh,
			"%s is more complex than a minimal border terminal" % ornament.name)
		var material := ornament.material_override as StandardMaterial3D
		assert_not_null(material, "%s has no authored ornament material" % ornament.name)
		if material != null:
			assert_true(material.no_depth_test,
				"%s can be covered by scenery; the pause surface never is" % ornament.name)

func test_the_cinematic_push_is_reversible() -> void:
	_menu.open()
	assert_true(_menu.cinematic_factor() > 1.0,
		"opening pause did not open the orthographic frame onto the landscape")
	_menu.close()
	assert_almost_eq(_menu.cinematic_factor(), 1.0, 0.0001,
		"closing pause did not return the camera to its authored framing")

func test_the_cinematic_pullback_becomes_a_rotated_aerial_tableau() -> void:
	var rig := CameraRigStub.new()
	_menu.set_camera_rig(rig)
	_menu.open()
	assert_true(_menu.cinematic_factor() >= 1.8,
		"the pause shot did not reveal a meaningfully larger piece of the valley")
	assert_true(rig.current_lean.x < -0.15,
		"the pause shot did not rise into a stronger observing angle")
	assert_true(rig.current_lean.y > 0.20,
		"the landscape retained the ordinary gameplay axis instead of rotating")
	assert_true(rig.current_offset.x < -2.0 and rig.current_offset.y > 0.8,
		"the player was not settled low-right away from the spatial text field")
	assert_true(rig.current_boom_factor > 1.0,
		"the optical surface remained at the ordinary gameplay distance")
	_menu.close()
	assert_eq(rig.current_lean, Vector3.ZERO,
		"closing pause did not restore the exact authored camera angle")
	assert_eq(rig.current_offset, Vector2.ZERO,
		"closing pause left the camera translated away from the character")
	assert_almost_eq(rig.current_boom_factor, 1.0, 0.0001,
		"closing pause did not restore the authored boom")

func test_the_pause_carries_no_film() -> void:
	# Owner ruling 2026-08-14: the in-world grade film read as murk and was
	# removed. The paused world keeps its own light; the words carry cream and
	# a shadow, and nothing stands between the player and the valley.
	var found_quad := false
	for node in _menu.find_children("*", "MeshInstance3D", true, false):
		if node.name == "FilmQuad":
			found_quad = true
	assert_false(found_quad, "the film quad is back -- it was rejected as 太污浊")

func test_the_world_is_muffled_while_the_camera_is_out() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	var before := AudioServer.get_bus_effect_count(bus)
	(Engine.get_main_loop() as SceneTree).root.add_child(_menu)
	_menu.open()
	assert_eq(AudioServer.get_bus_effect_count(bus), before + 1,
		"opening pause did not muffle the world (low-pass on Master)")
	_menu.free()
	_menu = null
	assert_eq(AudioServer.get_bus_effect_count(bus), before,
		"the muffle outlived the menu")

func test_the_hit_layer_sits_exactly_on_the_spatial_words() -> void:
	# The canvas hit rect and the projected word share one set of numbers; a
	# drift between them is the "hover answers somewhere else" defect.
	_menu.layout_for_viewport(Vector2(1920.0, 1080.0))
	var content: Rect2 = _menu.content_rect()
	var state_y := 144.0
	var pairs: Array = [
		[_menu.continue_button(), &"continue"], [_menu.settings_button(), &"settings"],
		[_menu.exit_button(), &"exit"], [_menu.cancel_button(), &"return"],
		[_menu.confirm_button(), &"confirm"],
	]
	for pair in pairs:
		var button := pair[0] as Button
		var target: Vector2 = ((_menu._spatial._targets[pair[1]] as Vector2)
			- content.position - Vector2(0.0, state_y))
		var rect := Rect2(button.position, button.size)
		assert_true(rect.grow(1.0).has_point(target),
			"%s: the word at %s is outside its hit rect %s" % [pair[1], target, rect])
		assert_almost_eq(rect.get_center().y, target.y, 1.5,
			"%s: hit rect is not centred on the word" % pair[1])
	for i in range(_menu.settings_row_buttons().size()):
		var row: Button = _menu.settings_row_buttons()[i]
		var row_id: StringName = _menu._spatial._row_ids[i]
		var row_target: Vector2 = ((_menu._spatial._targets[row_id] as Vector2)
			- content.position - Vector2(0.0, state_y))
		var row_rect := Rect2(row.position, row.size)
		assert_true(row_rect.grow(1.0).has_point(row_target),
			"%s: settings row word outside its hit rect" % row_id)

func _count_card_panels(node: Node) -> int:
	var count := 1 if node is PanelContainer else 0
	for child in node.get_children():
		count += _count_card_panels(child)
	return count
