class_name Beacon
extends Area3D

## One fuel-burning warm point in the valley.
##
## The entity owns only local truth: fuel, flame, interaction and light. Which
## day unlocks it, what the wind does across all five, and the blizzard guarantee
## belong to BeaconNetwork. Fuel is resolved through ServiceRegistry, while every
## outward consequence is published through EventBus.

const GROUP := &"beacon"
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const EVENT_FUELED := &"beacon.fueled"
const EVENT_LIT := &"beacon.lit"
const EVENT_EXTINGUISHED := &"beacon.extinguished"
const EVENT_UNLOCKED := &"beacon.unlocked"
const EVENT_OFFER_ENTERED := &"interaction.offer_entered"
const EVENT_OFFER_CHANGED := &"interaction.offer_changed"
const EVENT_OFFER_EXITED := &"interaction.offer_exited"
const EVENT_ACTIVATED := &"interaction.activated"
const EVENT_REJECTED := &"interaction.rejected"
const TARGET_WARMTH := &"core_temperature:recovery"
const TARGET_REST := &"fatigue:recovery"

@export var definition: BeaconDefinition = null
@export var interact_action: StringName = &"interact"
@export var occupant_service: StringName = &"player"

var _fuel := 0.0
var _lit := false
var _unlocked := false
var _near := false
var _clock := 0.0
var _economy = null
var _bus = null
var _registry = null
var _occupant: Node = null
var _survival = null
var _source_id: StringName = &""
var _light: OmniLight3D = null
var _flame: MeshInstance3D = null
var _wayfinder: MeshInstance3D = null
var _wayfinder_material: StandardMaterial3D = null
var _embers: GPUParticles3D = null
var _ember_motion: ParticleProcessMaterial = null
var _extinguish_smoke: GPUParticles3D = null
var _smoke_motion: ParticleProcessMaterial = null
var _landmark: Node3D = null
var _shape: CollisionShape3D = null
var _bible: ColorBible = null
var _wind_strength := 0.0
var _wind_velocity := Vector3.ZERO
var _wayfinder_state := -1
var _offer_present := false
var _last_offer: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	_resolve_services()
	set_event_bus(_bus)
	_apply_definition()


func _exit_tree() -> void:
	_withdraw_offer()
	_disconnect_interaction()
	# Group membership is state, not identity. Removal from the tree also removes
	# Godot groups, but doing it explicitly keeps the contract true during teardown
	# and makes the recovery modifier leave in the same frame.
	Fires.leave(self)
	clear_recovery()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_withdraw_offer()
		_disconnect_interaction()


func configure(value: BeaconDefinition) -> void:
	definition = value
	if definition != null:
		position = definition.world_position
	if is_inside_tree():
		_apply_definition()


func set_fuel_economy(economy) -> void:
	_economy = economy


func set_event_bus(bus) -> void:
	if bus == _bus:
		_connect_interaction()
		return
	_withdraw_offer()
	_disconnect_interaction()
	_bus = bus
	_connect_interaction()
	_publish_offer()


func set_survival_system(system) -> void:
	if _survival != null and _survival != system:
		clear_recovery()
	_survival = system


func set_occupant(node: Node) -> void:
	_occupant = node


func beacon_id() -> StringName:
	return definition.id if definition != null else &""


func is_lit() -> bool:
	return _lit


func is_unlocked() -> bool:
	return _unlocked


func fuel_remaining() -> float:
	return _fuel


func nominal_fill() -> float:
	if definition == null or definition.fuel_capacity <= 0.0:
		return 0.0
	return clampf(_fuel / definition.fuel_capacity, 0.0, 1.0)


func set_unlocked(value: bool) -> void:
	if _unlocked == value:
		_publish_offer()
		return
	_unlocked = value
	_drive_light()
	if _unlocked:
		_emit(EVENT_UNLOCKED, {"day": definition.unlock_day if definition != null else 0})
	_publish_offer()


## Authored/test path. Gameplay spends the shared inventory through refuel().
func add_fuel_seconds(seconds: float) -> float:
	if not is_finite(seconds) or seconds <= 0.0:
		return 0.0
	_fuel += seconds
	_drive_light()
	_publish_offer()
	return seconds


