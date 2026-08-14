class_name SurvivalRouteNode
extends Area3D

const EVENT_PICKED_UP := &"item.picked_up"
const EVENT_OFFER_ENTERED := &"interaction.offer_entered"
const EVENT_OFFER_CHANGED := &"interaction.offer_changed"
const EVENT_OFFER_EXITED := &"interaction.offer_exited"
const EVENT_ACTIVATED := &"interaction.activated"
const PICKUP_GROUP := &"route_pickup"
const DRESSING_GROUP := &"route_dressing"

@export var definition: SurvivalRouteNodeDefinition = null
@export var interact_action: StringName = &"interact"

var _visual: Node3D = null
var _shape: CollisionShape3D = null
var _painter: CelPainter = null
var _economy = null
var _bus = null
var _occupant: Node = null
var _near := false
var _collected := false
var _offer_present := false


func _ready() -> void:
	_resolve_services()
	set_event_bus(_bus)
	_apply_definition()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	_withdraw_offer()
	_disconnect_interaction()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_withdraw_offer()
		_disconnect_interaction()


func configure(value: SurvivalRouteNodeDefinition) -> void:
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


func set_occupant(occupant: Node) -> void:
	_occupant = occupant


func is_collected() -> bool:
	return _collected


## Restores the authored pickup without rebuilding its imported visual. This is
## deliberately silent: it is a boundary between attempts, not a world event
## the outgoing player should see or hear.
func reset_for_run() -> void:
	_near = false
	_withdraw_offer()
	_collected = false
	visible = true
	if definition == null or not definition.is_pickup():
		return
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	if _shape != null:
		_shape.set_deferred("disabled", false)


func collect() -> bool:
	if _collected or definition == null or not definition.is_pickup():
		return false
	_resolve_services()
	if _economy == null or not _economy.has_method("add") or not _economy.has_method("count_of"):
		return false
	var before := int(_economy.count_of(definition.item_id))
	var after := int(_economy.add(definition.item_id, definition.item_count))
	if after - before != definition.item_count:
		return false
	# The prompt goes first; a successful pickup must never linger until an Area
	# emits body_exited (monitoring is disabled below, so that signal may not).
	_near = false
	_withdraw_offer()
	_collected = true
	visible = false
	monitoring = false
	monitorable = false
	if _shape != null:
		_shape.set_deferred("disabled", true)
	_emit_pickup(after)
	return true


func _apply_definition() -> void:
	if definition == null:
		return
	position = definition.world_position
	rotation.y = deg_to_rad(definition.yaw_degrees)
	_build_visual()
	_settle_on_snow()
	if definition.is_pickup():
		add_to_group(PICKUP_GROUP)
		_build_shape()
	else:
		add_to_group(DRESSING_GROUP)
		collision_layer = 0
		collision_mask = 0
		monitoring = false
		monitorable = false


func _build_visual() -> void:
	if _visual != null or definition.model_scene == null:
		return
	_visual = definition.model_scene.instantiate() as Node3D
	if _visual == null:
		return
	_visual.name = "Visual"
	_visual.scale = definition.model_scale
	# Imported glTF scenes briefly submit their original surface overrides when
	# they enter the tree. Paint off-tree first so the renderer never observes a
	# null imported material between instancing and the cel/snow override.
	_painter = CelPainter.new()
	_painter.paint(
		_visual,
		definition.snow_receptivity_scale,
		definition.snow_threshold_bias
	)
	add_child(_visual)


func _build_shape() -> void:
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "PickupRadius"
		add_child(_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = definition.interaction_radius_m
	_shape.shape = sphere
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false


func _settle_on_snow() -> void:
	_resolve_services()
	var registry := get_node_or_null("/root/ServiceRegistry") if is_inside_tree() else null
	var snow = registry.get_service(&"snow_field") if registry != null else null
	if snow != null and snow.has_method("surface_height_at"):
		global_position.y = float(snow.surface_height_at(global_position)) - 0.05


func _accepts(body: Node) -> bool:
	_resolve_services()
	return _occupant != null and is_instance_valid(_occupant) and body == _occupant


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
	collect()


func _publish_offer() -> void:
	if not _near or _collected or definition == null or not definition.is_pickup():
		return
	if _bus == null:
		_resolve_services()
	if _bus == null:
		return
	_bus.emit_event(EVENT_OFFER_CHANGED if _offer_present else EVENT_OFFER_ENTERED, {
		"id": _offer_id(),
		"kind": &"pickup",
		"verb": "Pick up",
		"label": _item_label(),
		"world_position": global_position if is_inside_tree() else position,
		"enabled": true,
	})
	_offer_present = true


func _withdraw_offer() -> void:
	if not _offer_present:
		return
	if _bus != null and is_instance_valid(_bus):
		_bus.emit_event(EVENT_OFFER_EXITED, {"id": _offer_id()})
	_offer_present = false


func _offer_id() -> StringName:
	return StringName("pickup:%s" % String(definition.id if definition != null else &""))


func _item_label() -> String:
	if definition == null:
		return ""
	if _economy == null:
		_resolve_services()
	if _economy != null and _economy.has_method("definition_of"):
		var item = _economy.definition_of(definition.item_id)
		if item != null and String(item.display_name) != "":
			return String(item.display_name)
	return String(definition.item_id).capitalize()


func _connect_interaction() -> void:
	if _bus != null and is_instance_valid(_bus):
		_bus.subscribe(EVENT_ACTIVATED, _on_interaction_activated)


func _disconnect_interaction() -> void:
	if _bus != null and is_instance_valid(_bus):
		_bus.unsubscribe(EVENT_ACTIVATED, _on_interaction_activated)


func _resolve_services() -> void:
	if not is_inside_tree():
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null:
		if _economy == null:
			_economy = registry.get_service(&"fuel_economy")
		if _occupant == null:
			_occupant = registry.get_service(&"player") as Node
	if _bus == null:
		_bus = get_node_or_null("/root/EventBus")
		_connect_interaction()


func _emit_pickup(total: int) -> void:
	if _bus == null:
		_resolve_services()
	if _bus != null:
		var label := _item_label()
		_bus.emit_event(EVENT_PICKED_UP, {
			"node_id": definition.id,
			"route_id": definition.route_id,
			"item_id": definition.item_id,
			"kind": &"pickup",
			"label": label,
			"icon_id": definition.item_id,
			"count": definition.item_count,
			"total": total,
			"world_position": global_position if is_inside_tree() else position,
		})
