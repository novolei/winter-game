shader_type spatial;

// The same two-band selection as snow_ground.gdshader, for everything that is
// not the ground: the player, the blocked-out sheds, the tree silhouettes.
//
// Both bands are palette colours. Set them to the same value for a pure
// silhouette (the trees, Art Bible rule 7).
render_mode ambient_light_disabled, specular_disabled, diffuse_lambert;

uniform vec4 lit_color : source_color;
uniform vec4 shade_color : source_color;

// DRIVEN PER PRESET, through CelPainter.set_world_shading(). LightingDirector
// pushes LightingPreset.cel_band_threshold and .cel_band_softness on every
// write, so a solid falls further into its shadow band as the light goes. These
// are the fallback for a material built before anything is lit.
uniform float band_threshold = 0.30;
uniform float band_softness = 0.07;

// The colour the LIT band takes from the light -- see snow_ground.gdshader,
// which carries the reasoning. The two have to agree: the snow lying on a shed
// roof is painted with the same palette tone as the snow lying beside it, so a
// warm light that reached one and not the other would draw the roof line as a
// change of material.
//
// Not `source_color`: a linear multiplier, above 1.0 on the red channel
// whenever the light is warm.
uniform vec3 light_tint = vec3(1.0);

// ---------------------------------------------------------------------------
// THE SNOW THAT SETTLES ON IT
// ---------------------------------------------------------------------------
// Style document section 17, and the owner's 积雪 brief: snow lies on whatever
// faces the sky -- roof planes, branches, the pole's crossarm, window sills,
// the truck's bonnet -- and it arrives over time rather than being there or
// not. src/systems/snow_accumulation.gd owns the one scalar; every surface in
// the world reads it, and nothing is authored per object.
//
// WHY THIS MOVES A THRESHOLD RATHER THAN MIXING A COLOUR BY A DEPTH. Exactly
// the argument snow_ground.gdshader's grain block makes. Interpolating a
// surface toward white by the accumulation would be a gradient, which Art Bible
// rule 8 forbids, and every value along the way would be off the twelve. So the
// accumulation moves the LINE the snow lies above -- a cel boundary, like the
// two bands themselves -- and every pixel stays a palette entry with only the
// boundary's own smoothstep between them.
//
// WHY IT NEEDS THE NOISE, and this is the part that keeps the owner's 切记突变
// on a flat surface. A roof plane has ONE world normal across the whole of it,
// so a bare normal.y threshold flips the entire plane in a single frame however
// slowly the scalar moves -- a continuous input producing a discontinuous
// picture, which is the exact failure the whole feature is judged on. Adding a
// world-space noise to the normal's Y gives every point on the plane its own
// slightly different line, so the boundary CREEPS ACROSS the roof as the
// accumulation rises instead of arriving all at once. The snow spreads.
//
// TWO INVARIANTS, which tests/unit/test_snow_accumulation.gd asserts against
// CelPainter's constants rather than trusting the numbers here:
//
//   snow_bare_threshold - snow_edge_softness > 1 + snow_noise_strength
//       At cover 0 nothing anywhere is covered, whatever its normal. A world
//       that ships with a fleck of snow it never asked for has no bare state to
//       accumulate from.
//   snow_full_threshold - snow_edge_softness > snow_noise_strength
//       A vertical wall is never covered, at any cover. Style document section
//       18: 房屋墙体 -- 不要用.
uniform vec4 snow_lit : source_color = vec4(1.0);
uniform vec4 snow_shade : source_color = vec4(1.0);

// 0 bare .. 1 as covered as this weather gets. Pushed every frame by
// TerrainRenderer from SnowAccumulation.cover().
uniform float snow_cover = 0.0;

// Per palette colour, not per object: 0 keeps a surface bare whatever lies on
// everything around it. CelPainter sets it, and sets it for exactly one of the
// twelve -- see CelPainter.WARM_LIGHT_INDEX.
uniform float snow_receptivity = 1.0;

