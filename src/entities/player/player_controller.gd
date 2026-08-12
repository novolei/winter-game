class_name PlayerController
extends CharacterBody3D

## Walks, runs, and writes the lines in the snow.
##
## Speed is not a key. It is read off the ground -- how deep the snow is and how
## steeply it runs under the direction he is walking -- and the run is something
## he earns by keeping going rather than something he holds a button for. A drift
## drops him to a trudge, a bank slows him whether he is climbing it or dropping
## down it, and a path he has already flattened lets him run again. That last one
## is the point of SnowField having a packed layer at all -- the shortcut you beat
## into the snow is a real one.
##
## The whole speed model is the block headed HOW FAST A MAN CROSSES A SNOWFIELD
## below, and tests/unit/test_locomotion.gd checks it against the real world
## rather than against itself.
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
const FURROW_EVENT := &"player.furrow"

## The four takes this slice uses, out of the twenty-one in the merged library.
## Shooting, aiming, sneaking, the limp, the knockdown and the two deaths are
## all built and addressable -- see WandererAnimations -- and belong to later
## waves.
const IDLE_CLIP := WandererAnimations.IDLE
const IDLE_COLD_CLIP := WandererAnimations.IDLE_COLD
const WALK_CLIP := WandererAnimations.WALK
const RUN_CLIP := WandererAnimations.RUN

## The visual layer the character's own surfaces are put on, so a light can be
## aimed at him and at nothing else. Bit 0 stays set: the sun still lights him
## and he still casts into the world's shadow map.
const CHARACTER_LAYER := 1 << 1

## Where the breath comes from: metres from the Head bone, in the CHARACTER's
## frame -- +Y up, +Z the way he faces -- not in the bone's own.
##
## The rig has no jaw or mouth bone. It has 24, of which `Head` is the pivot at
## the base of the skull, `head_end` the crown and `headfront` a marker 18 cm
## straight out in front of the pivot. Measured off the mesh rather than guessed
## at, because the character is HOODED and the hood is what makes guessing wrong:
## scanning the head vertices by height, the coat collar reaches 1.395 m and the
## hood's brow juts forward again at 1.52-1.56 m, and the face sits in the recess
## between them, its surface at z = +0.109..+0.116 over the band 1.41-1.47 m.
## `headfront` is level with the brow, not with the mouth -- it marks the front of
## the HOOD.
##
## So the mouth is about a third of the way up that recess, at world height
## 1.43 m in the rest pose, which is 0.16 m above the Head pivot and 0.15 m in
## front of it; 0.17 here so the puffs are born just clear of the skin rather
## than inside it.
##
## The value it replaces, (0, -0.03, 0.17), was wrong twice over. It was
## interpreted in the head bone's rolled frame -- whose +Z pitches 36 degrees
## downward -- so "17 cm forward and 3 cm down" landed 12.5 cm BELOW the pivot
## and put the breath at his collarbone. _build_breath() now rotates this into
## the bone frame, so the comment above is true of what actually happens.
const BREATH_BONE := &"Head"
const BREATH_MOUTH_OFFSET := Vector3(0.0, 0.16, 0.17)

## ---------------------------------------------------------------------------
## HOW FAST A MAN CROSSES A SNOWFIELD
## ---------------------------------------------------------------------------
## The owner's ruling is the whole specification:
##
##   整体的速度需要受到地形的坡度和雪的厚度影响 ... 不管是行走还是奔跑只受到雪深
##   度和地形坡度的影响，但是整体的速度设计需要符合现实世界的理解和定义
##
## Two terrain inputs -- snow depth and the grade underfoot -- acting on the walk
## and the run alike, and a scale that answers to the real world. So:
##
##     speed = lerp(walk_speed, run_speed, gait) * terrain_factor(wade, grade)
##     terrain_factor = lerp(1, snow_factor * slope_factor, terrain_severity)
##
## and nothing else about the terrain multiplies it. `gait` is the auto-run
## promotion, eased, in 0..1. See top_speed_at(), and see terrain_severity for
## why the product is compressed rather than used raw.
##
## THE SCALE, in metres per second so it can be read against the model without
## converting anything:
##
##     stroll                1.1
##     ordinary walking      1.3 - 1.4
##     brisk walking         1.6
##     jogging               2.5 - 3.0
##     a fit person's run    3.5 - 4.5
##     a brief sprint        6   - 8
##
## The run shipped at 5.4 m/s. That is a 3:05/km pace -- inside elite marathon
## speed -- for a cold, burdened man in winter clothing crossing a snowfield, and
## it was the single reason clear ground felt wrong.
##
## It was also breaking the animation, invisibly. The run take covers 4.6 m/s of
## ground at rate 1 (anim_run_speed, measured off the clip), so at 5.4 the legs
## were played 17% faster than they carried him and the feet skated. Any run
## speed inside [anim_walk_speed, anim_run_speed] plants them -- see
## _drive_animation(), where `reference` collapses to the speed itself and the
## pace scale is exactly 1 across that whole band.
##
## 3.3 m/s is a 5:03/km jog: 2.4 times the walk, well inside what the run clip
## covers, and a pace a man in a heavy coat can hold across a field. He should
## never look like an athlete.
@export var run_speed := 3.3

## How fast he reaches whatever the terrain lets him do, in m/s^2.
##
## FLAT, AND DELIBERATELY NOT SCALED BY THE TERRAIN. A body that is slow but
## answers the key instantly feels fine; a body that is slow AND sluggish to
## start, stop and turn feels like wading through treacle, and only the first was
## ever asked for. They are different qualities and the terrain owns exactly one
## of them -- how fast he can go, never how quickly he agrees to go it.
##
## At 12 m/s^2 he reaches a 0.4 m/s trudge in two physics ticks and stops from it
## in two more, so pressing a direction in the deepest snow still produces
## immediate movement. Multiplying this by terrain_factor() would be the obvious
## next "realism" edit and it is the one to refuse.
@export var acceleration := 12.0

## The walk, and the one number in this file that was already right.
##
## 1.35 m/s is not a chosen number: it is `anim_walk_speed`, the ground speed at
## which the walk cycle plays at rate 1, so his feet plant instead of skating.
##
## THAT IT AGREES WITH TOBLER IS THE CORROBORATION, NOT THE CAUSE. Tobler's
## hiking function on the level gives 5.04 km/h = 1.40 m/s (see TOBLER_DECAY
## below), and this was derived from an animation clip with no reference to it.
## Two independent derivations landing within 4% of each other is the strongest
## evidence available that the scale of this whole model is right, and it is why
## the rest of it could be hung off Tobler with any confidence.
##
## It is also what is left when the body cannot run any more. GDD section 5's
## 疲劳归零后果 is 无法奔跑 -- cannot RUN -- and the survival model says so by
## putting `locomotion:run_speed` to zero. A body that read that as its top speed
## would be pinned at a standstill by an empty fatigue bar, which is a soft lock
## with no message rather than a penalty. So the run is taken away as a
## capability and this is the gait he falls back to.
@export var walk_speed := 1.35

## ---------------------------------------------------------------------------
## SNOW
## ---------------------------------------------------------------------------
## What is left of his pace in snow deep enough to wade -- SnowField.deep_depth_m,
## 0.42 m, which is knee-deep on this character.
##
## A FACTOR AND NOT A SPEED, and that is the one structural change to the model.
## It used to be an absolute `wade_speed = 1.5` with the top speed lerped from the
## run down to it. That works while the only gait is the run and the run is fast.
## It INVERTS the moment there is a walk: a walk of 1.35 lerped toward 1.5 speeds
## UP as the snow deepens, and a man who sprints into drifts to escape is a bug
## nobody would think to look for. The old minf() guard in top_speed_at() was
## exactly that inversion, caught for the exhausted case only.
##
## As a factor it cannot invert, and it composes with the slope term by
## MULTIPLICATION -- which is what makes a climb through a drift worse than either
## alone, as the owner asked. Adding the two penalties, or taking the worse of
## them, would not.
##
## 0.30 puts the walk at 0.41 m/s -- 1.5 km/h -- in 0.42 m of unpacked snow.
## Published figures for postholing knee-deep put it at 1-2 km/h. It also barely
## moves the feel that shipped: 1.5 against the old 5.4 was 0.28.
@export var deep_snow_factor := 0.30

