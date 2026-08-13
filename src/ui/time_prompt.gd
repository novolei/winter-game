class_name TimePrompt
extends Node

## UI design document section 5.10. Every four hours of world time the valley
## says what time it is, for four seconds, and then it does not.
##
## ---------------------------------------------------------------------------
## THIS IS WHAT REPLACED THE DAY DIAL, AND THE DIFFERENCE IS RULE 4
## ---------------------------------------------------------------------------
## The deleted corner cluster carried the clock as its largest gauge, on screen
## at every moment of the run. Rule 4 had to be amended to allow it and the owner
## has taken that amendment back, so 没有东西是常驻的，每个元素诞生时就带着自己的死期
## stands as written.
##
## The information did not have to go with the element. GDD section 3 makes
## `NIGHTFALL = GO HOME` a literal deadline and the player has to be able to plan
## against it -- so the clock still speaks, six times a day, and then leaves.
##
## Section 0's test, which is the only one that matters: 这个元素消失之后，玩家是否
## 仍然必须看世界？ Yes, and more than before -- between prompts the light, the
## snow and the sky are the only clock there is.
##
## ---------------------------------------------------------------------------
## AN HOUR IS A TWENTY-FOURTH OF THE DAY THE SCHEDULE AUTHORED
## ---------------------------------------------------------------------------
## Not a constant. `data/schedule/day_0N.tres` gives every day a daylight and a
## night budget -- 600/300 on day one, 240/660 on day seven -- and the prompt
## divides whichever day is being played. Retune a day's pacing and the prompt
## keeps step with it; write the period as 150 seconds and it silently does not,
## which is the failure this project has already recorded twice (a cooldown
## against a clip's length, a warm quota against a frame's real contents).
##
## tests/unit/test_time_prompt.gd asserts the RELATIONSHIP rather than the
## number, against the schedule's own seconds.
##
## ---------------------------------------------------------------------------
## IT ASKS THE CLOCK, AND IT LISTENS
## ---------------------------------------------------------------------------
## Both, and neither is redundant. It SUBSCRIBES so the phase is right on the
## frame it changes -- a prompt can surface on the very frame the sun goes down.
## It ASKS on build and again at every surfacing, because a node that only ever
## hears transitions can never learn the state it was born into, and
## `clock.night_started` has long since fired by the time a scene reloads after
## dark. That has now been found three times on this project.

const TimeArcScript := preload("res://src/ui/time_arc.gd")

const DATA_PATH := "res://data/ui/time_prompt.tres"

const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"

## Section 8's 元素 呵: 极轻的吸气 / 霜裂, 20 ms, -28 dB. Not cut yet and
## deliberately not stubbed -- tools/generate_ui_sounds.gd refuses, on the
## grounds that a wrong sound in the right place is harder to notice than
## silence. UIAudio.play() answers false quietly, so the day a row lands this
## element gains its voice with no code change.
const CUE_BORN := &"ui.breath"

var _layer = null
var _bus = null
var _clock = null
var _data: TimePromptData = null

## World seconds since the last prompt. The only state this object keeps, and it
## is a stopwatch rather than a copy of anything the clock owns.
var _elapsed := 0.0
var _surfaced := 0
var _live: TimeArc = null

var _night := false
var _day := 1

## LightingDirector, resolved lazily through ServiceRegistry. The prompt stands on
## the snow and has to be legible against it -- see TimeArc's header for the
## measurement that made this necessary, and for why it is a choice between two
## palette entries rather than a colour worked out at runtime.
var _lighting = null


func _ready() -> void:
	build()


## Resolves everything and subscribes. Separate from _ready() and idempotent so a
## test can drive this with no SceneTree.
func build() -> void:
	if _layer == null:
		var parent := get_parent()
		if parent != null and parent.has_method("surface"):
			_layer = parent
	if _data == null and ResourceLoader.exists(DATA_PATH):
		_data = ResourceLoader.load(DATA_PATH) as TimePromptData
	if is_inside_tree():
		# get_node_or_null, NOT Engine.get_singleton -- a project [autoload] is a
		# node under /root and never enters the singleton registry (trap 3).
		if _bus == null:
			set_event_bus(get_node_or_null("/root/EventBus"))
		if _clock == null:
			set_clock(get_node_or_null("/root/WorldClock"))
	_read_clock()


