extends SceneTree

## What fraction of a saved frame is warm, against Art Bible rule 12's 0.5%.
##
##   Godot_console.exe --headless --path <project> \
##       --script res://tools/measure_warm_share.gd -- <frame.png> [more.png ...]
##
## With no arguments it walks `.superpowers/sdd/wave3/dogs/` for `game-*.png`.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## Rule 12 caps warm pixels at half a percent of the frame, and until now that
## number has only ever been cited -- fourteen files quote it in a comment and
## not one of them measures it. The Director's amendment putting the companion
## dog on the warm list says in as many words that the share must be re-measured
## rather than assumed, because a dog is small but it MOVES and it shares the
## budget with the scarf, the windows and the truck.
##
## ---------------------------------------------------------------------------
## WHAT COUNTS AS A WARM PIXEL, AND WHY IT IS `r - b`
## ---------------------------------------------------------------------------
## Not "is this pixel one of the three warm tones". A rendered frame holds the
## LIT and SHADE band of every colour, the aerial-perspective fade, the sky, and
## the snow lens -- so an equality test would find almost nothing and report a
## reassuring zero.
##
## The discriminator is the palette's own shape. Every one of the nine cool
## entries has more blue than red, by a wide margin; all three warm entries have
## more red than blue, by a wider one:
##
##   snow[0]      #8FB0D8   r-b = -0.286      warm[0]  #6E2F2E   r-b = +0.251
##   structure[0] #33496E   r-b = -0.231      warm[1]  #A05A35   r-b = +0.420
##   structure[3] #131C30   r-b = -0.114      warm[2]  #FFB257   r-b = +0.659
##
## The narrowest cool margin is 0.114 and the narrowest warm margin is 0.251, so
## a threshold at 0.04 sits in a gap five times wider than it, and no amount of
## band-splitting or fog moves a colour across it: aerial perspective pulls
## everything TOWARDS the sky, which is cool, so it can only ever make a warm
## pixel less warm and never the reverse.
##
## `--threshold` is exposed so the number can be argued with rather than trusted.
##
## ---------------------------------------------------------------------------
## AND IT CHECKS THE FRAME IS IN THE SPACE IT IS ASSUMED TO BE IN
## ---------------------------------------------------------------------------
## Briefing trap 7: with a linear tonemap at exposure 1.0 a lit surface returns
## its palette hex EXACTLY, so a snow pixel in a saved PNG should read `#8FB0D8`.
## That is asserted here rather than believed, because everything above depends
## on it -- and because the first pass of the coat measurement compared the
## palette against a texture in sRGB, which reorders the warm entries and would
## have chosen a different dog.
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const DEFAULT_ROOT := "res://.superpowers/sdd/wave3/dogs"
const WARM_THRESHOLD := 0.04

## The HUD's own corner, reported separately.
##
## Rule 12 is about pixels on screen and the vitals cluster is on screen, so it
## is COUNTED -- but it is also another agent's live work and it moved under this
## measurement mid-task: the same frame read 0.0306% before the vitals ring
## landed and 0.0875% after. A single total that silently mixes the two makes
## every reading a joint claim about two people's work. So the world's share and
## the HUD's are both printed, and the dog is judged on the world's.
##
## As a fraction of the frame, so it holds at any capture resolution.
const HUD_RECT := Rect2(0.0, 0.0, 0.25, 0.16)

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var threshold := WARM_THRESHOLD
	var frames := PackedStringArray()
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--threshold" and index + 1 < args.size():
			threshold = float(args[index + 1])
		elif not args[index].begins_with("--") and (index == 0 or args[index - 1] != "--threshold"):
			frames.append(args[index])
	if frames.is_empty():
		frames = _frames_under(DEFAULT_ROOT)

	_report_palette()
	print("")
	print("%-40s %8s %9s %9s %8s   %s" % [
		"frame", "warm px", "of frame", "of world", "quota", "warmest pixel"])
	var worst := 0.0
	var worst_frame := ""
	for path in frames:
		var share := _measure(path, threshold)
		if share > worst:
			worst = share
			worst_frame = path
	print("")
	print("WORST FRAME (world only, HUD excluded): %s at %.4f%% of a 0.5000%% quota (%.0f%% of budget)" % [
		worst_frame.get_file(), worst * 100.0, worst * 100.0 / 0.5 * 100.0])
	quit(0 if worst <= 0.005 else 1)
	return true


func _frames_under(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	for entry in dir.get_files():
		if entry.begins_with("game-") and entry.ends_with(".png"):
			found.append(root.path_join(entry))
	found.sort()
	return found


## The palette's own red-minus-blue margins, so the threshold can be checked
## against the thing it separates rather than taken on trust.
func _report_palette() -> void:
	var bible: Resource = load(PALETTE_PATH)
	if bible == null:
		print("measure_warm_share: no palette at %s" % PALETTE_PATH)
		return
	for family in ["snow", "structure", "warm"]:
		var tones: Array = bible.get(family + "_tones")
		for index in range(tones.size()):
			var tone: Color = tones[index]
			print("   %-12s %s   r-b = %+.3f" % [
				"%s[%d]" % [family, index], tone.to_html(false), tone.r - tone.b])


func _measure(path: String, threshold: float) -> float:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		print("   %-46s could not be read" % path.get_file())
		return 0.0
	var width := image.get_width()
	var height := image.get_height()
	var warm := 0
	var hud_warm := 0
	var hud := Rect2(
		HUD_RECT.position.x * width, HUD_RECT.position.y * height,
		HUD_RECT.size.x * width, HUD_RECT.size.y * height)
	var warmest := 0.0
	var warmest_colour := Color(0, 0, 0)
	# The snow check: the most common colour in the top third of a valley frame
	# is sky or snow, and either is a cool palette value.
	var tally: Dictionary = {}
	for y in range(height):
		for x in range(width):
			var pixel := image.get_pixel(x, y)
			var margin := pixel.r - pixel.b
			if margin > threshold:
				warm += 1
				if hud.has_point(Vector2(x, y)):
					hud_warm += 1
				if margin > warmest:
					warmest = margin
					warmest_colour = pixel
			else:
				var key := pixel.to_html(false)
				tally[key] = int(tally.get(key, 0)) + 1
	var total := width * height
	var share := float(warm) / float(total)
	var commonest := ""
	var seen := 0
	for key in tally:
		if int(tally[key]) > seen:
			seen = int(tally[key])
			commonest = key
	var world := float(warm - hud_warm) / float(total)
	print("%-40s %8d %8.4f%% %8.4f%% %8s   %s (r-b %+.3f); commonest cool %s at %.1f%%" % [
		path.get_file(), warm, share * 100.0, world * 100.0,
		"OK" if world <= 0.005 else "OVER",
		warmest_colour.to_html(false), warmest, commonest, 100.0 * float(seen) / float(total)])
	return world
