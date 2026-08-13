extends SceneTree

## A repeatable Phase-A probe for the shipped SnowField depth distribution.
## It samples the full 120 m field on a half-metre lattice, then uses an
## integral image to examine every 12 m square on a one-metre stride.  The
## result deliberately measures depth rather than the rendered snow texture:
## this is the quantity the wade, footprint and furrow systems consume.

const SnowFieldScript := preload("res://src/systems/snow_field.gd")

const DEFAULT_SAMPLE_M := 0.5
const BLOCK_M := 12.0
const BLOCK_STRIDE_M := 1.0
const MIDDLE_LOW_M := 0.02
const MIDDLE_HIGH_M := 0.32


func _init() -> void:
	var field: SnowField = SnowFieldScript.new()
	field.build_at(Vector3.ZERO)
	var requested_span := float(_arg(OS.get_cmdline_user_args(), "--span", "120"))
	var sample_m := maxf(float(_arg(OS.get_cmdline_user_args(), "--sample", str(DEFAULT_SAMPLE_M))), 0.01)
	var requested_clamped := clampf(requested_span, BLOCK_M, field.extent())
	var cells := int(round(requested_clamped / sample_m))
	var span := float(cells) * sample_m
	var block_cells := int(round(BLOCK_M / sample_m))
	var stride_cells: int = maxi(1, int(round(BLOCK_STRIDE_M / sample_m)))
	var values: Array[float] = []
	values.resize(cells * cells)
	var sums: Array[float] = []
	sums.resize((cells + 1) * (cells + 1))
	var zero_depth := 0
	var near_bare := 0
	var wading := 0
	for y in range(cells):
		var row_sum := 0.0
		for x in range(cells):
			var at := Vector3(
				-span * 0.5 + (float(x) + 0.5) * sample_m,
				0.0,
				-span * 0.5 + (float(y) + 0.5) * sample_m
			)
			var depth := field.depth_at(at)
			values[y * cells + x] = depth
			row_sum += depth
			sums[(y + 1) * (cells + 1) + (x + 1)] = sums[y * (cells + 1) + (x + 1)] + row_sum
			if depth < MIDDLE_LOW_M:
				near_bare += 1
			if is_zero_approx(depth):
				zero_depth += 1
			if depth >= field.deep_depth_m:
				wading += 1

	var middle_blocks := 0
	var total_blocks := 0
	var min_mean := INF
	var max_mean := -INF
	var nearest_distance := INF
	var nearest_origin := Vector2.ZERO
	for y in range(0, cells - block_cells + 1, stride_cells):
		for x in range(0, cells - block_cells + 1, stride_cells):
			var mean := _mean_in(sums, cells + 1, x, y, block_cells)
			total_blocks += 1
			min_mean = minf(min_mean, mean)
			max_mean = maxf(max_mean, mean)
			if mean >= MIDDLE_LOW_M and mean <= MIDDLE_HIGH_M:
				middle_blocks += 1
			else:
				var distance := 0.0
				if mean < MIDDLE_LOW_M:
					distance = MIDDLE_LOW_M - mean
				else:
					distance = mean - MIDDLE_HIGH_M
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_origin = Vector2(
						-span * 0.5 + float(x) * sample_m,
						-span * 0.5 + float(y) * sample_m
					)

	print("snow depth scan: %.2f m lattice over %.2f m, %d x %d samples" % [
		sample_m, span, cells, cells,
	])
	print("  point depths: zero %.2f%%; < %.2f m %.2f%%; >= wade %.2f m %.2f%%" % [
		100.0 * float(zero_depth) / float(values.size()), MIDDLE_LOW_M,
		100.0 * float(near_bare) / float(values.size()), field.deep_depth_m,
		100.0 * float(wading) / float(values.size()),
	])
	print("  %.0f m squares, stride %.2f m: %d/%d middle [%.2f, %.2f] m; range %.3f..%.3f m" % [
		BLOCK_M, float(stride_cells) * sample_m, middle_blocks, total_blocks, MIDDLE_LOW_M, MIDDLE_HIGH_M, min_mean, max_mean,
	])
	print("  closest outside-band window begins at (%.1f, %.1f), distance %.5f m" % [
		nearest_origin.x, nearest_origin.y, nearest_distance,
	])
	field.free()
	quit()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _mean_in(sums: Array[float], width: int, x: int, y: int, side: int) -> float:
	var x2 := x + side
	var y2 := y + side
	var total := sums[y2 * width + x2] - sums[y * width + x2] - sums[y2 * width + x] + sums[y * width + x]
	return total / float(side * side)
