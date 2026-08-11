extends TestCase

## Breath is a readout, not an effect.
##
## GDD section 9 lists 呼出白气的浓度 among the diegetic channels the game uses
## instead of a HUD, so what these tests protect is that the parameters are
## actually *driven*. A constant puff is indistinguishable from a driven one in
## any screenshot, and would sail through a visual review while telling the
## player nothing at all -- which is the only way this feature can fail silently.
##
## The first test is the important one and it is not about the driving at all:
## `local_coords` is the difference between a trail of breath left along a path
## and a smear stuck to the character's chin, and it is one boolean.

const BreathFogScript := preload("res://src/entities/player/breath_fog.gd")


func _fresh() -> BreathFog:
	var breath: BreathFog = BreathFogScript.new()
	# _ready() has not run: nothing has been added to the tree (briefing trap 1).
	breath._ready()
	return breath


## THE ONE THAT MATTERS. Particles simulated in the emitter's local space follow
## the head, so the puffs never separate and never fall behind -- the reference's
## whole read, moving and standing both, is that they stay where they were
## exhaled.
func test_the_puffs_are_left_behind_in_world_space() -> void:
	var breath := _fresh()
	assert_false(
		breath.local_coords,
		"local_coords is on: every puff will drag along with the head and the "
			+ "trail will never form"
	)
	# And the other half of "discrete puffs strung out in a line": a burst per
	# breath makes a steam engine, and a dense stream makes fog.
	assert_eq(breath.explosiveness, 0.0, "breath is emitted steadily, not in bursts")
	assert_false(breath.one_shot, "the emitter must keep going, not fire once")
	assert_true(
		breath.amount <= 18,
		"%d puffs alive at once is a cloud; the reference shows about six" % breath.amount
	)
	breath.free()


## Cold is the primary driver: more of it, and it hangs about longer.
func test_cold_makes_the_breath_denser_and_longer_lived_than_warm() -> void:
	var warm := _fresh()
	warm.set_chill(0.0)
	warm._process(0.0)
	var warm_life: float = warm.lifetime
	var warm_amount: int = warm.amount
	var warm_birth: float = warm.process_material.scale_max
	# Node, not RefCounted: nothing below may read it (briefing section 2.2).
	warm.free()

	var cold := _fresh()
	cold.set_chill(1.0)
	cold._process(0.0)
	assert_true(
		cold.lifetime > warm_life,
		"a freezing breath lives %f s against a warm one's %f" % [cold.lifetime, warm_life]
	)
	assert_true(
		cold.amount > warm_amount,
		"a freezing breath keeps %d puffs in the air against a warm one's %d"
			% [cold.amount, warm_amount]
	)
	assert_true(
		cold.process_material.scale_max > warm_birth,
		"a freezing puff is born %f m across against a warm one's %f"
			% [cold.process_material.scale_max, warm_birth]
	)
	cold.free()


## Exertion is the rhythm, not the density: a running man breathes more often and
## harder, and that is what opens the spacing of the trail behind him.
func test_exertion_raises_the_rate_and_the_speed() -> void:
	var still := _fresh()
	still.set_exertion(0.0)
	still._process(0.0)
	var still_speed: float = still.process_material.initial_velocity_max
	# amount / lifetime is the emission rate: GPUParticles3D spreads `amount`
	# births evenly across one lifetime.
	var still_rate: float = float(still.amount) / still.lifetime
	still.free()

	var running := _fresh()
	running.set_exertion(1.0)
	running._process(0.0)
	assert_true(
		running.process_material.initial_velocity_max > still_speed,
		"a hard breath leaves at %f m/s against a resting one's %f"
			% [running.process_material.initial_velocity_max, still_speed]
	)
	assert_true(
		float(running.amount) / running.lifetime > still_rate,
		"running emits %f puffs a second against standing's %f"
			% [float(running.amount) / running.lifetime, still_rate]
	)
	running.free()


## The switch the interior reveal will own. Off means nothing is emitted at all,
## not merely a slower rhythm.
func test_indoors_emits_nothing() -> void:
	var breath := _fresh()
	breath.outdoors = false
	breath._process(0.0)
	assert_false(breath.emitting, "breath is still being emitted with outdoors off")
	breath.free()


## The hook, checked as a hook: it must exist and it must reach the puff, so that
## whoever writes src/systems/wind_system.gd has one place to connect and no
## reason to invent a second wind inside this file.
func test_the_wind_hook_reaches_the_puff() -> void:
	var breath := _fresh()
	breath.set_chill(1.0)
	breath._process(0.0)
	var still_air: Vector3 = breath.process_material.gravity
	breath.set_wind(Vector3(3.0, 0.0, 0.0))
	breath._process(0.0)
	assert_true(
		breath.process_material.gravity != still_air,
		"set_wind() left the puff drifting exactly as it did in still air"
	)
	breath.free()


## Sized against the camera, not against a face. The frame is 10.5 m tall, so a
## puff under about a tenth of a metre is a handful of pixels in play -- which is
## exactly how this effect fails: it looks right in a close-up and vanishes at
## the framing the game is actually played at.
func test_the_puff_is_big_enough_to_read_at_gameplay_framing() -> void:
	var breath := _fresh()
	breath.set_chill(1.0)
	breath._process(0.0)
	assert_true(
		breath.process_material.scale_max >= 0.1,
		"the coldest breath is born %f m across; at the game's 10.5 m frame that is "
			% breath.process_material.scale_max
			+ "under ten pixels and reads as nothing"
	)
	assert_true(
		breath.lifetime <= 2.5,
		"a puff living %f s smears across this camera and reads as fog, not breath"
			% breath.lifetime
	)
	breath.free()


