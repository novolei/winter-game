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
// stride against a crust line at 19 to 39 cm, so the line slides a little way
// down the swing leg and back. `feather` is what keeps that from reading as an
// edge moving; the alternative -- a height in the rig's own space -- is the one
// that cannot be got right, per the two failures above.
//
// The lines themselves are measured off the shipped rig rather than guessed at
// (24 bones, rest heights over a figure 1.6409 tall):
//
//     LeftToeBase  0.0365    LeftFoot  0.1288    LeftLeg (knee)  0.4212
//
// which is 2.2%, 7.9% and 25.7% of the figure. `boot_line` and `shin_line`
// below sit either side of the shin and under the knee.

// The crust's colour. Cool white, from `data/palette/color_bible.tres` taken
// part way toward white by the node that owns this material. Art Bible rule 12
// keeps the warm pixels for fire, windows, beacons, the truck and the scarf; a
// warm crust on his own boots would be a sixth source and would sit right next
// to the fifth.
//
// It is written into ALBEDO ONLY. There is no `light()` in this file, so the
// engine's own `diffuse_light *= albedo` happens exactly once and the colour
// reaches the screen at the palette value rather than at its square -- which is
// the other half of trap 7, and the half that is invisible until somebody
// samples a frame.
uniform vec3 snow_color : source_color = vec3(0.80, 0.86, 0.93);

// How much snow the legs are carrying, 0 clean .. 1 straight out of a drift.
// The one driven number, and it does three things at once: it decides the
// opacity, it decides HOW FAR UP THE LEG the crust reaches, and it decides how
// far the crust stands proud of the leg. All three fall away together as the
// walker sheds, so the legs clean up rather than switching off.
uniform float load : hint_range(0.0, 1.0) = 0.0;

// The Environment's own ambient fill, in LINEAR light, written by the node off
// the very Environment the character's coat is lit by.
//
// THIS IS THE OTHER HALF OF `ambient_light_disabled`, and without it the effect
// does not exist. `tests/art/test_character_lighting.gd` spells out why: the sun
// is at azimuth 118 against a camera yawed -35, nearly behind the lens, so every
// surface of the figure the camera can see is in its shade and the Environment's
// fill is very nearly the whole of the light on him. A shader that refuses
// ambient therefore renders a near-white crust as a dark blue-grey -- measured,
// and indistinguishable from the boot it is supposed to be sitting on.
//
// Adding it back as EMISSION rather than re-enabling ambient is not a dodge, it
// is the arithmetic: Godot's ambient contributes `ambient * ALBEDO` and this
// contributes exactly that, on this one material, read from the same two
// properties the gate reads. The fill stays a character control -- no world
// surface gains a light -- and the crust ends up in the same light as the coat
// underneath it, which is the only way the two can look like one leg.
uniform vec3 fill = vec3(0.0);

// The walker's own feet and his height, in world metres. Written every frame by
// the node -- his feet move, and a crust anchored to a stale height would climb
// his legs as he walked downhill.
uniform float origin_y = 0.0;
uniform float figure_height = 1.88;

// Where the crust's upper edge sits, as a fraction of the figure's height, with
// nothing on the legs and with a full load. See the bone measurements above:
// 0.10 is just over the ankle and 0.21 is mid-shin, comfortably under the knee
// at 0.257.
uniform float boot_line = 0.10;
uniform float shin_line = 0.21;

// How far below the edge the crust fades out. Snow on a leg has no hem, and
// this is also what absorbs the stride, per the note above.
uniform float feather = 0.055;

// The edge is not a ruled horizontal line, and it must not be: a crust that
// ends level all the way round reads as a painted-on sock. This wanders it by a
// smooth function of the surface's own UV, so the line differs around the leg,
// differs between the two legs, and -- being in UV rather than in any spatial
// coordinate -- STAYS ON THE SAME PATCH OF MESH through the whole walk cycle.
uniform float edge_wobble = 0.020;
uniform float wobble_frequency = 47.0;

// How far the crust stands off the leg, in metres. Small, and it earns its
// place twice: snow packed onto a boot genuinely sits proud of it, and a second
// pass drawn exactly coplanar with the first is a depth fight waiting for a
// driver to lose.
uniform float swell = 0.005;

// The most opaque the crust ever gets. Short of 1 on purpose -- a fully opaque
// white boot is a boot that has been replaced rather than one with snow on it.
uniform float max_opacity : hint_range(0.0, 1.0) = 0.86;

varying float crust;

void vertex() {
	// World, through the engine's own model matrix. See the note above: this is
	// the only height in this file that cannot be wrong about its units.
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float height = (world.y - origin_y) / max(figure_height, 0.0001);
	// Rises with the load: a full leg carries snow to mid-shin, and as it sheds
	// the line retreats down to the boot before it goes. That retreat is most of
	// what reads as "cleaning up" -- an edge that stayed put and only faded would
	// read as the effect being switched off.
	float edge = mix(boot_line, shin_line, load);
	edge += edge_wobble * sin(UV.x * wobble_frequency + UV.y * (wobble_frequency * 0.63));
	crust = (1.0 - smoothstep(edge - feather, edge, height)) * load;
	// The swell is authored in metres and applied in whatever units VERTEX uses,
	// so it is divided by the model matrix's own scale rather than assuming one.
	float metres_per_unit = max(length(MODEL_MATRIX[1].xyz), 0.000001);
	VERTEX += NORMAL * (swell / metres_per_unit) * crust;
}

void fragment() {
	ALBEDO = snow_color;
	// Snow is not wet and it is not metal. `specular_disabled` above is the
	// project-wide form of the same statement; these two keep it true of the
	// values as well as of the mode.
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// See `fill`: the ambient this shader is forbidden to receive, added back by
	// hand so the crust sits in the same light as the leg it is on.
	EMISSION = snow_color * fill;
	ALPHA = crust * max_opacity;
}
