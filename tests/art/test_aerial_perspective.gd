extends TestCase

## AERIAL PERSPECTIVE -- the depth fog that makes a far tree a different colour
## from a near one, and the coupling that makes it work at all.
##
## Every tree in the scene used to be the same near-black whatever its distance,
## which is the main reason the frame read flat. Real cold air does not work that
## way and neither does `Refs/game ref/level.jpg`. The fix belongs to the fog
## rather than to per-tree materials, so it applies to everything automatically
## and moves with the six presets.
##
## ---------------------------------------------------------------------------
## WHY DEPTH FOG, AND WHY ITS WINDOW IS A NINETY-METRE NUMBER
## ---------------------------------------------------------------------------
## The rig is ORTHOGRAPHIC on a 90 m boom (src/rendering/camera_rig.gd), so the
## whole farmstead sits between about 69 m and 100 m from the camera -- not
## because anything is far away, but because the camera is. Two consequences,
## and both are counter-intuitive:
##
##   * EXPONENTIAL fog cannot do this. 1 - exp(-density * depth) over 69..100 m
##     is very nearly a straight line that starts a long way above zero: to put
##     45% of fog on the far tree it puts 34% on the near one, and the near tree
##     is the one that has to stay black.
##
##   * DEPTH fog can, because its window is authored. Begin the ramp just in
##     front of the nearest thing in the frame and end it past the furthest, and
##     the near tree gets nothing while the far tree gets nearly all of it.
##
## The price is that the window is measured FROM THE CAMERA, so it is tied to
## `CameraRig.boom_length`. That coupling is invisible -- a boom is documented as
## a device for keeping geometry off the near plane that "does not change the
## picture at all", which stopped being true the moment the fog started reading
## depth. test_the_fog_window_is_measured_from_the_camera_the_boom_puts_there is
## that coupling, written down.

const PRESET_DIRECTORY := "res://data/lighting"
const SHADER_ROOT := "res://assets/shaders"

## What the fog window was solved against: the rig's own boom, and the depth
## spread of the farmstead about the point the camera looks at.
##
## Derived rather than guessed. The camera is pitched 45 and yawed -35, so its
## forward vector is (0.4056, -0.7071, -0.5792) and a ground offset (dx, dz)
## from the look point changes depth by -(0.4056*dx - 0.5792*dz). Over the trees
## in scenes/main.tscn that runs from -21 m (TreeA, the nearest) to +9 m (TreeJ,
## the furthest), and the establishing frame adds about +/-13 m of its own.
const TUNED_BOOM := 90.0

func _load_presets() -> Dictionary:
	var presets := {}
	var dir := DirAccess.open(PRESET_DIRECTORY)
	if dir == null:
		return presets
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var preset = ResourceLoader.load(
			PRESET_DIRECTORY.path_join(file_name), "", ResourceLoader.CACHE_MODE_IGNORE
		)
		if preset is LightingPreset:
			presets[file_name.trim_suffix(".tres")] = preset
	return presets


## THE COUPLING. A boom change moves every fog value in the game at once, and
## nothing on the camera says so.
func test_the_fog_window_is_measured_from_the_camera_the_boom_puts_there() -> void:
	var rig := CameraRig.new()
	var boom: float = rig.boom_length
	# Node3D, not RefCounted (briefing constraint 2).
	rig.free()
	assert_almost_eq(
		boom, TUNED_BOOM, 0.001,
		"the depth-fog windows in data/lighting/*.tres were solved against a %.0f m boom; "
			% TUNED_BOOM
			+ "the rig now booms %.1f m, so every preset's aerial perspective has moved" % boom
	)


## The window has to straddle the boom, or the whole frame lands on one end of
## the ramp and the fog stops being aerial perspective and becomes a flat tint.
func test_every_preset_brackets_the_frame_with_its_fog_window() -> void:
	var presets := _load_presets()
	assert_false(presets.is_empty(), "no presets loaded, so this gate inspected nothing")
	for name in presets:
		var preset = presets[name]
		assert_true(
			preset.fog_depth_begin < preset.fog_depth_end,
			"%s begins its fog at %.1f m and ends it at %.1f m"
				% [name, preset.fog_depth_begin, preset.fog_depth_end]
		)
		assert_true(
			preset.fog_depth_begin < TUNED_BOOM and preset.fog_depth_end > TUNED_BOOM,
			"%s fogs from %.1f m to %.1f m, which does not straddle the %.0f m boom: the "
				% [name, preset.fog_depth_begin, preset.fog_depth_end, TUNED_BOOM]
				+ "whole frame would land on one end of the ramp"
		)


