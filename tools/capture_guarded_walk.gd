extends Node

## Is the guarded walk a reading a player can take? Asked in the pixels he gets.
##
##   Godot_console.exe --path <project> res://tools/capture_guarded_walk.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/gait [--mode gait|pairs|probe]
##
##   gait   The measurement. Steps the PHASE of one gait cycle and photographs
##          the ordinary walk, the guarded walk and the weary walk at every rung,
##          then compares them at every relative shift.
##   pairs  The crowding check. Running against walking against the guarded walk,
##          which are 疲劳's whole reading and 冻伤足's whole reading standing next
##          to each other.
##   stand  The SAME instrument turned on the two shipped standing readouts, so
##          the gait's numbers can be read against something. 861bccb and 4784f59
##          both measured the stand with the animation PINNED at one instant,
##          which makes their noise floor zero by construction -- and a player
##          never sees a pinned instant. This mode steps the standing branch's own
##          clock and reports what the idle moves by itself.
##   ceiling  Can ANY bilateral gait in this library clear the bar, or is the
##          camera the limit? Every walk-shaped take in the library is put through
##          the guarded slot -- each on its OWN measured cycle count, derived here
##          rather than read off a table -- and scored against the same healthy
##          walk. This is the mode that answers "say whether it can".
##   probe  What the AnimationTree exposes and whether swapping a clip under a
##          live AnimationNodeAnimation moves its phase. Run this before trusting
##          either of the other two.
##
## ---------------------------------------------------------------------------
## WHY THE PHASE AND NOT THE BLEND -- THE OPPOSITE OF THE STANDING LADDERS
## ---------------------------------------------------------------------------
## tools/capture_stand_ladder.gd and tools/capture_hunch_ladder.gd both step the
## BLEND at one instant, because a stand is one pose and stepping time through it
## shows nothing. A WALK is the other case. Its silhouette is in violent motion
## by design, and two frames of the same healthy walk taken at different moments
## differ more than a healthy walk differs from a hurt one.
##
## That failure has already been shipped on this project once. The living-light
## proposal measured a body posture in a cast shadow, found `freezing` moved
## 181.4% of the silhouette, and then measured its own control: two frames of the
## SAME posture 430 frames apart moved 95.3%. Everything above that floor was the
## idle animation running, and the author said so and withdrew the claim.
##
## So this harness pins the phase and reports the floor, both:
##
##   * every clip is put on ONE shared cycle by the shipping graph's own rate
##     nodes, so a fraction of that cycle is the same fraction of every take's
##     own stride; the tree is advanced by exactly cycle/PHASES per rung.
##   * the comparison is minimised over the relative SHIFT between two takes,
##     because two clips authored by different hands do not start at the same
##     point of the stride, and comparing left-foot-forward against
##     right-foot-forward is a measurement of the phase error and not of the gait.
##   * the walk is photographed TWICE, once in each sweep, at the same phases.
##     Those two rows must be pixel-identical. That is the instrument's own zero
##     and it is printed rather than assumed.
##
## Apparatus otherwise lifted wholesale from tools/capture_hunch_ladder.gd, so
## the numbers land in the same table as the 934 px / 11.1% the frostbitten hands
## measure, the 1092 px / 12.7% the hunger stand measures and the 896 px / 10.4%
## the cold stand measures. A second measuring tool would have made four numbers
## nobody can put in one column.
##
## The footprint is measured against a PLATE -- one frame with the man hidden --
## rather than against a luminance threshold, for the reason capture_stand_ladder
## records: he is cel-shaded, so a threshold returns a dither of the shade band
## and the difference between two rungs is then dominated by interior speckle.

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")
const SurvivalSystemScript := preload("res://src/systems/survival_system.gd")

## Rungs around ONE gait cycle. Sixteen resolves the relative shift between two
## takes to a sixteenth of a stride, which is finer than the difference between
## adjacent frames at the rate the game plays these clips.
const PHASES := 16

## How many gait cycles are inside each take, MEASURED with
## tools/measure_body_readouts.gd --cycle and re-derived there rather than read
## off the clip's length:
##
##     walk           1.0667 s   1 cycle
##     walk_guarded   3.5667 s   3 cycles (foot autocorrelation 1.200 s)
##     walk_weary     8.7000 s   6 cycles (foot autocorrelation 1.460 s)
##
## Briefing: 不要用动画片段的长度去决定一个物理时长. A take's length is what the
## exporter happened to write out; its cycle is what the motion does.
const CYCLES := {"walk_guarded": 3, "walk_weary": 6}

## Every take in the library shaped like a walk, for `--mode ceiling`.
##
## Not a shortlist of things anybody proposes shipping -- `crouch_creep` reads as
## sneaking and `walk_carry` has a spear in it. They are here because the question
## is whether the GAIT BRANCH can carry an absolute reading at all, and the way to
## answer that is to hand it the most extreme silhouettes the library owns and see
## whether even those clear. A ceiling nobody wants to ship still tells the owner
## what a take he exports next would have to do.
const CEILING: Array = [
	"walk_guarded", "walk_weary", "walk_carry", "walk_balance",
	"crouch_creep", "crouch_walk_forward", "run_alt",
]

## Samples used to find how many gait cycles are inside a take. Divisible by
## 1..6, 8, 10 and 12, so an integer cycle count lands on an exact sample.
const CYCLE_SAMPLES := 120

## [label, gait blend, footing blend] for the gait sweep. `footing` 1.0 is
## whichever clip is in the guarded slot for that sweep.
##
## THREE rows and not two, because the shipped readout has two tiers and only one
## of them is a reading a player can act on. `footing_target()` remaps
## frostbite_feet's authored 0.5 and 0.2 onto [GUARDED_WALK_FLOOR, 1], which puts
## them at 0.80 and 1.00. The second tier is a man whose feet are gone; the FIRST
## is the one that arrives while he can still turn back, and measuring only the
## maximum would report the readout at a strength the player mostly never sees.
const GAIT_VARIANTS: Array = [["walk", 0.0, 0.0], ["tier1", 0.0, 0.80], ["hurt", 0.0, 1.0]]

## ...and for the crowding check. A tired man's whole visible reading is that he
## is walking where a rested man runs; a frostbitten man's is the guarded walk.
## Both are on this one branch of the graph, which is why they are photographed
## together.
const PAIR_VARIANTS: Array = [["running", 1.0, 0.0], ["walking", 0.0, 0.0], ["guarded", 0.0, 1.0]]

## [label, chill, hunch] for the standing sweep -- the two readouts 861bccb and
## the cold stand already ship, re-measured with the idle RUNNING.
const STAND_VARIANTS: Array = [
	["fed", PlayerControllerScript.IDLE_CHILL_FLOOR, 0.0],
	["cold", 1.0, 0.0],
	["hungry", PlayerControllerScript.IDLE_CHILL_FLOOR, 1.0],
]

