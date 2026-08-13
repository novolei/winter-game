extends TestCase

const StoreScript := preload("res://src/ui/settings_store.gd")

const TEST_PATH := "user://test_ui_settings.cfg"

func before_each() -> void:
	StoreScript.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

func after_each() -> void:
	StoreScript.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

func test_missing_file_yields_defaults() -> void:
	assert_eq(StoreScript.load_from(TEST_PATH), 0)
	assert_almost_eq(StoreScript.value(&"prompt_hold", 1.0), 1.0)

func test_store_then_value_round_trips() -> void:
	StoreScript.load_from(TEST_PATH)
	StoreScript.store(&"prompt_hold", 2.5)
	assert_almost_eq(StoreScript.value(&"prompt_hold", 1.0), 2.5)

func test_values_survive_a_fresh_load() -> void:
	StoreScript.load_from(TEST_PATH)
	StoreScript.store(&"stroke_bold", 1.0)
	StoreScript.reset()
	assert_eq(StoreScript.load_from(TEST_PATH), 1)
	assert_almost_eq(StoreScript.value(&"stroke_bold", 0.0), 1.0)

func test_a_corrupt_file_falls_back_to_defaults_without_noise() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{{{{ not a config file")
	file.close()
	assert_eq(StoreScript.load_from(TEST_PATH), 0)
	assert_almost_eq(StoreScript.value(&"screen_shake", 1.0), 1.0)

func test_unknown_ids_return_the_callers_fallback() -> void:
	StoreScript.load_from(TEST_PATH)
	assert_almost_eq(StoreScript.value(&"no_such_setting", 0.75), 0.75)
