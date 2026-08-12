class_name Inscription
extends Node3D

## Spatial typography -- UI design document section 5.9. A line of narration that
## stands IN the valley rather than on the lens.
##
## The camera dollies past it and the letters foreshorten, because they are
## geometry at a fixed world transform and not an overlay. Whatever stands in
## front occludes them. Then the wind takes them, one at a time, and they come
## apart into specks.
##
## ---------------------------------------------------------------------------
## THREE PROPERTIES ARE THE WHOLE EFFECT, AND EACH IS ONE LINE TO LOSE
## ---------------------------------------------------------------------------
## billboard DISABLED -- a billboarded glyph turns to face the camera, so a dolly
##     past it produces NO foreshortening whatsoever. The effect collapses into a
##     screen overlay that happens to be drawn in 3D, and it collapses silently:
##     the text still looks fine from the opening frame.
##
## depth test ON -- the occlusion compositing. Without it the narration draws over
##     the trees it is meant to be standing behind, and stops being in the world.
##
## alpha cut HASH -- Godot's stochastic transparency. Lowering alpha under it does
##     not fade the glyph evenly, it discards a growing scatter of its pixels. That
##     is what makes the exit read as the letter coming apart into snow rather
##     than being turned down. It costs nothing and needs no shader.
##
## tests/unit/test_inscription.gd asserts all three directly, because a
## screenshot only catches them if somebody looks at the right frame.
##
## ---------------------------------------------------------------------------
## WORD -> LETTER -> SPECK
## ---------------------------------------------------------------------------
## The dissolve happens at three scales at once, which is what stops it reading
## as one effect: the WORD comes apart because each letter leaves separately, the
## LETTER comes apart because alpha hash eats it, and the specks join the snow
## that is already falling in the scene. Nothing new is spawned -- the valley's
## own weather finishes the job.
##
## The direction is the WIND, the same wind that erases footprints in GDD section
## 8. The narration is subject to the valley's weather rather than to a screen
## effect, which is the difference between a transition and a place.

## Wind used when nobody says otherwise. Along the frame and slightly up, so the
## line leaves the way a breath does rather than falling like debris.
const DEFAULT_WIND := Vector2(1.0, -0.25)

## World units a glyph travels as it goes. About a metre and a half at the
## default scale -- far enough to clear where the word was, near enough that it
## is still legible as having been taken rather than teleported.
const DEFAULT_SCATTER_M := 1.4
const DEFAULT_SPIN := 0.9

## Font pixels to world metres. With a 64 px face this puts a line of Chinese at
## roughly 0.3 m per character, which reads at the montage camera's working
## distance without the letters becoming scenery.
const DEFAULT_PIXEL_SIZE := 0.0045
const DEFAULT_FONT_SIZE := 64

var _glyphs: Array[Label3D] = []
var _breaths: Array[Breath] = []
var _placed: Array[Vector3] = []
var _base_colour := Color.WHITE
var _outline_colour := Color.BLACK
var _width := 0.0

# --- composition ------------------------------------------------------------

