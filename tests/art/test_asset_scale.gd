extends TestCase

## THE GATE THAT SAYS A MODEL IS THE SIZE IT IS SUPPOSED TO BE.
##
## ---------------------------------------------------------------------------
## THE DEFECT, MEASURED, BEFORE ANY OF IT WAS IMPORTED
## ---------------------------------------------------------------------------
## `Docs/asset-inventory-low-poly-animals.md` section 1.1, on the animal package
## this project's wildlife comes out of:
##
##     The pack is authored at three different scales and Godot normalises none.
##     A wolf arrives 15 mm long, imports clean, and passes every art gate.
##
## Every gate this suite has says yes to that wolf. `test_topology.gd` likes its
## triangle count. `test_palette.gd` likes its colour. `test_import_wiring.gd`
## likes its `.import`. A take census finds all five of its animations and they
## all play. The only symptom is a creature nobody can see, which reads as a
## spawn bug and sends the next person into a file that has nothing wrong with
## it. Ten more animals were about to arrive out of that package.
##
## ---------------------------------------------------------------------------
## THE EXPECTATION IS DATA, NOT A TABLE IN THIS FILE
## ---------------------------------------------------------------------------
## Binding rule 4: a new animal must be a `.tres`, not a `.gd` change. So the
## bands live in `data/scale/`, are written by `tools/generate_asset_scales.gd`
## from REAL-WORLD sizes -- a rock dove's wingspan, a grizzly's length -- and
## adding an eleventh animal is one file in `data/`.
##
## Resolution is longest-match, the same rule `test_topology.gd::_budget_for`
## uses for triangle budgets: `res://assets/models/characters` is the class band
## and `.../characters/pigeon/pigeon.fbx` is that bird's own, and the file beats
## the folder because its `covers` string is longer.
##
## ---------------------------------------------------------------------------
## AND A FLOOR UNDER THE DATA, WHICH IS NOT THE SAME AS TRUSTING IT
## ---------------------------------------------------------------------------
## An asset that matches no band at all is still judged, against SANITY below.
## Otherwise the way to get a wrongly-scaled model past this gate would be to
## forget to write its `.tres` -- and "the gate never saw it" is the failure this
## whole framework exists to end. The class bands mean that in practice nothing
## reaches the sanity band; it is a fuse, and a fuse doing its job never fires.
##
## ---------------------------------------------------------------------------
## HOW BIG A MODEL IS, WHICH IS NOT THE OBVIOUS CALL
## ---------------------------------------------------------------------------
## `AssetProbe.bounds()` measures the mesh boxes AND the bone rest hull and
## takes the larger. That is not caution; it is the only correct answer.
## MEASURED on 4.7.1: `Mesh.get_aabb()` on the four Blender-exported characters
## returns a box in the skin's bind space, which the skeleton scales back up at
## runtime -- the bear reads 0.029 m and the wanderer 0.016 m, which is exactly
## the reading a 15 mm wolf gives, on four assets that are correct and shipped.
## The crow, imported through ufbx rather than Blender, reads its true 0.96 m
## from the same call. A gate built on the mesh box alone would have fired on
## every character in the game and been "fixed" by widening the floor to 10 mm,
## at which point it would pass the wolf.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")
const ScaleScript := preload("res://src/definitions/asset_scale.gd")

## Where the bands live and what the gate walks.
##
## `assets/models` only, deliberately -- NOT `AssetScanner.SCAN_ROOTS`, which
## also holds `res://scenes`. A size band is a fact about an authored asset of a
## known class; a scene's own geometry -- terrain, a level built in place --
## belongs to no class and is legitimately hundreds of metres across. Same call,
## and the same reasoning, as `test_topology.gd` leaving an unbudgeted mesh out
## of scope rather than failing it.
const BAND_ROOT := "res://data/scale"
const MODEL_ROOT := "res://assets/models"

## The floor and ceiling under everything, for an asset no band covers.
##
## A few centimetres to rather larger than a house. Wide enough that it can only
## fire on an asset that is wrong by an order of magnitude, which is precisely
## the defect: the package's three authoring scales differ by 10x and 100x.
const SANITY_SMALLEST_M := 0.02
const SANITY_LARGEST_M := 60.0

