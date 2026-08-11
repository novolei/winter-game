extends SceneTree

## Measures a candidate snow-relief profile the way the camera sees it, without
## rendering anything.
##
## WHY THIS EXISTS. The terrain relief has now been retuned three times, and the
## reason it keeps coming back is that the thing being judged -- "does the field
## read as flat like the painting, or as rolling dunes" -- was judged by eye off
## a screenshot each time. It is not a matter of taste and it is not height: what
## makes a 70 m frame read as dunes is **how much of the field shades itself**,
## which is the fraction of it whose own slope carries N.L below the cel band's
## threshold. `Refs/game ref/level.jpg` shades none of its field; every dark
## shape on it is something's cast shadow.
##
## So that fraction is the number to tune against, and this prints it, at both
## framings, in about four seconds a candidate against forty for a capture.
##
##     "D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless ##         --path "D:/Godot resource/winter-time" ##         --script res://tools/relief_scan.gd -- ##         --amp 2.4 --flatten 0.34 --sharp 3.0 --band 0.12 --azimuth 82
##
## The defaults are the linear profile, so passing nothing prints the "before".
## The shipped numbers are the ones in the command above: 79.9% lit before,
## 97.1% after, with the snow depth mechanic measurably untouched (there is a
## test for that -- tests/unit/test_snow_field.gd).
##
## It reads the parameters as arguments rather than off SnowField's exports on
## purpose: a sweep has to be able to ask about numbers that are not shipped.

const SnowFieldScript := preload("res://src/systems/snow_field.gd")

## Everything below is read off src/rendering/terrain_renderer.gd and
## src/rendering/lighting_director.gd. They are duplicated rather than loaded
## because this tool has to be able to ask "what if they were different".

const ELEVATION := 21.5
const BAND_SOFTNESS := 0.07
const EPSILON := 0.8

var BAND_THRESHOLD := 0.22

# The establishing shot: 70 m of frame width centred on the composition.
const CENTRE := Vector3(6.0, 0.0, -14.0)
const HALF_X := 35.0
const HALF_Z := 31.0
const STEP := 0.7

# The gameplay frame, at the porch.
const PLAY_CENTRE := Vector3(13.0, 0.0, -6.0)
const PLAY_HALF := 8.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var amp := float(_arg(args, "--amp", "3.2"))
	var flatten := float(_arg(args, "--flatten", "1.0"))
	var sharp := float(_arg(args, "--sharp", "2.0"))
	var azimuth := float(_arg(args, "--azimuth", "118.0"))
	BAND_THRESHOLD = float(_arg(args, "--band", "0.22"))
	var freq := float(_arg(args, "--freq", "0.05"))

	var field: Node = SnowFieldScript.new()
	field.terrain_amplitude_m = amp
	field.noise_frequency = freq
	if "drift_flatten" in field:
		field.drift_flatten = flatten
		field.drift_sharpness = sharp
	field.build_at(CENTRE)

	var sun := _sun(azimuth)
	var wide := _scan(field, sun, CENTRE, HALF_X, HALF_Z)
	var play := _scan(field, sun, PLAY_CENTRE, PLAY_HALF, PLAY_HALF)
	print("amp %.2f flatten %.2f sharp %.2f az %.0f band %.2f freq %.3f" % [amp, flatten, sharp, azimuth, BAND_THRESHOLD, freq])
	print("  wide 70x62m: lit %5.1f%%  surface p5..p95 %6.2f..%5.2f m  slope p50 %4.1f p75 %4.1f p90 %4.1f p99 %4.1f deg  depth %.2f..%.2f" % [
		wide["lit"] * 100.0, wide["p5"], wide["p95"],
		wide["s50"], wide["s75"], wide["s90"], wide["s99"], wide["depth_lo"], wide["depth_hi"],
	])
	print("  play 16x16m: lit %5.1f%%  surface p5..p95 %6.2f..%5.2f m  slope p50 %4.1f p75 %4.1f p90 %4.1f p99 %4.1f deg  depth %.2f..%.2f" % [
		play["lit"] * 100.0, play["p5"], play["p95"],
		play["s50"], play["s75"], play["s90"], play["s99"], play["depth_lo"], play["depth_hi"],
	])
	field.free()
	quit()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


## The direction the light travels, matching LightingDirector's rotation.
func _sun(azimuth_degrees: float) -> Vector3:
	var light := Node3D.new()
	light.rotation = Vector3(deg_to_rad(-ELEVATION), deg_to_rad(azimuth_degrees), 0.0)
	var forward := -light.transform.basis.z
	light.free()
	return forward.normalized()


func _scan(field: Node, sun: Vector3, centre: Vector3, half_x: float, half_z: float) -> Dictionary:
	var heights: Array[float] = []
	var slopes: Array[float] = []
	var lit := 0
	var total := 0
	var depth_lo := INF
	var depth_hi := -INF
	var to_light := -sun
	var x := centre.x - half_x
	while x <= centre.x + half_x:
		var z := centre.z - half_z
		while z <= centre.z + half_z:
			var at := Vector3(x, 0.0, z)
			var height: float = field.surface_height_at(at)
			var gradient: Vector2 = field.surface_gradient_at(at, EPSILON)
			var normal := Vector3(-gradient.x, 1.0, -gradient.y).normalized()
			var lambert := maxf(normal.dot(to_light), 0.0)
			var band := smoothstep(BAND_THRESHOLD - BAND_SOFTNESS, BAND_THRESHOLD + BAND_SOFTNESS, lambert)
			if band > 0.5:
				lit += 1
			total += 1
			heights.append(height)
			slopes.append(rad_to_deg(atan(gradient.length())))
			var depth: float = field.depth_at(at)
			depth_lo = minf(depth_lo, depth)
			depth_hi = maxf(depth_hi, depth)
			z += STEP
		x += STEP
	heights.sort()
	slopes.sort()
	return {
		"lit": float(lit) / float(total),
		"p5": heights[int(float(heights.size()) * 0.05)],
		"p95": heights[int(float(heights.size()) * 0.95)],
		"s50": slopes[int(float(slopes.size()) * 0.50)],
		"s75": slopes[int(float(slopes.size()) * 0.75)],
		"s90": slopes[int(float(slopes.size()) * 0.90)],
		"s99": slopes[int(float(slopes.size()) * 0.99)],
		"depth_lo": depth_lo,
		"depth_hi": depth_hi,
	}
