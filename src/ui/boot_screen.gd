class_name BootScreen
extends Control

const TOKENS_PATH := "res://data/ui/tokens.tres"
const SPLASH_PATH := "res://assets/branding/boot_splash.png"
const WORLD_LOAD_MIN := 0.05
const WORLD_LOAD_MAX := 0.78
const GRAPHICS_PREPARE_START := 0.84
const GRAPHICS_PREPARE_END := 0.98
const MINIMUM_PREPARE_FRAMES := 3
const STABLE_PIPELINE_FRAMES := 10
const MAXIMUM_PREPARE_SECONDS := 12.0

@export_file("*.tscn") var target_scene_path := "res://scenes/main.tscn"

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _status: Label = null
var _progress: ProgressBar = null
var _displayed_progress := 0.0
var _request_started := false
var _failed := false
var _preparing_graphics := false
var _world: Node = null
var _prepare_started_ms := 0
var _prepare_frames := 0
var _stable_pipeline_frames := 0
var _last_pipeline_count := -1

func _ready() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	print("Boot: renderer=%s; graphics=%s" % [
		RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(),
	])
	# SceneTree is still attaching the boot root while _ready() runs. Deferring
	# the procedural children avoids mutating a parent whose child list is busy,
	# and lets Windows receive a responsive arrow-cursor frame before world I/O.
	call_deferred("_present_then_begin_loading")

func _present_then_begin_loading() -> void:
	if not is_inside_tree():
		return
	build()
	_begin_loading_after_first_frame()

func build() -> void:
	if _progress != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tokens = ResourceLoader.load(TOKENS_PATH) as UITokens
	_fonts = UIFonts.new()
	_fonts.build(_tokens)

	var backdrop := TextureRect.new()
	backdrop.name = "Backdrop"
	backdrop.texture = ResourceLoader.load(SPLASH_PATH) as Texture2D
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var footer := MarginContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -132.0
	footer.offset_bottom = -48.0
	footer.add_theme_constant_override("margin_left", 96)
	footer.add_theme_constant_override("margin_right", 96)
	add_child(footer)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	footer.add_child(column)

	_status = Label.new()
	_status.text = "正在踏入长夜……"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_override("font", _fonts.interface)
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", _tokens.ink_primary)
	column.add_child(_status)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 4.0
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.value = 0.0
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = _tokens.line_deep
	track.set_corner_radius_all(2)
	_progress.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = _tokens.ink_secondary
	fill.set_corner_radius_all(2)
	_progress.add_theme_stylebox_override("fill", fill)
	column.add_child(_progress)

func _begin_loading_after_first_frame() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not ResourceLoader.exists(target_scene_path):
		present_failure()
		return
	_status.text = "正在铺开雪原……"
	var error := ResourceLoader.load_threaded_request(
		target_scene_path,
		"PackedScene",
		resource_subthreads_enabled()
	)
	if error != OK:
		present_failure()
		return
	_request_started = true
	set_process(true)

func _process(_delta: float) -> void:
	if _failed:
		return
	if _preparing_graphics:
		_poll_graphics_preparation()
		return
	if not _request_started:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(target_scene_path, progress)
	if not progress.is_empty():
		present_progress(world_load_progress(float(progress[0])))
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_request_started = false
			present_progress(WORLD_LOAD_MAX)
			var packed := ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
			if packed == null:
				present_failure()
				return
			_status.text = "正在准备图形资源……"
			present_progress(GRAPHICS_PREPARE_START)
			_prepare_world_after_feedback_frame(packed)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			present_failure()

func _prepare_world_after_feedback_frame(packed: PackedScene) -> void:
	# Draw the phase change before PackedScene.instantiate() and the world's
	# _ready() methods do their synchronous setup work.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_world = packed.instantiate()
	if _world == null:
		present_failure()
		return
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	var tree := get_tree()
	var root := tree.root
	var boot_index := get_index()
	root.add_child(_world)
	root.move_child(_world, boot_index)
	tree.current_scene = _world
	_preparing_graphics = true
	_prepare_started_ms = Time.get_ticks_msec()
	_prepare_frames = 0
	_stable_pipeline_frames = 0
	_last_pipeline_count = pipeline_compilation_count()
	print("Boot: world ready; preparing graphics pipelines from count=%d" % _last_pipeline_count)

func _poll_graphics_preparation() -> void:
	_prepare_frames += 1
	var pipeline_count := pipeline_compilation_count()
	if pipeline_count == _last_pipeline_count:
		_stable_pipeline_frames += 1
	else:
		_last_pipeline_count = pipeline_count
		_stable_pipeline_frames = 0
	var elapsed_seconds := float(Time.get_ticks_msec() - _prepare_started_ms) / 1000.0
	var timed_progress := clampf(elapsed_seconds / MAXIMUM_PREPARE_SECONDS, 0.0, 1.0)
	present_progress(lerpf(GRAPHICS_PREPARE_START, GRAPHICS_PREPARE_END, timed_progress))
	var is_stable := (
		_prepare_frames >= MINIMUM_PREPARE_FRAMES
		and _stable_pipeline_frames >= STABLE_PIPELINE_FRAMES
	)
	if is_stable or elapsed_seconds >= MAXIMUM_PREPARE_SECONDS:
		_finish_graphics_preparation(elapsed_seconds, pipeline_count)

func _finish_graphics_preparation(elapsed_seconds: float, pipeline_count: int) -> void:
	_preparing_graphics = false
	present_progress(1.0)
	print("Boot: graphics ready in %.2fs; pipeline compilations=%d" % [
		elapsed_seconds,
		pipeline_count,
	])
	if _world != null:
		_world.process_mode = Node.PROCESS_MODE_INHERIT
	queue_free()

static func world_load_progress(value: float) -> float:
	return lerpf(WORLD_LOAD_MIN, WORLD_LOAD_MAX, clampf(value, 0.0, 1.0))

static func resource_subthreads_enabled() -> bool:
	# Threaded I/O still runs off the main thread. Avoiding loader subthreads
	# prevents a large PackedScene from starving the splash and Windows messages.
	return false

static func pipeline_compilation_count() -> int:
	return (
		RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS
		)
		+ RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH
		)
		+ RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE
		)
		+ RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW
		)
	)

func present_progress(value: float) -> void:
	if _progress == null:
		build()
	_displayed_progress = maxf(_displayed_progress, clampf(value, 0.0, 1.0))
	_progress.value = _displayed_progress

func present_failure() -> void:
	if _status == null:
		build()
	_failed = true
	_request_started = false
	_preparing_graphics = false
	_status.text = "无法进入雪原，请重新启动游戏。"
	_status.add_theme_color_override("font_color", _tokens.life_warm)

func displayed_progress() -> float:
	return _displayed_progress

func has_failed() -> bool:
	return _failed

func status_label() -> Label:
	return _status

func progress_bar() -> ProgressBar:
	return _progress
