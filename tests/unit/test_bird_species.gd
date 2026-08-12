extends TestCase

## A bird is `Bird` plus a `.tres`, and this is the file that holds that claim to
## account.
##
## ---------------------------------------------------------------------------
## THE NUMBER THIS FILE EXISTS FOR
## ---------------------------------------------------------------------------
## `.superpowers/sdd/wave3/task-w3-pigeon-report.md` §4.1 measured the second
## bird in this game at 209 lines of code against 31 of data, and §4.3 said the
## third would cost the same 209 again, and the fourth, because GDScript forbids
## a subclass redeclaring a parent's constant and `Crow` kept its model, its
## colour and its facing in constants.
##
## Binding rule 4 says a new creature should be a new `.tres`. The test that
## matters here is `test_a_third_species_needs_no_subclass`: it builds a species
## that has no class anywhere in the project, hands it to the shipped
## `BirdFlock`, and requires real birds wearing it. Everything else in this file
## guards a specific way that could stop being true.
##
## ---------------------------------------------------------------------------
## AND THE ONE THAT WOULD HAVE CAUGHT THE MOST EXPENSIVE DEFECT SO FAR
## ---------------------------------------------------------------------------
## `test_the_rig_is_actually_turned_by_the_species_own_yaw`. The crow shipped a
## whole wave flying tail-first because Unity's models face +Z and `look_at()`
## aims -Z; at sixteen pixels a bird flying backwards still reads as a bird, so
## the owner caught it and the suite did not. That correction was `const
## MODEL_YAW := PI`, and moving a constant into data is exactly the kind of
## change that drops it in silence. So the yaw is asserted in the data AND
## through the rig `Bird` actually assembles, with a negative control that proves
## the turn comes from the species rather than from anywhere else.

const SpeciesScript := preload("res://src/definitions/bird_species.gd")
const TakeScript := preload("res://src/definitions/bird_take.gd")
const BirdAnimationsScript := preload("res://src/entities/wildlife/bird_animations.gd")
const FlockScript := preload("res://src/entities/wildlife/bird_flock.gd")
const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")

const CROW: BirdSpecies = preload("res://data/wildlife/crow.tres")
const PIGEON: BirdSpecies = preload("res://data/wildlife/pigeon.tres")

const PALETTE_PATH := "res://data/palette/color_bible.tres"

const A_WIRE := [
	{"at": Vector3(0.0, 5.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 5.0, 2.4), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 5.0, 4.8), "facing": Vector3(1.0, 0.0, 0.0)},
	{"at": Vector3(0.0, 5.0, 7.2), "facing": Vector3(1.0, 0.0, 0.0)},
]


## WorldClock in the one respect a flock reads it.
class ClockStand extends RefCounted:
	var night := false

	func is_night() -> bool:
		return night


## Annotated rather than inferred, so every read below is typed. A bare
## `[CROW, PIGEON]` returned as an untyped Array makes each loop variable a
## Variant, and then nothing it reaches can be inferred either.
func _species() -> Array[BirdSpecies]:
	var list: Array[BirdSpecies] = [CROW, PIGEON]
	return list


# --- the data, as shipped ------------------------------------------------------


func test_both_birds_are_on_disk_as_data() -> void:
	for path in ["res://data/wildlife/crow.tres", "res://data/wildlife/pigeon.tres"]:
		assert_true(ResourceLoader.exists(path), "%s is not in the project" % path)
	assert_eq(CROW.species_name, "crow", "the crow does not know what it is called")
	assert_eq(PIGEON.species_name, "pigeon", "the pigeon does not know what it is called")