func set_layer(layer) -> void:
	_layer = layer


func set_clock(clock) -> void:
	_clock = clock
	_read_clock()


func set_event_bus(bus) -> void:
	if _bus == bus:
		return
	_unsubscribe()
	_bus = bus
	_subscribe()


func data() -> TimePromptData:
	return _data


func is_night() -> bool:
	return _night


func day() -> int:
	return _day


func surfaced_count() -> int:
	return _surfaced


## The element on screen, or null. The layer owns it and frees it, so this is
## checked before it is touched.
func live() -> TimeArc:
	_purge()
	return _live


## The envelope this element is surfaced with, straight off the layer -- so a
## test reads what is actually driving the picture rather than a description of
## it. Null when nothing is on screen.
func breath() -> Breath:
	if _layer == null or live() == null or not _layer.has_method("breath_for"):
		return null
	return _layer.breath_for(_live)


# --- the cadence --------------------------------------------------------------

## How long one hour of world time lasts, in seconds: a twenty-fourth of the day
## being played. Zero outside a run, which is what stops the prompt existing
## there.
func hour_seconds() -> float:
	if _clock == null or _data == null or _data.hours_per_day <= 0.0:
		return 0.0
	if not _clock.has_method("current_schedule"):
		return 0.0
	var schedule = _clock.current_schedule()
	if schedule == null:
		return 0.0
	var whole_day: float = float(schedule.daylight_seconds) + float(schedule.night_seconds)
	return whole_day / _data.hours_per_day


func seconds_between() -> float:
	return 0.0 if _data == null else hour_seconds() * _data.hours_between


## How far through the current phase the world is, 0 at its start and 1 at its
## end. Asked of the clock rather than integrated here: the clock crosses phase
## boundaries inside a single long frame and a parallel count would drift off it.
func phase_progress() -> float:
	if _clock == null or not _clock.has_method("phase_duration"):
		return 0.0
	var duration: float = _clock.phase_duration()
	if duration <= 0.0:
		return 0.0
	return clampf(float(_clock.phase_elapsed()) / duration, 0.0, 1.0)


# --- driving ------------------------------------------------------------------

## Public and carrying the driving, the same shape as WorldClock, SurvivalSystem,
## UILayer and ThresholdSurfacing -- so a whole day of prompts is playable in a
## test with no frames.
func advance(delta: float) -> void:
	_purge()
	if not is_finite(delta) or delta <= 0.0:
		return
	if _clock == null or not _clock.has_method("is_running") or not _clock.is_running():
		return
	var period := seconds_between()
	if period <= 0.0:
		return
	_elapsed += delta
	if _elapsed < period:
		return
	# ONE PROMPT PER FRAME, whatever the frame was worth. A long frame or a
	# fast-forward can cover several periods, and surfacing four arcs on top of
	# each other would be a stutter rather than four announcements.
	_elapsed = fposmod(_elapsed, period)
	_surface()


func _process(delta: float) -> void:
	advance(delta)


## Puts one on screen now. Public because a screenshot harness must be able to
## photograph it without waiting four hours of world time for it.
func surface_now() -> TimeArc:
	return _surface()


func _surface() -> TimeArc:
	if _layer == null or _data == null:
		return null
	# ASKED AGAIN HERE, not only on the events. A clock with no bus -- a harness,
	# a test, a scene assembled in code -- would otherwise announce the phase it
	# was built in for the rest of the run.
	_read_clock()
	var arc: TimeArc = TimeArcScript.new()
	arc.name = "TimePrompt"
	if not arc.build(_tokens(), _fonts(), _data):
		# No tokens, no prompt. Freed rather than dropped: a Control is a Node and
		# an orphan is a leak at exit (briefing constraint 2).
		arc.free()
		return null
	arc.set_phase(_night, _day, phase_progress())
	arc.set_ground(ground_value())
	arc.layout_for(_canvas_size())
	_live = arc
	_surfaced += 1
	# 呵·重, which section 2.4 gives to 昼夜更替 -- this is the clock talking, and
	# it is the curve whose control point sits at 1.2.
	#
	# THE 弹性 IS IN THE MOTION, NOT IN THE OPACITY, and that is a measurement
	# rather than a preference. An elastic curve on a CLAMPED value arrives early,
	# holds at the clamp and then pulses back, which reads as a fault; measured on
	# this project, the heavy bloom returned 1.0044 on an alpha. So the overshoot
	# lands on SCALE -- .94 to 1.02 and settle -- and on the exit's 8 px upward
	# drift, while the opacity only ever climbs. See Breath.opacity_at().
	#
	# AND 散·长 ON THE WAY OUT, for exactly the reason the bloom is heavy. Section
	# 2.4 gives 昼夜更替 both halves -- 呵·重 320 and 散·长 1600 -- and this element
	# is the same voice on a shorter cycle; section 5.4's 日出 is written with that
	# pair. It also earns its length: with the hold doubled to eight seconds, an
	# exit that took a ninth of the dwell would read as the clock being cut off
	# rather than as the clock finishing. The dispersal (TimeArc, 边缘先化开) is
	# what fills those 1.6 seconds with something happening.
	_layer.surface(arc, _data.hold_seconds, true, Breath.Exit.LONG)
	_voice()
	return arc