## In DEPTH mode `fog_density` is not a density at all -- it is the fog's
## opacity where the window ends, a 0..1 blend. A value authored as if it were
## still an exponential density (0.0016) would be invisible, and one over 1.0
## would be a solid rectangle of fog colour.
func test_every_fog_opacity_is_a_fraction() -> void:
	var presets := _load_presets()
	assert_false(presets.is_empty(), "no presets loaded, so this gate inspected nothing")
	for name in presets:
		var preset = presets[name]
		assert_true(
			preset.fog_density >= 0.0 and preset.fog_density <= 1.0,
			"%s asks for a fog opacity of %f; in DEPTH mode this is a blend, not a density"
				% [name, preset.fog_density]
		)


## The one that would have caught authoring the fog as though it were still
## exponential: every preset that fogs at all has to put enough of it on the far
## end of the window to be seen.
func test_a_preset_that_fogs_at_all_fogs_visibly() -> void:
	var presets := _load_presets()
	assert_false(presets.is_empty(), "no presets loaded, so this gate inspected nothing")
	for name in presets:
		var preset = presets[name]
		if not preset.fog_enabled:
			continue
		assert_true(
			preset.fog_density >= 0.1,
			"%s enables fog at an opacity of %f, which is invisible" % [name, preset.fog_density]
		)


## THE SHADERS' HALF OF THE CONTRACT.
##
## The director pushes three values into the world every frame; the day a shader
## stops declaring one of them the push becomes a silent no-op, because
## `set_shader_parameter` on a uniform that does not exist neither warns nor
## fails.
func test_both_cel_shaders_take_the_light_the_preset_gives_them() -> void:
	for path in [
		"%s/snow_ground.gdshader" % SHADER_ROOT,
		"%s/cel_flat.gdshader" % SHADER_ROOT,
	]:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "could not read %s" % path)
		for uniform in ["band_threshold", "band_softness", "light_tint"]:
			assert_true(
				text.contains("uniform") and text.contains(uniform),
				"%s declares no `%s` uniform, so the preset's value reaches nothing"
					% [path, uniform]
			)


## Everything outside a `//` comment. The banned-feature scan below has to read
## the code and not the prose about it: both shaders now carry a paragraph
## naming the style document's PBR render mode as the thing NOT to borrow, and a
## substring search over the raw file finds that paragraph and calls it a
## violation. Caught by this test failing on its own first run.
func _code(path: String) -> String:
	var stripped := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var comment := line.find("//")
		stripped += (line if comment < 0 else line.substr(0, comment)) + "\n"
	return stripped


## Art Bible rule 8, on the shaders themselves rather than on materials.
##
## tests/art/test_shading_features.gd scans materials on disk; the world is
## drawn by two hand-written shaders that no material scan can see. The style
## document's snow shader arrives with `specular_schlick_ggx`, `ROUGHNESS = 0.92`
## and `SPECULAR = 0.15` in it, and the tempting thing when borrowing its noise
## is to borrow the render_mode line with it.
func test_neither_cel_shader_has_grown_a_specular_highlight() -> void:
	for path in [
		"%s/snow_ground.gdshader" % SHADER_ROOT,
		"%s/cel_flat.gdshader" % SHADER_ROOT,
	]:
		var code := _code(path)
		assert_true(code.contains("specular_disabled"), "%s does not disable specular" % path)
		for banned in ["specular_schlick_ggx", "diffuse_burley", "SCREEN_TEXTURE"]:
			assert_false(
				code.contains(banned),
				"%s uses %s, which Art Bible rule 8 forbids" % [path, banned]
			)


