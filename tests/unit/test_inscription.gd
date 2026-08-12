extends TestCase

## Spatial typography -- UI design document section 5.9. A line of narration that
## lives in the world rather than on the lens: written one glyph at a time,
## foreshortened by whatever the camera is doing, occluded by whatever stands in
## front of it, and finally taken by the wind and dissolved.
##
## ---------------------------------------------------------------------------
## THE THREE PROPERTIES THAT MAKE IT SPATIAL RATHER THAN AN OVERLAY
## ---------------------------------------------------------------------------
## Each is one line to get wrong and none of them raises anything:
##
##   billboard DISABLED   -- a billboarded glyph turns to face the camera, so a
##                           dolly past it produces no foreshortening at all and
##                           the whole effect collapses into a screen overlay
##                           that happens to be rendered in 3D.
##   depth test ON        -- the occlusion compositing. Without it the text draws
##                           over the trees it is supposed to be standing behind.
##   alpha cut HASH       -- what makes the exit read as the glyph coming apart
##                           into specks rather than fading out politely.
##
## So they are asserted directly. A screenshot would catch the first two, but
## only if somebody looked at the right frame.

const InscriptionScript := preload("res://src/ui/inscription.gd")
const UIFontsScript := preload("res://src/ui/ui_fonts.gd")
const TOKENS_PATH := "res://data/ui/tokens.tres"

const LINE := "长夜将尽"

var _tokens: UITokens
var _fonts
var _line: Inscription = null

