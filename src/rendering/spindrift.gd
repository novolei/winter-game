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
## Hence `stream_onset`. Below it this emits NOTHING. A spindrift that is always
## on is ground fog, it flattens the picture, and it removes the only thing that
## made it worth building.
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

## The strength a gust must reach before ANY snow lifts. See the header: this is
## the whole effect.
##
## 0.28 sits above the valley profile's gust midpoint and below its peak, so
## spindrift happens on the bigger half of ordinary gusts and on every squall --
## often enough to be part of the weather, rare enough to be an event.
@export var stream_onset := 0.28

## How fast the sheet travels, at the onset and at a full gale, in metres per
## second. Fast: the readability of this cue is almost entirely its SPEED against
## the stillness of the ground it crosses.
@export var stream_speed_min := 3.4
@export var stream_speed_max := 9.5

## The emission box, in world metres, centred on the point the camera is looking
## at. Wide enough to cover the widest framing the rig offers, and THIN: this is
## snow being dragged over a surface, not a blizzard at knee height.
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
@export var life_seconds := 1.15

## The streak, in metres: narrow across, long along travel. `transform_align`
## puts the quad's +Y on the particle's velocity, so `y` here IS the streak.
@export var streak_width := 0.050
@export var streak_length := 0.55

## The cone the snow leaves in. Wide enough that the sheet has a top and a
## bottom; narrow enough that it stays a sheet.
@export var spread_degrees := 14.0

## How far the palette's lightest snow is taken toward white, and the most alpha
## a streak ever has.
##
## WHITER than the falling flake (0.62) and LESS OPAQUE (0.78), and both halves
## were measured off a frame rather than reasoned. A streak is seen against SNOW,
## where the flake is mostly seen against sky and against the dark solids -- so at
## the flake's whiteness this cue was pale-blue-on-pale-blue and, at a strength of
## 0.7, invisible in the capture while every number said it was running. The alpha
## comes back down because there are three times as many streaks as there are
## flakes in a layer, and at the flake's opacity the sheet became a white bar
## across the bottom of the picture.
##
## Still far under the bloom threshold: linear 0.91 x 0.60 = 0.55 against 0.95.
## `test_wind.gd` pins that, the same way `test_snowfall.gd` pins the flake.
@export var streak_whiteness := 0.78
@export var streak_alpha := 0.60

## Where the ground is taken to be when nothing can be asked. Snowfall's own
## figure, for the same reason: it is the height the camera's view axis is taken
## to meet the world at.
@export var ground_height := 1.0

var _wind := Vector3.ZERO
var _strength := 0.0
var _process_material: ParticleProcessMaterial
var _snow_field = null


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


## How much of the sheet is running, 0 .. 1. Zero below the onset, and that zero
## is the effect.
static func stream_ratio(strength: float, onset: float) -> float:
	var held := clampf(strength, 0.0, 1.0)
	if held <= onset:
		return 0.0
	var span := 1.0 - onset
	if span <= 0.0:
		return 1.0
	# Raised to 1.5, so the sheet builds through a gust rather than arriving
	# whole. A linear ramp from the onset reads as a switch, because the onset is
	# already a switch and two of them land together -- and the square this was
	# written as first was the other error: it put only a third of the sheet on at
	# a strength of 0.7, which is most of a gale, and the cue did not read.
	var t := (held - onset) / span
	return clampf(pow(t, 1.5), 0.0, 1.0)


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


func _process(_delta: float) -> void:
	_place()
	_apply()


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
	amount = maxi(streaks, 1)
	lifetime = maxf(life_seconds, 0.05)
	# Velocity-aligned, billboarded round it: the quad's +Y lies along travel, so
	# a streak IS a streak rather than a dot with motion blur nobody rendered.
	transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var quad := QuadMesh.new()
	quad.size = Vector2(streak_width, streak_length)
	quad.material = _streak_material(bible)
	draw_pass_1 = quad

	_process_material = ParticleProcessMaterial.new()
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_material.emission_box_extents = volume_size * 0.5
	_process_material.spread = spread_degrees
	_process_material.direction = Vector3(1.0, 0.0, 0.0)
	# Settles back toward the ground over its life, which is what stops the sheet
	# climbing out of its own box and becoming weather.
	_process_material.gravity = Vector3(0.0, -0.45, 0.0)
	_process_material.scale_min = 0.7
	_process_material.scale_max = 1.25
	_process_material.alpha_curve = _fade_ramp()
	process_material = _process_material


## Cool white, from the palette rather than from a literal. Unshaded, so rule 8's
## banned list has nothing left to switch off; MIX rather than ADD, so two
## streaks crossing are not brighter than either.
##
## Billboarding is DISABLED on the material on purpose: `transform_align` on the
## node is already orienting the quad, and a material billboard would overwrite
## that orientation and turn every streak back into a dot.
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
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	surface.disable_receive_shadows = true
	surface.vertex_color_use_as_albedo = true
	return surface


## A streak that is solid through the middle and tapers at both ends, so the
## quad's edges never read as edges. Vertical fill, because the quad's +Y is the
## direction of travel.
func _streak_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 8
	texture.height = 64
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
	var ratio := stream_ratio(_strength, stream_onset)
	amount_ratio = ratio
	# Stopped outright below the onset rather than merely emptied: an emitter at
	# amount_ratio 0 still runs, and this one is meant to be nothing at all for
	# most of the game.
	emitting = ratio > 0.0
	if ratio <= 0.0:
		return
	var travel := stream_velocity()
	var speed := travel.length()
	if speed > 0.0001:
		_process_material.direction = travel / speed
	_process_material.initial_velocity_min = speed * 0.65
	_process_material.initial_velocity_max = speed
	_process_material.emission_box_extents = volume_size * 0.5
