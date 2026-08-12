class_name Frost
extends VitalPaint

## PARKED. One implementation of VitalPaint, behind the seam.
##
## ---------------------------------------------------------------------------
## STATUS: BUILT, VERIFIED, AND WITHDRAWN BY THE OWNER
## ---------------------------------------------------------------------------
## This is the frost language: the readout is not decorated with ice, it IS ice,
## grown from a seed along a substrate rather than faded in, hard-edged and
## translucent, refracting rather than glowing, and accumulating with how cold
## the body is. It compiles, it draws, and there are captures of it.
##
## The owner has withdrawn it as more than he wants and the look is undecided
## again. It is kept rather than deleted because it may come back in reduced
## form, and because it is the worked example of what a VitalPaint has to do.
##
## NOTHING IN FRONT OF THE SEAM DEPENDS ON IT. VitalStroke names it once, in a
## single const; a replacement look is that const and a new file.
##
## One piece of ice: the ShaderMaterial that assets/shaders/frost_arc.gdshader
## draws through, and the clock that grows it.
##
## ---------------------------------------------------------------------------
## THE MATERIAL IS THE ELEMENT, NOT AN EFFECT ON IT
## ---------------------------------------------------------------------------
## Nothing that uses this draws a bar and then frosts it. The caller hands over a
## substrate -- two points and a bow -- and the ice is the entire visual. So this
## object is not a decorator that can be switched off; switching it off leaves
## nothing on screen, which is the correct behaviour for a material.
##
## ---------------------------------------------------------------------------
## WHY THE ELEMENT DRAWS A TEXTURE RECT AND NOT A draw_rect()
## ---------------------------------------------------------------------------
## The shader needs UV across the element's own bounds. `draw_rect(rect, colour)`
## has no texture, and what a shader reads for UV in that case is not something
## worth depending on. `draw_texture_rect()` with a 1x1 white image is defined:
## UV runs 0..1 across the destination rectangle, every time. canvas() hands out
## that texture.
##
## The rectangle is a canvas, not a shape. Nothing rectangular reaches the
## screen -- the shader decides what exists inside it, and what exists is
## needles. Rule 1 is about the picture, and the picture is arcs.
##
## ---------------------------------------------------------------------------
## GROWTH IS NOT THE 呵
## ---------------------------------------------------------------------------
## Section 2.4's bloom is 200 ms and it governs the element's ARRIVAL -- its
## opacity and its scale, driven by UILayer. Crystallisation is a property of the
## material and it is slower, because 200 ms of creeping frost is a pop rather
## than a growth. Three bloom-lengths is long enough to read as ice forming and
## short enough that a readout is legible almost at once.
##
## Both are subject to section 5.6's cold snap, through set_time_scale().

const SHADER_PATH := "res://assets/shaders/frost_arc.gdshader"

## Three 呵 lengths. See the header.
const GROWTH_SECONDS := 0.62

## How fast rime chases what it is told to be. Slow on purpose: frost thickening
## is a thing you notice having happened, not a thing you watch happen. A readout
## that tracked the cold exactly would read as a gauge being driven rather than
## as ice on a window -- the briefing's own cue-versus-tell note, which says a
## cue earns belief by ARRIVING LATE.
const RIME_SECONDS := 9.0

## How far a needle reaches at full rime, in design pixels. Held here rather
## than at the call site because the substrate's clear space is sized from it and
## the two must not be able to disagree -- a needle longer than the padding is
## clipped by the element's own bounds, and a clipped needle has a flat end,
## which is the one thing property 2 says a crystal never has.
const NEEDLE_DESIGN_PX := 9.0

## Primary needles per 100 design pixels of substrate. Frost is not a fringe:
## many more than this reads as a comb, many fewer as a row of ticks.
const NEEDLE_DENSITY := 9.0

## The refraction sliver's width, and how much of the rim colour it takes. Hard
## and narrow -- property 4 is a caught edge, not a bloom.
const RIM_DESIGN_PX := 1.6
const RIM_STRENGTH := 1.0

## Where the light comes from, in the element's own space: up and to the left,
## matching the valley's low sun coming over the player's shoulder.
const LIGHT_DIR := Vector2(-0.6, -0.8)

## Property 3: you see the valley through the ice, and its boundary is still a
## line. The interior sits here and the silhouette goes opaque.
const BODY_ALPHA := 0.42

## What a stroke weighs before anybody says otherwise.
const FILL_DEFAULT_PX := 3.0

## How far a threshold's crystal terminal stands off the gauge, in design px.
const MARKER_DESIGN_PX := 5.0

var material: ShaderMaterial = null

## 0 = bare substrate, nothing on screen. 1 = the ice has reached the far end.
var growth := 0.0

var rime := 0.0

var _target_rime := 0.0
var _elapsed := 0.0
var _time_scale := 1.0
var _canvas: ImageTexture = null


