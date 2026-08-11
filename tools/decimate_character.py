"""Bring an externally-sourced character mesh inside the Art Bible's budget.

Art Bible section 2 rule 6 caps a character at ~8,000 triangles, and section 5
names the remedy for outside art in as many words: *Blender decimate*. The
supplied Meshy model is 12,108 triangles, half again over, so it goes through
this script rather than into the repo as it arrived.

Section 5.0 then decides the output format: anything a Blender script produces
is a `.glb`. Section 5.1 decides that the script itself is the artifact -- when
the silhouette is wrong you change a number here and re-run, you do not edit a
mesh by hand.

Materials are dropped outright. Rule 8 bans normal, roughness, metallic and
specular maps and rule 9 requires flat palette colour, so the supplied
photographic PBR set has nothing to contribute; the game paints this mesh from
`data/palette/color_bible.tres` at runtime. `tools/strip_scene_materials.gd`
removes whatever Godot's importer invents on the way in.

Later animation deliveries are folded in here too, and that is not a
convenience -- it is the only correct place for them. Meshy ships extra takes as
animation-only FBXs, and Godot's own FBX importer lands them in a *different
space* from the one this script's glTF export produces: metres against this
file's centimetres, and one of them still Z-up. Measured on 4.7.1, the
character's Hips rest sits at y=85.07 out of the `.glb` and at z=0.84 out of the
same rig's animation-only `.fbx`. Copying a track from one to the other puts the
skeleton through a 100x scale and an axis swap, and the visible result is not an
error message -- it is a character who vanishes, because his bones have been
flung tens of metres apart. Bringing the extra takes through this same round
trip makes them land in the same space by construction, with nothing to retarget
and nothing to keep in step by hand.

Run it -- source path first, destination second, then any number of
animation-only FBXs. Each extra take is named after its own filename, so name
the file for what the motion is:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/decimate_character.py -- <source.fbx> <dest.glb> \
        [<animation.fbx> ...]
"""

import os
import sys

import bpy

TRIANGLE_BUDGET = 8000

# Aim under the cap rather than at it. The decimator's collapse pass does not
# hit a requested ratio exactly, and a model that measures 7,999 is one Blender
# version away from failing the gate for no reason anyone will remember.
TARGET_TRIANGLES = 7000


def argv():
    if "--" not in sys.argv:
        raise SystemExit("decimate_character.py: expected '-- <source> <dest> [anim ...]'")
    rest = sys.argv[sys.argv.index("--") + 1:]
    if len(rest) < 2:
        raise SystemExit("decimate_character.py: expected at least two paths after '--'")
    return rest[0], rest[1], rest[2:]


def import_source(path):
    """Import through whichever FBX operator this Blender build ships.

    5.x moved to a built-in `wm.fbx_import`; the Python `io_scene_fbx` add-on is
    still there in some builds and is not in others. Ask rather than assume.
    """
    if hasattr(bpy.ops.wm, "fbx_import"):
        bpy.ops.wm.fbx_import(filepath=path)
        return
    bpy.ops.import_scene.fbx(filepath=path)


def triangle_count(mesh_objects):
    total = 0
    for obj in mesh_objects:
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


