class_name BreathFog
extends GPUParticles3D

## The white of a breath in cold air, emitted from the head.
##
## GDD section 9 lists 呼出白气的浓度 -- breath density -- as one of the diegetic
## readouts, alongside body language, screen frost and audio. There is no HUD, so
## this is not decoration: it is one of the few channels the game has for telling
## the player what state their body is in. Everything about it is therefore
## driven rather than constant.
##
##   set_chill()     core temperature, 0 warm .. 1 freezing. The primary driver
##                   and the one that carries information: colder air out of a
##                   colder body condenses more, so there is more of it and it
##                   hangs about longer.
##   set_exertion()  0 standing .. 1 running. Reads off the same ground speed the
##                   animation blend uses, so the two never disagree.
##   set_rate_scale() GDD section 9's 呼吸变浅变快, driven from data rather than
##                   from a branch here: SurvivalSystem publishes `breath:rate`
##                   out of res://data/stats/core_temperature.tres and whoever
##                   owns the body passes on what it says. Separate from
##                   set_chill() because it is a different fact -- chill is how
##                   much condenses, this is how OFTEN he breathes -- and the
##                   data quickens the breath at thresholds rather than smoothly.
##   set_wind()      A HOOK, and deliberately inert today. src/systems/
##                   wind_system.gd does not exist -- it is Wave 3 -- and
##                   inventing a wind here would mean two of them later.
##   outdoors        A switch, not a condition. The interior reveal is a later
##                   wave and there is nowhere indoors to be yet.
##
## WORLD SPACE IS THE WHOLE EFFECT, and it is the one thing here that cannot go
## wrong quietly. `local_coords = false` means a particle stays exactly where it
## was exhaled. A walking man therefore leaves a line of puffs strung back and up
## along his path, and a standing man's pile up at his face into a soft patch
## that spreads and fades. Leave the particles in local coordinates instead and
## every puff drags along with the head: the trail never forms, the standing
## patch never gathers, and what is left is a smear stuck to his chin. There is
## no "moving mode" and no "standing mode" in this file, and there should not be
## -- there is one emitter whose puffs stay put, and the two reads fall out of it.
##
## EMISSION IS CONTINUOUS AND SLOW rather than one burst per breath. The
## reference frames show four to six discrete, clearly separated round puffs
## alive at once, and that separation is what a low rate plus world space gives
## for nothing: at 4 a second over a 1.2 s life there are five in the air and the
## walker has covered a stride between each. A burst per exhale reads as a steam
## engine; a high rate reads as fog.
##
## Emitted from a BoneAttachment3D on the head rather than from an offset above
## the character's origin. That matters for exactly the takes that are not
## standing: through `knockdown_recover` the head travels 4.6 m and ends up on
## the ground, and a fixed offset would leave the breath in the air where his
## head used to be.
##
## IT IS VAPOUR, NOT SNOW. Breath is warm humid air condensing: slightly
## translucent, faintly grey, taking its colour from what is around it. An opaque
## white puff reads as a snowball stuck to his face. So the colour sits well back
## from white -- a cool grey-blue off the snow tones -- and the visibility is
## carried by ALPHA rather than by brightness. Art Bible rule 12 keeps the warm
## pixels for fire, windows, beacons, the scarf and the truck; steam is cool, and
## a breath that drifted warm would compete with the one beacon in the frame.
##
## IT EMERGES AND IT DISPERSES; it does not appear and it does not switch off.
## Both ends of a puff's life are eased, and they are eased differently, because
## the two things are not symmetrical:
##
##   birth  small and invisible, swelling to full size over the first sixth of
##          its life while the alpha comes up. Real breath clears the mouth.
##   death  the alpha falls away on a curve while the puff KEEPS EXPANDING. This
##          is the one that is easy to get backwards: vapour disperses, so the
##          oldest puff in a trail is the biggest and the faintest. Shrinking it
##          away instead makes the trail read as a row of dying sparks.
##
## FUSION, and what is actually shipped here. Real vapour merges: two puffs close
## together should read as one shape with a pinched waist, not as two circles
## overlapping. That is a metaball, and the honest way to get one is a screen
## space threshold -- render the puffs into a SubViewport and cut the ACCUMULATED
## alpha at a level, so the two fields sum past the threshold between the centres
## and the silhouette genuinely joins.
##
## That is not what this file does, and the reason is occlusion. A SubViewport
## composite has no depth, so the fused cloud would draw over everything in the
## frame -- including his own head, every time he walks away from this fixed
## isometric camera, which is half the time. Fixing that means carrying the
## breath's depth through the pass and testing it against the scene's, which is a
## rendering feature rather than a content change, in files another agent owns.
## See the task report for the estimate.
##
## What IS here is the union rather than the threshold: each puff carries a
## smooth bell of alpha instead of a disc with a soft rim, so where two overlap
## the composited alpha rises smoothly and the pair reads as one lumpy mass. It
## gets the merge and not the pinch. It costs nothing, it keeps depth sorting,
## and it is the correct approximation to be caught using rather than the wrong
## one -- but it is an approximation and it is not what was asked for.

