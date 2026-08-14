class_name Spindrift
extends GPUParticles3D

## Loose snow streaming along the ground in a gust: low, fast, and gone when the
## gust is.
##
## ---------------------------------------------------------------------------
## WHY THIS ONE AND NOT A STRONGER WIND
## ---------------------------------------------------------------------------
## Every other consumer of the wind in this project makes an existing thing move
## a little differently: the snowfall slants harder, footprints fill in sooner,
## the breath drifts. All of them are true and all of them are SUBTLE, and the
## complaint that opened this task was that the wind does not read at all. Making
## the same subtle things more violent does not fix that -- it just makes the
## snowfall look wrong.
##
## What fixes it is a cue that is NOT THERE and then IS. In a snowfield that is
## spindrift: loose surface snow picked up and carried in a sheet, low and fast,
## for the few seconds a gust lasts. It is the single most readable wind cue on
## flat white ground, it needs no new art -- the same soft dot the snowfall
## already draws -- and its entire value is the ONSET.
##
## Hence `stream_onset`, with a narrow feather below it. Below that feather this
## emits NOTHING; inside it the first powder appears continuously. A spindrift
## that is always on is ground fog, it flattens the picture, and it removes the
## only thing that made it worth building.
##
## ---------------------------------------------------------------------------
## IT IS NOT A SNOWFALL LAYER
## ---------------------------------------------------------------------------
## Deliberately outside `SnowfallLayer.GROUP`. A layer in that group is driven by
## `Snowfall`, which sets its density from the SNOWFALL RATE -- and spindrift on
## a clear, hard, windy day is a real and common thing. Tying it to how hard it
## is snowing would put it on at the wrong times and off at the right ones.
##
## It takes the wind through the same two hooks everything else does, so
## `WindSystem` finds it with no special case.
##
## ---------------------------------------------------------------------------
## WHAT IT MAY NOT DO -- the same list the flakes are held to
## ---------------------------------------------------------------------------
##   * Not warm. Art Bible rule 12 lists where warmth is allowed and blown snow
##     is not on it. The colour is the palette's lightest snow tone taken toward
##     white, read from `data/palette/color_bible.tres`, never written down here.
##   * Not glowing. MIX, not ADD; the peak stays under the environment's glow
##     threshold, exactly as `SnowfallLayer` argues.
##   * Unshaded, so Art Bible rule 8's banned list has nothing to switch off.
##   * No shadows. A thousand streaks in the shadow map for something nobody can
##     see is the same bill the snowfall already refused.

const PALETTE_PATH := "res://data/palette/color_bible.tres"

## The centre of the pickup shoulder. See `stream_onset_softness` below.
##
## 0.28 sits above the valley profile's gust midpoint and below its peak, so
## spindrift happens on the bigger half of ordinary gusts and on every squall --
## often enough to be part of the weather, rare enough to be an event.
@export var stream_onset := 0.28

## The onset is the centre of a soft shoulder, not a guillotine.  The gale
## profile's authored floor is exactly 0.28; without this shoulder every return
## to that floor empties the emitter and the next rise arrives as a packet.
## Strengths below `stream_onset - stream_onset_softness` remain truly silent.
@export_range(0.0, 0.25, 0.005) var stream_onset_softness := 0.10

## How fast the sheet travels, at the onset and at a full gale, in metres per
## second. Fast: the readability of this cue is almost entirely its SPEED against
## the stillness of the ground it crosses.
@export var stream_speed_min := 2.8
@export var stream_speed_max := 7.4

## The emission volume, in world metres, centred on the point the camera is
## looking at. Wide enough to cover the widest framing the rig offers, and THIN:
## this is snow being dragged over a surface, not a blizzard at knee height.
##
## `x` and `z` are the ground the sheet may be born on and are used as one
## quantity -- the pattern below is generated in the WIND's frame and then turned
## into the world, so the square is rotated and only the circle inscribed in it is
## guaranteed covered. At 34 m that circle is 17 m in radius, against a gameplay
## frame that shows about 17 x 15 m of ground.
@export var volume_size := Vector3(34.0, 0.50, 34.0)

## How far above the snow surface the middle of the box sits.
@export var hover_m := 0.22

## The particle buffer, allocated once at the full figure. Density is carried by
## `amount_ratio`, never by `amount` -- writing `amount` re-allocates and every
## streak on screen disappears on that frame, which for an effect whose whole
## point is its onset would be a visible tear every time a gust arrived.
@export var streaks := 2600

