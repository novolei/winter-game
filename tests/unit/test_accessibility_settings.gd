extends TestCase

const CatalogScript := preload("res://src/definitions/accessibility_catalog.gd")

var _catalog: AccessibilityCatalog = null

func before_each() -> void:
	_catalog = ResourceLoader.load(CatalogScript.CATALOG_PATH) as AccessibilityCatalog

func test_the_catalog_loads_with_three_entries() -> void:
	assert_not_null(_catalog, "accessibility_settings.tres did not load as a catalog")
	assert_eq(_catalog.entries.size(), 3)

func test_the_three_authored_settings_are_present() -> void:
	for id in [&"prompt_hold", &"stroke_bold", &"screen_shake"]:
		assert_not_null(_catalog.find(id), "catalog is missing %s" % id)

func test_prompt_hold_carries_the_authored_range() -> void:
	var setting := _catalog.find(&"prompt_hold")
	assert_almost_eq(setting.minimum, 0.5)
	assert_almost_eq(setting.maximum, 3.0)
	assert_almost_eq(setting.step, 0.25)
	assert_almost_eq(setting.default_value, 1.0)
	assert_false(setting.is_toggle)
	assert_eq(setting.tick_count(), 11)

func test_the_toggles_carry_the_authored_defaults() -> void:
	assert_almost_eq(_catalog.find(&"stroke_bold").default_value, 0.0, 0.0001,
		"stroke bold defaults off (UI document section 4.2)")
	assert_almost_eq(_catalog.find(&"screen_shake").default_value, 1.0, 0.0001,
		"screen shake defaults on (UI document section 4.2)")
	assert_true(_catalog.find(&"stroke_bold").is_toggle)
	assert_eq(_catalog.find(&"stroke_bold").tick_count(), 2)

func test_values_clamp_step_and_format() -> void:
	var hold := _catalog.find(&"prompt_hold")
	assert_almost_eq(hold.clamp_value(99.0), 3.0)
	assert_almost_eq(hold.stepped(3.0, 1), 3.0, 0.0001, "stepping past the top must clamp, not wrap")
	assert_almost_eq(hold.stepped(1.0, 1), 1.25)
	assert_eq(hold.format_value(1.0), "1×")
	assert_eq(hold.format_value(1.25), "1.25×")
	var toggle := _catalog.find(&"stroke_bold")
	assert_eq(toggle.format_value(0.0), "关")
	assert_eq(toggle.format_value(1.0), "开")
	assert_almost_eq(toggle.stepped(0.0, 1), 1.0)
	assert_almost_eq(toggle.stepped(1.0, -1), 0.0)