## How deep the snow may be before the run is taken away, as a wade factor.
##
## A CAPABILITY GATE, not a speed scaler, and it turns on the same distinction as
## the exhaustion rule: past wading depth you cannot lift your feet clear of the
## snow, you drag them -- which is precisely why the furrow further down this file
## exists. There is no run to be had, so there is nothing to slow down. GDD
## section 5's control table says it in one line: 奔跑（仅浅雪与道路上可用）.
##
## 0.6 of the wade factor is 0.25 m of snow. Above that he walks, and
## advance_gait() eases the demotion rather than cutting it, so entering a drift
## at a run reads as wading into it.
##
## THIS IS WHAT MAKES THE PACKED LAYER LOAD-BEARING. A path beaten flat drops the
## depth back under the gate, and running it again is the reward.
##
## This is the HEALTHY body's limit. The survival model scales it down through
## `locomotion:run_snow_limit` -- see run_snow_ceiling(), which is where GDD
## section 5's 雪深惩罚加剧 lives now that no body state is allowed to scale a
## speed.
@export var run_snow_limit := 0.6

## ---------------------------------------------------------------------------
## SLOPE -- Tobler's hiking function
## ---------------------------------------------------------------------------
##     W = 6 exp(-3.5 |S + 0.05|)   km/h,   S = rise / run
##
## Used rather than invented, for two reasons. It is the accepted empirical model
## of walking speed against grade, so 符合现实世界的理解 becomes a citation rather
## than an opinion. And it corroborates walk_speed above, which was derived from
## an animation clip and knows nothing about it.
##
## Its shape is correct gameplay for free. The peak is at a 5% DESCENT rather than
## on the level, and it falls away in both directions -- so a steep descent slows
## him as much as a climb does. A player reads that as careful footing and it
## needs no explanation. A model that only punished climbing would let him fall
## down every bank at full speed.
##
## slope_factor() is this curve divided by its own value at S = 0, so level ground
## multiplies by exactly 1 and the speeds authored above are the speeds on the
## level.
const TOBLER_DECAY := 3.5
const TOBLER_PEAK_GRADE := 0.05

## The floor under the slope term.
##
## Tobler goes to zero, and quickly: at 45 degrees it says 0.05 m/s, which on
## screen is a man stuck to a bank with nothing telling him why. That is the same
## failure as the exhaustion soft lock, and it gets the same answer -- a floor
## rather than a special case.
##
## MEASURED against the ground this game actually serves, rather than guessed at.
## Over an 80 m square of the shipped field sampled every half metre, the steepest
## grade underfoot is 0.049 at the median (2.8 deg), 0.269 at the 90th percentile
## (15.1 deg), 0.461 at the 99th (24.7 deg) and 0.639 at its very worst (32.6 deg,
## one bank in 6,400 square metres). At 0.25 the floor binds only above a 0.40
## climb or a 0.50 descent -- about the top 1% of the terrain -- so Tobler's curve
## is intact everywhere the player normally walks, and the worst the ground can
## do to a walk is 0.34 m/s rather than a standstill.
##
## A const rather than an @export because slope_factor() is static: it is
## arithmetic with a right answer, the way SnowField.drift_relief() is, and a
## curve whose shape depended on which instance you asked would not be.
const SLOPE_FLOOR := 0.25

## ---------------------------------------------------------------------------
## HOW HARD THE TERRAIN IS ALLOWED TO BITE
## ---------------------------------------------------------------------------
## TO TUNE THIS YOU DO NOT NEED THE MATHS BELOW. It is one dial for how much snow
## and slope are allowed to slow him down:
##
##     0.0  terrain does nothing; he moves at the same speed everywhere
##     0.55 SHIPPED -- the worst ground in the game leaves him half his pace
##     1.0  raw Tobler; the worst ground leaves him an eighth of it, a crawl
##
## Raise it if the world feels too easy to cross, lower it if he feels bogged
## down. Nothing else needs to change with it, and
## tools/measure_locomotion.gd prints the whole resulting speed table.
##
##     terrain_factor = lerp(1, snow_factor * slope_factor, terrain_severity)
##
## DO NOT "FIX" THIS BACK TO RAW TOBLER. It is not a fudge covering a modelling
## error -- the model above is correct and stays correct -- it is a deliberate
## amplitude compression, and here is the reason, because the next person to read
## this file will otherwise remove it.
##
## **Tobler describes a hiker crossing terrain over hours.** Our player crosses
## the valley in a minute. The same curve, experienced continuously and without
## the compensating sense of a long journey being made, reads as oppression
## rather than as effort -- which is the well-known gap between realistic movement
## penalties and how they feel under time compression. The owner played it and
## said so exactly: 我感觉整个 debuff 太严重了 ... 只要能体现出速度减缓的趋势就好了.
## Feel the trend, not the struggle.
##
## A lerp toward 1 is the compression that costs nothing structural. It is
## MONOTONE in the raw product, so every relationship the model builds survives
## untouched: deeper snow is still slower than shallow, uphill is still slower
## than flat, the peak is still at a 5% descent, and a climb through a drift is
## still worse than either alone. Only the SPREAD shrinks. The model still
## describes the world truthfully in relative terms -- which is the part a player
## can actually perceive -- while costing less in absolute terms.
##
## 0.55 rather than a rounder number because the target was the worst case in the
## game, not the knob. The floor of the raw product is deep_snow_factor x
## SLOPE_FLOOR = 0.30 x 0.25 = 0.075, an eighth of the clear-ground walk and a
## crawl; 1 - 0.55 x (1 - 0.075) = 0.49, which is half the clear-ground walk. He
## should feel slowed, never stuck.
##
## Raise it toward 1 to get raw Tobler back; drop it to 0 to switch the terrain
## off entirely. tools/measure_locomotion.gd prints both the raw and the shipped
## figures side by side so the realism claim stays checkable at any setting.
@export var terrain_severity := 0.55

## ---------------------------------------------------------------------------
## AUTO-RUN
## ---------------------------------------------------------------------------
## How long he has to keep going before the walk becomes a run, in seconds.
##
## TO TUNE: lower it and he breaks into a run almost as soon as you press a
## direction; raise it and he only runs once you have clearly committed to going
## somewhere. 0 promotes him immediately. Nothing else moves with it.
##
## The owner asked for the threshold to be a user setting and for a sensible
## default to be picked now. 1.2 s is about two paces at walking speed: long
## enough that crossing a room, stepping round a doorway or nudging into place
## never promotes him, short enough that setting off across the field does.
##
## THIS IS A DEFAULT, NOT THE VALUE. register_settings() publishes it as
## AUTO_RUN_SETTING and reads whatever the player has chosen back over it, so a
## settings screen binds a slider to a name that already exists with a range on
## it. 0 promotes him as soon as he is moving.
@export var auto_run_delay := 1.2

## How far off his own heading counts as a change of direction rather than a
## curve, in degrees.
##
## TO TUNE: lower it and he drops out of a run at the slightest turn, so running
## only survives a straight line; raise it and only a full about-face stops him.
## 70 is "a corner keeps the run, a flick or a reversal does not".
##
## Measured against a SMOOTHED heading (auto_run_heading_smoothing below) rather
## than against the last frame, because at 60 Hz a single frame of even a violent
## turn is a couple of degrees and nothing would ever trigger. The smoothed
## heading lags the input by roughly (turn rate) x (1 / smoothing), so at 70
## degrees a corner taken at 180 deg/s survives -- it lags about 45 -- and a flick
## or an about-face does not.
@export var auto_run_turn_degrees := 70.0
@export var auto_run_heading_smoothing := 4.0

## How fast the promotion and the demotion ease, as a closed fraction per second
## -- the same form as turn_speed and vertical_smoothing.
##
## Eased rather than stepped, and that is not a polish item: a body that snaps
## from walk to run at a threshold is worse than no auto-run at all, because the
## threshold becomes something the player can see. 3.0 puts full run about a
## second after the promotion; 6.0 takes it off in half of that, because slowing
## down is a decision and speeding up is a commitment.
##
## The animation follows for free -- _drive_animation() blends on the ground speed
## this produces, so the legs cross over on exactly the same ramp.
@export var auto_run_rise := 3.0
@export var auto_run_fall := 6.0

