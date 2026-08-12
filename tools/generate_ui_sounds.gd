extends SceneTree

## Generator for res://data/audio/ui_sounds.tres -- UI design document section 8.
##
## Run: godot --headless --path <project> --script res://tools/generate_ui_sounds.gd
##
## ---------------------------------------------------------------------------
## TWO FILES, THREE CUES
## ---------------------------------------------------------------------------
## Section 8 asks for a distinct sound on menu move, on confirm and on back, and
## specifies the third as "同上，降 3 个半音" -- the confirm sound, three semitones
## down. So back and confirm share a file and differ by pitch, which is both
## cheaper and better: two sounds cut from the same object read as the same
## mechanism doing two things, which is what a menu is.
##
## button_press.wav carries TWO transients, a press and a release, and that is
## why it is the confirm rather than the move: committing to something should
## sound like a mechanism completing, not like brushing past it.
##
## ---------------------------------------------------------------------------
## THE 呵 IS 670 ms, NOT SECTION 8's 20 ms, AND THAT CHANGES WHERE IT GOES
## ---------------------------------------------------------------------------
## Section 8 specified the bloom sound as "极轻的吸气 / 霜裂, 20 ms" -- written
## before any asset existed. The supplied breath is a real exhale: 0.67 s after
## trimming, and it does not compress to 20 ms without becoming a click.
##
## The asset is better than the spec, but it belongs somewhere else. Fired on
## EVERY element bloom -- which is a 200 ms event that can happen three times in
## a row when thresholds stack (section 5.2) -- half-second breaths would overlap
## into a wash. So it is the sound of the HEAVY bloom: the day announcement, the
## Tab screen opening, an ending. Section 8's own table already puts it there
## ("Tab 开 -- 呼气声 + 霜在玻璃上蔓延, 320 ms"); this makes that the only place
## it plays.
##
## The small elements stay silent on arrival. That is not a gap -- an interface
## whose every appearance chirps is the thing rule 6 was never asking for.
##
## ---------------------------------------------------------------------------
## THE CRITICAL THRESHOLD IS TWO SOUNDS, WHICH IS WHAT SECTION 8 ASKED FOR
## ---------------------------------------------------------------------------
## "心跳 + 极高频耳鸣, 耳鸣 -34 dB". The heartbeat is the SAME heartbeat as the
## ordinary threshold -- it is one body -- and the tinnitus is what is added.
##
## An earlier pass had no tinnitus asset and substituted a heartbeat pitched four
## semitones down. That worked, but it invented a distinction the design never
## asked for. With the real sound in hand the pitch trick is gone: the heartbeat
## is at unity again and ui.critical simply LAYERS ui.tinnitus. One less
## invented thing.
##
## The tinnitus is 7.56 s and its energy runs the whole length, which suits what
## it represents. 濒危 is not an event, it is a STATE -- the stat sits below 0.15
## and stays there -- so a sound that outlasts the 2.4 s surfacing is correct
## rather than long. Whoever wires section 5.2 may want it looping.

const OUT_DIR := "res://data/audio"
const OUT_PATH := "res://data/audio/ui_sounds.tres"

const CONFIRM_STREAM := "res://assets/audio/ui/button_press.wav"
const MOVE_STREAM := "res://assets/audio/ui/click.mp3"
const BREATH_STREAM := "res://assets/audio/ui/breath.wav"
const RIPPLE_STREAM := "res://assets/audio/ui/ripple.wav"
const HEARTBEAT_STREAM := "res://assets/audio/ui/heartbeat.mp3"
const NIGHTFALL_STREAM := "res://assets/audio/ui/nightfall_thump.mp3"
const TINNITUS_STREAM := "res://assets/audio/ui/tinnitus.wav"

## Three semitones down, as a ratio. Section 8 gives the interval; this is what
## it is worth.
const THREE_SEMITONES_DOWN := 0.8408964


