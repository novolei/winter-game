extends TestCase

## Snowfall is weather, not decoration.
##
## GDD section 7 makes the weather a mechanic and section 4 makes day 7 a
## whiteout, so the thing these tests protect is that the snow is DRIVEN. A
## constant snowfall and a driven one are indistinguishable in any screenshot --
## which is the only way this feature can fail silently, and it is the same trap
## tests/unit/test_breath_fog.gd was written against.
##
## Two of them are about the camera rather than about the snow, and they are the
## ones that would otherwise be found last: this camera is ORTHOGRAPHIC, so a
## flake does not get smaller with distance. Size on screen is the only thing
## separating the three layers, and a flake sized for a perspective camera is
## either invisible or enormous here.

const SnowfallLayerScript := preload("res://src/rendering/snowfall_layer.gd")
const SnowfallScript := preload("res://src/rendering/snowfall.gd")
const CameraRigScript := preload("res://src/rendering/camera_rig.gd")
const SnowFieldScript := preload("res://src/systems/snow_field.gd")

const DISTANT_SCENE := "res://scenes/effects/snow_distant.tscn"
const NEAR_SCENE := "res://scenes/effects/snow_near.tscn"
const LENS_SCENE := "res://scenes/effects/snow_lens.tscn"

## What the lighting director hands the snowfall. A RefCounted, so it frees
## itself and nothing here has to remember it (briefing section 2.2).
class FakeLighting extends RefCounted:
	var look: LightingPreset = null
	## True is the ordinary case -- the clock crossfades between the six over
	## eight seconds. False is a CUT: the debug hotkeys and the screenshot
	## harness both snap a preset on outright.
	var crossfading := true

	func active_preset() -> LightingPreset:
		return look

	func is_crossfading() -> bool:
		return crossfading


## Stands in for TrackMask, and answers to the name TrackMask itself chose --
## see test_the_snowfall_reaches_the_footprints_by_the_name_the_mask_chose.
class FakeMask extends RefCounted:
	var rate := -1.0

	func set_snowfall_rate(value: float) -> void:
		rate = value


func _layer(path: String) -> SnowfallLayer:
	var scene: PackedScene = load(path)
	var layer: SnowfallLayer = scene.instantiate()
	# Nothing has been added to a tree, so nothing has called it (briefing trap 1).
	layer._ready()
	return layer


func _director() -> Snowfall:
	var director: Snowfall = SnowfallScript.new()
	director._ready()
	return director


func _preset(id: StringName) -> LightingPreset:
	var look := LightingPreset.new()
	look.id = id
	return look


## The vertical world extent of the frame, read off the rig rather than copied,
## so that a change of framing moves these tests with it.
func _frame_height_m() -> float:
	var rig: CameraRig = CameraRigScript.new()
	var height: float = rig.orthographic_size
	rig.free()
	return height


## EVERY framing the camera can be at, read off the rig. Not a list of numbers:
## the whole defect these tests were written against was a snowfall that knew
## about one framing, and a test that knew about three would be the same mistake
## one size larger. A stop added to CameraRig arrives here on its own.
func _framing_stops() -> Array:
	var rig: CameraRig = CameraRigScript.new()
	var stops: Array = Array(rig.framing_stops)
	rig.free()
	return stops


## The stops, plus the places BETWEEN them -- which is where the frame actually
## spends the length of every zoom. CameraRig eases from one stop to the next
## over 0.12-0.22 s, so a snowfall that were correct at three sizes and wrong at
## every size in between would trade one pop for a smear of them, and no
## screenshot at rest could tell the two apart.
func _framing_samples() -> Array:
	var stops := _framing_stops()
	stops.sort()
	var samples: Array = []
	for index in range(stops.size()):
		samples.append(float(stops[index]))
		if index + 1 < stops.size():
			# Two along each leg, so "correct at the ends" cannot pass for
			# "correct throughout".
			var low := float(stops[index])
			var high := float(stops[index + 1])
			samples.append(lerpf(low, high, 0.33))
			samples.append(lerpf(low, high, 0.67))
	return samples


## The aspect the capture harness shoots and the widest the game is likely to be
## played at -- the same 16:10 test_a_flake_is_still_in_frame_when_it_dies has
## always used. Hardcoded deliberately: reading it off the layer under test
## would make every assertion below circular.
const FRAME_ASPECT := 1.6


func _frame(height: float) -> Vector2:
	return Vector2(height * FRAME_ASPECT, height)


## The viewport the legibility floor is judged against, in pixels. About a
## thousand tall, which is what snowfall_layer.gd's size bands were reasoned in
## and what the capture harness shoots.
func _pixels() -> Vector2:
	return Vector2(1600.0, 1000.0)


func _surface(layer: SnowfallLayer) -> StandardMaterial3D:
	var mesh: Mesh = layer.draw_pass_1
	if mesh == null:
		return null
	return mesh.surface_get_material(0) as StandardMaterial3D


# --- the three layers -------------------------------------------------------

## THE ONE THAT MATTERS FOR LAYERS 1 AND 2. Particles simulated in the emitter's
## own space travel with the emitter, and this emitter follows the camera: the
## whole field of snow would slide along with the player, which is the one thing
## that cannot happen. Layer 3 is the deliberate opposite -- it is ON the lens.
func test_world_snow_stays_in_the_world_and_lens_snow_rides_the_camera() -> void:
	for path in [DISTANT_SCENE, NEAR_SCENE]:
		var layer := _layer(path)
		assert_false(
			layer.local_coords,
			"%s simulates in local space: the whole snowfall will slide along with "
				% path + "the camera instead of falling past it"
		)
		assert_false(layer.camera_space, "%s is a world layer" % path)
		layer.free()

	var lens := _layer(LENS_SCENE)
	assert_true(
		lens.local_coords,
		"the lens layer must ride the camera; in world space it is left behind the "
			+ "moment the player walks"
	)
	assert_true(lens.camera_space, "the lens layer is a camera layer")
	lens.free()


## The document's three layers, and the reason there are three: they are
## separated by SIZE, because under a parallel projection distance cannot
## separate them.
func test_the_three_layers_are_three_different_sizes() -> void:
	var distant := _layer(DISTANT_SCENE)
	var near := _layer(NEAR_SCENE)
	var lens := _layer(LENS_SCENE)
	assert_true(
		distant.flake_size_max < near.flake_size_max,
		"the distant flake is %f m against the near one's %f: they will read as one layer"
			% [distant.flake_size_max, near.flake_size_max]
	)
	assert_true(
		near.flake_size_max < lens.flake_size_max,
		"the near flake is %f m against the lens flake's %f"
			% [near.flake_size_max, lens.flake_size_max]
	)
	# Section 23's band, and the one number in the document that is a hard count:
	# 30-60 in front of the lens. More is a windscreen, fewer never crosses.
	assert_true(
		lens.flakes_blizzard >= 30 and lens.flakes_blizzard <= 60,
		"%d flakes in front of the lens; the document asks for 30-60" % lens.flakes_blizzard
	)
	assert_true(
		distant.flakes_blizzard > near.flakes_blizzard,
		"the distant layer carries %d flakes against the near layer's %d"
			% [distant.flakes_blizzard, near.flakes_blizzard]
	)
	distant.free()
	near.free()
	lens.free()


