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
## The frame is 10.5 m tall (CameraRig.orthographic_size) over about a thousand
## pixels, so a metre is roughly 95 px:
##
##   distant  0.035-0.055 m  ->  3-5 px    specks, the texture of the air
##   near     0.050-0.090 m  ->  5-9 px    the snow the player actually sees
##   lens     0.100-0.180 m  ->  10-17 px  the one that crosses the picture
##
## and that arithmetic is also why this draws a SOFT DOT rather than the
## hexagonal flake the document prefers. At 5 px a hexagon is a dot with worse
## aliasing; at 17 px -- the largest flake in the game, and only on the lens
## layer -- it would be six pixels of star crawling through a moving frame. The
## document is right that a hexagon is the more artistic choice, and wrong that
## this camera can show one.
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

## ON THE LENS RATHER THAN IN THE WORLD. Layers 1 and 2 are false: the emitter
## follows the camera and its particles must NOT, or the whole snowfall slides
## along with the player. Layer 3 is true and is the deliberate opposite -- it
## rides the camera, it is not in world space, and style document section 23 is
## explicit that it does not need to be. It only has to cross the picture.
@export var camera_space := false

## The emission box, full size, centred on this node. In world metres for a
## world layer; in CAMERA metres for a lens layer, where x is across the frame
## and y is up it.
@export var volume_size := Vector3(36.0, 22.0, 36.0)

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
	_process_material.emission_box_extents = volume_size * 0.5
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

	# A GPUParticles3D is culled by this box and not by where its particles
	# actually got to, so it has to cover the whole fall and the whole drift or
	# the snow vanishes the moment the emitter's own origin leaves the frame.
	var reach := _reach()
	visibility_aabb = AABB(volume_size * -0.5 - reach, volume_size + reach * 2.0)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _flake_material(bible)
	draw_pass_1 = quad


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
	gradient.offsets = PackedFloat32Array([0.0, 0.08, 0.82, 1.0])
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
	# The clear day is a FRACTION of the storm's buffer rather than a smaller
	# buffer -- see the header.
	var floor_ratio := float(flakes_clear) / float(maxi(flakes_blizzard, 1))
	amount_ratio = clampf(lerpf(floor_ratio, 1.0, _rate), 0.0, 1.0)
	randomness = lerpf(randomness_clear, randomness_blizzard, _rate)

	# The slant goes into the DIRECTION the flake is born travelling in, not into
	# a sideways acceleration -- see drift_clear above for the measurement that
	# settled it. `direction` is in this node's own space, which for a world layer
	# is the world (Snowfall only ever translates it) and for a lens layer is the
	# frame itself.
	var velocity := birth_velocity()
	var speed := velocity.length()
	if speed > 0.0001:
		_process_material.direction = velocity / speed
	_process_material.initial_velocity_min = speed * 0.7
	_process_material.initial_velocity_max = speed

	# Gravity is where a ParticleProcessMaterial keeps every constant
	# acceleration, so the flake's gentle sag and whatever the wind system is
	# gusting arrive here together.
	_process_material.gravity = Vector3(0.0, -fall_accel, 0.0) + _wind

	# Born a little smaller when it is barely snowing. A clear sky with the same
	# flakes as a blizzard, only fewer, reads as a broken emitter.
	var size := lerpf(0.82, 1.0, _rate)
	_process_material.scale_min = flake_size_min * size
	_process_material.scale_max = flake_size_max * size