## Draws whole fuel items until the nominal tank is full. A whole log may put
## the gauge over capacity; keeping that surplus is mandatory because silently
## deleting it would leak the game's only currency.
func refuel() -> float:
	if not _unlocked or definition == null:
		return 0.0
	_resolve_services()
	if _economy == null or not _economy.has_method("draw_burn_seconds"):
		return 0.0
	var wanted := minf(
		definition.refill_request_seconds,
		maxf(definition.fuel_capacity - _fuel, 0.0)
	)
	if wanted <= 0.0:
		return 0.0
	var drawn := float(_economy.draw_burn_seconds(wanted))
	if drawn <= 0.0:
		return 0.0
	add_fuel_seconds(drawn)
	_emit(EVENT_FUELED, {"added_seconds": drawn, "fuel_seconds": _fuel})
	_publish_offer()
	return drawn


func light() -> bool:
	if not _unlocked or _lit or _fuel <= 0.0:
		return false
	_lit = true
	Fires.join(self)
	_drive_light()
	_emit(EVENT_LIT, {"fuel_seconds": _fuel})
	_publish_offer()
	return true


func interact() -> bool:
	if not _unlocked:
		return false
	# A gust can extinguish a beacon without consuming the fuel already in its
	# bowl. Relighting that ember must not first withdraw another whole item.
	if not _lit and _fuel > 0.0:
		var relit := light()
		_publish_offer()
		return relit
	var before := _fuel
	refuel()
	var ignited := light()
	var changed := ignited or not is_equal_approx(before, _fuel)
	_publish_offer()
	return changed


func extinguish(cause: StringName = &"manual") -> bool:
	if not _lit:
		return false
	_lit = false
	Fires.leave(self)
	clear_recovery()
	_burst_extinguish_smoke()
	_drive_light()
	_emit(EVENT_EXTINGUISHED, {"cause": cause, "fuel_seconds": _fuel})
	_publish_offer()
	return true


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_clock += delta
	if _lit and definition != null:
		_fuel = maxf(_fuel - delta * definition.burn_rate, 0.0)
		if _fuel <= 0.0:
			extinguish(&"empty")
	_drive_light()


## Probability of losing this flame during one tick. The exponential converts
## a per-second hazard into the same result at 30, 60 or 144 Hz.
func wind_extinguish_probability(wind_strength: float, delta: float) -> float:
	if not _lit or definition == null or delta <= 0.0:
		return 0.0
	var threshold := definition.wind_extinguish_threshold
	if wind_strength <= threshold or threshold >= 1.0:
		return 0.0
	var exposure := (clampf(wind_strength, 0.0, 1.0) - threshold) / (1.0 - threshold)
	return 1.0 - exp(-definition.wind_extinguish_rate_per_second * exposure * delta)


func try_wind_extinguish(wind_strength: float, delta: float, sample: float) -> bool:
	if clampf(sample, 0.0, 1.0) >= wind_extinguish_probability(wind_strength, delta):
		return false
	return extinguish(&"wind")


## BeaconNetwork supplies the coupled weather sample. This intentionally does
## not claim WindSystem's one-argument `set_wind(Vector3)` consumer vocabulary.
func set_weather_wind(wind_strength: float, wind_velocity: Vector3) -> void:
	_wind_strength = clampf(wind_strength, 0.0, 1.0)
	_wind_velocity = Vector3(wind_velocity.x, 0.0, wind_velocity.z)
	if _ember_motion != null:
		_ember_motion.gravity = Vector3(
			_wind_velocity.x * 0.42, 1.35, _wind_velocity.z * 0.42)
	if _smoke_motion != null:
		_smoke_motion.gravity = Vector3(
			_wind_velocity.x * 0.55, 0.95, _wind_velocity.z * 0.55)


func light_energy_now() -> float:
	if not _lit or definition == null:
		return 0.0
	var fuel_factor := 1.0
	if definition.low_fuel_fade_seconds > 0.0:
		fuel_factor = clampf(_fuel / definition.low_fuel_fade_seconds, 0.0, 1.0)
	var pulse := 1.0
	if definition.pulse_seconds > 0.0:
		pulse -= definition.pulse_fraction * (0.5 + 0.5 * sin(TAU * _clock / definition.pulse_seconds))
	return definition.light_energy * fuel_factor * pulse


## The signal's warm refuge is the beacon's ground-level control point. The
## emissive marker may be on a roof or tower, but the player fuels and shelters
## at this origin; it is also the stable point the 3D fire voice leads toward.
func fire_position() -> Vector3:
	return _origin_of(self)


## How much of this burning signal reaches one world-space point, 0 .. 1.
## This is one of the three questions required by Fires and uses the same point
## fire_position() reports, so navigation, melting and recovery cannot disagree.
func warmth_at(point: Vector3) -> float:
	if not _lit or definition == null:
		return 0.0
	var distance := fire_position().distance_to(point)
	if distance <= definition.warm_radius_m:
		return 1.0
	if definition.warm_falloff_m <= 0.0:
		return 0.0
	return 1.0 - smoothstep(
		definition.warm_radius_m,
		definition.warm_radius_m + definition.warm_falloff_m,
		distance
	)