## THE STORM IS MORE SNOW, AND IT COSTS NO REALLOCATION.
##
## `amount` re-allocates the particle buffer, so driving density through it would
## empty the sky on every frame of an eight-second lighting crossfade. The count
## is allocated once at the blizzard figure and `amount_ratio` -- which does not
## restart anything -- carries the weather.
func test_the_storm_puts_more_flakes_in_the_air_without_restarting_them() -> void:
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		layer.set_snowfall_rate(0.0)
		layer._apply()
		var clear_buffer: int = layer.amount
		var clear_alive: int = layer.flakes_alive()

		layer.set_snowfall_rate(1.0)
		layer._apply()
		assert_true(
			layer.flakes_alive() > clear_alive,
			"%s keeps %d flakes in a blizzard against %d on a clear day"
				% [path, layer.flakes_alive(), clear_alive]
		)
		assert_eq(
			layer.amount, clear_buffer,
			"%s re-allocated its particle buffer to change density: every flake in "
				% path + "the air disappears on the frame the weather moves"
		)
		assert_true(clear_alive > 0, "%s stops snowing entirely when clear" % path)
		layer.free()


## 风大 -> 足迹速消. The wind is the other half of the storm, and it is what makes
## a blizzard read as one: snow that falls straight down in a gale is a shower.
##
## THE DRIFT IS A VELOCITY AND NOT AN ACCELERATION, which is the one place this
## deliberately departs from the style document. A sideways acceleration
## integrates twice over a lifetime of up to fourteen seconds and carries every
## flake clean out of the frame -- measured, on the first lens screenshot, where
## the flakes were only ever visible in the top third of the picture because they
## had left it sideways before they could fall through it. A blown flake travels
## at a constant slant; that is what these assert.
func test_the_storm_drives_the_snow_sideways() -> void:
	var layer := _layer(NEAR_SCENE)
	layer.set_snowfall_rate(0.0)
	layer._apply()
	var calm: Vector3 = layer.birth_velocity()
	layer.set_snowfall_rate(1.0)
	layer._apply()
	var storm: Vector3 = layer.birth_velocity()
	assert_true(
		absf(storm.x) > absf(calm.x),
		"the blizzard drifts at %f m/s across against the clear day's %f" % [storm.x, calm.x]
	)
	assert_true(
		calm.y < 0.0 and storm.y < 0.0,
		"the snow must fall: clear %f, storm %f m/s" % [calm.y, storm.y]
	)
	# And the slant itself, which is what a screenshot shows. Past about 45
	# degrees the snow reads as being blown horizontally rather than as falling.
	var slant := absf(storm.x) / absf(storm.y)
	assert_true(
		slant > 0.15 and slant < 1.0,
		"the blizzard falls at a slant of %f across per down" % slant
	)
	layer.free()


## The corollary, and the reason the fix above was not simply "use a smaller
## number": a flake has to still be in the picture at the end of its life. It is
## the same arithmetic in both axes -- speed times lifetime against the size of
## the frame -- and getting it wrong is invisible in a still, because the flakes
## that left are not in the shot to be counted.
##
## Checked at every framing rather than at one. With the emission volume and the
## fall both derived from the frame this is invariant by construction -- which is
## the point, and is exactly the property that has to be pinned rather than
## assumed.
func test_a_flake_is_still_in_frame_when_it_dies() -> void:
	for height in _framing_samples():
		# The frame is as wide as it is tall times the aspect; 16:10 is what the
		# capture harness shoots and the widest the game is likely to be played at.
		var frame: Vector2 = _frame(height)
		for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
			var layer := _layer(path)
			layer.set_frame_size(frame)
			layer.set_snowfall_rate(1.0)
			layer._apply()
			var material := layer.process_material as ParticleProcessMaterial
			var across: float = (
				material.direction.x * material.initial_velocity_max * layer.life_seconds
			)
			var fed_from: float = material.emission_box_extents.x * 2.0
			assert_true(
				absf(across) < frame.x + fed_from,
				"%s blows its flakes %.1f m sideways in one life, out of a %.1f m frame "
					% [path, across, frame.x] + "that is fed from a %.1f m box" % fed_from
			)
			layer.free()


## THE WIND HOOK, checked as a hook. src/systems/wind_system.gd is Wave 3 and
## does not exist; this is where it connects, and until it does the snow must
## already be drifting on its own rather than waiting.
func test_the_wind_hook_reaches_the_flake_and_the_snow_drifts_without_it() -> void:
	var layer := _layer(NEAR_SCENE)
	layer.set_snowfall_rate(0.5)
	layer._apply()
	assert_true(
		absf(layer.birth_velocity().x) > 0.0,
		"the snow falls dead straight with nothing driving it: it is waiting for a "
			+ "wind system that does not exist yet"
	)
	# A gust is a CHANGE to a flake already falling, so the hook arrives as an
	# acceleration, on gravity, in the vocabulary BreathFog.set_wind() uses.
	var still: Vector3 = layer.process_material.gravity
	layer.set_wind(Vector3(4.0, 0.0, 0.0))
	layer._apply()
	assert_true(
		layer.process_material.gravity.x > still.x,
		"set_wind() left the flake drifting at %f, exactly as it did in still air"
			% layer.process_material.gravity.x
	)
	layer.free()


## Art Bible rule 12: warm pixels are for fire, windows, beacons, the scarf and
## the truck. Snow is not on that list, and a snowflake is the easiest thing in
## the frame to make accidentally cream-coloured.
func test_the_flake_is_cool_white_and_never_warm() -> void:
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		var surface := _surface(layer)
		assert_not_null(surface, "%s draws no flake at all" % path)
		if surface != null:
			var albedo: Color = surface.albedo_color
			assert_true(
				albedo.b >= albedo.g and albedo.g >= albedo.r,
				"%s draws a flake at (%f, %f, %f) -- warm, and rule 12 does not list snow"
					% [path, albedo.r, albedo.g, albedo.b]
			)
		layer.free()


## GLOW BELONGS TO THE WARM SOURCES -- the lit window, the firebox, the beacon.
## Snow catching the bloom reads as cheap, and it is the easiest thing in the
## frame to do it by accident: a white billboard at full alpha clears any
## threshold under 1.0 on its own.
##
## The threshold is LightingDirector's `glow_hdr_threshold`, copied rather than
## read, and that is a compromise rather than a preference: building a
## LightingDirector to ask it costs an engine error on this working tree that has
## nothing to do with snow (see the report), and a test that adds noise to the
## console is worse than a test that names its number.
const GLOW_HDR_THRESHOLD := 0.95


func test_the_flake_stays_under_the_bloom_threshold() -> void:
	var threshold := GLOW_HDR_THRESHOLD
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		var surface := _surface(layer)
		assert_not_null(surface, "%s draws no flake at all" % path)
		if surface != null:
			# What the compositor sees: the albedo in LINEAR space, which is where
			# the threshold is measured, times the most alpha the flake ever has.
			var linear: Color = surface.albedo_color.srgb_to_linear()
			var peak: float = maxf(maxf(linear.r, linear.g), linear.b) * surface.albedo_color.a
			assert_true(
				peak < threshold,
				"%s peaks at %f against a bloom threshold of %f: the snow will glow, and "
					% [path, peak, threshold] + "glow belongs to the fire and the windows"
			)
			assert_eq(
				surface.blend_mode, BaseMaterial3D.BLEND_MODE_MIX,
				"%s blends additively, which is a glow by another name" % path
			)
		layer.free()


