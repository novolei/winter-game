shader_type particles;

// Weather accent motion. The shared Snowfall layers already provide depth and
// density; this shader supplies the individual flakes that make a weather event
// legible: curved paths, mass in changing wind, and a tumble that loses energy.
//
// The stock ParticleProcessMaterial turbulence is deliberately not used here.
// Godot mixes the WHOLE velocity toward its noise field, which this project has
// measured to erase most of a long-lived snowflake's fall. Here curl is a FORCE,
// projected across horizontal travel, so it cannot turn gravity into suspension.
// Godot integrates VELOCITY after process(); do not integrate position here too.

uniform vec3 volume_extents = vec3(17.0, 8.0, 15.0);
uniform vec3 travel_direction = vec3(0.0, -1.0, 0.0);
uniform vec2 speed_range = vec2(1.0, 2.0);
uniform float spread_degrees = 12.0;
uniform vec2 scale_range = vec2(0.75, 1.25);
uniform float fall_acceleration = 0.2;

// Exponential response toward the live air, in 1/s. Each particle rolls its own
// rate once at birth, so heavy and light flakes do not change heading together.
uniform vec2 damping_range = vec2(0.0);

// Lateral acceleration in m/s^2, approximate eddy width in metres, and field
// evolution in eddy-widths per second.
uniform vec2 turbulence_influence_range = vec2(0.0);
uniform float turbulence_scale = 0.8;
uniform float turbulence_drift = 0.12;

// Pose is authored as three gestures rather than one motor-like angular speed:
// a slow rock, a smaller flutter and an occasional eased half-turn. All values
// are rolled once per flake and evaluated analytically from age, so the same
// flake has the same pose at every simulation rate.
uniform vec2 angular_velocity_range = vec2(0.0);
uniform float angular_damping = 0.0;
uniform vec2 rock_amplitude_range = vec2(0.0);
uniform vec2 rock_frequency_range = vec2(0.0);
uniform float rock_end_multiplier = 1.0;
uniform vec2 flutter_amplitude_range = vec2(0.0);
uniform vec2 flutter_frequency_range = vec2(0.0);
uniform float flip_probability = 0.0;
uniform vec2 flip_duration_range = vec2(0.0);
uniform float flip_edge_scale = 1.0;


float roll(float base, float salt) {
	return fract(sin((base + salt) * 12.9898) * 43758.5453);
}


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


vec3 cone_direction(vec3 centre, float spread, float seed) {
	vec3 axis = normalize(centre);
	vec3 helper = abs(axis.y) < 0.98 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(helper, axis));
	vec3 bitangent = cross(axis, tangent);
	float azimuth = roll(seed, 7.3) * 6.2831853;
	float radius = tan(spread * 0.0174532925) * sqrt(roll(seed, 11.5));
	vec3 offset = (tangent * cos(azimuth) + bitangent * sin(azimuth)) * radius;
	return normalize(axis + offset);
}


void start() {
	float seed = float(NUMBER) + float(RANDOM_SEED) * 0.00013;
	vec3 local_position = vec3(
		roll(seed, 1.7) * 2.0 - 1.0,
		roll(seed, 3.1) * 2.0 - 1.0,
		roll(seed, 5.9) * 2.0 - 1.0
	) * volume_extents;
	TRANSFORM[3].xyz = (EMISSION_TRANSFORM * vec4(local_position, 1.0)).xyz;

	float size = mix(scale_range.x, scale_range.y, roll(seed, 13.7));
	TRANSFORM[0].xyz = vec3(size, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, size, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, size);

	float speed = mix(speed_range.x, speed_range.y, roll(seed, 17.1));
	VELOCITY = cone_direction(travel_direction, spread_degrees, seed) * speed;

	// x drag rate, y birth spin, z first phase, w preferred travel speed.
	USERDATA1 = vec4(
		mix(damping_range.x, damping_range.y, roll(seed, 19.3)),
		radians(mix(angular_velocity_range.x, angular_velocity_range.y, roll(seed, 23.9))),
		roll(seed, 29.7) * 6.2831853,
		speed
	);
	float base_angle = roll(seed, 31.1) * 6.2831853;
	// x birth size, y base angle, z second phase, w rock amplitude.
	USERDATA2 = vec4(
		size,
		base_angle,
		roll(seed, 33.5) * 6.2831853,
		radians(mix(rock_amplitude_range.x, rock_amplitude_range.y, roll(seed, 35.9)))
	);
	// x rock Hz, y flutter amplitude, z flutter Hz, w reserved.
	USERDATA3 = vec4(
		mix(rock_frequency_range.x, rock_frequency_range.y, roll(seed, 39.1)),
		radians(mix(flutter_amplitude_range.x, flutter_amplitude_range.y, roll(seed, 41.7))),
		mix(flutter_frequency_range.x, flutter_frequency_range.y, roll(seed, 43.3)),
		0.0
	);
	float flip_duration = mix(flip_duration_range.x, flip_duration_range.y, roll(seed, 47.9));
	float flip_start = mix(0.24, 0.68, roll(seed, 51.1)) * LIFETIME;
	if (roll(seed, 53.7) >= flip_probability || flip_duration <= 0.0) {
		flip_start = LIFETIME + 1.0;
	}
	// x flip start seconds, y duration, z direction, w reserved.
	USERDATA4 = vec4(
		flip_start,
		max(flip_duration, 0.001),
		roll(seed, 57.3) < 0.5 ? -1.0 : 1.0,
		0.0
	);
	// x billboard rotation, y this flake's curl strength, z normalised age.
	CUSTOM = vec4(
		base_angle,
		mix(turbulence_influence_range.x, turbulence_influence_range.y, roll(seed, 37.7)),
		0.0,
		0.0
	);
	COLOR = vec4(1.0, 1.0, 1.0, 0.0);
}


