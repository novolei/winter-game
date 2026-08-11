class_name CameraRig
extends Node3D

## The fixed three-quarter view. Set once in _ready() and never touched again;
## follow is position only, so nothing the player does can rotate the frame.
##
## Orthographic, not perspective. The deciding evidence is in the reference
## in-game frame: two characters standing at clearly different depths are drawn
## at almost identical heights. Perspective cannot do that at any playable
## distance -- only a parallel projection can -- and it is what gives the image
## its flat diorama read. This overrides the Art Bible's "slight perspective"
## in rule 1, which was written from the establishing shot in level.jpg.
##
## `size` is the *vertical* world extent of the frame (keep_aspect defaults to
## KEEP_HEIGHT). Under a pitched camera a standing figure of height h projects
## to h * cos(pitch), so the figure's share of frame height is
##
##     h * cos(pitch) / size
##
## and that is the number the reference pins down: 125 px of a 1101 px frame,
## about 11%. Everything else about the framing follows from it.

## A vertical wall projects at cos(pitch) of its height while the ground
## compresses by sin(pitch), so the ratio between them is 1/tan(pitch): at 57
## degrees a wall reads at 0.65 of its ground footprint and every building
## collapses into its own roof. At 45 it reads at exactly 1.0 -- a box looks
## like a box, a trunk reads as a long vertical line, and a standing figure
## reads as a figure instead of a shadow with a hat.
@export var pitch_degrees := 45.0
@export var yaw_degrees := -35.0

## Vertical world extent of the frame, in metres, and under a parallel
## projection the *only* control over apparent size -- boom_length moves the
## camera without changing the picture at all, and exists solely to keep
## geometry in front of the near plane.
##
## Set by measurement, not by arithmetic: the predicted value put the figure at
## 9.8% of frame height rather than 11%, because a capsule's silhouette under a
## pitched camera is wider than h * cos(pitch). 10.5 measures at 11.4%, against
## the reference's 125 px in 1101.
@export var orthographic_size := 10.5
@export var boom_length := 90.0

## Kept for the perspective fallback, unused while orthographic.
@export var field_of_view := 22.0
@export var use_orthographic := true

## Metres per second the rig closes on the target. Low enough that the frame
## drifts rather than snaps, high enough that a running player does not outrun
## the middle of the shot.
@export var follow_speed := 4.5

## Where in the frame the player sits. Pushed slightly forward of centre so
## there is room ahead and the trail behind stays in shot.
@export var target_height := 1.0

var _camera: Camera3D
var _target: Node3D


func _ready() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	rotation = Vector3(deg_to_rad(-pitch_degrees), deg_to_rad(yaw_degrees), 0.0)
	if _camera == null:
		return
	if use_orthographic:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = orthographic_size
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = field_of_view
	_camera.position = Vector3(0.0, 0.0, boom_length)
	_camera.rotation = Vector3.ZERO
	# Under a parallel projection the near plane is a real clipping plane at a
	# fixed distance rather than something distance hides, so it sits close to
	# the camera and the boom does the work of keeping the world in front of it.
	_camera.near = 0.05
	_camera.far = 400.0
	_camera.current = true


func _resolve() -> void:
	if _target != null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return
	_target = registry.get_service(&"player") as Node3D


func _process(delta: float) -> void:
	_resolve()
	if _target == null:
		return
	var wanted := _target.global_position + Vector3(0.0, target_height, 0.0)
	# Exponential smoothing, frame-rate independent: the fraction of the gap
	# closed per second is what is fixed, not the fraction closed per frame.
	var blend := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(wanted, blend)


## Used by the capture harness to skip the follow lag and frame the shot
## immediately.
func snap_to_target() -> void:
	_resolve()
	if _target == null:
		return
	global_position = _target.global_position + Vector3(0.0, target_height, 0.0)