## Rule 6: 每一次呵气都有一个声音，视觉与音频同帧诞生. See CUE_BORN.
func _voice() -> void:
	if _layer == null or not _layer.has_method("audio"):
		return
	var audio = _layer.call("audio")
	if audio != null:
		audio.play(CUE_BORN)


## How bright the snow behind the prompt is, 0..1.
##
## The LIGHTING, not the clock. They mostly agree and sometimes do not, and the
## exception is not hypothetical: day 6 is authored `nightfall -> whiteout`, so its
## DAY is the darker of its two phases and its NIGHT is the brighter. A prompt that
## picked its ink from the phase would be wrong on exactly the day GDD section 4
## calls the emotional peak.
##
## active_preset() returns the BLEND while a crossfade runs, so the prompt
## inherits the director's own eight-second fade with nothing to engineer.
func ground_value() -> float:
	if _lighting == null and is_inside_tree():
		var registry := get_node_or_null("/root/ServiceRegistry")
		if registry != null:
			_lighting = registry.get_service(&"lighting")
	if _lighting == null or not _lighting.has_method("active_preset"):
		return 0.5
	return TimeArc.ground_for(_lighting.call("active_preset"))


# --- the clock ----------------------------------------------------------------

func _read_clock() -> void:
	if _clock == null:
		return
	if _clock.has_method("is_night"):
		_night = bool(_clock.is_night())
	if _clock.has_method("current_day"):
		_day = int(_clock.current_day())


func _on_day_started(payload) -> void:
	_night = false
	if payload is int:
		_day = int(payload)
	else:
		_read_clock()


func _on_night_started(payload) -> void:
	_night = true
	if payload is int:
		_day = int(payload)
	else:
		_read_clock()


# --- internals ----------------------------------------------------------------

## The layer frees the element when its breath is over, so every reference here
## has to be checked before it is touched.
func _purge() -> void:
	if _live != null and not is_instance_valid(_live):
		_live = null


func _tokens() -> UITokens:
	if _layer != null and _layer.has_method("tokens"):
		return _layer.call("tokens")
	return null


func _fonts() -> UIFonts:
	if _layer != null and _layer.has_method("fonts"):
		return _layer.call("fonts")
	return null


## The canvas Controls are positioned in, which under `canvas_items` stretch is
## NOT the window size (briefing trap 10).
func _canvas_size() -> Vector2:
	if is_inside_tree():
		var viewport := get_viewport()
		if viewport != null:
			return viewport.get_visible_rect().size
	return Vector2(1920.0, 1080.0)


func _subscribe() -> void:
	if _bus == null:
		return
	_bus.subscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.subscribe(EVENT_NIGHT_STARTED, _on_night_started)


func _unsubscribe() -> void:
	if _bus == null:
		return
	_bus.unsubscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.unsubscribe(EVENT_NIGHT_STARTED, _on_night_started)


## NOT `_exit_tree()`, and the difference is a leak. That notification is only
## delivered to a node that was IN a tree, and a prompt built by a test or a
## harness never enters one -- so a subscription left behind on a freed object is
## a callback the bus goes on holding. PREDELETE arrives either way. Measured as
## a real leak on ThresholdSurfacing, which has the same note.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		_unsubscribe()
