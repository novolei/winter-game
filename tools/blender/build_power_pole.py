"""Build the power pole, and -- separately -- one metre of wire.

Two assets, because they are two different jobs. Art Bible rule 11 says the
line across the frame *is* the detail:

    "The whole picture's sense of detail comes entirely from lines: wheel ruts,
     chains of footprints, ploughed furrows, the power lines crossing the frame."

A wire baked into the pole would be a wire of one fixed length, aimed one fixed
way, and rule 11's line would end up as a stub. So `power_wire.glb` is its own
model: one straight element, 1 m long, that the scene stretches between two
poles. See WIRING below for how to place it.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_power_pole.py

Optional arguments after `--`: `--glb`, `--wire`, `--blend`, `--renders`,
`--no-render`.

---------------------------------------------------------------------------
THE POLE
---------------------------------------------------------------------------
8.20 m of pole above ground, 0.28 m across at the butt and tapering. The shaft
is a four-sided tapered tube -- 8 triangles, no caps, because the butt is buried
and the head sits on top of it -- which is a quarter of what a box chain would
cost and is the only reason there is budget left for three insulators.

Everything above the transformer is silhouette: the crossarm, its two braces,
three insulators on the arm and one on the head. At the game's distance those
are a handful of pixels each, and they are what tells a pole from a dead tree.

Tie points, for whoever strings the wires -- local metres, Blender Z-up, which
becomes (x, z, -y) in Godot:

    crossarm ends   (-1.00, 0, 8.06) and (1.00, 0, 8.06)
    head            (0, 0, 8.44)
    service drop    (0.34, 0, 5.30), off the transformer bracket

---------------------------------------------------------------------------
WIRING
---------------------------------------------------------------------------
`power_wire.glb` is 1 m long, runs along Blender +Y, and Blender +Y becomes
**Godot -Z**. That is deliberate: -Z is the axis `Node3D.look_at()` aims, so
stringing a wire in Godot is two lines and no trigonometry.

    var wire := preload(".../power_wire.glb").instantiate()
    wire.position = pole_a_tie
    wire.look_at(pole_b_tie)
    wire.scale.z = pole_a_tie.distance_to(pole_b_tie)

**The wire is straight, not catenary.** In `level.jpg` it is painted straight,
and a sag modelled here would not scale with the span -- scaling X or Z stretches
the length while leaving the sag at its modelled 1 m value, so a long span would
sag less than a short one, which is backwards. A scene that wants sag chains two
wires through a low midpoint, which costs one more instance and is correct at
any span.
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

SHAFT = "PAL_STRUCT_2"     # dark, but not the near-black of the hardware
HEAD = "PAL_SNOW_5"        # the weathered cap the reference shows
ARM = "PAL_STRUCT_3"
## Insulators and the wire itself: rule 7's near-black, and `_BARE`.
##
## THE WIRE IS THE REASON THE MARK EXISTS. `cel_flat.gdshader`'s settled snow is
## a 1.33 m pattern and this wire is 0.07 m square -- one to two pixels at the
## game camera. A hairline cannot carry a pattern; it can only break into
## dashes, and a wire breaking into dashes reads as a MESH COMING APART. Measured
## on the shipped scene: the line is solid at cover 0.362 and dotted at 0.620,
## with the same camera and the same framing, and it starts going at cover 0.14.
##
## Snow does lie on a power line in life. It cannot be drawn at one pixel, and
## the honest reading at this framing is that the line does not take it.
HARDWARE = kit.bare("PAL_STRUCT_4")
CAN = "PAL_SNOW_5"

BURIED = -0.45             # the butt starts below ground: the tube has no cap
TOP_Z = 8.15               # where the shaft ends, inside the head block
ARM_Z = 7.94               # top of the crossarm
ARM_HALF = 1.00


def build_pole():
    kit.tube("Shaft", SHAFT, (0.0, 0.0, BURIED), (0.0, 0.0, TOP_Z), 0.14, 0.105,
             sides=4, roll=math.pi / 4.0)
    kit.block("Head", HEAD, -0.13, 0.13, -0.13, 0.13, TOP_Z - 0.22, 8.34)
    kit.block("Head_Insulator", HARDWARE, -0.06, 0.06, -0.06, 0.06, 8.34 - kit.BITE, 8.50)

    kit.block("Crossarm", ARM, -ARM_HALF - 0.06, ARM_HALF + 0.06, -0.06, 0.06,
              ARM_Z - 0.13, ARM_Z)
    # Two braces from the pole out to the arm ends. A box rotated about +Y
    # takes its own +X to (cos, 0, -sin), so the rotation is the negative of
    # the angle the brace actually climbs at.
    for sign in (-1.0, 1.0):
        dx, dz = sign * 0.62, 0.52
        angle = math.atan2(dz, abs(dx)) * (1.0 if sign > 0 else -1.0)
        kit.box("Brace_%s" % ("R" if sign > 0 else "L"), ARM,
                (sign * 0.42, 0.0, ARM_Z - 0.13 - dz / 2.0),
                (math.hypot(dx, dz), 0.07, 0.07), (0.0, -angle, 0.0))
    for i, x in enumerate((-0.86, 0.0, 0.86)):
        kit.block("Insulator_%d" % (i + 1), HARDWARE, x - 0.055, x + 0.055,
                  -0.055, 0.055, ARM_Z - kit.BITE, ARM_Z + 0.16)
    kit.panel("Arm_Snow", kit.SNOW, "+z", ARM_Z + 0.005,
              -ARM_HALF - 0.05, ARM_HALF + 0.05, -0.05, 0.05)

    # The transformer can, hung off a bracket on the near face.
    kit.block("Can_Bracket", ARM, -0.10, 0.34, -0.16, 0.16, 5.24, 5.44)
    kit.cylinder("Can", CAN, (0.34, 0.0, 4.98), (0.34, 0.0, 5.96), 0.30, sides=8)

    kit.block("Drift", kit.SNOW, -0.36, 0.36, -0.36, 0.36, 0.0, 0.13)


def build_wire():
    """One metre of wire along +Y, from the origin. See WIRING in the docstring.

    0.07 m square, which is far thicker than a real conductor and is the point:
    at the game's framing a 10 mm wire is a fifth of a pixel and simply is not
    there, and rule 11 says this line is carrying the whole frame.
    """
    kit.block("Wire", HARDWARE, -0.035, 0.035, 0.0, 1.0, -0.035, 0.035)


def main():
    root = kit.project_root()
    props = os.path.join(root, "assets", "models", "props")
    source = os.path.join(root, "assets", "source", "props")
    glb = kit.argument("--glb", os.path.join(props, "power_pole.glb"))
    wire_glb = kit.argument("--wire", os.path.join(props, "power_wire.glb"))
    blend = kit.argument("--blend", os.path.join(source, "power_pole.blend"))
    renders = kit.argument("--renders", os.path.join(root, ".superpowers", "sdd", "wave1"))

    kit.reset()
    build_pole()
    obj = kit.finish("Power_Pole", BUDGET, label="power_pole")
    low, high = kit.bbox(obj)
    print("power_pole: %.2f m above ground, crossarm %.2f m across"
          % (high[2], 2.0 * ARM_HALF + 0.12))
    kit.export_glb(glb)
    kit.save_blend(blend)

    if not kit.has_flag("--no-render"):
        fx, fy = high[0] + 1.4, low[1] - 0.6
        kit.three_quarter(
            os.path.join(renders, "prop-power-pole.png"),
            [low, high, (low[0], low[1], 0.0), (high[0], high[1], 0.0)]
            + kit.figure_corners(fx, fy),
            figure=(fx, fy, math.radians(20.0)), resolution=(1000, 1400))

    # The wire is its own file and its own scene, so nothing of the pole's can
    # follow it out.
    kit.reset()
    build_wire()
    kit.finish("Power_Wire", BUDGET, label="power_wire")
    kit.export_glb(wire_glb)
    kit.save_blend(os.path.join(source, "power_wire.blend"))


main()
