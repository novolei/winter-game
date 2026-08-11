class_name PlayerController
extends CharacterBody3D

## Walks, runs, and writes the lines in the snow.
##
## Speed is not a key. It is read off the snow: bare ground lets you run, a
## drift drops you to a trudge, and a path you have already flattened lets you
## run again. That last one is the point of SnowField having a packed layer at
## all -- the shortcut you beat into the snow is a real one.
##
## Footprints go out as an EventBus event rather than as calls into TrackMask
## and SnowField. The player does not need to know either of them exists, and
## when the bear starts leaving prints in Wave 4 it emits the same event.
##
## The body is the supplied Winter Wanderer, rendered with the maps Meshy
## delivered. The character is exempt from the Art Bible's surface rules by the
## owner's ruling -- see _build_body() -- so unlike everything else in this
## project it reads no colour out of the palette at all.

const MODEL_PATH := "res://assets/models/characters/winter_wanderer.glb"
const ALBEDO_PATH := "res://assets/models/characters/winter_wanderer_albedo.png"
const NORMAL_PATH := "res://assets/models/characters/winter_wanderer_normal.png"
const ROUGHNESS_PATH := "res://assets/models/characters/winter_wanderer_roughness.png"
const METALLIC_PATH := "res://assets/models/characters/winter_wanderer_metallic.png"
const STEP_SOUND_PATHS := [
	"res://assets/audio/foley/footstep_snow_01.wav",
	"res://assets/audio/foley/footstep_snow_02.wav",
]
const FOOTPRINT_EVENT := &"player.footprint"

## The two takes this slice uses, out of the eighteen in the file. Shooting,
## aiming, sneaking, the limp and the two death takes belong to later waves.
const WALK_CLIP := &"Walking"
const RUN_CLIP := &"Running"

@export var run_speed := 5.4
@export var wade_speed := 1.5
@export var acceleration := 12.0

## Metres of travel between prints, and how far each sits off the centre line.
@export var stride_length := 0.72
@export var stride_width := 0.19

## Half-length of a print. Big, deliberately: these tracks are the only texture
## the snow has and they have to read from the game camera. Shrinking the mark
## to boot scale made them disappear -- what was actually wrong was the halo
## bleeding out around them, and that is fixed by the compact rim in
## TrackMask.stamp(), not by making the print small.
@export var print_radius := 0.28

## Longer than it is wide, and pointed where the walker was going.
@export var print_aspect := 1.5

## ---------------------------------------------------------------------------
## How a print changes with the snow it is made in
## ---------------------------------------------------------------------------
## Deep snow: the full-size print that was approved -- more snow displaced, and
## the walls of the hole collapse, so the edge is softer and more ragged.
## Thin snow on a scoured crest: smaller, sharper, barely more than a scuff.
##
## This is what ties the trail to the terrain. A chain of prints deepening as it
## descends into a hollow tells you where the drifts are without anything having
## to draw them, which is Art Bible rule 11's point about the lines in the snow
## being narrative -- they record what happened.
@export var print_thin_scale := 0.74
@export var print_core_deep := 0.48
@export var print_core_thin := 0.74
@export var print_irregularity_deep := 0.3
@export var print_irregularity_thin := 0.08

## Per-step variation, so no two prints share an outline. Applied on top of
## everything above.
@export var print_heading_jitter := 0.22
@export var print_aspect_jitter := 0.12
@export var print_scale_jitter := 0.08

## ---------------------------------------------------------------------------
## Prints trenching together in the deepest snow
## ---------------------------------------------------------------------------
## Past about knee depth the legs stop clearing the snow between footfalls and
## start ploughing through it, so the gap between consecutive prints partly
## fills in. On a scoured crest nothing of the sort happens, which is why this
## is gated on the same depth ratio that already drives the print's size,
## softness and raggedness -- one fact about the snow, read four ways.
##
## A HINT, and the numbers here are what "a hint" costs. Two earlier passes were
## both plainly wrong and both are worth recording, because the failure is not
## the one you would guess:
##
##   0.50 strength / 0.70 width, from 0.45 depth -- the prints dissolved
##       outright and the trail became a continuous white ridge.
##   0.30 strength / 0.42 width, from 0.55 depth -- still a ribbon: an angular
##       zigzag snake with the prints absorbed into its corners.
##
## The second failure was geometric rather than a matter of degree, and no
## reduction in strength would have fixed it -- see _place_print() on why the
## groove now runs down the centre line instead of foot to foot. What is left is
## a groove a sixth as strong as a print, a third of its width, and only in the
## deepest fifth of the depth range.
@export var trench_depth_start := 0.8
@export var trench_strength := 0.16
@export var trench_width := 0.32
@export var trench_irregularity := 0.25

