extends TestCase

## A wire has its own snow geometry because a seven-centimetre cable cannot
## receive the broad terrain snow shader without turning into broken dashes.
## Pure checks pin the physical scales, and two small live instances prove the
## manual particle receiver's snow gate and current-perch hand-off headlessly.

const WireSnowScript := preload("res://src/entities/wire_snow.gd")
const PerchScript := preload("res://src/entities/wildlife/perch_points.gd")
const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")
const CelPainterScript := preload("res://src/rendering/cel_painter.gd")
const WIRE_MODEL := preload("res://assets/models/props/power_wire.glb")
const PRIMARY_SNOW_SCENE := preload("res://scenes/effects/snow_near.tscn")
const PALETTE := preload("res://data/palette/color_bible.tres")

const FULL_TRAVEL := Vector3(0.132, 0.042, 0.021)
## The accepted single-sided sheet immediately before the owner's additional
## 10% reduction. Keeping that cross-section here turns "10%" into a measured
## relationship rather than another pair of visually plausible constants.
const PREVIOUS_ROOT_X_M := -0.025
const PREVIOUS_THIN_LIP_X_M := 0.073
const PREVIOUS_FULL_LIP_X_M := 0.094

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


func test_the_cap_grows_continuously_from_the_shared_cover() -> void:
	assert_almost_eq(WireSnowScript.cap_height(0.0), 0.0, 0.000001, "a bare world left snow on the wire")
	assert_true(
		WireSnowScript.cap_height(0.62) > 0.0,
		"the opening accumulation cover did not create visible wire snow"
	)
	assert_true(
		WireSnowScript.cap_height(0.95) > WireSnowScript.cap_height(0.62),
		"a deepening storm did not thicken the wire's settled crown"
	)
	assert_true(
		WireSnowScript.cap_lip_x(0.95) > WireSnowScript.cap_lip_x(0.10),
		"cover depth did not broaden the one-sided snow lip while leaving the dark wire alone"
	)
	assert_true(
		WireSnowScript.cover_rebuild_step() <= 1.0 / 255.0 + 0.000001,
		"the wire held several visible weather buckets before redrawing its snow crown"
	)


