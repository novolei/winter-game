extends TestCase

## The character is the only thing in this game lit by Godot's stock PBR, and
## that fact is load-bearing in a way nothing wrote down until it caused a
## defect.
##
## Every shader in the project declares `ambient_light_disabled`, so the
## Environment's ambient reaches the character and nothing else. It had been set
## to the palette's darkest navy at 0.35 on the reasoning that it "reaches
## nothing that matters" -- and since the sun is at azimuth 118 against a camera
## yawed -35, nearly behind the lens, that near-black fill was very nearly the
## whole of the light on every surface of the figure the camera could see. The
## coat sampled off the rendered frame at **#02050C**. The character was a
## silhouette, the owner reported it as "no textures", and no gate saw a thing:
## the art gates read materials and meshes on disk, and this was two numbers on
## an Environment built at runtime.
##
## These four tests are that gate. The first is the one that matters most,
## because it pins the *premise* rather than the value: the day someone adds a
## world shader without `ambient_light_disabled`, this number silently stops
## being a character control and starts being a world light.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const LightingDirectorScript := preload("res://src/rendering/lighting_director.gd")
const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const SCHEME_PATH := "res://data/characters/wanderer_pale.tres"
const SHADER_ROOT := "res://assets/shaders"


## The fill the Environment is ACTUALLY built with, read off the Environment.
##
## Not recomputed from the exported knobs, and the difference is the whole value
## of this file: the first version of these tests re-derived the colour from
## `character_fill_tint`, and restoring the shipped defect -- the assignment line
## put back to `structure_tones[2]` -- left them green. A gate that reproduces
## the code it is checking is checking nothing.
##
## `_ready()` is called by hand because nothing has been added to the tree
## (briefing trap 1). It returns early at the `Sun` lookup, which is after the
## Environment is built and is all this needs.
func _fill() -> Color:
	var director: LightingDirector = LightingDirectorScript.new()
	director._ready()
	var env := director.environment
	var colour: Color = env.ambient_light_color
	var energy: float = env.ambient_light_energy
	var source: int = env.ambient_light_source
	# Node, not RefCounted (briefing section 2.2).
	director.free()
	if source != Environment.AMBIENT_SOURCE_COLOR:
		# Anything else and the two numbers below are not what lights the figure.
		return Color(0.0, 0.0, 0.0)
	var linear := colour.srgb_to_linear()
	return Color(linear.r * energy, linear.g * energy, linear.b * energy)


## THE PREMISE. Ambient is a character-only control only for as long as every
## other shader refuses it.
## SCOPED TO SPATIAL SHADERS, and the scoping is the premise rather than a
## loophole in it.
##
## `ambient_light_disabled` is a render_mode that only `shader_type spatial`
## has. A canvas_item shader cannot declare it -- the line is a compile error
## there -- and does not need to: ambient light does not reach a canvas item at
## all, so it refuses the fill by construction rather than by declaration.
##
## Unscoped, this gate asserted a proxy (does the file contain a string) instead
## of the property it exists to protect (can this shader receive the character
## fill). The first canvas_item shader in the project failed it while satisfying
## the premise completely -- assets/shaders/montage_film.gdshader, the montage's
## grain and vignette pass.
##
## The anti-vacuity guard moves with the scoping. Counting all shaders would let
## the spatial set fall to zero unnoticed while the total stayed healthy, which
## is exactly the shape of silent-skip this project has closed four times.
func test_every_shader_in_the_project_still_disables_ambient() -> void:
	var shaders := AssetScannerScript.find_files(SHADER_ROOT, [".gdshader"])
	var spatial: Array[String] = []
	for path in shaders:
		if FileAccess.get_file_as_string(path).contains("shader_type spatial"):
			spatial.append(path)
	assert_true(
		spatial.size() >= 2,
		"found %d spatial shaders among %d under %s; this gate means nothing if it inspected none"
			% [spatial.size(), shaders.size(), SHADER_ROOT]
	)
	for path in spatial:
		var text := FileAccess.get_file_as_string(path)
		assert_true(
			text.contains("ambient_light_disabled"),
			"%s does not declare ambient_light_disabled, so LightingDirector's "
				% path
				+ "character fill is now a world light and the whole frame has moved"
		)


## The value. Reproduces the render arithmetic rather than a screenshot: a
## surface renders at albedo * illumination * exposure, so a fill this far below
## the light the snow is drawn at cannot lift any albedo out of black.
func test_the_character_fill_is_brighter_than_the_snow_it_bounces_off() -> void:
	var bible = load(LightingDirectorScript.PALETTE_PATH)
	var fill := _fill()
	var darkest: Color = bible.snow_tones[bible.snow_tones.size() - 1].srgb_to_linear()
	var fill_luma := 0.2126 * fill.r + 0.7152 * fill.g + 0.0722 * fill.b
	var snow_luma := 0.2126 * darkest.r + 0.7152 * darkest.g + 0.0722 * darkest.b
	assert_true(
		fill_luma >= snow_luma,
		"the character's fill is %f against the darkest snow tone's %f: a figure "
			% [fill_luma, snow_luma]
			+ "standing on a snowfield is filled by the snow, not by less than it"
	)


## The tint. A fill this blue drives the coat's blue channel to clipping while
## its red is still at a quarter, and the coat stops reading as the blue-grey it
## is painted -- measured at four energies before this number was chosen.
func test_the_character_fill_is_near_neutral() -> void:
	var fill := _fill()
	var high := maxf(fill.r, maxf(fill.g, fill.b))
	var low := minf(fill.r, minf(fill.g, fill.b))
	assert_true(low > 0.0, "the fill has a zero channel")
	assert_true(
		high / low <= 1.6,
		"the character's fill spans %f between its brightest and dimmest channel; "
			% (high / low)
			+ "past about 1.6 the coat renders as saturated blue rather than blue-grey"
	)
	# And the premise of that check: the palette tone it is mixed from really is
	# blue enough to matter, so passing means the mix did the work.
	var snow = load(LightingDirectorScript.PALETTE_PATH).snow_tones[0].srgb_to_linear()
	assert_true(
		snow.b / snow.r > 2.0,
		"snow_tones[0] is not actually blue, so this test proves nothing"
	)


## The key light exists to model the figure, and it must light only the figure:
## every other surface is on a cel shader whose light() would add it a second
## time and lay a second shadow band across the snow.
func test_the_character_key_light_reaches_the_character_and_nothing_else() -> void:
	var controller: PlayerController = PlayerControllerScript.new()
	controller.scheme_path = SCHEME_PATH
	controller._scheme = load(SCHEME_PATH) as CharacterScheme
	assert_not_null(controller._scheme, "no CharacterScheme at %s" % SCHEME_PATH)
	controller._build_key_light()
	var key := controller.get_node_or_null("KeyLight") as DirectionalLight3D
	assert_not_null(key, "the pale scheme asks for a key light and none was built")
	if key != null:
		assert_eq(
			key.light_cull_mask, PlayerControllerScript.CHARACTER_LAYER,
			"the key light is not culled to the character's own layer"
		)
		assert_false(key.shadow_enabled, "the character's key light must not cast")
	assert_true(
		PlayerControllerScript.CHARACTER_LAYER != 1,
		"CHARACTER_LAYER is the default layer, so culling to it culls nothing"
	)
	controller.free()
