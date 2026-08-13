extends SceneTree

## Generator for res://data/stats/*.tres -- the five interlocking survival stats
## of GDD section 5, and every interlock between them.
##
## Run:
##   godot --headless --path <project> --script res://tools/generate_stats.gd
##
## THIS FILE IS THE TUNING SURFACE. The .tres files are generated, never hand
## authored (briefing constraint 7), so this table is where a number gets
## changed and this comment block is where the reasoning lives. Nothing in
## src/ knows any of these values, and adding a stat or an interlock here needs
## no code anywhere.
##
## ---------------------------------------------------------------------------
## WHERE THE NUMBERS COME FROM
## ---------------------------------------------------------------------------
## GDD section 4 gives the only hard clock in the design: every day is daylight
## plus night, and every one of the seven adds up to the same 900 SECONDS --
## 600+300, 480+420, 420+480, 300+600, 240+660. The run is 6300 s, which is the
## GDD's "about 105 minutes". Every lifetime below is stated as a multiple of
## that day, because that is the only unit a designer can feel.
##
##   core_temperature  1200 s = 1 1/3 days
##       Day 1's daylight is 600 s and its night 300 s. GDD section 3 doubles
##       the loss after dark, so a day out plus a night out is 600 + 2*300 =
##       1200 s of drain: EXACTLY one bar. Stay out through one full cycle and
##       you die at dawn. That is "NIGHTFALL = GO HOME" expressed as a number
##       rather than as a warning. It also means a full day's excursion costs a
##       little over half the bar, so the fire is a daily necessity from day 1.
##
##   hunger            720 s = 0.8 day
##       Deliberately SHORTER than a day, so a day's work always ends hungrier
##       than it began and a skipped meal is felt before the next dawn. It is
##       also what makes total neglect fatal inside one day: hunger crosses 0.30
##       at 504 s and 0.05 at 684 s, and the compounding heat loss finishes the
##       job at 826 s.
##
##   thirst            600 s = 2/3 day
##       The most frequent chore: twice a day, morning and evening. Snow must be
##       melted to drink and melting costs fuel, so this is the interlock that
##       pulls the fuel economy into every single day.
##
##   fatigue           1800 s = 2 days
##       The slow one. Two days awake and he cannot run -- which lands exactly
##       when GDD section 4 turns the nights into work, on days 6 and 7. Nothing
##       in the shipped model puts fatigue back; sleep and rest do that, and
##       they push onto fatigue:recovery.
##
##   frostbite_hands   600 s of unbroken cold
##   frostbite_feet    900 s of unbroken cold
##       No clock of their own: GDD section 5 calls frostbite 暴露时间的函数, a
##       function of exposure, so it moves only while core temperature is under
##       0.35 and it never comes back on its own. Note the arithmetic that
##       follows: at 0.35 of a bar you have at most ~420 s of life left, so ONE
##       cold spell cannot cost a whole limb. Frostbite can only be accumulated
##       across several near-misses, which is what 局部累积 means in play.
##       Hands go faster than feet: gloves come off to work, boots stay on.
##
## ---------------------------------------------------------------------------
## POLARITY
## ---------------------------------------------------------------------------
## Every stat is a RESERVE: 1.0 healthy, 0.0 the worst it gets, always falling.
## frostbite_hands = 1.0 means the hands are FINE. GDD section 5's own table is
## written this way ("疲劳 ... 归零后果: 无法奔跑"), and one direction for all of
## them is what lets a readout say "low is bad" without knowing which stat it is
## holding.
##
## ---------------------------------------------------------------------------
## COMPOUNDING
## ---------------------------------------------------------------------------
## ModifierStack evaluates (base + sum ADD) * product MULTIPLY, so two tiers on
## the same stat MULTIPLY TOGETHER. hunger below 0.30 is 1.5x and below 0.05 is
## another 2.0x, which is 3.0x when starving -- that is intended, and it is why
## the second tier's number looks small next to the effect it has.

const DAY := 900.0

const ADD := 0  # Modifier.Operation.ADD
const MUL := 1  # Modifier.Operation.MULTIPLY
const BELOW := 0  # ThresholdEffect.Comparison.BELOW

