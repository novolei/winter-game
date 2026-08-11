"""Collapse five Mixamo exports into one scavenger: one mesh, five takes.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_scavenger.py

Optional arguments after `--`:

    --source <dir>     default "Refs/game ref/zombie thread"
    --glb <path>       default assets/models/characters/scavenger/scavenger.glb
    --target <n>       triangles to aim at, default 7000
    --texture <n>      long-edge cap for every map, default 1024
    --inventory        print every take with its length and root travel
    --no-export        measure and report, write nothing

---------------------------------------------------------------------------
WHY THIS SCRIPT EXISTS AT ALL: 460 MB FOR ONE MESH AND FIVE CLIPS
---------------------------------------------------------------------------
Mixamo hands you a separate FBX per animation and **puts a full copy of the
character in each one**. Measured:

    Ch05_nonPBR@Boxing.fbx              115 MB   mesh + rig + 12 maps + 1 take
    Ch05_nonPBR@Falling Back Death.fbx  115 MB   mesh + rig + 12 maps + 1 take
    Ch05_nonPBR@Flying Back Death.fbx   115 MB   mesh + rig + 12 maps + 1 take
    Ch05_nonPBR@Knocked Out.fbx         115 MB   mesh + rig + 12 maps + 1 take
    Ch05_nonPBR@Kicking.fbx            0.5 MB   rig + 1 take, no mesh

Four identical 47,768-triangle meshes and forty-eight identical 4K maps, for one
character. Dropping that into `assets/models/` would quadruple this repository
for nothing, and Godot would import each copy separately.

So: the first file is the mesh, and every take after it is merged onto that one
rig and everything else the file brought is deleted before the next one opens.
`rigkit.merge_take()` does the deleting and its header says why that has to
happen per file rather than at the end.

The one 0.5 MB file is the shape all five should have been.

---------------------------------------------------------------------------
THE THREE NUMBERS
---------------------------------------------------------------------------
**47,768 -> 7,000 triangles.** Art Bible rule 6 caps a character at ~8,000 and
the source is six times over it. 7,000 rather than the bear's 3,000 because this
is a man standing next to another man: the player is 6,999 triangles after
`tools/decimate_character.py`, they appear at the same size on screen, and a
scavenger at a third of the player's density would read as the cheaper of the
two. The bear has no such neighbour to be compared against.

**4096 -> 1024 on every map.** Rule 1 puts a character at about 11% of screen
height -- roughly 120 px on a 1080p display -- so even 1024 is eight times more
texel than the screen can show. This is where 115 MB per file comes from and
almost all of it is invisible.

**12 maps -> 6.** Diffuse and Normal are kept, per the character exception box
in Art Bible section 2. Specular and Glossiness are dropped: the file calls
itself `nonPBR` and means it, glTF has no socket for either, and left connected
Blender's importer routes them into Roughness and Specular IOR Level, which the
exporter bakes into a metallic-roughness map -- and rule 8 bans specular
highlights across the whole game. `rigkit.make_matte()` does that and only that.

---------------------------------------------------------------------------
WHAT THIS DOES NOT DO
---------------------------------------------------------------------------
No behaviour, no state machine, no loop flags, no library resource. The takes
come through under English snake_case names and are enumerated in the wave
report; which of them the threat AI uses, and what is still missing for GDD
section 8's starving man, is that batch's call and the report's list.
"""

import os
import sys

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

import propkit as kit  # noqa: E402
import rigkit  # noqa: E402

TRIANGLE_BUDGET = 8000
TARGET_TRIANGLES = 7000
TEXTURE_LIMIT = 1024

# Which take `rigkit.verify_export` re-poses the written .glb on. `boxing` is
# in place; every other take in this set travels.
VERIFY_TAKE = "boxing"

