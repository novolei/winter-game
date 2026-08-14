class_name FireGlow
extends OmniLight3D

## The light an open flame throws, coloured from the palette like every warm
## source in the project.
##
## Briefing constraint 6 bans a literal colour in `src/`, `data/`, `scenes/`
## and `assets/`, so an OmniLight3D dropped into a scene cannot carry the
## amber itself -- a `.tscn` colour field IS a hardcoded colour. The stove
## (`src/entities/stove/stove.gd`) and the beacons solved this by reading
## `data/palette/color_bible.tres` at runtime; this is the same pattern for
## the small dressing fires that have no system of their own, starting with
## the burning barrel on the workyard.
##
## The flicker is two sines, not noise: noise needs a RandomNumberGenerator
## per light, and a phase drifted by world position keeps two barrels in one
## frame from breathing in step without any state at all.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"

## Ordinary exterior meshes, the character and snow have separate visual
## layers. This open flame intentionally reaches all three, but snow handles
## local lights through its own soft coloured branch rather than through the
## directional cel band that used to paint a pixel-edged white disc.
const WORLD_PROP_RENDER_LAYER := 1
const CHARACTER_RENDER_LAYER := 1 << 1
const SNOW_RENDER_LAYER := 1 << 3
const FIRE_LIT_RENDER_LAYERS := \
	WORLD_PROP_RENDER_LAYER | CHARACTER_RENDER_LAYER | SNOW_RENDER_LAYER

## Night-time energy. Daylight deliberately suppresses this same small pool;
## the radius does not expand at night.
@export var base_energy := 3.2
## A real flame remains present in daylight, but the bright winter environment
## makes its contribution much quieter than it is after dark.
@export_range(0.0, 1.0) var day_energy_multiplier := 0.12
## How far the flicker swings, as a fraction of `base_energy`.
@export_range(0.0, 1.0) var flicker := 0.22
## Breaths per second, roughly. Fire flickers faster than a lamp hums.
@export var flicker_speed := 7.0
## A burning barrel is a local landmark, not a yard floodlight.
@export_range(0.5, 6.0, 0.05) var radial_range_m := 2.6
## Higher attenuation concentrates the useful light near the flame and gives
## nearby three-dimensional forms a readable radial falloff.
@export_range(0.1, 8.0, 0.05) var radial_attenuation := 2.2
@export var cast_local_shadows := true

var _phase := 0.0
var _night := false
var _bus = null
var _subscribed := false


func _ready() -> void:
	_apply_radial_contract()
	var bible = load(PALETTE_PATH)
	# warm_tones' last entry is the bright amber the windows and the beacons
	# share -- the same choice stove.gd makes for its firelight.
	if bible != null and not bible.warm_tones.is_empty():
		light_color = bible.warm_tones[bible.warm_tones.size() - 1]
	# A phase off the world position, so two of these in one frame do not
	# breathe in step. Outside the tree there is no position and the light
	# simply starts at zero phase.
	if is_inside_tree():
		var at := global_position
		_phase = fmod(at.x * 1.7 + at.z * 2.3, TAU)
	_attach_bus()
	_apply_flicker()


func _exit_tree() -> void:
	_detach_bus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_detach_bus()


func _process(delta: float) -> void:
	_phase += delta * flicker_speed
	_apply_flicker()


## Public for deterministic tests and for an authored preview that has no
## running clock. Gameplay reaches it only through the two EventBus callbacks.
func set_night(value: bool) -> void:
	_night = value
	_apply_flicker()


func set_event_bus(bus) -> void:
	_detach_bus()
	_bus = bus
	_attach_bus()


func _apply_radial_contract() -> void:
	omni_range = radial_range_m
	omni_attenuation = radial_attenuation
	shadow_enabled = cast_local_shadows
	light_cull_mask = FIRE_LIT_RENDER_LAYERS


func _apply_flicker() -> void:
	var phase_energy := base_energy if _night else base_energy * day_energy_multiplier
	var wave := sin(_phase) * 0.6 + sin(_phase * 2.7) * 0.4
	light_energy = phase_energy * (1.0 + flicker * wave)


func _attach_bus() -> void:
	if _bus == null and is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.subscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_subscribed = true


func _detach_bus() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.unsubscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_subscribed = false


func _on_day_started(_payload) -> void:
	set_night(false)


func _on_night_started(_payload) -> void:
	set_night(true)
