extends TestCase

## The character reads through what stands in front of him.
##
## ---------------------------------------------------------------------------
## WHY THIS IS A FEATURE AND NOT A NICETY
## ---------------------------------------------------------------------------
## Art Bible rule 1's last row is "旋转：永不旋转，只跟随" -- the camera never
## rotates, it only follows. That is the whole of the reason this exists. In a
## game with a swingable camera, walking behind the farmhouse is a thing the
## player fixes with the right stick. Here there is no stick: the frame is fixed
## at 45 degrees and yawed -35, and the house, the trees and the pole sit
## between the lens and the player constantly. The owner reported the character
## disappearing, and the reference frame from the source video shows the answer
## -- the figure reads THROUGH the geometry as a soft silhouette while the
## trunks and branches stay fully drawn.
##
## ---------------------------------------------------------------------------
## THE TECHNIQUE, AND THE ONE THING IT DEPENDS ON
## ---------------------------------------------------------------------------
## `BaseMaterial3D.stencil_mode = STENCIL_MODE_XRAY`. The character's own
## material writes the stencil buffer wherever it passes the depth test; Godot
## builds it a second pass that draws unshaded, alpha-blended, with the depth
## test off and the stencil compared NOT_EQUAL -- so the ghost lands on exactly
## the pixels where the figure was hidden and on no others.
##
## Nothing about the occluders changes. That matters: they are cel-shaded,
## palette-coloured and specular-disabled by Art Bible rules 8 and 9, and
## tests/art/test_shading_features.gd enforces it. Fading the house instead
## would have meant touching every world material and widening that exemption.
## The character is already exempt (§2's exception box), so the whole effect
## lives on the one material that was allowed to carry it.
##
## The first test below pins the engine contract the effect rests on. It is
## worth a test of its own because if a Godot update changed what X-Ray sets up,
## the symptom would be a screenshot nobody was looking at.

const SCHEME_DIR := "res://data/characters"
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const CONTROLLER_SOURCE := "res://src/entities/player/player_controller.gd"


func _schemes() -> Array:
	var found: Array = []
	var dir := DirAccess.open(SCHEME_DIR)
	if dir == null:
		return found
	for file in dir.get_files():
		if file.ends_with(".tres"):
			found.append("%s/%s" % [SCHEME_DIR, file])
	found.sort()
	return found


# --- the engine contract -----------------------------------------------------

## What STENCIL_MODE_XRAY actually builds, measured on 4.7.1 rather than assumed.
##
## Every clause here is load-bearing:
##
##   next_pass         there is a second draw of the same geometry at all
##   UNSHADED          the ghost is a flat silhouette, not a lit figure -- a lit
##                     one would read as the character standing in front
##   TRANSPARENCY_ALPHA the alpha in stencil_color is what reaches the screen
##   no_depth_test     the pass is not thrown away by the depth buffer that hid
##                     the first one
##   READ + NOT_EQUAL  and yet it lands ONLY where the first pass did not draw,
##                     which is the entire difference between an x-ray and a
##                     character painted over the top of the scenery
func test_the_engine_still_builds_the_x_ray_pass_this_effect_rests_on() -> void:
	var material := StandardMaterial3D.new()
	material.stencil_color = Color(0.56, 0.69, 0.85, 0.45)
	material.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY

	assert_eq(
		material.stencil_flags, BaseMaterial3D.STENCIL_FLAG_WRITE,
		"the visible pass must WRITE the stencil, or the ghost has nothing to test against"
	)
	var ghost = material.next_pass
	assert_not_null(ghost, "X-Ray must build a second pass; without one nothing is drawn through anything")
	if not (ghost is BaseMaterial3D):
		return
	var second := ghost as BaseMaterial3D
	assert_eq(second.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "the ghost must be a flat silhouette")
	assert_eq(second.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "the ghost must be alpha-blended")
	assert_true(second.no_depth_test, "the ghost must survive the depth buffer that hid the first pass")
	assert_eq(
		second.stencil_flags, BaseMaterial3D.STENCIL_FLAG_READ,
		"the ghost must READ the stencil rather than write it"
	)
	assert_eq(
		second.stencil_compare, BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL,
		"NOT_EQUAL is what confines the ghost to the pixels where the figure was hidden"
	)
	assert_eq(
		second.albedo_color, material.stencil_color,
		"the ghost's colour and alpha must be the scheme's stencil_color"
	)


# --- the scheme --------------------------------------------------------------

func test_a_scheme_dresses_a_material_in_its_own_ghost() -> void:
	var scheme := CharacterScheme.new()
	scheme.ghost_color = Color(0.4, 0.6, 0.9, 0.5)
	var material := StandardMaterial3D.new()
	scheme.wear_ghost(material)
	assert_eq(material.stencil_mode, BaseMaterial3D.STENCIL_MODE_XRAY)
	assert_eq(material.stencil_color, scheme.ghost_color)
	assert_not_null(material.next_pass, "no second pass was built, so nothing reads through anything")


