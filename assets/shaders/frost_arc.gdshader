shader_type canvas_item;
render_mode blend_mix, unshaded;

// ---------------------------------------------------------------------------
// FROST IS NOT A TEXTURE LAID OVER A READOUT. IT IS WHAT THE READOUT IS MADE OF
// ---------------------------------------------------------------------------
// This shader does not decorate a bar. There is no bar. It is handed a SUBSTRATE
// -- two endpoints and a bow -- and it grows ice along it. Everything the player
// sees is the ice: the track, the reserve, the terminals, all of it.
//
// That is also how it obeys UI design document rule 1 (没有矩形). A frost needle
// is a stroke with a sharp terminal, and a chain of them along a curve is an
// arc. There is no quad in the output; the quad is only the canvas the field is
// evaluated over, which is why the element draws one white texture rect and lets
// this file decide what exists inside it.
//
// The five properties, and where each one lives below:
//
//   1. IT GROWS, IT DOES NOT FADE IN.  `growth` is a creeping front along the
//      substrate with a ragged leading edge. At growth 0 there is nothing at
//      all -- not a transparent readout, NOTHING -- and the element arrives by
//      crystallising along itself. See `alive`.
//   2. CRYSTALLINE.  Needles lean at -30 / 0 / +30 degrees off the substrate
//      normal, which is the hexagonal family, and they taper to a point rather
//      than ending flat. See `needles()`.
//   3. HARD EDGE, TRANSLUCENT BODY.  The silhouette resolves over ~1.5 px --
//      antialiasing, not softness -- while the interior sits at `body_alpha`.
//      You see the valley through the ice and its boundary is still a line.
//      This is the opposite of a gaussian blur, deliberately.
//   4. REFRACTION, NOT GLOW.  A hard bright sliver just INSIDE the silhouette,
//      on the side whose surface normal faces `light_dir`, and nowhere else.
//      Nothing is added outside the shape, so there is no bloom. Bloom on cold
//      reads cheap -- the same judgement that kept it off the snowfall.
//   5. IT ACCUMULATES AND IT CLEARS.  `rime` lengthens the needles and thickens
//      the body. Warmth takes it down. A readout that has been on screen a
//      while is visibly more frosted than one that just arrived.
//
// ---------------------------------------------------------------------------
// NO COLOUR IS AUTHORED HERE
// ---------------------------------------------------------------------------
// Briefing constraint 6. Every colour arrives as a uniform, read out of
// data/palette/color_bible.tres by the GDScript that builds this material. The
// defaults are white so that an unset uniform is obvious on screen rather than
// plausible.
//
// ---------------------------------------------------------------------------
// TIME IS A UNIFORM, NOT `TIME`
// ---------------------------------------------------------------------------
// Same reason Breath is a pure function of t rather than a Tween: a screenshot
// harness has to be able to sample an exact moment, and a montage may be
// scrubbed. `TIME` cannot be rewound.

// --- the substrate, in the drawn rect's own pixel space ----------------------

uniform vec2 rect_px = vec2(1.0, 1.0);
uniform vec2 from_px = vec2(0.0, 0.0);
uniform vec2 to_px = vec2(1.0, 0.0);

// Perpendicular offset at the midpoint. Zero is a straight stroke; positive
// bows it. Used by section 5.2's 52px 短弧.
uniform float bow_px = 0.0;

// 0 draws the substrate between from_px and to_px; 1 draws a circular arc.
// ONE distance field serves both, so the gauge and the note cannot end up with
// two different ideas of what a frosted stroke looks like.
uniform int arc_mode = 0;
uniform vec2 centre_px = vec2(0.0);
uniform float radius_px = 1.0;
uniform float start_rad = 0.0;
uniform float span_rad = 6.2831853;

// Up to four thresholds riding the gauge, as positions along it (0..1).
// Negative means "no marker here", which is why they are packed into a vec4
// rather than an array: a Godot shader uniform array is another thing that can
// silently fail to be written, and four is what the deepest stat in
// data/stats/*.tres actually authors (core_temperature: 0.50, 0.35, 0.20, 0.15).
uniform vec4 markers = vec4(-1.0);
uniform float marker_px = 4.0;

// --- what the readout says ---------------------------------------------------

// Where the reserve ends, along the substrate. Everything before it is the
// filled stroke, everything after is the hairline trough it will come back
// along. EVERY survival stat is a reserve that falls (survival_system.gd's
// polarity note), so this is 1.0 when the player is well.
uniform float fill : hint_range(0.0, 1.0) = 1.0;

// --- the material ------------------------------------------------------------

uniform float growth : hint_range(0.0, 1.0) = 1.0;
uniform float rime : hint_range(0.0, 1.0) = 0.5;

