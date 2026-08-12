shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back,
	ambient_light_disabled, specular_disabled, diffuse_lambert;

// The snow a walker is carrying -- packed onto his boots and shins by wading,
// and settled onto his hood and shoulders by the sky -- drawn as a second pass
// over whatever he is already wearing.
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
// VERIFIED AGAINST THE PICTURE, not merely reasoned about. `tools/
// measure_crust_coverage.gd` projects the walker's soles and the top of the band
// it was given into frame pixels, and counts where the band actually drew:
//
//     asked for  0.000 .. 0.430 m above his soles
//     drew from  0.087 .. 0.502 m
//
// Both ends of that disagreement are correct and worth knowing. The bottom is
// the SINK -- `PlayerController` draws him down into the drift, so the lowest
// 8.7 cm of him is behind the snow mesh. The top is the STRIDE: the mask is a
// world height, so on the lifted rear foot the band rides 7 cm higher up the
// leg. That is the documented cost of taking the height in world space, and the
// alternative -- a height in the rig's own space -- is the one that cannot be
// got right, per the two failures above.
//
// The two ends of the range are measured off the shipped rig rather than
// guessed at (24 bones, rest heights over a figure 1.6409 tall):
//
//     LeftToeBase  0.0365    LeftFoot  0.1288    LeftLeg (knee)  0.4212
//
// which is 2.2%, 7.9% and 25.7% of the figure. `boot_line` below is just over
// the ankle and the node's cap is the knee; where the crust actually stops
// between them is measured off the snow, not authored -- see `wade_line`.

// The crust's colour. NEARLY WHITE -- the palette's snow entry taken almost all
// the way to white by the node that owns this material, then scaled to the value
// this surface may be drawn at. See `SnowLoad.shed_whiteness` for why nearly
// white is the correct reading of that entry here: the palette's blue describes
// a snow FIELD at distance under a blue sky, and a patch of snow on a dark coat a
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

// ---------------------------------------------------------------------------
// TWO LOADS, TWO REGIONS, ONE CRUST
// ---------------------------------------------------------------------------
// `load` is what he WADED THROUGH: it lives on the boots and shins, between the
// boot line and the line he actually walked into, and it comes off when his feet
// hit the ground.
//
// `settle` is what FELL ON HIM: it lives on whatever faces the sky -- the hood,
// the shoulders, the tops of the forearms, the rim of a boot -- it builds while
// he stands still in a snowfall, and it has no band at all.
//
// They are separate because they are different facts, and a walker can carry
// either without the other: a man crossing a drift on a clear night has the
// first and not the second, and a man standing under a blizzard on bare ground
// has the second and not the first. The fragment takes whichever is greater
// where the two overlap, because a patch of leg carrying snow from both sources
// is still one patch of snow.
uniform float load : hint_range(0.0, 1.0) = 0.0;
uniform float settle : hint_range(0.0, 1.0) = 0.0;

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

// Where the wading crust's upper edge sits, as a fraction of the figure's
// height, with nothing on the legs and with a full load.
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
// shallow one. The node holds it between `boot_line` and the measured knee at
// 0.257, so it can never climb past the leg it is on.
//
// ---------------------------------------------------------------------------
// RULED: THE CRUST MAY NOT OVERSTATE THE LINE. THE SNOW IS WHAT IS SHORT.
// ---------------------------------------------------------------------------
// This lands on the BOOT, and that is correct rather than a shortfall. Measured
// off the frame: he is 1.88 m, `PlayerController` sinks him through 75% of the
// depth, and the field holds 0.42 .. 0.60 m -- so the snow line on the DRAWN
// figure runs 32 .. 45 cm, against a knee at 48 cm. In 60 cm of snow a man this
// tall standing three quarters of the way into it has the surface at the top of
// his boots. "It should reach 34-43 cm" and "the white is only on the boot" are
// the same sentence on this character.
//
// It was tempting to draw the crust higher than the snow he walked through so it
// would read further up the leg. THAT IS FORBIDDEN, by ruling, and the reason is
// worth keeping: the entire value of this band is that it RECORDS something
// true. A crust that flatters the number looks fine on today's terrain and
// breaks visibly the moment the terrain gets deeper, and by then nobody
// remembers it was a fudge.
//
// The field is the thing that is wrong, and it is not this file's to fix. Two
// features found that independently: this one, and the footprint work, which
// measured the same field as 35% bare, 41% past the wading gate, and with no
// 12 m square anywhere holding a mean depth between 0.02 and 0.32 m -- too
// shallow AND missing its whole middle range, which is why every depth-dependent
// behaviour in the game reads closer to binary than it should. Leave this honest
// and it climbs his leg for free the day the drifts get deeper.
uniform float boot_line = 0.10;
uniform float wade_line = 0.21;

