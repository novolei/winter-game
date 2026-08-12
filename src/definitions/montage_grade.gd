class_name MontageGrade
extends Resource

## The look of a montage: what is in focus, what the air does, and how much film
## is between the lens and the eye. UI design document section 4.5.
##
## ---------------------------------------------------------------------------
## WHY THIS IS NOT THE GAME'S LOOK, AND MUST NOT BECOME IT
## ---------------------------------------------------------------------------
## Art Bible section 1.2 sets two quantified acceptance lines for the GAME's
## frame -- snow lands at 62% of white, and the blue channel runs about 121
## points over the red -- measured after lighting and tonemapping. Grain, a
## vignette and heavy aerial fog move every one of those numbers. So this grade
## belongs to the montage, which happens when nobody is playing, in the same way
## and for the same reason the montage camera is perspective while the game's is
## orthographic (see MontageShot).
##
## It is applied through Camera3D.environment and Camera3D.attributes, which are
## OVERRIDES: they exist while the montage camera does and the world's own
## environment resumes the moment it goes away. Nothing has to be restored, so
## nothing can be restored wrongly.
##
## ---------------------------------------------------------------------------
## THE FOCUS IS NOT AUTHORED
## ---------------------------------------------------------------------------
## `focus_padding` is a distance PAST THE LINE, not a distance from the camera.
## MontageDirector measures the camera to the inscription every frame and puts
## the far blur just behind it, so the text stays sharp while the valley softens
## and the focus pulls itself as the camera comes in. An authored focus distance
## would be wrong on the first frame the camera moved, which is every frame.

## ---------------------------------------------------------------------------
## THESE NUMBERS ARE THE SECOND PASS, AND THE FIRST ONE IS THE LESSON
## ---------------------------------------------------------------------------
## Every value here started roughly three times higher, and the captured frame
## came back as a heavy filter rather than as a look: the vignette closed into a
## tunnel, the fog washed the snow off the palette entirely -- Art Bible section
## 1.2's blue-over-red of about 121 points went to nearly zero -- and the glow
## turned the farmhouse wall into one bloom.
##
## A grade is meant to be FELT and not SEEN. The way to tell is to cover the
## frame's corners: if the middle still looks graded, it is too much. What is
## left below is enough to change how the picture feels and not enough to argue
## with the twelve colours underneath it.

# --- depth of field ---------------------------------------------------------

@export var dof_enabled := true

## How far past the line the far blur starts, in metres. Enough that the line's
## own depth -- it stands at an angle, so its far end is metres further away --
## is comfortably inside the sharp zone.
@export var focus_padding := 3.0

## Over how many metres the far blur reaches full strength.
@export var dof_far_transition := 22.0

## Godot's blur radius. Small numbers go a long way; past about 0.1 the
## background stops reading as a place and becomes a wash.
@export_range(0.0, 0.3) var dof_amount := 0.022

## Near blur is off by default. A foreground this empty has nothing to soften,
## and switching it on mostly blurs the line itself the moment the camera
## overshoots it.
@export var dof_near_enabled := false
@export var dof_near_distance := 1.2
@export var dof_near_transition := 1.0

# --- the air ----------------------------------------------------------------

@export var fog_enabled := true

## Written by tools/generate_montages.gd out of the palette, never here
## (briefing constraint 6).
@export var fog_colour := Color.WHITE

@export_range(0.0, 0.2) var fog_density := 0.0035

## How much the fog takes its colour from what is behind it rather than from
## fog_colour. High values read as real aerial perspective; low values as a
## flat wash laid over the distance, which is the more stylised of the two and
## the one that suits a twelve-colour world.
@export_range(0.0, 1.0) var fog_aerial_perspective := 0.12

@export_range(0.0, 1.0) var fog_sky_affect := 0.15

## Fog that thins with height, so the valley floor sits in it and the roofs
## come out of it.
@export var fog_height := 6.0
@export var fog_height_density := 0.02

# --- the glow ---------------------------------------------------------------
#
# This is what softens the letters. Label3D draws a hard alpha edge and there is
# no blur on it; bloom bleeding out of the amber is what turns that edge into
# light rather than into a cut. It also does the job the design wants it to do
# in the first place -- warm is the presence of heat (rule 3), and heat glows.

@export var glow_enabled := true

## The amber is multiplied by this before it is drawn, to push it over the
## environment's HDR threshold. Below the threshold nothing blooms at all, which
## is the failure that looks like "glow does not work".
@export_range(1.0, 4.0) var text_emission := 1.9

@export_range(0.0, 2.0) var glow_bloom := 0.10
@export_range(0.0, 4.0) var glow_hdr_threshold := 1.25
@export_range(0.0, 2.0) var glow_strength := 0.85
@export_range(0.0, 4.0) var glow_intensity := 0.40

# --- the film -----------------------------------------------------------------

## Grain is applied more strongly in shadow than in highlight, which is how film
## actually behaves -- a uniform layer of noise reads as a dirty screen.
@export_range(0.0, 0.3) var grain_amount := 0.055

## Grain cell size in screen pixels. At 1.0 it is per-pixel and disappears into
## the display; a little larger and it reads as emulsion.
@export_range(0.5, 6.0) var grain_size := 1.8

## How much of the grain survives into the highlights.
@export_range(0.0, 1.0) var grain_highlight_falloff := 0.3

@export_range(0.0, 1.0) var vignette_amount := 0.20

## Where the vignette starts and finishes, as a fraction of the half-diagonal.
@export_range(0.0, 1.5) var vignette_start := 0.78
@export_range(0.0, 1.5) var vignette_end := 1.40

## Also out of the palette. A vignette to black would put a colour in the frame
## that is not one of the twelve, at the edges of every montage frame.
@export var vignette_colour := Color.BLACK