## A groove is only drawn between two steps that actually followed each other.
## Beyond this many strides apart the walker stopped, turned, or the game
## restarted, and joining them would rule a line across untouched snow.
@export var trench_max_stride_gap := 1.8

## How far a print skews down the fall line, per unit of slope. The mask is a
## plan view, so a shape that is round on a tilted surface is already stored
## squashed along the fall line by cos(slope); this is the extra stretch on top
## that makes a boot on a flank read as placed rather than punched. The net at
## 30 degrees is about a third longer downhill than across.
@export var print_downhill_stretch := 0.9

## What fraction of the snow's depth the body sinks through. 0 stands on top of
## a drift like a table; 1 stands on the bare ground with the snow up to the
## knee. At 0.75 a metre of snow swallows most of a boot and half a shin, which
## is what the reference figure reads as.
@export var sink_fraction := 0.75

## Y is damped rather than assigned. Height is already sampled continuously and
## bilinearly, but treading the snow down drops the surface under the character
## the instant a print lands, and the sun turns every centimetre of that into
## 2.5 cm of shadow. Smoothing costs nothing and removes the stepping. Too much
## of it and the character wades through crests instead of over them: at 14 the
## lag is about 7 cm on a 20-degree slope at walking pace.
@export var vertical_smoothing := 14.0

## How tall the traveller is, and therefore both the collision capsule and the
## scale the model is drawn at -- the mesh's own height is measured at load and
## divided out, so this number is the one that decides.
##
## Set by measuring the frame, not by choosing a plausible human height, because
## Art Bible rule 1 makes the *screen* height the specification: the figure is
## about 11% of frame height, 125 px of 1101 in the reference. Meshy exported
## this model at 1.64 m, which is not an authored decision -- it is whatever the
## generator produced -- and at 1.64 m the figure measured 9.5% against the
## capsule it replaces at 11.4%. Rule 1 also says in as many words that its
## numbers are a starting point and the screenshot decides.
##
## The alternative was to close the same gap on the camera, and it was rejected:
## orthographic_size is entangled with the terrain wavelength, the sun
## elevation, the shadow range and the print scale, all tuned together against a
## 10.5 m frame and all approved. This changes one number that nothing else
## depends on.
@export var body_height := 1.88
@export var body_radius := 0.28

## ---------------------------------------------------------------------------
## The character
## ---------------------------------------------------------------------------
## How fast the figure turns to face where it is going, in the same
## closed-fraction-per-second form as the camera's follow.
@export var turn_speed := 12.0

## The ground speed at which each clip plays at rate 1. Below the first the
## stride slows down with the walk; above the second it speeds up with the run.
## Set so the feet plant rather than skate -- the walk cycle covers about 1.4 m
## in its 1.07 s, the run about 3.1 m in its 0.67 s.
@export var anim_walk_speed := 1.35
@export var anim_run_speed := 4.6

## A ceiling on the playback rate, so a sprint down a scoured slope cannot spin
## the legs into a blur.
@export var anim_max_pace := 1.5

## ---------------------------------------------------------------------------
## Footstep audio
## ---------------------------------------------------------------------------
## Two hand-cut single steps, alternated at random. Two files is the minimum
## that stops a walk cycle sounding like a metronome, and the small pitch spread
## on top covers the rest.
@export var step_volume_db := -7.0

## Ratio, not semitones: AudioStreamRandomizer varies pitch over
## [1/random_pitch, random_pitch], so 1.05 is roughly +/- 5%.
@export var step_pitch_spread := 1.05
@export var step_volume_spread_db := 1.5

