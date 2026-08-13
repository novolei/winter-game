extends TestCase

## The settings page's spatial copy -- the visible Label3D glyphs and the
## depth-composited track/marker/tick quads that mirror the accessibility rows
## on the pause surface. Rows are built from the AccessibilityCatalog, so a new
## .tres entry grows the spatial page without a script change.

const SpatialScript := preload("res://src/ui/spatial_pause_menu.gd")
const Tokens: UITokens = preload("res://data/ui/tokens.tres")

var _spatial: SpatialPauseMenu = null

func before_each() -> void:
	var fonts := UIFonts.new()
	fonts.build(Tokens)
	_spatial = SpatialScript.new()
	_spatial.setup(Tokens, fonts)

func after_each() -> void:
	if _spatial != null:
		_spatial.free()
		_spatial = null

func test_the_menu_gains_a_settings_choice() -> void:
	var found := false
	for label in _spatial.labels():
		if label.text == "设　置":
			found = true
	assert_true(found, "the spatial menu has no settings choice")

func test_settings_rows_are_built_from_the_catalog() -> void:
	var ids := _spatial.row_label_ids()
	assert_eq(ids.size(), 3)
	assert_true(ids.has(&"row_prompt_hold"))

func test_rows_hide_outside_the_settings_state() -> void:
	_spatial.set_state(&"settings")
	var visibility := {}
	for label in _spatial.labels():
		visibility[label.name] = label.visible
	for label in _spatial.labels():
		if String(label.name).begins_with("Row"):
			assert_true(visibility[label.name],
				"%s was hidden in the settings state" % label.name)
	_spatial.set_state(&"menu")
	for label in _spatial.labels():
		if String(label.name).begins_with("Row"):
			assert_false(label.visible, "%s stayed visible in the menu state" % label.name)

func test_set_row_value_updates_the_word_and_slides_the_marker() -> void:
	_spatial.layout(Rect2(24.0, 100.0, 384.0, 420.0), 1.0, false, 144.0)
	var value_id := &"row_prompt_hold_value"
	var marker_before := (_spatial._track_layouts[value_id] as Rect2).position.x
	_spatial.set_row_value(&"prompt_hold", "3×", 1.0)
	for label in _spatial.labels():
		if label.name == "RowPromptHoldValue":
			assert_eq(label.text, "3×", "the value word did not update")
	var marker_after := (_spatial._track_layouts[value_id] as Rect2).position.x
	assert_true(marker_after > marker_before,
		"the marker rect did not slide when the fraction changed")

func test_the_settings_state_has_a_heading() -> void:
	var heading := _heading_label()
	assert_not_null(heading, "the spatial settings page has no heading")
	assert_eq(heading.text, "设　置", "the settings heading carries the wrong word")
	_spatial.set_state(&"menu")
	assert_false(heading.visible, "the settings heading stayed visible in the menu state")
	_spatial.set_state(&"settings")
	assert_true(heading.visible, "the settings heading was hidden in the settings state")

func test_tracks_and_ticks_are_depth_composited_quads() -> void:
	var quads := _spatial.track_quads()
	# 3 轨道 + 3 游标 + 11 + 2 + 2 刻度
	assert_eq(quads.size(), 21)
	for quad in quads:
		assert_true(quad.mesh is QuadMesh)
		var material := quad.material_override as StandardMaterial3D
		assert_not_null(material)
		assert_false(material.no_depth_test)

func _heading_label() -> Label3D:
	for label in _spatial.labels():
		if label.name == "SettingsHeading":
			return label
	return null
