class_name SnowfallLayer
extends GPUParticles3D

## One of the three layers of falling snow. Style document sections 21-23 --
## distant, near, and the one in front of the lens -- are the same emitter with
## different numbers, so this is one script and three scenes rather than three
## scripts.
##
## ---------------------------------------------------------------------------
## THE CAMERA IS ORTHOGRAPHIC, WHICH IS THE WHOLE REASON THE NUMBERS MOVED
## ---------------------------------------------------------------------------
## The style document's bands were written for a perspective camera, where a
## distant flake is small BECAUSE it is distant. Under a parallel projection a
## flake is the same size on screen whether it is two metres from the lens or
## ninety, so distance separates nothing at all: SIZE and SPEED are the only
## things that make one layer read as further away than another, and every
## figure here is a screen size first and a world size second.
##
## Over about a thousand pixels of frame height:
##
##   distant  3-5 px    specks, the texture of the air
##   near     5-9 px    the snow the player actually sees
##   lens     10-17 px  the one that crosses the picture
##
## and that arithmetic is also why this draws a SOFT DOT rather than the
## hexagonal flake the document prefers. At 5 px a hexagon is a dot with worse
## aliasing; at 17 px -- the largest flake in the game, and only on the lens
## layer -- it would be six pixels of star crawling through a moving frame. The
## document is right that a hexagon is the more artistic choice, and wrong that
## this camera can show one.
##
## ---------------------------------------------------------------------------
## THOSE ARE PIXELS, AND THE FRAME IS NOT A CONSTANT
## ---------------------------------------------------------------------------
## Every metre below was authored against ONE frame height, because at the time
## that was the only framing there was. The camera now cycles through several on
## Shift+wheel, EASES between them over a fifth of a second, and resolves the
## player's chosen stop through a ModifierStack so a later system can push the
## frame out during a whiteout or pull it in indoors.
##
## So the metres are not the authored quantity. `authored_frame` is the frame
## they were measured against, and everything metric on this layer is divided by
## it and multiplied by the frame the camera is ACTUALLY drawing -- every frame,
## so it follows the tween rather than snapping when the stop changes.
##
## THIS FILE MUST NEVER LEARN THE STOPS. They live in CameraRig, they are a
## player-facing list that will grow, and a copy of them here is the same defect
## one wave later. What arrives is a frame size in metres; where it came from is
## none of this layer's business.
##
## TWO SCALES, AND WHICH ONE A NUMBER TAKES IS DECIDED BY WHAT IT IS
##
## The EMISSION GEOMETRY -- the box, where it sits, how far back up the view axis
## it is pulled -- takes geometry_scale(). On the lens that is the frame, because
## a camera-space box is a statement about the picture. In the world it is FIXED:
## the box is a volume of air holding a fixed number of flakes at a fixed density,
## sized to cover the widest frame, and a tighter frame simply sees less of it.
## That is what makes "you are seeing more of the same snowstorm" literally true.
##
## The FLAKE -- its size, its fall, its drift -- scales only on the lens layer.
## flake_scale(), and the split is the whole of the art direction:
##
##   * Layers 1 and 2 are IN THE WORLD. A snowflake is a physical object at a
##     physical size, and zooming out must make it smaller on screen exactly as
##     it makes the trees and the character smaller. A world flake that held its
##     share of the screen would grow fatter as the player pulled back, and how
##     hard it is snowing -- a fact about the world -- would appear to change
##     every time he touched the camera.
##   * Layer 3 is ON THE LENS. It stands in for snow at or near the glass, it is
##     not in the world at all, and a camera-space effect does not zoom. Its
##     screen size is held constant.
##
## ---------------------------------------------------------------------------
## AND A FLOOR, BECAUSE PHYSICAL SCALING RUNS OUT
## ---------------------------------------------------------------------------
## Scaling a world flake honestly means that at a wide enough frame it stops
## being a flake and becomes a sub-pixel sample that shimmers as it moves.
## `min_flake_pixels` is the floor it is drawn at instead -- a small lie, drawing
## a distant speck slightly larger than it is, and worth it.
##
## When even the LARGEST flake in a layer is under the floor the lie is no longer
## small: every flake is the same clamped size and none is the size it should be.
## At that point the layer FADES OUT. A layer that can no longer draw a flake
## honestly should stop drawing, not alias.
##
## ---------------------------------------------------------------------------
## DENSITY IS `amount_ratio`, NEVER `amount`
## ---------------------------------------------------------------------------
## Writing `amount` re-allocates the particle buffer and every flake in the sky
## disappears on that frame. The weather moves continuously -- the lighting
## crossfades over eight seconds and the snow follows it -- so driving density
## through `amount` would empty and refill the sky sixty times a second for the
## whole of a phase change. The buffer is allocated once at the blizzard figure
## and `amount_ratio`, which does not restart anything, carries the weather.
##
## ---------------------------------------------------------------------------
## WHAT THE FLAKE MAY NOT DO
## ---------------------------------------------------------------------------
##   * It may not be warm. Art Bible rule 12 lists where warmth is allowed --
##     fire, windows, beacons, the scarf, the truck -- and snow is not on it, so
##     the colour is the palette's lightest snow tone taken most of the way to
##     white and never past neutral.
##   * It may not glow. Bloom belongs to the warm sources; snow catching the
##     bloom reads as cheap. The peak the flake can reach is kept under the
##     environment's glow threshold, and the blend is MIX rather than ADD.
##   * It may not acquire specular or roughness (rule 8). `unshaded` is the whole
##     of that in one property, and it is also why the flake needs no light.
##   * It may not cast a shadow. Two thousand flakes in an 8192 shadow map with
##     four splits is a large bill for something nobody can see.