## Where the auto-run threshold lives for a settings screen to find it.
##
## Registered at runtime rather than written into project.godot, for the same
## reason _register_actions() registers the movement keys there: this is the whole
## control surface of the slice and it belongs in one readable place. Nothing
## calls ProjectSettings.save(), so a run never writes to project.godot.
const AUTO_RUN_SETTING := "winter_time/controls/auto_run_delay_seconds"

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
## The furrow the legs plough in deep snow
## ---------------------------------------------------------------------------
## Past wading depth you cannot lift your feet clear of the snow. You drag them,
## and a dragged boot does not stamp, it PLOUGHS -- so what the walker leaves
## between his prints is not a fainter footprint, it is a groove with an
## inverted-triangle cross-section (倒三角): deepest along the centre line and
## rising in a straight taper to the surface at both edges. TrackMask.plough()
## holds that shape and the reasoning for it.
##
## THREE PASSES AT THIS, AND THE FIRST TWO ARE WORTH KEEPING ON THE RECORD,
## because neither failure is the one the numbers suggest:
##
##   0.50 strength / 0.70 width, from 0.45 depth -- the prints dissolved outright
##       and the trail became a continuous white ridge.
##   0.30 strength / 0.42 width, from 0.55 depth -- still a ribbon: an angular
##       zigzag snake with the prints absorbed into its corners.
##   0.16 strength / 0.32 width, from 0.80 depth -- tuned down far enough to
##       escape the second failure and straight past "a hint" into absent. There
##       was no trench at all, only isolated ovals.
##
## The second failure was GEOMETRIC and no amount of tuning addressed it, which
## is why the third pass -- tuning -- landed on nothing rather than on something.
## A groove emitted as one segment per footfall is a polyline by construction:
## the segment is 0.72 m long and the groove is 0.17 m wide, so every change of
## direction is a twelve-to-one elbow with a hard corner in it. Noise does not
## hide a corner, it gives you a noisy corner. 需要避免之前那种连续的折线的感官.
##
## So the furrow is no longer drawn between footfalls at all. advance_furrow()
## samples the walker's REAL position every physics tick and stamps along the
## path actually travelled, in segments shorter than the groove is wide -- and
## then the groove curves because the walk curves, with no joint anywhere to see.
##
## THE GATE, in metres of snow rather than as a fraction of whatever the field's
## maximum happens to be. 0.42 m is SnowField.deep_depth_m, the depth the game
## already calls "reduced to a trudge": the furrow starts exactly where wading
## starts, which is the physical claim rather than a tuned one. Measured over an
## 80 m square of the shipped field, 41% of the ground is at or above it, 35%
## carries no snow at all, and the maximum is 0.60 m -- so a scoured crest never
## furrows and a drift always does. The taper out at a drift's edge needs no
## second rule: `bite` below goes to zero on its own.
@export var furrow_depth_start_m := 0.42

## Peak depth on the centre line, in mask units, in the deepest snow. Against a
## footprint's 1.0 at the same depth -- so the boot pockets still win outright
## wherever they overlap the channel, which is what keeps their outlines.
@export var furrow_strength := 0.72

## Half-width in the deepest snow. About a 34 cm channel, which is the width of
## a pair of legs dragged through a drift, and the number that sets how steep the
## two flanks are: at this depth and width they meet the snow at about 13
## degrees, which is enough to put them either side of the shader's grain band.
@export var furrow_half_width_m := 0.17

## Shallower snow ploughs a narrower channel as well as a shallower one, down to
## this fraction of the width at the gate.
@export var furrow_narrow_at_gate := 0.55

## How fast the furrow bites once it bites at all. Below 1 it rises steeply just
## past the gate and flattens off deeper in -- which is what stops the third
## pass's failure from coming back, because a linear ramp across the 0.42 .. 0.60
## band spends its first metres of drift drawing something invisible.
@export var furrow_onset := 0.5

## How far the walker travels between furrow samples. Small ENOUGH IS THE WHOLE
## POINT: it has to stay under furrow_half_width_m, because that is what makes
## the union of the segments the exact swept region of the path rather than a
## chain of capsules with visible joins. At 6 cm it is a third of the width, and
## about two and a half physics ticks at walking pace.
@export var furrow_sample_m := 0.06

## Further than this in one tick is not a walk. A respawn, a scene restart or a
## `--start` teleport puts the walker somewhere he did not walk to, and joining
## the two would rule a furrow across untouched snow. Well over the 9 cm a
## physics tick can cover at full sprint.
@export var furrow_max_jump_m := 0.5

## The wobble down the run, so the channel does not read as an extruded ribbon.
## Indexed by DISTANCE WALKED rather than sampled per segment, so it is a smooth
## function of the path and neighbouring segments agree with each other -- which
## is what keeps the joints invisible while the depth and width still wander.
##
## The wavelength has to stay comfortably longer than the groove is wide. The
## segments composite with max(), so a wobble whose own slope beats the flank's
## is flattened into its own upper envelope; at 1.1 m against a 0.17 m width
## there is a factor of twenty in hand.
@export var furrow_wobble_wavelength_m := 1.1
@export var furrow_depth_wobble := 0.22
@export var furrow_width_wobble := 0.25
@export var furrow_wobble_seed := 20260812

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

## Where standing still ends and locomotion begins, in ground speed.
##
## Below the first the figure is idling outright; above the second the walk
## carries him entirely; between them the two are crossfaded. Narrow, and set
## against acceleration rather than against top speed: at 12 m/s^2 the walk is
## fully faded in a tenth of a second after the key goes down, which is about
## how long it takes a person to lean into a step. Widening it makes him look
## like he is wading out of treacle every time he starts.
##
## The lower bound is not zero because move_toward leaves a hair of velocity for
## a frame or two after the key comes up, and an idle that flickers back to a
## crawl at every stop is worse than one that starts a frame late.
@export var anim_idle_speed := 0.12
@export var anim_moving_speed := 0.85

## How cold he looks when he stops, 0 = the warm relaxed stand, 1 = shivering.
##
## GDD section 5 and section 9 make body language the readout for the survival
## stats and there is no HUD, so this is the beginning of that: `set_chill()`
## takes it, and the temperature system drives it when it lands.
##
## IT HAS LANDED. drive_readouts() now sets this every physics frame from
## body_chill(), which is 1 - the core temperature reserve, and the same number
## goes to the breath so the two readouts cannot disagree. The value below is
## what stands when there is no survival model running -- a test, or a scene
## built before the autoload -- and nothing else.
##
## NOTE WHAT THAT CHANGES ON SCREEN: a man at full core temperature now reads as
## chill 0, so the warm relaxed stand is what the first minutes of day 1 look
## like. That is what the paragraph below argued against for the UNDRIVEN case,
## and it is the price of the stand being a readout at all. If the owner decides
## he should never look fully relaxed while he is outdoors, the fix is a floor in
## body_chill() -- one line, and a number.
##
## It defaults to 1 rather than to 0, which inverts the obvious mapping, and the
## screenshots decided it. `idle` is Meshy's `Idle_4` and it barely moves --
## measured, not judged: its dominant frequency is 0.07 Hz and its per-frame
## direction reverses about a tenth as often as the cold take's. The owner's
## word for it was 僵硬, stiff, and they are right. Every minute of this game so
## far is spent outdoors in a wind, where nobody stands still; the warm stand is
## the special case and belongs to the farmhouse interior, so it waits there
## with a name on it.
@export var chill := 1.0

## ---------------------------------------------------------------------------
## Which of the wanderer's looks to wear
## ---------------------------------------------------------------------------
## A path rather than a preloaded resource, so adding a third look is a new
## `.tres` in data/characters/ and nothing else -- no `.gd` anywhere changes.
## See CharacterScheme for what the two shipped looks are and why both exist.
##
## The scheme also carries the character's own key light, because the sun cannot
## do that job: it is at azimuth 118 against a camera yawed -35, which is nearly
## behind the lens, so every surface of the figure the camera can see is in its
## shade. Left to the Environment's fill alone the figure is evenly lit from all
## sides -- correctly coloured, but a flat paper cut-out with no form. The key
## puts the form back, aimed from the camera's own quarter for exactly that
## reason, and culled to CHARACTER_LAYER because every other surface in the game
## is on a cel shader whose light() would add it a second time and lay a second
## shadow band across the snow.
@export_file("*.tres") var scheme_path := "res://data/characters/wanderer_pale.tres"

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
var _survival: Node
var _scheme: CharacterScheme
var _steps: AudioStreamPlayer
var _breath: BreathFog
var _model: Node3D
var _animation: AnimationTree
var _stride_accumulator := 0.0
var _left_foot := true
var _facing := Vector3.FORWARD
var _grounded := false
var _furrow_noise: FastNoiseLite
var _furrow_anchor := Vector3.ZERO
var _has_furrow_anchor := false
var _furrow_travel := 0.0
## The two gait cycles' own lengths, measured off the clips in _build_animation(),
## and the shared length both are remapped onto. See _lock_gait_cycles(). The
## defaults are the shipped clips' measured values so a body built without a
## model still computes a sane pace.
var _walk_period := 1.0667
var _run_period := 0.6667
var _cycle_period := 0.6667
## The auto-run: how long he has kept going, which way he has been going, and how
## far the walk has been promoted toward the run. See advance_gait().
var _run_hold := 0.0
var _run_heading := Vector3.ZERO
var _run_blend := 0.0


