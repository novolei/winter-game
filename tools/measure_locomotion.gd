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
##   4. The joint distribution of what a man walking a random line actually gets.
##   5. SPEED AGAINST TIME IN MOTION -- the momentum table. Entry, recovery and
##      ceiling, stepped at 60 Hz through the controller's own advance_gait() and
##      advance_momentum(), so the auto-run's staging against the rhythm is
##      visible rather than argued.
##   6. Walking it: a crossing of the real field, and a stop-turn-restart.
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


## The ground worth quoting, used by sections 1b and 5 so the two tables describe
## the same cases and can be read against each other.
const CASES := [
	["bare, level", 0.0, 0.0, "bare flat"],
	["bare, 15% climb", 0.0, 0.15, "bare +15%"],
	["bare, 25% climb", 0.0, 0.25, "bare +25%"],
	["bare, 5% descent (the peak)", 0.0, -0.05, "bare -5%"],
	["half a drift, level", 0.5, 0.0, "half flat"],
	["full drift, level", 1.0, 0.0, "DEEP flat"],
	["full drift, 25% climb", 1.0, 0.25, "DEEP +25%"],
	["the worst the game can do", 1.0, 1.0, "the worst"],
]


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
	print("=== 1b. The raw model, the first step, and the found rhythm ===")
	print("terrain_severity compresses the raw product toward 1: the model's shape and")
	print("ordering are kept, its amplitude is not. See PlayerController.terrain_severity")
	print("for why -- Tobler describes hours of hiking and this player crosses the valley")
	print("in a minute. The raw column is what the realism claim is checked against.")
	print("")
	print("ENTRY is the first step onto this ground, cold. RHYTHM is the same ground once")
	print("he is fully in his stride against it -- see PlayerController.momentum_relief.")
	print("At full rhythm the model behaves as though terrain_severity were %.3f." % [
		player.terrain_severity * (1.0 - player.momentum_relief),
	])
	print("")
	print("  case                           raw     entry    rhythm   entry m/s  rhythm m/s")
	for entry in CASES:
		var label: String = entry[0]
		var wade: float = entry[1]
		var grade: float = entry[2]
		var raw: float = player.snow_factor(wade) * PlayerControllerScript.slope_factor(grade)
		var cold: float = player.terrain_factor(wade, grade, 0.0)
		var warm: float = player.terrain_factor(wade, grade, player.terrain_effort(wade, grade))
		print("  %-28s %7.3f  %7.3f  %7.3f    %7.2f     %7.2f" % [
			label, raw, cold, warm, player.walk_speed * cold, player.walk_speed * warm,
		])

	print("")
	print("=== 2. Ground speed, m/s (min/km in brackets) ===")
	print("walk_speed %.2f  run_speed %.2f  deep_snow_factor %.2f  slope floor %.2f" % [
		player.walk_speed, player.run_speed, player.deep_snow_factor,
		PlayerControllerScript.SLOPE_FLOOR,
	])
	print("terrain_severity %.2f -- every figure below is the COMPRESSED one." % player.terrain_severity)
	print("momentum_relief %.2f -- ENTRY is a cold first step, RHYTHM is fully in stride." % player.momentum_relief)
	print("Reference paces, m/s: stroll 1.1 | walk 1.3-1.4 | brisk 1.6 | jog 2.5-3.0")
	print("                      sustained run 3.5-4.5 | sprint 6-8")
	for run_blend in [0.0, 1.0]:
		for warm in [false, true]:
			print("")
			print("  --- %s, %s ---" % [
				"RUN (blend 1.0)" if run_blend > 0.5 else "WALK (blend 0.0)",
				"RHYTHM" if warm else "ENTRY",
			])
			var header := "  grade    "
			for wade in [0.0, 0.25, 0.5, 0.75, 1.0]:
				header += "  snow %4.2f m " % (wade * 0.42)
			print(header)
			for grade in [-0.35, -0.25, -0.15, -0.05, 0.0, 0.05, 0.15, 0.25, 0.35]:
				var row := "  %+6.2f   " % grade
				for wade in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var carried := player.terrain_effort(wade, grade) if warm else 0.0
					var speed: float = player.top_speed_at(wade, grade, run_blend, carried)
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
	var in_stride: Array[float] = []
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
				in_stride.append(
					player.top_speed_at(wade, grade, gait, player.terrain_effort(wade, grade))
				)
				total += 1
				if gait > 0.5:
					ran += 1
	walked.sort()
	in_stride.sort()
	print("  %d (point, heading) pairs. The run is available on %.0f%% of them." % [
		total, 100.0 * float(ran) / float(total),
	])
	print("  %.0f%% of the ground is at or past wading depth (%.2f m); that fraction is a" % [
		100.0 * float(wading) / float(points), field.deep_depth_m,
	])
	print("  property of the terrain, not of this model, and it is what decides how much")
	print("  of the world is a trudge.")
	print("")
	print("                    entry (a cold first step)   in his stride")
	for percentile in [1, 5, 10, 25, 50, 75, 95]:
		var index := mini(int(float(percentile) / 100.0 * float(walked.size())), walked.size() - 1)
		var speed: float = walked[index]
		var warm: float = in_stride[index]
		print("    p%-3d          %5.2f m/s  (%s /km)      %5.2f m/s  (%s /km)" % [
			percentile, speed, pace(speed), warm, pace(warm),
		])
	print("  slowest %.2f -> %.2f m/s, fastest %.2f -> %.2f m/s" % [
		walked[0], in_stride[0], walked[walked.size() - 1], in_stride[in_stride.size() - 1],
	])

	print("")
	print("=== 5. Speed against time in motion -- the rhythm ===")
	print("Stepped at 60 Hz through the controller's own advance_gait() and")
	print("advance_momentum(), from a standstill on each ground. So the auto-run's")
	print("promotion and the rhythm's recovery are both in these numbers, at the")
	print("timescales they actually run at, and the two can be read against each other.")
	print("")
	print("momentum_rise %.2f/s  momentum_fall %.2f/s  auto_run_delay %.2f s" % [
		player.momentum_rise, player.momentum_fall, player.auto_run_delay,
	])
	_time_table(player, false)
	_time_table(player, true)

	print("")
	print("=== 6. Walking it: a 70 m line across the real field ===")
	print("The controller's own advance_gait() and top_speed_at(), stepped at 60 Hz")
	print("against the real snow and the real relief -- so the auto-run promotes and")
	print("demotes exactly as it would in play. Sampled every 5 m of ground covered.")
	_traverse(player, field, "first crossing, unbroken snow")
	# ...and again over the trail the first crossing beat flat, which is the whole
	# point of SnowField carrying a packed layer.
	_pack_the_line(field)
	_traverse(player, field, "second crossing, over the packed trail")

	print("")
	print("=== 7. Stopping halfway, and setting off again ===")
	print("The moment the rhythm exists to sell: a man who stops in a drift, turns,")
	print("and sets off again has to break trail from cold. Same 60 Hz stepping, on")
	print("a full drift on the level, with a 3 s stand and an about-face in the middle.")
	_stop_and_start()

	field.free()
	player.free()
	print("")
	quit()