## How long a streak lives. Short: it is a thing being flung, not a thing
## falling, and a long life carries it out of the box and lets it read as fog.
@export var life_seconds := 0.72

## The powder shard, in metres. Direction belongs to the SHEET and its lanes;
## locking every individual quad onto velocity duplicates that information as a
## field of parallel tracer rounds. A compact, freely rotating shard lets the
## same wind read as powder breaking up.
@export var streak_width := 0.060
@export var streak_length := 0.12

## Birth timing, speed variation and aerodynamic drag. All three are bounded:
## variation breaks marching rows without letting a flake reverse, while
## frictional drag takes the mechanical constancy out of its flight.
@export_range(0.0, 1.0, 0.01) var birth_randomness := 0.58
@export var speed_ratio_range := Vector2(0.72, 1.0)
@export var drag_range := Vector2(0.25, 0.70)
@export var angular_velocity_range := Vector2(-140.0, 140.0)
@export_range(0.0, 1.0, 0.01) var spin_end_multiplier := 0.08
## Stock turbulence is safe here only because the particle lives 0.72 seconds,
## the influence is very small, and the settling gravity remains dominant. It
## supplies a last irregular flutter rather than becoming the motion model.
@export var turbulence_influence_range := Vector2(0.002, 0.007)
@export_range(0.01, 2.0, 0.01) var turbulence_noise_scale := 0.18
@export_range(0.0, 1.0, 0.01) var turbulence_noise_speed := 0.10

## The cone the snow leaves in.
##
## ---------------------------------------------------------------------------
## THIS IS NOT FREE VARIATION, AND IT WAS FOR AS LONG AS THE SHEET HAD NO SHAPE
## ---------------------------------------------------------------------------
## At 14 degrees this read as pleasant scatter, and it was: the sheet was a
## uniform box of streaks and a wide cone cost nothing, because there was no
## structure for it to erase and no direction it had to state.
##
## Both of those changed. The owner's complaint was 风的方向貌似比较固定 -- and
## the wind's instantaneous heading is NOT fixed, it swings 91 degrees through a
## blizzard. What was fixed was the PICTURE of it: this sheet is the only thing on
## screen that shows a direction, and at 14 degrees its own angle scatter buried
## the signal it was supposed to carry.
##
## The number is a CROSSWIND DISTANCE, not an angle. The rejected 14-degree,
## 11-metre flight wandered 2.7 m sideways and erased its own heading. The
## shipped short flight and three-degree cone remain small beside the soft lane,
## so the field still states one direction.
##
## See `crosswind_spread_m()`, which is where that arithmetic lives, and
## `tests/unit/test_wind.gd`, which holds it against the two lengths it must stay
## under: the streak, and the ribbon spacing the sheet is emitted on.
@export var spread_degrees := 3.0

## How far the palette's lightest snow is taken toward white, and the most alpha
## a streak ever has.
##
## Slightly whiter than the falling flake and substantially more translucent,
## measured from the full-gale frame rather than reasoned. A shard is seen against SNOW,
## where the flake is mostly seen against sky and against the dark solids -- so at
## the flake's whiteness this cue was pale-blue-on-pale-blue and, at a strength of
## 0.7, invisible in the capture while every number said it was running. The alpha
## comes back down because there are three times as many streaks as there are
## flakes in a layer, and at the flake's opacity the sheet became a white bar
## across the bottom of the picture.
##
## Still far under the bloom threshold; the test below computes the exact value.
## `test_wind.gd` pins that, the same way `test_snowfall.gd` pins the flake.
@export var streak_whiteness := 0.70
@export var streak_alpha := 0.34

## Where the ground is taken to be when nothing can be asked. Snowfall's own
## figure, for the same reason: it is the height the camera's view axis is taken
## to meet the world at.
@export var ground_height := 1.0

