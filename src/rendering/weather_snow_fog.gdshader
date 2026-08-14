shader_type fog;

// One normalized, seamless field is read at two world scales. The broad read
// supplies the veil; the lighter second read breaks its edge. Motion comes from
// an integrated world-space offset supplied by the runtime, never from TIME.

uniform sampler3D density_noise : repeat_enable, filter_linear;
uniform float fog_density = 0.0;
uniform float peak_density = 0.0;
uniform vec3 fog_albedo;
uniform vec3 macro_scale_m = vec3(12.0, 5.0, 8.0);
uniform vec3 detail_scale_m = vec3(4.5, 2.5, 3.0);
uniform float detail_weight = 0.28;
uniform float noise_contrast = 0.30;
uniform vec3 advection_offset = vec3(0.0);

uniform vec3 camera_position = vec3(0.0);
uniform vec3 camera_forward = vec3(0.0, 0.0, -1.0);
uniform float near_clear_depth = 76.0;
uniform float near_full_depth = 88.0;
uniform float far_fade_start = 112.0;
uniform float far_fade_end = 128.0;


void fog() {
	float depth = dot(WORLD_POSITION - camera_position, normalize(camera_forward));
	float near_gate = smoothstep(near_clear_depth, near_full_depth, depth);
	float far_gate = 1.0 - smoothstep(far_fade_start, far_fade_end, depth);
	float depth_window = near_gate * far_gate;

	vec3 macro_uv = fract((WORLD_POSITION - advection_offset) / max(macro_scale_m, vec3(0.001)));
	vec3 detail_uv = fract((WORLD_POSITION - advection_offset * 1.37) / max(detail_scale_m, vec3(0.001)));
	float macro_noise = texture(density_noise, macro_uv).r;
	float detail_noise = texture(density_noise, detail_uv).r;
	float combined = mix(macro_noise, detail_noise, clamp(detail_weight, 0.0, 0.5));
	float contrast = clamp(noise_contrast, 0.0, 0.75);
	float veil = clamp(1.0 + (combined - 0.5) * 2.0 * contrast, 1.0 - contrast, 1.0 + contrast);

	DENSITY = min(max(fog_density, 0.0) * veil * depth_window, min(max(peak_density, 0.0), 0.064));
	ALBEDO = fog_albedo;
}
