shader_type particles;

// 袅袅炊烟 -- the motion half of it. src/rendering/chimney_smoke.gd owns the
// colour, the placement and the fire; this file owns how a puff MOVES, because
// everything that separates smoke from a particle emitter pointed upward is a
// per-particle, per-frame decision that a ParticleProcessMaterial cannot make.
//
// ---------------------------------------------------------------------------
// WHY THIS IS NOT A ParticleProcessMaterial
// ---------------------------------------------------------------------------
// Four things had to be true, and the stock material can do one of them:
//
//   1. BUOYANCY FALLS OFF. Smoke leaves the flue fast because it is hot and
//      slows as it cools and mixes with the air. `gravity` is one vector shared
//      by every particle alive, so it cannot be a function of age. Here it is:
//      see `buoyancy_decay`.
//
//   2. TURBULENCE GROWS WITH AGE, not with height. A puff that has existed
//      longer is more broken up -- that is what makes smoke CURL instead of
//      travel. The stock material has `turbulence_influence_over_life`, but it
//      MIXES the velocity toward the noise field rather than adding a force, so
//      raising it deletes the motion it is supposed to disturb. This project
//      has already measured that on the snowfall (see test_snowfall.gd:441:
//      the flakes stop falling). Here turbulence is a FORCE and the rise
//      survives it.
//
//   3. IT IS A RIBBON. A narrow mouth and a low spread, widened by turbulence
//      rather than by emitting wide.
//
//   4. THE GUST HAS TO TRAVEL UP THE COLUMN, and that is the one that decides
//      whether this reads as smoke or as a flag. See below.
//
// ---------------------------------------------------------------------------
// HOW THE COLUMN COMES TO BE MADE OF WIND HISTORY
// ---------------------------------------------------------------------------
// `wind` is a single uniform, the same for every particle, rewritten each
// frame. That sounds like it could only ever move the whole column together --
// and it would, if the wind were applied to POSITION. It is applied to
// VELOCITY, through a first-order drag:
//
//     dv/dt = (wind - v) / coupling_seconds
//
// so a puff accelerates toward the air around it and then travels with it. Its
// position is therefore the integral of the wind SINCE ITS OWN BIRTH:
//
//     x(t) = x_flue + INTEGRAL from t_birth to t of wind(s) ds
//
// Differentiate that with respect to AGE and the slope of the column at age `a`
// is wind(t - a). The column is literally a plot of the last few seconds of
// weather, drawn upward. A gust at time t_g is a steep section at age t - t_g,
// and as t advances that section belongs to ever older -- ever higher --
// particles. **The kink climbs.** Nothing here computes that; it is what
// integrating a shared force per particle means, and it is the whole reason the
// wind is not simply added to the emitter's position.
//
// The same idea is extended to APPEARANCE by USERDATA1.x, which each puff sets
// once, at birth, to the wind strength it was born into and never updates. A
// gust therefore does not merely bend the column -- it makes a SEGMENT of the
// column shreddier and thinner, and that segment travels up with the bend.
//
// ---------------------------------------------------------------------------
// THE ENGINE INTEGRATES VELOCITY. DO NOT DO IT AGAIN.
// ---------------------------------------------------------------------------
// Godot 4.7.1 applies `TRANSFORM[3].xyz += VELOCITY * DELTA` itself after
// `process()` returns. The docs for particle shaders do not say so either way.
// Measured on this build with a two-emitter probe at a known rise: the emitter
// that also did it by hand climbed 4.08 m where the correct answer was 2.00 m.
// A shader that adds the line looks *almost* right -- a column of the wrong
// height that also reads as accelerating -- which is exactly the kind of wrong
// that survives a review.
//
// ---------------------------------------------------------------------------
// NO COLOUR LIVES HERE
// ---------------------------------------------------------------------------
// Binding constraint 6: colour comes from data/palette/color_bible.tres and is
// written nowhere else. `COLOR.rgb` stays at 1.0, which is the identity for the
// multiply against the draw material's albedo -- the same trick trap 7 uses on
// ALBEDO. Only the ALPHA is authored here, because the alpha is a shape over
// time rather than a colour.

