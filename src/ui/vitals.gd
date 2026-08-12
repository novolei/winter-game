class_name Vitals
extends Control

## The five survival readings, permanently, in the left breathing margin, made
## of ice.
##
## ---------------------------------------------------------------------------
## THIS IS THE ELEMENT RULE 4 WAS AMENDED FOR
## ---------------------------------------------------------------------------
## The UI design document's rule 4 read 没有东西是常驻的 and its forbidden column
## named 常驻状态条 outright. The owner overruled it and the Director narrowed the
## exemption to exactly this (`9dd5ba8`): 除五条生存读数外，没有东西是常驻的.
## Minimaps, quest trackers, durability and crosshairs are still forbidden, and
## section 0's test still governs everything else -- 这个元素消失之后，玩家是否仍然
## 必须看世界？
##
## So this file is the whole of the exemption. If a second permanent element ever
## wants to exist, it does not belong here and it does not inherit this ruling.
##
## ---------------------------------------------------------------------------
## PERMANENT IS NOT THE SAME AS LOUD, AND RULE 2 STILL BINDS
## ---------------------------------------------------------------------------
## 中心 85% 永远是世界. These live hard against the left breathing border, they
## are about a twentieth of the frame wide, and they carry no text and no icons
## while nothing is wrong. What makes them legible is not size, it is that they
## are the only vertical straight-ish things in a valley made of drifts.
##
## Being permanent buys the player one thing only: the reading is AVAILABLE. How
## a crossing announces itself is section 5.2's job, and it still happens --
## ThresholdSurfacing puts words next to this stack at the moment a threshold
## breaks, which is also how the player learns which stroke is which. The stack
## is the reference; the note names it. Neither works nearly as well alone.
##
## ---------------------------------------------------------------------------
## IT ASKS THE MODEL, AND IT LISTENS. BOTH, AND FOR DIFFERENT THINGS
## ---------------------------------------------------------------------------
## The fill is POLLED, because there is no per-frame value event and a level has
## to be continuous. The crossing is SUBSCRIBED, because a crossing is a moment
## and comparing this frame's value with last frame's to rediscover a moment the
## model already announced is how two systems come to disagree about what a
## threshold is.
##
## And the values are read once in _ready() as well as on every event. A node
## that only ever hears transitions can never learn a state that changed before
## it existed -- this project has paid for that twice -- and here the fix is
## structural rather than a patch: the state is derived from the value, so a
## reading is correct on its first frame whatever happened before it.

const VitalStrokeScript := preload("res://src/ui/vital_stroke.gd")

const LAYOUT_PATH := "res://data/ui/vital_layout.tres"
const COPY_PATH := "res://data/ui/threshold_copy.tres"

const EVENT_THRESHOLD_CROSSED := &"survival.threshold_crossed"
const EVENT_STAT_DEPLETED := &"survival.stat_depleted"
const EVENT_STAT_RECOVERED := &"survival.stat_recovered"

## Section 8's 元素 呵: 极轻的吸气 / 霜裂, 20 ms, -28 dB. Not cut yet, deliberately
## not stubbed. Named so it works the day it lands.
const CUE_BORN := &"ui.breath"

## EVERY DIMENSION IN THIS CLUSTER COMES FROM Engraved'S PROPORTIONAL SYSTEM.
##
## 绝对精美且高度风格一致性. Five gauges each tuned until it looked right are five
## things that happen to resemble one another today. So the radii, the gap, the
## stroke weights and the ring's opening all derive from three numbers -- the 8 px
## grid section 2.3 already sets, one ratio of 2, and one angle of 60 degrees --
## and this file takes them from there rather than declaring its own.
##
## Named here so that the layout reads without opening the look, and so that a
## replacement look inherits the same proportions instead of inventing new ones.
const LARGE_RADIUS_DESIGN_PX := Engraved.LARGE_RADIUS
const SMALL_RADIUS_DESIGN_PX := Engraved.SMALL_RADIUS
const CLUSTER_GAP_DESIGN_PX := Engraved.GAP

