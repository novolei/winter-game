class_name ConcernReadout
extends Node3D

## One survival reading, drawn above an animal's head, world-anchored.
##
## The silhouette is the bottle and the horizontal line across it is the liquid:
## the stat's own icon, cut at a height, `scrim/veil` below the line and
## `ink/muted` above it. Both tones are OPAQUE and the edge between them is hard.
##
## ---------------------------------------------------------------------------
## WHY BOTH TONES ARE OPAQUE, WHICH IS THE WHOLE DESIGN
## ---------------------------------------------------------------------------
## The obvious build is one colour at two opacities -- solid below the line and
## faint above. On a dark background that is exactly right, and it is what the
## owner's reference does. **This game's background is snow**, and a faint mark
## on near-white snow is not faint, it is absent. Measured, against the lit snow
## band as it actually renders (`#A5CBF9`, luminance 0.577):
##
##   scrim/veil at 100%   9.65 : 1     the filled part -- unmissable
##   scrim/veil at  28%   1.9  : 1     the empty part -- gone
##
## When the empty part goes, the SHAPE goes with it, and all that survives is a
## dark blob at the bottom of nothing. The player can see that something is
## wrong and cannot see WHICH THING, which is the one job this readout has.
##
## So the empty part is not a weaker version of the filled part. It is a second
## flat palette tone, at full opacity, chosen to sit on the other side of the
## snow from the first. The whole silhouette is therefore always present and the
## level is a value step inside it -- which is what an empty glass looks like.
##
## ---------------------------------------------------------------------------
## WHICH TWO TONES, AND WHY NOTHING LIGHTER WAS AVAILABLE
## ---------------------------------------------------------------------------
## Measured across all twelve entries of data/palette/color_bible.tres against
## the lit snow band. Contrast ratios, after the 1.155 screen gain the cel pass
## applies (briefing trap 7):
##
##   snow_tones[0..4]        1.00 .. 2.00 : 1     the whole light half of the
##                                                palette IS the snow
##   structure_tones[0..3]   4.53 .. 9.65 : 1
##   warm_tones[2] #FFB257   1.13 : 1
##
## Two things fall out of that table and both are worth keeping.
##
## **There is no light saturated cool colour in this palette.** A reference that
## works by putting saturated cyan on dark rock cannot be transposed: the closest
## thing here, `ink/muted`, manages 2.00 : 1 against snow and nothing does
## better while still reading as lighter than the fill. So the badge separates
## from the snow by being DARK, not by being brighter or more saturated.
##
## **Warm would not have helped even if rule 3 allowed it.** `#FFB257` on lit
## snow is 1.13 : 1 -- the palette's brightest warm is almost exactly the
## luminance of snow and would have been the least visible choice on the board.
## Rule 3 forbids it because warm means heat; the measurement says it is also
## the wrong tool.
##
## The pair shipped is `structure_tones[3]` filled over `snow_tones[4]` empty:
## the largest value step available (4.82 : 1 between them) with the strongest
## fill-against-snow (9.65 : 1) of any pair that keeps that step.
##
## It also survives the other two grounds without a second design. Against the
## shade band and against a night ground the fill goes dark-on-dark while the
## EMPTY tone lifts to 3.91 : 1 -- so on snow the reading is carried by the
## filled part and after dark by the unfilled part, and the shape never leaves.
##
## ---------------------------------------------------------------------------
## SCREEN-CONSTANT SIZE, WORLD-ANCHORED POSITION
## ---------------------------------------------------------------------------
## A status marker that shrinks with the framing stop is a status marker that
## stops working at the stop where the player most needs it -- at
## `orthographic_size` 17.0 the dog itself is 29 px tall. So the position is in
## the world and rides the animal, and the SIZE is a constant share of frame
## height: `pixel_size` is recomputed from the camera's own `size` every frame,
## which under a parallel projection is exactly the frame's height in metres.
##
## Bounded at both ends in world metres so that a stop outside the shipped three
## cannot produce a badge either bigger than the animal or smaller than the
## legibility floor. Across 10.5 / 13.5 / 17.0 neither bound engages.
##
## ---------------------------------------------------------------------------
## THE ICON TEXTURE IS READ, NEVER MOUNTED
## ---------------------------------------------------------------------------
## `assets/ui/icons/*.png` are imported for 2D with `detect_3d/compress_to=1`.
## Assigning one to a 3D material asks the editor to re-import it VRAM-compressed
## the next time the project is opened -- it would rewrite an `.import` file this
## task must not touch, and it would hand the 2D interface a lossy texture as a
## side effect of something happening in the world.
##
## So the PNG is only ever read as an `Image`, and what goes on the sprite is an
## `ImageTexture` this class builds. Reading a texture does not trip the detector;
## drawing with it in 3D does.
##
## It also means the glyphs stay live art: the two tones are painted onto
## whatever alpha the file currently holds, and the fill is measured against the
## icon's own INK bounding box rather than its canvas, so a redrawn icon set --
## squat, tall, off-centre -- arrives correct with no code change.