## Art Bible rule 8's banned list. Unshaded is the whole of it in one property:
## no specular, no roughness, no reflection, nothing to tune off later.
func test_the_flake_acquires_no_specular_or_roughness() -> void:
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		var surface := _surface(layer)
		assert_not_null(surface, "%s draws no flake at all" % path)
		if surface != null:
			assert_eq(
				surface.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED,
				"%s is shaded, and rule 8 bans specular and roughness outright" % path
			)
		layer.free()


## THE ORTHOGRAPHIC TRAP. The frame is 10.5 m tall over about a thousand pixels,
## so a metre is roughly a hundred pixels and the document's numbers -- written
## for a perspective camera where distant snow shrinks -- have to be read as
## screen sizes here. Under two pixels is not a flake, it is noise.
##
## The AUTHORED sizes, at the framing they were authored for -- that the art is
## sane before any floor rescues it. What happens to a world flake as the frame
## widens is physical scaling and is guarded separately, by the floor test.
##
## The lens flake is checked at EVERY framing, because it is the one the style
## document says matters and it is the one whose pixels are meant to be constant.
func test_every_flake_is_big_enough_to_read_at_gameplay_framing() -> void:
	var viewport := _pixels()
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		layer.set_snowfall_rate(1.0)
		layer.set_frame_size(layer.authored_frame)
		layer.set_frame_pixels(viewport)
		layer._apply()
		var authored: float = (
			layer.flake_size_max * viewport.y / layer.authored_frame.y
		)
		assert_true(
			authored >= layer.min_flake_pixels,
			("%s authors its largest flake at %.1f px at its own framing, under the %.1f "
				+ "px floor: the art is relying on the clamp to be legible at all")
				% [path, authored, layer.min_flake_pixels]
		)
		layer.free()

	# A lens flake has to be seen crossing the frame, not inferred -- at every
	# framing, since holding that is the whole reason it is a camera-space layer.
	for height in _framing_samples():
		var lens := _layer(LENS_SCENE)
		lens.set_snowfall_rate(1.0)
		lens.set_frame_size(_frame(height))
		lens.set_frame_pixels(viewport)
		lens._apply()
		var drawn: float = (lens.process_material as ParticleProcessMaterial).scale_max
		var pixels: float = drawn * viewport.y / height
		assert_true(
			pixels >= 9.0,
			"the lens flake is %.1f px at a %.1f m frame; it is meant to be the one you "
				% [pixels, height] + "notice"
		)
		lens.free()


## TURBULENCE STOPS THE SNOW FALLING, and this test exists because it took a
## wide-frame screenshot and four wrong hypotheses to find that out.
##
## ParticleProcessMaterial's turbulence does not ADD a curl to the velocity, it
## MIXES the velocity toward the noise field by `turbulence_influence`. The field
## has no downward bias, so at an influence of 0.1-0.55 the flakes stop falling
## and mill about inside the box they were born in: measured, at a 40 m framing,
## as a four-metre-tall band of snow that should have been fourteen. Nothing
## about the emitter's own numbers looks wrong while it happens -- the printed
## velocity, lifetime and direction were all exactly as authored.
##
## So the swirl is off, and this is the guard that keeps it off. If a later wave
## wants it back, the influence has to be small enough that the fall survives,
## and this test is where that argument gets written down.
func test_no_layer_hijacks_its_own_fall_with_turbulence() -> void:
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		assert_false(
			(layer.process_material as ParticleProcessMaterial).turbulence_enabled,
			"%s turns turbulence on, which mixes the fall away and leaves the snow "
				% path + "hanging in the air where it was emitted"
		)
		layer.free()


## Two thousand shadow casters, in a game whose shadows are the subject of the
## frame and are already cast at 8192 with four splits. This is the cheapest
## defect on the list and the easiest to ship.
func test_no_flake_casts_a_shadow_or_lights_anything() -> void:
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		assert_eq(
			layer.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s casts shadows: a thousand flakes just entered the shadow map" % path
		)
		assert_eq(
			layer.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"%s contributes to global illumination" % path
		)
		layer.free()


## A GPUParticles3D is culled by its visibility box, not by where its particles
## actually are, so a box smaller than the fall is a snowfall that vanishes the
## moment the emitter's own origin leaves the frame.
func test_the_visibility_box_covers_where_the_flakes_actually_go() -> void:
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		var box: AABB = layer.visibility_aabb
		var half: Vector3 = layer.volume_size * 0.5
		assert_true(
			box.size.x >= layer.volume_size.x and box.size.z >= layer.volume_size.z,
			"%s emits over %s but is culled by a box of %s" % [path, layer.volume_size, box.size]
		)
		assert_true(
			box.position.y <= -half.y,
			"%s emits down to %f but its visibility box starts at %f"
				% [path, -half.y, box.position.y]
		)
		layer.free()


# --- the director -----------------------------------------------------------

## GDD section 4: day 7 is the whiteout and days 1-2 are safe. The six presets
## already switch per day, so the weather is wired to what exists rather than to
## a weather system that is three waves away.
func test_the_whiteout_is_a_blizzard_and_the_pale_day_is_nearly_clear() -> void:
	var director := _director()
	var lighting := FakeLighting.new()
	director.set_lighting(lighting)

	lighting.look = _preset(&"whiteout")
	director.settle()
	var storm: float = director.snowfall_rate()

	lighting.look = _preset(&"pale_day")
	director.settle()
	var calm: float = director.snowfall_rate()

	assert_true(storm >= 0.9, "WHITEOUT snows at %f; day 7 is a blizzard" % storm)
	assert_true(
		calm > 0.0 and calm <= 0.25,
		"PALE DAY snows at %f; it is meant to be nearly clear, not clear and not weather"
			% calm
	)
	assert_true(storm > calm * 3.0, "the storm is only %f times the pale day" % (storm / calm))
	director.free()


## A preset the table has never heard of still snows. The alternative is a new
## look shipping with an empty sky and nothing on screen to say why.
func test_a_preset_nobody_mapped_still_snows() -> void:
	var director := _director()
	var lighting := FakeLighting.new()
	director.set_lighting(lighting)
	lighting.look = _preset(&"an_unmapped_look")
	director.settle()
	assert_true(
		director.snowfall_rate() > 0.0,
		"an unmapped preset leaves the sky empty at %f" % director.snowfall_rate()
	)
	director.free()


## THE WEATHER HOOK. src/systems/weather_system.gd is Wave 3. When it arrives it
## takes the wheel from the lighting preset; until then the preset drives, and
## the snow is never inert.
func test_the_weather_hook_takes_the_wheel_from_the_lighting() -> void:
	var director := _director()
	var lighting := FakeLighting.new()
	director.set_lighting(lighting)
	lighting.look = _preset(&"pale_day")
	director.settle()
	var from_preset: float = director.snowfall_rate()

	director.set_snowfall_rate(1.0)
	director.settle()
	assert_true(
		director.snowfall_rate() > from_preset,
		"set_snowfall_rate() was overruled by the lighting preset: %f"
			% director.snowfall_rate()
	)
	assert_eq(director.target_snowfall_rate(), 1.0, "the target is what was asked for")
	director.free()