## How large a glyph stands in a gauge, as a fraction of that gauge's radius.
const GLYPH_RATIO := 0.62

## How long the rest of the cluster stays quiet after one reading surges, and how
## far down it goes. The span matches section 5.2's hold, so the dimming and the
## words that explain it end together.
const FOCUS_SECONDS := 2.4
const FOCUS_DIM := 0.45

var _tokens: UITokens = null
var _layout: VitalLayout = null
var _copy: ThresholdCopyMap = null
var _bus = null
var _model = null
var _strokes: Array[VitalStroke] = []
var _viewport := Vector2(1920.0, 1080.0)

## ---------------------------------------------------------------------------
## WHY THIS ELEMENT IS A CHILD OF UILayer AND IS NOT HANDED TO IT
## ---------------------------------------------------------------------------
## UILayer's whole contract is that it takes an element, drives its envelope and
## FREES IT -- rule 4 made a property of the system rather than of each author.
## This is the one element rule 4 was amended for, so handing it over would be
## asking the layer to break its own promise, and bloom()'s infinite hold is a
## workaround rather than a fit.
##
## Two concrete failures came with the workaround, both silent. The layer records
## an element's home position at adopt time and writes it back every frame, so a
## window resize would move the stack in relayout() and the layer would put it
## straight back where it used to be. And a child's _ready() runs BEFORE its
## parent's, so bloom() would be called while UILayer had not loaded its tokens
## yet -- Breath.surface(null, ...) returns the DEFAULT hold rather than the
## infinite one, and the permanent readout would quietly die after three seconds.
##
## So it lives on the layer, to be composited with everything else, and drives
## its own 呵. Section 1.2 still binds: nothing appears instantly.
var _focus: StringName = &""
var _focus_left := 0.0

var _birth: Breath = null
var _birth_elapsed := 0.0
var _voiced := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build()
	# Asked, not waited for. See the header.
	read_model()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(relayout):
		viewport.size_changed.connect(relayout)


## Loads the tokens and the layout and builds one stroke per reading. Separate
## from _ready() and idempotent, so a test can have a stack with no SceneTree.
func build() -> void:
	if _tokens == null:
		_tokens = _tokens_from_layer()
	if _layout == null and ResourceLoader.exists(LAYOUT_PATH):
		_layout = ResourceLoader.load(LAYOUT_PATH) as VitalLayout
	if _copy == null and ResourceLoader.exists(COPY_PATH):
		_copy = ResourceLoader.load(COPY_PATH) as ThresholdCopyMap
	if _bus == null and is_inside_tree():
		# get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry
		# is a node under /root and never enters the engine's singleton registry
		# (briefing trap 3). Written the plausible way, every event would be
		# swallowed for ever with no diagnostic.
		set_event_bus(get_node_or_null("/root/EventBus"))
	if _model == null and is_inside_tree():
		set_model(get_node_or_null("/root/SurvivalSystem"))
	if _strokes.is_empty():
		_build_strokes()
	if _birth == null:
		# Bloom, then hold with no death on it. INF is what makes it permanent,
		# and it is the ONLY thing about this element that differs from a
		# transient one -- so if rule 4 is ever narrowed again, this constant is
		# where the change is made.
		_birth = Breath.surface(_tokens, INF, false)
		modulate.a = 0.0
	relayout()
	# ASKED HERE, not only in _ready(). A caller that builds a stack outside a
	# SceneTree -- a test, a screenshot harness, a scene assembled in code --
	# otherwise gets six readings showing a well man over a body that is already
	# freezing, and nothing would announce the discrepancy because no event is
	# ever sent for a state that has not changed.
	read_model()


func set_event_bus(bus) -> void:
	if _bus == bus:
		return
	_unsubscribe()
	_bus = bus
	_subscribe()


