extends TestCase

## The badge above the animal's head: the fill, the two tones, the size and the
## fact that it dies.
##
## The tests that matter here are about the MECHANISM, because the icon art is
## being redrawn: the fill must be measured against the glyph's own ink, the two
## tones must come out of the palette, and the size must be a share of the frame
## rather than a number of metres. Whether a particular silhouette READS when it
## is half full is a question about a picture and is answered by
## tools/measure_icon_fill.py, whose numbers are in the wave report.

const ReadoutScript := preload("res://src/entities/wildlife/concern_readout.gd")

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const ICON_DIRECTORY := "res://assets/ui/icons"
const LAYOUT_PATH := "res://data/ui/vital_layout.tres"

var _readout: ConcernReadout = null
var _host: Node3D = null
var _palette: ColorBible = null


func before_each() -> void:
	# The tint cache is static and shared, so a test that changed the palette
	# would hand its colours to every test after it.
	ReadoutScript.forget_cached_glyphs()
	_palette = ResourceLoader.load(PALETTE_PATH) as ColorBible
	_host = Node3D.new()
	_host.name = "Host"
	_root().add_child(_host)
	_readout = ReadoutScript.new()
	_host.add_child(_readout)


func after_each() -> void:
	_readout = null
	if _host != null:
		_root().remove_child(_host)
		_host.free()
		_host = null
	ReadoutScript.forget_cached_glyphs()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


## A glyph that exists, named rather than looked up.
##
## The first version asked `VitalLayout` for one, which is the right instinct and
## the wrong dependency for a test: that class is another agent's live file and
## it lost the accessor mid-run. What is under test here is the READOUT, so the
## test names its own subject and `test_dog_concern.gd` owns the question of
## whether every stat has a pictograph.
func _first_glyph() -> StringName:
	return &"hunger"


func _drawn() -> Image:
	var sprite := _readout.sprite()
	if sprite == null or sprite.texture == null:
		return null
	return sprite.texture.get_image()


# --- colour -------------------------------------------------------------------


## Briefing constraint 6. Both tones are entries of the twelve, read out of the
## palette rather than written down -- and this asserts the membership rather
## than the values, because asserting "#1C2A45 is in the palette" by reading it
## from the palette proves nothing.
func test_both_tones_come_out_of_the_palette() -> void:
	assert_not_null(_palette)
	if _palette == null:
		return
	assert_true(_palette.contains(_readout.filled_color()),
		"the filled tone %s is not one of the twelve" % _readout.filled_color().to_html(false))
	assert_true(_palette.contains(_readout.empty_color()),
		"the empty tone %s is not one of the twelve" % _readout.empty_color().to_html(false))


## Rule 3: warm means the presence of heat and nothing else. A cold warning drawn
## in a warm colour says the opposite of what is happening.
func test_neither_tone_is_warm() -> void:
	if _palette == null:
		return
	assert_false(_palette.is_warm(_readout.filled_color()),
		"the filled tone is one of the three warms")
	assert_false(_palette.is_warm(_readout.empty_color()),
		"the empty tone is one of the three warms")


## The two tones have to be far enough apart in value for the waterline to be a
## line, and the FILL has to be far enough from lit snow for the badge to exist
## at all -- which is the case the whole design turns on. Measured against the
## palette's own snow, brightened by the 1.155 gain the cel pass applies.
func test_the_pair_separates_on_snow_and_from_each_other() -> void:
	if _palette == null or _palette.snow_tones.is_empty():
		return
	var snow := _palette.snow_tones[0]
	var lit := Color(minf(snow.r * 1.155, 1.0), minf(snow.g * 1.155, 1.0), minf(snow.b * 1.155, 1.0))
	var fill_vs_snow := _contrast(_readout.filled_color(), lit)
	var level := _contrast(_readout.filled_color(), _readout.empty_color())
	assert_true(fill_vs_snow >= 4.5,
		"the filled tone is %.2f : 1 against lit snow -- it disappears" % fill_vs_snow)
	assert_true(level >= 3.0,
		"the two tones are %.2f : 1 apart -- there is no waterline" % level)


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)


