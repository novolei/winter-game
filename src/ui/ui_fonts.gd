class_name UIFonts
extends RefCounted

## The three font families of UI design document section 2.2, assembled into the
## chains Godot actually renders from.
##
## ---------------------------------------------------------------------------
## THE LATIN FACE IS THE BASE. THE CJK FACE IS THE FALLBACK. THIS IS NOT COSMETIC
## ---------------------------------------------------------------------------
## Noto Serif SC and Noto Sans SC ship their own Latin glyphs -- the Source Han
## families were drawn with a matching Latin from Source Serif and Source Sans.
## Godot resolves a chain per GLYPH: base font first, then each fallback in turn.
##
## So a chain with Noto in the base slot renders Latin out of NOTO and never
## reaches Cormorant or Inter. Nothing is logged. Nothing is missing. The text is
## present, legible, correctly spaced, and in a typeface nobody chose -- the whole
## of section 2.2 undone by the order of two lines.
##
## Built the way round it is below, Cormorant covers the Latin it has and every
## Chinese glyph falls through to Noto, which is the arrangement the design
## specifies. tests/unit/test_ui_fonts.gd proves it by MEASUREMENT rather than by
## reading this configuration back, because a chain built the wrong way round is
## still a perfectly valid chain.
##
## ---------------------------------------------------------------------------
## WHY THE SINGLE-FACE VARIATIONS ARE PUBLIC
## ---------------------------------------------------------------------------
## `display_latin_only` and `interface_latin_only` exist so the test can measure
## a string through one face at a time and compare. They are not for drawing
## with -- a Control that used one directly would render Chinese as boxes.

const TABULAR := &"tnum"

## The `wght` axis, as the integer tag code FontVariation requires. Resolved from
## the name rather than written as 2003265652, so it reads as what it is -- and
## asked of the text server rather than computed here, because the packing is the
## server's business and not this file's.
static var _WEIGHT_TAG: int = TextServerManager.get_primary_interface().name_to_tag("wght")

var display: FontVariation = null
var display_latin_only: FontVariation = null
var display_cjk: FontVariation = null

var interface: FontVariation = null
var interface_latin_only: FontVariation = null
var interface_cjk: FontVariation = null

var instrument: FontVariation = null

## Kept so display_at() and interface_at() can rebuild a chain at another weight
## without being handed the tokens again.
var _tokens_latin_path := ""
var _tokens_cjk_path := ""
var _interface_latin_path := ""
var _interface_cjk_path := ""

## Assembles every chain from the paths and weights in `tokens`. Safe to call
## again; it replaces what was there.
##
## A null token set, or a path that does not resolve, leaves the corresponding
## family NULL rather than substituting anything. That is deliberate: a chain
## that quietly fell back to Godot's built-in face would put the entire interface
## in the wrong typeface and look like a design decision. is_ready() is what a
## caller checks.
func build(tokens: UITokens) -> void:
	display = null
	display_latin_only = null
	display_cjk = null
	interface = null
	interface_latin_only = null
	interface_cjk = null
	instrument = null
	_tokens_latin_path = ""
	_tokens_cjk_path = ""
	_interface_latin_path = ""
	_interface_cjk_path = ""
	if tokens == null:
		return
	_tokens_latin_path = tokens.display_latin_path
	_tokens_cjk_path = tokens.display_cjk_path
	_interface_latin_path = tokens.interface_latin_path
	_interface_cjk_path = tokens.interface_cjk_path

	display_latin_only = _variation(tokens.display_latin_path, tokens.display_latin_weight)
	display_cjk = _variation(tokens.display_cjk_path, tokens.display_cjk_weight)
	display = _chain(tokens.display_latin_path, tokens.display_latin_weight, display_cjk)

	interface_latin_only = _variation(tokens.interface_latin_path, tokens.interface_latin_weight)
	interface_cjk = _variation(tokens.interface_cjk_path, tokens.interface_cjk_weight)
	interface = _chain(tokens.interface_latin_path, tokens.interface_latin_weight, interface_cjk)

	instrument = _variation(tokens.instrument_path, 0)
	if instrument != null:
		# Section 2.2 calls this a hard requirement. The Tab readout changes
		# every frame and proportional digits make the whole line jump sideways
		# when 68 becomes 71. IBM Plex Mono is monospaced already, so this is
		# belt and braces -- and it is the line that keeps being true if the
		# instrument face is ever swapped for a proportional one.
		instrument.opentype_features = { TABULAR: 1 }

func is_ready() -> bool:
	return display != null and interface != null and instrument != null

## A display chain at an arbitrary weight, for type that does not stand on the
## screen.
##
## Section 2.2 sets the display family at its lightest -- Noto Serif SC 200,
## which is the floor of its axis -- and that is right for type on a scrim, where
## the background is controlled and the thinness reads as air. It is wrong for
## SPATIAL typography: a line standing in the valley has a whole snow field
## behind it at 62% of white and no scrim at all, and at 200 it washes out into
## the ground it is standing on. Weight is what buys it presence when nothing
## else can.
##
## Same ordering rule as the main chains -- Latin base, CJK fallback -- for the
## same reason, which build() spells out at length.
func display_at(latin_weight: int, cjk_weight: int) -> FontVariation:
	if _tokens_latin_path == "" or _tokens_cjk_path == "":
		return display
	var cjk := _variation(_tokens_cjk_path, cjk_weight)
	var chain := _variation(_tokens_latin_path, latin_weight)
	if chain == null:
		return cjk
	if cjk != null:
		chain.fallbacks = [cjk]
	return chain