func set_model(model) -> void:
	_model = model


func set_tokens(tokens: UITokens) -> void:
	_tokens = tokens


func stroke_count() -> int:
	return _strokes.size()


func stroke_for(stat: StringName) -> VitalStroke:
	for stroke in _strokes:
		if stroke.stat() == stat:
			return stroke
	return null


func layout() -> VitalLayout:
	return _layout


# --- the reading -------------------------------------------------------------

## Pulls every reading out of the model. Called on ready, and every frame for
## the level. Harmless with no model: the strokes keep what they had, which is
## their authored full, so a scene with no run going shows a well man rather
## than a dead one.
func read_model() -> void:
	if _model == null:
		return
	for stroke in _strokes:
		var id := stroke.stat()
		if id == &"" or not _model.has_stat(id):
			continue
		stroke.set_reading(
			_model.fraction_of(id),
			_model.is_depleted(id),
			_model.net_rate_of(id) > 0.0
		)


func advance(delta: float) -> void:
	read_model()
	# Section 5.6: the cold snap slows the whole interface, and the ice with it.
	# Read off the layer every frame rather than at build time, because the
	# weather turns after the readout exists.
	var scale := 1.0
	var parent := get_parent()
	if parent != null and parent.has_method("time_scale"):
		scale = maxf(float(parent.call("time_scale")), 0.0001)
	# THE OTHER READINGS DIM WHILE ONE SURGES. The eye should be taken to the one
	# that matters, and with colour spent on rule 3 the only way to do that is to
	# make everything else quieter. Decays over the same span a section 5.2 note
	# lives for, so the cluster is level again by the time the words have gone.
	if _focus_left > 0.0:
		_focus_left = maxf(_focus_left - delta, 0.0)
	var focused := _focus_left > 0.0
	for stroke in _strokes:
		stroke.set_time_scale(scale)
		stroke.set_attenuation(
			1.0 if not focused or stroke.stat() == _focus else FOCUS_DIM)
		stroke.advance(delta)
	_breathe_in(delta / scale)


## The 呵, driven here rather than by the layer. See the note on _birth.
func _breathe_in(step: float) -> void:
	if _birth == null or not is_finite(step) or step <= 0.0:
		return
	_birth_elapsed += step
	modulate.a = _birth.opacity_at(_birth_elapsed)
	var amount := _birth.scale_at(_birth_elapsed)
	scale = Vector2(amount, amount)
	if _voiced:
		return
	_voiced = true
	# Rule 6: 每一次呵气都有一个声音，视觉与音频同帧诞生. Section 8's own 呵 asset has
	# not been cut -- tools/generate_ui_sounds.gd refuses to stub it, on the
	# grounds that a wrong sound in the right place is harder to notice than
	# silence -- so this asks for a cue that does not exist yet and UIAudio
	# quietly answers false. The day a row lands in data/audio/ui_sounds.tres
	# this element gains its voice with no code change.
	if parent_audio() != null:
		parent_audio().play(CUE_BORN)


func parent_audio():
	var parent := get_parent()
	if parent != null and parent.has_method("audio"):
		return parent.call("audio")
	return null


func _process(delta: float) -> void:
	advance(delta)


## For a screenshot harness: photograph readings that have finished
## crystallising rather than ones caught part-grown.
func finish_growth() -> void:
	for stroke in _strokes:
		stroke.finish_growth()
	if _birth != null:
		# Past the overshoot and settled, so a capture is of the readout rather
		# than of it arriving.
		_birth_elapsed = maxf(_birth_elapsed, _birth.delay + _birth.bloom_seconds)
		modulate.a = _birth.opacity_at(_birth_elapsed)
		scale = Vector2.ONE


# --- the crossing ------------------------------------------------------------

