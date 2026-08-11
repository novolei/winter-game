extends TestCase

## The three threats -- bear, scavenger, zombie -- held to the numbers and the
## properties their task brief set, which the project-wide gates cannot check.
##
## ---------------------------------------------------------------------------
## WHY A FILE OF ITS OWN, WHEN THREE GATES ALREADY SCAN assets/models/
## ---------------------------------------------------------------------------
## Because every one of those gates deliberately looks *away* from these three,
## and a gate that is told to skip something cannot also be the thing that
## proves it is right.
##
##   - `test_palette.gd` and `test_shading_features.gd` skip anything under
##     `AssetScanner.SURFACE_RULE_EXEMPT_ROOTS`. The Art Bible's exception box
##     says characters keep their own PBR maps, so a bear with a normal map is
##     correct and must not be reported.
##   - `test_import_wiring.gd :: test_no_world_model_generates_lods` skips the
##     same list -- it is scoped to *world* models by name and by intent.
##   - `test_topology.gd` does see them, but it is a **per-mesh** gate, and the
##     zombie is three meshes. Body 5,408 + top 1,154 + pants 886 = 7,448, and
##     every one of those passes an 8,000 per-mesh budget on its own even if the
##     asset as a whole were three times over it. That hole is why the farmhouse
##     needed its own test, and it is the same hole here.
##
## So this file asserts the three things the exemptions make invisible: that the
## exemption **covers these folders on purpose**, that the maps the exemption
## exists to protect are actually present, and that auto-LOD is off.
##
## ---------------------------------------------------------------------------
## THE EXEMPTION IS THE POINT, AND IT IS ASSERTED BOTH WAYS
## ---------------------------------------------------------------------------
## `AssetScanner.SURFACE_RULE_EXEMPT_ROOTS` holds `res://assets/models/characters`
## and matches on a trailing slash, so `characters/bear/bear.glb` is already
## exempt without anyone adding a line -- **which is exactly the situation the
## Art Bible warns about**:
##
##     美术门禁必须显式豁免 assets/models/characters/，而不是靠碰巧扫不到它而放行。
##     因错误原因保持沉默的门禁，比会报错的门禁更糟。
##
## An exemption that happens to reach a folder and an exemption that was decided
## for that folder are indistinguishable until someone tightens the prefix match
## -- and then three characters silently start failing rules 8 and 9, or worse,
## get repainted from the 12-colour table and pass everything. So the coverage
## is pinned here by name, with negative controls, rather than left to the
## prefix rule being what it is today.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")

const BEAR := "res://assets/models/characters/bear/bear.glb"
const SCAVENGER := "res://assets/models/characters/scavenger/scavenger.glb"
const ZOMBIE := "res://assets/models/characters/zombie/zombie.glb"

## Art Bible rule 6. Not waived by the exception box, which waives rules 8 and 9
## and says in as many words that the triangle budget still applies.
const CHARACTER_BUDGET := 8000

## Measured after `tools/blender/build_*.py`. **Whole-asset** totals, which is
## the number rule 6 is about and the number no per-mesh gate can produce.
const TRIANGLES := {
	BEAR: 3000,
	SCAVENGER: 7000,
	ZOMBIE: 7448,
}

## How many takes each `.glb` is expected to carry into Godot.
const TAKE_COUNTS := {
	BEAR: 81,
	SCAVENGER: 5,
	ZOMBIE: 12,
}

## The takes GDD section 8 and section 9 name, against the take that serves each.
##
## This is the load-bearing half of the animation inventory: the wave report
## lists all 98, but these are the ones a *design sentence* points at, and a
## re-export that quietly drops one would otherwise be found by the threat AI
## batch rather than here.
##
##   The bear -- "it warns you first, and then it charges. It knocks you down."
##   The zombie -- section 9 builds dread by taking the music away, and the
##   scream is what cuts through the silence.
const REQUIRED_TAKES := {
	BEAR: [
		"Stand_Idle_01",              # the roam it warns you out of
		"Trans_Stand_to_StandHind",   # the warning: rears onto its hind legs
		"Run",                        # the charge
		"Attack_Run_01_AttackF",      # the charge that connects
		"Attack_StandAngry_01_High",  # the blow that knocks the player down
		"Death_Stand_R01",            # after the player shoots
	],
	SCAVENGER: [
		"boxing", "kicking",
		"falling_back_death", "flying_back_death", "knocked_out",
	],
	ZOMBIE: [
		"idle", "walk", "run",
		"scream",                     # GDD section 9's payoff
		"attack",
		"crawl", "crawl_run",
		"death", "dying",
	],
}

const LOD_LINE := "meshes/generate_lods=false"
const PALETTE_WIRING := "import_script/path=\"res://tools/palette_import_materials.gd\""


func _models() -> Array:
	return TRIANGLES.keys()