## Loads the shader and builds the material. False when the shader is not there,
## which is a legal inert state: the element draws nothing rather than taking the
## scene down with it.
##
## ResourceLoader.exists() is asked FIRST because load() on a missing path logs
## three ERROR lines before returning null, and by this project's standard a
## dirty console is a failed run whether or not the absence was handled.
func build(tokens: UITokens) -> bool:
	if not ResourceLoader.exists(SHADER_PATH):
		return false
	var shader := ResourceLoader.load(SHADER_PATH) as Shader
	if shader == null:
		return false
	material = ShaderMaterial.new()
	material.shader = shader
	set_colours(tokens)

	# EVERY uniform is written here, including the ones nothing ever changes.
	#
	# set_shader_parameter() on a name the shader does not declare is silently
	# ignored, and get_shader_parameter() on one that was never written returns
	# NULL rather than the shader's default. So a uniform renamed on one side of
	# this boundary and not the other stops having any effect, raises nothing,
	# and reads on screen as a tuning problem. tests/unit/test_frost.gd walks the
	# shader's own uniform list against this.
	material.set_shader_parameter(&"needle_density", NEEDLE_DENSITY)
	material.set_shader_parameter(&"rim_px", RIM_DESIGN_PX)
	material.set_shader_parameter(&"rim_strength", RIM_STRENGTH)
	material.set_shader_parameter(&"light_dir", LIGHT_DIR)
	material.set_shader_parameter(&"body_alpha", BODY_ALPHA)
	material.set_shader_parameter(&"outline_px", 1.0)
	material.set_shader_parameter(&"seed", 0.0)
	material.set_shader_parameter(&"fill", 1.0)
	material.set_shader_parameter(&"centre_px", Vector2.ZERO)
	material.set_shader_parameter(&"radius_px", 1.0)
	material.set_shader_parameter(&"start_rad", 0.0)
	material.set_shader_parameter(&"span_rad", TAU)
	set_markers(Vector4(-1.0, -1.0, -1.0, -1.0), MARKER_DESIGN_PX)
	set_substrate(Vector2.ONE, Vector2.ZERO, Vector2.RIGHT, 0.0)
	set_weights(1.0, FILL_DEFAULT_PX, NEEDLE_DESIGN_PX)
	set_mark(false, Color.TRANSPARENT if tokens == null else tokens.life_warm)
	_publish()
	return true


func is_ready() -> bool:
	return material != null


## The 1x1 white image the element draws through. Built on demand and owned by
## this object, so it goes when the element goes -- a statically cached texture
## would still be held at shutdown and "resources still in use at exit" is a
## failed run here.
func material_for_element() -> Material:
	return material


func canvas() -> Texture2D:
	if _canvas == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_canvas = ImageTexture.create_from_image(image)
	return _canvas


# --- what the ice is grown on ------------------------------------------------

## `rect_px` is the element's own size; `from_px` and `to_px` are the ends of the
## substrate inside it; `bow_px` is how far the middle bulges. Zero bow is a
## straight stroke, which is what the five readouts want, and a bow is section
## 6.1's arc. One distance field serves both.
func set_substrate(rect_px: Vector2, from_px: Vector2, to_px: Vector2, bow_px := 0.0) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"arc_mode", 0)
	material.set_shader_parameter(&"rect_px", rect_px)
	material.set_shader_parameter(&"from_px", from_px)
	material.set_shader_parameter(&"to_px", to_px)
	material.set_shader_parameter(&"bow_px", bow_px)


## A radial gauge. The reserve creeps around the ring from `start_rad`, so the
## fill is frost growing rather than a wedge rotating -- which is the single
## change that makes this gauge unmistakably this game's.
func set_ring(
	rect_px: Vector2, centre_px: Vector2, radius_px: float,
	start_rad: float, span_rad: float
) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"arc_mode", 1)
	material.set_shader_parameter(&"rect_px", rect_px)
	material.set_shader_parameter(&"centre_px", centre_px)
	material.set_shader_parameter(&"radius_px", maxf(radius_px, 0.5))
	material.set_shader_parameter(&"start_rad", start_rad)
	material.set_shader_parameter(&"span_rad", span_rad)


## Where the model's own thresholds sit along this gauge, 0..1, up to four.
## Anything negative is no marker. Read out of data/stats by way of the copy
## table, so a marker cannot stand somewhere the model does not change.
func set_markers(positions: Vector4, size_px: float) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"markers", positions)
	material.set_shader_parameter(&"marker_px", maxf(size_px, 0.0))


## Where the reserve ends along the substrate, 0..1.
func set_fill(fraction: float) -> void:
	if material != null:
		material.set_shader_parameter(&"fill", clampf(fraction, 0.0, 1.0))


func set_weights(trough_px: float, fill_px: float, needle_px: float) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"trough_px", trough_px)
	material.set_shader_parameter(&"fill_px", fill_px)
	material.set_shader_parameter(&"needle_px", needle_px)