# --- the ribbons -------------------------------------------------------------
#
# WHY THE SHEET IS NOT A BOX ANY MORE, AND THE MEASUREMENT THAT SETTLED IT
#
# A uniform scatter of streaks is not a stylisation of blowing snow. It is a
# DIFFERENT PHENOMENON: it is fog. Field work on real blowing snow resolves the
# ground sheet into meandering, bifurcating peak-flux ribbons -- "snow snakes" --
# about 0.3 m wide and about 5 m apart, and the simulation literature states the
# failure mode directly: without turbulence the particles distribute uniformly;
# with it they organise into patchy clusters.
#
# This sheet measured as the uniform case. Ink counted per 128 px cell and
# corrected for mean streak area gave a dispersion index of 1.12, where 1.0 is a
# Poisson scatter and real structure sits well above 1.5. That is the whole of
# why an effect filling 92.5% of the frame did not read as the ground doing
# something -- there was nothing in it for the eye to follow.
#
# So emission moves from a box to a POINT CLOUD baked into lanes. No shader: the
# points are a 4096-pixel Image built on the CPU, and the only per-frame cost is
# rebuilding it a few times a second so the pattern lives.

## How far apart the ribbons run, and how wide each diffuse coverage band is, in
## world metres.  The old 0.30 m uniform strip made every lane a hard isolated
## packet.  This wider support is distributed with a dense powder core and sparse
## edges by `soft_lane_offset()` below.
@export var ribbon_spacing_m := 5.0
@export var ribbon_width_m := 1.30

## Exponent applied to a uniform cross-lane sample.  One is a hard uniform band;
## values above one progressively feather the edges while remaining bounded by
## `ribbon_width_m`, so diffuse never becomes an unbounded fog fill.
@export_range(1.0, 3.0, 0.05) var ribbon_edge_falloff := 1.8

## Most lifted grains form a thin continuous bed; the remainder reinforce the
## authored soft ribbons. Without this bed, even a feathered lane is followed by
## several metres of literal zero and the full-gale frame separates into clumps.
## It is still not fog: the bed exists only above the wind pickup shoulder, lasts
## less than a second, and is carried flat across the surface.
@export_range(0.0, 1.0, 0.01) var diffuse_share := 0.72

## How far a ribbon wanders across the wind over its length, in metres, and over
## what distance along the wind it does it. A ribbon that ran straight would be a
## painted stripe; the meander is what makes it a snake.
##
## ---------------------------------------------------------------------------
## AND IT IS BOUNDED BY THE SAME BUDGET THE CONE IS -- MEASURED, NOT REASONED
## ---------------------------------------------------------------------------
## A STREAK FLIES STRAIGHT. It is born on the ribbon and then holds the line it
## was given, so the meander is not decoration on the lane, it is a SMEAR of it.
##
## The first broadening attempt widened only the meander and closed the lanes up.
## This version spends the budget on soft COVERAGE instead: about 0.28 m of cone,
## 0.60 m of meander swing and a 1.30 m feathered band total about 2.18 m, still
## under half the five-metre spacing.  The lanes breathe without reading as
## isolated thirty-centimetre strips or dissolving into uniform fog.
##
## `crosswind_smear_m()` is that arithmetic, and `tests/unit/test_wind.gd` holds
## it against the spacing so the next person to reach for a livelier meander is
## told what it costs before the frame is rendered.
@export var ribbon_meander_m := 0.30
@export var ribbon_meander_period_m := 11.0

## How fast the whole pattern slides across the wind, in metres per second.
##
## NOT DECORATION -- IT IS WHAT STOPS THE PATTERN BEING WALLPAPER. The emitter
## follows the camera and the lanes are laid out in the wind's own frame, so with
## nothing moving them a standing player under a steady wind would see the same
## stripes in the same places for as long as he stood there. Real snow snakes
## advance and wander. Slow on purpose: this is the field breathing, not a
## scrolling texture.
@export var ribbon_drift_mps := 0.28

## How fast the meander phase travels ALONG the ribbon, in metres per second.
## This is deliberately much slower than the lifted grains: the broad pattern
## breathes while each short shard crosses it, without a rebake visibly relocating
## a powder band.
@export var ribbon_advance_mps := 0.65

## How many points the cloud holds, and how often it is rebuilt.
##
## A REBAKE IS SEAMLESS AND THAT IS NOT LUCK. `emission_point_texture` is read
## only when a particle is BORN, so replacing it moves nothing already in flight;
## and because the pattern is a continuous function of time sampled at fixed
## per-point offsets, two consecutive bakes differ principally by
## `ribbon_drift_mps * rebake_seconds` -- 7 cm at the shipped figures, half a
## short shard. See
## `tests/unit/test_wind.gd`, which asserts exactly that rather than trusting it.
@export var ribbon_points := 4096
@export var rebake_seconds := 0.25