## The lighting crossfades over eight seconds and reports the preset it is
## BECOMING from the first frame of it, so a snowfall that read that directly
## would snap to blizzard the instant the clock struck. Weather arrives.
func test_the_weather_arrives_rather_than_snapping() -> void:
	var director := _director()
	var lighting := FakeLighting.new()
	director.set_lighting(lighting)
	lighting.look = _preset(&"pale_day")
	director.settle()
	var before: float = director.snowfall_rate()

	lighting.look = _preset(&"whiteout")
	director._process(0.1)
	var after_a_frame: float = director.snowfall_rate()
	assert_true(
		after_a_frame > before,
		"a tenth of a second of storm moved nothing: %f" % after_a_frame
	)
	assert_true(
		after_a_frame < 0.5,
		"a tenth of a second took the snow to %f: the sky filled in one frame"
			% after_a_frame
	)
	director.free()


## ...AND THE OTHER HALF OF THAT RULE: when the lighting CUTS, the weather cuts
## with it. Art Bible section 4.2's six hotkeys snap a preset on outright, and so
## does tools/capture_frame.gd at the shutter -- both exist to answer "what does
## this look like at midnight" without playing four days to find out, and both
## would answer it with the wrong weather if the snow spent six seconds easing
## into a frame that was captured one frame later.
func test_the_weather_cuts_when_the_lighting_cuts() -> void:
	var director := _director()
	var lighting := FakeLighting.new()
	lighting.crossfading = false
	director.set_lighting(lighting)
	lighting.look = _preset(&"pale_day")
	director.settle()

	lighting.look = _preset(&"whiteout")
	director._process(0.016)
	assert_true(
		director.snowfall_rate() >= 0.9,
		"one frame after the look was CUT to WHITEOUT the sky is at %f: a screenshot "
			% director.snowfall_rate() + "of day 7 would show day 1's weather"
	)
	director.free()


## The hook TrackMask itself named -- see src/systems/track_mask.gd, which
## reserves `set_snowfall_rate` for exactly this and fills footprints in faster
## when it is fed. Both halves are asserted: that the snowfall speaks the word,
## and that the mask still answers to it.
func test_the_snowfall_reaches_the_footprints_by_the_name_the_mask_chose() -> void:
	var mask := TrackMask.new()
	assert_true(
		mask.has_method("set_snowfall_rate"),
		"TrackMask no longer answers to set_snowfall_rate; the snowfall is talking to itself"
	)
	mask.free()

	var director := _director()
	var fake := FakeMask.new()
	director.set_track_mask(fake)
	director.set_snowfall_rate(0.8)
	director.settle()
	assert_almost_eq(
		fake.rate, 0.8, 0.02,
		"the mask was told %f while the sky is at %f" % [fake.rate, director.snowfall_rate()]
	)
	director.free()


## Wind reaches the layers as a velocity, which is what a particle needs, and it
## is still at rest until something drives it -- the snow's own drift is on the
## layer and does not depend on this.
func test_the_wind_hook_is_still_by_default_and_reaches_the_layers_when_driven() -> void:
	var director := _director()
	assert_eq(director.wind_strength(), 0.0, "the wind starts blowing on its own")
	assert_eq(
		director.wind_velocity(), Vector3.ZERO,
		"a still wind is pushing %s at the flakes" % director.wind_velocity()
	)

	var layer := _layer(NEAR_SCENE)
	director.set_wind_strength(1.0)
	assert_true(
		director.wind_velocity().length() > 0.0,
		"a full gale pushes nothing at all"
	)
	director.drive(layer)
	assert_true(
		layer.wind().length() > 0.0,
		"the gale never reached the layer: %s" % layer.wind()
	)
	layer.free()
	director.free()


## The layers are found by group rather than by path, which is the only reason
## the lens layer can live under the camera -- a node this director must never
## hold a reference to, because two other systems are already inside it.
func test_a_layer_publishes_itself_where_the_director_looks() -> void:
	var layer := _layer(LENS_SCENE)
	assert_true(
		layer.is_in_group(SnowfallLayerScript.GROUP),
		"the layer is not in group '%s'" % SnowfallLayerScript.GROUP
	)
	assert_eq(
		SnowfallScript.LAYER_GROUP, SnowfallLayerScript.GROUP,
		"the director looks for '%s' and the layers join '%s'"
			% [SnowfallScript.LAYER_GROUP, SnowfallLayerScript.GROUP]
	)
	layer.free()


## THE GEOMETRY, and the reason it is arithmetic rather than a transform: under a
## parallel projection, sliding a point along the view axis does not move it on
## screen at all. That is what lifts the volume into the air without taking it
## out of frame -- a world-vertical offset at a 45 degree pitch would put it a
## long way above the top of the picture.
func test_the_volume_sits_over_what_the_camera_is_looking_at() -> void:
	# The rig, exactly as CameraRig builds it: pitched 45, on a 90 m boom.
	var rig: CameraRig = CameraRigScript.new()
	var pitch: float = deg_to_rad(rig.pitch_degrees)
	var yaw: float = deg_to_rad(rig.yaw_degrees)
	var boom: float = rig.boom_length
	rig.free()

	var basis := Basis.from_euler(Vector3(-pitch, yaw, 0.0))
	var forward: Vector3 = -basis.z
	var focus := Vector3(4.0, 1.0, -7.0)
	var camera_position: Vector3 = focus - forward * boom

	var centre: Vector3 = SnowfallScript.volume_centre(camera_position, forward, focus.y, 0.0)
	assert_almost_eq(centre.x, focus.x, 0.01, "the volume is not over the frame in x")
	assert_almost_eq(centre.z, focus.z, 0.01, "the volume is not over the frame in z")
	assert_almost_eq(centre.y, focus.y, 0.01, "the volume is not on the ground with no pullback")

	# Backed up the view axis, the volume rises. At a 45 degree pitch it rises by
	# sin(45) of the pullback, and it stays exactly where it was on screen.
	var raised: Vector3 = SnowfallScript.volume_centre(camera_position, forward, focus.y, 20.0)
	assert_true(
		raised.y > centre.y + 10.0,
		"a 20 m pullback lifted the volume only %f m" % (raised.y - centre.y)
	)
	var screen_right := Vector3(0.8192, 0.0, 0.5736)
	assert_almost_eq(
		(raised - centre).dot(screen_right), 0.0, 0.01,
		"the pullback slid the volume sideways across the frame"
	)


## THE HIGHEST THE GROUND CAN GET: the deepest drift on the tallest rise. Read
## off SnowField rather than written down here -- a copy would go stale the first
## time somebody retuned the relief, and it would go stale in silence.
func _snow_ceiling() -> float:
	var field = SnowFieldScript.new()
	var ceiling: float = field.terrain_amplitude_m + field.max_depth_m
	field.free()
	return ceiling


## Where the camera looks, as a unit vector. The pitch is the rig's, so a change
## of camera moves this test with it.
func _view_forward() -> Vector3:
	var rig: CameraRig = CameraRigScript.new()
	var basis := Basis.from_euler(
		Vector3(-deg_to_rad(rig.pitch_degrees), deg_to_rad(rig.yaw_degrees), 0.0)
	)
	rig.free()
	return -basis.z