## The time table for section 5. `factors` prints the terrain multiplier; the
## other prints the ground speed it produces, which also carries the gait.
func _time_table(player: PlayerController, as_speed: bool) -> void:
	var marks := [0.0, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0]
	print("")
	print("  --- %s ---" % (
		"ground speed, m/s (the gait is in here too)" if as_speed
		else "terrain factor (1.00 = flat shallow snow, and the ceiling)"
	))
	var header := "   t s  "
	for entry in CASES:
		header += " %10s" % entry[3]
	print(header)
	for mark in marks:
		var row := "  %5.2f " % mark
		for entry in CASES:
			var wade: float = entry[1]
			var grade: float = entry[2]
			var walker: PlayerController = PlayerControllerScript.new()
			var heading := Vector3(0.0, 0.0, -1.0)
			var elapsed := 0.0
			var delta := 1.0 / 60.0
			while elapsed < mark - delta * 0.5:
				walker.advance_gait(delta, heading, wade)
				walker.advance_momentum(delta, heading, wade, grade)
				elapsed += delta
			if as_speed:
				row += " %10.2f" % walker.top_speed_at(
					wade, grade, walker.run_blend(), walker.momentum()
				)
			else:
				row += " %10.3f" % walker.terrain_factor(wade, grade, walker.momentum())
			walker.free()
		print(row)