func _ready() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null:
		registry.register(&"player", self)
	# Trap 3: an autoload is a node under /root, never an Engine singleton.
	_bus = get_node_or_null("/root/EventBus")
	_build_body()
	_build_audio()
	_register_actions()
	register_settings()
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

	_scheme = load(scheme_path) as CharacterScheme
	if _scheme == null:
		# Never silently: a missing scheme means the figure is painted by
		# whatever StandardMaterial3D defaults to, which is white plastic.
		push_warning("player_controller: no CharacterScheme at %s" % scheme_path)
		_scheme = CharacterScheme.new()

	var body_material := StandardMaterial3D.new()
	body_material.albedo_texture = load(ALBEDO_PATH)
	# The scheme's whole job. Multiplies the model's own maps; see
	# CharacterScheme.albedo_tint for why it is also what unclips the scarf.
	body_material.albedo_color = _scheme.albedo_tint
	if _scheme.normal_map_enabled:
		body_material.normal_enabled = true
		body_material.normal_texture = load(NORMAL_PATH)
	if _scheme.roughness_map_enabled:
		body_material.roughness_texture = load(ROUGHNESS_PATH)
	if _scheme.metallic_map_enabled:
		# metallic defaults to 0 and *multiplies* the map, so the map does nothing
		# at all until this is 1. roughness already defaults to 1 and needs no such
		# line, which is exactly the sort of asymmetry that gets a metallic map
		# shipped wired up and inert.
		body_material.metallic = 1.0
		body_material.metallic_texture = load(METALLIC_PATH)
	# The camera never rotates (Art Bible rule 1), so a figure who walks behind
	# the house cannot be recovered by swinging the view -- he has to be drawn
	# through it. See CharacterScheme.wear_ghost(): two property writes on the
	# character's own material, and nothing in the world changes.
	_scheme.wear_ghost(body_material)
	# Overridden rather than assigned into the mesh: the .glb's own surface
	# material is whatever Godot invented for a primitive that arrived without
	# one, and the model file is not the place to keep a material that is
	# assembled from four separate files.
	for surface in _mesh_instances(_model):
		surface.material_override = body_material
		surface.layers |= CHARACTER_LAYER

	_build_key_light()
	_build_animation()
	_build_breath()


## The breath rides the head bone. See BreathFog for why that matters and for
## what drives it.
##
## The aim node exists because the Head bone's own axes are not the character's:
## its rest basis is rolled, so "forward" on that bone is not the way he is
## facing. Cancelling the rest basis leaves a node whose +Z is the model's +Z --
## which is the way this model faces -- while still following the head through
## every take. The scale term cancels the model's own, so BreathFog's numbers
## are metres of world rather than of Meshy's centimetres.
func _build_breath() -> void:
	var skeleton := _first_of_type(_model, &"Skeleton3D") as Skeleton3D
	if skeleton == null:
		return
	var head := skeleton.find_bone(BREATH_BONE)
	if head < 0:
		push_warning("player_controller: the rig has no %s bone to breathe from" % BREATH_BONE)
		return

	var attachment := BoneAttachment3D.new()
	attachment.name = "BreathAnchor"
	attachment.bone_name = BREATH_BONE
	skeleton.add_child(attachment)

	var aim := Node3D.new()
	aim.name = "BreathAim"
	var unrolled := skeleton.get_bone_global_rest(head).basis.orthonormalized().inverse()
	var world_scale := skeleton.global_transform.basis.get_scale().y
	var units := 1.0 / maxf(world_scale, 0.0001)
	# The offset is authored in the CHARACTER's frame but consumed in the BONE's,
	# because this node's origin is expressed in its parent BoneAttachment3D --
	# which carries the head bone's own rolled axes, pitched 36 degrees forward.
	# Rotating it by the inverse rest basis is what makes "up and forward" mean up
	# and forward. Without this line the same constant reads as up-and-down-the-
	# skull, and the breath comes out of his chest.
	var mouth := unrolled * (BREATH_MOUTH_OFFSET * units)
	aim.transform = Transform3D(unrolled.scaled(Vector3.ONE * units), mouth)
	attachment.add_child(aim)

	var fog := BreathFog.new()
	fog.name = "Breath"
	aim.add_child(fog)
	attach_breath(fog)


## Hands the controller the fog it drives. Called by _build_breath() once the
## emitter is under the head bone, and by a test that cannot build a skeleton.
func attach_breath(fog: BreathFog) -> void:
	_breath = fog


## The survival model this body reads itself out of. Injected by a test, or
## resolved from the autoload in _resolve(); null is a valid state and means
## every authored default stands untouched.
func set_survival_system(system: Node) -> void:
	_survival = system


## The form, not the level -- the level is the Environment's fill. See
## scheme_path above, and LightingDirector.character_fill_energy.
func _build_key_light() -> void:
	if _scheme == null or _scheme.key_energy <= 0.0:
		return
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation = Vector3(
		deg_to_rad(-_scheme.key_elevation_degrees),
		deg_to_rad(_scheme.key_azimuth_degrees),
		0.0)
	key.light_energy = _scheme.key_energy
	# Left white. Every other colour in this project comes out of the palette;
	# this one must not, for the reason LightingDirector.character_fill_energy
	# spells out -- a blue light on a blue-grey coat clips the blue channel
	# before the red one is halfway up, and the coat stops reading as its own
	# colour. Nothing else in the game is lit by it.
	key.light_cull_mask = CHARACTER_LAYER
	key.shadow_enabled = false
	key.light_specular = 0.0
	add_child(key)


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


## Idle, walk and run, blended by the speed the snow already decides.
##
## The AnimationPlayer that arrives inside the .glb knows only the eighteen
## takes that were merged into that file, under Meshy's own names. It is given
## the whole library instead -- twenty takes, including the idle and the
## knockdown that shipped as separate animation-only FBXs -- replacing its
## default library rather than sitting beside it, so every clip in the game is
## addressed by one name with no library prefix.
##
## THE GRAPH'S SHAPE IS THE WHOLE OF THE IDLE FIX, and the ordering is not
## arbitrary:
##
##     walk ------.
##                 >-- gait --> pace ---.
##     run  ------'                      >-- motion --> output
##     idle -----.                      /
##                >-- chill -----------'
##     idle_cold '
##
## `chill` is the standing-still half of GDD section 5's no-HUD readout: one
## number from the survival stats decides how cold the man looks when he stops.
## It sits inside the idle branch rather than over the output so that it costs
## nothing while he is moving -- at full speed `motion` is 1 and neither idle
## contributes at all.
##
## ---------------------------------------------------------------------------
## THE TWO IDLES ARE **NOT** PUT ON A SHARED CYCLE, AND THAT IS THE POINT
## ---------------------------------------------------------------------------
## The same question was asked of them as of the walk and the run, because the
## lengths are further apart than the gaits' are:
##
##     idle 14.0000 s     idle_cold 3.0000 s     ratio 4.6667
##
## The answer is different, and the reason is that a period is only worth locking
## when it is a PHASE. Two gait cycles have one: each carries a left foot and a
## right foot that have to agree about which is forward. Two standing idles do
## not. Both keep the feet planted throughout, so their average is a standing
## pose at any relative phase, and there is nothing to fight.
##
## Locking them would also destroy both takes. Stretching the shiver to 14 s
## makes it a slow wobble, and the shiver is the readout the owner asked for by
## name; compressing the neutral idle to 3 s makes a man who barely moves twitch.
## The mismatch is a feature here: 14 against 3 shares no common multiple under 42
## seconds, so the mixture never visibly repeats.
##
## What they DID need was `sync`, and badly. `chill` reaches exactly 1.0 whenever
## no survival model is running -- which is its authored default -- and at 1.0 the
## neutral idle's weight is zero, so it froze solid and re-entered stale the
## moment anything moved `chill` off the endpoint.
##
## The time scale sits *inside* the locomotion branch, not over the whole graph.
## It has to: pace goes to zero with the ground speed, which is what stops a
## standing character from sliding along with his legs cycling -- and a time
## scale over the output would freeze the idle along with it, leaving exactly
## the frozen mid-stride pose the idle exists to replace.
##
## Freezing the walk branch at a standstill is still the right behaviour, it is
## just no longer visible: at zero speed `motion` is zero, so the frozen legs
## contribute nothing, and when the player moves off again the cycle resumes
## from where it stopped rather than snapping to frame one.
## A Blend2 that keeps BOTH its inputs running.
##
## ---------------------------------------------------------------------------
## THE STRADDLE, AND WHY EVERY BLEND IN THIS TREE IS SYNCED
## ---------------------------------------------------------------------------
## `AnimationNodeBlend2` inherits `sync` from `AnimationNodeSync` and IT DEFAULTS
## TO FALSE -- verified on this build rather than read off the docs. With `sync`
## off, an input whose blend weight reaches 0 stops advancing and is held at
## whatever frame it happened to be on. When its weight comes back up it re-enters
## the mix at a stale, arbitrary phase, and two locomotion cycles mixed pose by
## pose then average one clip's stance against the other's. Where one has the left
## leg forward and the other the right, the average is a man walking with his legs
## apart.
##
## THIS DEFECT IS OLDER THAN THE SPEED REWORK AND THAT REWORK IS WHAT EXPOSED IT.
## The graph had these three unsynced Blend2 nodes before any of it. What changed
## is where `gait` sits: the run used to be 5.4 m/s and it was the only speed the
## body had, so `inverse_lerp(1.35, 4.6, 5.4)` clamped and the character was
## PINNED at gait 1.0 -- a pure run, the walk contributing nothing, nothing mixed
## and nothing to go wrong. He now walks at 1.35, jogs at 3.3, and spends nearly
## all his time at intermediate values, which is exactly where the latent defect
## draws.
##
## `sync` is set on all three deliberately, and each one earns it:
##
##   gait    two gait cycles. THE straddle. Non-negotiable.
##   chill   two idles, and it is the shiver readout. `chill` reaches 1.0 whenever
##           no survival model is running, which froze the neutral idle outright.
##   motion  the idle branch used to freeze solid for as long as he was moving,
##           then resume stale the moment he stopped -- a pop at the end of every
##           journey. The locomotion branch is still frozen at a standstill, but
##           by `pace` going to zero rather than by this, so the comment above
##           about resuming where it stopped still holds.
static func _synced_blend() -> AnimationNodeBlend2:
	var blend := AnimationNodeBlend2.new()
	blend.sync = true
	return blend


