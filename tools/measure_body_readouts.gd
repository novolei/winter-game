extends Node

## What is actually in the takes the body readouts want to use, measured off the
## skeleton rather than read off the names.
##
##   Godot_console.exe --path <project> res://tools/measure_body_readouts.tscn \
##       --headless -- [--takes] [--limp] [--hands] [--posture]
##
## Written because a take's name is the supplier's intent and not its contents
## (briefing trap 15). `Limping_Walk_inplace` was imported as `walk_limp` and had
## never been played; before anything was wired to it, the question "does it
## limp" had to be answered by a number. The answer was no, and the take now
## ships under the name it earned, `walk_guarded`.
##
## ---------------------------------------------------------------------------
## AND THE RENAME BROKE THIS TOOL FOR SEVEN WEEKS OF NOTHING SAYING SO
## ---------------------------------------------------------------------------
## Every clip list below is a literal, and every loop over one begins
## `if not _player.has_animation(clip): continue`. When 9e7a6db renamed the take,
## the lists kept saying `walk_limp`, the guard kept finding nothing, and the
## guarded walk silently dropped out of every table this file prints. Two later
## tasks read those tables. A row that is ABSENT reads as a take that was not
## interesting rather than as a measurement that never ran.
##
## The lists are now the shipping names. If a take is named here and missing from
## the library that is worth a line on the console, not a silent skip -- see
## _missing().
##
## A LIMP IS AN ASYMMETRY, so that is what is measured. In a sound walk the two
## feet trace the same curve half a cycle apart, so the left trace against the
## right trace shifted by half a cycle correlates near 1. A limp breaks that:
## one foot lifts less, or stays down longer, or the hip drops onto one side.
## Anything that only looked at "does the skeleton move" would pass a second
## copy of the ordinary walk.

const MODEL_PATH := "res://assets/models/characters/winter_wanderer.glb"

## 100 Hz over the clip, which resolves a 0.6 s cycle into 60 points.
const SAMPLE_HZ := 100.0

var _skeleton: Skeleton3D = null
var _player: AnimationPlayer = null
var _model: Node3D = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var all := args.is_empty()
	_build()
	if _skeleton == null or _player == null:
		push_error("measure_body_readouts: no skeleton or no AnimationPlayer")
		get_tree().quit(1)
		return
	if all or args.has("--takes"):
		_report_takes()
	if all or args.has("--limp"):
		_report_gait_symmetry()
	if all or args.has("--hands"):
		_report_hands()
	if all or args.has("--posture"):
		_report_posture()
	if all or args.has("--cycle"):
		_report_cycles()
	if all or args.has("--stride"):
		_report_strides()
	get_tree().quit()


