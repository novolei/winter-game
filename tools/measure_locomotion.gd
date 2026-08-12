extends SceneTree

## Measures what the locomotion model actually does on the shipped ground.
##
## Run it:
##
##   "D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless \
##       --path "D:/Godot resource/winter-time" \
##       --script res://tools/measure_locomotion.gd
##
## Three tables, in the order a reviewer needs them:
##
##   1. Tobler's hiking function against PlayerController.slope_factor(), so the
##      claim "this is Tobler" can be checked rather than believed.
##   2. Ground speed over the grid of (grade, snow depth) the game actually
##      serves, in m/s and in min/km, against the real-world pace table.
##   3. The distribution of grade the shipped SnowField produces -- which is what
##      decides whether the slope term is a texture you feel or a wall you hit.
##
## It prints and exits. Nothing here is a test; tests/unit/test_locomotion.gd is.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const SnowFieldScript := preload("res://src/systems/snow_field.gd")

## Tobler's hiking function, in km/h, from the paper rather than from the
## implementation under measurement. W = 6 exp(-3.5 |S + 0.05|).
static func tobler_kmh(grade: float) -> float:
	return 6.0 * exp(-3.5 * absf(grade + 0.05))


static func pace(speed: float) -> String:
	if speed <= 0.001:
		return "  --  "
	var seconds_per_km := 1000.0 / speed
	return "%d:%02d" % [int(seconds_per_km) / 60, int(seconds_per_km) % 60]