const PALETTE_PATH := "res://data/palette/color_bible.tres"

## Where a layer publishes itself so Snowfall can find it. A group rather than a
## node path because the lens layer lives under the camera -- a node this system
## must not hold a reference to, since other systems are already inside it.
const GROUP := &"snowfall_layer"

## How much of a flake's life is spent fading up from nothing -- see
## _fade_ramp(), which is where it is actually spent. Named rather than buried in
## the ramp because it is also a DISTANCE: a flake falls while it fades, and the
## birth band has to clear the top of the picture by at least that far or the
## fade lands on screen. tests/unit/test_snowfall.gd measures exactly that.
const FADE_IN_FRACTION := 0.08

## ...and how much is spent fading back down to nothing at the end of it.
##
## Named for the same reason its sibling is, and it took longer to earn the name:
## this is ALSO a distance, and until the birth boxes were lifted off the ground
## it was a distance spent underground. A flake that meets the snow surface is
## deleted by the depth buffer at whatever opacity it happened to have, so the
## ramp only does its job for the part of the buffer born high enough to reach it
## -- which on the near layer was 5.9% of the box, and which nothing measured
## because 0.82 was a literal inside a gradient rather than a number with a name.
##
## tests/unit/test_snowfall.gd holds the birth box against it.
const FADE_OUT_FRACTION := 0.18

## ON THE LENS RATHER THAN IN THE WORLD. Layers 1 and 2 are false: the emitter
## follows the camera and its particles must NOT, or the whole snowfall slides
## along with the player. Layer 3 is true and is the deliberate opposite -- it
## rides the camera, it is not in world space, and style document section 23 is
## explicit that it does not need to be. It only has to cross the picture.
@export var camera_space := false

## The emission box, full size, centred on this node. In world metres for a
## world layer; in CAMERA metres for a lens layer, where x is across the frame
## and y is up it.
##
## FOR A CAMERA-SPACE LAYER x IS DERIVED, not read: the box has to span whatever
## the camera is currently drawing, which is a thing the scene file cannot know.
## The authored x is what that derivation comes to at `authored_frame`, and
## tests/unit/test_snowfall.gd holds the two to each other so the scene file
## stays a truthful description of the box rather than a dead number.
@export var volume_size := Vector3(36.0, 22.0, 36.0)

## THE UNIT EVERY METRE ON THIS LAYER IS EXPRESSED IN: the frame, in world
## metres, that these numbers were authored against -- x across and y up.
##
## NOT A FRAMING STOP, AND PLEASE DO NOT "FIX" IT INTO ONE. The y here happens to
## equal CameraRig's tightest stop, because that is the framing the art was tuned
## at -- but it is a DENOMINATOR, not a value the camera can be set to. Nothing
## here reads, stores, or compares against the list of stops; adding a fourth
## changes nothing in this file. That property is the one that matters, and it is
## why this survived review as a plain number rather than being rewritten as
## frame-fractions in the scene files, which would bake the same 10.5 into every
## authored fraction while making them unreadable.
##
## All it does is turn the authored metres into a ratio that holds at any frame
## the camera might present -- including one no stop names, which is where the
## frame sits for the whole of every eased zoom.
##
## A layer nobody has framed uses this as the frame, so every number below is
## used exactly as written: a unit-test subject, or a layer standing in a scene
## with no orthographic camera, behaves the way its scene file reads.
@export var authored_frame := Vector2(16.8, 10.5)