func recovery_at(point: Vector3) -> Dictionary:
	var warmth := warmth_at(point)
	return {
		TARGET_WARMTH: definition.warmth_recovery_per_second * warmth if definition != null else 0.0,
		TARGET_REST: definition.rest_recovery_per_second * warmth if definition != null else 0.0,
	}


## Replaces this beacon's own contribution rather than accumulating it each
## frame. Separate source ids let two nearby fires coexist without one clearing
## the other's modifier.
func apply_recovery(point: Vector3) -> void:
	if _survival == null:
		return
	var source := _source()
	_survival.remove_source(source)
	var rates := recovery_at(point)
	for target in rates:
		var amount: float = rates[target]
		if amount > 0.0:
			_survival.push_modifier(target, source, Modifier.Operation.ADD, amount)


func clear_recovery() -> void:
	if _survival != null:
		_survival.remove_source(_source())


func _process(delta: float) -> void:
	advance(delta)
	# Inventory may change while two Areas overlap. Rebuild only when the
	# value-only payload actually changes, so this is not an event per frame.
	_publish_offer()
	if _survival == null:
		_resolve_services()
	if _survival == null:
		return
	var body := _player() as Node3D
	if body == null:
		clear_recovery()
		return
	apply_recovery(_origin_of(body))


func _apply_definition() -> void:
	if definition == null:
		return
	position = definition.world_position
	_build_landmark()
	_build_light()
	_build_flame()
	_build_wayfinder()
	_build_embers()
	_build_extinguish_smoke()
	_build_interaction_shape()
	_drive_light()


func _build_landmark() -> void:
	if _landmark != null or definition.landmark_scene == null:
		return
	_landmark = definition.landmark_scene.instantiate() as Node3D
	if _landmark == null:
		return
	_landmark.name = "Landmark"
	_landmark.rotation.y = deg_to_rad(definition.landmark_yaw_degrees)
	add_child(_landmark)


func _build_light() -> void:
	if _light == null:
		_light = OmniLight3D.new()
		_light.name = "WarmPoint"
		_light.shadow_enabled = false
		add_child(_light)
	var bible := _palette()
	if bible != null and not bible.warm_tones.is_empty():
		_light.light_color = bible.warm_tones[clampi(
			definition.warm_tone_index, 0, bible.warm_tones.size() - 1)]
	_light.position = definition.light_offset
	_light.omni_range = definition.light_range_m


func _build_flame() -> void:
	if _flame == null:
		_flame = MeshInstance3D.new()
		_flame.name = "FlameCore"
		_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(_flame)
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = definition.flame_height_m * 0.24
	flame_mesh.height = definition.flame_height_m
	flame_mesh.radial_segments = 8
	flame_mesh.rings = 4
	var bible := _palette()
	if bible != null and not bible.warm_tones.is_empty():
		var warm := bible.warm_tones[clampi(
			definition.warm_tone_index, 0, bible.warm_tones.size() - 1)]
		var material := StandardMaterial3D.new()
		material.albedo_color = warm
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = warm
		material.emission_energy_multiplier = 1.35
		flame_mesh.material = material
	_flame.mesh = flame_mesh
	_flame.position = definition.light_offset


func _build_wayfinder() -> void:
	if _wayfinder == null:
		_wayfinder = MeshInstance3D.new()
		_wayfinder.name = "Wayfinder"
		_wayfinder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wayfinder.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(_wayfinder)
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(definition.flame_height_m * 0.62, 0.32)
	ring.outer_radius = ring.inner_radius + maxf(definition.flame_height_m * 0.12, 0.07)
	ring.rings = 12
	ring.ring_segments = 4
	_wayfinder_material = StandardMaterial3D.new()
	_wayfinder_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material = _wayfinder_material
	_wayfinder.mesh = ring
	_wayfinder.position = definition.light_offset + Vector3(0.0, 1.15, 0.0)