func _initialize() -> void:
	var player: PlayerController = PlayerControllerScript.new()

	print("")
	print("=== 1. Tobler's hiking function vs slope_factor() ===")
	print("W = 6 exp(-3.5 |S + 0.05|) km/h. slope_factor is that curve divided by")
	print("its own value at S = 0, so flat ground is exactly 1.")
	print("")
	print("  grade    angle    Tobler km/h   Tobler m/s   Tobler/flat   slope_factor")
	var flat := tobler_kmh(0.0)
	for grade in [-0.50, -0.35, -0.25, -0.15, -0.10, -0.05, 0.0, 0.05, 0.10, 0.15, 0.25, 0.35, 0.50]:
		var kmh := tobler_kmh(grade)
		print("  %+6.2f  %+6.1f deg   %8.3f     %7.3f      %7.4f       %7.4f" % [
			grade,
			rad_to_deg(atan(grade)),
			kmh,
			kmh / 3.6,
			kmh / flat,
			PlayerControllerScript.slope_factor(grade),
		])

	print("")
	print("=== 1b. The raw model against what ships ===")
	print("terrain_severity compresses the raw product toward 1: the model's shape and")
	print("ordering are kept, its amplitude is not. See PlayerController.terrain_severity")
	print("for why -- Tobler describes hours of hiking and this player crosses the valley")
	print("in a minute. The raw column is what the realism claim is checked against.")
	print("")
	print("  case                          raw factor   shipped   raw m/s   shipped m/s")
	var cases := [
		["bare, level", 0.0, 0.0],
		["bare, 15% climb", 0.0, 0.15],
		["bare, 25% climb", 0.0, 0.25],
		["bare, 5% descent (the peak)", 0.0, -0.05],
		["half a drift, level", 0.5, 0.0],
		["full drift, level", 1.0, 0.0],
		["full drift, 25% climb", 1.0, 0.25],
		["the worst the game can do", 1.0, 1.0],
	]
	for entry in cases:
		var label: String = entry[0]
		var wade: float = entry[1]
		var grade: float = entry[2]
		var raw: float = player.snow_factor(wade) * PlayerControllerScript.slope_factor(grade)
		var shipped: float = player.terrain_factor(wade, grade)
		print("  %-28s  %8.3f  %8.3f  %8.2f      %8.2f" % [
			label, raw, shipped, player.walk_speed * raw, player.walk_speed * shipped,
		])

	print("")
	print("=== 2. Ground speed, m/s (min/km in brackets) ===")
	print("walk_speed %.2f  run_speed %.2f  deep_snow_factor %.2f  slope floor %.2f" % [
		player.walk_speed, player.run_speed, player.deep_snow_factor,
		PlayerControllerScript.SLOPE_FLOOR,
	])
	print("terrain_severity %.2f -- every figure below is the COMPRESSED one." % player.terrain_severity)
	print("Reference paces, m/s: stroll 1.1 | walk 1.3-1.4 | brisk 1.6 | jog 2.5-3.0")
	print("                      sustained run 3.5-4.5 | sprint 6-8")
	for run_blend in [0.0, 1.0]:
		print("")
		print("  --- %s ---" % ("RUN (blend 1.0)" if run_blend > 0.5 else "WALK (blend 0.0)"))
		var header := "  grade    "
		for wade in [0.0, 0.25, 0.5, 0.75, 1.0]:
			header += "  snow %4.2f m " % (wade * 0.42)
		print(header)
		for grade in [-0.35, -0.25, -0.15, -0.05, 0.0, 0.05, 0.15, 0.25, 0.35]:
			var row := "  %+6.2f   " % grade
			for wade in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var speed: float = player.top_speed_at(wade, grade, run_blend)
				row += "  %5.2f (%s)" % [speed, pace(speed)]
			print(row)

	print("")
	print("NOTE: the RUN rows past 0.25 m of snow are the pure function only.")
	print("run_snow_limit gates the promotion above a wade factor of %.2f, so in play" % player.run_snow_limit)
	print("advance_gait() has already eased him back to the WALK row by then.")

	print("")
	print("=== 3. What grades the shipped SnowField actually serves ===")
	var field: SnowField = SnowFieldScript.new()
	field.build_at(Vector3.ZERO)
	var samples: Array[float] = []
	var worst := 0.0
	# An 80 m square about the origin, at 0.5 m, which is about two paces.
	for iz in range(-80, 81):
		for ix in range(-80, 81):
			var here := Vector3(float(ix) * 0.5, 0.0, float(iz) * 0.5)
			var steepest: float = field.surface_gradient_at(here).length()
			samples.append(steepest)
			worst = maxf(worst, steepest)
	samples.sort()
	print("  %d samples over an 80 m square, 0.5 m apart." % samples.size())
	print("  steepest grade in any direction (the gradient's own length):")
	for percentile in [50, 75, 90, 95, 99, 100]:
		var index := mini(int(float(percentile) / 100.0 * float(samples.size())), samples.size() - 1)
		var grade: float = samples[index]
		print("    p%-3d  grade %.3f  (%4.1f deg)  slope_factor %.3f" % [
			percentile, grade, rad_to_deg(atan(grade)), PlayerControllerScript.slope_factor(grade),
		])
	print("  worst %.3f (%.1f deg), slope_factor %.3f" % [
		worst, rad_to_deg(atan(worst)), PlayerControllerScript.slope_factor(worst),
	])

	print("")
	print("=== 4. What a man walking a random line across it actually gets ===")
	print("The joint distribution -- snow and slope are correlated, since the wind")
	print("fills the hollows and the hollows are what the flanks lead down into, so")
	print("neither margin predicts this. Eight headings per sample point.")
	var walked: Array[float] = []
	var ran := 0
	var total := 0
	var wading := 0
	var points := 0
	for iz in range(-60, 61):
		for ix in range(-60, 61):
			var here := Vector3(float(ix) * 0.5, 0.0, float(iz) * 0.5)
			var wade: float = field.wade_factor(here)
			points += 1
			if wade >= 0.999:
				wading += 1
			var gradient: Vector2 = field.surface_gradient_at(here)
			for turn in range(8):
				var heading := Vector3(1.0, 0.0, 0.0).rotated(
					Vector3.UP, TAU * float(turn) / 8.0
				)
				var grade: float = PlayerControllerScript.grade_along(gradient, heading)
				var gait := 1.0 if player.can_run(wade) else 0.0
				walked.append(player.top_speed_at(wade, grade, gait))
				total += 1
				if gait > 0.5:
					ran += 1
	walked.sort()
	print("  %d (point, heading) pairs. The run is available on %.0f%% of them." % [
		total, 100.0 * float(ran) / float(total),
	])
	print("  %.0f%% of the ground is at or past wading depth (%.2f m); that fraction is a" % [
		100.0 * float(wading) / float(points), field.deep_depth_m,
	])
	print("  property of the terrain, not of this model, and it is what decides how much")
	print("  of the world is a trudge.")
	for percentile in [1, 5, 10, 25, 50, 75, 95]:
		var index := mini(int(float(percentile) / 100.0 * float(walked.size())), walked.size() - 1)
		var speed: float = walked[index]
		print("    p%-3d  %5.2f m/s  (%s /km)" % [percentile, speed, pace(speed)])
	print("  slowest %.2f m/s, fastest %.2f m/s" % [walked[0], walked[walked.size() - 1]])

	print("")
	print("=== 5. Walking it: a 70 m line across the real field ===")
	print("The controller's own advance_gait() and top_speed_at(), stepped at 60 Hz")
	print("against the real snow and the real relief -- so the auto-run promotes and")
	print("demotes exactly as it would in play. Sampled every 5 m of ground covered.")
	_traverse(player, field, "first crossing, unbroken snow")
	# ...and again over the trail the first crossing beat flat, which is the whole
	# point of SnowField carrying a packed layer.
	_pack_the_line(field)
	_traverse(player, field, "second crossing, over the packed trail")

	field.free()
	player.free()
	print("")
	quit()