## The interface chain at an arbitrary weight, for type that stands on the world
## with nothing behind it.
##
## Section 2.2 sets this family at 300 Light, which is right where the interface
## owns the background. The breath layer (section 3) owns nothing -- it wakes on
## an event, draws onto the valley, and rule 1 forbids a plate -- and at 300 its
## strokes are thinner than a pixel at Body 17, so antialiasing hands the player a
## blend of ink and snow rather than the ink. See UITokens.breath_cjk_weight for
## the measurement, and section 5.9, which found the same thing for the same layer
## in its world-space form and answered it the same way.
##
## `spacing` is section 2.2's letter spacing in whole pixels, and it is taken here
## rather than applied by the caller to the chain it gets back. Wrapping a
## finished chain in a second FontVariation to add tracking LOSES the weight on
## the base face -- see _variation() for the measurement -- and it is the shape
## every caller reaches for first, because it reads as harmless.
##
## Same ordering rule as the main chains -- Latin base, CJK fallback -- for the
## same reason, which build() spells out at length. Returns the shipped
## `interface` chain unchanged when the token set is not available, rather than
## nothing: a missing weight should cost legibility, not the words.
func interface_at(latin_weight: int, cjk_weight: int, spacing: int = 0) -> FontVariation:
	if _interface_latin_path == "" or _interface_cjk_path == "":
		return interface
	var cjk := _variation(_interface_cjk_path, cjk_weight, spacing)
	var chain := _variation(_interface_latin_path, latin_weight, spacing)
	if chain == null:
		return cjk if cjk != null else interface
	if cjk != null:
		chain.fallbacks = [cjk]
	return chain


## The size a family should be set at, for a design-pixel size in section 2.2's
## ladder. Sizes are authored against 1080 and scale with the short edge, the
## same rule the breathing border follows -- so type and margins cannot drift
## apart at another resolution.
static func size_for(design_size: float, tokens: UITokens, viewport_size: Vector2) -> int:
	if tokens == null:
		return int(roundf(design_size))
	return int(roundf(tokens.design_px(design_size, viewport_size)))

# --- internals --------------------------------------------------------------

## ---------------------------------------------------------------------------
## THE WEIGHT AXIS IS KEYED BY TAG CODE, AND ONLY BY TAG CODE
## ---------------------------------------------------------------------------
## `variation_opentype` takes the OpenType axis tag as an INTEGER. A String or a
## StringName key is accepted by the Dictionary, stored, read back identically --
## and silently never applied. Measured on 4.7.1, Inter set at 200 px:
##
##   key form     wght 100    wght 400    wght 900
##   StringName   1119.0      1119.0      1119.0     <- 400, the font's default
##   String       1119.0      1119.0      1119.0     <- 400, the font's default
##   int          1074.0      1119.0      1201.0     <- the axis actually moves
##
## and `TextServer.font_get_variation_coordinates()` on the resulting RID returns
## an EMPTY dictionary for the first two forms.
##
## This file shipped with `{ &"wght": weight }` and so every weight in section
## 2.2 was inert: the interface CJK face rendered at NotoSansSC-VF's own default,
## which is 100 THIN, where the document asks for 300 Light, and the interface
## Latin rendered at Inter's 400 Regular. Nothing errored. tests/unit/
## test_ui_fonts.gd passed throughout, because it read the Dictionary back
## instead of measuring what the face did -- the configuration was perfect and
## the rendering ignored it.
##
## NOTE that `opentype_features` below is NOT the same: measured, it honours a
## StringName key and produces tabular figures. Two neighbouring properties of
## one class, two different key contracts, one of them silent. That asymmetry is
## the whole trap.
##
## `spacing` is applied HERE rather than by wrapping the finished chain, because
## a FontVariation whose base_font is another FontVariation DROPS the inner one's
## variation coordinates for the base face -- measured, same run: the outer RID
## came back empty at every weight while the fallback's kept it. One level per
## face is what keeps a weight and a tracking on the same object.
##
## Weight 0 means "leave the axis alone" -- for a static face like IBM Plex Mono
## Light, which has no axis to set and would reject one.
func _variation(path: String, weight: int, spacing: int = 0) -> FontVariation:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var base := ResourceLoader.load(path) as Font
	if base == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base
	if weight > 0:
		variation.variation_opentype = { _WEIGHT_TAG: weight }
	if spacing != 0:
		variation.spacing_glyph = spacing
	return variation

func _chain(latin_path: String, latin_weight: int, cjk: FontVariation) -> FontVariation:
	var chain := _variation(latin_path, latin_weight)
	if chain == null:
		# No Latin face: fall back to the CJK one alone rather than to nothing,
		# so the game is still readable while somebody works out why the file is
		# missing. Its own Latin is not the chosen one, which is why this is the
		# degraded path and not the arrangement.
		return cjk
	if cjk != null:
		# Assigned as a whole array, not appended to: Font.fallbacks returns a
		# copy, so `chain.fallbacks.append(x)` mutates a temporary and silently
		# does nothing.
		chain.fallbacks = [cjk]
	return chain