const PALETTE_PATH := "res://data/palette/color_bible.tres"

## Off, and nothing is emitted at all. The interior reveal will own this.
@export var outdoors := true

## Puffs a second, standing and flat out. Low on purpose: the reference has about
## half a dozen in the air at once, and anything much above that stops being a
## line of separate breaths and becomes a cloud.
@export var puff_rate_rest := 4.0
@export var puff_rate_hard := 7.0

## How long one puff survives. Short by design -- 很快消失 -- and at this camera
## angle a long-lived particle smears across the frame and reads as weather
## rather than as a person breathing.
@export var puff_life_warm := 0.9
@export var puff_life_cold := 1.6

## How fast it leaves the mouth, in metres a second. A hard breath is thrown
## further, which is what opens the spacing in the trail when he runs.
##
## This is also what stands the cloud OFF HIS FACE, and that is the reason these
## numbers are not small. Breath leaves the mouth with momentum; it does not
## condense on the lips. Against the damping below, a resting breath coasts about
## half a metre before it stops -- at this camera roughly a head and a half in
## front of him, which is far enough that the cloud is outside the silhouette of
## the hood instead of sitting on it. A puff that merges with another INSIDE his
## outline is a puff nobody can see merging.
@export var puff_speed_rest := 1.25
@export var puff_speed_hard := 1.9

## Radius at birth, in metres, and the multiple of it the puff has swollen to by
## the time it is gone.
##
## It EXPANDS. Vapour disperses -- it spreads out and thins until there is
## nothing left of it -- so the oldest puff in the trail is the largest and the
## faintest one. This is deliberately the opposite of what this file used to do.
##
## Sized against the camera, not against a face: the frame is 10.5 m tall over
## 1000 px, so a metre is 95 px and a puff that looks right in a close-up is four
## pixels in play. The birth radius is also what makes puffs overlap enough to
## fuse when he is standing still -- see the class comment.
@export var puff_radius_birth := 0.20
@export var puff_radius_death := 1.80

## How much of the puff a warm body produces. Not zero: an exhale in this climate
## is visible even from someone who is fine, and a channel that disappears
## entirely at one end cannot be read as a scale.
@export var density_warm := 0.35

## Peak opacity, at the point in its life where the puff is densest -- and the
## knob that decides whether this reads as vapour. A translucent grey puff over
## snow is steam; an opaque one is a snowball, whatever colour it is. Brightness
## is NOT the knob, which is why this is well short of solid while the tone stays
## only part way to white.
##
## Landed by measurement rather than by taste: at 0.52 the brightest pixel of the
## cloud sampled #c1dcff against snow at #9bc0ed, which was too slight to find at
## gameplay framing once the aerial perspective lightened the field. At 0.62 it
## sampled #bbd9ff against #86a9db -- still unmistakably cool and unmistakably not
## white, blue a full quarter above red, and visible at 11% of frame height.
@export var puff_opacity := 0.62

## How far the colour is pulled from the snow toward white. Low: at zero the puff
## is exactly the snow's own tone and disappears into it, at one it is the white
## card this replaced. Just under half leaves a cool off-white that is clearly
## lighter than the field without leaving the snow tones.
@export var puff_whiteness := 0.42

var _chill := 1.0
var _exertion := 0.0
var _rate_scale := 1.0
var _wind := Vector3.ZERO
var _process_material: ParticleProcessMaterial


func _ready() -> void:
	_build()
	_apply()


## Core temperature, 0 warm .. 1 freezing. See the class comment.
func set_chill(amount_cold: float) -> void:
	_chill = clampf(amount_cold, 0.0, 1.0)


