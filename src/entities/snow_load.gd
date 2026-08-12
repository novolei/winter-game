extends Node3D

## A CHILD OF A WALKER. Snow packs onto his boots and shins when he wades a
## drift, and settles on his hood and shoulders when it snows on him -- and he
## knocks both off again, step by step, until he is clean. What he is carrying
## makes him colder.
##
## ---------------------------------------------------------------------------
## ONE LOAD FIELD, TWO SOURCES, AND THEY LIVE IN DIFFERENT PLACES
## ---------------------------------------------------------------------------
##   WADED   from below. Boots and shins, gated on `SnowField.deep_depth_m`,
##           packed on by a footfall and knocked off by one. It marks him to the
##           depth he actually walked through.
##   SETTLED from above. Whatever faces the sky -- hood, shoulders, the tops of
##           the sleeves, the rim of a boot -- fed by the snowfall rate and by
##           nothing else, so it builds while he STANDS STILL and only while it
##           is actually snowing.
##
## The owner asked for exactly one special case and it is not written anywhere:
## "with no snowfall, only walking in deep snow marks the boots and shins". That
## falls out. The settling rate is proportional to the snowfall rate, so at a
## rate of zero it is zero, and the waded half is untouched by weather.
##
## THREE THINGS TAKE IT OFF, and the first of them is why standing still is what
## lets it build:
##   * A FOOTFALL shakes some of both loose. Same impact model as the shed --
##     see below -- so a man who walks it off has to walk, and a man who stands
##     in a blizzard accumulates.
##   * WARMTH MELTS IT, fast: inside a building, or near a lit fire. Snow on a
##     coat in a warm room is gone in seconds and the player should be able to
##     watch it go.
##   * WIND STRIPS the settled half. Loose snow on a shoulder in a gale does not
##     stay there. The waded half is packed and is not touched by this.
##
## AND IT MAKES HIM COLD. The total load pushes a MULTIPLY onto
## `core_temperature:drain` through SurvivalSystem's own modifier stack, which is
## the seam NightExposure and Stove already use, in the same remove-then-push
## idiom they use. Snow on your clothes takes heat out of you; that is the whole
## claim, and it is an input to the survival model rather than anything to do
## with how fast he walks.
##
## ---------------------------------------------------------------------------
## WHY IT IS A CHILD AND NOT AN AUTOLOAD
## ---------------------------------------------------------------------------
## The crust is a material parameter on one particular mesh, so ONE instance can
## only ever whiten ONE character's legs. An autoload is one instance. That is
## the whole argument: this effect subscribes to `player.footprint` rather than
## calling into the player precisely so the bear in Wave 4 and the hungry man in
## Wave 5 get leg snow for free, and a single global node cannot deliver them.
##
## So it is a node under the body it belongs to. It finds its subject by looking
## UP -- its nearest Node3D ancestor is the walker it dresses -- which means
## giving the bear leg snow is adding one child node to the bear and nothing
## else: no registry entry, no export to point, no `.gd` change anywhere. It
## still takes its footfalls off the bus and still ignores the ones that landed
## too far away to be its own, so two walkers in one scene each shed their own
## snow.
##
## ---------------------------------------------------------------------------
## THE MODEL: IT COMES OFF BY IMPACT, NOT BY THE PASSAGE OF TIME
## ---------------------------------------------------------------------------
## Nothing here runs on a timer and nothing here fades. Snow leaves a leg
## because the leg hits the ground, so every change to the load happens on a
## FOOTFALL and on nothing else. That one decision buys the effect its rhythm
## for free: the bursts land on the steps because they ARE the steps, and a walk
## that slows down sheds more slowly without a line of code saying so.
##
## Each step takes the same FRACTION of what is still there, so the load decays
## exponentially per footfall rather than linearly. That is the physical claim,
## not a curve chosen for looks: the loose powder goes in the first two or three
## strides, and what is left has been compacted by the leg and part-melted by
## body heat and refrozen, and it clings. At the shipped retention of 0.70 the
## sheds run 0.30, 0.21, 0.15, 0.10, 0.07, ... -- three bursts you cannot miss as
## he clears the drift, then progressively less, then a trace on the boot that is
## still there twenty steps later.
##
## Loading is the same rule read backwards: a step in deep snow packs a fixed
## fraction of what is still BARE, so a leg fills quickly and can never fill past
## full. One rule, two directions, and the walk in and the walk out are the same
## arithmetic.
##
## ---------------------------------------------------------------------------
## TWO POPULATIONS, SEPARATED BY DRAG AND BY NOTHING ELSE -- AND GRAINS ARE THE
## MAJORITY
## ---------------------------------------------------------------------------
##   GRAINS  low drag, and most of the shed. Snow packed onto a leg by wading is
##           compacted crystal; a footfall breaks it into crumbs. They are thrown
##           -- outward and forward, over a wide angle -- they fall, and they
##           ARRIVE somewhere. Crisp-edged, opaque, and drawn big enough to be
##           individually visible at the framing the game is played at.
##   MIST    high drag, and a small fraction. Only the finest part of a crust is
##           light enough to become airborne at all. It barely falls, it hangs,
##           it spreads, and it goes out soft.
##
## THE MIX IS THE POINT AND IT WAS WRONG THE FIRST TIME. Mist in the majority
## reads as steam off a boot: weightless, and nothing like the granular spray a
## boot full of packed snow actually throws. Grains alone read as gravel with
## nothing behind them. So grains lead by roughly four to one, and the mist stays
## on to soften the leading edge of the burst and to catch the low sun.
##
## The reason the two behave differently is one number each, `grain_damping` and
## `mist_damping`. The wind hook then falls out of that same number rather than
## being a second decision: see `wind_response()`, which is why a gust carries
## the mist away and hardly deflects a grain.
##
## ---------------------------------------------------------------------------
## THE SNOW LINE ON YOUR LEGS IS THE DEPTH YOU WALKED THROUGH
## ---------------------------------------------------------------------------
## That is the one physical fact this whole effect is about, and it is the fact
## the crust has to state. So the crust's upper edge is not a tuned band: it is
## the deepest snow he actually waded through this crossing, MEASURED, remembered
## until his legs are clean again, and reset when they are.
##
## It is measured rather than assumed because the number that matters is not the
## snow's depth -- it is how far up the DRAWN figure the snow reached, and those
## are not the same. `PlayerController` sinks the body through a fraction of the
## depth so the figure looks like it is standing IN the drift rather than on it,
## so his soles are drawn some way above the true ground. `snow_line_on_the_leg()`
## therefore asks the field where the surface is and the body where its feet are,
## and subtracts. Nothing here holds a copy of the sink, and nothing here can
## drift out of step with it.
##
## Two things fall out of that, and both matter:
##
##   * WHILE HE IS IN THE DRIFT THE CRUST IS EXACTLY BURIED. Its top coincides
##     with the snow surface by construction, so there is nothing to see until he
##     steps out -- which is correct, his legs are under the snow, and it is what
##     the effect looked like before this was measured rather than guessed.
##   * IT IS VARIABLE. A shallow crossing marks him a little and a deep one marks
##     him a lot, and the difference is several times the area. A constant band
##     reads as texture and disappears at the game camera; a quantity that
##     changes between two crossings is the thing an eye at that distance can
##     actually catch.
##
## The spray is what the player reads as "and now I am losing it". What they read
## as "I am carrying snow" is the legs themselves going whiter -- opaque
## near-white patches from the boot up to that line, capped under the knee,
## broken up by noise and thinning out as they climb.
##
## PATCHES AND NOT A BAND, AND OPAQUE AND NOT A WASH. The first version varied
## its ALPHA with the load, and pale snow at half alpha over a dark coat is a
## blue transparent film -- which is what it looked like, and it was reported as
## exactly that. What varies now is COVERAGE: how much of the leg carries snow at
## all. Every patch that does is solid, bare fabric shows between them, and as he
## sheds the patches go out one at a time instead of the whole crust dimming.
## `assets/shaders/snow_load.gdshader` holds it, and it rides
## `GeometryInstance3D.material_overlay` so that neither the character's Meshy
## maps nor the x-ray ghost already in his `next_pass` is disturbed.
##
## ---------------------------------------------------------------------------
## IT KNOWS ABOUT FOOTFALLS, NOT ABOUT THE PLAYER
## ---------------------------------------------------------------------------
## Everything above is driven by `player.footprint` off the EventBus, which
## `PlayerController` emits deliberately so that nothing needs to know about the
## player -- its own comment says the bear will emit the same event in Wave 4.
## So this file makes no edits to the player and contains no reference to him.
##
## The depth that loads a leg is `SnowField.deep_depth_m`, read off the field
## rather than restated here. It is the same 0.42 m that already means "reduced
## to a trudge" and that gates the ploughed furrow: one fact about the snow, now
## read three ways rather than four.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const CRUST_SHADER_PATH := "res://assets/shaders/snow_load.gdshader"
const FOOTPRINT_EVENT := &"player.footprint"

## The events this listens to for warmth, all of them already published by
## somebody else. Nothing here reaches into a farmhouse or a stove: a building
## says when it has been entered, a fire says when it has been lit, and this node
## melts what it is carrying if either is near. A Wave 5 beacon that emits
## `stove.lit` melts snow off a walker for free.
const INTERIOR_ENTERED_EVENT := &"interior.entered"
const INTERIOR_EXITED_EVENT := &"interior.exited"
const FIRE_LIT_EVENT := &"stove.lit"
const FIRE_OUT_EVENT := &"stove.went_out"

## The service that says how hard it is snowing, and the autoload that holds the
## body's reserves. Both resolved rather than referenced -- see `_resolve()`.
const SNOWFALL_SERVICE := &"snowfall"
const SURVIVAL_PATH := "/root/SurvivalSystem"

## SurvivalSystem's channel grammar: "<stat>:<channel>". A bare stat id means the
## drain channel, but it is spelled out here because a warmth source and a chill
## source must never be able to land on the same stack -- see the survival
## system's own note on why recovery is a separate stack from drain.
const CHILL_TARGET := &"core_temperature:drain"
const CHILL_SOURCE := &"snow_load"

## How near a footfall has to be to count as this walker's.
##
## The footprint payload carries no publisher, and it should not: it is a fact
## about a patch of snow, not a message from a character. So a walker's own steps
## are picked out by where they landed. One and a half metres is wider than a
## stride and much narrower than the distance between two characters who are not
## standing on each other.
##
## WITH NO SUBJECT ABOVE IT THIS CLAIMS EVERYTHING, which is the useful default
## rather than the safe-looking one: an instance built by a test with no parent
## still sheds snow, and the alternative -- an effect that silently does nothing
## when a lookup fails -- is the failure mode this project has been bitten by
## most.
@export var claim_radius_m := 1.5

## ---------------------------------------------------------------------------
## The load
## ---------------------------------------------------------------------------
## How much of what is still bare gets packed on by one step in deep snow. High:
## wading is not subtle, and a leg that took eight strides to load would spend
## most of a drift looking clean.
@export var pack_per_step := 0.55

## How much of the load SURVIVES one step on ground that is not deep. The whole
## shape of the effect is this number -- see the header for the sequence it
## produces. Lower and he is clean in two strides with one big burst; higher and
## the bursts never become distinct.
@export var shed_retention := 0.70

## Below this the leg is treated as clean for the purposes of throwing snow. The
## crust keeps fading below it -- it is continuous all the way to zero -- but an
## exponential never actually arrives, and emitting a burst of nought point three
## of a particle for the rest of the run is not a physical claim, it is a leak.
@export var shed_floor := 0.02

