extends Node

## Indirection layer between systems and the singletons they use.
## Registered as autoload "ServiceRegistry".
##
## Resolving collaborators through a registry, rather than by reaching for a
## global by name, is what lets a test for one system substitute a stand-in
## and run without booting all the others.

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
