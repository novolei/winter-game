"""Acceptance renders for the three threats, from the exported .glb files.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/render_threats.py

Optional arguments after `--`: `--models <dir>`, `--out <dir>`, `--only <name>`,
`--samples <n>`.

Built from the `.glb` files rather than by calling the build scripts again, for
the reason `render_farmstead.py` gives: it is also the cheapest end-to-end check
of the exports. A model that failed to write, exported inside-out, lost its maps
or came out at the wrong scale shows up here and nowhere else in this wave.

---------------------------------------------------------------------------
WHY EVERY ONE OF THESE IS A *POSED* FRAME
---------------------------------------------------------------------------
A decimated skinned mesh has exactly one interesting failure mode: the collapse
runs after the armature deform instead of before it, the vertex weights are
scrambled, and the model **looks perfect in bind pose** and tears itself apart
the moment a take plays. A render of the rest pose cannot see that -- it is the
one pose that is right either way.

So each render below sets a real take at a real frame. If the weights survived
the collapse the bear rears up on its hind legs; if they did not, this is where
it is obvious.

Every image also carries the 1.8 m scale figure from `propkit`, because "is this
the right size" is not answerable from a picture of one object.

The usual caveat applies: these are Cycles renders under a plain low sun and the
game will not look like this. Read them for silhouette, deformation and scale.
"""

import os
import sys

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import propkit as kit  # noqa: E402
import rigkit  # noqa: E402

# [output name, model, take, where in the take, what it is for].
#
# `where` is a fraction of the take's frame range. Fractions rather than frame
# numbers so a re-delivery of the same motion at a different length still lands
# on the same beat.
SHOTS = [
    ("bear-idle", "bear/bear.glb", "Stand_Idle_01", 0.00,
     "the shape, on all fours"),
    ("bear-warning", "bear/bear.glb", "Trans_Stand_to_StandHind", 1.00,
     "GDD 8's warning: reared up on the hind legs"),
    ("bear-charge", "bear/bear.glb", "Run", 0.35,
     "GDD 8's charge, mid-stride"),
    ("bear-attack", "bear/bear.glb", "Attack_StandAngry_01_High", 0.55,
     "GDD 8's blow -- the one that knocks the player down"),

    ("scavenger-boxing", "scavenger/scavenger.glb", "boxing", 0.30,
     "the only aggression take the folder has"),
    ("scavenger-knocked-out", "scavenger/scavenger.glb", "knocked_out", 0.45,
     "the reaction takes are the valuable half of this set"),

    ("zombie-idle", "zombie/zombie.glb", "idle", 0.50,
     "the shape and the scale"),
    ("zombie-scream", "zombie/zombie.glb", "scream", 0.55,
     "GDD 9's payoff, cutting through the silence"),
    ("zombie-crawl", "zombie/zombie.glb", "crawl", 0.50,
     "a crawling body in deep snow"),
]


def import_glb(path):
    """Import, and return the objects the *rig* accounts for.

    Not a set-difference against `bpy.data.objects` before the import, which is
    what `render_farmstead.py` does and what the first version of this did.
    `read_factory_settings(use_empty=True)` leaves the startup file's Icosphere
    resident, removing it does not survive the next import, and it lands on the
    "new" side of the difference -- so a 2 m sphere at the origin joined every
    bounding box and every shot was framed for a subject twice the size of its
    subject. `rigkit.skinned_meshes()` has the measurements.
    """
    kit.reset()
    bpy.ops.import_scene.gltf(filepath=path)
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not armatures:
        raise SystemExit("render_threats: %s has no armature" % path)
    return armatures + rigkit.skinned_meshes()


def posed_bounds(objects):
    """World-space (min, max) of the meshes **as posed**.

    `obj.bound_box` is the bind-pose mesh and is the wrong box for every frame
    in this file. The evaluated depsgraph copy is the one the renderer draws.
    """
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


def shot(name, model_dir, out_dir, relative, take, where, samples):
    path = os.path.join(model_dir, relative)
    made = import_glb(path)
    armatures = [o for o in made if o.type == "ARMATURE"]
    roots = []
    for obj in made:
        top = obj
        while top.parent is not None:
            top = top.parent
        if top not in roots:
            roots.append(top)

    frame = rigkit.set_pose(armatures[0], take, where)
    lo, hi = posed_bounds(made)

    # Stand it on the ground plane. The exports keep their source's own origin
    # and two of the three sit below zero in some poses; a character sunk into
    # the snow is a render artefact that reads as a modelling error.
    for root in roots:
        root.location.z -= lo.z
    bpy.context.view_layer.update()
    lo, hi = posed_bounds(made)

    # The figure stands clear of the widest point rather than at a fixed
    # distance: the bear reared up is three times the footprint of the bear
    # walking, and a fixed offset puts the figure inside it.
    figure_x = hi.x + 0.9
    corners = [tuple(lo), tuple(hi)] + kit.figure_corners(figure_x, 0.0)

    print("render_threats: %-22s take %-26s frame %-4d  %.2f x %.2f x %.2f m"
          % (name, take, frame, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))

    kit.three_quarter(os.path.join(out_dir, "%s.png" % name), corners,
                      figure=(figure_x, 0.0, 0.0), samples=samples,
                      resolution=(1200, 900))


def main():
    root = kit.project_root()
    model_dir = kit.argument("--models", os.path.join(root, "assets", "models", "characters"))
    out_dir = kit.argument("--out", os.path.join(root, ".superpowers", "sdd", "wave5"))
    only = kit.argument("--only", "")
    samples = int(kit.argument("--samples", 48))

    for name, relative, take, where, purpose in SHOTS:
        if only and only not in name:
            continue
        print("render_threats: %s -- %s" % (name, purpose))
        shot(name, model_dir, out_dir, relative, take, where, samples)


main()
