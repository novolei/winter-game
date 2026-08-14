extends Node

## Fixed-camera evidence for the friendly-pigeon feeding loop. The harness uses
## the real main scene, flock, interaction director, player gesture, crumb
## scatter and affection label. It only removes unrelated random movement from
## the plate and deterministically drives the same public seams gameplay uses.
##
##   Godot_console.exe --path <project> res://tools/capture_pigeon_feeding.tscn \
##       --resolution 1600x1000 -- --out-prefix D:/somewhere/pigeon-feeding
##
## Writes <prefix>-hold.png, -crumbs.png, -peck.png and -heart.png.

const DEFAULT_PREFIX := "user://pigeon-feeding"
const HOLD_FRACTION := 0.50
const WAIT_LIMIT_SECONDS := 14.0
const POLL_SECONDS := 0.04

var _prefix := DEFAULT_PREFIX
var _flock: PigeonFlock = null
var _pigeon: Pigeon = null
var _player: PlayerController = null
var _director: InteractionDirector = null
var _layer: UILayer = null
var _rig: CameraRig = null


func _ready() -> void:
	_prefix = _string_arg(OS.get_cmdline_user_args(), "--out-prefix", DEFAULT_PREFIX)
	call_deferred("_run")


func _run() -> void:
	_flock = get_node_or_null("Main/Pigeons") as PigeonFlock
	_player = get_node_or_null("Main/Player") as PlayerController
	_director = get_node_or_null("Main/UI/Interaction") as InteractionDirector
	_layer = get_node_or_null("Main/UI") as UILayer
	_rig = get_node_or_null("Main/CameraRig") as CameraRig
	if _flock == null or _player == null or _director == null or _layer == null or _rig == null:
		push_error("capture_pigeon_feeding: expected main player, pigeon flock, camera and interaction UI")
		get_tree().quit(1)
		return

	_quiet_unrelated_presentation()
	_flock.random_seed = 20260813
	# Main's child `_ready()` has already seeded its generator before this root
	# harness runs, so changing the exported value alone would only label the run
	# as deterministic. Rewind the capture-only generator to the same seed here.
	var capture_rng := _flock.get("_rng") as RandomNumberGenerator
	if capture_rng != null:
		capture_rng.seed = hash(_flock.random_seed)
	_flock.first_arrival_seconds = 999.0
	_flock.friendly_visit_chance = 0.0
	_flock.friendly_check_seconds = 60.0
	_flock.friendly_radius_min_m = 3.20
	_flock.friendly_radius_max_m = 3.20
	_flock.friendly_wait_min_seconds = 60.0
	_flock.friendly_wait_max_seconds = 60.0
	_flock.max_ground_visitors = 1
	_flock.flush_radius_m = 0.0
	_flock.set_watched(_player)

	_frame_camera()
	if not _flock.try_friendly_visit(true):
		push_error("capture_pigeon_feeding: forced friendly visit was refused")
		get_tree().quit(1)
		return
	if not await _wait_until_waiting():
		push_error("capture_pigeon_feeding: visitor did not settle within %.1f seconds" % WAIT_LIMIT_SECONDS)
		get_tree().quit(1)
		return

	_face_player_to(_pigeon.where())
	_director.reconsider()
	await _wait(0.45)
	_frame_camera()
	var prompt := _prompt()
	if prompt == null or not prompt.guide_line_enabled():
		push_error("capture_pigeon_feeding: guided feeding prompt did not surface")
		get_tree().quit(1)
		return

	# Stop only the input poll. The same director still owns focus, progress and
	# activation; deterministic input calls replace a human holding E.
	_director.set_process(false)
	var half_hold := _flock.feeding_hold_seconds * HOLD_FRACTION
	_director.advance_interaction(half_hold, true, true)
	prompt = _prompt()
	print("capture_pigeon_feeding: hold %.0f%%, guide=%s, copy='%s', rect=%s, anchor=%s" % [
		_director.hold_progress() * 100.0,
		prompt.guide_line_enabled(), prompt.copy_text(), Rect2(prompt.position, prompt.size),
		prompt.screen_anchor().snapped(Vector2.ONE)])
	await _save_frozen("%s-hold.png" % _prefix)

	if not _director.advance_interaction(
		_flock.feeding_hold_seconds - half_hold, true, false
	):
		push_error("capture_pigeon_feeding: completed hold did not activate feeding")
		get_tree().quit(1)
		return

	# The handful releases 0.58 s into the real temporary gesture. At +0.42 s
	# the pieces have separated enough to read as a fan while all fourteen are
	# still above their deterministic landing patch.
	await _wait(_flock.feed_release_seconds + 0.42)
	var scatter := _latest_scatter()
	if scatter == null:
		push_error("capture_pigeon_feeding: no breadcrumb scatter after release")
		get_tree().quit(1)
		return
	print("capture_pigeon_feeding: crumbs mid-flight, %d/%d settled, world bounds=%s" % [
		scatter.settled_count(), scatter.crumb_count(), _crumb_bounds(scatter)])
	await _save_frozen("%s-crumbs.png" % _prefix)

	if not await _wait_for_ground_state(Pigeon.GroundState.EATING):
		push_error("capture_pigeon_feeding: pigeon did not reach crumbs and peck")
		get_tree().quit(1)
		return
	await _wait(0.375)
	var beak := _bone_world_position(_pigeon, &"JawEnd_M")
	var beak_gap := _flat_gap(beak, _pigeon.food_target())
	print(("capture_pigeon_feeding: peck state=%d, pigeon=%s, food=%s, gap=%.2f m, " \
			+ "lean=%.1f deg, beak-above-food=%.3f m, beak-food-flat=%.3f m") % [
		_pigeon.ground_state(), _pigeon.where().snapped(Vector3(0.01, 0.01, 0.01)),
		_pigeon.food_target().snapped(Vector3(0.01, 0.01, 0.01)),
		_flat_gap(_pigeon.where(), _pigeon.food_target()),
		_pigeon.feeding_body_pitch_degrees(), beak.y - _pigeon.food_target().y, beak_gap])
	if beak.y - _pigeon.food_target().y > 0.055 or beak_gap > 0.08:
		push_error("capture_pigeon_feeding: beak does not reach the ground food patch")
		get_tree().quit(1)
		return
	await _save_frozen("%s-peck.png" % _prefix)

	if not await _wait_for_heart():
		push_error("capture_pigeon_feeding: meal completed without an affection heart")
		get_tree().quit(1)
		return
	# The polling seam can notice the new child up to 40 ms into its life. Another
	# 180 ms catches the enlarged main heart settling and the delayed small heart
	# in its overshoot, so both sizes and their stagger read in one frame.
	await _wait(0.18)
	var heart := _pigeon.get_node_or_null("AffectionHeart") as PigeonAffection
	print("capture_pigeon_feeding: heart pop, count=%d, sizes=%s, affection=%d, screen=%s" % [
		heart.heart_count() if heart != null else 0,
		heart.heart_font_sizes() if heart != null else [], _flock.affection_count(),
		get_viewport().get_camera_3d().unproject_position(heart.global_position).snapped(Vector2.ONE)
			if heart != null else Vector2(-1.0, -1.0)])
	await _save_frozen("%s-heart.png" % _prefix)
	get_tree().quit()


