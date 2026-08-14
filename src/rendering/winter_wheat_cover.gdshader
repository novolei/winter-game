shader_type spatial;

// A low winter-wheat crown: the lower leaves disappear into settled snow and
// only the soft upper leaf tips retain the field's dark structure tone.
// CelPainter drives the light and snow uniforms, so this one material follows
// the rest of the world through both time of day and accumulation.
render_mode ambient_light_disabled, specular_disabled, cull_disabled, diffuse_lambert;

uniform vec4 wheat_lit : source_color;
uniform vec4 wheat_shade : source_color;
uniform vec4 snow_lit : source_color;
uniform vec4 snow_shade : source_color;
uniform float band_threshold = 0.30;
uniform float band_softness = 0.07;
uniform vec3 light_tint = vec3(1.0);
uniform float snow_cover = 0.0;

varying float leaf_tip;

void vertex() {
	leaf_tip = UV.y;
}

void fragment() {
	// White is the identity for Godot's post-light ALBEDO multiply.  The actual
	// palette colours are selected outright in light(), never multiplied.
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	// The leaves lie low enough that snow eats their base, but their outer half
	// still reads as a continuous young crop rather than isolated dark pins.
	float snow_line = clamp(0.48 + snow_cover * 0.30, 0.0, 0.90);
	float exposed = smoothstep(snow_line, min(snow_line + 0.28, 1.0), leaf_tip);
	float lambert = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float band = smoothstep(
		band_threshold - band_softness,
		band_threshold + band_softness,
		lambert * ATTENUATION
	);
	vec3 lit = mix(snow_lit.rgb, wheat_lit.rgb, exposed);
	vec3 shade = mix(snow_shade.rgb, wheat_shade.rgb, exposed);
	DIFFUSE_LIGHT += mix(shade, lit * light_tint, band);
}