## ---------------------------------------------------------------------------
## The hook Wave 3's weather can drive, and the only optional thing here
## ---------------------------------------------------------------------------
## Dry powder in hard cold does not stick; snow near freezing does. So colder air
## should shed faster, and the model already has the number that says so.
##
## THIS IS A HOOK AND IT IS INERT, in the vocabulary BreathFog's and
## SnowfallLayer's identically-named hooks use. `src/systems/weather_system.gd`
## is Wave 3 and does not exist, and there is no air temperature anywhere in the
## project today -- `core_temperature` is the BODY's reserve, which is a
## different fact and would be the wrong one to read. Inventing an air
## temperature here would mean two of them later. `_air_chill` therefore stays 0
## until something calls `set_air_chill()`, and at 0 `shed_retention` above is
## exactly what applies.
@export var shed_retention_cold := 0.56

## ---------------------------------------------------------------------------
## The snow that falls ON him
## ---------------------------------------------------------------------------
## How much of what is still BARE settles in a second of the heaviest snowfall
## there is. The same saturating rule as the waded half, on a clock rather than
## on footfalls -- because this one IS about the passage of time: it is the sky
## depositing snow at a rate, and a man who stands still for a minute in a
## whiteout is a man wearing a minute of it.
##
## ---------------------------------------------------------------------------
## THIS IS THE NUMBER THAT DECIDES WHETHER STANDING STILL IS A PROCESS OR A
## SWITCH, AND IT WAS THREE TIMES TOO FAST
## ---------------------------------------------------------------------------
## Reported by the owner playing it: "玩家身上的积雪速度太过于快了 … 现在静止一下
## 子身上的积雪就很明显了，我希望可以是一个真实随静止时间慢慢变化的过程". Snow
## appearing on a man the moment he stops is not weather, it is a state change
## with a fade on it. What he asked for is something he can watch happen.
##
## SO IT IS TUNED IN SECONDS OF STANDING STILL, NOT IN THIS CONSTANT. The
## landmarks are measured off rendered frames with
## `tools/measure_crust_coverage.gd` at the framing the game is played at, which
## counts the pixels the crust actually paints:
##
##     settle 0.005 ->  240 px   THE FLOOR -- see below
##     settle 0.10  ->  472 px   twice the floor: the first state worth calling snow
##     settle 0.30  ->  688 px   over half a caked man: unmistakable
##     settle 1.00  -> 1255 px   caked
##
## The floor is worth knowing because no rate can move it: `crease_bias`
## saturates the noise field on the most upward-facing folds, so the first flake
## to land puts 240 px of white in his creases whatever this number says. What
## this number controls is everything after that.
##
## At 1/120, and with `Snowfall`'s own 0.12 for `pale_day` and 1.0 for
## `whiteout`, the day-one time constant comes out at exactly 1000 seconds:
##
##                     day 1 (0.12)      whiteout (1.0)
##     one minute      0.058, 395 px     0.394, ~800 px
##     legible (0.10)  105 s             13 s
##     obvious (0.30)  357 s             43 s
##
## -- a minute of standing about on day one is barely perceptible and it takes
## the better part of six minutes to become obvious, while a blizzard does both
## in seconds. The 8.3x between them is the snowfall rate and nothing else: there
## is no second model for heavy weather, which is why `test_snow_load.gd` pins
## the RATIO of the two times as well as the times.
##
## The previous 1/40 put him at 0.165 after a minute of day one and made it
## obvious in 119 seconds, which is what was reported.
@export var settle_per_second := 1.0 / 120.0

## What a footfall shakes off the settled half, as a fraction of what is there.
##
## SEPARATE FROM `shed_retention`, and much harsher, because it is a different
## material. The waded crust has been compacted by the leg and part-melted by
## body heat and refrozen, and it clings; snow that has merely landed on a
## shoulder is loose and the first hard step takes most of it. At 0.45 retention
## the settled load runs 0.55, 0.30, 0.17, 0.09 -- gone in four or five strides,
## which is what makes "shake it off at the door" a thing a player can do.
@export var settle_retention := 0.45

## How much of the settled half the wind strips per second, per m/s^2 of it. The
## waded crust is packed and gets none of this -- the same distinction the two
## retentions above make.
##
## ---------------------------------------------------------------------------
## RULED: WIND ON A BODY IS NOT WIND ON A ROOF, AND THIS WAS THE WRONG MODEL
## ---------------------------------------------------------------------------
## This started at 0.09, written when `set_wind()` was a hook nobody called and
## the only picture in mind was loose snow blowing off a shoulder. Then
## `src/systems/wind_system.gd` arrived and drove it, and the number turned out
## to be describing a roof.
##
## ON A ROOF, REMOVAL IS RIGHT. A flat horizontal surface holds loose snow and a
## gale takes it away, which is exactly what the ground and accumulation shaders
## do with the same wind and they are correct to.
##
## ON A MAN IT IS WRONG, AND WRONG IN THE OPPOSITE DIRECTION. A vertical, rough,
## folded surface standing in driven snow gets PLASTERED. Anybody who has stood
## out in a blizzard comes back caked on the windward side, not cleaned off. Wind
## in heavy snowfall increases deposition on a body; it does not strip it. Roof
## snow and body snow are different materials on different surfaces, and they
## must no more share a model than they share an appearance.
##
## WHAT THE WRONG MODEL COST, measured. Settling gains `k(1-s)` a second and this
## strips `settle_wind_strip * |wind| * s`, so a standing man equilibrates at
## `s* = k/(k+w)`. In the game's own whiteout -- wind measured at 0.11 .. 0.46 --
## 0.09 put that at a QUARTER of a load, and under the shipped gale profile at
## 0.07. The worst weather in the game could never cover him. Nothing errored and
## no test failed; only a capture of a man standing in a whiteout not going white
## showed it, and since the load is what raises his heat loss, the survival
## coupling went quietest exactly where it should have been loudest.
##
## SO IT IS A RESIDUAL, NOT A FORCE, and 0.003 is derived rather than dialled:
## the scour may not hold a standing man below 0.85 at the strongest wind the
## shipped profile produces in a whiteout, so
## `strip = k(1 - 0.85) / (0.85 * 0.46)`. What that then gives everywhere else:
##
##     whiteout, ordinary wind 0.28   plateau 0.91   obvious in 44 s
##     whiteout, gusting at    0.46   plateau 0.86
##     whiteout, gale peak     1.14   plateau 0.71
##     whiteout, full gale     1.68   plateau 0.62
##
## -- a gale is still a visible difference from still air, and it can no longer
## keep him clean. `tests/unit/test_snow_load.gd::
## test_a_blizzard_cakes_him_even_with_the_wind_blowing` holds all of that.
##
## The mechanism is unchanged and still earns its place on a CLEAR day, which is
## the case it was written for: with nothing falling, wind is the only thing
## other than a footfall that takes loose snow off a shoulder.
##
## FLAGGED, NOT BUILT: the truthful version of this is DIRECTIONAL -- the
## windward side accumulates while the leeward scours -- which at this project's
## fixed camera yaw would be genuinely beautiful. It is a per-fragment claim
## about `dot(normal, wind)` rather than a scalar, and it is not what was asked
## for. See the task report.
@export var settle_wind_strip := 0.003

## How fast warmth melts BOTH loads, as a fraction of what is left per second.
## The owner asked for "quickly" and this is quickly: at 0.55 a full load is
## under a tenth in four seconds and gone in eight. Fast enough to watch, slow
## enough to be a thing that happens rather than a switch.
@export var melt_per_second := 0.55

## How near a lit fire has to be for its warmth to melt what he is carrying.
## Stove's own `warm_radius_m` is 3.0 and its falloff runs to 6.0; this sits
## between them, because melting the snow off a coat is a thing that happens
## where you can feel the fire rather than everywhere its light reaches.
@export var fire_melt_radius_m := 4.0

## ---------------------------------------------------------------------------
## What it costs him
## ---------------------------------------------------------------------------
## How much faster he loses heat with a FULL load on, as a multiplier on
## `core_temperature`'s drain. 1.0 would be free; at 1.55 a man caked in snow
## cools about half again as fast as a dry one, which is roughly the difference
## between a 20-minute reserve and a 13-minute one.
##
## A MULTIPLY rather than an ADD, and on the drain channel rather than against
## recovery, because that is what it is: snow on your clothes does not remove a
## fixed number of degrees, it defeats the insulation, so everything that was
## already taking heat out of you takes it out faster. It composes correctly with
## NightExposure's own 2.0 for the same reason.
@export var chill_at_full_load := 1.55

## How much the load has to move before the modifier is rewritten. SurvivalSystem
## wants remove-then-push -- a re-push without the remove compounds the stack --
## and doing that pair sixty times a second to track a number that changes on
## footfalls would be churn. Two per cent is finer than anything the player can
## perceive and coarse enough that a steady walk rewrites it once a step.
@export var chill_step := 0.02

## ---------------------------------------------------------------------------
## Where on the leg it sits
## ---------------------------------------------------------------------------
## As fractions of the subject's height. Measured off the shipped rig rather than
## chosen: its toe sits at 2.2% of the figure, its ankle at 7.9% and its knee at
## 25.7%.
##
## ONLY THE TWO ENDS ARE AUTHORED. Where the crust actually reaches is
## `wade_fraction()` -- the snow line he waded through, measured -- and these two
## are the floor and the ceiling it lives between:
##
##   `boot_line`  what a nearly-clean leg still wears. The last of it clings to
##                the boot, so the line RETREATS to here as he sheds rather than
##                merely fading, which is what reads as cleaning up rather than
##                as an effect being switched off.
##   `knee_line`  the measured knee, and a hard cap. A crust over the knee is not
##                snow off a drift, it is a costume change, and the field can be
##                retuned deeper without this having to be re-checked by eye.
##
## RULED, AND THE RULING IS LOAD-BEARING: what these produce today is a crust on
## the BOOT, because 32-45 cm on a 1.88 m figure sunk three quarters into the
## snow IS the boot, and the crust may NOT be drawn higher than the snow he
## actually waded to make it read further up the leg. The band's whole value is
## that it records something true; a flattered number survives today's terrain
## and breaks the day the drifts get deeper. The snow is what is short, not this.
## `assets/shaders/snow_load.gdshader` carries the measurements and the second,
## independent finding that reached the same conclusion.
@export var boot_line := 0.10
@export var knee_line := 0.257

## Fallback height for a subject that publishes no `body_height`.
@export var subject_height := 1.9

## ---------------------------------------------------------------------------
## The grains -- the majority, and what the shed IS
## ---------------------------------------------------------------------------
## Grains in one burst at a full shed. The count scales with the shed, so this is
## the FIRST stride out of a drift and every later one is a fraction of it.
@export var grains_per_shed := 60.0

## Short. A grain is knocked loose, thrown, and lands; it has no business still
## being in the air a second later.
@export var grain_life := 0.5

## How hard it comes off, in metres a second before the spread below is applied.
## This is an IMPACT: the foot hits the ground and the crust that was on it keeps
## going. Nothing here drifts out of anything.
@export var grain_speed := 2.3

## How wide the spray opens, in degrees either side of the direction of travel.
## Wide, because a boot hitting packed snow throws it sideways as much as
## forwards, and a narrow cone reads as a jet rather than as something breaking.
@export var grain_spread_degrees := 70.0

