shader_type canvas_item;

// The film between the lens and the eye -- UI design document section 4.5.
//
// Grain and a vignette, and nothing else. No chromatic aberration and no
// letterbox: this world is twelve flat colours and long soft shadows, and a
// frame that also fringes and crops reads as a filter stack rather than as a
// look.
//
// ---------------------------------------------------------------------------
// THE GRAIN IS LUMINANCE DEPENDENT, WHICH IS THE WHOLE DIFFERENCE
// ---------------------------------------------------------------------------
// Real emulsion carries most of its noise in the shadows and almost none in the
// highlights. A uniform layer of noise over the frame does not read as film, it
// reads as a dirty screen -- and in this game it would land hardest on the snow,
// which is 62% of white across most of the picture and the one place grain
// should be invisible.
//
// ---------------------------------------------------------------------------
// BOTH COLOURS COME IN AS UNIFORMS
// ---------------------------------------------------------------------------
// The vignette darkens toward a colour the caller supplies out of the palette,
// never toward black. A vignette to black would put a thirteenth colour in the
// frame, at the edge of every montage, in a project whose first constraint is
// that there are twelve (briefing constraint 6).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float grain_amount : hint_range(0.0, 0.3) = 0.055;
uniform float grain_size : hint_range(0.5, 6.0) = 1.8;
uniform float grain_highlight_falloff : hint_range(0.0, 1.0) = 0.3;

uniform float vignette_amount : hint_range(0.0, 1.0) = 0.45;
uniform float vignette_start : hint_range(0.0, 1.5) = 0.55;
uniform float vignette_end : hint_range(0.0, 1.5) = 1.15;
uniform vec3 vignette_colour : source_color = vec3(0.07, 0.11, 0.19);

// Advanced by the director from montage time rather than read from TIME, so a
// captured frame is reproducible: the same montage second always grains the
// same way, and a screenshot harness comparing two runs is comparing the
// pictures rather than the moment each one happened to render.
uniform float grain_seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 colour = texture(screen_tex, SCREEN_UV).rgb;

	// --- vignette ---------------------------------------------------------
	// Measured on the aspect-corrected offset from centre, so the falloff is
	// circular rather than an ellipse that stretches with the window.
	vec2 offset = (SCREEN_UV - vec2(0.5)) * vec2(2.0, 2.0);
	offset.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float radius = length(offset);
	float falloff = smoothstep(vignette_start, vignette_end, radius) * vignette_amount;
	colour = mix(colour, vignette_colour, falloff);

	// --- grain ------------------------------------------------------------
	vec2 cell = floor(SCREEN_UV / (SCREEN_PIXEL_SIZE * max(grain_size, 0.5)));
	float noise = hash(cell + vec2(grain_seed, grain_seed * 1.7)) - 0.5;
	float luminance = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	// Full strength in the dark, `grain_highlight_falloff` of it in the light.
	float weight = mix(1.0, grain_highlight_falloff, clamp(luminance, 0.0, 1.0));
	colour += noise * grain_amount * weight;

	COLOR = vec4(colour, 1.0);
}
