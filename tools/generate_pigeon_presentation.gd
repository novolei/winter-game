extends SceneTree

## Generates the data resource for the owner's three pigeon plumages and two
## supplied sounds, plus the explicitly exempt affection-heart colour. Run after
## the audio files have been copied and imported:
##
##   godot --headless --path <project> --script res://tools/generate_pigeon_presentation.gd
##
## The owner explicitly exempted pigeon plumage from the world's twelve surface
## colours. Colour literals still live only in tools, and the runtime reads the
## generated resource rather than carrying a second hidden palette in code.

const OUTPUT_PATH := "res://data/wildlife/pigeon_presentation.tres"
const CALL_PATH := "res://assets/audio/wildlife/pigeon/pigeon_call.mp3"
const DEPARTURE_PATH := "res://assets/audio/wildlife/pigeon/pigeon_departure_wings.ogg"


func _initialize() -> void:
	var PresentationScript := load("res://src/definitions/pigeon_presentation.gd")
	var presentation: PigeonPresentation = PresentationScript.new()
	presentation.plumage_tones = [
		# Grey-brown: muted taupe, not the previous red-brown world accent.
		Color("#746A61"),
		# Grey-black: charcoal with enough blue to sit in winter light.
		Color("#343942"),
		# Milk white: warm enough to read as plumage rather than a snow chip.
		Color("#DDD4C2"),
	] as Array[Color]
	presentation.plumage_texture_tint_strength = 0.34
	# A deliberately UI-like pink. The owner explicitly exempted this tiny heart
	# from the twelve world-surface colours; keeping it in generated data makes
	# that exception visible and prevents a hidden literal in runtime code.
	presentation.heart_color = Color("#FF78A8")
	# The feed interaction's dedicated theme green. It is intentionally not added
	# to UITokens: ordinary world prompts keep the twelve-colour UI language, while
	# this one hold affordance may match the owner's green reference ring/leader.
	presentation.feed_prompt_color = Color("#51FF2D")
	# The owner chose a quiet straight leader, but the charcoal read too black on
	# snow. Use the colour bible's muted slate-grey so it remains secondary to the
	# bright green charge ring without relying on transparency.
	presentation.feed_guide_color = Color("#667890")
	presentation.ground_call = load(CALL_PATH) as AudioStream
	presentation.departure_wings = load(DEPARTURE_PATH) as AudioStream

	if presentation.ground_call == null or presentation.departure_wings == null:
		push_error("generate_pigeon_presentation: import the two pigeon sounds first")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/wildlife"))
	var error := ResourceSaver.save(presentation, OUTPUT_PATH)
	print("generate_pigeon_presentation: save returned %d" % error)
	quit(0 if error == OK else 1)