# --- the pulse ---------------------------------------------------------------

## The periods the whole field pulses on, in seconds, and how deeply.
##
## Measured in the field as a dominant frequency below 0.1 Hz with periodic peaks
## around 10, 35, 70 and 90 seconds. Three of them, incommensurate, so the sheet
## surges and eases without ever repeating inside a session -- the same argument
## `WindSystem.gust_field()` makes for its three octaves.
##
## This is NOT the gust. The gust is already carried by `stream_ratio()`, arrives
## from the wind system, and is what decides whether the sheet exists at all. This
## is the structure INSIDE a running sheet, and it is why a sustained gale does
## not draw a constant wash.
@export var pulse_seconds := Vector3(10.3, 35.7, 89.0)
@export var pulse_depth := 0.45

var _wind := Vector3.ZERO
var _strength := 0.0
var _process_material: ParticleProcessMaterial
var _snow_field = null

## The point cloud, and the fixed per-point offsets the bake shapes. Drawn ONCE
## from a seeded stream rather than per bake: re-drawing them would make every
## rebake a new pattern instead of the same pattern a moment later, which is the
## difference between a field that lives and one that flickers.
var _points_image: Image = null
var _points_texture: ImageTexture = null
var _along: PackedFloat32Array = PackedFloat32Array()
var _across: PackedFloat32Array = PackedFloat32Array()
var _diffuse_across: PackedFloat32Array = PackedFloat32Array()
var _distribution: PackedFloat32Array = PackedFloat32Array()
var _lift: PackedFloat32Array = PackedFloat32Array()
var _lane: PackedInt32Array = PackedInt32Array()
var _since_bake := 0.0
var _baked_at := -1.0
var _clock := 0.0
var _was_streaming := false
var _bake_count := 0


func _ready() -> void:
	_build()
	_apply()


## THE WIND HOOKS. Only the DIRECTION of the vector is taken -- the speed of
## blown surface snow is not the acceleration a falling flake feels, and pinning
## the two together would mean retuning the snowfall to retune this.
func set_wind(velocity: Vector3) -> void:
	_wind = velocity


func set_wind_strength(strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)


func wind_strength() -> float:
	return _strength


## How much of the sheet is running, 0 .. 1. Zero below the onset shoulder, and
## smoothly increasing through it so a gale cannot chatter on its own floor.
static func stream_ratio(strength: float, onset: float, softness: float = 0.0) -> float:
	var held := clampf(strength, 0.0, 1.0)
	var start := maxf(clampf(onset, 0.0, 1.0) - maxf(softness, 0.0), 0.0)
	if held <= start:
		return 0.0
	var span := 1.0 - start
	if span <= 0.0:
		return 1.0
	# Raised to 1.5, so the sheet builds through a gust rather than arriving
	# whole. A linear ramp from the onset reads as a switch, because the onset is
	# already a switch and two of them land together -- and the square this was
	# written as first was the other error: it put only a third of the sheet on at
	# a strength of 0.7, which is most of a gale, and the cue did not read.
	var t := (held - start) / span
	return clampf(pow(t, 1.5), 0.0, 1.0)


## Maps a uniform -1..1 sample into a broad lane with a dense centre and sparse
## shoulders.  Unlike clipping or a second hard strip, the transform is smooth,
## symmetric and strictly bounded by half the authored coverage width.
static func soft_lane_offset(sample: float, width: float, falloff: float) -> float:
	var held := clampf(sample, -1.0, 1.0)
	return signf(held) * pow(absf(held), maxf(falloff, 1.0)) * maxf(width, 0.0) * 0.5


## Where one ribbon's middle sits ACROSS the wind, at a point `along` it, at time
## `at`. Pure and static, so the whole shape of the field is checkable with no
## node, no texture and no rendered frame.
##
## Three things are happening and they are deliberately separate:
##
##   * the lane's own offset, so the ribbons are `spacing` apart;
##   * a crosswind SLIDE of the whole field, which is what stops a standing
##     player seeing the same stripes in the same places;
##   * a MEANDER whose argument advances along the wind with time, so the shape
##     travels down the ribbon rather than the ribbon translating rigidly.
##
## Two meander components at an irrational ratio, phased per lane. One eddy
## crossing seven lanes in step is a corrugation; snow snakes bifurcate and
## wander independently, and the per-lane phase is the whole of that.
static func ribbon_centre(
	lane: int, lanes: int, spacing: float, along: float, at: float,
	meander: float, period: float, drift: float, advance: float
) -> float:
	var base := (float(lane) - float(maxi(lanes, 1) - 1) * 0.5) * spacing + drift * at
	if period <= 0.0 or meander == 0.0:
		return base
	var w := TAU / period
	var travelled := along - advance * at
	var phase := float(lane) * 2.399963
	return base + meander * (
		0.62 * sin(w * travelled + phase)
		+ 0.38 * sin(w * 2.37 * travelled + phase * 1.7 + 1.1)
	)


