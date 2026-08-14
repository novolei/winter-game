class_name PigeonAffection
extends Node3D

## Two brief world-space hearts after a pigeon finishes eating. One is clearly
## larger, one smaller, and their head-top offsets change per meal. They remain
## an animal response rather than a permanent status badge: staggered pop, soft
## overshoot, float and clear in just over a second.

const PRESENTATION: PigeonPresentation = preload("res://data/wildlife/pigeon_presentation.tres")
const HEART_ANIMATION_SECONDS := 1.05
const SMALL_DELAY_SECONDS := 0.08
const DURATION_SECONDS := HEART_ANIMATION_SECONDS + SMALL_DELAY_SECONDS
const RISE_M := 0.25
const BIG_FONT_SIZE := 68
const SMALL_FONT_SIZE := 46
const HEART_PIXEL_SIZE := 0.0034

var _elapsed := 0.0
var _origin := Vector3.ZERO
var _seed := 0
var _labels: Array[Label3D] = []
var _offsets: Array[Vector3] = []
var _delays: Array[float] = []


func configure(seed: int) -> void:
	_seed = seed


func _ready() -> void:
	_origin = position
	var specs := heart_specs_for(_seed if _seed != 0 else int(get_instance_id()))
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var label := Label3D.new()
		label.name = "HeartBig" if index == 0 else "HeartSmall"
		label.text = "♥"
		label.font_size = int(spec["font_size"])
		label.pixel_size = HEART_PIXEL_SIZE
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.modulate = PRESENTATION.heart_color
		add_child(label)
		_labels.append(label)
		_offsets.append(spec["offset"] as Vector3)
		_delays.append(float(spec["delay"]))
	_apply()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> bool:
	if not is_finite(delta) or delta <= 0.0:
		return _elapsed < DURATION_SECONDS
	_elapsed = minf(_elapsed + delta, DURATION_SECONDS)
	_apply()
	if _elapsed >= DURATION_SECONDS and is_inside_tree():
		queue_free()
	return _elapsed < DURATION_SECONDS


static func scale_for(seconds: float) -> float:
	var t := maxf(seconds, 0.0)
	if t <= 0.0:
		return 0.0
	if t < 0.18:
		# Back-out: the small overshoot is the readable reward motion.
		var x := t / 0.18
		var shifted := x - 1.0
		return 1.0 + 2.70158 * shifted * shifted * shifted + 1.70158 * shifted * shifted
	if t < 0.36:
		var x := (t - 0.18) / 0.18
		var eased := x * x * (3.0 - 2.0 * x)
		return lerpf(1.10, 1.0, eased)
	if t < 0.68:
		return 1.0 + sin((t - 0.36) / 0.32 * PI) * 0.035
	return 1.0


static func alpha_for(seconds: float) -> float:
	var t := maxf(seconds, 0.0)
	if t < 0.08:
		return clampf(t / 0.08, 0.0, 1.0)
	if t <= 0.68:
		return 1.0
	return 1.0 - clampf((t - 0.68) / (HEART_ANIMATION_SECONDS - 0.68), 0.0, 1.0)


static func rise_for(seconds: float) -> float:
	var x := clampf(maxf(seconds, 0.0) / HEART_ANIMATION_SECONDS, 0.0, 1.0)
	var eased := x * x * (3.0 - 2.0 * x)
	return RISE_M * eased


## Stable for a supplied seed so captures and tests can reproduce a meal, while
## gameplay hands in a fresh flock RNG draw for a different head-top pairing.
static func heart_specs_for(seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var angle := rng.randf_range(0.0, TAU)
	var spread := Vector3(cos(angle), 0.0, sin(angle))
	var cross := Vector3(-spread.z, 0.0, spread.x)
	var big_offset := spread * rng.randf_range(0.045, 0.085) \
		+ cross * rng.randf_range(-0.025, 0.025) \
		+ Vector3.UP * rng.randf_range(0.015, 0.045)
	var small_offset := -spread * rng.randf_range(0.060, 0.105) \
		+ cross * rng.randf_range(-0.030, 0.030) \
		+ Vector3.UP * rng.randf_range(0.070, 0.115)
	return [
		{"font_size": BIG_FONT_SIZE, "offset": big_offset, "delay": 0.0},
		{"font_size": SMALL_FONT_SIZE, "offset": small_offset, "delay": SMALL_DELAY_SECONDS},
	]


func heart_count() -> int:
	return _labels.size()


func heart_offsets() -> Array[Vector3]:
	return _offsets.duplicate()


func heart_font_sizes() -> Array[int]:
	var sizes: Array[int] = []
	for label in _labels:
		sizes.append(label.font_size)
	return sizes


func _apply() -> void:
	position = _origin
	for index in range(_labels.size()):
		var label := _labels[index]
		var local_time := maxf(_elapsed - _delays[index], 0.0)
		label.scale = Vector3.ONE * scale_for(local_time)
		var sway_sign := 1.0 if index == 0 else -1.0
		label.position = _offsets[index] + Vector3(
			sway_sign * 0.014 * sin(local_time * (7.0 + float(index))),
			rise_for(local_time),
			0.0
		)
		var colour := PRESENTATION.heart_color
		colour.a *= alpha_for(local_time) if _elapsed >= _delays[index] else 0.0
		label.modulate = colour
