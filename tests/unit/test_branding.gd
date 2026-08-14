extends TestCase

const SPLASH_PATH := "res://assets/branding/boot_splash.png"
const ICON_PATH := "res://assets/branding/app_icon.png"
const WINDOW_MODE_SETTING := "display/window/size/mode"

func test_project_uses_the_wintertime_branding() -> void:
	assert_eq(ProjectSettings.get_setting("application/boot_splash/image"), SPLASH_PATH)
	assert_eq(ProjectSettings.get_setting("application/config/icon"), ICON_PATH)

func test_debug_builds_run_windowed_but_release_builds_start_fullscreen() -> void:
	assert_eq(ProjectSettings.get_setting(WINDOW_MODE_SETTING), Window.MODE_WINDOWED)
	assert_eq(
		ProjectSettings.get_setting(WINDOW_MODE_SETTING + ".release"), Window.MODE_FULLSCREEN,
		"the release feature stopped overriding the windowed development default"
	)
	assert_false(
		ProjectSettings.has_setting(WINDOW_MODE_SETTING + ".standalone"),
		"a standalone override would force exported Debug clients fullscreen too"
	)
	assert_true(OS.has_feature("debug"), "the test harness stopped representing a Debug build")
	assert_eq(
		ProjectSettings.get_setting_with_override(WINDOW_MODE_SETTING), Window.MODE_WINDOWED,
		"the Debug feature did not resolve to the windowed base setting"
	)

func test_boot_splash_is_a_full_hd_landscape_image() -> void:
	var texture := ResourceLoader.load(SPLASH_PATH) as Texture2D
	assert_not_null(texture, "boot splash could not be loaded")
	if texture != null:
		assert_eq(texture.get_size(), Vector2(1920, 1080))

func test_app_icon_has_a_square_high_resolution_source() -> void:
	var texture := ResourceLoader.load(ICON_PATH) as Texture2D
	assert_not_null(texture, "application icon could not be loaded")
	if texture != null:
		assert_eq(texture.get_size(), Vector2(1024, 1024))
