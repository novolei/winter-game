extends TestCase

const EventBusScript := preload("res://src/core/event_bus.gd")

class Probe extends Node:
	var payloads: Array = []
	func on_event(payload) -> void:
		payloads.append(payload)

class SelfUnsubscribingProbe extends Node:
	var bus
	var calls := 0
	func handle_once(_payload) -> void:
		calls += 1
		bus.unsubscribe(&"test.event", handle_once)

func test_subscriber_receives_payload() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	bus.emit_event(&"test.event", 42)
	assert_eq(probe.payloads.size(), 1, "subscriber should be called once")
	assert_eq(probe.payloads[0], 42, "payload should arrive intact")
	probe.free()
	bus.free()

func test_unsubscribe_stops_delivery() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	bus.unsubscribe(&"test.event", probe.on_event)
	bus.emit_event(&"test.event", 1)
	assert_true(probe.payloads.is_empty(), "unsubscribed callback must not be called")
	probe.free()
	bus.free()

func test_emitting_with_no_subscribers_is_safe() -> void:
	var bus = EventBusScript.new()
	bus.emit_event(&"nobody.listening", 1)
	assert_eq(bus.subscriber_count(&"nobody.listening"), 0, "unknown event should report zero subscribers")
	bus.free()

func test_duplicate_subscribe_delivers_once() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	bus.subscribe(&"test.event", probe.on_event)
	bus.emit_event(&"test.event", 1)
	assert_eq(probe.payloads.size(), 1, "subscribing twice must not double-deliver")
	probe.free()
	bus.free()

func test_freed_subscriber_is_pruned() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"test.event", probe.on_event)
	probe.free()
	bus.emit_event(&"test.event", 1)
	assert_eq(bus.subscriber_count(&"test.event"), 0, "a callback on a freed object must be pruned, not crash")
	bus.free()

func test_clear_removes_every_subscription() -> void:
	var bus = EventBusScript.new()
	var probe := Probe.new()
	bus.subscribe(&"a", probe.on_event)
	bus.subscribe(&"b", probe.on_event)
	bus.clear()
	assert_eq(bus.subscriber_count(&"a"), 0, "clear must drop subscriptions for a")
	assert_eq(bus.subscriber_count(&"b"), 0, "clear must drop subscriptions for b")
	probe.free()
	bus.free()

func test_callback_may_unsubscribe_itself_during_dispatch() -> void:
	var bus = EventBusScript.new()
	var once := SelfUnsubscribingProbe.new()
	once.bus = bus
	var other := Probe.new()
	bus.subscribe(&"test.event", once.handle_once)
	bus.subscribe(&"test.event", other.on_event)
	bus.emit_event(&"test.event", 1)
	assert_eq(once.calls, 1, "the self-unsubscribing handler should run once")
	assert_eq(other.payloads.size(), 1, "the other subscriber must still receive this dispatch")
	bus.emit_event(&"test.event", 2)
	assert_eq(once.calls, 1, "after unsubscribing itself it must not run again")
	assert_eq(other.payloads.size(), 2, "the remaining subscriber still receives later events")
	once.free()
	other.free()
	bus.free()