## Every colour comes from the tokens, which the generator read out of
## data/palette/color_bible.tres. Briefing constraint 6: there is no hex anywhere
## on this path, including in the shader, whose uniform defaults are white so
## that an unset one is obvious rather than plausible.
func set_colours(tokens: UITokens, fill_colour := Color.TRANSPARENT) -> void:
	if material == null or tokens == null:
		return
	material.set_shader_parameter(&"trough_colour", tokens.line_hairline)
	var reserve := tokens.ink_primary if fill_colour == Color.TRANSPARENT else fill_colour
	material.set_shader_parameter(&"fill_colour", reserve)
	# The refraction highlight, and the ONLY thing in this material that is
	# brighter than the reserve. `ink/primary` is the lightest of the twelve
	# snow tones, so a lit edge reads as the sun catching ice rather than as a
	# thirteenth colour.
	material.set_shader_parameter(&"rim_colour", tokens.ink_primary)
	# The darkest structure tone, which is section 5.9's answer to the same
	# problem -- ink on 62% snow -- and not black, because a thirteenth colour on
	# the edge of every stroke is still a thirteenth colour.
	material.set_shader_parameter(&"outline_colour", tokens.line_deep)


func set_reserve_colour(colour: Color) -> void:
	if material != null:
		material.set_shader_parameter(&"fill_colour", colour)


## Per element, so two readouts stacked one above the other do not crystallise
## into the same shape. Deterministic, never randf(): a captured frame has to be
## the same captured frame tomorrow.
func set_seed(value: float) -> void:
	if material != null:
		material.set_shader_parameter(&"seed", value)


func set_outline(width_px: float) -> void:
	if material != null:
		material.set_shader_parameter(&"outline_px", maxf(width_px, 0.0))


func set_body_alpha(value: float) -> void:
	if material != null:
		material.set_shader_parameter(&"body_alpha", clampf(value, 0.0, 1.0))


## The one warm mark, at the head of the reserve, on only while the reserve is
## being put back. Section 5.2 names this as the single legal warm use in the
## breath layer, and rule 3 is why it takes a boolean rather than a colour with
## an implied meaning: it is on when heat is entering the body, and at no other
## time.
func set_mark(on: bool, colour: Color, size_px := 3.0) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"mark_on", 1.0 if on else 0.0)
	material.set_shader_parameter(&"mark_colour", colour)
	material.set_shader_parameter(&"mark_px", size_px)


## Thickens the ice at once and lets the ordinary chase pull it back down.
##
## This is what "emphatic when it matters" is made of. Nothing is added to the
## screen when a threshold breaks and nothing has to be removed afterwards --
## the material already accumulates and clears, so the emphasis is the readout
## being MORE ITSELF for a while. Compare the alternative, which is a second
## element that somebody has to remember to take away.
func surge(amount: float) -> void:
	rime = clampf(maxf(rime, amount), 0.0, 1.0)
	_publish()


# --- growing ------------------------------------------------------------------

## How frosted this should settle at, 0..1. Chased rather than snapped -- see
## RIME_SECONDS.
func set_target_emphasis(value: float) -> void:
	_target_rime = clampf(value, 0.0, 1.0)


## Starts the ice again from nothing. For an element being reused rather than
## rebuilt.
func reseed(from_rime := 0.0) -> void:
	growth = 0.0
	rime = clampf(from_rime, 0.0, 1.0)
	_elapsed = 0.0


## Section 5.6. The cold snap makes the air still, and the ice with it.
func set_time_scale(scale: float) -> void:
	if is_finite(scale) and scale > 0.0:
		_time_scale = scale


## Public and carrying the driving, the same shape as WorldClock, SurvivalSystem
## and UILayer -- so a whole crystallisation is playable in a test with no frames
## and samplable by a screenshot harness at an exact moment.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var step := delta / _time_scale
	_elapsed += step
	growth = clampf(growth + step / GROWTH_SECONDS, 0.0, 1.0)
	# Exponential chase rather than a linear ramp: rime has no destination it is
	# travelling to, it has a value it is settling at, and that value moves.
	var closing := 1.0 - exp(-step / RIME_SECONDS)
	rime = clampf(lerpf(rime, _target_rime, closing), 0.0, 1.0)
	_publish()


## Snaps to fully grown. For an element that must be readable in the frame it is
## captured in -- a screenshot harness, or a readout being restored after a
## montage rather than being born.
func finish() -> void:
	growth = 1.0
	rime = _target_rime
	_publish()


func elapsed() -> float:
	return _elapsed


func _publish() -> void:
	if material == null:
		return
	material.set_shader_parameter(&"growth", growth)
	material.set_shader_parameter(&"rime", rime)
	material.set_shader_parameter(&"elapsed", _elapsed)