## Nearly no drag: a grain is ballistic, which is what makes it ARRIVE somewhere.
## This is also the whole of its difference from the mist -- see `wind_response()`
## -- so a gust carries the mist away and hardly deflects a grain.
@export var grain_damping := 0.22

## What is left of gravity once the air has had its say -- and the number that
## decides whether a grain is SEEN at all.
##
## Measured, not chosen. At a full 9.8 a crumb thrown off a boot 20 cm up is back
## down in 0.2 s, and the ground it lands on is a displaced mesh drawn above the
## body's own origin -- so it does not land, it goes THROUGH the surface and
## disappears. Ten grains a step were being emitted, flying correctly, and were
## invisible in every frame; switching gravity off entirely was what showed them
## still there. At 6.0 the same crumb arcs for about 0.4 s and travels half a
## metre, which is a flight the eye can follow, and `grain_life` below ends just
## after it reaches the snow.
##
## It is not a cheat: a 5 cm crumb of snow has a great deal of surface for its
## mass, and this is what is left of its weight after the air.
@export var grain_fall := 6.0

## How wide a grain is DRAWN, in metres -- and it is a legibility figure rather
## than a size.
##
## Under about 2.5 px a particle stops being an object and becomes a sub-pixel
## sample that shimmers. `SnowfallLayer.min_flake_pixels` is this project's own
## figure and its header derives it at length; a grain that falls under it does
## not read as grit, it reads as haze, which is the exact failure this population
## exists to avoid. Fewer grains that can be seen beat more that cannot.
##
## The arithmetic, against the framing the game is played at -- CameraRig's
## `orthographic_size` of 10.5 m over an 800 px frame, so 76.2 px per metre. The
## size spread below runs to 0.85 of this at the small end, so the SMALLEST grain
## in a burst is 0.0425 m and 3.2 px, and the largest is 4.4 px. The floor is
## checked against the smallest, because a floor that only the average clears is
## not a floor.
##
## At CameraRig's widest framing stop of 17.0 m the smallest grain falls to about
## 2.0 px, under the floor. That is a deliberate line rather than an oversight:
## the wide stop is a zoom-out and everything in it gets smaller. Sizing for it
## instead would put 8 cm lumps of snow on his boots at the framing he is
## actually played at.
@export var grain_size_m := 0.05

## How much a grain's size varies within one burst, either side of the size
## above. Narrow, unlike the mist's: the floor above has to hold for the smallest
## grain in the spread, and a wide spread spends most of its range below it.
@export var grain_size_spread := 0.15

## ---------------------------------------------------------------------------
## The mist -- the minority, and an accompaniment rather than the effect
## ---------------------------------------------------------------------------
## Snow packed onto a leg by wading is compacted crystal, and a footfall breaks
## it into grains. Only the finest fraction of that ever becomes airborne, so
## this count is a small fraction of the grains' and it must stay that way: mist
## in the majority is what makes a shed read as steam off a boot.
##
## It still earns its place. It softens the leading edge of the burst and it is
## the part that catches a 21.5-degree sun, so the spray has something behind it
## rather than being a handful of dots in clear air.
@export var mist_per_shed := 7.0

## How long a puff survives, and how fast it leaves the boot. Slow: this fraction
## is carried off, not thrown.
@export var mist_life := 1.4
@export var mist_speed := 0.75

## The drag, and it is the whole difference between the two populations. High
## enough that the kick off the boot is spent in about a third of a second and
## what is left drifts.
@export var mist_damping := 2.6

## What is left of gravity once the air is holding it up. Not 9.8 and not
## pretending to be: a mote this fine reaches terminal velocity immediately, and
## against the damping above this settles at about 35 cm a second, which is a
## puff sinking rather than a stone dropping.
@export var mist_fall := 0.9

## The still-air drift, in metres a second. SnowfallLayer makes the same argument
## for the same reason: snow that hangs dead still looks wrong on a calm day too,
## and this is the part the wind hook then adds to rather than replaces.
@export var mist_drift := Vector3(0.16, 0.0, 0.06)

## Birth and death radius of one puff, in metres. It EXPANDS -- fine snow
## disperses,
## so the oldest puff in a shed is the biggest and the faintest. BreathFog makes
## the same point about vapour at greater length and it is the same physics.
@export var mist_radius_birth := 0.05
@export var mist_radius_death := 0.18

## The most alpha a puff ever carries. The mist is the ONLY soft-edged, part-
## transparent thing here: a small blob with a soft falloff reads as fog whatever
## size it is drawn at, which is right for this fraction and wrong for every
## other part of the effect.
@export var mist_alpha := 0.45

## ---------------------------------------------------------------------------
## What the shed is drawn in -- one hue, three values
## ---------------------------------------------------------------------------
## THE HUE IS NEARLY WHITE, AND THAT IS A CORRECTION RATHER THAN A DRIFT.
##
## The palette's snow entry describes the snow FIELD: a huge area seen at
## distance under a blue sky, through the aerial perspective this project builds
## on purpose. Its blue comes from that situation. A patch of snow on a dark coat
## a metre from the lens is in a different one -- lit directly, scattering white
## -- and taking the field's blue there is what produced a crust that read as a
## blue transparent film over his legs rather than as snow on them.
##
## So the tone is that palette entry taken almost all the way to white. It is
## still not a literal and still moves if the palette moves; it is simply
## acknowledged that the entry was never a claim about this case. The character
## is already exempt from the Art Bible's surface rules by the owner's ruling,
## so nothing new is being excused here.
@export var shed_whiteness := 0.88

## And three VALUES, because the same white has to be drawn three different ways.
##
## Value is separated from hue because the two answer different questions. The
## hue answers "what colour is snow on a coat" and is shared. The value answers
## "how bright may this be drawn before Art Bible rule 12's glow -- which belongs
## to the fire, the windows, the beacon, the truck and the scarf -- starts coming
## off a boot", and that has a different answer for a lit surface than for an
## unshaded billboard, because the two reach the screen by different routes.
@export var crust_value := 0.42
@export var grain_value := 0.86
@export var mist_value := 0.74

## ---------------------------------------------------------------------------
## The crust on the leg
## ---------------------------------------------------------------------------
## OPAQUE WHERE IT EXISTS. The crust used to vary its alpha with the load, which
## is what made it read as a blue film: at half alpha you see the dark coat
## through pale snow, and pale-over-dark is a wash. What varies now is COVERAGE
## -- how many patches of the leg carry snow at all -- and every patch that does
## is solid. Bare fabric shows BETWEEN the patches, not THROUGH them.
@export var crust_opacity := 1.0

## HOW MUCH OF THE CLOTH CARRIES SNOW where the crust is thickest, at the sole.
##
## THIS IS THE NUMBER THE EFFECT WAS FAILING ON, and it was failing by an order
## of magnitude rather than by a little. Measured off a rendered frame with
## `tools/measure_crust_coverage.gd` -- which renders the band on its own, renders
## the crust, and counts one against the other -- the shipped version covered
## 30.9% of the band at a full load and **2.9%** at 0.70. 0.70 is the first load
## the game ever shows, because the crust is exactly buried while he is still in
## the drift and his first step out sheds three tenths of it, so 2.9% is what
## every frame anybody judged this by actually contained. It read as a dusting of
## sparkles on a boot rim rather than as a man who had waded a drift.
##
## The target is a third to a half of the band, so this is the coverage at the
## sole and `patch_scatter` thins it from there. Do not tune it by eye -- run the
## measurement.
@export var crust_coverage := 0.44

## How the covered fraction is SPREAD, as a frequency over the character's UVs.
## Higher is many small marks; lower is a few big slabs.
##
## THIS IS A DIFFERENT AXIS FROM `crust_coverage` ABOVE, and treating them as one
## is the mistake that produced the look the owner rejected. The threshold decides
## how MUCH of the cloth carries snow; this decides how that amount is
## distributed. The same 44% is four blocks or two hundred marks depending only on
## this number, and only the second reads as a man who has been out in it.
##
## IT WENT DOWN FOR THE WRONG REASON AND HAS COME BACK UP. At a measured coverage
## of 2.9% the prescription was "bigger patches, not more of them", and this went
## from 42 to 11.5. The 2.9% had three other causes entirely -- all in the band
## arithmetic, all fixed, coverage now 43.9% -- so the coarsening was a remedy for
## someone else's problem, and what it actually did is what low-frequency noise
## always does: large connected regions of on and of off. The figure came out with
## a few blocky patches on the hood and one shoulder and bare arms, chest and
## thighs between them.
##
## The ends of the range are both real. Below about 20 the marks connect into
## slabs; above about 42 a mark on a 130 px figure at the game camera is a
## sub-pixel sample and shimmers instead of sitting still.
@export var patch_scale := 30.0

## How hard the edges of the patches are against the noise's own distribution. At
## 1 the noise is used raw and the threshold sweeps a soft, gradual field; higher
## stretches it so patches appear and disappear as WHOLE patches, which is the
## breaking-up read the shed is supposed to have.
##
## Around 1.8 the stretched field is close to flat, which is what makes
## `crust_coverage` above mean very nearly "this fraction of the cloth" -- so it
## can be aimed at a measured target instead of tuned until it looks right.
@export var patch_contrast := 1.8

## How far the clump outlines are pushed about by a coarse noise of their own.
## Thresholding a plain fBm gives round shoulders; this pulls them into fingers
## and inlets, which is the shape snow actually breaks into.
@export var patch_warp := 0.55

## How far below the crust's upper line the coverage ramp runs, AS A FRACTION OF
## THE BAND. At the sole every patch is present; approaching the line he waded
## only the luckiest few are.
##
## AGAINST THE BAND, NOT THE FIGURE, and that is the other half of the fix. It
## used to be 0.16 of the FIGURE -- 30 cm -- against a band that is only 43 cm
## tall, so five sixths of the crust lived on the falling half of the ramp and
## the whole thing collapsed the moment the band shortened. Measured against the
## band it keeps its shape whether he came out of half a metre of snow or a fifth
## of one.
@export var patch_scatter := 0.35

## The same pair for the snow that FELL on him: how much of an upward-facing
## surface it covers at a full settled load, how far up a surface has to face
## before it holds any, and how quickly that gate opens.
##
## `settle_facing` is what makes the two loads live in different places without a
## line of code choosing: at 0.12 a vertical shin collects nothing out of the
## sky, while a hood, a shoulder, the top of a sleeve and the rim of a boot all
## do. A man standing still in a blizzard whitens from the top and a man out of a
## drift whitens from the bottom, and neither is a special case.
@export var settle_coverage := 0.82
@export var settle_facing := 0.12
@export var settle_falloff := 0.62

## How strongly the character's own normal map decides WHERE it catches.
##
## Snow settles on the upward-facing side of every crease and seam, and the
## figure already carries a normal map with all of them in it -- see
## `_crease_map_of()`, which takes it off whatever material is already on the
## mesh rather than naming a file, so a bear with its own map gets its own
## creases and a subject with no map gets plain noise.
@export var crease_bias := 0.42

## How far into the noise field one wearer may be offset from another, in the
## noise's own cells. See `_noise_offset`.
##
## Eight rather than eighty, and the reason is arithmetic rather than taste. The
## field decorrelates completely within ONE cell, so eight is already far more
## variety than anybody can exhaust -- the offset is continuous, not one of eight
## slots. The ceiling is what keeps the hash honest: `snow_hash` takes `fract()`
## of its input multiplied by a few hundred, and every cell of offset pushes the
## third octave's lookup further out into float32's coarse ground, where the hash
## starts quantising and the field starts to band.
const NOISE_OFFSET_CELLS := 8.0