## ---------------------------------------------------------------------------
## THE FOOTPRINT LEGIBILITY FLOOR -- the depth fog, read where the player stands
## ---------------------------------------------------------------------------
## A depth fog blends every pixel toward the fog colour, so whatever fraction of
## fog sits at a depth is the fraction of CONTRAST thrown away at that depth --
## for a footprint exactly as much as for a tree. And the player is always at
## the boom, because the rig is built around him.
##
## That makes `fog at the boom` the number the tracking mechanic lives or dies
## on. GDD section 8 puts footprints at the centre of the game: the bear and the
## scavenger read the same `track_mask` the terrain shader reads, and
## 风大 -> 足迹速消 -> 你安全; 风停 -> 足迹留存 -> 你被跟上. A preset that fogs
## the ground under his feet away deletes that, and nothing else in the suite
## would notice -- the presets' own gates measure luminance and palette, not
## whether a mark in the snow survives.
##
## MEASURED, at 8f2043f, in a real blizzard with the player walking through it
## (harness and frames in .superpowers/sdd/wave3/whiteout/):
##
##   preset      fog at boom   freshest 2 m of trail   trail in frame
##   pale_day       0.165           36.3 / 255         followable
##   whiteout       0.615           30.1 / 255         followable, ~10 prints
##
## So WHITEOUT throws away 61.5 % of every mark under his feet and the trail is
## still there. The ceiling is set just above what was photographed, NOT at some
## principled limit: past 0.615 nobody has looked.
##
## THE RAMP IS A SMOOTHSTEP, and that was settled by measurement rather than by
## reading `fog_depth_curve = 1.0` (lighting_director.gd:292) and assuming it
## meant linear. Three shots of one patch of open snow at a known depth, under
## TONE_MAPPER_LINEAR so the sRGB transfer can be undone exactly:
##
##   ramp position t   measured fog   smoothstep(t)   linear t
##             0.20        0.0928         0.104         0.200
##             0.50        0.4841         0.500         0.500
##             0.60        0.6327         0.648         0.600
##
## The lighting audit reported this ramp as linear. It is not, and the difference
## is 11 % of the whiteout's own opacity, so the gate uses the measured curve.
const FOG_AT_BOOM_CEILING := 0.70

## The other half of the same ruling, and it exists so that nobody buys the line
## above by softening the storm. 保留，但不删脚印 -- the whiteout keeps striking
## on any day and keeps taking the world; what it may not do is take the ground
## underfoot. A whiteout the player can see through is not a whiteout.
const WHITEOUT_FAR_EDGE_FLOOR := 0.65


## Godot's depth fog, as measured on 4.7.1 -- see the block above.
func _fog_at(preset, distance: float) -> float:
	if not preset.fog_enabled:
		return 0.0
	var span: float = maxf(preset.fog_depth_end - preset.fog_depth_begin, 0.0001)
	var t: float = clampf((distance - preset.fog_depth_begin) / span, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t) * preset.fog_density


func test_no_preset_fogs_away_the_ground_the_player_is_standing_on() -> void:
	var rig := CameraRig.new()
	var boom: float = rig.boom_length
	rig.free()
	var presets := _load_presets()
	assert_false(presets.is_empty(), "no presets loaded, so this gate inspected nothing")
	for name in presets:
		var here := _fog_at(presets[name], boom)
		assert_true(
			here <= FOG_AT_BOOM_CEILING,
			"%s puts %.3f of fog on the %.0f m boom -- the depth the player always "
				% [name, here, boom]
				+ "stands at -- so it throws away that much of every footprint under his "
				+ "feet. The ceiling is %.2f because %.3f is the thickest fog a trail has "
					% [FOG_AT_BOOM_CEILING, 0.615]
				+ "actually been photographed followable through. Past it, re-shoot the "
				+ "trail before moving this number."
		)


func test_the_whiteout_still_takes_the_far_field() -> void:
	var rig := CameraRig.new()
	var boom: float = rig.boom_length
	# The gameplay frame is pitched 45 degrees, so a metre up the screen is a
	# metre further from the camera: the frame's depth span IS its height.
	var far_edge: float = boom + rig.orthographic_size * 0.5
	rig.free()
	var presets := _load_presets()
	if not presets.has("whiteout"):
		assert_true(false, "no res://data/lighting/whiteout.tres to gate")
		return
	var there := _fog_at(presets["whiteout"], far_edge)
	assert_true(
		there >= WHITEOUT_FAR_EDGE_FLOOR,
		"the whiteout leaves %.3f of fog at %.1f m, the far edge of the gameplay frame. "
			% [there, far_edge]
			+ "Below %.2f the storm stops taking the distance, and the storm taking the "
				% WHITEOUT_FAR_EDGE_FLOOR
			+ "distance is the whole of 能见度归零. If this went red buying footprint "
			+ "legibility, the trade is the wrong way round: the near field is the floor, "
			+ "the far field is the storm."
	)
