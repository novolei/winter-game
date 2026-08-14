extends TestCase

## The seven-day fuel economy is one equation spread across authored Resources:
## route pickups are its income; beacon burn rates, night lengths and stove
## recipes are its costs. Keep the assertion here at those data seams so tuning
## any one of them has to preserve a finishable run rather than a copied total.

const MAIN_SCENE := "res://scenes/main.tscn"
const STOVE_SCENE := "res://scenes/entities/stove/stove.tscn"


func _resource_files(directory_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return result
	var names := directory.get_files()
	names.sort()
	for name in names:
		if name.ends_with(".tres"):
			result.append(directory_path.path_join(name))
	return result


func _beacons() -> Dictionary:
	var result: Dictionary = {}
	for path in _resource_files("res://data/beacons"):
		var definition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if definition is BeaconDefinition:
			result[definition.id] = definition
	return result


func _schedules() -> Array[DaySchedule]:
	var result: Array[DaySchedule] = []
	for path in _resource_files("res://data/schedule"):
		var schedule = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if schedule is DaySchedule:
			result.append(schedule)
	result.sort_custom(func(first: DaySchedule, second: DaySchedule) -> bool:
		return first.day_number < second.day_number
	)
	return result


func _items() -> Dictionary:
	var result: Dictionary = {}
	for path in _resource_files("res://data/items"):
		var definition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if definition is ItemDefinition:
			result[definition.id] = definition
	return result


func _starting_stove_fuel() -> float:
	var packed := ResourceLoader.load(MAIN_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return 0.0
	var state := packed.get_state()
	for node_index in range(state.get_node_count()):
		var instance := state.get_node_instance(node_index) as PackedScene
		if instance == null or instance.resource_path != STOVE_SCENE:
			continue
		for property_index in range(state.get_node_property_count(node_index)):
			if state.get_node_property_name(node_index, property_index) == &"starting_fuel_seconds":
				return float(state.get_node_property_value(node_index, property_index))
	return 0.0


func _stove_burn_rate() -> float:
	var packed := ResourceLoader.load(STOVE_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return 0.0
	var stove := packed.instantiate()
	var rate := float(stove.get(&"burn_rate"))
	stove.free()
	return rate


func test_every_scheduled_beacon_resolves_and_agrees_on_its_unlock_day() -> void:
	var beacons := _beacons()
	var scheduled: Dictionary = {}
	for schedule in _schedules():
		if schedule.beacon_unlocked == &"":
			continue
		assert_true(
			beacons.has(schedule.beacon_unlocked),
			"day %d names missing beacon '%s'" % [schedule.day_number, schedule.beacon_unlocked]
		)
		if not beacons.has(schedule.beacon_unlocked):
			continue
		assert_false(
			scheduled.has(schedule.beacon_unlocked),
			"beacon '%s' is scheduled more than once" % schedule.beacon_unlocked
		)
		scheduled[schedule.beacon_unlocked] = schedule.day_number
		var beacon: BeaconDefinition = beacons[schedule.beacon_unlocked]
		assert_eq(
			beacon.unlock_day,
			schedule.day_number,
			"schedule and beacon disagree on when '%s' unlocks" % schedule.beacon_unlocked
		)
	assert_eq(scheduled.size(), beacons.size(), "not every shipped beacon has one scheduled unlock")


func test_pickups_cover_the_no_wind_run_and_leave_one_coal_for_the_storm() -> void:
	var items := _items()
	var supply := 0.0
	for path in _resource_files("res://data/route_nodes"):
		var node = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not (node is SurvivalRouteNodeDefinition) or not node.is_pickup():
			continue
		assert_true(items.has(node.item_id), "%s names an item outside the catalogue" % node.id)
		if items.has(node.item_id):
			var item: ItemDefinition = items[node.item_id]
			supply += item.fuel_value * float(node.item_count)

	var schedules := _schedules()
	var day_starts: Dictionary = {}
	var total_run := 0.0
	var total_nights := 0.0
	for schedule in schedules:
		day_starts[schedule.day_number] = total_run
		total_run += schedule.daylight_seconds + schedule.night_seconds
		total_nights += schedule.night_seconds

	var beacon_cost := 0.0
	for beacon in _beacons().values():
		assert_true(day_starts.has(beacon.unlock_day), "%s unlocks outside the run" % beacon.id)
		if day_starts.has(beacon.unlock_day):
			beacon_cost += (total_run - float(day_starts[beacon.unlock_day])) * beacon.burn_rate

	var snow: ItemDefinition = items.get(&"snow", null)
	var stew: ItemDefinition = items.get(&"canned_stew", null)
	var coal: ItemDefinition = items.get(&"coal", null)
	assert_not_null(snow, "the daily melt cost has no snow definition")
	assert_not_null(stew, "the daily cooking cost has no stew definition")
	assert_not_null(coal, "the storm reserve has no coal-sized unit")
	if snow == null or stew == null or coal == null:
		return
	var daily_chores := 2.0 * snow.heat_seconds + 2.0 * stew.heat_seconds
	var stove_cost := maxf(
		total_nights * _stove_burn_rate() - _starting_stove_fuel(),
		0.0
	)
	var baseline := beacon_cost + stove_cost + daily_chores * float(schedules.size())
	var reserve := supply - baseline
	assert_true(
		reserve >= coal.fuel_value,
		"pickups bank %.0fs against a %.0fs baseline, leaving %.0fs rather than one %.0fs storm reserve"
			% [supply, baseline, reserve, coal.fuel_value]
	)
