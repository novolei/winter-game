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

Run it -- source path first, destination second:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/decimate_character.py -- <source.fbx> <dest.glb>
"""

import sys

import bpy

TRIANGLE_BUDGET = 8000

# Aim under the cap rather than at it. The decimator's collapse pass does not
# hit a requested ratio exactly, and a model that measures 7,999 is one Blender
# version away from failing the gate for no reason anyone will remember.
TARGET_TRIANGLES = 7000


def argv():
    if "--" not in sys.argv:
        raise SystemExit("decimate_character.py: expected '-- <source> <dest>'")
    rest = sys.argv[sys.argv.index("--") + 1:]
    if len(rest) != 2:
        raise SystemExit("decimate_character.py: expected exactly two paths after '--'")
    return rest[0], rest[1]


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


def main():
    source, destination = argv()

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
