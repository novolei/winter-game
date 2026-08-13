class_name InteractionDirector
extends Node

## The sole owner of the world's interact input.
##
## World entities publish value-only offers while the player is inside their
## Area3D. This node chooses one offer by actor-to-anchor distance and publishes
## one command for one press. Entities still validate the command before they
## mutate their own state; the director never holds or invokes a live target.

const EVENT_OFFER_ENTERED := &"interaction.offer_entered"
const EVENT_OFFER_CHANGED := &"interaction.offer_changed"
const EVENT_OFFER_EXITED := &"interaction.offer_exited"
const EVENT_FOCUS_CHANGED := &"interaction.focus_changed"
const EVENT_ACTIVATED := &"interaction.activated"
const EVENT_REJECTED := &"interaction.rejected"
const PromptScript := preload("res://src/ui/interaction_prompt.gd")
const FOCUS_SWITCH_MARGIN_M := 0.20

@export var interact_action: StringName = &"interact"
@export var occupant_service: StringName = &"player"

var _bus = null
var _registry = null
var _occupant: Node3D = null
var _offers: Dictionary = {}
var _focused: StringName = &""
var _layer: UILayer = null
var _prompt: Control = null
var _prompt_revision := 0
var _hold_elapsed := 0.0
var _activation_latched := false


func _ready() -> void:
	if _bus == null:
		set_event_bus(get_node_or_null("/root/EventBus"))
	_layer = get_parent() as UILayer
	# A child's _ready() runs before its parent's. Building UILayer here mutates
	# that parent while SceneTree is still attaching its children, so finish on
	# the deferred boundary after UILayer._ready() has built the shared UI stack.
	call_deferred("_finish_ready_after_parent")


func _finish_ready_after_parent() -> void:
	if not is_inside_tree():
		return
	if _layer != null and _layer.tokens() == null:
		_layer.build()
	_resolve_occupant()
	reconsider()


func _exit_tree() -> void:
	_dismiss_prompt()
	_disconnect_bus()
	_offers.clear()
	_focused = &""


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_disconnect_bus()


func set_event_bus(bus) -> void:
	if bus == _bus:
		_connect_bus()
		return
	_disconnect_bus()
	_bus = bus
	_connect_bus()


func set_occupant(node: Node3D) -> void:
	if node != _occupant:
		_hold_elapsed = 0.0
		_activation_latched = false
	_occupant = node
	reconsider()


func offer_count() -> int:
	return _offers.size()


func focused_id() -> StringName:
	return _focused


func focused_offer() -> Dictionary:
	if _focused == &"" or not _offers.has(_focused):
		return {}
	return (_offers[_focused] as Dictionary).duplicate(true)


func prompt_revision() -> int:
	return _prompt_revision


func hold_progress() -> float:
	if _focused == &"" or not _offers.has(_focused):
		return 0.0
	var offer: Dictionary = _offers[_focused]
	var duration := float(offer.get("hold_seconds", 0.0))
	if duration <= 0.0:
		return 1.0
	return clampf(_hold_elapsed / duration, 0.0, 1.0)


func reconsider() -> void:
	_resolve_occupant()
	# Once a hold has begun, the player has committed to the pictured offer.
	# Two wandering pigeons can exchange "nearest" by a few centimetres; letting
	# that steal focus would empty the ring even though neither bird left view.
	if (_hold_elapsed > 0.0 or _activation_latched) and _focused != &"" \
			and _offers.has(_focused) \
			and _offer_meets_facing(_offers[_focused] as Dictionary):
		return
	var next: StringName = &""
	var best_distance := INF
	for raw_id in _offers:
		var id := StringName(raw_id)
		var offer: Dictionary = _offers[id]
		if not _offer_meets_facing(offer):
			continue
		var distance := _distance_to_offer(offer)
		if distance < best_distance - 0.0001:
			best_distance = distance
			next = id
		elif is_equal_approx(distance, best_distance) and (next == &"" or String(id) < String(next)):
			next = id
	# Before a hold starts, keep a small spatial margin too. Exact ties still use
	# the deterministic id rule above; near-ties keep the existing prompt stable.
	if next != _focused and _focused != &"" and _offers.has(_focused):
		var focused_offer: Dictionary = _offers[_focused]
		if _offer_meets_facing(focused_offer):
			var focused_distance := sqrt(maxf(_distance_to_offer(focused_offer), 0.0))
			var next_distance := sqrt(maxf(best_distance, 0.0))
			if not is_equal_approx(next_distance, focused_distance) \
					and next_distance + FOCUS_SWITCH_MARGIN_M >= focused_distance:
				next = _focused
	_set_focus(next)


