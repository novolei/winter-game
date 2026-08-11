extends Node

## Indirection layer between systems and the singletons they use.
## Registered as autoload "ServiceRegistry".
##
## Autoloads are not instantiated when Godot runs with --script, which is
## how the test suite runs. Resolving collaborators through this registry
## is what lets a test for one system run without booting all the others.

var _services: Dictionary = {}

func register(key: StringName, service: Object) -> void:
	_services[key] = service

func get_service(key: StringName) -> Object:
	return _services.get(key, null)

func has(key: StringName) -> bool:
	return _services.has(key)

func unregister(key: StringName) -> void:
	_services.erase(key)

func clear() -> void:
	_services.clear()
