extends TestCase

const ExitMenuScript := preload("res://src/ui/exit_menu.gd")

var _menu = null

func before_each() -> void:
	_menu = ExitMenuScript.new()
	_menu.set_quit_action(func() -> void: pass)
	_menu.build()

func after_each() -> void:
	if _menu != null:
		_menu.free()
		_menu = null

func test_the_status_line_anchors_the_hierarchy() -> void:
	_menu.layout_for_viewport(Vector2(1920.0, 1080.0))
	var status := _menu.get_node("ExitMenuRoot/BreathRail/NightContext/DayAndPhase") as Label
	var status_size := status.get_theme_font_size("font_size")
	# 42 设计像素 × 1080 短边缩放（frame_scale 上限 1.25 不计入 tokens.scale_for 的 1.0 基准）
	assert_true(status_size >= 40,
		"the day line must anchor the composition, got %d" % status_size)

func test_the_caption_steps_down_from_the_status() -> void:
	_menu.layout_for_viewport(Vector2(1920.0, 1080.0))
	var status := _menu.get_node("ExitMenuRoot/BreathRail/NightContext/DayAndPhase") as Label
	var caption := _menu.get_node("ExitMenuRoot/BreathRail/NightContext/Remaining/Caption") as Label
	assert_true(caption.get_theme_font_size("font_size") <=
		int(roundf(status.get_theme_font_size("font_size") * 0.45)),
		"the caption must clearly subordinate to the day line")