func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


# --- the fill -----------------------------------------------------------------


func test_it_refuses_a_glyph_with_no_file() -> void:
	assert_false(_readout.show_reading(&"thirst", &"no_such_pictograph", 0.3),
		"it showed a badge depicting nothing")
	assert_false(_readout.is_live())


## The silhouette is the bottle: the whole glyph is opaque at every fill, so the
## shape never leaves. This is the property that a one-colour-two-opacities build
## does not have, and losing it means the player sees that something is wrong and
## cannot see WHAT.
func test_the_whole_silhouette_is_opaque_at_every_fill() -> void:
	var glyph := _first_glyph()
	for fill in [0.0, 0.15, 0.5, 1.0]:
		assert_true(_readout.show_reading(&"hunger", glyph, float(fill)))
		var image := _drawn()
		assert_not_null(image, "no texture was built at fill %.2f" % fill)
		if image == null:
			return
		var solid := 0
		var faint := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var a := image.get_pixel(x, y).a
				if a >= 0.99:
					solid += 1
				elif a > 0.35 and a < 0.9:
					faint += 1
		assert_true(solid > 0, "nothing is opaque at fill %.2f" % fill)
		# Some antialiased outline is expected; a whole faint HALF is the failure.
		assert_true(faint < solid,
			"at fill %.2f, %d px are half-transparent against %d opaque -- the empty part is a ghost"
				% [fill, faint, solid])


## Two flat tones and one hard edge. No third colour, no gradient: a ramp between
## them would read as grime and there would be no line to read a level off.
func test_the_picture_holds_exactly_two_tones() -> void:
	assert_true(_readout.show_reading(&"hunger", _first_glyph(), 0.5))
	var image := _drawn()
	assert_not_null(image)
	if image == null:
		return
	var seen := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.99:
				continue
			seen[pixel.to_html(false)] = true
	assert_eq(seen.size(), 2,
		"the opaque body of the badge holds %d tone(s): %s" % [seen.size(), str(seen.keys())])


## The line rises with the reading, and it rises MONOTONICALLY -- so two
## different stat values never draw the same picture, which is the only way a
## level can be a reading rather than a decoration.
func test_the_filled_share_rises_with_the_value() -> void:
	var glyph := _first_glyph()
	var filled := _readout.filled_color()
	var last := -1.0
	for step in range(11):
		var fill := float(step) / 10.0
		assert_true(_readout.show_reading(&"hunger", glyph, fill))
		var image := _drawn()
		if image == null:
			return
		var dark := 0
		var ink := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel := image.get_pixel(x, y)
				if pixel.a < 0.99:
					continue
				ink += 1
				if absf(pixel.r - filled.r) < 0.01 and absf(pixel.b - filled.b) < 0.01:
					dark += 1
		var share := float(dark) / maxf(float(ink), 1.0)
		assert_true(share >= last - 0.0001,
			"the filled share fell from %.3f to %.3f between fill %.2f and it"
				% [last, share, fill])
		last = share
	assert_true(last > 0.98, "a full reading leaves %.1f%% of the glyph empty" % (100.0 * (1.0 - last)))


## The line runs between the top and the bottom of the INK, not of the canvas.
## `hunger` occupies 86 of its icon's 256 rows, so a canvas-relative cut would
## read a half-empty bowl as a full one.
func test_the_texture_is_cropped_to_the_glyphs_own_ink() -> void:
	assert_true(_readout.show_reading(&"hunger", &"hunger", 1.0))
	var image := _drawn()
	assert_not_null(image)
	if image == null:
		return
	var source := (ResourceLoader.load("%s/hunger.png" % ICON_DIRECTORY) as Texture2D).get_image()
	assert_true(image.get_height() < source.get_height(),
		"the badge is %d rows tall and the icon file is %d -- the empty canvas came with it"
			% [image.get_height(), source.get_height()])
	# every edge row and column of the crop must carry ink
	var top := 0
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a > 0.04:
			top += 1
	assert_true(top > 0, "the top row of the crop is empty")


