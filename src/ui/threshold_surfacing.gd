class_name ThresholdSurfacing
extends Node

## UI design document section 5.2. Turns `survival.threshold_crossed`,
## `survival.stat_depleted` and `survival.stat_recovered` into words in the left
## breathing border, and then lets them die.
##
## ---------------------------------------------------------------------------
## EMERGENCE AND PERMANENCE ARE NOT ALTERNATIVES
## ---------------------------------------------------------------------------
## The margin stack (Vitals) makes a reading AVAILABLE. This makes a crossing
## ANNOUNCE ITSELF. A player who is not looking at the margin -- which is most of
## the time, because the third pillar wants his eyes in the valley -- learns
## nothing from a level that quietly moved. He learns everything from 手指不听使唤了
## appearing beside the reading that just thickened.
##
## It is also the only place the strokes are ever named. The stack carries no
## labels; the note carries the icon and the words. So the interface teaches its
## own vocabulary at exactly the moment the vocabulary matters, and never at any
## other time.
##
## ---------------------------------------------------------------------------
## THE UI DECIDES NOTHING
## ---------------------------------------------------------------------------
## Section 5.2: payload 已经携带 {stat, threshold, comparison, active, value,
## targets}——UI 不需要自己判断任何东西. This file does not compare a value with a
## threshold, does not keep last frame's reading, and does not know what any
## threshold is. It looks the words up and puts them on screen.
##
## That matters because the model sub-steps at 0.25 s to avoid missing a crossing
## inside one long frame (survival_system.gd). A readout that rediscovered
## crossings by comparison would miss exactly the ones the model went to that
## trouble to catch.
##
## ---------------------------------------------------------------------------
## A NOTE WITH NO WORDS IS A DELIBERATE STATE
## ---------------------------------------------------------------------------
## Section 5.2's 恢复 row specifies the arc collapsing in reverse and a life/warm
## mark walking back from the end, and specifies NO copy. So a recovery surfaces
## the icon and the ice and says nothing, which is right: the reserve coming back
## is not news the player has to act on, and printing the worsening line at the
## moment it stopped being true would be worse than silence.

const ThresholdNoteScript := preload("res://src/ui/threshold_note.gd")

const COPY_PATH := "res://data/ui/threshold_copy.tres"
const LAYOUT_PATH := "res://data/ui/vital_layout.tres"

const EVENT_THRESHOLD_CROSSED := &"survival.threshold_crossed"
const EVENT_STAT_DEPLETED := &"survival.stat_depleted"
const EVENT_STAT_RECOVERED := &"survival.stat_recovered"

## Section 8's 阈值恶化: 一次心跳的低频, 45 Hz, -18 dB. The asset has not been cut
## -- tools/generate_ui_sounds.gd says so and deliberately refuses to stub it,
## because a wrong sound in the right place is harder to notice than silence.
## Named and called anyway, so the day a row for it lands in
## data/audio/ui_sounds.tres this element gains its voice with no code change.
## UIAudio.play() returns false for a cue that is not there, quietly.
const CUE_WORSENED := &"ui.threshold"

## Section 5.2's timing: 呵 200 / 持 2400 / 散 900. The bloom and the drift are
## the token defaults; only the hold is this section's own.
const HOLD_SECONDS := 2.4

## Section 5.2: 多条同时 -- 纵向堆叠，间距 8px，第 N 条延迟 160×N ms（错峰是 juice，
## 也是可读性）. Four lines arriving on one frame is a wall; four arriving a sixth
## of a second apart is a body reporting in.
const STAGGER_SECONDS := 0.16
const STACK_GAP_DESIGN_PX := 8.0

## Section 5.2: 左侧呼吸边界内，垂直 38% 高度.
const TOP_FRACTION := 0.38

var _layer = null
var _bus = null
var _model = null
var _copy: ThresholdCopyMap = null
var _layout: VitalLayout = null

## Notes waiting out their stagger: [{note, delay}].
var _pending: Array = []

## Notes handed to the layer. It owns them now and will free them; this list is
## purged of the dead on every advance, which is also how the stack knows where
## the next note goes.
var _live: Array = []


func _ready() -> void:
	build()