## WHERE A FLAKE IS BORN, AGAINST WHERE THE GROUND CAN BE.
##
## `SnowNear` shipped with the floor of its birth box at y = -0.83 -- below world
## zero, and 3.8 m below the highest surface SnowField can present. Flakes were
## being born INSIDE the hill: alive, simulating, drawn nowhere, and invisible
## from birth for the whole of a seven-second life. Measured on the near layer,
## the loss was 5.3% of the buffer born underground, and hiding the terrain
## revealed 17% more of the layer's ink at any instant.
##
## Nothing failed. The layer emitted its full count, every printed number was
## correct, and the only symptom was a layer quietly drawing less snow than it
## was authored to -- which reads as tuning rather than as a defect, and which is
## why it survived two waves.
##
## THE FIX IS SPENT ON `pullback_m`, WHICH IS WHY IT IS FREE. Under a parallel
## projection, sliding a volume along the view axis does not move it on screen at
## all, so the box lifts clear of the terrain without the snow moving a pixel. A
## world-vertical lift would have carried it out of the top of the picture.
##
## Asserted across every framing, because `geometry_scale()` scales the pullback
## and the box together and a guarantee that held only at the authored frame
## would be no guarantee at all.
func test_no_world_layer_is_born_inside_the_ground() -> void:
	var ceiling := _snow_ceiling()
	var forward := _view_forward()
	var director := _director()
	var camera_position := Vector3(0.0, 90.0, 0.0)
	for path in [DISTANT_SCENE, NEAR_SCENE]:
		var layer := _layer(path)
		for height in _framing_samples():
			layer.set_frame_size(_frame(float(height)))
			var centre: Vector3 = SnowfallScript.volume_centre(
				camera_position, forward, director.ground_height, director.pullback_for(layer)
			)
			var bottom: float = centre.y - layer.emission_extents().y
			assert_true(
				bottom >= ceiling,
				"%s is born from y=%.2f at a %.1f m frame, and the snow surface reaches %.2f"
					% [path.get_file(), bottom, float(height), ceiling]
			)
		layer.free()
	director.free()


## ...and the reason that fix is worth anything: a flake that meets the snow
## surface is DELETED by the depth buffer at whatever opacity it had, which is
## precisely the abrupt disappearance the fade ramp exists to prevent. The ramp
## was running underground.
##
## SO THE ASSERTION IS ABOUT THE RAMP GETTING ANY OF THE BUFFER AT ALL, and the
## bar is taken from the ramp itself rather than picked: a layer should give the
## fade at least as large a share of its BIRTH BOX as the ramp gives it of a LIFE.
## `FADE_OUT_FRACTION` is 18% of a life; the near layer was handing it 5.9% of the
## box, and after the lift it hands it 21.9%.
##
## ---------------------------------------------------------------------------
## AND IT DELIBERATELY DOES NOT ASK THAT THE FADE FINISH, BECAUSE IT CANNOT
## ---------------------------------------------------------------------------
## The box's height was authored AS the distance a flake falls in one life --
## 24.3 m of box against 24.3 m of fall on the near layer, 35.6 against 35.2 on
## the distant one. A flake born at the floor therefore always ends its life a
## whole box-height lower, so the share that completes its ramp above the surface
## is (box_top - surface - fall) / box_height, which is near zero wherever the box
## is put. Lifting it far enough to fix that would stand the box 25 m up and take
## the near snow out of the picture entirely.
##
## Measured against the worst surface the field can present, the lift moved
## "finishes the fade" from 0.0% to 0.2%. That is not the fix and is not claimed
## as one. The rest of that handoff -- a flake decelerating near the surface and
## being absorbed into the ground sheet rather than deleted by the depth buffer --
## needs a per-particle response to the terrain height, which is a particle
## process shader, and is not this.
func test_the_fade_ramp_gets_a_real_share_of_the_birth_box() -> void:
	var ceiling := _snow_ceiling()
	var forward := _view_forward()
	var director := _director()
	var camera_position := Vector3(0.0, 90.0, 0.0)
	var share: float = SnowfallLayerScript.FADE_OUT_FRACTION
	for path in [DISTANT_SCENE, NEAR_SCENE]:
		var layer := _layer(path)
		layer.set_frame_size(layer.authored_frame)
		var centre: Vector3 = SnowfallScript.volume_centre(
			camera_position, forward, director.ground_height, director.pullback_for(layer)
		)
		var half: float = layer.emission_extents().y
		var life: float = layer.life_seconds
		# How far a flake has fallen by the moment its ramp begins, at the storm's
		# speed plus the sag. Derived from the ramp rather than from a literal, so
		# retuning the ramp moves this test with it.
		var to_fade: float = life * (1.0 - share)
		var fallen: float = layer.fall_speed_blizzard * to_fade \
			+ 0.5 * layer.fall_accel * to_fade * to_fade
		var reaching: float = clampf(
			(centre.y + half - ceiling - fallen) / maxf(2.0 * half, 0.001), 0.0, 1.0
		)
		assert_true(
			reaching >= share,
			"%s: only %.1f%% of the birth box reaches the fade before the snow "
				% [path.get_file(), 100.0 * reaching]
				+ "surface at %.2f m, against a ramp that occupies %.0f%% of a life"
				% [ceiling, 100.0 * share]
		)
		layer.free()
	director.free()


## A camera that is not looking down never meets the ground, and the arithmetic
## for where it does divides by exactly that. The frame stays snowy rather than
## sending the volume to infinity.
func test_a_level_camera_does_not_send_the_snow_to_infinity() -> void:
	var centre: Vector3 = SnowfallScript.volume_centre(
		Vector3(0.0, 3.0, 0.0), Vector3(1.0, 0.0, 0.0), 1.0, 10.0
	)
	assert_true(
		centre.length() < 1000.0,
		"a level camera put the snow at %s" % centre
	)


# --- the frame the camera is actually drawing -------------------------------
#
# The snowfall was tuned against an orthographic camera at one size, because at
# the time that was the only framing there was. The camera now cycles through
# three on Shift+wheel and EASES between them, and a later wave will modulate the
# frame on top of the player's choice through CameraRig's ModifierStack.
#
# So none of the tests below names a size. They ask CameraRig which framings
# exist, and they ask at the places BETWEEN them too, because the frame spends
# the length of every zoom there: a snowfall that were right at three sizes and
# wrong at every size in between would trade one visible pop for a smear of them.


## SYMPTOM 1, AND THE WORST OF THE THREE: a flake has to drift INTO the picture.
## A birth band that has slipped inside the frame is snow appearing out of
## nothing in the middle of the shot, which reads as a bug to anyone watching
## rather than as weather.
##
## The margin is not a taste. A flake spends the first FADE_IN_FRACTION of its
## life fading up from nothing and it is falling the whole time, so the band has
## to clear the top edge by at least that far or the fade finishes on screen --
## which is the same pop, one step softer.
func test_the_lens_birth_band_never_starts_inside_the_picture() -> void:
	var lens := _layer(LENS_SCENE)
	# The blizzard, which is the fast case and therefore the demanding one: a
	# flake that falls harder has less of its fade left when it arrives.
	lens.set_snowfall_rate(1.0)
	for height in _framing_samples():
		lens.set_frame_size(_frame(height))
		lens._apply()
		var material := lens.process_material as ParticleProcessMaterial
		var bottom: float = (
			lens.position.y + material.emission_shape_offset.y - material.emission_box_extents.y
		)
		var top_edge: float = height * 0.5
		var fade_fall: float = (
			absf(lens.birth_velocity().y)
			* lens.flake_scale()
			* lens.life_seconds
			* SnowfallLayerScript.FADE_IN_FRACTION
		)
		assert_true(
			bottom >= top_edge + fade_fall,
			("a %.1f m frame reaches %.2f m and the lens snow is born from %.2f m, which "
				+ "is %.2f m of clearance against the %.2f m a flake falls while it is "
				+ "still fading up: it appears on screen")
				% [height, top_edge, bottom, bottom - top_edge, fade_fall]
		)
	lens.free()