// Where the snow line sits at cover 0 and at cover 1, in normal.y. CelPainter
// owns the authored values; these are the fallback for a material built before
// it has said anything.
uniform float snow_bare_threshold = 1.50;
uniform float snow_full_threshold = 0.45;
uniform float snow_edge_softness = 0.05;

// 1/wavelength, in world metres. 0.75 is a 1.33 m patch, which is the size the
// six snow patches modelled onto the farmhouse roof already are -- so the snow
// the shader grows between them reads as more of the same thing rather than as
// a second, finer effect laid over it. Measured up from 1.7 (0.6 m) after the
// first capture: at that scale a roof came out speckled rather than drifted.
uniform float snow_noise_scale = 0.75;
uniform float snow_noise_strength = 0.30;

varying vec3 v_world;
varying vec3 v_world_normal;

// Value noise. The same hash snow_ground.gdshader uses, in three dimensions
// rather than two, because a wall and the roof above it are at the same XZ and
// must not be handed the same number.
float snow_hash(vec3 p) {
	p = fract(p * vec3(123.34, 456.21, 314.15));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y * p.z);
}

float snow_cell(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x00 = mix(snow_hash(i + vec3(0.0, 0.0, 0.0)), snow_hash(i + vec3(1.0, 0.0, 0.0)), f.x);
	float x10 = mix(snow_hash(i + vec3(0.0, 1.0, 0.0)), snow_hash(i + vec3(1.0, 1.0, 0.0)), f.x);
	float x01 = mix(snow_hash(i + vec3(0.0, 0.0, 1.0)), snow_hash(i + vec3(1.0, 0.0, 1.0)), f.x);
	float x11 = mix(snow_hash(i + vec3(0.0, 1.0, 1.0)), snow_hash(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

// Two octaves, for the same reason the ground's grain uses two: one octave of
// value noise is a grid, and at the patch size the roof wants you can see the
// cells it was built on. The second breaks them up without changing the size of
// the drift, and the weights sum to 1 so the range stays 0..1 and the two
// invariants above still hold exactly.
float snow_noise(vec3 p) {
	return snow_cell(p) * 0.76 + snow_cell(p * 2.3 + vec3(11.7, 5.3, 3.1)) * 0.24;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// World space, and it has to be built here: NORMAL is model space in
	// vertex() and VIEW space in fragment(), so reading it in fragment() and
	// calling the result "up" would tie which way is up to where the camera is
	// looking.
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// White on purpose -- see snow_ground.gdshader. Godot multiplies
	// DIFFUSE_LIGHT by ALBEDO after the light loop, so the palette colour is
	// chosen once, in light(), and never squared. That is also why the snow
	// blend below is in light() and not here: written into ALBEDO it would come
	// out multiplied twice, which does not look like a bug, it looks like the
	// art direction being a bit dark.
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float lambert = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float band = smoothstep(band_threshold - band_softness, band_threshold + band_softness, lambert * ATTENUATION);

	float cover = clamp(snow_cover * snow_receptivity, 0.0, 1.0);
	float topness = normalize(v_world_normal).y
		+ (snow_noise(v_world * snow_noise_scale) * 2.0 - 1.0) * snow_noise_strength;
	float snow_line = mix(snow_bare_threshold, snow_full_threshold, cover);
	float lying = smoothstep(snow_line - snow_edge_softness, snow_line + snow_edge_softness, topness);

	// Both bands take the snow, so a covered surface is lit and shaded by the
	// same pair the ground uses. Snow lying on a shed roof and snow lying beside
	// it are then the same two colours, which is the whole point of the roof not
	// announcing itself as a different material.
	vec3 lit = mix(lit_color.rgb, snow_lit.rgb, lying);
	vec3 shade = mix(shade_color.rgb, snow_shade.rgb, lying);
	DIFFUSE_LIGHT += mix(shade, lit * light_tint, band);
}
