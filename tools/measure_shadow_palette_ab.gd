extends SceneTree

## Measures the matched 1600x1000 output of capture_shadow_palette_ab.tscn.
##
## Example:
## Godot_console.exe --headless --path <project> --script \
##   res://tools/measure_shadow_palette_ab.gd -- \
##   --dir C:/.../winter-time-shadow-palette-ab
##
## The two rectangles are deliberately away from the traveller, building faces,
## snow particles, and the hard transition itself. They sample adjacent open
## snow and the broad, uninterrupted farmhouse cast shadow in the real opening
## gameplay framing. This is a reviewer instrument, not runtime code.

const PRESETS := [&"pale_day", &"sunrise", &"nightfall", &"deep_night", &"whiteout"]
const CANDIDATES := [&"control", &"slate_a", &"slate_b"]
const LIT_SAMPLE := Rect2i(850, 300, 200, 60)
const SHADOW_SAMPLE := Rect2i(900, 430, 200, 70)
const EXPECTED_SIZE := Vector2i(1600, 1000)


func _initialize() -> void:
	var directory := _string_arg(OS.get_cmdline_user_args(), "--dir", "")
	if directory.is_empty():
		push_error("measure_shadow_palette_ab: pass --dir containing the capture PNGs")
		quit(1)
		return
	print("candidate,preset,lit,shadow,lit_chroma,shadow_chroma,chroma_ratio,luminance_ratio,day_gate")
	var failed := false
	for candidate in CANDIDATES:
		for preset in PRESETS:
			var path := directory.path_join("%s_%s.png" % [candidate, preset])
			var image := Image.load_from_file(path)
			if image == null:
				push_error("measure_shadow_palette_ab: could not load %s" % path)
				failed = true
				continue
			if image.get_size() != EXPECTED_SIZE:
				push_error(
					"measure_shadow_palette_ab: %s is %s; expected %s" % [
						path, image.get_size(), EXPECTED_SIZE
					]
				)
				failed = true
				continue
			var lit := _mean(image, LIT_SAMPLE)
			var shadow := _mean(image, SHADOW_SAMPLE)
			var lit_chroma := _chroma(lit)
			var shadow_chroma := _chroma(shadow)
			var chroma_ratio := float(shadow_chroma) / maxf(float(lit_chroma), 0.0001)
			var luminance_ratio := _luminance(shadow) / maxf(_luminance(lit), 0.0001)
			var gate := "not_applicable"
			if preset == &"pale_day":
				gate = "pass" if chroma_ratio <= 1.5 and luminance_ratio >= 0.78 and luminance_ratio <= 0.88 else "fail"
				if gate == "fail":
					failed = true
			print("%s,%s,#%s,#%s,%d,%d,%.3f,%.3f,%s" % [
				candidate, preset, lit.to_html(false), shadow.to_html(false), lit_chroma,
				shadow_chroma, chroma_ratio, luminance_ratio, gate
			])
	quit(1 if failed else 0)


func _string_arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _mean(image: Image, region: Rect2i) -> Color:
	var sum := Vector3.ZERO
	var count := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var pixel := image.get_pixel(x, y)
			sum += Vector3(pixel.r, pixel.g, pixel.b)
			count += 1
	return Color(sum.x / count, sum.y / count, sum.z / count)


func _chroma(color: Color) -> int:
	var encoded := color.to_html(false)
	var red := encoded.substr(0, 2).hex_to_int()
	var green := encoded.substr(2, 2).hex_to_int()
	var blue := encoded.substr(4, 2).hex_to_int()
	return maxi(red, maxi(green, blue)) - mini(red, mini(green, blue))


func _luminance(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
