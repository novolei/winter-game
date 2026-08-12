shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back,
	ambient_light_disabled, specular_disabled, diffuse_lambert;

// The snow packed onto a walker's boots and shins, drawn as a second pass over
// whatever he is already wearing.
//
// ---------------------------------------------------------------------------
// WHY THIS IS AN OVERLAY AND NOT A CHANGE TO HIS MATERIAL
// ---------------------------------------------------------------------------
// The character is exempt from the Art Bible's surface rules by the owner's
// ruling and keeps the four PBR maps Meshy delivered -- see
// `PlayerController._build_body()`. His material also already carries a second
// pass: `CharacterScheme.wear_ghost()` sets `STENCIL_MODE_XRAY`, and the engine
// builds the x-ray silhouette into `next_pass`. Writing snow into either of
// those means taking something away.
//
// So this rides `GeometryInstance3D.material_overlay`, which is a separate
// property from both `material_override` and `next_pass`: one write on the mesh
// instance, nothing on the material, and the ghost is untouched. The snow is
// added on top of what is there, which is exactly what snow does.
//
// ---------------------------------------------------------------------------
// THE THREE RENDER MODES ON THE SECOND LINE, AND WHY THEY ARE NOT DECORATION
// ---------------------------------------------------------------------------
// `ambient_light_disabled` is briefing trap 7 and `tests/art/
// test_character_lighting.gd` is the gate that holds it: every shader in this
// project refuses ambient, which is what makes the Environment's fill a
// CHARACTER control rather than a world light. This shader is the first one
// that lives ON the character, so it is also the first place where that rule
// costs something -- the crust is lit by the sun and by the character's own key
// light, while the coat under it also gets the fill. That is a real difference
// and it was measured rather than argued about; see the task report. The rule
// stands as written, because a gate relaxed once per exception is not a gate.
//
// `specular_disabled` and `diffuse_lambert` follow the rest of the project's
// shaders for the reason Art Bible rule 8 gives: there is no gloss anywhere in
// this world, and snow packed onto a boot is the last surface that should
// acquire one.
//
// ---------------------------------------------------------------------------
// THE MASK IS A HEIGHT IN METRES, TAKEN THROUGH MODEL_MATRIX, AND THAT IS THE
// ONLY FORM OF IT THAT SURVIVES
// ---------------------------------------------------------------------------
// Two versions of this shader failed before this one, both silently, and both
// for the same reason: they assumed they knew what space `VERTEX` was in.
//
//   1. Masked against the mesh's own AABB. `Mesh.get_aabb()` reports the
//      wanderer at 1.6409 tall, and `VERTEX` on that mesh is nothing like that
//      -- its skin's bind poses carry a scale of 100. Every fragment failed the
//      comparison and the shader painted nothing at all.
//   2. Masked against that AABB multiplied by the bind scale. That is right in
//      the bind pose -- it renders correctly on a model standing in its rest
//      pose, which is what a probe scene shows you -- and wrong in the game,
//      where the crust collapsed into the last three centimetres above the sole.
//
// Both were shaders that compiled, ran, cost a draw call and produced no
// diagnostic. The second is the worse of the two, because it looked right in
// isolation.
//
// So the height is not taken in `VERTEX`'s space at all. `MODEL_MATRIX` is BY
// DEFINITION the matrix that puts `VERTEX` into world space -- the engine's own
// next line uses it for exactly that -- so it is correct whatever the units are,
// and whether or not the skinning has been folded into it. `origin_y` is the
// walker's own feet and `figure_height` is how tall he is, both in metres, both
// written by the node off the body it is actually on. Nothing here can be out by
// a factor of a hundred, because nothing here has a factor in it.
//
// THE COST, stated plainly: this is a WORLD height, so it does not ride with a
// lifted foot. Measured on the shipped walk, the toe rises about 6 cm over a
// stride against a crust line somewhere between 19 and 45 cm, so the line slides
// a little way down the swing leg and back. `feather` is what keeps that from
// reading as an edge moving; the alternative -- a height in the rig's own space
// -- is the one that cannot be got right, per the two failures above.
//
// The two ends of that range are measured off the shipped rig rather than
// guessed at (24 bones, rest heights over a figure 1.6409 tall):
//
//     LeftToeBase  0.0365    LeftFoot  0.1288    LeftLeg (knee)  0.4212
//
// which is 2.2%, 7.9% and 25.7% of the figure. `boot_line` below is just over
// the ankle and the node's cap is the knee; where the crust actually stops
// between them is measured off the snow, not authored -- see `wade_line`.