## Seeded under user://, outside every scanned root, so the project-wide test
## keeps measuring the project. One folder per shape so each end-to-end test can
## still assert "reported exactly once".
const FIXTURE_ROOT := "user://scale_gate_fixture"
const TINY_ROOT := "user://scale_gate_fixture/tiny"
const TINY_MESH := "user://scale_gate_fixture/tiny/fifteen_millimetres.tres"
const HUGE_ROOT := "user://scale_gate_fixture/huge"
const HUGE_MESH := "user://scale_gate_fixture/huge/four_hundred_metres.tres"
const SCALED_ROOT := "user://scale_gate_fixture/scaled"
const SCALED_SCENE := "user://scale_gate_fixture/scaled/shrunk_by_its_root.tscn"

## What a creature band looks like, for the fixtures. The pigeon's own numbers.
const FIXTURE_SMALLEST := 0.55
const FIXTURE_LARGEST := 0.90


func before_each() -> void:
	for folder in [TINY_ROOT, HUGE_ROOT, SCALED_ROOT]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	ResourceSaver.save(_box(0.015), TINY_MESH)
	ResourceSaver.save(_box(400.0), HUGE_MESH)
	ResourceSaver.save(_scene_shrunk_by_its_root(), SCALED_SCENE)


func after_each() -> void:
	for path in [
		TINY_MESH, HUGE_MESH, SCALED_SCENE,
		TINY_ROOT, HUGE_ROOT, SCALED_ROOT, FIXTURE_ROOT,
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _box(side: float) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(side, side, side)
	return mesh


## A model of the right size whose ROOT NODE is scaled to a hundredth.
##
## This is the shape of the real defect and the reason the fixtures are not all
## loose meshes: `nodes/root_scale` in an `.import` file lands on the root node's
## transform, so the mesh's own AABB is untouched and only the chain above it
## says the asset is 15 mm. A gate that read mesh boxes and ignored node
## transforms would report this fixture as a perfectly good 1 m model.
func _scene_shrunk_by_its_root() -> PackedScene:
	var root := Node3D.new()
	root.name = "Shrunk"
	root.scale = Vector3(0.01, 0.01, 0.01)
	var instance := MeshInstance3D.new()
	instance.name = "Body"
	instance.mesh = _box(0.7)
	root.add_child(instance)
	instance.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	# pack() has copied what it needs; every Node this allocated is freed here on
	# every path (briefing section 2.2).
	root.free()
	return packed


# --- the gate's own body ------------------------------------------------------


## Every band in `data/scale`, loaded.
func _bands() -> Array:
	var found: Array = []
	var dir := DirAccess.open(BAND_ROOT)
	if dir == null:
		return found
	for entry in dir.get_files():
		if not entry.ends_with(".tres"):
			continue
		var band = ResourceLoader.load(BAND_ROOT.path_join(entry))
		if band != null:
			found.append(band)
	return found


## The most specific band covering `path`, or null.
func _band_for(path: String, bands: Array):
	var best = null
	for band in bands:
		if not band.applies_to(path):
			continue
		if best == null or band.specificity() > best.specificity():
			best = band
	return best


## "" when the asset at `path` is a plausible size, or the reason it is not.
##
## Split from the walk so both branches are reachable from a test without a file
## on disk being the wrong size -- the same shape `test_topology.gd::_offenders_in`
## has, and for the same reason.
func _refusal(path: String, measured: Dictionary, bands: Array) -> String:
	if measured["error"] != "":
		return "%s %s" % [path, measured["error"]]
	# Nothing to measure is a real answer, not a zero. The crow's four animation
	# files carry no mesh and no armature at all -- 3ds Max exported the rig as a
	# hierarchy of nulls -- and a gate that judged their empty box against a floor
	# would report four offenders that are exactly as they should be.
	if int(measured["meshes"]) == 0 and int(measured["bones"]) == 0:
		return ""
	var size: Vector3 = measured["size"]
	var band = _band_for(path, bands)
	if band != null:
		var refusal: String = band.refusal(size)
		return "" if refusal == "" else "%s %s" % [path, refusal]
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest < SANITY_SMALLEST_M or longest > SANITY_LARGEST_M:
		return ("%s measures %.4f x %.4f x %.4f m, whose longest side %.4f m is outside the %.3f..%.1f m "
			+ "sanity band every model is held to. No band in %s covers it, so this is the fuse rather "
			+ "than a considered expectation -- write it one.") % [
			path, size.x, size.y, size.z, longest, SANITY_SMALLEST_M, SANITY_LARGEST_M, BAND_ROOT]
	return ""


## The whole walk, with the root as a parameter so the exact production path can
## be aimed at a seeded fixture folder.
func _collect_scale_offenders(root: String, bands: Array) -> PackedStringArray:
	var offenders := PackedStringArray()
	for path in AssetScannerScript.find_files(root, AssetScannerScript.MESH_SUFFIXES):
		var refusal := _refusal(path, AssetProbeScript.bounds(path), bands)
		if refusal != "":
			offenders.append(refusal)
	return offenders


func _fixture_band(covers: String) -> AssetScale:
	var band: AssetScale = ScaleScript.new()
	band.covers = covers
	band.smallest_m = FIXTURE_SMALLEST
	band.largest_m = FIXTURE_LARGEST
	band.reason = "a fixture standing in for a bird."
	return band


# --- the band resource --------------------------------------------------------


func test_a_band_covers_its_own_folder_and_the_files_under_it() -> void:
	var band := _fixture_band("res://assets/models/characters")
	assert_true(band.applies_to("res://assets/models/characters"), "a band must cover the folder it names")
	assert_true(
		band.applies_to("res://assets/models/characters/pigeon/pigeon.fbx"),
		"a band must cover a file under the folder it names"
	)


## The trailing-slash rule, which is the whole reason a sibling folder does not
## inherit somebody else's band. Without it `characters_wip` is judged as a
## creature and reports green having been measured against the wrong numbers.
func test_a_band_does_not_reach_a_sibling_folder_that_merely_starts_the_same() -> void:
	var band := _fixture_band("res://assets/models/characters")
	assert_false(
		band.applies_to("res://assets/models/characters_wip/pigeon.fbx"),
		"the prefix match must be on a path separator"
	)
	assert_false(band.applies_to("res://assets/models/props/power_pole.glb"), "a band must not reach another class")


## An empty `covers` must cover NOTHING. A band saved without its path set would
## otherwise match every asset in the project by prefix and quietly become the
## only expectation any of them is judged against.
func test_a_band_with_no_path_covers_nothing() -> void:
	var band: AssetScale = ScaleScript.new()
	assert_false(band.applies_to("res://assets/models/characters/crow/crow.fbx"), "an unset band must cover nothing")


func test_a_band_refuses_a_model_under_its_floor() -> void:
	var band := _fixture_band("res://assets/models/characters")
	var refusal := band.refusal(Vector3(0.0073, 0.0026, 0.0026))
	assert_true(refusal != "", "a 7 mm bird must be refused")
	assert_true(refusal.contains("0.550"), "the refusal must say what the floor was, got: %s" % refusal)


func test_a_band_refuses_a_model_over_its_ceiling() -> void:
	var band := _fixture_band("res://assets/models/characters")
	assert_true(band.refusal(Vector3(72.67, 26.49, 26.31)) != "", "a 72 m bird must be refused")


func test_a_band_accepts_a_model_inside_it() -> void:
	var band := _fixture_band("res://assets/models/characters")
	assert_eq(band.refusal(Vector3(0.7267, 0.2649, 0.2631)), "", "a rock dove at 0.73 m must pass")


## Exactly at the floor and exactly at the ceiling. A reversed or off-by-one
## comparison passes every other test in this file.
func test_the_band_edges_are_inclusive() -> void:
	var band := _fixture_band("res://assets/models/characters")
	assert_eq(band.refusal(Vector3(FIXTURE_SMALLEST, 0.1, 0.1)), "", "exactly the floor must pass")
	assert_eq(band.refusal(Vector3(FIXTURE_LARGEST, 0.1, 0.1)), "", "exactly the ceiling must pass")


## Longest match wins, so a per-asset band beats its class band. Without this an
## eleventh animal's own numbers would be shadowed by the wide class band that
## exists only so nothing arrives unjudged.
func test_a_files_own_band_beats_the_folders() -> void:
	var wide: AssetScale = ScaleScript.new()
	wide.covers = "res://assets/models/characters"
	wide.smallest_m = 0.08
	wide.largest_m = 4.0
	var tight := _fixture_band("res://assets/models/characters/pigeon/pigeon.fbx")
	var chosen = _band_for("res://assets/models/characters/pigeon/pigeon.fbx", [wide, tight])
	assert_not_null(chosen, "nothing matched at all")
	if chosen == null:
		return
	assert_eq(chosen.covers, tight.covers, "the file's own band must win over the folder's")


# --- the gate, end to end against files on disk -------------------------------


## The 15 mm wolf, in the shape a `.tres` can carry it.
func test_the_gate_finds_a_model_under_its_floor_on_disk() -> void:
	var offenders := _collect_scale_offenders(TINY_ROOT, [_fixture_band(TINY_ROOT)])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the 15 mm mesh must be reported exactly once, got: %s" % report)
	assert_true(report.contains(TINY_MESH), "the report must name the file, got: %s" % report)


func test_the_gate_finds_a_model_over_its_ceiling_on_disk() -> void:
	var offenders := _collect_scale_offenders(HUGE_ROOT, [_fixture_band(HUGE_ROOT)])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the 400 m mesh must be reported exactly once, got: %s" % report)
	assert_true(report.contains(HUGE_MESH), "the report must name the file, got: %s" % report)


## THE ONE THAT MATCHES THE REAL DEFECT. `nodes/root_scale` scales the root node
## and leaves the mesh's own AABB alone, so this fixture is a 0.7 m box inside a
## node scaled to a hundredth. A gate reading mesh boxes without the chain above
## them measures 0.7 m and passes it.
func test_the_gate_sees_a_model_shrunk_by_its_root_node() -> void:
	var offenders := _collect_scale_offenders(SCALED_ROOT, [_fixture_band(SCALED_ROOT)])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "the root-scaled model must be reported exactly once, got: %s" % report)
	assert_true(report.contains(SCALED_SCENE), "the report must name the file, got: %s" % report)


