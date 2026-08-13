class_name AccessibilityCatalog
extends Resource

## The settings the pause menu offers, in display order.

const CATALOG_PATH := "res://data/ui/accessibility_settings.tres"

@export var entries: Array[AccessibilitySetting] = []

func find(setting_id: StringName) -> AccessibilitySetting:
	for entry in entries:
		if entry != null and entry.id == setting_id:
			return entry
	return null
