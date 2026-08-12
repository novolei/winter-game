extends Node

## Photographs the two body readouts that had none -- hunger and frostbite -- at
## the framing the game is actually played at.
##
##   Godot_console.exe --path <project> res://tools/capture_body_readouts.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/body --takes
##
## Modes:
##   --takes    the candidate walk clips, side by side, one figure each. Answers
##              "which of these actually limps" with a picture rather than with a
##              correlation coefficient.
##   --posture  a ladder of blend VALUES at one instant, which is the only
##              instrument that can show a posture change (briefing, "blending
##              posture is not blending amplitude"). A sheet stepping TIME cannot:
##              every frame of it is a plausible pose.
##
## The camera is the game's -- CameraRig's pitch 45, yaw -35, orthographic, and
## its 10.5 m stop -- because the acceptance question is whether a player can
## tell these apart while playing, not whether an animator can tell them apart in
## a viewport. A figure is 11.4% of frame height there and that is the whole
## difficulty of the task.

const MODEL_PATH := "res://assets/models/characters/winter_wanderer.glb"
const ALBEDO_PATH := "res://assets/models/characters/winter_wanderer_albedo.png"
const NORMAL_PATH := "res://assets/models/characters/winter_wanderer_normal.png"
const ROUGHNESS_PATH := "res://assets/models/characters/winter_wanderer_roughness.png"
const SCHEME_PATH := "res://data/characters/wanderer_pale.tres"

const PlayerControllerScript := preload("res://src/entities/player/player_controller.gd")

const PITCH_DEGREES := 45.0
const YAW_DEGREES := -35.0

## The game's default stop. tools/capture_body_readouts --ortho overrides it, and
## a tight number is for diagnosing, never for judging.
const GAME_ORTHO := 10.5

var _out := "user://body"
var _ortho := GAME_ORTHO
var _mode := "takes"
var _camera: Camera3D = null
var _figures: Array = []


func _ready() -> void:
	_read_arguments()
	_build_world()
	await RenderingServer.frame_post_draw
	match _mode:
		"posture":
			await _capture_posture()
		"ladder":
			await _capture_ladder()
		_:
			await _capture_takes()
	get_tree().quit()


func _read_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--out" and index + 1 < args.size():
			_out = args[index + 1]
		elif args[index] == "--ortho" and index + 1 < args.size():
			_ortho = float(args[index + 1])
		elif args[index] == "--takes":
			_mode = "takes"
		elif args[index] == "--posture":
			_mode = "posture"
		elif args[index] == "--ladder":
			_mode = "ladder"


# --- the world ----------------------------------------------------------------

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Off-palette on purpose: this is a diagnostic sheet, not a frame of the game.
	# A pale flat ground is what makes a dark silhouette's legs readable, which is
	# the entire job here.
	env.background_color = Color(0.66, 0.70, 0.76)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.88)
	env.ambient_light_energy = 0.9
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-70.0), 0.0)
	sun.light_energy = 1.5
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.80, 0.84, 0.90)
	ground.material_override = material
	add_child(ground)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _ortho
	var aim := Vector3(deg_to_rad(-PITCH_DEGREES), deg_to_rad(YAW_DEGREES), 0.0)
	_camera.rotation = aim
	var back := Basis.from_euler(aim).z
	_camera.position = Vector3(0.0, 1.0, 0.0) + back * 40.0
	_camera.near = 0.05
	_camera.far = 120.0
	add_child(_camera)
	_camera.make_current()


## One figure: the character model, scaled to the controller's body height, wearing
## the shipped scheme, with the merged library on its AnimationPlayer and manual
## advance so the sheet samples exact intervals rather than this machine's frame
## rate.
##
## `slot` is a position along the camera's own right vector rather than along
## world X. A row laid out in world space runs diagonally across a frame yawed
## -35 degrees and half of it falls out of shot; a row laid out in camera space
## is a row on the screen, which is what a comparison sheet needs.
func _add_figure(slot: float, facing: Vector3) -> Dictionary:
	var scene: PackedScene = load(MODEL_PATH)
	var model := scene.instantiate() as Node3D
	add_child(model)
	var right := _camera.global_transform.basis.x
	model.position = Vector3(right.x, 0.0, right.z).normalized() * slot
	model.rotation.y = atan2(facing.x, facing.z)
	# The same scale PlayerController._scale_to_body_height() applies: the glTF
	# rig is authored in centimetres and stands a hundred times too tall
	# otherwise (briefing trap 15.3).
	var aabb := _aabb_of(model)
	if aabb.size.y > 0.0001:
		var factor := 1.88 / aabb.size.y
		model.scale = Vector3(factor, factor, factor)
	_wear_the_scheme(model)
	var player := _first(model, "AnimationPlayer") as AnimationPlayer
	if player != null:
		if player.has_animation_library(&""):
			player.remove_animation_library(&"")
		player.add_animation_library(&"", WandererAnimations.build())
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var figure := {"model": model, "player": player}
	_figures.append(figure)
	return figure