## Deep snow is a duller, softer sound than a boot on a scoured crest. Cheap,
## so it is here; set to zero to switch the behaviour off.
@export var step_depth_quieten_db := 3.5
@export var step_depth_pitch_drop := 0.1

var _snow: Node
var _bus: Node
var _steps: AudioStreamPlayer
var _model: Node3D
var _animation: AnimationTree
var _stride_accumulator := 0.0
var _left_foot := true
var _facing := Vector3.FORWARD
var _grounded := false
var _last_print_centre := Vector3.ZERO
var _has_last_print := false


func _ready() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null:
		registry.register(&"player", self)
	# Trap 3: an autoload is a node under /root, never an Engine singleton.
	_bus = get_node_or_null("/root/EventBus")
	_build_body()
	_build_audio()
	_register_actions()
	# Subscribed to its own event rather than called from _place_print(): the
	# print and the sound are the same fact, so they should not be able to fall
	# out of step by someone editing one call site. Anything else that starts
	# leaving prints gets footstep audio for free.
	if _bus != null:
		_bus.subscribe(FOOTPRINT_EVENT, _on_footprint)


func _exit_tree() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.get_service(&"player") == self:
		registry.unregister(&"player")
	if _bus != null:
		_bus.unsubscribe(FOOTPRINT_EVENT, _on_footprint)
	# Quitting mid-stride otherwise leaves the AudioServer holding a playback,
	# and with it both WAVs: "ERROR: 2 resources still in use at exit", which is
	# a dirty console and a failed run by this project's standard. Verified with
	# --verbose -- it named footstep_snow_01.wav and footstep_snow_02.wav.
	if _steps != null:
		_steps.stop()


## The character renders with the maps Meshy delivered, not with the palette.
##
## That is the owner's ruling -- 人物的颜色不受 GDD 的影响 -- and the Art Bible is
## being amended to match: rules 8 and 9 (no normal/roughness/metallic/specular,
## flat colour from the 12-entry table) are about the *world*. They still hold
## for buildings, terrain, props and vegetation, and the art gates still enforce
## them there; assets/models/characters/ is exempt, listed in
## AssetScanner.SURFACE_RULE_EXEMPT_ROOTS so the exemption is a decision on the
## record rather than a silence.
##
## The material is assembled here rather than carried by the model because Meshy
## delivered the four maps as loose files next to the FBX -- only the albedo was
## ever embedded in it. Building it in Godot also keeps each map a separate
## imported texture, so the normal map gets normal-map compression and the
## albedo does not.
func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = body_radius
	shape.height = body_height
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, body_height * 0.5, 0.0)
	add_child(collider)

	var scene: PackedScene = load(MODEL_PATH)
	_model = scene.instantiate() as Node3D
	if _model == null:
		return
	# Named rather than left as the .glb's own root name, so the node path is
	# stable if the model is ever regenerated or replaced.
	_model.name = "Body"
	add_child(_model)
	_scale_to_body_height()

	var body_material := StandardMaterial3D.new()
	body_material.albedo_texture = load(ALBEDO_PATH)
	body_material.normal_enabled = true
	body_material.normal_texture = load(NORMAL_PATH)
	body_material.roughness_texture = load(ROUGHNESS_PATH)
	# metallic defaults to 0 and *multiplies* the map, so the map does nothing at
	# all until this is 1. roughness already defaults to 1 and needs no such line,
	# which is exactly the sort of asymmetry that gets a metallic map shipped
	# wired up and inert.
	body_material.metallic = 1.0
	body_material.metallic_texture = load(METALLIC_PATH)
	# Overridden rather than assigned into the mesh: the .glb's own surface
	# material is whatever Godot invented for a primitive that arrived without
	# one, and the model file is not the place to keep a material that is
	# assembled from four separate files.
	for surface in _mesh_instances(_model):
		surface.material_override = body_material

	_build_animation()


## Measured off the mesh rather than against a constant, so regenerating the
## model at a different size -- Meshy's scale is arbitrary -- changes nothing
## here. The bind-pose AABB stands on the model's origin, so its top edge is the
## figure's height.
func _scale_to_body_height() -> void:
	var meshes := _mesh_instances(_model)
	if meshes.is_empty() or meshes[0].mesh == null:
		return
	var box := meshes[0].mesh.get_aabb()
	var source := box.position.y + box.size.y
	if source < 0.1:
		return
	_model.scale = Vector3.ONE * (body_height / source)