func test_settled_cover_is_one_continuous_top_ribbon_instead_of_dashes() -> void:
	for index in range(20):
		assert_true(
			WireSnowScript.drift_is_occupied(index, 0.62),
			"opening cover left a dashed gap at top-ribbon section %d" % index
		)
	assert_false(
		WireSnowScript.drift_is_occupied(0, 0.0),
		"a bare wire still carried the continuous snow ribbon"
	)
	var wire = _live_wire(0.62)
	var cap := wire.get_node("SnowCaps") as MeshInstance3D
	var arrays: Array = (cap.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_eq(normals.size(), vertices.size(), "the crown omitted the face normals its cel snow requires")
	var upward := 0
	for normal in normals:
		if normal.dot(Vector3.UP) > 0.85:
			upward += 1
	assert_true(upward >= 4, "the continuous crown has no upward-facing lit snow sheet")


func test_the_crown_reaches_both_ends_of_the_real_wire() -> void:
	var wire := _live_imported_wire(0.62)
	var dark_mesh := _dark_wire_mesh(wire)
	var cap := wire.get_node("SnowCaps") as MeshInstance3D
	assert_not_null(dark_mesh, "the shipped wire root stopped being its real mesh")
	assert_not_null(cap, "the shipped wire did not build its snow crown")
	if dark_mesh == null or cap == null:
		return
	var wire_box: AABB = AssetProbeScript._placed(wire, dark_mesh) * dark_mesh.mesh.get_aabb()
	var cap_box: AABB = AssetProbeScript._placed(wire, cap) * cap.mesh.get_aabb()
	assert_almost_eq(
		cap_box.position.z, wire_box.position.z, 0.0001,
		"snow began %.3f m short of the far wire end" % absf(cap_box.position.z - wire_box.position.z)
	)
	assert_almost_eq(
		cap_box.end.z, wire_box.end.z, 0.0001,
		"snow stopped %.3f m short of the near wire end" % absf(cap_box.end.z - wire_box.end.z)
	)


func test_the_visible_crown_overhangs_only_one_side_of_the_real_wire() -> void:
	var wire := _live_imported_wire(0.62)
	var dark_mesh := _dark_wire_mesh(wire)
	var cap := wire.get_node("SnowCaps") as MeshInstance3D
	assert_not_null(dark_mesh, "the shipped wire root stopped being its real mesh")
	assert_not_null(cap, "the shipped wire did not build its snow crown")
	if dark_mesh == null or cap == null:
		return
	var wire_box: AABB = AssetProbeScript._placed(wire, dark_mesh) * dark_mesh.mesh.get_aabb()
	var cap_box: AABB = AssetProbeScript._placed(wire, cap) * cap.mesh.get_aabb()
	var left_overhang := maxf(wire_box.position.x - cap_box.position.x, 0.0)
	var right_overhang := maxf(cap_box.end.x - wire_box.end.x, 0.0)
	assert_true(
		minf(left_overhang, right_overhang) <= 0.01,
		"snow still overhung both sides of the cable (left %.3f m, right %.3f m)"
			% [left_overhang, right_overhang]
	)
	assert_true(
		maxf(left_overhang, right_overhang) >= 0.035,
		"the retained side lost the broad snow lip requested for visible depth"
	)
	assert_true(
		maxf(left_overhang, right_overhang) <= 0.060,
		"the retained side ignored the requested 30%% width reduction"
	)
	assert_true(
		absf(left_overhang - right_overhang) >= 0.035,
		"the crown remained a symmetric pair of snow lines instead of one side"
	)
	var arrays: Array = (cap.mesh as ArrayMesh).surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for normal in normals:
		assert_true(
			normal.dot(Vector3.UP) > 0.999,
			"a downward/sideways crown face can shade into a second grey snow line: %s" % normal
		)


func test_the_one_sided_sheet_is_exactly_ten_percent_narrower_than_the_accepted_version() -> void:
	for cover in [0.62, 1.0]:
		var amount := smoothstep(0.035, 1.0, cover)
		var previous_lip := lerpf(PREVIOUS_THIN_LIP_X_M, PREVIOUS_FULL_LIP_X_M, amount)
		var previous_width := previous_lip - PREVIOUS_ROOT_X_M
		var wire = _live_wire(cover)
		var cap := wire.get_node("SnowCaps") as MeshInstance3D
		var current_width := cap.mesh.get_aabb().size.x
		assert_almost_eq(
			current_width / previous_width, 0.90, 0.0001,
			"cover %.2f changed the accepted wire snow width by %.1f%% instead of -10%%"
				% [cover, (current_width / previous_width - 1.0) * 100.0]
		)


func test_wire_snow_uses_the_main_falling_flake_colour_without_changing_roofs() -> void:
	var primary_snow = PRIMARY_SNOW_SCENE.instantiate()
	_owned_nodes.append(primary_snow)
	primary_snow._ready()
	var flake_surface := primary_snow.draw_pass_1.surface_get_material(0) as StandardMaterial3D
	assert_not_null(flake_surface, "the main falling-snow layer stopped publishing its flake material")
	if flake_surface == null:
		return
	var falling := flake_surface.albedo_color
	var falling_opaque := Color(falling.r, falling.g, falling.b, 1.0)
	var wire = _live_wire(0.62)
	var cap := wire.get_node("SnowCaps") as MeshInstance3D
	var actual := cap.material_override as ShaderMaterial
	var expected := CelPainterScript.new().material_for(PALETTE.snow_tones[0])
	assert_not_null(actual, "wire snow stopped using a world cel material")
	if actual == null:
		return
	assert_eq(actual.shader.resource_path, expected.shader.resource_path)
	for uniform in [
		"band_threshold", "band_softness", "light_tint",
	]:
		assert_eq(
			actual.get_shader_parameter(uniform), expected.get_shader_parameter(uniform),
			"wire snow drifted from roof snow at shader uniform %s" % uniform
		)
	assert_eq(
		actual.get_shader_parameter("lit_color"), falling_opaque,
		"the wire crown did not use the colour of the main falling flakes"
	)
	assert_eq(
		actual.get_shader_parameter("shade_color"), falling_opaque,
		"the wire crown shaded back into a different colour than the falling flakes"
	)
	assert_almost_eq(
		float(actual.get_shader_parameter("snow_receptivity")), 0.0, 0.0001,
		"a mesh made entirely of snow received a second dark accumulation layer"
	)
	assert_eq(
		expected.get_shader_parameter("shade_color"), PALETTE.snow_tones[3],
		"the wire-specific brightening accidentally changed ordinary roof snow"
	)
	var grains := wire.find_child("BirdSnowShed", true, false) as GPUParticles3D
	var mist := wire.find_child("BirdSnowMist", true, false) as GPUParticles3D
	assert_not_null(grains, "wire snow stopped building its hard-grain pool")
	assert_not_null(mist, "wire snow stopped building its powder-mist pool")
	if grains == null or mist == null:
		return
	var grain_mesh := grains.draw_pass_1 as ArrayMesh
	assert_not_null(grain_mesh, "hard grains fell back to a square QuadMesh")
	if grain_mesh == null:
		return
	var grain_surface := grain_mesh.surface_get_material(0) as StandardMaterial3D
	var grain_colour := grain_surface.albedo_color
	assert_eq(
		Color(grain_colour.r, grain_colour.g, grain_colour.b, 1.0), falling_opaque,
		"bird-shed grains fell back to the dark base snow instead of the main flake colour"
	)
	var mist_quad := mist.draw_pass_1 as QuadMesh
	var mist_surface := mist_quad.material as StandardMaterial3D
	var mist_texture := mist_surface.albedo_texture as GradientTexture2D
	var mist_colour: Color = mist_texture.gradient.colors[0]
	assert_eq(
		Color(mist_colour.r, mist_colour.g, mist_colour.b, 1.0), falling_opaque,
		"bird-shed powder fell back to the dark base snow instead of the main flake colour"
	)
	assert_true(
		mist_colour.a <= 0.15,
		"the enlarged wire powder became a bright round blob instead of thin fog"
	)


func test_the_crown_overlaps_the_real_wire_instead_of_floating_above_it() -> void:
	var wire := _live_imported_wire(0.62)
	var dark_mesh := _dark_wire_mesh(wire)
	var cap := wire.get_node("SnowCaps") as MeshInstance3D
	assert_not_null(dark_mesh, "the shipped wire root stopped being its real mesh")
	assert_not_null(cap, "the shipped wire did not build its snow crown")
	if dark_mesh == null or cap == null:
		return
	var wire_box: AABB = AssetProbeScript._placed(wire, dark_mesh) * dark_mesh.mesh.get_aabb()
	var cap_box: AABB = AssetProbeScript._placed(wire, cap) * cap.mesh.get_aabb()
	var overlap := wire_box.end.y - cap_box.position.y
	assert_true(
		overlap >= 0.01,
		"the snow crown only touched the real wire by %.3f m and can rasterise as a floating line"
			% overlap
	)
	assert_true(cap_box.intersects(wire_box), "the one-sided snow surface no longer intersects the cable")
	assert_true(cap_box.end.y > wire_box.end.y, "the crown was buried completely inside the wire")


func test_a_birds_clear_patch_stays_point_four_metres_on_short_and_long_wires() -> void:
	for span_length_m in [8.0, 34.0]:
		var physical_width: float = WireSnowScript.clearance_fraction(float(span_length_m)) \
			* float(span_length_m)
		assert_almost_eq(
			physical_width, 0.40, 0.00001,
			"a %.1f m wire turned one bird's patch into %.3f m" % [span_length_m, physical_width]
		)
	assert_almost_eq(
		WireSnowScript.bird_clearance_metres(), 0.40, 0.00001,
		"the authored bird patch left the requested 0.35-0.45 m range"
	)


func test_takeoff_is_stronger_and_wider_than_landing_but_bare_wire_is_silent() -> void:
	var landing: Dictionary = WireSnowScript.burst_profile(0.62, false)
	var takeoff: Dictionary = WireSnowScript.burst_profile(0.62, true)
	assert_true(
		int(landing["grains"]) >= 14 and int(landing["mist"]) >= 5,
		"opening-storm landing burst stayed too sparse at the widest gameplay framing"
	)
	assert_true(
		int(takeoff["grains"]) >= 24 and int(takeoff["mist"]) >= 8,
		"opening-storm wing wash stayed too sparse at the widest gameplay framing"
	)
	assert_true(int(takeoff["grains"]) > int(landing["grains"]), "take-off did not shed more hard grains")
	assert_true(int(takeoff["mist"]) > int(landing["mist"]), "wing wash did not raise more soft powder")
	assert_true(float(takeoff["width_m"]) > float(landing["width_m"]), "take-off fan was not wider")
	assert_true(float(takeoff["speed_m_s"]) > float(landing["speed_m_s"]), "take-off was not stronger")
	var amount := smoothstep(0.035, 1.0, 0.62)
	assert_almost_eq(
		float(landing["width_m"]), lerpf(0.22, 0.32, amount) * 2.2, 0.000001,
		"the hard-grain and powder landing bloom did not reach the requested 2.2x scale"
	)
	assert_almost_eq(
		float(takeoff["width_m"]), lerpf(0.48, 0.70, amount) * 2.2, 0.000001,
		"the hard-grain and powder takeoff bloom did not reach the requested 2.2x scale"
	)
	var bare: Dictionary = WireSnowScript.burst_profile(0.0, true)
	assert_eq(int(bare["grains"]), 0, "bare wire planned grain particles")
	assert_eq(int(bare["mist"]), 0, "bare wire planned powder mist")


func test_a_live_bare_wire_accepts_neither_particles_nor_a_clear_patch() -> void:
	var wire = _live_wire(0.0)
	wire.receive_perch_landing({"at": Vector3(2.0, 5.0, 1.0), "local": Vector3(0.0, 0.0, -0.5)})
	wire.receive_perch_departure({"at": Vector3(2.0, 5.0, 1.0), "local": Vector3(0.0, 0.0, -0.5)})
	var totals: Dictionary = wire.emission_totals()
	assert_eq(int(totals["grains"]), 0, "bare wire emitted hard snow grains")
	assert_eq(int(totals["mist"]), 0, "bare wire emitted snow mist")
	assert_almost_eq(
		wire.last_clear_width_metres(), 0.0, 0.00001,
		"bare wire recorded an exposed-snow patch"
	)


func test_live_events_use_the_moving_anchor_and_the_buffer_holds_both_shipped_flocks() -> void:
	var wire = WireSnowScript.new()
	wire.position = Vector3(2.0, 6.0, 0.0)
	wire.scale = Vector3(1.0, 1.0, 34.0)
	var perches: PerchPoints = PerchScript.new()
	perches.kind = PerchPoints.Kind.SPAN
	perches.spacing_m = 3.0
	wire.add_child(perches)
	var perch: Dictionary = perches.perches()[0]
	var stale_at: Vector3 = perch["at"]
	wire.position += FULL_TRAVEL
	wire.set("_snow", SnowCover.new(0.62))
	wire.prepare_visuals_for_test()
	(Engine.get_main_loop() as SceneTree).root.add_child(wire)
	_owned_nodes.append(wire)

	wire.receive_perch_landing(perch)
	var landing_totals: Dictionary = wire.emission_totals()
	var current_at: Vector3 = perches.placement() * (perch["local"] as Vector3)
	assert_true(stale_at.distance_to(current_at) > 0.1, "the fixture did not move enough to expose stale world-at use")
	assert_almost_eq(
		wire.last_burst_position().distance_to(current_at), 0.0, 0.00001,
		"landing particles stayed at the wire's old sampled position"
	)
	assert_almost_eq(
		wire.last_clear_width_metres(), 0.40, 0.00001,
		"the live 34 m span did not cut the authored physical hand-width"
	)
	var cap := wire.get_node("SnowCaps") as MeshInstance3D
	var arrays: Array = (cap.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var perch_fraction := -(perch["local"] as Vector3).z
	var visible_before := -INF
	var visible_after := INF
	for vertex in vertices:
		var vertex_fraction := -vertex.z
		if vertex_fraction <= perch_fraction:
			visible_before = maxf(visible_before, vertex_fraction)
		if vertex_fraction >= perch_fraction:
			visible_after = minf(visible_after, vertex_fraction)
	var rendered_gap_m := (visible_after - visible_before) * 34.0
	assert_almost_eq(
		rendered_gap_m, 0.40, 0.0001,
		"the rendered crown quantised the 0.40 m patch into a %.3f m segment gap" % rendered_gap_m
	)

	wire.receive_perch_departure(perch)
	var both_totals: Dictionary = wire.emission_totals()
	assert_true(
		int(both_totals["grains"]) - int(landing_totals["grains"]) > int(landing_totals["grains"]),
		"the live take-off did not emit more grains than the landing"
	)
	assert_true(
		int(both_totals["mist"]) - int(landing_totals["mist"]) > int(landing_totals["mist"]),
		"the live wing wash did not emit more mist than the landing"
	)
	var strongest: Dictionary = WireSnowScript.burst_profile(1.0, true)
	var grains := wire.find_child("BirdSnowShed", true, false) as GPUParticles3D
	var mist := wire.find_child("BirdSnowMist", true, false) as GPUParticles3D
	assert_not_null(grains, "wire snow stopped building its hard-grain pool")
	assert_not_null(mist, "wire snow stopped building its powder-mist pool")
	if grains == null or mist == null:
		return
	assert_true(
		grains.is_set_as_top_level() and mist.is_set_as_top_level(),
		"the particle pools inherited the wire's long-span scale and stretched a local puff into a line"
	)
	assert_true(
		grains.visibility_aabb.has_point(current_at)
			and mist.visibility_aabb.has_point(current_at),
		"the detached world-space pools culled the live contact point"
	)
	var strongest_landing: Dictionary = WireSnowScript.burst_profile(1.0, false)
	# The production scene has five crows and six pigeons sharing this receiver.
	# A quick landing-to-startle can leave both populations alive at once, so the
	# pool must cover both tails rather than silently dropping the last birds.
	var simultaneous_birds := 11
	assert_true(
		grains.amount >= (
			int(strongest["grains"]) + int(strongest_landing["grains"])
		) * simultaneous_birds,
		"grain buffer silently drops late birds when the crow and pigeon flocks depart together"
	)
	assert_true(
		mist.amount >= (
			int(strongest["mist"]) + int(strongest_landing["mist"])
		) * simultaneous_birds,
		"mist buffer silently drops late birds when the crow and pigeon flocks depart together"
	)
	assert_true(mist.lifetime < 1.0, "wing powder lingered as ambient fog instead of a short puff")


func test_bird_snow_particles_remain_readable_at_the_default_widest_framing() -> void:
	var wire = _live_wire(0.62)
	var grains := wire.find_child("BirdSnowShed", true, false) as GPUParticles3D
	var mist := wire.find_child("BirdSnowMist", true, false) as GPUParticles3D
	assert_not_null(grains, "wire snow stopped building its hard-grain pool")
	assert_not_null(mist, "wire snow stopped building its powder-mist pool")
	if grains == null or mist == null:
		return
	var grain_motion := grains.process_material as ParticleProcessMaterial
	var grain_mesh := grains.draw_pass_1 as ArrayMesh
	assert_not_null(grain_mesh, "hard grains fell back to square billboards")
	if grain_mesh != null:
		var grain_arrays: Array = grain_mesh.surface_get_arrays(0)
		var grain_vertices: PackedVector3Array = grain_arrays[Mesh.ARRAY_VERTEX]
		var grain_normals: PackedVector3Array = grain_arrays[Mesh.ARRAY_NORMAL]
		var grain_indices: PackedInt32Array = grain_arrays[Mesh.ARRAY_INDEX]
		assert_true(grain_vertices.size() > 4, "the irregular snow shard has only a quad silhouette")
		var first_cross := (
			grain_vertices[grain_indices[1]] - grain_vertices[grain_indices[0]]
		).cross(grain_vertices[grain_indices[2]] - grain_vertices[grain_indices[0]])
		assert_true(
			first_cross.dot(Vector3.BACK) < -0.01
				and grain_normals[grain_indices[0]].dot(Vector3.BACK) > 0.99,
			"the irregular billboard is back-face culled instead of facing the camera"
		)
		var shortest := INF
		var longest := 0.0
		for vertex in grain_vertices:
			if vertex.length_squared() <= 0.000001:
				continue
			shortest = minf(shortest, vertex.length())
			longest = maxf(longest, vertex.length())
		assert_true(longest - shortest > 0.04, "the shard perimeter became a regular polygon")
	assert_true(
		grain_motion.angle_max - grain_motion.angle_min >= 350.0,
		"irregular grains no longer begin at random orientations"
	)
	var mist_motion := mist.process_material as ParticleProcessMaterial
	assert_true(
		mist_motion.scale_min >= 0.16 * 2.0 and mist_motion.scale_max >= 0.26 * 2.0,
		"wire powder discs did not grow to at least twice their accepted size"
	)
	# Camera framing is a vertical orthographic span: world metres * viewport
	# pixels / 17 m. The smallest visible hard grain and the mist's authored
	# initial 42% scale both need to clear the project's 2.5 px readability floor.
	var widest_vertical_m := 17.0
	var reference_height_px := 800.0
	assert_true(
		grain_motion.scale_min * reference_height_px / widest_vertical_m >= 2.5,
		"the smallest hard grain fell below 2.5 px at the default widest framing"
	)
	assert_true(
		grain_motion.scale_max / grain_motion.scale_min >= 1.5,
		"hard grains lost their per-particle size variation and read as identical dots"
	)
	assert_true(
		mist_motion.scale_min * 0.42 * reference_height_px / widest_vertical_m >= 2.5,
		"the powder puff began below 2.5 px at the default widest framing"
	)


func _live_wire(cover: float):
	var wire = WireSnowScript.new()
	wire.set("_snow", SnowCover.new(cover))
	wire.prepare_visuals_for_test()
	wire.call("_set_cover", cover, true)
	(Engine.get_main_loop() as SceneTree).root.add_child(wire)
	_owned_nodes.append(wire)
	return wire


func _live_imported_wire(cover: float) -> Node3D:
	var wire := WIRE_MODEL.instantiate() as Node3D
	wire.set_script(WireSnowScript)
	wire.set("_snow", SnowCover.new(cover))
	wire.call("prepare_visuals_for_test")
	wire.call("_set_cover", cover, true)
	(Engine.get_main_loop() as SceneTree).root.add_child(wire)
	_owned_nodes.append(wire)
	return wire


func _dark_wire_mesh(wire: Node3D) -> MeshInstance3D:
	for node in wire.find_children("*", "MeshInstance3D", true, false):
		if node.name != &"SnowCaps":
			return node as MeshInstance3D
	return null