uniform float trough_px = 1.0;
uniform float fill_px = 3.0;
uniform float needle_px = 7.0;

// How many primary needles per 100 px of substrate. Frost is not a fringe: too
// many reads as a comb, too few as a row of ticks.
uniform float needle_density = 9.0;

uniform float body_alpha : hint_range(0.0, 1.0) = 0.42;
uniform float rim_px = 1.6;
uniform float rim_strength : hint_range(0.0, 1.0) = 1.0;

// Where the light comes from, in rect space. Up and to the left, matching the
// valley's own low sun coming over the player's shoulder.
uniform vec2 light_dir = vec2(-0.6, -0.8);

uniform vec4 trough_colour : source_color = vec4(1.0);
uniform vec4 fill_colour : source_color = vec4(1.0);
uniform vec4 rim_colour : source_color = vec4(1.0);

// A single dark pixel just OUTSIDE the ice, and the reason it exists is
// measured rather than aesthetic.
//
// `ink/primary` is `snow_tones[0]`. It is not merely near the colour of lit
// snow, it IS the colour of lit snow -- the design document takes the interface
// ink from the top of the snow ramp on purpose. A readout in it, laid over a
// field the Art Bible pins at 62% of white, has no contrast at all where it
// matters most, and the failure is not visible on a dark mock-up.
//
// Section 5.9 already hit this and already settled it: 这行叙述立在 62% 亮度的雪前
// 面...描边保留而不是关掉...但它取自最暗的结构色而不是黑. The same answer, for the
// same reason, from the same palette. It is also what real ice does against a
// bright ground.
uniform float outline_px = 1.0;
uniform vec4 outline_colour : source_color = vec4(1.0);

// THE ONE WARM THING THIS MATERIAL IS ALLOWED TO DRAW.
//
// Section 5.2: 弧反向收拢，`life/warm` 的点从末端走回——这是暖色在呼吸层唯一的合法
// 用途，因为它表示热量正在进入身体. Section 6.1 says the same from the other side:
// 净速率 > 0（恢复中）: 弧末端一个 life/warm 的 3px 点缓慢前移.
//
// So the mark exists only while the reserve is being PUT BACK, and it sits at
// the head of the reserve, which is precisely where the heat is going. It is
// off (`mark_on` 0) at every other moment, including while the stat is merely
// important or merely low -- rule 3 forbids warmth as emphasis.
uniform float mark_on : hint_range(0.0, 1.0) = 0.0;
uniform float mark_px = 3.0;
uniform vec4 mark_colour : source_color = vec4(1.0);

// Per-element, so two readouts side by side do not crystallise identically.
uniform float seed = 0.0;
uniform float elapsed = 0.0;

const int SAMPLES = 40;

// The classic fract(sin(x)*k). Same hash Breath uses for glyph scatter, for the
// same reason: reproducible across runs and platforms, touching no RNG state,
// so a captured frame is the same captured frame tomorrow.
float hash11(float n) {
	return fract(sin(n * 12.9898 + 78.233) * 43758.5453);
}

vec2 substrate_at(float s) {
	if (arc_mode == 1) {
		float angle = start_rad + span_rad * s;
		return centre_px + vec2(cos(angle), sin(angle)) * radius_px;
	}
	vec2 along = to_px - from_px;
	float span = max(length(along), 0.0001);
	vec2 normal = vec2(-along.y, along.x) / span;
	return mix(from_px, to_px, s) + normal * bow_px * sin(s * PI);
}

// Nearest point on the substrate: a coarse sweep, then one projection onto the
// chord through the winning sample's neighbours.
//
// The sweep ALONE is not good enough and the error is the interesting kind. Its
// minimum overestimates the true distance by roughly the half-step along the
// curve, so a hairline one pixel wide measured against a 40-sample sweep of a
// 200 px substrate comes out about two pixels thick -- uniformly, and never
// varying, so it reads as "the stroke weight is wrong" rather than as a sampling
// artefact. The projection removes it for the price of one more evaluation.
void nearest(vec2 p, out float out_s, out float out_dist, out float out_side) {
	float best_d = 1e9;
	float best_s = 0.0;
	for (int i = 0; i <= SAMPLES; i++) {
		float s = float(i) / float(SAMPLES);
		float d = distance(p, substrate_at(s));
		if (d < best_d) {
			best_d = d;
			best_s = s;
		}
	}
	float step_s = 1.0 / float(SAMPLES);
	float s0 = clamp(best_s - step_s, 0.0, 1.0);
	float s1 = clamp(best_s + step_s, 0.0, 1.0);
	vec2 a = substrate_at(s0);
	vec2 b = substrate_at(s1);
	vec2 ab = b - a;
	float ab2 = max(dot(ab, ab), 0.0001);
	float t = clamp(dot(p - a, ab) / ab2, 0.0, 1.0);
	vec2 foot = a + ab * t;
	out_s = mix(s0, s1, t);
	out_dist = distance(p, foot);
	// Which side of the curve. The needles have to know, or every one of them
	// would grow on both sides at once and the frost would be a symmetric
	// caterpillar rather than a crystal.
	out_side = sign((ab.x * (p.y - a.y)) - (ab.y * (p.x - a.x)));
	if (out_side == 0.0) {
		out_side = 1.0;
	}
}

