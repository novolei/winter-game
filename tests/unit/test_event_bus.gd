extends TestCase

const EventBusScript := preload("res://src/core/event_bus.gd")

class Probe extends Node:
	var payloads: Array = []
	func on_event(payload) -> void:
		payloads.append(payload)

func test_subscriber_receives_payload() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	bus.emit_event(&"test.event", 42)
	assert_eq(probe.payloads.size(), 1, "subscriber should be called once")
	assert_eq(probe.payloads[0], 42, "payload should arrive intact")
	probe.free()

func test_unsubscribe_stops_delivery() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	bus.unsubscribe(&"test.event", probe.on_event)
	bus.emit_event(&"test.event", 1)
	assert_true(probe.payloads.is_empty(), "unsubscribed callback must not be called")
	probe.free()

func test_emitting_with_no_subscribers_is_safe() -> void:
	var bus = EventBusScript.new()
	bus.emit_event(&"nobody.listening", 1)
	assert_eq(bus.subscriber_count(&"nobody.listening"), 0, "unknown event should report zero subscribers")

func test_duplicate_subscribe_delivers_once() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	bus.subscribe(&"test.event", probe.on_event)
	bus.emit_event(&"test.event", 1)
	assert_eq(probe.payloads.size(), 1, "subscribing twice must not double-deliver")
	probe.free()

func test_freed_subscriber_is_pruned() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	probe.free()
	bus.emit_event(&"test.event", 1)
	assert_eq(bus.subscriber_count(&"test.event"), 0, "a callback on a freed object must be pruned, not crash")

func test_clear_removes_every_subscription() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"a", probe.on_event)
	bus.subscribe(&"b", probe.on_event)
	bus.clear()
	assert_eq(bus.subscriber_count(&"a"), 0, "clear must drop subscriptions for a")
	assert_eq(bus.subscriber_count(&"b"), 0, "clear must drop subscriptions for b")
	probe.free()
