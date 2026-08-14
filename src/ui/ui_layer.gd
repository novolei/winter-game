class_name UILayer
extends CanvasLayer

## The layer everything transient lives on, and the thing that takes it away.
## UI design document section 3.
##
## ---------------------------------------------------------------------------
## RULE 4 IS A PROPERTY OF THIS FILE, NOT OF EACH ELEMENT'S AUTHOR
## ---------------------------------------------------------------------------
## "没有东西是常驻的。每个元素诞生时就带着自己的死期." Written as advice, that rule
## survives exactly as long as everybody remembers it. Written here, whoever adds
## an interaction prompt does not GET to forget to remove it -- surface() takes
## the element, drives its envelope, and frees it.
##
## The failure that prevents is not an untidy screen. A Control left behind sits
## over the valley for the rest of the run, in a game whose first pillar is that
## the player must keep looking at the world.
##
## ---------------------------------------------------------------------------
## advance() IS PUBLIC AND CARRIES THE DRIVING
## ---------------------------------------------------------------------------
## _process only forwards, the same shape as WorldClock, SurvivalSystem, Stove
## and MontageDirector -- so a whole element lifetime is playable in a test with
## no frames, including the cold snap, which is otherwise a thing you can only
## check by watching and counting.
##
## ---------------------------------------------------------------------------
## WHAT LIVES HERE AND WHAT DOES NOT
## ---------------------------------------------------------------------------
## The tokens, the font chains and the interface's voice, because every element
## needs all three and none of them should be loaded twice. What does NOT live
## here is any opinion about what the elements SAY: the breath layer's contents
## are section 5's, and they arrive as Controls somebody else built.

const TOKENS_PATH := "res://data/ui/tokens.tres"
const PerformanceOverlayScript := preload("res://src/ui/performance_overlay.gd")
const SettingsStoreScript := preload("res://src/ui/settings_store.gd")

## Below LightingDebugPanel's 100, which must stay on top of everything, and
## above the world.
const LAYER_ORDER := 10

## Registered so the pause menu can push accessibility changes without a
## scene path. Same pattern as CameraRig's "camera_rig" entry.
const SERVICE_KEY := &"ui_layer"

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _audio: UIAudio = null
var _performance_overlay: Control = null
var _time_scale := 1.0
var _preference_scale := 1.0
var _stroke_scale := 1.0

## One entry per element being driven: its control, its envelope, where it was
## put, and how far through it is.
var _live: Array = []

func _ready() -> void:
	if _tokens == null:
		build()
	register_with(get_node_or_null("/root/ServiceRegistry"))


func _exit_tree() -> void:
	# A scene replacement must not leave the registry pointing at a freed
	# CanvasLayer. The real-main survival smoke deliberately boots and tears down
	# the shipped scene in one test, which makes this lifecycle boundary visible.
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.get_service(SERVICE_KEY) == self:
		registry.unregister(SERVICE_KEY)

## Loads the tokens, builds the fonts and the voice. Separate from _ready() so a
## test can have a layer without a SceneTree -- and idempotent, because _ready()
## calls it and a test may have called it first.
func build() -> void:
	layer = LAYER_ORDER
	if _tokens == null:
		_tokens = ResourceLoader.load(TOKENS_PATH) as UITokens
	if _fonts == null:
		_fonts = UIFonts.new()
		_fonts.build(_tokens)
	if _audio == null:
		_audio = UIAudio.new()
		_audio.name = "Voice"
		add_child(_audio)
		_audio.load_map()
	# Debug-only like LightingDebugPanel: a release build never instantiates the
	# instrumentation, while a debug build keeps it asleep until F3 is pressed.
	if _performance_overlay == null and OS.is_debug_build():
		_performance_overlay = PerformanceOverlayScript.new()
		_performance_overlay.name = "PerformanceOverlay"
		add_child(_performance_overlay)
		_performance_overlay.attach(_tokens, _fonts)
	apply_accessibility()

func tokens() -> UITokens:
	return _tokens

func fonts() -> UIFonts:
	return _fonts

func audio() -> UIAudio:
	return _audio


## Kept out of the transient surface() lifecycle: diagnostics are developer
## instrumentation, not a diegetic message that should bloom and drift away.
func performance_overlay() -> Control:
	return _performance_overlay

## Section 2.3's breathing border, in screen pixels, off the short edge.
func edge_pixels(viewport_size: Vector2) -> float:
	return 0.0 if _tokens == null else _tokens.edge_pixels(viewport_size)