## SYMPTOM 2. The emission box has to be at least as wide as the picture, or one
## side of the frame has no lens snow crossing it at all -- invisible in a still
## and obvious the moment anything moves.
##
## It also has to overhang, and the overhang belongs on the side the drift blows
## FROM: a flake that crosses the frame sideways has to have come from somewhere
## off the edge of it.
func test_the_lens_snow_reaches_both_edges_of_the_picture() -> void:
	var lens := _layer(LENS_SCENE)
	lens.set_snowfall_rate(1.0)
	for height in _framing_samples():
		var frame: Vector2 = _frame(height)
		lens.set_frame_size(frame)
		lens._apply()
		var material := lens.process_material as ParticleProcessMaterial
		var centre: float = lens.position.x + material.emission_shape_offset.x
		var half: float = material.emission_box_extents.x
		var edge: float = frame.x * 0.5
		var bare: float = maxf(0.0, (centre - half) - (-edge)) + maxf(0.0, edge - (centre + half))
		assert_true(
			centre - half <= -edge and centre + half >= edge,
			("a %.1f m frame is %.1f m wide and the lens snow is born between %.1f and "
				+ "%.1f: %.1f m of the picture never sees a lens flake")
				% [height, frame.x, centre - half, centre + half, bare]
		)
		# And the run-up, on the upwind side. Which side that is comes off the
		# drift rather than out of the scene file, so a layer re-authored to blow
		# the other way does not quietly lose it.
		var upwind: float = -signf(lens.drift_blizzard.x)
		if upwind < 0.0:
			assert_true(
				centre - half < -edge,
				("the lens box starts exactly at the left edge of a %.1f m frame, so a "
					+ "flake drifting in from the left has nowhere to come from") % height
			)
		elif upwind > 0.0:
			assert_true(
				centre + half > edge,
				"the lens box ends exactly at the right edge of a %.1f m frame" % height
			)

	# THE TRIPWIRE. A camera-space layer DERIVES its width, so the authored
	# volume_size.x is never read -- which would make it a dead number nobody
	# could trust, and the next person to edit it would change nothing and not
	# find out. At the frame the layer was authored against, the derivation has to
	# come to exactly what the scene file says it does.
	lens.set_frame_size(lens.authored_frame)
	lens._apply()
	var authored_span: float = (
		(lens.process_material as ParticleProcessMaterial).emission_box_extents.x * 2.0
	)
	assert_almost_eq(
		authored_span, lens.volume_size.x, 0.001,
		("the lens box works out to %.2f m at its own authored frame while the scene "
			+ "file says %.2f: the picture, the run-up and the margin no longer add up "
			+ "to the box the file describes")
			% [authored_span, lens.volume_size.x]
	)
	lens.free()


## SYMPTOM 3, AND THE RULING ON IT. The camera has three framings and a flake has
## to answer to one of two rules, decided by which side of the lens it is on:
##
##   * A WORLD flake is a physical object. Zooming out must make it smaller on
##     screen, exactly as it makes the trees and the character smaller. Its size
##     in METRES is the constant. A world flake that held its share of the screen
##     would grow fatter as the player pulled back, and how hard it is snowing --
##     a fact about the world -- would appear to change when he touched nothing
##     but the camera.
##   * A LENS flake is a camera-space effect standing in for snow at the glass. It
##     is not in the world and does not zoom with it. Its size in PIXELS is the
##     constant.
##
## What shipped was neither rule: metres held constant on all three, which is
## right for the two world layers by accident and wrong for the lens layer, whose
## 17 px flake had shrunk to 10.6 at the widest framing.
func test_a_world_flake_keeps_its_metres_and_a_lens_flake_keeps_its_pixels() -> void:
	var viewport := _pixels()
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		layer.set_snowfall_rate(1.0)
		var first_metres := -1.0
		var first_pixels := -1.0
		for height in _framing_samples():
			layer.set_frame_size(_frame(height))
			layer.set_frame_pixels(viewport)
			layer._apply()
			# The size the layer WANTS, before the legibility floor clamps it --
			# the floor is a separate rule and has its own test.
			var metres: float = (
				layer.flake_size_max * layer.flake_scale() * lerpf(0.82, 1.0, 1.0)
			)
			var on_screen: float = metres * viewport.y / height
			if first_metres < 0.0:
				first_metres = metres
				first_pixels = on_screen
			if layer.camera_space:
				assert_almost_eq(
					on_screen, first_pixels, 0.01,
					("%s is on the lens and draws its largest flake %.1f px at a %.1f m "
						+ "frame against %.1f px at the tightest: a camera-space effect "
						+ "does not zoom") % [path, on_screen, height, first_pixels]
				)
			else:
				assert_almost_eq(
					metres, first_metres, 0.0001,
					("%s is in the world and its largest flake is %.3f m at a %.1f m frame "
						+ "against %.3f m at the tightest: a snowflake does not change size "
						+ "because the camera moved") % [path, metres, height, first_metres]
				)
				assert_true(
					height <= _framing_samples()[0] + 0.001 or on_screen < first_pixels,
					("%s holds %.1f px at a %.1f m frame, the same as at the tightest: a "
						+ "world flake that keeps its share of the screen gets fatter as "
						+ "the player pulls back") % [path, on_screen, height]
				)
		layer.free()


## THE LEGIBILITY FLOOR, which is what physical scaling runs into. Below about
## two and a half pixels a flake is not a flake, it is a sub-pixel sample that
## shimmers as it crosses the frame -- video noise where the art direction asked
## for the texture of the air. So the drawn size is clamped at the floor even
## though that draws a distant speck slightly larger than it honestly is.
func test_no_flake_is_ever_drawn_below_the_legibility_floor() -> void:
	var viewport := _pixels()
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		layer.set_snowfall_rate(1.0)
		for height in _framing_samples():
			layer.set_frame_size(_frame(height))
			layer.set_frame_pixels(viewport)
			layer._apply()
			var material := layer.process_material as ParticleProcessMaterial
			var smallest: float = material.scale_min * viewport.y / height
			assert_true(
				smallest >= layer.min_flake_pixels - 0.001,
				"%s draws its smallest flake at %.2f px at a %.1f m frame, under its own "
					% [path, smallest, height] + "%.1f px floor" % layer.min_flake_pixels
			)
		layer.free()

	# ...and the floor is switched OFF, not guessed at, when nobody has said how
	# big the viewport is. A floor converted through an assumed resolution is a
	# guess wearing a measurement's clothes.
	var unframed := _layer(DISTANT_SCENE)
	unframed.set_frame_size(_frame(17.0))
	unframed._apply()
	assert_eq(
		unframed.legibility_floor_m(), 0.0,
		"a layer with no viewport invented a %f m floor" % unframed.legibility_floor_m()
	)
	unframed.free()


