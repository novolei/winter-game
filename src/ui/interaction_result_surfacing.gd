class_name InteractionResultSurfacing
extends Node

## Turns successful world mutations and refused interaction attempts into short
## receipts in the lower-left breathing border. Domain events remain the truth;
## this node never polls inventory, beacons or the stove, and never stores a live
## producer from a payload.

const ReceiptScript := preload("res://src/ui/interaction_receipt.gd")

const EVENT_ITEM_PICKED_UP := &"item.picked_up"
const EVENT_BEACON_FUELED := &"beacon.fueled"
const EVENT_BEACON_LIT := &"beacon.lit"
const EVENT_BEACON_EXTINGUISHED := &"beacon.extinguished"
const EVENT_STOVE_STOKED := &"stove.stoked"
const EVENT_STOVE_WENT_OUT := &"stove.went_out"
const EVENT_INTERACTION_REJECTED := &"interaction.rejected"

## UI design section 5.3: 呵 200 / 持 1400 / 散 900.
const SUCCESS_HOLD_SECONDS := 1.4
const REJECT_HOLD_SECONDS := 2.0
const OUTAGE_HOLD_SECONDS := 2.6
const STACK_GAP_DESIGN_PX := 8.0
const MAX_LIVE := 3

var _layer = null
var _bus = null
var _lighting = null

## key -> normalized value-only spec. Beacon fueled/lit events share a key and
## are folded here before a Control exists.
var _pending: Dictionary = {}
var _pending_order: Array[StringName] = []
var _flush_scheduled := false

## key -> Control. UILayer owns their lifetime; this table is purged before use.
var _live: Dictionary = {}
var _live_order: Array[StringName] = []


func _ready() -> void:
	build()


func build() -> void:
	if _layer == null:
		var parent := get_parent()
		if parent != null and parent.has_method("surface"):
			_layer = parent
	# PackedScene children receive _ready() before their parent. UILayer owns its
	# build in its own _ready(); asking it to add Voice/diagnostic children from
	# here hits Godot's "parent is busy setting up children" guard.
	if _bus == null and is_inside_tree():
		set_event_bus(get_node_or_null("/root/EventBus"))


func set_layer(layer) -> void:
	_layer = layer


func set_event_bus(bus) -> void:
	if bus == _bus:
		_subscribe()
		return
	_unsubscribe()
	_bus = bus
	_subscribe()


func set_lighting(lighting) -> void:
	_lighting = lighting


func pending_count() -> int:
	return _pending.size()


func live_count() -> int:
	_purge_live()
	return _live.size()


func active_for(key: StringName):
	_purge_live()
	var raw: Variant = _live.get(key, null)
	return raw if raw != null and is_instance_valid(raw) else null


## Public test seam. EventBus callbacks call the same method, so normalization,
## coalescing and malformed-payload behavior have one implementation.
func ingest(event_id: StringName, payload: Variant) -> void:
	if not (payload is Dictionary):
		return
	var spec := _spec_for(event_id, payload as Dictionary)
	if spec.is_empty():
		return
	var key := StringName(spec.get("key", &""))
	if key == &"":
		return
	if _pending.has(key):
		_pending[key] = _merge_specs(_pending[key], spec)
	else:
		_pending[key] = spec
		_pending_order.append(key)
	_schedule_flush()


## Deferred by the live EventBus path, public so a unit test can force the end
## of the current call stack without waiting for a SceneTree frame.
func flush_pending() -> void:
	_flush_scheduled = false
	if _pending_order.is_empty():
		return
	var order := _pending_order.duplicate()
	var batch := _pending.duplicate(true)
	_pending.clear()
	_pending_order.clear()
	for key in order:
		if batch.has(key):
			_surface_spec(_finalize_spec(batch[key]))


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_purge_live()
	for key in _live_order:
		var raw: Variant = _live.get(key, null)
		if raw != null and is_instance_valid(raw) and raw.has_method("advance"):
			raw.call("advance", delta)


func _process(delta: float) -> void:
	advance(delta)


func _schedule_flush() -> void:
	if _flush_scheduled:
		return
	_flush_scheduled = true
	if is_inside_tree():
		call_deferred("flush_pending")


