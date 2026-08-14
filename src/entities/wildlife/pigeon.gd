class_name Pigeon
extends Bird

signal footprint_stamped(position: Vector3, heading: Vector3, left_foot: bool)
signal meal_completed(position: Vector3)

## A rock dove: `Bird` plus `data/wildlife/pigeon.tres`, and nothing else.
##
## ---------------------------------------------------------------------------
## THE 209 LINES THIS FILE USED TO BE
## ---------------------------------------------------------------------------
## `.superpowers/sdd/wave3/task-w3-pigeon-report.md` §4.1 measured the second
## bird in this game at 209 lines of code against 31 of data, and §4.3 named the
## reason: `Pigeon extends Crow` could not change the parent's model, colour or
## yaw by declaring different values, because GDScript forbids a subclass
## redeclaring a parent's constant. It had to rename all three (`DOVE_MODEL`,
## `DOVE_PALETTE_INDEX`, `DOVE_YAW`) and then override `_init`, `_build_rig`,
## `material`, `palette_tone` and `_play` to reach them -- a near-copy of the
## parent in each case.
##
## All five overrides are gone:
##
##   `_init`         -> the beat lengths are `launch_seconds`/`land_seconds`/
##                      `crouch_fraction`/`launch_climb_m`/`mill_speed`/
##                      `cruise_speed` on the species, seeded by `Bird.set_species()`
##   `_build_rig`    -> reads `species.model()` and `species.model_yaw`
##   `material`      -> `palette_tone()` is an instance method now, so it dispatches
##   `palette_tone`  -> `species.tone()`
##   `_play`         -> `species.roles` replaced `Pigeon.TRANSLATION`, and the two
##                      SUBSTITUTIONS it hid (there is no glide take and no
##                      wings-out-on-the-perch take) are now visible AS
##                      substitutions: two roles pointing at one take
##
## ---------------------------------------------------------------------------
## WHAT IS STILL TRUE OF THIS BIRD AND IS NOW IN THE `.tres`
## ---------------------------------------------------------------------------
##   * thirteen takes, of which the behaviour drives seven; `walk`, `run` and the
##     transitions are named but nothing drives them yet
##   * `structure_tones[1]`, one step in from the crow's near-black, because a
##     rock dove is the grey one and two near-black birds at sixteen pixels are
##     one bird -- and not `structure_tones[0]`, which is the farmhouse siding
##     the bird sits on
##   * it does not leave at nightfall: `daylight_only = false`
##   * it will not land on a perch another bird is standing on
##   * `animation/trimming` is **ON** for this pack, which is the opposite of the
##     crow's -- see `data/wildlife/pigeon.tres`'s generator and `BirdTake.seconds`
const SPECIES := preload("res://data/wildlife/pigeon.tres")
const PRESENTATION: PigeonPresentation = preload("res://data/wildlife/pigeon_presentation.tres")
const ORIGINAL_ALBEDO: Texture2D = preload("res://assets/models/characters/pigeon/Dove-rock_COL_2k.png")

enum Plumage { GREY_BROWN, GREY_BLACK, MILK_WHITE }
enum GroundState { NONE, ARRIVING, WANDERING, SEEKING_FOOD, EATING, LEAVING }

const PLUMAGE_COUNT := 3
const WALK_TAKE := &"walk"
const PECK_TAKE := &"peck"
const WALK_SPEED_MPS := 0.34
const WANDER_RADIUS_M := 0.45
const FLEE_RADIUS_M := 1.75
const FOOD_REACH_M := 0.24
const FEEDING_BODY_PITCH_DEGREES := -30.0
const FEEDING_LEAN_SECONDS := 0.18
const MEAL_LINGER_SECONDS := 8.0
const PECK_EVERY_SECONDS := 4.6
const FOOTSTEP_DISTANCE_M := 0.095
const FOOTSTEP_WIDTH_M := 0.050

var _plumage_variant := -1
var _ground_visit := false
var _ground_state: GroundState = GroundState.NONE
var _ground_anchor := Vector3.ZERO
var _food_target := Vector3.ZERO
var _meal_count := 0
var _feeding_lean := 0.0
var _ground_wait_left := 0.0
var _ground_cycle := 0.0
var _peck_left := 0.0
var _walk_phase := 0.0
var _ground_watched: Node3D = null
var _ground_surface = null
var _ground_calls_left := 0
var _ground_call_timer := 0.0
var _ground_calls_played := 0
var _departure_sounds_played := 0
var _call_voice: AudioStreamPlayer3D = null
var _departure_voice: AudioStreamPlayer3D = null
var _footstep_distance := 0.0
var _left_foot := true


func _init() -> void:
	species = SPECIES