## The graph, as a pure function of nothing.
##
## Static, and it allocates no Node -- every AnimationNode is a Resource, so this
## frees itself and a test may call it freely (briefing constraint 2). That is the
## point of it being separate: the shape of this graph and the flags on it are
## what regressed, and checking them used to mean standing a whole character up,
## which loads a model, four textures and a skeleton and leaks RIDs on the way
## out. Now the thing that broke is the thing under test, and nothing else runs.
##
## The two rate nodes carry constants set by _lock_gait_cycles() once the tree is
## live; everything else here is fixed wiring.
static func build_blend_tree() -> AnimationNodeBlendTree:
	var idle := AnimationNodeAnimation.new()
	idle.animation = IDLE_CLIP
	var idle_cold := AnimationNodeAnimation.new()
	idle_cold.animation = IDLE_COLD_CLIP
	var walk := AnimationNodeAnimation.new()
	walk.animation = WALK_CLIP
	var run := AnimationNodeAnimation.new()
	run.animation = RUN_CLIP

	var graph := AnimationNodeBlendTree.new()
	graph.add_node("idle", idle)
	graph.add_node("idle_cold", idle_cold)
	graph.add_node("chill", _synced_blend())
	graph.add_node("walk", walk)
	graph.add_node("run", run)
	# One per clip, holding a constant that puts both cycles on the run's length.
	graph.add_node("walk_rate", AnimationNodeTimeScale.new())
	graph.add_node("run_rate", AnimationNodeTimeScale.new())
	graph.add_node("gait", _synced_blend())
	graph.add_node("pace", AnimationNodeTimeScale.new())
	graph.add_node("motion", _synced_blend())
	graph.connect_node("chill", 0, "idle")
	graph.connect_node("chill", 1, "idle_cold")
	graph.connect_node("walk_rate", 0, "walk")
	graph.connect_node("run_rate", 0, "run")
	graph.connect_node("gait", 0, "walk_rate")
	graph.connect_node("gait", 1, "run_rate")
	graph.connect_node("pace", 0, "gait")
	graph.connect_node("motion", 0, "chill")
	graph.connect_node("motion", 1, "pace")
	graph.connect_node("output", 0, "motion")
	return graph


## What the two rate nodes have to hold for both cycles to be one length.
##
## Static and pure so the arithmetic can be checked without a tree: x is the
## walk's rate, y is the run's. The run is the shared length -- see
## _lock_gait_cycles() for why that end and not the other.
static func cycle_rates(walk_period: float, run_period: float) -> Vector2:
	var shared := maxf(run_period, 0.0001)
	return Vector2(maxf(walk_period, 0.0001) / shared, run_period / shared)


## Put the walk and the run on one shared cycle length.
##
## SYNC ALONE IS NOT ENOUGH, and this is the half that is easy to miss. `sync`
## keeps both inputs advancing; it does not make them advance at the same RATE.
## Measured off the shipped clips:
##
##     walk  1.0667 s     run  0.6667 s     ratio 1.6000
##
## Two cycles 1.6 times apart in period drift through each other continuously, so
## even perfectly synced they are only in phase for an instant and the feet fight
## everywhere else. That is a beat, and it is worse than a constant error because
## it never settles.
##
## The fix is one `AnimationNodeTimeScale` in front of each clip, holding a
## constant: the clip's own period over the shared one. The walk runs at 1.600 and
## the run at 1.000, so both cycles are the RUN's length, and `pace` downstream
## scales the locked pair together.
##
## The run was chosen as the shared length rather than the walk because it keeps
## `pace` at or below 1 across the whole speed range, which leaves anim_max_pace
## as the guard it was meant to be instead of a clamp that bites at the top of
## the run.
##
## ---------------------------------------------------------------------------
## `use_custom_timeline` WAS TRIED FIRST AND IT DOES NOT WORK HERE
## ---------------------------------------------------------------------------
## `AnimationNodeAnimation` gained `use_custom_timeline`, `timeline_length` and
## `stretch_time_scale` for exactly this problem, and reading the names it is the
## obvious answer -- declare both clips onto one timeline and let the engine remap
## them. Measured on 4.7.1, setting all three STOPS THE SKELETON: sampling the
## thigh's swing through the graph gives a range of 0.000 rad at gait 0.5 and 1.0,
## and 0.361 rather than 0.548 at gait 0. A frozen character, not a retimed one.
##
## It is written down because the property names are inviting and the failure is
## silent -- no error, no warning, just a man standing still while every parameter
## reads correct. Whatever those three properties mean on this build, it is not
## what a blend tree of two locomotion clips needs. TimeScale is arithmetic on the
## delta and it is verifiable, which is why it is what ships.
##
## Nothing is resampled either way -- this scales time, it does not rewrite keys --
## so the poses are exactly the authored ones at both endpoints.
##
## PHASE IS DELIBERATELY LEFT ALONE, and it was measured before that was decided.
## Cross-correlating the thigh swing of the two clips, resampled to a common 360
## points with the mean removed:
##
##     LeftUpLeg    best shift 0.886 of a cycle, correlation 0.885 (0.726 unshifted)
##     RightUpLeg   best shift 0.014 of a cycle, correlation 0.795 (0.789 unshifted)
##
## The two legs disagree about which shift is best, so there is no single offset
## that improves both -- correcting the left leg's 0.886 would drag the right leg
## off its own optimum for a gain of 0.006. They already start broadly in phase.
## The residual is asymmetry authored into the takes: within one clip the left and
## right thighs are 0.411 (walk) and 0.461 (run) of a cycle apart where a clean
## cycle would be 0.500. Closing that is a re-export and an asset decision, not a
## retime, so `start_offset` is left at zero and the numbers are in the report.
## Applied once, after the tree is live: these are constants, and the only thing
## that could change them is a re-exported clip of a different length.
func _lock_gait_cycles() -> void:
	_cycle_period = _run_period
	var rates := cycle_rates(_walk_period, _run_period)
	_animation.set(&"parameters/walk_rate/scale", rates.x)
	_animation.set(&"parameters/run_rate/scale", rates.y)