## Seven motions, and every species must have an answer for all of them --
## including "the same take as another role", which is what a species with no
## glide says. A missing row is silent by design: `Bird._play()` leaves whatever
## was running, which is right for a bird that genuinely has no such take and
## invisible for one that should.
func test_every_species_covers_all_seven_roles() -> void:
	for species in _species():
		var missing := PackedStringArray()
		for role in BirdSpecies.ROLES:
			if species.take_for(role) == &"":
				missing.append(String(role))
		assert_eq(missing.size(), 0, "%s has no take for %s" % [species.species_name, ", ".join(missing)])


func test_every_role_names_a_take_the_species_actually_has() -> void:
	for species in _species():
		var dangling := PackedStringArray()
		for role in BirdSpecies.ROLES:
			var take := species.take_for(role)
			if take != &"" and species.take_named(take) == null:
				dangling.append("%s -> %s" % [role, take])
		assert_eq(
			dangling.size(), 0,
			"%s maps %s to a take it does not carry, so the bird stands still and nothing errors" % [
				species.species_name, ", ".join(dangling)]
		)


func test_every_take_name_is_unique_within_a_species() -> void:
	for species in _species():
		var seen: Dictionary = {}
		var repeated := PackedStringArray()
		for take in species.takes:
			if seen.has(take.take_name):
				repeated.append(String(take.take_name))
			seen[take.take_name] = true
		assert_eq(repeated.size(), 0, "%s names %s twice" % [species.species_name, ", ".join(repeated)])
		assert_true(species.takes.size() > 0, "%s has no takes at all" % species.species_name)


func test_every_source_file_a_take_names_is_in_the_project() -> void:
	for species in _species():
		assert_true(
			ResourceLoader.exists(species.model_path),
			"%s's model %s is not in the project" % [species.species_name, species.model_path]
		)
		for path in species.source_files():
			assert_true(
				ResourceLoader.exists(path),
				"%s takes an animation from %s, which is not in the project" % [species.species_name, path]
			)


## The two ways of saying how long a take is have to agree. A sliced take knows
## its frame range AND its seconds, deliberately: a generator that derived one
## from the other could not be wrong, and this is the column that caught the
## dove's `animation/trimming` at eight seconds instead of four.
func test_a_sliced_takes_stored_length_agrees_with_its_frame_range() -> void:
	for species in _species():
		for take in species.takes:
			if not take.is_sliced():
				continue
			assert_almost_eq(
				take.seconds, float(take.last_frame - take.first_frame) / species.source_fps, 0.001,
				"%s/%s says %.3f s but frames %d..%d at %.0f fps are %.3f s" % [
					species.species_name, take.take_name, take.seconds,
					take.first_frame, take.last_frame, species.source_fps,
					float(take.last_frame - take.first_frame) / species.source_fps]
			)


## One library name per species, or two birds in one scene collide on the
## AnimationPlayer and the second one's takes replace the first's.
func test_the_two_birds_do_not_share_a_library_name() -> void:
	assert_true(CROW.library != PIGEON.library, "both birds hang their takes under '%s'" % CROW.library)
	assert_true(CROW.library != &"", "the crow's library has no name")
	assert_true(PIGEON.library != &"", "the pigeon's library has no name")


func test_each_bird_reads_its_colour_out_of_the_palette() -> void:
	var bible: Resource = load(PALETTE_PATH)
	assert_not_null(bible, "the palette is missing, so nothing can be resolved from it")
	if bible == null:
		return
	for species in _species():
		var tone: Color = species.tone()
		assert_true(
			bible.contains(tone),
			"%s is painted %s, which is not in the 12-colour table" % [species.species_name, tone.to_html(false)]
		)


## A rock dove is the grey one. Two near-black birds at sixteen pixels are one
## bird, and `structure_tones[0]` is the farmhouse siding the dove sits on.
func test_the_pigeon_is_lighter_than_the_crow_and_is_not_the_siding() -> void:
	var bible: Resource = load(PALETTE_PATH)
	assert_not_null(bible, "the palette is missing")
	if bible == null:
		return
	var crow: Color = CROW.tone()
	var pigeon: Color = PIGEON.tone()
	assert_true(
		pigeon.get_luminance() > crow.get_luminance(),
		"the pigeon (%s) is not lighter than the crow (%s), so they are one bird at this framing" % [
			pigeon.to_html(false), crow.to_html(false)]
	)
	assert_true(
		pigeon != bible.structure_tones[0],
		"the pigeon wears the farmhouse's own siding, and the eave is one of the things it sits on"
	)


