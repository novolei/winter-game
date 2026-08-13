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
	_spatial.set_state(&"menu")
	for label in _spatial.labels():
		if String(label.name).begins_with("Row"):
			assert_false(label.visible, "%s stayed visible in the menu state" % label.name)

func test_tracks_and_ticks_are_depth_composited_quads() -> void:
	var quads := _spatial.track_quads()
	# 3 轨道 + 3 游标 + 11 + 2 + 2 刻度
	assert_eq(quads.size(), 21)
	for quad in quads:
		assert_true(quad.mesh is QuadMesh)
		var material := quad.material_override as StandardMaterial3D
		assert_not_null(material)
		assert_false(material.no_depth_test)