## No band, and the model is absurd. The fuse.
func test_an_unbanded_model_is_still_held_to_the_sanity_floor() -> void:
	var offenders := _collect_scale_offenders(TINY_ROOT, [])
	var report := "; ".join(offenders)
	assert_eq(offenders.size(), 1, "an unbanded 15 mm mesh must still be reported, got: %s" % report)
	assert_true(report.contains("sanity band"), "it must say it fell through to the fuse, got: %s" % report)


## No band, and the model is fine. The fuse must not be a second, tighter gate.
func test_an_unbanded_model_of_a_plausible_size_is_left_alone() -> void:
	var offenders := _collect_scale_offenders(SCALED_ROOT.get_base_dir().path_join("plausible"), [])
	assert_eq(offenders.size(), 0, "a folder with nothing in it cannot produce an offender")
	assert_eq(_refusal("res://made/up.glb", {
		"error": "", "meshes": 1, "bones": 0, "size": Vector3(2.29, 1.43, 0.56),
	}, []), "", "a 2.3 m unbanded model is inside the sanity band and is not this gate's business")


## An asset that never imported loads as null, which is invisible to every gate
## that skips what it cannot read.
func test_an_unloadable_asset_is_an_offender() -> void:
	var path := "res://assets/models/characters/never_imported.fbx"
	var refusal := _refusal(path, {
		"error": "could not be loaded at all", "meshes": 0, "bones": 0, "size": Vector3.ZERO,
	}, [])
	assert_true(refusal != "", "an unloadable asset must be an offender")
	assert_true(refusal.contains(path), "the report must name it, got: %s" % refusal)