## The whole feature must be switchable from data, per the standing rule that a
## look is a `.tres` and not a branch. Alpha zero is a ghost nobody can see, so
## it is the off switch rather than a second field that can disagree with it.
func test_a_scheme_that_asks_for_no_alpha_gets_no_second_pass() -> void:
	var scheme := CharacterScheme.new()
	scheme.ghost_color = Color(0.4, 0.6, 0.9, 0.0)
	var material := StandardMaterial3D.new()
	scheme.wear_ghost(material)
	assert_eq(material.stencil_mode, BaseMaterial3D.STENCIL_MODE_DISABLED)
	assert_true(material.next_pass == null, "an invisible ghost must not cost a second draw of the character")


## Art Bible rule 12: warm pixels are reserved for fire, lit windows, beacons,
## the scarf and the truck. A ghost is drawn over the darkest geometry in the
## frame -- the trees are `#131C30` -- so a warm one would be the loudest thing
## on screen and would read as one of the five things it is not.
func test_no_ghost_is_a_warm_shape() -> void:
	var bible = load(PALETTE_PATH)
	assert_not_null(bible, "the palette must load for this test to mean anything")
	for path in _schemes():
		var scheme = load(path)
		if not (scheme is CharacterScheme):
			continue
		var ghost: Color = scheme.ghost_color
		if ghost.a <= 0.0:
			continue
		assert_false(
			bible.is_warm(Color(ghost.r, ghost.g, ghost.b)),
			"%s ghosts in %s, which is one of rule 12's three warm tones" % [path, ghost.to_html(false)]
		)
		assert_true(
			ghost.b > ghost.r + 0.15,
			"%s ghosts in %s -- rule 12 reserves warm pixels, and that is not a cool colour"
				% [path, ghost.to_html(false)]
		)


## The ghost is drawn over the world, so it takes a world colour. Nothing about
## the character's own exemption from the 12-colour table licenses inventing a
## thirteenth colour and painting a third of the screen with it.
func test_every_ghost_is_a_colour_from_the_palette() -> void:
	var bible = load(PALETTE_PATH)
	assert_not_null(bible)
	var seen := 0
	for path in _schemes():
		var scheme = load(path)
		if not (scheme is CharacterScheme):
			continue
		var ghost: Color = scheme.ghost_color
		if ghost.a <= 0.0:
			continue
		seen += 1
		assert_true(
			bible.contains(Color(ghost.r, ghost.g, ghost.b)),
			"%s ghosts in %s, which is not in data/palette/color_bible.tres" % [path, ghost.to_html(false)]
		)
	assert_true(seen > 0, "no shipped scheme asks for a ghost at all, so the feature is off everywhere")


## The figure has to separate from what it is drawn over, and what it is drawn
## over is the darkest geometry in the game. A ghost darker than a tree is a
## character who is still invisible, with a second draw call to pay for it.
func test_every_ghost_is_brighter_than_the_trees_it_shows_through() -> void:
	var bible = load(PALETTE_PATH)
	assert_not_null(bible)
	if bible == null:
		return
	var tree: Color = bible.structure_tones[3]
	var tree_luma := 0.2126 * tree.r + 0.7152 * tree.g + 0.0722 * tree.b
	for path in _schemes():
		var scheme = load(path)
		if not (scheme is CharacterScheme) or scheme.ghost_color.a <= 0.0:
			continue
		var ghost: Color = scheme.ghost_color
		var luma := 0.2126 * ghost.r + 0.7152 * ghost.g + 0.0722 * ghost.b
		assert_true(
			luma > tree_luma * 3.0,
			"%s ghosts at luma %.3f against a tree at %.3f -- it would not read through one"
				% [path, luma, tree_luma]
		)


# --- the wiring --------------------------------------------------------------

## The one line that connects the two.
##
## Read off the source rather than exercised, and that is a deliberate trade
## rather than laziness: reaching the material means `PlayerController` builds
## its body, which loads a 2.6 MB model, a 15 MB albedo and a twenty-take
## animation library -- for one property. The behaviour either side of the line
## is tested properly above and in test_character_scheme.gd; what is left is
## whether anybody calls it, and a missing call has exactly one symptom, which
## is a screenshot nobody took.
func test_the_player_dresses_its_body_material_in_the_scheme_s_ghost() -> void:
	var source := FileAccess.get_file_as_string(CONTROLLER_SOURCE)
	assert_true(source != "", "%s could not be read" % CONTROLLER_SOURCE)
	assert_true(
		source.contains("wear_ghost(body_material)"),
		"%s never calls wear_ghost() on the material the figure is drawn with, so the character still disappears behind the house"
			% CONTROLLER_SOURCE
	)