// How far the ice reaches away from the substrate at this point along it.
//
// Two combs. The coarse one is the primary needles; the fine one is the
// branching, and it is multiplied by the coarse one's local presence so the
// small crystals sit ON the big ones instead of scattering between them, which
// is the difference between frost and noise.
//
// THE HEXAGONAL BIAS IS THE LEAN. A needle leaning by tan(30 degrees) off the
// substrate normal stands at 60 degrees to the substrate, which is the angle
// real ice branches at. Three leans -- minus thirty, zero, plus thirty -- drawn
// per needle from the hash, give the whole family.
float substrate_length() {
	if (arc_mode == 1) {
		return max(radius_px * abs(span_rad), 1.0);
	}
	return max(distance(from_px, to_px), 1.0);
}

float needles(float s, float across_px, float side, float length_px) {
	float substrate_px = substrate_length();
	float reach = 0.0;
	for (int k = 0; k < 2; k++) {
		float band = float(k);
		float density = needle_density * mix(1.0, 2.9, band) * substrate_px * 0.01;
		float scale = mix(1.0, 0.38, band);
		float t = s * density + seed * 7.31 + band * 3.77;
		float cell = floor(t);
		float f = fract(t) - 0.5;
		float h = hash11(cell + seed * 13.0 + band * 101.0);
		float h_side = hash11(cell * 1.73 + seed * 5.0 + band * 57.0);
		float h_lean = hash11(cell * 2.91 + seed * 3.0 + band * 19.0);

		// A needle grows on one side only.
		float wants = h_side < 0.5 ? -1.0 : 1.0;
		float on_this_side = step(0.0, wants * side);

		// tan(-30) / 0 / tan(+30), picked by the hash.
		float lean = floor(h_lean * 3.0) - 1.0;
		lean *= 0.5773503;

		// Shear the along-axis coordinate by how far out we are, so the needle
		// is a slanted spine rather than a perpendicular one.
		float shear = lean * (across_px / substrate_px) * density;
		float f_leaned = f - shear;

		// Triangular in cross-section: full length at the spine, nothing at the
		// edge. That taper is what gives a SHARP TERMINAL -- a needle that fell
		// off at a constant width would end in a blunt bar.
		//
		// THE MULTIPLIER IS THE DIFFERENCE BETWEEN FROST AND A TWIG. At 2.6 a
		// needle occupied about three quarters of its cell, so neighbours met
		// and the silhouette came out as a continuous wobble -- measured on the
		// first probe, and it read as a branch rather than as ice. At 5.0 a
		// needle occupies two fifths of its cell and there is bare substrate
		// between them, which is what makes them read as separate crystals.
		float taper = clamp(1.0 - abs(f_leaned) * 5.0, 0.0, 1.0);
		taper *= taper;

		float this_reach = length_px * scale * mix(0.35, 1.0, h) * taper * on_this_side;
		if (band > 0.5) {
			// The fine comb only exists where the coarse one already reached.
			this_reach *= smoothstep(0.0, length_px * 0.35, reach);
		}
		reach = max(reach, this_reach);
	}
	return reach;
}

