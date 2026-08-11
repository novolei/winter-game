"""Build the snow-covered flatbed truck.

The second vehicle on the farm, and deliberately not a second pickup. The owner's
reference is a stake-bed working truck: **orange cab, blue-grey flatbed with tall
open side rails, dark wheels, and snow lying on the cab roof and along the bed
rails.** Bigger and older than the pickup that is already in the yard.

Run it -- Blender 5.x, background, no GUI:

    blender --background --python tools/blender/build_flatbed_truck.py

Optional arguments after `--`:

    --models  <dir>   default assets/models/props
    --source  <dir>   default assets/source/props
    --renders <dir>   default .superpowers/sdd/wave1
    --no-render       skip the acceptance render

---------------------------------------------------------------------------
THE RAILS FIT INSIDE 200, AND HERE IS THE ARITHMETIC
---------------------------------------------------------------------------
The brief asked to say so if they could not. They can, but only because the two
cheap primitives do the work the expensive one would have:

    hood 12 + cab 12 + cab-roof snow 12 + windscreen 2 + 2 side windows 4
    + grille 2 + bed deck 12 + bed snow 2 + headboard 12 + 2 top rails 24
    + 2 rail snow caps 4 + 4 stakes 24 + tail rail 12 + 4 wheels 64  =  198

Two things bought the rails. **The snow on the bed and along the rails is a flat
panel, 2 triangles, not a slab at 12.** The camera looks down at 45 degrees and
never rotates (rule 1), so snow lying on a horizontal surface is only ever seen
from above; a slab would spend ten triangles on four edges nobody can see. The
snow on the *cab roof* is a real slab, because that one is the silhouette against
the sky at gameplay framing and its edge is the whole point of it.

**A stake is a three-sided tube, 6 triangles, not a box at 12.** Same argument
the trees make: a triangular section is invisible on a post 14 cm thick, and four
stakes as boxes would have cost the tail rail and one wheel.

What did *not* fit and is not here: a second axle (a real flatbed of this size is
a six-wheeler), mudguards, mirrors, and a load on the bed. The first is 32
triangles for a shape that reads at 70 m as a slightly longer dark smudge under
the chassis; the others are all under a pixel.

---------------------------------------------------------------------------
COLOUR
---------------------------------------------------------------------------
Rule 12 allows warm colour in five places in the entire game and **卡车 -- the
truck -- is one of them**, which is what lets this asset carry an orange cab at
all. `PAL_WARM_2` (#A05A35, rust orange) rather than the pickup's `PAL_WARM_1`
(#6E2F2E, deep red): the two vehicles stand within thirty metres of each other in
the establishing shot and the whole reason for a second vehicle is that it is not
the first one.

The bed, the rails and the headboard are `PAL_STRUCT_1` -- the same blue-grey the
farmhouse siding uses -- so the cab is the only warm thing on the truck and the
warm quota is spent on the smaller half of the vehicle.
"""

import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402

BUDGET = 200
NAME = "Flatbed_Truck"
FILE = "flatbed_truck"

CAB = "PAL_WARM_2"          # rust orange -- rule 12's truck
BODY = "PAL_STRUCT_1"       # blue-grey flatbed, rails and headboard
DARK = "PAL_STRUCT_4"       # wheels, grille, glass
SNOW = "PAL_SNOW_1"
GLASS = "PAL_STRUCT_3"

# Everything in metres, Blender Z-up, the truck facing -Y (= Godot +Z).
HALF_WIDTH = 1.10
NOSE = -3.20
TAIL = 3.20
FRAME_TOP = 1.15            # the bed deck's top surface
FRAME_BOTTOM = 0.95
CAB_TOP = 2.45
RAIL_TOP = 2.20
WHEEL_R = 0.52