func _quiet_unrelated_presentation() -> void:
	var crows := get_node_or_null("Main/Crows") as CrowFlock
	if crows != null:
		crows.enabled = false
	for path in [
		"Main/Snowfall", "Main/WeatherVfx", "Main/WeatherSnowFog",
		"Main/CameraRig/Camera3D/SnowLens"
	]:
		var visual := get_node_or_null(path)
		if visual is Node3D:
			(visual as Node3D).visible = false
		elif visual is CanvasItem:
			(visual as CanvasItem).visible = false
	var wind := get_node_or_null("Main/Wind")
	if wind != null:
		wind.process_mode = Node.PROCESS_MODE_DISABLED


func _frame_camera() -> void:
	_rig.orthographic_size = 10.5
	_rig.refresh_framing()
	var tween := _rig.framing_tween()
	if tween != null and tween.is_valid():
		tween.kill()
	_rig.apply_framed_size(10.5)
	_rig.snap_to_target()
	# Hold the authored gameplay shot exactly; the bird moves inside it while the
	# framing itself remains comparable across all four evidence images.
	_rig.set_process(false)


func _face_player_to(at: Vector3) -> void:
	var toward := at - _player.global_position
	toward.y = 0.0
	if toward.length_squared() > 0.0001:
		# Capture-only setup of the controller's preserved heading. The interaction
		# itself still starts the public feed gesture through EventBus.
		_player.set("_facing", toward.normalized())


func _wait_until_waiting() -> bool:
	var elapsed := 0.0
	while elapsed < WAIT_LIMIT_SECONDS:
		for child in _flock.get_children():
			var candidate := child as Pigeon
			if candidate != null and candidate.is_ground_visitor():
				_pigeon = candidate
				if candidate.is_waiting_for_food():
					return true
		await _wait(POLL_SECONDS)
		elapsed += POLL_SECONDS
	return false


func _wait_for_ground_state(wanted: Pigeon.GroundState) -> bool:
	var elapsed := 0.0
	while elapsed < WAIT_LIMIT_SECONDS and is_instance_valid(_pigeon):
		if _pigeon.ground_state() == wanted:
			return true
		await _wait(POLL_SECONDS)
		elapsed += POLL_SECONDS
	return false


func _wait_for_heart() -> bool:
	var elapsed := 0.0
	while elapsed < WAIT_LIMIT_SECONDS and is_instance_valid(_pigeon):
		if _pigeon.get_node_or_null("AffectionHeart") != null:
			return true
		await _wait(POLL_SECONDS)
		elapsed += POLL_SECONDS
	return false


func _prompt() -> InteractionPrompt:
	var raw: Variant = _director.get("_prompt")
	return raw as InteractionPrompt if raw != null and is_instance_valid(raw) else null


func _latest_scatter() -> BreadcrumbScatter:
	for index in range(_flock.get_child_count() - 1, -1, -1):
		var scatter := _flock.get_child(index) as BreadcrumbScatter
		if scatter != null:
			return scatter
	return null


func _crumb_bounds(scatter: BreadcrumbScatter) -> AABB:
	var positions := scatter.crumb_positions()
	if positions.is_empty():
		return AABB()
	var low: Vector3 = positions[0]
	var high: Vector3 = positions[0]
	for at in positions:
		low = low.min(at)
		high = high.max(at)
	return AABB(low, high - low)


func _bone_world_position(root: Node, bone_name: StringName) -> Vector3:
	for node in root.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		if skeleton == null:
			continue
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return Vector3(INF, INF, INF)


func _save_frozen(path: String) -> void:
	Engine.time_scale = 0.0
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	Engine.time_scale = 1.0
	if error != OK:
		push_error("capture_pigeon_feeding: could not write %s (error %d)" % [path, error])
	else:
		print("capture_pigeon_feeding: wrote ", ProjectSettings.globalize_path(path))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _string_arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


static func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