func _surface_spec(spec: Dictionary) -> void:
	if _layer == null or spec.is_empty():
		return
	_purge_live()
	var key := StringName(spec.get("key", &""))
	var existing: Variant = _live.get(key, null)
	if existing != null and is_instance_valid(existing):
		existing.apply_spec(spec)
		existing.set_ground(ground_value())
		var viewport := _canvas_size()
		existing.layout_for(viewport)
		_layout_live(viewport)
		_layer.refresh_hold(existing, _hold_seconds(spec))
		return

	while _live_order.size() >= MAX_LIVE:
		var oldest: StringName = _live_order.pop_front()
		var old: Variant = _live.get(oldest, null)
		_live.erase(oldest)
		if old != null and is_instance_valid(old):
			_layer.dismiss(old, Breath.Exit.FAST)

	var receipt = ReceiptScript.new()
	if not receipt.build(_tokens(), _fonts(), spec):
		receipt.free()
		return
	receipt.name = "Result_%s" % String(key).replace(":", "_")
	receipt.set_ground(ground_value())
	var viewport := _canvas_size()
	receipt.layout_for(viewport)
	_live[key] = receipt
	_live_order.append(key)
	_layout_live(viewport)
	_layer.surface(receipt, _hold_seconds(spec))


func _layout_live(viewport: Vector2) -> void:
	var edge := 0.0 if _tokens() == null else _tokens().edge_pixels(viewport)
	var gap := 0.0 if _tokens() == null \
		else _tokens().design_px(STACK_GAP_DESIGN_PX, viewport)
	var y := viewport.y - edge
	# Newest is closest to the bottom edge; older receipts rise above it.
	for index in range(_live_order.size() - 1, -1, -1):
		var key := _live_order[index]
		var raw: Variant = _live.get(key, null)
		if raw == null or not is_instance_valid(raw):
			continue
		var receipt: Control = raw
		y -= receipt.size.y
		var home := Vector2(edge, y)
		receipt.position = home
		if _layer.has_method("rehome"):
			_layer.rehome(receipt, home)
		y -= gap


func _spec_for(event_id: StringName, payload: Dictionary) -> Dictionary:
	match event_id:
		EVENT_ITEM_PICKED_UP:
			return _pickup_spec(payload)
		EVENT_BEACON_FUELED:
			return _beacon_spec(payload, true)
		EVENT_BEACON_LIT:
			return _beacon_spec(payload, false)
		EVENT_BEACON_EXTINGUISHED:
			return _outage_spec(payload, &"beacon")
		EVENT_STOVE_STOKED:
			return _stove_spec(payload)
		EVENT_STOVE_WENT_OUT:
			return _outage_spec(payload, &"stove")
		EVENT_INTERACTION_REJECTED:
			return _rejected_spec(payload)
	return {}


func _pickup_spec(payload: Dictionary) -> Dictionary:
	var item_id := StringName(payload.get("item_id", &""))
	if item_id == &"":
		return {}
	var label := _label(payload, String(item_id).capitalize())
	var count := maxi(int(payload.get("count", 1)), 1)
	var total := maxi(int(payload.get("total", count)), count)
	return {
		"key": StringName("pickup:%s" % String(item_id)),
		"kind": &"pickup",
		"copy": "Picked up · %s" % label,
		"amount": "+%d · %d" % [count, total],
		"icon_id": StringName(payload.get("icon_id", item_id)),
		"count": count,
		"total": total,
		"world_position": _position(payload),
		"rejected": false,
	}


func _beacon_spec(payload: Dictionary, fueled: bool) -> Dictionary:
	var id := StringName(payload.get("id", &""))
	if id == &"":
		return {}
	var added := maxf(float(payload.get("added_seconds", 0.0)), 0.0)
	return {
		"key": StringName("beacon:%s" % String(id)),
		"kind": &"beacon",
		"label": _label(payload, String(id).capitalize()),
		"copy": "",
		"amount": "",
		"icon_id": StringName(payload.get("icon_id", &"beacon")),
		"added_seconds": added,
		"fuel_seconds": maxf(float(payload.get("fuel_seconds", 0.0)), 0.0),
		"saw_fueled": fueled,
		"saw_lit": not fueled,
		"world_position": _position(payload),
		"rejected": false,
	}


func _stove_spec(payload: Dictionary) -> Dictionary:
	var id := StringName(payload.get("id", &"stove"))
	if id == &"":
		id = &"stove"
	var added := maxf(float(payload.get("added_seconds", 0.0)), 0.0)
	if added <= 0.0:
		return {}
	return {
		"key": StringName("stove:%s" % String(id)),
		"kind": &"stove",
		"copy": "Added fuel · %s" % _label(payload, "Stove"),
		"amount": "+%s" % _format_duration(added),
		"icon_id": StringName(payload.get("icon_id", &"stoke_fire")),
		"added_seconds": added,
		"fuel_seconds": maxf(float(payload.get("fuel_seconds", 0.0)), 0.0),
		"world_position": _position(payload),
		"rejected": false,
	}


