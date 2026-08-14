"""Build the tire swing.

The smallest asset in the wave and the one that does the most work per triangle.
Every other thing on this farm says a place exists; this one says people lived
here, and specifically that a child did. It hangs from the low limb of
`tree_bare_a`, which is bare to two levels for exactly that reason -- a limb
somebody put a rope on has been climbed.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_tire_swing.py

Optional arguments after `--`: `--glb`, `--blend`, `--renders`, `--no-render`.

---------------------------------------------------------------------------
THE ORIGIN IS AT THE TOP, NOT ON THE GROUND
---------------------------------------------------------------------------
Every other asset in this wave has its origin on the ground because that is
where it meets the world. This one meets the world at the *branch*, so the
origin is the hang point and the whole model is below it: rope from Z=0 down to
Z=-1.42, tire hanging under that, lowest point Z=-2.15. Place the node at a
branch and it hangs correctly with no offset arithmetic.

`tools/blender/build_trees.py` prints the anchor on tree A's swing limb:

    tree_bare_a swing anchor  (-1.90, 0.14, 2.80)   local metres, Blender Z-up

which is (-1.90, 2.80, -0.14) in Godot. Hung there, the bottom of the tire is
0.65 m above the ground before snow.

---------------------------------------------------------------------------
WHY A TORUS IS ALLOWED HERE
---------------------------------------------------------------------------
Nothing else in this wave is round -- the doctrine is boxes, and rule 5 bans
bevels. A tire is the one object whose entire identity is that it is a ring: a
box tire is a box. It is 10 segments around and 3 across, 60 triangles, and at
three across the tube's section is a triangle, which is invisible on something
70 mm thick and near-black. That leaves the rope and the knot inside 100.
"""

import math
import os
import sys

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402

BUDGET = 100

RUBBER = "PAL_STRUCT_4"
ROPE = "PAL_STRUCT_3"

# The first 18 cm enters the supporting limb.  A rope cannot visually begin on
# a hard-edged low-poly branch without a pinhole of sky at some camera angles;
# a short overlap makes the attachment read as tied into the wood, not merely
# placed against it.
ROPE_BRANCH_OVERLAP_Z = 0.18
ROPE_END_Z = -1.42
TIRE_R = 0.265             # to the middle of the tread
TIRE_THICK = 0.105
HUB_Z = ROPE_END_Z - TIRE_R - TIRE_THICK * 0.5


def build():
    # Two segments so the rope has a kink in it. One straight segment reads as
    # a rod, and a rod does not swing.
    kit.tube("Rope_Upper", ROPE, (0.0, 0.0, ROPE_BRANCH_OVERLAP_Z), (0.035, 0.02, -0.74),
             0.022, 0.022, sides=3)
    kit.tube("Rope_Lower", ROPE, (0.035, 0.02, -0.74), (0.0, 0.0, ROPE_END_Z),
             0.022, 0.022, sides=3)
    kit.block("Knot", ROPE, -0.05, 0.05, -0.05, 0.05, ROPE_END_Z - 0.09, ROPE_END_Z + 0.02)
    # Axis along Y, so the tire hangs face-on to Godot's +Z -- the same way the
    # farmhouse porch and the truck's grille face.
    kit.ring("Tire", RUBBER, (0.0, 0.0, HUB_Z), (0.0, 1.0, 0.0),
             TIRE_R, TIRE_THICK, major_seg=10, minor_seg=3)


def main():
    root = kit.project_root()
    glb = kit.argument("--glb", os.path.join(
        root, "assets", "models", "props", "tire_swing.glb"))
    blend = kit.argument("--blend", os.path.join(
        root, "assets", "source", "props", "tire_swing.blend"))
    renders = kit.argument("--renders", os.path.join(root, ".superpowers", "sdd", "wave1"))

    kit.reset()
    build()
    obj = kit.finish("Tire_Swing", BUDGET, label="tire_swing")
    low, high = kit.bbox(obj)
    print("tire_swing: hangs %.2f m below its origin, tire %.2f m across"
          % (-low[2], 2.0 * (TIRE_R + TIRE_THICK * 0.5)))
    kit.export_glb(glb)
    kit.save_blend(blend)

    if not kit.has_flag("--no-render"):
        # Everything from here down is render-only: the export is already
        # written, so nothing added now can reach the .glb.
        #
        # The swing hangs *below* its origin, so for a picture it is lifted onto
        # a stub of branch at a plausible height and given ground to shadow.
        hang = 2.55
        obj.location.z = hang
        kit.tube("Render_Limb", kit.TIMBER, (-1.30, 0.35, hang + 0.28),
                 (0.95, -0.22, hang + 0.60), 0.085, 0.045, sides=4)
        low2 = (low[0] - 1.4, low[1] - 0.4, 0.0)
        high2 = (high[0] + 1.1, high[1] + 0.5, high[2] + hang + 0.25)
        fx, fy = 1.5, -0.9
        kit.three_quarter(
            os.path.join(renders, "prop-tire-swing.png"),
            [low2, high2] + kit.figure_corners(fx, fy),
            figure=(fx, fy, math.radians(210.0)), resolution=(1300, 1150))


main()
