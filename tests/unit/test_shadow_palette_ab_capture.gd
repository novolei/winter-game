extends TestCase

const CaptureScript := preload("res://tools/capture_shadow_palette_ab.gd")


func _candidate(id: StringName) -> Dictionary:
	var capture := CaptureScript.new()
	var candidate: Dictionary = capture.candidate_for(id)
	capture.free()
	return candidate


func _review_bible(id: StringName) -> ColorBible:
	var capture := CaptureScript.new()
	var bible: ColorBible = capture.review_bible_for(id)
	capture.free()
	return bible


func _chroma(color: Color) -> int:
	var encoded := color.to_html(false)
	var red := encoded.substr(0, 2).hex_to_int()
	var green := encoded.substr(2, 2).hex_to_int()
	var blue := encoded.substr(4, 2).hex_to_int()
	return maxi(red, maxi(green, blue)) - mini(red, mini(green, blue))


func _encoded_luminance(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


func test_the_review_has_one_shipped_control_and_two_named_candidates() -> void:
	for id in [&"control", &"slate_a", &"slate_b"]:
		assert_false(_candidate(id).is_empty(), "missing shadow palette review candidate '%s'" % id)
	assert_true(_candidate(&"unknown").is_empty(), "unknown candidate silently falls back to a colour")


func test_each_candidate_is_cooler_than_neutral_but_less_chromatic_than_the_control() -> void:
	var control: Color = _candidate(&"control")["snow_shade"]
	var control_chroma := _chroma(control)
	for id in [&"slate_a", &"slate_b"]:
		var shade: Color = _candidate(id)["snow_shade"]
		assert_true(shade.b > shade.r, "%s is no longer a cold shadow" % id)
		assert_true(
			_chroma(shade) <= 50,
			"%s spans %d encoded channels; review candidates must stay in the 35-50 slate band"
			% [id, _chroma(shade)]
		)
		assert_true(
			_chroma(shade) < control_chroma,
			"%s is not less chromatic than the shipped #%s control" % [id, control.to_html(false)]
		)


func test_each_candidate_preserves_a_darker_track_step() -> void:
	for id in [&"control", &"slate_a", &"slate_b"]:
		var candidate := _candidate(id)
		var shade: Color = candidate["snow_shade"]
		var track: Color = candidate["track_shade"]
		assert_true(
			_encoded_luminance(track) < _encoded_luminance(shade),
			"%s makes its track shade as bright as its broad shadow" % id
		)


func test_each_review_candidate_is_a_complete_palette_with_its_shadow_entries_inside_it() -> void:
	for id in [&"control", &"slate_a", &"slate_b"]:
		var candidate := _candidate(id)
		var bible := _review_bible(id)
		assert_not_null(bible, "%s cannot build a review ColorBible" % id)
		if bible == null:
			continue
		assert_eq(bible.all_colors().size(), 12, "%s review palette is not a 12-colour Bible" % id)
		assert_true(
			bible.contains(candidate["snow_shade"]),
			"%s writes a shadow outside its own review ColorBible" % id
		)
		assert_true(
			bible.contains(candidate["track_shade"]),
			"%s writes a track shade outside its own review ColorBible" % id
		)
