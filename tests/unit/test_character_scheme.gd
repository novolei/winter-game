extends TestCase

## Two looks for the wanderer, and the shape of the data that holds them.
##
## The dark silhouette and the pale Meshy palette are both defensible -- one
## separates from bright snow at gameplay framing, the other shows the character
## the model was painted as -- and the owner asked for both rather than for a
## verdict. What these tests protect is that the *choice* stays data: a third
## look must be a new `.tres` under data/characters/ and nothing else, which is
## the standing rule (briefing section 2.4) and the reason this is a Resource at
## all instead of two branches in player_controller.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const SCHEME_DIR := "res://data/characters"


func _schemes() -> Array:
	var found: Array = []
	var dir := DirAccess.open(SCHEME_DIR)
	if dir == null:
		return found
	for file in dir.get_files():
		# Exported projects rename .tres to .remap; the gates elsewhere in this
		# suite run from source, so plain .tres is enough here.
		if file.ends_with(".tres"):
			found.append("%s/%s" % [SCHEME_DIR, file])
	found.sort()
	return found


func test_every_scheme_on_disk_loads_and_is_a_character_scheme() -> void:
	var paths := _schemes()
	assert_true(paths.size() >= 2, "expected at least the two shipped looks, found %d" % paths.size())
	for path in paths:
		var scheme = load(path)
		assert_true(scheme is CharacterScheme, "%s did not load as a CharacterScheme" % path)
		if scheme is CharacterScheme:
			assert_true(String(scheme.id) != "", "%s has no id" % path)
			assert_true(scheme.display_name != "", "%s has no display_name" % path)


func test_no_two_schemes_share_an_id() -> void:
	var seen: Dictionary = {}
	for path in _schemes():
		var scheme = load(path)
		if not (scheme is CharacterScheme):
			continue
		assert_false(seen.has(scheme.id), "two schemes both call themselves %s" % scheme.id)
		seen[scheme.id] = path


## The player's default has to name a scheme that exists, or the figure is
## painted by whatever StandardMaterial3D defaults to -- white plastic -- and
## the only symptom is a screenshot.
func test_the_player_s_default_scheme_exists() -> void:
	var controller: PlayerController = PlayerControllerScript.new()
	var path: String = controller.scheme_path
	# Node, not RefCounted (briefing section 2.2).
	controller.free()
	assert_true(ResourceLoader.exists(path), "player_controller defaults to %s and there is no such file" % path)
	var scheme = load(path)
	assert_true(scheme is CharacterScheme, "%s is not a CharacterScheme" % path)


## The two shipped looks must actually be two looks. A pair of schemes that
## render the same is the failure this whole feature exists to avoid, and it is
## invisible in every other test.
func test_the_dark_look_is_substantially_darker_than_the_pale_one() -> void:
	var pale = load("%s/wanderer_pale.tres" % SCHEME_DIR)
	var dark = load("%s/wanderer_dark.tres" % SCHEME_DIR)
	assert_not_null(pale)
	assert_not_null(dark)
	if pale == null or dark == null:
		return
	var pale_linear := (pale.albedo_tint as Color).srgb_to_linear()
	var dark_linear := (dark.albedo_tint as Color).srgb_to_linear()
	var pale_luma := 0.2126 * pale_linear.r + 0.7152 * pale_linear.g + 0.0722 * pale_linear.b
	var dark_luma := 0.2126 * dark_linear.r + 0.7152 * dark_linear.g + 0.0722 * dark_linear.b
	assert_true(
		dark_luma < pale_luma * 0.35,
		"dark renders at %f of the frame's light against pale's %f; that is not a "
			% [dark_luma, pale_luma]
			+ "silhouette, it is the same coat slightly dimmed"
	)
	# The scarf is the one thing that survives a silhouette, so the tint must not
	# be so cold that it takes the warm accent with it.
	assert_true(
		dark_linear.r > 0.0, "the dark look has no red left at all; the scarf is gone"
	)


## A silhouette has no interior form to reveal, so it does not pay for a key
## light -- and the fact that the scheme decides that, rather than a constant in
## player_controller, is the data-driven claim.
func test_the_scheme_decides_whether_there_is_a_key_light() -> void:
	var pale = load("%s/wanderer_pale.tres" % SCHEME_DIR)
	var dark = load("%s/wanderer_dark.tres" % SCHEME_DIR)
	if pale == null or dark == null:
		return
	assert_true(pale.key_energy > 0.0, "the pale look has no key light and reads flat")
	assert_eq(dark.key_energy, 0.0, "the silhouette pays for a key light it cannot show")
