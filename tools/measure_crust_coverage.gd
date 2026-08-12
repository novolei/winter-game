extends Node

## How much of a walker's legs the snow crust actually covers, counted off a
## rendered frame rather than judged by eye.
##
## THE INSTRUMENT EXISTS BECAUSE EYEBALLING PRODUCED 5%. The crust is meant to
## read as material on the cloth -- a third to a half of the band it occupies --
## and two rounds of tuning by inspection landed an order of magnitude below
## that without anybody being able to say so with a number. So this counts.
##
## ---------------------------------------------------------------------------
## HOW IT COUNTS, AND WHY THE DENOMINATOR IS RENDERED RATHER THAN COMPUTED
## ---------------------------------------------------------------------------
## Three renders of one frozen instant, differing ONLY in the crust's uniforms:
##
##   BARE   load 0. The crust draws nothing. This is the walker's own cloth.
##   ZONE   load 1, `patch_contrast` 0, `crease_bias` 0, `patch_scatter` ~0.
##          The noise field collapses to a constant 0.5 and the coverage ramp
##          collapses to a step, so the shader paints the WHOLE band it is
##          allowed to occupy, solid, and nothing outside it. That is the
##          crusted zone, drawn by the shader's own band arithmetic rather than
##          by a second copy of it here that could disagree.
##   REAL   load 1, shipped uniforms. The crust as it actually renders.
##
## Then, per pixel:
##
##   zone  = ZONE differs from BARE      the visible cloth inside the band
##   crust = REAL differs from BARE      the cloth that carries snow
##   coverage = crust / zone
##
## Differencing against BARE is what isolates the character: identical geometry,
## identical camera, identical light, so the only pixels that can move are the
## ones the crust painted. It also means "visible" is handled for free -- a
## fragment behind the coat or off-screen never drew in either pass and so is in
## neither count.
##
## The frame is frozen first (`SceneTree.paused`, every emitter's `speed_scale`
## to zero, the weather layers hidden) because a snowflake crossing the leg
## between two of the three renders is a difference that is not snow ON the leg.
## The run prints a NOISE FLOOR -- BARE captured twice and differenced against
## itself -- so that is a checked claim rather than an assumed one.
##
## ---------------------------------------------------------------------------
##   Godot_console.exe --path <project> --fixed-fps 60 --resolution 900x900 \
##       res://tools/measure_crust_coverage.tscn -- \
##       --out D:/somewhere/coverage --at 14.8,-11 --wade 0.43 --load 1.0
##
## Arguments:
##   --out <prefix>   writes <prefix>-bare.png, -zone.png, -real.png, -mask.png
##   --at x,z         where the walker stands
##   --load <0..1>    the WADED load to measure at (default 1.0)
##   --settle <0..1>  the SETTLED load to measure at (default 0.0). Measure one at
##                    a time: they occupy different parts of him, so a run with
##                    both on reports a number that describes neither.
##   --wade <m>       the crossing to wear, in metres of snow line (default 0.43)
##   --ortho <m>      frame height in metres (default 2.2)
##   --wait <n>       frames to run before freezing (default 40)
##   --patch-scale <n>  overrides how the covered fraction is SPREAD, for a sweep.
##                    The zone pass does not use it, so the denominator is
##                    identical across a sweep and the numbers compare directly.
##   --offset x,y     pins the wearer's noise offset. TWO BUILDS OF THIS EFFECT
##                    ARE JUDGED ON THE SAME MARKS OR THEY ARE NOT JUDGED AT ALL:
##                    each wearer now rolls its own offset at construction, so
##                    without this every capture would draw a different pattern
##                    and a sweep would be comparing samples rather than settings.

const WAIT_FRAMES := 40