func _build_embers() -> void:
	if _embers != null:
		return
	_embers = GPUParticles3D.new()
	_embers.name = "WindEmbers"
	_embers.amount = 12
	_embers.lifetime = 0.72
	_embers.fixed_fps = 20
	_embers.one_shot = false
	_embers.local_coords = false
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_embers.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_embers.visibility_aabb = AABB(Vector3(-5.0, -1.0, -5.0), Vector3(10.0, 7.0, 10.0))
	_embers.position = definition.light_offset
	_ember_motion = ParticleProcessMaterial.new()
	_ember_motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_ember_motion.emission_sphere_radius = 0.12
	_ember_motion.direction = Vector3.UP
	_ember_motion.spread = 24.0
	_ember_motion.initial_velocity_min = 0.45
	_ember_motion.initial_velocity_max = 1.1
	_ember_motion.gravity = Vector3(0.0, 1.35, 0.0)
	_ember_motion.scale_min = 0.45
	_ember_motion.scale_max = 1.0
	_embers.process_material = _ember_motion
	_embers.draw_pass_1 = _particle_quad(0.055, _warm_color())
	add_child(_embers)


func _build_extinguish_smoke() -> void:
	if _extinguish_smoke != null:
		return
	_extinguish_smoke = GPUParticles3D.new()
	_extinguish_smoke.name = "ExtinguishSmoke"
	_extinguish_smoke.amount = 18
	_extinguish_smoke.lifetime = 1.45
	_extinguish_smoke.fixed_fps = 20
	_extinguish_smoke.one_shot = true
	_extinguish_smoke.explosiveness = 0.86
	_extinguish_smoke.local_coords = false
	_extinguish_smoke.emitting = false
	_extinguish_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_extinguish_smoke.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_extinguish_smoke.visibility_aabb = AABB(Vector3(-7.0, -1.0, -7.0), Vector3(14.0, 9.0, 14.0))
	_extinguish_smoke.position = definition.light_offset
	_smoke_motion = ParticleProcessMaterial.new()
	_smoke_motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_smoke_motion.emission_sphere_radius = 0.18
	_smoke_motion.direction = Vector3.UP
	_smoke_motion.spread = 38.0
	_smoke_motion.initial_velocity_min = 0.55
	_smoke_motion.initial_velocity_max = 1.5
	_smoke_motion.gravity = Vector3(0.0, 0.95, 0.0)
	_smoke_motion.scale_min = 0.7
	_smoke_motion.scale_max = 1.7
	_extinguish_smoke.process_material = _smoke_motion
	var smoke := _structure_color()
	smoke.a = 0.58
	_extinguish_smoke.draw_pass_1 = _particle_quad(0.24, smoke)
	add_child(_extinguish_smoke)


func _particle_quad(size: float, tone: Color) -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = tone
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	return quad


func _burst_extinguish_smoke() -> void:
	if _extinguish_smoke == null:
		return
	_extinguish_smoke.restart()
	_extinguish_smoke.emitting = true


func _palette() -> ColorBible:
	if _bible == null:
		_bible = load(PALETTE_PATH) as ColorBible
	return _bible


func _warm_color() -> Color:
	var bible := _palette()
	return bible.warm_tones[clampi(
		definition.warm_tone_index, 0, bible.warm_tones.size() - 1)]


func _structure_color() -> Color:
	var bible := _palette()
	return bible.structure_tones[mini(2, bible.structure_tones.size() - 1)]