func _mesh_instances(node: Node, found: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		_mesh_instances(child, found)
	return found


func _first_of_type(node: Node, type: StringName) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var found := _first_of_type(child, type)
		if found != null:
			return found
	return null


## Walk and run, blended by the speed the snow already decides.
##
## There is no idle take in the file -- one has been asked for. Until it lands
## the blend is simply frozen at zero speed: the time scale goes to zero with
## the ground speed, so a standing character holds the pose he stopped in rather
## than sliding along with his legs still cycling. Swapping in a real idle is
## one AnimationNodeAnimation and one more blend input.
func _build_animation() -> void:
	var player := _first_of_type(_model, &"AnimationPlayer") as AnimationPlayer
	if player == null:
		return
	if not player.has_animation(WALK_CLIP) or not player.has_animation(RUN_CLIP):
		push_warning("player_controller: %s is missing %s or %s" % [MODEL_PATH, WALK_CLIP, RUN_CLIP])
		return

	var walk := AnimationNodeAnimation.new()
	walk.animation = WALK_CLIP
	var run := AnimationNodeAnimation.new()
	run.animation = RUN_CLIP

	var graph := AnimationNodeBlendTree.new()
	graph.add_node("walk", walk)
	graph.add_node("run", run)
	graph.add_node("gait", AnimationNodeBlend2.new())
	graph.add_node("pace", AnimationNodeTimeScale.new())
	graph.connect_node("gait", 0, "walk")
	graph.connect_node("gait", 1, "run")
	graph.connect_node("pace", 0, "gait")
	graph.connect_node("output", 0, "pace")

	_animation = AnimationTree.new()
	_animation.name = "Gait"
	_animation.tree_root = graph
	add_child(_animation)
	_animation.anim_player = _animation.get_path_to(player)
	# Explicit, and not optional. The tracks are stored relative to the model's
	# own root ("Armature/Skeleton3D:Hips"), while AnimationMixer.root_node
	# defaults to the mixer's parent -- which here is the player, one level
	# above. Left at the default every track resolves to nothing and the
	# character stands in his bind pose with no error printed anywhere.
	_animation.root_node = _animation.get_path_to(_model)
	_animation.active = true


## Blend by speed, and play at the rate that actually covers the ground, so the
## feet plant instead of skating.
func _drive_animation() -> void:
	if _animation == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var gait := clampf(inverse_lerp(anim_walk_speed, anim_run_speed, speed), 0.0, 1.0)
	var reference := lerpf(anim_walk_speed, anim_run_speed, gait)
	_animation.set(&"parameters/gait/blend_amount", gait)
	_animation.set(&"parameters/pace/scale", clampf(speed / reference, 0.0, anim_max_pace))


## Non-positional, deliberately. The sources are stereo, which Godot spatialises
## badly, and these are the camera subject's own footsteps -- they are not
## coming from somewhere in the scene, they are coming from under you. Another
## character's steps would want AudioStreamPlayer3D and mono sources.
func _build_audio() -> void:
	var randomizer := AudioStreamRandomizer.new()
	# NO_REPEATS rather than RANDOM: with only two clips, plain random plays the
	# same one twice in a row a quarter of the time, and that is exactly the
	# artefact having two clips was meant to remove.
	randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	randomizer.random_pitch = step_pitch_spread
	randomizer.random_volume_offset_db = step_volume_spread_db
	for index in range(STEP_SOUND_PATHS.size()):
		randomizer.add_stream(index, load(STEP_SOUND_PATHS[index]))

	_steps = AudioStreamPlayer.new()
	_steps.stream = randomizer
	_steps.bus = &"Master"
	add_child(_steps)


func _on_footprint(payload) -> void:
	if not (payload is Dictionary):
		return
	var data: Dictionary = payload
	_play_step(float(data.get("depth_ratio", 0.0)))


## The clips are already single steps, so this is play-and-forget: no offset to
## seek to and no timer to stop it. The randomizer picks the clip and applies
## its own pitch and level spread; these two lines are the snow's contribution
## on top of that.
func _play_step(depth_ratio: float) -> void:
	if _steps == null or _steps.stream == null:
		return
	var depth := clampf(depth_ratio, 0.0, 1.0)
	_steps.volume_db = step_volume_db - step_depth_quieten_db * depth
	_steps.pitch_scale = 1.0 - step_depth_pitch_drop * depth
	_steps.play()


## Registered here rather than in project.godot because these four actions are
## the whole input surface of the slice and this keeps them in one readable
## place. `has_action` first, so a real input map added later wins.
func _register_actions() -> void:
	var bindings := {
		&"move_forward": [KEY_W, KEY_UP],
		&"move_back": [KEY_S, KEY_DOWN],
		&"move_left": [KEY_A, KEY_LEFT],
		&"move_right": [KEY_D, KEY_RIGHT],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)


func _resolve() -> void:
	if _snow != null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return
	_snow = registry.get_service(&"snow_field") as Node


func _physics_process(delta: float) -> void:
	_resolve()

	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	# Screen-relative, because the camera never rotates: "up" on the keyboard
	# has to mean "up the screen" or the fixed frame becomes unusable.
	var camera := get_viewport().get_camera_3d()
	var yaw := 0.0
	if camera != null:
		yaw = camera.global_rotation.y
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	var wade := 0.0
	if _snow != null:
		wade = _snow.wade_factor(global_position)
	var top_speed := lerpf(run_speed, wade_speed, wade)

	var wanted := direction * top_speed
	velocity.x = move_toward(velocity.x, wanted.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, wanted.z, acceleration * delta)
	velocity.y = 0.0

	var before := global_position
	move_and_slide()

	# No gravity and no floor collider: the ground is a displaced mesh with no
	# physics body, so the field is read directly. Feet land between the bare
	# ground and the snow surface -- on a scoured crest those are the same
	# place, in a hollow they are a metre apart and the body sinks into it.
	if _snow != null:
		var ground: float = _snow.terrain_height_at(global_position)
		var depth: float = _snow.depth_at(global_position)
		var wanted_y := ground + depth * (1.0 - sink_fraction)
		if _grounded:
			var blend := 1.0 - exp(-vertical_smoothing * delta)
			global_position.y = lerpf(global_position.y, wanted_y, blend)
		else:
			# First frame: land on the surface rather than easing down to it
			# from wherever the scene happened to place the body.
			global_position.y = wanted_y
			_grounded = true

	var travelled := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if travelled > 0.0001:
		_facing = Vector3(velocity.x, 0.0, velocity.z).normalized()
		_advance_stride(travelled)

	_face_travel(delta)
	_drive_animation()


## The model is authored facing +Z -- its `headfront` bone sits a few
## centimetres in front of `Head` along +Z -- rather than Godot's usual -Z, so
## the yaw that points it down a heading is atan2(x, z) and not atan2(x, -z).
## Getting that sign wrong makes a character who walks backwards perfectly
## convincingly, which is why it is written down.
func _face_travel(delta: float) -> void:
	if _model == null or _facing.length_squared() < 0.0001:
		return
	var wanted := atan2(_facing.x, _facing.z)
	var blend := 1.0 - exp(-turn_speed * delta)
	_model.rotation.y = lerp_angle(_model.rotation.y, wanted, blend)


func _advance_stride(travelled: float) -> void:
	_stride_accumulator += travelled
	while _stride_accumulator >= stride_length:
		_stride_accumulator -= stride_length
		_place_print()


func _place_print() -> void:
	var side := 1.0 if _left_foot else -1.0
	_left_foot = not _left_foot
	var lateral := Vector3(-_facing.z, 0.0, _facing.x) * side * stride_width
	var spot := global_position + lateral

	var depth := 0.0
	var max_depth := 1.0
	if _snow != null:
		depth = _snow.depth_at(spot)
		max_depth = maxf(_snow.max_depth_m, 0.0001)
	# A print in bare snow is a scuff; a print in a drift is a hole. Depth at
	# the spot, not a constant, is what makes a trail through a drift read
	# darker than one across a wind-scoured patch -- and sound different too.
	var depth_ratio := clampf(depth / max_depth, 0.0, 1.0)
	var strength := clampf(0.34 + 0.66 * depth_ratio, 0.0, 1.0)

	# The walker's centre line, not the foot. Recorded whether or not the event
	# goes out, so the next step measures its gap from the right place.
	var previous := _last_print_centre
	var had_previous := _has_last_print
	_last_print_centre = global_position
	_has_last_print = true

	if _bus == null:
		return

	# Everything below varies per step. The randomness lives here rather than
	# inside TrackMask so that a stamp stays a pure function of its arguments --
	# and because it is the *walker* that is inconsistent, not the snow.
	var heading := Vector2(_facing.x, _facing.z).rotated(
		randf_range(-print_heading_jitter, print_heading_jitter)
	)
	var scale := lerpf(print_thin_scale, 1.0, depth_ratio) * (
		1.0 + randf_range(-print_scale_jitter, print_scale_jitter)
	)

	# Which way the ground runs under this step. The gradient points uphill and
	# its length is tan(slope), so the fall line is its negative and cos(slope)
	# falls straight out of it.
	var fall := Vector2.ZERO
	var downhill_scale := 1.0
	if _snow != null:
		var gradient: Vector2 = _snow.surface_gradient_at(spot)
		var steepness := gradient.length()
		if steepness > 0.02:
			fall = -gradient.normalized()
			var cos_slope := 1.0 / sqrt(1.0 + steepness * steepness)
			downhill_scale = cos_slope * (1.0 + print_downhill_stretch * steepness)

	var payload := {
		"position": spot,
		"depth": depth,
		"depth_ratio": depth_ratio,
		"strength": strength,
		"radius": print_radius * scale,
		"forward": heading,
		"aspect": print_aspect * (1.0 + randf_range(-print_aspect_jitter, print_aspect_jitter)),
		"core": lerpf(print_core_thin, print_core_deep, depth_ratio),
		"irregularity": lerpf(print_irregularity_thin, print_irregularity_deep, depth_ratio),
		# Any large spread works; it only has to move the noise far enough that
		# two prints never see the same patch of it.
		"edge_seed": randf() * 997.0,
		"fall": fall,
		"downhill_scale": downhill_scale,
		# Barely wider than the print. This is the "influence beyond the mark"
		# that was spreading a metre of disturbed snow around every step.
		"pack_radius": print_radius * 1.2,
		# One boot does not flatten 40% of the snow column. It was that number
		# that dropped the ground under the character in a visible step every
		# time a print landed. A path still packs down -- it just takes the
		# dozen steps it should.
		"pack_amount": 0.09,
	}

	# Ramped in rather than switched on: a hard threshold would put a visible
	# line across the snow at whatever depth it sat at, with a channel on one
	# side of it and separate prints on the other.
	var trench := smoothstep(trench_depth_start, 1.0, depth_ratio)
	if trench > 0.0 and had_previous \
			and global_position.distance_to(previous) <= stride_length * trench_max_stride_gap:
		# DOWN THE CENTRE LINE, not from the last print to this one. Consecutive
		# prints alternate sides, so joining them draws a polyline that reverses
		# its lateral offset at every step -- an angular zigzag with a hard
		# corner in each print, which is what the second pass shipped and what
		# made it read as a snake rather than as snow. The walker's own path has
		# no such corners: it is a smooth curve sampled every stride, so the
		# segments meet almost straight. It is also what actually happens --
		# the legs plough a channel down the middle and the boots punch pockets
		# either side of it.
		payload["trench_from"] = previous
		payload["trench_to"] = global_position
		payload["trench_strength"] = strength * trench_strength * trench
		# Measured off the print's half-width, not its half-length -- the groove
		# is as wide as the leg that dragged through it, and the print is longer
		# than it is wide. At this width it reaches the inner edge of each print
		# and no further, which is the whole of the effect: the gap partly fills,
		# the outlines survive.
		payload["trench_radius"] = print_radius * scale / print_aspect * trench_width
		payload["trench_irregularity"] = trench_irregularity * trench

	_bus.emit_event(FOOTPRINT_EVENT, payload)
