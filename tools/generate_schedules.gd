extends SceneTree

## One-off generator for res://data/schedule/day_01..07.tres.
## Values come from GDD section 4.
## Run: godot --headless --path <project> --script res://tools/generate_schedules.gd

func _initialize() -> void:
	var DayScheduleScript := load("res://src/definitions/day_schedule.gd")

	# THE NIGHT PRESET COLUMN, and how it was read off the GDD.
	#
	# Section 4's 主导光照 column names one look per day and writes two of the
	# seven as a transition: day 2 is `PALE DAY → NIGHTFALL` and day 6
	# `NIGHTFALL → WHITEOUT`. A day has two phases, so the arrow is the phase
	# change -- daylight preset on the left, night preset on the right -- and the
	# five rows without an arrow name whichever phase that day is remembered for.
	#
	# Reading the whole column that way gives the pairs below:
	#
	#   1  PALE DAY            daylight is safe; the first dark is only NIGHTFALL,
	#                          which is the dusk the tutorial teaches you to fear.
	#   2  PALE DAY→NIGHTFALL  written as a transition; taken literally.
	#   3  NIGHTFALL           夜开始变长. The daylight is already dusk-toned and
	#                          the night goes past it into DEEP NIGHT.
	#   4  DEEP NIGHT          熊首次出现. The one day whose DAYLIGHT is named for
	#                          the dark, and it is named that in the GDD.
	#   5  SUNRISE             二十分钟的暖 -- a warm dawn you spend, and a night
	#                          that goes back to the dark you now know.
	#   6  NIGHTFALL→WHITEOUT  written as a transition. The storm arrives with the
	#                          dark, which is the attack/defence inversion.
	#   7  WHITEOUT            纯死守. A blizzard does not stop at sundown.
	#
	# THE DAY-1 EVENT COLUMN, and why it is 短暂放晴 rather than nothing or a storm.
	#
	# Day 1 shipped with an EMPTY pool, which is not a typo -- section 4 writes
	# day 1 as `PALE DAY 无事挂心`, and its 设计意图 is 教学：走路、雪深、火炉.
	# Day 1 is authored calm and stays authored calm.
	#
	# But an empty pool has a consequence nobody chose. `plan_phase()` builds its
	# draw from this array, so `wanted = min(events_per_phase, 0) = 0` and day 1
	# queues no weather in either phase; the daylight preset never changes inside
	# a phase; and the first lighting change of a NEW GAME is therefore the dusk
	# crossfade at t = 600 s. Measured on five seeds at HEAD: 601.0 s every time,
	# with the ten samples before it inside 0.57 % of each other. The owner played
	# it, saw a frame that never moved for ten minutes, and concluded the lighting
	# was not wired. It is -- 67 correct state changes across a seven-day run and a
	# 4.641x luminance spread between the extremes -- but nothing in day 1's data
	# can show him that.
	#
	# So day 1 gets exactly one event, and it is the only one of the six whose GDD
	# section 7 line is entirely benign: 短暂放晴, 能见度↑ 体温回升 —— 移动窗口.
	# It costs the player nothing, it threatens nothing, and 无事挂心 survives it.
	# What it does buy is the game's own iron law -- 天空就是天气预报 -- taught on
	# the day built for teaching. A tutorial day on which the sky never once does
	# anything teaches the opposite lesson.
	#
	# NOT 雪雾, which is what the lighting audit proposed. It reaches the light
	# sooner (its TELL carries `nightfall`, so the crossfade starts at the warning
	# rather than at the arrival) but it is 能见度↓ in the middle of the teaching
	# day, and 第一次算错归途的恐慌 is day 2's design intent, which is where
	# `snow_fog` already sits.
	#
	# AND IT IS THE FORCED COLUMN, NOT THE ALLOWED COLUMN. That is not a stylistic
	# choice -- `allowed_weather_events` is drawn in BOTH phases, and putting
	# 短暂放晴 in it was measured turning night 1 into daylight: the tell carries
	# `pale_day` and the arrival `sunrise`, so on two seeds the night ran
	# NIGHTFALL -> PALE DAY at t=676 -> SUNRISE at t=706, exposure 0.780 climbing
	# to 1.100 in the middle of the dark. `plan_phase()` adds the FORCED beat only
	# when `not night`, so the forced column is the seam that gives the daylight
	# an event and leaves the night alone. It also makes the beat guaranteed
	# rather than drawn, which is what section 7's 编排层 is for: 强制节拍，保证
	# 戏剧弧线不被随机性破坏. A teaching beat that only happens on some runs is
	# not a teaching beat.
	#
	# day, daylight, night, day preset, night preset, allowed events, forced event, beacon
	var rows := [
		[1, 600.0, 300.0, &"pale_day",  &"nightfall",  [],                              &"clear_break", &"farmhouse_chimney"],
		[2, 600.0, 300.0, &"pale_day",  &"nightfall",  [&"snow_fog"],                                 &"",         &"gas_station"],
		[3, 480.0, 420.0, &"nightfall", &"deep_night", [&"snow_fog", &"clear_break"],                 &"",         &"church_tower"],
		[4, 480.0, 420.0, &"deep_night",&"deep_night", [&"wind_shift", &"snow_fog"],                  &"",         &"logging_camp"],
		[5, 420.0, 480.0, &"sunrise",   &"deep_night", [&"clear_break", &"cold_snap"],                &"",         &"transmission_tower"],
		[6, 300.0, 600.0, &"nightfall", &"whiteout",   [&"cold_snap", &"freezing_rain", &"wind_shift"], &"",       &""],
		[7, 240.0, 660.0, &"whiteout",  &"whiteout",   [&"wind_shift"],                               &"blizzard", &""],
	]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/schedule"))
	var failed := false
	for row in rows:
		var schedule = DayScheduleScript.new()
		schedule.day_number = row[0]
		schedule.daylight_seconds = row[1]
		schedule.night_seconds = row[2]
		schedule.primary_lighting_preset = row[3]
		schedule.night_lighting_preset = row[4]
		var events: Array[StringName] = []
		for e in row[5]:
			events.append(e)
		schedule.allowed_weather_events = events
		schedule.forced_weather_event = row[6]
		schedule.beacon_unlocked = row[7]

		var path := "res://data/schedule/day_%02d.tres" % row[0]
		var error := ResourceSaver.save(schedule, path)
		if error != OK:
			print("generate_schedules: FAILED %s (%d)" % [path, error])
			failed = true
			continue
		print("generate_schedules: wrote %s" % path)
	# SceneTree.quit() only *requests* exit at the end of the current iteration
	# -- it does not return from the function. An early quit(1) inside the loop
	# therefore fell through to the "wrote" print and was later overwritten by a
	# trailing quit(0), so a failed save still reported success. Accumulate the
	# failure and quit exactly once, as the last statement, the same shape
	# tools/generate_palette.gd uses. This cannot regrow the fall-through bug.
	quit(1 if failed else 0)
