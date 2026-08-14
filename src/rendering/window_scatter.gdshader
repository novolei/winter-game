shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, ambient_light_disabled, fog_disabled;

// One material draws two deliberately small pieces of air: the rectangular
// corona around the pane and the tapered shaft between the pane and the porch
// roof. This is light in air, not an albedo texture on the world, so its soft
// edge does not weaken the project's two-band surface language.
uniform vec4 light_color : source_color;
uniform float intensity : hint_range(0.0, 8.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.10;
uniform float edge_softness : hint_range(0.01, 0.49) = 0.18;
uniform bool halo_mode = false;

float soft_box(vec2 uv, float edge) {
	float x = smoothstep(0.0, edge, uv.x) * (1.0 - smoothstep(1.0 - edge, 1.0, uv.x));
	float y = smoothstep(0.0, edge, uv.y) * (1.0 - smoothstep(1.0 - edge, 1.0, uv.y));
	return x * y;
}

void fragment() {
	float edge = clamp(edge_softness, 0.01, 0.49);
	float halo = soft_box(UV, edge);
	float sides = smoothstep(0.0, edge, UV.x) * (1.0 - smoothstep(1.0 - edge, 1.0, UV.x));
	float leaves_pane = smoothstep(0.0, 0.10, UV.y);
	float loses_itself = 1.0 - smoothstep(0.52, 1.0, UV.y);
	float shaft = sides * leaves_pane * loses_itself;
	float mask = halo_mode ? halo : shaft;
	float energy = max(intensity, 0.0);
	ALBEDO = light_color.rgb;
	EMISSION = light_color.rgb * energy;
	ALPHA = mask * opacity * clamp(energy, 0.0, 1.0);
}
