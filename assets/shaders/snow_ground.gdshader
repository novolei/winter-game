shader_type spatial;

// Two-band cel shading for the snow field (Art Bible rule 8/9/10).
//
// The two bands are *selected*, never computed: the shadow band is a colour
// taken from the 12-colour palette, not the lit colour multiplied by a factor.
// A multiply produces off-palette colours, which is the one thing rule 9
// forbids. `ambient_light_disabled` is what makes that guarantee hold -- with
// ambient added on top, the shadow band would drift off-palette again.
//
// The height and track lookups here are byte-for-byte the same formula
// SnowField.depth_at() and TrackMask.value_at() use on the CPU, so what the
// player wades through is what the screen draws.
render_mode ambient_light_disabled, specular_disabled, diffuse_lambert;

// SnowField: 512x512 over field_extent metres, both layers world-anchored at
// field_origin (the world XZ of texel 0,0).
//
// snow_terrain holds normalised ground height. Everything else is derived from
// it, by the same three lines SnowField uses on the CPU:
//
//   ground  = drift_relief(terrain - 0.5) * terrain_amplitude
//   depth   = max_depth * scour(terrain) * (1 - packed)
//   surface = ground + depth
//
// The wind strips the crests and dumps the snow in the hollows, so depth is a
// function of the terrain rather than a second noise. One texture answers both
// "how high is the ground here" and "how deep is the snow on it".
uniform sampler2D snow_terrain : filter_linear, repeat_disable;
uniform sampler2D snow_packed : filter_linear, repeat_disable;
uniform vec2 field_origin = vec2(-60.0, -60.0);
uniform float field_extent = 120.0;
uniform float terrain_amplitude = 3.4;
uniform float terrain_contrast = 1.45;
// The drift profile. SnowField.drift_relief() is these same three lines: the
// relief is a curve on the noise, not a multiple of it, so the field is gentle
// where the noise is near its mean and banks into a real drift only out at the
// tails. The reasoning is in src/systems/snow_field.gd; the numbers arrive from
// terrain_renderer.gd so there is one place to change them.
uniform float drift_flatten = 0.34;
uniform float drift_sharpness = 3.0;
uniform float max_depth = 1.05;
uniform float scour_hollow = 0.36;
uniform float scour_crest = 0.72;

// TrackMask, dynamic layer: one image, any number of prints. A thousand
// footprints cost the same as one because they are all already composited into
// this texture. The window follows the player.
uniform sampler2D track_mask : filter_linear, repeat_disable;
uniform vec2 track_origin = vec2(-45.0, -45.0);
uniform float track_extent = 90.0;

// TrackMask, static layer: ploughed furrows and old tyre tracks, baked once
// into a window that is fixed in the world (Art Bible section 3). Read exactly
// like the dynamic layer and combined with max(), because a furrow and a boot
// print are the same kind of mark in the snow -- the split exists so the wind
// can erase one of them and not the other, not so they can look different.
//
// hint_default_black matters: an unassigned sampler2D reads as *white* in
// Godot, which would render the entire field as one flat track-toned slab if
// this uniform were ever left unset.
uniform sampler2D static_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec2 static_origin = vec2(-60.0, -60.0);
uniform float static_extent = 120.0;

// A print is 29 cm long. The ground mesh has 44 cm quads, so the mesh cannot
// represent one -- pushing the vertices down was what produced the radiating
// shards around every footprint. So a print is not geometry: it is a dent in
// the *normal*, at the depth below, reconstructed per pixel. The mesh carries
// metre-scale relief and the normal carries centimetre-scale relief, and each
// is asked only for what it can actually resolve.
uniform float track_depth = 0.05;

// The ridge of snow pushed out around a print, in metres, and how far up the
// mask's falloff it sits. Small: a rim you can see the shape of, not a crater.
uniform float track_rim = 0.014;
uniform float track_rim_extent = 0.4;

// How far the print's colour shifts toward the track tones. Low on purpose:
// with the normal doing the work a print reads as a dent, and leaning on
// colour as well is what made them look like dark smudges stamped on top.
uniform float track_tint = 0.5;