func _build_interaction_shape() -> void:
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "InteractionRadius"
		add_child(_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = definition.interaction_radius_m
	_shape.shape = sphere
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false


func _drive_light() -> void:
	if _light != null:
		_light.light_energy = light_energy_now()
		_light.visible = _lit
	if _flame != null:
		_flame.visible = _lit
		var pulse_scale := 1.0
		if _lit and definition != null and definition.light_energy > 0.0:
			pulse_scale = 0.92 + 0.08 * light_energy_now() / definition.light_energy
		_flame.scale = Vector3(pulse_scale, pulse_scale * (1.0 + 0.12 * _wind_strength), pulse_scale)
		_flame.rotation = Vector3(
			_wind_velocity.z * 0.025 * _wind_strength,
			0.0,
			-_wind_velocity.x * 0.025 * _wind_strength
		)
	if _embers != null:
		_embers.emitting = _lit
		_embers.amount_ratio = (0.28 + 0.72 * _wind_strength) if _lit else 0.0
	_drive_wayfinder()


func _drive_wayfinder() -> void:
	if _wayfinder == null or _wayfinder_material == null:
		return
	_wayfinder.visible = _unlocked
	var state := 2 if _lit else (1 if _unlocked else 0)
	if state != _wayfinder_state:
		_wayfinder_state = state
		var tone := _warm_color() if _lit else _structure_color()
		_wayfinder_material.albedo_color = tone
		_wayfinder_material.emission_enabled = _lit
		_wayfinder_material.emission = tone
		_wayfinder_material.emission_energy_multiplier = 1.18
	var breath := 1.0
	if _lit and definition != null and definition.pulse_seconds > 0.0:
		breath = 0.94 + 0.06 * (0.5 + 0.5 * sin(TAU * _clock / definition.pulse_seconds))
	_wayfinder.scale = Vector3.ONE * breath


func _on_body_entered(body: Node) -> void:
	if _accepts(body):
		_near = true
		_publish_offer()


func _on_body_exited(body: Node) -> void:
	if _accepts(body):
		_near = false
		_withdraw_offer()


func _on_interaction_activated(payload) -> void:
	if not (payload is Dictionary):
		return
	if StringName(payload.get("id", &"")) != _offer_id() or not _near:
		return
	if not interact():
		_emit_interaction_rejected()


func _emit_interaction_rejected() -> void:
	var bus = _event_bus()
	if bus == null:
		return
	var offer := _interaction_offer()
	bus.emit_event(EVENT_REJECTED, {
		"id": _offer_id(),
		"kind": &"beacon",
		"verb": String(offer.get("verb", "Use")),
		"label": definition.display_name if definition != null else "Beacon",
		"reason": StringName(offer.get("reason", &"unavailable")),
		"world_position": fire_position(),
	})


func _publish_offer() -> void:
	if not _near or definition == null:
		return
	var bus = _event_bus()
	if bus == null:
		return
	var offer := _interaction_offer()
	if _offer_present and offer == _last_offer:
		return
	bus.emit_event(EVENT_OFFER_CHANGED if _offer_present else EVENT_OFFER_ENTERED, offer)
	_offer_present = true
	_last_offer = offer


func _withdraw_offer() -> void:
	if not _offer_present:
		return
	if _bus != null and is_instance_valid(_bus):
		_bus.emit_event(EVENT_OFFER_EXITED, {"id": _offer_id()})
	_offer_present = false
	_last_offer.clear()


func _interaction_offer() -> Dictionary:
	var enabled := _unlocked
	var reason: StringName = &"" if _unlocked else &"locked"
	if _unlocked and not _lit and _fuel > 0.0:
		enabled = true
	elif _unlocked:
		var available := _inventory_fuel_seconds()
		enabled = available > 0.0 and (definition.fuel_capacity - _fuel) > 0.0
		if not enabled:
			reason = &"full" if (definition.fuel_capacity - _fuel) <= 0.0 else &"no_fuel"
	return {
		"id": _offer_id(),
		"kind": &"beacon",
		"verb": "Add fuel" if _lit else "Light",
		"label": definition.display_name,
		"world_position": fire_position(),
		"enabled": enabled,
		"reason": reason,
	}


func _inventory_fuel_seconds() -> float:
	if _economy == null:
		_resolve_services()
	if _economy != null and _economy.has_method("fuel_seconds"):
		return float(_economy.fuel_seconds())
	return 0.0


func _offer_id() -> StringName:
	return StringName("beacon:%s" % String(beacon_id()))


func _connect_interaction() -> void:
	if _bus != null and is_instance_valid(_bus):
		_bus.subscribe(EVENT_ACTIVATED, _on_interaction_activated)


func _disconnect_interaction() -> void:
	if _bus != null and is_instance_valid(_bus):
		_bus.unsubscribe(EVENT_ACTIVATED, _on_interaction_activated)


func _accepts(body: Node) -> bool:
	var who := _player()
	return who != null and who == body


func _player() -> Node:
	if _occupant != null and is_instance_valid(_occupant):
		return _occupant
	_resolve_services()
	if _registry != null:
		_occupant = _registry.get_service(occupant_service) as Node
	return _occupant


func _resolve_services() -> void:
	if not is_inside_tree():
		return
	if _registry == null:
		_registry = get_node_or_null("/root/ServiceRegistry")
	if _registry != null and _economy == null:
		_economy = _registry.get_service(&"fuel_economy")
	if _survival == null:
		_survival = get_node_or_null("/root/SurvivalSystem")
	if _bus == null:
		_bus = get_node_or_null("/root/EventBus")
		_connect_interaction()


func _event_bus():
	if _bus == null:
		_resolve_services()
	return _bus


static func _origin_of(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


func _source() -> StringName:
	if _source_id == &"":
		_source_id = StringName("beacon:%d" % get_instance_id())
	return _source_id


func _emit(event: StringName, extra: Dictionary) -> void:
	if _bus == null:
		_resolve_services()
	if _bus == null:
		return
	var payload := {
		"id": beacon_id(),
		"kind": &"beacon",
		"label": definition.display_name if definition != null else "",
		"world_position": fire_position(),
		"lit": _lit,
		"unlocked": _unlocked,
	}
	for key in extra:
		payload[key] = extra[key]
	_bus.emit_event(event, payload)
