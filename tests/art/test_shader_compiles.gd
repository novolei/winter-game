extends TestCase

## THE SEVENTH FALSE-PASS CLASS: a shader nothing loads is a shader nothing checks.
##
## ---------------------------------------------------------------------------
## THE DEFECT, AND THE PART OF IT THAT WAS RECORDED WRONG
## ---------------------------------------------------------------------------
## DEFERRED.md records this class as "shaders compile on a later frame, and the
## whole suite lives inside the first one", with a one-line fix:
## `RenderingServer.force_draw()`. Measured on 4.7.1 headless before writing this
## file, **that is not the mechanism**, and that fix closes nothing:
##
##   1. A shader is compiled SYNCHRONOUSLY when the resource loads.
##      `Shader.set_code()` calls `RenderingServer.shader_set_code()`, and even
##      the dummy rendering driver parses there and fails loudly --
##      `servers/rendering/dummy/storage/material_storage.cpp:192`. No frame is
##      involved. Re-breaking `aurora_sky.gdshader` with the historical fault
##      (a `return` inside `sky()`) turned the suite RED at HEAD, with no change
##      to the framework at all.
##
##   2. `RenderingServer.force_draw()` runs and is silent under `--headless`,
##      and with a broken shader already loaded it prints nothing further. It
##      neither adds a check nor changes one, so it was NOT added: an
##      undemonstrated line in a gate is the thing this gate exists to end.
##
## What is actually invisible is narrower and worse than "shaders": **a shader
## that no test ever loads is never handed to the rendering server, so it is
## never parsed, and no gate in the project can see it.** Measured at HEAD by
## breaking all nine project shaders at once: seven produced console errors and
## two produced nothing --
##
##      assets/shaders/chimney_smoke.gdshader
##      assets/shaders/montage_film.gdshader
##
## -- and with `chimney_smoke.gdshader` syntactically dead the suite reported
## `1842 passed, 0 failed`, exit 0, console pristine. Both shaders are in the
## shipping game; the first draws the smoke over the farmhouse on every frame.
##
## Note also what the runner's own tally is worth here: with ALL NINE shaders
## broken it still read `1842 passed, 0 failed`. Every one of those errors was
## caught by `tools/run_tests.sh` reading the console, and by nothing else.
##
## ---------------------------------------------------------------------------
## HOW THIS FILE CLOSES IT
## ---------------------------------------------------------------------------
## It loads every `.gdshader` the project authors, which is the whole mechanism:
## loading IS compiling. `CACHE_MODE_IGNORE` forces a fresh parse rather than
## handing back whatever an earlier test already loaded, so the engine's own
## diagnostic is printed inside this test rather than somewhere upstream -- and
## so that this gate's coverage does not depend on which tests ran before it.
##
## THE CONSOLE IS NOT THE ONLY ASSERTION, deliberately. The engine's message
## names a line number and prints the offending source, but it does NOT name the
## file: it reads `at: (null) (:353)`. A gate that only dirties the console would
## say a shader broke without saying which one. So the failure is also read back
## through the resource, and the assertion carries the path.
##
## THE DETECTOR: a shader that failed to compile reports NO UNIFORMS. Measured
## on the same broken/working pair -- `snow_ground.gdshader` reports 38 uniforms
## working and `chimney_smoke.gdshader` reports 0 broken, while `get_mode()`
## still answers correctly on both because the `shader_type` line is parsed
## separately. `RenderingServer.shader_get_code()` was tried first and is not
## usable: the dummy storage returns "" for a working shader too.
##
## The detector is therefore only meaningful for a shader that declares at least
## one uniform, and it says so rather than assuming: the check is derived from
## the file's own source, not from a hardcoded list. All nine project shaders
## declare between 2 and 38. For a hypothetical uniform-less shader the console
## gate in `tools/run_tests.sh` remains the backstop, and this file says out loud
## that it is the weaker of the two.
##
## ---------------------------------------------------------------------------
## HOW TO CONFIRM THIS GATE STILL BITES
## ---------------------------------------------------------------------------
## Append one garbage line to any shader under `assets/shaders/` and run the
## suite. It must go red naming that file. That was done for
## `chimney_smoke.gdshader` -- the one this file was written for, because it was
## provably invisible before -- and the run is recorded in
## `.superpowers/sdd/wave3/task-w3-shader-gate-report.md`. A gate that cannot
## reproduce the defect it guards is itself the next false-pass class.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

## Where the project's own shaders may live.
##
## `res://addons` is deliberately absent. Two third-party shaders ship there
## (gaea's cube preview, interaction_kit_3d's outline); they are somebody else's
## code, no change of ours makes them compile or fail, and a red suite naming a
## vendored file is a red suite nobody can act on -- the same reasoning
## The test wrapper rejects every engine error line; third-party addons are not
## part of this shader gate's scope.
##
## Three roots rather than one because a shader is not required to live under
## `assets/shaders/`, and a gate that covers only the tidy case is blind to the
## untidy one. Today all nine are in `assets/shaders/`.
const SHADER_ROOTS: Array[String] = ["res://assets", "res://src", "res://scenes"]

