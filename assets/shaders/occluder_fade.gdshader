shader_type spatial;

// What a thing standing between the camera and the player turns into.
//
// See src/rendering/occluder_fader.gd for the whole feature. Two render modes
// here are the reason this is its own shader rather than the cel shader with
// both bands set to one colour:
//
//   blend_mix        the object has to be see-through, not dithered. A stipple
//                    at this frame size reads as noise, not as glass.
//   depth_draw_never THE ONE THAT MATTERS. A faded occluder that still writes
//                    depth still HIDES the character -- measured: with the tree
//                    faded to a translucent grey and still writing depth, the
//                    figure behind it was culled exactly as before and only his
//                    head, which cleared the crown, was drawn. The fade would
//                    have looked right in a screenshot of the tree and done
//                    nothing at all for the thing it exists to fix.
//
// unshaded, and both `ambient_light_disabled` and `specular_disabled` are here
// to keep the promise every other shader in this project makes -- see
// tests/art/test_character_lighting.gd, which asserts the first of those across
// every shader on disk, and Art Bible rule 8 for the second.
render_mode unshaded, blend_mix, depth_draw_never, cull_back,
	ambient_light_disabled, specular_disabled, shadows_disabled, fog_disabled;

// The whole object, one flat colour. Set from data by OccluderFader --
// data/rendering/occluder_fade.tres -- and off the 12-colour palette by the
// owner's ruling that this is a rendering affordance and not an albedo.
//
uniform vec4 tint : source_color = vec4(0.09, 0.09, 0.11, 1.0);

// How much of the tint reaches the screen, PER INSTANCE.
//
// `GeometryInstance3D.transparency` is what the rest of this project fades
// with, and it does not work here: it fades a material that never writes ALPHA
// (measured by the interior agent on the cel shader), but a shader that assigns
// ALPHA itself -- as this one must, to be genuinely see-through -- overwrites
// whatever the instance asked for. The first build of this shader came back a
// solid near-black tree.
//
// An `instance uniform` gets the per-object number back without a material per
// object: one material for every faded thing in the frame, and
// `set_instance_shader_parameter()` for how far along each of them is.
instance uniform float fade_opacity = 1.0;

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a * fade_opacity;
}