// The two scales the normal is rebuilt at. The wide one skips over the height
// field's own 23 cm texel grid, which at this grazing sun would otherwise lay
// a corduroy pattern across the whole field; the narrow one is small enough to
// resolve a boot.
uniform float ground_normal_epsilon = 0.8;
uniform float track_normal_epsilon = 0.06;

// All five from data/palette/color_bible.tres, uploaded by terrain_renderer.gd.
uniform vec4 snow_lit : source_color;
uniform vec4 snow_shade : source_color;
uniform vec4 track_lit : source_color;
uniform vec4 track_shade : source_color;
// The grain's second tone -- one step down the same family from snow_lit. See
// the grain block in light().
uniform vec4 snow_grain_tone : source_color;

// The sun sits ~11 degrees above the horizon, so N.L on flat ground is only
// about 0.19. The threshold has to sit below that or the whole field reads as
// shadow; the softness is what gives the shadow edge its feathered border.
//
// DRIVEN PER PRESET. LightingDirector pushes LightingPreset.cel_band_threshold
// and .cel_band_softness through TerrainRenderer every frame, so more of the
// field falls into the shadow band as the light goes. The values here are the
// fallback for a frame before anything is lit.
uniform float band_threshold = 0.09;
uniform float band_softness = 0.05;

// THE COLOUR THE LIT BAND TAKES FROM THE LIGHT, and the only route warm light
// has to the snow.
//
// The two bands SELECT palette colours, so a preset could change the world's
// brightness and its haze and never its hue -- which is why SUNRISE warmed the
// buildings (fog moves dark surfaces further than light ones) and left the snow
// cold lavender. This multiplies the LIT band only. LightingDirector normalises
// it to unit luminance before pushing it, so it rotates the hue and does not
// touch the brightness the preset's exposure was tuned against.
//
// The SHADE band is deliberately untinted: warm sun on cold shadow is what a
// winter dawn is, and it is what keeps Art Bible section 4.1's promise that the
// shadow band is a palette colour chosen outright rather than a computed one.
//
// Not `source_color`: this is a linear multiplier, not a colour to be looked at,
// and its red channel goes above 1.0 whenever the light is warm.
uniform vec3 light_tint = vec3(1.0);

// THE SNOW GRAIN -- style document section 15, made legal.
//
// The field was one flat fill. The document asks for it to vary slightly, and
// says in as many words that you should barely be able to see it. Interpolating
// the snow colour by a noise is the obvious implementation and it breaks two
// rules at once: Art Bible rule 8 forbids gradients, and every value in the
// document's own example is outside the twelve.
//
// So the noise moves a BAND BOUNDARY instead. The lit band splits across a
// second, higher threshold that flat ground straddles -- flat ground is at
// N.L = sin(21.5) = 0.366 -- and the noise jitters where that boundary falls.
// Which of two adjacent palette tones a patch of snow takes then varies, every
// pixel is still exactly a palette entry, and it is dithering between discrete
// steps rather than a ramp between them.
//
// grain_amount is measured against the Lambert spread the terrain's own slopes
// produce, about +/-0.06. Much past that and the jitter reads as bumpiness the
// ground does not have and fights the drifts that are actually there.
uniform float grain_threshold = 0.38;
uniform float grain_softness = 0.03;
uniform float grain_amount = 0.05;
uniform float grain_scale = 0.14;

varying vec3 v_world;