func set_plumage_variant(value: int) -> void:
	_plumage_variant = clampi(value, 0, PLUMAGE_COUNT - 1)
	_material = null
	var rig := get_node_or_null("Rig") as Node3D
	if rig != null:
		_paint(rig)


func plumage_variant() -> int:
	return _plumage_variant


## The owner explicitly released pigeon plumage from the world's twelve surface
## colours. The tones still live in generated data, never hidden in this script.
static func plumage_tone(variant: int) -> Color:
	if PRESENTATION == null or PRESENTATION.plumage_tones.size() < PLUMAGE_COUNT:
		return SPECIES.tone()
	return PRESENTATION.plumage_tones[clampi(variant, 0, PLUMAGE_COUNT - 1)]


func palette_tone() -> Color:
	return plumage_tone(_plumage_variant) if _plumage_variant >= 0 else super.palette_tone()


## Preserve the pack-authored beak, breast, wing, eye and foot colours. The
## selected plumage is a restrained luma-preserving grade on top of that map,
## never the single flat replacement that reduced the bird to a silhouette.
func material() -> ShaderMaterial:
	if _material != null:
		return _material
	if _painter == null:
		_painter = CelPainter.new()
	var tone := palette_tone()
	_material = _painter.material_for(
		tone,
		true,
		ORIGINAL_ALBEDO,
		1.0,
		0.0,
		tone,
		PRESENTATION.plumage_texture_tint_strength
	)
	return _material


## Arrive on the snow near somebody, then walk and peck rather than becoming a
## wire perch. The ordinary Bird approach and landing remain the flight model.
func begin_ground_visit(
	landing: Vector3,
	from: Vector3,
	watched: Node3D,
	wait_seconds: float,
	surface = null,
	call_count := 3
) -> bool:
	_ground_visit = true
	_ground_state = GroundState.ARRIVING
	_ground_anchor = landing
	_food_target = Vector3.ZERO
	_meal_count = 0
	_feeding_lean = 0.0
	_ground_wait_left = maxf(wait_seconds, 1.0)
	_ground_cycle = 0.0
	_peck_left = 0.0
	_walk_phase = float(_plumage_variant + 1) * 1.37
	_ground_watched = watched
	_ground_surface = surface
	_ground_calls_left = clampi(call_count, 2, 4)
	_ground_call_timer = 0.08
	_ground_calls_played = 0
	_departure_sounds_played = 0
	_footstep_distance = 0.0
	_left_foot = true
	var toward := _watched_position() - landing
	var began := approach(
		{"at": landing, "facing": Vector3(toward.x, 0.0, toward.z)},
		from,
		0.16,
		1.4
	)
	if not began:
		_ground_visit = false
		_ground_state = GroundState.NONE
	return began


func is_ground_visitor() -> bool:
	return _ground_visit


func is_waiting_for_food() -> bool:
	return _ground_visit and _ground_state == GroundState.WANDERING \
		and state() == State.PERCHED


func ground_state() -> GroundState:
	return _ground_state


func ground_anchor() -> Vector3:
	return _ground_anchor


func ground_position() -> Vector3:
	return where()


func food_target() -> Vector3:
	return _food_target


func meal_count() -> int:
	return _meal_count


func reserve_food_arrival(seconds: float) -> void:
	if not _ground_visit or _ground_state != GroundState.WANDERING:
		return
	_ground_wait_left = maxf(_ground_wait_left, maxf(seconds, 0.0) + MEAL_LINGER_SECONDS)


func feeding_lean() -> float:
	return _feeding_lean


func feeding_body_pitch_degrees() -> float:
	return FEEDING_BODY_PITCH_DEGREES * _feeding_lean


func is_perched() -> bool:
	return false if _ground_visit else super.is_perched()


func is_on_the_wire() -> bool:
	return false if _ground_visit else super.is_on_the_wire()


func is_inbound() -> bool:
	# BirdFlock normally refuses a landing whose target is near the player. This
	# one was deliberately chosen for that reason, so it must not be called off.
	return false if _ground_visit else super.is_inbound()


func is_landing() -> bool:
	return false if _ground_visit else super.is_landing()


func receive_food(target: Vector3 = Vector3(INF, INF, INF)) -> void:
	if not is_waiting_for_food():
		return
	_food_target = target if _is_finite_point(target) else where()
	_food_target.y = _surface_height(_food_target)
	_ground_wait_left = maxf(_ground_wait_left, MEAL_LINGER_SECONDS)
	_ground_cycle = 0.0
	_peck_left = 0.0
	if _flat_gap(where(), _food_target) <= FOOD_REACH_M:
		_begin_eating()
	else:
		_ground_state = GroundState.SEEKING_FOOD
		play_take(WALK_TAKE)


func ground_call_count() -> int:
	return _ground_calls_played


func departure_sound_count() -> int:
	return _departure_sounds_played


