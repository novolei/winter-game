"""Build the well house -- the smallest thing on the farm.

In `Refs/game ref/level.jpg` it stands alone in the middle of the snow with its
own long shadow and nothing near it, which is the whole reason it is in the
frame: rule 10 says the shadows are the composition, and this is the object
that exists to cast one. So it is deliberately plain -- a gabled box, a door,
two patches of snow and a marker stake -- because anything more would make the
eye stop on the building instead of the shadow.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_well_house.py

Optional arguments after `--`: `--glb`, `--blend`, `--renders`, `--no-render`.

2.10 x 1.90 m on plan, eave at 1.80 m, ridge at 2.48 m. Against the 1.8 m
figure the eave is exactly head height, which is what makes it read as *small*
rather than as a shed seen from further away -- in an orthographic game there is
no perspective to tell the two apart, so the only cue is a person beside it.

Filed under `assets/models/buildings/` beside the tool shed, because that is
what it is. Front faces -Y in Blender (+Z in Godot), origin on the ground at
the centre of the plan.
"""

import math
import os
import sys

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402

## The task brief's number, which is tighter than the folder's.
##
## This is a small outbuilding, not a prop, so it is filed under
## `assets/models/buildings/` where rule 6 allows 500 -- filed by *kind*, not by
## whichever budget it happens to squeeze under. It would in fact fit the 200
## prop budget, and filing it there for that reason would have been picking a
## folder to satisfy an arithmetic result. The 300 here and in
## `tests/art/test_prop_models.gd` is the brief's cap, and it binds first.
BUDGET = 300

X0, X1 = -1.05, 1.05
Y0, Y1 = -0.95, 0.95
T = 0.12
BASE_Z = 0.16
EAVE_Z = 1.80
RIDGE_Z = 2.48
RUN, RISE = 0.95, 0.68     # a 35.6 degree pitch -- steeper than the shed's,
SLOPE = math.hypot(RUN, RISE)   # because a small roof needs a steep one to read
VERGE = 0.18
EAVE = 0.34
ROOF_T = 0.10
SNOW_T = 0.13


def build():
    kit.block("Foundation", kit.SKIRT, X0 - 0.06, X1 + 0.06, Y0 - 0.06, Y1 + 0.06,
              0.0, BASE_Z)
    kit.block("Wall_Back", kit.SIDING, X0, X1, Y1 - T, Y1, BASE_Z - kit.BITE, EAVE_Z)
    kit.block("Wall_Front", kit.SIDING, X0, X1, Y0, Y0 + T, BASE_Z - kit.BITE, EAVE_Z)
    kit.block("Wall_Left", kit.SIDING, X0, X0 + T, Y0, Y1, BASE_Z - kit.BITE, EAVE_Z)
    kit.block("Wall_Right", kit.SIDING, X1 - T, X1, Y0, Y1, BASE_Z - kit.BITE, EAVE_Z)
    kit.prism_y("Gable_Left", kit.SIDING, Y0, Y1, 0.0, EAVE_Z, RIDGE_Z, X0, X0 + T)
    kit.prism_y("Gable_Right", kit.SIDING, Y0, Y1, 0.0, EAVE_Z, RIDGE_Z, X1 - T, X1)

    for sign, side in ((-1, "Front"), (1, "Back")):
        kit.slope_y("Roof_" + side, kit.ROOF, sign, 0.0, RIDGE_Z, RUN, RISE,
                    X0 - VERGE, X1 + VERGE, ROOF_T, -0.05, SLOPE + EAVE,
                    -ROOF_T / 2.0)
    kit.block("Ridge_Cap", kit.ROOF, X0 - VERGE, X1 + VERGE, -0.09, 0.09,
              RIDGE_Z - 0.09, RIDGE_Z + 0.05)

    for tag, sign, x0, x1, d0, d1 in (
        ("F1", -1, -0.78, -0.02, 0.24, 0.78),
        ("B1", 1, -0.18, 0.72, 0.28, 0.86),
    ):
        kit.slope_y("Snow_" + tag, kit.SNOW, sign, 0.0, RIDGE_Z, RUN, RISE,
                    x0, x1, SNOW_T, d0, d1, SNOW_T / 2.0 - kit.BITE)

    # Two icicles, because two is enough to say "it has been cold for weeks"
    # and seven would make this compete with the shed.
    eave_y = -(RUN + EAVE * RUN / SLOPE)
    eave_z = RIDGE_Z - (SLOPE + EAVE) * RISE / SLOPE
    for i, (x, length) in enumerate(((-0.55, 0.34), (0.42, 0.23))):
        kit.spike("Icicle_%d" % (i + 1), kit.ICE, x, eave_y + 0.02,
                  eave_z - ROOF_T - 0.02, length, 0.080)

    # A hatch rather than a door: 0.80 x 1.35, which is a thing you reach into.
    kit.panel("Door_Surround", kit.SURROUND, "-y", Y0 - 0.02, -0.44, 0.44, BASE_Z, 1.42)
    kit.panel("Door_Panel", kit.SKIRT, "-y", Y0 - 0.04, -0.36, 0.36, BASE_Z, 1.34)

    # The stake beside it. It is in the reference, and it is the thing that says
    # somebody has to find this in a whiteout.
    kit.block("Stake", kit.ROOF, 1.52, 1.60, -0.28, -0.20, 0.0, 1.55)
    kit.block("Stake_Flag", "PAL_WARM_2", 1.50, 1.62, -0.36, -0.12, 1.34, 1.52)
    kit.block("Drift", kit.SNOW, X0 - 0.22, 0.55, Y1 - 0.08, Y1 + 0.58, 0.0, 0.38)


def main():
    root = kit.project_root()
    glb = kit.argument("--glb", os.path.join(
        root, "assets", "models", "buildings", "well_house", "well_house.glb"))
    blend = kit.argument("--blend", os.path.join(
        root, "assets", "source", "buildings", "well_house.blend"))
    renders = kit.argument("--renders", os.path.join(root, ".superpowers", "sdd", "wave1"))

    kit.reset()
    build()
    obj = kit.finish("Well_House", BUDGET, label="well_house")
    low, high = kit.bbox(obj)
    print("well_house: %.2f x %.2f m on plan, ridge %.2f m"
          % (high[0] - low[0], high[1] - low[1], high[2]))
    kit.export_glb(glb)
    kit.save_blend(blend)

    if not kit.has_flag("--no-render"):
        fx, fy = high[0] + 1.1, low[1] - 0.3
        kit.three_quarter(
            os.path.join(renders, "prop-well-house.png"),
            [low, high, (low[0], low[1], 0.0), (high[0], high[1], 0.0)]
            + kit.figure_corners(fx, fy),
            figure=(fx, fy, math.radians(160.0)), resolution=(1500, 1100))


main()