## Resolves everything and subscribes. Separate from _ready() and idempotent so a
## test can drive this with no SceneTree.
func build() -> void:
	if _layer == null:
		var parent := get_parent()
		if parent != null and parent.has_method("surface"):
			_layer = parent
	if _copy == null and ResourceLoader.exists(COPY_PATH):
		_copy = ResourceLoader.load(COPY_PATH) as ThresholdCopyMap
	if _layout == null and ResourceLoader.exists(LAYOUT_PATH):
		_layout = ResourceLoader.load(LAYOUT_PATH) as VitalLayout
	if is_inside_tree():
		# get_node_or_null, NOT Engine.get_singleton -- a project [autoload] is a
		# node under /root and never enters the singleton registry (trap 3).
		if _bus == null:
			set_event_bus(get_node_or_null("/root/EventBus"))
		if _model == null:
			_model = get_node_or_null("/root/SurvivalSystem")


func set_layer(layer) -> void:
	_layer = layer


func set_model(model) -> void:
	_model = model


func set_event_bus(bus) -> void:
	if _bus == bus:
		return
	_unsubscribe()
	_bus = bus
	_subscribe()


func pending_count() -> int:
	return _pending.size()


func live_count() -> int:
	_purge()
	return _live.size()


# --- the events --------------------------------------------------------------

## EventBus always calls back with exactly one argument, even when the payload is
## null; a callback taking zero or two is a runtime error at dispatch time rather
## than a parse error.
func _on_threshold_crossed(payload) -> void:
	if not (payload is Dictionary):
		return
	var data: Dictionary = payload
	var stat := StringName(data.get("stat", &""))
	var threshold := float(data.get("threshold", 0.0))
	if bool(data.get("active", false)):
		_queue(stat, _copy_for(stat, threshold), false)
		_voice()
	else:
		# Back up through a threshold. Wordless -- see the header.
		_queue(stat, "", false)


func _on_stat_depleted(payload) -> void:
	if not (payload is Dictionary):
		return
	var stat := StringName((payload as Dictionary).get("stat", &""))
	# The floor is not one of the authored thresholds -- they all sit strictly
	# above it -- so it borrows the most severe row the designer wrote for this
	# stat, which is already true at zero.
	var row: ThresholdCopy = null
	if _copy != null:
		row = _copy.lowest_row_for(stat)
	_queue(stat, "" if row == null else row.text, true)
	_voice()


func _on_stat_recovered(payload) -> void:
	if payload is Dictionary:
		_queue(StringName((payload as Dictionary).get("stat", &"")), "", false)


# --- driving -----------------------------------------------------------------

## Public and carrying the driving, the same shape as WorldClock, SurvivalSystem,
## UILayer and MontageDirector -- so a whole stagger is playable in a test with
## no frames.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_purge()
	# The notes are driven from here rather than from a _process() of their own,
	# so a harness that steps this object also steps the ice on every note it is
	# holding -- and so a note cannot run at one speed in the game and another in
	# a capture.
	for note in _live:
		note.advance(delta)
	if _pending.is_empty():
		return
	var ready_now: Array = []
	for entry in _pending:
		entry["delay"] = float(entry["delay"]) - delta
		if float(entry["delay"]) <= 0.0:
			ready_now.append(entry)
	for entry in ready_now:
		_pending.erase(entry)
		_release(entry["note"])


func _process(delta: float) -> void:
	advance(delta)


# --- internals ---------------------------------------------------------------

func _copy_for(stat: StringName, threshold: float) -> String:
	return "" if _copy == null else _copy.text_for(stat, threshold)


## Builds the note now -- so it holds the reading as it was AT THE CROSSING --
## and holds it back for its share of the stagger.
func _queue(stat: StringName, text: String, depleted: bool) -> void:
	if _layer == null or _layout == null or stat == &"":
		return
	var row := _layout.row_for(stat)
	if row == null:
		# A stat with no layout row cannot be drawn and, more to the point,
		# cannot be identified by the player. Silence beats an unlabelled mark.
		return
	var fraction := 1.0
	var recovering := false
	if _model != null and _model.has_stat(stat):
		fraction = _model.fraction_of(stat)
		recovering = _model.net_rate_of(stat) > 0.0
		depleted = depleted or _model.is_depleted(stat)

	var note: ThresholdNote = ThresholdNoteScript.new()
	note.name = "Note_%s" % stat
	if not note.build(_tokens(), _fonts(), row, text, fraction, depleted, recovering):
		# No shader, no note. Freed rather than dropped: a Control is a Node and
		# an orphan is a leak at exit (briefing constraint 2).
		note.free()
		return
	_purge()
	var index := _live.size() + _pending.size()
	_pending.append({"note": note, "delay": STAGGER_SECONDS * float(index)})


