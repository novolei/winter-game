class_name PauseChoreography
extends RefCounted

## The stagger schedule behind the pause surface's cascade (design spec
## section 2.1/2.4). A pure function of time: ExitMenu drives it from one
## tween, and a test drives it with no frames at all.
##
## Opening: each line blooms (opacity 0 -> 1, +8px -> home, QUINT OUT),
## starting stagger_seconds after the line before it.
## Closing: the same lines in EXACT reverse, drifting up and out (QUAD IN).

const STAGGER_RATIO := 0.35
const RISE_PIXELS := 8.0

var lines: Array[StringName] = []
var stagger_seconds := 0.07
var line_seconds := 0.20
var is_closing := false

static func opening(tokens: UITokens, ids: Array[StringName]) -> PauseChoreography:
	var schedule := PauseChoreography.new()
	schedule.lines = ids.duplicate()
	schedule.line_seconds = tokens.bloom_seconds
	schedule.stagger_seconds = tokens.bloom_seconds * STAGGER_RATIO
	schedule.is_closing = false
	return schedule

static func closing(tokens: UITokens, ids: Array[StringName]) -> PauseChoreography:
	var schedule := PauseChoreography.new()
	schedule.lines = ids.duplicate()
	schedule.lines.reverse()
	schedule.line_seconds = tokens.drift_fast_seconds
	schedule.stagger_seconds = tokens.drift_fast_seconds * STAGGER_RATIO
	schedule.is_closing = true
	return schedule

## State-to-state swaps (menu -> confirm, menu -> settings) are not arrivals,
## they are re-dealings of the same hand: much tighter stagger, quick bloom, so
## the page that was asked for is THERE before the finger leaves the key.
static func transition(tokens: UITokens, ids: Array[StringName]) -> PauseChoreography:
	var schedule := PauseChoreography.new()
	schedule.lines = ids.duplicate()
	schedule.line_seconds = tokens.bloom_seconds * 0.8
	schedule.stagger_seconds = tokens.bloom_seconds * 0.14
	schedule.is_closing = false
	return schedule

func start_at(index: int) -> float:
	return stagger_seconds * index

func total_seconds() -> float:
	return stagger_seconds * maxi(lines.size() - 1, 0) + line_seconds

func alpha_at(index: int, t: float) -> float:
	var p := _eased(_progress_at(index, t))
	return (1.0 - p) if is_closing else p

func offset_at(index: int, t: float) -> float:
	var p := _eased(_progress_at(index, t))
	# Opening settles AT home from +8 below; closing leaves home upward.
	return (-p * RISE_PIXELS) if is_closing else ((1.0 - p) * RISE_PIXELS)

func _progress_at(index: int, t: float) -> float:
	if index < 0 or index >= lines.size() or line_seconds <= 0.0:
		return 1.0
	return clampf((t - start_at(index)) / line_seconds, 0.0, 1.0)

func _eased(p: float) -> float:
	# QUINT OUT to arrive, QUAD IN to leave -- the tween curves the menu
	# already uses, written out so no Tween is needed to evaluate them.
	return p * p if is_closing else 1.0 - pow(1.0 - p, 5.0)