func _build() -> void:
	var scene := ResourceLoader.load(MODEL_PATH) as PackedScene
	_model = scene.instantiate() as Node3D
	add_child(_model)
	_player = _first(_model, "AnimationPlayer") as AnimationPlayer
	_skeleton = _first(_model, "Skeleton3D") as Skeleton3D
	if _player == null:
		return
	if _player.has_animation_library(&""):
		_player.remove_animation_library(&"")
	_player.add_animation_library(&"", WandererAnimations.build())
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func _first(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var found := _first(child, type)
		if found != null:
			return found
	return null


## Whether a clip this file asks for is absent -- and SAYS SO when it is.
##
## The silent `continue` this replaces is what let a renamed take vanish out of
## six tables at once with a clean console (see the header). A tool that measures
## takes by name has to treat a name it cannot resolve as news, because the
## output of a measurement that never ran looks exactly like the output of a
## measurement whose subject was uninteresting.
func _missing(clip: String) -> bool:
	if _player.has_animation(clip):
		return false
	print("  (%s: NOT IN THE LIBRARY -- this row was not measured, it was skipped)" % clip)
	return true


# --- what is in the library ---------------------------------------------------

func _report_takes() -> void:
	print("--- the library ---")
	var names := _player.get_animation_list()
	print("%d takes" % names.size())
	for name in names:
		var animation := _player.get_animation(name)
		print("  %-22s %7.4f s  tracks %3d  loop %s" % [
			name, animation.length, animation.get_track_count(),
			"linear" if animation.loop_mode == Animation.LOOP_LINEAR else "none",
		])
	print("--- bones (%d) ---" % _skeleton.get_bone_count())
	var bones := PackedStringArray()
	for index in range(_skeleton.get_bone_count()):
		bones.append(_skeleton.get_bone_name(index))
	print("  " + ", ".join(bones))


# --- is it a limp -------------------------------------------------------------

## Samples one bone's world-ish position (skeleton space) across a whole clip.
func _trace(clip: StringName, bone: String) -> Array:
	var index := _skeleton.find_bone(bone)
	if index < 0:
		return []
	var animation := _player.get_animation(clip)
	var count := int(animation.length * SAMPLE_HZ)
	var out: Array = []
	for step in range(count):
		_player.play(clip)
		_player.seek(float(step) / SAMPLE_HZ, true)
		_player.advance(0.0)
		out.append(_skeleton.get_bone_global_pose(index).origin)
	return out


func _heights(trace: Array) -> Array[float]:
	var out: Array[float] = []
	for point in trace:
		out.append((point as Vector3).y)
	return out


func _span(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var low := INF
	var high := -INF
	for v in values:
		low = minf(low, v)
		high = maxf(high, v)
	return high - low


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


## Pearson correlation of `a` against `b` rotated by `shift` samples.
func _correlate(a: Array[float], b: Array[float], shift: int) -> float:
	var count: int = mini(a.size(), b.size())
	if count < 4:
		return 0.0
	var mean_a := _mean(a)
	var mean_b := _mean(b)
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in range(count):
		var x := a[i] - mean_a
		var y := b[(i + shift) % count] - mean_b
		num += x * y
		da += x * x
		db += y * y
	if da <= 0.0 or db <= 0.0:
		return 0.0
	return num / sqrt(da * db)


## Fraction of the cycle a foot spends within `band` metres of its own floor --
## its stance. A limp shortens the stance on the bad leg.
func _stance_share(values: Array[float], band := 0.02) -> float:
	if values.is_empty():
		return 0.0
	var low := INF
	for v in values:
		low = minf(low, v)
	var down := 0
	for v in values:
		if v <= low + band:
			down += 1
	return float(down) / float(values.size())


func _report_gait_symmetry() -> void:
	print("--- gait symmetry: a limp is an asymmetry ---")
	print("%-14s %8s %8s %8s %8s %8s %8s %8s" % [
		"take", "L lift", "R lift", "ratio", "L stance", "R stance", "mirror r", "hip dip",
	])
	for clip in ["walk", "run", "walk_guarded", "walk_weary", "walk_carry"]:
		if _missing(clip):
			continue
		var left := _heights(_trace(clip, "LeftFoot"))
		var right := _heights(_trace(clip, "RightFoot"))
		var hips := _heights(_trace(clip, "Hips"))
		if left.is_empty() or right.is_empty():
			continue
		var lift_l := _span(left)
		var lift_r := _span(right)
		var half: int = left.size() / 2
		print("%-14s %8.4f %8.4f %8.3f %8.3f %8.3f %8.3f %8.4f" % [
			clip, lift_l, lift_r,
			minf(lift_l, lift_r) / maxf(maxf(lift_l, lift_r), 0.0001),
			_stance_share(left), _stance_share(right),
			_correlate(left, right, half),
			_span(hips),
		])


# --- what one cycle inside a long take looks like -----------------------------

## The lag at which a trace best repeats itself. A take four times a walk cycle
## long is four cycles, or one cycle and dead air, and the two are not the same
## asset -- see briefing trap 15, where a take imported carrying five seconds of
## preceding timeline played it as silence before the motion.
func _period_of(values: Array[float], dt: float) -> float:
	if values.size() < 20:
		return 0.0
	var mean := _mean(values)
	var best := -INF
	var best_lag := 0
	for lag in range(10, values.size() / 2):
		var score := 0.0
		for i in range(values.size() - lag):
			score += (values[i] - mean) * (values[i + lag] - mean)
		score /= float(values.size() - lag)
		if score > best:
			best = score
			best_lag = lag
	return float(best_lag) * dt


func _report_cycles() -> void:
	var dt := 1.0 / SAMPLE_HZ
	for clip in ["walk", "walk_guarded", "walk_weary"]:
		if _missing(clip):
			continue
		var left := _heights(_trace(clip, "LeftFoot"))
		var right := _heights(_trace(clip, "RightFoot"))
		var length: float = _player.get_animation(clip).length
		var period := _period_of(left, dt)
		print("--- %s: %.4f s, foot cycle %.4f s (%.2f cycles in the take) ---" % [
			clip, length, period, length / maxf(period, 0.0001),
		])
		# The traces themselves, 40 columns across the whole take, so dead air and
		# a change of behaviour partway through are both visible as a shape.
		_print_trace("  L foot", left, 40)
		_print_trace("  R foot", right, 40)
		# ...and symmetry measured inside ONE cycle rather than across the take.
		var count: int = mini(int(period * SAMPLE_HZ), left.size())
		if count < 8:
			continue
		var one_l: Array[float] = []
		var one_r: Array[float] = []
		for i in range(count):
			one_l.append(left[i])
			one_r.append(right[i])
		print("  within one cycle: L lift %.4f  R lift %.4f  ratio %.3f  mirror r %.3f" % [
			_span(one_l), _span(one_r),
			minf(_span(one_l), _span(one_r)) / maxf(maxf(_span(one_l), _span(one_r)), 0.0001),
			_correlate(one_l, one_r, count / 2),
		])


## A trace as a row of digits 0..9 scaled to its own range: shape without a plot.
func _print_trace(label: String, values: Array[float], columns: int) -> void:
	if values.is_empty():
		return
	var low := INF
	var high := -INF
	for v in values:
		low = minf(low, v)
		high = maxf(high, v)
	var span := maxf(high - low, 0.0001)
	var row := ""
	for column in range(columns):
		var index := int(float(column) / float(columns) * float(values.size()))
		row += str(clampi(int((values[index] - low) / span * 9.0), 0, 9))
	print("%s [%s]  %.3f .. %.3f" % [label, row, low, high])


# --- how far a cycle carries him ----------------------------------------------

## Metres of ground per gait cycle, off the root's own translation.
##
## This is the number `pace` is computed against -- PlayerController drives the
## clips in STRIDES, not in speeds -- so a take whose cycle covers less ground
## than the walk's must be played faster at the same ground speed or the feet
## skate. Guessing it from the clip's length is exactly the mistake briefing
## trap "不要用动画片段的长度去决定一个物理时长" is about.
func _report_strides() -> void:
	print("--- ground covered per cycle (metres, after the 1.88 m body scale) ---")
	print("%-14s %9s %9s %9s %10s" % ["take", "cycle s", "cm/cycle", "m/cycle", "m/s at r1"])
	# PlayerController scales the model so it stands 1.88 m; the rig is authored
	# in centimetres, so the same factor converts these traces to metres.
	var scale := 1.88 / _standing_height()
	var cycles := {
		"walk": 1.0667, "run": 0.6667, "walk_guarded": 1.1889,
		"walk_weary": 1.4500, "walk_carry": 1.1333,
	}
	print("(every take is IN PLACE -- root travel is under half a centimetre per")
	print(" cycle -- so the ground speed that plants the feet is the rate the")
	print(" STANCE foot slides backwards under the hips, not any excursion)")
	print("%-14s %11s %11s" % ["take", "slip rig/s", "m/s vs walk"])
	var reference := 0.0
	var rows: Array = []
	for clip in ["walk", "run", "walk_guarded", "walk_weary", "walk_carry"]:
		if _missing(clip):
			continue
		var cycle: float = cycles.get(clip, 1.0)
		var hips := _trace(clip, "Hips")
		var slip := maxf(
			_stance_slip(_trace(clip, "LeftFoot"), hips, cycle),
			_stance_slip(_trace(clip, "RightFoot"), hips, cycle)
		)
		if clip == "walk":
			reference = slip
		rows.append([clip, slip])
	for row in rows:
		print("%-14s %11.3f %11.4f" % [
			row[0], row[1], 1.35 * float(row[1]) / maxf(reference, 0.0001),
		])
	print("(calibrated against anim_walk_speed = 1.35, which is itself the speed")
	print(" at which the WALK's feet plant -- so these are relative statements)")
	print("(scale factor from the body height would have been %.4f)" % scale)


## How fast the stance foot slides backwards under the hips, in rig units per
## second. During stance the foot is planted on the ground, so in world terms it
## is the body that moves: the foot's backward speed relative to the hips IS the
## ground speed the clip was authored for.
##
## Measured on the samples where the foot sits in the lowest tenth of its own
## height range -- its stance -- and reported as the median step, so one frame of
## interpolation overshoot cannot set the number.
func _stance_slip(foot: Array, hips: Array, cycle: float) -> float:
	var samples: int = mini(int(cycle * SAMPLE_HZ), mini(foot.size(), hips.size()))
	if samples < 8:
		return 0.0
	var heights: Array[float] = []
	for i in range(samples):
		heights.append((foot[i] as Vector3).y)
	var low := INF
	var high := -INF
	for h in heights:
		low = minf(low, h)
		high = maxf(high, h)
	var gate := low + (high - low) * 0.10
	var steps: Array[float] = []
	for i in range(samples - 1):
		if heights[i] > gate or heights[i + 1] > gate:
			continue
		var a: Vector3 = (foot[i] as Vector3) - (hips[i] as Vector3)
		var b: Vector3 = (foot[i + 1] as Vector3) - (hips[i + 1] as Vector3)
		steps.append(Vector2(b.x - a.x, b.z - a.z).length() * SAMPLE_HZ)
	if steps.is_empty():
		return 0.0
	steps.sort()
	return steps[steps.size() / 2]


## The model's own height in rig units, so the centimetre rig can be converted.
func _standing_height() -> float:
	var box := AABB()
	var first := true
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var here: AABB = (node as MeshInstance3D).get_aabb()
		box = here if first else box.merge(here)
		first = false
	return maxf(box.size.y, 0.0001)


# --- where the hands are ------------------------------------------------------

## Hand position relative to the hips, in the skeleton's own frame. Positive Y is
## up the body, positive Z is out in front (the model faces +Z).
func _hand_offset(clip: StringName, bone: String, at: float) -> Vector3:
	var index := _skeleton.find_bone(bone)
	var hips := _skeleton.find_bone("Hips")
	if index < 0 or hips < 0:
		return Vector3.ZERO
	_player.play(clip)
	_player.seek(at, true)
	_player.advance(0.0)
	var hand := _skeleton.get_bone_global_pose(index).origin
	var root := _skeleton.get_bone_global_pose(hips).origin
	return hand - root


func _report_hands() -> void:
	print("--- where the hands sit, relative to the hips (metres) ---")
	print("%-14s %6s  %-22s %-22s %8s" % ["take", "t", "left (x,y,z)", "right (x,y,z)", "|sep|"])
	for clip in ["idle", "idle_cold", "walk", "walk_guarded", "walk_weary"]:
		if _missing(clip):
			continue
		var length: float = _player.get_animation(clip).length
		for fraction in [0.0, 0.25, 0.5, 0.75]:
			var at: float = length * fraction
			var left := _hand_offset(clip, "LeftHand", at)
			var right := _hand_offset(clip, "RightHand", at)
			print("%-14s %6.2f  %-22s %-22s %8.4f" % [
				clip, at,
				"%+.3f %+.3f %+.3f" % [left.x, left.y, left.z],
				"%+.3f %+.3f %+.3f" % [right.x, right.y, right.z],
				(left - right).length(),
			])


# --- how tall he stands -------------------------------------------------------

## Head height and forward lean, which is what separates a posture from a tremor.
func _report_posture() -> void:
	print("--- posture: head height and lean ---")
	print("%-14s %9s %9s %9s" % ["take", "head y", "head z", "hips y"])
	for clip in ["idle", "idle_cold", "walk", "walk_guarded", "walk_weary"]:
		if _missing(clip):
			continue
		var length: float = _player.get_animation(clip).length
		var head := _skeleton.find_bone("Head")
		var hips := _skeleton.find_bone("Hips")
		var head_y := 0.0
		var head_z := 0.0
		var hips_y := 0.0
		var count := 8
		for step in range(count):
			_player.play(clip)
			_player.seek(length * float(step) / float(count), true)
			_player.advance(0.0)
			var h := _skeleton.get_bone_global_pose(head).origin
			head_y += h.y
			head_z += h.z
			hips_y += _skeleton.get_bone_global_pose(hips).origin.y
		print("%-14s %9.4f %9.4f %9.4f" % [
			clip, head_y / count, head_z / count, hips_y / count,
		])
