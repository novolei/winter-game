extends Control

## A quiet, opt-in instrumentation slate for performance work.  It is not part
## of the player-facing HUD: it begins hidden, costs no monitor queries until it
## is opened, and the normal game interface remains beneath it.
##
## The overlay samples its readout four times per second. Frame durations are
## retained in a fixed ring on every visible frame so a one-frame hitch is not
## averaged away, but that path only writes a float and allocates nothing.

const TOGGLE_ACTION := &"toggle_performance_metrics"
const SAMPLE_INTERVAL_SECONDS := 0.25
const WORST_WINDOW_FRAMES := 240
const SNOW_FIELD_SERVICE := &"snow_field"

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _registry: Object = null
var _frame_history := PackedFloat32Array()
var _frame_cursor := 0
var _frame_count := 0
var _sample_elapsed := 0.0
var _is_open := false
var _panel: PanelContainer = null
var _readout: Label = null


func _init() -> void:
	_frame_history.resize(WORST_WINDOW_FRAMES)
	visible = false
	set_process(false)


## UILayer owns the palette and font chains. The performance overlay only
## consumes those prepared UI resources; it never authors a diagnostic colour.
func attach(tokens: UITokens, fonts: UIFonts) -> void:
	_tokens = tokens
	_fonts = fonts
	if _panel == null:
		_build()
	set_open(false)


## Injection keeps the overlay testable and maintains the project's system
## boundary: SnowField is discovered through ServiceRegistry, never by a scene
## path or a direct system reference.
func set_service_registry(registry: Object) -> void:
	_registry = registry


func is_open() -> bool:
	return _is_open


func set_open(open: bool) -> void:
	_is_open = open
	visible = open
	set_process(open)
	if open:
		_sample_elapsed = SAMPLE_INTERVAL_SECONDS
		_refresh_readout()


func toggle() -> void:
	set_open(not _is_open)


## Public so the binding can be proven without constructing a Viewport. The
## exact-match requirement intentionally leaves Shift+F3 to lighting's deep
## night preview rather than stealing a neighbouring debug control.
func handle_input(event: InputEvent) -> bool:
	if event == null or not event.is_action_pressed(TOGGLE_ACTION, false, true):
		return false
	toggle()
	return true


func _input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	advance(delta)


## Split from _process for a deterministic unit test. While closed this returns
## before touching either monitors or the frame-history ring.
func advance(delta: float) -> void:
	if not _is_open or not is_finite(delta) or delta < 0.0:
		return
	_record_frame_time(delta * 1000.0)
	_sample_elapsed += delta
	if _sample_elapsed < SAMPLE_INTERVAL_SECONDS:
		return
	_sample_elapsed = fmod(_sample_elapsed, SAMPLE_INTERVAL_SECONDS)
	_refresh_readout()


func worst_frame_ms() -> float:
	var worst := 0.0
	for index in range(_frame_count):
		worst = maxf(worst, _frame_history[index])
	return worst


func _record_frame_time(frame_ms: float) -> void:
	_frame_history[_frame_cursor] = maxf(frame_ms, 0.0)
	_frame_cursor = (_frame_cursor + 1) % WORST_WINDOW_FRAMES
	_frame_count = mini(_frame_count + 1, WORST_WINDOW_FRAMES)


func _refresh_readout() -> void:
	if _readout != null:
		_readout.text = format_metrics(_metric_snapshot())


