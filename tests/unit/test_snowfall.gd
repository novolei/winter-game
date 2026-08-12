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
## At EVERY framing, not only the tightest. The camera now offers three and eases
## between them, and a flake that keeps its metres while the frame widens is a
## flake losing its pixels -- the distant layer's specks go under two of them and
## become noise rather than air.
func test_every_flake_is_big_enough_to_read_at_gameplay_framing() -> void:
	for height in _framing_samples():
		var pixels_per_metre: float = 1000.0 / height
		for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
			var layer := _layer(path)
			layer.set_frame_size(_frame(height))
			layer.set_snowfall_rate(1.0)
			layer._apply()
			var drawn: float = (layer.process_material as ParticleProcessMaterial).scale_max
			var pixels: float = drawn * pixels_per_metre
			assert_true(
				pixels >= 2.5,
				"%s draws its largest flake %.3f m across at a %.1f m frame, which is "
					% [path, drawn, height] + "%.1f px" % pixels
			)
			if path == LENS_SCENE:
				# And the one the document says matters. A lens flake has to be seen
				# crossing the frame, not inferred.
				assert_true(
					pixels >= 9.0,
					"the lens flake is %.1f px at a %.1f m frame; it is meant to be the "
						% [pixels, height] + "one you notice"
				)
			layer.free()


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
			* lens.frame_scale()
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


## SYMPTOM 3. Under a parallel projection a flake is the same size on screen
## whether it is two metres from the lens or ninety, so SIZE is the only thing
## separating the three layers -- and snowfall_layer.gd's header states those
## sizes in PIXELS, which is the number that actually matters. A flake that keeps
## its metres when the frame widens loses its pixels, and the lens layer stops
## reading as the one in front of the lens.
func test_a_flake_keeps_its_authored_screen_size_at_every_framing() -> void:
	var pixels := 1000.0
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		layer.set_snowfall_rate(1.0)
		var authored := -1.0
		for height in _framing_samples():
			layer.set_frame_size(_frame(height))
			layer._apply()
			var material := layer.process_material as ParticleProcessMaterial
			var on_screen: float = material.scale_max * pixels / height
			if authored < 0.0:
				authored = on_screen
			assert_almost_eq(
				on_screen, authored, 0.01,
				("%s draws its largest flake %.1f px at a %.1f m frame against %.1f px at "
					+ "the tightest: the layer no longer reads at the size it was authored")
					% [path, on_screen, height, authored]
			)
		layer.free()


## THE TRANSITION, which is the case no screenshot at rest can show. CameraRig
## does not jump between stops, it eases over 0.12-0.22 s on a cubic or quintic
## curve, so the frame spends every zoom at a size that is not any stop at all.
##
## A snowfall that sampled the framing once, when the stop changed, would be
## correct in all three screenshots and wrong for the whole of every zoom. What
## this pins is exactly that difference: the geometry has to be STRICTLY between
## the two ends when the frame is, not merely equal to one of them.
func test_the_snow_tracks_the_frame_between_the_stops_and_not_only_at_them() -> void:
	var stops := _framing_stops()
	stops.sort()
	assert_true(
		stops.size() >= 2,
		"the rig offers %d framing(s); there is no zoom to track" % stops.size()
	)
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
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


## Every layer, not only the one on the lens. Layers 1 and 2 are world-space and
## were authored against the same single framing, so their emission volumes carry
## the same dependency: a box sized to hold the frame's footprint at one framing
## holds a shrinking fraction of it as the frame grows.
##
## Stated as a SHARE of the frame rather than as metres, which is the property
## that has to hold and the one that makes every authored number below it correct
## at a framing nobody has invented yet.
func test_every_layer_scales_its_emission_volume_with_the_frame() -> void:
	for path in [DISTANT_SCENE, NEAR_SCENE, LENS_SCENE]:
		var layer := _layer(path)
		var authored := -1.0
		for height in _framing_samples():
			layer.set_frame_size(_frame(height))
			layer._apply()
			var material := layer.process_material as ParticleProcessMaterial
			var share: float = material.emission_box_extents.y / height
			if authored < 0.0:
				authored = share
			assert_almost_eq(
				share, authored, 0.0001,
				("%s emits over %.3f frame-heights at a %.1f m frame against %.3f at the "
					+ "tightest: the volume is authored against one framing")
					% [path, share, height, authored]
			)
		layer.free()


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
	director.drive(layer)
	assert_eq(
		layer.frame_size(), wide,
		"the director drove the layer without telling it what it is drawing into: %s"
			% layer.frame_size()
	)
	assert_true(
		layer.frame_scale() > 1.0,
		"a 17 m frame against a layer authored at %.1f m scaled by %.2f"
			% [layer.authored_frame.y, layer.frame_scale()]
	)
	assert_almost_eq(
		director.pullback_for(layer), layer.pullback_m * layer.frame_scale(), 0.001,
		"the volume grew with the frame and kept its authored %.1f m pullback"
			% layer.pullback_m
	)
	layer.free()
	director.free()
