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

## Below LightingDebugPanel's 100, which must stay on top of everything, and
## above the world.
const LAYER_ORDER := 10

var _tokens: UITokens = null
var _fonts: UIFonts = null
var _audio: UIAudio = null
var _time_scale := 1.0

## One entry per element being driven: its control, its envelope, where it was
## put, and how far through it is.
var _live: Array = []

func _ready() -> void:
	if _tokens == null:
		build()

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

func tokens() -> UITokens:
	return _tokens

func fonts() -> UIFonts:
	return _fonts

func audio() -> UIAudio:
	return _audio

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

## Section 5.6. Applied to elements ALREADY breathing as well as to new ones --
## a cold snap that only reached whatever appeared after the weather turned would
## be a rule about the future rather than about the air.
func set_time_scale(scale: float) -> void:
	if is_finite(scale) and scale > 0.0:
		_time_scale = scale

func time_scale() -> float:
	return _time_scale

func live_count() -> int:
	return _live.size()

## Takes everything at once, without a drift. For a cut -- an ending, a scene
## change -- where the interface should simply not be there any more.
func clear() -> void:
	for entry in _live:
		_release(entry["control"])
	_live.clear()

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _live.is_empty():
		return
	var step := delta / _time_scale
	var finished: Array = []
	for entry in _live:
		entry["elapsed"] = float(entry["elapsed"]) + step
		var breath: Breath = entry["breath"]
		var control: Control = entry["control"]
		var t: float = entry["elapsed"]
		if breath.is_finished(t):
			finished.append(entry)
			continue
		control.modulate.a = breath.opacity_at(t)
		var amount := breath.scale_at(t)
		control.scale = Vector2(amount, amount)
		control.position = entry["home"] + breath.offset_at(t)
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
func _release(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	if control.get_parent() == self:
		remove_child(control)
	control.free()
