extends TestCase

## The accepted Slate B review swatch is a palette decision, not a temporary
## capture override. Pin the two shadow-side entries here so a future palette
## regeneration cannot quietly restore the more saturated blue control.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const SLATE_B_SNOW_SHADOW := Color("#76889F")
const SLATE_B_TRACK_SHADOW := Color("#667890")


func test_shipped_snow_shadow_uses_the_approved_restrained_slate_b_pair() -> void:
	var bible: ColorBible = load(PALETTE_PATH)
	assert_not_null(bible, "the shipping ColorBible must load")
	if bible == null:
		return
	assert_eq(bible.snow_tones[3], SLATE_B_SNOW_SHADOW)
	assert_eq(bible.snow_tones[4], SLATE_B_TRACK_SHADOW)


func test_the_shipped_slate_b_shadow_stays_cold_but_subordinate_to_lit_snow() -> void:
	var bible: ColorBible = load(PALETTE_PATH)
	assert_not_null(bible, "the shipping ColorBible must load")
	if bible == null:
		return
	var shadow: Color = bible.snow_tones[3]
	var lit: Color = bible.snow_tones[0]
	var shadow_chroma := _encoded_chroma(shadow)
	var lit_chroma := _encoded_chroma(lit)
	assert_true(shadow.b > shadow.r, "snow shade must remain visibly cold")
	assert_true(shadow_chroma <= 50, "shadow must remain in the restrained slate chroma band")
	assert_true(
		shadow_chroma <= lit_chroma * 1.5,
		"shadow chroma must not outrun its adjacent lit snow"
	)
	# This is the palette-space proxy for the 0.78..0.88 screen-space gate in
	# the D3D12 capture report. Tonemapping and the live light band raise the
	# final screen ratio; palette entries themselves sit in this tighter range.
	var palette_luminance_ratio := _encoded_luminance_ratio(shadow, lit)
	assert_true(
		palette_luminance_ratio >= 0.77 and palette_luminance_ratio <= 0.80,
		"shadow must retain the palette-space separation that renders as a readable cast shadow"
	)


func _encoded_chroma(color: Color) -> int:
	var encoded := color.to_html(false)
	var red := encoded.substr(0, 2).hex_to_int()
	var green := encoded.substr(2, 2).hex_to_int()
	var blue := encoded.substr(4, 2).hex_to_int()
	return maxi(red, maxi(green, blue)) - mini(red, mini(green, blue))


func _encoded_luminance_ratio(shadow: Color, lit: Color) -> float:
	var shadow_luminance := 0.2126 * shadow.r + 0.7152 * shadow.g + 0.0722 * shadow.b
	var lit_luminance := 0.2126 * lit.r + 0.7152 * lit.g + 0.0722 * lit.b
	return shadow_luminance / lit_luminance
