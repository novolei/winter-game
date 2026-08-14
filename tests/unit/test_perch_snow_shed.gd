extends TestCase

## Snow loosened by a bird belongs to the surface it gripped, not to either
## species.  These checks hold the generic receiver to three contracts before
## the production scene is allowed to use it: it must not invent snow, it must
## resolve a moving declaration on the event frame, and the two authored snowy
## perches must place their declaration directly under a receiver.

const ShedScript := preload("res://src/entities/perch_snow_shed.gd")
const PerchScript := preload("res://src/entities/wildlife/perch_points.gd")
const CelPainterScript := preload("res://src/rendering/cel_painter.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const OPENING_COVER := 0.62
const SHIPPING_ORTHO_HEIGHT_M := 17.0
const SHIPPING_VIEWPORT_HEIGHT_PX := 800.0
const AUTHORED_HOST_CAPACITY := 11

var _owned_nodes: Array[Node] = []


class SnowCover extends RefCounted:
	var amount := 0.0

	func _init(initial: float) -> void:
		amount = initial

	func cover() -> float:
		return amount


func after_each() -> void:
	for node in _owned_nodes:
		if is_instance_valid(node):
			node.free()
	_owned_nodes.clear()


func test_surface_modes_follow_the_snow_that_is_really_on_each_perch() -> void:
	assert_almost_eq(
		ShedScript.surface_amount(0.0, ShedScript.Response.DIRECT_COVER),
		0.0, 0.000001,
		"a bare flat top planned loose snow"
	)
	assert_true(
		ShedScript.surface_amount(OPENING_COVER, ShedScript.Response.DIRECT_COVER) > 0.0,
		"the opening blanket did not reach the power-pole crossarm"
	)
	assert_almost_eq(
		ShedScript.surface_amount(0.50, ShedScript.Response.ROOF_MASS),
		0.0, 0.000001,
		"the roof emitted before its modelled snow mass existed"
	)
	assert_almost_eq(
		ShedScript.surface_amount(OPENING_COVER, ShedScript.Response.ROOF_MASS),
		CelPainterScript.snow_mass(OPENING_COVER), 0.000001,
		"the eave gate drifted from the blend shape the player actually sees"
	)


func test_bare_hosts_are_silent_and_takeoff_is_stronger_than_landing() -> void:
	assert_almost_eq(
		ShedScript.BLOOM_SPATIAL_SCALE, 2.2, 0.000001,
		"the complete hard-grain and powder bloom did not reach the requested 2.2x scale"
	)
	assert_true(
		ShedScript.GRAIN_REACH_MAX - ShedScript.GRAIN_REACH_MIN >= 0.70
			and ShedScript.MIST_REACH_MAX - ShedScript.MIST_REACH_MIN >= 0.60,
		"the per-particle reach collapsed back into a recognisable spherical shell"
	)
	var source := SnowCover.new(0.50)
	var shed = _live_shed(ShedScript.Response.ROOF_MASS, source)
	var perch := {
		"at": Vector3(2.0, 4.0, -1.0),
		"facing": Vector3.RIGHT,
	}
	shed.receive_perch_landing(perch)
	shed.receive_perch_departure(perch)
	var bare: Dictionary = shed.emission_totals()
	assert_eq(int(bare["grains"]), 0, "a roof with no snow mass emitted hard grains")
	assert_eq(int(bare["mist"]), 0, "a roof with no snow mass emitted powder mist")

	source.amount = OPENING_COVER
	shed.receive_perch_landing(perch)
	var after_landing: Dictionary = shed.emission_totals()
	assert_true(int(after_landing["grains"]) > 0, "a snowy landing shed no grains")
	assert_true(int(after_landing["mist"]) > 0, "a snowy landing raised no powder")
	shed.receive_perch_departure(perch)
	var after_takeoff: Dictionary = shed.emission_totals()
	assert_true(
		int(after_takeoff["grains"]) - int(after_landing["grains"])
			> int(after_landing["grains"]),
		"wing wash did not shed more hard snow than the feet landing"
	)
	assert_true(
		int(after_takeoff["mist"]) - int(after_landing["mist"])
			> int(after_landing["mist"]),
		"wing wash did not raise more snow mist than the feet landing"
	)


func test_a_run_uses_its_live_anchor_and_local_facing_after_the_host_moves() -> void:
	var source := SnowCover.new(OPENING_COVER)
	var shed = _live_shed(ShedScript.Response.ROOF_MASS, source)
	shed.position = Vector3(7.0, 1.5, -4.0)
	shed.rotation.y = 0.28
	var perches: PerchPoints = PerchScript.new()
	perches.kind = PerchPoints.Kind.RUN
	perches.run_from = Vector3(-3.8, 3.03, 3.85)
	perches.run_to = Vector3(0.2, 3.03, 3.85)
	perches.spacing_m = 1.1
	shed.add_child(perches)
	var perch: Dictionary = perches.perches()[0]
	var stale: Vector3 = perch["at"]

	shed.position += Vector3(1.2, 0.3, -0.7)
	shed.rotation.y += 0.44
	var placed := perches.placement()
	var live: Vector3 = placed * (perch["local"] as Vector3)
	shed.receive_perch_departure(perch)
	assert_true(stale.distance_to(live) > 0.5, "the fixture did not expose stale world-position use")
	assert_almost_eq(
		shed.last_burst_position().distance_to(live), 0.0, 0.00001,
		"the burst stayed where the eave was when the perch was sampled"
	)
	var axes: Array[Vector3] = shed.last_burst_axes()
	assert_eq(axes.size(), 3, "the receiver did not publish its resolved surface frame")
	if axes.size() != 3:
		return
	var expected_along := placed.basis * (perch["local_facing"] as Vector3)
	var expected_up := placed.basis.y.normalized()
	expected_along = (expected_along - expected_up * expected_along.dot(expected_up)).normalized()
	assert_true(
		axes[2].dot(expected_along) > 0.999,
		"a RUN along local +X was treated like a stretched wire along local -Z"
	)
	assert_almost_eq(axes[0].dot(axes[1]), 0.0, 0.0001, "side and up are not orthogonal")
	assert_almost_eq(axes[0].dot(axes[2]), 0.0, 0.0001, "side and run are not orthogonal")
	assert_almost_eq(axes[1].dot(axes[2]), 0.0, 0.0001, "up and run are not orthogonal")
	var local_burst: Vector3 = shed.global_transform.affine_inverse() * live
	assert_true(
		shed.visibility_bounds().has_point(local_burst),
		"the offset eave burst is alive but culled outside its emitter-local AABB"
	)


func test_burst_directions_fill_a_compact_sphere_instead_of_fanning_one_way() -> void:
	var summed := Vector3.ZERO
	var min_side := INF
	var max_side := -INF
	var min_up := INF
	var max_up := -INF
	var min_along := INF
	var max_along := -INF
	var samples := 24
	for index in range(samples):
		var radial: Vector3 = ShedScript.spherical_direction(
			index, samples, 0.137, Vector3.RIGHT, Vector3.UP, Vector3.FORWARD
		)
		summed += radial
		min_side = minf(min_side, radial.dot(Vector3.RIGHT))
		max_side = maxf(max_side, radial.dot(Vector3.RIGHT))
		min_up = minf(min_up, radial.dot(Vector3.UP))
		max_up = maxf(max_up, radial.dot(Vector3.UP))
		min_along = minf(min_along, radial.dot(Vector3.FORWARD))
		max_along = maxf(max_along, radial.dot(Vector3.FORWARD))
	assert_true(
		summed.length() / float(samples) < 0.01,
		"the stratified sphere retained a one-way drift"
	)
	assert_true(min_side < -0.9 and max_side > 0.9, "the burst missed one side of the perch")
	assert_true(min_up < -0.9 and max_up > 0.9, "the burst flattened into a horizontal ring")
	assert_true(min_along < -0.9 and max_along > 0.9, "the burst missed the front or back of the perch")


func test_the_shared_buffers_and_grains_survive_the_shipping_widest_view() -> void:
	var shed = _live_shed(
		ShedScript.Response.DIRECT_COVER, SnowCover.new(OPENING_COVER)
	)
	var strongest_landing: Dictionary = ShedScript.burst_profile(1.0, false)
	var strongest_departure: Dictionary = ShedScript.burst_profile(1.0, true)
	var grains := shed.get_node("PerchSnowGrains") as GPUParticles3D
	var mist := shed.get_node("PerchSnowMist") as GPUParticles3D
	assert_not_null(grains, "the shared hard-snow population was not built")
	assert_not_null(mist, "the shared powder population was not built")
	if grains == null or mist == null:
		return
	var required_grains := AUTHORED_HOST_CAPACITY * (
		int(strongest_landing["grains"]) + int(strongest_departure["grains"])
	)
	var required_mist := AUTHORED_HOST_CAPACITY * (
		int(strongest_landing["mist"]) + int(strongest_departure["mist"])
	)
	assert_true(
		grains.amount >= required_grains,
		"the hard-snow bloom drops a landing tail when both shipped flocks share a host"
	)
	assert_true(
		mist.amount >= required_mist,
		"the powder bloom drops a landing tail when both shipped flocks share a host"
	)
	assert_eq(
		ShedScript.buffer_sizes(11), Vector2i(512, 256),
		"the reusable cache policy cannot carry all eleven wire birds and their tails"
	)
	var grain_motion := grains.process_material as ParticleProcessMaterial
	assert_true(grains.draw_pass_1 is ArrayMesh, "shared hard snow still uses a square QuadMesh")
	assert_true(
		grain_motion.angle_max - grain_motion.angle_min >= 350.0,
		"shared irregular grains lost their random orientation"
	)
	var minimum_pixels := grain_motion.scale_min * SHIPPING_VIEWPORT_HEIGHT_PX \
		/ SHIPPING_ORTHO_HEIGHT_M
	assert_true(
		minimum_pixels >= 2.5,
		"the smallest shed grain is only %.2f px at the shipping 17 m view" % minimum_pixels
	)
	assert_true(
		grain_motion.scale_max / grain_motion.scale_min >= 1.5,
		"hard grains lost their per-particle size variation and read as identical dots"
	)
	var mist_motion := mist.process_material as ParticleProcessMaterial
	assert_true(
		ShedScript.MIST_VISUAL_SCALE >= 2.0
			and mist_motion.scale_min >= 0.16 * 2.0
			and mist_motion.scale_max >= 0.26 * 2.0,
		"the fog discs did not grow to at least twice their accepted size"
	)
	assert_true(
		float(ShedScript.MIST_ALPHA_PROFILE[0]) <= 0.15,
		"the enlarged powder core became a bright round blob instead of thin fog"
	)
	var mist_birth_pixels := mist_motion.scale_min * 0.42 * SHIPPING_VIEWPORT_HEIGHT_PX \
		/ SHIPPING_ORTHO_HEIGHT_M
	assert_true(
		mist_birth_pixels >= 2.5,
		"the powder puff begins at only %.2f px in the shipping 17 m view" % mist_birth_pixels
	)
	assert_true(mist.lifetime < 0.9, "the wing puff lingers as ambient fog")
	var crossarm_perch := {
		"at": Vector3(0.0, 8.5, 0.0),
		"facing": Vector3.FORWARD,
	}
	shed.receive_perch_departure(crossarm_perch)
	var crossarm_local: Vector3 = (
		shed.global_transform.affine_inverse() * Vector3(0.0, 8.5, 0.0)
	)
	assert_true(
		shed.visibility_bounds().has_point(crossarm_local),
		"the 8.5 m crossarm burst is alive but culled outside its emitter-local AABB"
	)


func test_main_routes_the_eave_and_crossarm_through_their_snow_hosts() -> void:
	var main := MAIN_SCENE.instantiate()
	_owned_nodes.append(main)
	var eave_host := main.get_node_or_null("Farmhouse/EaveSnowShed")
	var eave := main.get_node_or_null("Farmhouse/EaveSnowShed/Perches") as PerchPoints
	var crossarm_host := main.get_node_or_null("Farmstead/PowerPole/CrossarmSnowShed")
	var crossarm := main.get_node_or_null(
		"Farmstead/PowerPole/CrossarmSnowShed/Perches"
	) as PerchPoints
	for pair in [[eave_host, eave], [crossarm_host, crossarm]]:
		assert_not_null(pair[0], "a production snowy-perch receiver is missing")
		assert_not_null(pair[1], "a production perch declaration was lost while reparenting")
		if pair[0] == null or pair[1] == null:
			continue
		assert_true(pair[0].has_method(&"receive_perch_landing"), "the direct host cannot receive landings")
		assert_true(pair[0].has_method(&"receive_perch_departure"), "the direct host cannot receive takeoffs")
		assert_true(pair[1].get_parent() == pair[0], "Bird only addresses the declaration's direct parent")
	if eave_host != null and eave != null:
		assert_eq(eave_host.get("snow_response"), ShedScript.Response.ROOF_MASS)
		assert_eq(eave.kind, PerchPoints.Kind.RUN)
		assert_eq(eave.run_from, Vector3(-3.8, 3.03, 3.85), "the eave moved while gaining a host")
		assert_eq(eave.run_to, Vector3(0.2, 3.03, 3.85), "the eave shortened while gaining a host")
	if crossarm_host != null and crossarm != null:
		assert_eq(crossarm_host.get("snow_response"), ShedScript.Response.DIRECT_COVER)
		assert_eq(crossarm.kind, PerchPoints.Kind.POINTS)
		assert_eq(crossarm.points.size(), 5, "the crossarm lost a perch while gaining a host")


func _live_shed(response: int, source: SnowCover):
	var shed = ShedScript.new()
	shed.snow_response = response
	shed.set_snow_source(source)
	shed.prepare_visuals_for_test()
	(Engine.get_main_loop() as SceneTree).root.add_child(shed)
	_owned_nodes.append(shed)
	return shed