# --- which way the bird points -------------------------------------------------


func test_every_bird_carries_the_half_turn_that_undoes_unity_s_forward() -> void:
	for species in _species():
		assert_almost_eq(
			absf(species.model_yaw), PI, 0.0001,
			("%s's model_yaw is %.4f rad. Both packs came out of a .unitypackage, Unity's models face +Z "
				+ "and look_at() aims -Z, so a bird with no correction flies tail-first -- which shipped "
				+ "for a whole wave and only the owner caught it.") % [species.species_name, species.model_yaw]
		)


## THE GUARD THE BRIEF ASKED FOR, and it measures the rig rather than the field.
##
## A species can carry the right yaw and a `_build_rig()` that forgot to apply it
## would still pass every assertion above. So this builds the crow the way the
## game builds it, and asks where the model's own +Z -- the beak, on both these
## deliveries -- has ended up. It must be pointing where `look_at()` aims.
##
## The second half is the negative control: the same code path with a species
## whose yaw is zero must leave the rig alone. Without it, a `_build_rig()` that
## turned every bird by PI regardless of its data would pass the first half.
func test_the_rig_is_actually_turned_by_the_species_own_yaw() -> void:
	var turned = _rig_forward(CROW)
	assert_not_null(turned, "the crow built no rig to measure")
	if turned != null:
		assert_almost_eq(
			(turned as Vector3).z, -1.0, 0.01,
			("the crow's model faces %s after _build_rig(), not (0, 0, -1). The model's own +Z is its beak "
				+ "and look_at() aims -Z, so this bird flies tail-first.") % [turned]
		)
	# A stand-in species over the same asset, declaring no correction at all.
	var straight: BirdSpecies = SpeciesScript.new()
	straight.species_name = "unturned"
	straight.model_path = CROW.model_path
	straight.library = &"unturned"
	straight.model_yaw = 0.0
	var untouched = _rig_forward(straight)
	assert_not_null(untouched, "the stand-in built no rig to measure")
	if untouched != null:
		assert_almost_eq(
			(untouched as Vector3).z, 1.0, 0.01,
			("a species declaring model_yaw = 0 came out facing %s, so the half-turn is being applied "
				+ "from somewhere other than the data and no species could ever decline it.") % [untouched]
		)