def build():
    # -- the cab, which is the warm half -------------------------------------
    # The hood stands between the fenders rather than flush with them, which is
    # the single detail that stops a 1950s truck reading as a van. It is
    # narrower and lower than the cab and it is a separate block for that
    # reason alone.
    kit.block("Hood", CAB, -0.86, 0.86, NOSE, -2.26, FRAME_TOP - kit.BITE, 1.68)
    kit.block("Cab", CAB, -HALF_WIDTH, HALF_WIDTH, -2.32, -1.08, FRAME_TOP - kit.BITE, CAB_TOP)

    # Rule 4: a window is a flat rectangle and nothing else.
    kit.panel("Windscreen", GLASS, "-y", -2.33, -0.80, 0.80, 1.80, 2.32)
    kit.panel("Window_L", GLASS, "-x", -HALF_WIDTH - 0.01, -2.10, -1.30, 1.84, 2.32)
    kit.panel("Window_R", GLASS, "+x", HALF_WIDTH + 0.01, -2.10, -1.30, 1.84, 2.32)
    kit.panel("Grille", DARK, "-y", NOSE - 0.01, -0.70, 0.70, 1.02, 1.42)

    # Snow on the cab roof. The one place on this truck it is a real slab: at
    # gameplay framing this edge is the truck's skyline.
    kit.block("Cab_Snow", SNOW, -1.06, 1.06, -2.34, -1.06, CAB_TOP - kit.BITE, CAB_TOP + 0.13)

    # -- the flatbed ---------------------------------------------------------
    kit.block("Bed_Deck", BODY, -HALF_WIDTH, HALF_WIDTH, -1.10, TAIL, FRAME_BOTTOM, FRAME_TOP)
    # Seen from above and from nowhere else -- see the header.
    kit.panel("Bed_Snow", SNOW, "+z", FRAME_TOP + 0.02, -1.02, 1.02, -1.04, TAIL - 0.06)

    # -- the rails, which are what make it a flatbed rather than a trailer ----
    kit.block("Headboard", BODY, -HALF_WIDTH, HALF_WIDTH, -1.10, -0.96, FRAME_TOP - kit.BITE, RAIL_TOP)
    kit.block("Tail_Rail", BODY, -HALF_WIDTH, HALF_WIDTH, TAIL - 0.14, TAIL, FRAME_TOP - kit.BITE, RAIL_TOP)
    for side, sign in (("L", -1.0), ("R", 1.0)):
        inner = sign * (HALF_WIDTH - 0.16)
        outer = sign * HALF_WIDTH
        kit.block("Rail_%s" % side, BODY,
                  min(inner, outer), max(inner, outer), -0.98, TAIL - 0.12,
                  RAIL_TOP - 0.17, RAIL_TOP)
        kit.panel("Rail_Snow_%s" % side, SNOW, "+z", RAIL_TOP + 0.02,
                  min(inner, outer) - 0.03, max(inner, outer) + 0.03,
                  -0.98, TAIL - 0.12)
        # Two uprights a side. With the headboard and the tail rail standing at
        # the ends, the side reads as four verticals under a top rail, which is
        # a stake bed. Three-sided tubes, buried at both ends: no caps needed.
        for index, at_y in enumerate((0.30, 1.90)):
            kit.tube("Stake_%s%d" % (side, index), BODY,
                     (sign * (HALF_WIDTH - 0.08), at_y, FRAME_TOP - 0.05),
                     (sign * (HALF_WIDTH - 0.08), at_y, RAIL_TOP - 0.10),
                     0.075, 0.070, sides=3)

    # -- wheels --------------------------------------------------------------
    # Six-sided tube plus one outer face, exactly as the pickup's: the inner cap
    # is pressed into the chassis and never seen, and 16 triangles a wheel
    # instead of 20 is what left room for the tail rail.
    for name, at_y in (("F", -2.40), ("R", 1.70)):
        for side, sign in (("L", -1.0), ("R", 1.0)):
            hub_in = sign * (HALF_WIDTH - 0.30)
            hub_out = sign * (HALF_WIDTH + 0.02)
            kit.tube("Wheel_%s%s" % (name, side), DARK,
                     (hub_in, at_y, WHEEL_R), (hub_out, at_y, WHEEL_R),
                     WHEEL_R, WHEEL_R, sides=6)
            kit.disc("Hub_%s%s" % (name, side), DARK,
                     (hub_out, at_y, WHEEL_R), (sign, 0.0, 0.0), WHEEL_R - 0.02, sides=6)


def main():
    root = kit.project_root()
    models = kit.argument("--models", os.path.join(root, "assets", "models", "props"))
    source = kit.argument("--source", os.path.join(root, "assets", "source", "props"))
    renders = kit.argument("--renders", os.path.join(root, ".superpowers", "sdd", "wave1"))

    kit.reset()
    build()
    obj = kit.finish(NAME, BUDGET, label=FILE)
    kit.export_glb(os.path.join(models, FILE + ".glb"))
    kit.save_blend(os.path.join(source, FILE + ".blend"))
    low, high = kit.bbox(obj)
    print("%s: %.2f x %.2f m, %.2f m to the rail top, %.2f m over the cab snow"
          % (FILE, high[0] - low[0], high[1] - low[1], RAIL_TOP, high[2]))
    if not kit.has_flag("--no-render"):
        fx, fy = high[0] + 1.3, low[1] + 0.4
        kit.three_quarter(
            os.path.join(renders, "prop-flatbed-truck.png"),
            [low, high] + kit.figure_corners(fx, fy),
            figure=(fx, fy, 0.4), resolution=(1400, 1050))


main()
