extends Node

## How much of a run has something on screen, and how often two prompts are up at
## once. UI design document sections 5.2 and 5.10, rule 4.
##
##   Godot_console.exe --headless --path <project> \
##       res://tools/measure_prompt_traffic.tscn -- [--player tends|none]
##       [--seconds 6300] [--step 0.0166667] [--floor 0.02]
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## Rule 4 is 没有东西是常驻的, and the owner deleted a corner HUD to get it back.
## Doubling a prompt's dwell moves it toward the thing rule 4 forbids by exactly
## the factor it is doubled by, and **a thing that never quite leaves is a HUD**
## whatever its author calls it. That is not a judgement anybody should make by
## watching; it is a duty cycle, and a duty cycle is a number.
##
## It also answers the question the two prompts cannot answer themselves: they do
## not know about each other. Section 5.2's note is born on the body's clock and
## section 5.10's prompt on the world's, and nothing anywhere reconciles them.
##
## ---------------------------------------------------------------------------
## IT RUNS THE REAL SYSTEMS, AND IT MEASURES THE TREE RATHER THAN A MODEL OF IT
## ---------------------------------------------------------------------------
## The real `SurvivalSystem` on the real `data/stats/*.tres`, the real
## `WorldClock` on the real `data/schedule/*.tres`, the real `ThresholdSurfacing`
## and `TimePrompt` on the real `UILayer`. Occupancy is read off the LAYER'S OWN
## CHILDREN every step -- what is actually parented and breathing -- rather than
## from intervals worked out from the constants, because the constants are what
## is under review.
##
## Everything here has a public `advance()`, so a seven day run is a loop and not
## seven days.
##
## ---------------------------------------------------------------------------
## THE PLAYER IS ONE STATED RULE, AND IT IS STATED BECAUSE IT IS AN ASSUMPTION
## ---------------------------------------------------------------------------
## Threshold traffic depends on what the player does, and this tool cannot know
## that. So there are two scenarios and both are labelled:
##
##   --player none    nobody eats, drinks or warms up. The body falls from full
##                    and core temperature kills him partway through day two.
##                    This is the authored data with no behaviour in it at all,
##                    and it is the densest burst of crossings the data can make.
##
##   --player tends   whenever a reading falls below `--floor`, he deals with it
##                    and it goes back to full. One rule, no tuning, and it keeps
##                    a run alive for all seven days -- which is the only way to
##                    see the traffic over a whole run. Recovery crossings count:
##                    section 5.2 surfaces a wordless note on the way back up too.
##
## Neither is "the" answer. Between them they bracket it, and the number that
## needs no scenario at all -- the prompt's own duty cycle -- is printed on its
## own line.

const UILayerScript := preload("res://src/ui/ui_layer.gd")
const SurfacingScript := preload("res://src/ui/threshold_surfacing.gd")
const PromptScript := preload("res://src/ui/time_prompt.gd")

var _player := "tends"
var _seconds := 0.0
var _step := 1.0 / 60.0
var _floor := 0.02

var _layer: UILayer = null
var _surfacing = null
var _prompt = null
var _clock = null
var _survival = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_player = _string_arg(args, "--player", _player)
	_seconds = float(_string_arg(args, "--seconds", "0"))
	_step = float(_string_arg(args, "--step", str(_step)))
	_floor = float(_string_arg(args, "--floor", str(_floor)))

	_clock = get_node_or_null("/root/WorldClock")
	_survival = get_node_or_null("/root/SurvivalSystem")
	if _clock == null or _survival == null:
		push_error("measure_prompt_traffic: the autoloads are not there")
		get_tree().quit(1)
		return

	_layer = UILayerScript.new()
	_layer.name = "UI"
	add_child(_layer)
	_layer.build()

	_surfacing = SurfacingScript.new()
	_surfacing.name = "ThresholdSurfacing"
	_layer.add_child(_surfacing)
	_surfacing.build()

	_prompt = PromptScript.new()
	_prompt.name = "TimePrompt"
	_layer.add_child(_prompt)
	_prompt.build()

	_run()
	_teardown()
	get_tree().quit()


## A dirty console is a failed run by this project's standard even for an
## instrument: a tool that reports "9 ObjectDB instances leaked" beside a duty
## cycle invites the reader to discount both numbers.
##
## Two separate things had to be let go of.
##
## 1. Elements still breathing when the run ends are still parented to the layer,
##    and the layer's own clear() is what detaches and frees them.
##
## 2. THE VOICES, which is the one that was actually leaking. Traced with
##    --verbose: eight `AudioStreamPlaybackMP3` plus `heartbeat.mp3` itself at a
##    reference count of eight -- one per voice in UIAudio's pool, which is
##    POOL_SIZE. It is BOUNDED at the pool size and does not grow with the run:
##    171 notes over seven days leak the same eight objects as eleven do. It
##    appears here and not in the game because this tool quits synchronously
##    inside _ready(), so the audio server never gets a frame in which to release
##    what it is holding.
##
##    Left as a tool-side stop rather than a change to UIAudio: the object is
##    bounded, the mechanism is process shutdown rather than the class, and
##    src/ui/ui_audio.gd is not this task's file. Reported rather than patched.
func _teardown() -> void:
	if _layer == null:
		return
	if _layer.has_method("clear"):
		_layer.clear()
	if _layer.has_method("audio"):
		var voice = _layer.call("audio")
		if voice != null and is_instance_valid(voice):
			for child in voice.get_children():
				if child is AudioStreamPlayer:
					child.stop()
					child.stream = null


func _string_arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


# --- the run -------------------------------------------------------------------