## EventBus calls back with exactly one argument, always, even when the payload
## is null -- a callback taking zero or two is a runtime error at dispatch, not
## a parse error.
func _on_threshold_crossed(payload) -> void:
	if not (payload is Dictionary):
		return
	# `active` false is the stat coming back UP through a threshold. That is
	# good news, and thickening the ice on good news would make the material
	# mean two opposite things.
	if not bool((payload as Dictionary).get("active", false)):
		return
	_surge((payload as Dictionary).get("stat", &""))


func _on_stat_depleted(payload) -> void:
	if payload is Dictionary:
		_surge((payload as Dictionary).get("stat", &""))


func _on_stat_recovered(payload) -> void:
	# Nothing to thicken. A reserve leaving its floor is announced by the warm
	# mark at the head of it, which set_reading() turns on from the net rate --
	## the one legal warm use in the breath layer (section 5.2).
	if payload is Dictionary:
		read_model()


func _surge(stat) -> void:
	var stroke := stroke_for(StringName(stat))
	if stroke == null:
		return
	stroke.surge()
	_focus = stroke.stat()
	_focus_left = FOCUS_SECONDS


# --- layout ------------------------------------------------------------------

## Anchored to the LEFT EDGE and sized off the canvas, never off a fixed
## viewport. The project stretches `canvas_items` / `expand`, which reveals extra
## screen area rather than letterboxing it, so a layout pinned to 1920x1080
## would drift off the edge of every other window (briefing constraint, system
## map section 8).
func relayout() -> void:
	if _tokens == null:
		return
	_viewport = _canvas_size()
	var edge := _tokens.edge_pixels(_viewport)
	var large := _tokens.design_px(LARGE_RADIUS_DESIGN_PX, _viewport)
	var small := _tokens.design_px(SMALL_RADIUS_DESIGN_PX, _viewport)
	var gap := _tokens.design_px(CLUSTER_GAP_DESIGN_PX, _viewport)

	# ANCHORED TO THE CORNER, not offset from a remembered size. Under
	# `canvas_items` / `expand` the canvas changes shape with the window and
	# extra screen area is revealed rather than letterboxed, so a cluster placed
	# by fixed coordinates walks off the edge of every aspect but the one it was
	# authored at. Everything below is measured from (edge, edge).
	position = Vector2(edge, edge)

	var centres: Array[Vector2] = []
	var radii: Array[float] = []
	var cursor := 0.0
	for stroke in _strokes:
		var radius := large if _is_heat(stroke) else small
		centres.append(Vector2(cursor + radius, large))
		radii.append(radius)
		cursor += radius * 2.0 + gap
	size = Vector2(maxf(cursor - gap, 1.0), large * 2.0)
	# Scaling a Control pivots on its top-left corner unless told otherwise, so
	# without this the cluster's own bloom would grow it out of the screen corner
	# instead of opening it where it stands.
	pivot_offset = size * 0.5

	for index in range(_strokes.size()):
		var stroke := _strokes[index]
		var radius: float = radii[index]
		var element := radius + _tokens.design_px(VitalStroke.PAD_DESIGN_PX, _viewport)
		# Every gauge's centre is on the large one's centre line, so the row
		# reads as one instrument rather than as a chart.
		stroke.place_ring(
			centres[index] - Vector2(element, element),
			radius,
			_viewport,
			_markers_for(stroke.stat())
		)
	queue_redraw()


## Where the model's own thresholds sit around a gauge, 0..1, up to four.
##
## Read out of the copy table, which tests/unit/test_ui_threshold_copy.gd holds
## against data/stats/*.tres in both directions -- so a marker can only ever
## stand where the body really does change, and retuning a threshold moves the
## mark with no code change. A marker invented in GDScript would be a second
## opinion about the model, and it would be wrong within a week.
func _markers_for(stat: StringName) -> Vector4:
	var out := Vector4(-1.0, -1.0, -1.0, -1.0)
	if _copy == null:
		return out
	var thresholds := _copy.thresholds_for(stat)
	for index in range(mini(thresholds.size(), 4)):
		out[index] = clampf(thresholds[index], 0.0, 1.0)
	return out