# --- driving ----------------------------------------------------------------

## Takes an element, gives it a full breath, and frees it at the end of it.
## `hold` below zero takes the token default.
func surface(control: Control, hold := -1.0, heavy := false, exit := Breath.Exit.NORMAL) -> void:
	_adopt(control, Breath.surface(_tokens, hold, heavy, exit))

## Blooms and then HOLDS, with no death on it. For section 5.5's fire line, which
## stays for as long as the player is standing at the fire -- a duration nobody
## can author up front. Whoever blooms one owns dismissing it.
func bloom(control: Control, heavy := false) -> void:
	var breath := Breath.surface(_tokens, INF, heavy)
	_adopt(control, breath)

## Ends a held element: it drifts out and frees itself. Harmless on something
## this layer never had.
func dismiss(control: Control, exit := Breath.Exit.NORMAL) -> void:
	for entry in _live:
		if entry["control"] != control:
			continue
		var breath: Breath = entry["breath"]
		# Rewritten rather than replaced, so the element carries on from where it
		# is instead of blooming again on its way out.
		breath.hold_seconds = maxf(float(entry["elapsed"]) - breath.bloom_seconds, 0.0)
		match exit:
			Breath.Exit.FAST: breath.exit_seconds = _tokens.drift_fast_seconds
			Breath.Exit.LONG: breath.exit_seconds = _tokens.drift_long_seconds
			_: breath.exit_seconds = _tokens.drift_seconds
		return


## Moves the resting point of an element the layer already drives without
## stealing the Breath's current drift from it. World-projected controls call
## this after every projection: changing `position` alone would last only until
## advance() restored the home captured when the element was adopted.
func rehome(control, home: Vector2) -> bool:
	if control == null or not is_instance_valid(control) or not home.is_finite():
		return false
	for entry in _live:
		var raw: Variant = entry["control"]
		if raw == null or not is_instance_valid(raw) or raw != control:
			continue
		entry["home"] = home
		var breath: Breath = entry["breath"]
		control.position = home + breath.offset_at(float(entry["elapsed"]))
		return true
	return false


## Restarts the readable hold of an existing transient without adopting it a
## second time. Pickup receipts use this when another copy of the same item is
## collected: one Control updates and remains long enough to read, while _live
## still contains exactly one entry for it.
func refresh_hold(control, hold := -1.0) -> bool:
	if control == null or not is_instance_valid(control):
		return false
	for entry in _live:
		var raw: Variant = entry["control"]
		if raw == null or not is_instance_valid(raw) or raw != control:
			continue
		var breath: Breath = entry["breath"]
		breath.hold_seconds = _tokens.hold_seconds if hold < 0.0 else maxf(hold, 0.0)
		# The receipt itself may pulse the changed amount; the whole composition
		# remains settled rather than replaying its entrance.
		entry["elapsed"] = breath.bloom_seconds
		control.modulate.a = breath.opacity_at(breath.bloom_seconds)
		control.scale = Vector2.ONE * breath.scale_at(breath.bloom_seconds)
		control.position = entry["home"] + breath.offset_at(breath.bloom_seconds)
		if control.has_method("set_envelope"):
			control.call("set_envelope", breath, breath.bloom_seconds)
		return true
	return false

## Section 5.6. Applied to elements ALREADY breathing as well as to new ones --
## a cold snap that only reached whatever appeared after the weather turned would
## be a rule about the future rather than about the air.
func set_time_scale(scale: float) -> void:
	if is_finite(scale) and scale > 0.0:
		_time_scale = scale

func time_scale() -> float:
	return _time_scale

## Section 4.2's reading aids, re-read from the store. The prompt-hold
## preference COMPOSES with the weather's time scale in advance(): neither
## overwrites the other.
func apply_accessibility() -> void:
	_preference_scale = clampf(SettingsStoreScript.value(&"prompt_hold", 1.0), 0.5, 3.0)
	_stroke_scale = 2.0 if SettingsStoreScript.value(&"stroke_bold", 0.0) >= 0.5 else 1.0

func preference_scale() -> float:
	return _preference_scale

func stroke_scale() -> float:
	return _stroke_scale

func register_with(registry) -> void:
	if registry != null:
		registry.register(SERVICE_KEY, self)

func live_count() -> int:
	return _live.size()