// ---------------------------------------------------------------------------
// HOW MUCH OF THE LEG CARRIES SNOW, AND WHY THIS IS THE NUMBER THAT WAS WRONG
// ---------------------------------------------------------------------------
// `crust_coverage` is the fraction of the cloth that carries snow where the
// crust is at its thickest, at the sole. `patch_scatter` is how much of the band
// -- as a fraction of the band, NOT of the figure -- it thins out over as it
// climbs toward the line he waded.
//
// THE PREVIOUS VERSION OF THESE TWO IS WHY THE EFFECT READ AS A DUSTING OF
// SPARKLES. It measured the thinning against the FIGURE (0.16 of him, 30 cm)
// while the whole band is only 43 cm tall, so five sixths of the band was on the
// falling half of the ramp; and it multiplied the coverage by the load a SECOND
// time, on top of the edge already retreating with the load. The two compounded:
//
//     load 1.00   30.9% of the band covered
//     load 0.70    2.9%
//
// and 0.70 is the FIRST load the game ever shows, because the crust is buried
// while he is still in the drift and his first step out sheds three tenths of
// it. So every frame anybody ever judged this by was the 2.9% one. Measured with
// `tools/measure_crust_coverage.gd`, which counts the crust against the band off
// a rendered frame rather than estimating it.
//
// Now the load moves the EDGE and nothing else: snow does not become more
// porous as it comes off a leg, the area it occupies shrinks from the top down.
// The only thing `load` still scales is the last of it, so a nearly-clean leg
// fades out instead of switching off.
uniform float crust_coverage : hint_range(0.0, 1.0) = 0.44;
uniform float patch_scatter : hint_range(0.0, 1.0) = 0.35;

// The same pair for the snow that FELL on him. `settle_facing` is how far a
// surface has to face upward before it holds any: at 0 a vertical shin would
// collect snowfall, which is wrong, and at 1 only a perfectly level shoulder
// would, which is a hat rather than a snow load.
uniform float settle_coverage : hint_range(0.0, 1.0) = 0.82;
uniform float settle_facing : hint_range(-1.0, 1.0) = 0.12;
uniform float settle_falloff : hint_range(0.05, 2.0) = 0.62;

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
// CLUMPS, NOT GRIT, AND THAT IS WHAT `patch_scale` IS FOR. Raising the coverage
// of a fine speckle gives you forty per cent of NOISE, not forty per cent of
// snow -- the eye reads a camouflage print rather than material stuck to cloth.
// So the noise is nearly four times coarser than the first version's 42, most of
// its weight is in the base octave rather than spread across three, and the
// whole field is pushed about by a warp of its own so a clump has fingers and
// inlets instead of the round shoulder a plain threshold on fBm produces.
uniform float patch_scale = 11.5;
uniform float patch_contrast = 1.8;
uniform float patch_warp = 0.55;

// WHERE it catches, as opposed to how much of it there is.
//
// Snow settles on the upward-facing side of things -- the top of a boot, the
// upper face of every fold and seam in a coat -- and slides off the underside.
// The figure's own normal map already contains every one of those folds, in the
// same UVs this shader reads, so it costs one texture fetch to put the snow
// where the cloth would actually hold it instead of scattering it evenly.
//
// CENTRED ON A VERTICAL SURFACE, which is a correction. It used to be measured
// against a pivot of 0.25, so a plain vertical shin -- which is most of the band
// -- lost a flat tenth of its coverage before anything else happened, and the
// bias was a tax rather than a redistribution. Now a vertical surface neither
// gains nor loses, an upward-facing fold gains, and an overhang loses.
//
// Unbound this is a flat normal map -- Godot's default for `hint_normal` -- and
// the bias then follows the surface's own geometry, so a subject with no normal
// map still catches snow on its upward faces rather than getting an artifact.
uniform sampler2D crease_map : hint_normal;
uniform float crease_bias = 0.42;

// The most opaque the crust gets. 1 now, and that IS the fix: see the breakup
// note above. Left as a uniform because a subject whose snow should read thinner
// -- wet snow on a waterproof, say -- is a value change rather than a code one.
uniform float max_opacity : hint_range(0.0, 1.0) = 1.0;

