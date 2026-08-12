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

var display: FontVariation = null
var display_latin_only: FontVariation = null
var display_cjk: FontVariation = null

var interface: FontVariation = null
var interface_latin_only: FontVariation = null
var interface_cjk: FontVariation = null

var instrument: FontVariation = null

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
	if tokens == null:
		return

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

## The size a family should be set at, for a design-pixel size in section 2.2's
## ladder. Sizes are authored against 1080 and scale with the short edge, the
## same rule the breathing border follows -- so type and margins cannot drift
## apart at another resolution.
static func size_for(design_size: float, tokens: UITokens, viewport_size: Vector2) -> int:
	if tokens == null:
		return int(roundf(design_size))
	return int(roundf(tokens.design_px(design_size, viewport_size)))

# --- internals --------------------------------------------------------------

## Weight 0 means "leave the axis alone" -- for a static face like IBM Plex Mono
## Light, which has no axis to set and would reject one.
func _variation(path: String, weight: int) -> FontVariation:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var base := ResourceLoader.load(path) as Font
	if base == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base
	if weight > 0:
		variation.variation_opentype = { &"wght": weight }
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
