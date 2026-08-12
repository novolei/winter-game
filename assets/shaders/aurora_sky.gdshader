shader_type sky;

// THE NIGHT SKY, AND THE THING HANGING IN IT.
//
// This replaces ProceduralSkyMaterial on Environment.sky. It carries three
// things, in this order behind one another:
//
//   1. the vertical gradient the six lighting presets already author -- zenith,
//      horizon, curve, energy -- reproduced from ProceduralSkyMaterial's own
//      formula so that swapping the material moves none of the six;
//   2. a star field, which the presets switch on through `star_amount`;
//   3. the aurora: several overlapping curtains, ADDED over the two above, which
//      is why the stars show through it.
//
// ---------------------------------------------------------------------------
// WHY REPLACING THE STOCK SKY IS SAFE HERE, MEASURED RATHER THAN ASSERTED
// ---------------------------------------------------------------------------
// LightingDirector sets `ambient_light_sky_contribution = 0` and
// `reflected_light_source = DISABLED`, so nothing in the game is LIT by the sky.
// The sky reaches the frame only as background pixels, and at every framing the
// game currently uses the ground plane fills the frame and there are none. So
// the only thing this file can change is what a camera sees when it is aimed
// above the horizon -- which is exactly the feature it exists for.
//
// ---------------------------------------------------------------------------
// THE ORTHOGRAPHIC CAMERA CANNOT SEE ANY OF THIS, AND THAT IS NOT A BUG
// ---------------------------------------------------------------------------
// Under a parallel projection EVERY view ray is the same direction, so EYEDIR is
// constant across the whole frame and a sky shader can only ever produce ONE
// FLAT COLOUR. No gradient, no stars, no curtain. That is a property of the
// projection, not of this shader.
//
// The Art Bible's rule 1 ruling on the crow close-up already anticipates it:
// 正交投影下向上仰视没有透视收敛 -- an upward look under orthographic has no
// convergence -- and it permits blending to perspective for that moment. So this
// curtain is authored for, and can only be judged under, a PERSPECTIVE camera.
// tools/capture_aurora.gd takes its sky shots with one, and says so.
//
// ---------------------------------------------------------------------------
// COLOUR
// ---------------------------------------------------------------------------
// Green and teal are in neither the 12-colour table nor rule 12's warm
// allowance, and neither table governs them: the twelve govern ALBEDO, while
// sky, fog, ambient and light colour are atmosphere -- the boundary recorded in
// Docs/style optimization.md. An aurora is sky, and it is its own light source.
// Every colour below arrives as a uniform from data/aurora/*.tres; there is not
// one literal in this file.

// --- the gradient the six presets author ------------------------------------
//
// Names and semantics deliberately identical to ProceduralSkyMaterial's, so the
// block in LightingDirector._write() that fills them reads the same as before.
uniform vec4 sky_top_color : source_color = vec4(0.36, 0.48, 0.65, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.72, 0.80, 0.90, 1.0);
uniform float sky_curve : hint_range(0.0, 1.0) = 0.15;
uniform float sky_energy = 1.0;
uniform vec4 ground_horizon_color : source_color = vec4(0.72, 0.80, 0.90, 1.0);
uniform vec4 ground_bottom_color : source_color = vec4(0.36, 0.48, 0.65, 1.0);
uniform float ground_curve : hint_range(0.0, 1.0) = 0.15;
uniform float ground_energy = 1.0;

// The dither ProceduralSkyMaterial's `use_debanding` adds. A gradient this
// shallow banks visibly on an 8-bit target without it.
uniform float debanding = 1.0;

// --- the stars ---------------------------------------------------------------
//
// Driven from LightingPreset.star_amount, so PALE DAY has none and DEEP NIGHT
// has all of them, and a crossfade between two presets fades the field in.
uniform float star_amount = 0.0;
uniform float star_density = 220.0;
uniform float star_radius = 0.052;
uniform float star_twinkle = 0.35;
// How far up the dome they begin. A star sitting exactly on the horizon reads as
// a stuck pixel rather than as a star.
uniform float star_horizon_fade = 0.16;
uniform vec4 star_color : source_color = vec4(0.86, 0.91, 1.0, 1.0);

// --- the curtain -------------------------------------------------------------
//
// 0 when there is no aurora, which is nearly always. Everything below is skipped
// outright at zero.
uniform float aurora_strength = 0.0;
uniform float aurora_opacity = 1.0;