// --- the flue ---------------------------------------------------------------

// Radius of the mouth the smoke leaves through, in metres. Small: point 3 above.
uniform float mouth_radius = 0.16;

// Metres a second the smoke leaves at, and how much that varies puff to puff.
// This is the hot half of the effect -- it is fast at the lip and it is not
// fast for long.
uniform float exit_speed = 1.35;
uniform float exit_jitter = 0.35;

// How far off vertical the mouth throws, as a fraction of the exit speed. Low,
// or the ribbon leaves as a cone.
uniform float exit_spread = 0.16;

// --- buoyancy ---------------------------------------------------------------

// Upward acceleration at birth, m/s^2, and how quickly it is lost over the
// particle's life. `exp(-age * decay)`, so at a decay of 3.2 a puff has 4% of
// its lift left at the end and is coasting on what the air does to it.
//
// A CONSTANT rise is the single most recognisable tell of a particle emitter
// pointed upward, because nothing real keeps accelerating for nine seconds.
uniform float buoyancy = 1.10;
uniform float buoyancy_decay = 3.20;

// How quickly vertical speed bleeds off, as a time constant in seconds. With
// the buoyancy above this settles the rise at a terminal speed instead of
// letting it run away, and it is what makes the top of the column stall and
// spread rather than shoot off frame.
uniform float rise_damping_seconds = 1.60;

// --- the wind ---------------------------------------------------------------

// The air the smoke is in, in metres a second, in world space. Written every
// frame by ChimneySmoke.set_wind(). See the header for why one uniform can
// produce a column with several seconds of weather in it.
uniform vec3 wind = vec3(0.0);

// How long a puff takes to come up to the speed of the air around it. Short
// enough that a gust reaches the smoke while it is still a gust; long enough
// that the smoke at the lip has not been blown sideways before it clears the
// chimney, which is what makes the bend start ABOVE the flue rather than at it.
uniform float coupling_seconds = 0.55;

// 0 dead still .. 1 full gale, as WindSystem reports it. Read at birth only.
uniform float wind_strength = 0.0;

// --- turbulence -------------------------------------------------------------

// The size of the eddies, in metres -- larger divides, smaller number is bigger
// swirls. At 0.55 the features are about a metre across, which at this camera
// is the scale that reads as folding rather than as fizz.
uniform float curl_scale = 0.55;

// How hard the curl field pushes, m/s^2, at the END of a puff's life.
uniform float curl_strength = 1.15;

// The exponent on age. Above 1 the young smoke near the flue stays a clean
// ribbon and the break-up arrives further up, which is what makes the column
// read as ageing rather than as noisy.
uniform float curl_growth = 1.70;

// How much the wind a puff was BORN INTO adds to its own turbulence. This is
// the tearing: at a full gale a puff is pushed about three times as hard as one
// born in a lull, so the ribbon comes apart into separate scraps -- and because
// it is read at birth, the shredded stretch travels up the column with the bend
// that made it.
uniform float curl_wind_gain = 2.60;

// How fast the eddy field itself evolves, in field-widths a second. Slow: the
// motion should come from the smoke moving THROUGH the field, not from the
// field boiling underneath it.
uniform float curl_drift = 0.11;

// --- shape over life --------------------------------------------------------

// Radius at birth, and the multiple of it a puff has swollen to when it is
// gone. It only ever GROWS: smoke disperses, so the oldest puff is the biggest
// and the faintest one. A curve that came back down reads as a spark going out.
uniform float size_birth = 0.55;
uniform float size_death = 4.20;

// How much of the growth has happened by half life, 0 .. 1. Below 0.5 the swell
// is back-loaded, which is what dispersal actually looks like -- slow while the
// puff is still coherent, quickly once it has broken up.
uniform float size_bias = 0.38;

