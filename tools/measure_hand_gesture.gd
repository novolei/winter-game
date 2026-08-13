extends Node

## Does any take in any library contain a HELD hand-to-the-body gesture?
##
##   Godot_console.exe --path <project> res://tools/measure_hand_gesture.tscn \
##       --headless -- [--model res://path.glb] [--all] [--bones]
##
## ---------------------------------------------------------------------------
## THE FRAME IS BUILT FROM THE REST POSE, NOT ASSUMED
## ---------------------------------------------------------------------------
## The wanderer is a Y-up rig facing +Z with bones called Hips/LeftHand. The
## RPG-Character pack under assets/rigs/ is a 53-bone rig calling them
## B_Pelvis/B_L_Hand, and nothing guarantees it faces the same way. A sweep that
## hard-codes either is measuring one pack and lying about the other.
##
## So an anatomical basis is derived from each rig's own rest pose:
##
##   up       pelvis -> head
##   forward  foot -> toe, with the up component removed  (a toe is in front of
##            its own heel in every humanoid rig ever made, which is what makes
##            this unambiguous where a bone's local axes are not)
##   left     up x forward, sign fixed so the LEFT thigh has a positive x
##
## Hand offsets are reported in that basis, so "20 cm up and 15 cm in front of
## the hip joint" means the same sentence about every pack.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS, AND WHY IT IS A MEASUREMENT RATHER THAN A GREP
## ---------------------------------------------------------------------------
## 饥饿 has no single-frame reading. The one that would work is a hand to the
## stomach when he stops, and the wave 3 report says the 21-take library has no
## such gesture -- a claim made by reading names. This project has been burned
## three times by taking a filename as evidence of contents, most recently by
## `Limping_Walk_inplace`, which does not limp.
##
## So the question is asked of the skeleton. For every sample of every take:
##
##   HAND OFFSET, relative to the hips, in the skeleton's own frame:
##     x   across the body   (0 is the midline)
##     y   up the body       (0 is the hip joint)
##     z   in front of it    (the model faces +Z)
##
## A hand-to-stomach gesture is a hand that is
##
##   * near the midline           |x| small
##   * at belly height            y in the band between hip and sternum
##   * in front of the torso      z positive, and not merely hanging
##   * AND STAYS THERE            held across many consecutive samples
##
## That last clause is the one a naive search would drop, and it is the one that
## decides the question. A death take swings a hand across the belly on its way
## to the ground; a man clutching his stomach keeps it there. A gesture that is
## only ever passed through cannot be held at a stop, so `held` -- the longest
## RUN of consecutive qualifying samples -- is the column to read, not `best`.
##
## The bands are printed with the results so the verdict can be argued with.

## 60 Hz over the clip. Fine enough that a half-second hold is 30 samples and
## cannot be mistaken for interpolation passing through.
const SAMPLE_HZ := 60.0

## The stomach, in hip-relative CENTIMETRES on the 1.88 m body.
##
## The rig is authored in centimetres and the conversion is 1.0 -- see
## _metres_per_unit(), which measures it rather than assuming it.
##
## Read off the model rather than typed in: the wanderer's hip joint sits at the
## pelvis and the sternum 45 cm above it, so the belly is the lower two-thirds of
## that. The forward gate is 5 cm, which an arm hanging at the side cannot reach
## -- measured, the neutral idle's hands never pass z = 7.8 and spend the cycle
## near zero.
const BELLY_LOW := 0.0
const BELLY_HIGH := 30.0
const BELLY_ACROSS := 22.0
const BELLY_FORWARD := 5.0

## Degrees off vertical at which a torso counts as bent over. A man standing at
## ease still reads a few degrees -- the wanderer's own neutral idle is the
## calibration and it is printed with the results, so this is a number the table
## itself can be checked against rather than one taken on trust.
const HUNCH_DEGREES := 20.0

