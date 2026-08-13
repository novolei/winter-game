extends TestCase

## The pause surface's focus feedback -- the focused choice gains one weight
## step and a two-pixel lift while the rest dim to the third opacity step, and
## a settings adjustment lands with a short settle pulse on the value word.

const SpatialScript := preload("res://src/ui/spatial_pause_menu.gd")
const Tokens: UITokens = preload("res://data/ui/tokens.tres")

var _spatial: SpatialPauseMenu = null
var _fonts: UIFonts = null

func before_each() -> void:
	_fonts = UIFonts.new()
	_fonts.build(Tokens)
	_spatial = SpatialScript.new()
	_spatial.setup(Tokens, _fonts)

func after_each() -> void:
	if _spatial != null:
		_spatial.free()
		_spatial = null

func _weight_of(label: Label3D) -> int:
	var variation := label.font as FontVariation
	if variation == null:
		return 0
	var coords: Dictionary = variation.variation_opentype
	return int(coords.values()[0]) if not coords.is_empty() else 0

func test_focus_boldens_the_choice_by_one_weight_step() -> void:
	_spatial.set_state(&"menu")
	_spatial.set_focus(SpatialPauseMenu.CONTINUE)
	var focused := _label(&"Continue")
	var resting := _label(&"Exit")
	assert_eq(_weight_of(focused) - _weight_of(resting),
		SpatialScript.FOCUS_WEIGHT_STEP)

func test_unfocused_choices_dim_to_the_third_opacity_step() -> void:
	_spatial.set_state(&"menu")
	_spatial.set_focus(SpatialPauseMenu.CONTINUE)
	var resting := _label(&"Exit") as Label3D
	assert_almost_eq(resting.modulate.a, Tokens.opacity_steps[2], 0.02)

func test_the_focused_choice_lifts_two_pixels() -> void:
	_spatial.set_state(&"menu")
	_spatial.set_focus(SpatialPauseMenu.EXIT)
	assert_almost_eq(_spatial.focus_lift_for(SpatialPauseMenu.EXIT),
		SpatialScript.FOCUS_LIFT_PIXELS)
	assert_almost_eq(_spatial.focus_lift_for(SpatialPauseMenu.CONTINUE), 0.0)

func test_a_value_pulse_decays_over_a_few_frames() -> void:
	_spatial.set_state(&"settings")
	_spatial.pulse_row_value(&"prompt_hold")
	assert_almost_eq(_spatial.row_pulse(&"prompt_hold"), 1.0)
	for i in range(30):
		_spatial._process(1.0 / 60.0)
	assert_true(_spatial.row_pulse(&"prompt_hold") < 0.1,
		"the settle pulse never decayed")

func test_focus_moves_between_settings_rows() -> void:
	_spatial.set_state(&"settings")
	_spatial.set_focus(&"row_stroke_bold")
	assert_almost_eq(_spatial.focus_lift_for(&"row_stroke_bold"),
		SpatialScript.FOCUS_LIFT_PIXELS)
	assert_almost_eq(_spatial.focus_lift_for(&"row_prompt_hold"), 0.0)

func _label(label_name: String) -> Label3D:
	for label in _spatial.labels():
		if label.name == label_name:
			return label
	return null