## Places the note in the stack and hands it to the layer, which owns its death
## from here.
func _release(note) -> void:
	if note == null or not is_instance_valid(note):
		return
	if _layer == null:
		note.free()
		return
	var tokens := _tokens()
	var viewport := _canvas_size()
	var note_size: Vector2 = note.layout_for(viewport)
	var gap := 0.0 if tokens == null else tokens.design_px(STACK_GAP_DESIGN_PX, viewport)
	# 左侧呼吸边界内, but CLEAR OF THE PERMANENT READINGS, which stand in the same
	# margin, and the notes are indented past them wherever they are.
	#
	# This was real. The first capture with both systems live had six lines of
	# copy laid straight across the six readings they were naming -- worse than
	# either alone, because the words obscured the thing they exist to identify.
	# The gauges have since moved to the top corner and the notes hang below
	# them, so the clash is gone; the clearance is still computed rather than
	# assumed, because the next person to move either one will not remember.
	var edge := 0.0
	var below := 0.0
	if tokens != null:
		edge = tokens.edge_pixels(viewport)
		var cluster := Vitals.cluster_size(tokens, _layout, viewport)
		below = edge + cluster.y + gap

	_purge()
	var y := maxf(viewport.y * TOP_FRACTION, below)
	for live in _live:
		y += live.size.y + gap
	note.position = Vector2(edge, y)
	_live.append(note)
	# hold = 2400 ms. The bloom and the drift come from the tokens, so section
	# 5.6's cold snap reaches this element like every other one.
	_layer.surface(note, HOLD_SECONDS)
	if _layer.has_method("time_scale"):
		note.set_time_scale(_layer.time_scale())


## Rule 6: every 呵 has a sound. See CUE_WORSENED -- the asset is not cut yet and
## is deliberately not stubbed.
func _voice() -> void:
	if _layer == null or not _layer.has_method("audio"):
		return
	var audio = _layer.call("audio")
	if audio != null:
		audio.play(CUE_WORSENED)


## The layer frees a note when its breath is over, so every reference here has to
## be checked before it is touched.
func _purge() -> void:
	var alive: Array = []
	for note in _live:
		if note != null and is_instance_valid(note):
			alive.append(note)
	_live = alive


func _tokens() -> UITokens:
	if _layer != null and _layer.has_method("tokens"):
		return _layer.call("tokens")
	return null


func _fonts() -> UIFonts:
	if _layer != null and _layer.has_method("fonts"):
		return _layer.call("fonts")
	return null


## The canvas Controls are positioned in, which under `canvas_items` stretch is
## not the window size (briefing trap 10).
func _canvas_size() -> Vector2:
	if is_inside_tree():
		var viewport := get_viewport()
		if viewport != null:
			return viewport.get_visible_rect().size
	return Vector2(1920.0, 1080.0)


func _subscribe() -> void:
	if _bus == null:
		return
	_bus.subscribe(EVENT_THRESHOLD_CROSSED, _on_threshold_crossed)
	_bus.subscribe(EVENT_STAT_DEPLETED, _on_stat_depleted)
	_bus.subscribe(EVENT_STAT_RECOVERED, _on_stat_recovered)


func _unsubscribe() -> void:
	if _bus == null:
		return
	_bus.unsubscribe(EVENT_THRESHOLD_CROSSED, _on_threshold_crossed)
	_bus.unsubscribe(EVENT_STAT_DEPLETED, _on_stat_depleted)
	_bus.unsubscribe(EVENT_STAT_RECOVERED, _on_stat_recovered)


## NOT `_exit_tree()`, and the difference is a leak.
##
## `_exit_tree()` is only delivered to a node that was IN a tree. A surfacing
## built by a test, or by a harness that drives it directly, never enters one --
## so freeing it would never run this, and every note still waiting out its
## stagger would survive as an orphan. Measured: "49 ObjectDB instances were
## leaked at exit", plus the CanvasItem, material, shader, texture and font RIDs
## hanging off them, which is a failed run by this project's standard whatever
## the test tally says.
##
## PREDELETE is delivered whenever the object goes, in a tree or out of one.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE and what != NOTIFICATION_EXIT_TREE:
		return
	_unsubscribe()
	# Anything still waiting out its stagger has never been handed to the layer,
	# so nothing else will ever free it.
	for entry in _pending:
		var note = entry["note"]
		if note != null and is_instance_valid(note):
			note.free()
	_pending.clear()