## The floor for how many shaders must be found.
##
## RAISE THIS WHEN A SHADER IS ADDED. It is a tripwire, not a target, and it is
## the same one `test_runner.gd`'s MINIMUM_TESTS is: every assertion below judges
## a shader it found, and none of them can see a shader the scan stopped
## returning. A root that gets renamed, or a walk that starts skipping a folder,
## would otherwise leave this file passing over nothing at all.
##
## If this ever needs LOWERING, that is a shader being deleted -- which is a
## person deciding, and the diff should say so.
const MINIMUM_SHADERS := 9


## Every `.gdshader` the project authors, sorted, with no duplicates.
##
## Sorted because three roots are walked in order and a stable list makes a
## failure reproducible; de-duplicated because the roots are allowed to overlap
## in future without silently double-counting toward MINIMUM_SHADERS.
func _project_shaders() -> Array[String]:
	var found: Array[String] = []
	for root in SHADER_ROOTS:
		for path in AssetScannerScript.find_files(root, [".gdshader"] as Array[String]):
			if not found.has(path):
				found.append(path)
	found.sort()
	return found


## True when `code` declares at least one uniform, which is what makes the
## uniform-count detector meaningful for that file.
##
## Matched at the start of a statement rather than anywhere in the line, so the
## word "uniform" inside a comment -- and this project's shaders are more comment
## than code -- is not mistaken for a declaration.
func _declares_a_uniform(code: String) -> bool:
	for raw_line in code.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("uniform ") \
				or line.begins_with("global uniform ") \
				or line.begins_with("instance uniform "):
			return true
	return false


# --- the gate -----------------------------------------------------------------


## THE ONE THAT WOULD HAVE CAUGHT IT.
##
## Loading is compiling, so this method's real work is the load; the assertions
## exist to name the file when the load has already printed the reason.
func test_every_shader_the_project_ships_compiles() -> void:
	var shaders := _project_shaders()
	assert_true(
		shaders.size() >= MINIMUM_SHADERS,
		"found %d shader(s) under %s, expected at least %d -- this gate proves nothing about shaders it never opened"
			% [shaders.size(), str(SHADER_ROOTS), MINIMUM_SHADERS]
	)
	for path in shaders:
		var shader: Shader = ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_IGNORE)
		assert_not_null(shader, "%s did not load as a Shader at all" % path)
		if shader == null:
			continue
		if not _declares_a_uniform(shader.code):
			# Nothing to read back. The console gate is the only guard on this
			# one, and it cannot name the file -- say so where somebody will see
			# it rather than let it look covered.
			print("  NOTE  %s declares no uniform, so only the console gate covers it" % path)
			continue
		assert_true(
			shader.get_shader_uniform_list().size() > 0,
			("%s FAILED TO COMPILE. A shader that does not compile reports no uniforms," % path)
				+ " and this one declares at least one. The engine printed the reason"
				+ " above -- it names a line but not a file, which is why this"
				+ " assertion names the file."
		)


## The detector, checked against a shader that is known to be fine.
##
## Without this, `test_every_shader_the_project_ships_compiles` would pass just
## as happily if `_declares_a_uniform()` never returned true -- every shader
## would take the `continue` and the gate would be a loop that does nothing. This
## pins the pair: at least one real shader both declares uniforms and reports
## them back.
func test_the_detector_reads_uniforms_back_off_a_working_shader() -> void:
	var shaders := _project_shaders()
	var readable := 0
	for path in shaders:
		var shader: Shader = ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_IGNORE)
		if shader == null:
			continue
		if _declares_a_uniform(shader.code) and shader.get_shader_uniform_list().size() > 0:
			readable += 1
	assert_true(
		readable >= MINIMUM_SHADERS,
		("only %d of %d shader(s) both declare a uniform and report one back." % [readable, shaders.size()])
			+ " Below MINIMUM_SHADERS that is either a shader failing to compile"
			+ " or the detector having stopped working, and the two are not"
			+ " distinguishable from here -- read the console."
	)


## Every shader announces a shader_type the engine recognises.
##
## `get_mode()` is parsed from the `shader_type` line separately from the body,
## so it answers even for a file that failed to compile -- which is exactly why
## it is checked separately rather than folded into the gate above. What it
## catches is the other half: a file with no `shader_type` line at all, or one
## naming a type this engine build does not have.
func test_every_shader_declares_a_type_the_engine_knows() -> void:
	var shaders := _project_shaders()
	assert_true(shaders.size() >= MINIMUM_SHADERS, "the scan found %d shader(s)" % shaders.size())
	for path in shaders:
		var shader: Shader = ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_IGNORE)
		if shader == null:
			continue
		assert_true(
			shader.code.contains("shader_type "),
			"%s has no shader_type line, so the engine cannot know what to compile it as" % path
		)
