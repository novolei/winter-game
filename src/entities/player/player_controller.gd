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
## The blocked-out capsule here is a stand-in and nothing more; the real
## character arrives later.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const CEL_SHADER_PATH := "res://assets/shaders/cel_flat.gdshader"
const STEP_SOUND_PATHS := [
	"res://assets/audio/foley/footstep_snow_01.wav",
	"res://assets/audio/foley/footstep_snow_02.wav",
]
const FOOTPRINT_EVENT := &"player.footprint"

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

@export var body_height := 1.75
@export var body_radius := 0.28

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
var _stride_accumulator := 0.0
var _left_foot := true
var _facing := Vector3.FORWARD
var _grounded := false


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


## Built in code rather than saved into the scene so the capsule's colour can
## come from the palette instead of being a literal in a .tscn.
func _build_body() -> void:
	var bible: ColorBible = load(PALETTE_PATH)
	var shader: Shader = load(CEL_SHADER_PATH)

	var shape := CapsuleShape3D.new()
	shape.radius = body_radius
	shape.height = body_height
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, body_height * 0.5, 0.0)
	add_child(collider)

	var body_material := ShaderMaterial.new()
	body_material.shader = shader
	body_material.set_shader_parameter("lit_color", bible.structure_tones[1])
	body_material.set_shader_parameter("shade_color", bible.structure_tones[3])

	var capsule := CapsuleMesh.new()
	capsule.radius = body_radius
	capsule.height = body_height
	capsule.radial_segments = 12
	capsule.rings = 4
	var body := MeshInstance3D.new()
	body.mesh = capsule
	body.material_override = body_material
	body.position = Vector3(0.0, body_height * 0.5, 0.0)
	add_child(body)

	# Art Bible rule 12: the warm quota is 0.5% of the frame and the scarf is
	# one of the five places it is allowed to appear. At this camera distance
	# it is a handful of pixels, which is exactly the intent.
	var scarf_material := ShaderMaterial.new()
	scarf_material.shader = shader
	scarf_material.set_shader_parameter("lit_color", bible.warm_tones[1])
	scarf_material.set_shader_parameter("shade_color", bible.warm_tones[0])
	var scarf_mesh := BoxMesh.new()
	scarf_mesh.size = Vector3(body_radius * 2.1, 0.16, body_radius * 2.1)
	var scarf := MeshInstance3D.new()
	scarf.mesh = scarf_mesh
	scarf.material_override = scarf_material
	scarf.position = Vector3(0.0, body_height * 0.78, 0.0)
	add_child(scarf)


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

	_bus.emit_event(FOOTPRINT_EVENT, {
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
	})
