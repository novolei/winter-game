extends TestCase

## Pointer parallax -- the spatial copy counter-follows the cursor by at most
## six pixels with exponential smoothing. Compact layouts pin it to zero, and
## the camera itself never moves (a moving camera is what would nauseate).

const SpatialScript := preload("res://src/ui/spatial_pause_menu.gd")
const Tokens: UITokens = preload("res://data/ui/tokens.tres")

var _spatial: SpatialPauseMenu = null

func before_each() -> void:
	var fonts := UIFonts.new()
	fonts.build(Tokens)
	_spatial = SpatialScript.new()
	_spatial.setup(Tokens, fonts)

func after_each() -> void:
	if _spatial != null:
		_spatial.free()
		_spatial = null

func test_the_pointer_offset_is_capped() -> void:
	_spatial.set_pointer_normalized(Vector2(5.0, -5.0))
	for i in range(120):
		_spatial._process(1.0 / 60.0)
	var offset := _spatial.pointer_offset()
	assert_true(offset.length() <= SpatialScript.POINTER_PARALLAX_PIXELS * 1.42,
		"parallax escaped its cap: %s" % offset)

func test_parallax_counters_the_cursor() -> void:
	_spatial.set_pointer_normalized(Vector2(1.0, 0.0))
	for i in range(120):
		_spatial._process(1.0 / 60.0)
	assert_true(_spatial.pointer_offset().x < 0.0,
		"the copy must drift AGAINST the cursor, not with it")

func test_compact_layout_forces_zero() -> void:
	_spatial.set_pointer_normalized(Vector2(1.0, 1.0))
	_spatial.layout(Rect2(Vector2.ZERO, Vector2(300, 320)), 0.78, true, 104.0)
	for i in range(120):
		_spatial._process(1.0 / 60.0)
	assert_eq(_spatial.pointer_offset(), Vector2.ZERO)
