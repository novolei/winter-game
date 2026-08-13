extends SceneTree

## Phase-B capture probe for the opening mature-snow field.  It prints values
## that can be attached to a visual capture: replay stability, recenter
## stability, open-snow spread, and the protected first-day corridor.  It does
## not mutate a save or start weather.

const SnowFieldScript := preload("res://src/systems/snow_field.gd")
const RunBootScript := preload("res://src/systems/run_boot.gd")
const SnowFieldTests := preload("res://tests/unit/test_snow_field.gd")
const RunBootTests := preload("res://tests/unit/test_run_boot.gd")

const SEED_A := 1729
const SEED_B := 8191
const SNOW_SHADER_PATH := "res://src/rendering/snow_ground.gdshader"
const REPLAY_TOLERANCE_M := 0.0001
const PROTECTED_ROUTE_TOLERANCE_M := 0.001
const MINIMUM_OPEN_DELTA_M := 0.015

var _ran := false


# Tests that exercise ServiceRegistry need a live root tree.  Under --script
# that is only true on the first process tick, not in _initialize().
func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run_probe()
	return true


func _run_probe() -> void:
	var first: SnowField = SnowFieldScript.new()
	var second: SnowField = SnowFieldScript.new()
	var replay: SnowField = SnowFieldScript.new()
	first.set_run_seed(SEED_A)
	second.set_run_seed(SEED_B)
	replay.set_run_seed(SEED_A)
	first.build_at(Vector3.ZERO)
	second.build_at(Vector3.ZERO)
	replay.build_at(Vector3(31.0, 0.0, -22.0))

	var open_delta := 0.0
	for x in range(-48, 49, 4):
		for z in range(-48, 49, 4):
			var spot := Vector3(float(x), 0.0, float(z))
			open_delta = maxf(open_delta, absf(first.depth_at(spot) - second.depth_at(spot)))

	var route_delta := 0.0
	for route in _safe_routes():
		for index in range(route.size() - 1):
			var from: Vector3 = route[index]
			var to: Vector3 = route[index + 1]
			var steps := maxi(int(ceilf(from.distance_to(to) / 0.5)), 1)
			for step in range(steps + 1):
				var spot := from.lerp(to, float(step) / float(steps))
				route_delta = maxf(route_delta, absf(first.depth_at(spot) - second.depth_at(spot)))

	var rebuild_delta := 0.0
	# This rectangle is inside both the origin window and the separately built
	# window below, so it proves absolute-world replay rather than edge clamping.
	for x in range(-20, 45, 11):
		for z in range(-40, 35, 11):
			var spot := Vector3(float(x), 0.0, float(z))
			rebuild_delta = maxf(rebuild_delta, absf(first.depth_at(spot) - replay.depth_at(spot)))

	var replay_spot := Vector3(-20.0, 0.0, 20.0)
	var before := first.depth_at(replay_spot)
	first.follow(Vector3(37.0, 0.0, 28.0))
	var after := first.depth_at(replay_spot)

	var boot = RunBootScript.new()
	boot.run_seed = SEED_A
	var boot_seed_stable := boot.current_run_seed() == SEED_A and boot.current_run_seed() == SEED_A
	var shader: Shader = ResourceLoader.load(SNOW_SHADER_PATH, "Shader", ResourceLoader.CACHE_MODE_IGNORE)
	var shader_has_mature_layer := shader != null and _shader_has_uniform(shader, &"mature_snow") \
		and _shader_has_uniform(shader, &"mature_variation_m")
	var unit_contracts_pass := _run_unit_contracts()
	print("run-seed snow probe")
	print("  seed A/B: %d / %d" % [SEED_A, SEED_B])
	print("  open snow max delta: %.4f m" % open_delta)
	print("  protected route max delta: %.4f m" % route_delta)
	print("  recenter replay at (%.1f, %.1f): %.4f -> %.4f m" % [
		replay_spot.x, replay_spot.z, before, after,
	])
	print("  same-seed rebuilt window max delta: %.4f m" % rebuild_delta)
	print("  explicit RunBoot seed stable: %s" % boot_seed_stable)
	print("  rendering mature-layer uniforms present: %s" % shader_has_mature_layer)
	print("  focused unit contracts passed: %s" % unit_contracts_pass)
	var passed := open_delta >= MINIMUM_OPEN_DELTA_M \
		and route_delta <= PROTECTED_ROUTE_TOLERANCE_M \
		and absf(after - before) <= REPLAY_TOLERANCE_M \
		and rebuild_delta <= REPLAY_TOLERANCE_M \
		and boot_seed_stable \
		and shader_has_mature_layer \
		and unit_contracts_pass
	if not passed:
		push_error("run-seed snow probe did not meet its deterministic/safety contract")
	first.free()
	second.free()
	replay.free()
	boot.free()
	quit(0 if passed else 1)