func _is_heat(stroke: VitalStroke) -> bool:
	return _layout != null and stroke.stat() == _layout.frost_source


# --- the glyphs ---------------------------------------------------------------

## Drawn HERE rather than on the gauge, because a CanvasItem carries one material
## and the gauge's is the frost shader. A glyph pushed through it would be ice
## rather than a pictograph.
##
## VECTOR STROKES, never a bitmap. All four things this design asks of a glyph
## are things a raster cannot do: take its colour from the palette at runtime,
## stay sharp at three framing stops and any window size, carry emphasis in
## stroke weight -- which is the only channel rule 3 leaves once warmth is spoken
## for -- and belong to a material that grows rather than being pasted on.
func _draw() -> void:
	if _tokens == null or _layout == null:
		return
	for stroke in _strokes:
		var row := _layout.row_for(stroke.stat())
		if row == null:
			continue
		var centre := stroke.position + stroke.centre()
		var reach: float = (stroke.size.x * 0.5
			- _tokens.design_px(VitalStroke.PAD_DESIGN_PX, _viewport)) * GLYPH_RATIO
		var colour := VitalTone.colour_for(_tokens, stroke.state(), _is_heat(stroke))
		var weight := _tokens.design_px(
			VitalTone.fill_design_px(stroke.state()) * 0.6, _viewport)
		_draw_glyph(row.glyph, centre, maxf(reach, 2.0), colour, maxf(weight, 1.0))


func _draw_glyph(
	kind: StringName, centre: Vector2, reach: float, colour: Color, weight: float
) -> void:
	match kind:
		&"heat":
			# A six-armed radiant: warmth, and a snowflake's own symmetry. The
			# one glyph that is allowed to be drawn warm, because it is the one
			# reading that IS heat.
			for step in range(6):
				var angle := float(step) * PI / 3.0
				var arm := Vector2(cos(angle), sin(angle))
				draw_line(centre + arm * reach * 0.32, centre + arm * reach, colour, weight, true)
			draw_arc(centre, reach * 0.30, 0.0, TAU, 18, colour, weight, true)
		&"hunger":
			# A bowl: a half-circle under a short rim.
			draw_arc(centre + Vector2(0.0, -reach * 0.20), reach * 0.78,
				0.0, PI, 20, colour, weight, true)
			draw_line(
				centre + Vector2(-reach * 0.9, -reach * 0.20),
				centre + Vector2(reach * 0.9, -reach * 0.20), colour, weight, true)
		&"thirst":
			# A drop: two straight flanks meeting at a point over a round belly.
			draw_arc(centre + Vector2(0.0, reach * 0.18), reach * 0.62,
				0.0, PI, 18, colour, weight, true)
			draw_line(centre + Vector2(0.0, -reach),
				centre + Vector2(-reach * 0.62, reach * 0.18), colour, weight, true)
			draw_line(centre + Vector2(0.0, -reach),
				centre + Vector2(reach * 0.62, reach * 0.18), colour, weight, true)
		&"fatigue":
			# A bolt.
			draw_polyline(PackedVector2Array([
				centre + Vector2(reach * 0.45, -reach),
				centre + Vector2(-reach * 0.35, reach * 0.05),
				centre + Vector2(reach * 0.20, reach * 0.05),
				centre + Vector2(-reach * 0.45, reach),
			]), colour, weight, true)
		&"unresolved":
			# AN OBVIOUS GAP, NOT A PLAUSIBLE GUESS.
			#
			# Frostbite has no settled pictograph -- there is no drawing everyone
			# reads as "this limb is freezing" -- and inventing something
			# plausible is much harder to notice and correct later than a hole.
			# A broken ring reads as unfinished at any size, which is the whole
			# requirement. Named in the report for the owner to settle.
			var dashes := 7
			for step in range(dashes):
				var from_a := TAU * float(step) / float(dashes)
				draw_arc(centre, reach * 0.66, from_a, from_a + TAU / float(dashes) * 0.5,
					6, colour, weight, true)
		&"crystal_up", &"crystal_down":
			# A branching crystal, pointing away from the body's middle for the
			# hands and toward it for the feet. AN HONEST PLACEHOLDER: frostbite
			# has no settled pictograph, and this says the material and the place
			# without claiming to say the injury. Flagged rather than guessed.
			var way := -1.0 if kind == &"crystal_up" else 1.0
			var tip := centre + Vector2(0.0, way * reach)
			draw_line(centre + Vector2(0.0, -way * reach * 0.4), tip, colour, weight, true)
			for side in [-1.0, 1.0]:
				draw_line(centre + Vector2(0.0, way * reach * 0.15),
					centre + Vector2(side * reach * 0.62, way * reach * 0.72),
					colour, weight, true)
		_:
			draw_arc(centre, reach * 0.7, 0.0, TAU, 6, colour, weight, true)