## The smallest a flake may be DRAWN, in pixels of frame height.
##
## Under about this a flake is no longer a flake: it is a sub-pixel sample that
## shimmers as it crosses the frame, and reads as video noise rather than as
## weather. Physical scaling walks the world layers toward it as the frame
## widens, so the size is clamped here rather than allowed to go under -- and if
## even the largest flake in the layer lands under it, the layer fades out
## instead. See legibility_floor_m() and legibility_fade().
##
## 2.5 px is this project's own figure, from the test that has guarded the flake
## sizes since the snowfall shipped.
@export var min_flake_pixels := 2.5

## How far below the floor a layer is completely gone: half of it, an octave. The
## fade runs across that interval so the layer leaves rather than blinks.
const FADE_OUT_OCTAVE := 0.5

## CAMERA-SPACE LAYERS ONLY -- how far above the top edge of the picture the
## BOTTOM of the birth band sits, in authored metres.
##
## This is the whole reason a lens flake appears to drift in rather than blink
## on, and it is not slack. It pays for two things:
##
##   * THE FADE. A flake spends its first FADE_IN_FRACTION of life fading up from
##     nothing and is falling the entire time, so a band that merely touched the
##     top edge would finish its fade on screen -- the same pop, one step softer.
##     That is 1.62 m of it at the blizzard's fall speed.
##   * ONE FRAME OF THE ZOOM. Godot steps a SceneTree tween AFTER the node
##     _process pass, so the frame the camera reports has already moved on by the
##     time anything reads it: measured at 60 fps as the top edge gaining 0.32 m
##     on the snow for exactly one frame after a notch is taken. The remainder
##     here absorbs that, with enough left over that the guarantee does not
##     quietly become frame-rate dependent.
##
## What shipped had none of this: the band was placed in absolute camera metres,
## so it stayed exactly where it was while the top edge of the frame moved away
## from it, and at the widest framing the whole band was 4 m inside the picture.
@export var lens_clearance_m := 2.4

## CAMERA-SPACE LAYERS ONLY -- how far the birth box overhangs the picture, in
## authored metres: `lead` on the side the drift blows FROM and `margin` on the
## other. A flake that crosses the frame sideways has to have come from
## somewhere, and the run-up is that somewhere.
##
## Which side is which is taken from `drift_blizzard`, not authored, so a layer
## re-tuned to blow the other way keeps its run-up instead of silently emitting
## its overhang downwind where nothing can use it.
@export var lens_lead_m := 7.6
@export var lens_margin_m := 1.6

## How far back up the view axis the volume sits, and the reason the snow is in
## frame at all. Read by Snowfall, which is what actually places the node; see
## Snowfall.volume_centre() for why backing up the view axis is what lifts the
## volume into the air without moving it on screen. Ignored by a lens layer.
@export var pullback_m := 16.0

## The particle count at nothing-much and at the day-7 blizzard. The buffer is
## allocated at the blizzard figure once; see the header.
@export var flakes_clear := 90
@export var flakes_blizzard := 1200

## How long a flake lives. Longer than it looks: with the fall speeds below a
## flake covers a good part of the volume in its life, and a life short enough
## to be safe is one where flakes visibly wink out mid-air.
@export var life_seconds := 11.0

## Birth size in metres. See the header for what these are in pixels, which is
## the number that actually matters.
@export var flake_size_min := 0.035
@export var flake_size_max := 0.055

## How fast a flake falls, clear and in the storm. The storm does not merely add
## flakes -- snow in a gale moves, and a blizzard made only of more flakes reads
## as a heavier shower.
@export var fall_speed_clear := 0.9
@export var fall_speed_blizzard := 2.1

## Downward acceleration. Nothing like gravity: a flake reaches its terminal
## speed in the first metre of a real fall, so what is wanted here is a gentle
## sag on top of the initial speed, not a stone.
@export var fall_accel := 0.2

## The sideways drift, clear and in the storm. This is the style document's
## "wind X / Z", and it belongs to the SNOWFALL rather than to any wind system:
## snow that falls dead straight looks wrong on a still day too.
##
## IT IS A VELOCITY, IN METRES PER SECOND, AND THE DOCUMENT'S NUMBER IS AN
## ACCELERATION. That is a deliberate departure and it was measured rather than
## reasoned: a sideways acceleration integrates twice over a lifetime of up to
## fourteen seconds, so at the document's 0.45 a flake travels forty-odd metres
## across a seventeen-metre frame and is gone before it has fallen through the
## picture. The first lens screenshot showed exactly that -- flakes visible only
## in the top third, because they had left sideways. A blown flake travels at a
## constant slant, which is what a velocity gives and what the eye reads as wind.
##
## The wind hook is still an acceleration, because a gust is a change. See
## set_wind().
@export var drift_clear := Vector3(0.25, 0.0, 0.08)
@export var drift_blizzard := Vector3(1.2, 0.0, 0.35)