## AND WHAT HAPPENS WHEN THE FLOOR IS NOT ENOUGH. Clamping a small flake up is a
## small lie. Once even the LARGEST flake in a layer is under the floor, every
## flake is the same clamped size and not one is the size it should be -- the lie
## is the whole layer. A layer that can no longer draw a flake honestly should
## stop drawing rather than alias, so it fades out.
func test_a_layer_that_can_no_longer_draw_a_flake_honestly_fades_out() -> void:
	var viewport := _pixels()
	# No layer may be fading at any framing the camera can currently reach, AT ANY
	# WEATHER: the fade is a guard against a framing nobody has authored yet, not
	# something the player can provoke with the scroll wheel.
	#
	# Both ends of the weather, because a clear day authors a smaller flake than a
	# blizzard and the two used to stack -- which took the distant layer to 57%
	# faded at the widest framing on a 1280x800 window, measured. The fade answers
	# a question about the camera, so the weather is not allowed into it.
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		for rate in [0.0, 1.0]:
			var layer := _layer(path)
			layer.set_snowfall_rate(float(rate))
			for height in _framing_samples():
				layer.set_frame_size(_frame(height))
				layer.set_frame_pixels(viewport)
				layer._apply()
				assert_eq(
					layer.transparency, 0.0,
					("%s is %.0f%% faded out at a %.1f m frame in weather %.1f, and that "
						+ "is a framing the player can actually reach")
						% [path, layer.transparency * 100.0, height, float(rate)]
				)
			layer.free()

	# Driven past what any stop asks for, a world layer leaves -- and it leaves on
	# a ramp rather than a switch, or the disappearance is its own pop.
	var distant := _layer(DISTANT_SCENE)
	distant.set_snowfall_rate(1.0)
	distant.set_frame_pixels(viewport)
	var honest: float = distant.flake_size_max
	# The frame at which the largest flake lands exactly on the floor, and the one
	# at which it has fallen a full octave below it. Derived from the layer's own
	# numbers rather than named, so this test moves when the art does.
	var at_floor: float = honest * viewport.y / distant.min_flake_pixels
	var fully_gone: float = at_floor / SnowfallLayerScript.FADE_OUT_OCTAVE
	for pair in [[at_floor, 0.0], [fully_gone, 1.0]]:
		distant.set_frame_size(_frame(float(pair[0])))
		distant._apply()
		assert_almost_eq(
			distant.transparency, float(pair[1]), 0.01,
			"at a %.1f m frame the distant layer is %.2f transparent, wanted %.2f"
				% [float(pair[0]), distant.transparency, float(pair[1])]
		)
	distant.set_frame_size(_frame(lerpf(at_floor, fully_gone, 0.5)))
	distant._apply()
	assert_true(
		distant.transparency > 0.05 and distant.transparency < 0.95,
		("halfway past the floor the distant layer is %.2f transparent: it is switching "
			+ "off rather than fading, and a layer that vanishes in one frame is its own "
			+ "pop") % distant.transparency
	)
	var widest: float = _framing_samples()[_framing_samples().size() - 1]
	assert_true(
		at_floor > widest,
		("the distant layer would begin fading at a %.1f m frame against a widest stop "
			+ "of %.1f: the guard is inside the range the camera already offers")
			% [at_floor, widest]
	)
	# AND THE RESOLUTION THIS DEPENDS ON, stated rather than left implicit. The
	# floor is a pixel fact, so the headroom shrinks with the window: this is the
	# viewport height at which the widest stop would begin fading the layer, and
	# it is the number to watch if a wider stop is ever added.
	var fades_at_pixels: float = widest * distant.min_flake_pixels / honest
	assert_true(
		fades_at_pixels < 800.0,
		("the distant layer begins to fade at the widest stop on any window under %.0f "
			+ "px tall, which is a window people actually use") % fades_at_pixels
	)
	distant.free()


## THE TRANSITION, which is the case no screenshot at rest can show. CameraRig
## does not jump between stops, it eases over 0.12-0.22 s on a cubic or quintic
## curve, so the frame spends every zoom at a size that is not any stop at all.
##
## A snowfall that sampled the framing once, when the stop changed, would be
## correct in all three screenshots and wrong for the whole of every zoom. What
## this pins is exactly that difference: the geometry has to be STRICTLY between
## the two ends when the frame is, not merely equal to one of them.
##
## The LENS layer is what has to track, and it is the only one that can get this
## wrong: a world box is a fixed volume of air, so there is nothing in it that
## follows the frame and therefore nothing that can lag behind one. The test that
## pins that is test_the_lens_box_tracks_the_frame_and_a_world_box_holds_a_volume_of_air.
func test_the_snow_tracks_the_frame_between_the_stops_and_not_only_at_them() -> void:
	var stops := _framing_stops()
	stops.sort()
	assert_true(
		stops.size() >= 2,
		"the rig offers %d framing(s); there is no zoom to track" % stops.size()
	)
	for path in [LENS_SCENE]:
		var layer := _layer(path)
		layer.set_snowfall_rate(1.0)
		for index in range(stops.size() - 1):
			var low: float = float(stops[index])
			var high: float = float(stops[index + 1])
			var at_low: float = _emission_reach(layer, low)
			var at_high: float = _emission_reach(layer, high)
			var midway: float = _emission_reach(layer, lerpf(low, high, 0.5))
			assert_true(
				at_high > at_low,
				("%s emits over %.2f m at a %.1f m frame and %.2f m at a %.1f m one: the "
					+ "volume does not follow the frame at all")
					% [path, at_low, low, at_high, high]
			)
			assert_true(
				midway > at_low and midway < at_high,
				("%s emits over %.2f m halfway between a %.1f and a %.1f m frame against "
					+ "%.2f and %.2f at the ends: the framing is being sampled at the stops "
					+ "rather than followed through the tween")
					% [path, midway, low, high, at_low, at_high]
			)
		layer.free()


## Half the vertical extent of wherever a layer is currently emitting, as one
## number, so a tween can be watched through it.
func _emission_reach(layer: SnowfallLayer, height: float) -> float:
	layer.set_frame_size(_frame(height))
	layer._apply()
	return (layer.process_material as ParticleProcessMaterial).emission_box_extents.y


## THE TRAP UNDERNEATH THE FIX. The lens layer simulates in LOCAL space -- it has
## to, it rides the camera -- and a local-space emitter carries every particle
## already in flight along with it when it moves. Placing the birth band by
## moving the node would therefore drag the whole lens snowfall up the screen for
## the length of every zoom: one pop at one framing, traded for a smear during
## all of them.
##
## The band moves through the process material's own emission offset instead,
## which reaches only the flakes not yet born.
func test_the_lens_emitter_never_moves_so_flakes_in_flight_are_not_dragged() -> void:
	var lens := _layer(LENS_SCENE)
	var anchored: Vector3 = lens.position
	var offsets: Array[float] = []
	for height in _framing_samples():
		lens.set_frame_size(_frame(height))
		lens._apply()
		assert_eq(
			lens.position, anchored,
			"the lens emitter moved to %s for a %.1f m frame; every flake in the air went "
				% [lens.position, height] + "with it"
		)
		offsets.append((lens.process_material as ParticleProcessMaterial).emission_shape_offset.y)
	assert_true(
		offsets[offsets.size() - 1] > offsets[0],
		"the birth band sat at %.2f m at every framing: it is not tracking the frame"
			% offsets[0]
	)
	lens.free()