func _outage_spec(payload: Dictionary, kind: StringName) -> Dictionary:
	# Only exhaustion is player-actionable. Smothering and weather already read
	# through their own animation/VFX, and surfacing them here would misreport an
	# intentional or forced extinguish as a supply shortage.
	if StringName(payload.get("cause", &"")) != &"empty":
		return {}
	var id := StringName(payload.get("id", &""))
	if id == &"":
		return {}
	var fallback := _kind_label(kind)
	return {
		"key": StringName("outage:%s:%s" % [String(kind), String(id)]),
		"kind": kind,
		"copy": "Went out · %s" % _label(payload, fallback),
		"amount": "",
		"icon_id": StringName(payload.get("icon_id", _icon_for_kind(kind))),
		"cause": &"empty",
		"world_position": _position(payload),
		"rejected": false,
		"hold_seconds": OUTAGE_HOLD_SECONDS,
	}


func _rejected_spec(payload: Dictionary) -> Dictionary:
	var id := StringName(payload.get("id", &"interaction"))
	var kind := StringName(payload.get("kind", &"interaction"))
	var reason := StringName(payload.get("reason", &"unavailable"))
	var label := _label(payload, _kind_label(kind))
	return {
		"key": StringName("rejected:%s" % String(id)),
		"kind": kind,
		"copy": "%s · %s" % [label, _reason_copy(reason)],
		"amount": "",
		"icon_id": StringName(payload.get("icon_id", _icon_for_kind(kind))),
		"reason": reason,
		"world_position": _position(payload),
		"rejected": true,
	}


func _merge_specs(first: Dictionary, second: Dictionary) -> Dictionary:
	var first_is_beacon_fold := first.has("saw_fueled") or first.has("saw_lit")
	var second_is_beacon_fold := second.has("saw_fueled") or second.has("saw_lit")
	if not first_is_beacon_fold or not second_is_beacon_fold:
		return second.duplicate(true)
	var merged := first.duplicate(true)
	merged["saw_fueled"] = bool(first.get("saw_fueled", false)) \
		or bool(second.get("saw_fueled", false))
	merged["saw_lit"] = bool(first.get("saw_lit", false)) \
		or bool(second.get("saw_lit", false))
	for field in ["label", "icon_id", "fuel_seconds", "world_position"]:
		if second.has(field):
			merged[field] = second[field]
	merged["added_seconds"] = maxf(
		float(first.get("added_seconds", 0.0)),
		float(second.get("added_seconds", 0.0))
	)
	return merged


func _finalize_spec(spec: Dictionary) -> Dictionary:
	# Rejections keep the interacted kind (for icon/copy lookup), so `kind ==
	# beacon` alone does not identify a fueled/lit aggregate. Only the domain
	# event normalizer writes these two fold markers.
	if not spec.has("saw_fueled") and not spec.has("saw_lit"):
		return spec
	var result := spec.duplicate(true)
	var label := String(result.get("label", "Beacon"))
	var fueled := bool(result.get("saw_fueled", false))
	var lit := bool(result.get("saw_lit", false))
	if fueled and lit:
		result["copy"] = "Lit · %s" % label
	elif fueled:
		result["copy"] = "Added fuel · %s" % label
	else:
		result["copy"] = "Lit · %s" % label
	var added := float(result.get("added_seconds", 0.0))
	result["amount"] = "+%s" % _format_duration(added) if fueled and added > 0.0 else ""
	return result


func ground_value() -> float:
	if _lighting == null and is_inside_tree():
		var registry := get_node_or_null("/root/ServiceRegistry")
		if registry != null:
			_lighting = registry.get_service(&"lighting")
	if _lighting == null or not _lighting.has_method("active_preset"):
		return UIInk.UNKNOWN_GROUND
	return UIInk.ground_for(_lighting.call("active_preset"))


func _purge_live() -> void:
	var order: Array[StringName] = []
	for key in _live_order:
		var raw: Variant = _live.get(key, null)
		if raw != null and is_instance_valid(raw):
			order.append(key)
		else:
			_live.erase(key)
	_live_order = order


func _tokens() -> UITokens:
	return _layer.tokens() if _layer != null and _layer.has_method("tokens") else null


func _fonts() -> UIFonts:
	return _layer.fonts() if _layer != null and _layer.has_method("fonts") else null