// WHERE IT HANGS. `aurora_bearing` is a world compass angle in radians measured
// from -Z toward +X, which is the same convention the camera rig's yaw uses; the
// fixed rig looks along 35 degrees, so a curtain near there is the one an upward
// lean would find. `aurora_span` is the HALF width in radians -- at the shipped
// value the curtain covers most of the visible half of the horizon, which is
// what 巨幕 means.
uniform float aurora_bearing = 0.6109;
uniform float aurora_span = 0.9599;

// The vertical extent, in radians of elevation. Low and shallow: 远远天际, on
// the horizon at a great distance, never overhead.
//
// These three and `aurora_band_lift` below are INERT fallbacks -- every one is
// overwritten by LightingDirector.set_aurora_curtain() the moment a curtain
// opens -- but they are kept equal to the shipped data/aurora/*.tres so that
// nothing here can quietly disagree with what actually renders. 6 and 32 degrees.
uniform float aurora_base = 0.1047;
uniform float aurora_top = 0.5585;

// THE RAYS, AND THEY ARE THE WHOLE THING.
//
// A smooth green gradient is a coloured fog. What makes an aurora read as an
// aurora is that it is made of VERTICAL STRIATIONS -- field-aligned rays, all
// parallel, at several thicknesses at once. So the brightness is a function of
// the HORIZONTAL angle alone, coherent all the way up a ray, and the vertical
// coordinate only supplies the envelope and a slight lean.
//
//   frequency  how many rays across the curtain
//   sharpness  how hard the fine octave is squeezed -- higher is more filament,
//              less wash
//   shear      how far a ray leans as it climbs, which is what stops the field
//              reading as a barcode
uniform float aurora_ray_frequency = 5.4;
uniform float aurora_ray_sharpness = 2.2;
uniform float aurora_shear = 0.55;

// HOW IT MOVES, AND WHY IT NEVER REPEATS.
//
// Three bands, each drifting at its own speed and breathing on its own two
// periods, and none of the six numbers is a rational multiple of another. The
// combined figure has a period on the order of tens of thousands of seconds --
// far past any session -- so a player standing still watches it change rather
// than sees it cycle. That is the requirement, and it is bought with irrational
// ratios rather than with a long texture.
uniform float aurora_drift = 0.035;

// The three curtains: colour, opacity, where its lower hem hangs relative to the
// band above, and how wide a slice of the span it occupies. Authored in
// data/aurora/*.tres.
//
// NO DEFAULTS ON THE THREE, deliberately. An unset colour uniform is black and
// adds nothing, so a curtain nobody handed data draws nothing -- which is the
// right failure. A plausible green here would be a second place the aurora's
// colour lives, and this project has already been bitten once by a definition's
// default quietly becoming the shipped value (see the note beside
// `data/weather/wind_valley.tres` in tests/unit/test_wind.gd).
uniform vec4 aurora_color_a : source_color;
uniform vec4 aurora_color_b : source_color;
uniform vec4 aurora_color_c : source_color;
uniform vec3 aurora_band_opacity = vec3(1.0, 0.72, 0.45);
uniform vec3 aurora_band_lift = vec3(0.0, 0.25, 0.50);
uniform vec3 aurora_band_offset = vec3(0.0, -0.31, 0.47);

const float PI_HALF = 1.5707963267948966;

