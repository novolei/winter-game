"""Build the open water well -- a yard prop for the farmstead.

The farm already has a well HOUSE (the gabled box out on the snow, built by
`build_well_house.py`). This is the open well itself: a stone ring you can
look into, two posts, a little gabled roof, a crank and a bucket on a rope.
It reads as the working well of the yard; the house out on the field stays
what it always was.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_water_well.py

Optional arguments after `--`: `--glb`, `--blend`, `--renders`, `--no-render`.

1.72 x 1.90 m on plan counting the roof, 2.30 m to the ridge, the stone ring
0.78 m across -- against the 1.8 m figure the rim is just below the hip, which
is what makes it a well and not a fountain. Filed under `assets/models/props/`
on the prop budget: 200 triangles, and the count below lands under it.

Front faces -Y in Blender (+Z in Godot); the crank is on the +X side.
Origin on the ground at the centre of the ring.
"""

import math
import os
import sys

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402

## The prop folder's own number (tests/art/test_topology.gd), and what
## tests/art/test_prop_models.gd pins this file to. Nothing here was left off
## to fit it; the count lands under with room.
BUDGET = 200

STONE = "PAL_STRUCT_2"
SHAFT = "PAL_STRUCT_4"
TIMBER = "PAL_STRUCT_4"
BUCKET = "PAL_STRUCT_3"
ROOF = "PAL_STRUCT_4"
SNOW = "PAL_SNOW_1"

R_OUT = 0.78
R_IN = 0.60
RIM_Z = 0.88
SIDES = 8

# The little roof over the ring: ridge along X.
RIDGE_Z = 2.30
RUN, RISE = 0.75, 0.34
SLOPE = math.hypot(RUN, RISE)
EAVE = 0.14
ROOF_T = 0.07
SNOW_T = 0.05


def _ring_wall(name, slot, radius, z0, z1, inward=False):
    """One band of a round wall. `inward` faces it INTO the shaft."""
    angles = [2.0 * math.pi * i / SIDES for i in range(SIDES)]
    low = [(radius * math.cos(t), radius * math.sin(t), z0) for t in angles]
    high = [(radius * math.cos(t), radius * math.sin(t), z1) for t in angles]
    faces = []
    for i in range(SIDES):
        j = (i + 1) % SIDES
        if inward:
            faces.append((i, SIDES + i, SIDES + j, j))
        else:
            faces.append((i, j, SIDES + j, SIDES + i))
    return kit.emit(name, slot, low + high, faces)


def _annulus(name, slot, r_in, r_out, z):
    """A flat ring facing up: the rim the snow lies on."""
    angles = [2.0 * math.pi * i / SIDES for i in range(SIDES)]
    inner = [(r_in * math.cos(t), r_in * math.sin(t), z) for t in angles]
    outer = [(r_out * math.cos(t), r_out * math.sin(t), z) for t in angles]
    faces = []
    for i in range(SIDES):
        j = (i + 1) % SIDES
        faces.append((i, SIDES + i, SIDES + j, j))
    return kit.emit(name, slot, inner + outer, faces)


def build():
    # The stone ring: outer wall, inner wall, the rim between them, and the
    # water at the bottom of the visible shaft. The inner wall stops at the
    # water; below that nothing can be seen at the game camera.
    _ring_wall("Ring_Outer", STONE, R_OUT, 0.0, RIM_Z)
    _ring_wall("Ring_Inner", SHAFT, R_IN, 0.45, RIM_Z, inward=True)
    _annulus("Rim", STONE, R_IN, R_OUT + 0.04, RIM_Z)
    kit.disc("Water", SHAFT, (0.0, 0.0, 0.55), (0.0, 0.0, 1.0), R_IN,
             sides=SIDES)
    # The snow on the rim overhangs a hand's width past the stone, the way a
    # settled lip does.
    _annulus("Rim_Snow", SNOW, R_IN - 0.04, R_OUT + 0.08, RIM_Z + 0.02)

    # Posts, axle and crank. The crank is one arm; a handle block spent twelve
    # triangles nobody could read at the game camera.
    for side, x in (("L", -0.92), ("R", 0.92)):
        kit.block("Post_" + side, TIMBER, x - 0.06, x + 0.06,
                  -0.08, 0.08, 0.0, 2.02)
    kit.tube("Axle", TIMBER, (-0.95, 0.0, 1.70), (0.95, 0.0, 1.70),
             0.05, 0.05, sides=4)
    kit.tube("Crank", TIMBER, (0.95, 0.0, 1.70), (1.12, 0.0, 1.52),
             0.03, 0.03, sides=3)

    # Rope and bucket, hanging over the mouth.
    kit.tube("Rope", TIMBER, (0.0, 0.0, 1.70), (0.0, 0.0, 1.04),
             0.018, 0.018, sides=3)
    kit.tube("Bucket", BUCKET, (0.0, 0.0, 0.78), (0.0, 0.0, 1.04),
             0.13, 0.15, sides=5)
    kit.disc("Bucket_Floor", SHAFT, (0.0, 0.0, 0.80), (0.0, 0.0, 1.0),
             0.13, sides=5)

    # The roof: two slabs, their snow, and two gable ends. `_BARE` on the
    # planes for propkit's documented reason -- a plane must not whiten behind
    # its own snow.
    for sign, side in ((-1, "Front"), (1, "Back")):
        kit.slope_y("Roof_" + side, kit.bare(ROOF), sign, 0.0, RIDGE_Z,
                    RUN, RISE, -1.14, 1.14, ROOF_T, 0.0, SLOPE + EAVE,
                    -ROOF_T / 2.0)
        kit.slope_y("Roof_Snow_" + side, SNOW, sign, 0.0, RIDGE_Z + 0.02,
                    RUN, RISE, -1.17, 1.17, SNOW_T, 0.03, SLOPE + EAVE - 0.03,
                    ROOF_T / 2.0 + SNOW_T / 2.0)
    kit.prism_y("Gable_Left", STONE, -RUN, RUN, 0.0, RIDGE_Z - RISE, RIDGE_Z,
                -1.10, -1.02)
    kit.prism_y("Gable_Right", STONE, -RUN, RUN, 0.0, RIDGE_Z - RISE, RIDGE_Z,
                1.02, 1.10)


def _clear_scene():
    """Empty the scene without `read_factory_settings` -- safe for a live
    Blender MCP session, identical to the batch file's `build_one`."""
    import bpy
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)
    kit._MATERIALS.clear()
    del kit._PARTS[:]


def main():
    root = kit.project_root()
    glb = kit.argument("--glb", os.path.join(
        root, "assets", "models", "props", "water_well.glb"))
    blend = kit.argument("--blend", os.path.join(
        root, "assets", "source", "props", "water_well.blend"))
    renders = kit.argument("--renders", os.path.join(
        root, ".superpowers", "sdd", "wave1"))

    _clear_scene()
    build()
    obj = kit.finish("Water_Well", BUDGET, label="water_well")
    low, high = kit.bbox(obj)
    print("water_well: %.2f x %.2f m on plan, ridge %.2f m"
          % (high[0] - low[0], high[1] - low[1], high[2]))
    kit.export_glb(glb)
    kit.save_blend(blend)

    if not kit.has_flag("--no-render"):
        fx, fy = high[0] + 1.0, low[1] - 0.4
        kit.three_quarter(
            os.path.join(renders, "prop-water-well.png"),
            [low, high, (low[0], low[1], 0.0), (high[0], high[1], 0.0)]
            + kit.figure_corners(fx, fy),
            figure=(fx, fy, math.radians(160.0)), resolution=(1500, 1100))


main()