## The crow's four animation files carry no mesh and no armature. An empty box
## is not a small model.
func test_a_file_with_no_geometry_is_not_judged_as_a_tiny_one() -> void:
	assert_eq(_refusal("res://assets/models/characters/crow/crow_fly.fbx", {
		"error": "", "meshes": 0, "bones": 0, "size": Vector3.ZERO,
	}, []), "", "an animation-only file has no size and must not be measured against a floor")


# --- the bands as shipped -----------------------------------------------------


func test_the_bands_are_on_disk() -> void:
	var bands := _bands()
	assert_true(
		bands.size() >= 4,
		"only %d band(s) loaded out of %s -- run tools/generate_asset_scales.gd" % [bands.size(), BAND_ROOT]
	)


## Every band names a path that exists. A typo in `covers` makes the band cover
## nothing, and a band covering nothing is indistinguishable from a band that is
## being satisfied -- the gate reports green over an asset class it never judged.
func test_every_band_covers_something_real() -> void:
	var offenders := PackedStringArray()
	for band in _bands():
		var covers: String = band.covers
		if covers == "":
			offenders.append("a band in %s has no `covers` path at all" % BAND_ROOT)
		elif not (FileAccess.file_exists(covers) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(covers))):
			offenders.append("%s is named by a band but is neither a file nor a folder" % covers)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## Every band is the right way up and says why it is what it is.