## How long a window of standing the stand sweep covers, in seconds.
##
## The standing branch is NOT retimed the way the locomotion branch is -- `chill`
## and `hunch` blend a 14.000 s idle, a 3.000 s shiver and a 1.700 s hunch with no
## rate node between them -- so there is no shared cycle to step and no "phase" to
## pin. What there is instead is a WINDOW: three seconds is one whole loop of the
## shiver, and it is about as long as a player looks at a man before deciding
## whether anything is wrong with him.
const STAND_WINDOW := 3.0

const SETTLE_FRAMES := 90
const CROP := Vector2i(120, 150)
const ZOOM := 3
const JND := 2.0 / 255.0
const PLATE_EPS := 2.0 / 255.0

var _out := "user://gait"
var _mode := "gait"
var _player: PlayerController = null
var _body = null
var _camera: Camera3D = null
var _tree: AnimationTree = null
var _clips: AnimationPlayer = null
var _shared := 0.6667
var _frames := 0
var _done := false
var _plate: Image = null
## label -> Array[Image] of PHASES crops, and label -> Array[PackedByteArray].
var _rows: Dictionary = {}
var _row_masks: Dictionary = {}
## The same masks with everything at or below the hip line cleared -- see _bands().
var _row_upper: Dictionary = {}
var _order: Array[String] = []
var _centre := Vector2i.ZERO
var _width := 0
var _height := 0
var _hip_row := 0
## Screen pixels per world metre of height at the player's distance, measured off
## the camera rather than assumed. Everything a gait does is a distance in
## centimetres, and this is the only number that turns one into a reading.
var _px_per_m := 0.0
## label -> Array[Vector2] of PHASES entries, each [left foot, right foot] height
## above his own root in metres. Read off the live skeleton at the same instant
## the frame was captured.
var _row_feet: Dictionary = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--out" and index + 1 < args.size():
			_out = args[index + 1]
		elif args[index] == "--mode" and index + 1 < args.size():
			_mode = args[index + 1]
	_player = get_node_or_null("Main/Player") as PlayerController
	if _player == null:
		push_error("capture_guarded_walk: scenes/main.tscn has no Player")
		get_tree().quit(1)
		return
	_body = SurvivalSystemScript.new()
	_body.load_from_directory()
	_body.start()
	_player.set_survival_system(_body)


func _exit_tree() -> void:
	if _body != null:
		_body.free()


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	_done = true
	_run()


func _run() -> void:
	_pin_camera()
	_freeze()
	if _tree == null:
		push_error("capture_guarded_walk: the player has no Gait AnimationTree")
		get_tree().quit(1)
		return
	_clips = _tree.get_node_or_null(_tree.anim_player) as AnimationPlayer
	_shared = _length_of(WandererAnimations.RUN)
	if _mode == "probe":
		_probe()
		get_tree().quit()
		return
	# This node keeps running while everything else stops. Without it the wind,
	# the snow field and the sky advance between rungs, and the plate difference
	# then holds pixels that are not the man -- two frames that are not of the
	# same shot, which is the briefing's own condition for a capture being
	# evidence.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_locate()
	await _take_plate()
	_neutral()
	if _mode == "stand":
		await _sweep_stand()
	elif _mode == "ceiling":
		await _sweep_ceiling()
	elif _mode == "pairs":
		await _sweep("walk_guarded", PAIR_VARIANTS, "")
	else:
		# The ordinary walk is photographed in BOTH sweeps, at the same phases,
		# and the two rows must come back identical. That is this harness's own
		# zero and it is printed rather than assumed.
		await _sweep("walk_guarded", GAIT_VARIANTS, "guarded")
		await _sweep("walk_weary", GAIT_VARIANTS, "weary")
	_measure()
	_write()
	get_tree().quit()


func _pin_camera() -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null:
		return
	rig.call("snap_to_target")
	# Stopped, not merely snapped: the rig eases toward its target every frame
	# and a frame that drifts between rungs is not the same shot.
	rig.set_process(false)
	rig.set_physics_process(false)
	_camera = rig.get_node_or_null("Camera3D") as Camera3D


func _freeze() -> void:
	_player.set_physics_process(false)
	_player.set_process(false)
	_tree = _player.get_node_or_null("Gait") as AnimationTree
	if _tree != null:
		_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_hush(get_tree().root)


func _hush(node: Node) -> void:
	if node is GPUParticles3D:
		var gpu := node as GPUParticles3D
		gpu.emitting = false
		gpu.speed_scale = 0.0
		gpu.visible = false
	elif node is CPUParticles3D:
		var cpu := node as CPUParticles3D
		cpu.emitting = false
		cpu.speed_scale = 0.0
		cpu.visible = false
	for child in node.get_children():
		_hush(child)


func _length_of(clip: StringName) -> float:
	if _clips == null or not _clips.has_animation(clip):
		push_error("capture_guarded_walk: the library holds no take called %s" % clip)
		return 1.0
	return maxf(_clips.get_animation(clip).length, 0.0001)


## Everything on this body that is not the gait, put where a warm fed man has it,
## so the sweep measures the walk and not some other readout leaking in.
func _neutral() -> void:
	_tree.set(&"parameters/motion/blend_amount", 1.0)
	_tree.set(&"parameters/pace/scale", 1.0)
	_tree.set(&"parameters/chill/blend_amount", PlayerControllerScript.IDLE_CHILL_FLOOR)
	_tree.set(&"parameters/hunch/blend_amount", 0.0)


