class_name AccessibilitySetting
extends Resource

## One row of the pause menu's settings page (UI document section 4.2).
## Adding a setting is a .tres entry, never a .gd change.

@export var id: StringName = &""
@export var label: String = ""
@export var is_toggle := false
@export var minimum := 0.0
@export var maximum := 1.0
@export var step := 0.25
@export var default_value := 0.0

func clamp_value(value: float) -> float:
	return clampf(value, minimum, maximum)

func stepped(value: float, direction: int) -> float:
	if is_toggle:
		return 0.0 if value >= 0.5 else 1.0
	if direction == 0:
		return clamp_value(value)
	return clamp_value(value + step * signf(float(direction)))

func format_value(value: float) -> String:
	if is_toggle:
		return "开" if value >= 0.5 else "关"
	var clamped := clamp_value(value)
	var text := "%.2f" % clamped
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text + "×"

func tick_count() -> int:
	if is_toggle or step <= 0.0:
		return 2
	return int(roundf((maximum - minimum) / step)) + 1

func fraction_of(value: float) -> float:
	if maximum <= minimum:
		return 0.0
	return clampf((clamp_value(value) - minimum) / (maximum - minimum), 0.0, 1.0)
