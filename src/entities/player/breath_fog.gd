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

const PALETTE_PATH := "res://data/palette/color_bible.tres"

## Off, and nothing is emitted at all. The interior reveal will own this.
@export var outdoors := true

## Puffs a second, standing and flat out. Low on purpose: the reference has about
## half a dozen in the air at once, and anything much above that stops being a
## line of separate breaths and becomes a cloud.
@export var puff_rate_rest := 3.0
@export var puff_rate_hard := 7.0

## How long one puff survives. Short by design -- 很快消失 -- and at this camera
## angle a long-lived particle smears across the frame and reads as weather
## rather than as a person breathing.
@export var puff_life_warm := 0.9
@export var puff_life_cold := 1.6

## How fast it leaves the mouth. A hard breath is thrown further, which is what
## opens the spacing in the trail when he runs.
@export var puff_speed_rest := 0.75
@export var puff_speed_hard := 1.5

## Radius at birth, in metres, and the fraction of it left at death.
##
## It SHRINKS. The reference's older puffs are both smaller and fainter than the
## fresh one at the mouth, and that is what makes the trail read as a sequence in
## time rather than as one cloud with a ragged edge.
##
## Sized against the camera, not against a face: the frame is 10.5 m tall over
## 1000 px, so a metre is 95 px and a puff that looks right in a close-up is four
## pixels in play.
@export var puff_radius_birth := 0.15
@export var puff_radius_fade := 0.35

## How much of the puff a warm body produces. Not zero: an exhale in this climate
## is visible even from someone who is fine, and a channel that disappears
## entirely at one end cannot be read as a scale.
@export var density_warm := 0.35

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
	_process_material.direction = Vector3(0.0, 0.55, 1.0)
	_process_material.spread = 24.0
	# Warm air rises, which is what angles the trail up in the reference.
	_process_material.gravity = Vector3(0.0, 0.34, 0.0)
	# It stops almost as soon as it leaves him. Breath does not travel.
	_process_material.damping_min = 1.1
	_process_material.damping_max = 1.8
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_process_material.emission_sphere_radius = 0.05
	_process_material.color_ramp = _fade_ramp()
	_process_material.scale_curve = _shrink_curve()
	process_material = _process_material

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var surface := StandardMaterial3D.new()
	# Cool white with the snow's own cast. Art Bible rule 12 keeps the warm pixels
	# for fire, windows, beacons, the scarf and the truck; breath is not on that
	# list, so it stays in the snow tones.
	surface.albedo_color = bible.snow_tones[0].lerp(Color.WHITE, 0.72)
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


## A round billboard with a soft rim, not a wisp: the reference's puffs are crisp
## discs. Full alpha holds most of the way out and falls off in the last third.
##
## Built rather than imported -- it is two dozen bytes of gradient, and importing
## a PNG for it would put an art asset in the repo that nobody can tune without a
## paint program.
func _puff_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.52, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.92),
		Color(1.0, 1.0, 1.0, 0.35),
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


## Alpha over the particle's life: in fast, out slow, ending fully transparent. A
## puff that starts at full alpha pops into existence at the mouth.
func _fade_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.80),
		Color(1.0, 1.0, 1.0, 0.42),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Radius over life, as a multiple of the size the particle was born at. It opens
## a little as it clears the mouth and then shrinks away, so the oldest puff in
## the trail is the smallest one.
func _shrink_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.72))
	curve.add_point(Vector2(0.22, 1.0))
	curve.add_point(Vector2(1.0, puff_radius_fade))
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

	# scale_curve carries the shrink over the particle's life, so these two are
	# the size it is BORN at. A warm breath is born smaller.
	var birth := puff_radius_birth * lerpf(0.66, 1.0, density)
	_process_material.scale_min = birth * 0.8
	_process_material.scale_max = birth * 1.2

	# The inert half of the hook: zero until Wave 3's wind system calls
	# set_wind(), and then the puff drifts with the weather instead of only with
	# the walker.
	_process_material.gravity = Vector3(0.0, 0.34, 0.0) + _wind
