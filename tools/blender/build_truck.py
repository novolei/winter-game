"""Build the pickup -- the dead red truck in the yard.

    "Don't ask AI for realistic meshes. It will not deliver. Simple shapes, it
     does well."

Nine boxes, four wheels and nine flat panels. No curve, no bevel, no chrome.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_truck.py

Optional arguments after `--`: `--glb`, `--blend`, `--renders`, `--no-render`.

---------------------------------------------------------------------------
WHY IT LOOKS LIKE THIS
---------------------------------------------------------------------------
Rule 12 lists five places warm colour is allowed in the whole game, and the
truck is one of them. In `level.jpg` it is one of only three warm objects in the
frame, so **its silhouette is doing compositional work** -- it is the thing the
eye lands on after the lit window. That decided the shape: a 1950s stepped-body
pickup, whose profile is four distinct rectangles at four heights (bumper,
fender, cab, bed) rather than one smooth wedge. A modern truck is a single mass
and would read as a red smudge.

Proportions are a 1950s half-ton: 5.05 m long, 1.96 m wide, 1.88 m over the cab
roof, wheels 0.80 m across. Against the 1.8 m figure in the render, the cab roof
is just above head height, which is right.

Snow is three flat `PAL_SNOW_1` panels -- roof, hood, bed -- and they are the
cheapest thing in the model at 2 triangles each and the most valuable: bright
snow directly against `#6E2F2E` is the whole reason the truck reads at distance.

**Not modelled, deliberately:** the load of poles standing out of the bed in the
reference. One pole is 12 triangles, and one pole reads as an accident rather
than as a load. That is cargo, not truck, and it belongs in its own prop if the
scene ever wants it.

Front faces -Y in Blender, which is +Z in Godot. Origin is on the ground under
the middle of the truck, so it sits on Y=0 with no offset.
"""

import math
import os
import sys

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402

BUDGET = 200

BODY = "PAL_WARM_1"        # #6E2F2E -- rule 12's deep red
DARK = "PAL_STRUCT_4"      # wheels, glass, the inside of things
GRILLE = "PAL_STRUCT_3"
CHROME = "PAL_STRUCT_1"    # weathered, not chrome: a cold slate blue
LAMP = "PAL_SNOW_2"
SNOW = kit.SNOW

## Half-width of the body, and where the wheels sit.
HALF = 0.98
WHEEL_R = 0.40
WHEEL_X = 0.86             # centre of the tread
WHEEL_HALF = 0.13
AXLE_F, AXLE_R = -1.72, 1.70


def wheel(tag, sx, y):
    """One wheel: a six-sided tube plus its outer face. 16 triangles.

    A `cylinder` would be 20 and its inner cap is buried in the body where
    nothing can see it. Four wheels at 16 rather than 20 is 16 triangles, which
    is exactly the snow on the roof, the hood and the bed.
    """
    inner = (sx * (WHEEL_X - WHEEL_HALF), y, WHEEL_R)
    outer = (sx * (WHEEL_X + WHEEL_HALF), y, WHEEL_R)
    kit.tube("Wheel_" + tag, DARK, inner, outer, WHEEL_R, WHEEL_R, sides=6)
    kit.disc("Wheel_%s_Face" % tag, DARK, outer, (sx, 0.0, 0.0), WHEEL_R, sides=6)


def build():
    # -- the four masses of the profile, front to back --------------------
    kit.block("Bumper", CHROME, -0.92, 0.92, -2.52, -2.42, 0.58, 0.74)
    # Wide, low fenders with a narrower, taller hood standing between them.
    # Two boxes at the same height read as one long snout and the truck loses
    # twenty years; this is what makes it a 1950s truck rather than a car.
    kit.block("Fenders", BODY, -0.96, 0.96, -2.42, -1.36, 0.50, 1.12)
    kit.block("Hood", BODY, -0.70, 0.70, -2.30, -0.48, 0.62, 1.30)
    kit.block("Cab", BODY, -0.94, 0.94, -0.48, 0.78, 0.50, 1.60)
    # The roof is narrower than the cab and set back from its front face. That
    # step is the single most recognisable thing about an old pickup.
    kit.block("Roof", BODY, -0.86, 0.86, -0.34, 0.80, 1.60, 1.86)
    kit.block("Bed", BODY, -0.96, 0.96, 0.78, 2.48, 0.50, 1.04)
    kit.block("Bed_Side_L", BODY, -0.96, -0.80, 0.78, 2.48, 1.04, 1.44)
    kit.block("Bed_Side_R", BODY, 0.80, 0.96, 0.78, 2.48, 1.04, 1.44)
    kit.block("Tailgate", BODY, -0.96, 0.96, 2.32, 2.48, 1.04, 1.44)

    for tag, sx, y in (("FL", -1.0, AXLE_F), ("FR", 1.0, AXLE_F),
                       ("RL", -1.0, AXLE_R), ("RR", 1.0, AXLE_R)):
        wheel(tag, sx, y)

    # -- glass, lamps and grille: flat rectangles, rule 4 ------------------
    kit.panel("Windscreen", DARK, "-y", -0.50, -0.72, 0.72, 1.18, 1.58)
    kit.panel("Window_L", DARK, "-x", -0.95, -0.36, 0.64, 1.18, 1.56)
    kit.panel("Window_R", DARK, "+x", 0.95, -0.36, 0.64, 1.18, 1.56)
    kit.panel("Window_Rear", DARK, "+y", 0.79, -0.58, 0.58, 1.20, 1.54)
    kit.panel("Grille", GRILLE, "-y", -2.43, -0.50, 0.50, 0.62, 1.02)
    kit.panel("Lamp_L", LAMP, "-y", -2.43, -0.86, -0.62, 0.80, 1.04)
    kit.panel("Lamp_R", LAMP, "-y", -2.43, 0.62, 0.86, 0.80, 1.04)

    # -- snow: three panels, and they carry the whole silhouette -----------
    kit.panel("Snow_Roof", SNOW, "+z", 1.87, -0.82, 0.82, -0.30, 0.76)
    kit.panel("Snow_Hood", SNOW, "+z", 1.31, -0.64, 0.64, -2.10, -0.56)
    kit.panel("Snow_Bed", SNOW, "+z", 1.28, -0.78, 0.78, 0.86, 2.30)


def main():
    root = kit.project_root()
    glb = kit.argument("--glb", os.path.join(root, "assets", "models", "props", "pickup_truck.glb"))
    blend = kit.argument("--blend", os.path.join(root, "assets", "source", "props", "pickup_truck.blend"))
    renders = kit.argument("--renders", os.path.join(root, ".superpowers", "sdd", "wave1"))

    kit.reset()
    build()
    obj = kit.finish("Pickup_Truck", BUDGET, label="pickup_truck")
    low, high = kit.bbox(obj)
    print("pickup_truck: %.2f long x %.2f wide x %.2f tall"
          % (high[1] - low[1], high[0] - low[0], high[2]))
    kit.export_glb(glb)
    kit.save_blend(blend)

    if not kit.has_flag("--no-render"):
        fx, fy = high[0] + 1.3, low[1] + 0.6
        kit.three_quarter(
            os.path.join(renders, "prop-pickup-truck.png"),
            [low, high, (low[0], low[1], 0.0), (high[0], high[1], 0.0)]
            + kit.figure_corners(fx, fy),
            figure=(fx, fy, math.radians(200.0)), resolution=(1500, 1000))


main()