## Where the model's own +Z points once `Bird` has assembled and turned the rig.
## In the tree, because that is the only place `_ready()` runs; freed here, so
## nothing leaks (briefing constraint 2).
##
## NORMALISED, and it has to be from the day a species may declare its own size:
## `rig.scale` is part of the basis, so `basis * (0, 0, 1)` on a bird drawn ten
## per cent larger comes back 1.1 long. This asks which WAY the beak points; how
## big the bird is, is `_rig_scale()` below, and the two are separate claims.
func _rig_forward(species: BirdSpecies):
	var rig := _rig_of(species)
	if rig == null:
		return null
	var forward := (rig.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	_drop(rig)
	return forward


## What the rig was actually scaled to, which is a different question from which
## way it faces.
func _rig_scale(species: BirdSpecies):
	var rig := _rig_of(species)
	if rig == null:
		return null
	var scale := rig.scale
	_drop(rig)
	return scale


## The `Rig` node a `Bird` assembles for `species`, still in the tree. The caller
## frees the bird through `_drop()`.
func _rig_of(species: BirdSpecies) -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.get_root() == null:
		return null
	var bird := Bird.new()
	bird.species = species
	tree.get_root().add_child(bird)
	for child in bird.get_children():
		var rig := child as Node3D
		if rig != null and rig.name == "Rig":
			return rig
	tree.get_root().remove_child(bird)
	bird.free()
	return null


func _drop(rig: Node3D) -> void:
	var bird := rig.get_parent()
	if bird == null:
		return
	if bird.get_parent() != null:
		bird.get_parent().remove_child(bird)
	bird.free()


# --- how big the bird is drawn ---------------------------------------------------
#
# The owner asked for crows and pigeons ten per cent larger, and the answer to
# "is that data?" was no: `_build_rig()` never wrote a scale at all and neither
# `BirdSpecies` nor `Bird` had a field for one, so the size a bird was drawn at
# was whatever `nodes/root_scale` in its `.import` happened to produce. It is
# `species.model_scale` now, and these are what say so.


func test_both_birds_are_drawn_ten_per_cent_larger_than_their_asset() -> void:
	for species in _species():
		assert_almost_eq(
			species.model_scale, 1.1, 0.0001,
			"%s is drawn at %.4f of its asset's size, not the 1.1 the owner asked for" % [
				species.species_name, species.model_scale]
		)


## THE NEGATIVE CONTROL, and it is the half that matters: without it a
## `_build_rig()` that scaled every bird by 1.1 regardless of its data would pass
## the assertion above and the field would be decoration.
func test_the_rig_wears_the_species_own_scale_and_a_species_may_decline_it() -> void:
	var worn = _rig_scale(CROW)
	assert_not_null(worn, "the crow built no rig to measure")
	if worn != null:
		assert_almost_eq(
			(worn as Vector3).x, CROW.model_scale, 0.0001,
			"the crow's rig came out at %s against the %.4f its species declares" % [worn, CROW.model_scale]
		)
	var plain: BirdSpecies = SpeciesScript.new()
	plain.species_name = "unscaled"
	plain.model_path = CROW.model_path
	plain.library = &"unscaled"
	plain.model_scale = 1.0
	var untouched = _rig_scale(plain)
	assert_not_null(untouched, "the stand-in built no rig to measure")
	if untouched != null:
		assert_almost_eq(
			(untouched as Vector3).x, 1.0, 0.0001,
			("a species declaring model_scale = 1.0 came out at %s, so the size is being applied from "
				+ "somewhere other than the data and no species could ever decline it") % [untouched]
		)


## A BIGGER BIRD STILL STANDS ON THE WIRE.
##
## Measured on the delivered rigs: the lowest toe sits at y = +0.0008 m on the
## crow and y = -0.0006 m on the pigeon, which is to say the models' origins ARE
## their foot plane. Scaling about that origin therefore moves the feet by a
## tenth of those numbers -- 0.08 mm and 0.06 mm -- against the 0.14 m
## `WireSway` moves a span through a squall. This is what says the scale went on
## the RIG and not on the bird, because scaling the bird would move the node the
## perch positions and put the feet through the wire.
func test_a_bird_drawn_larger_still_has_its_feet_on_the_perch() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "no SceneTree to build a rig in")
	if tree == null or tree.get_root() == null:
		return
	for species in _species():
		var bird := Bird.new()
		bird.species = species
		tree.get_root().add_child(bird)
		bird.perch_on(Vector3(0.0, 6.0, 0.0), Vector3(1.0, 0.0, 0.0))
		var lowest := INF
		for node in bird.find_children("*", "Skeleton3D", true, false):
			var skeleton := node as Skeleton3D
			for index in range(skeleton.get_bone_count()):
				var at: Vector3 = skeleton.global_transform \
					* skeleton.get_bone_global_pose(index).origin
				lowest = minf(lowest, at.y)
		assert_true(lowest < INF, "%s put no bones in the world" % species.species_name)
		if lowest < INF:
			assert_almost_eq(
				lowest, 6.0, 0.01,
				("%s's lowest bone stands %.4f m from the wire it was placed on. The model's origin is "
					+ "its foot plane, so a scale applied to the rig must leave the feet where they were.")
					% [species.species_name, lowest - 6.0]
			)
		tree.get_root().remove_child(bird)
		bird.free()