func _build_animation() -> void:
	var player := _first_of_type(_model, &"AnimationPlayer") as AnimationPlayer
	if player == null:
		return
	# Replaces rather than adds: an AnimationPlayer may hold several libraries,
	# and leaving the imported one in place under the same empty name is an
	# error, while leaving it under another name means the same take is reachable
	# by two different strings.
	if player.has_animation_library(&""):
		player.remove_animation_library(&"")
	player.add_animation_library(&"", WandererAnimations.build())
	for clip in [IDLE_CLIP, IDLE_COLD_CLIP, WALK_CLIP, RUN_CLIP]:
		if not player.has_animation(clip):
			push_warning("player_controller: the merged library is missing %s" % clip)
			return

	# Measured off the clips rather than typed in, so a re-export at a different
	# length retimes itself. See _lock_gait_cycles().
	_walk_period = maxf(player.get_animation(WALK_CLIP).length, 0.0001)
	_run_period = maxf(player.get_animation(RUN_CLIP).length, 0.0001)

	var graph := build_blend_tree()

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
	# After the tree is live: these are AnimationTree parameters, not resource
	# properties, so there is nothing to set them on until it exists.
	_lock_gait_cycles()


## How much of him the walk carries, against the idle. 0 standing, 1 walking.
##
## THE TWO BOUNDS ARE STATED FOR BARE, LEVEL GROUND AND SCALED BY WHAT THE GROUND
## ALLOWS, and that scaling is not decoration -- without it the slower speed model
## introduces a regression that looks like an animation bug. They were absolute
## metres per second, and they were right while the slowest a man could move was
## 1.5. A trudge at 0.41 m/s sits a third of the way through a crossfade tuned to
## finish at 0.85, so the character would slide across a drift half standing
## still.
##
## Scaling keeps every approved number: on bare level ground these are still
## exactly anim_idle_speed and anim_moving_speed, and everywhere else they are the
## same FRACTION of the pace the ground allows. The stopping debounce the lower
## bound exists for scales with them, so it stays the same couple of physics
## ticks at any depth.
##
## Deliberately scaled by the terrain only, not by the survival channels. The
## walk's own share of `locomotion:speed` is 0.72 at its very worst, which leaves
## a walking man well clear of the upper bound; folding it in would make how
## awake he looks depend on how tired he is.
func motion_blend(speed: float, wade: float, grade: float) -> float:
	var reach := maxf(terrain_factor(wade, grade), 0.02)
	return clampf(
		inverse_lerp(anim_idle_speed * reach, anim_moving_speed * reach, speed), 0.0, 1.0
	)


## Blend by speed, and play at the rate that actually covers the ground, so the
## feet plant instead of skating.
##
## One number drives the gait and the pace, and it is the ground speed the terrain
## decided: snow_factor() and slope_factor() have already pulled the top speed
## down by the time this reads velocity, and the auto-run's eased blend is in
## there too. So a player crossing a drift does not merely move slower -- he drops
## out of the run into the walk and shortens his stride, because the same metre
## per second the snow took away is the one this reads. The auto-run needs no
## separate animation wiring for the same reason.
##
## THE PACE IS COMPUTED IN STRIDES, NOT IN SPEEDS, and it has to be now that
## _lock_gait_cycles() puts both clips on one timeline. The old form divided the
## ground speed by `lerp(anim_walk_speed, anim_run_speed, gait)`, which is the
## speed the pair would cover if each played at ITS OWN length -- and neither does
## any more, so that number no longer describes anything.
##
## What survives the remap is the distance each cycle covers, which is a property
## of the clip and not of how fast it is played:
##
##     stride = lerp(anim_walk_speed * walk_period, anim_run_speed * run_period, gait)
##
## 1.44 m for the walk cycle, 3.07 m for the run -- and those agree with the
## measurements in the anim_walk_speed comment, which is the check that the
## exports and the clips still describe the same takes. One shared cycle covers
## `stride` metres in `_cycle_period / pace` seconds, so matching that to the
## ground speed gives the line below.
##
## It still lands on exactly 1 at a pure run and 0.625 at a pure walk -- both
## clips playing at their authored rate, which is the whole point -- and it stays
## under anim_max_pace across the entire speed range, so that clamp is a guard
## again rather than something that bites at the top of the run.
func _drive_animation(wade: float, grade: float) -> void:
	if _animation == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var gait := clampf(inverse_lerp(anim_walk_speed, anim_run_speed, speed), 0.0, 1.0)
	var stride := lerpf(anim_walk_speed * _walk_period, anim_run_speed * _run_period, gait)
	var pace := speed * _cycle_period / maxf(stride, 0.0001)
	_animation.set(&"parameters/motion/blend_amount", motion_blend(speed, wade, grade))
	_animation.set(&"parameters/gait/blend_amount", gait)
	_animation.set(&"parameters/pace/scale", clampf(pace, 0.0, anim_max_pace))
	_animation.set(&"parameters/chill/blend_amount", clampf(chill, 0.0, 1.0))


## How cold he looks standing still. 0 is the warm relaxed stand, 1 the shiver.
##
## The seam GDD section 5's survival stats plug into: whoever owns 体温 calls
## this and the body says it, with no HUD in between. Kept as a method rather
## than left to whoever wants to poke `chill` so that the clamp and the
## parameter name stay in one place.
func set_chill(amount: float) -> void:
	chill = clampf(amount, 0.0, 1.0)
	if _animation != null:
		_animation.set(&"parameters/chill/blend_amount", chill)


## ---------------------------------------------------------------------------
## Reading the body -- GDD section 9's readouts, with no HUD between them
## ---------------------------------------------------------------------------
## How cold he IS, 0 warm .. 1 freezing.
##
## THE INVERSE OF THE STAT, and this is the one line in the wiring that cannot be
## got wrong quietly. Every survival stat is a RESERVE: core_temperature 1.0 is a
## warm man and 0.0 is a dead one. Passing fraction_of() straight through is the
## obvious-looking thing to write, it compiles, it runs, and it gives a man in
## perfect health the breath and the body language of a man about to die -- from
## the first frame of the game, with nothing on screen to contradict it. It would
## read as art direction.
##
## Returns the authored `chill` when there is no survival model: the cold idle
## and the fog were both tuned against 1.0 because everything so far happens
## outdoors in a wind, and a scene with no model running must not turn that off.
## A man standing outdoors in this weather is never perfectly still, so the
## shiver never fully switches off. IDLE_CHILL_FLOOR is the amount of it he
## carries at full warmth.
##
## The owner asked for the shiver idle as the default and the neutral one read
## as stiff. Swapping the two clips would have done it, but at the cost of the
## gradient: the whole point of blending these is that colder means visibly
## more shiver, and that is one of GDD section 9's readouts with no HUD behind
## it. A floor keeps both -- always alive, and still legible as it worsens.
##
## Raise this and a healthy man looks hypothermic; drop it to zero and the
## default idle goes stiff again. It is deliberately not 0.0 and deliberately
## not high.
const IDLE_CHILL_FLOOR := 0.45


func body_chill() -> float:
	if _survival == null:
		return maxf(chill, IDLE_CHILL_FLOOR)
	var cold := clampf(1.0 - _survival.fraction_of(&"core_temperature"), 0.0, 1.0)
	# Remap onto [FLOOR, 1] rather than clamping, so the whole range of the stat
	# still moves the body. A clamp would flatten every temperature above the
	# floor into one identical pose and throw the readout away above it.
	return IDLE_CHILL_FLOOR + cold * (1.0 - IDLE_CHILL_FLOOR)


## ---------------------------------------------------------------------------
## THE SPEED MODEL
## ---------------------------------------------------------------------------
## Tobler's hiking function, normalised so level ground is exactly 1.
##
##     W(S) = 6 exp(-3.5 |S + 0.05|)          km/h
##     slope_factor(S) = W(S) / W(0) = exp(-3.5 (|S + 0.05| - 0.05))
##
## Static and contextless on purpose, the way SnowField.drift_relief() and
## sample_bilinear() are: it is the one piece of this model that is arithmetic
## with a right answer, and tests/unit/test_locomotion.gd computes the paper's own
## curve independently and compares.
##
## S is signed: positive climbing, negative descending. The peak sits at -0.05,
## so the fastest ground in the game is a gentle downhill and both a climb and a
## steep drop cost.
static func slope_factor(grade: float) -> float:
	var raw := exp(-TOBLER_DECAY * (absf(grade + TOBLER_PEAK_GRADE) - TOBLER_PEAK_GRADE))
	return maxf(raw, SLOPE_FLOOR)