## The four maps and the tint PlayerController._build_body() assembles. Without
## it the figure renders in whatever StandardMaterial3D defaults to -- white
## plastic -- and a silhouette judgement made against a white figure on pale snow
## is a judgement about the harness.
func _wear_the_scheme(model: Node3D) -> void:
	var scheme := load(SCHEME_PATH) as CharacterScheme
	if scheme == null:
		scheme = CharacterScheme.new()
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(ALBEDO_PATH)
	material.albedo_color = scheme.albedo_tint
	if scheme.normal_map_enabled:
		material.normal_enabled = true
		material.normal_texture = load(NORMAL_PATH)
	if scheme.roughness_map_enabled:
		material.roughness_texture = load(ROUGHNESS_PATH)
	for mesh in _all(model, "MeshInstance3D"):
		(mesh as MeshInstance3D).material_override = material


func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh in _all(node, "MeshInstance3D"):
		var here: AABB = (mesh as MeshInstance3D).get_aabb()
		box = here if first else box.merge(here)
		first = false
	return box


func _first(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var found := _first(child, type)
		if found != null:
			return found
	return null


func _all(node: Node, type: String, found: Array = []) -> Array:
	if node.is_class(type):
		found.append(node)
	for child in node.get_children():
		_all(child, type, found)
	return found


# --- the sheets ---------------------------------------------------------------

## Cell size for a contact sheet. The figure is narrow, so a square frame spends
## most of itself on background; each shot is cropped to a portrait strip down
## the middle before it goes on the sheet.
const CELL_W := 300
const CELL_H := 560
const COLUMNS := 8


func _shot() -> Image:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _cell() -> Image:
	var image: Image = await _shot()
	var full := image.get_size()
	var strip := int(float(full.y) * float(CELL_W) / float(CELL_H))
	image = image.get_region(Rect2i((full.x - strip) / 2, 0, strip, full.y))
	image.resize(CELL_W, CELL_H, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	return image


## The candidate walks, ONE ROW PER TAKE, columns stepping across that take's own
## gait cycle.
##
## Each row is one figure standing in the same place under the same light, so a
## difference between two rows is a difference between two takes. Each row is
## sampled across ITS OWN cycle rather than across a shared duration, because the
## cycles are 1.07, 1.19 and 1.45 seconds long and a shared window would sample
## one of them at a different point of its stride than another and call that a
## difference in gait.
func _capture_takes() -> void:
	var clips := ["walk", "walk_limp", "walk_weary"]
	# Measured cycle length, not clip length: walk_limp is three cycles in one take
	# and walk_weary is six, so playing "the clip" would step six strides in a row
	# of six columns and photograph the same pose six times.
	var cycles := {
		"walk": 1.0667, "walk_limp": 1.1889, "walk_weary": 1.4500,
		"walk_carry": 1.1333, "idle": 3.0, "idle_cold": 3.0,
	}
	# In profile to the camera. A gait is judged from the side -- which leg swings
	# and how far -- and the game's own three-quarter view is a harder read, so a
	# take that fails here fails everywhere.
	var basis := _camera.global_transform.basis.x
	var facing := Vector3(basis.x, 0.0, basis.z)
	var figure := _add_figure(0.0, facing)
	var player: AnimationPlayer = figure["player"]
	var sheet := Image.create_empty(CELL_W * COLUMNS, CELL_H * clips.size(), false, Image.FORMAT_RGBA8)
	for row in range(clips.size()):
		var clip: String = clips[row]
		if player == null or not player.has_animation(clip):
			continue
		var cycle: float = cycles.get(clip, 1.0)
		player.play(clip)
		player.seek(0.0, true)
		for column in range(COLUMNS):
			player.advance(cycle / float(COLUMNS))
			var frame: Image = await _cell()
			sheet.blit_rect(
				frame, Rect2i(0, 0, CELL_W, CELL_H), Vector2i(CELL_W * column, CELL_H * row)
			)
	var path := "%s_takes.png" % _out
	sheet.save_png(path)
	print("capture_body_readouts: %s  rows top to bottom: %s" % [path, str(clips)])


## ---------------------------------------------------------------------------
## THE LADDER: BLEND VALUES AT ONE INSTANT, NOT TIME AT ONE BLEND
## ---------------------------------------------------------------------------
## `walk` and `walk_guarded` differ in POSTURE, and the briefing's own note says
## what that means for the instrument: "a contact sheet stepping TIME at one
## blend value cannot show this -- every frame looks like a plausible pose. Step
## the BLEND VALUE at one instant instead and read the silhouettes."
##
## So every column below is the same moment of the same cycle, and the ONLY thing
## that changes across the row is the number. Where the silhouette stops looking
## like an ordinary walk is where GUARDED_WALK_FLOOR belongs.
##
## Two rows, because a gait has no single instant that represents it: one at
## mid-stance and one at mid-swing. A floor that only reads at one of them is a
## floor that reads half the time.
func _capture_ladder() -> void:
	var player := PlayerControllerScript.new()
	add_child(player)
	player.set_physics_process(false)
	var tree := player.get_node_or_null("Gait") as AnimationTree
	if tree == null:
		push_error("capture_body_readouts: the controller built no AnimationTree")
		return
	# MANUAL, or the tree advances twice per iteration -- once on its own with the
	# real frame delta and again on the explicit advance() below, which would put
	# this machine's frame rate inside the measurement.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var right := _camera.global_transform.basis.x
	player.position = Vector3.ZERO
	var body := player.get_node_or_null("Body") as Node3D
	if body != null:
		body.rotation.y = atan2(right.x, right.z)

	var values := [0.0, 0.30, 0.45, 0.60, 0.80, 1.0]
	var moments := [0.0, 0.5]
	var sheet := Image.create_empty(
		CELL_W * values.size(), CELL_H * moments.size(), false, Image.FORMAT_RGBA8
	)
	tree.set(&"parameters/motion/blend_amount", 1.0)
	tree.set(&"parameters/gait/blend_amount", 0.0)
	tree.set(&"parameters/pace/scale", 1.0)
	for row in range(moments.size()):
		# Advance to the moment ONCE, then hold it: every column of a row is the
		# same frame of the cycle with only the blend moved.
		tree.set(&"parameters/footing/blend_amount", 0.0)
		tree.advance(0.0)
		tree.advance(float(moments[row]) * player._cycle_period)
		for column in range(values.size()):
			tree.set(&"parameters/footing/blend_amount", float(values[column]))
			tree.advance(0.0)
			var frame: Image = await _cell()
			sheet.blit_rect(
				frame, Rect2i(0, 0, CELL_W, CELL_H), Vector2i(CELL_W * column, CELL_H * row)
			)
	var path := "%s_ladder.png" % _out
	sheet.save_png(path)
	print("capture_body_readouts: %s  columns %s, rows = mid-stance then mid-swing" % [
		path, str(values),
	])


## A ladder of blend VALUES at one instant. See the briefing note this exists for.
func _capture_posture() -> void:
	var clips := ["idle", "idle_cold"]
	var spacing := 2.2
	var left := -spacing * float(clips.size() - 1) * 0.5
	var facing := _camera.global_transform.basis.x
	for index in range(clips.size()):
		var figure := _add_figure(left + spacing * float(index), Vector3(facing.x, 0.0, facing.z))
		var player: AnimationPlayer = figure["player"]
		if player != null and player.has_animation(clips[index]):
			player.play(clips[index])
			player.seek(0.5, true)
	var image: Image = await _shot()
	var path := "%s_posture.png" % _out
	image.save_png(path)
	print("capture_body_readouts: %s  (%s)" % [path, str(clips)])