var _skeleton: Skeleton3D = null
var _player: AnimationPlayer = null
var _model: Node3D = null
var _model_path := WandererAnimations.MODEL_PATH
var _hips := -1
var _left := -1
var _right := -1
var _head := -1
var _foot := -1
var _toe := -1
var _thigh := -1
var _frame := Basis.IDENTITY


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--model" and index + 1 < args.size():
			_model_path = args[index + 1]
	if not ResourceLoader.exists(_model_path):
		print("measure_hand_gesture: no such model %s" % _model_path)
		get_tree().quit(1)
		return
	_build()
	if _skeleton == null or _player == null:
		print("measure_hand_gesture: %s has no skeleton or no AnimationPlayer" % _model_path)
		get_tree().quit(1)
		return
	if args.has("--bones"):
		_report_bones()
	_resolve_bones()
	if _hips < 0 or _left < 0 or _right < 0:
		print("measure_hand_gesture: %s has no Hips/LeftHand/RightHand" % _model_path)
		get_tree().quit(1)
		return
	_build_frame()
	_report()
	get_tree().quit()


func _build() -> void:
	var scene := ResourceLoader.load(_model_path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	add_child(_model)
	_player = _first(_model, "AnimationPlayer") as AnimationPlayer
	_skeleton = _first(_model, "Skeleton3D") as Skeleton3D
	if _player == null:
		return
	# The wanderer's takes are renamed on import by WandererAnimations; every other
	# model is read as it shipped, so a foreign library keeps its own names and a
	# name that needed trimming shows up as itself (briefing trap 15).
	if _model_path == WandererAnimations.MODEL_PATH:
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


func _report_bones() -> void:
	var names := PackedStringArray()
	for index in range(_skeleton.get_bone_count()):
		names.append(_skeleton.get_bone_name(index))
	print("--- %d bones ---" % names.size())
	print("  " + ", ".join(names))


## Tolerant of naming, because a foreign pack does not have to use the wanderer's
## bone names and the whole point of this sweep is to reach packs it did not
## write.
func _find(candidates: Array) -> int:
	for name in candidates:
		var index := _skeleton.find_bone(name)
		if index >= 0:
			return index
	# Second pass, case-insensitive and by substring, for rigs that prefix every
	# bone with the armature's name.
	for name in candidates:
		var needle := String(name).to_lower()
		for index in range(_skeleton.get_bone_count()):
			if _skeleton.get_bone_name(index).to_lower().ends_with(needle):
				return index
	return -1


func _resolve_bones() -> void:
	_hips = _find(["Hips", "mixamorig_Hips", "B_Pelvis", "pelvis", "Bip01_Pelvis"])
	_left = _find(["LeftHand", "mixamorig_LeftHand", "B_L_Hand", "hand_l", "Bip01_L_Hand"])
	_right = _find(["RightHand", "mixamorig_RightHand", "B_R_Hand", "hand_r", "Bip01_R_Hand"])
	_head = _find(["Head", "mixamorig_Head", "B_Head", "head"])
	_foot = _find(["LeftFoot", "mixamorig_LeftFoot", "B_L_Foot", "foot_l"])
	_toe = _find(["LeftToeBase", "mixamorig_LeftToeBase", "B_L_Toe0", "toe_l", "LeftToe"])
	_thigh = _find(["LeftUpLeg", "mixamorig_LeftUpLeg", "B_L_Thigh", "thigh_l"])


## The anatomical basis, off the rest pose. See the header.
##
## Falls back to the world axes only if a rig is missing the bones it is built
## from, and says so, because a silent fallback would report a foreign pack in
## the wanderer's frame and every number would look plausible.
func _build_frame() -> void:
	var have := _head >= 0 and _foot >= 0 and _toe >= 0 and _thigh >= 0
	if not have:
		print("measure_hand_gesture: WARNING -- missing head/foot/toe/thigh, "
			+ "falling back to world axes; offsets below are NOT anatomical")
		return
	var pelvis := _skeleton.get_bone_global_rest(_hips).origin
	var up := (_skeleton.get_bone_global_rest(_head).origin - pelvis).normalized()
	var toe := _skeleton.get_bone_global_rest(_toe).origin
	var foot := _skeleton.get_bone_global_rest(_foot).origin
	var forward := toe - foot
	forward = (forward - up * forward.dot(up)).normalized()
	if not (up.is_finite() and forward.is_finite()) or forward.length_squared() < 0.5:
		print("measure_hand_gesture: WARNING -- degenerate rest pose, world axes")
		return
	var left := up.cross(forward).normalized()
	# Sign fixed against the rig's own left leg rather than against a convention,
	# because the convention is exactly the thing that differs between packs.
	if (_skeleton.get_bone_global_rest(_thigh).origin - pelvis).dot(left) < 0.0:
		left = -left
	_frame = Basis(left, up, forward)
	print("measure_hand_gesture: anatomical frame  up %s  fwd %s  left %s" % [
		_terse(up), _terse(forward), _terse(left),
	])


func _terse(v: Vector3) -> String:
	return "(%+.2f %+.2f %+.2f)" % [v.x, v.y, v.z]


## A world offset expressed in the anatomical basis: x left, y up, z forward.
func _anatomical(offset: Vector3) -> Vector3:
	return Vector3(offset.dot(_frame.x), offset.dot(_frame.y), offset.dot(_frame.z))


## Centimetres of the 1.88 m body per rig unit, measured off the SKELETON's rest
## pose rather than off the meshes.
##
## Mesh.get_aabb() reports these rigs at roughly 1/100 of life size (briefing trap
## 15.3) -- the wanderer comes back 0.016 m tall -- so a factor derived from it is
## out by two orders of magnitude, and the first run of this tool printed hands
## fifty metres above the hips because of exactly that. The rest pose does not
## have the problem: it is the same space get_bone_global_pose() reports in, so
## the ratio between the two is honest whatever units either is in.
func _metres_per_unit() -> float:
	var top := -INF
	var bottom := INF
	for index in range(_skeleton.get_bone_count()):
		# Along the body's own up, so a Z-up pack measures its height and not its
		# depth. Root-to-crown rather than absolute, because a rig whose root sits
		# at the hips reports negative feet.
		var along := _skeleton.get_bone_global_rest(index).origin.dot(_frame.y)
		top = maxf(top, along)
		bottom = minf(bottom, along)
	var height := top - bottom
	if height <= 0.0001:
		return 1.0
	# 188 centimetres, because everything below is quoted in centimetres: a
	# hand's excursion is a two-digit number in cm and a three-decimal one in
	# metres, and the first is the one a reader can hold in their head.
	return 188.0 / height


func _report() -> void:
	var scale := _metres_per_unit()
	print("--- %s ---" % _model_path)
	print("rest pose is %.4f rig units tall; x %.3f cm per unit" % [188.0 / scale, scale])
	print("belly band: |x| <= %.0f, y in [%.0f, %.0f], z >= %.0f -- CENTIMETRES from the" % [
		BELLY_ACROSS, BELLY_LOW, BELLY_HIGH, BELLY_FORWARD,
	])
	print("hip joint on the 1.88 m body. x across, y up, z forward.")
	print("hold = longest RUN of consecutive qualifying samples, in seconds.")
	print("")
	print("%-24s %7s %7s %7s %7s %7s %7s %7s %7s %6s" % [
		"take", "len s", "y min", "y max", "z max", "|x| min", "sep min", "hits", "hold s", "hand",
	])
	var names := _player.get_animation_list()
	var found: Array = []
	for raw in names:
		var clip := String(raw)
		var animation := _player.get_animation(clip)
		if animation == null:
			continue
		var length := animation.length
		var count: int = maxi(int(length * SAMPLE_HZ), 2)
		var y_min := INF
		var y_max := -INF
		var z_max := -INF
		var x_min := INF
		var sep_min := INF
		var hits := 0
		var run := 0
		var best_run := 0
		var best_at := 0.0
		var best_hand := "-"
		for step in range(count):
			var at := length * float(step) / float(count)
			_player.play(clip)
			_player.seek(at, true)
			_player.advance(0.0)
			var root := _skeleton.get_bone_global_pose(_hips).origin
			var lh := _anatomical(_skeleton.get_bone_global_pose(_left).origin - root) * scale
			var rh := _anatomical(_skeleton.get_bone_global_pose(_right).origin - root) * scale
			y_min = minf(y_min, minf(lh.y, rh.y))
			y_max = maxf(y_max, maxf(lh.y, rh.y))
			z_max = maxf(z_max, maxf(lh.z, rh.z))
			x_min = minf(x_min, minf(absf(lh.x), absf(rh.x)))
			sep_min = minf(sep_min, (lh - rh).length())
			var l_ok := _in_band(lh)
			var r_ok := _in_band(rh)
			if l_ok or r_ok:
				hits += 1
				run += 1
				if run > best_run:
					best_run = run
					best_at = at
					best_hand = "both" if (l_ok and r_ok) else ("L" if l_ok else "R")
			else:
				run = 0
		var hold := float(best_run) / SAMPLE_HZ
		print("%-24s %7.3f %7.1f %7.1f %7.1f %7.1f %7.1f %7d %7.3f %6s" % [
			clip, length, y_min, y_max, z_max, x_min, sep_min, hits, hold, best_hand,
		])
		if hold > 0.0:
			found.append([clip, hold, best_at, best_hand])
	print("")
	if found.is_empty():
		print("NOTHING in this library holds a hand at the belly for a single sample.")
	else:
		print("--- takes that hold it, and for how long ---")
		found.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
		for row in found:
			print("  %-24s holds %.3f s, run ending at t=%.3f, %s hand" % [
				row[0], row[1], row[2], row[3],
			])
	_report_hunch(scale)


## The OTHER shape a starving man has, and the one a hand cannot carry at this
## framing: doubled over.
##
## A belly clutch is a hand. A hunch is the whole torso, so it moves the
## silhouette instead of moving four pixels inside it -- which is the difference
## between a readout and a measurement nobody can see. `UnarmedIdleInjured` was
## what forced this section: it fails the belly band outright (both hands sit 13
## to 16 cm BELOW the hip joint) and the reason turned out to be that the man is
## bent forward with his arms hanging, not that the take is inert.
##
## `lean` is the angle the hips->head line makes with the body's own up. A man
## standing straight reads a few degrees; the numbers below say which takes hold
## anything more, and for how long.
func _report_hunch(scale: float) -> void:
	if _head < 0:
		return
	print("")
	print("--- posture: how far he is bent over, and whether he stays there ---")
	print("lean = angle of the hips->head line off the body's up axis, degrees.")
	print("hold = longest run with lean >= %.0f deg, seconds." % HUNCH_DEGREES)
	print("")
	print("%-24s %8s %8s %8s %9s %9s %8s" % [
		"take", "lean min", "lean max", "lean avg", "head up", "head fwd", "hold s",
	])
	var rows: Array = []
	for raw in _player.get_animation_list():
		var clip := String(raw)
		var animation := _player.get_animation(clip)
		if animation == null:
			continue
		var length := animation.length
		var count: int = maxi(int(length * SAMPLE_HZ), 2)
		var lean_min := INF
		var lean_max := -INF
		var lean_sum := 0.0
		var up_min := INF
		var fwd_max := -INF
		var run := 0
		var best_run := 0
		for step in range(count):
			_player.play(clip)
			_player.seek(length * float(step) / float(count), true)
			_player.advance(0.0)
			var root := _skeleton.get_bone_global_pose(_hips).origin
			var head := _anatomical(_skeleton.get_bone_global_pose(_head).origin - root)
			var lean := rad_to_deg(Vector2(Vector2(head.x, head.z).length(), head.y).angle())
			lean = 90.0 - lean
			lean_min = minf(lean_min, lean)
			lean_max = maxf(lean_max, lean)
			lean_sum += lean
			up_min = minf(up_min, head.y * scale)
			fwd_max = maxf(fwd_max, head.z * scale)
			if lean >= HUNCH_DEGREES:
				run += 1
				best_run = maxi(best_run, run)
			else:
				run = 0
		var hold := float(best_run) / SAMPLE_HZ
		print("%-24s %8.1f %8.1f %8.1f %9.1f %9.1f %8.3f" % [
			clip, lean_min, lean_max, lean_sum / float(count), up_min, fwd_max, hold,
		])
		if hold > 0.0:
			rows.append([clip, hold, lean_sum / float(count)])
	print("")
	if rows.is_empty():
		print("NOTHING in this library holds a hunch.")
		return
	print("--- takes that HOLD a hunch ---")
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	for row in rows:
		print("  %-24s holds %.3f s at a mean lean of %.1f deg" % [row[0], row[1], row[2]])


func _in_band(hand: Vector3) -> bool:
	return (
		absf(hand.x) <= BELLY_ACROSS
		and hand.y >= BELLY_LOW and hand.y <= BELLY_HIGH
		and hand.z >= BELLY_FORWARD
	)
