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


## Older puffs are smaller as well as fainter -- that is what makes the trail read
## as a sequence in time rather than as one cloud with a ragged edge.
func test_a_puff_shrinks_and_fades_as_it_ages() -> void:
	var breath := _fresh()
	var scale_curve: Curve = (breath.process_material.scale_curve as CurveTexture).curve
	assert_true(
		scale_curve.sample(1.0) < scale_curve.sample(0.25),
		"the puff ends at %f of its size against %f in its youth: it grows, and the "
			% [scale_curve.sample(1.0), scale_curve.sample(0.25)]
			+ "reference's oldest puff is its smallest"
	)
	var ramp: Gradient = (breath.process_material.color_ramp as GradientTexture1D).gradient
	assert_eq(ramp.sample(1.0).a, 0.0, "the puff does not fade out completely")
	assert_true(ramp.sample(0.2).a > 0.5, "the puff never becomes visible at all")
	breath.free()
