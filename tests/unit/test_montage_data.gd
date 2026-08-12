extends TestCase

## The gate on res://data/montage -- UI design document section 4.5.
##
## tests/unit/test_montage_director.gd tests the machine on montages it builds
## itself. This file tests the CONTENT: that the shipped montages are playable,
## and specifically that every authored line finishes before its own shot cuts.
##
## That is the failure worth a test. An inscription still scattering when the cut
## lands loses its last glyphs mid-flight -- and it is invisible unless somebody
## happens to watch that exact second, at which point it reads as a rendering
## glitch rather than as a duration that is four tenths too short.

const MONTAGE_DIR := "res://data/montage"
const TOKENS_PATH := "res://data/ui/tokens.tres"

var _tokens: UITokens
var _montages: Array = []

func before_each() -> void:
	_tokens = ResourceLoader.load(TOKENS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as UITokens
	_montages = []
	var dir := DirAccess.open(MONTAGE_DIR)
	if dir == null:
		return
	var names := dir.get_files()
	names.sort()
	for entry in names:
		var file_name := entry
		# An exported build serves data/*.tres as *.tres.remap.
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource := ResourceLoader.load(
			MONTAGE_DIR.path_join(file_name), "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is Montage:
			_montages.append(resource)

func test_at_least_the_opening_ships() -> void:
	assert_true(_montages.size() > 0, "%s holds no montage -- run tools/generate_montages.gd" % MONTAGE_DIR)
	var ids: Array[StringName] = []
	for montage in _montages:
		ids.append(montage.id)
	assert_true(ids.has(&"opening"), "the opening montage is missing; found %s" % [ids])

func test_every_montage_has_an_id_and_some_shots() -> void:
	for montage in _montages:
		assert_true(montage.id != &"", "a montage shipped with no id")
		assert_true(montage.shot_count() > 0, "montage %s has no shots" % montage.id)

## A zero-length shot cannot be seen and a negative one runs the clock backwards.
func test_every_shot_lasts_a_positive_time() -> void:
	for montage in _montages:
		for index in montage.shot_count():
			var shot: MontageShot = montage.shots[index]
			assert_not_null(shot, "%s shot %d is null" % [montage.id, index])
			if shot == null:
				continue
			assert_true(shot.duration > 0.0,
				"%s shot %d lasts %.2f s" % [montage.id, index, shot.duration])

## THE ONE THIS FILE EXISTS FOR.
##
## The line's duration is not authored -- it falls out of the character count,
## because every glyph is staggered and every glyph's hold grows to match. So a
## line lengthened by two characters silently needs another 0.28 s of shot, and
## nothing would say so.
func test_every_line_finishes_before_its_shot_cuts() -> void:
	for montage in _montages:
		for index in montage.shot_count():
			var shot: MontageShot = montage.shots[index]
			if shot == null or not shot.has_text():
				continue
			var count := shot.text.length()
			# The last glyph is the one that finishes last.
			var line := Breath.inscription(_tokens, count - 1, count)
			var needed: float = shot.text_start + line.total_seconds()
			assert_true(needed <= shot.duration,
				"%s shot %d: \"%s\" needs %.2f s (starts at %.2f, runs %.2f) but the shot is %.2f s"
					% [montage.id, index, shot.text, needed, shot.text_start,
					   line.total_seconds(), shot.duration])

## A line that begins before the shot does, or after it ends, is an authoring
## slip that the fit test above would not always catch on its own.
func test_every_line_starts_inside_its_shot() -> void:
	for montage in _montages:
		for index in montage.shot_count():
			var shot: MontageShot = montage.shots[index]
			if shot == null or not shot.has_text():
				continue
			assert_true(shot.text_start >= 0.0,
				"%s shot %d starts its line at %.2f s" % [montage.id, index, shot.text_start])
			assert_true(shot.text_start < shot.duration,
				"%s shot %d starts its line at %.2f s, after the %.2f s shot has cut"
					% [montage.id, index, shot.text_start, shot.duration])

## The montage camera is a PERSPECTIVE camera and its field of view is the thing
## the whole effect is made of -- a zero or a negative one is not a look, it is a
## broken projection.
func test_every_shot_has_a_sane_field_of_view() -> void:
	for montage in _montages:
		for index in montage.shot_count():
			var shot: MontageShot = montage.shots[index]
			if shot == null:
				continue
			for fov in [shot.fov_from, shot.fov_to]:
				assert_true(fov > 1.0 and fov < 179.0,
					"%s shot %d has a field of view of %.1f" % [montage.id, index, fov])

## The camera has to actually go somewhere, or the shot is a still frame and the
## letters never foreshorten -- which is the entire point of section 5.9.
func test_the_camera_moves_in_every_shot_that_carries_a_line() -> void:
	for montage in _montages:
		for index in montage.shot_count():
			var shot: MontageShot = montage.shots[index]
			if shot == null or not shot.has_text():
				continue
			var travelled := shot.camera_from.origin.distance_to(shot.camera_to.origin)
			var zoomed := absf(shot.fov_from - shot.fov_to)
			assert_true(travelled > 0.1 or zoomed > 0.5,
				"%s shot %d holds still, so its line can never foreshorten" % [montage.id, index])

## A montage that outlasts the player's patience is a design decision, not an
## accident, and this is where it would be noticed becoming one.
func test_no_montage_outstays_its_welcome() -> void:
	for montage in _montages:
		assert_true(montage.total_seconds() <= 45.0,
			"montage %s runs %.1f s" % [montage.id, montage.total_seconds()])