## AND THE SIZE GATE STILL COVERS THE BIRD THE GAME DRAWS.
##
## `tests/art/test_asset_scale.gd` measures the ASSET on disk, which is the right
## instrument for the defect it exists for -- a wolf arriving at 15 mm. It cannot
## see a scale applied at runtime, so the day `model_scale` exists the game can
## draw a bird any size it likes and that gate stays green. This closes it: the
## asset's measured size TIMES the species' own scale has to be inside the band
## the bird's own `data/scale/*.tres` declares.
func test_a_bird_as_drawn_is_still_inside_its_own_size_band() -> void:
	for species in _species():
		var bounds := AssetProbeScript.bounds(species.model_path)
		assert_eq(bounds["error"], "", "%s's model did not load: %s" % [species.species_name, bounds["error"]])
		var size: Vector3 = bounds["size"]
		var band: AssetScale = load("res://data/scale/%s.tres" % species.species_name)
		assert_not_null(band, "%s has no size band in data/scale" % species.species_name)
		if band != null:
			var refusal := band.refusal(size * species.model_scale)
			assert_eq(
				refusal, "",
				"%s as the game draws it (%.4f m longest, %.2fx its asset's %.4f m) %s" % [
					species.species_name,
					maxf(size.x, maxf(size.y, size.z)) * species.model_scale,
					species.model_scale, maxf(size.x, maxf(size.y, size.z)), refusal]
			)


# --- the two packs want opposite import settings -------------------------------


## `animation/trimming` HAS TO BE OFF FOR THE CROW AND ON FOR THE DOVE, and
## getting either wrong is silent.
##
##   OFF for the crow, because its clips are frame RANGES inside one long take
##   and trimming slides every number the table is written in. Measured:
##   `crow_perch.fbx` imported 100 frames long instead of 183 with it on.
##
##   ON for the dove, because each clip is its own `AnimationStack` but all
##   thirteen sit on ONE shared timeline -- a stack running 120..215 imports as
##   0..215 with five seconds of nothing on the front. Measured: `idle_right` at
##   8.958 s against a true 3.958 s, `death` at 23.792 s against 0.875 s. The
##   symptom is a bird that lands on a wire and stands still for five seconds
##   before its idle begins, and the wait varies by the clip's position in the
##   file, so it looks broken differently for every take.
##
## So the setting is a property of how a pack laid its clips out, NOT a project
## convention -- which is exactly the thing a third animal will get wrong by
## copying whichever bird it read first. This test is here to say so out loud,
## in one place, with both values side by side.
func test_the_two_packs_want_opposite_trimming_and_each_file_has_the_one_it_needs() -> void:
	for take in CROW.takes:
		var path := take.file(CROW.model_path)
		assert_true(
			_import_text(path).contains("animation/trimming=false"),
			("%s must import with trimming OFF: the crow's takes are frame ranges inside one long take, "
				+ "and trimming slides every frame number the species is written in.") % path
		)
	assert_true(
		_import_text(PIGEON.model_path).contains("animation/trimming=true"),
		("%s must import with trimming ON: its thirteen stacks share one timeline, so without it every "
			+ "take carries the whole preceding timeline as dead air.") % PIGEON.model_path
	)


## Immutable tracks stay for both, and for the same reason: default true drops a
## bone whose value never leaves its rest, so playing take A then B then A again
## leaves every bone B moved and A does not exactly where B left it -- a perched
## bird with its wings still spread.
func test_no_bird_file_drops_its_immutable_tracks() -> void:
	var files := PackedStringArray([PIGEON.model_path])
	files.append_array(CROW.source_files())
	for path in files:
		assert_true(
			_import_text(path).contains("animation/remove_immutable_tracks=false"),
			"%s drops immutable tracks, so switching takes leaves untouched bones where the previous take left them" % path
		)


