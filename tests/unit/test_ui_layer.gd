extends TestCase

## The layer everything transient lives on -- UI design document section 3.
##
## ---------------------------------------------------------------------------
## THE RULE THIS FILE ENFORCES IS RULE 4
## ---------------------------------------------------------------------------
## "没有东西是常驻的。每个元素诞生时就带着自己的死期." The design document says
## that about the interface; this makes it a property of the SYSTEM rather than
## of each element's author. Whoever adds a prompt does not get to forget to
## remove it, because the layer removes it -- and a leak here is not an untidy
## screen, it is a Control that goes on sitting over the valley for the rest of
## the run.
##
## advance() is public and carries the driving; _process only forwards, the same
## shape as WorldClock, SurvivalSystem, Stove and MontageDirector. So a whole
## element lifetime is playable in a test with no frames.

const UILayerScript := preload("res://src/ui/ui_layer.gd")

var _layer: UILayer = null

func before_each() -> void:
	_layer = UILayerScript.new()
	_layer.build()

func after_each() -> void:
	# CanvasLayer is a Node (briefing constraint 2), and it owns whatever it
	# adopted -- so freeing it is also what proves the adoption was real.
	if _layer != null:
		_layer.free()
		_layer = null

func _panel() -> Control:
	var control := Control.new()
	control.size = Vector2(200.0, 80.0)
	control.position = Vector2(40.0, 60.0)
	return control

# --- what it hands out ------------------------------------------------------

func test_it_carries_the_tokens_and_the_fonts() -> void:
	assert_not_null(_layer.tokens(), "the layer must load data/ui/tokens.tres")
	assert_not_null(_layer.fonts(), "the layer must build the font chains")
	assert_true(_layer.fonts().is_ready())

func test_it_carries_the_interface_voice() -> void:
	assert_not_null(_layer.audio(), "rule 6: every 呵 has a sound")
	assert_true(_layer.audio().cue_count() > 0)

## Section 2.3: everything lives inside the breathing border, and the border is
## taken off the SHORT edge so it reads the same at every aspect ratio.
func test_it_reports_the_breathing_border() -> void:
	assert_almost_eq(_layer.edge_pixels(Vector2(1920, 1080)), 81.0, 0.001)
	assert_almost_eq(_layer.edge_pixels(Vector2(2560, 1080)), 81.0, 0.001)

# --- the lifecycle ----------------------------------------------------------

func test_the_layer_starts_empty() -> void:
	assert_eq(_layer.live_count(), 0)

func test_surfacing_adopts_the_element() -> void:
	_layer.surface(_panel())
	assert_eq(_layer.live_count(), 1)

## An element is invisible on the frame it is handed over. If it were not, it
## would appear at full strength for one frame and then bloom, which is a flash.
func test_an_element_is_invisible_the_moment_it_is_handed_over() -> void:
	var panel := _panel()
	_layer.surface(panel)
	assert_almost_eq(panel.modulate.a, 0.0, 0.0001)

func test_it_blooms_to_full_and_settles_at_its_own_size() -> void:
	var panel := _panel()
	_layer.surface(panel)
	_layer.advance(_layer.tokens().bloom_seconds)
	assert_almost_eq(panel.modulate.a, 1.0, 0.001)
	assert_almost_eq(panel.scale.x, 1.0, 0.001, "the overshoot has to come back to 1")

## Scaling a Control pivots on its top-left corner unless told otherwise, so a
## bloom would grow the element out of its own corner and slide it across the
## screen rather than opening it in place.
func test_the_bloom_scales_from_the_middle_of_the_element() -> void:
	var panel := _panel()
	_layer.surface(panel)
	assert_almost_eq(panel.pivot_offset.x, 100.0, 0.001)
	assert_almost_eq(panel.pivot_offset.y, 40.0, 0.001)

func test_it_drifts_upward_on_the_way_out() -> void:
	var panel := _panel()
	var tokens := _layer.tokens()
	_layer.surface(panel)
	_layer.advance(tokens.bloom_seconds + tokens.hold_seconds + tokens.drift_seconds * 0.999)
	assert_true(panel.position.y < 60.0, "it should have risen from its authored y")
	assert_true(panel.modulate.a < 0.05)

## RULE 4, MECHANICALLY. The element is gone, and the layer is empty again.
func test_the_element_frees_itself_when_its_breath_is_over() -> void:
	_layer.surface(_panel())
	var tokens := _layer.tokens()
	_layer.advance(tokens.bloom_seconds + tokens.hold_seconds + tokens.drift_seconds + 0.01)
	assert_eq(_layer.live_count(), 0, "a surfaced element outlived its own breath")

func test_advancing_an_empty_layer_is_harmless() -> void:
	_layer.advance(10.0)
	assert_eq(_layer.live_count(), 0)

# --- the two-part form ------------------------------------------------------

## Section 5.5's fire line blooms and then stays for as long as the player is
## standing at the fire, which is not a duration anybody can author up front.
func test_a_bloomed_element_holds_until_it_is_dismissed() -> void:
	var panel := _panel()
	_layer.bloom(panel)
	_layer.advance(60.0)
	assert_eq(_layer.live_count(), 1, "bloom() must not put a death on the element")
	assert_almost_eq(panel.modulate.a, 1.0, 0.001)

func test_dismissing_takes_it_away() -> void:
	var panel := _panel()
	_layer.bloom(panel)
	_layer.advance(5.0)
	_layer.dismiss(panel)
	_layer.advance(_layer.tokens().drift_seconds + 0.01)
	assert_eq(_layer.live_count(), 0)

func test_dismissing_something_it_never_had_is_harmless() -> void:
	var stranger := _panel()
	_layer.dismiss(stranger)
	assert_eq(_layer.live_count(), 0)
	stranger.free()

# --- the cold snap ----------------------------------------------------------

## Section 5.6: the cold snap adds nothing to the screen and slows everything
## already on it. Applied to elements that are ALREADY breathing, or the effect
## would only reach whatever happened to appear after the weather turned.
func test_the_cold_snap_slows_what_is_already_on_screen() -> void:
	var panel := _panel()
	_layer.surface(panel)
	var plain: float = _layer.tokens().bloom_seconds + _layer.tokens().hold_seconds \
		+ _layer.tokens().drift_seconds
	_layer.set_time_scale(_layer.tokens().cold_snap_scale)
	# Just past where it would have ended at normal pace: still there, because
	# every phase is now four tenths longer.
	_layer.advance(plain + 0.01)
	assert_eq(_layer.live_count(), 1, "the cold snap did not reach an element already breathing")

func test_clearing_takes_everything_at_once() -> void:
	_layer.surface(_panel())
	_layer.surface(_panel())
	assert_eq(_layer.live_count(), 2)
	_layer.clear()
	assert_eq(_layer.live_count(), 0)