func test_every_band_is_a_usable_range_with_a_reason() -> void:
	var offenders := PackedStringArray()
	for band in _bands():
		if band.smallest_m <= 0.0 or band.largest_m <= band.smallest_m:
			offenders.append("%s has the impossible range %.3f..%.3f m" % [
				band.covers, band.smallest_m, band.largest_m])
		if String(band.reason).strip_edges() == "":
			offenders.append("%s carries no reason, so a failure cannot tell anyone where its numbers came from" % band.covers)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## Every class of asset the project actually ships is covered by a band, so the
## sanity fuse stays a fuse. Not an offence for an individual asset -- that would
## fire on the first model somebody adds -- but a missing CLASS band means a
## whole folder falls through to numbers nobody chose.
func test_every_asset_class_has_a_band() -> void:
	var bands := _bands()
	var offenders := PackedStringArray()
	for folder in ["buildings", "vegetation", "props", "characters"]:
		var path := MODEL_ROOT.path_join(folder)
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			continue
		if _band_for(path.path_join("anything.glb"), bands) == null:
			offenders.append("%s has no band, so everything in it falls through to the sanity fuse" % path)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The gate must be measuring something. Every other test here would pass just
## as happily against a walk that found no files, a probe that returned nothing,
## or a `bounds()` that had been stubbed -- and the folders are full, so an empty
## result is a broken instrument rather than a clean project.
func test_the_gate_actually_measures_the_models_it_walks() -> void:
	var measured := 0
	for path in AssetScannerScript.find_files(MODEL_ROOT, AssetScannerScript.MESH_SUFFIXES):
		var bounds := AssetProbeScript.bounds(path)
		if bounds["error"] == "" and bounds["size"].length() > 0.0:
			measured += 1
	assert_true(measured >= 10, "only %d model(s) under %s produced a size at all" % [measured, MODEL_ROOT])


## And it must be measuring them CORRECTLY. The crow is the one asset whose real
## size is written down in a shipped report -- 0.960 x 0.567 x 0.294 m, wings
## spread -- so it is the calibration.
func test_the_measurement_agrees_with_the_crow_report_s_own_figure() -> void:
	var bounds := AssetProbeScript.bounds("res://assets/models/characters/crow/crow.fbx")
	assert_eq(bounds["error"], "", "the crow did not load")
	var size: Vector3 = bounds["size"]
	assert_almost_eq(size.x, 0.960, 0.01, "the crow's wingspan measured %.4f m, the W2 report recorded 0.960" % size.x)
	assert_almost_eq(size.y, 0.567, 0.01, "the crow's height measured %.4f m, the W2 report recorded 0.567" % size.y)


## The whole project, on every run. Collected and asserted once after the walk
## rather than per asset: a per-asset assertion in an empty folder executes zero
## assertions, and the runner fails a test that does -- correctly, since it
## cannot tell an empty loop from one a runtime error aborted.
func test_every_model_is_a_plausible_size() -> void:
	var offenders := _collect_scale_offenders(MODEL_ROOT, _bands())
	assert_eq(offenders.size(), 0, "; ".join(offenders))
