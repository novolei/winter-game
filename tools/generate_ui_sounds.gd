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
## WHAT SECTION 8 STILL WANTS AND THIS CANNOT SHIP
## ---------------------------------------------------------------------------
## No asset exists yet for: the 呵 itself (a very light in-breath or frost
## crack, 20 ms, around -28 dB), the interaction ripple, the threshold heartbeat
## at 45 Hz, or the nightfall thump. They are deliberately NOT stubbed with a
## stand-in -- a wrong sound in the right place is harder to notice than silence,
## and tests/unit/test_ui_audio.gd asserts every cue in this map points at a file
## that actually exists.

const OUT_DIR := "res://data/audio"
const OUT_PATH := "res://data/audio/ui_sounds.tres"

const CONFIRM_STREAM := "res://assets/audio/ui/button_press.wav"
const MOVE_STREAM := "res://assets/audio/ui/click.mp3"

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

	var map = MapScript.new()
	# Typed-array property, so the local MUST be annotated: `var x = [...]` is a
	# Variant holding an untyped Array, the typed setter rejects it, and the VM
	# breaks out of this function without a word (briefing trap 4). The generator
	# would then save an EMPTY map and print success.
	var cues: Array[UISoundCue] = [move, confirm, back]
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