## How much of a flake's start is randomised. The storm is the messier one.
@export var randomness_clear := 0.35
@export var randomness_blizzard := 0.55

## The cone the flakes leave the emitter in. Wide, because they are not being
## thrown anywhere -- they are drifting, and a narrow cone reads as a fountain.
@export var spread_degrees := 32.0

## How far the palette's lightest snow is taken toward white, and the most alpha
## a flake ever has. Both are bloom controls as much as colour ones -- see the
## header, and tests/unit/test_snowfall.gd, which pins the product of the two
## under the environment's glow threshold.
@export var flake_whiteness := 0.62
@export var flake_alpha := 0.78

var _rate := 0.0
var _wind := Vector3.ZERO
var _process_material: ParticleProcessMaterial

## What the camera is drawing, in world metres, or ZERO for "nobody has said".
## Pushed by Snowfall every frame -- see Snowfall.drive().
var _frame := Vector2.ZERO

## The frame the emission geometry was last rebuilt for. Rebuilding costs
## nothing but an assignment, and doing it only when the frame moves keeps the
## per-frame work to the two properties the weather actually changes.
var _applied_frame := Vector2(-1.0, -1.0)

## The same frame in pixels, for the legibility floor. Nothing geometric depends
## on it, so it never triggers a reframe.
var _pixels := Vector2.ZERO


func _ready() -> void:
	add_to_group(GROUP)
	_build()
	_apply()


## 0 clear .. 1 heavy, and the same word TrackMask chose for the same fact --
## see src/systems/track_mask.gd, which fills footprints in faster when it is
## told the same number. Snowfall pushes this to every layer in GROUP.
func set_snowfall_rate(rate: float) -> void:
	_rate = clampf(rate, 0.0, 1.0)


func snowfall_rate() -> float:
	return _rate


## THE WIND HOOK, in the vocabulary BreathFog's identically-named hook uses: an
## acceleration added to the flake's own drift. src/systems/wind_system.gd is
## Wave 3 and does not exist; until it does this stays at zero and the snow
## drifts anyway, on `drift_clear`..`drift_blizzard` above. A hook that leaves
## the effect inert until somebody writes the other end is a hook that ships
## broken.
##
## Snowfall.wind_velocity() is what normally calls this, so that a weather system
## can drive one number instead of finding three emitters.
func set_wind(velocity: Vector3) -> void:
	_wind = velocity


func wind() -> Vector3:
	return _wind


# --- the frame ---------------------------------------------------------------

## THE FRAMING HOOK. What the camera is drawing right now, in world metres: x
## across the picture and y up it. Snowfall pushes it every frame, from the
## camera itself, so it follows the framing tween continuously instead of
## snapping when the player's chosen stop changes.
##
## Vector2.ZERO means nobody has said, and then `authored_frame` stands in and
## every number on this layer is used exactly as its scene file writes it.
##
## THE GEOMETRY MOVES HERE, NOT ON THE NEXT _process(). Node order decides which
## of a layer and its director runs first, and the lens layer loses: it lives
## under the camera, which is above Snowfall in the scene. Waiting for its own
## next frame would therefore have it draw one frame of every zoom against the
## previous frame's framing -- measured, at 60 fps, as the birth band's clearance
## dipping by a third of a metre on the two frames after a notch was taken. The
## reframe costs two property writes; it can happen the moment it is known.
func set_frame_size(metres: Vector2) -> void:
	_frame = metres
	if _process_material != null and effective_frame() != _applied_frame:
		_reframe()


func frame_size() -> Vector2:
	return _frame


## How big that frame is in PIXELS. A second, separate fact from the frame in
## metres, and separate because it answers a different question: the legibility
## floor is about aliasing, aliasing is about pixels, and a floor converted
## through an assumed resolution would be a guess dressed as a measurement.
##
## Vector2.ZERO means nobody has said, and then there is no floor and no fade --
## which is the honest answer rather than a default one.
func set_frame_pixels(pixels: Vector2) -> void:
	_pixels = pixels


func frame_pixels() -> Vector2:
	return _pixels


## The frame actually in force: what was pushed, or what this layer was authored
## against when nothing has been.
func effective_frame() -> Vector2:
	return authored_frame if _frame.y <= 0.0 else _frame


## What the EMISSION GEOMETRY scales by, on every layer: the authored metres as a
## multiple of the frame now in force. Exactly 1.0 at the frame this layer was
## tuned against, which is the case in every unit test that does not say
## otherwise -- so the scene files stay readable as the thing they describe.
##
## The box is not a physical fact. It exists to hold the picture, so it grows
## when the picture does, whichever side of the lens the layer is on.
func frame_scale() -> float:
	if authored_frame.y <= 0.0:
		return 1.0
	return effective_frame().y / authored_frame.y