## 0 standing .. 1 running, off the same ground speed the animation blend reads.
func set_exertion(effort: float) -> void:
	_exertion = clampf(effort, 0.0, 1.0)


## How much faster than the authored rhythm he is breathing. 1.0 is the tuning
## above and the only value anything sees until something drives it; the shipped
## survival stats reach 1.25 below half a bar of warmth and 1.875 below a fifth.
##
## Capped at 4 because `amount` re-allocates the particle buffer: a channel that
## somehow arrived at a hundred would not make a hundredfold breath, it would
## make a cloud, and the cap keeps a bad number in the data from looking like a
## bug in the emitter.
func set_rate_scale(scale: float) -> void:
	_rate_scale = clampf(scale, 0.0, 4.0)


## Puffs a second, after everything driving it. The emitter can only carry whole
## particles, so `amount` rounds this off and two different rates can round to
## the same buffer size -- this is the number the readout actually means, and the
## one to assert against.
func puffs_per_second() -> float:
	if not outdoors:
		return 0.0
	return lerpf(puff_rate_rest, puff_rate_hard, _exertion) * lerpf(0.7, 1.0, _density()) * _rate_scale


## How much of the puff a body this cold produces, `density_warm` .. 1.
func _density() -> float:
	return lerpf(density_warm, 1.0, _chill)


## THE HOOK. Wave 3's wind system calls this; until then it is called by nobody
## and the value stays zero. Kept rather than left out so that whoever writes
## src/systems/wind_system.gd has somewhere obvious to connect, instead of
## inventing a second wind inside this file.
func set_wind(velocity: Vector3) -> void:
	_wind = velocity


func _build() -> void:
	var bible = load(PALETTE_PATH)

	# The whole effect. See the class comment; nothing else in this file matters
	# if this line is wrong.
	local_coords = false
	# Steady and slow: the separation between puffs comes from the rate and from
	# world space, not from bursting.
	explosiveness = 0.0
	one_shot = false
	randomness = 0.35
	amount = 6
	# The emitter rides the head and the puffs are left behind it, so the box has
	# to cover where they have been, not where he is. Too small and the whole
	# trail pops out of existence as he walks away from it.
	visibility_aabb = AABB(Vector3(-4.0, -3.0, -4.0), Vector3(8.0, 6.0, 8.0))

	_process_material = ParticleProcessMaterial.new()
	# +Z is the way he is facing: the model is authored facing +Z, and the aim
	# node player_controller builds cancels the head bone's own rest roll so that
	# this axis means the same thing here.
	#
	# Flatter than it was. The puff needs HORIZONTAL distance from the body -- the
	# cloud belongs in front of the face, not stacked above the hood -- and the
	# rise is the gravity term's job, not this one's.
	_process_material.direction = Vector3(0.0, 0.28, 1.0)
	_process_material.spread = 22.0
	# Warm air rises, which is what angles the trail up in the reference.
	_process_material.gravity = Vector3(0.0, 0.34, 0.0)
	# It coasts about half a metre and stops. Breath carries clear of the face and
	# then goes nowhere: see puff_speed_rest for the arithmetic these two are half
	# of.
	_process_material.damping_min = 1.3
	_process_material.damping_max = 1.9
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_process_material.emission_sphere_radius = 0.05
	_process_material.color_ramp = _fade_ramp()
	_process_material.scale_curve = _swell_curve()
	process_material = _process_material

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var surface := StandardMaterial3D.new()
	# Vapour, not snow. A cool grey-blue off the snow's own lightest tone, pulled
	# only part way to white -- see puff_whiteness, and the class comment on why
	# the alpha carries this rather than the brightness. Art Bible rule 12 keeps
	# the warm pixels for fire, windows, beacons, the scarf and the truck; breath
	# is not on that list, so it stays in the snow tones.
	surface.albedo_color = bible.snow_tones[0].lerp(Color.WHITE, puff_whiteness)
	# A bare QuadMesh is a rectangle, and a rectangle of flat white is what a
	# first pass at this actually looks like on screen: a paper card stuck to his
	# face. The radial alpha is not a refinement, it is the difference between a
	# puff and a card.
	surface.albedo_texture = _puff_texture()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	surface.billboard_keep_scale = true
	surface.disable_receive_shadows = true
	quad.material = surface
	draw_pass_1 = quad