const TRAVERSE_FROM := Vector3(-35.0, 0.0, -12.0)
const TRAVERSE_TO := Vector3(35.0, 0.0, 12.0)


func _pack_the_line(field: SnowField) -> void:
	var steps := 400
	for index in range(steps + 1):
		var here := TRAVERSE_FROM.lerp(TRAVERSE_TO, float(index) / float(steps))
		for _pass in range(24):
			field.pack_at(here, 0.34, 0.09)


func _traverse(player: PlayerController, field: SnowField, label: String) -> void:
	var heading := (TRAVERSE_TO - TRAVERSE_FROM).normalized()
	var span := TRAVERSE_FROM.distance_to(TRAVERSE_TO)
	var here := TRAVERSE_FROM
	var travelled := 0.0
	var elapsed := 0.0
	var next_report := 0.0
	var delta := 1.0 / 60.0
	# The gait is per-crossing: he sets off from a standstill each time.
	player.advance_gait(delta, Vector3.ZERO, 0.0)
	print("")
	print("  --- %s ---" % label)
	print("    at m    snow m   grade    gait   speed m/s   what he is doing")
	while travelled < span and elapsed < 600.0:
		var wade: float = field.wade_factor(here)
		var grade: float = PlayerControllerScript.grade_along(
			field.surface_gradient_at(here), heading
		)
		var gait: float = player.advance_gait(delta, heading, wade)
		var speed: float = player.top_speed_at(wade, grade, gait)
		if travelled >= next_report:
			var doing := "walking"
			if gait > 0.6:
				doing = "running"
			elif gait > 0.05:
				doing = "changing gait"
			if wade >= 0.999:
				doing += ", wading a drift"
			elif not player.can_run(wade):
				doing += ", snow too deep to run"
			if grade > 0.12:
				doing += ", climbing"
			elif grade < -0.12:
				doing += ", descending"
			print("    %5.1f   %5.2f   %+6.3f   %4.2f     %5.2f     %s" % [
				travelled, field.depth_at(here), grade, gait, speed, doing,
			])
			next_report += 5.0
		here += heading * speed * delta
		travelled += speed * delta
		elapsed += delta
	print("    %5.1f m in %.1f s -- %.2f m/s average (%s /km)" % [
		travelled, elapsed, travelled / maxf(elapsed, 0.001), pace(travelled / maxf(elapsed, 0.001)),
	])
