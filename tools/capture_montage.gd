extends Node

## Screenshot harness for the opening montage -- UI design document sections 4.5
## and 5.9. Plays data/montage/opening.tres against the real main scene, from a
## perspective camera, and writes a PNG at each authored moment.
##
##   Godot_console.exe --path <project> res://tools/capture_montage.tscn \
##       --resolution 1600x900 -- --out D:/somewhere/montage
##
## Lives in tools/ and is never referenced by the game, the same way
## capture_frame.gd is: the acceptance criterion for spatial typography is an
## IMAGE -- does the line foreshorten, is it occluded, does the wind take it --
## and an image has to be producible from a shell with nobody at the keyboard.
##
## ---------------------------------------------------------------------------
## WHY IT BRINGS ITS OWN CAMERA
## ---------------------------------------------------------------------------
## The main scene's camera is orthographic (Art Bible rule 1), and an
## orthographic dolly changes framing and nothing else -- there is no
## foreshortening to photograph. So this makes a Camera3D, makes it current, and
## hands it to the director. See MontageShot for why that is not a breach of
## rule 1.

const MONTAGE_PATH := "res://data/montage/opening.tres"
const TOKENS_PATH := "res://data/ui/tokens.tres"
const DEFAULT_OUTPUT := "user://montage"

## SOLVED FROM THE MONTAGE, NOT HARDCODED. The first pass listed six literal
## seconds, and they were silently wrong the moment GLYPH_STAGGER moved: a line's
## duration falls out of its character count, so every shutter time shifted and
## two frames landed on a line that had already blown away. A frame taken at the
## wrong moment does not fail, it just photographs nothing, which is the worst
## way for a harness to be broken.
##
## Two per shot that carries a line: one while it is fully written and being
## read, one partway through the wind taking it.
var _shutter: Array = []

var _director: MontageDirector = null
var _camera: Camera3D = null
var _elapsed := 0.0
var _next := 0
var _output := DEFAULT_OUTPUT


func _ready() -> void:
	_output = _argument("--out", DEFAULT_OUTPUT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))

	var montage := ResourceLoader.load(MONTAGE_PATH) as Montage
	if montage == null:
		push_error("capture_montage: no montage at %s" % MONTAGE_PATH)
		get_tree().quit(1)
		return

	var tokens := ResourceLoader.load(TOKENS_PATH) as UITokens
	var fonts := UIFonts.new()
	fonts.build(tokens)
	if not fonts.is_ready():
		push_error("capture_montage: the font chains did not build")
		get_tree().quit(1)
		return

	_camera = Camera3D.new()
	_camera.name = "MontageCamera"
	add_child(_camera)
	# Takes over from the main scene's orthographic rig. Without this the frames
	# are the game's own view and nothing in them moves.
	_camera.current = true

	_director = MontageDirector.new()
	_director.name = "MontageDirector"
	add_child(_director)
	_director.set_camera(_camera)
	_director.set_fonts(fonts)
	_director.set_tokens(tokens)
	# The director drives itself from _process; this harness drives it by hand so
	# the shutter lands on an exact montage time rather than on whichever frame
	# happened to be rendering.
	_director.set_process(false)
	_director.play(montage)

	_plan_shutter(montage, tokens)
	print("capture_montage: %d shots, %.1f s, %d frames -> %s"
		% [montage.shot_count(), montage.total_seconds(), _shutter.size(), _output])


## Works out when each line is worth photographing, from the line itself.
func _plan_shutter(montage: Montage, tokens: UITokens) -> void:
	_shutter.clear()
	var shot_start := 0.0
	for index in montage.shot_count():
		var shot: MontageShot = montage.shots[index]
		if shot == null:
			continue
		if shot.has_text():
			var count := shot.text.length()
			var first := Breath.inscription(tokens, 0, count)
			var last := Breath.inscription(tokens, count - 1, count)
			var base: float = shot_start + shot.text_start
			# A third into the last glyph's hold: everything is written, nothing
			# has started to go.
			_shutter.append([
				base + last.delay + last.bloom_seconds + last.hold_seconds * 0.33,
				"%02d_shot%d_written" % [_shutter.size() + 1, index + 1]])
			# Halfway between the first glyph leaving and the last one finishing,
			# which is the only window where the line is visibly coming APART
			# rather than merely present or merely gone.
			var opens: float = first.exit_begins()
			var closes: float = last.total_seconds()
			_shutter.append([
				base + lerpf(opens, closes, 0.45),
				"%02d_shot%d_scattering" % [_shutter.size() + 1, index + 1]])
		shot_start += shot.duration


func _process(delta: float) -> void:
	if _director == null:
		return
	# A FIXED STEP, not the real delta. This machine renders far faster than real
	# time and the montage would otherwise be sampled at whatever rate the scene
	# happened to cost that run -- which is the same trap capture_frame.gd
	# documents about frame-numbered routes walking a different distance every
	# time the rendering cost changed.
	var step := 1.0 / 60.0
	_elapsed += step
	_director.advance(step)

	while _next < _shutter.size() and _elapsed >= float(_shutter[_next][0]):
		_shoot(String(_shutter[_next][1]))
		_next += 1

	if _next >= _shutter.size():
		print("capture_montage: done")
		get_tree().quit(0)


func _shoot(label: String) -> void:
	# The frame currently on screen is the one BEFORE this tick's changes were
	# drawn, so wait for the next post-draw before reading the viewport back.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _output.path_join("%s.png" % label)
	var error := image.save_png(path)
	print("  %-22s t=%5.2f s  shot %d  -> %s (%d)"
		% [label, _elapsed, _director.current_shot_index(), path, error])


func _argument(name: String, fallback: String) -> String:
	var argv := OS.get_cmdline_user_args()
	for index in range(argv.size() - 1):
		if argv[index] == name:
			return argv[index + 1]
	return fallback