# [file, take name]. The first entry is the one the mesh comes from; the rest
# contribute nothing but their single action.
#
# Names are English snake_case for the take, not for the file -- the files stay
# under Mixamo's own names so the delivery can still be traced -- and they say
# what the motion is rather than what it is for. `knocked_out` is not called
# `scared_off`: it is a man being knocked down, and calling it what the design
# wishes it were is how a placeholder survives into a shipped game.
TAKES = [
    ("Ch05_nonPBR@Boxing.fbx", "boxing"),
    ("Ch05_nonPBR@Kicking.fbx", "kicking"),
    ("Ch05_nonPBR@Falling Back Death.fbx", "falling_back_death"),
    ("Ch05_nonPBR@Flying Back Death.fbx", "flying_back_death"),
    ("Ch05_nonPBR@Knocked Out.fbx", "knocked_out"),
]


def main():
    root = kit.project_root()
    source = kit.argument("--source", os.path.join(root, "Refs", "game ref", "zombie thread"))
    destination = kit.argument("--glb", os.path.join(
        root, "assets", "models", "characters", "scavenger", "scavenger.glb"))
    target = int(kit.argument("--target", TARGET_TRIANGLES))
    texture_limit = int(kit.argument("--texture", TEXTURE_LIMIT))

    base_file, base_take = TAKES[0]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rigkit.import_fbx(os.path.join(source, base_file))

    meshes = rigkit.meshes()
    armature = rigkit.armature()
    if not meshes:
        raise SystemExit("build_scavenger: %s holds no mesh" % base_file)
    if armature is None:
        raise SystemExit("build_scavenger: %s holds no armature" % base_file)

    before = rigkit.triangle_count(meshes)
    print("build_scavenger: %s has %d triangles across %d mesh(es), %d bones"
          % (base_file, before, len(meshes), len(armature.data.bones)))

    rigkit.drop_empties()
    armature.name = "Armature"
    meshes[0].name = "Scavenger"
    meshes[0].data.name = "Scavenger"

    # Every Mixamo file's single action is called `mixamo.com`, so the base
    # file's take is renamed here for the same reason the merged ones are named
    # by the caller: five of them under their own name would be one.
    for action in bpy.data.actions:
        action.name = base_take
        action.use_fake_user = True
        rigkit.shift_to_frame_one(action)
    for track in (armature.animation_data.nla_tracks if armature.animation_data else []):
        track.name = base_take

    # Before the merges, not after. Each merge briefly holds a second set of
    # twelve 4K maps in memory, and shrinking the resident set first is the
    # difference between one spare copy and five.
    rigkit.downscale_images(texture_limit)

    for name, take in TAKES[1:]:
        rigkit.merge_take(armature, os.path.join(source, name), take)

    rigkit.decimate_to(meshes, target)
    after = rigkit.triangle_count(meshes)
    print("build_scavenger: decimated %d -> %d triangles (target %d)" % (before, after, target))
    if after > TRIANGLE_BUDGET:
        raise SystemExit("build_scavenger: %d triangles is over the %d character budget"
                         % (after, TRIANGLE_BUDGET))

    rigkit.make_matte(meshes)
    rigkit.report_materials(meshes)

    if len(bpy.data.actions) != len(TAKES):
        raise SystemExit("build_scavenger: %d takes in the scene, expected %d: %s"
                         % (len(bpy.data.actions), len(TAKES),
                            sorted(bpy.data.actions.keys())))

    if kit.has_flag("--inventory"):
        rigkit.print_inventory(armature)

    span = rigkit.posed_span(armature, VERIFY_TAKE)
    print("build_scavenger: %s is %s metres on %r; bind box %s"
          % (meshes[0].name, span, VERIFY_TAKE, rigkit.dimensions(meshes)))
    rigkit.clear_pose(armature)

    if kit.has_flag("--no-export"):
        print("build_scavenger: --no-export, nothing written")
        return

    rigkit.export_character_glb(destination)
    print("build_scavenger: wrote %s (%d triangles, %d takes)"
          % (destination, after, len(bpy.data.actions)))
    rigkit.verify_export(destination, VERIFY_TAKE, span)


main()