// Peak alpha, and where in the life it falls. The rise is quick -- smoke is
// dense at the lip -- and the fall is long and convex, so the column THINS OUT
// of existence instead of reaching a ceiling. `test_chimney_smoke.gd` asserts
// there is no frame in which a puff visibly stops existing.
uniform float peak_alpha = 0.38;
uniform float alpha_in = 0.07;
uniform float alpha_hold = 0.20;

// How much of the alpha a full gale takes off. Wind does not only bend smoke,
// it MIXES it away: a torn column is a fainter one, and without this the
// fragments read as solid lumps.
uniform float wind_thinning = 0.45;

// Multiplies the whole alpha. ChimneySmoke drives this from the fire, so the
// column builds and fades rather than switching.
uniform float draught = 1.0;


// --- a divergence-free field, and why it has to be one ----------------------
//
// The curl of any vector field has zero divergence, so this noise has no
// sources and no sinks anywhere. That matters here rather than being a nicety:
// a plain 3D noise read as a velocity has places where the field flows inward,
// and puffs pile into them and sit there. The result is smoke that clumps into
// beads at fixed points in the world, which is unmistakable once seen and looks
// like a bug in the emitter rather than in the noise.

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(cell);
	float n100 = hash31(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(cell + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

// The vector potential the curl is taken of. Three decorrelated noises -- the
// offsets are large and arbitrary so the components do not share features,
// which they would at small offsets and the field would degenerate toward a
// plane.
vec3 potential(vec3 p, float t) {
	return vec3(
		value_noise(p + vec3(0.0, t, 0.0)),
		value_noise(p + vec3(37.1, 17.7 + t, 5.3)),
		value_noise(p + vec3(11.9, 3.1 + t, 71.4))
	) - 0.5;
}

vec3 curl_at(vec3 p, float t) {
	const float e = 0.35;
	vec3 dpx = potential(p + vec3(e, 0.0, 0.0), t) - potential(p - vec3(e, 0.0, 0.0), t);
	vec3 dpy = potential(p + vec3(0.0, e, 0.0), t) - potential(p - vec3(0.0, e, 0.0), t);
	vec3 dpz = potential(p + vec3(0.0, 0.0, e), t) - potential(p - vec3(0.0, 0.0, e), t);
	return vec3(
		dpy.z - dpz.y,
		dpz.x - dpx.z,
		dpx.y - dpy.x
	) / (2.0 * e);
}


// A stable 0..1 per particle.
//
// The seed is PASSED IN rather than read from NUMBER here, and that is not a
// style choice: a particle shader's built-ins exist only inside `start()` and
// `process()`, so a free function that reaches for NUMBER fails to compile with
// "Unknown identifier in expression" and no line that mentions particles.
float roll(float base, float salt) {
	return fract(sin((base + salt) * 12.9898) * 43758.5453);
}


void start() {
	// NUMBER is the particle's serial since the emitter started, so it changes
	// every time this slot is reborn -- which is what makes two successive puffs
	// out of the same slot differ instead of repeating.
	float seed = float(NUMBER) + float(RANDOM_SEED) * 0.00013;

	// Where the mouth is. A disc rather than a point: the flue has a width, and
	// a ribbon leaving a single point reads as a laser however much turbulence
	// is put on it afterwards. sqrt on the radius keeps the disc evenly filled
	// instead of crowding the centre.
	float angle = roll(seed, 1.7) * 6.2831853;
	float radius = sqrt(roll(seed, 3.1)) * mouth_radius;
	vec3 mouth = vec3(cos(angle) * radius, 0.0, sin(angle) * radius);
	TRANSFORM[3].xyz = (EMISSION_TRANSFORM * vec4(mouth, 1.0)).xyz;

	// Up, fast, and barely spread. See exit_speed.
	float speed = exit_speed * (1.0 + (roll(seed, 5.9) - 0.5) * 2.0 * exit_jitter);
	VELOCITY = normalize(vec3(
		(roll(seed, 7.3) - 0.5) * 2.0 * exit_spread,
		1.0,
		(roll(seed, 11.5) - 0.5) * 2.0 * exit_spread
	)) * speed;

	// THE MEMORY. Set once and never touched again -- see the header.
	//   x  the wind this puff was born into
	//   y  its own size roll
	//   z  where in the eddy field it reads, so two puffs at the same place
	//      still disagree
	//   w  unused; reserved so a later term does not have to renumber the rest
	USERDATA1 = vec4(
		clamp(wind_strength, 0.0, 1.0),
		0.72 + roll(seed, 13.7) * 0.56,
		roll(seed, 17.1) * 100.0,
		0.0
	);

	// CUSTOM.y is this project's own age clock, integrated below. Godot does not
	// keep one a shader can read, and the engine's own lifetime bookkeeping is
	// not exposed -- so a shader that needs age has to count it.
	CUSTOM = vec4(0.0, 0.0, 0.0, LIFETIME);
	COLOR = vec4(1.0, 1.0, 1.0, 0.0);
}


void process() {
	// Age, 0 at the lip and 1 at the end.
	CUSTOM.y = clamp(CUSTOM.y + DELTA / max(LIFETIME, 0.001), 0.0, 1.0);
	float age = CUSTOM.y;
	float born_into = USERDATA1.x;

	// 1. BUOYANCY, FALLING OFF. Hot at the lip, cooling all the way up.
	VELOCITY.y += buoyancy * exp(-age * buoyancy_decay) * DELTA;

	// 2. AND BLED OFF, so the rise reaches a terminal speed. Exponential rather
	//    than subtractive: a subtractive damping crosses zero and reverses,
	//    which would rain the smoke back down on the roof.
	VELOCITY.y -= VELOCITY.y * (1.0 - exp(-DELTA / max(rise_damping_seconds, 0.001)));

	// 3. THE WIND, as a drag toward the air rather than as a push. This is the
	//    line the travelling kink comes out of; see the header.
	float catch_up = 1.0 - exp(-DELTA / max(coupling_seconds, 0.001));
	VELOCITY.x += (wind.x - VELOCITY.x) * catch_up;
	VELOCITY.z += (wind.z - VELOCITY.z) * catch_up;

	// 4. TURBULENCE, GROWING WITH AGE AND WITH THE GUST IT WAS BORN INTO. A
	//    force added to the velocity, never a mix into it -- see the header for
	//    what the stock material does instead and why it deletes the rise.
	vec3 here = TRANSFORM[3].xyz;
	float gain = curl_strength * pow(age, curl_growth) * (1.0 + born_into * curl_wind_gain);
	VELOCITY += curl_at(here / max(curl_scale, 0.01) + vec3(USERDATA1.z),
		TIME * curl_drift) * gain * DELTA;

	// --- what it looks like ------------------------------------------------

	// Size only ever grows. `size_bias` decides how much of it has happened by
	// half life; pow with an exponent derived from it puts the knee where the
	// tuner asked rather than where a curve happened to bend.
	float shaped = pow(age, log(clamp(size_bias, 0.05, 0.95)) / log(0.5));
	float size = mix(size_birth, size_death, shaped) * USERDATA1.y;
	TRANSFORM[0].xyz = vec3(size, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, size, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, size);

	// Alpha: up quickly, hold, then a long convex tail to nothing. The tail is
	// the requirement -- particles that vanish at a lifetime boundary put a
	// visible ceiling on the column, and a ceiling is the tell that this is a
	// finite buffer of quads rather than air.
	float rise_in = smoothstep(0.0, max(alpha_in, 0.001), age);
	float fall = 1.0 - smoothstep(clamp(alpha_hold, 0.0, 0.99), 1.0, age);
	// Cubed: a linear fall still has a slope where it meets zero, and at this
	// framing the eye finds that as an edge on the top of the column.
	fall = fall * fall * fall;
	float thinned = 1.0 - born_into * clamp(wind_thinning, 0.0, 1.0);
	// rgb stays at the identity; the draw material owns the colour.
	COLOR = vec4(1.0, 1.0, 1.0, peak_alpha * rise_in * fall * thinned * draught);
}