def decimate(mesh_objects, ratio):
    for obj in mesh_objects:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        modifier = obj.modifiers.new(name="Budget", type="DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = ratio
        # Vertex weights survive a collapse, so the rig still drives the mesh
        # afterwards -- but only if the decimate runs before the armature
        # deform. Applying it out of order works and warns; moving it to the
        # top of the stack is free and does not.
        while obj.modifiers.find("Budget") > 0:
            bpy.ops.object.modifier_move_up(modifier="Budget")
        bpy.ops.object.modifier_apply(modifier="Budget")
        obj.select_set(False)


def rename_actions():
    """`Armature|Walking` back to `Walking`.

    Blender's FBX importer prefixes every take with the object it was bound to.
    glTF names its animations after the actions, and Godot names its animations
    after those -- so without this the game would be asking for a clip called
    `Armature|Walking`, which is a name nobody would choose to type twice.
    """
    for action in bpy.data.actions:
        if "|" in action.name:
            action.name = action.name.rsplit("|", 1)[-1]


def fcurves_of(action):
    """Blender 5 actions are slotted and no longer expose `fcurves` directly."""
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                curves.extend(bag.fcurves)
    return curves


def shift_to_frame_one(action):
    """Slide an action so its first key is on frame 1.

    Meshy's animation-only files start on frame 2. The glTF exporter bakes from
    frame 1 regardless, so the take ships with its first eighth of a second
    holding the *bind* pose -- and then snapping into the authored first frame.
    On the knockdown that is a 15 cm jolt of the hips before the blow lands,
    which reads as a hitch rather than as an anticipation.
    """
    start = action.frame_range[0]
    delta = 1.0 - start
    if abs(delta) < 0.5:
        return
    for curve in fcurves_of(action):
        for key in curve.keyframe_points:
            key.co.x += delta
            key.handle_left.x += delta
            key.handle_right.x += delta
        curve.update()


def merge_animation(armature, path):
    """Fold one animation-only FBX into the character's own action list.

    The take is named after the file rather than after whatever Meshy called it
    -- both deliveries so far arrived with their single action called `Scene`,
    so two of them merged under their own names would collide outright.

    Stashed into an NLA track rather than merely renamed, because that is what
    makes the glTF exporter see it. Blender's FBX importer stashes each take of
    a multi-take file the same way, which is why the eighteen in the character
    file all come out the other side; an action sitting loose in `bpy.data` with
    nothing referring to it does not.
    """
    known = set(bpy.data.actions.keys())
    objects = set(bpy.data.objects.keys())
    import_source(path)

    added = [a for a in bpy.data.actions if a.name not in known]
    if not added:
        raise SystemExit("decimate_character.py: %s holds no animation" % path)
    if len(added) > 1:
        raise SystemExit(
            "decimate_character.py: %s holds %d takes; this expects one per file "
            "because the take is named after the file" % (path, len(added))
        )

    action = added[0]
    action.name = os.path.splitext(os.path.basename(path))[0]
    action.use_fake_user = True
    shift_to_frame_one(action)

    if armature.animation_data is None:
        armature.animation_data_create()
    track = armature.animation_data.nla_tracks.new()
    track.name = action.name
    strip = track.strips.new(action.name, int(action.frame_range[0]), action)
    # Blender 5 actions carry slots; an unbound strip evaluates to nothing.
    if hasattr(action, "slots") and action.slots and hasattr(strip, "action_slot"):
        strip.action_slot = action.slots[0]
    # Muted, exactly as the FBX importer leaves the takes it stashes. The
    # exporter evaluates each action on its own; an unmuted stack would only
    # change what the viewport shows.
    track.mute = True

    # The rig that arrived with the take. Its bones are the same 24 by the same
    # names, which is why the action drops straight onto the character -- but
    # left in the scene it exports as a second skeleton.
    for name in list(bpy.data.objects.keys()):
        if name not in objects:
            bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)

    print("decimate_character: merged %s as %r (%d frames)" % (
        os.path.basename(path), action.name,
        int(action.frame_range[1] - action.frame_range[0]) + 1))


def main():
    source, destination, animations = argv()

    bpy.ops.wm.read_factory_settings(use_empty=True)
    import_source(source)

    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    if not meshes:
        raise SystemExit("decimate_character.py: the source holds no mesh")

    before = triangle_count(meshes)
    print("decimate_character: source has %d triangles" % before)

    if before > TRIANGLE_BUDGET:
        decimate(meshes, min(1.0, TARGET_TRIANGLES / float(before)))

    for obj in meshes:
        # Rule 8 and rule 9: nothing this model arrived with is usable, and a
        # material carried through to the .glb is a material the art gates have
        # to judge. Leave the surfaces bare.
        obj.data.materials.clear()

    after = triangle_count(meshes)
    print("decimate_character: writing %d triangles" % after)
    if after > TRIANGLE_BUDGET:
        raise SystemExit(
            "decimate_character.py: still %d triangles, over the %d budget"
            % (after, TRIANGLE_BUDGET)
        )

    rename_actions()

    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if animations and not armatures:
        raise SystemExit("decimate_character.py: the source holds no armature to merge takes onto")
    for path in animations:
        merge_animation(armatures[0], path)

    print("decimate_character: exporting %d takes" % len(bpy.data.actions))

    bpy.ops.export_scene.gltf(
        filepath=destination,
        export_format="GLB",
        export_materials="NONE",
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_bake_animation=True,
        # The takes are already sampled per frame and the walk cycle's first and
        # last frames are the same pose; trimming to "actually moved" would clip
        # the loop point off the end of the cycle.
        export_optimize_animation_size=False,
    )
    print("decimate_character: wrote %s" % destination)


main()