func activate_focused() -> bool:
	if _focused == &"" or not _offers.has(_focused):
		return false
	var offer: Dictionary = _offers[_focused]
	if not _offer_meets_facing(offer):
		reconsider()
		return false
	if not bool(offer.get("enabled", true)):
		_emit(EVENT_REJECTED, {
			"id": _focused,
			"kind": StringName(offer.get("kind", &"")),
			"verb": String(offer.get("verb", "Use")),
			"label": String(offer.get("label", "")),
			"reason": StringName(offer.get("reason", &"unavailable")),
			"world_position": offer.get("world_position", Vector3.ZERO),
		})
		return false
	var payload := {
		"id": _focused,
		"kind": StringName(offer.get("kind", &"")),
		"world_position": offer.get("world_position", Vector3.ZERO),
		"target_position": offer.get("target_position", offer.get("world_position", Vector3.ZERO)),
	}
	_emit(EVENT_ACTIVATED, payload)
	if _layer != null and _layer.audio() != null:
		_layer.audio().play(&"ui.ripple")
	# The command may synchronously withdraw or rewrite the selected offer.
	reconsider()
	return true


## Deterministic input seam shared by runtime and unit tests. Hold offers charge
## while the action remains pressed; a completion cannot repeat until release.
## Tap offers preserve the existing press-edge behaviour.
func advance_interaction(delta: float, pressed: bool, just_pressed := false) -> bool:
	reconsider()
	if not pressed:
		_activation_latched = false
		_clear_hold_progress()
		return false
	if _focused == &"" or not _offers.has(_focused):
		_clear_hold_progress()
		return false
	if _activation_latched:
		return false

	var offer: Dictionary = _offers[_focused]
	var duration := float(offer.get("hold_seconds", 0.0))
	if duration <= 0.0:
		if not just_pressed:
			return false
		_activation_latched = true
		return activate_focused()

	var step := delta if is_finite(delta) else 0.0
	_hold_elapsed = minf(_hold_elapsed + maxf(step, 0.0), duration)
	_update_prompt_hold_progress()
	if _hold_elapsed + 0.00001 < duration:
		return false
	_activation_latched = true
	return activate_focused()


func _process(delta: float) -> void:
	advance_interaction(
		delta,
		Input.is_action_pressed(interact_action),
		Input.is_action_just_pressed(interact_action)
	)
	_update_prompt_projection()


func _on_offer_entered(payload) -> void:
	_upsert_offer(payload)


func _on_offer_changed(payload) -> void:
	_upsert_offer(payload)


func _on_offer_exited(payload) -> void:
	if not (payload is Dictionary):
		return
	var id := StringName(payload.get("id", &""))
	if id == &"":
		return
	_offers.erase(id)
	reconsider()


func _upsert_offer(payload) -> void:
	if not (payload is Dictionary):
		return
	var id := StringName(payload.get("id", &""))
	var at: Variant = payload.get("world_position", null)
	if id == &"" or not (at is Vector3):
		return
	var hold_seconds := float(payload.get("hold_seconds", 0.0))
	if not is_finite(hold_seconds):
		hold_seconds = 0.0
	var facing_dot_min := float(payload.get("facing_dot_min", -1.0))
	if not is_finite(facing_dot_min):
		facing_dot_min = -1.0
	var clean := {
		"id": id,
		"kind": StringName(payload.get("kind", &"")),
		"verb": String(payload.get("verb", "Use")),
		"label": String(payload.get("label", "")),
		"world_position": at,
		"target_position": payload.get("target_position", at),
		"enabled": bool(payload.get("enabled", true)),
		"reason": StringName(payload.get("reason", &"")),
		"hold_seconds": maxf(hold_seconds, 0.0),
		"facing_dot_min": clampf(facing_dot_min, -1.0, 1.0),
		"guide_line": bool(payload.get("guide_line", false)),
	}
	var was_focused := id == _focused
	var previous: Dictionary = _offers.get(id, {})
	var content_changed := previous.is_empty() or not _same_offer_content(previous, clean)
	var anchor_changed: bool = not previous.is_empty() \
		and previous.get("world_position", Vector3.ZERO) != at
	_offers[id] = clean
	reconsider()
	if was_focused and id == _focused and content_changed:
		_emit(EVENT_FOCUS_CHANGED, focused_offer())
		_rebuild_prompt()
	elif was_focused and id == _focused and anchor_changed:
		_move_prompt_anchor(at)


func _set_focus(value: StringName) -> void:
	if value == _focused:
		return
	_clear_hold_progress()
	_focused = value
	_emit(EVENT_FOCUS_CHANGED, focused_offer() if _focused != &"" else null)
	_rebuild_prompt()


func _rebuild_prompt() -> void:
	_hold_elapsed = 0.0
	_prompt_revision += 1
	_dismiss_prompt()
	if _focused == &"" or _layer == null or not _offers.has(_focused):
		return
	var offer: Dictionary = _offers[_focused]
	var prompt = PromptScript.new()
	if not prompt.build(
		_layer.tokens(),
		_layer.fonts(),
		_input_key_copy(),
		String(offer.get("verb", "Use")),
		String(offer.get("label", ""))
	):
		prompt.free()
		return
	prompt.set_guide_line(bool(offer.get("guide_line", false)))
	prompt.set_hold_progress(
		0.0 if float(offer.get("hold_seconds", 0.0)) > 0.0 else 1.0
	)
	prompt.set_stroke_scale(_layer.stroke_scale())
	prompt.set_world_anchor(offer.get("world_position", Vector3.ZERO))
	prompt.layout_for(get_viewport().get_visible_rect().size)
	_prompt = prompt
	_layer.bloom(prompt)
	_update_prompt_projection()