func call_voice() -> AudioStreamPlayer3D:
	return _call_voice


func departure_voice() -> AudioStreamPlayer3D:
	return _departure_voice


func advance(delta: float) -> void:
	# Fear outranks every friendly action, including an inbound ground arrival
	# and a meal already under way. There is no hysteresis because departure is a
	# one-way transition: once startled, this visit cannot turn back around.
	if _ground_visit and is_finite(delta) and delta > 0.0 \
			and _watched_flat_gap() <= FLEE_RADIUS_M:
		_leave_ground(_watched_position())
	super.advance(delta)
	if not _ground_visit or state() != State.PERCHED or not is_finite(delta) or delta <= 0.0:
		return
	if _ground_state == GroundState.ARRIVING:
		_ground_state = GroundState.WANDERING
		_ground_cycle = PECK_EVERY_SECONDS * 0.45
		play_take(WALK_TAKE)
	_advance_ground(delta)


func _advance_ground(delta: float) -> void:
	_advance_ground_calls(delta)
	match _ground_state:
		GroundState.WANDERING:
			_advance_wander(delta)
		GroundState.SEEKING_FOOD:
			_advance_food_seek(delta)
		GroundState.EATING:
			_advance_eating(delta)


func _advance_wander(delta: float) -> void:
	_ground_wait_left -= delta
	if _ground_wait_left <= 0.0:
		_leave_ground(_watched_position())
		return
	_ground_cycle += delta
	if _peck_left > 0.0:
		_peck_left -= delta
		if _peck_left <= 0.0:
			play_take(WALK_TAKE)
		return
	if _ground_cycle >= PECK_EVERY_SECONDS:
		_ground_cycle = 0.0
		_peck_left = _peck_duration()
		play_take(PECK_TAKE)
		return
	_walk_phase += delta * 0.23
	var radius := WANDER_RADIUS_M * (0.78 + sin(_walk_phase * 0.71) * 0.22)
	var desired := _ground_anchor \
		+ Vector3(cos(_walk_phase), 0.0, sin(_walk_phase)) * radius
	_walk_toward(desired, delta)


func _advance_food_seek(delta: float) -> void:
	if _flat_gap(where(), _food_target) <= FOOD_REACH_M:
		_begin_eating()
		return
	_walk_toward(_food_target, delta)
	if _flat_gap(where(), _food_target) <= FOOD_REACH_M:
		_begin_eating()


func _begin_eating() -> void:
	_ground_state = GroundState.EATING
	_peck_left = _peck_duration()
	# The walk already turns toward the patch, but food offered directly under a
	# waiting bird has no walk frame to do so. Preserve the last useful target
	# bearing before the full-body feeding lean begins.
	var toward := _food_target - where()
	toward.y = 0.0
	if toward.length_squared() > 0.0001:
		_aim(toward.normalized())
	_set_feeding_lean(0.0)
	play_take(PECK_TAKE)


func _advance_eating(delta: float) -> void:
	_peck_left -= delta
	var duration := _peck_duration()
	var elapsed := maxf(duration - maxf(_peck_left, 0.0), 0.0)
	var into_pose := smoothstep(0.0, FEEDING_LEAN_SECONDS, elapsed)
	var out_of_pose := smoothstep(0.0, FEEDING_LEAN_SECONDS, maxf(_peck_left, 0.0))
	_set_feeding_lean(minf(into_pose, out_of_pose))
	if _peck_left > 0.0:
		return
	var completed_at := _food_target
	_meal_count += 1
	_ground_state = GroundState.WANDERING
	_food_target = Vector3.ZERO
	_ground_cycle = 0.0
	_peck_left = 0.0
	_set_feeding_lean(0.0)
	play_take(WALK_TAKE)
	meal_completed.emit(completed_at)


func _walk_toward(target: Vector3, delta: float) -> void:
	var desired := target
	desired.y = _surface_height(desired)
	var current := where()
	var motion := desired - current
	var flat_motion := Vector3(motion.x, 0.0, motion.z)
	if flat_motion.length_squared() <= 0.0001:
		return
	var next := current.move_toward(desired, WALK_SPEED_MPS * delta)
	next.y = _surface_height(next)
	_place(next)
	var heading := flat_motion.normalized()
	_aim(heading)
	_footstep_distance += Vector2(next.x - current.x, next.z - current.z).length()
	while _footstep_distance >= FOOTSTEP_DISTANCE_M:
		_footstep_distance -= FOOTSTEP_DISTANCE_M
		_stamp_foot(next, heading)


func _peck_duration() -> float:
	return maxf(SPECIES.length_of(PECK_TAKE), 0.01)


