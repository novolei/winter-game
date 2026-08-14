extends TestCase

const BootScreenScript := preload("res://src/ui/boot_screen.gd")

var _screen = null

func before_each() -> void:
	_screen = BootScreenScript.new()
	_screen.build()

func after_each() -> void:
	if _screen != null:
		_screen.free()
		_screen = null

func test_project_enters_the_lightweight_boot_scene_first() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/boot.tscn")

func test_windows_prefers_vulkan_with_a_d3d12_fallback() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/rendering_device/driver.windows"), "vulkan")
	assert_true(ProjectSettings.get_setting("rendering/rendering_device/fallback_to_d3d12"))

func test_release_build_writes_a_diagnostic_log() -> void:
	assert_true(ProjectSettings.get_setting("debug/file_logging/enable_file_logging"))
	assert_eq(ProjectSettings.get_setting("debug/file_logging/log_path"),
		"user://logs/wintertime.log")

func test_pipeline_and_shader_caches_are_enabled() -> void:
	assert_true(ProjectSettings.get_setting("rendering/rendering_device/pipeline_cache/enable"))
	assert_true(ProjectSettings.get_setting("rendering/shader_compiler/shader_cache/enabled"))

func test_shadow_atlases_fit_integrated_graphics() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"), 4096)
	assert_eq(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_size"), 4096)

func test_boot_screen_targets_the_world_without_preloading_it() -> void:
	assert_eq(_screen.target_scene_path, "res://scenes/main.tscn")
	assert_false(ResourceLoader.has_cached(_screen.target_scene_path),
		"constructing the boot UI synchronously loaded the world it exists to defer")

func test_ready_defers_procedural_children_until_the_boot_root_is_attached() -> void:
	var live_screen = BootScreenScript.new()
	Engine.get_main_loop().root.add_child(live_screen)
	assert_eq(live_screen.get_child_count(), 0,
		"_ready() must not mutate the boot root while SceneTree is attaching it")
	live_screen.free()

func test_progress_is_monotonic_and_clamped() -> void:
	_screen.present_progress(0.42)
	assert_almost_eq(_screen.displayed_progress(), 0.42, 0.001)
	_screen.present_progress(0.20)
	assert_almost_eq(_screen.displayed_progress(), 0.42, 0.001, "loading progress moved backwards")
	_screen.present_progress(2.0)
	assert_almost_eq(_screen.displayed_progress(), 1.0, 0.001)

func test_resource_loading_reserves_progress_for_graphics_preparation() -> void:
	assert_almost_eq(BootScreenScript.world_load_progress(0.0), 0.05, 0.001)
	assert_almost_eq(BootScreenScript.world_load_progress(1.0), 0.78, 0.001)

func test_resource_loading_does_not_compete_with_the_splash_ui_for_worker_threads() -> void:
	assert_false(BootScreenScript.resource_subthreads_enabled())

func test_loading_feedback_uses_the_project_font_and_has_a_text_fallback() -> void:
	assert_not_null(_screen.status_label().get_theme_font("font"))
	assert_true(_screen.status_label().text.length() > 0)
	assert_not_null(_screen.progress_bar())

func test_a_failed_load_becomes_a_readable_error_state() -> void:
	_screen.present_failure()
	assert_true(_screen.has_failed())
	assert_true(_screen.status_label().text.contains("无法"))