func _run() -> void:
	# The schedules FIRST, then start(). WorldClock.start() refuses an empty
	# clock and returns false, and a clock that never started has a zero period,
	# a zero run length and no phase -- which is what this tool printed on its
	# first run: `every 0.0 s -> duty 9920000%`. SurvivalSystem loads its own
	# stats in _ready(); the clock does not, because game_state.gd is what loads
	# them in the game.
	if int(_clock.schedule_count()) == 0:
		_clock.load_schedules_from_directory()
	if not bool(_clock.start()):
		push_error("measure_prompt_traffic: the clock refused to start -- no schedules")
		get_tree().quit(1)
		return
	_survival.start()
	if _seconds <= 0.0:
		_seconds = float(_clock.total_run_seconds())

	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var period: float = _prompt.seconds_between()

	var frames := 0
	var with_note := 0
	var with_prompt := 0
	var with_both := 0
	var notes_seen := 0
	var prompts_seen := 0
	var most_notes := 0
	var deepest := 0.0
	var collisions := 0
	var was_colliding := false
	var streak := 0
	var longest_streak := 0
	var longest_quiet := 0
	var quiet := 0
	var died_at := -1.0

	var t := 0.0
	while t < _seconds:
		# The order a tree would tick them in: the world, then the body, then the
		# things that watch both, then the layer that carries what they made.
		_clock.advance(_step)
		_survival.advance(_step)
		if _player == "tends":
			_tend()
		_prompt.advance(_step)
		_surfacing.advance(_step)
		_layer.advance(_step)

		if died_at < 0.0 and _survival.is_dead():
			died_at = t

		var live := _census()
		var notes: int = live["notes"]
		var prompt_up: bool = live["prompt"]
		frames += 1
		if notes > 0:
			with_note += 1
		if prompt_up:
			with_prompt += 1
		var colliding := notes > 0 and prompt_up
		if colliding:
			with_both += 1
			if not was_colliding:
				collisions += 1
		was_colliding = colliding
		most_notes = maxi(most_notes, notes)
		deepest = maxf(deepest, float(live["bottom"]))
		if notes > 0 or prompt_up:
			streak += 1
			longest_quiet = maxi(longest_quiet, quiet)
			quiet = 0
		else:
			quiet += 1
			longest_streak = maxi(longest_streak, streak)
			streak = 0
		t += _step
	longest_streak = maxi(longest_streak, streak)
	longest_quiet = maxi(longest_quiet, quiet)

	prompts_seen = int(_prompt.surfaced_count())
	notes_seen = _notes_raised

	# Annotated rather than inferred: `_prompt` is untyped (it is built from a
	# preloaded script), so `.data()` is a Variant and `:=` cannot infer from it.
	var note_life: float = _layer.tokens().bloom_seconds + SurfacingScript.HOLD_SECONDS \
		+ _layer.tokens().drift_seconds
	var prompt_life: float = _layer.tokens().bloom_heavy_seconds + _prompt.data().hold_seconds \
		+ _layer.tokens().drift_long_seconds

	print("measure_prompt_traffic: %s, %.0f s at %.4f s/step, canvas %.0f x %.0f" % [
		_player, _seconds, _step, canvas.x, canvas.y])
	if died_at >= 0.0:
		print("  the body died at %.1f s; the clock and the prompt ran on" % died_at)
	print("  section 5.10 prompt   every %.1f s, alive %.2f s  -> duty %.2f%%" % [
		period, prompt_life, prompt_life / maxf(period, 0.0001) * 100.0])
	print("  section 5.2 note      alive %.2f s each" % note_life)
	print("  one note overlaps the prompt with probability (%.2f + %.2f) / %.1f = %.1f%%" % [
		note_life, prompt_life, period, (note_life + prompt_life) / maxf(period, 0.0001) * 100.0])
	print("")
	print("  raised                %d prompts, %d notes" % [prompts_seen, notes_seen])
	print("  a note on screen      %.2f%% of the run" % (float(with_note) / float(frames) * 100.0))
	print("  the prompt on screen  %.2f%% of the run" % (float(with_prompt) / float(frames) * 100.0))
	print("  BOTH at once          %.2f%% of the run, in %d separate episodes" % [
		float(with_both) / float(frames) * 100.0, collisions])
	print("  anything on screen    %.2f%% of the run" % (
		float(frames - _quiet_frames) / float(frames) * 100.0))
	print("  longest unbroken stretch with something on screen  %.2f s" % (
		float(longest_streak) * _step))
	print("  longest stretch with NOTHING on screen             %.2f s" % (
		float(longest_quiet) * _step))
	print("  most notes stacked at once  %d, reaching %.0f px down a %.0f px canvas" % [
		most_notes, deepest, canvas.y])


## What is actually parented to the layer and breathing, right now. Notes are
## counted by instance id rather than by asking the surfacing for a tally, so the
## number is of things that exist on the layer.
func _census() -> Dictionary:
	var notes := 0
	var prompt := false
	var bottom := 0.0
	for child in _layer.get_children():
		if child is TimeArc:
			prompt = true
		elif child is ThresholdNote:
			notes += 1
			bottom = maxf(bottom, child.position.y + child.size.y)
			var id := child.get_instance_id()
			if not _seen.has(id):
				_seen[id] = true
				_notes_raised += 1
	if notes == 0 and not prompt:
		_quiet_frames += 1
	return {"notes": notes, "prompt": prompt, "bottom": bottom}


var _quiet_frames := 0
var _notes_raised := 0
var _seen: Dictionary = {}


## The stated player: whatever falls below the floor, he deals with. One rule.
func _tend() -> void:
	for stat_id in _survival.stat_ids():
		if float(_survival.fraction_of(stat_id)) <= _floor:
			_survival.restore(stat_id, 1.0)


func _process(_delta: float) -> void:
	pass