func _import_text(path: String) -> String:
	var file := FileAccess.open(path + ".import", FileAccess.READ)
	return file.get_as_text() if file != null else ""


# --- a name with a space in it -------------------------------------------------


func test_an_exact_take_name_wins() -> void:
	var available := {"Dove_Fly": true, "Dove_Fly ": true}
	assert_eq(
		BirdAnimationsScript.matching_name(available, "Dove_Fly"), "Dove_Fly",
		"an exact match must never be overtaken by a trimmed one"
	)


## `Dove_Run to Idle ` -- the pack's exporter wrote a trailing space, and one
## take of thirteen went missing on the pigeon's first run because the lookup did
## not carry it. Tolerated in both directions, because the next delivery may fix
## the typo and the data would then be the one with the space.
func test_a_name_that_differs_only_by_whitespace_is_still_found() -> void:
	assert_eq(
		BirdAnimationsScript.matching_name({"Dove_Run to Idle ": true}, "Dove_Run to Idle"),
		"Dove_Run to Idle ",
		"a take the file spells with a trailing space was dropped"
	)
	assert_eq(
		BirdAnimationsScript.matching_name({"Dove_Run to Idle": true}, "Dove_Run to Idle "),
		"Dove_Run to Idle",
		"a table that carries the space cannot find a file that has stopped having one"
	)


func test_a_name_nothing_matches_is_reported_as_missing() -> void:
	assert_eq(BirdAnimationsScript.matching_name({"Dove_Fly": true}, "Dove_Soar"), "", "an absent take was matched to something")
	assert_eq(BirdAnimationsScript.matching_name({}, "Dove_Fly"), "", "an empty file matched a take")
	assert_eq(BirdAnimationsScript.matching_name({"Dove_Fly": true}, ""), "", "a nameless request matched a take")


## The shipped data keeps the file's own spelling BYTE FOR BYTE, so the fallback
## above never runs in the shipped configuration -- and never pushes the warning
## it is required to push, which would fail the run.
func test_the_dove_packs_trailing_space_is_stored_byte_for_byte() -> void:
	var take := PIGEON.take_named(&"run_to_idle")
	assert_not_null(take, "the pigeon lost its run_to_idle take")
	if take == null:
		return
	assert_eq(
		take.source_name, "Dove_Run to Idle ",
		"the trailing space has been tidied out of the data, so every build() now warns"
	)


# --- what a bird takes from its species ----------------------------------------


func test_a_bird_adopts_its_species_beats() -> void:
	var crow := Bird.new()
	crow.species = CROW
	var dove := Bird.new()
	dove.species = PIGEON
	assert_almost_eq(crow.launch_seconds, 29.0 / 30.0, 0.001, "the crow's launch is not its take's length")
	assert_almost_eq(dove.launch_seconds, 0.375, 0.001, "the dove's launch is not its take's length")
	assert_almost_eq(dove.land_seconds, 0.417, 0.001, "the dove's landing is not its take's length")
	assert_true(dove.cruise_speed < crow.cruise_speed, "a pigeon flies slower than a crow")
	assert_almost_eq(crow.land_flare, 0.58, 0.001, "the flare measured off Rav_Land has gone")
	crow.free()
	dove.free()


## `ResourceLoader` hands every caller the same instance (briefing trap 6), so a
## bird that tuned its own species would tune every bird of that species --
## including ones already in the air, and including the next test to run.
func test_a_bird_never_writes_to_the_species_it_shares() -> void:
	var before := CROW.cruise_speed
	var one := Bird.new()
	one.species = CROW
	one.cruise_speed = 3.0
	var two := Bird.new()
	two.species = CROW
	assert_almost_eq(CROW.cruise_speed, before, 0.0001, "tuning one bird edited the species")
	assert_almost_eq(two.cruise_speed, before, 0.0001, "tuning one bird reached the next bird hatched")
	one.free()
	two.free()


