class_name RunResultSurfacing
extends CanvasLayer

## The terminal boundary of one attempt.
##
## Death is deliberately not an interaction receipt and not the pause menu. It
## stops the world, reports only the day, then offers one way to begin again.
## Abandonment remains visually empty here; its ending belongs entirely to the
## helicopter and the world fade described by the UI design.

const TOKENS: UITokens = preload("res://data/ui/tokens.tres")

const EVENT_RUN_ENDED := &"game.run_ended"
const EVENT_RUN_RESET := &"game.run_reset"
const EVENT_RUN_STARTED := &"game.run_started"
const EVENT_RESTART_REQUESTED := &"game.restart_requested"

const OUTCOME_DEAD := &"dead"
const OUTCOME_ABANDONED := &"abandoned"

const VEIL_SECONDS := 0.8
const LINE_BLOOM_SECONDS := 0.32
const RESTART_READY_SECONDS := 2.0
const RESULT_LAYER := 85

const DAY_GLYPHS := ["", "一", "二", "三", "四", "五", "六", "七", "八"]

var _bus = null
var _subscribed := false
var _fonts := UIFonts.new()

var _surface: Control = null
var _veil: ColorRect = null
var _copy_column: VBoxContainer = null
var _day_label: Label = null

var _active := false
var _elapsed := 0.0
var _restart_ready := false
var _restart_requested := false
var _restart_committed := false
var _reload_pending := false
var _paused_by_result := false
var _reload_action := Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = RESULT_LAYER
	if _bus == null:
		set_event_bus(get_node_or_null("/root/EventBus"))


func _exit_tree() -> void:
	_unsubscribe()
	_release_pause()


func _process(delta: float) -> void:
	advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not _restart_ready or _restart_requested:
		return
	if event.is_action_pressed("interact"):
		request_restart()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func build() -> void:
	if _surface != null:
		return
	_fonts.build(TOKENS)

	_surface = Control.new()
	_surface.name = "ResultSurface"
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)

	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.color = TOKENS.scrim_veil
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_veil)

	_copy_column = VBoxContainer.new()
	_copy_column.name = "Copy"
	_copy_column.set_anchor(SIDE_LEFT, TOKENS.edge_fraction)
	_copy_column.set_anchor(SIDE_TOP, 0.45)
	_copy_column.set_anchor(SIDE_RIGHT, 0.72)
	_copy_column.set_anchor(SIDE_BOTTOM, 0.45)
	_copy_column.add_theme_constant_override("separation", TOKENS.grid_unit * 2)
	_copy_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_copy_column)

	_day_label = Label.new()
	_day_label.name = "Day"
	_day_label.add_theme_font_override("font", _fonts.display)
	_day_label.add_theme_font_size_override("font_size", 56)
	_day_label.add_theme_color_override("font_color", TOKENS.ink_primary)
	_day_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_copy_column.add_child(_day_label)

	visible = false
	_apply_frame()


func set_event_bus(bus) -> void:
	if bus == _bus:
		_subscribe()
		return
	_unsubscribe()
	_bus = bus
	_subscribe()


func set_reload_action(action: Callable) -> void:
	_reload_action = action


func is_active() -> bool:
	return _active


func is_restart_ready() -> bool:
	return _restart_ready


func is_reload_pending() -> bool:
	return _reload_pending


func day_text() -> String:
	return _day_label.text if _day_label != null else ""


func has_visible_result() -> bool:
	return visible and _active


func advance(delta: float) -> void:
	if not _active or not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta
	_restart_ready = _elapsed >= RESTART_READY_SECONDS
	_apply_frame()


func request_restart() -> bool:
	if not _active or not _restart_ready or _restart_requested or _reload_pending:
		return false
	# The domain restart already succeeded but replacing the old scene failed.
	# Retrying E must retry only that final boundary; emitting another reset
	# would be refused by the now-running GameState and could duplicate listeners.
	if _restart_committed:
		_restart_requested = true
		_reload_pending = true
		if is_inside_tree():
			call_deferred("flush_reload")
		return true
	_restart_requested = true
	_emit(EVENT_RESTART_REQUESTED, {"seed": 0})
	# EventBus dispatch is synchronous. A successful GameState restart has
	# already returned game.run_started and armed the reload by this line.
	if _reload_pending:
		return true
	_restart_requested = false
	return false


## Public deterministic seam used by the smoke test. Production schedules the
## same method deferred so the current EventBus dispatch can unwind before its
## scene is replaced.
func flush_reload() -> bool:
	if not _reload_pending:
		return false
	var succeeded := false
	if _reload_action.is_valid():
		var custom_result: Variant = _reload_action.call()
		succeeded = true if custom_result == null else int(custom_result) == OK
	elif is_inside_tree():
		succeeded = get_tree().reload_current_scene() == OK
	if not succeeded:
		_reload_pending = false
		_restart_requested = false
		# Keep the only recovery surface visible and keep ownership of the pause.
		# The next E retries scene replacement without starting a second run.
		_claim_pause()
		return false
	_reload_pending = false
	_restart_requested = false
	_restart_committed = false
	_active = false
	visible = false
	_release_pause()
	return true


func _on_run_ended(payload) -> void:
	if not (payload is Dictionary):
		return
	var outcome := StringName((payload as Dictionary).get("outcome", &""))
	if outcome == OUTCOME_ABANDONED:
		return
	if outcome != OUTCOME_DEAD or _active:
		return
	build()
	_elapsed = 0.0
	_restart_ready = false
	_restart_requested = false
	_restart_committed = false
	_reload_pending = false
	_day_label.text = _day_copy(int((payload as Dictionary).get("day", 0)))
	_active = true
	visible = true
	_claim_pause()
	_apply_frame()


func _on_run_reset(_payload) -> void:
	# Reset is only the first half of a restart transaction. Keeping the result
	# visible here prevents a failed begin_run() from exposing a dead world.
	pass


func _on_run_started(_payload) -> void:
	if not _active or not _restart_requested or _reload_pending:
		return
	_restart_committed = true
	_reload_pending = true
	if is_inside_tree():
		call_deferred("flush_reload")


func _apply_frame() -> void:
	if _veil == null or _day_label == null:
		return
	_veil.modulate.a = clampf(_elapsed / VEIL_SECONDS, 0.0, 1.0)
	_day_label.modulate.a = clampf(
		(_elapsed - VEIL_SECONDS) / LINE_BLOOM_SECONDS, 0.0, 1.0
	)


func _claim_pause() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree.paused:
		return
	tree.paused = true
	_paused_by_result = true


func _release_pause() -> void:
	if is_inside_tree() and _paused_by_result:
		get_tree().paused = false
	_paused_by_result = false


func _subscribe() -> void:
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_RUN_ENDED, _on_run_ended)
	_bus.subscribe(EVENT_RUN_RESET, _on_run_reset)
	_bus.subscribe(EVENT_RUN_STARTED, _on_run_started)
	_subscribed = true


func _unsubscribe() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_RUN_ENDED, _on_run_ended)
	_bus.unsubscribe(EVENT_RUN_RESET, _on_run_reset)
	_bus.unsubscribe(EVENT_RUN_STARTED, _on_run_started)
	_subscribed = false


func _emit(event_id: StringName, payload: Dictionary) -> void:
	if _bus != null:
		_bus.emit_event(event_id, payload)


static func _day_copy(day: int) -> String:
	var glyph: String = DAY_GLYPHS[day] if day >= 0 and day < DAY_GLYPHS.size() else str(day)
	return "第 %s 日。" % glyph