## How much drag has to be present before the air can carry a particle at all.
## The mist and the grains get their wind response from this one expression
## rather than from two hand-set numbers, which is what keeps them a single
## physical claim -- see `wind_response()`.
const WIND_COUPLING_REFERENCE := 1.0

## Godot's `emit_particle` flags, named rather than spelled 5.
const EMIT_PLACED := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY

var _bus: Node
var _registry: Node
var _snow: Node
var _snowfall: Node
var _survival: Node
var _subject: Node3D
var _mist: GPUParticles3D
var _grains: GPUParticles3D
var _mist_material: ParticleProcessMaterial
var _grain_material: ParticleProcessMaterial
var _crusts: Array[ShaderMaterial] = []
var _dressed: Array[MeshInstance3D] = []
var _load := 0.0
## WHERE IN THE NOISE FIELD THIS PARTICULAR WEARER STANDS, in the noise's own
## cells. The owner asked for this: "身上的积雪的位置和面积好像每次都是固定的" --
## the snow was in the same places every time, because the field is a hash of the
## surface's UVs and nothing else.
##
## ROLLED HERE, AT CONSTRUCTION, AND THAT IS THE WHOLE OF THE DESIGN. Three
## things follow from where this line is, and each of them was a requirement:
##
##   * IT BELONGS TO THE WEARER. One SnowLoad dresses one body, so one roll is
##     one character's pattern -- and the bear in wave 4 gets its own by being a
##     second instance rather than by anybody passing it a seed.
##   * IT IS NOT A FUNCTION OF WHERE HE IS. Seeding from world position would
##     make the marks crawl across him as he walks, which is worse than a fixed
##     pattern because motion is what the eye catches.
##   * IT IS NOT A FUNCTION OF TIME. Not rewritten per frame -- the per-frame
##     block in `_process()` deliberately does not touch it -- so within one
##     accumulation cycle his snow appears and disappears in the same places, and
##     the threshold reads as patches going out one at a time rather than as
##     static.
##
## ONE ROLL PER LOAD, THOUGH, AND NOT ONE PER WEARER. The third property above
## was first written as "once, at construction", which froze the pattern for the
## whole life of the character rather than for the life of a load -- so a walker
## who crossed a drift, cleaned himself off and crossed another came out wearing
## the same marks in the same places. The owner asked for that not to be true,
## and offered to accept it if it were a performance decision. It is not one: the
## offset is a single vec2 uniform. See `_watch_for_a_clean_slate()` for the rule
## and for what "clean" had to be defined as.
##
## Godot randomises the global seed at startup, so two playthroughs differ; a
## replay or a capture that needs the same pattern twice calls
## `set_noise_offset()`, and a pinned pattern is never re-rolled.
var _noise_offset := Vector2(randf(), randf()) * NOISE_OFFSET_CELLS
## Whether he was clear of snow at the last look. The re-roll happens on the EDGE
## -- the moment the load reaches zero -- rather than on every frame he stands
## clean, which is what makes it one new pattern per crossing instead of a new
## one every frame he happens to be carrying nothing.
##
## True at birth, because a new wearer is clean and already carries a fresh
## offset: his first crossing must not re-roll a pattern nobody has seen yet.
var _clean := true
## Whether somebody has pinned this wearer's pattern by hand. See
## `set_noise_offset()`: a capture that pinned an offset so it could be compared
## against another capture must not have it re-rolled out from under it.
var _pattern_pinned := false
## How far up his legs the snow reached at the DEEPEST point of this crossing, in
## world metres above his soles. See the header: this is the whole of what the
## crust's upper edge says, and it is remembered until the legs are clean.
var _wade_line_m := 0.0
var _last_shed := 0.0
var _steps_since_drift := 0
var _wind := Vector3.ZERO
var _air_chill := 0.0
## What the sky has put on him, 0 clean .. 1 caked. Separate from `_load` because
## it lives somewhere else on the body, is fed by something else, and comes off
## at a different rate -- see the header.
var _settle := 0.0
var _snowfall_rate := 0.0
var _sky_overridden := false
var _indoors := false
## Whether the world has been asked what was already burning and already warm
## when this node arrived. See `_ask_what_is_already_true()`.
var _asked_the_world := false
## Where the lit fires are. Kept as positions rather than as nodes because that
## is what the events carry, and because a fire is a place that is warm rather
## than an object this needs to hold on to.
var _fires: Dictionary = {}
## The last chill multiplier actually pushed at SurvivalSystem, so the
## remove-then-push pair happens when the load MOVES rather than every frame.
var _chill_pushed := 1.0


func _ready() -> void:
	_build()
	# Trap 3: an autoload is a node under /root, never an Engine singleton. Guarded
	# on is_inside_tree() because an absolute path cannot be resolved from a node
	# that is not in a tree, and a unit test builds this one with `.new()` --
	# unguarded it is an engine ERROR, which by this project's standard is a failed
	# run whatever the assertions said.
	if is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
	if _bus != null:
		_bus.subscribe(FOOTPRINT_EVENT, _on_footprint)
		# WARMTH, TAKEN OFF WHOEVER PUBLISHES IT. A building says it has been
		# entered and a fire says it has been lit; nothing here knows what a
		# farmhouse or a stove is, so a Wave 5 beacon that emits `stove.lit` melts
		# the snow off a walker without a line being added.
		_bus.subscribe(INTERIOR_ENTERED_EVENT, _on_interior_entered)
		_bus.subscribe(INTERIOR_EXITED_EVENT, _on_interior_exited)
		_bus.subscribe(FIRE_LIT_EVENT, _on_fire_lit)
		_bus.subscribe(FIRE_OUT_EVENT, _on_fire_out)


func _exit_tree() -> void:
	if _bus != null:
		_bus.unsubscribe(FOOTPRINT_EVENT, _on_footprint)
		_bus.unsubscribe(INTERIOR_ENTERED_EVENT, _on_interior_entered)
		_bus.unsubscribe(INTERIOR_EXITED_EVENT, _on_interior_exited)
		_bus.unsubscribe(FIRE_LIT_EVENT, _on_fire_lit)
		_bus.unsubscribe(FIRE_OUT_EVENT, _on_fire_out)
	# A walker who leaves the scene stops being cold. Leaving a MULTIPLY behind on
	# a stat nobody is applying it to any more is the exact failure the
	# remove-then-push idiom exists to prevent.
	if _survival != null and is_instance_valid(_survival):
		_survival.remove_source(CHILL_SOURCE)
	_undress()


# --- the model ----------------------------------------------------------------

## What a footfall in deep snow leaves on the leg.
##
## A fixed fraction of what is still BARE, so the first stride into a drift packs
## the most on and no number of strides packs past full. Static and contextless
## on purpose: it is arithmetic with a right answer, and it is the piece a test
## can pin down exactly without a scene, a bus or a snow field.
static func loaded_after(carried: float, gain: float) -> float:
	var held := clampf(carried, 0.0, 1.0)
	return clampf(held + (1.0 - held) * clampf(gain, 0.0, 1.0), 0.0, 1.0)


## What a footfall on ground that is not deep knocks OFF.
##
## The same rule read the other way: a fixed fraction of what is still there. The
## consequence is the whole look -- successive sheds fall away geometrically, so
## the first strides out of a drift burst and the later ones do not.
static func shed_by_a_step(carried: float, retention: float) -> float:
	return clampf(carried, 0.0, 1.0) * (1.0 - clampf(retention, 0.0, 1.0))


## What a second of snowfall settles onto him.
##
## The same saturating fraction-of-what-is-bare rule as `loaded_after`, and
## deliberately so: one physical claim, read three ways. `rate` is the snowfall
## rate, 0 clear .. 1 whiteout, so THE SPECIAL CASE THE OWNER ASKED FOR IS NOT
## WRITTEN ANYWHERE -- at a rate of nothing, nothing settles, and only wading
## marks him.
##
## Framerate-correct rather than `+= rate * delta`: an exponential approach
## integrated per frame drifts with the frame time, and this effect is judged in
## captures taken at a fixed 60 while the game runs at whatever it runs at.
static func settled_after(carried: float, rate: float, gain_per_second: float, delta: float) -> float:
	var held := clampf(carried, 0.0, 1.0)
	var pace := maxf(gain_per_second, 0.0) * clampf(rate, 0.0, 1.0)
	if pace <= 0.0 or delta <= 0.0:
		return held
	return clampf(held + (1.0 - held) * (1.0 - exp(-pace * delta)), 0.0, 1.0)


## What a second of warmth, or of wind, takes off. Also a fraction of what is
## left per second, and also integrated properly for the same reason.
static func decayed_after(carried: float, per_second: float, delta: float) -> float:
	var held := clampf(carried, 0.0, 1.0)
	if per_second <= 0.0 or delta <= 0.0:
		return held
	return clampf(held * exp(-per_second * delta), 0.0, 1.0)


## How much faster he loses heat carrying this much snow.
##
## Linear in the load and starting at 1.0, so a dry man is charged nothing and
## the modifier can be pushed unconditionally rather than being a special case at
## zero. A MULTIPLY on the drain channel: snow does not remove a fixed number of
## degrees, it defeats the insulation, so it scales whatever was already taking
## heat out of him.
static func chill_multiplier(carried: float, at_full: float) -> float:
	return 1.0 + (maxf(at_full, 1.0) - 1.0) * clampf(carried, 0.0, 1.0)


## How much of a wind a particle with this much drag picks up, 0 .. 1.
##
## The two populations differ in ONE property and everything else follows from
## it. Drag is what couples a particle to the air it is in, so a mote of mist
## -- which stops dead in a third of a second -- is carried, and a grain, which
## is ballistic, is barely deflected. Writing two hand-tuned wind strengths would
## have got the same picture out of two decisions that could drift apart; this
## way there is one decision and it is `mist_damping` against `grain_damping`.
static func wind_response(damping: float) -> float:
	var drag := maxf(damping, 0.0)
	return drag / (drag + WIND_COUPLING_REFERENCE)


## Turns an expected particle count into a whole one.
##
## THE FRACTIONAL PART IS A PROBABILITY, and that is what keeps the tail of a
## shed HONEST rather than continuous. At an expectation of 0.4 a particle is
## thrown on two steps in five and none at all on the other three, which is what
## a boot with almost nothing left on it actually does. Rounding instead would
## give either a particle every single step or none ever, depending on which side
## of a half the tuning happened to land -- and by the twelfth stride out of a
## drift both expectations are well under one.
##
## Takes the roll rather than making it, so a test can pin both branches.
static func burst_count(expected: float, roll: float) -> int:
	if expected <= 0.0:
		return 0
	var whole := int(floorf(expected))
	if roll < expected - float(whole):
		whole += 1
	return whole


## The retention actually in force, after the air temperature hook. At the
## inert default this is `shed_retention` exactly.
func retention_now() -> float:
	return lerpf(shed_retention, shed_retention_cold, clampf(_air_chill, 0.0, 1.0))


## How much snow the legs are carrying, 0 clean .. 1 straight out of a drift.
func carried() -> float:
	return _load


## How much has settled on him out of the sky, 0 clean .. 1 caked.
func settled() -> float:
	return _settle


## What he is carrying altogether, and the number the survival system is charged
## for. The larger of the two rather than their sum, because they are loads on
## DIFFERENT PARTS of him -- a man with white shoulders and white boots is not
## carrying twice what a man with only white shoulders is, and adding them would
## let two half-loads cost more than one whole one.
func total_load() -> float:
	return maxf(_load, _settle)