## `Crow.palette_tone()` was STATIC, and a static does not dispatch through an
## instance -- so the parent's `material()` resolved the crow's colour even on a
## pigeon, and the pigeon had to override `material()` as well. Two of the five
## overrides the second bird paid for were this one fact.
func test_the_colour_dispatches_through_the_instance() -> void:
	var crow: Bird = Crow.new()
	var dove: Bird = Pigeon.new()
	assert_true(
		crow.palette_tone() != dove.palette_tone(),
		"a crow and a pigeon resolve the same colour %s through the same method" % crow.palette_tone().to_html(false)
	)
	assert_eq(crow.palette_tone(), CROW.tone(), "the crow's colour is not its species'")
	assert_eq(dove.palette_tone(), PIGEON.tone(), "the pigeon's colour is not its species'")
	crow.free()
	dove.free()


# --- the whole point -----------------------------------------------------------


## A species with no class anywhere in the project, driving the shipped
## `BirdFlock`, must produce real birds.
##
## THIS IS BINDING RULE 4 FOR CREATURES, AND IT IS ASSERTED RATHER THAN CLAIMED.
## Nothing below names `Crow`, `Pigeon`, `CrowFlock` or `PigeonFlock`: the flock
## is `bird_flock.gd` with a species set on it, exactly as a `.tscn` would set
## one, and the birds it hatches are plain `Bird`s wearing the third species'
## colour, model, takes and node name.
func test_a_third_species_needs_no_subclass() -> void:
	var third := _a_third_bird()
	var flock: BirdFlock = FlockScript.new()
	flock.species = third
	flock.random_seed = 20260812
	flock.set_perches(A_WIRE)
	assert_eq(flock.fewest, 3, "the flock did not take its size from the species")
	assert_eq(flock.most, 3, "the flock did not take its size from the species")
	assert_almost_eq(flock.flush_radius_m, 6.5, 0.001, "the flock did not take its flush radius from the species")
	var arrived := flock.arrive_now()
	assert_eq(arrived, 3, "%d birds arrived, and the species asks for three" % arrived)
	var named := 0
	for bird in flock.birds():
		assert_true(bird.species == third, "a bird hatched wearing somebody else's species")
		assert_eq(bird.palette_tone(), third.tone(), "the third bird is not its own colour")
		if String(bird.name).begins_with("WinterWren"):
			named += 1
	assert_eq(named, arrived, "the birds are not named after the species that made them")
	# And its takes build, out of the same builder, with no code of their own.
	var library := BirdAnimationsScript.build(third)
	assert_true(library.has_animation(&"sitting"), "the third bird's own take name did not reach the library")
	assert_true(
		library.get_animation_list().size() == third.takes.size(),
		"the third bird's library holds %d of its %d takes" % [
			library.get_animation_list().size(), third.takes.size()]
	)
	flock.free()