## What a FLAKE scales by -- its size, its fall, its drift -- which is a
## different question with a different answer per layer. See the header.
##
## 1.0 in the world, because a snowflake is a physical object and the camera
## moving must not change it. frame_scale() on the lens, because a camera-space
## effect stands outside the world and does not zoom with it.
func flake_scale() -> float:
	return frame_scale() if camera_space else 1.0


## What the EMISSION BOX scales by, which turns out not to be frame_scale()
## either -- and the reason is the whole of why the snow no longer thins out when
## the player zooms.
##
## A WORLD LAYER'S BOX IS A VOLUME OF AIR, NOT A VIEWPORT. It holds a fixed
## number of flakes at a fixed density, sized to cover the widest frame; a
## tighter frame simply sees less of it. That is what makes "you are seeing more
## of the same snowstorm" literally true: zoom out and the frame sweeps a larger
## cross-section of the same field, so it catches proportionally more flakes,
## each of them smaller, and the ink on screen stays put.
##
## A box that scaled WITH the frame did the opposite. It kept the same number of
## flakes in the picture while each one shrank, so the storm visibly eased off as
## the player pulled back -- measured at 62.8% of its coverage at the widest stop.
## Flake size was right by then and the weather still changed character when he
## touched the camera; the defect had only moved axis.
##
## It still grows if the frame outgrows it, because the alternative is a picture
## whose edges have no snow in them -- which is where this whole task started.
##
## ---------------------------------------------------------------------------
## DO NOT "OPTIMISE" THIS BACK INTO A BOX THAT SCALES
## ---------------------------------------------------------------------------
## A scaling box holds fewer particles at the tight framing, and that looks like
## free performance. It is not, and the obvious way to buy the coverage back --
## allocate for the widest frame and discard per-particle in the draw shader
## against a stable random -- was specified, considered, and rejected on two
## grounds:
##
##   1. IT WOULD COST THE TESTS THEIR EYES. Culling needs a ShaderMaterial, and
##      the moment the flake stops being a StandardMaterial3D the three art-rule
##      tests -- cool-white (rule 12), under the bloom threshold, no specular or
##      roughness (rule 8) -- can no longer read `albedo_color`, `blend_mode` or
##      `shading_mode`. They would be reduced to asserting against uniform names
##      invented for the occasion. Trading a test's ability to see an
##      engine-understood property for machinery that produces the same picture
##      is a bad trade.
##   2. IT WOULD BE SLOWER TO SETTLE. With a box that scales, particles already
##      in flight sit in the old smaller region while new ones are born in the
##      larger one, so the density needs a full particle lifetime -- eleven
##      seconds on the distant layer -- to even out across the new box. A fixed
##      volume of air has nothing to redistribute: the frustum does the
##      discarding, for free, on the frame the camera moves.
##
## The measured cost of doing it this way is 0.040 ms/frame for the whole
## snowfall at the widest stop, 3598 particles allocated across the three layers.
func geometry_scale() -> float:
	var scale := frame_scale()
	return scale if camera_space else maxf(1.0, scale)


## How many pixels a metre of frame height is worth right now. Zero when the
## viewport is unknown, which switches the legibility floor off rather than
## guessing at it.
func pixels_per_metre() -> float:
	var frame := effective_frame()
	if _pixels.y <= 0.0 or frame.y <= 0.0:
		return 0.0
	return _pixels.y / frame.y


## The smallest a flake may be drawn, in world metres: min_flake_pixels converted
## at the framing now in force. Zero -- no floor at all -- when the viewport is
## unknown.
func legibility_floor_m() -> float:
	var per_metre := pixels_per_metre()
	if per_metre <= 0.0:
		return 0.0
	return min_flake_pixels / per_metre


## 1 while the layer can still draw its flake honestly, 0 once it cannot, and a
## ramp between.
##
## Clamping a small flake up to the floor draws it slightly larger than it is,
## which is a lie worth telling. When even the LARGEST flake is under the floor
## the lie is the whole layer -- every flake the same clamped size, not one of
## them the size it should be -- and the honest move is to stop drawing rather
## than to alias. `largest_m` is the largest flake's size BEFORE the clamp,
## because after it there is nothing left to notice.
func legibility_fade(largest_m: float) -> float:
	var floor_m := legibility_floor_m()
	if floor_m <= 0.0 or largest_m >= floor_m:
		return 1.0
	var gone := floor_m * FADE_OUT_OCTAVE
	if largest_m <= gone:
		return 0.0
	return (largest_m - gone) / (floor_m - gone)