## The alpha across one puff, centre to rim -- a smooth bell rather than a disc
## with a soft edge, and that difference is the fusion approximation the class
## comment describes.
##
## A disc has a shoulder in it. Overlap two and the eye finds both outlines and
## reads two circles with a bright lens between them. A bell has no shoulder
## anywhere, so where two overlap the composited alpha rises smoothly through the
## join and the pair reads as one mass. It is the union of two fields without the
## threshold that would pinch the waist between them.
##
## Built rather than imported -- it is two dozen bytes of gradient, and importing
## a PNG for it would put an art asset in the repo that nobody can tune without a
## paint program.
func _puff_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.44, 0.64, 0.82, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.94),
		Color(1.0, 1.0, 1.0, 0.76),
		Color(1.0, 1.0, 1.0, 0.46),
		Color(1.0, 1.0, 1.0, 0.17),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


## Alpha over the particle's life. Both ends are eased and neither is a cliff.
##
## It comes up over the first tenth rather than starting lit, so the puff emerges
## from the mouth instead of appearing at it; and it goes out along a long convex
## tail rather than being switched off at death, so a puff that is still 26% lit
## three quarters of the way through has faded to nothing by the end without any
## frame in which it visibly stopped existing. The peak is puff_opacity, which is
## the number that decides whether this reads as vapour.
func _fade_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.06, 0.16, 0.40, 0.66, 0.86, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, puff_opacity * 0.55),
		Color(1.0, 1.0, 1.0, puff_opacity),
		Color(1.0, 1.0, 1.0, puff_opacity * 0.86),
		Color(1.0, 1.0, 1.0, puff_opacity * 0.50),
		Color(1.0, 1.0, 1.0, puff_opacity * 0.18),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Radius over life, as a multiple of the size the particle was born at.
##
## Up quickly from small -- the puff swells out of the mouth over the first sixth
## rather than arriving at full size -- and then it KEEPS OPENING for the rest of
## its life, all the way to puff_radius_death, while the ramp above thins it out.
## That is what dispersal looks like. A curve that came back down would make the
## oldest puff the smallest, which reads as a spark going out.
##
## Curve points default to flat tangents, so the interpolation between them is
## already eased and neither the birth nor the swell has a corner in it.
func _swell_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = maxf(puff_radius_death, 1.0)
	curve.add_point(Vector2(0.0, 0.42))
	curve.add_point(Vector2(0.16, 1.0))
	curve.add_point(Vector2(0.55, puff_radius_death * 0.66))
	curve.add_point(Vector2(1.0, puff_radius_death))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _process(_delta: float) -> void:
	_apply()


## Everything the survival stats say, applied to the emitter.
##
## Called every frame, but `amount` is written only when the rounded value has
## actually changed: assigning it re-allocates the particle buffer and every puff
## in the air disappears at once, which at one frame in sixty is a flicker nobody
## would be able to diagnose.
func _apply() -> void:
	if not outdoors:
		emitting = false
		return
	emitting = true

	# Cold is the primary driver, and it does two things: more of it, and it
	# hangs about longer before it disperses.
	var density := _density()
	lifetime = lerpf(puff_life_warm, puff_life_cold, _chill)

	# Exertion is the rhythm. A running man breathes more often and harder, and
	# the rate is what strings the trail out behind him. breath:rate quickens it
	# on top of that: GDD section 9's 呼吸变浅变快 is a cold man panting, not an
	# exerted one.
	var rate := puffs_per_second()
	var wanted := clampi(int(round(rate * lifetime)), 2, 18)
	if wanted != amount:
		amount = wanted

	var speed := lerpf(puff_speed_rest, puff_speed_hard, _exertion)
	_process_material.initial_velocity_min = speed * 0.7
	_process_material.initial_velocity_max = speed

	# scale_curve carries the swell over the particle's life, so these two are the
	# size it is BORN at. A warm breath is born smaller.
	var birth := puff_radius_birth * lerpf(0.66, 1.0, density)
	_process_material.scale_min = birth * 0.8
	_process_material.scale_max = birth * 1.2

	# The inert half of the hook: zero until Wave 3's wind system calls
	# set_wind(), and then the puff drifts with the weather instead of only with
	# the walker.
	_process_material.gravity = Vector3(0.0, 0.34, 0.0) + _wind