var _out := ""
var _at := Vector2(14.8, -11.0)
var _load := 1.0
var _settle := 0.0
var _wade := 0.43
var _ortho := 2.2
var _wait := WAIT_FRAMES
var _patch_scale := -1.0
var _offset := Vector2(-1.0, -1.0)
var _frame := 0
var _done := false
var _legs: Node = null
var _crusts: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_load = float(_arg(args, "--load", "1.0"))
	_settle = float(_arg(args, "--settle", "0.0"))
	_wade = float(_arg(args, "--wade", "0.43"))
	_ortho = float(_arg(args, "--ortho", "2.2"))
	_wait = int(_arg(args, "--wait", str(WAIT_FRAMES)))
	_patch_scale = float(_arg(args, "--patch-scale", "-1"))
	var at := _arg(args, "--at", "")
	if at != "":
		var parts := at.split(",")
		if parts.size() == 2:
			_at = Vector2(float(parts[0]), float(parts[1]))
	var pinned := _arg(args, "--offset", "")
	if pinned != "":
		var parts := pinned.split(",")
		if parts.size() == 2:
			_offset = Vector2(float(parts[0]), float(parts[1]))
	if _out == "":
		push_error("measure_crust_coverage: --out is required")
		get_tree().quit()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame == 1:
		_place()
		return
	if _frame < _wait:
		return
	_done = true
	_measure()


func _place() -> void:
	var body := get_node_or_null("Main/Player") as Node3D
	if body != null:
		body.global_position = Vector3(_at.x, body.global_position.y, _at.y)
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null:
		rig.orthographic_size = _ortho
		if rig.has_method("apply_framed_size"):
			rig.apply_framed_size(_ortho)
		if rig.has_method("snap_to_target"):
			rig.snap_to_target()


## Everything that would move between three renders of "the same" instant.
##
## The tree is paused, which stops the walk and the animation; the emitters are
## stopped by hand, because GPU particles are advanced by the rendering server
## and a paused tree does not reach them; and the weather layers are hidden
## outright, because a flake drawn in FRONT of a leg is a difference between two
## frames that has nothing to do with what is on the leg.
func _freeze() -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()
	for weather in ["Main/Snowfall", "Main/SnowLens"]:
		var node := get_node_or_null(weather)
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		elif node is Node3D:
			(node as Node3D).visible = false
	var emitters: Array[GPUParticles3D] = []
	_emitters_of(get_tree().root, emitters)
	for emitter in emitters:
		emitter.speed_scale = 0.0
		emitter.visible = false
	Engine.time_scale = 0.0
	get_tree().paused = true
	if _legs != null:
		# The crust's uniforms are written from _process(), so the one node that
		# must keep running is the one being measured.
		_legs.process_mode = Node.PROCESS_MODE_ALWAYS


static func _emitters_of(node: Node, found: Array[GPUParticles3D]) -> void:
	if node is GPUParticles3D:
		found.append(node as GPUParticles3D)
	for child in node.get_children():
		_emitters_of(child, found)


