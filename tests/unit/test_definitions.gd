extends TestCase

const StatDefinitionScript := preload("res://src/definitions/stat_definition.gd")
const ThresholdEffectScript := preload("res://src/definitions/threshold_effect.gd")
const WeatherEventDefinitionScript := preload("res://src/definitions/weather_event_definition.gd")
const ItemDefinitionScript := preload("res://src/definitions/item_definition.gd")
const ThreatDefinitionScript := preload("res://src/definitions/threat_definition.gd")
const BeaconDefinitionScript := preload("res://src/definitions/beacon_definition.gd")
const LightingPresetScript := preload("res://src/definitions/lighting_preset.gd")
const DayScheduleScript := preload("res://src/definitions/day_schedule.gd")
const ColorBibleScript := preload("res://src/definitions/color_bible.gd")

const SCRATCH := "user://test_definitions_roundtrip.tres"

func after_each() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))

func _round_trip(resource: Resource) -> Resource:
	var save_error := ResourceSaver.save(resource, SCRATCH)
	assert_eq(save_error, OK, "saving the resource should succeed")
	return ResourceLoader.load(SCRATCH, "", ResourceLoader.CACHE_MODE_IGNORE)

func test_stat_definition_round_trips() -> void:
	var stat = StatDefinitionScript.new()
	stat.id = &"core_temperature"
	stat.initial_value = 1.0
	stat.base_decay_per_second = 0.002
	stat.lethal_at_min = true
	var loaded = _round_trip(stat)
	assert_eq(loaded.id, &"core_temperature", "id should survive save/load")
	assert_almost_eq(loaded.base_decay_per_second, 0.002, 0.00001, "decay rate should survive save/load")
	assert_true(loaded.lethal_at_min, "lethal flag should survive save/load")

func test_stat_definition_holds_threshold_effects() -> void:
	var effect = ThresholdEffectScript.new()
	effect.watch_stat = &"hunger"
	effect.threshold = 0.3
	effect.target_stat = &"core_temperature"
	effect.value = 1.5
	var stat: StatDefinition = StatDefinitionScript.new()
	stat.id = &"core_temperature"
	stat.threshold_effects = [effect]
	var loaded = _round_trip(stat)
	assert_eq(loaded.threshold_effects.size(), 1, "the nested effect should survive save/load")
	assert_eq(loaded.threshold_effects[0].watch_stat, &"hunger", "nested effect fields should survive")

func test_weather_event_definition_round_trips() -> void:
	var event = WeatherEventDefinitionScript.new()
	event.id = &"blizzard"
	event.tell_duration_range = Vector2(20.0, 40.0)
	event.extinguishes_beacons = true
	event.min_beacons_extinguished = 1
	var loaded = _round_trip(event)
	assert_eq(loaded.id, &"blizzard", "id should survive save/load")
	assert_true(loaded.extinguishes_beacons, "beacon flag should survive save/load")
	assert_eq(loaded.min_beacons_extinguished, 1, "beacon count should survive save/load")

func test_weather_event_tell_duration_is_within_spec() -> void:
	var event = WeatherEventDefinitionScript.new()
	assert_almost_eq(event.tell_duration_range.x, 20.0, 0.001, "spec requires a 20-40s tell window")
	assert_almost_eq(event.tell_duration_range.y, 40.0, 0.001, "spec requires a 20-40s tell window")

func test_item_definition_round_trips() -> void:
	var item = ItemDefinitionScript.new()
	item.id = &"split_log"
	item.category = ItemDefinitionScript.Category.FUEL
	item.fuel_value = 180.0
	var loaded = _round_trip(item)
	assert_eq(loaded.id, &"split_log", "id should survive save/load")
	assert_almost_eq(loaded.fuel_value, 180.0, 0.001, "fuel value should survive save/load")

func test_threat_definition_round_trips() -> void:
	var threat: ThreatDefinition = ThreatDefinitionScript.new()
	threat.id = &"bear"
	threat.perception_kinds = [ThreatDefinitionScript.PerceptionKind.SCENT]
	threat.charge_speed = 8.0
	threat.warns_before_charging = true
	threat.first_active_day = 4
	var loaded = _round_trip(threat)
	assert_eq(loaded.id, &"bear", "id should survive save/load")
	assert_eq(loaded.perception_kinds.size(), 1, "perception list should survive save/load")
	assert_true(loaded.warns_before_charging, "warning flag should survive save/load")
	assert_eq(loaded.first_active_day, 4, "spec puts the bear on day 4")

func test_beacon_definition_round_trips() -> void:
	var beacon = BeaconDefinitionScript.new()
	beacon.id = &"church_tower"
	beacon.world_position = Vector3(120.0, 0.0, -85.0)
	beacon.fuel_capacity = 600.0
	var loaded = _round_trip(beacon)
	assert_eq(loaded.id, &"church_tower", "id should survive save/load")
	assert_almost_eq(loaded.world_position.x, 120.0, 0.001, "position should survive save/load")

func test_lighting_preset_round_trips() -> void:
	var preset = LightingPresetScript.new()
	preset.id = &"whiteout"
	preset.fog_density = 0.08
	preset.cel_band_threshold = 0.5
	var loaded = _round_trip(preset)
	assert_eq(loaded.id, &"whiteout", "id should survive save/load")
	assert_almost_eq(loaded.fog_density, 0.08, 0.0001, "fog density should survive save/load")

func test_day_schedule_round_trips() -> void:
	var schedule = DayScheduleScript.new()
	schedule.day_number = 7
	schedule.daylight_seconds = 240.0
	schedule.night_seconds = 660.0
	schedule.forced_weather_event = &"blizzard"
	var loaded = _round_trip(schedule)
	assert_eq(loaded.day_number, 7, "day number should survive save/load")
	assert_almost_eq(loaded.daylight_seconds, 240.0, 0.001, "daylight length should survive save/load")
	assert_eq(loaded.forced_weather_event, &"blizzard", "day 7 forces the storm")

func test_color_bible_asset_has_twelve_colors() -> void:
	var bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(bible, "the palette asset must exist at res://data/palette/color_bible.tres")
	assert_eq(bible.all_colors().size(), 12, "the palette is exactly 12 colors")
	assert_eq(bible.warm_tones.size(), 3, "exactly 3 of them are warm")

func test_color_bible_recognises_a_palette_color() -> void:
	var bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(bible.contains(Color("#8FB0D8")), "the brightest snow tone is in the palette")
	assert_true(bible.contains(Color("#FFB257")), "the amber window tone is in the palette")

func test_color_bible_rejects_an_off_palette_color() -> void:
	var bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_false(bible.contains(Color("#00FF00")), "pure green is not in the palette")
	assert_false(bible.contains(Color("#FFFFFF")), "pure white is not in the palette")

func test_color_bible_identifies_warm_tones() -> void:
	var bible = ResourceLoader.load("res://data/palette/color_bible.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(bible.is_warm(Color("#FFB257")), "amber is a warm tone")
	assert_false(bible.is_warm(Color("#8FB0D8")), "snow is not a warm tone")