## ---------------------------------------------------------------------------
## THE PHASE IS PINNED HERE, AND THIS IS THE WHOLE INSTRUMENT
## ---------------------------------------------------------------------------
## `pace` is held at 1.0, so one advance of `_shared` seconds is exactly one
## shared cycle; each clip's own rate node then carries that onto one whole cycle
## of that clip. Stepping `_shared / PHASES` therefore steps every take by the
## same FRACTION OF ITS OWN STRIDE, which is the only sense in which two takes of
## different length can be at "the same" moment.
##
## Every Blend2 in this graph is synced, so both inputs advance whatever the
## weight is -- which is why one sweep can photograph two variants at one instant
## by writing a blend value and advancing by ZERO between them.
##
## The settle advance at the top is not decoration: swapping the clip under a
## live AnimationNodeAnimation may or may not carry its playback position across,
## and `--mode probe` prints which. Advancing one whole shared cycle before the
## first rung puts the take at a defined phase either way.
func _sweep(clip: String, variants: Array, suffix: String, cycles := 0) -> void:
	var graph := _tree.tree_root as AnimationNodeBlendTree
	var slot := graph.get_node("walk_guarded") as AnimationNodeAnimation
	slot.animation = StringName(clip)
	var count: int = cycles if cycles > 0 else int(CYCLES.get(clip, 1))
	var period := _length_of(StringName(clip)) / maxf(float(count), 1.0)
	_tree.set(&"parameters/guarded_rate/scale", period / maxf(_shared, 0.0001))
	print("capture_guarded_walk: %s -- take %.4f s / %d cycles = %.4f s, rate %.4f on the %.4f s shared cycle"
		% [clip, _length_of(StringName(clip)), count, period,
			period / maxf(_shared, 0.0001), _shared])
	_tree.advance(_shared)
	for row in variants:
		var label: String = String(row[0]) + suffix
		if not _rows.has(label):
			_rows[label] = []
			_row_feet[label] = []
			_order.append(label)
	# ...and the claim that the phase IS pinned, checked against what the engine
	# says rather than against the arithmetic that was supposed to produce it.
	# Every clip's own position is read at every rung and reported as a fraction
	# of its own cycle; those two columns must step by 1/PHASES together.
	var walk_phase := PackedStringArray()
	var slot_phase := PackedStringArray()
	for rung in range(PHASES):
		for row in variants:
			var label: String = String(row[0]) + suffix
			_tree.set(&"parameters/gait/blend_amount", float(row[1]))
			_tree.set(&"parameters/footing/blend_amount", float(row[2]))
			# Zero, so nothing advances: the same instant, the same clips, one
			# float different.
			_tree.advance(0.0)
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			(_rows[label] as Array).append(_crop(image))
			(_row_feet[label] as Array).append(_feet())
		walk_phase.append("%.3f" % fposmod(
			float(_tree.get("parameters/walk/current_position")) / _length_of(WandererAnimations.WALK),
			1.0
		))
		slot_phase.append("%.3f" % fposmod(
			float(_tree.get("parameters/walk_guarded/current_position")) / maxf(period, 0.0001),
			1.0
		))
		_tree.advance(_shared / float(PHASES))
	print("  walk phase within its own cycle: " + " ".join(walk_phase))
	print("  %s phase within its own cycle: %s" % [clip, " ".join(slot_phase)])


## The standing branch, stepped through STAND_WINDOW seconds of its own clock.
##
## `motion` goes to 0 so the locomotion branch contributes nothing, and the two
## readouts already shipped are photographed at every step alongside the fed warm
## figure. What comes out is the number 861bccb could not produce: how much of
## his outline the idle moves ON ITS OWN, which is the floor those readouts have
## to clear and which nobody had measured.
func _sweep_stand() -> void:
	_tree.set(&"parameters/motion/blend_amount", 0.0)
	for row in STAND_VARIANTS:
		var label: String = String(row[0])
		_rows[label] = []
		_order.append(label)
	print("capture_guarded_walk: standing, %.2f s in %d steps of %.4f s"
		% [STAND_WINDOW, PHASES, STAND_WINDOW / float(PHASES)])
	for step in range(PHASES):
		for row in STAND_VARIANTS:
			_tree.set(&"parameters/chill/blend_amount", float(row[1]))
			_tree.set(&"parameters/hunch/blend_amount", float(row[2]))
			_tree.advance(0.0)
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			(_rows[String(row[0])] as Array).append(_crop(image))
		_tree.advance(STAND_WINDOW / float(PHASES))


## How many gait cycles are inside a take, MEASURED off the motion rather than
## read off the clip's length.
##
## Briefing: 不要用动画片段的长度去决定一个物理时长 -- a take's length is what the
## exporter happened to write out. walk_guarded is 3.5667 s of THREE strides and
## walk_weary 8.7 s of SIX, and dropping either onto the graph as though its
## length were its period photographs a man vibrating.
##
## A looping gait of `c` cycles repeats every CYCLE_SAMPLES/c samples, so the
## count is the LARGEST c whose half-open residue is small -- larger c means a
## shorter period, and a six-cycle clip also "repeats" at three and at two.
func _cycles_in(clip: String) -> int:
	var graph := _tree.tree_root as AnimationNodeBlendTree
	var slot := graph.get_node("walk_guarded") as AnimationNodeAnimation
	slot.animation = StringName(clip)
	var whole := _length_of(StringName(clip))
	_tree.set(&"parameters/guarded_rate/scale", whole / maxf(_shared, 0.0001))
	_tree.set(&"parameters/gait/blend_amount", 0.0)
	_tree.set(&"parameters/footing/blend_amount", 1.0)
	_tree.advance(whole)
	var trace: Array[float] = []
	for sample in range(CYCLE_SAMPLES):
		_tree.advance(_shared / float(CYCLE_SAMPLES))
		trace.append(_feet().x)
	var swing: float = trace.max() - trace.min()
	var best := 1
	for count in range(8, 0, -1):
		if CYCLE_SAMPLES % count != 0:
			continue
		var step: int = CYCLE_SAMPLES / count
		var residue := 0.0
		for k in range(CYCLE_SAMPLES):
			residue += absf(trace[k] - trace[(k + step) % CYCLE_SAMPLES])
		residue /= float(CYCLE_SAMPLES)
		if residue < 0.15 * maxf(swing, 0.0001):
			best = count
			break
	print("  %-22s %7.4f s / %d cycles = %.4f s   (foot swing %.1f cm)"
		% [clip, whole, best, whole / float(best), swing * 100.0])
	return best


## Each candidate take through the guarded slot, on its own measured cycle, at
## footing 1.0 -- the most that take can ever say. The healthy walk is row 0 and
## is the reference every ratio is taken against.
func _sweep_ceiling() -> void:
	print("capture_guarded_walk: cycle counts, measured off the foot trace ---")
	var counts: Dictionary = {}
	for clip in CEILING:
		counts[clip] = _cycles_in(String(clip))
	print("")
	for index in range(CEILING.size()):
		var clip: String = String(CEILING[index])
		# The healthy walk is photographed in the FIRST sweep only. At footing 0
		# the guarded slot contributes nothing, so it would come back identical in
		# every sweep -- which `--mode gait` proves rather than assumes, at 0.0 px.
		var variants: Array = [["walk", 0.0, 0.0]] if index == 0 else []
		variants.append([clip, 0.0, 1.0])
		await _sweep(clip, variants, "", int(counts[clip]))