## The half-extents of the box new flakes are born in, in this node's own space.
##
## Pure arithmetic on the frame, which is what makes the whole of this checkable
## at any framing without a viewport, a camera or a rendered frame.
func emission_extents() -> Vector3:
	var scale := geometry_scale()
	var half := volume_size * 0.5 * scale
	if not camera_space:
		return half
	# DEPTH IS INERT IN CAMERA SPACE. Under a parallel projection nothing about a
	# flake changes with its distance from the lens, so the box's z is a place to
	# put the snow rather than a size -- and scaling it would push the near face
	# of the box back THROUGH the camera at the wider framings, where flakes are
	# born behind the lens and never seen.
	half.z = volume_size.z * 0.5
	half.x = _lens_span() * 0.5
	return half


## Where that box sits, in this node's own space.
##
## Zero for a world layer: Snowfall places the whole node, over whatever the
## camera is looking at. For a camera-space layer this is the entire fix -- see
## _reframe() for why the box moves and the NODE does not.
func emission_offset() -> Vector3:
	if not camera_space:
		return Vector3.ZERO
	var scale := geometry_scale()
	var band := volume_size.y * scale
	# THE POINT OF THE EXERCISE. The bottom of the band sits above the top edge of
	# the picture by the clearance, so a flake is born out of shot and drifts in.
	var bottom := effective_frame().y * 0.5 + lens_clearance_m * scale
	return Vector3(_lens_centre(), bottom + band * 0.5, 0.0)


## Across the frame, a camera-space box spans the whole picture plus its run-up.
## Derived rather than authored because the picture is not a fixed width: it
## grows with the framing AND with the window's aspect, and a box that covered it
## at one and not the other leaves a bare strip down one side of the frame that
## no still can show.
func _lens_span() -> float:
	return effective_frame().x + (lens_lead_m + lens_margin_m) * geometry_scale()


## ...and it is not centred on the picture. The long overhang goes on the side
## the drift blows FROM, which is where a flake crossing the frame has to have
## come from. Taken from the drift rather than authored: a layer re-tuned to blow
## the other way keeps its run-up.
func _lens_centre() -> float:
	var across := drift_blizzard.x
	if absf(across) < 0.0001:
		# Nothing blowing, so neither side is upwind and the overhang splits.
		return 0.0
	var scale := geometry_scale()
	return -signf(across) * (lens_lead_m - lens_margin_m) * 0.5 * scale


## How many flakes are actually being kept in the air, as against how many the
## buffer could hold. This is the number a screenshot shows and the one to
## assert against.
func flakes_alive() -> int:
	return int(round(float(amount) * amount_ratio))


## The velocity a flake is born with, at the weather currently set: the fall, and
## the slant the storm is blowing it at. What a screenshot shows is the ratio of
## the two.
##
## The wind hook is NOT in here. A gust is a change to a flake already falling,
## so it arrives as an acceleration on the process material's gravity; this is
## the flake's own steady travel.
func birth_velocity() -> Vector3:
	var drift := drift_clear.lerp(drift_blizzard, _rate)
	return Vector3(drift.x, -lerpf(fall_speed_clear, fall_speed_blizzard, _rate), drift.z)


func _build() -> void:
	var bible = load(PALETTE_PATH)

	# See the header: the buffer is sized once, for the storm, and never
	# re-allocated to change the weather.
	amount = maxi(flakes_blizzard, 1)
	lifetime = life_seconds
	# ALREADY SNOWING ON FRAME ONE. A GPUParticles3D starts empty and fills over a
	# whole lifetime, and now that a lens flake is born ABOVE the picture rather
	# than inside it, the first one does not even enter the frame for a second or
	# so -- which is a visibly thin sky for anything that looks early, including
	# every screenshot harness in tools/. One lifetime of preprocessing is exactly
	# the amount that reaches steady state, and it is the same intent as
	# Snowfall.settle(): the first frame of a run is the weather the day asks for,
	# not the start of it filling in.
	preprocess = life_seconds
	local_coords = camera_space
	explosiveness = 0.0
	one_shot = false
	# 30 simulation steps a second with interpolation between them. A flake
	# drifting at two metres a second does not need sixty, and this is a third of
	# the whole system's cost for nothing visible.
	fixed_fps = 30
	interpolate = true
	# Rule 10 makes the shadows the subject of the frame and they are cast at
	# 8192 across four splits. A thousand flakes do not belong in that map.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	_process_material = ParticleProcessMaterial.new()
	# Down. For a world layer this node is never rotated -- Snowfall only ever
	# translates it -- so local down is world down. For a lens layer the camera's
	# 45 degree pitch is the frame's own vertical, so local down is DOWN THE
	# SCREEN, which is what a flake crossing the lens has to do.
	_process_material.direction = Vector3(0.0, -1.0, 0.0)
	_process_material.spread = spread_degrees
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_material.color_ramp = _fade_ramp()
	# TURBULENCE IS OFF, AND STAYS OFF. It does not add a curl to the fall, it
	# MIXES the velocity toward a noise field that has no downward bias, so the
	# snow stops falling and hangs in the box it was emitted in -- measured at a
	# 40 m framing as a four-metre band of snow that should have been fourteen,
	# with every printed emitter number correct while it happened. The variation
	# the style document wants comes from `spread` and `randomness` instead, both
	# of which vary a flake's own straight path rather than replacing it.
	# tests/unit/test_snowfall.gd holds this shut.
	_process_material.turbulence_enabled = false
	process_material = _process_material
	_reframe()

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _flake_material(bible)
	draw_pass_1 = quad