void process() {
	CUSTOM.z = clamp(CUSTOM.z + DELTA / max(LIFETIME, 0.001), 0.0, 1.0);
	float age = CUSTOM.z;

	// Drag gives a flake mass and memory when live wind turns. Exponential
	// response is frame-rate stable and never crosses through its target.
	vec3 target = normalize(travel_direction) * USERDATA1.w;
	float response = 1.0 - exp(-max(USERDATA1.x, 0.0) * DELTA);
	VELOCITY += (target - VELOCITY) * response;
	VELOCITY.y -= fall_acceleration * DELTA;

	// Curl only pushes across horizontal travel. It can make an S-curve or a
	// side-slip, but it cannot spend the downward component that makes this snow.
	vec3 eddy = curl_at(
		TRANSFORM[3].xyz / max(turbulence_scale, 0.05) + vec3(USERDATA1.z),
		TIME * turbulence_drift
	);
	vec3 lateral = vec3(eddy.x, 0.0, eddy.z);
	vec3 flat_travel = vec3(travel_direction.x, 0.0, travel_direction.z);
	if (dot(flat_travel, flat_travel) > 0.000001) {
		flat_travel = normalize(flat_travel);
		lateral -= flat_travel * dot(lateral, flat_travel);
	}
	float turbulent_window = smoothstep(0.04, 0.24, age)
		* (1.0 - smoothstep(0.72, 1.0, age));
	VELOCITY += lateral * CUSTOM.y * turbulent_window * DELTA;

	// Analytic, layered pose. Birth spin quickly gives way to an irregular rock;
	// a quieter double-frequency flutter catches the edge; a small minority ease
	// through one half-turn and squash side-on. Nothing here touches trajectory.
	float elapsed = age * LIFETIME;
	float spin_angle = USERDATA1.y * elapsed;
	if (angular_damping > 0.000001) {
		spin_angle = USERDATA1.y * (1.0 - exp(-angular_damping * elapsed)) / angular_damping;
	}
	float rock_phase = USERDATA1.z + 6.2831853 * USERDATA3.x * elapsed
		+ 0.22 * sin(6.2831853 * USERDATA3.x * 0.31 * elapsed + USERDATA2.z);
	float rock_wave = 0.72 * sin(rock_phase)
		+ 0.20 * sin(1.73 * rock_phase + USERDATA2.z)
		+ 0.08 * sin(0.43 * rock_phase - USERDATA2.z);
	float rock_envelope = rock_end_multiplier
		+ (1.0 - rock_end_multiplier) * exp(-angular_damping * 0.55 * elapsed);
	float rock_angle = USERDATA2.w * rock_envelope * rock_wave;
	float flutter_phase = 6.2831853 * USERDATA3.z * elapsed;
	float flutter_angle = USERDATA3.y * (
		0.75 * sin(flutter_phase + USERDATA2.z)
		+ 0.25 * sin(2.31 * flutter_phase + USERDATA1.z)
	) * turbulent_window;
	float flip_progress = clamp((elapsed - USERDATA4.x) / USERDATA4.y, 0.0, 1.0);
	float flip_eased = flip_progress * flip_progress * flip_progress
		* (flip_progress * (flip_progress * 6.0 - 15.0) + 10.0);
	float flip_angle = USERDATA4.z * 3.14159265 * flip_eased;
	CUSTOM.x = USERDATA2.y + spin_angle + rock_angle + flutter_angle + flip_angle;
	float edge = clamp(flip_edge_scale, 0.1, 1.0);
	float width_scale = 1.0 - (1.0 - edge) * pow(sin(3.14159265 * flip_eased), 2.0);
	TRANSFORM[0].xyz = vec3(USERDATA2.x * width_scale, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, USERDATA2.x, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, USERDATA2.x);

	float fade_in = smoothstep(0.0, 0.08, age);
	float fade_out = 1.0 - smoothstep(0.72, 1.0, age);
	// RGB is the identity; the palette-derived draw material owns colour.
	COLOR = vec4(1.0, 1.0, 1.0, fade_in * fade_out);
}