void fragment() {
	vec2 p = UV * rect_px;

	float s;
	float dist;
	float side;
	nearest(p, s, dist, side);

	// --- 1. the creeping front ------------------------------------------------
	//
	// Ragged, so the ice arrives as ice rather than as a wipe. The overshoot
	// past 1.0 is what lets the raggedness still finish: a front that stopped
	// exactly at 1.0 would leave the last few percent of the substrate bare
	// forever, at every growth value the element ever reaches.
	float ragged = (hash11(floor(s * 11.0) + seed * 31.0) - 0.5) * 0.16;
	float front = growth * 1.2 - 0.1 + ragged;
	float alive = 1.0 - smoothstep(front - 0.012, front + 0.012, s);

	// --- 2. the substrate's own weight ---------------------------------------
	float filled = step(s, fill);
	float core_px = mix(trough_px, fill_px, filled) * 0.5;

	// --- 3. the ice on it -----------------------------------------------------
	float reach = needles(s, dist, side, needle_px * rime * alive);
	float body_px = (core_px + reach) * alive;

	// Signed distance to the silhouette: negative inside the ice.
	float edge = dist - body_px;

	// --- 4. hard edge, translucent body --------------------------------------
	//
	// 1.5 px of transition is antialiasing and nothing else. Anything wider
	// would be the gaussian this material exists in opposition to.
	float inside = smoothstep(0.75, -0.75, edge);
	// 1 at the silhouette, 0 deep in the ice.
	float at_edge = smoothstep(-max(rim_px * 2.0, 1.0), 0.0, edge);
	float ice_alpha = inside * mix(body_alpha, 1.0, at_edge);

	// The dark hairline the ice stands on. Outside the silhouette only, so it
	// never dims the ice itself -- it gives it a ground to be seen against.
	float outer = smoothstep(0.75, -0.75, edge - outline_px);
	float outline_alpha = clamp(outer - inside, 0.0, 1.0) * outline_colour.a;

	vec4 base = mix(trough_colour, fill_colour, filled);
	float alpha = ice_alpha;

	// --- 5. refraction --------------------------------------------------------
	//
	// A hard sliver just inside the silhouette, on the lit side only. `step`
	// rather than `smoothstep` on the facing term: a soft falloff here is a
	// glow, and a glow is the thing this is instead of.
	vec2 gradient = normalize(vec2(dFdx(edge), dFdy(edge)) + vec2(1e-6));
	float facing = step(0.25, dot(gradient, normalize(light_dir)));
	float band = step(-rim_px, edge) * step(edge, 0.0);
	float catches = band * facing * rim_strength;

	vec3 rgb = mix(base.rgb, rim_colour.rgb, catches);
	// The lit edge is also the least see-through part of the ice, because that
	// is what a refracting edge does.
	alpha = mix(alpha, max(alpha, base.a), catches);
	alpha *= base.a;

	// The outline UNDER the ice, composited the usual way round: ice over
	// hairline, so a thin stroke is dark-edged and legible on snow while a thick
	// one is unaffected.
	float composite = alpha + outline_alpha * (1.0 - alpha);
	rgb = (rgb * alpha + outline_colour.rgb * outline_alpha * (1.0 - alpha))
		/ max(composite, 0.0001);
	alpha = composite;

	// --- 5b. the thresholds, as crystal terminals ----------------------------
	//
	// A sharp spur standing off the gauge where the data really does change
	// what the body can do. Drawn as a needle rather than as a solid triangle,
	// because a triangle is a filled shape and rule 1's whole list is filled
	// shapes -- and because a crystal terminal is what this material makes.
	//
	// They are read out of data/stats/*.tres by way of the copy table, so a
	// marker cannot end up in a place the model does not actually care about.
	float marker = 0.0;
	for (int i = 0; i < 4; i++) {
		float at = markers[i];
		if (at < 0.0) {
			continue;
		}
		vec2 seat = substrate_at(clamp(at, 0.0, 1.0));
		// Outward from the substrate: away from the gauge's centre in ring mode,
		// off the far side of the stroke otherwise.
		vec2 out_dir = arc_mode == 1
			? normalize(seat - centre_px)
			: normalize(vec2(to_px.y - from_px.y, from_px.x - to_px.x) + vec2(1e-6));
		vec2 tip = seat + out_dir * marker_px;
		// Distance to the segment seat->tip, tapered so it ends in a point.
		vec2 spur = tip - seat;
		float t = clamp(dot(p - seat, spur) / max(dot(spur, spur), 0.0001), 0.0, 1.0);
		float across = distance(p, seat + spur * t);
		float width = mix(marker_px * 0.34, 0.2, t);
		marker = max(marker, smoothstep(width + 0.6, width - 0.6, across));
	}
	marker *= alive;
	rgb = mix(rgb, base.rgb, marker);
	alpha = max(alpha, marker * base.a);

	// --- 6. heat entering the body -------------------------------------------
	//
	// Drawn last and opaque, over whatever the ice was doing there. A warm mark
	// half-hidden behind translucent frost would read as a rendering fault
	// rather than as the one warm pixel in the interface.
	float to_mark = distance(p, substrate_at(clamp(fill, 0.0, 1.0)));
	float mark = smoothstep(mark_px * 0.5 + 0.75, mark_px * 0.5 - 0.75, to_mark);
	mark *= step(0.5, mark_on) * alive;
	rgb = mix(rgb, mark_colour.rgb, mark);
	alpha = mix(alpha, mark_colour.a, mark);

	COLOR = vec4(rgb, alpha);
}