## The emission box, moved and resized to the frame the camera is drawing.
##
## THE NODE DOES NOT MOVE, AND THAT IS NOT AN ACCIDENT. A camera-space layer
## simulates in LOCAL coordinates -- it has to, it rides the camera -- and a
## local-space emitter carries every particle already in flight along with it
## whenever it moves. Placing the birth band by setting `position` would drag the
## entire lens snowfall up the screen for the length of every zoom: one pop at
## one framing, traded for a smear during all of them.
##
## `emission_shape_offset` moves the birth REGION inside that local space
## instead, and reaches only the flakes not yet born. Nothing already falling
## notices, so a zoom changes what is emitted without disturbing what is emitted
## already -- which is also why size and velocity, both sampled at birth, cross a
## framing change without a seam.
func _reframe() -> void:
	if _process_material == null:
		return
	_applied_frame = effective_frame()
	var extents := emission_extents()
	var offset := emission_offset()
	_process_material.emission_box_extents = extents
	_process_material.emission_shape_offset = offset
	# A GPUParticles3D is culled by this box and not by where its particles
	# actually got to, so it has to cover the whole fall and the whole drift or
	# the snow vanishes the moment the emitter's own origin leaves the frame.
	# The box scales with the frame; how far a flake travels out of it scales with
	# the FLAKE, which in the world is not at all.
	var span := extents + _reach() * flake_scale()
	visibility_aabb = AABB(offset - span, span * 2.0)


## The furthest a flake gets from the box it was born in, per axis: the fall and
## the drift, both at their storm values, both over a whole life. Generous on
## purpose -- an over-large culling box costs a little culling, and one that is
## too small is a snowfall that blinks out of existence.
func _reach() -> Vector3:
	var seconds := maxf(life_seconds, 0.0)
	var fall := fall_speed_blizzard * seconds + 0.5 * fall_accel * seconds * seconds
	return Vector3(
		absf(drift_blizzard.x) * seconds,
		fall,
		absf(drift_blizzard.z) * seconds
	)


## Cool white, from the palette rather than from a literal, and unshaded so that
## rule 8's banned list has nothing to switch off. See the header for why it is
## a dot and not a hexagon.
func _flake_material(bible) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	var snow: Color = bible.snow_tones[0]
	surface.albedo_color = Color(
		lerpf(snow.r, 1.0, flake_whiteness),
		lerpf(snow.g, 1.0, flake_whiteness),
		lerpf(snow.b, 1.0, flake_whiteness),
		flake_alpha
	)
	surface.albedo_texture = _flake_texture()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# MIX, not ADD. Additive blending is a glow by another name, and two flakes
	# crossing would be brighter than either.
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	surface.billboard_keep_scale = true
	surface.disable_receive_shadows = true
	surface.vertex_color_use_as_albedo = true
	return surface


## A dot with a crisp core and a short falloff, NOT a soft blob. At five pixels
## across a gentle radial gradient has no solid centre left and the flake reads
## as a grey smudge; the core has to hold nearly to the rim for anything to
## survive being that small.
func _flake_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 0.82, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.45),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture


## In at the top of the volume, out at the bottom. Without the fade a flake
## appears and disappears in mid-air, which at this camera distance is the most
## obvious tell that snow is particles.
func _fade_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(
		[0.0, FADE_IN_FRACTION, 1.0 - FADE_OUT_FRACTION, 1.0]
	)
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _process(_delta: float) -> void:
	_apply()


