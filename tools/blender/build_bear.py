"""Bring the bear inside the low-poly look, and keep everything else it has.

    "The bear is realistic here and we need more low poly models, so I asked AI
     to decimate it in Blender."
                                                    -- the reference video

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_bear.py

Optional arguments after `--`:

    --source <fbx>     default assets/source/characters/bear/bear_animated.fbx
    --glb <path>       default assets/models/characters/bear/bear.glb
    --target <n>       triangles to aim at, default 3000
    --inventory        print every take with its length and root travel
    --no-export        measure and report, write nothing

---------------------------------------------------------------------------
WHY 3,000 AND NOT 7,508
---------------------------------------------------------------------------
The source is a realistic bear and this game is not realistic. The reference
video hit the same wall with the same asset and published its three decimation
stages -- 7,588 original, 2,996 in the game, 797 heavy -- and shipped the middle
one. Measured here the source is **7,508** triangles, so the video's own numbers
line up with this file to within eighty triangles and the middle tier is the
target.

Art Bible rule 6 caps a character at ~8,000, so the source would pass the gate
untouched. That is not the reason to decimate it. The reason is that a 7,500
triangle photoreal bear standing next to a farmhouse built from eight boxes
reads as an asset from another game -- **the budget is not the constraint here,
the look is**, and 3,000 is where the video landed after looking at it.

---------------------------------------------------------------------------
WHY THE TEXTURES STAY, WHEN NOTHING ELSE IN THIS FOLDER KEEPS TEXTURES
---------------------------------------------------------------------------
Art Bible rules 8 and 9 -- no normal maps, everything flat, colour only from the
12-entry table -- have an exception box, and characters are it:

    角色（主角、饿汉、熊）不受 12 色表与禁用特性清单约束，使用其自带的 PBR
    贴图与材质。

The world is the uniform blue so that a character can be picked out of it at a
glance, and a character needs its own surface to do that. So unlike
`tools/decimate_character.py`, which clears every material slot on the way past,
this script exports the bear's three materials and the five maps behind them:
head albedo + normal, body albedo + normal, teeth albedo. They are packed inside
the source FBX already, so they travel with the `.glb` and there is no second
file to keep in step.

The triangle budget is *not* waived by that box and says so in as many words:
rule 6 is a performance constraint and has nothing to do with colour. The check
at the end of this script is the same 8,000, and 3,000 clears it three-fold.

---------------------------------------------------------------------------
WHAT COMES OUT
---------------------------------------------------------------------------
One `.glb`: one mesh, a 35-bone rig, and **81 animation takes**. All 81 are
exported rather than the four the threat AI will start with, because picking the
subset is that batch's judgement and not this one's, and an unexported take
costs a re-run of this script to get back. `--inventory` prints them.

The four beats GDD section 8 needs -- *"it warns you first, and then it charges;
it knocks you down"* -- all exist in the source. The report names them.
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

# Rule 6. Not waived by the character exception box -- that box waives rules 8
# and 9 only.
TRIANGLE_BUDGET = 8000

# The reference video's middle tier. See the header.
TARGET_TRIANGLES = 3000

# Which take `rigkit.verify_export` re-poses the written .glb on. An idle: a
# cycle carrying root motion measures a different box every frame.
VERIFY_TAKE = "Stand_Idle_01"


def main():
    root = kit.project_root()
    source = kit.argument("--source", os.path.join(
        root, "assets", "source", "characters", "bear", "bear_animated.fbx"))
    destination = kit.argument("--glb", os.path.join(
        root, "assets", "models", "characters", "bear", "bear.glb"))
    target = int(kit.argument("--target", TARGET_TRIANGLES))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    rigkit.import_fbx(source)

    meshes = rigkit.meshes()
    armature = rigkit.armature()
    if not meshes:
        raise SystemExit("build_bear: %s holds no mesh" % source)
    if armature is None:
        raise SystemExit("build_bear: %s holds no armature" % source)

    before = rigkit.triangle_count(meshes)
    print("build_bear: source has %d triangles across %d mesh(es), %d bones, %d takes"
          % (before, len(meshes), len(armature.data.bones), len(bpy.data.actions)))

    # The FBX carries a null at the top of the hierarchy that holds nothing and
    # would export as an empty node for a reader to wonder about. Everything
    # with geometry or a bone in it is kept.
    rigkit.drop_empties()

    # Named for what they are rather than for what the exporter called them.
    #
    # The wrapper null above the armature is deliberately *not* removed -- see
    # `rigkit.drop_empties()`, which is where the eighty-five-times-too-big bear
    # is written up -- so this character's skeleton lands one level deeper than
    # the player's: `Bear/Armature/Skeleton3D` against `Armature/Skeleton3D`.
    # That is a path the threat batch reads once, not a scale bug it debugs.
    armature.name = "Armature"
    meshes[0].name = "Bear_Body"
    meshes[0].data.name = "Bear_Body"
    for obj in bpy.data.objects:
        if obj.type == "EMPTY" and obj.children:
            obj.name = "Bear"

    rigkit.decimate_to(meshes, target)
    after = rigkit.triangle_count(meshes)
    print("build_bear: decimated %d -> %d triangles (target %d)" % (before, after, target))
    if after > TRIANGLE_BUDGET:
        raise SystemExit("build_bear: %d triangles is over the %d character budget"
                         % (after, TRIANGLE_BUDGET))

    # The materials are the point of this asset and are deliberately NOT cleared
    # -- see the header. What is worth doing is telling the truth about them:
    # the source is a game asset from an engine with a specular workflow, and
    # left alone the glTF exporter writes a metallic of whatever the importer
    # guessed. Flat, rough, non-metal is what fur is.
    rigkit.make_matte(meshes)
    rigkit.report_materials(meshes)

    rigkit.rename_actions()
    if kit.has_flag("--inventory"):
        rigkit.print_inventory(armature)

    # The take the export is verified against, and a frame in the middle of
    # it. An idle rather than a charge: a cycle with root motion measures a
    # different box at every frame and the comparison would be noise.
    span = rigkit.posed_span(armature, VERIFY_TAKE)
    print("build_bear: %s is %s metres on %r; bind box %s"
          % (meshes[0].name, span, VERIFY_TAKE, rigkit.dimensions(meshes)))
    rigkit.clear_pose(armature)

    if kit.has_flag("--no-export"):
        print("build_bear: --no-export, nothing written")
        return

    rigkit.export_character_glb(destination)
    print("build_bear: wrote %s (%d triangles, %d takes)"
          % (destination, after, len(bpy.data.actions)))
    rigkit.verify_export(destination, VERIFY_TAKE, span)


main()