## Where the tones come from. Both are entries of the twelve; see the header for
## the measurement that chose them.
const FILLED_INDEX := 3     ## structure_tones[3], the palette's darkest
const EMPTY_INDEX := 4      ## snow_tones[4], the darkest of the light half

const DEFAULT_PALETTE := "res://data/palette/color_bible.tres"
const DEFAULT_TOKENS := "res://data/ui/tokens.tres"
const DEFAULT_ICON_DIRECTORY := "res://assets/ui/icons"

## Fill is quantised before the texture is rebuilt. 1/64 is finer than a pixel
## of waterline at every size this draws at, and it turns "recomposite every
## frame" into "recomposite when the picture would actually differ".
const FILL_STEPS := 64.0

## Section 2.4's `散` carries the element up 8 design pixels as it goes. Design
## pixels are against a 1080 reference frame, so in the world that is a share of
## the frame's height and comes out the same size at every stop.
const DRIFT_RISE_FRACTION := 8.0 / 1080.0

@export_file("*.tres") var palette_path := DEFAULT_PALETTE
@export_file("*.tres") var tokens_path := DEFAULT_TOKENS
@export_dir var icon_directory := DEFAULT_ICON_DIRECTORY

## The badge's height as a share of frame height. 0.044 is 44 px in a 1000 px
## frame and 48 px at 1080p, and it is a measurement rather than a taste: at
## 32 px the boot's tread breaks into noise and the bolt's waterline is one
## pixel; at 44 all six glyphs hold their shape and their level. See
## tools/measure_icon_fill.py.
@export var frame_share := 0.044

## The bounds on the screen-constant size, in world metres. Across the three
## shipped stops the badge is 0.462 / 0.594 / 0.748 m and neither bound engages;
## they exist so a fourth stop cannot silently produce an absurd one.
@export var min_world_m := 0.35
@export var max_world_m := 0.95

## Held on screen after the bloom. Read from UITokens when there is one.
@export var hold_seconds := 2.4

var _sprite: Sprite3D = null
var _texture: ImageTexture = null
var _tokens: UITokens = null
var _palette: ColorBible = null
var _breath: Breath = null
var _clock := 0.0
var _anchor := Vector3.ZERO
var _stat: StringName = &""
var _glyph: StringName = &""
var _fill := 1.0
var _drawn_step := -1
var _glyph_box := Vector2i.ZERO
var _empty_image: Image = null
var _full_image: Image = null
var _live := false

## Keyed by "<glyph>|<icon dir>". Two pre-tinted images per glyph, built once and
## shared by every animal in the scene.
static var _cache: Dictionary = {}


func _ready() -> void:
	_load_resources()
	_build_sprite()
	visible = false


func _load_resources() -> void:
	# Asked before loading. ResourceLoader.load() on a missing path prints three
	# ERROR lines before returning null, and by this project's standard a dirty
	# console is a failed run whether or not the absence was handled.
	if _palette == null and ResourceLoader.exists(palette_path):
		_palette = ResourceLoader.load(palette_path) as ColorBible
	if _tokens == null and ResourceLoader.exists(tokens_path):
		_tokens = ResourceLoader.load(tokens_path) as UITokens
	if _tokens != null:
		hold_seconds = _tokens.hold_seconds


func _build_sprite() -> void:
	if _sprite != null:
		return
	_sprite = Sprite3D.new()
	_sprite.name = "Glyph"
	# BILLBOARD_ENABLED, not FIXED_Y. The camera is pitched 45 degrees down, so a
	# Y-billboard would stand the badge on its edge and foreshorten it to a
	# sliver; the full billboard faces the camera squarely and, because the rig
	# never rolls, stays upright on screen without a second correction.
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Unshaded, so the two palette tones reach the frame as authored rather than
	# through the world's two-band cel light -- a gauge that changes colour with
	# the time of day is a gauge with two variables in it.
	_sprite.shaded = false
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# Drawn after the world so it is never sorted behind the animal it belongs
	# to, while still being occluded by geometry in front of it -- it is a thing
	# in the valley, not an overlay.
	_sprite.render_priority = 1
	add_child(_sprite)


## The colour of the part that is still there.
func filled_color() -> Color:
	if _palette == null or _palette.structure_tones.size() <= FILLED_INDEX:
		return Color.BLACK
	return _palette.structure_tones[FILLED_INDEX]


## The colour of the part that has been lost.
func empty_color() -> Color:
	if _palette == null or _palette.snow_tones.size() <= EMPTY_INDEX:
		return Color.WHITE
	return _palette.snow_tones[EMPTY_INDEX]


