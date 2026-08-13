extends TestCase

## The pause menu's settings state -- UI design document section 4.2's three
## accessibility rows, living inside the ExitMenu as a third navigation state
## between menu and confirm. Values write through to the SettingsStore and
## clamp at the catalog's boundaries instead of wrapping.

const ExitMenuScript := preload("res://src/ui/exit_menu.gd")
const StoreScript := preload("res://src/ui/settings_store.gd")

const TEST_PATH := "user://test_ui_settings_menu.cfg"

var _menu = null

func before_each() -> void:
	StoreScript.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	StoreScript.load_from(TEST_PATH)
	_menu = ExitMenuScript.new()
	_menu.set_quit_action(func() -> void: pass)
	_menu.build()

func after_each() -> void:
	if _menu != null:
		_menu.free()
		_menu = null
	StoreScript.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

func test_the_menu_offers_settings_between_continue_and_exit() -> void:
	_menu.toggle()
	assert_not_null(_menu.settings_button())
	assert_eq(_menu.settings_button().text, "设　置")
	assert_eq(_menu.state(), &"menu")

func test_opening_settings_swaps_the_state_without_closing() -> void:
	_menu.toggle()
	_menu.open_settings()
	assert_true(_menu.is_open())
	assert_eq(_menu.state(), &"settings")
	assert_true(_menu.is_adjusting())
	assert_false(_menu.is_confirming())

func test_escape_from_settings_returns_to_the_menu() -> void:
	_menu.toggle()
	_menu.open_settings()
	_menu.handle_cancel()
	assert_eq(_menu.state(), &"menu")
	_menu.handle_cancel()
	assert_false(_menu.is_open(), "escape from the menu still closes the pause")

func test_the_rows_come_from_the_catalog() -> void:
	_menu.toggle()
	_menu.open_settings()
	var rows: Array = _menu.settings_row_buttons()
	assert_eq(rows.size(), 3)
	assert_true((rows[0] as Button).text.begins_with("提示停留时长"))

func test_adjusting_writes_through_and_clamps() -> void:
	_menu.toggle()
	_menu.open_settings()
	# 焦点默认在第一行（prompt_hold，默认 1.0）
	assert_true(_menu.adjust_focused(1))
	assert_almost_eq(StoreScript.value(&"prompt_hold", 1.0), 1.25)
	for i in range(20):
		_menu.adjust_focused(1)
	assert_almost_eq(StoreScript.value(&"prompt_hold", 1.0), 3.0)
	assert_false(_menu.adjust_focused(1), "at the ceiling a step must refuse, not wrap")

func test_row_text_reflects_the_stored_value() -> void:
	_menu.toggle()
	_menu.open_settings()
	_menu.adjust_focused(1)
	var rows: Array = _menu.settings_row_buttons()
	assert_true((rows[0] as Button).text.contains("1.25×"))