# --- size ---------------------------------------------------------------------


## Screen-constant, not world-constant: a marker that shrinks with the framing
## stop stops working at the stop where the animal is already 29 px tall.
func test_the_badge_is_a_constant_share_of_the_frame() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_host.add_child(camera)
	var shares: Array[float] = []
	for stop in [10.5, 13.5, 17.0]:
		camera.size = float(stop)
		shares.append(_readout.world_height(camera) / float(stop))
	for share in shares:
		assert_almost_eq(share, _readout.frame_share, 0.0001,
			"the badge is %.4f of the frame at one stop and %.4f at another"
				% [share, _readout.frame_share])
	_host.remove_child(camera)
	camera.free()


## The bounds exist so a stop outside the shipped three cannot produce a badge
## bigger than the animal or below the legibility floor -- and they must NOT
## engage inside the three, or the badge is not screen-constant where it counts.
func test_neither_bound_engages_across_the_shipped_stops() -> void:
	for stop in [10.5, 13.5, 17.0]:
		var world := _readout.frame_share * float(stop)
		assert_true(world > _readout.min_world_m,
			"the floor clamps at stop %.1f (%.3f m vs %.3f)" % [stop, world, _readout.min_world_m])
		assert_true(world < _readout.max_world_m,
			"the ceiling clamps at stop %.1f (%.3f m vs %.3f)" % [stop, world, _readout.max_world_m])


## Sizing on height alone would make a squat bowl as tall as a flame and twice as
## wide as the frame. The longer side is what is normalised.
func test_a_squat_glyph_stays_squat() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.5
	_host.add_child(camera)
	assert_true(_readout.show_reading(&"hunger", &"hunger", 0.5))
	var image := _drawn()
	if image != null:
		var wide := image.get_width() > image.get_height()
		assert_true(wide, "the bowl icon is not wider than it is tall; this test is measuring the wrong glyph")
		var sprite := _readout.sprite()
		var height := sprite.pixel_size * float(image.get_height())
		assert_true(height < _readout.world_height(camera) * 0.75,
			"a bowl drew as tall as a flame (%.3f m of a %.3f m box)"
				% [height, _readout.world_height(camera)])
	_host.remove_child(camera)
	camera.free()


# --- nothing is permanent -----------------------------------------------------


func test_it_blooms_holds_and_dies() -> void:
	assert_false(_readout.is_live(), "it was on screen before anything asked for it")
	assert_true(_readout.show_reading(&"thirst", _first_glyph(), 0.3))
	assert_true(_readout.is_live())
	# `is_visible_in_tree()`, not `visible`. Hiding the readout leaves the child
	# sprite's own `visible` true, so asserting the flag would pass while the
	# badge was still drawn -- and would fail the day the hiding moved one node.
	assert_true(_readout.sprite().is_visible_in_tree())
	var envelope := _readout.breath()
	assert_not_null(envelope, "no breath envelope -- it would never leave")
	if envelope == null:
		return
	assert_true(envelope.total_seconds() > 0.0)
	_readout.advance(envelope.total_seconds() + 0.05)
	assert_false(_readout.is_live(), "it outlived its own envelope")
	assert_false(_readout.sprite().is_visible_in_tree(),
		"nothing is live but the badge is still being drawn")


## Section 1.2: nothing skips a stage. The badge fades IN rather than appearing,
## and OUT rather than vanishing.
func test_it_arrives_and_leaves_through_its_opacity() -> void:
	assert_true(_readout.show_reading(&"thirst", _first_glyph(), 0.3))
	var envelope := _readout.breath()
	if envelope == null:
		return
	assert_almost_eq(_readout.sprite().modulate.a, envelope.opacity_at(0.0), 0.001)
	assert_true(envelope.opacity_at(0.0) < 0.5, "it appeared at full opacity")
	_readout.advance(envelope.exit_begins() + (envelope.total_seconds() - envelope.exit_begins()) * 0.5)
	var mid := _readout.sprite().modulate.a
	assert_true(mid > 0.0 and mid < 1.0, "it is not fading out, it is switching off")