## Show this reading, now. `fill` is the stat's own 0..1 fraction.
##
## Returns false when the glyph has no file, rather than showing an empty badge:
## a marker that appears and depicts nothing is worse than no marker, because the
## player learns that the dog's warnings are sometimes meaningless.
func show_reading(stat: StringName, glyph: StringName, fill: float) -> bool:
	_load_resources()
	_build_sprite()
	if not set_glyph(glyph):
		return false
	_stat = stat
	set_fill(fill)
	_breath = Breath.surface(_tokens, hold_seconds) if _tokens != null else null
	_clock = 0.0
	_live = true
	visible = true
	_apply_envelope()
	return true


## Swap the pictograph. Public so a reading that worsens into a different stat
## can change what it depicts without restarting its life.
func set_glyph(glyph: StringName) -> bool:
	if glyph == _glyph and _empty_image != null:
		return true
	var layers := _layers(glyph, icon_directory, filled_color(), empty_color())
	if layers.is_empty():
		return false
	_glyph = glyph
	_empty_image = layers["empty"]
	_full_image = layers["full"]
	_glyph_box = layers["box"]
	_texture = null
	_drawn_step = -1
	return true


func set_fill(fill: float) -> void:
	_fill = clampf(fill, 0.0, 1.0)
	_redraw()


## The point the badge sits ABOVE -- the top of the animal's head, not the badge's
## own centre.
##
## The difference is not bookkeeping. A `Sprite3D` is centred on its origin, so
## anchoring at the head put half the badge INSIDE the dog: measured on the first
## capture, the droplet's lower half lay across the retriever's shoulders and
## read as a marking on the animal rather than as a thing above it. And because
## the badge's height changes with the framing stop, no fixed offset the caller
## could pass would clear the head at all three -- the correction has to be made
## here, where the current height is known.
func anchor_at(world_position: Vector3) -> void:
	_anchor = world_position
	_place()


## Half the badge's own height at this camera, which is what `anchor_at` has to
## add to clear whatever it is standing over.
func half_height() -> float:
	return _world_height(_current_camera()) * 0.5


func fill() -> float:
	return _fill


func glyph() -> StringName:
	return _glyph


func stat() -> StringName:
	return _stat


## Whether anything is on screen. False before the first reading and again the
## instant the envelope finishes -- nothing here is permanent.
func is_live() -> bool:
	return _live


func sprite() -> Sprite3D:
	return _sprite


func breath() -> Breath:
	return _breath


## Seconds since this reading appeared. What a capture needs in order to seek to
## a chosen point in the envelope rather than to add to wherever it had got to.
func age() -> float:
	return _clock


func _process(delta: float) -> void:
	advance(delta)


## Public and carrying everything, so a test or a capture drives it without a
## tree tick.
func advance(delta: float) -> void:
	if not _live or not is_finite(delta) or delta < 0.0:
		return
	_clock += delta
	if _breath != null and _breath.is_finished(_clock):
		_live = false
		visible = false
		return
	_apply_envelope()


## How tall the badge draws, in pixels of the saved frame.
##
## `DisplayServer.window_get_size()` rather than the viewport's canvas rect:
## under this project's `canvas_items` stretch the two disagree by 10-25% and
## only the window matches the PNG (briefing trap 10).
func screen_height_px(camera: Camera3D, window_height: float) -> float:
	if camera == null or _sprite == null:
		return 0.0
	var world := _world_height(camera)
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL or camera.size <= 0.0:
		return 0.0
	return world / camera.size * window_height


## The badge's height in metres at this camera. Public because the report has to
## state it and a test has to hold the bounds to the shipped framing stops.
func world_height(camera: Camera3D) -> float:
	return _world_height(camera)


func _world_height(camera: Camera3D) -> float:
	if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return clampf(min_world_m, min_world_m, max_world_m)
	return clampf(frame_share * camera.size, min_world_m, max_world_m)


func _current_camera() -> Camera3D:
	if not is_inside_tree():
		return null
	var viewport := get_viewport()
	return null if viewport == null else viewport.get_camera_3d()


func _apply_envelope() -> void:
	if _sprite == null:
		return
	var camera := _current_camera()
	var world := _world_height(camera)
	var opacity := 1.0
	var scale_now := 1.0
	if _breath != null:
		opacity = _breath.opacity_at(_clock)
		scale_now = _breath.scale_at(_clock)
	# The glyph box is normalised on its LONGER side, so a squat bowl stays squat
	# and a tall flame stays tall. Sizing on height alone would make the bowl as
	# tall as the flame and four times as wide.
	var span := float(maxi(_glyph_box.x, _glyph_box.y))
	_sprite.pixel_size = world * scale_now / maxf(span, 1.0)
	_sprite.modulate = Color(1.0, 1.0, 1.0, opacity)
	_place()