## Is he somewhere warm enough for it to melt off him? Public because it is the
## kind of thing a test wants to state directly, and because whoever wires a
## second warm place can drive it without inventing a second event.
func is_thawing() -> bool:
	if _indoors:
		return true
	if _fires.is_empty() or _subject == null or not is_instance_valid(_subject):
		return false
	var here := _origin_of(_subject)
	for spot in _fires.values():
		if (spot as Vector3).distance_to(here) <= fire_melt_radius_m:
			return true
	return false


## What the last footfall knocked off. Zero on a step that loaded instead.
func last_shed() -> float:
	return _last_shed


## How far up his legs the snow reached at the deepest point of this crossing, in
## metres. Zero once the legs are clean and the crossing is over.
func wade_line_m() -> float:
	return _wade_line_m


## Where the crust reaches at a FULL load, as a fraction of the figure: the snow
## line he waded, held between the boot and the knee.
##
## The floor is not a safety clamp -- it is the last of the crust clinging to the
## boot. The ceiling is: `SnowField.max_depth_m` is a number somebody may raise,
## and a crust above the knee stops being snow off a drift.
func wade_fraction() -> float:
	var height := _subject_height()
	if height <= 0.0:
		return boot_line
	return clampf(_wade_line_m / height, boot_line, knee_line)


## Where the crust's upper edge is RIGHT NOW, as a fraction of the figure. It
## starts at the line he waded and retreats to the boot as he sheds -- the same
## journey the shader makes, computed here so a test can read it without a GPU.
func crust_top_fraction() -> float:
	return lerpf(boot_line, wade_fraction(), clampf(_load, 0.0, 1.0))


## One line for tools/capture_sequence.gd. A still cannot show whether the first
## step bursts and the fourth does not; the numbers beside the frames can. `line`
## is the crust's own height in centimetres, which is what makes a deep crossing
## and a shallow one comparable across two sequences rather than only by eye.
## `pattern` is where in the noise field this crossing's snow is being drawn
## from, and it is here for the same reason trap 9 gives: when a value is
## generated in code, print what the engine actually got. A re-roll that fired on
## the wrong edge, or never fired at all, looks identical in a still -- two
## frames of a boot with snow on it -- and is one number apart in the log.
##
## `wind` is beside it because the two clocked forces on the settled half now
## fight each other and the loser is invisible: a settled load that stops rising
## has either saturated or is being stripped as fast as it lands, and only this
## number tells the two apart. Measured standing still in a whiteout, it is the
## difference between "he cakes up" and "he plateaus at a fifth of a load".
func report() -> String:
	return "snowload[load=%.2f settle=%.2f shed=%.2f steps=%d wade=%.0fcm line=%.0fcm fall=%.2f wind=%.2f pattern=(%.2f,%.2f)%s]" % [
		_load, _settle, _last_shed, _steps_since_drift,
		_wade_line_m * 100.0, crust_top_fraction() * _subject_height() * 100.0,
		_snowfall_rate, _wind.length(), _noise_offset.x, _noise_offset.y,
		" thawing" if is_thawing() else "",
	]


# --- the hooks ----------------------------------------------------------------

## THE WIND HOOK, in the vocabulary BreathFog and SnowfallLayer already use for
## the identical hook. `src/systems/wind_system.gd` is Wave 3; until it exists
## this is called by nobody and the value stays zero, and the mist drifts on
## `mist_drift` alone. Both populations are driven from it through
## `wind_response()`, so one call moves the mist a long way and the grains
## hardly at all.
func set_wind(velocity: Vector3) -> void:
	_wind = velocity
	_apply_wind()


func wind() -> Vector3:
	return _wind


## 0 near freezing .. 1 hard dry cold. See `shed_retention_cold`: this is the
## optional half of the effect and it is deliberately inert, because there is no
## air temperature in this project yet and inventing one here would mean two of
## them later.
func set_air_chill(amount: float) -> void:
	_air_chill = clampf(amount, 0.0, 1.0)


## Which part of the noise field this wearer's snow is drawn from, in cells.
func noise_offset() -> Vector2:
	return _noise_offset


## Pins the pattern, rather than rolling one.
##
## For a capture that has to be comparable with another capture -- two builds of
## this effect judged side by side are judged on the same marks or they are not
## judged at all -- and for a replay or a loaded save that wants the walker it
## had. Everything already dressed is rewritten, so this works after the fact and
## not only before.
##
## AND IT PINS, which is the whole of the word: a wearer whose pattern was set by
## hand never re-rolls it when he shakes clean. Without that, a measurement that
## happened to walk the load down to nothing between two of its own renders would
## silently start comparing two different patterns and report the difference as
## the difference between two builds.
func set_noise_offset(offset: Vector2) -> void:
	_pattern_pinned = true
	_write_noise_offset(offset)


func _write_noise_offset(offset: Vector2) -> void:
	_noise_offset = offset
	for crust in _crusts:
		crust.set_shader_parameter(&"noise_offset", _noise_offset)


## Is he carrying anything at all?
##
## `shed_floor` IS the answer and not a second number beside it. This file
## already calls that "clean" twice -- it is the point below which a shed stops
## throwing particles, and the point at which the chill modifier comes off the
## survival stack -- and a third definition that could drift from those two would
## be a defect looking for somewhere to happen.
func is_clean() -> bool:
	return total_load() < shed_floor


## A NEW CROSSING GETS A NEW PATTERN, and the trigger is the load reaching zero
## rather than him stopping.
##
## The owner asked for the snow to land somewhere else next time, and said he
## would accept a fixed pattern if it were a performance decision. IT IS NOT ONE.
## The offset is one vec2 uniform and rolling it again costs a uniform write. The
## pattern is frozen because it MUST be frozen while a load persists -- patches
## that jump position while snow is on him are a far louder artefact than a
## repeat, and that is what the stability constraint exists to prevent. The
## constraint was simply written wider than it needed to be: it froze the pattern
## for the life of the wearer instead of for the life of a load.
##
## So, three behaviours, and only the second of them is new:
##
##   * While he is carrying anything, nothing moves.
##   * The moment he is completely clear, the next accumulation starts somewhere
##     else in the field.
##   * A short walk that leaves some of the load on him keeps the pattern, which
##     is what the physics says: the snow still on him has not moved.
##
## "ZERO" HAS TO BE A THRESHOLD, AND THAT IS THE PART THAT DECIDES WHETHER ANY OF
## THIS WORKS. Both decay rules are exponential, so the load approaches zero and
## never arrives -- a re-roll waiting for a true zero never fires and the whole
## feature silently does nothing, which is the defect class this project has been
## bitten by most. Clean is `shed_floor`, 0.02, the number this file already uses
## for it. At the shipped retentions that is eleven footfalls out of a full
## crossing (0.70^11 = 0.0198) and five for the settled half (0.45^5 = 0.0185):
## a few seconds of walking, reached in play rather than in principle.
##
## AND THE SWAP CANNOT BE SEEN HAPPENING, which is what makes the edge safe to
## put here rather than at the start of the next crossing. At a load of 0.02 the
## vertex stage scales the waded coverage by `smoothstep(0.0, 0.16, 0.02)` =
## 0.042, so under 2% of the boot is carrying anything; the settled half at 0.02
## covers 1.6% of what faces the sky. The pattern moves while there is nothing
## drawn to move.
func _watch_for_a_clean_slate() -> void:
	var clear := is_clean()
	if clear and not _clean and not _pattern_pinned:
		_write_noise_offset(Vector2(randf(), randf()) * NOISE_OFFSET_CELLS)
	_clean = clear


## Injection point for a test, and for whoever wires a second walker without a
## registry. Null is a legal state and means nothing ever loads -- a walker with
## no snow field is a walker with no snow.
func set_snow_field(field: Node) -> void:
	_snow = field


## Overrides the walker found by looking up the tree. For a test, and for anyone
## who wants this node somewhere other than under the body it dresses.
func set_subject(subject: Node3D) -> void:
	_undress()
	_subject = subject


## How hard it is snowing, 0 clear .. 1 whiteout.
##
## PUSHED OR PULLED, and both work. `Snowfall` publishes itself under
## `&"snowfall"` and this reads `snowfall_rate()` off it every frame, which is
## the same arrangement `SnowAccumulation` uses. This setter exists so a test can
## make it snow without a weather system, and so anything that wants to override
## the sky for one walker can -- a man under a porch roof, say.
##
## ONCE SET IT STICKS, exactly as `Snowfall.set_snowfall_rate()` sticks, and for
## the same reason: a setter that the next frame's pull silently overwrites is a
## setter that does nothing, which is worse than not having one. Found the way
## these things are always found -- a unit test made it snow and the node
## obediently ignored it the moment it was in a real scene.
func set_snowfall_rate(rate: float) -> void:
	_snowfall_rate = clampf(rate, 0.0, 1.0)
	_sky_overridden = true


func snowfall_rate() -> float:
	return _snowfall_rate


## Injection point for the body's reserves. Null is legal and means the load
## costs him nothing, which is what a walker in a test scene should experience.
func set_survival_system(system: Node) -> void:
	if _survival != null and is_instance_valid(_survival) and _survival != system:
		_survival.remove_source(CHILL_SOURCE)
	_survival = system
	_chill_pushed = 1.0


## Warmth, by hand. The events do this on their own; this is for a test, and for
## whoever builds a warm place that is neither a building nor a fire.
func set_indoors(inside: bool) -> void:
	_indoors = inside


# --- warmth, off the bus ------------------------------------------------------

## THE STATE THAT WAS ALREADY TRUE BEFORE THIS NODE EXISTED.
##
## A node that listens only for a TRANSITION can never learn a state that changed
## before it was there to hear it. `stove.lit` fires once, at ignition, and the
## farmhouse stove ignites at startup from `start_lit` -- so a walker who begins
## the run beside a burning stove subscribes to a change that already happened
## and stands in the warm carrying snow forever. It presents as "works when I
## walk in, broken when I start inside", which reads like a wiring fault and is
## not one.
##
## So the change is subscribed to AND the state is asked for, once. Two details
## that are not incidental:
##
##   * ON THE FIRST PROCESS, NOT IN `_ready()`. Ready runs bottom-up in tree
##     order; this node sits under Player and the stove under Farmhouse further
##     down the scene, so at our `_ready()` the stove's own `_ready()` has not
##     run and it is not lit yet whatever `start_lit` says. By the first
##     `_process` the whole tree is up -- the same reason briefing trap 1 gives
##     for the test runner ticking before it asserts.
##   * BY CAPABILITY, NOT BY NAME. Nothing here knows what a stove or a farmhouse
##     is, so this asks whatever can answer: a thing that both `is_lit()` and can
##     say how warm a point is, is a fire; a thing that knows whether its occupant
##     is inside is a building. Duck-typed exactly like the `snowfall_rate()` and
##     `surface_height_at()` reads elsewhere in this file. Neither publishes
##     itself as a service, which is the API gap this works around -- see the
##     report; a registry key or a group for fires would make this a lookup
##     rather than a walk.
func _ask_what_is_already_true() -> void:
	if _asked_the_world:
		return
	# From the topmost thing above this node rather than from `get_tree().root`,
	# which in the game is the same walk and out of a tree is the difference
	# between working and not being testable at all.
	var world := get_parent()
	if world == null:
		return
	while world.get_parent() != null:
		world = world.get_parent()
	_asked_the_world = true
	var answered: Array[Node] = []
	_capable_of(world, answered)
	for node in answered:
		if node.has_method(&"is_occupant_inside") and _is_mine(node) \
				and bool(node.call(&"is_occupant_inside")):
			_indoors = true
		if node.has_method(&"is_lit") and node.has_method(&"warmth_at") \
				and bool(node.call(&"is_lit")) and node is Node3D:
			_fires[_origin_of(node as Node3D)] = _origin_of(node as Node3D)