// The crust's colour. NEARLY WHITE -- the palette's snow entry taken almost all
// the way to white by the node that owns this material, then scaled to the value
// this surface may be drawn at. See `LegSnow.shed_whiteness` for why nearly
// white is the correct reading of that entry here: the palette's blue describes
// a snowFIELD at distance under a blue sky, and a patch of snow on a dark coat a
// metre from the lens is lit directly and scatters white. Taking the field's
// blue onto the coat is what made the first version read as a blue film.
//
// Art Bible rule 12 keeps the WARM pixels for fire, windows, beacons, the truck
// and the scarf; a white crust takes none of that quota, and its value is held
// below the glow threshold so no part of it becomes a sixth warm source by
// blooming.
//
// It is written into ALBEDO ONLY. There is no `light()` in this file, so the
// engine's own `diffuse_light *= albedo` happens exactly once and the colour
// reaches the screen at the palette value rather than at its square -- which is
// the other half of trap 7, and the half that is invisible until somebody
// samples a frame.
uniform vec3 snow_color : source_color = vec3(0.80, 0.86, 0.93);

// How much snow the legs are carrying, 0 clean .. 1 straight out of a drift.
// It does three things at once: it decides the opacity, it decides how far the
// edge has RETREATED from `wade_line` back down toward the boot, and it decides
// how far the crust stands proud of the leg. All three fall away together as the
// walker sheds, so the legs clean up rather than switching off.
//
// Note which of the two heights this is not: the load says how much is LEFT, and
// `wade_line` says how far up it ever went. A walk out of a shallow drift and a
// walk out of a deep one look identical in the load and completely different on
// the leg, which is the point.
uniform float load : hint_range(0.0, 1.0) = 0.0;

// The Environment's own ambient fill, in LINEAR light, written by the node off
// the very Environment the character's coat is lit by.
//
// THIS IS THE OTHER HALF OF `ambient_light_disabled`, AND IT IS A FIX RATHER
// THAN A WORKAROUND. That was challenged and then settled by measurement rather
// than by argument; the three frames are beside the task report as
// `ambient-a-add-back`, `ambient-b-no-fill` and `ambient-c-native`, all of the
// same walker at the same instant with the crust covering his whole body so it
// could be sampled:
//
//     a  ambient_light_disabled + this add-back   mean #8ea2bd   luma 0.628
//     b  ambient_light_disabled, no add-back      mean #768aa6   luma 0.534
//     c  ambient allowed natively, no add-back    mean #8ea2bd   luma 0.628
//
// a and c agree to the hex digit. This does not approximate Godot's ambient, it
// reproduces it: the engine contributes `ambient * ALBEDO` to diffuse and this
// contributes exactly that as emission, from the same two Environment properties
// the gate reads, re-read every frame so the six lighting presets carry it.
//
// b is what the rule costs without it, and it is not subtle -- in that frame the
// crust renders DARKER than the coat it is sitting on.
//
// The reason the character needs this and no other surface does: the coat is a
// stock StandardMaterial3D, so ambient reaches it natively and always has. The
// rule that every shader must refuse ambient is a rule about WORLD shaders --
// it exists so the Environment's fill stays a character control -- and this is
// the first shader in the project that lives ON the character, where obeying it
// takes light away from the one surface the fill was authored for. The material
// is not mis-wired: its mesh carries `layers = 3`, which includes the character
// key light's own `light_cull_mask = 2`, so the sun and the key reach the crust
// exactly as they reach the coat. Ambient is the only thing it loses, and this
// is the line that gives it back.
uniform vec3 fill = vec3(0.0);

// The walker's own feet and his height, in world metres. Written every frame by
// the node -- his feet move, and a crust anchored to a stale height would climb
// his legs as he walked downhill.
uniform float origin_y = 0.0;
uniform float figure_height = 1.88;