func _measure() -> void:
	var player := get_node_or_null("Main/Player") as Node3D
	if player == null:
		push_error("measure_crust_coverage: no player")
		get_tree().quit()
		return
	_legs = player.get_node_or_null("LegSnow")
	if _legs == null:
		_legs = player.get_node_or_null("SnowLoad")
	if _legs == null:
		push_error("measure_crust_coverage: the walker is wearing no snow node")
		get_tree().quit()
		return
	_freeze()
	_crusts = _legs.get("_crusts")
	if _crusts == null or _crusts.is_empty():
		push_error("measure_crust_coverage: the walker was never dressed")
		get_tree().quit()
		return

	# IS THE CRUST ACTUALLY MOUNTED, AND IS THE MESH ACTUALLY BEING DRAWN.
	#
	# A zone of zero px has two completely different causes and the number alone
	# cannot tell them apart: the band arithmetic put the crust nowhere, or the
	# crust is not on the mesh at all. The second happens -- another system takes
	# the same instance's `material_override` or drives its `transparency` when the
	# walker is near the farmhouse -- and it presents as a measurement of nothing
	# rather than as an error, which cost a previous round its own explanation.
	var dressed: Array = _legs.get("_dressed")
	for index in range(dressed.size()):
		var mesh: MeshInstance3D = dressed[index]
		print("measure: %s mounted=%s transparency=%.3f visible=%s override=%s" % [
			mesh.name, str(mesh.material_overlay == _crusts[index]), mesh.transparency,
			str(mesh.is_visible_in_tree()),
			"none" if mesh.material_override == null else mesh.material_override.get_class()])

	# The pattern first, and before anything is rendered: pinning it is what makes
	# one run's frames comparable with another's now that every wearer rolls its
	# own. Left alone when it was not asked for, so an ordinary measurement still
	# sees whatever this walker happens to be wearing.
	if _offset.x >= 0.0:
		_legs.call("set_noise_offset", _offset)
	if _patch_scale > 0.0:
		for crust in _crusts:
			crust.set_shader_parameter(&"patch_scale", _patch_scale)

	# The shipped values, read off the first material so this file restates none
	# of them and cannot fall out of step with a retune.
	var kept := {}
	for key in ["patch_contrast", "crease_bias", "patch_scatter", "crust_coverage",
			"settle_coverage"]:
		kept[key] = _crusts[0].get_shader_parameter(StringName(key))

	# BOTH LOADS ARE WRITTEN ON EVERY PASS, and the settled one is the reason. The
	# walker's own node is the one node left running while the tree is paused --
	# it has to be, it writes the uniforms -- so the live weather kept settling
	# snow on his shoulders BETWEEN the bare frame and the zone frame. The first
	# run after that feature landed reported the crusted zone as reaching 1.98 m up
	# a man 1.88 m tall, which is the picture telling you the instrument is
	# measuring two things at once.
	_wear(0.0, 0.0, _wade)
	var bare := await _shot("bare")
	var floor_image := await _shot("floor")
	_wear(_load, _settle, _wade)
	var real := await _shot("real")
	for crust in _crusts:
		crust.set_shader_parameter(&"patch_contrast", 0.0)
		crust.set_shader_parameter(&"crease_bias", 0.0)
		crust.set_shader_parameter(&"patch_scatter", 0.0005)
		crust.set_shader_parameter(&"crust_coverage", 1.0)
		crust.set_shader_parameter(&"settle_coverage", 1.0)
	# THE ZONE IS TAKEN AT THE SAME TWO LOADS AS THE FRAME IT IS THE DENOMINATOR
	# OF, with the noise removed and the coverage saturated. Anything else compares
	# a crust against a region it was never asked to fill.
	_wear(maxf(_load, 0.0), _settle, _wade)
	var zone := await _shot("zone")
	for key in kept:
		for crust in _crusts:
			crust.set_shader_parameter(StringName(key), kept[key])

	var noise := _count(bare, floor_image)
	var zone_mask := _mask(bare, zone)
	var crust_mask := _mask(bare, real)
	var zone_pixels := 0
	var crust_pixels := 0
	var stray := 0
	for index in range(zone_mask.size()):
		if zone_mask[index]:
			zone_pixels += 1
			if crust_mask[index]:
				crust_pixels += 1
		elif crust_mask[index]:
			stray += 1
	_paint(bare, zone_mask, crust_mask)
	# The legs at a size a person can read, framed off the zone's own bounding box
	# rather than off a rectangle typed in here -- so the close-up follows the
	# effect when the band moves instead of having to be re-aimed by hand.
	var around := _bounds(zone_mask, bare.get_width(), bare.get_height())
	_zoom(bare, around, "bare")
	_zoom(real, around, "real")
	_zoom(zone, around, "zone")

	var covered := 0.0 if zone_pixels == 0 else 100.0 * float(crust_pixels) / float(zone_pixels)
	print("measure: load=%.2f settle=%.2f wade=%.2fm ortho=%.1fm at (%.1f, %.1f)" % [
		_load, _settle, _wade, _ortho, _at.x, _at.y])
	# What the shader was actually handed, printed rather than assumed. Trap 9's
	# lesson in one line: when a value is generated in code, read back what the
	# engine got rather than what the call said.
	print("measure: surfaces=%d  %s" % [_crusts.size(), _uniforms()])
	# Which wearer's pattern this is. Printed rather than assumed, trap 9's lesson:
	# a run whose offset was not the one asked for is a run compared against the
	# wrong picture, and nothing else in the output would say so.
	print("measure: noise_offset=%s" % str(_crusts[0].get_shader_parameter(&"noise_offset")))
	print("measure: feet_y=%.3f  height=%.3f  band_top=%.3fm" % [
		player.global_position.y, float(_legs.call("_subject_height")),
		float(_legs.call("wade_fraction")) * float(_legs.call("_subject_height"))])
	print("measure: zone=%d px  crust=%d px  COVERAGE=%.1f%%" % [
		zone_pixels, crust_pixels, covered])
	print("measure: outside the zone=%d px   noise floor=%d px" % [stray, noise])
	# WHERE THE BAND ACTUALLY LANDED, against where it was asked to. The camera is
	# asked to project the walker's soles and the top of the band it was given, so
	# the two are in the frame's own pixels; the zone's bounding box is measured in
	# the same pixels. A band that renders shorter than it was told to is a fault in
	# the mask, and no amount of tuning the noise would ever have found it.
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var feet := player.global_position
		var asked := float(_legs.call("wade_fraction")) * float(_legs.call("_subject_height"))
		# BRIEFING TRAP 10. unproject_position answers in the 2D canvas rect, which
		# under this project's `canvas_items` stretch is NOT the size of the PNG the
		# mask was counted in. Reading the two against each other unconverted made
		# the walker's soles land 46 px below the bottom of a frame he is standing
		# in the middle of.
		var canvas := get_viewport().get_visible_rect().size
		var to_png := float(bare.get_height()) / maxf(canvas.y, 1.0)
		var sole_px := camera.unproject_position(feet).y * to_png
		var top_px := camera.unproject_position(feet + Vector3(0.0, asked, 0.0)).y * to_png
		var box := _rows(zone_mask, bare.get_width(), bare.get_height(), 0)
		var solid := _rows(zone_mask, bare.get_width(), bare.get_height(), 8)
		var scale_px := absf(sole_px - top_px) / maxf(asked, 0.0001)
		print("measure: the zone's rows run %d..%d, and %d..%d if a row of eight is required" % [
			int(box.x), int(box.y), int(solid.x), int(solid.y)])
		print("measure: canvas %dx%d, frame %dx%d, so canvas px x %.4f" % [
			int(canvas.x), int(canvas.y), bare.get_width(), bare.get_height(), to_png])
		print("measure: soles at y=%.1f px, %.2fm above them is y=%.1f px (%.1f px/m)" % [
			sole_px, asked, top_px, scale_px])
		# WHAT THE BAND IS IN METRES, off the picture. The bottom row is the lowest
		# of him the camera can see -- lower than his origin only if he is standing
		# on the snow rather than in it -- so both ends are quoted against the soles.
		print("measure: the band runs %.3fm .. %.3fm above his soles (asked 0 .. %.3fm)" % [
			(sole_px - float(solid.y)) / maxf(scale_px, 0.0001),
			(sole_px - float(solid.x)) / maxf(scale_px, 0.0001), asked])
	get_tree().quit()


