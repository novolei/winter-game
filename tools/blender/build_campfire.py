"""Build the stone-ring campfire -- the UNLIT one.

A ring of irregular stones around a small pile of kindling, modelled off the
owner's reference screenshots: a dozen chunky blocks with no two alike, a
dark scorch on the ground they enclose, and five leaning sticks in the
middle. There is deliberately NO fire in this model -- the game needs both an
unlit and a lit state, and the lit state is code's job (a `FireGlow` light
and whatever flame the systems add), not the mesh's. What the mesh owes both
states is a fire that is READY: stones, scorch, wood.

The farm already has `synty_firepit.glb`, a Synty composite. This one exists
because the reference's ring is chunkier and reads at the fixed camera as
individual placed stones, and because an authored prop goes through propkit's
palette slots like everything else on the farm.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_campfire.py

Optional arguments after `--`: `--glb`, `--blend`, `--renders`, `--no-render`.

1.5 m across counting the scorch, stones 0.2-0.3 m tall -- ankle height
against the 1.8 m figure, a ring you step up to, not over. Origin on the
ground at the centre of the ring. No front: a ring has no facing.
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

STONE_A = "PAL_STRUCT_2"
STONE_B = "PAL_STRUCT_1"
STONE_C = "PAL_STRUCT_3"
CHAR = "PAL_STRUCT_4"
WOOD = "PAL_STRUCT_4"

## The ring. Hand-tuned, one row per stone: angle around the ring, how far its
## centre sits off the ring line, its three sizes, and a yaw and a lean. No
## two alike is the whole read of the reference; a loop with a formula would
## give eleven identical stones on a perfect circle, which is a flower pot.
## Deterministic: no RNG, a re-run is byte-identical.
STONES = (
    # deg   off    w     d     h     yaw    lean
    (0,     0.00,  0.34, 0.24, 0.26, 0.10,  0.04),
    (33,   -0.03,  0.28, 0.22, 0.31, -0.21, -0.06),
    (66,    0.02,  0.36, 0.26, 0.22, 0.35,  0.03),
    (97,   -0.02,  0.26, 0.20, 0.28, -0.08,  0.07),
    (130,   0.03,  0.33, 0.25, 0.25, 0.18, -0.04),
    (163,  -0.01,  0.29, 0.22, 0.30, -0.30,  0.05),
    (196,   0.01,  0.35, 0.24, 0.23, 0.06, -0.07),
    (229,  -0.03,  0.27, 0.21, 0.29, 0.28,  0.02),
    (262,   0.02,  0.32, 0.26, 0.24, -0.14, -0.05),
    (295,  -0.02,  0.30, 0.22, 0.27, 0.22,  0.06),
    (328,   0.01,  0.34, 0.24, 0.25, -0.04, -0.03),
)
RING_R = 0.60

## The kindling: five leaning sticks, a loose teepee that collapsed a little.
## (start, end, radius) -- three-sided tubes, no caps, like every limb in the
## wood.
STICKS = (
    ((-0.26, -0.10, 0.02), (0.06, 0.05, 0.34), 0.045),
    ((0.24, -0.16, 0.02), (-0.04, 0.02, 0.30), 0.050),
    ((-0.06, 0.26, 0.02), (0.03, -0.06, 0.32), 0.042),
    ((0.16, 0.20, 0.02), (-0.10, -0.08, 0.22), 0.038),
    ((-0.20, 0.14, 0.02), (0.14, -0.14, 0.16), 0.040),
)


def build():
    # The scorch first: the dark ground the ring encloses. Rule 11's lines
    # record what already happened, and this patch says a fire has been here.
    kit.disc("Scorch", CHAR, (0.0, 0.0, 0.02), (0.0, 0.0, 1.0), 0.48,
             sides=10)

    # The stones. Each tips a few degrees around its own radial axis and yaws
    # off the tangent, so the ring reads placed, not stamped. Alternate three
    # structure tones the way fieldstone alternates.
    tones = (STONE_A, STONE_B, STONE_C)
    for index, (deg, off, w, d, h, yaw, lean) in enumerate(STONES):
        a = math.radians(deg)
        r = RING_R + off
        cx, cy = r * math.cos(a), r * math.sin(a)
        # Yaw so the long side runs along the ring, then the hand jitter.
        facing = a + math.pi / 2.0 + yaw
        kit.box("Stone_%02d" % index, tones[index % 3],
                (cx, cy, h * 0.5 - 0.04), (w, d, h), (lean, 0.0, facing))

    # The wood. Laid, not stacked: this fire was made and never lit.
    for index, (p0, p1, radius) in enumerate(STICKS):
        kit.tube("Stick_%d" % index, WOOD, p0, p1, radius, radius * 0.85,
                 sides=3)


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
        root, "assets", "models", "props", "campfire.glb"))
    blend = kit.argument("--blend", os.path.join(
        root, "assets", "source", "props", "campfire.blend"))
    renders = kit.argument("--renders", os.path.join(
        root, ".superpowers", "sdd", "wave1"))

    _clear_scene()
    build()
    obj = kit.finish("Campfire", BUDGET, label="campfire")
    low, high = kit.bbox(obj)
    print("campfire: %.2f m across, %.2f m tall"
          % (high[0] - low[0], high[2]))
    kit.export_glb(glb)
    kit.save_blend(blend)

    if not kit.has_flag("--no-render"):
        fx, fy = high[0] + 0.9, low[1] - 0.4
        kit.three_quarter(
            os.path.join(renders, "prop-campfire.png"),
            [low, high, (low[0], low[1], 0.0), (high[0], high[1], 0.0)]
            + kit.figure_corners(fx, fy),
            figure=(fx, fy, math.radians(160.0)), resolution=(1500, 1100))


main()
