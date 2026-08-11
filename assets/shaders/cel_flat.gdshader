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

void fragment() {
	// White on purpose -- see snow_ground.gdshader. Godot multiplies
	// DIFFUSE_LIGHT by ALBEDO after the light loop, so the palette colour is
	// chosen once, in light(), and never squared.
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float lambert = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float band = smoothstep(band_threshold - band_softness, band_threshold + band_softness, lambert * ATTENUATION);
	DIFFUSE_LIGHT += mix(shade_color.rgb, lit_color.rgb * light_tint, band);
}