## The grade a walker actually faces: the terrain's gradient resolved along his
## own heading, in rise over run.
##
## NOT the terrain's steepest slope, and the difference is the whole point.
## SnowField.surface_gradient_at() points uphill and its length is tan(slope), so
## a man traversing a bank along the contour reads 0 -- level ground underfoot,
## which is what it is -- while the same bank taken straight up reads its full
## steepness. Using the raw magnitude would slow a player who is not climbing
## anything.
static func grade_along(gradient: Vector2, heading: Vector3) -> float:
	var flat := Vector2(heading.x, heading.z)
	if flat.length_squared() < 0.000001:
		return 0.0
	return gradient.dot(flat.normalized())


## What the snow leaves him, 1 on bare ground down to deep_snow_factor at wading
## depth.
##
## A PURE FUNCTION OF THE GROUND. It used to read `locomotion:snow_cost` so a
## tired man was slowed more by the same drift; that channel is gone. The body
## does not get to change what the terrain costs -- see can_run() for where GDD
## section 5's 雪深惩罚加剧 lives now.
func snow_factor(wade: float) -> float:
	return lerpf(1.0, deep_snow_factor, clampf(wade, 0.0, 1.0))


## Everything the ground does to him, as one multiplier, compressed.
##
## The two raw terms are the honest physical model and stay available separately
## -- snow_factor() and slope_factor() are what a realism claim is checked
## against. This is what actually reaches the velocity, and terrain_severity is
## the one knob between them. See its comment for why the gap exists and why it
## must not be closed.
func terrain_factor(wade: float, grade: float) -> float:
	var raw := snow_factor(wade) * slope_factor(grade)
	return lerpf(1.0, raw, clampf(terrain_severity, 0.0, 1.0))


## The pace the run would reach if he were running, before the terrain touches it.
##
## `locomotion:run_speed` goes to ZERO when fatigue is empty, and maxf() against
## the walk is what turns that into 无法奔跑 rather than a standstill. A partial
## multiply -- nothing authored uses one today -- scales the run down but can
## never take it under the walk.
func run_ceiling() -> float:
	return maxf(walk_speed, _channel(&"locomotion:run_speed", run_speed))


## How deep the snow may be before the run goes, after the body has had its say.
##
## WHERE GDD SECTION 5's 雪深惩罚加剧 LIVES. `locomotion:run_snow_limit` is
## scaled down by fatigue and by ruined feet, so a tired man loses the run in
## snow a fresh man still runs through -- the snow penalty has genuinely worsened
## for him, and it has done so without any body state touching the speed itself.
func run_snow_ceiling() -> float:
	return clampf(_channel(&"locomotion:run_snow_limit", run_snow_limit), 0.0, 1.0)


## Whether there is a run to be had here at all.
##
## THE ONLY PLACE THE BODY IS ALLOWED TO AFFECT MOVEMENT. Both gates are
## capabilities rather than speeds: how deep the snow is against what this body
## can still manage, and whether there is any run left in him at all.
func can_run(wade: float) -> bool:
	if clampf(wade, 0.0, 1.0) > run_snow_ceiling():
		return false
	return run_ceiling() > walk_speed + 0.0001


## The top ground speed the body can manage: in snow of this wade factor, on this
## grade, with the walk promoted this far toward the run.
##
## Public and pure so the model can be exercised without a scene tree, a snow
## field or a bus -- which is what lets test_locomotion.gd check it against the
## real world rather than against a screenshot.
##
## `gait` is NOT gated here. The gates live in advance_gait(), which eases the
## blend toward zero when they shut, because cutting the speed the moment the
## snow deepened would be exactly the step change the auto-run is supposed to
## avoid. This function stays a pure function of its three arguments, so it is
## monotone in wade for any fixed gait and there is no way to get a faster answer
## out of deeper snow.
##
## ---------------------------------------------------------------------------
## NOTHING ABOUT THE BODY SCALES THIS NUMBER
## ---------------------------------------------------------------------------
## The owner's rule -- 只受到雪深度和地形坡度的影响 -- is literally true here, and
## it is worth saying what it cost to make it so. `locomotion:speed` used to be
## applied on the way out (0.85 when tired, 0.85/0.80 for ruined feet) and
## `locomotion:snow_cost` on the way in, so the same ground gave two different
## speeds depending on the body. Both are gone.
##
## GDD section 5's 疲劳高 -> 移速下降 and 足部冻伤 -> 移速永久下降 are NOT dropped.
## They are restated as capability gates, in the vocabulary the GDD already uses
## for 无法奔跑, and they live in can_run() and run_snow_ceiling(). The rule that
## separates them is worth keeping in one line:
##
##   the TERRAIN says how fast the ground lets you move -- it SCALES
##   the BODY says how much capability is left  -- it GATES
##
## So the only thing the survival model can still reach in here is run_ceiling(),
## which decides whether the `gait` argument has anywhere to go. See
## tools/generate_stats.gd for why that is better design and not just a way to
## satisfy two documents at once.
func top_speed_at(wade: float, grade := 0.0, gait := 0.0) -> float:
	var pace := lerpf(walk_speed, run_ceiling(), clampf(gait, 0.0, 1.0))
	return maxf(pace * terrain_factor(wade, grade), 0.0)


## How far the walk has been promoted toward the run, 0 .. 1.
func run_blend() -> float:
	return _run_blend


## Advances the auto-run by one tick and returns the new blend.
##
## `direction` is what he is being ASKED to do -- the horizontal input, zero when
## he is standing -- rather than the velocity he ended up with. Reading velocity
## would make the promotion depend on the snow he is already in, and a man wading
## out of a drift would have to earn the run twice.
##
## Three things end a run, and they are the three the owner named plus the one
## GDD section 5 already had:
##
##   stopping           -- the hold resets outright, so setting off again costs
##                         the full threshold. Stopping is a decision.
##   a sharp turn       -- more than auto_run_turn_degrees off his own smoothed
##                         heading. A curve is not a turn; see the constant.
##   snow / exhaustion  -- can_run(), a capability rather than a speed.
##
## The blend eases toward its target rather than being assigned, which is what
## keeps every one of those from being a step change in velocity.
func advance_gait(delta: float, direction: Vector3, wade: float, forced := false) -> float:
	var flat := Vector3(direction.x, 0.0, direction.z)
	var moving := flat.length_squared() > 0.0001
	if not moving:
		_run_hold = 0.0
		_run_heading = Vector3.ZERO
	else:
		var heading := flat.normalized()
		if _run_heading.length_squared() < 0.0001:
			_run_heading = heading
		elif rad_to_deg(_run_heading.angle_to(heading)) > auto_run_turn_degrees:
			# A flick or an about-face. He has to commit again.
			_run_hold = 0.0
			_run_heading = heading
		else:
			var turn := 1.0 - exp(-auto_run_heading_smoothing * maxf(delta, 0.0))
			_run_heading = _run_heading.lerp(heading, turn).normalized()
		# Capped so a long walk does not bank credit a stumble cannot spend.
		_run_hold = minf(_run_hold + delta, auto_run_delay + 1.0)

	var wants := moving and can_run(wade) and (forced or _run_hold >= auto_run_delay)
	var target := 1.0 if wants else 0.0
	var rate := auto_run_rise if target > _run_blend else auto_run_fall
	_run_blend = lerpf(_run_blend, target, 1.0 - exp(-rate * maxf(delta, 0.0)))
	# An exponential ease never arrives. Left alone the blend sits a thousandth
	# short of the target for ever, which is harmless but shows up in any test
	# that asks whether he is running.
	if absf(_run_blend - target) < 0.001:
		_run_blend = target
	return _run_blend


## Publishes the auto-run threshold as a setting and reads the player's choice
## back over the authored default.
##
## Idempotent, and safe to call from a test: it adds one key, never calls
## ProjectSettings.save(), and a value already present wins. The property info is
## what a settings screen needs to build the slider in UI design section 4.2's
## 操作 group without hardcoding a range.
##
## Read at _ready(), so a settings screen that writes the setting mid-run should
## call this again -- that is the whole of "apply", and it is why the function is
## public and idempotent rather than a private one-shot.
func register_settings() -> void:
	if not ProjectSettings.has_setting(AUTO_RUN_SETTING):
		ProjectSettings.set_setting(AUTO_RUN_SETTING, auto_run_delay)
	ProjectSettings.set_initial_value(AUTO_RUN_SETTING, auto_run_delay)
	ProjectSettings.add_property_info({
		"name": AUTO_RUN_SETTING,
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.0,5.0,0.1",
	})
	ProjectSettings.set_as_basic(AUTO_RUN_SETTING, true)
	var chosen := float(ProjectSettings.get_setting(AUTO_RUN_SETTING, auto_run_delay))
	auto_run_delay = maxf(chosen, 0.0)