## The weather, applied to the emitter. Everything here is a property that can
## be written while particles are in flight; nothing here re-allocates.
func _apply() -> void:
	if _process_material == null:
		return
	# Where the frame is now. Cheap enough to ask every frame, which is what
	# makes the snow follow an eased zoom rather than jump at the end of one.
	if effective_frame() != _applied_frame:
		_reframe()
	# The FLAKE's scale, not the box's. In the world these are different numbers
	# and the difference is the art direction -- see flake_scale().
	var scale := flake_scale()

	# The clear day is a FRACTION of the storm's buffer rather than a smaller
	# buffer -- see the header. Deliberately NOT scaled by the framing: the box
	# grows in every axis with the frame, so a fixed count keeps the same number
	# of flakes per screen area at every framing, which is the thing the style
	# document's counts were actually about.
	var floor_ratio := float(flakes_clear) / float(maxi(flakes_blizzard, 1))
	amount_ratio = clampf(lerpf(floor_ratio, 1.0, _rate), 0.0, 1.0)
	randomness = lerpf(randomness_clear, randomness_blizzard, _rate)

	# The slant goes into the DIRECTION the flake is born travelling in, not into
	# a sideways acceleration -- see drift_clear above for the measurement that
	# settled it. `direction` is in this node's own space, which for a world layer
	# is the world (Snowfall only ever translates it) and for a lens layer is the
	# frame itself.
	#
	# The SPEED carries the framing and the direction does not: scaling both would
	# be scaling the slant, and the slant is an angle.
	var velocity := birth_velocity()
	var speed := velocity.length()
	if speed > 0.0001:
		_process_material.direction = velocity / speed
	_process_material.initial_velocity_min = speed * 0.7 * scale
	_process_material.initial_velocity_max = speed * scale

	# Gravity is where a ParticleProcessMaterial keeps every constant
	# acceleration, so the flake's gentle sag and whatever the wind system is
	# gusting arrive here together -- and both scale, because a gale that changed
	# the snow's slant when the player zoomed would be the same defect this whole
	# section exists to remove.
	_process_material.gravity = (Vector3(0.0, -fall_accel, 0.0) + _wind) * scale

	# Born a little smaller when it is barely snowing. A clear sky with the same
	# flakes as a blizzard, only fewer, reads as a broken emitter.
	var size := lerpf(0.82, 1.0, _rate)
	var honest_min := flake_size_min * size * scale
	var honest_max := flake_size_max * size * scale
	# ...and never smaller than a flake can legibly be drawn. Under the floor a
	# flake is a shimmering sub-pixel sample rather than snow, so it is drawn AT
	# the floor instead -- and if the whole layer has arrived there, it leaves.
	#
	# ---------------------------------------------------------------------------
	# THE CLAMP IS NOT INK-NEUTRAL, AND THAT IS A DECISION, NOT AN OVERSIGHT
	# ---------------------------------------------------------------------------
	# Drawing a flake bigger than it honestly is adds coverage, and it adds more of
	# it the wider the frame gets, because more of the distribution falls under the
	# floor. Measured: with the snowfall at the PALE DAY rate the three stops carry
	# 100 / 143 / 141 per cent of the tightest one's ink, where a blizzard carries
	# 100 / 96 / 101. So in light snow the picture does gain snow as the player
	# pulls back, which is the one place "the weather must not change when the
	# frame moves" still does not hold.
	#
	# The fix is known and was costed: multiply amount_ratio by
	# (honest_area / drawn_area), so a clamped layer emits proportionally fewer,
	# bigger, legible flakes and the ink comes out exactly right. It is NOT taken,
	# and the reason is what amount_ratio does rather than what it computes:
	# lowering it does not remove particles already in flight, so the density
	# settles over a full lifetime -- five to fourteen seconds here. That lag would
	# sit on a PLAYER-INITIATED action; the zoom finishes in under half a second
	# and the snow would go on visibly settling for ten more, which reads as a bug.
	#
	# The error it would fix is a forty per cent change in about a sixth of the
	# snow, in the direction of more, in weather where the absolute quantity is
	# barely visible. An error nobody can see beats a lag everybody can.
	var floor_m := legibility_floor_m()
	_process_material.scale_min = maxf(honest_min, floor_m)
	_process_material.scale_max = maxf(honest_max, floor_m)
	# THE FADE IS JUDGED WITHOUT THE WEATHER IN IT -- flake_size_max at the current
	# framing, not the slightly smaller flake a clear day asks for.
	#
	# Measured the other way round first, and it was wrong: at 1280x800 the clear
	# day's 0.82 stacked on top of the framing and took the distant layer to 57%
	# faded at the widest stop, so the sky thinned out because it had stopped
	# snowing hard rather than because the frame had moved. The fade answers "can
	# this LAYER be drawn at this FRAMING", which is a question about the camera
	# and the resolution and nothing else. The weather still moves the flake's
	# size; the clamp still keeps every individual flake legible while it does.
	transparency = clampf(
		1.0 - legibility_fade(flake_size_max * scale), 0.0, 1.0
	)
