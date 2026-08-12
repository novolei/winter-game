class_name VitalPaint
extends RefCounted

## THE SEAM. Everything about HOW a survival reading is drawn lives behind this
## and nothing in front of it.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## The visual language for the readouts was chosen, built, and then withdrawn --
## the owner asked for something simpler than the frost that was on the screen.
## Then the whole permanent presentation was withdrawn in its turn. Through both,
## the BEHAVIOUR never moved: reading the stats, the state a value puts a reading
## in, the surge when a threshold breaks, the words that announce it.
##
## That is the case for the seam, made twice. This class is where a look is
## swapped without a rewrite.
##
##   In front of the seam -- knows values, thresholds, states, geometry:
##     VitalTone       what a reading MEANS at a given value
##     VitalReadings   the model and the layout, put together per reading
##     VitalStroke     one reading: where it stands, how big, what it says
##     ThresholdSurfacing / ThresholdNote   section 5.2
##
##   Behind the seam -- knows pixels, and nothing else:
##     this class, and whatever implements it
##
## A new look is a new subclass and one changed constant in VitalStroke. It is
## not allowed to need a change anywhere in the list above; if it does, something
## about a value has leaked into something about a picture, and that is the thing
## this file exists to prevent.
##
## ---------------------------------------------------------------------------
## WHAT THE SEAM DELIBERATELY DOES NOT CARRY
## ---------------------------------------------------------------------------
## No colour DECISIONS. The caller resolves a colour from VitalTone -- which
## reads the palette and obeys rule 3, including the one ruling that survives any
## visual change: the only warm mark in the breath layer is heat entering the
## body. An implementation is told what colour to use and never chooses.
##
## No thresholds. The caller passes marker positions it read out of the model's
## own data.
##
## ---------------------------------------------------------------------------
## WHY IT IS RefCounted AND NOT A Node
## ---------------------------------------------------------------------------
## So it can be built, driven and thrown away in a test with no SceneTree and no
## leak. `Node` is not reference counted and an un-freed one is a dirty console,
## which by this project's standard is a failed run (briefing constraint 2).

## Builds whatever the look needs. False leaves the reading undrawn, which must
## be a legal inert state rather than a crash: a missing shader or a missing
## texture should cost the readout, not the run.
func build(_tokens: UITokens) -> bool:
	return false


func is_ready() -> bool:
	return false


## The material the element renders through, or null for a look that draws with
## plain canvas calls.
func material_for_element() -> Material:
	return null


## The texture the element draws, or null. A look that paints procedurally over
## the element's bounds needs one; one that draws lines does not.
func canvas() -> Texture2D:
	return null


# --- geometry ----------------------------------------------------------------

## A straight or bowed stroke between two points, in element-local pixels.
func set_substrate(
	_rect_px: Vector2, _from_px: Vector2, _to_px: Vector2, _bow_px := 0.0
) -> void:
	pass


## A radial gauge. Section 6.1's 断弧 -- the corner cluster that also used this
## has been deleted.
func set_ring(
	_rect_px: Vector2, _centre_px: Vector2, _radius_px: float,
	_start_rad: float, _span_rad: float
) -> void:
	pass


## Where the model's own thresholds sit along the gauge, 0..1, up to four.
## Negative means no marker.
func set_markers(_positions: Vector4, _size_px: float) -> void:
	pass


func set_weights(_trough_px: float, _fill_px: float, _texture_px: float) -> void:
	pass


func set_outline(_width_px: float) -> void:
	pass


# --- what it is told to say --------------------------------------------------

## Where the reserve ends along the substrate, 0..1.
func set_fill(_fraction: float) -> void:
	pass


## Every colour arrives from the palette by way of the tokens. No implementation
## may author one (briefing constraint 6).
func set_colours(_tokens: UITokens, _fill_colour := Color.TRANSPARENT) -> void:
	pass


func set_reserve_colour(_colour: Color) -> void:
	pass


## The one warm mark, at the head of the reserve, on only while heat is entering
## the body -- section 5.2's single legal warm use in the breath layer.
func set_mark(_on: bool, _colour: Color, _size_px := 3.0) -> void:
	pass


## Per element, so two readings side by side do not resolve identically.
## Deterministic, never randf(): a captured frame has to be the same frame
## tomorrow.
func set_seed(_value: float) -> void:
	pass


# --- driving ------------------------------------------------------------------

## How emphatic the look should settle at, 0..1. What that MEANS is the
## implementation's business; the caller only says how much.
func set_target_emphasis(_value: float) -> void:
	pass


## Emphasis at once, decaying by itself afterwards. This is what a threshold
## breaking looks like, and it is behaviour rather than appearance: nothing is
## added to the screen and nothing has to be remembered and taken away.
func surge(_amount: float) -> void:
	pass


func set_time_scale(_scale: float) -> void:
	pass


## Public and carrying the driving, the same shape as WorldClock, SurvivalSystem
## and UILayer -- so an element's whole arrival is playable in a test with no
## frames and samplable by a screenshot harness at an exact moment.
func advance(_delta: float) -> void:
	pass


## Straight to fully arrived. For a capture, which must photograph a finished
## readout rather than one caught part-way in.
func finish() -> void:
	pass


## Draws the reading with plain canvas calls, for a look that is line-work rather
## than a shaded surface.
##
## A CanvasItem carries ONE material, so a look built out of `draw_line()` and
## `draw_arc()` cannot also be a shader -- and the settled look, 「刻度」Engraved,
## is entirely strokes. Such an implementation returns null from
## material_for_element() and does its work here instead. Both paths are first
## class; the element calls this unconditionally and a shader look simply does
## nothing in it.
func draw_into(_item: CanvasItem, _size: Vector2) -> void:
	pass


## Retired by the owner's ruling -- 不要圆环外的分段的指针 -- and kept on the seam
## as a no-op so a future look can have one without the seam changing shape.
func set_needle(_on: bool) -> void:
	pass


## Dims this reading so another one can be the loud one. 1.0 is full presence.
func set_attenuation(_amount: float) -> void:
	pass