## Interlocks are filed under the stat they WATCH, so "what does hunger do to
## me" is one file rather than a search. Each row is
## [threshold, target, operation, value].
##
## A target is "<stat>" (its drain), "<stat>:recovery", or a behaviour channel
## belonging to whoever owns that behaviour. The behaviour channels used here:
##
##   locomotion:run_speed       0 means running is off entirely
##   locomotion:run_snow_limit  scales how deep the snow may be before the run
##                              goes; 0.5 means he loses it in half the depth a
##                              healthy man manages
##   locomotion:rhythm     how much of the terrain's penalty a man who keeps
##                         going wins back; 0 means the first step's price is the
##                         price for ever
##   locomotion:footing    how much of an ordinary walk his feet can still carry;
##                         0 puts him fully into the guarded walk
##   stand:composure       how much of his ordinary bearing his hands let him
##                         keep; 0 draws them right in
##   stand:carriage        how much of his upright carriage he still holds; 0
##                         bends him fully over
##   ignition:speed        how fast a fire can be lit
##   aim:steadiness        weapon steadiness
##   vision:focus          GDD 5's 画面轻微失焦
##   breath:rate           GDD 9's 呼吸变浅变快
##
## ---------------------------------------------------------------------------
## THE BODY GATES; IT DOES NOT SCALE
## ---------------------------------------------------------------------------
## `locomotion:speed` and `locomotion:snow_cost` used to live here as plain
## multipliers -- 0.85 off the top speed when tired, 1.35 on the snow penalty --
## and BOTH ARE GONE. The owner's ruling is that the only things which scale
## movement speed are snow depth and terrain slope; the GDD requires fatigue and
## frostbite to affect locomotion. Both stand, because they are different kinds
## of thing:
##
##   the TERRAIN says how fast the ground lets you move.  It SCALES the number.
##   the BODY says how much of your capability is left.   It GATES, and the
##                                                        number is untouched.
##
## The pattern was already here for fatigue at zero -- 无法奔跑 takes the RUN
## away rather than scaling anything -- and every locomotion effect is now
## written in that vocabulary.
##
## It is also better design, and that is the argument that decides it rather than
## document-reconciliation. "You can no longer run" is a legible event the player
## understands and can act on. A silent 15% speed reduction is something a player
## feels as the game being unresponsive and cannot name -- which is exactly the
## complaint that started the locomotion rework.
const STATS := [
	{
		"id": &"core_temperature",
		"display_name": "Core temperature",
		"lifetime": 1200.0,
		"lethal": true,
		"effects": [
			# The body starts telling on itself long before it is in danger:
			# GDD section 9 has no HUD, so breath is the first readout.
			[0.50, &"breath:rate", MUL, 1.25],
			# 冻伤是暴露时间的函数. Below a third of a bar the extremities start
			# to go: 1/600 per second on the hands, 1/900 on the booted feet.
			[0.35, &"frostbite_hands", ADD, 1.0 / 600.0],
			[0.35, &"frostbite_feet", ADD, 1.0 / 900.0],
			[0.20, &"breath:rate", MUL, 1.5],
			# Nearly dead costs double. This is the price of the near-miss that
			# the player survives and remembers.
			[0.15, &"frostbite_hands", MUL, 2.0],
			[0.15, &"frostbite_feet", MUL, 2.0],
		],
	},
	{
		"id": &"hunger",
		"display_name": "Hunger",
		"lifetime": 720.0,
		"lethal": false,
		"effects": [
			# GDD 5: 饥饿低 -> 身体产热下降 -> 体温下降加速.
			[0.30, &"core_temperature", MUL, 1.5],
			# 归零后果: 体温加速流失. Compounds with the row above to 3.0x.
			[0.05, &"core_temperature", MUL, 2.0],
			# ...and the half of hunger a player can SEE. Until this row the
			# stat's whole expression was a number on another bar: a starving man
			# looked exactly like a fed one, and with no HUD there was nothing at
			# all to read. He now loses his RHYTHM -- he pays the first step's
			# price into every drift and every climb and never wins it back, so he
			# sets off level with a fed man and is left behind over the next few
			# strides.
			#
			# THIS IS A GATE AND NOT A SCALER, and it is worth being exact about
			# why, because the row looks like the `locomotion:speed` multiply that
			# was deleted from this file. What it scales is how much RELIEF
			# persistence buys, and the relief is bounded by the terrain's own
			# penalty -- on ground that costs nothing there is nothing to take
			# away. A starving man on a beaten trail walks at a fed man's pace,
			# and in a drift he walks at the honest unrelieved terrain speed,
			# never below it. See PlayerController.rhythm_ceiling().
			[0.30, &"locomotion:rhythm", MUL, 0.5],
			[0.05, &"locomotion:rhythm", MUL, 0.0],
			# ...and the half of hunger a player can see WITHOUT a second man to
			# compare him with, which is the half the rhythm could never be.
			#
			# The rhythm is a PACE, and a pace is relative: two agents measured it
			# on the game camera and both concluded that a starving man is legible
			# only beside a fed one, which this game does not contain. A POSTURE is
			# absolute -- it is read in one frame, off one figure -- and this one
			# changes his HEIGHT, so there is nothing to compare it against.
			#
			# The stand is a retargeted authored take, not a pose anybody invented
			# here; see WandererAnimations.IDLE_HUNCHED for where it came from and
			# PlayerController.HUNGER_HUNCH_FLOOR for the silhouette ladder that
			# decided the two tiers below land where they do.
			[0.30, &"stand:carriage", MUL, 0.5],
			[0.05, &"stand:carriage", MUL, 0.0],
		],
	},
	{
		"id": &"thirst",
		"display_name": "Thirst",
		"lifetime": 600.0,
		"lethal": false,
		"effects": [
			# GDD 5: 口渴低 -> 疲劳恢复变慢. On the RECOVERY channel, never the
			# drain: dehydration does not tire you, it stops rest working.
			[0.30, &"fatigue:recovery", MUL, 0.5],
			# 画面轻微失焦.
			[0.30, &"vision:focus", MUL, 0.85],
			# 归零后果: 疲劳无法恢复.
			[0.05, &"fatigue:recovery", MUL, 0.0],
		],
	},
	{
		"id": &"fatigue",
		"display_name": "Fatigue",
		"lifetime": 1800.0,
		"lethal": false,
		"effects": [
			# GDD 5: 疲劳高 -> 移速下降、雪深惩罚加剧. ONE ROW ANSWERS BOTH, which
			# is the happy part of the gate rewrite rather than a shortcut.
			# "You lose the run in half the snow a fresh man manages" IS the
			# 雪深惩罚加剧 -- the snow penalty has genuinely worsened for him --
			# and it is also the 移速下降, because the gait he is left with is
			# the walk. Two graded scalers collapse into one legible capability.
			[0.30, &"locomotion:run_snow_limit", MUL, 0.5],
			# Compounds with the row above to 0.25, so a badly tired man keeps
			# the run only on ground that is nearly bare.
			[0.10, &"locomotion:run_snow_limit", MUL, 0.5],
			# 归零后果: 无法奔跑. A multiply by zero rather than an OVERRIDE:
			# ModifierStack's override slot cannot tell "override with NAN" from
			# "no override" (DEFERRED W2-2), and nothing here needs it.
			[0.02, &"locomotion:run_speed", MUL, 0.0],
		],
	},
	{
		"id": &"frostbite_hands",
		"display_name": "Frostbite (hands)",
		"lifetime": INF,
		"lethal": false,
		"effects": [
			# GDD 5: 冻伤...会让其它四条全面恶化. The hands take heat and food:
			# ruined circulation loses warmth, and a shivering body burns more.
			[0.50, &"core_temperature", MUL, 1.10],
			[0.50, &"hunger", MUL, 1.15],
			# 手部冻伤 -> 点火变慢、射击精度下降. The nastiest loop in the game:
			# cold hands make the fire slower to light, which makes you colder.
			[0.50, &"ignition:speed", MUL, 0.60],
			[0.50, &"aim:steadiness", MUL, 0.70],
			[0.20, &"ignition:speed", MUL, 0.50],
			[0.20, &"aim:steadiness", MUL, 0.60],
			# ...and the part a player can SEE. Every row above this one is a
			# consequence with no cause on screen: a man whose fire takes twice as
			# long to light is being told about his hands by a failure, which
			# reads as the game being unfair rather than as his body being hurt.
			# He now draws his hands in and keeps them there.
			#
			# Reuses the cold idle's own arms rather than a new take -- a man
			# tucking ruined hands away and a man hugging himself against the cold
			# put their hands in the same place. See
			# PlayerController.stand_chill().
			[0.50, &"stand:composure", MUL, 0.5],
			[0.20, &"stand:composure", MUL, 0.0],
		],
	},
	{
		"id": &"frostbite_feet",
		"display_name": "Frostbite (feet)",
		"lifetime": INF,
		"lethal": false,
		"effects": [
			# The other two of the four: every step on ruined feet costs more,
			# and that heavier work is paid for in breath, so in water.
			[0.50, &"fatigue", MUL, 1.25],
			[0.50, &"thirst", MUL, 1.10],
			# 足部冻伤 -> 移速永久下降，直到在火边治疗. Permanent because nothing
			# restores a limb: only SurvivalSystem.restore() does, and that is
			# what treating it at a fire will call.
			#
			# Two stages, the same shape as fatigue: sore feet cannot carry a run
			# through a drift, ruined feet cannot carry one at all. Losing the run
			# IS the 移速下降 the GDD asks for -- stated as something the player
			# can notice happening, and can walk to a fire to undo.
			[0.50, &"locomotion:run_snow_limit", MUL, 0.5],
			[0.20, &"locomotion:run_speed", MUL, 0.0],
			# ...and the reading the two rows above never had. Losing the run is
			# a capability the player is meant to notice, and until now the only
			# way he could notice it was by pressing a direction and finding that
			# the auto-run had quietly stopped firing. He now WALKS differently:
			# lower, shorter-stepped, both feet guarded. The take is the library's
			# own, and which take and why is the long block at
			# WandererAnimations.WALK_GUARDED.
			#
			# Bilateral on purpose. 足部冻伤 is both feet, so a limp -- one leg
			# favouring the other -- would be the wrong picture even if the
			# library's limp were usable, which measurement says it is not.
			[0.50, &"locomotion:footing", MUL, 0.5],
			[0.20, &"locomotion:footing", MUL, 0.0],
		],
	},
]