## The whole field's slow surge, between `1 - depth` and 1.
##
## Bounded ABOVE at 1 rather than centred on it, because this multiplies
## `amount_ratio`, which the engine clamps at 1: an envelope that overshot would
## flat-top at every peak and read as a mechanism. So the pulse is a series of
## EASINGS-OFF from full, which is also the honest shape -- blowing snow surges
## and then runs out of loose material.
static func pulse_at(t: float, periods: Vector3, depth: float) -> float:
	var shaped := 0.0
	var weight := 0.0
	var octaves := [
		[periods.x, 0.42, 0.0], [periods.y, 0.35, 1.7], [periods.z, 0.23, 4.1]
	]
	for octave in octaves:
		var period: float = octave[0]
		if period <= 0.0:
			continue
		var w: float = octave[1]
		shaped += w * (0.5 + 0.5 * sin(TAU * t / period + float(octave[2])))
		weight += w
	if weight <= 0.0:
		return 1.0
	return 1.0 - clampf(depth, 0.0, 1.0) * (1.0 - clampf(shaped / weight, 0.0, 1.0))


## How many ribbons fit across the volume.
func lane_count() -> int:
	if ribbon_spacing_m <= 0.0:
		return 1
	return maxi(1, int(round(volume_size.x / ribbon_spacing_m)))


## How far off the heading the emission cone can carry a streak over its whole
## life, in world metres, at the speed a full gale gives it.
##
## THE NUMBER THAT DECIDES WHETHER THE SHEET CAN SAY ANYTHING. It is the scale at
## which this effect blurs, and everything spatial about the sheet has to be
## larger than it or it is gone within one lifetime. That is a RELATIONSHIP
## between `spread_degrees`, `stream_speed_max` and `life_seconds`, so changing
## any one of the three moves it -- which is why it is computed rather than
## written down, and why the test asserts it against the two lengths it has to
## stay under rather than against a number somebody typed.
func crosswind_spread_m() -> float:
	return stream_speed_max * life_seconds * tan(deg_to_rad(maxf(spread_degrees, 0.0)))


## How far across the wind the ribbon's own wander carries the band it paints.
##
## Not `2 * ribbon_meander_m`, because a streak only samples the ribbon over the
## `stream_speed_max * life_seconds` it flies -- so a meander whose period is far
## LONGER than that flight is seen as a straight lane leaning slightly, and costs
## nothing. The swing is the full 2A only once the flight covers half a period.
func meander_swing_m() -> float:
	var flight := stream_speed_max * life_seconds
	var period := maxf(ribbon_meander_period_m, 0.001)
	return 2.0 * absf(ribbon_meander_m) * sin(minf(PI * flight / period, PI * 0.5))


## EVERYTHING THAT WIDENS A LANE, added up, in world metres.
##
## The one number that decides whether this sheet has structure or is a wash. It
## has to stay well under `ribbon_spacing_m` or the lanes close up, and the way it
## fails is silent: every parameter still reads correct, the emitter still emits
## ribbons, and the picture is a uniform scatter. That is exactly how the first
## version of both this and the cone shipped.
func crosswind_smear_m() -> float:
	return crosswind_spread_m() + meander_swing_m() + ribbon_width_m


## The direction and speed the sheet travels, in world metres per second. Flat by
## construction: snow dragged over a surface goes across it.
func stream_velocity() -> Vector3:
	var flat := Vector3(_wind.x, 0.0, _wind.z)
	if flat.length_squared() < 0.000001:
		return Vector3.ZERO
	return flat.normalized() * lerpf(stream_speed_min, stream_speed_max, _strength)