## Older puffs are BIGGER and fainter. Vapour disperses -- it spreads out and
## thins until there is nothing left of it -- so the oldest puff in the trail is
## the largest one.
##
## This test used to assert the exact opposite, and the reversal is deliberate
## rather than a test bent to fit the code: shrinking a puff away makes it read
## as a spark going out, and the owner asked for dispersal instead. What is
## pinned here is the new intent, in the same detail the old one was.
func test_a_puff_swells_and_thins_as_it_disperses() -> void:
	var breath := _fresh()
	var scale_curve: Curve = (breath.process_material.scale_curve as CurveTexture).curve
	assert_true(
		scale_curve.sample(1.0) > scale_curve.sample(0.25) * 1.4,
		"the puff ends at %f of its birth size against %f in its youth: it is not "
			% [scale_curve.sample(1.0), scale_curve.sample(0.25)]
			+ "dispersing, and vapour does not hold its size or shrink away"
	)
	var ramp: Gradient = (breath.process_material.color_ramp as GradientTexture1D).gradient
	assert_eq(ramp.sample(1.0).a, 0.0, "the puff does not fade out completely")
	assert_true(ramp.sample(0.2).a > 0.25, "the puff never becomes visible at all")
	breath.free()


## Both ends of a puff's life are eased. It emerges from the mouth rather than
## appearing at it, and it disperses rather than switching off -- and the death
## in particular has to be a curve rather than a cliff, which a two-point ramp
## from lit to nothing would not be.
func test_a_puff_emerges_and_disperses_rather_than_popping() -> void:
	var breath := _fresh()
	var scale_curve: Curve = (breath.process_material.scale_curve as CurveTexture).curve
	var ramp: Gradient = (breath.process_material.color_ramp as GradientTexture1D).gradient

	# Birth: small and invisible, up to full size and lit within the first sixth.
	assert_eq(ramp.sample(0.0).a, 0.0, "the puff is born already lit and pops in")
	assert_true(
		scale_curve.sample(0.0) < 0.6,
		"the puff is born at %f of its size: it appears rather than emerging"
			% scale_curve.sample(0.0)
	)
	assert_true(
		scale_curve.sample(0.18) >= 0.95,
		"the puff is still only %f of its size a fifth of the way through; the "
			% scale_curve.sample(0.18)
			+ "birth is meant to be quick, not the whole of its life"
	)

	# Death: still faintly there late on, so the last of it is a curve and not a
	# frame in which the puff stopped existing.
	var late: float = ramp.sample(0.88).a
	assert_true(
		late > 0.01 and late < ramp.sample(0.4).a * 0.4,
		"at 88%% of its life the puff is at alpha %f against %f at 40%%: the fade "
			% [late, ramp.sample(0.4).a]
			+ "out is a cliff rather than a curve"
	)
	breath.free()


## Vapour, not snow. The puff has to be clearly lighter than the field it is seen
## against and clearly NOT white, and it has to lean on alpha rather than on
## brightness -- an opaque white puff reads as a snowball stuck to his face.
func test_the_puff_reads_as_vapour_rather_than_as_snow() -> void:
	var breath := _fresh()
	var bible = load("res://data/palette/color_bible.tres")
	var snow: Color = bible.snow_tones[0]
	var surface: StandardMaterial3D = (breath.draw_pass_1 as QuadMesh).material
	var tone: Color = surface.albedo_color

	assert_true(
		tone.v > snow.v,
		"the puff is no lighter than the snow behind it and will not be seen at all"
	)
	assert_true(
		tone.v < 0.97,
		"the puff is at value %f, which is effectively white: Art Bible rule 12 "
			% tone.v
			+ "aside, an opaque white blob reads as a snowball, not as breath"
	)
	# Cool, not warm: rule 12 reserves the warm pixels for fire, windows, beacons,
	# the scarf and the truck. Blue above red is the whole of the test.
	assert_true(
		tone.b > tone.r,
		"the puff has drifted warm (r=%f b=%f) and is competing with the beacons"
			% [tone.r, tone.b]
	)

	# And the visibility is carried by alpha. A peak opacity anywhere near 1 means
	# the brightness above was doing the work after all.
	var ramp: Gradient = (breath.process_material.color_ramp as GradientTexture1D).gradient
	var peak := 0.0
	for step in range(21):
		peak = maxf(peak, ramp.sample(float(step) / 20.0).a)
	assert_true(
		peak > 0.2 and peak < 0.7,
		"the puff peaks at alpha %f; vapour is translucent, and at this alpha it "
			% peak
			+ "is either invisible or a solid object"
	)
	breath.free()


## The cloud has to stand off the face. Puffs that condense on his lips sit
## inside the silhouette of the hood, where nobody can see them overlap and where
## they read as a smudge on the model rather than as breath.
func test_the_cloud_carries_clear_of_the_head() -> void:
	var breath := _fresh()
	breath.set_exertion(0.0)
	breath._process(0.0)
	var material: ParticleProcessMaterial = breath.process_material
	# Coasting distance under linear damping: v^2 / 2a. Compared against the head,
	# which is about 0.22 m across on this rig.
	var speed: float = material.initial_velocity_max
	var damping := (material.damping_min + material.damping_max) * 0.5
	var carry := speed * speed / (2.0 * maxf(damping, 0.0001))
	assert_true(
		carry > 0.35,
		"a resting breath coasts %.2f m before it stops, which is inside his own "
			% carry
			+ "hood; the cloud has to stand out in front of the face"
	)
	# Forward, not up: the rise is the gravity term's job.
	assert_true(
		material.direction.z > material.direction.y * 2.0,
		"the breath is aimed more upward than forward (%s) and will stack over the "
			% str(material.direction)
			+ "hood instead of standing in front of it"
	)
	breath.free()