## Where a Node3D is, without asserting that it is in a tree.
##
## `global_position` fails an engine ERROR outside a tree -- the same trap
## `_place()` already guards -- and by this project's standard a stray ERROR is a
## failed run whatever the assertions said. Out of a tree the local position IS
## the world position, because there is no parent transform to compose with.
static func _origin_of(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


static func _capable_of(node: Node, found: Array[Node]) -> void:
	if node.has_method(&"is_occupant_inside") \
			or (node.has_method(&"is_lit") and node.has_method(&"warmth_at")):
		found.append(node)
	for child in node.get_children():
		_capable_of(child, found)


## Is this building talking about the walker THIS node dresses?
##
## `interior.entered` carries no subject -- it is a fact about a building, not a
## message about a character -- so the building is asked who its occupant is and
## the answer compared against the body above this node. Without it, the bear in
## Wave 4 would thaw every time the player stepped indoors.
##
## Unanswerable means yes, which is the same useful default `claim_radius_m`
## documents: a node with nothing above it in the tree, or a payload with no
## reveal in it, still gets warm. An effect that silently does nothing when a
## lookup fails is the failure mode this project has been bitten by most.
func _is_mine(reveal) -> bool:
	if _subject == null or not is_instance_valid(_subject):
		return true
	if reveal == null or not is_instance_valid(reveal) or not reveal.has_method(&"occupant"):
		return true
	var inhabitant = reveal.call(&"occupant")
	return inhabitant == null or inhabitant == _subject


## All four handlers take one untyped argument, because EventBus always calls
## back with exactly one whatever the payload is, and a payload this cannot use
## must be ignored rather than crash the publisher.
func _on_interior_entered(payload) -> void:
	if _is_mine(_reveal_in(payload)):
		_indoors = true


func _on_interior_exited(payload) -> void:
	if _is_mine(_reveal_in(payload)):
		_indoors = false


static func _reveal_in(payload):
	return null if not (payload is Dictionary) else (payload as Dictionary).get("reveal", null)


func _on_fire_lit(payload) -> void:
	if not (payload is Dictionary):
		return
	var spot = (payload as Dictionary).get("position", null)
	if spot is Vector3:
		# Keyed by where it is, so a fire that announces itself twice is one fire
		# and a fire that goes out can be found again by the same key.
		_fires[spot] = spot


func _on_fire_out(payload) -> void:
	if not (payload is Dictionary):
		return
	var spot = (payload as Dictionary).get("position", null)
	if spot is Vector3:
		_fires.erase(spot)


# --- the footfall -------------------------------------------------------------

## Untyped, because it arrives off the bus and a payload this cannot use must be
## ignored rather than crash the publisher.
func _on_footprint(payload) -> void:
	if not (payload is Dictionary):
		return
	var data: Dictionary = payload
	var spot = data.get("position", null)
	if not (spot is Vector3):
		return
	if not _claims(spot):
		return
	# The depth AT THE FOOT, which the publisher has already measured, rather
	# than a second sample taken from the field at the body's centre. The foot is
	# where the leg meets the snow, so it is the honest place to ask.
	step(spot, float(data.get("depth", 0.0)), _heading_of(data))


## One footfall, and the whole of the model. Public so a test can walk a body
## through a drift and out of it without a bus, a field or a scene tree.
func step(spot: Vector3, depth: float, heading: Vector2) -> void:
	# EVERY footfall shakes the settled half loose, in the drift and out of it, and
	# that is the whole of why STANDING STILL is what lets it build. It is a
	# separate retention from the waded crust's because it is a different material:
	# what has merely landed on a shoulder is loose, and the first hard step takes
	# most of it, while a crust packed by a leg and refrozen clings.
	var shaken := shed_by_a_step(_settle, settle_retention)
	_settle = maxf(_settle - shaken, 0.0)
	if shaken >= shed_floor:
		_throw(spot, shaken, heading, _subject_height() * 0.45, _subject_height() * 0.95)
	var deep := _deep_depth()
	if depth >= deep:
		_load = loaded_after(_load, pack_per_step)
		# THE HIGH-WATER MARK, and the reason it is a max rather than the latest
		# reading: a man who crosses a shoulder of the drift and then a hollow
		# comes out wearing the hollow. Snow does not come off a leg because the
		# next step was shallower -- it comes off when the leg hits the ground, and
		# that is the other branch.
		_wade_line_m = maxf(_wade_line_m, snow_line_on_the_leg(spot, depth))
		_last_shed = 0.0
		_steps_since_drift = 0
		_place(spot)
		return
	_steps_since_drift += 1
	var shed := shed_by_a_step(_load, retention_now())
	_load = maxf(_load - shed, 0.0)
	_last_shed = shed
	_place(spot)
	if _load + shed < shed_floor:
		# Long clean. Nothing left to knock off, and the crust below the floor is
		# already fading to nothing on its own -- so the crossing is over, and the
		# next drift gets to leave its own mark rather than inheriting this one's.
		_wade_line_m = 0.0
	else:
		_throw(spot, shed, heading, 0.06, _leg_top_m())
	# Written as an else rather than an early return so that this line is reached
	# on both branches: the step that takes him under the floor is the commonest
	# way a load ends, and a re-roll that the commonest case skipped would be a
	# feature that fires only in the rare one.
	_watch_for_a_clean_slate()


## How far up his legs the snow he is standing in actually reaches, in metres.
##
## NOT THE DEPTH. The depth is how thick the snow is; this is how far up the
## figure the camera can see it climb, and the two differ by the sink --
## `PlayerController` draws the body some way down INTO the drift so it reads as
## standing in the snow rather than on it, which puts his soles above the true
## ground by exactly the part of the depth he has sunk through.
##
## So it is not calculated from the sink, it is measured either side of it: the
## field is asked where its surface is and the body is asked where its feet are.
## Nothing here holds a copy of `sink_fraction`, so nothing here can fall out of
## step with it -- and the crust's top lands exactly ON the snow line, which is
## what keeps it invisible while he is still in the drift and correct the instant
## he leaves it.
##
## With no field or no body to ask -- a unit test, a walker in an empty scene --
## the depth IS the answer, because with nothing sunk there is nothing to
## subtract.
## Capped at the depth itself, which is not a safety clamp but the same physical
## statement said twice: the snow on your leg cannot be deeper than the snow.
##
## It earns its place on a transient. The body eases DOWN into a drift over about
## a third of a second while the surface under it rises at once, so for the first
## stride or two of a crossing the gap between them is wider than the snow really
## is -- and this records a maximum, so an over-read on the entry stride would
## stick for the whole crossing.
func snow_line_on_the_leg(spot: Vector3, depth: float) -> float:
	var deepest := maxf(depth, 0.0)
	if _snow != null and _subject != null and is_instance_valid(_subject) \
			and _subject.is_inside_tree():
		var above_the_soles := float(_snow.surface_height_at(spot)) - _subject.global_position.y
		return clampf(above_the_soles, 0.0, deepest)
	return deepest


## The depth at which a leg starts collecting snow.
##
## READ OFF THE FIELD AND NOT RESTATED. `SnowField.deep_depth_m` is already the
## depth the game calls a trudge and already the depth the ploughed furrow starts
## at; a copy of the number here would be a fourth threshold that could disagree
## with the other three. With no field resolved this returns INF, which is the
## correct behaviour rather than a guard: there is no snow, so nothing loads.
func _deep_depth() -> float:
	_resolve()
	if _snow == null:
		return INF
	return float(_snow.deep_depth_m)


## Is this footfall this walker's?
##
## See `claim_radius_m`: with nobody resolved, everything is claimed.
func _claims(spot: Vector3) -> bool:
	_resolve()
	if _subject == null or not is_instance_valid(_subject):
		return true
	var here := _origin_of(_subject)
	return Vector2(spot.x - here.x, spot.z - here.z).length() <= claim_radius_m


static func _heading_of(data: Dictionary) -> Vector2:
	var forward = data.get("forward", null)
	if forward is Vector2 and (forward as Vector2).length_squared() > 0.0001:
		return (forward as Vector2).normalized()
	return Vector2.ZERO


# --- throwing it --------------------------------------------------------------

## The burst: the grains that are the shed, and the little mist that goes with
## them.
##
## Emitted one particle at a time, in WORLD space, at a transform this file
## chooses. That is what lets the count be exactly proportional to the shed --
## the thing the whole design rests on -- and it is why the emitters are driven
## by `emit_particle()` rather than by a rate. A rate would put the burst on a
## clock, and the clock is the one thing this effect must not have.
## THE BAND IS AN ARGUMENT, because there are two of them. The waded crust throws
## its shed off the boots and shins -- the band the crust is actually occupying,
## so a deep crossing throws off the whole shin and a nearly-clean leg off the
## boot. The settled load throws off the shoulders and the hood. One burst
## routine, two heights, and the particles land wherever the snow was.
func _throw(spot: Vector3, shed: float, heading: Vector2, low: float, high: float) -> void:
	if _mist == null or _grains == null or shed <= 0.0:
		return
	var thrown := burst_count(grains_per_shed * shed, randf())
	for _index in range(thrown):
		_grains.emit_particle(
			Transform3D(Basis.IDENTITY, _birth_point(spot, low, high)),
			_grain_velocity(heading), Color.WHITE, Color.WHITE, EMIT_PLACED)
	var puffs := burst_count(mist_per_shed * shed, randf())
	for _index in range(puffs):
		_mist.emit_particle(
			Transform3D(Basis.IDENTITY, _birth_point(spot, low, lerpf(low, high, 0.8))),
			_powder_velocity(heading), Color.WHITE, Color.WHITE, EMIT_PLACED)


## Somewhere in the band the snow was sitting on. Spread over the whole band
## rather than emitted from a point, because the snow is not on a point -- it is
## on a leg, or across a pair of shoulders.
func _birth_point(spot: Vector3, low: float, high: float) -> Vector3:
	return spot + Vector3(
		randf_range(-0.055, 0.055),
		randf_range(low, maxf(high, low + 0.04)),
		randf_range(-0.055, 0.055))


## Off the boot, forward and a little up. The leg is swinging when the snow comes
## off it, so the powder goes where the leg was going; the rest is scatter.
func _powder_velocity(heading: Vector2) -> Vector3:
	var throw := Vector3(heading.x, 0.0, heading.y) * randf_range(0.25, 0.7)
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * randf_range(0.2, 0.6)
	var rise := Vector3(0.0, randf_range(0.1, 0.45), 0.0)
	return (throw + scatter + rise) * mist_speed


## THROWN, not released. A grain leaves the boot with the speed the impact gave
## it, over a wide cone about the way he is walking, and then does what its mass
## says: it falls, and it lands.
##
## The cone is the part that reads. A narrow one is a jet and a zero-width one is
## a line of dots; `grain_spread_degrees` either side of the heading is a boot
## breaking a crust rather than aiming it. The vertical component is small and
## can go either way -- some of it is flicked up off the toe and the rest is
## simply shaken off the side -- because a spray that all rises reads as a puff
## and one that all drops reads as a leak.
func _grain_velocity(heading: Vector2) -> Vector3:
	var forward := heading if heading.length_squared() > 0.0001 else Vector2.RIGHT
	var fan := deg_to_rad(grain_spread_degrees)
	var aimed := forward.rotated(randf_range(-fan, fan))
	# Square-rooted so the speeds bunch toward the top of the range rather than
	# spreading evenly: most of what a footfall throws is thrown hard, and the
	# slow tail is the few crumbs that merely fall off.
	var speed := grain_speed * sqrt(randf_range(0.18, 1.0))
	# Mostly up, and never far down. It has to clear the snow surface -- which is
	# drawn ABOVE the body's own origin -- or the arc ends before it has begun.
	var rise := randf_range(0.05, 0.75)
	return Vector3(aimed.x, rise, aimed.y) * speed


## Where the crust reaches on this subject RIGHT NOW, in world metres. The shed
## comes off the band the crust is actually occupying, so a deep crossing throws
## it off the whole shin and a nearly-clean leg throws it off the boot -- the
## particles and the crust are one statement, not two.
func _leg_top_m() -> float:
	return _subject_height() * crust_top_fraction()


## How tall the walker says he is, in metres. Published by PlayerController as
## `body_height`; the fallback is for a subject that publishes nothing, and for a
## test with no body at all.
func _subject_height() -> float:
	if _subject != null and is_instance_valid(_subject):
		var published = _subject.get("body_height")
		if published != null:
			return float(published)
	return subject_height


## Keeps the emitters' culling boxes over the walker.
##
## A GPUParticles3D is culled by `visibility_aabb` around its own node, and these
## particles are in WORLD space -- so without this the whole shed would be culled
## out of existence the moment the walker got 4 m from wherever this node started.
## Moving the node does not drag the particles: that is the point of world space,
## and it is the same arrangement Snowfall uses to place its layers.
##
## As a child of the walker the parent already carries the box between footfalls;
## this re-anchors it on the FOOT rather than the body's centre, and keeps an
## instance that was parented somewhere else working.
func _place(spot: Vector3) -> void:
	# global_position asserts is_inside_tree() and prints an engine ERROR when it
	# fails, which the suite's pristine-output rule turns into a failure a long way
	# from its cause. Out of a tree there is no camera to cull against anyway.
	if is_inside_tree():
		global_position = spot
	else:
		position = spot


# --- the crust ----------------------------------------------------------------

func _process(delta: float) -> void:
	_resolve()
	# After _resolve(), so the subject is known before any building is asked whose
	# occupant it holds. Once, and only ever from inside a tree.
	_ask_what_is_already_true()
	if _subject != null and is_instance_valid(_subject):
		_dress(_subject)
	_advance_settled(delta)
	# After the clocked half and before the uniforms, so a load that melted or was
	# stripped away this frame re-rolls in the same frame the crust is written --
	# a footfall is not the only way a wearer gets clean.
	_watch_for_a_clean_slate()
	_charge_for_the_load()
	var feet := 0.0
	if _subject != null and is_instance_valid(_subject):
		feet = _origin_of(_subject).y
	var fill: Color = ambient_fill()
	var line := wade_fraction()
	for crust in _crusts:
		crust.set_shader_parameter(&"load", _load)
		# What fell ON him, which the shader puts on whatever faces the sky. The
		# waded load beside it is a band; this one has no height at all.
		crust.set_shader_parameter(&"settle", _settle)
		# THE DEPTH HE WALKED THROUGH, and the one number that makes this effect
		# say anything. Written every frame beside the load because the pair is
		# what the shader mixes: the line is where the crust reaches when he is
		# fully loaded, and the load is how far back down toward the boot it has
		# retreated since.
		crust.set_shader_parameter(&"wade_line", line)
		# Every frame, not once: his feet move, and a crust anchored to a stale
		# height would ride up his legs the moment he walked downhill.
		crust.set_shader_parameter(&"origin_y", feet)
		crust.set_shader_parameter(&"fill", Vector3(fill.r, fill.g, fill.b))


## The half of the model that IS about the passage of time, and the only half.
##
## The waded crust is untouched by anything here -- it changes on a footfall and
## on nothing else, which is the claim `tests/unit/test_snow_load.gd` opens with.
## What is on a clock is the sky depositing snow at a rate, the wind stripping it
## off again, and warmth melting it, all three of which are genuinely rates.
##
## The one exception is warmth, which takes BOTH: a man who walks into a warm
## room does not keep the crust on his boots either, and that is the behaviour the
## owner asked for by name.
func _advance_settled(delta: float) -> void:
	if not _sky_overridden and _snowfall != null and is_instance_valid(_snowfall) \
			and _snowfall.has_method("snowfall_rate"):
		_snowfall_rate = clampf(float(_snowfall.snowfall_rate()), 0.0, 1.0)
	if is_thawing():
		_settle = decayed_after(_settle, melt_per_second, delta)
		_load = decayed_after(_load, melt_per_second, delta)
		if _load < shed_floor:
			_wade_line_m = 0.0
		return
	_settle = settled_after(_settle, _snowfall_rate, settle_per_second, delta)
	# Loose snow does not stay on a shoulder in a gale. The waded crust is packed
	# and gets none of this.
	_settle = decayed_after(_settle, settle_wind_strip * _wind.length(), delta)


## What the load costs him, pushed at the body's own reserves.
##
## REMOVE THEN PUSH, which SurvivalSystem's own header calls mandatory: a second
## push without the remove leaves two MULTIPLYs on one stack, and a load that
## ticked up a hundred times would end up multiplying by the hundredth power.
## `chill_step` is what keeps that pair off the per-frame path.
##
## At a clean body the source is removed outright rather than pushed at 1.0. A
## modifier that does nothing is still a modifier: it shows up in
## `modifier_count()`, it survives a reload, and "there is no snow on him" should
## look like nothing rather than like a multiplication by one.
func _charge_for_the_load() -> void:
	if _survival == null or not is_instance_valid(_survival):
		return
	# CLEAN IS ITS OWN STATE, and `shed_floor` is what says so -- the same number
	# that already means "there is nothing left worth throwing off a boot". Both
	# rules here decay exponentially and neither ever reaches zero, so without a
	# floor the source would never be taken off: the charge would fall to a
	# thousandth of a per cent and sit there for the rest of the run.
	var clean := total_load() < shed_floor
	if clean and _chill_pushed <= 1.0 + 0.0001:
		return
	var wanted := 1.0 if clean else chill_multiplier(total_load(), chill_at_full_load)
	if not clean and absf(wanted - _chill_pushed) < chill_step:
		return
	_survival.remove_source(CHILL_SOURCE)
	_chill_pushed = 1.0
	if clean:
		return
	if _survival.push_modifier(CHILL_TARGET, CHILL_SOURCE, Modifier.Operation.MULTIPLY, wanted):
		_chill_pushed = wanted


## One property write per mesh, and nothing about the character's own material
## changes.
##
## `material_overlay` rather than `material_override` or `next_pass`, and the
## choice is forced twice over: the override is where PlayerController mounts the
## four Meshy maps, and `next_pass` is where `STENCIL_MODE_XRAY` builds the ghost
## that lets the figure read through the farmhouse. Overlay is the third slot and
## nothing else is using it.
##
## An overlay that is already occupied is left alone. A silent fight over one
## property between two systems is the defect this project has already paid for
## once, with `transparency`.
func _dress(subject: Node3D) -> void:
	if not _dressed.is_empty():
		return
	var meshes: Array[MeshInstance3D] = []
	_meshes_of(subject, meshes)
	for mesh in meshes:
		if mesh.mesh == null or mesh.material_overlay != null:
			continue
		var crust := crust_material()
		crust.set_shader_parameter(&"figure_height", _subject_height())
		# THE CREASES THE SNOW CATCHES IN, taken off whatever the mesh is already
		# wearing. Snow does not lie evenly on cloth: it collects on the upward
		# side of every fold and seam, and the figure's own normal map already has
		# every one of those in it, in the same UVs this shader is reading.
		var creases := _crease_map_of(mesh)
		if creases != null:
			crust.set_shader_parameter(&"crease_map", creases)
		mesh.material_overlay = crust
		_dressed.append(mesh)
		_crusts.append(crust)


## The normal map already on a mesh, or null.
##
## Read off the material the mesh is wearing rather than loaded from a path, so
## this file still names no character and no texture: the wanderer's four Meshy
## maps arrive because PlayerController put them there, a bear's arrive because
## whoever built the bear put those there, and a subject with no normal map gets
## plain unbiased noise rather than an error.
static func _crease_map_of(mesh: MeshInstance3D) -> Texture2D:
	var worn: Material = mesh.material_override
	if worn == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		worn = mesh.get_active_material(0)
	var pbr := worn as BaseMaterial3D
	if pbr == null or not pbr.normal_enabled:
		return null
	return pbr.normal_texture


## The Environment's ambient fill, in linear light.
##
## READ OFF THE LIVE ENVIRONMENT, never restated. The crust's shader declares
## `ambient_light_disabled` because `tests/art/test_character_lighting.gd`
## requires it of every shader in the project -- a rule about WORLD shaders, whose
## whole purpose is to keep the Environment's fill a CHARACTER control. This is
## the first shader that lives on the character, so it is the first place the rule
## takes light away from the one surface the fill was authored for.
##
## The coat beside it is a stock StandardMaterial3D and has always received
## ambient natively; nothing is mis-wired. So the fill is read here and handed to
## the shader, which adds it back as emission on that one material. Measured
## three ways -- see the shader's own note and the `ambient-*` frames beside the
## task report -- the result is identical to letting Godot apply ambient itself.
##
## Read every frame rather than copied because the six lighting presets each
## carry their own ambient, and a copy would be right for one of them.
##
## Returns black when there is no ambient to have, which is the right answer
## rather than a guard: the crust is then lit by the sun and the key alone, which
## is exactly what the coat under it gets in that case too.
func ambient_fill() -> Color:
	var env := _environment()
	if env == null or env.ambient_light_source != Environment.AMBIENT_SOURCE_COLOR:
		return Color(0.0, 0.0, 0.0)
	var linear := env.ambient_light_color.srgb_to_linear()
	var energy := env.ambient_light_energy
	return Color(linear.r * energy, linear.g * energy, linear.b * energy)


func _environment() -> Environment:
	if not is_inside_tree():
		return null
	var viewport := get_viewport()
	if viewport == null:
		return null
	var camera := viewport.get_camera_3d()
	if camera != null and camera.environment != null:
		return camera.environment
	var world := viewport.find_world_3d()
	return null if world == null else world.environment


func _undress() -> void:
	for index in range(_dressed.size()):
		var mesh := _dressed[index]
		if is_instance_valid(mesh) and mesh.material_overlay == _crusts[index]:
			mesh.material_overlay = null
	_dressed.clear()
	_crusts.clear()


## A crust material carrying everything that does not depend on the mesh it
## lands on. Public so a test can read what it was given without building a body.
##
## One per surface rather than one shared, because `foot_y` and `figure_height`
## are facts about a particular mesh -- a subject drawn as two meshes at two
## scales would otherwise get one of them masked against the other's box.
func crust_material() -> ShaderMaterial:
	var crust := ShaderMaterial.new()
	crust.shader = load(CRUST_SHADER_PATH)
	crust.set_shader_parameter(&"snow_color", snow_tone(crust_value))
	crust.set_shader_parameter(&"boot_line", boot_line)
	crust.set_shader_parameter(&"wade_line", wade_fraction())
	crust.set_shader_parameter(&"max_opacity", crust_opacity)
	crust.set_shader_parameter(&"crust_coverage", crust_coverage)
	crust.set_shader_parameter(&"patch_scale", patch_scale)
	crust.set_shader_parameter(&"patch_contrast", patch_contrast)
	crust.set_shader_parameter(&"patch_warp", patch_warp)
	# WHOSE PATTERN THIS IS. Written here, at build, and never in `_process()` --
	# see `_noise_offset` for why the once matters as much as the randomness.
	crust.set_shader_parameter(&"noise_offset", _noise_offset)
	crust.set_shader_parameter(&"patch_scatter", patch_scatter)
	crust.set_shader_parameter(&"settle_coverage", settle_coverage)
	crust.set_shader_parameter(&"settle_facing", settle_facing)
	crust.set_shader_parameter(&"settle_falloff", settle_falloff)
	crust.set_shader_parameter(&"crease_bias", crease_bias)
	crust.set_shader_parameter(&"load", _load)
	crust.set_shader_parameter(&"settle", _settle)
	return crust


## The colour the whole shed is drawn in, at a given value.
##
## NEARLY WHITE, AND NOT A LITERAL. The hue comes off
## `data/palette/color_bible.tres` and is taken almost all the way to white by
## `shed_whiteness` -- see that export for why nearly-white is the correct
## reading of the palette here rather than a departure from it. The value is then
## how bright this particular surface may be drawn, which is a separate question
## with a separate answer per surface.
##
## Multiplied in sRGB rather than in linear, because that is the space these
## values are authored and read back in: every number in this file that a person
## tunes is an sRGB one, and a knob that behaves differently from the colour
## picker it is compared against is a knob nobody can set.
func snow_tone(value: float) -> Color:
	var white := _near_white()
	var v := clampf(value, 0.0, 1.0)
	return Color(white.r * v, white.g * v, white.b * v)


func _near_white() -> Color:
	var bible = load(PALETTE_PATH)
	if bible == null:
		return Color(0.95, 0.96, 0.98)
	var snow: Color = bible.snow_tones[0]
	return snow.lerp(Color.WHITE, clampf(shed_whiteness, 0.0, 1.0))


# --- the emitters -------------------------------------------------------------

func _build() -> void:
	# The grains first, and with the bigger buffer: they are the majority of every
	# burst, and a buffer too small does not warn -- it silently drops the tail of
	# the biggest shed in the run, which is the one stride anybody would look at.
	_grains = _build_population(
		"Grains", 128, grain_life, grain_damping, grain_size_m, grain_size_spread,
		null, _grain_ramp(), _grain_texture(), snow_tone(grain_value), 1.0)
	_grain_material = _grains.process_material as ParticleProcessMaterial
	_mist = _build_population(
		"Mist", 32, mist_life, mist_damping, mist_radius_birth, 0.3,
		_swell_curve(mist_radius_death / maxf(mist_radius_birth, 0.0001)),
		_powder_ramp(), _powder_texture(), snow_tone(mist_value), mist_alpha)
	_mist_material = _mist.process_material as ParticleProcessMaterial
	_apply_wind()


func _build_population(
		name_of: String, buffer: int, life: float, damping: float, radius: float,
		size_spread: float, swell: CurveTexture, ramp: GradientTexture1D,
		dot: GradientTexture2D, tone: Color, alpha: float) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = name_of
	# THE WHOLE EFFECT, and the one line here that cannot go wrong quietly. A puff
	# knocked off a boot stays where it was knocked off; the walker keeps going and
	# leaves it behind him. In local space every puff would drag along with the leg
	# and the shed would read as a permanent smear on his shins.
	emitter.local_coords = false
	emitter.amount = buffer
	emitter.lifetime = life
	emitter.one_shot = false
	emitter.explosiveness = 0.0
	# NOT EMITTING, AND THAT IS WHAT MAKES THE MANUAL EMISSION WORK. Every
	# particle here arrives by `emit_particle()`, on a footfall.
	#
	# MEASURED ON 4.7.1, because the plausible arrangement is the broken one. The
	# obvious way to stop an emitter producing a rate of its own while still
	# accepting manual particles is `emitting = true` with `amount_ratio = 0`, on
	# the reasoning that a system has to be running to simulate anything. It is
	# silent and it emits NOTHING: three emitters side by side under one camera,
	# configured true/0, false/1 and true/1, produced no particles, particles, and
	# particles. `emitting = false` is processed on demand, and a burst still
	# appears on an emitter whose previous particles all died a second earlier --
	# which is the case that actually matters here, since a walk on clear ground
	# sheds nothing for minutes at a time.
	emitter.emitting = false
	# Rule 10 makes the long shadows the subject of the frame, cast at 8192 across
	# four splits. A hundred crumbs of snow do not belong in that map.
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Around the walker, who this node follows. Generous enough to cover where the
	# mist drifts to over its life and where a grain lands.
	emitter.visibility_aabb = AABB(Vector3(-3.0, -1.5, -3.0), Vector3(6.0, 4.5, 6.0))

	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	motion.damping_min = damping * 0.8
	motion.damping_max = damping * 1.2
	motion.scale_min = radius * (1.0 - size_spread)
	motion.scale_max = radius * (1.0 + size_spread)
	motion.color_ramp = ramp
	if swell != null:
		motion.scale_curve = swell
	emitter.process_material = motion

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _surface(tone, alpha, dot)
	emitter.draw_pass_1 = quad
	add_child(emitter)
	return emitter


## Cool, unshaded, alpha-blended and mixed rather than added.
##
## Unshaded is Art Bible rule 8's banned list in one property -- there is no
## specular, no roughness and no reflection to switch off -- and MIX rather than
## ADD is rule 12 again: additive blending is a glow by another name, and two
## puffs crossing would be brighter than either. `tests/unit/test_snow_load.gd`
## holds the peak under the environment's bloom threshold.
func _surface(tone: Color, alpha: float, dot: GradientTexture2D) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color(tone.r, tone.g, tone.b, alpha)
	surface.albedo_texture = dot
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	surface.billboard_keep_scale = true
	surface.disable_receive_shadows = true
	return surface


## A smooth bell, centre to rim, for the mist -- and the only soft edge here.
##
## The same shape and the same reasoning as `BreathFog._puff_texture()`, and
## deliberately not a different one: a disc has a shoulder in it, and where two
## discs overlap the eye finds both outlines and reads two circles. A bell has no
## shoulder anywhere, so the composited alpha rises smoothly through the join and
## a shed reads as one drifting mass rather than as a handful of dots.
func _powder_texture() -> GradientTexture2D:
	return _radial(
		PackedFloat32Array([0.0, 0.24, 0.48, 0.7, 1.0]),
		PackedFloat32Array([1.0, 0.9, 0.62, 0.28, 0.0]))


## A GRAIN HAS AN EDGE ON IT, and that edge is most of why it reads as grit.
##
## A small blob with a soft falloff is fog whatever size it is drawn at -- the
## eye reads the gradient, not the dot. So this is flat to nine tenths of the
## radius and then gone, which at 4 px across leaves a hard-edged fleck with one
## texel of anti-aliasing round it rather than a smudge. The bell above is the
## opposite shape for the opposite reason, and the two textures are the whole
## visual difference between the populations once the physics has separated them.
func _grain_texture() -> GradientTexture2D:
	return _radial(
		PackedFloat32Array([0.0, 0.88, 0.97, 1.0]),
		PackedFloat32Array([1.0, 1.0, 0.0, 0.0]))


func _radial(offsets: PackedFloat32Array, alphas: PackedFloat32Array) -> GradientTexture2D:
	var gradient := Gradient.new()
	var colors := PackedColorArray()
	for alpha in alphas:
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 48
	texture.height = 48
	return texture


## Alpha over a puff's life. It emerges and it disperses; neither end is a cliff.
## The long convex tail is what stops the mist having a frame in which it
## visibly stopped existing.
func _powder_ramp() -> GradientTexture1D:
	return _ramp(
		PackedFloat32Array([0.0, 0.08, 0.3, 0.62, 0.85, 1.0]),
		PackedFloat32Array([0.0, 1.0, 0.86, 0.46, 0.15, 0.0]))


## A grain is opaque for the whole of its life. It does not disperse -- it lands
## -- so there is no fade at all until the last tenth, and that last tenth is
## only there so it does not blink out in mid-air.
func _grain_ramp() -> GradientTexture1D:
	return _ramp(
		PackedFloat32Array([0.0, 0.85, 1.0]),
		PackedFloat32Array([1.0, 1.0, 0.0]))


func _ramp(offsets: PackedFloat32Array, alphas: PackedFloat32Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	var colors := PackedColorArray()
	for alpha in alphas:
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Radius over life, as a multiple of the size the puff was born at. Up quickly
## out of the boot, then it KEEPS OPENING while the ramp above thins it -- which
## is what dispersal looks like. A curve that came back down would make the
## oldest puff the smallest and the shed would read as sparks going out.
func _swell_curve(growth: float) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = maxf(growth, 1.0)
	curve.add_point(Vector2(0.0, 0.45))
	curve.add_point(Vector2(0.18, 1.0))
	curve.add_point(Vector2(0.6, growth * 0.62))
	curve.add_point(Vector2(1.0, growth))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## Gravity is where a ParticleProcessMaterial keeps every constant acceleration,
## so what is left of a grain's weight and whatever the wind system is blowing
## arrive in the same slot. The drift is the still-air part and the wind adds to
## it; each population takes the share of the wind its own drag earns it.
func _apply_wind() -> void:
	if _mist_material != null:
		_mist_material.gravity = Vector3(mist_drift.x, -mist_fall, mist_drift.z) \
			+ _wind * wind_response(mist_damping)
	if _grain_material != null:
		_grain_material.gravity = Vector3(0.0, -grain_fall, 0.0) \
			+ _wind * wind_response(grain_damping)


# --- resolution ---------------------------------------------------------------

## The subject is found by looking UP and the snow field by looking sideways, and
## the difference is the whole of item 3: a walker is a PLACE IN THE TREE -- this
## node is part of him -- while the snow field is a service the world publishes
## and every walker in it shares.
##
## Looking up rather than at an exported path also means a second walker needs no
## configuration at all: drop the scene under the bear and it dresses the bear.
##
## get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is a
## node under /root and never enters the engine's singleton registry (briefing
## trap 3).
func _resolve() -> void:
	if _subject == null or not is_instance_valid(_subject):
		_subject = _walker_above()
	if not is_inside_tree():
		return
	if _registry == null:
		_registry = get_node_or_null("/root/ServiceRegistry")
	if _registry != null:
		if _snow == null:
			_snow = _registry.get_service(&"snow_field") as Node
		# The sky, pulled rather than pushed -- the same arrangement
		# SnowAccumulation uses on the same service, and for the same reason: the
		# rate is a fact about the world that several systems read, not a message
		# anybody sends. `set_snowfall_rate()` overrides it for one walker.
		if _snowfall == null:
			_snowfall = _registry.get_service(SNOWFALL_SERVICE) as Node
	if _survival == null:
		_survival = get_node_or_null(SURVIVAL_PATH)


## The body this node is a part of: its nearest Node3D ancestor.
##
## Null is a legal answer and means "nobody" rather than "error" -- a test builds
## this with `.new()` and never parents it, and `claim_radius_m` documents what
## an unparented instance then does.
func _walker_above() -> Node3D:
	var above := get_parent()
	while above != null:
		if above is Node3D:
			return above as Node3D
		above = above.get_parent()
	return null


static func _meshes_of(node: Node, found: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		_meshes_of(child, found)