## Puts a crossing on the legs without walking one.
##
## Reaches past the node's own accessors deliberately: `_load` and `_wade_line_m`
## are only ever set by a footfall, which is the design, and a measurement that
## had to walk a real drift would be measuring the walk as well as the crust.
## The model that produces these two numbers has its own tests; this file is
## about what the shader does with them.
func _wear(carried: float, settled: float, wade: float) -> void:
	_legs.set("_load", carried)
	_legs.set("_settle", settled)
	_legs.set("_wade_line_m", wade)
	for crust in _crusts:
		crust.set_shader_parameter(&"load", carried)
		crust.set_shader_parameter(&"settle", settled)
	# One paused tick, so the node's own _process() writes the rest of the pair.
	await get_tree().process_frame


func _uniforms() -> String:
	var said := ""
	for key in ["load", "wade_line", "boot_line", "figure_height", "origin_y",
			"patch_scale", "patch_contrast", "patch_scatter", "crease_bias"]:
		var value = _crusts[0].get_shader_parameter(StringName(key))
		said += "%s=%s " % [key, "unset" if value == null else "%.4f" % float(value)]
	return said


func _shot(tag: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	if tag != "floor":
		var error := image.save_png("%s-%s.png" % [_out, tag])
		if error != OK:
			push_error("measure_crust_coverage: could not write %s" % tag)
	return image


## Pixels that moved, as a flat bool array. The threshold is well clear of both
## dithering and 8-bit rounding, and well under the near-white-on-navy step the
## crust actually makes.
const MOVED := 14


func _mask(before: Image, after: Image) -> PackedByteArray:
	var a := before.get_data()
	var b := after.get_data()
	var moved := PackedByteArray()
	moved.resize(a.size() / 4)
	for index in range(moved.size()):
		var at := index * 4
		var difference := absi(int(a[at]) - int(b[at]))
		difference = maxi(difference, absi(int(a[at + 1]) - int(b[at + 1])))
		difference = maxi(difference, absi(int(a[at + 2]) - int(b[at + 2])))
		moved[index] = 1 if difference >= MOVED else 0
	return moved


func _count(before: Image, after: Image) -> int:
	var moved := _mask(before, after)
	var total := 0
	for value in moved:
		total += value
	return total


## The first and last rows a mask occupies, ignoring rows holding fewer than
## `least` pixels. A bounding box is decided by its single worst outlier, and one
## stray pixel of anti-aliasing on a mitten reported a boot-high band as
## chest-high; a row count says where the mask actually IS.
static func _rows(mask: PackedByteArray, width: int, height: int, least: int) -> Vector2i:
	var first := -1
	var last := -1
	for y in range(height):
		var count := 0
		var at := y * width
		for x in range(width):
			count += mask[at + x]
		if count <= least:
			continue
		if first < 0:
			first = y
		last = y
	return Vector2i(first, last)


## The exact rectangle a mask occupies, in frame pixels.
static func _bounds_raw(mask: PackedByteArray, width: int, height: int) -> Rect2i:
	var left := width
	var right := 0
	var top := height
	var bottom := 0
	for index in range(mask.size()):
		if mask[index] == 0:
			continue
		var x := index % width
		var y := index / width
		left = mini(left, x)
		right = maxi(right, x)
		top = mini(top, y)
		bottom = maxi(bottom, y)
	if right < left:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


## The rectangle the zone occupies, grown by half its own height so the crust is
## seen against the leg it is on rather than cut out of it.
static func _bounds(mask: PackedByteArray, width: int, height: int) -> Rect2i:
	var left := width
	var right := 0
	var top := height
	var bottom := 0
	for index in range(mask.size()):
		if mask[index] == 0:
			continue
		var x := index % width
		var y := index / width
		left = mini(left, x)
		right = maxi(right, x)
		top = mini(top, y)
		bottom = maxi(bottom, y)
	if right < left:
		return Rect2i(0, 0, width, height)
	var pad := int(maxf(24.0, float(bottom - top) * 0.75))
	left = maxi(0, left - pad)
	top = maxi(0, top - pad * 2)
	right = mini(width - 1, right + pad)
	bottom = mini(height - 1, bottom + pad)
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


func _zoom(image: Image, around: Rect2i, tag: String) -> void:
	var region := image.get_region(around)
	region.resize(region.get_width() * 3, region.get_height() * 3, Image.INTERPOLATE_NEAREST)
	var error := region.save_png("%s-%s-zoom.png" % [_out, tag])
	if error != OK:
		push_error("measure_crust_coverage: could not write the %s close-up" % tag)


## The picture of the measurement, so the number can be checked against what it
## claims to have counted: the zone in one colour, the crust inside it in
## another, over the walker as he actually renders.
func _paint(bare: Image, zone: PackedByteArray, crust: PackedByteArray) -> void:
	var painted := Image.create(bare.get_width(), bare.get_height(), false, Image.FORMAT_RGBA8)
	painted.copy_from(bare)
	for index in range(zone.size()):
		if zone[index] == 0 and crust[index] == 0:
			continue
		var x := index % bare.get_width()
		var y := index / bare.get_width()
		var tint := Color(1.0, 0.25, 0.15) if zone[index] == 1 else Color(1.0, 0.9, 0.1)
		if crust[index] == 1 and zone[index] == 1:
			tint = Color(0.1, 1.0, 0.35)
		painted.set_pixel(x, y, painted.get_pixel(x, y).lerp(tint, 0.75))
	var error := painted.save_png("%s-mask.png" % _out)
	if error != OK:
		push_error("measure_crust_coverage: could not write the mask")