func _initialize() -> void:
	var StatDefinitionScript := load("res://src/definitions/stat_definition.gd")
	var ThresholdEffectScript := load("res://src/definitions/threshold_effect.gd")
	var directory := "res://data/stats"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))

	var failed := false
	for row in STATS:
		var stat: StatDefinition = StatDefinitionScript.new()
		stat.id = row["id"]
		stat.display_name = row["display_name"]
		stat.initial_value = 1.0
		stat.min_value = 0.0
		stat.max_value = 1.0
		var lifetime: float = row["lifetime"]
		stat.base_decay_per_second = 0.0 if is_inf(lifetime) else 1.0 / lifetime
		stat.lethal_at_min = row["lethal"]

		# Annotated, not `var effects = []`. An untyped local would make the
		# compiler emit an untyped Array for the assignment below, the typed
		# setter would reject it, and the VM would ABORT the rest of this
		# function -- silently, after having written some of the files
		# (briefing trap 4).
		var effects: Array[ThresholdEffect] = []
		for effect_row in row["effects"]:
			var effect: ThresholdEffect = ThresholdEffectScript.new()
			effect.watch_stat = row["id"]
			effect.comparison = BELOW
			effect.threshold = effect_row[0]
			effect.target_stat = effect_row[1]
			effect.operation = effect_row[2]
			effect.value = effect_row[3]
			effects.append(effect)
		stat.threshold_effects = effects

		var path := "%s/%s.tres" % [directory, row["id"]]
		var error := ResourceSaver.save(stat, path)
		if error != OK:
			print("generate_stats: FAILED %s (%d)" % [path, error])
			failed = true
			continue
		print("generate_stats: wrote %s" % path)
	# quit() only REQUESTS exit at the end of the current iteration; it does not
	# return from this function. An early quit(1) inside the loop would fall
	# through and be overwritten by a later quit(0), reporting success over a
	# failed save. Accumulate, and quit exactly once, last.
	quit(1 if failed else 0)