// Where the crust's upper edge sits, as a fraction of the figure's height, with
// nothing on the legs and with a full load.
//
// `boot_line` is authored -- 0.10 is just over the measured ankle at 0.079, and
// it is the last of the crust still clinging to the boot when nearly all of it
// has gone.
//
// `wade_line` IS NOT AUTHORED. It is written every frame by the node and it is
// THE DEPTH HE WALKED THROUGH: the snow line measured on his own legs at the
// deepest point of the crossing he is currently wearing, divided by his height.
// That is the physical fact this whole effect exists to state, and a fixed band
// in its place said nothing -- a man who had just crossed a full drift came out
// with a crust that stopped at his ankle, exactly like a man who had crossed a
// shallow one.
//
// It is also what makes the effect legible at the game camera, where the figure
// is a hundred pixels tall. A constant band at that size is texture and reads as
// nothing; a band that is twice the height after a deep crossing than after a
// shallow one is a DIFFERENCE, and a difference is the only thing an eye at that
// distance can catch. The node holds it between `boot_line` and the measured
// knee at 0.257, so it can never climb past the leg it is on.
uniform float boot_line = 0.10;
uniform float wade_line = 0.21;

// How far below the crust's upper line the COVERAGE ramp runs, as a fraction of
// the figure. Snow on a leg has no hem: it is solid at the boot, and it thins
// out into scattered flecks as it climbs. This is the length of that thinning,
// and it is also what absorbs the stride, per the note above.
uniform float patch_scatter = 0.16;

// How far the crust stands off the leg, in metres. Small, and it earns its
// place twice: snow packed onto a boot genuinely sits proud of it, and a second
// pass drawn exactly coplanar with the first is a depth fight waiting for a
// driver to lose.
uniform float swell = 0.005;

// ---------------------------------------------------------------------------
// THE BREAKUP: A THRESHOLD ON NOISE, NOT A FADE ON ALPHA
// ---------------------------------------------------------------------------
// This is the correction that matters most in this file, and the reason is
// worth stating rather than inferring. The first version of this shader scaled
// ALPHA by how much snow was on the leg. Pale snow at half alpha over a dark
// navy coat is not half-covered cloth -- it is a wash, and it renders as a blue
// transparent film painted over his legs. That is precisely how it was reported.
//
// Snow on cloth is not partly transparent anywhere. It is opaque where it sits
// and absent where it does not, and what varies with how much of it there is is
// the COVERAGE: how much of the leg has any on it at all. So `coverage` below
// becomes a THRESHOLD on a noise field. As the load builds the threshold drops
// and more patches appear; as he sheds it rises and patches go out ONE AT A
// TIME, which is what breaking up looks like as opposed to dimming.
//
// One mechanism, three things bought with it: the irregular patchwork, a shed
// that visibly disintegrates, and a silhouette that can never read as a painted
// band because it does not have an edge to read.
uniform float patch_scale = 42.0;
uniform float patch_contrast = 2.1;

// WHERE it catches, as opposed to how much of it there is.
//
// Snow settles on the upward-facing side of things -- the top of a boot, the
// upper face of every fold and seam in a coat -- and slides off the underside.
// The figure's own normal map already contains every one of those folds, in the
// same UVs this shader reads, so it costs one texture fetch to put the snow
// where the cloth would actually hold it instead of scattering it evenly.
//
// Unbound this is a flat normal map -- Godot's default for `hint_normal` -- and
// the bias then contributes nothing but a constant, so a subject with no normal
// map gets plain noise rather than an artifact.
uniform sampler2D crease_map : hint_normal;
uniform float crease_bias = 0.42;

// The most opaque the crust gets. 1 now, and that IS the fix: see the breakup
// note above. Left as a uniform because a subject whose snow should read thinner
// -- wet snow on a waterproof, say -- is a value change rather than a code one.
uniform float max_opacity : hint_range(0.0, 1.0) = 1.0;

// How much of this patch of leg is covered, 0 none .. 1 solid.
varying float coverage;

// A hash-based value noise. Two octaves and a half, on the surface's own UVs so
// the patches STAY ON THE SAME PATCH OF MESH through the whole walk cycle --
// exactly the reason the edge wobble this replaces was in UV space too.
float snow_hash(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 47.53);
	return fract(p.x * p.y);
}