func _import_text(model_path: String) -> String:
	var path := model_path + ".import"
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## Whole-asset triangles: every mesh in the file, added up.
##
## `Mesh.get_faces()` rather than dividing an index array by three, for the
## reason `test_topology.gd` records at length -- a triangle strip of N vertices
## is N-2 triangles and the division reports a third of that, which is how a
## mesh three times over budget gets waved through.
func _triangles(path: String) -> int:
	var probe := AssetProbeScript.probe(path)
	if probe["error"] != "":
		return -1
	var total := 0
	for entry in probe["meshes"]:
		var mesh: Mesh = entry["resource"]
		total += mesh.get_faces().size() / 3
	return total


## Every take name in the file's AnimationLibrary.
##
## Walks `PackedScene.get_state()` rather than instantiating, so this allocates
## no Node and there is nothing to free -- briefing section 2.2, and the same
## choice `AssetProbe` documents. Godot stores each library as its own
## `libraries/<name>` property, so the value arrives as an AnimationLibrary
## directly; the Dictionary branch is there because that is the shape the
## property has on a hand-built AnimationPlayer, and a walk that only handles
## the shape it saw once is a walk that silently finds nothing later.
func _takes(path: String) -> PackedStringArray:
	var names := PackedStringArray()
	var scene := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		return names
	var state := scene.get_state()
	for node in state.get_node_count():
		for property in state.get_node_property_count(node):
			var value = state.get_node_property_value(node, property)
			if value is AnimationLibrary:
				for take in (value as AnimationLibrary).get_animation_list():
					names.append(take)
			elif value is Dictionary:
				for entry in (value as Dictionary).values():
					if entry is AnimationLibrary:
						for take in (entry as AnimationLibrary).get_animation_list():
							names.append(take)
	return names


## Every BaseMaterial3D on every surface, with a label saying where it came from.
func _surfaces(path: String) -> Array:
	var found := []
	var probe := AssetProbeScript.probe(path)
	if probe["error"] != "":
		return found
	for entry in probe["meshes"]:
		var mesh: Mesh = entry["resource"]
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			if material is BaseMaterial3D:
				found.append(["%s surface %d" % [entry["label"], surface], material])
	return found


func test_every_threat_model_is_on_disk_and_imports() -> void:
	# A model that never imported loads as null, and a null is invisible to
	# every other gate in this suite -- it passes them all by not being there.
	var offenders := PackedStringArray()
	for path in _models():
		var probe := AssetProbeScript.probe(path)
		if probe["error"] != "":
			offenders.append("%s %s" % [path, probe["error"]])
		elif (probe["meshes"] as Array).is_empty():
			offenders.append("%s imported but holds no mesh at all" % path)
	assert_eq(offenders.size(), 0, "; ".join(offenders))


func test_every_threat_model_is_inside_the_character_budget() -> void:
	var offenders := PackedStringArray()
	for path in _models():
		var count := _triangles(path)
		if count < 0:
			offenders.append("%s could not be counted" % path)
		elif count > CHARACTER_BUDGET:
			offenders.append("%s is %d triangles over the whole asset, past rule 6's %d -- re-run its tools/blender/build_*.py with a lower --target" % [path, count, CHARACTER_BUDGET])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The numbers, not just the ceiling.
##
## The budget alone would let a re-export come back at 7,900 triangles and call
## it a pass. These three were each aimed at a specific number for a specific
## reason -- the bear at the reference video's own middle decimation tier, the
## scavenger at the player's density because they stand next to each other --
## and a build that drifts off them is a build worth looking at even though
## nothing is broken.
func test_every_threat_model_landed_on_the_triangle_count_it_was_aimed_at() -> void:
	for path in _models():
		var expected: int = TRIANGLES[path]
		var count := _triangles(path)
		assert_eq(count, expected, "%s is %d triangles, was built at %d" % [path, count, expected])


## The bear specifically: the reference video decimated the same asset to 2,996
## and shipped that, so 3,000 is not a round number someone liked.
func test_the_bear_sits_at_the_reference_video_s_middle_tier() -> void:
	var count := _triangles(BEAR)
	assert_true(
		count > 797 and count < 7508,
		"the bear is %d triangles; the video's three tiers were 7,588 original / 2,996 shipped / 797 heavy, and this is meant to be the middle one" % count
	)
	assert_true(
		absi(count - 2996) <= 300,
		"the bear is %d triangles, which is not within 300 of the video's shipped 2,996" % count
	)