func _report_stand() -> void:
	print("")
	print("--- the standing readouts, with the idle RUNNING ---")
	print("861bccb and 4784f59 both measured these with the tree advanced by ZERO,")
	print("which makes the floor zero by construction. A player never sees that.")
	var area := _mean_area("fed")
	var total := 0.0
	var worst := 0.0
	for shift in range(1, PHASES):
		var here := _shifted("fed", "fed", shift)
		total += here
		worst = maxf(worst, here)
	print("  the fed warm stand's OWN motion over %.1f s: one step apart %.0f px (%.1f%%),"
		% [STAND_WINDOW, _shifted("fed", "fed", 1),
			100.0 * _shifted("fed", "fed", 1) / maxf(area, 1.0)])
	print("    mean %.0f px (%.1f%%), largest %.0f px (%.1f%%)"
		% [total / float(PHASES - 1), 100.0 * (total / float(PHASES - 1)) / maxf(area, 1.0),
			worst, 100.0 * worst / maxf(area, 1.0)])
	print("")
	print("%-14s %10s %8s %12s %12s" % [
		"readout", "same-step", "of foot", "nearest worst", "nearest best",
	])
	for label in _order:
		if label == "fed":
			continue
		var near := _nearest("fed", label)
		print("%-14s %10.0f %7.1f%% %12.0f %12.0f" % [
			label, _shifted("fed", label, 0),
			100.0 * _shifted("fed", label, 0) / maxf(area, 1.0),
			float(near[0]), float(near[1]),
		])
	print("")
	print("  cold against hungry: %.0f px" % _shifted("cold", "hungry", 0))
	print("")
	print("`nearest best` is the frame of that readout which comes CLOSEST to some")
	print("frame of a fed warm man. If it is at or below the floor above, that frame")
	print("is a fed man as far as anyone looking at him is concerned.")


func _locate() -> void:
	# Briefing trap 10: unproject_position() answers in the 1152x720 stretch
	# canvas while the saved PNG is the 1600x1000 window, and cropping at the raw
	# value lands 215 px away from the man and measures his shadow.
	var canvas := get_viewport().get_visible_rect().size
	var shot := Vector2(DisplayServer.window_get_size())
	var at := _camera.unproject_position(_player.global_position + Vector3(0.0, 0.9, 0.0))
	_centre = Vector2i(at * Vector2(shot.x / maxf(canvas.x, 1.0), shot.y / maxf(canvas.y, 1.0)))
	var top := _camera.unproject_position(_player.global_position + Vector3(0.0, 1.88, 0.0))
	var foot := _camera.unproject_position(_player.global_position)
	var scale: float = shot.y / maxf(canvas.y, 1.0)
	_px_per_m = absf(top.y - foot.y) * scale / 1.88
	print("capture_guarded_walk: window %s; a 1.88 m man projects %.1f px, %.1f%% of the frame" % [
		DisplayServer.window_get_size(), absf(top.y - foot.y) * scale,
		100.0 * absf(top.y - foot.y) * scale / maxf(shot.y, 1.0),
	])
	print("capture_guarded_walk: %.1f px per world metre of height at his distance." % _px_per_m)
	# The hip line, in the crop's own rows. Everything the cast shadow puts on the
	# screen lies below it at this sun and this camera -- the shadow runs down and
	# away from his boots -- so an upper band cut here is the man's arms, torso and
	# head and nothing else. See _bands().
	var hip := _camera.unproject_position(_player.global_position + Vector3(0.0, 0.95, 0.0))
	_hip_row = int(hip.y * scale) - clampi(
		_centre.y - CROP.y, 0, maxi(int(shot.y) - CROP.y * 2, 0)
	)
	print("capture_guarded_walk: the hip line falls on crop row %d of %d" % [_hip_row, CROP.y * 2])


func _take_plate() -> void:
	_player.visible = false
	await RenderingServer.frame_post_draw
	var plate := get_viewport().get_texture().get_image()
	plate.convert(Image.FORMAT_RGBA8)
	_plate = _crop(plate)
	_player.visible = true


