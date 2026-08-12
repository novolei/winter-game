extends TestCase

## The material the interface is made of.
##
## ---------------------------------------------------------------------------
## WHAT THIS FILE CAN AND CANNOT PROVE
## ---------------------------------------------------------------------------
## It CANNOT prove the shader draws ice. The suite runs headless, inside one
## frame, with a dummy rendering driver -- it never compiles a `.gdshader` and
## would stay green over one that fails to. That gap is a registered open class
## in DEFERRED.md and the shader was verified the only way currently available:
## by running the scene and reading the console.
##
## What it CAN prove is everything on this side of the boundary -- that the
## material is built, that every uniform the shader declares is actually being
## written, that growth and rime move the way the direction says, and that no
## colour reaches the material from anywhere but the palette. Those are the
## failures that look like art direction rather than like bugs.

const FrostScript := preload("res://src/ui/frost.gd")
const TOKENS_PATH := "res://data/ui/tokens.tres"

var _tokens: UITokens = null
var _frost: Frost = null

func before_each() -> void:
	_tokens = ResourceLoader.load(TOKENS_PATH) as UITokens
	_frost = FrostScript.new()
	_frost.build(_tokens)

# Frost is RefCounted and so is everything it holds -- ShaderMaterial, Shader,
# ImageTexture -- so there is nothing to free (briefing constraint 2 is about
# Node).

# --- it exists ---------------------------------------------------------------

func test_the_shader_is_on_disk_and_loads() -> void:
	assert_true(ResourceLoader.exists(Frost.SHADER_PATH),
		"the material has no shader at %s" % Frost.SHADER_PATH)
	assert_not_null(ResourceLoader.load(Frost.SHADER_PATH) as Shader)

func test_it_builds_a_material() -> void:
	assert_true(_frost.is_ready())
	assert_not_null(_frost.material)
	assert_not_null(_frost.material.shader)

## The canvas the element draws through. draw_rect() has no texture and what a
## shader reads for UV in that case is not worth depending on; the textured form
## is defined.
func test_it_carries_a_one_pixel_canvas() -> void:
	var canvas := _frost.canvas()
	assert_not_null(canvas)
	assert_eq(canvas.get_width(), 1)
	assert_eq(canvas.get_height(), 1)

# --- every uniform is actually written ---------------------------------------

## The failure this catches is a uniform renamed in the shader and not here.
## Nothing errors -- set_shader_parameter() on a name the shader does not
## declare is silently ignored, and get_shader_parameter() then returns null --
## so the effect simply stops happening and looks like a tuning problem.
func test_every_uniform_the_shader_declares_is_written() -> void:
	_frost.set_substrate(Vector2(40, 200), Vector2(20, 190), Vector2(20, 10), 0.0)
	_frost.set_fill(0.5)
	_frost.set_weights(1.0, 3.0, 9.0)
	_frost.set_outline(1.0)
	_frost.set_seed(3.0)
	_frost.set_body_alpha(0.42)
	_frost.set_mark(true, _tokens.life_warm)
	_frost.set_target_emphasis(1.0)
	_frost.advance(1.0)

	var unwritten: Array[String] = []
	for entry in _frost.material.shader.get_shader_uniform_list():
		var name := StringName(entry["name"])
		if _frost.material.get_shader_parameter(name) == null:
			unwritten.append(String(name))
	assert_eq(unwritten.size(), 0,
		"uniforms the shader declares that nothing ever sets: %s" % ", ".join(unwritten))

# --- it grows, it does not fade in -------------------------------------------

## Property 1 of the direction. At growth 0 there is no readout at all -- not a
## transparent one, NONE -- and it arrives by crystallising along itself.
func test_it_starts_at_nothing() -> void:
	assert_almost_eq(_frost.growth, 0.0, 0.0001)
	assert_almost_eq(float(_frost.material.get_shader_parameter(&"growth")), 0.0, 0.0001)

func test_it_grows_monotonically_and_stops_at_full() -> void:
	var last := 0.0
	for step in range(40):
		_frost.advance(0.05)
		assert_true(_frost.growth >= last, "the ice went backwards")
		last = _frost.growth
	assert_almost_eq(_frost.growth, 1.0, 0.0001)

## Crystallisation is slower than the 呵. Section 2.4's 200 ms governs the
## element's ARRIVAL; 200 ms of creeping frost is a pop rather than a growth.
func test_the_ice_takes_longer_than_the_bloom() -> void:
	assert_true(Frost.GROWTH_SECONDS > _tokens.bloom_seconds * 2.0,
		"a bloom-length crystallisation is a pop, not a growth")

func test_a_harness_can_photograph_a_finished_one() -> void:
	_frost.set_target_emphasis(0.8)
	_frost.finish()
	assert_almost_eq(_frost.growth, 1.0, 0.0001)
	assert_almost_eq(_frost.rime, 0.8, 0.0001)

# --- it accumulates and it clears --------------------------------------------