// How much of this patch of leg the WADED crust covers, 0 none .. 1 solid. The
// settled half is a fragment-stage quantity, because it depends on which way the
// surface faces rather than on where it is.
varying float waded;

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
	// THE WARP IS WHAT GIVES A CLUMP AN EDGE WORTH LOOKING AT. Thresholding a
	// plain fBm gives blobs with smooth round shoulders -- readable as a pattern,
	// not as something stuck on. Pushing the lookup about by a coarse noise of its
	// own pulls those outlines into fingers and inlets, which is the shape snow
	// breaks into, and it costs two more lookups at the base frequency.
	vec2 warp = vec2(snow_noise(p * 0.87 + 11.3), snow_noise(p * 0.87 + 41.9)) - 0.5;
	vec2 q = p + warp * patch_warp;
	// MOST OF THE WEIGHT IN THE BASE OCTAVE. Spread evenly across three, the field
	// has no scale of its own and a threshold on it produces grit at every
	// coverage. Weighted like this the first octave decides where the clumps ARE
	// and the other two only rough up their edges.
	float sum = snow_noise(q) * 0.72;
	sum += snow_noise(q * 2.17 + 19.7) * 0.19;
	sum += snow_noise(q * 5.13 + 47.3) * 0.09;
	// Stretched about its own mean, because the octaves above pile up around a
	// half. Stretched to roughly the spread of a flat distribution, `coverage`
	// below means very nearly "this fraction of the cloth", which is what lets the
	// number be aimed at a target rather than tuned until it looks right.
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
	float full = max(wade_line, boot_line);
	float edge = mix(boot_line, full, load);
	// WHERE IN THE BAND THIS IS, 0 at the sole and 1 at the line he waded.
	//
	// AGAINST THE CROSSING, NOT AGAINST WHAT IS LEFT OF IT, and that distinction
	// is worth more than it looks. Measured against the retreating edge instead,
	// the thinning ramp shortens as he sheds, so the surviving crust gets SPARSER
	// as well as shorter and the two compound: 36.4% of the band at a full load
	// fell to 19.0% one step out of the drift. Against the crossing, the profile
	// is fixed the moment he waded it and the load only decides how far up it
	// still reaches -- which is the claim the header makes and now the one the
	// arithmetic makes too.
	float climb = clamp(height / max(full, 0.0001), 0.0, 1.0);
	float thinning = 1.0 - smoothstep(1.0 - patch_scatter, 1.0, climb);
	// And where it still reaches. A hair of feather rather than a hard step: the
	// band is a world height and the swing leg slides a few centimetres through it
	// over a stride, which on a ruled edge reads as a line moving up his shin.
	float reaches = 1.0 - smoothstep(edge - 0.006, edge + 0.006, height);
	// The load moves the edge, not the density -- see `crust_coverage`. The only
	// thing it still scales is the last of it, so the final trace on a boot fades
	// out rather than switching off.
	waded = crust_coverage * thinning * reaches * smoothstep(0.0, 0.16, load);
	// The swell is authored in metres and applied in whatever units VERTEX uses,
	// so it is divided by the model matrix's own scale rather than assuming one.
	float metres_per_unit = max(length(MODEL_MATRIX[1].xyz), 0.000001);
	VERTEX += NORMAL * (swell / metres_per_unit) * max(waded, settle * settle_coverage);
}

void fragment() {
	float patches = snow_patches(UV * patch_scale);
	// The fold the snow is sitting in. The map is tangent space, so it is taken
	// back through the surface's own frame and compared against world up, which
	// in fragment() is whichever direction VIEW_MATRIX sends (0, 1, 0).
	vec3 bumped = texture(crease_map, UV).xyz * 2.0 - 1.0;
	vec3 folded = normalize(TANGENT * bumped.x + BINORMAL * bumped.y + NORMAL * bumped.z);
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float upness = dot(folded, up);
	// WHAT FELL ON HIM. No band and no height: snow out of the sky lands on
	// whatever faces the sky, which on this figure is the hood, the shoulders, the
	// tops of the sleeves and the rim of each boot, and lands on nothing that
	// faces down. That the legs are largely vertical is why a man standing still
	// in a blizzard whitens from the top while a man out of a drift whitens from
	// the bottom, with no code anywhere saying so.
	float settled = settle * settle_coverage
		* smoothstep(settle_facing, settle_facing + settle_falloff, upness);
	float coverage = max(waded, settled);
	// The fold it is caught in, signed about a vertical surface: an upward-facing
	// crease gains snow it would not otherwise have earned and an overhang loses
	// snow it would.
	float caught = crease_bias * upness;
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