// --- noise -------------------------------------------------------------------
//
// Value noise, hashed. No texture: a curtain that never repeats cannot be a
// texture, and the whole of this file has to run in a sky pass with nothing
// bound to it.
float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453123);
}

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise11(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

// Three octaves at irrational-ish ratios, normalised to 0..1. The offsets stop
// the octaves lining up at the origin, which would otherwise put one conspicuous
// bright ray at bearing zero in every showing.
float fbm11(float x) {
	float v = 0.5 * noise11(x);
	v += 0.25 * noise11(x * 2.137 + 11.31);
	v += 0.125 * noise11(x * 4.319 + 27.77);
	return v / 0.875;
}

// --- the star field ----------------------------------------------------------
//
// One candidate per cell of a cubic lattice laid over the direction sphere. The
// jitter is kept well inside the cell and the radius well under the jitter, so a
// star never straddles a boundary and a single-cell lookup finds all of them --
// which is what keeps this to four hashes instead of the twenty-seven a
// neighbourhood search would cost.
float star_field(vec3 dir) {
	vec3 p = dir * star_density;
	vec3 cell = floor(p);
	vec3 f = p - cell - 0.5;
	float h = hash31(cell);
	// Most cells are empty. The threshold is what sets the density in the sky
	// rather than the lattice spacing, so the two can be tuned apart.
	if (h < 0.955) {
		return 0.0;
	}
	vec3 jitter = vec3(
		hash31(cell + vec3(1.7, 0.0, 0.0)),
		hash31(cell + vec3(0.0, 2.3, 0.0)),
		hash31(cell + vec3(0.0, 0.0, 3.1))
	);
	jitter = (jitter - 0.5) * 0.6;
	float d = length(f - jitter);
	// Magnitude. A field of identical dots reads as noise; a field with a few
	// bright ones and many faint ones reads as a sky.
	float magnitude = fract(h * 91.7);
	float radius = star_radius * (0.35 + 0.65 * magnitude);
	float disc = smoothstep(radius, 0.0, d);
	disc *= disc;
	float twinkle = 0.78 + 0.22 * sin(TIME * (1.1 + magnitude * 2.9) + h * 37.0);
	return disc * mix(1.0, twinkle, star_twinkle) * (0.28 + 0.72 * magnitude);
}

// --- one curtain -------------------------------------------------------------
//
// `along` is the horizontal angle from the curtain's centre, `up` the elevation,
// both in radians. Returns 0..1 coverage.
//
// The three parts, and each one is a stated requirement:
//
//   RAYS       a coarse octave says where there is any curtain at all, a fine
//              pair says where the filaments are inside it. Both are functions
//              of `along` only, which is what makes them run vertically.
//   HEM        the lower edge is SOFT and DISSOLVES: its height is itself a
//              function of `along`, so neighbouring rays end at different
//              heights and the bottom breaks into tips instead of being cut off
//              by a line.
//   CROWN      the upper edge is DIFFUSE: a long fade, also per-column, so the
//              curtain thins away into the sky rather than stopping.
float curtain(float along, float up, float base, float top, float phase,
		float speed, float frequency) {
	float span = max(aurora_span, 0.0001);
	// Off the ends of the curtain rather than clipped at them.
	float across = clamp(abs(along) / span, 0.0, 1.0);
	float ends = 1.0 - smoothstep(0.55, 1.0, across);
	if (ends <= 0.0) {
		return 0.0;
	}

	// The ray coordinate. TIME drifts it sideways; the shear term leans a ray
	// over as it climbs, which is the difference between a curtain and a fence.
	float height = clamp((up - base) / max(top - base, 0.0001), 0.0, 1.0);
	float ray = along * frequency + phase;
	ray += aurora_shear * height;
	ray += TIME * speed;

	float coarse = fbm11(ray * 0.37);
	float fine = 0.62 * noise11(ray * 3.11 + 5.19) + 0.38 * noise11(ray * 7.73 + 19.41);
	float rays = coarse * mix(0.30, 1.0, pow(clamp(fine, 0.0, 1.0), aurora_ray_sharpness));

	// The hem, and the crown. Both wobble with `along` on their own slow
	// octaves, so the edges belong to the rays rather than to the band.
	float hem = base + (fbm11(ray * 0.23 + 3.7) - 0.5) * (top - base) * 0.38;
	float hem_soft = (top - base) * 0.30;
	float lower = smoothstep(hem, hem + hem_soft, up);

	float crown = top + (fbm11(ray * 0.19 + 8.1) - 0.5) * (top - base) * 0.44;
	float crown_soft = (top - base) * 0.62;
	float upper = 1.0 - smoothstep(crown - crown_soft, crown, up);

	return clamp(rays * lower * upper * ends, 0.0, 1.0);
}

// How bright this band is right now. Two sines whose periods are in an
// irrational ratio, times a slow noise on a third -- so the figure never comes
// back to where it was. See `aurora_drift`.
float breath(float phase, float slow, float fast) {
	float a = 0.5 + 0.5 * sin(TIME * slow + phase);
	float b = 0.5 + 0.5 * sin(TIME * fast + phase * 2.7);
	float c = noise11(TIME * slow * 0.41 + phase * 5.3);
	return clamp(0.36 + 0.40 * a + 0.16 * b + 0.20 * c, 0.0, 1.2);
}

void sky() {
	// ProceduralSkyMaterial's own gradient, reproduced. `sky_curve` and
	// `ground_curve` are exponents' denominators and a preset could in principle
	// author zero, which would be a division by zero rather than a flat sky.
	float v_angle = acos(clamp(EYEDIR.y, -1.0, 1.0));
	float c = 1.0 - v_angle / PI_HALF;
	vec3 upper = mix(
		sky_horizon_color.rgb,
		sky_top_color.rgb,
		clamp(1.0 - pow(1.0 - c, 1.0 / max(sky_curve, 0.001)), 0.0, 1.0)
	) * sky_energy;
	float g = (v_angle - PI_HALF) / PI_HALF;
	vec3 lower = mix(
		ground_horizon_color.rgb,
		ground_bottom_color.rgb,
		clamp(1.0 - pow(1.0 - g, 1.0 / max(ground_curve, 0.001)), 0.0, 1.0)
	) * ground_energy;
	vec3 col = mix(lower, upper, step(0.0, EYEDIR.y));

	// THE RADIANCE CUBEMAP GETS THE GRADIENT AND NOTHING ELSE.
	//
	// Nothing in this game samples it: LightingDirector sets
	// ambient_light_sky_contribution to 0 and disables reflections, and says so
	// in as many words. The aurora reaches the world through an explicit,
	// measurable light_tint overlay instead -- see
	// LightingDirector.set_world_light_overlay() -- so paying for stars and three
	// curtains across six cubemap faces every frame would buy a picture nobody
	// reads. The gradient stays, because that is what an ambient would want if
	// anyone ever switched one on.
	//
	// Written as an `if` around the body rather than as an early return, and that
	// is not a style choice: **`return` inside `sky()` is a compile error on
	// 4.7.1** -- "Using 'return' in the 'sky' processor function is incorrect."
	// The same holds for `vertex()`, `fragment()` and `light()`; ordinary
	// functions like `curtain()` above are unaffected.
	if (!AT_CUBEMAP_PASS) {
		float above = smoothstep(0.0, star_horizon_fade, EYEDIR.y);

		if (star_amount > 0.0) {
			col += star_color.rgb * star_field(EYEDIR) * star_amount * above;
		}

		if (aurora_strength > 0.0) {
			// The curtain's own frame: `forward` points along the bearing, `right`
			// across it. `along` is then the horizontal angle from its centre and
			// `up` the elevation, which is the pair every band is drawn in.
			float s = sin(aurora_bearing);
			float k = cos(aurora_bearing);
			vec3 forward = vec3(s, 0.0, -k);
			vec3 right = vec3(k, 0.0, s);
			float along = atan(dot(EYEDIR, right), dot(EYEDIR, forward));
			float up = asin(clamp(EYEDIR.y, -1.0, 1.0));

			float depth = aurora_top - aurora_base;
			// ADDED, not mixed, and that is what makes it semi-transparent: the
			// stars and the gradient underneath are still in the answer wherever
			// the curtain is not opaque. It is also what an emissive sheet of
			// excited air actually does to a photograph.
			vec3 lit = vec3(0.0);
			lit += aurora_color_a.rgb * aurora_band_opacity.x * breath(0.0, 0.113, 0.291)
				* curtain(along + aurora_band_offset.x, up,
					aurora_base + depth * aurora_band_lift.x,
					aurora_top + depth * aurora_band_lift.x,
					0.0, aurora_drift, aurora_ray_frequency);
			lit += aurora_color_b.rgb * aurora_band_opacity.y * breath(2.13, 0.079, 0.197)
				* curtain(along + aurora_band_offset.y, up,
					aurora_base + depth * aurora_band_lift.y,
					aurora_top + depth * aurora_band_lift.y,
					13.7, aurora_drift * 1.618, aurora_ray_frequency * 0.73);
			lit += aurora_color_c.rgb * aurora_band_opacity.z * breath(4.71, 0.053, 0.131)
				* curtain(along + aurora_band_offset.z, up,
					aurora_base + depth * aurora_band_lift.z,
					aurora_top + depth * aurora_band_lift.z,
					29.3, aurora_drift * 0.577, aurora_ray_frequency * 1.31);

			col += lit * aurora_strength * aurora_opacity * above;
		}

		// The dither ProceduralSkyMaterial applies under `use_debanding`. Half a
		// least-significant bit of noise, which is invisible and is the difference
		// between a gradient and a staircase.
		if (debanding > 0.0) {
			float dither = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233) * 2.0)) * 43758.5453);
			col += (dither * 0.00196078431 - 0.00098039215) * debanding;
		}
	}

	COLOR = col;
}
