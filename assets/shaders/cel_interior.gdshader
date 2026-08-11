shader_type spatial;

// The inside of a building, and the only warm surface in the game.
//
// GDD section 2, pillar one: 暖色即生存 -- warm IS survival. The valley is one
// blue-grey field from horizon to horizon, and this room is the single place
// that is not. That contrast, seen across a threshold in one unbroken frame, is
// what makes walking home mean anything.
//
// ---------------------------------------------------------------------------
// WHY THIS EXISTS RATHER THAN A WARM LIGHT ON cel_flat
// ---------------------------------------------------------------------------
// cel_flat.gdshader's light() never reads LIGHT_COLOR. It uses the light only
// to pick between two palette colours:
//
//     DIFFUSE_LIGHT += mix(shade_color, lit_color, band);
//
// That is the whole two-band cel look and it is deliberate -- a colour chosen
// once, off the 12-entry table, never multiplied (briefing trap 7). But it has
// a consequence nobody had met until something was lit indoors: **a fire cannot
// tint anything.** An amber OmniLight in that room does not make it amber; it
// pushes whatever it reaches from the shade band into the lit band and leaves
// it exactly as blue as it was. Measured: the stove's light did nothing to the
// room's hue and everything to an 18 m disc of snow outside the walls.
//
// So warmth here is not a light colour, it is a SECOND PAIR OF PALETTE ENTRIES
// and a blend between them. `warmth` at 0 is this shader being cel_flat exactly;
// at 1 the same two bands are read out of the palette's warm family instead.
// The fire drives that number, so the room is amber while it burns and goes
// blue-grey when it dies -- which is the readout GDD section 9 asks for, with
// no HUD attached to it.
//
// ---------------------------------------------------------------------------
// max, NOT +=
// ---------------------------------------------------------------------------
// This is the one line that differs structurally from cel_flat. Once the roof
// is faded the sun reaches the floor, so the room is lit by the sun AND by the
// stove, and light() runs once per light. Accumulating would put the floor at
// twice its palette colour -- exactly the squaring trap 7 warns about, arrived
// at from the other direction. Taking the brightest instead keeps every pixel
// on a palette entry however many lights reach it, and lets the fire win near
// the hearth without ever exceeding the table.
render_mode ambient_light_disabled, specular_disabled, diffuse_lambert;

uniform vec4 lit_color : source_color;
uniform vec4 shade_color : source_color;
uniform vec4 warm_lit_color : source_color;
uniform vec4 warm_shade_color : source_color;

// 0 = cold, this shader is cel_flat. 1 = the warm pair. Driven by
// src/entities/interior/interior_warmth.gd off whether the fire is burning.
uniform float warmth : hint_range(0.0, 1.0) = 0.0;

// Art Bible rule 12 keeps warm pixels for fire, windows, beacons, the scarf and
// the truck, and the firebox is the first of them to be inside a room. Non-zero
// only on the surfaces that are meant to be a light SOURCE rather than a lit
// surface, and multiplied by warmth so a dead fire is a dark hole rather than a
// glowing one. The Environment's glow (threshold 0.95, softlight, strength per
// lighting preset) is what turns this into a bloom -- there is no second glow
// here and there must not be.
uniform float emission_strength : hint_range(0.0, 4.0) = 0.0;

uniform float band_threshold = 0.30;
uniform float band_softness = 0.07;

void fragment() {
	// White on purpose -- see cel_flat.gdshader and briefing trap 7. Godot
	// multiplies DIFFUSE_LIGHT by ALBEDO after the light loop, so the palette
	// colour is chosen once, in light(), and never squared.
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = mix(lit_color.rgb, warm_lit_color.rgb, warmth) * emission_strength * warmth;
}

void light() {
	float lambert = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float band = smoothstep(band_threshold - band_softness, band_threshold + band_softness, lambert * ATTENUATION);
	vec3 lit = mix(lit_color.rgb, warm_lit_color.rgb, warmth);
	vec3 shade = mix(shade_color.rgb, warm_shade_color.rgb, warmth);
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, mix(shade, lit, band));
}