func _shader_has_uniform(shader: Shader, wanted: StringName) -> bool:
	for uniform in shader.get_shader_uniform_list():
		if StringName(uniform.get("name", &"")) == wanted:
			return true
	return false


## Runs precisely the Phase-B regression methods through the real TestCase
## lifecycle.  This remains a focused proof while the shared full suite is
## intentionally deferred until external ignored-art imports are stable.
func _run_unit_contracts() -> bool:
	var checks := [
		{"script": SnowFieldTests, "method": &"test_a_run_seed_replays_the_same_open_snow_after_a_recentre"},
		{"script": SnowFieldTests, "method": &"test_the_registered_run_owner_injects_the_seed_before_the_field_builds"},
		{"script": SnowFieldTests, "method": &"test_the_same_run_seed_rebuilds_the_same_open_snow_field"},
		{"script": SnowFieldTests, "method": &"test_different_run_seeds_change_only_open_snow"},
		{"script": SnowFieldTests, "method": &"test_run_seed_does_not_change_the_authored_first_day_safe_routes"},
		{"script": RunBootTests, "method": &"test_an_explicit_run_seed_is_stable_for_the_whole_boot"},
		{"script": RunBootTests, "method": &"test_an_unset_run_seed_is_minted_once"},
	]
	var passed := true
	for check in checks:
		var test_case = check["script"].new()
		test_case.reset_failures()
		test_case.before_each()
		test_case.call(check["method"])
		test_case.after_each()
		var failures: Array[String] = test_case.failures()
		if test_case.assertion_count() == 0:
			failures.append("no assertions executed")
		if failures.is_empty():
			print("  PASS  %s :: %s" % [check["script"].resource_path.get_file(), check["method"]])
			continue
		passed = false
		for failure in failures:
			push_error("%s :: %s -- %s" % [check["script"].resource_path, check["method"], failure])
	return passed


func _safe_routes() -> Array:
	return [
		[Vector3.ZERO, Vector3(14.8, 0.0, -10.8)],
		_road_route(),
		[
			Vector3(2.7, 0.0, -25.6),
			Vector3(4.6, 0.0, -22.2),
			Vector3(4.85, 0.0, -18.16),
		],
		_yard_route(),
		_east_trail(),
		_well_trail(),
	]


func _road_route() -> Array:
	return [
		Vector3(45.0, 0.0, -59.0), Vector3(30.0, 0.0, -46.0), Vector3(20.0, 0.0, -37.0),
		Vector3(11.0, 0.0, -29.5), Vector3(2.7, 0.0, -25.6), Vector3(-9.0, 0.0, -28.5),
		Vector3(-24.0, 0.0, -34.0), Vector3(-41.0, 0.0, -40.0),
	]


func _yard_route() -> Array:
	return [
		Vector3(4.2, 0.0, -20.6), Vector3(6.4, 0.0, -16.4),
		Vector3(10.6, 0.0, -12.4), Vector3(14.4, 0.0, -9.6),
	]


func _east_trail() -> Array:
	return [
		Vector3(16.5, 0.0, -8.5), Vector3(24.0, 0.0, 3.0),
		Vector3(30.0, 0.0, 13.0), Vector3(37.2, 0.0, 24.9),
	]


func _well_trail() -> Array:
	return [
		Vector3(13.5, 0.0, -8.0), Vector3(8.6, 0.0, -0.4), Vector3(4.4, 0.0, 3.2),
		Vector3(-1.0, 0.0, 10.5), Vector3(-4.6, 0.0, 17.5),
	]