## THE EMISSION BOX, and the two opposite rules it follows either side of the
## lens. This is what stops the storm easing off when the player scrolls a wheel.
##
##   * A LENS box is a statement about the picture, so it tracks the frame: its
##     share of the frame is constant and its metres are not.
##   * A WORLD box is a volume of AIR holding a fixed number of flakes at a fixed
##     density. Its METRES are constant and its share of the frame is not: a
##     tighter frame simply sees less of the same field. That is what makes the
##     snow on screen grow as the picture does -- more flakes, each smaller,
##     netting the same ink -- rather than the same flakes getting smaller, which
##     was measured at 62.8% of its coverage at the widest stop.
##
## The world box still grows if the frame outgrows it, because a picture whose
## edges have no snow in them is where this whole task started.
func test_the_lens_box_tracks_the_frame_and_a_world_box_holds_a_volume_of_air() -> void:
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		var first_share := -1.0
		var first_metres := -1.0
		for height in _framing_samples():
			layer.set_frame_size(_frame(height))
			layer._apply()
			var material := layer.process_material as ParticleProcessMaterial
			var metres: float = material.emission_box_extents.y
			var share: float = metres / height
			if first_share < 0.0:
				first_share = share
				first_metres = metres
			if layer.camera_space:
				assert_almost_eq(
					share, first_share, 0.0001,
					("%s emits over %.3f frame-heights at a %.1f m frame against %.3f at "
						+ "the tightest: the lens box is not tracking the picture")
						% [path, share, height, first_share]
				)
			else:
				assert_almost_eq(
					metres, first_metres, 0.0001,
					("%s emits over %.2f m at a %.1f m frame against %.2f m at the "
						+ "tightest: a world box is a volume of air and the camera moving "
						+ "must not resize it") % [path, metres, height, first_metres]
				)
		layer.free()

	# ...and it does grow, once the frame is genuinely bigger than the field it
	# was authored to fill. The alternative is bare edges.
	var distant := _layer(DISTANT_SCENE)
	var outgrown: float = distant.authored_frame.y * 2.0
	distant.set_frame_size(_frame(distant.authored_frame.y))
	distant._apply()
	var held: float = (distant.process_material as ParticleProcessMaterial).emission_box_extents.y
	distant.set_frame_size(_frame(outgrown))
	distant._apply()
	var grown: float = (distant.process_material as ParticleProcessMaterial).emission_box_extents.y
	assert_almost_eq(
		grown, held * 2.0, 0.01,
		("a frame twice the field the distant layer was authored to fill left its box at "
			+ "%.2f m against %.2f: the picture would have edges with no snow in them")
			% [grown, held]
	)
	distant.free()


## Where the frame comes from. Not from a copy of CameraRig's stops -- this file
## must never learn them -- but from the size the camera is drawing right now,
## which is where the rig's framing tween lands every frame.
func test_the_snowfall_reads_the_frame_the_camera_is_drawing() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 13.5
	var frame: Vector2 = SnowfallScript.frame_size(camera, Vector2(1600.0, 1000.0))
	assert_almost_eq(frame.y, 13.5, 0.001, "the frame is %.2f m tall, not 13.5" % frame.y)
	assert_almost_eq(
		frame.x, 21.6, 0.001, "a 16:10 viewport makes a 13.5 m frame %.2f m wide" % frame.x
	)

	# KEEP_WIDTH is the other half of the same property, and reading it the wrong
	# way round scales the snow by the aspect ratio rather than by the frame.
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	var wide: Vector2 = SnowfallScript.frame_size(camera, Vector2(1600.0, 1000.0))
	assert_almost_eq(wide.x, 13.5, 0.001, "under KEEP_WIDTH the size is the WIDTH: %.2f" % wide.x)
	assert_almost_eq(wide.y, 8.4375, 0.001, "the frame is %.2f m tall" % wide.y)

	# A perspective camera has no frame height in metres -- it has a different one
	# at every depth -- so there is nothing to scale by, and saying so is better
	# than inventing one.
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	assert_eq(
		SnowfallScript.frame_size(camera, Vector2(1600.0, 1000.0)), Vector2.ZERO,
		"a perspective camera was given a frame height in metres"
	)
	assert_eq(
		SnowfallScript.frame_size(null, Vector2(1600.0, 1000.0)), Vector2.ZERO,
		"no camera at all still produced a frame"
	)
	camera.free()

	# ...and the pixel count comes off the viewport's own size rather than off its
	# visible rect. Under this project's `canvas_items` stretch those are different
	# numbers -- 1152 x 720 of canvas inside a 1280 x 800 window, measured -- and
	# the legibility floor is a fact about the pixels on the glass.
	#
	# The SubViewport branch is exercised here; the Window branch is NOT, and that
	# is deliberate. A Window built outside the tree and freed leaves ten RIDs
	# behind at exit ("10 resources still in use"), which fails the run's cleanliness
	# check for no gain -- the branch is a property read. It was verified by
	# measurement instead, against a real windowed run: window (1280, 800),
	# visible rect (1152, 720), texture (1423, 889), and the PNG the frame actually
	# saved was 1280 x 800. Only the window agreed with the pixels.
	var sub := SubViewport.new()
	sub.size = Vector2i(640, 360)
	assert_eq(
		SnowfallScript.viewport_pixels(sub), Vector2(640.0, 360.0),
		"a SubViewport reports %s pixels" % SnowfallScript.viewport_pixels(sub)
	)
	sub.free()
	assert_eq(
		SnowfallScript.viewport_pixels(null), Vector2.ZERO,
		"no viewport at all still produced a pixel count"
	)


## The director is what carries the frame to the layers, on the same frame and
## through the same call that carries the weather -- so a layer cannot end up
## driven with this frame's snowfall and last frame's framing.
##
## The pullback goes with it. It is how far back up the view axis the volume
## sits, and a volume that grew with the frame while its pullback did not would
## sink into the ground it is meant to be falling onto.
func test_the_director_hands_every_layer_the_frame_and_scales_the_pullback() -> void:
	var director := _director()
	var layer := _layer(NEAR_SCENE)
	var wide: Vector2 = _frame(17.0)
	director.set_frame_size(wide)
	director.set_frame_pixels(_pixels())
	director.drive(layer)
	assert_eq(
		layer.frame_size(), wide,
		"the director drove the layer without telling it what it is drawing into: %s"
			% layer.frame_size()
	)
	# ...in pixels as well as in metres. The legibility floor is about aliasing and
	# a layer that never hears the resolution cannot judge it.
	assert_eq(
		layer.frame_pixels(), _pixels(),
		"the layer was never told how big the viewport is: %s" % layer.frame_pixels()
	)
	assert_almost_eq(
		director.pullback_for(layer), layer.pullback_m * layer.geometry_scale(), 0.001,
		"the volume and its pullback disagree about the framing: the box would sink "
			+ "into the ground it is supposed to be falling onto"
	)
	# A frame the world layer's field already covers must not move its box at all,
	# and therefore must not move the pullback either.
	director.set_frame_size(_frame(layer.authored_frame.y * 0.5))
	director.drive(layer)
	assert_almost_eq(
		director.pullback_for(layer), layer.pullback_m, 0.001,
		"a tighter frame shortened the pullback to %.2f m: a world box is a volume of "
			% director.pullback_for(layer) + "air and does not shrink when the camera zooms in"
	)
	layer.free()
	director.free()