## Where the camera's view axis meets the ground. The same two lines
## `Snowfall.volume_centre()` opens with, and written out here rather than
## borrowed: this system must not hold a reference to that one, and the arithmetic
## is shorter than the import would be.
##
## A camera that is not looking down never meets the ground, and the divide below
## is by exactly how steeply it is. Guarded, or a level camera sends the sheet to
## infinity.
static func ground_focus(camera_position: Vector3, forward: Vector3, height: float) -> Vector3:
	var direction := forward.normalized()
	if direction.y >= -0.001:
		return camera_position
	return camera_position + direction * ((height - camera_position.y) / direction.y)


func _process(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	_place()
	var streaming := stream_ratio(_strength, stream_onset, stream_onset_softness) > 0.0
	if streaming and not _was_streaming:
		# Direction and ribbon phase must be correct on the first visible frame;
		# waiting for the periodic refresh would briefly reuse the lull's heading.
		bake(_clock)
		_since_bake = 0.0
	elif streaming:
		_since_bake += maxf(delta, 0.0)
		# Fifteen 60 Hz frames are mathematically 0.25 seconds but their floating
		# representation can land a hair below it.  Do not postpone a visual bake
		# by a whole render frame for that rounding residue.
		if _since_bake + 0.000001 >= maxf(rebake_seconds, 0.0):
			_since_bake = 0.0
			bake(_clock)
	else:
		# Do not accumulate idle time into a burst of immediate uploads.  A sheet
		# beginning after a lull gets exactly the single onset bake above.
		_since_bake = 0.0
	_was_streaming = streaming
	_apply()


# --- the point cloud ---------------------------------------------------------

## THE FIXED PART OF EVERY POINT, drawn once.
##
## Where a point sits ALONG its ribbon, how far across the ribbon's own width, how
## high in the thin slab, and which lane it belongs to. The bake shapes these; it
## never re-draws them, because a rebake has to be the same pattern a moment later
## rather than a different pattern.
##
## One long stream from one seeding, per trap 14: a generator re-seeded per
## decision has a measurably biased fourth draw, and a pattern is a few thousand
## decisions in a row.
func _seed_points() -> void:
	var count := point_count()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5F1D21F7
	# The first few draws of a freshly seeded stream are not yet mixed -- trap 14
	# measured the fourth as low as 0.09 where a uniform draw averages 0.5. They
	# are thrown away rather than laid into the first lane.
	for _discard in 16:
		rng.randf()
	_along.resize(count)
	_across.resize(count)
	_diffuse_across.resize(count)
	_distribution.resize(count)
	_lift.resize(count)
	_lane.resize(count)
	var lanes := lane_count()
	var half := volume_size.x * 0.5
	for i in count:
		_along[i] = rng.randf_range(-half, half)
		_across[i] = rng.randf_range(-1.0, 1.0)
		_diffuse_across[i] = rng.randf_range(-half, half)
		_distribution[i] = rng.randf()
		_lift[i] = rng.randf_range(-1.0, 1.0)
		_lane[i] = i % lanes


## The lanes, laid out in the WIND's own frame and then turned into the world.
##
## Public and taking the time, so a test can bake two moments and compare them --
## which is the one thing about this that was flagged as untested when it was
## proposed.
##
## THE ROTATION IS BAKED IN AND THE NODE IS NOT ROTATED. Turning the emitter
## instead would have been fewer lines, but it puts `direction` into a frame that
## has to be kept in step with the one `stream_velocity()` speaks, and this file
## already writes a WORLD direction from a world wind. A rotation that lives in
## exactly one place cannot fall out of step with itself.
func bake(at: float) -> void:
	if _points_image == null:
		return
	var heading := 0.0
	var flat := Vector3(_wind.x, 0.0, _wind.z)
	if flat.length_squared() > 0.000001:
		heading = atan2(flat.z, flat.x)
	var c := cos(heading)
	var s := sin(heading)
	var half := volume_size.x * 0.5
	var lanes := lane_count()
	var width := _points_image.get_width()
	for i in _along.size():
		var along: float = _along[i]
		var ribbon_across := ribbon_centre(
			_lane[i], lanes, ribbon_spacing_m, along, at,
			ribbon_meander_m, ribbon_meander_period_m, ribbon_drift_mps, ribbon_advance_mps
		) + soft_lane_offset(_across[i], ribbon_width_m, ribbon_edge_falloff)
		# The continuous bed shares the slow crosswind slide. Leaving its births
		# static while only the accent ribbons moved made most of the field read as
		# wallpaper, despite the flakes themselves travelling through it.
		var diffuse_across := _diffuse_across[i] + ribbon_drift_mps * at
		var across: float = diffuse_across \
			if _distribution[i] < clampf(diffuse_share, 0.0, 1.0) else ribbon_across
		# Wrapped, so a lane that has slid off one side of the volume comes back on
		# the other. The field is unbounded; the box it is sampled through is not.
		across = wrapf(across, -half, half)
		_points_image.set_pixel(
			i % width,
			i / width,
			Color(
				along * c - across * s,
				_lift[i] * volume_size.y * 0.5,
				along * s + across * c
			)
		)
	if _points_texture == null:
		_points_texture = ImageTexture.create_from_image(_points_image)
	else:
		_points_texture.update(_points_image)
	if _process_material != null:
		_process_material.emission_point_texture = _points_texture
	_baked_at = at
	_bake_count += 1


func bake_count() -> int:
	return _bake_count


func reset_bake_count() -> void:
	_bake_count = 0


## How many points the cloud actually holds: `ribbon_points` rounded to fill the
## texture exactly, because `emission_point_count` indexes pixels and a partly
## filled last row would emit a block of streaks from the origin.
func point_count() -> int:
	var wanted := maxi(ribbon_points, 1)
	var width := mini(wanted, 128)
	var height := maxi(1, int(ceil(float(wanted) / float(width))))
	return width * height


## Every point of the cloud as it was last baked, in this node's own space. The
## instrument the tests read the field's shape off.
func baked_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if _points_image == null:
		return out
	var width := _points_image.get_width()
	for i in _along.size():
		var c := _points_image.get_pixel(i % width, i / width)
		out.append(Vector3(c.r, c.g, c.b))
	return out


func baked_at() -> float:
	return _baked_at


## Follows the camera along the ground. Not the player: the camera is what
## decides which patch of snow is on screen, and a sheet centred on a man who has
## walked to the edge of the frame streams past empty ground.
func _place() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	var focus := ground_focus(camera.global_position, -camera.global_basis.z, ground_height)
	global_position = Vector3(focus.x, _surface_at(focus) + hover_m, focus.z)


## The snow surface under a point, if anything can say. Asked by method rather
## than by type so a scene without a snow field is a sheet at `ground_height`
## instead of a crash on the first frame.
func _surface_at(world: Vector3) -> float:
	if _snow_field == null:
		var registry := get_node_or_null("/root/ServiceRegistry")
		if registry != null:
			_snow_field = registry.get_service(&"snow_field")
	if _snow_field == null or not _snow_field.has_method("surface_height_at"):
		return ground_height
	return _snow_field.surface_height_at(world)


func _build() -> void:
	var bible = load(PALETTE_PATH)

	# World space. The sheet crosses the ground; particles must not ride the
	# emitter as it follows the camera, or the whole gust slides with the player.
	local_coords = false
	one_shot = false
	explosiveness = 0.0
	randomness = clampf(birth_randomness, 0.0, 1.0)
	amount = maxi(streaks, 1)
	lifetime = maxf(life_seconds, 0.05)
	# The sheet's lanes and bulk travel already carry direction. Individual powder
	# shards billboard and tumble, so they do not become a parallel tracer field.
	transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var quad := QuadMesh.new()
	quad.size = Vector2(streak_width, streak_length)
	quad.material = _streak_material(bible)
	draw_pass_1 = quad

	var count := point_count()
	var width := mini(maxi(ribbon_points, 1), 128)
	_points_image = Image.create_empty(width, count / width, false, Image.FORMAT_RGBF)
	_seed_points()

	_process_material = ParticleProcessMaterial.new()
	# POINTS, NOT A BOX. See the ribbon block above for the measurement that moved
	# it: a box emits a Poisson scatter, and a Poisson scatter of blowing snow is
	# indistinguishable from fog.
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	_process_material.emission_point_count = count
	_process_material.spread = spread_degrees
	_process_material.direction = Vector3(1.0, 0.0, 0.0)
	# Settles back toward the ground over its life, which is what stops the sheet
	# climbing out of its own box and becoming weather.
	_process_material.gravity = Vector3(0.0, -0.45, 0.0)
	_process_material.scale_min = 0.7
	_process_material.scale_max = 1.25
	_process_material.particle_flag_damping_as_friction = true
	_process_material.damping_min = maxf(minf(drag_range.x, drag_range.y), 0.0)
	_process_material.damping_max = maxf(maxf(drag_range.x, drag_range.y), 0.0)
	_process_material.particle_flag_rotate_y = true
	_process_material.angle_min = -180.0
	_process_material.angle_max = 180.0
	_process_material.angular_velocity_min = angular_velocity_range.x
	_process_material.angular_velocity_max = angular_velocity_range.y
	_process_material.angular_velocity_curve = _spin_drag_curve(spin_end_multiplier)
	_process_material.turbulence_enabled = turbulence_influence_range.y > 0.0
	_process_material.turbulence_influence_min = maxf(turbulence_influence_range.x, 0.0)
	_process_material.turbulence_influence_max = maxf(
		turbulence_influence_range.y, turbulence_influence_range.x
	)
	_process_material.turbulence_noise_scale = maxf(turbulence_noise_scale, 0.01)
	_process_material.turbulence_noise_speed = Vector3.ONE * maxf(turbulence_noise_speed, 0.0)
	_process_material.alpha_curve = _fade_ramp()
	process_material = _process_material
	bake(0.0)


## Cool white, from the palette rather than from a literal. Unshaded, so rule 8's
## banned list has nothing left to switch off; MIX rather than ADD, so two
## streaks crossing are not brighter than either.
##
## Particle billboarding keeps CUSTOM.x available as the flake's readable roll.
func _streak_material(bible) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	var snow: Color = bible.snow_tones[0]
	surface.albedo_color = Color(
		lerpf(snow.r, 1.0, streak_whiteness),
		lerpf(snow.g, 1.0, streak_whiteness),
		lerpf(snow.b, 1.0, streak_whiteness),
		streak_alpha
	)
	surface.albedo_texture = _streak_texture()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	surface.billboard_keep_scale = true
	surface.disable_receive_shadows = true
	surface.vertex_color_use_as_albedo = true
	return surface


## An off-centre radial lentil rather than a white rectangle. Its asymmetry is
## what makes the damped roll readable without drawing a literal snowflake icon.
func _streak_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.44, 0.74, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.48),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.43, 0.48)
	texture.fill_to = Vector2(0.98, 0.48)
	texture.width = 32
	texture.height = 32
	return texture