func _canvas_size() -> Vector2:
	if is_inside_tree():
		var viewport := get_viewport()
		if viewport != null:
			return viewport.get_visible_rect().size
	return Vector2(1920.0, 1080.0)


func _hold_seconds(spec: Dictionary) -> float:
	var fallback := REJECT_HOLD_SECONDS \
		if bool(spec.get("rejected", false)) else SUCCESS_HOLD_SECONDS
	var value := float(spec.get("hold_seconds", fallback))
	return maxf(value, 0.0) if is_finite(value) else fallback


func _subscribe() -> void:
	if _bus == null or not is_instance_valid(_bus):
		return
	_bus.subscribe(EVENT_ITEM_PICKED_UP, _on_item_picked_up)
	_bus.subscribe(EVENT_BEACON_FUELED, _on_beacon_fueled)
	_bus.subscribe(EVENT_BEACON_LIT, _on_beacon_lit)
	_bus.subscribe(EVENT_BEACON_EXTINGUISHED, _on_beacon_extinguished)
	_bus.subscribe(EVENT_STOVE_STOKED, _on_stove_stoked)
	_bus.subscribe(EVENT_STOVE_WENT_OUT, _on_stove_went_out)
	_bus.subscribe(EVENT_INTERACTION_REJECTED, _on_interaction_rejected)


func _unsubscribe() -> void:
	if _bus == null or not is_instance_valid(_bus):
		return
	_bus.unsubscribe(EVENT_ITEM_PICKED_UP, _on_item_picked_up)
	_bus.unsubscribe(EVENT_BEACON_FUELED, _on_beacon_fueled)
	_bus.unsubscribe(EVENT_BEACON_LIT, _on_beacon_lit)
	_bus.unsubscribe(EVENT_BEACON_EXTINGUISHED, _on_beacon_extinguished)
	_bus.unsubscribe(EVENT_STOVE_STOKED, _on_stove_stoked)
	_bus.unsubscribe(EVENT_STOVE_WENT_OUT, _on_stove_went_out)
	_bus.unsubscribe(EVENT_INTERACTION_REJECTED, _on_interaction_rejected)


func _on_item_picked_up(payload) -> void:
	ingest(EVENT_ITEM_PICKED_UP, payload)


func _on_beacon_fueled(payload) -> void:
	ingest(EVENT_BEACON_FUELED, payload)


func _on_beacon_lit(payload) -> void:
	ingest(EVENT_BEACON_LIT, payload)


func _on_beacon_extinguished(payload) -> void:
	ingest(EVENT_BEACON_EXTINGUISHED, payload)


func _on_stove_stoked(payload) -> void:
	ingest(EVENT_STOVE_STOKED, payload)


func _on_stove_went_out(payload) -> void:
	ingest(EVENT_STOVE_WENT_OUT, payload)


func _on_interaction_rejected(payload) -> void:
	ingest(EVENT_INTERACTION_REJECTED, payload)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE and what != NOTIFICATION_EXIT_TREE:
		return
	_unsubscribe()
	_pending.clear()
	_pending_order.clear()
	_flush_scheduled = false


static func _label(payload: Dictionary, fallback: String) -> String:
	var label := String(payload.get("label", payload.get("display_name", ""))).strip_edges()
	return fallback if label == "" else label


static func _position(payload: Dictionary) -> Vector3:
	var value: Variant = payload.get("world_position", Vector3.ZERO)
	return value if value is Vector3 and value.is_finite() else Vector3.ZERO


static func _format_duration(seconds: float) -> String:
	var whole := maxi(int(roundf(maxf(seconds, 0.0))), 0)
	return "%d:%02d" % [whole / 60, whole % 60]


static func _kind_label(kind: StringName) -> String:
	match kind:
		&"beacon": return "Beacon"
		&"stove": return "Stove"
		&"pickup": return "Item"
		&"door": return "Door"
	return "Interaction"


static func _icon_for_kind(kind: StringName) -> StringName:
	match kind:
		&"beacon": return &"beacon"
		&"stove": return &"stoke_fire"
		&"door": return &"door"
	return &"interact"


static func _reason_copy(reason: StringName) -> String:
	match reason:
		&"locked": return "Locked"
		&"no_fuel": return "No fuel"
		&"not_enough_fuel": return "Not enough fuel"
		&"no_food": return "No food"
		&"no_water": return "No water"
		&"stale_action": return "Action changed"
		&"full": return "Already full"
	return "Unavailable"
