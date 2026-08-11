extends TestCase

const ServiceRegistryScript := preload("res://src/core/service_registry.gd")

class FakeService extends RefCounted:
	var label := "real"

## ServiceRegistry extends Node, which is not reference-counted. Every
## instance a test builds is freed in after_each(), or the suite reports
## leaked ObjectDB instances and the output stops being pristine.
var _registry = null

func after_each() -> void:
	if _registry != null:
		_registry.free()
		_registry = null

func _build():
	_registry = ServiceRegistryScript.new()
	return _registry

func test_registered_service_is_returned() -> void:
	var registry = _build()
	var service := FakeService.new()
	registry.register(&"snow_field", service)
	assert_eq(registry.get_service(&"snow_field"), service, "the registered instance should come back")

func test_unknown_key_returns_null() -> void:
	var registry = _build()
	assert_eq(registry.get_service(&"nothing_here"), null, "an unregistered key should resolve to null")

func test_has_reports_registration() -> void:
	var registry = _build()
	assert_false(registry.has(&"snow_field"), "nothing is registered yet")
	registry.register(&"snow_field", FakeService.new())
	assert_true(registry.has(&"snow_field"), "the key should now be present")

func test_register_replaces_previous_binding() -> void:
	var registry = _build()
	var first := FakeService.new()
	var second := FakeService.new()
	second.label = "fake"
	registry.register(&"snow_field", first)
	registry.register(&"snow_field", second)
	assert_eq(registry.get_service(&"snow_field").label, "fake", "re-registering must replace, so tests can inject fakes")

func test_unregister_removes_the_binding() -> void:
	var registry = _build()
	registry.register(&"snow_field", FakeService.new())
	registry.unregister(&"snow_field")
	assert_false(registry.has(&"snow_field"), "unregister should remove the key")

func test_clear_removes_everything() -> void:
	var registry = _build()
	registry.register(&"a", FakeService.new())
	registry.register(&"b", FakeService.new())
	registry.clear()
	assert_false(registry.has(&"a"), "clear should drop a")
	assert_false(registry.has(&"b"), "clear should drop b")
