"""Build the tool shed -- the small outbuilding beside the farmhouse.

Boxes and a roof, exactly as the farmhouse is, in the same clapboard blue:
`PAL_STRUCT_1` walls, `PAL_STRUCT_4` roof, `PAL_SNOW_1` snow, `PAL_SNOW_2`
icicles. Nothing here is a colour the house does not already use, which is the
point -- the shed has to read as belonging to the same farm.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_tool_shed.py

Optional arguments after `--`: `--glb`, `--blend`, `--renders`, `--no-render`.

---------------------------------------------------------------------------
WHY IT IS FILED UNDER buildings/ AND NOT props/
---------------------------------------------------------------------------
Art Bible rule 6 gives a secondary building 500 triangles and a prop 200. This
is a building by class -- a gable roof, a door, a foundation, an eave -- and it
comes in at 240, so filed as a prop it would fail `tests/art/test_topology.gd`
against a budget written for crates and buckets.

The first version of this script put it in `assets/models/props/tool_shed/` and
proposed to raise that folder's budget to 500. That was the wrong instinct and
the coordinator rejected it: **put an asset where its kind belongs and let the
budget follow, rather than choosing a folder and then editing the gate to suit
the number.** A raised budget is a weakened gate even when the number is
defensible, and `assets/models/buildings` already says 500 without anyone
touching a test. No gate was changed for this asset.

---------------------------------------------------------------------------
THE SHAPE
---------------------------------------------------------------------------
3.00 x 2.30 m on plan, eave at 2.25 m, ridge at 2.95 m, ridge running along X.
The front roof runs 0.58 m past the wall on the slope and lands on two posts,
which makes the covered bay the reference shows and gives the icicles an eave
to hang from. Clearance under that eave is 1.86 m -- a 1.8 m character walks
under it with nothing to spare, which is the check that decided the pitch, and
it is the whole reason this reads as a *shed* rather than as a small house.

Front faces -Y in Blender, which is +Z in Godot: the same way the farmhouse
porch faces. Origin is on the ground at the centre of the plan.
"""

import math
import os
import sys

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402

## The Art Bible's secondary-building tier. See the docstring.
BUDGET = 500

X0, X1 = -1.50, 1.50
Y0, Y1 = -1.15, 1.15
T = 0.12                   # wall thickness
BASE_Z = 0.16              # top of the foundation
EAVE_Z = 2.25              # top of the walls
RIDGE_Z = 2.95
RUN, RISE = 1.15, 0.70     # half-span and rise: a 31.3 degree pitch
SLOPE = math.hypot(RUN, RISE)
VERGE = 0.20               # roof overhang past the gable ends
FRONT_EAVE = 0.58          # ...and past the front wall, measured down the slope
BACK_EAVE = 0.22
ROOF_T = 0.10
SNOW_T = 0.13

## Where the front roof edge ends up, which is what the posts have to reach and
## what the icicles hang off. Derived rather than typed, so changing the pitch
## moves the posts with it instead of leaving them in the air.
FRONT_EAVE_Y = -(RUN + FRONT_EAVE * RUN / SLOPE)
FRONT_EAVE_Z = RIDGE_Z - (SLOPE + FRONT_EAVE) * RISE / SLOPE