## What the body is telling the readouts, driven every physics frame.
##
## One number for how cold he is, and it goes to both the stand and the breath:
## GDD section 9's readouts have to agree with each other or they stop being a
## readout. `speed` is the ground speed, which is also what the animation blend
## reads, so exertion cannot disagree with the gait either.
func drive_readouts(speed: float) -> void:
	set_chill(body_chill())
	if _breath == null:
		return
	_breath.set_exertion(clampf(inverse_lerp(anim_idle_speed, run_speed, speed), 0.0, 1.0))
	_breath.set_chill(chill)
	# GDD section 9's 呼吸变浅变快. Data, not a branch: the threshold rows live in
	# data/stats/core_temperature.tres and this passes on whatever they say.
	_breath.set_rate_scale(_channel(&"breath:rate", 1.0))


## One line of plumbing to the survival model's published channels. An absent
## model, or a channel nothing has an opinion about, returns the base untouched.
func _channel(channel: StringName, base_value: float) -> float:
	if _survival == null:
		return base_value
	return _survival.channel_value(channel, base_value)


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


## Registered here rather than in project.godot because these five actions are
## the whole input surface of the slice and this keeps them in one readable
## place. `has_action` first, so a real input map added later wins.
##
## `move_run` is GDD section 5's control table -- Shift | 奔跑 -- and it does not
## replace the auto-run, it short-circuits its wait. Holding it promotes him now;
## letting it go hands him back to the timer rather than dropping him to a walk,
## because a player who has been sprinting for ten seconds has plainly committed.
func _register_actions() -> void:
	var bindings := {
		&"move_forward": [KEY_W, KEY_UP],
		&"move_back": [KEY_S, KEY_DOWN],
		&"move_left": [KEY_A, KEY_LEFT],
		&"move_right": [KEY_D, KEY_RIGHT],
		&"move_run": [KEY_SHIFT],
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
	# get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is a
	# node under /root and never enters the engine's singleton registry
	# (briefing trap 3). A null _survival is a legal state -- every authored
	# default stands -- which is exactly why getting this wrong would be silent.
	if _survival == null:
		_survival = get_node_or_null("/root/SurvivalSystem")
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

	# The two things the owner's ruling says decide his speed, read off the ground
	# he is standing on: how deep the snow is, and how steeply it runs along the
	# way he is going. The grade is resolved along `direction` rather than taken
	# as the terrain's steepest slope -- see grade_along().
	var wade := 0.0
	var grade := 0.0
	if _snow != null:
		wade = _snow.wade_factor(global_position)
		grade = grade_along(_snow.surface_gradient_at(global_position), direction)

	# Whether he is walking or running, eased, and gated on the snow he is in.
	var forced := InputMap.has_action(&"move_run") and Input.is_action_pressed(&"move_run")
	var gait := advance_gait(delta, direction, wade, forced)
	var top_speed := top_speed_at(wade, grade, gait)

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
	var snow_depth := 0.0
	var snow_max := 1.0
	if _snow != null:
		var ground: float = _snow.terrain_height_at(global_position)
		snow_depth = _snow.depth_at(global_position)
		snow_max = maxf(_snow.max_depth_m, 0.0001)
		var wanted_y := ground + snow_depth * (1.0 - sink_fraction)
		if _grounded:
			var blend := 1.0 - exp(-vertical_smoothing * delta)
			global_position.y = lerpf(global_position.y, wanted_y, blend)
		else:
			# First frame: land on the surface rather than easing down to it
			# from wherever the scene happened to place the body.
			global_position.y = wanted_y
			_grounded = true

	# The furrow, from where the body ACTUALLY is on this tick -- not from where
	# the last foot landed. See advance_furrow(): that distinction is the whole
	# of the third pass at this feature. Called whatever the snow is doing, so
	# the anchor keeps up with the walker across ground too thin to plough.
	var furrows := advance_furrow(global_position, snow_depth, snow_max)
	if _bus != null:
		for sample in furrows:
			_bus.emit_event(FURROW_EVENT, sample)

	var travelled := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if travelled > 0.0001:
		_facing = Vector3(velocity.x, 0.0, velocity.z).normalized()
		_advance_stride(travelled)

	_face_travel(delta)
	_drive_animation(wade, grade)
	drive_readouts(Vector2(velocity.x, velocity.z).length())


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

	_bus.emit_event(FOOTPRINT_EVENT, payload)


## ---------------------------------------------------------------------------
## The furrow
## ---------------------------------------------------------------------------
## Every furrow segment the walk from the last anchor to `here` has earned.
##
## Called once per physics tick with the body's real position, and it returns
## payloads rather than emitting them so the geometry can be tested without a
## scene tree, a bus or a snow field. That matters more than it usually would:
## the two rejected passes at this feature failed on GEOMETRY -- the shape of the
## line, not the strength of it -- and a straight-line screenshot cannot tell a
## good version from a bad one. tests/unit/test_furrow.gd walks an arc and
## measures the corner in degrees.
##
## The anchor advances whether or not anything is drawn, so a walker crossing
## from a drift onto a scoured crest and back again does not join the two drifts
## with a line across the bare ground between them.
func advance_furrow(here: Vector3, depth: float, max_depth: float) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	if not _has_furrow_anchor:
		_has_furrow_anchor = true
		_furrow_anchor = here
		return samples

	var from := _furrow_anchor
	var step := Vector2(here.x - from.x, here.z - from.z).length()
	if step > furrow_max_jump_m:
		# Not a walk: a respawn, a restart, or a harness dropping the body
		# somewhere else. Re-anchor and draw nothing.
		_furrow_anchor = here
		return samples
	if step < furrow_sample_m:
		return samples
	_furrow_anchor = here

	# A physics tick cannot cover more than about 9 cm at full sprint, so this
	# splits nothing in practice. It is here for the frame that stalls: one long
	# segment is exactly the polyline the whole design avoids.
	var pieces := maxi(int(ceilf(step / maxf(furrow_sample_m, 0.001))), 1)
	for index in range(pieces):
		var a := from.lerp(here, float(index) / float(pieces))
		var b := from.lerp(here, float(index + 1) / float(pieces))
		# Advanced even when the gate is shut, so the wobble stays a continuous
		# function of ground covered rather than of ground covered in deep snow.
		_furrow_travel += step / float(pieces)
		var sample := _furrow_sample(a, b, depth, max_depth)
		if not sample.is_empty():
			samples.append(sample)
	return samples


## One segment, or an empty dictionary where the snow is too thin to plough.
func _furrow_sample(from: Vector3, to: Vector3, depth: float, max_depth: float) -> Dictionary:
	var span := maxf(max_depth - furrow_depth_start_m, 0.001)
	var bite := clampf((depth - furrow_depth_start_m) / span, 0.0, 1.0)
	if bite <= 0.0:
		return {}
	# See furrow_onset: below 1 this rises steeply off the gate, so the first
	# metres of a drift draw something you can actually see.
	bite = pow(bite, furrow_onset)
	return {
		"from": from,
		"to": to,
		"depth": maxf(
			furrow_strength * bite * (1.0 + _wobble(_furrow_travel) * furrow_depth_wobble),
			0.0
		),
		"half_width": maxf(
			furrow_half_width_m
				* lerpf(furrow_narrow_at_gate, 1.0, bite)
				* (1.0 + _wobble(_furrow_travel + WOBBLE_WIDTH_PHASE) * furrow_width_wobble),
			0.01
		),
	}


## Far enough along the same noise that the width never tracks the depth. Any
## large offset does; this one is prime and unmemorable on purpose.
const WOBBLE_WIDTH_PHASE := 613.0


## The wobble, as a function of metres walked. One noise field, built once, with
## a fixed seed -- the variation has to be reproducible or a print laid down on
## one frame could be redrawn differently on the next.
func _wobble(travel: float) -> float:
	if _furrow_noise == null:
		_furrow_noise = FastNoiseLite.new()
		_furrow_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_furrow_noise.fractal_octaves = 2
		_furrow_noise.seed = furrow_wobble_seed
		_furrow_noise.frequency = 1.0 / maxf(furrow_wobble_wavelength_m, 0.01)
	return _furrow_noise.get_noise_1d(travel)
