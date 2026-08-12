class_name MontageShot
extends Resource

## One camera move, and whatever is written in the world while it happens.
## UI design document sections 4.5 and 5.9.
##
## ---------------------------------------------------------------------------
## WHY A MONTAGE SHOT CARRIES ITS OWN CAMERA AND ITS OWN FOV
## ---------------------------------------------------------------------------
## The game's camera is ORTHOGRAPHIC (Art Bible rule 1), and an orthographic
## camera has no perspective to change: dollying it forward alters the framing
## and nothing else. Spatial typography depends entirely on the opposite -- the
## letters foreshorten because the camera is approaching them -- so a montage
## shot runs its own PERSPECTIVE camera with an authored field of view.
##
## That is not a breach of rule 1. Rule 1 is about the view the game is PLAYED
## in: fixed, never rotating, only following, so that every frame is a
## composition the player can learn. A montage is by definition a different
## camera language, and it happens when nobody is playing.
##
## fov_from and fov_to being separate also buys a dolly zoom for free, which is
## worth having available and worth using approximately never.
##
## ---------------------------------------------------------------------------
## THE TEXT HAS TO FIT INSIDE THE SHOT
## ---------------------------------------------------------------------------
## An inscription that is still scattering when the shot cuts loses its last
## glyphs mid-flight, and that is invisible until somebody watches the cut at the
## right moment. tests/unit/test_montage_data.gd asserts the fit for every
## authored shot, so it is a failing suite rather than a thing to notice later.

@export var duration := 8.0

## Where the camera starts and where it ends. Interpolated with
## Transform3D.interpolate_with, so rotation slerps rather than lerping through
## a squashed basis.
@export var camera_from := Transform3D.IDENTITY
@export var camera_to := Transform3D.IDENTITY

## Degrees. Wider than the game's 22 is usual here -- a long lens flattens the
## perspective change that the whole effect is made of.
@export var fov_from := 40.0
@export var fov_to := 40.0

## 0 is a constant-velocity dolly, 1 is fully eased at both ends. A push-in
## usually wants a little but not much: a dolly does move at a constant speed,
## and easing it hard reads as a camera that is being animated rather than moved.
@export_range(0.0, 1.0) var camera_ease := 0.35

## Empty for a shot that is only a camera move.
@export var text := ""

## Where the line STANDS. A fixed world transform, which is what makes the
## camera's approach change its perspective -- see Inscription.
@export var text_transform := Transform3D.IDENTITY

@export var text_font_size := 64
@export var text_pixel_size := 0.0045

## When in the shot the writing begins.
@export var text_start := 0.6

## Which way the wind takes it, and how far in metres.
@export var wind := Vector2(1.0, -0.25)
@export var scatter_metres := 1.4
@export var scatter_spin := 0.9

## Which of the six looks this shot is lit by. Empty leaves the lighting alone.
@export var lighting_preset: StringName = &""

func has_text() -> bool:
	return text.strip_edges() != ""

## Progress through the shot, after the authored easing. `t` is in seconds.
func progress_at(t: float) -> float:
	if duration <= 0.0:
		return 1.0
	var p := clampf(t / duration, 0.0, 1.0)
	# smoothstep blended toward linear by camera_ease, rather than chosen
	# between them, so the knob is continuous and a shot can be nudged.
	return lerpf(p, smoothstep(0.0, 1.0, p), clampf(camera_ease, 0.0, 1.0))

func camera_at(t: float) -> Transform3D:
	return camera_from.interpolate_with(camera_to, progress_at(t))

func fov_at(t: float) -> float:
	return lerpf(fov_from, fov_to, progress_at(t))
