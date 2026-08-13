class_name SettingsStore
extends RefCounted

## The pause menu settings' home on disk. Static, because the menu, the UI
## layer and future consumers all read the same three values and none of them
## should own the others. ConfigFile, not Resource serialization: a player can
## hand-edit it, and a corrupt file is dropped wholesale back to defaults.

const DEFAULT_PATH := "user://ui_settings.cfg"
const SECTION := "accessibility"

static var _values: Dictionary = {}
static var _path := DEFAULT_PATH
static var _loaded := false

## Reads the file. Missing or corrupt is a legal, silent zero -- the defaults
## in the catalog are the fallback, and the player never sees an error.
static func load_from(path := DEFAULT_PATH) -> int:
	_path = path
	_values = {}
	_loaded = true
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return 0
	if not file.has_section(SECTION):
		# A valid file that never heard of us (or a corrupt one that parsed
		# to nothing) is still a silent zero, not an engine error.
		return 0
	var count := 0
	for key in file.get_section_keys(SECTION):
		_values[StringName(key)] = float(file.get_value(SECTION, key, 0.0))
		count += 1
	return count

static func value(id: StringName, fallback: float) -> float:
	if not _loaded:
		load_from()
	return float(_values.get(id, fallback))

static func store(id: StringName, new_value: float) -> void:
	if not _loaded:
		load_from()
	_values[id] = new_value
	var file := ConfigFile.new()
	# Merge whatever is on disk so a hand edit to another key survives.
	file.load(_path)
	file.set_value(SECTION, String(id), new_value)
	file.save(_path)

## Test seam: drops the static state so the next value() re-reads from disk.
static func reset() -> void:
	_values = {}
	_path = DEFAULT_PATH
	_loaded = false