## Property 5. And it arrives LATE, which is what makes it a cue rather than a
## gauge -- the briefing's own note on cues says a viewer believes in a world
## because something is late.
func test_rime_chases_its_target_rather_than_snapping_to_it() -> void:
	_frost.set_target_emphasis(1.0)
	_frost.advance(0.5)
	assert_true(_frost.rime > 0.0, "it must start closing")
	assert_true(_frost.rime < 0.5,
		"half a second must not deliver most of the accumulation -- ice that "
		+ "tracked the cold exactly reads as a gauge being driven")
	_frost.advance(60.0)
	assert_almost_eq(_frost.rime, 1.0, 0.01)

func test_warmth_clears_it_again() -> void:
	_frost.set_target_emphasis(1.0)
	_frost.advance(60.0)
	_frost.set_target_emphasis(0.1)
	_frost.advance(60.0)
	assert_almost_eq(_frost.rime, 0.1, 0.01)

## Emphasis by material: a threshold breaking thickens the ice at once, and the
## ordinary chase takes it back down with no element added and none removed.
func test_a_surge_thickens_at_once_and_then_clears() -> void:
	_frost.set_target_emphasis(0.3)
	_frost.advance(60.0)
	_frost.surge(1.0)
	assert_almost_eq(_frost.rime, 1.0, 0.0001, "a surge is immediate or it is not emphasis")
	_frost.advance(60.0)
	assert_almost_eq(_frost.rime, 0.3, 0.02, "and it has to come back down by itself")

func test_a_surge_never_lowers_the_ice() -> void:
	_frost.set_target_emphasis(1.0)
	_frost.advance(60.0)
	var before: float = _frost.rime
	_frost.surge(0.2)
	assert_true(_frost.rime >= before,
		"a surge asking for less ice than there already is must leave it alone")

# --- section 5.6 -------------------------------------------------------------

func test_the_cold_snap_slows_the_ice_too() -> void:
	var plain := FrostScript.new()
	plain.build(_tokens)
	plain.advance(Frost.GROWTH_SECONDS)
	assert_almost_eq(plain.growth, 1.0, 0.0001)

	_frost.set_time_scale(_tokens.cold_snap_scale)
	_frost.advance(Frost.GROWTH_SECONDS)
	assert_true(_frost.growth < 0.99,
		"a cold snap must reach the material as well as the envelope")

func test_a_nonsense_time_scale_is_refused() -> void:
	_frost.set_time_scale(0.0)
	_frost.set_time_scale(-3.0)
	_frost.advance(Frost.GROWTH_SECONDS)
	assert_almost_eq(_frost.growth, 1.0, 0.0001)

func test_a_nonsense_delta_does_nothing() -> void:
	_frost.advance(0.0)
	_frost.advance(-1.0)
	_frost.advance(NAN)
	assert_almost_eq(_frost.growth, 0.0, 0.0001)

# --- constraint 6 -------------------------------------------------------------

## No hex anywhere on this path. Every colour the material carries has to BE a
## palette entry -- and the shader's own defaults are white, so an unset uniform
## is obvious on screen rather than plausible.
func test_every_colour_it_writes_is_in_the_palette() -> void:
	var palette := ResourceLoader.load("res://data/palette/color_bible.tres") as ColorBible
	assert_not_null(palette)
	_frost.set_colours(_tokens)
	_frost.set_mark(true, _tokens.life_warm)
	for name in [&"trough_colour", &"fill_colour", &"rim_colour", &"outline_colour",
			&"mark_colour"]:
		var value = _frost.material.get_shader_parameter(name)
		assert_not_null(value, "%s was never written" % name)
		if value != null:
			assert_true(palette.contains(value),
				"%s is not one of the twelve: %s" % [name, value])

## The one warm uniform is off until heat is actually going in. Rule 3 does not
## allow a warm pixel to mean "look at this".
func test_the_warm_mark_is_off_by_default() -> void:
	assert_almost_eq(float(_frost.material.get_shader_parameter(&"mark_on")), 0.0, 0.0001)

# --- the absent shader --------------------------------------------------------

## A missing shader is a legal inert state: the element draws nothing rather
## than taking the scene down with it.
func test_a_missing_shader_is_inert_rather_than_fatal() -> void:
	var orphan: Frost = FrostScript.new()
	# Every setter has to survive being called on it, because the element that
	# owns one does not check before every call.
	orphan.set_substrate(Vector2.ONE, Vector2.ZERO, Vector2.ONE, 1.0)
	orphan.set_fill(0.5)
	orphan.set_weights(1.0, 2.0, 3.0)
	orphan.set_outline(1.0)
	orphan.set_colours(_tokens)
	orphan.set_mark(true, Color.WHITE)
	orphan.set_seed(1.0)
	orphan.set_body_alpha(0.5)
	orphan.surge(1.0)
	orphan.advance(1.0)
	orphan.finish()
	assert_false(orphan.is_ready())
