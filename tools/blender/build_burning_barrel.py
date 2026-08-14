"""Build the burning oil barrel -- a workyard fire in a steel drum.

A 45-gallon drum, open at the top, with embers inside and three faceted
flame tongues standing out of it. The barrel itself is the palette's dark
steel blue -- rule 12 does not spend a warm body colour on a container, the
warm here is the fire and only the fire. Every flame and the ember bed carry
`_BARE` slots, because a flame cannot take the cel shader's settled snow.

The firelight it casts is not the model's job: scenes add an OmniLight3D
driven by `src/entities/fire_glow.gd`, which reads the amber out of
`data/palette/color_bible.tres` like every other warm source in the project.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_burning_barrel.py

Optional arguments after `--`: `--glb`, `--blend`, `--renders`, `--no-render`.

0.68 m across, 0.86 m to the rim, flames to about 1.35 m -- against the 1.8 m
figure the fire burns at chest height, which is where a workyard barrel fire
burns. Origin on the ground at the centre of the drum.
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
## tests/art/test_prop_models.gd pins this file to.
BUDGET = 200

STEEL = "PAL_STRUCT_3"
CHAR = "PAL_STRUCT_4"
EMBERS = "PAL_WARM_1"
FLAME_MID = "PAL_WARM_2"
FLAME = "PAL_WARM_3"

R = 0.30
R_IN = 0.27
RIM_Z = 0.86
SIDES = 10


def build():
    # The drum: an open tube, an inner wall down to the ember bed, and a rim
    # ring. No bottom face -- the game camera is 45 degrees up and never sees
    # under anything, and the char disc below closes the view into the drum.
    kit.tube("Drum", STEEL, (0.0, 0.0, 0.0), (0.0, 0.0, RIM_Z), R, R,
             sides=SIDES)
    angles = [2.0 * math.pi * i / SIDES for i in range(SIDES)]
    low = [(R_IN * math.cos(t), R_IN * math.sin(t), 0.60) for t in angles]
    high = [(R_IN * math.cos(t), R_IN * math.sin(t), RIM_Z) for t in angles]
    kit.emit("Drum_Inner", CHAR, low + high,
             [(i, SIDES + i, SIDES + (i + 1) % SIDES, (i + 1) % SIDES)
              for i in range(SIDES)])
    outer = [(0.33 * math.cos(t), 0.33 * math.sin(t), RIM_Z) for t in angles]
    inner = [(R_IN * math.cos(t), R_IN * math.sin(t), RIM_Z) for t in angles]
    kit.emit("Rim", CHAR, inner + outer,
             [(i, SIDES + i, SIDES + (i + 1) % SIDES, (i + 1) % SIDES)
              for i in range(SIDES)])

    # What is burning: a bed of deep-red embers and three tongues of flame.
    # Four-sided pyramids, leaning apart, because one centred spike reads as a
    # birthday candle and three leaning ones read as a fire.
    kit.disc("Embers", kit.bare(EMBERS), (0.0, 0.0, 0.62), (0.0, 0.0, 1.0),
             R_IN, sides=SIDES)
    kit.tube("Flame_Main", kit.bare(FLAME), (0.0, 0.0, 0.64),
             (0.03, 0.02, 1.34), 0.20, 0.0, sides=4)
    kit.tube("Flame_Left", kit.bare(FLAME_MID), (-0.08, 0.04, 0.64),
             (-0.13, 0.08, 1.10), 0.12, 0.0, sides=4)
    kit.tube("Flame_Right", kit.bare(FLAME), (0.10, -0.05, 0.64),
             (0.16, -0.09, 1.02), 0.09, 0.0, sides=4)

    # The scorched ring the drum stands in. Grounds the fire the way rule
    # 11's lines ground everything else on the snow.
    kit.disc("Scorch", CHAR, (0.0, 0.0, 0.01), (0.0, 0.0, 1.0), 0.55,
             sides=SIDES)


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
        root, "assets", "models", "props", "burning_barrel.glb"))
    blend = kit.argument("--blend", os.path.join(
        root, "assets", "source", "props", "burning_barrel.blend"))
    renders = kit.argument("--renders", os.path.join(
        root, ".superpowers", "sdd", "wave1"))

    _clear_scene()
    build()
    obj = kit.finish("Burning_Barrel", BUDGET, label="burning_barrel")
    low, high = kit.bbox(obj)
    print("burning_barrel: %.2f m across, flame tip %.2f m"
          % (high[0] - low[0], high[2]))
    kit.export_glb(glb)
    kit.save_blend(blend)

    if not kit.has_flag("--no-render"):
        fx, fy = high[0] + 0.8, low[1] - 0.4
        kit.three_quarter(
            os.path.join(renders, "prop-burning-barrel.png"),
            [low, high, (low[0], low[1], 0.0), (high[0], high[1], 0.0)]
            + kit.figure_corners(fx, fy),
            figure=(fx, fy, math.radians(160.0)), resolution=(1500, 1100))


main()