## The whole reason the exception box exists. Rules 8 and 9 strip the world to
## flat palette colour; a character is exempt **so that it can carry its own
## surface** and be picked out of that uniform blue at a glance.
##
## Asserting the exemption without asserting the maps would leave the exemption
## doing nothing: a character whose textures failed to travel through the export
## is flat grey plastic, passes every gate in the suite, and looks like an art
## decision rather than a broken build.
func test_every_threat_surface_carries_the_albedo_the_exemption_exists_for() -> void:
	var offenders := PackedStringArray()
	var seen := 0
	for path in _models():
		for entry in _surfaces(path):
			seen += 1
			var material: BaseMaterial3D = entry[1]
			if material.albedo_texture == null:
				offenders.append("%s: %s has no albedo texture, so it renders as untextured plastic" % [path, entry[0]])
	assert_true(seen > 0, "no surface was found on any threat model, so this test checked nothing")
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## Normal maps are rule 8's first banned item and these three are allowed them.
## Per model rather than per surface: the bear's teeth material has no normal map
## in the source and inventing one would be worse than not having it.
func test_every_threat_model_carries_at_least_one_normal_map() -> void:
	for path in _models():
		var mapped := 0
		for entry in _surfaces(path):
			var material: BaseMaterial3D = entry[1]
			if material.normal_enabled and material.normal_texture != null:
				mapped += 1
		assert_true(mapped > 0, "%s carries no normal map on any surface; the character exception box exists precisely so it can" % path)


## Art Bible rule 6's budget is hand-spent, one triangle at a time, by
## `tools/blender/build_*.py`. An automatic decimator handed a 3,000-triangle
## bear has nothing left to take that is not load-bearing.
##
## `test_import_wiring.gd :: test_no_world_model_generates_lods` cannot cover
## this: it skips every exempt root by design, and these three are under one.
func test_no_threat_model_generates_lods() -> void:
	var offenders := PackedStringArray()
	for path in _models():
		var text := _import_text(path)
		if text == "":
			offenders.append("%s has no .import file, so it has never been imported" % path)
		elif not text.contains(LOD_LINE):
			offenders.append("%s does not carry `%s`, so Godot will decimate a model that was already decimated by hand" % [path, LOD_LINE])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The other half of the exemption, and the more dangerous half.
##
## `tools/palette_import_materials.gd` rebuilds every material flat from the
## 12-colour table. Wired into a character it would delete the maps the two
## tests above check for -- and because the result would be *on* palette and
## flat, every other art gate in the suite would go green over it.
func test_no_threat_model_is_repainted_from_the_palette() -> void:
	var offenders := PackedStringArray()
	for path in _models():
		if _import_text(path).contains(PALETTE_WIRING):
			offenders.append("%s carries `%s`, which would repaint it from the 12-colour table and pass every other gate doing it" % [path, PALETTE_WIRING])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The Art Bible's own instruction, pinned. See this file's header.
func test_the_character_exemption_covers_every_threat_subfolder() -> void:
	for path in _models():
		assert_true(
			AssetScannerScript.is_surface_rule_exempt(path),
			"%s is not covered by AssetScanner.SURFACE_RULE_EXEMPT_ROOTS (%s), so the surface gates will fail it for carrying the maps the Art Bible's exception box grants it" % [path, ", ".join(AssetScannerScript.SURFACE_RULE_EXEMPT_ROOTS)]
		)
	# Negative controls. Without these the test passes just as happily against
	# an exemption that has been widened to everything, which would take the
	# surface rules off the whole project and report green doing it.
	assert_false(
		AssetScannerScript.is_surface_rule_exempt("res://assets/models/props/pickup_truck.glb"),
		"a prop must not be exempt from the surface rules"
	)
	assert_false(
		AssetScannerScript.is_surface_rule_exempt("res://assets/models/vegetation/tree_bare_a.glb"),
		"a tree must not be exempt from the surface rules"
	)
	# The trailing-slash rule, which is the whole reason the bear folder is
	# already covered. A sibling that merely starts with the same letters is not.
	assert_false(
		AssetScannerScript.is_surface_rule_exempt("res://assets/models/characters_wip/bear.glb"),
		"the prefix match must be on a path separator, or any folder starting with `characters` gets the exemption"
	)


func test_every_threat_model_carries_the_takes_its_design_needs() -> void:
	var offenders := PackedStringArray()
	for path in _models():
		var have := _takes(path)
		for take in REQUIRED_TAKES[path]:
			if not have.has(take):
				offenders.append("%s has no take called `%s`" % [path, take])
	assert_eq(offenders.size(), 0, "; ".join(offenders))


## The counts as well as the names, because the consolidation is the deliverable.
##
## The scavenger's five takes arrived as five 115 MB files each carrying its own
## full copy of the mesh, and the zombie's twelve as twelve animation-only ones.
## Both were merged onto one rig by one script. A merge that silently dropped a
## take, or stashed one where the glTF exporter could not see it, produces a
## perfectly valid file with fewer clips in it and nothing that says so.
func test_the_libraries_hold_every_take_that_was_merged() -> void:
	for path in _models():
		var expected: int = TAKE_COUNTS[path]
		var have := _takes(path)
		assert_eq(have.size(), expected, "%s holds %d takes, %d were merged into it" % [path, have.size(), expected])