func _stamp_foot(at: Vector3, heading: Vector3) -> void:
	var side := 1.0 if _left_foot else -1.0
	_left_foot = not _left_foot
	var lateral := Vector3(-heading.z, 0.0, heading.x) * side * FOOTSTEP_WIDTH_M
	var mark := at + lateral
	mark.y = _surface_height(mark)
	footprint_stamped.emit(mark, heading, not _left_foot)


func _leave_ground(watched_at: Vector3) -> void:
	if not _ground_visit:
		return
	_set_feeding_lean(0.0)
	var away := where() - watched_at
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3.FORWARD
	var leaving := (away.normalized() + Vector3.UP * 0.42).normalized()
	var departed := false
	if state() == State.PERCHED:
		# Bird.scatter checks its concrete state, not the virtual is_perched()
		# answer, so a ground visitor can reuse the signed-off take-off curve.
		departed = scatter(leaving, 0.0, 0.18, 1.2)
	elif state() == State.INBOUND or state() == State.LANDING:
		departed = give_up()
		if departed:
			# `give_up()` normally keeps the approach bearing. A friendly arrival
			# startled before touchdown must instead leave away from the player.
			_heading = leaving
			_departure = leaving
	if not departed:
		return
	_play_departure_sound()
	_ground_visit = false
	_ground_state = GroundState.LEAVING
	_food_target = Vector3.ZERO
	_peck_left = 0.0
	_ground_watched = null
	_ground_surface = null


func _set_feeding_lean(amount: float) -> void:
	_feeding_lean = clampf(amount, 0.0, 1.0)
	# Bird's node origin is the foot plane and its -Z points along the current
	# ground heading. Pitching that stable parent therefore carries breast, neck
	# and animated head toward the same crumb patch without changing bone lengths
	# or lowering the feet through the snow.
	rotation.x = deg_to_rad(FEEDING_BODY_PITCH_DEGREES) * _feeding_lean


## The supplied recording is allowed to finish before the next call begins.
## Two to four complete calls read as an animal settling; restarting one sample
## mid-word would read as a broken loop.
func _advance_ground_calls(delta: float) -> void:
	if _ground_calls_left <= 0:
		return
	_ground_call_timer -= delta
	if _ground_call_timer > 0.0:
		return
	_ground_calls_left -= 1
	_ground_calls_played += 1
	_play_ground_call()
	var length := PRESENTATION.ground_call.get_length() if PRESENTATION.ground_call != null else 0.0
	_ground_call_timer = maxf(length, 0.0) + PRESENTATION.call_silence_seconds


func _play_ground_call() -> void:
	_ensure_audio_voices()
	if _call_voice == null or not is_inside_tree():
		return
	# One supplied voice, made into a small natural burst by restrained pitch
	# steps rather than layering duplicate players on the same frame.
	var pitch_step := float((_ground_calls_played - 1) % 3 - 1)
	_call_voice.pitch_scale = 1.0 + pitch_step * PRESENTATION.call_pitch_step
	_call_voice.play()


func _play_departure_sound() -> void:
	_departure_sounds_played += 1
	_ensure_audio_voices()
	if _departure_voice == null or not is_inside_tree():
		return
	if _call_voice != null and _call_voice.playing:
		_call_voice.stop()
	_departure_voice.play()


func _ensure_audio_voices() -> void:
	if not is_inside_tree() or PRESENTATION == null:
		return
	if _call_voice == null:
		_call_voice = _make_voice(
			&"GroundCall",
			PRESENTATION.ground_call,
			PRESENTATION.call_volume_db,
			PRESENTATION.call_carry_m
		)
	if _departure_voice == null:
		_departure_voice = _make_voice(
			&"DepartureWings",
			PRESENTATION.departure_wings,
			PRESENTATION.departure_volume_db,
			PRESENTATION.departure_carry_m
		)


func _make_voice(
	voice_name: StringName,
	stream: AudioStream,
	volume_db: float,
	carry_m: float
) -> AudioStreamPlayer3D:
	if stream == null:
		return null
	var voice := AudioStreamPlayer3D.new()
	voice.name = voice_name
	voice.stream = stream
	voice.volume_db = volume_db
	voice.max_distance = carry_m
	voice.unit_size = PRESENTATION.unit_size_m
	add_child(voice)
	return voice


func _watched_position() -> Vector3:
	if _ground_watched == null or not is_instance_valid(_ground_watched):
		return where()
	return _ground_watched.global_position if _ground_watched.is_inside_tree() else _ground_watched.position


func _watched_flat_gap() -> float:
	if _ground_watched == null or not is_instance_valid(_ground_watched):
		return INF
	return _flat_gap(where(), _watched_position())


static func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _is_finite_point(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _surface_height(at: Vector3) -> float:
	if _ground_surface != null and is_instance_valid(_ground_surface) \
			and _ground_surface.has_method(&"surface_height_at"):
		return float(_ground_surface.call(&"surface_height_at", at))
	return at.y
