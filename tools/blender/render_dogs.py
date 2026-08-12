"""Acceptance renders for the three dogs, from the exported `.glb` files.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/render_dogs.py

Optional arguments after `--`: `--models <dir>`, `--out <dir>`, `--only <name>`,
`--samples <n>`.

Built from the `.glb` rather than by calling `build_dog.py` again, for the reason
`render_threats.py` gives: it is also the cheapest end-to-end check of the
export. A take that failed to stash, a rig that lost its root bone or a dog that
came out at the wrong scale shows up here and nowhere else in Blender.

---------------------------------------------------------------------------
WHY THE AUTHORED TAKES GET THREE FRAMES EACH AND THE PACK'S GET ONE
---------------------------------------------------------------------------
The pack's five are motion somebody else made and this project only has to carry
intact; one posed frame proves the weights survived and the take is not the bind
pose. `lie` and `growl` are authored here, so what has to be looked at is not
whether they move but whether they READ -- and that is a question about a
silhouette at one instant, three times over, not about a cycle.

The `lie` breath is deliberately sampled at its two extremes and its middle: a
breath that is visible in a still pair is a breath that is too big.

---------------------------------------------------------------------------
THE CAMERA IS ROUND THE FRONT, AND THAT COST A ROUND OF WRONG CONCLUSIONS
---------------------------------------------------------------------------
`propkit.three_quarter`'s default azimuth of 30 degrees puts the camera behind
these models, because `build_dog.py` turns the rig to face Godot's -Z and the
prop renders were framed for objects that face the other way. From behind, at 45
degrees down, a dog's skull foreshortens into what looks exactly like a muzzle
pointing at the sky -- and the first pass of this wave read the walk, the sit and
the growl as having the head thrown back, on all three dogs, and started
"fixing" a rig that was correct. The source FBX rendered at the same frame
settled it: identical bounding box to four decimals, head plainly down.

So: azimuth round the front, elevation low enough to read a silhouette against
the horizon rather than a plan view of the animal's back.

These are Cycles renders under a plain low sun and the game will not look like
this. Read them for silhouette, deformation and scale. The frames that answer
"does this belong in the valley" are the Godot captures in the wave report,
taken at the game camera under the game's own light.
"""

import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import propkit as kit  # noqa: E402
import rigkit  # noqa: E402

## Round the front of a model that faces glTF -Z, and low. See the header.
AZIMUTH = 215.0
ELEVATION = 22.0

# [take, where in the take, what the frame is for].
SHOTS = [
    ("idle", 0.50, "the shape, on all fours"),
    ("walk", 0.30, "mid-stride: proves the skin still follows the rig"),
    ("run", 0.40, "the gait the companion will spend most of its time in"),
    ("sit", 1.00, "the pack's closest thing to a settled dog"),
    ("bark", 0.45, "the mouth open, which is the only take with a jaw in it"),
    ("stand", 1.00, "the settle into an alert four-footed stance"),
    # 0.125, not 0.25: the take holds TWO breaths, so a quarter of the way
    # through is a zero crossing and the two frames come out identical -- which
    # is what the first pass sampled, and it reported a breath that was not
    # moving.
    ("lie", 0.00, "the rescue scene's opening pose, at the bottom of a breath"),
    ("lie", 0.125, "the top of the breath"),
    ("lie", 0.60, "the tail twitch"),
    ("growl", 0.00, "head low and forward, weight back"),
    ("growl", 0.25, "the tail at one end of its sweep"),
    ("growl", 0.75, "and at the other"),
]


def import_glb(path):
    kit.reset()
    bpy.ops.import_scene.gltf(filepath=path)
    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if not armatures:
        raise SystemExit("render_dogs: %s has no armature" % path)
    return armatures + rigkit.skinned_meshes()


def posed_bounds(objects):
    """World-space (min, max) of the meshes as posed, not as bound."""
    graph = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in objects:
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        for vertex in mesh.vertices:
            world = evaluated.matrix_world @ vertex.co
            for axis in range(3):
                lo[axis] = min(lo[axis], world[axis])
                hi[axis] = max(hi[axis], world[axis])
        evaluated.to_mesh_clear()
    return lo, hi


def shot(breed, model_dir, out_dir, take, where, samples):
    made = import_glb(os.path.join(model_dir, "dogs", "%s.glb" % breed))
    armatures = [obj for obj in made if obj.type == "ARMATURE"]
    if bpy.data.actions.get(take) is None:
        # Not fatal: the chihuahua genuinely has no `stand`, which is the
        # pack's gap and the reason `DogAnimations` has a fallback rule at all.
        # A renderer that stopped here would make an honest hole look like a
        # broken build.
        print("render_dogs: %s has no take %r -- skipped; it has %s"
              % (breed, take, sorted(bpy.data.actions.keys())))
        return
    frame = rigkit.set_pose(armatures[0], take, where)
    lo, hi = posed_bounds(made)

    # NOT stood on the ground the way render_threats.py does it. Whether these
    # poses reach z = 0 by themselves is the thing under test -- `lie` is settled
    # onto the floor by measurement in build_dog.py and a render that silently
    # lifted it would hide a dog buried in the snow.
    # Close to the animal, not the 0.9 m `render_threats.py` uses. A dog is a
    # tenth of a bear's volume and the figure at arm's length is what decides the
    # frame: at 0.9 m the golden retriever lying down was 12% of the image and
    # the pose could not be read at all.
    figure_x = hi.x + 0.45
    corners = [tuple(lo), tuple(hi)] + kit.figure_corners(figure_x, 0.0)
    name = "%s-%s-%02d" % (breed, take, int(round(where * 100)))
    print("render_dogs: %-30s frame %-4d  %.3f x %.3f x %.3f m  floor z %+.4f"
          % (name, frame, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, lo.z))
    kit.three_quarter(os.path.join(out_dir, "%s.png" % name), corners,
                      figure=(figure_x, 0.0, 0.0), samples=samples,
                      resolution=(1100, 850), azimuth=AZIMUTH, elevation=ELEVATION)


def main():
    root = kit.project_root()
    model_dir = kit.argument("--models", os.path.join(root, "assets", "models", "characters"))
    out_dir = kit.argument("--out", os.path.join(root, ".superpowers", "sdd", "wave3", "dogs"))
    only = kit.argument("--only", "")
    samples = int(kit.argument("--samples", 40))

    for breed in ("chihuahua", "golden_retriever", "great_dane"):
        for take, where, purpose in SHOTS:
            if only and only not in "%s-%s" % (breed, take):
                continue
            shot(breed, model_dir, out_dir, take, where, samples)


main()