func _dismiss_prompt() -> void:
	if _prompt == null or not is_instance_valid(_prompt):
		_prompt = null
		return
	if _layer != null:
		_layer.dismiss(_prompt, Breath.Exit.FAST)
	else:
		_prompt.free()
	_prompt = null


func _move_prompt_anchor(value: Vector3) -> void:
	if _prompt == null or not is_instance_valid(_prompt):
		return
	_prompt.set_world_anchor(value)
	_update_prompt_projection()


func _clear_hold_progress() -> void:
	if is_zero_approx(_hold_elapsed):
		_update_prompt_hold_progress()
		return
	_hold_elapsed = 0.0
	_update_prompt_hold_progress()


func _update_prompt_hold_progress() -> void:
	if _prompt == null or not is_instance_valid(_prompt):
		return
	_prompt.set_hold_progress(hold_progress())


func _update_prompt_projection() -> void:
	if _prompt == null or not is_instance_valid(_prompt) or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_prompt.visible = false
		return
	if _prompt.project_world_anchor(camera, get_viewport().get_visible_rect().size) \
			and _layer != null:
		# Projection chooses the new resting point. UILayer owns the Breath offset
		# around that point, so teach it the new home before its next advance()
		# rather than letting it snap the prompt back to the first projected frame.
		_layer.rehome(_prompt, _prompt.position)


func _input_key_copy() -> String:
	for event in InputMap.action_get_events(interact_action):
		if event is InputEventKey and event.physical_keycode == KEY_E:
			return "E"
	return "E"


func _distance_to_offer(offer: Dictionary) -> float:
	var at: Vector3 = offer.get("target_position", offer.get("world_position", Vector3.ZERO))
	if _occupant == null or not is_instance_valid(_occupant):
		return at.length_squared()
	var origin := _occupant.global_position if _occupant.is_inside_tree() else _occupant.position
	return origin.distance_squared_to(at)


func _offer_meets_facing(offer: Dictionary) -> bool:
	var threshold := float(offer.get("facing_dot_min", -1.0))
	if threshold <= -1.0:
		return true
	if _occupant == null or not is_instance_valid(_occupant):
		return false
	var at: Vector3 = offer.get("world_position", Vector3.ZERO)
	var origin := _occupant.global_position if _occupant.is_inside_tree() else _occupant.position
	var toward := at - origin
	toward.y = 0.0
	if toward.length_squared() <= 0.000001:
		return true
	toward = toward.normalized()
	var forward := _interaction_forward()
	return forward != Vector3.ZERO and forward.dot(toward) >= threshold


func _interaction_forward() -> Vector3:
	if _occupant == null or not is_instance_valid(_occupant):
		return Vector3.ZERO
	if _occupant.has_method(&"interaction_forward"):
		var supplied: Variant = _occupant.call(&"interaction_forward")
		if supplied is Vector3:
			var stable := supplied as Vector3
			stable.y = 0.0
			if stable.is_finite() and stable.length_squared() > 0.000001:
				return stable.normalized()
	var basis := _occupant.global_transform.basis \
		if _occupant.is_inside_tree() else _occupant.transform.basis
	var fallback := -basis.z
	fallback.y = 0.0
	if not fallback.is_finite() or fallback.length_squared() <= 0.000001:
		return Vector3.ZERO
	return fallback.normalized()


func _same_offer_content(left: Dictionary, right: Dictionary) -> bool:
	var left_content := left.duplicate(true)
	var right_content := right.duplicate(true)
	left_content.erase("world_position")
	right_content.erase("world_position")
	return left_content == right_content


func _resolve_occupant() -> void:
	if _occupant != null and is_instance_valid(_occupant):
		return
	if not is_inside_tree():
		return
	if _registry == null:
		_registry = get_node_or_null("/root/ServiceRegistry")
	if _registry != null:
		_occupant = _registry.get_service(occupant_service) as Node3D


func _connect_bus() -> void:
	if _bus == null or not is_instance_valid(_bus):
		return
	_bus.subscribe(EVENT_OFFER_ENTERED, _on_offer_entered)
	_bus.subscribe(EVENT_OFFER_CHANGED, _on_offer_changed)
	_bus.subscribe(EVENT_OFFER_EXITED, _on_offer_exited)


func _disconnect_bus() -> void:
	if _bus == null or not is_instance_valid(_bus):
		_bus = null
		return
	_bus.unsubscribe(EVENT_OFFER_ENTERED, _on_offer_entered)
	_bus.unsubscribe(EVENT_OFFER_CHANGED, _on_offer_changed)
	_bus.unsubscribe(EVENT_OFFER_EXITED, _on_offer_exited)
	_bus = null


func _emit(event: StringName, payload) -> void:
	if _bus != null and is_instance_valid(_bus):
		_bus.emit_event(event, payload)
