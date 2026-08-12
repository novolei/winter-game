extends Node3D

## A CHILD OF A WALKER. Snow packs onto his boots and shins in a drift, and he
## knocks it off again, step by step, until his legs are clean.
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
## `assets/shaders/leg_snow.gdshader` holds it, and it rides
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
const CRUST_SHADER_PATH := "res://assets/shaders/leg_snow.gdshader"
const FOOTPRINT_EVENT := &"player.footprint"

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

## How big the patches are, as a frequency over the character's UVs. Higher is
## finer grit; lower is bigger slabs.
@export var patch_scale := 42.0

## How hard the edges of the patches are against the noise's own distribution. At
## 1 the noise is used raw and the threshold sweeps a soft, gradual field; higher
## stretches it so patches appear and disappear as WHOLE patches, which is the
## breaking-up read the shed is supposed to have.
@export var patch_contrast := 2.1

## How far below the crust's upper line the coverage ramp runs, as a fraction of
## the figure. This is what makes it thick low down and scattered at the top
## rather than a band with an edge: at the sole the coverage is full and every
## patch is present; approaching the line only the luckiest few are.
@export var patch_scatter := 0.16

## How strongly the character's own normal map decides WHERE it catches.
##
## Snow settles on the upward-facing side of every crease and seam, and the
## figure already carries a normal map with all of them in it -- see
## `_crease_map_of()`, which takes it off whatever material is already on the
## mesh rather than naming a file, so a bear with its own map gets its own
## creases and a subject with no map gets plain noise.
@export var crease_bias := 0.42

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
var _subject: Node3D
var _mist: GPUParticles3D
var _grains: GPUParticles3D
var _mist_material: ParticleProcessMaterial
var _grain_material: ParticleProcessMaterial
var _crusts: Array[ShaderMaterial] = []
var _dressed: Array[MeshInstance3D] = []
var _load := 0.0
## How far up his legs the snow reached at the DEEPEST point of this crossing, in
## world metres above his soles. See the header: this is the whole of what the
## crust's upper edge says, and it is remembered until the legs are clean.
var _wade_line_m := 0.0
var _last_shed := 0.0
var _steps_since_drift := 0
var _wind := Vector3.ZERO
var _air_chill := 0.0


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


func _exit_tree() -> void:
	if _bus != null:
		_bus.unsubscribe(FOOTPRINT_EVENT, _on_footprint)
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
func report() -> String:
	return "legsnow[load=%.2f shed=%.2f steps=%d wade=%.0fcm line=%.0fcm]" % [
		_load, _last_shed, _steps_since_drift,
		_wade_line_m * 100.0, crust_top_fraction() * _subject_height() * 100.0,
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
		return
	_throw(spot, shed, heading)


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
	var here := _subject.global_position
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
func _throw(spot: Vector3, shed: float, heading: Vector2) -> void:
	if _mist == null or _grains == null:
		return
	var top := _leg_top_m()
	var thrown := burst_count(grains_per_shed * shed, randf())
	for _index in range(thrown):
		_grains.emit_particle(
			Transform3D(Basis.IDENTITY, _birth_point(spot, top)),
			_grain_velocity(heading), Color.WHITE, Color.WHITE, EMIT_PLACED)
	var puffs := burst_count(mist_per_shed * shed, randf())
	for _index in range(puffs):
		_mist.emit_particle(
			Transform3D(Basis.IDENTITY, _birth_point(spot, top * 0.8)),
			_powder_velocity(heading), Color.WHITE, Color.WHITE, EMIT_PLACED)


## Somewhere on the boot or the shin. Spread over the whole band rather than
## emitted from a point, because the snow is not on a point -- it is on a leg.
func _birth_point(spot: Vector3, top: float) -> Vector3:
	return spot + Vector3(
		randf_range(-0.055, 0.055),
		randf_range(0.06, maxf(top, 0.1)),
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

func _process(_delta: float) -> void:
	_resolve()
	if _subject != null and is_instance_valid(_subject):
		_dress(_subject)
	var feet := 0.0
	if _subject != null and is_instance_valid(_subject):
		feet = _subject.global_position.y
	var fill: Color = ambient_fill()
	var line := wade_fraction()
	for crust in _crusts:
		crust.set_shader_parameter(&"load", _load)
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
	crust.set_shader_parameter(&"patch_scale", patch_scale)
	crust.set_shader_parameter(&"patch_contrast", patch_contrast)
	crust.set_shader_parameter(&"patch_scatter", patch_scatter)
	crust.set_shader_parameter(&"crease_bias", crease_bias)
	crust.set_shader_parameter(&"load", _load)
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
## puffs crossing would be brighter than either. `tests/unit/test_leg_snow.gd`
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
	if _snow != null or not is_inside_tree():
		return
	if _registry == null:
		_registry = get_node_or_null("/root/ServiceRegistry")
	if _registry != null:
		_snow = _registry.get_service(&"snow_field") as Node


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