// Value noise, and nothing else borrowed from the style document's shader --
// its render_mode line carries `specular_schlick_ggx` and its fragment() sets
// ROUGHNESS and SPECULAR, all three of which Art Bible rule 8 forbids outright.
float grain_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float grain_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(grain_hash(i), grain_hash(i + vec2(1.0, 0.0)), f.x),
		mix(grain_hash(i + vec2(0.0, 1.0)), grain_hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

// The heightfield covers 120 m; the drawn plane is wider than that so the
// frame never contains the field's own edge or the horizon behind it. Outside
// the window the ground settles to the noise's mean and goes flat -- which is
// what distant snow looks like in the reference anyway. Without the fade,
// repeat_disable would clamp to the border texels and streak them out to the
// edge of the world.
//
// The ramp is wide (14% of the window, about 17 m) because the terrain now has
// metres of relief: a short ramp turns the window boundary into a visible ring
// of ground sloping down to the mean, and that ring travels with the player.
float window_falloff(vec2 uv) {
	vec2 to_edge = min(uv, vec2(1.0) - uv);
	return smoothstep(0.0, 0.14, min(to_edge.x, to_edge.y));
}

float terrain_at(vec2 w) {
	vec2 uv = (w - field_origin) / field_extent;
	float raw = mix(0.5, textureLod(snow_terrain, uv, 0.0).r, window_falloff(uv));
	return clamp((raw - 0.5) * terrain_contrast + 0.5, 0.0, 1.0);
}

float packed_at(vec2 w) {
	vec2 uv = (w - field_origin) / field_extent;
	return textureLod(snow_packed, uv, 0.0).r * window_falloff(uv);
}

// repeat_disable clamps to the edge texel, which would smear the outermost
// footprint across the rest of the world. Outside a window there are no tracks,
// so say so.
float layer_at(sampler2D layer, vec2 w, vec2 layer_origin, float layer_extent) {
	vec2 uv = (w - layer_origin) / layer_extent;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	return textureLod(layer, uv, 0.0).r;
}

float track_at(vec2 w) {
	return max(
		layer_at(track_mask, w, track_origin, track_extent),
		layer_at(static_mask, w, static_origin, static_extent)
	);
}

float drift_relief(float signed_height) {
	float crest = pow(abs(signed_height * 2.0), drift_sharpness);
	return signed_height * (drift_flatten + (1.0 - drift_flatten) * crest);
}

// Metre-scale, and the only part the mesh is asked to draw.
float ground_height(vec2 w) {
	float terrain = terrain_at(w);
	float ground = drift_relief(terrain - 0.5) * terrain_amplitude;
	float scour = 1.0 - smoothstep(scour_hollow, scour_crest, terrain);
	return ground + max_depth * scour * (1.0 - packed_at(w));
}

// Centimetre-scale, and only ever seen through the normal.
//
// The second term is the snow the boot pushed outward. The mask cannot store a
// negative -- it is an R8 image and 0 means untouched -- so the rim is derived
// from the mask's own profile instead: a bump that peaks in the outer skirt of
// a print, where the value is low but not zero, and vanishes both at the centre
// and inside the pressed core. It costs one extra line and it is most of what
// makes a deep print read as displaced snow rather than as a dent.
float track_height(vec2 w) {
	float t = track_at(w);
	float skirt = clamp(t / track_rim_extent, 0.0, 1.0);
	float rim = 4.0 * skirt * (1.0 - skirt);
	return -t * track_depth + rim * track_rim;
}

// Slope of the ground, by central difference at a scale wide enough to step
// over the height field's texel grid.
vec2 ground_gradient(vec2 w, float e) {
	float xr = ground_height(w + vec2(e, 0.0));
	float xl = ground_height(w - vec2(e, 0.0));
	float zr = ground_height(w + vec2(0.0, e));
	float zl = ground_height(w - vec2(0.0, e));
	return vec2(xr - xl, zr - zl) / (2.0 * e);
}

// Slope of the footprints, at a scale small enough to resolve one.
vec2 track_gradient(vec2 w, float e) {
	float xr = track_height(w + vec2(e, 0.0));
	float xl = track_height(w - vec2(e, 0.0));
	float zr = track_height(w + vec2(0.0, e));
	float zl = track_height(w - vec2(0.0, e));
	return vec2(xr - xl, zr - zl) / (2.0 * e);
}

void vertex() {
	// The ground plane is translated, never rotated or scaled, so its world XZ
	// is just the local XZ plus the model origin -- no inverse() per vertex.
	vec3 w = VERTEX + MODEL_MATRIX[3].xyz;
	float h = ground_height(w.xz);
	VERTEX.y += h;
	w.y += h;
	v_world = w;

	// A coarse normal, so the shadow pass and any fallback path have something
	// sane. The normal that actually gets lit is rebuilt per pixel below --
	// interpolating this one across a 44 cm triangle is what facets a drift.
	vec2 g = ground_gradient(w.xz, ground_normal_epsilon);
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
}

void fragment() {
	// The normal is reconstructed here, not interpolated from the vertices,
	// and it is the single fix for both kinds of faceting: the shard pattern
	// around every footprint and the flat triangles across every drift. Two
	// scales because the surface has two: metres of dune and centimetres of
	// boot. For a height field h, the normal is (-dh/dx, 1, -dh/dz).
	vec2 ground_slope = ground_gradient(v_world.xz, ground_normal_epsilon);
	// A print is pressed along the *surface* normal, not along world Y. The
	// mask stores a vertical displacement, and a vertical displacement on a
	// tilted surface is only cos(slope) as deep measured perpendicular to it --
	// so prints on a flank read shallower than the same print on the flat,
	// which is backwards. Dividing by cos(slope), which is
	// 1/sqrt(1 + |grad|^2), restores it.
	float perpendicular = sqrt(1.0 + dot(ground_slope, ground_slope));
	vec2 slope = ground_slope
		+ track_gradient(v_world.xz, track_normal_epsilon) * perpendicular;
	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	// NORMAL is view space in fragment(), unlike in vertex() where it is model
	// space. Writing a world-space vector straight in lights the ground from
	// wherever the camera happens to be looking.
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	// White, and that is load-bearing. Godot multiplies the accumulated
	// DIFFUSE_LIGHT by ALBEDO after the light loop, so putting the snow colour
	// here as well would square it -- #8FB0D8 came out as #4D75B5 on the first
	// run. The colour is chosen once, in light(), and reaches the screen
	// untouched.
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float lambert = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	// ATTENUATION carries the directional light's shadow term, already
	// softened by the shadow filter, so folding it in here is what makes the
	// long cast shadows land in the dark band with a soft edge.
	float shaded = lambert * ATTENUATION;
	float band = smoothstep(band_threshold - band_softness, band_threshold + band_softness, shaded);

	// The grain, as a second boundary inside the lit band. Two octaves so the
	// patches do not all arrive at one wavelength, mapped to -1..1 and added to
	// the Lambert term -- which is the same thing as subtracting it from the
	// threshold, written the way round that keeps `grain_threshold` readable as
	// "the slope this splits at".
	//
	// It composes with band_threshold rather than replacing it: the preset
	// decides where the shadow starts, this decides how the lit field varies.
	float grain = grain_noise(v_world.xz * grain_scale)
		+ 0.35 * grain_noise(v_world.xz * grain_scale * 2.7);
	grain = (grain / 1.35 - 0.5) * 2.0;
	float grain_band = smoothstep(
		grain_threshold - grain_softness,
		grain_threshold + grain_softness,
		shaded + grain * grain_amount
	);
	vec3 snow_surface = mix(snow_grain_tone.rgb, snow_lit.rgb, grain_band);

	// Scaled down by track_tint: the print is a dent now, drawn by the normal,
	// and the colour is only there to keep it readable at a distance where the
	// shading detail is a pixel wide. At full strength it went back to being a
	// sticker on the snow.
	float t = track_at(v_world.xz) * track_tint;
	vec3 lit = mix(snow_surface, track_lit.rgb, t);
	vec3 shade = mix(snow_shade.rgb, track_shade.rgb, t);
	// LIGHT_COLOR is deliberately not a factor: the band picks a palette
	// colour outright. That is the only way the shadow band is guaranteed to
	// still be a palette colour once it reaches the screen. `light_tint` is not
	// LIGHT_COLOR -- it is an authored, luminance-normalised hue rotation on the
	// lit band alone, and the shade band never sees it.
	DIFFUSE_LIGHT += mix(shade, lit * light_tint, band);
}