func _spin_drag_curve(end_multiplier: float) -> CurveTexture:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 1.0
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.35, 0.62))
	curve.add_point(Vector2(1.0, clampf(end_multiplier, 0.0, 1.0)))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## In fast, out slow. Snow is picked up abruptly and settles gradually, and the
## asymmetry is most of what makes the sheet read as being dragged rather than
## being drawn.
func _fade_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.10, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## The gust, applied. Everything here can be written while particles are in
## flight; nothing here re-allocates.
func _apply() -> void:
	if _process_material == null:
		return
	var ratio := stream_ratio(_strength, stream_onset, stream_onset_softness)
	# ...times the field's own slow surge. The gust decides WHETHER there is a
	# sheet; the pulse decides how much of it is running at this moment, and it is
	# what stops a sustained gale drawing a constant wash. Safe on `amount_ratio`
	# for the reason the header gives -- it never re-allocates -- and safe on THIS
	# emitter in particular because a streak lives 0.72 s, so the sheet answers a
	# change within about a second rather than over the eleven a snow layer takes.
	amount_ratio = ratio * pulse_at(_clock, pulse_seconds, pulse_depth)
	# Stopped outright below the onset shoulder rather than merely emptied: an emitter at
	# amount_ratio 0 still runs, and this one is meant to be nothing at all for
	# most of the game. Judged on the GUST, not on the pulsed figure: a pulse that
	# could switch the emitter off would restart the sheet from empty every time it
	# troughed.
	emitting = ratio > 0.0
	if ratio <= 0.0:
		return
	var travel := stream_velocity()
	var speed := travel.length()
	if speed > 0.0001:
		_process_material.direction = travel / speed
	var ratio_min := clampf(minf(speed_ratio_range.x, speed_ratio_range.y), 0.0, 1.0)
	var ratio_max := clampf(maxf(speed_ratio_range.x, speed_ratio_range.y), ratio_min, 1.0)
	_process_material.initial_velocity_min = speed * ratio_min
	_process_material.initial_velocity_max = speed * ratio_max