float snow_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = snow_hash(cell);
	float b = snow_hash(cell + vec2(1.0, 0.0));
	float c = snow_hash(cell + vec2(0.0, 1.0));
	float d = snow_hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float snow_patches(vec2 p) {
	float sum = snow_noise(p) * 0.60;
	sum += snow_noise(p * 2.13 + 19.7) * 0.27;
	sum += snow_noise(p * 4.61 + 47.3) * 0.13;
	// Stretched about its own mean, because the octaves above pile up around a
	// half and a threshold sweeping that would take the whole leg from bare to
	// covered over a narrow part of its travel. Stretched, the patches arrive
	// and leave steadily across the whole range of the load.
	return clamp((sum - 0.5) * patch_contrast + 0.5, 0.0, 1.0);
}

void vertex() {
	// World, through the engine's own model matrix. See the note above: this is
	// the only height in this file that cannot be wrong about its units.
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float height = (world.y - origin_y) / max(figure_height, 0.0001);
	// Rises with the load, to the line he actually waded: a full leg carries snow
	// to the depth it walked through, and as it sheds the line retreats down to
	// the boot before it goes. That retreat is most of what reads as "cleaning
	// up" -- an edge that stayed put and only faded would read as the effect
	// being switched off. `max` because a crossing shallower than the boot line
	// must still leave the boot marked rather than invert the mix.
	float edge = mix(boot_line, max(wade_line, boot_line), load);
	// Solid at the sole, thinning out to nothing at the line. Times the load, so
	// the whole thing sparsens as he sheds rather than only shortening.
	coverage = (1.0 - smoothstep(edge - patch_scatter, edge, height)) * load;
	// The swell is authored in metres and applied in whatever units VERTEX uses,
	// so it is divided by the model matrix's own scale rather than assuming one.
	float metres_per_unit = max(length(MODEL_MATRIX[1].xyz), 0.000001);
	VERTEX += NORMAL * (swell / metres_per_unit) * coverage;
}

void fragment() {
	float patches = snow_patches(UV * patch_scale);
	// The fold the snow is sitting in. The map is tangent space, so it is taken
	// back through the surface's own frame and compared against world up, which
	// in fragment() is whichever direction VIEW_MATRIX sends (0, 1, 0).
	vec3 bumped = texture(crease_map, UV).xyz * 2.0 - 1.0;
	vec3 folded = normalize(TANGENT * bumped.x + BINORMAL * bumped.y + NORMAL * bumped.z);
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// Signed about a shallow pivot rather than clamped at zero: a surface facing
	// up gets snow it would not otherwise have earned, and one facing down loses
	// snow it would. A one-sided bonus would just raise the coverage everywhere.
	float caught = crease_bias * (dot(folded, up) - 0.25);
	float field = clamp(patches + caught, 0.0, 1.0);
	// OPAQUE OR ABSENT. The width is a screen-space derivative rather than a
	// constant, so the boundary is one pixel of anti-aliasing wide at the game
	// camera AND at a close-up, instead of crisp at one and mushy at the other.
	float width = max(fwidth(field), 0.002);
	// THE THRESHOLD OVERSHOOTS AT BOTH ENDS, AND THAT IS NOT PADDING.
	//
	// `field` is clamped into 0..1, so a plain `1.0 - coverage` threshold sits
	// exactly ON the top of its range at zero coverage -- and a smoothstep
	// centred on its own input returns a half. The first version of this put a
	// scatter of half-opaque flecks over every part of the figure the crust was
	// nowhere near, including his head, because "no snow here" evaluated to 50%
	// alpha wherever the biased noise had saturated. Ending the sweep one
	// feather-width OUTSIDE the field's range at each end is what makes zero
	// coverage mean bare and full coverage mean solid.
	float threshold = mix(1.0 + width, -width, coverage);
	float snow = smoothstep(threshold - width, threshold + width, field);
	ALBEDO = snow_color;
	// Snow is not wet and it is not metal. `specular_disabled` above is the
	// project-wide form of the same statement; these two keep it true of the
	// values as well as of the mode.
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// See `fill`: the ambient this shader is forbidden to receive, added back by
	// hand so the crust sits in the same light as the leg it is on.
	EMISSION = snow_color * fill;
	ALPHA = snow * max_opacity;
}
