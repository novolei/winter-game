extends Node

## Global publish/subscribe hub. Registered as autoload "EventBus".
##
## Systems never hold references to one another; they publish and subscribe
## here. Deleting any one system must leave the others compiling and passing
## their tests -- that property is what this class exists to protect.

var _subscribers: Dictionary = {}

func subscribe(event: StringName, callback: Callable) -> void:
	if not _subscribers.has(event):
		_subscribers[event] = []
	var list: Array = _subscribers[event]
	if not list.has(callback):
		list.append(callback)

func unsubscribe(event: StringName, callback: Callable) -> void:
	if not _subscribers.has(event):
		return
	var list: Array = _subscribers[event]
	list.erase(callback)
	if list.is_empty():
		_subscribers.erase(event)

func emit_event(event: StringName, payload: Variant = null) -> void:
	if not _subscribers.has(event):
		return
	# Iterate a copy: a callback may subscribe or unsubscribe during dispatch.
	var list: Array = (_subscribers[event] as Array).duplicate()
	for entry in list:
		var callback := entry as Callable
		if not callback.is_valid():
			unsubscribe(event, callback)
			continue
		callback.call(payload)

func subscriber_count(event: StringName) -> int:
	if not _subscribers.has(event):
		return 0
	return (_subscribers[event] as Array).size()

func clear() -> void:
	_subscribers.clear()