func before_each() -> void:
	_tokens = ResourceLoader.load(TOKENS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as UITokens
	_fonts = UIFontsScript.new()
	_fonts.build(_tokens)

func after_each() -> void:
	# Node is not reference counted; an un-freed one is a leaked ObjectDB
	# instance and a dirty console (briefing constraint 2).
	if _line != null:
		_line.free()
		_line = null

func _write(text := LINE) -> Inscription:
	_line = InscriptionScript.new()
	_line.compose(text, _fonts.display, _tokens)
	return _line

# --- composition ------------------------------------------------------------

func test_it_makes_one_glyph_for_each_visible_character() -> void:
	var line := _write("长夜将尽")
	assert_eq(line.glyph_count(), 4)

## A space advances the pen but has nothing to draw, and a Label3D holding a
## space is an invisible node that still costs a draw call and still takes a
## breath of its own -- which would put a gap in the stagger where nothing
## appears.
func test_spaces_advance_the_line_without_becoming_glyphs() -> void:
	var line := _write("a b")
	assert_eq(line.glyph_count(), 2, "two visible characters")
	assert_true(line.width() > 0.0)

func test_glyphs_are_laid_out_left_to_right() -> void:
	var line := _write()
	var previous := -INF
	for i in line.glyph_count():
		var x: float = line.glyph_at(i).position.x
		assert_true(x > previous, "glyph %d sits at %.4f, not right of %.4f" % [i, x, previous])
		previous = x

func test_an_empty_line_makes_nothing_and_lasts_no_time() -> void:
	var line := _write("")
	assert_eq(line.glyph_count(), 0)
	assert_almost_eq(line.total_seconds(), 0.0, 0.0001)

# --- the three spatial properties -------------------------------------------

## If the glyph billboards, the camera dolly produces no perspective change and
## section 5.9 is just an overlay drawn in 3D.
func test_glyphs_do_not_billboard() -> void:
	var line := _write()
	for i in line.glyph_count():
		assert_eq(line.glyph_at(i).billboard, BaseMaterial3D.BILLBOARD_DISABLED,
			"glyph %d billboards, so it can never foreshorten" % i)

## Occlusion compositing: the text has to be behind what is in front of it.
func test_glyphs_are_depth_tested_so_the_world_can_occlude_them() -> void:
	var line := _write()
	for i in line.glyph_count():
		assert_false(line.glyph_at(i).no_depth_test,
			"glyph %d ignores depth, so it draws through the trees" % i)

## Alpha hash is what turns the exit into specks rather than a fade.
func test_glyphs_dissolve_by_hash_rather_than_fading_flat() -> void:
	var line := _write()
	for i in line.glyph_count():
		assert_eq(line.glyph_at(i).alpha_cut, Label3D.ALPHA_CUT_HASH,
			"glyph %d fades flat instead of coming apart" % i)

## Section 5.9 gives narration the warm token because it is the voice of somebody
## still alive -- the first pillar, not an exception to it.
func test_the_line_is_written_in_the_warm_token() -> void:
	var line := _write()
	assert_eq(line.glyph_at(0).modulate.r, _tokens.life_warm.r)
	assert_eq(line.glyph_at(0).modulate.g, _tokens.life_warm.g)
	assert_eq(line.glyph_at(0).modulate.b, _tokens.life_warm.b)

# --- the writing ------------------------------------------------------------

func test_nothing_is_visible_before_the_first_glyph_is_written() -> void:
	var line := _write()
	line.seek(0.0)
	for i in line.glyph_count():
		assert_almost_eq(line.glyph_at(i).modulate.a, 0.0, 0.0001, "glyph %d" % i)

## Written, not switched on: at the moment the first glyph is fully present the
## last one has not started.
func test_the_line_is_written_one_glyph_after_another() -> void:
	var line := _write()
	var first_done: float = line.breath_at(0).delay + line.breath_at(0).bloom_seconds
	line.seek(first_done)
	assert_almost_eq(line.glyph_at(0).modulate.a, 1.0, 0.001, "the first glyph is there")
	var last := line.glyph_count() - 1
	assert_true(line.glyph_at(last).modulate.a < 0.999,
		"the last glyph is already fully written, so the line appeared rather than being written")

## Every glyph must be readable for the same length of time. A constant hold
## would leave the opening character on screen longer than the closing one,
## because the closing one was written later.
func test_every_glyph_is_readable_for_the_same_span() -> void:
	var line := _write()
	var spans: Array[float] = []
	for i in line.glyph_count():
		spans.append(line.breath_at(i).hold_seconds)
	for i in range(1, spans.size()):
		assert_almost_eq(spans[i], spans[0], 0.0001, "glyph %d holds for a different span" % i)

func test_the_whole_line_is_present_in_the_middle_of_its_hold() -> void:
	var line := _write()
	var last := line.glyph_count() - 1
	var b := line.breath_at(last)
	line.seek(b.delay + b.bloom_seconds + b.hold_seconds * 0.5)
	for i in line.glyph_count():
		assert_almost_eq(line.glyph_at(i).modulate.a, 1.0, 0.001, "glyph %d" % i)

# --- the wind ---------------------------------------------------------------

## The glyphs sit exactly where they were written until the wind reaches them.
## Text that crept during its own hold reads as sliding rather than as written.
func test_glyphs_hold_their_place_until_the_wind_takes_them() -> void:
	var line := _write()
	line.scatter_along(Vector2(1.0, -0.25), 1.4, 0.9)
	var placed: Array[Vector3] = []
	for i in line.glyph_count():
		placed.append(line.glyph_at(i).position)
	var b := line.breath_at(line.glyph_count() - 1)
	line.seek(b.delay + b.bloom_seconds + b.hold_seconds * 0.5)
	for i in line.glyph_count():
		assert_almost_eq(line.glyph_at(i).position.distance_to(placed[i]), 0.0, 0.0001,
			"glyph %d moved during its hold" % i)

func test_by_the_end_every_glyph_has_gone_and_moved() -> void:
	var line := _write()
	line.scatter_along(Vector2(1.0, -0.25), 1.4, 0.9)
	var placed: Array[Vector3] = []
	for i in line.glyph_count():
		placed.append(line.glyph_at(i).position)
	line.seek(line.total_seconds())
	for i in line.glyph_count():
		assert_almost_eq(line.glyph_at(i).modulate.a, 0.0, 0.0001, "glyph %d is still visible" % i)
		assert_true(line.glyph_at(i).position.distance_to(placed[i]) > 0.5,
			"glyph %d never went anywhere" % i)

## Letters of one word must not fly off in formation -- that reads as a sliding
## block rather than a word coming apart.
func test_no_two_glyphs_leave_on_the_same_vector() -> void:
	var line := _write()
	line.scatter_along(Vector2(1.0, -0.25), 1.4, 0.9)
	var placed: Array[Vector3] = []
	for i in line.glyph_count():
		placed.append(line.glyph_at(i).position)
	line.seek(line.total_seconds())
	var moves: Array[Vector3] = []
	for i in line.glyph_count():
		moves.append(line.glyph_at(i).position - placed[i])
	for i in range(moves.size()):
		for j in range(i + 1, moves.size()):
			assert_true(moves[i].distance_to(moves[j]) > 0.001,
				"glyphs %d and %d left on identical vectors" % [i, j])

func test_glyphs_turn_as_they_go() -> void:
	var line := _write()
	line.scatter_along(Vector2(1.0, -0.25), 1.4, 0.9)
	line.seek(line.total_seconds())
	var turned := 0
	for i in line.glyph_count():
		if absf(line.glyph_at(i).rotation.z) > 0.05:
			turned += 1
	assert_eq(turned, line.glyph_count(), "every glyph should have turned on its way out")

# --- lifetime ---------------------------------------------------------------

func test_it_reports_when_the_whole_line_is_over() -> void:
	var line := _write()
	assert_false(line.is_finished(0.0))
	assert_false(line.is_finished(line.total_seconds() - 0.01))
	assert_true(line.is_finished(line.total_seconds()))

## The line lasts as long as its LAST glyph, not its first.
func test_the_total_covers_the_last_glyph() -> void:
	var line := _write()
	var last = line.breath_at(line.glyph_count() - 1)
	assert_almost_eq(line.total_seconds(), last.total_seconds(), 0.0001)

## Section 5.6 again: the cold snap reaches the narration too.
func test_the_cold_snap_slows_the_whole_line() -> void:
	var plain := _write()
	var plain_total := plain.total_seconds()
	plain.free()
	_line = null
	var cold := _write()
	cold.stretch(_tokens.cold_snap_scale)
	assert_almost_eq(cold.total_seconds(), plain_total * _tokens.cold_snap_scale, 0.0001)