## The envelope an element is being driven by, or null if this layer does not
## hold it. Published so a caller can assert what is ACTUALLY driving the picture
## rather than rebuilding a Breath that describes it -- which would pass whether
## or not the element had been surfaced the way its author meant.
func breath_for(control: Control) -> Breath:
	for entry in _live:
		if entry["control"] == control:
			return entry["breath"]
	return null

## Takes everything at once, without a drift. For a cut -- an ending, a scene
## change -- where the interface should simply not be there any more.
func clear() -> void:
	for entry in _live:
		_release(entry["control"])
	_live.clear()

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _live.is_empty():
		return
	var step := delta / (_time_scale * _preference_scale)
	var finished: Array = []
	for entry in _live:
		# READ UNTYPED, CHECKED, THEN NARROWED -- briefing trap 18.
		#
		# `bloom()`'s contract is "whoever blooms one owns dismissing it", so an
		# owner is entitled to free its own element. `var control: Control =
		# entry["control"]` is a type-checked assignment from a `Dictionary`
		# value, and GDScript validates the instance AT the assignment: it threw
		# `Trying to assign invalid previously freed instance` and aborted this
		# whole function, so every element BEHIND the freed one stopped breathing
		# too. `Breath` is `RefCounted` and the entry holds it alive, so only the
		# `Control` needs this.
		var raw: Variant = entry["control"]
		if raw == null or not is_instance_valid(raw):
			# Finished, not skipped: an element that no longer exists can never
			# breathe again, and `_live` is walked every frame.
			finished.append(entry)
			continue
		var control: Control = raw
		entry["elapsed"] = float(entry["elapsed"]) + step
		var breath: Breath = entry["breath"]
		var t: float = entry["elapsed"]
		if breath.is_finished(t):
			finished.append(entry)
			continue
		control.modulate.a = breath.opacity_at(t)
		var amount := breath.scale_at(t)
		control.scale = Vector2(amount, amount)
		control.position = entry["home"] + breath.offset_at(t)
		# 散 · 边缘先化开. This layer can only move an element as a WHOLE; the order
		# its parts come apart in is the element's own business, so an element that
		# has parts is handed its envelope and works its own dispersal out. See
		# Breath.dispersal_at(), TimeArc._lead_for() and ThresholdNote's leads.
		#
		# PUSHED, not ticked. An element with a _process() of its own runs at one
		# speed in the running game and another in every harness that drives this
		# layer by hand -- VitalStroke's header spells that out and it is the shape
		# of defect this project keeps paying for. And it is pushed only to elements
		# this layer was HANDED, never to whatever a tree sweep found answering to
		# the name (briefing trap 16).
		if control.has_method("set_envelope"):
			control.call("set_envelope", breath, t)
	for entry in finished:
		_live.erase(entry)
		_release(entry["control"])

func _process(delta: float) -> void:
	advance(delta)

# --- internals --------------------------------------------------------------

func _adopt(control: Control, breath: Breath) -> void:
	if control == null:
		return
	if control.get_parent() != self:
		if control.get_parent() != null:
			control.get_parent().remove_child(control)
		add_child(control)
	# Scaling a Control pivots on its top-left corner unless told otherwise, so
	# without this the bloom grows the element OUT OF its own corner -- it opens
	# and slides at the same time, which reads as a layout bug rather than as a
	# bloom.
	control.pivot_offset = control.size * 0.5
	# Invisible on the frame it is handed over. Otherwise it shows at full
	# strength for one frame and then blooms, which is a flash.
	control.modulate.a = 0.0
	_live.append({
		"control": control,
		"breath": breath,
		"home": control.position,
		"elapsed": 0.0,
	})

## Detached and freed outright rather than queue_free()'d. The same reason
## MontageDirector does: a deferred free never arrives for a layer advanced by a
## test or a screenshot harness, and live_count() has to be true on the frame the
## element ended rather than at the end of one.
##
## THE PARAMETER IS UNTYPED ON PURPOSE, and it is the same shape
## `ThresholdSurfacing._release()` already uses. Typed, the instance is validated
## AT THE CALL -- `_release(entry["control"])` threw on a control its owner had
## already freed, and the `is_instance_valid()` guard on the line below could
## never run. Briefing trap 18.
func _release(control) -> void:
	if control == null or not is_instance_valid(control):
		return
	if control.get_parent() == self:
		remove_child(control)
	control.free()
