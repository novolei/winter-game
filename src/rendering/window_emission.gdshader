shader_type spatial;
render_mode unshaded, specular_disabled, ambient_light_disabled, fog_disabled;

// A window is both a pane and a promise. The cold colour is the same darkest
// structural palette entry used by every unlit pane; the warm colour is read
// from ColorBible by FarmhouseWindowLight. No colour is authored in shader
// source, and a dead stove can therefore take the pane all the way back to the
// surrounding winter instead of leaving an orange sticker behind.
uniform vec4 cold_color : source_color;
uniform vec4 warm_color : source_color;
uniform float warmth : hint_range(0.0, 1.0) = 0.0;
uniform float emission_energy : hint_range(0.0, 8.0) = 0.0;
uniform vec2 pane_center = vec2(0.0);
uniform vec2 pane_size = vec2(1.0);
uniform float muntin_strength : hint_range(0.0, 1.0) = 0.88;
varying vec2 pane_uv;

void vertex() {
	pane_uv = (VERTEX.xy - pane_center) / max(pane_size, vec2(0.001)) + vec2(0.5);
}

void fragment() {
	float source = clamp(warmth, 0.0, 1.0);
	float edge_distance = min(
		min(pane_uv.x, 1.0 - pane_uv.x),
		min(pane_uv.y, 1.0 - pane_uv.y)
	);
	float core = smoothstep(0.0, 0.24, edge_distance);
	float vertical = 1.0 - smoothstep(0.030, 0.052, abs(pane_uv.x - 0.5));
	float horizontal_a = 1.0 - smoothstep(0.022, 0.044, abs(pane_uv.y - 0.333));
	float horizontal_b = 1.0 - smoothstep(0.022, 0.044, abs(pane_uv.y - 0.667));
	float muntin = max(vertical, max(horizontal_a, horizontal_b)) * clamp(muntin_strength, 0.0, 1.0);
	float transmission = mix(1.0, 0.10, muntin);
	float emission_shape = mix(0.58, 1.12, core) * transmission;
	float albedo_shape = mix(0.78, 1.0, core) * transmission;
	ALBEDO = mix(cold_color.rgb, warm_color.rgb, source * albedo_shape);
	// emission_energy already contains the continuous fire and reveal factors.
	// Multiplying by source again would square both fades and make the final
	// minute of fuel collapse unnaturally fast; source shapes albedo only.
	EMISSION = warm_color.rgb * max(emission_energy, 0.0) * emission_shape;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