func _crop(image: Image) -> Image:
	var size := image.get_size()
	var rect := Rect2i(
		clampi(_centre.x - CROP.x, 0, maxi(size.x - CROP.x * 2, 0)),
		clampi(_centre.y - CROP.y, 0, maxi(size.y - CROP.y * 2, 0)),
		mini(CROP.x * 2, size.x), mini(CROP.y * 2, size.y)
	)
	var out := Image.create_empty(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(image, rect, Vector2i.ZERO)
	return out


## The widest channel's difference. Max rather than mean: a shift confined to one
## channel is still visible, and averaging across three divides it by three and
## calls it invisible.
func _apart(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


func _mask(image: Image) -> PackedByteArray:
	var out := PackedByteArray()
	var w := image.get_width()
	out.resize(w * image.get_height())
	for y in range(image.get_height()):
		for x in range(w):
			out[y * w + x] = 1 if _apart(
				image.get_pixel(x, y), _plate.get_pixel(x, y)
			) > PLATE_EPS else 0
	return out


func _area(mask: PackedByteArray) -> int:
	var count := 0
	for i in range(mask.size()):
		if mask[i] == 1:
			count += 1
	return count


func _xor(a: PackedByteArray, b: PackedByteArray) -> int:
	var count := 0
	for i in range(a.size()):
		if a[i] != b[i]:
			count += 1
	return count


## ---------------------------------------------------------------------------
## WHY THE SILHOUETTE IS CUT AT THE HIPS, AND WHY THAT IS THE WHOLE QUESTION
## ---------------------------------------------------------------------------
## A walking man's outline is two different signals stacked on top of each other,
## and a single XOR adds them and loses both:
##
##   BELOW the hips -- the legs and the cast shadow. This moves enormously with
##   the phase of the stride and it is what sets the noise floor. Its difference
##   between two takes is confounded by where in the stride each one is.
##
##   ABOVE the hips -- the arms, the torso, the head. In an ordinary walk the
##   arms swing, but they swing about a carriage; a guarded walk moves the
##   CARRIAGE. That difference is there at every phase, so it survives not
##   knowing which moment you are looking at, and it is the kind of difference a
##   viewer can take from a single frame with no second man in it.
##
## So both bands are reported. If the reading lives above the hips, it is
## absolute; if it lives below them, it is a difference between two moments and
## the player has to have been watching.
func _bands(mask: PackedByteArray) -> PackedByteArray:
	var out := mask.duplicate()
	var start: int = clampi(_hip_row, 0, _height) * _width
	for i in range(start, out.size()):
		out[i] = 0
	return out


func _measure() -> void:
	_width = (_rows[_order[0]] as Array)[0].get_width()
	_height = (_rows[_order[0]] as Array)[0].get_height()
	for label in _order:
		var masks: Array = []
		var upper: Array = []
		for crop in (_rows[label] as Array):
			var mask := _mask(crop)
			masks.append(mask)
			upper.append(_bands(mask))
		_row_masks[label] = masks
		_row_upper[label] = upper
	print("")
	print("--- footprints, per rung of the cycle (px inside the plate difference) ---")
	print("%-10s %8s %8s %8s" % ["row", "mean", "min", "max"])
	for label in _order:
		var areas: Array[int] = []
		for mask in (_row_masks[label] as Array):
			areas.append(_area(mask))
		var total := 0
		var low := 1 << 30
		var high := 0
		for a in areas:
			total += a
			low = mini(low, a)
			high = maxi(high, a)
		print("%-10s %8.0f %8d %8d" % [label, float(total) / float(areas.size()), low, high])
	if _mode == "stand":
		_report_stand()
	elif _mode == "ceiling":
		_report_ratio("walk")
	elif _mode == "pairs":
		_report_pairs()
	else:
		_report_gait()


## Mean XOR across the whole cycle when `b` is read `shift` rungs later than `a`.
func _shifted(a: String, b: String, shift: int, band := false) -> float:
	var source := _row_upper if band else _row_masks
	var left: Array = source[a]
	var right: Array = source[b]
	var total := 0
	for k in range(PHASES):
		total += _xor(left[k], right[(k + shift) % PHASES])
	return float(total) / float(PHASES)


func _mean_area(label: String, band := false) -> float:
	var source := _row_upper if band else _row_masks
	var total := 0
	for mask in (source[label] as Array):
		total += _area(mask)
	return float(total) / float(PHASES)


## The best relative alignment of two rows, and what separates them there.
## Returns [shift, mean xor px, worst rung px, best rung px].
func _aligned(a: String, b: String, band := false) -> Array:
	var best := INF
	var best_shift := 0
	for shift in range(PHASES):
		var here := _shifted(a, b, shift, band)
		if here < best:
			best = here
			best_shift = shift
	var source := _row_upper if band else _row_masks
	var left: Array = source[a]
	var right: Array = source[b]
	var low := 1 << 30
	var high := 0
	for k in range(PHASES):
		var here := _xor(left[k], right[(k + best_shift) % PHASES])
		low = mini(low, here)
		high = maxi(high, here)
	return [best_shift, best, high, low]


## ---------------------------------------------------------------------------
## THE QUESTION A SHIFT CURVE CANNOT ASK: is any frame of this MISTAKABLE?
## ---------------------------------------------------------------------------
## A mean over the cycle can hide a reading that is present at some moments and
## absent at others, and "absent at some moments" is fatal for a gait -- a player
## glancing at his man catches one moment, not a mean.
##
## So: for every rung of `b`, the distance to the CLOSEST rung of `a`, whatever
## its phase. If the largest of those is still big, no frame of `b` resembles any
## frame of `a` and the reading is in every frame. If the smallest is near the
## healthy walk's own sampling floor, that frame of `b` is a frame of `a` as far
## as a viewer is concerned.
##
## Returns [worst-case nearest px, best-case nearest px, mean nearest px].
func _nearest(a: String, b: String, band := false) -> Array:
	var source := _row_upper if band else _row_masks
	var left: Array = source[a]
	var right: Array = source[b]
	var low := INF
	var high := 0.0
	var total := 0.0
	for k in range(PHASES):
		var nearest := 1 << 30
		for j in range(PHASES):
			nearest = mini(nearest, _xor(right[k], left[j]))
		low = minf(low, float(nearest))
		high = maxf(high, float(nearest))
		total += float(nearest)
	return [high, low, total / float(PHASES)]


func _print_shift_curve(a: String, b: String) -> void:
	var line := PackedStringArray()
	for shift in range(PHASES):
		line.append("%d:%.0f" % [shift, _shifted(a, b, shift)])
	print("    " + "  ".join(line))


func _report_gait() -> void:
	print("")
	print("--- the instrument's own zero ---")
	print("The ordinary walk was photographed in both sweeps at the same phases.")
	var zero := _shifted("walk" + "guarded", "walk" + "weary", 0)
	print("  walkguarded against walkweary, rung for rung: %.1f px mean" % zero)
	print("")
	print("--- THE NOISE FLOOR: what the walk's own motion moves, unpinned ---")
	print("Every rung of the healthy walk against every other. Shift 0 is the same")
	print("rung twice and must be zero; everything else is the gait being a gait.")
	_print_shift_curve("walkguarded", "walkguarded")
	var walk_area := _mean_area("walkguarded")
	var floor_min := INF
	var floor_max := 0.0
	var floor_total := 0.0
	for shift in range(1, PHASES):
		var here := _shifted("walkguarded", "walkguarded", shift)
		floor_min = minf(floor_min, here)
		floor_max = maxf(floor_max, here)
		floor_total += here
	print("  one rung apart (1/%d of a stride): %.0f px, %.1f%% of his footprint"
		% [PHASES, _shifted("walkguarded", "walkguarded", 1),
			100.0 * _shifted("walkguarded", "walkguarded", 1) / maxf(walk_area, 1.0)])
	print("  smallest non-zero %.0f px (%.1f%%) | mean %.0f px (%.1f%%) | largest %.0f px (%.1f%%)"
		% [floor_min, 100.0 * floor_min / maxf(walk_area, 1.0),
			floor_total / float(PHASES - 1),
			100.0 * (floor_total / float(PHASES - 1)) / maxf(walk_area, 1.0),
			floor_max, 100.0 * floor_max / maxf(walk_area, 1.0)])
	print("")
	print("--- THE SIGNAL: each hurt walk against the healthy one, phase-aligned ---")
	print("%-22s %6s %10s %8s %10s %10s" % [
		"pair", "shift", "mean px", "of foot", "worst rung", "best rung",
	])
	for row in [["walkguarded", "tier1guarded", "guarded, tier 1 (0.80)"],
			["walkguarded", "hurtguarded", "guarded, tier 2 (1.00)"],
			["walkweary", "tier1weary", "weary, tier 1 (0.80)"],
			["walkweary", "hurtweary", "weary, tier 2 (1.00)"]]:
		var out := _aligned(String(row[0]), String(row[1]))
		print("%-22s %6d %10.0f %7.1f%% %10d %10d" % [
			String(row[2]), int(out[0]), float(out[1]),
			100.0 * float(out[1]) / maxf(walk_area, 1.0), int(out[2]), int(out[3]),
		])
		_print_shift_curve(String(row[0]), String(row[1]))
	print("")
	print("--- and the two hurt walks against each other ---")
	var both := _aligned("hurtguarded", "hurtweary")
	print("  guarded against weary: shift %d, %.0f px, %.1f%% of the guarded footprint"
		% [int(both[0]), float(both[1]),
			100.0 * float(both[1]) / maxf(_mean_area("hurtguarded"), 1.0)])
	print("")
	print("--- IS ANY FRAME MISTAKABLE? nearest healthy frame, whatever its phase ---")
	print("A rung of the healthy walk's nearest OTHER rung is this harness's sampling")
	print("floor: one sixteenth of a stride is %.0f px, so nothing can measure below it."
		% _shifted("walkguarded", "walkguarded", 1))
	print("%-26s %10s %10s %10s" % ["row", "worst px", "best px", "mean px"])
	for row in [["walkguarded", "tier1guarded", "guarded, tier 1 (0.80)"],
			["walkguarded", "hurtguarded", "guarded, tier 2 (1.00)"],
			["walkweary", "tier1weary", "weary, tier 1 (0.80)"],
			["walkweary", "hurtweary", "weary, tier 2 (1.00)"]]:
		var near := _nearest(String(row[0]), String(row[1]))
		print("%-26s %10.0f %10.0f %10.0f" % [
			String(row[2]), float(near[0]), float(near[1]), float(near[2]),
		])
	print("")
	print("--- THE SAME QUESTION ABOVE THE HIPS, WHERE A CARRIAGE LIVES ---")
	print("Legs and cast shadow removed. This band is what a viewer can read without")
	print("knowing which moment of the stride he is looking at.")
	var upper_area := _mean_area("walkguarded", true)
	print("  the healthy walk's upper band: %.0f px of footprint" % upper_area)
	var band_floor_min := INF
	var band_floor_max := 0.0
	var band_total := 0.0
	for shift in range(1, PHASES):
		var here := _shifted("walkguarded", "walkguarded", shift, true)
		band_floor_min = minf(band_floor_min, here)
		band_floor_max = maxf(band_floor_max, here)
		band_total += here
	print("  ITS OWN motion (the arms swinging): one rung apart %.0f px (%.1f%%),"
		% [_shifted("walkguarded", "walkguarded", 1, true),
			100.0 * _shifted("walkguarded", "walkguarded", 1, true) / maxf(upper_area, 1.0)])
	print("    mean %.0f px (%.1f%%), largest %.0f px (%.1f%%)"
		% [band_total / float(PHASES - 1),
			100.0 * (band_total / float(PHASES - 1)) / maxf(upper_area, 1.0),
			band_floor_max, 100.0 * band_floor_max / maxf(upper_area, 1.0)])
	print("%-26s %6s %10s %8s %10s %10s" % [
		"pair (upper band)", "shift", "mean px", "of band", "worst near", "best near",
	])
	for row in [["walkguarded", "tier1guarded", "guarded, tier 1 (0.80)"],
			["walkguarded", "hurtguarded", "guarded, tier 2 (1.00)"],
			["walkweary", "tier1weary", "weary, tier 1 (0.80)"],
			["walkweary", "hurtweary", "weary, tier 2 (1.00)"]]:
		var out := _aligned(String(row[0]), String(row[1]), true)
		var near := _nearest(String(row[0]), String(row[1]), true)
		print("%-26s %6d %10.0f %7.1f%% %10.0f %10.0f" % [
			String(row[2]), int(out[0]), float(out[1]),
			100.0 * float(out[1]) / maxf(upper_area, 1.0), float(near[0]), float(near[1]),
		])
	print("")
	print("For the same camera and the same metric, elsewhere on this body:")
	print("  the cold stand      896 px   10.4% of footprint")
	print("  the ruined hands    934 px   11.1%")
	print("  the hunger hunch   1092 px   12.7%")
	print("  疲劳's stand           0 px    0.0%  (it has none)")
	print("...but those three were measured with the idle PINNED, so their floor is")
	print("zero by construction. `--mode stand` re-measures them with it running.")
	_report_lift()
	_report_asymmetry()
	_report_pace()


## What each take has to be played at to keep its feet on the ground, across the
## speeds this game's terrain actually hands the player.
##
## The take's authored ground speed is the rate its stance foot slides backwards
## under the hips (every take here is in place), measured in
## tools/measure_body_readouts.gd --stride and calibrated against
## anim_walk_speed = 1.35. A playback rate is a HONESTY question, not a
## legibility one, and it is the reason Injured_Walk was rejected -- so it is
## printed beside the legibility numbers rather than in another document.
func _report_pace() -> void:
	print("")
	print("--- and the pace each take needs, which is the other half of the question ---")
	var authored := {"walk": 1.350, "walk_guarded": 0.924, "walk_weary": 0.523}
	var speeds: Array[float] = [
		_player.walk_speed * _player.deep_snow_factor,
		0.60, 0.80, 1.00, _player.walk_speed,
	]
	print("%-14s %9s %s" % ["take", "authored", "playback multiple at ground speed (m/s)"])
	var header := PackedStringArray()
	for speed in speeds:
		header.append("%8.2f" % speed)
	print("%-14s %9s %s" % ["", "", " ".join(header)])
	for clip in ["walk", "walk_guarded", "walk_weary"]:
		var line := PackedStringArray()
		for speed in speeds:
			line.append("%8.2fx" % (speed / float(authored[clip])))
		print("%-14s %8.3f  %s" % [clip, float(authored[clip]), " ".join(line)])
	print("(the leftmost column is walk_speed x deep_snow_factor -- a cold start in")
	print(" the deepest snow, which is the slowest the ruling ever lets him move)")


## Topmost set row of a mask -- how high his head sits in the frame.
##
## Safe to take off the whole mask rather than the upper band: at this sun and
## this camera the cast shadow runs down and away from his boots, which is the
## same fact _bands() relies on and _locate() prints the hip row for.
func _crown(mask: PackedByteArray) -> int:
	for y in range(_height):
		var base := y * _width
		for x in range(_width):
			if mask[base + x] == 1:
				return y
	return _height


## ---------------------------------------------------------------------------
## THE PHYSICAL CLAIM, IN THE ONLY UNIT THAT ANSWERS THE QUESTION
## ---------------------------------------------------------------------------
## Every claim ever made for these two takes is a DISTANCE. The guarded walk's
## feet "lift 40% less"; Injured_Walk has "one foot that barely leaves the
## ground", 8.51 cm against 2.02. Both were measured and both are true.
##
## Neither has ever been stated in PIXELS, and pixels is what the player is
## handed. This project has already shipped one readout that failed for exactly
## that reason -- the frostbitten hands move 9 cm, which is about five pixels on
## a man 110 px tall, and the report saying so had to be written after the work.
##
## So: measured live off the skeleton at the same instants the frames were taken,
## in centimetres, and then converted at the camera's own measured scale.
func _report_lift() -> void:
	print("")
	print("--- what the feet actually do, in cm and then in pixels ---")
	print("%-14s %9s %9s %7s %9s %9s" % [
		"row", "left cm", "right cm", "ratio", "left px", "right px",
	])
	for label in _order:
		var entries: Array = _row_feet[label]
		if entries.is_empty():
			continue
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for entry in entries:
			var at: Vector2 = entry
			low = Vector2(minf(low.x, at.x), minf(low.y, at.y))
			high = Vector2(maxf(high.x, at.x), maxf(high.y, at.y))
		var lift := high - low
		print("%-14s %9.2f %9.2f %7.3f %9.1f %9.1f" % [
			label, lift.x * 100.0, lift.y * 100.0,
			minf(lift.x, lift.y) / maxf(maxf(lift.x, lift.y), 0.0001),
			lift.x * _px_per_m, lift.y * _px_per_m,
		])
	print("  (`ratio` is the smaller foot's lift over the larger: 1.0 is bilateral,")
	print("   and it is the number that says whether a take limps at all.)")


## ---------------------------------------------------------------------------
## IS THE LIMP THERE IN PIXELS? THE TEST THAT NEEDS NO SECOND MAN
## ---------------------------------------------------------------------------
## Everything above compares a hurt walk against a healthy one, and that is a
## RELATIVE reading -- it needs the reference frame the real game does not
## contain. It is the same instrument that condemned 饥饿's pace, and if the
## guarded walk only passes there it has the same disease.
##
## The brief's premise is that a limp escapes this, because an asymmetry is
## ABSOLUTE: a viewer knows without being told that a man's two steps should
## match. That premise has never been tested and it is testable.
##
## A symmetric gait says everything about itself twice per stride -- the left
## half and the right half are the same sentence with the feet swapped -- so any
## scalar read off the silhouette comes back with period 1/2 stride. A limp does
## not: its halves differ, and the trace acquires a fundamental at the FULL
## stride. So compare each rung with the rung half a cycle later, using one man
## and no reference gait at all.
##
## Two scalars, both things an eye tracks by itself: the footprint AREA, and the
## CROWN ROW -- how high his head sits, which is the bob a limp is famous for.
##
## The camera is three-quarter rear, so the near leg and the far leg do not
## project alike and even a perfectly symmetric gait leaves a residue. That
## residue is the floor, and the HEALTHY WALK is what measures it.
func _report_asymmetry() -> void:
	print("")
	print("--- HALF-CYCLE ASYMMETRY: one man, no reference gait ---")
	print("Each rung against the rung half a stride later. A bilateral gait repeats")
	print("itself every half stride and scores near the healthy walk's residue; a")
	print("limp does not. The healthy walk IS the floor, because this camera is")
	print("three-quarter rear and the two legs never project alike.")
	print("%-14s %12s %12s %10s %12s %12s" % [
		"row", "area half", "area p-p", "share", "crown half", "crown p-p",
	])
	var half: int = PHASES / 2
	for label in _order:
		var areas: Array[float] = []
		var crowns: Array[float] = []
		for mask in (_row_masks[label] as Array):
			areas.append(float(_area(mask)))
			crowns.append(float(_crown(mask)))
		var area_half := 0.0
		var crown_half := 0.0
		for k in range(PHASES):
			area_half += absf(areas[k] - areas[(k + half) % PHASES])
			crown_half += absf(crowns[k] - crowns[(k + half) % PHASES])
		area_half /= float(PHASES)
		crown_half /= float(PHASES)
		var area_pp: float = areas.max() - areas.min()
		var crown_pp: float = crowns.max() - crowns.min()
		print("%-14s %11.0f %12.0f %9.1f%% %11.2f %12.0f" % [
			label, area_half, area_pp,
			100.0 * area_half / maxf(area_pp, 1.0), crown_half, crown_pp,
		])
	print("  (`share` is the half-cycle difference as a fraction of the whole swing.")
	print("   Crown columns are in ROWS of the frame -- i.e. in screen pixels.)")


func _report_pairs() -> void:
	print("")
	print("--- 疲劳 and 冻伤足 on one branch: every pair, phase-aligned ---")
	print("%-12s %-12s %6s %10s %9s" % ["a", "b", "shift", "mean px", "of a"])
	for i in range(_order.size()):
		for j in range(i + 1, _order.size()):
			var out := _aligned(_order[i], _order[j])
			print("%-12s %-12s %6d %10.0f %8.1f%%" % [
				_order[i], _order[j], int(out[0]), float(out[1]),
				100.0 * float(out[1]) / maxf(_mean_area(_order[i]), 1.0),
			])
	print("")
	print("--- and the walk's own motion, as the floor all three sit on ---")
	for label in _order:
		var total := 0.0
		var worst := 0.0
		for shift in range(1, PHASES):
			var here := _shifted(label, label, shift)
			total += here
			worst = maxf(worst, here)
		print("  %-12s mean rung-against-rung %.0f px (%.1f%% of its own footprint), largest %.0f px"
			% [label, total / float(PHASES - 1),
				100.0 * (total / float(PHASES - 1)) / maxf(_mean_area(label), 1.0), worst])
	_report_ratio("walking")


## ---------------------------------------------------------------------------
## THE CONTROL THAT CALIBRATES EVERY OTHER NUMBER IN THIS FILE
## ---------------------------------------------------------------------------
## `--mode gait` scores the guarded walk against a floor and the score is bad.
## Before believing that, the SCALE has to be checked against something nobody
## disputes -- otherwise a test that fails everything has proved nothing.
##
## The control is 疲劳: a tired man WALKS where a rested man RUNS. That is the
## largest change this branch of the graph can make to a silhouette, it is a
## difference every player can name, and it is 疲劳's entire visible expression.
## If walking-instead-of-running does not clear the bar, the bar is wrong. If it
## clears comfortably, the bar is calibrated and the guarded walk is simply quiet.
##
## The statistic is the one a glancing player is actually subject to:
##
##     ratio = (the hurt gait's MOST MISTAKABLE frame's distance to the nearest
##              healthy frame) / (the largest distance between two HEALTHY frames)
##
## At or above 1.0, no frame of the hurt gait is as close to a healthy frame as
## two healthy frames get to each other, so the reading survives not knowing which
## moment of the stride you caught. Below 1.0 there is a moment where the hurt man
## is, to a viewer with no reference, a healthy man at another point of his step.
func _report_ratio(base: String) -> void:
	print("")
	print("--- THE RATIO: most-mistakable frame over the healthy gait's own churn ---")
	print("`best` is a MINIMUM over 256 frame pairs and it jitters with where the 16")
	print("rungs happen to land; `mean` is the average over the cycle and is stable to")
	print("about a percent. Both are printed because the verdict should not rest on the")
	print("noisier one -- re-sampled at different rungs, one `best` here moved 38%.")
	for band in [false, true]:
		var worst := 0.0
		var floor_mean := 0.0
		for shift in range(1, PHASES):
			var here := _shifted(base, base, shift, band)
			worst = maxf(worst, here)
			floor_mean += here
		floor_mean /= float(PHASES - 1)
		print("")
		print("  %s -- `%s` differs from ITSELF by up to %.0f px (mean %.0f)" % [
			"upper band" if band else "whole silhouette", base, worst, floor_mean,
		])
		print("  %-22s %9s %7s %9s %7s   %s" % [
			"take", "best px", "ratio", "mean px", "ratio", "verdict",
		])
		for label in _order:
			if label == base:
				continue
			var near := _nearest(base, label, band)
			print("  %-22s %9.0f %7.2f %9.0f %7.2f   %s" % [
				label, float(near[1]), float(near[1]) / maxf(worst, 1.0),
				float(near[2]), float(near[2]) / maxf(floor_mean, 1.0),
				"READS" if float(near[1]) >= worst else "does not read",
			])


## ---------------------------------------------------------------------------
## What the tree actually exposes, and whether a clip swap keeps its phase
## ---------------------------------------------------------------------------
## Briefing trap 9 ends on the habit this is: when you drive a resource from
## code, print what the engine produced and read it, rather than writing the
## expected behaviour from memory. The `_sweep()` settle advance exists because
## of what this prints.
func _probe() -> void:
	print("--- parameters the live tree exposes ---")
	for entry in _tree.get_property_list():
		var name: String = entry.get("name", "")
		if name.begins_with("parameters/"):
			print("  %-46s = %s" % [name, str(_tree.get(name))])
	print("")
	print("--- does swapping the clip under a live AnimationNodeAnimation keep its phase? ---")
	var graph := _tree.tree_root as AnimationNodeBlendTree
	var slot := graph.get_node("walk_guarded") as AnimationNodeAnimation
	_neutral()
	_tree.set(&"parameters/footing/blend_amount", 1.0)
	_tree.set(&"parameters/gait/blend_amount", 0.0)
	_tree.advance(_shared * 0.37)
	var before := _foot_gap()
	print("  guarded, 0.37 of a cycle in: foot gap %.4f m" % before)
	slot.animation = &"walk_weary"
	_tree.set(&"parameters/guarded_rate/scale",
		(_length_of(&"walk_weary") / 6.0) / maxf(_shared, 0.0001))
	_tree.advance(0.0)
	print("  swapped to walk_weary, advance(0):  foot gap %.4f m" % _foot_gap())
	slot.animation = &"walk_guarded"
	_tree.set(&"parameters/guarded_rate/scale",
		(_length_of(&"walk_guarded") / 3.0) / maxf(_shared, 0.0001))
	_tree.advance(0.0)
	var after := _foot_gap()
	print("  swapped back, advance(0):           foot gap %.4f m  (drift %.4f)"
		% [after, absf(after - before)])
	print("")
	print("  A drift of zero means the swap carried the position and a sweep could")
	print("  interleave clips. Anything else means each clip needs its own sweep,")
	print("  which is what _sweep() does.")


## Both feet's height above his own root, in METRES, off the live skeleton at the
## instant the frame was taken.
##
## Not off get_bone_global_pose() alone. Briefing trap 15.3: these characters
## measure about 1/100 of life size in the skeleton's own space, which is why
## _foot_gap() below prints "37 m" between a walking man's boots and why a scale
## gate written naively against get_aabb() fires on every correct model in this
## project. Multiplying through the skeleton's global transform puts the bone
## back in the world, where a centimetre is a centimetre and _px_per_m can turn
## it into the only unit that answers the question.
func _feet() -> Vector2:
	var skeleton := _skeleton(_player)
	if skeleton == null:
		return Vector2.ZERO
	var left := skeleton.find_bone("LeftFoot")
	var right := skeleton.find_bone("RightFoot")
	if left < 0 or right < 0:
		push_error("capture_guarded_walk: the rig has no LeftFoot/RightFoot bone")
		return Vector2.ZERO
	var to_world := skeleton.global_transform
	var base := _player.global_position.y
	return Vector2(
		(to_world * skeleton.get_bone_global_pose(left).origin).y - base,
		(to_world * skeleton.get_bone_global_pose(right).origin).y - base
	)


## How far apart his feet are, which is a one-number read on where in the stride
## he is: near zero at mid-stance and at its widest at contact.
func _foot_gap() -> float:
	var skeleton := _skeleton(_player)
	if skeleton == null:
		return 0.0
	var left := skeleton.find_bone("LeftFoot")
	var right := skeleton.find_bone("RightFoot")
	if left < 0 or right < 0:
		return 0.0
	return (skeleton.get_bone_global_pose(left).origin
		- skeleton.get_bone_global_pose(right).origin).length()


func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _skeleton(child)
		if found != null:
			return found
	return null


## ---------------------------------------------------------------------------
## The sheets. One row per variant, one column per rung of the cycle.
## ---------------------------------------------------------------------------
## The 1:1 sheet is the one that answers the question. The 3x sheet draws the man
## three times the size the game ever does, and two agents on this project have
## already judged a readout from a magnified diagnostic view.
##
## The rows are laid out at the PHASE-ALIGNED shift, not rung for rung, because
## rung for rung is a picture of the phase error rather than of the gait.
func _write() -> void:
	var shifts := {}
	for label in _order:
		shifts[label] = 0
	if _mode == "gait":
		for pair in [["walkguarded", "tier1guarded"], ["walkguarded", "hurtguarded"],
				["walkweary", "tier1weary"], ["walkweary", "hurtweary"]]:
			shifts[pair[1]] = int(_aligned(String(pair[0]), String(pair[1]))[0])
	elif _mode == "pairs":
		for label in _order:
			if label != _order[0]:
				shifts[label] = int(_aligned(_order[0], label)[0])
	var columns := 8
	var step: int = maxi(PHASES / columns, 1)
	var gap := 6
	var rows := _order.size()
	var strip := Image.create_empty(
		(_width + gap) * columns - gap, (_height + gap) * rows - gap, false, Image.FORMAT_RGBA8
	)
	strip.fill(Color(1, 1, 1, 1))
	var sheet := Image.create_empty(
		((_width + gap) * columns - gap) * ZOOM, ((_height + gap) * rows - gap) * ZOOM,
		false, Image.FORMAT_RGBA8
	)
	sheet.fill(Color(1, 1, 1, 1))
	var masks := Image.create_empty(
		(_width + gap) * columns - gap, (_height + gap) * rows - gap, false, Image.FORMAT_RGBA8
	)
	masks.fill(Color(1, 1, 1, 1))
	for r in range(rows):
		var label: String = _order[r]
		var shift: int = shifts[label]
		for c in range(columns):
			var rung: int = (c * step + shift) % PHASES
			var crop: Image = (_rows[label] as Array)[rung]
			var at := Vector2i((_width + gap) * c, (_height + gap) * r)
			strip.blit_rect(crop, Rect2i(0, 0, _width, _height), at)
			var big := crop.duplicate()
			big.resize(_width * ZOOM, _height * ZOOM, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(big, Rect2i(0, 0, _width * ZOOM, _height * ZOOM), at * ZOOM)
			var flat := Image.create_empty(_width, _height, false, Image.FORMAT_RGBA8)
			var mask: PackedByteArray = (_row_masks[label] as Array)[rung]
			for y in range(_height):
				for x in range(_width):
					flat.set_pixel(x, y, Color.BLACK if mask[y * _width + x] == 1 else Color.WHITE)
			masks.blit_rect(flat, Rect2i(0, 0, _width, _height), at)
	strip.save_png("%s_%s_true_scale.png" % [_out, _mode])
	sheet.save_png("%s_%s_sheet.png" % [_out, _mode])
	masks.save_png("%s_%s_masks.png" % [_out, _mode])
	print("")
	print("wrote %s_%s_true_scale.png (1:1), _sheet.png (%dx), _masks.png" % [_out, _mode, ZOOM])
	print("rows, top to bottom: " + ", ".join(_order))
	print("columns step 1/%d of a gait cycle; each row is drawn at its own" % columns)
	print("phase-aligned shift, so a column is the same moment of the stride in every row.")