## A full drift on the level, walked into from a standstill, stood in, turned in,
## and set off from again.
##
## Its own controller, not the one section 6 walked across the field: that one
## finishes the packed crossing at a full run, and reusing it would open this
## table at a gait it has no business being at.
func _stop_and_start() -> void:
	var player: PlayerController = PlayerControllerScript.new()
	var delta := 1.0 / 60.0
	var heading := Vector3(0.0, 0.0, -1.0)
	var wade := 1.0
	var grade := 0.0
	var script := [
		["setting off", heading, 6.0],
		["standing still", Vector3.ZERO, 3.0],
		["setting off again, the other way", -heading, 6.0],
	]
	print("")
	print("     t s   doing                              momentum   factor   m/s")
	var elapsed := 0.0
	for leg in script:
		var label: String = leg[0]
		var direction: Vector3 = leg[1]
		var span: float = leg[2]
		var spent := 0.0
		var next_report := 0.0
		while spent < span - delta * 0.5:
			player.advance_gait(delta, direction, wade)
			player.advance_momentum(delta, direction, wade, grade)
			spent += delta
			elapsed += delta
			if spent >= next_report:
				print("    %5.2f   %-32s   %6.3f   %6.3f  %5.2f" % [
					elapsed,
					label,
					player.momentum(),
					player.terrain_factor(wade, grade, player.momentum()),
					player.top_speed_at(wade, grade, player.run_blend(), player.momentum()),
				])
				next_report += 1.0
	player.free()


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
	# The gait and the rhythm are per-crossing: he sets off from a standstill each
	# time, so neither is carried over from the crossing before.
	player.advance_gait(delta, Vector3.ZERO, 0.0)
	for _settle in range(300):
		player.advance_momentum(delta, Vector3.ZERO, 0.0, 0.0)
	print("")
	print("  --- %s ---" % label)
	# `won back` rather than the momentum share: the share divides by the effort,
	# and on rolling bare ground the effort passes through zero every few metres
	# (Tobler's peak is a 5% DESCENT), so the share flickers between 0 and 1 while
	# nothing about the walk has changed. What the rhythm is worth here, in metres
	# per second, is the honest column and it goes to zero on its own.
	print("    at m    snow m   grade    gait  won back   speed m/s   what he is doing")
	while travelled < span and elapsed < 600.0:
		var wade: float = field.wade_factor(here)
		var grade: float = PlayerControllerScript.grade_along(
			field.surface_gradient_at(here), heading
		)
		var gait: float = player.advance_gait(delta, heading, wade)
		var momentum: float = player.advance_momentum(delta, heading, wade, grade)
		var speed: float = player.top_speed_at(wade, grade, gait, momentum)
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
			print("    %5.1f   %5.2f   %+6.3f   %4.2f    %+6.2f     %5.2f     %s" % [
				travelled,
				field.depth_at(here),
				grade,
				gait,
				speed - player.top_speed_at(wade, grade, gait, 0.0),
				speed,
				doing,
			])
			next_report += 5.0
		here += heading * speed * delta
		travelled += speed * delta
		elapsed += delta
	print("    %5.1f m in %.1f s -- %.2f m/s average (%s /km)" % [
		travelled, elapsed, travelled / maxf(elapsed, 0.001), pace(travelled / maxf(elapsed, 0.001)),
	])