## Lays the line out and gives every glyph its own breath. Safe to call again;
## it replaces what was there.
func compose(text: String, font: Font, tokens: UITokens,
		font_size := DEFAULT_FONT_SIZE, pixel_size := DEFAULT_PIXEL_SIZE) -> void:
	for glyph in _glyphs:
		glyph.queue_free()
	_glyphs.clear()
	_breaths.clear()
	_placed.clear()
	_width = 0.0
	if text == "" or font == null:
		return

	_base_colour = tokens.life_warm if tokens != null else Color.WHITE
	_outline_colour = tokens.scrim_veil if tokens != null else Color.BLACK

	# Prefix measurement rather than per-character advances, so kerning survives:
	# the x of character i is the width of everything before it. Measuring each
	# glyph on its own and summing would drop every kerning pair in the line.
	var count := text.length()
	var offsets: Array[float] = []
	for i in range(count + 1):
		offsets.append(font.get_string_size(
			text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	_width = offsets[count] * pixel_size

	for i in range(count):
		var character := text[i]
		# A space advances the pen and draws nothing. Giving it a Label3D would
		# cost a draw call for an invisible node -- and, worse, a breath of its
		# own, putting a beat in the writing where nothing appears.
		if character.strip_edges() == "":
			continue

		var glyph := Label3D.new()
		glyph.text = character
		glyph.font = font
		glyph.font_size = font_size
		glyph.pixel_size = pixel_size
		glyph.modulate = _transparent(_base_colour)
		# See the header. Both of these are the effect.
		glyph.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		glyph.no_depth_test = false
		glyph.double_sided = true
		glyph.shaded = false
		# Clean to begin with; seek() switches it to ALPHA_CUT_HASH when the wind
		# reaches this glyph. Hash dithers EVERY partial-alpha pixel, including
		# the antialiased rim of a fully opaque glyph, so leaving it on for the
		# whole life stipples the text the entire time it is being read. It is a
		# dissolve, not a render mode.
		glyph.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		# AN OUTLINE, AND ITS ALPHA HAS TO BE DRIVEN TOO.
		#
		# Label3D defaults to a 12 px outline in pure black, and outline_modulate
		# is a SEPARATE colour from modulate -- so fading the glyph fades only the
		# fill, and what is left at the end of the exit is a solid black letter.
		# That shipped in the first capture: the line scattered into black.
		#
		# Kept rather than switched off, because this narration stands against
		# snow at roughly 70% lightness and warm-on-white is the one pairing in
		# the palette with no contrast to spare. Taken from the darkest structure
		# tone rather than from black, so it is still the twelve.
		glyph.outline_size = maxi(int(round(float(font_size) * 0.07)), 1)
		glyph.outline_modulate = _transparent(_outline_colour)
		# Centred on the line's own origin, so placing an inscription in the
		# world is placing its middle rather than its left edge.
		glyph.position = Vector3(offsets[i] * pixel_size - _width * 0.5, 0.0, 0.0)

		add_child(glyph)
		_glyphs.append(glyph)
		_placed.append(glyph.position)
		# The CHARACTER index, not the glyph index: a space should still cost a
		# beat, so the hand appears to pause over it.
		_breaths.append(Breath.inscription(tokens, i, count))

	scatter_along(DEFAULT_WIND, DEFAULT_SCATTER_M, DEFAULT_SPIN)
	seek(0.0)

## Points the exit somewhere. `distance` is in world metres.
func scatter_along(wind: Vector2, distance: float, spin: float) -> void:
	for breath in _breaths:
		breath.scatter(wind, distance, spin)

## Section 5.6 -- the cold snap reaches the narration too.
func stretch(factor: float) -> void:
	for breath in _breaths:
		breath.stretch(factor)

# --- playing ----------------------------------------------------------------

## Puts the line in the state it is in at `seconds`. Driven from outside rather
## than from _process, so a montage can scrub, a test can sample an exact moment,
## and a screenshot harness can land on the frame it means to.
func seek(seconds: float) -> void:
	for i in range(_glyphs.size()):
		var glyph := _glyphs[i]
		var breath := _breaths[i]
		var alpha := breath.opacity_at(seconds)
		glyph.modulate = _with_alpha(_base_colour, alpha)
		# The outline is a separate colour and fades on its own or not at all.
		glyph.outline_modulate = _with_alpha(_outline_colour, alpha)
		# Grainy only while it is being taken. Set every frame rather than once at
		# the crossing, because seek() is a SCRUB -- a montage may be played
		# backwards, or sampled at an arbitrary moment by a screenshot harness,
		# and a one-shot switch would leave the glyph in whichever mode it last
		# passed through.
		glyph.alpha_cut = (Label3D.ALPHA_CUT_HASH if seconds >= breath.exit_begins()
			else Label3D.ALPHA_CUT_DISABLED)
		var offset: Vector2 = breath.offset_at(seconds)
		# The offset is authored in the plane of the line, so it moves the glyph
		# across the inscription's own face -- a line standing at an angle to the
		# camera has its letters blow along ITSELF, not along the world axes.
		glyph.position = _placed[i] + Vector3(offset.x, -offset.y, 0.0)
		glyph.rotation.z = breath.rotation_at(seconds)
		var scale_amount: float = breath.scale_at(seconds)
		glyph.scale = Vector3(scale_amount, scale_amount, 1.0)

func total_seconds() -> float:
	var longest := 0.0
	for breath in _breaths:
		longest = maxf(longest, breath.total_seconds())
	return longest

func is_finished(seconds: float) -> bool:
	return seconds >= total_seconds()

# --- reading ----------------------------------------------------------------

func glyph_count() -> int:
	return _glyphs.size()

func glyph_at(index: int) -> Label3D:
	return _glyphs[index] if index >= 0 and index < _glyphs.size() else null

func breath_at(index: int) -> Breath:
	return _breaths[index] if index >= 0 and index < _breaths.size() else null

## Width of the whole line in world metres.
func width() -> float:
	return _width

# --- internals --------------------------------------------------------------

func _transparent(colour: Color) -> Color:
	return _with_alpha(colour, 0.0)

func _with_alpha(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, clampf(alpha, 0.0, 1.0))