func _place() -> void:
	# `global_position` is `ERR_FAIL_COND(!is_inside_tree())` inside the engine:
	# read or written outside the tree it prints to the console and returns an
	# identity transform. A dirty console is a failed run here, and a node built
	# by a capture tool before it is parented hits this on its first reading.
	if not is_inside_tree():
		return
	var rise := 0.0
	if _breath != null:
		var camera := _current_camera()
		var frame := 10.5 if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL else camera.size
		# offset_at is in design pixels against a 1080 reference and is NEGATIVE
		# upward, matching a screen's y axis. In the world, up is positive.
		rise = -_breath.offset_at(_clock).y * frame / 1080.0
	global_position = _anchor + Vector3.UP * (rise + half_height())


func _redraw() -> void:
	if _empty_image == null or _sprite == null:
		return
	var step := int(round(_fill * FILL_STEPS))
	if step == _drawn_step and _texture != null:
		return
	_drawn_step = step
	var w := _glyph_box.x
	var h := _glyph_box.y
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# blit, not blend. The two layers carry the SAME alpha, so blending them
	# would compound the antialiased outline into a fatter, softer edge -- the
	# one thing this design must not have. A blit replaces the region outright,
	# which keeps the outline exactly as the artist drew it and makes the
	# waterline a hard edge with no gradient anywhere.
	image.blit_rect(_empty_image, Rect2i(0, 0, w, h), Vector2i.ZERO)
	var cut := int(round(float(h) - _fill * float(h)))
	cut = clampi(cut, 0, h)
	if cut < h:
		image.blit_rect(_full_image, Rect2i(0, cut, w, h - cut), Vector2i(0, cut))
	# A NEW texture every time, rather than `ImageTexture.update()`.
	#
	# `update()` goes through `RenderingServer.texture_replace()`, and under
	# `--headless` the dummy driver does not carry the replacement back: measured,
	# `get_image()` returned the fill-0.00 picture after two updates to 0.50 and
	# 1.00, identical to the byte. Nothing errors. The badge would have been
	# frozen at whatever level it first drew, and the whole suite is headless, so
	# no test could ever have seen it -- the gate would have passed while the
	# feature did nothing.
	#
	# `create_from_image()` takes the `texture_2d_create()` path, which the dummy
	# driver does keep. The cost is one texture per quantised fill change while a
	# badge is on screen -- a handful over its three and a half seconds -- and it
	# buys a readout the tests can actually read.
	_texture = ImageTexture.create_from_image(image)
	_sprite.texture = _texture


## The two pre-tinted layers for one glyph, cropped to its ink.
##
## Cached across every animal in the scene: the tint is a per-pixel GDScript loop
## over the icon's bounding box, which is fine once and wasteful six times a
## second.
static func _layers(glyph: StringName, directory: String, filled: Color, empty: Color) -> Dictionary:
	var key := "%s|%s|%s|%s" % [glyph, directory, filled.to_html(), empty.to_html()]
	if _cache.has(key):
		return _cache[key]
	var path := "%s/%s.png" % [directory, glyph]
	if glyph == &"" or not ResourceLoader.exists(path):
		return {}
	var texture := ResourceLoader.load(path) as Texture2D
	if texture == null:
		return {}
	var source := texture.get_image()
	if source == null:
		return {}
	if source.is_compressed():
		# A VRAM-compressed icon cannot be read pixel by pixel. Decompressing is
		# the honest recovery: the alternative is a silently blank badge.
		source.decompress()
	var box := _ink_box(source)
	if box.size.x <= 0 or box.size.y <= 0:
		return {}
	var empty_image := Image.create_empty(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
	var full_image := Image.create_empty(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
	for y in range(box.size.y):
		for x in range(box.size.x):
			var a := source.get_pixel(box.position.x + x, box.position.y + y).a
			empty_image.set_pixel(x, y, Color(empty.r, empty.g, empty.b, a))
			full_image.set_pixel(x, y, Color(filled.r, filled.g, filled.b, a))
	var layers := {"empty": empty_image, "full": full_image, "box": box.size}
	_cache[key] = layers
	return layers


## The icon's own ink, not its canvas.
##
## `hunger` occupies 86 of its 256 rows and every other glyph occupies 190, so a
## line placed against the canvas would read 0.50 as a full bowl. Measuring the
## ink is also what lets a redrawn icon set land without a code change.
static func _ink_box(image: Image) -> Rect2i:
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.04:
				continue
			low.x = mini(low.x, x)
			low.y = mini(low.y, y)
			high.x = maxi(high.x, x)
			high.y = maxi(high.y, y)
	if high.x < low.x or high.y < low.y:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(low, high - low + Vector2i.ONE)


## Drops the shared tint cache. For tests, which must not carry one test's
## palette into the next.
static func forget_cached_glyphs() -> void:
	_cache.clear()
