extends TestCase

const SwingScript := preload("res://src/entities/tire_swing.gd")
const PendulumScript := preload("res://src/rendering/wind_pendulum.gd")
const SWING_MODEL := "res://assets/models/props/tire_swing.glb"
const WIND_SCENE := "res://scenes/effects/wind.tscn"
const FRAME := 1.0 / 60.0


func test_the_shipped_wind_scene_really_publishes_its_swing_driver_group() -> void:
	var packed := ResourceLoader.load(WIND_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert_not_null(packed, "the wind scene did not load")
	if packed == null:
		return
	var state := packed.get_state()
	var found := false
	for index in state.get_node_count():
		if state.get_node_name(index) != &"TireSwing":
			continue
		found = true
		var groups := state.get_node_groups(index)
		assert_true(&"wind_swing_driver" in groups, "the scene text silently discarded the driver group")
		assert_true(&"wind_consumer" in groups, "wind never reaches the tire pendulum")
	assert_true(found, "the wind scene has no tire pendulum driver")


func test_contact_reaches_the_driver_from_the_actual_wind_scene() -> void:
	var world := Node.new()
	var packed := ResourceLoader.load(WIND_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert_not_null(packed, "the wind scene did not load")
	if packed == null:
		world.free()
		return
	var wind := packed.instantiate()
	var swing := SwingScript.new()
	swing.add_to_group(&"wind_swing")
	world.add_child(wind)
	world.add_child(swing)
	Engine.get_main_loop().root.add_child(world)
	var driver := wind.get_node_or_null("TireSwing")
	assert_not_null(driver, "the actual wind scene has no pendulum driver")
	assert_true(driver != null and driver.is_in_group(&"wind_swing_driver"), "the runtime driver is undiscoverable")
	if driver != null:
		swing.receive_player_impact(Vector3(0.16, 0.0, 0.0))
		driver.call(&"_process", FRAME)
		var tilt := driver.call(&"tilt_of", swing) as Vector2
		assert_true(absf(tilt.x) > 0.001, "the collision relay found no live wind driver")
	Engine.get_main_loop().root.remove_child(world)
	world.free()


func test_the_runtime_swing_derives_a_non_blocking_sensor_from_its_real_tire() -> void:
	var packed := load(SWING_MODEL) as PackedScene
	assert_not_null(packed, "the tire swing model did not import")
	if packed == null:
		return
	var swing := packed.instantiate() as Node3D
	swing.set_script(SwingScript)
	Engine.get_main_loop().root.add_child(swing)
	var sensor: Area3D = swing.call(&"impact_sensor")
	assert_not_null(sensor, "the Jolt-safe impact sensor was not built")
	if sensor != null:
		assert_eq(sensor.collision_layer, 0, "the sensor became a second blocking collider")
		var shape := sensor.get_node_or_null("TireContact") as CollisionShape3D
		assert_not_null(shape, "the sensor did not copy the imported tire shape")
		if shape != null:
			assert_true(shape.shape is SphereShape3D, "the contact area no longer follows the compact tire")
			var physical := swing.call(&"_first_collision_shape", swing) as CollisionShape3D
			assert_true(
				physical != null and (shape.shape as SphereShape3D).radius > (physical.shape as SphereShape3D).radius,
				"the sensor cannot see the body until after Jolt has already resolved the solid contact"
			)
	Engine.get_main_loop().root.remove_child(swing)
	swing.free()


func test_a_deep_snow_walking_bump_still_kicks_the_existing_wind_pendulum() -> void:
	var world := Node.new()
	var driver := PendulumScript.new()
	driver.add_to_group(&"wind_swing_driver")
	var swing := SwingScript.new()
	world.add_child(driver)
	world.add_child(swing)
	Engine.get_main_loop().root.add_child(world)
	# Below the previous 0.35 m/s rejection threshold, representative of a body
	# wading through deep snow rather than running on clear ground.
	swing.receive_player_impact(Vector3(0.16, 0.0, 0.0))
	driver._drive(swing, FRAME, 0.0, deg_to_rad(24.0))
	assert_true(
		absf(driver.tilt_of(swing).x) > 0.001,
		"the slow physical bump never entered the wind pendulum's state"
	)
	Engine.get_main_loop().root.remove_child(world)
	world.free()