## Whether nightfall empties the wire is one boolean in the data. `PigeonFlock`
## used to override four methods to say it; a third species says it in a field,
## and both flocks below are the same class.
func test_daylight_only_is_the_whole_of_the_night_difference() -> void:
	var clock := ClockStand.new()
	clock.night = true
	var roosting := _a_third_bird()
	var leaves := _a_third_bird()
	leaves.daylight_only = true
	var day_bird: BirdFlock = FlockScript.new()
	day_bird.species = leaves
	day_bird.set_world_clock(clock)
	day_bird.set_perches(A_WIRE)
	day_bird.attach()
	var night_bird: BirdFlock = FlockScript.new()
	night_bird.species = roosting
	night_bird.set_world_clock(clock)
	night_bird.set_perches(A_WIRE)
	night_bird.attach()
	assert_true(day_bird.is_night(), "a daylight-only flock born at night does not know the wires must be empty")
	assert_true(day_bird.is_dark(), "the flock does not know the sun is down")
	assert_false(night_bird.is_night(), "a roosting flock is being told to empty the wires")
	assert_true(night_bird.is_dark(), "a roosting flock does not know the sun is down, which is a different question")
	# And the rule is what actually blocks the arrival. Through `advance()` rather
	# than `arrive_now()`: the latter is the door a capture uses to put birds out
	# whatever the timer says, and it deliberately does not ask the clock.
	day_bird.first_arrival_seconds = 0.5
	night_bird.first_arrival_seconds = 0.5
	var left := 6.0
	while left > 0.0:
		day_bird.advance(1.0 / 60.0)
		night_bird.advance(1.0 / 60.0)
		left -= 1.0 / 60.0
	assert_eq(day_bird.bird_count(), 0, "a daylight-only flock landed after dark")
	assert_true(night_bird.bird_count() > 0, "a roosting flock refused to land after dark")
	day_bird.free()
	night_bird.free()
	clock.night = false


## The occupied-perch filter is data too, and it now reads the whole tree for
## `Bird` rather than for `Crow` -- so it sees every species, not only its own.
func test_avoiding_an_occupied_perch_is_data_too() -> void:
	var choosy := _a_third_bird()
	var careless := _a_third_bird()
	careless.avoids_occupied_perches = false
	var one: BirdFlock = FlockScript.new()
	one.species = choosy
	one.set_perches(A_WIRE)
	var two: BirdFlock = FlockScript.new()
	two.species = careless
	two.set_perches(A_WIRE)
	# Nobody is standing anywhere, so both offer everything -- the filter must not
	# cost a perch when there is nothing to avoid.
	assert_eq(one.available_perches().size(), A_WIRE.size(), "the filter dropped a perch nobody was on")
	assert_eq(two.available_perches().size(), A_WIRE.size(), "the unfiltered flock lost a perch")
	assert_eq(
		BirdFlock.free_of(A_WIRE, [Vector3(0.0, 5.0, 2.4)], choosy.occupied_within_m).size(),
		A_WIRE.size() - 1,
		"a perch with a bird standing on it is still on offer"
	)
	one.free()
	two.free()


## A bird this project does not have a class for. Built here rather than written
## to disk, so the suite carries the proof without the valley carrying a wren.
func _a_third_bird() -> BirdSpecies:
	var species: BirdSpecies = SpeciesScript.new()
	species.species_name = "winter_wren"
	# Borrowing the dove's asset. What is being proved is that the DATA drives the
	# code, not that a wren model exists.
	species.model_path = PIGEON.model_path
	species.library = &"winter_wren"
	species.source_fps = 24.0
	species.model_yaw = PI
	species.palette_family = "structure"
	species.palette_index = 2
	var rows: Array[BirdTake] = []
	for row in [
		["sitting", "Dove_Idle Left", true],
		["watching", "Dove_Idle Right", true],
		["away", "Dove_Idle to Fly", false],
		["beating", "Dove_Fly", true],
		["down", "Dove_Fly to Idle", false],
	]:
		var take: BirdTake = TakeScript.new()
		take.take_name = StringName(row[0])
		take.source_name = row[1]
		take.loops = bool(row[2])
		rows.append(take)
	species.takes = rows
	species.roles = {
		BirdSpecies.PERCH: &"sitting",
		BirdSpecies.LOOK: &"watching",
		BirdSpecies.FLAP: &"away",
		BirdSpecies.TAKE_OFF: &"away",
		BirdSpecies.FLY: &"beating",
		BirdSpecies.GLIDE: &"beating",
		BirdSpecies.LAND: &"down",
	}
	species.fewest = 3
	species.most = 3
	species.flush_radius_m = 6.5
	species.daylight_only = false
	species.avoids_occupied_perches = true
	return species