func _initialize() -> void:
	var CueScript := load("res://src/definitions/ui_sound_cue.gd")
	var MapScript := load("res://src/definitions/ui_sound_map.gd")

	var move = CueScript.new()
	move.cue_id = &"ui.move"
	move.stream_path = MOVE_STREAM
	# Well under the confirm. Moving a selection happens constantly and must sit
	# beneath the wind rather than on top of it.
	move.gain_db = -14.0
	move.pitch_scale = 1.0
	# A little spread, because this is the one cue that fires over and over and
	# an identical repeat reads as a metronome. Small enough that it is never
	# heard as a different sound.
	move.pitch_spread = 0.04
	move.notes = "菜单移动。Section 8 asks for a packed-snow thud; this click stands in until one is cut."

	var confirm = CueScript.new()
	confirm.cue_id = &"ui.confirm"
	confirm.stream_path = CONFIRM_STREAM
	confirm.gain_db = -6.0
	confirm.pitch_scale = 1.0
	# Zero, deliberately: a confirm that wandered in pitch would read as a
	# different sound each time, and this one has to mean exactly one thing.
	confirm.pitch_spread = 0.0
	confirm.notes = "菜单确认。Two transients -- a press and a release -- so committing sounds like a mechanism completing."

	var back = CueScript.new()
	back.cue_id = &"ui.back"
	back.stream_path = CONFIRM_STREAM
	back.gain_db = -8.0
	back.pitch_scale = THREE_SEMITONES_DOWN
	back.pitch_spread = 0.0
	back.notes = "菜单返回。Section 8: the confirm sound, three semitones down. Same file; the pitch is the whole difference."

	var bloom = CueScript.new()
	bloom.cue_id = &"ui.bloom"
	bloom.stream_path = BREATH_STREAM
	# Far under everything. Section 8 asks for -28 dB and the trimmed asset peaks
	# at 0.19, so it is already a quiet recording; this keeps it under the wind
	# rather than over it.
	bloom.gain_db = -20.0
	bloom.pitch_scale = 1.0
	bloom.pitch_spread = 0.05
	bloom.notes = "元素 呵 -- HEAVY blooms only: day/night, Tab, endings. See the header for why not every bloom."

	var ripple = CueScript.new()
	ripple.cue_id = &"ui.ripple"
	ripple.stream_path = RIPPLE_STREAM
	ripple.gain_db = -12.0
	ripple.pitch_scale = 1.0
	ripple.pitch_spread = 0.03
	ripple.notes = "交互确认。Starts on the same frame as the 涟漪 ring expanding from the world anchor (section 5.1)."

	var threshold = CueScript.new()
	threshold.cue_id = &"ui.threshold"
	threshold.stream_path = HEARTBEAT_STREAM
	threshold.gain_db = -16.0
	threshold.pitch_scale = 1.0
	# Zero: a heartbeat that wandered in pitch would read as a different body.
	threshold.pitch_spread = 0.0
	threshold.notes = "阈值恶化。Section 8's 45 Hz heartbeat."

	var critical = CueScript.new()
	critical.cue_id = &"ui.critical"
	critical.stream_path = HEARTBEAT_STREAM
	critical.gain_db = -11.0
	# Unity, same as ui.threshold: it is the same body and the same heart. What
	# makes this one worse is the layer, not the pitch.
	critical.pitch_scale = 1.0
	critical.pitch_spread = 0.0
	critical.layer_cue_id = &"ui.tinnitus"
	critical.notes = "阈值濒危。Section 8's 心跳 + 极高频耳鸣, as one cue layering another."

	var tinnitus = CueScript.new()
	tinnitus.cue_id = &"ui.tinnitus"
	tinnitus.stream_path = TINNITUS_STREAM
	# Section 8 names this number outright. It is meant to be at the edge of
	# hearing -- the player should notice the silence around it before they
	# notice the tone.
	tinnitus.gain_db = -34.0
	tinnitus.pitch_scale = 1.0
	tinnitus.pitch_spread = 0.0
	tinnitus.notes = "极高频耳鸣。Layered by ui.critical; a STATE sound, not an event. 7.56 s."

	var nightfall = CueScript.new()
	nightfall.cue_id = &"ui.nightfall"
	nightfall.stream_path = NIGHTFALL_STREAM
	# Raised from -7 by its own test. At -7 the menu CONFIRM (-6) was louder than
	# the deadline, which is the mix arguing with GDD section 3 -- a button press
	# cannot outweigh the one line the whole day is built around.
	nightfall.gain_db = -3.0
	nightfall.pitch_scale = 1.0
	nightfall.pitch_spread = 0.0
	nightfall.notes = "入夜。GDD section 3 makes NIGHTFALL = GO HOME a literal deadline; this is the loudest cue in the map on purpose."

	var map = MapScript.new()
	# Typed-array property, so the local MUST be annotated: `var x = [...]` is a
	# Variant holding an untyped Array, the typed setter rejects it, and the VM
	# breaks out of this function without a word (briefing trap 4). The generator
	# would then save an EMPTY map and print success.
	var cues: Array[UISoundCue] = [move, confirm, back, bloom, ripple,
		threshold, critical, tinnitus, nightfall]
	map.cues = cues

	var missing: Array[String] = []
	for cue in map.cues:
		if not FileAccess.file_exists(cue.stream_path):
			missing.append(cue.stream_path)
	if not missing.is_empty():
		printerr("generate_ui_sounds: stream(s) not on disk: %s" % ", ".join(missing))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var error := ResourceSaver.save(map, OUT_PATH)
	print("generate_ui_sounds: save returned %d, %d cues" % [error, map.cues.size()])
	quit(0 if error == OK else 1)