# --- internals ---------------------------------------------------------------

## The canvas the Controls live in, not the window. Under `canvas_items` stretch
## these are different numbers (briefing trap 10) and a Control is positioned in
## the first one.
## How wide the corner cluster is, without needing one to exist.
##
## Published so that anything else living in the same corner can keep clear of
## it without looking this node up by name through the scene tree -- a layout
## that breaks when somebody renames a node is worse than one constant computed
## twice from the same data.
static func cluster_size(
	tokens: UITokens, layout: VitalLayout, viewport_size: Vector2
) -> Vector2:
	if tokens == null:
		return Vector2.ZERO
	var large := tokens.design_px(LARGE_RADIUS_DESIGN_PX, viewport_size)
	var small := tokens.design_px(SMALL_RADIUS_DESIGN_PX, viewport_size)
	var gap := tokens.design_px(CLUSTER_GAP_DESIGN_PX, viewport_size)
	var rows := [] if layout == null else layout.ordered()
	var width := 0.0
	for row in rows:
		width += (large if row.stat == layout.frost_source else small) * 2.0 + gap
	return Vector2(maxf(width - gap, 0.0), large * 2.0)


func _canvas_size() -> Vector2:
	if is_inside_tree():
		var viewport := get_viewport()
		if viewport != null:
			return viewport.get_visible_rect().size
	return _viewport


func _tokens_from_layer() -> UITokens:
	var parent := get_parent()
	if parent != null and parent.has_method("tokens"):
		var carried = parent.call("tokens")
		if carried is UITokens:
			return carried
	if ResourceLoader.exists(UILayer.TOKENS_PATH):
		return ResourceLoader.load(UILayer.TOKENS_PATH) as UITokens
	return null


func _build_strokes() -> void:
	if _layout == null:
		return
	var index := 0
	for row in _layout.ordered():
		var stroke: VitalStroke = VitalStrokeScript.new()
		stroke.name = "Stroke_%s" % row.stat
		# Deterministic, never randf(): two readings must not crystallise
		# identically, and a captured frame has to be the same frame tomorrow.
		if not stroke.build(_tokens, row, float(index) * 3.7 + 1.3):
			# The shader is not there. Nothing is drawn rather than the run being
			# taken down -- and the stroke is still freed, because a Control is a
			# Node and an orphan is a leak at exit (briefing constraint 2).
			stroke.free()
			index += 1
			continue
		stroke.set_is_heat(row.stat == _layout.frost_source)
		add_child(stroke)
		_strokes.append(stroke)
		index += 1


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


## PREDELETE as well as EXIT_TREE: a stack built outside a SceneTree never
## receives the second one, and a subscription left behind on a freed object is
## a callback the bus goes on holding. See ThresholdSurfacing's note, where the
## same mistake was measured as a real leak.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		_unsubscribe()
