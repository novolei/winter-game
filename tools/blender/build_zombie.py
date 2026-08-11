"""Fold the Scary Zombie Pack into one character: one mesh, twelve takes.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_zombie.py

Optional arguments after `--`:

    --source <dir>     default assets/source/characters/zombie
    --glb <path>       default assets/models/characters/zombie/zombie.glb
    --target <n>       triangle ceiling, default 7600
    --texture <n>      long-edge cap for every map, default 1024
    --inventory        print every take with its length and root travel
    --no-export        measure and report, write nothing

---------------------------------------------------------------------------
THIS IS THE SHAPE THE SCAVENGER SET SHOULD HAVE HAD
---------------------------------------------------------------------------
`Zombiegirl W Kurniawan.fbx` is 16.9 MB and holds the mesh, the rig and the
maps and **no animation at all**; the twelve takes are 0.3-0.8 MB each and hold
a rig and one action and no mesh. 23 MB for a complete character with twelve
clips, against the `zombie thread` folder's 460 MB for one character with five
-- because that one put a full copy of the mesh and twelve 4K maps inside every
single file. Same exporter, same site, two different download options.

`tools/blender/build_scavenger.py` therefore has a purge step per merge and this
script does not need one; `rigkit.merge_take()` runs it either way and it costs
nothing when there is nothing to purge.

---------------------------------------------------------------------------
TRIANGLES: NOTHING IS DECIMATED HERE, DELIBERATELY
---------------------------------------------------------------------------
The source is **7,448** triangles across three meshes -- body 5,408, top 1,154,
pants 886 -- and Art Bible rule 6 caps a character at ~8,000. It is already
inside the budget, so the ceiling below is above it and `decimate_to()` returns
without touching anything.

That is a decision, not an oversight. Rule 6 is a cap, not a target: the bear
was collapsed because a photoreal bear next to a farmhouse made of eight boxes
reads as an asset from another game, and the scavenger because it was six times
over. Neither applies here. And this character is three separate meshes, so one
shared decimate ratio would thin the top's and the pants' silhouettes -- 6% off
an 886-triangle garment is paid entirely at its outline -- to buy 450 triangles
nothing is short of.

The number is here so a bigger re-delivery still lands in budget rather than
sailing past the gate.

---------------------------------------------------------------------------
WHAT THE TAKES ARE FOR
---------------------------------------------------------------------------
GDD section 8 keeps threats rare -- very few of them, and every meeting able to
kill you. So the takes that matter are the ones that sell **one** encounter,
not crowd variety: `idle`, `walk`, `scream`, `attack`.

`scream` is a design asset rather than a piece of audio. GDD section 9 builds
dread by taking the music *away*; the scream is what cuts through that silence,
and its timing is the whole effect. It is 85 frames at 30 fps in the source and
this script asserts it is still 85 on the way out -- see `EXPECTED_FRAMES`.
Nothing in the merge should resample a take, and an assertion is cheaper than
discovering in-game that something did.

`crawl` and `crawl_run` are kept and named plainly. A zombie crawling through
deep snow is the most specific image in this pack.
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
TARGET_TRIANGLES = 7600      # a ceiling above the source, not a target. See the header.
TEXTURE_LIMIT = 1024

# Which take `rigkit.verify_export` re-poses the written .glb on. An idle: the
# walk, run and both crawls carry root motion.
VERIFY_TAKE = "idle"

MESH_FILE = "Zombiegirl W Kurniawan.fbx"

# [file, take name]. Every one of these is animation-only; the mesh file above
# carries no action at all.
#
# Named for the motion in English snake_case (briefing constraint 3), and named
# *plainly*: `dying` and `death` are two different takes in the pack and both
# are kept under names that say which is which rather than merged into one
# guess. `biting_alt` is the pack's `zombie biting (2)`.
TAKES = [
    ("zombie idle.fbx", "idle"),
    ("zombie walk.fbx", "walk"),
    ("zombie run.fbx", "run"),
    ("zombie crawl.fbx", "crawl"),
    ("running crawl.fbx", "crawl_run"),
    ("zombie scream.fbx", "scream"),
    ("zombie attack.fbx", "attack"),
    ("zombie neck bite.fbx", "neck_bite"),
    ("zombie biting.fbx", "biting"),
    ("zombie biting (2).fbx", "biting_alt"),
    ("zombie death.fbx", "death"),
    ("zombie dying.fbx", "dying"),
]

# Measured off the sources before the merge. Checked after it, because a merge
# that quietly resamples a take does not error -- it just makes the scream a
# different scream. See the header.
EXPECTED_FRAMES = {
    "idle": 131, "walk": 122, "run": 25, "crawl": 155, "crawl_run": 21,
    "scream": 85, "attack": 80, "neck_bite": 126, "biting": 209,
    "biting_alt": 71, "death": 90, "dying": 101,
}

# Renamed from the source's `ZombieGirl_*`, so the three parts read in English
# and sort together in Godot's scene tree.
MESH_NAMES = {
    "ZombieGirl_Body": "Zombie_Body",
    "ZombieGirl_Top": "Zombie_Top",
    "ZombieGirl_Pants": "Zombie_Pants",
}


def main():
    root = kit.project_root()
    source = kit.argument("--source", os.path.join(
        root, "assets", "source", "characters", "zombie"))
    destination = kit.argument("--glb", os.path.join(
        root, "assets", "models", "characters", "zombie", "zombie.glb"))
    target = int(kit.argument("--target", TARGET_TRIANGLES))
    texture_limit = int(kit.argument("--texture", TEXTURE_LIMIT))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    rigkit.import_fbx(os.path.join(source, MESH_FILE))

    meshes = rigkit.meshes()
    armature = rigkit.armature()
    if not meshes:
        raise SystemExit("build_zombie: %s holds no mesh" % MESH_FILE)
    if armature is None:
        raise SystemExit("build_zombie: %s holds no armature" % MESH_FILE)
    if bpy.data.actions:
        raise SystemExit("build_zombie: %s unexpectedly holds %d take(s); the "
                         "merge below assumes the mesh file is animation-free"
                         % (MESH_FILE, len(bpy.data.actions)))

    before = rigkit.triangle_count(meshes)
    print("build_zombie: %s has %d triangles across %d meshes, %d bones"
          % (MESH_FILE, before, len(meshes), len(armature.data.bones)))
    for obj in meshes:
        obj.data.calc_loop_triangles()
        print("build_zombie:   %-22s %5d triangles" % (obj.name, len(obj.data.loop_triangles)))

    rigkit.drop_empties()
    armature.name = "Armature"
    for obj in meshes:
        renamed = MESH_NAMES.get(obj.name)
        if renamed:
            obj.name = renamed
            obj.data.name = renamed

    rigkit.downscale_images(texture_limit)

    for name, take in TAKES:
        rigkit.merge_take(armature, os.path.join(source, name), take)

    rigkit.decimate_to(meshes, target)
    after = rigkit.triangle_count(meshes)
    if after > TRIANGLE_BUDGET:
        raise SystemExit("build_zombie: %d triangles is over the %d character budget"
                         % (after, TRIANGLE_BUDGET))

    rigkit.make_matte(meshes)
    rigkit.report_materials(meshes)

    if len(bpy.data.actions) != len(TAKES):
        raise SystemExit("build_zombie: %d takes in the scene, expected %d: %s"
                         % (len(bpy.data.actions), len(TAKES), sorted(bpy.data.actions.keys())))
    wrong = []
    for action in bpy.data.actions:
        frames = int(action.frame_range[1] - action.frame_range[0]) + 1
        expected = EXPECTED_FRAMES.get(action.name)
        if expected is not None and frames != expected:
            wrong.append("%s is %d frames, was %d in the source" % (action.name, frames, expected))
    if wrong:
        raise SystemExit("build_zombie: a take changed length in the merge: %s" % "; ".join(wrong))
    print("build_zombie: all %d takes kept their source length" % len(bpy.data.actions))

    if kit.has_flag("--inventory"):
        rigkit.print_inventory(armature)

    span = rigkit.posed_span(armature, VERIFY_TAKE)
    print("build_zombie: %d triangles, %s metres on %r; bind box %s"
          % (after, span, VERIFY_TAKE, rigkit.dimensions(meshes)))
    rigkit.clear_pose(armature)

    if kit.has_flag("--no-export"):
        print("build_zombie: --no-export, nothing written")
        return

    rigkit.export_character_glb(destination)
    print("build_zombie: wrote %s (%d triangles, %d takes)"
          % (destination, after, len(bpy.data.actions)))
    rigkit.verify_export(destination, VERIFY_TAKE, span)


main()