## All Performance monitor values are treated as optional telemetry. The known
## monitor ids are stable in Godot 4.7, but an unsupported renderer can still
## report zero; the formatter renders that as n/a rather than inventing a value.
func _metric_snapshot() -> Dictionary:
	var snow_tiles := 0
	var recenter_ms := 0.0
	var snow = _snow_field()
	if snow != null:
		if snow.has_method("dynamic_tile_count"):
			snow_tiles = int(snow.call("dynamic_tile_count"))
		if snow.has_method("last_recentre_duration_ms"):
			recenter_ms = float(snow.call("last_recentre_duration_ms"))
	return {
		"fps": float(Engine.get_frames_per_second()),
		"frame_ms": _latest_frame_ms(),
		"worst_frame_ms": worst_frame_ms(),
		"process_ms": _monitor_ms(Performance.TIME_PROCESS),
		"physics_ms": _monitor_ms(Performance.TIME_PHYSICS_PROCESS),
		"draw_calls": _monitor_count(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": _monitor_count(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": _monitor_count(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"ram_bytes": _monitor_value(Performance.MEMORY_STATIC),
		"vram_bytes": _monitor_value(Performance.RENDER_VIDEO_MEM_USED),
		"snow_tiles": snow_tiles,
		"recenter_ms": recenter_ms,
	}


func _latest_frame_ms() -> float:
	if _frame_count == 0:
		return 0.0
	return _frame_history[(_frame_cursor - 1 + WORST_WINDOW_FRAMES) % WORST_WINDOW_FRAMES]


func _monitor_ms(monitor: Performance.Monitor) -> float:
	return _monitor_value(monitor) * 1000.0


func _monitor_count(monitor: Performance.Monitor) -> int:
	return maxi(int(roundi(_monitor_value(monitor))), 0)


func _monitor_value(monitor: Performance.Monitor) -> float:
	var raw: Variant = Performance.get_monitor(monitor)
	if not (raw is int or raw is float):
		return 0.0
	var value := float(raw)
	return value if is_finite(value) and value >= 0.0 else 0.0


func _snow_field() -> Object:
	var registry := _registry
	if registry == null and is_inside_tree():
		registry = get_node_or_null("/root/ServiceRegistry")
	if registry == null or not registry.has_method("get_service"):
		return null
	return registry.call("get_service", SNOW_FIELD_SERVICE) as Object


## Pure formatting makes telemetry display testable without relying on a
## renderer-specific Performance monitor. It is intentionally called only at
## the four-Hz sample boundary.
static func format_metrics(metrics: Dictionary) -> String:
	return "PERFORMANCE  [F3]\n" \
		+ "FPS %5.0f   frame %5.1f ms   worst/240f %5.1f ms\n" % [
			_number(metrics, "fps"), _number(metrics, "frame_ms"), _number(metrics, "worst_frame_ms")
		] \
		+ "CPU process %5.1f ms   physics %5.1f ms\n" % [
			_number(metrics, "process_ms"), _number(metrics, "physics_ms")
		] \
		+ "GPU draws %5d   prims %7d   objects %5d\n" % [
			int(_number(metrics, "draw_calls")), int(_number(metrics, "primitives")), int(_number(metrics, "objects"))
		] \
		+ "Memory RAM %s   VRAM %s\n" % [
			_bytes(_number(metrics, "ram_bytes")), _bytes(_number(metrics, "vram_bytes"))
		] \
		+ "Snow tiles %4d   recenter %5.1f ms" % [
			int(_number(metrics, "snow_tiles")), _number(metrics, "recenter_ms")
		]


static func _number(metrics: Dictionary, key: String) -> float:
	var raw: Variant = metrics.get(key, 0.0)
	if raw is int or raw is float:
		var value := float(raw)
		if is_finite(value):
			return maxf(value, 0.0)
	return 0.0


static func _bytes(value: float) -> String:
	if value <= 0.0:
		return "n/a"
	var mib := value / (1024.0 * 1024.0)
	return "%.0f MiB" % mib


func _build() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -276.0
	offset_top = 22.0
	offset_right = -22.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var style := StyleBoxFlat.new()
	if _tokens != null:
		style.bg_color = _tokens.scrim_veil
		style.bg_color.a = _tokens.opacity_steps[1]
		style.border_color = _tokens.line_hairline
		style.border_color.a = _tokens.opacity_steps[3]
	style.set_border_width_all(1)
	style.set_content_margin_all(10.0)
	_panel.add_theme_stylebox_override("panel", style)

	_readout = Label.new()
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.autowrap_mode = TextServer.AUTOWRAP_OFF
	_readout.add_theme_font_size_override("font_size", 12)
	if _tokens != null:
		_readout.add_theme_color_override("font_color", _tokens.ink_primary)
	if _fonts != null and _fonts.instrument != null:
		_readout.add_theme_font_override("font", _fonts.instrument)
	_panel.add_child(_readout)