def build():
    kit.block("Foundation", kit.SKIRT, X0 - 0.07, X1 + 0.07, Y0 - 0.07, Y1 + 0.07,
              0.0, BASE_Z)
    kit.block("Wall_Back", kit.SIDING, X0, X1, Y1 - T, Y1, BASE_Z - kit.BITE, EAVE_Z)
    kit.block("Wall_Front", kit.SIDING, X0, X1, Y0, Y0 + T, BASE_Z - kit.BITE, EAVE_Z)
    kit.block("Wall_Left", kit.SIDING, X0, X0 + T, Y0, Y1, BASE_Z - kit.BITE, EAVE_Z)
    kit.block("Wall_Right", kit.SIDING, X1 - T, X1, Y0, Y1, BASE_Z - kit.BITE, EAVE_Z)
    kit.prism_y("Gable_Left", kit.SIDING, Y0, Y1, 0.0, EAVE_Z, RIDGE_Z, X0, X0 + T)
    kit.prism_y("Gable_Right", kit.SIDING, Y0, Y1, 0.0, EAVE_Z, RIDGE_Z, X1 - T, X1)

    for sign, side, eave in ((-1, "Front", FRONT_EAVE), (1, "Back", BACK_EAVE)):
        kit.slope_y("Roof_" + side, kit.ROOF, sign, 0.0, RIDGE_Z, RUN, RISE,
                    X0 - VERGE, X1 + VERGE, ROOF_T, -0.06, SLOPE + eave, -ROOF_T / 2.0)
    kit.block("Ridge_Cap", kit.ROOF, X0 - VERGE, X1 + VERGE, -0.11, 0.11,
              RIDGE_Z - 0.10, RIDGE_Z + 0.06)

    # Snow lies in patches with gaps between them and none of it touching the
    # ridge: the roof is the darkest thing on the building and the snow is what
    # interrupts it, not what replaces it. Same rule as the farmhouse.
    for tag, sign, x0, x1, d0, d1 in (
        ("F1", -1, -1.32, -0.58, 0.32, 0.98),
        ("F2", -1, 0.05, 1.05, 0.55, 1.28),
        ("B1", 1, -1.10, 0.08, 0.26, 0.92),
    ):
        kit.slope_y("Snow_" + tag, kit.SNOW, sign, 0.0, RIDGE_Z, RUN, RISE,
                    x0, x1, SNOW_T, d0, d1, SNOW_T / 2.0 - kit.BITE)

    # The two posts under the front eave, and the bay they make.
    for i, x in ((1, -1.28), (2, 1.28)):
        kit.block("Post_%d" % i, kit.SIDING, x - 0.07, x + 0.07,
                  FRONT_EAVE_Y - 0.07, FRONT_EAVE_Y + 0.07, 0.10, FRONT_EAVE_Z)

    # A row of icicles along the front eave. Tapered spikes, nothing more.
    for i in range(6):
        x = -1.34 + i * 0.54
        length = (0.42, 0.25, 0.36, 0.21, 0.46, 0.28)[i]
        kit.spike("Icicle_%d" % (i + 1), kit.ICE, x, FRONT_EAVE_Y + 0.02,
                  FRONT_EAVE_Z - ROOF_T - 0.02, length, 0.085)

    # The door: 0.95 x 2.00 against a 1.8 m character, under the covered bay.
    kit.panel("Door_Surround", kit.SURROUND, "-y", Y0 - 0.02, -0.50, 0.50, BASE_Z, 2.02)
    kit.panel("Door_Panel", kit.SKIRT, "-y", Y0 - 0.04, -0.42, 0.42, BASE_Z, 1.94)
    # One small window on the right wall, no frame geometry (rule 4).
    kit.panel("Win_Surround", kit.SURROUND, "+x", X1 + 0.02, -0.44, 0.06, 1.30, 1.92)
    kit.panel("Win_Pane", kit.GLASS_DARK, "+x", X1 + 0.04, -0.37, -0.01, 1.37, 1.85)

    kit.block("Step", kit.SKIRT, -0.55, 0.55, Y0 - 0.46, Y0, 0.0, 0.14)
    # Drifted against the back wall, where the wind put it.
    kit.block("Drift", kit.SNOW, X0 - 0.22, 0.72, Y1 - 0.08, Y1 + 0.58, 0.0, 0.40)


def main():
    root = kit.project_root()
    glb = kit.argument("--glb", os.path.join(
        root, "assets", "models", "buildings", "tool_shed", "tool_shed.glb"))
    blend = kit.argument("--blend", os.path.join(
        root, "assets", "source", "buildings", "tool_shed.blend"))
    renders = kit.argument("--renders", os.path.join(root, ".superpowers", "sdd", "wave1"))

    kit.reset()
    build()
    obj = kit.finish("Tool_Shed", BUDGET, label="tool_shed")
    low, high = kit.bbox(obj)
    print("tool_shed: %.2f x %.2f m on plan, ridge %.2f m, clearance under the "
          "front eave %.2f m" % (high[0] - low[0], high[1] - low[1], high[2],
                                 FRONT_EAVE_Z - ROOF_T))
    kit.export_glb(glb)
    kit.save_blend(blend)

    if not kit.has_flag("--no-render"):
        fx, fy = high[0] + 1.2, low[1] - 0.4
        kit.three_quarter(
            os.path.join(renders, "prop-tool-shed.png"),
            [low, high, (low[0], low[1], 0.0), (high[0], high[1], 0.0)]
            + kit.figure_corners(fx, fy),
            figure=(fx, fy, math.radians(150.0)), resolution=(1500, 1100))


main()
