"""Build the church -- the valley's northeast beacon landmark.

This building used to be one function inside `build_world_landmarks.py`, the
batch file the four beacons were delivered through. It moves out to its own
script because that is where every other building lives (`build_farmhouse.py`,
`build_tool_shed.py`, `build_well_house.py`): one building, one script, one
place to change a number and re-run.

It also fixes a real defect the batch version shipped: its two roof slabs were
rotated so they peaked at the EAVES and dipped to a valley at the ridge line --
a butterfly roof hiding under its snow slabs. The gable here is a gable.

The brief's numbers: a medium church, not a chapel and not a cathedral. The
nave keeps the batch version's footprint (4.6 x 8.4 m of wall, eave at 3.60,
ridge at 4.90) because `tests/art/test_world_landmark_models.gd` pins the
silhouette envelope this file must keep: 4-7 m wide, 7-12 m high, 7-12 m deep.
What the rebuild adds is the construction the 45-degree camera can actually
read: a proper gable roof with snow, a bell tower with a ledge and belfry, an
entry porch, buttresses, and the cross over the spire. One amber window, the
belfry's, because this landmark is a beacon and rule 12 spends its warm pixels
on exactly that.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_church.py

Optional arguments after `--`: `--glb`, `--blend`, `--renders`, `--no-render`.

Front faces -Y in Blender (+Z in Godot) -- the porch and the door are on the
tower side. Origin on the ground at the centre of the nave plan.
"""

import math
import os
import sys

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402

## A runaway guard, not an art target -- the same number the landmark batch
## used, and the same number `tests/art/test_topology.gd` pins this file to.
## The Art Bible's rule-6 exception for the four beacon landmarks is explicit:
## readability at the fixed game camera decides the count, this catches an
## accidental subdivision.
BUDGET = 5000

BODY = "PAL_STRUCT_1"
BODY_MID = "PAL_STRUCT_2"
TRIM = "PAL_STRUCT_3"
DARK = "PAL_STRUCT_4"
SNOW = "PAL_SNOW_1"
SNOW_SHADE = "PAL_SNOW_2"
ICE = "PAL_SNOW_2"
BEACON = "PAL_WARM_3"

# The nave. These six numbers are the silhouette the landmark gate pins.
X0, X1 = -2.30, 2.30
Y0, Y1 = -4.20, 4.20
EAVE_Z = 3.60
RIDGE_Z = 4.90

RUN = 2.68                    # half-span plus the eave overhang
RISE = RIDGE_Z - EAVE_Z
SLOPE = math.hypot(RUN, RISE)
ANGLE = math.atan2(RISE, RUN)
ROOF_LEN = 9.10               # ridge runs along Y, past both gable ends
ROOF_T = 0.16
SNOW_T = 0.07

# The tower stands in front of the nave, on the front (-Y) side.
TW_X = 1.25
TW_Y0, TW_Y1 = -5.50, -4.20
TW_TOP = 6.45
SPIRE_TIP = 9.70


def _roof_pair(prefix, slot, thick, lift, length, inset=0.0):
    """One slab per side of the ridge, peaking AT the ridge.

    A plain box is symmetric, so the two sides are the same call with the
    centre mirrored and the roll reversed by pi: for the right side the local
    +x axis must point down-slope, `(cosA, 0, -sinA)`, which is a rotation of
    +ANGLE about Y; for the left it is ANGLE - pi.
    """
    for sign, side in ((1.0, "R"), (-1.0, "L")):
        centre = (sign * RUN * 0.5 + sign * lift * math.sin(ANGLE),
                  0.0,
                  RIDGE_Z - RISE * 0.5 + lift * math.cos(ANGLE))
        roll = ANGLE if sign > 0.0 else ANGLE - math.pi
        kit.box(prefix + side, slot, centre,
                (SLOPE - inset, length, thick), (0.0, roll, 0.0))


def build():
    # The massing: skirt, nave, two gable ends. Four convex bodies.
    kit.block("Foundation", TRIM, X0 - 0.12, X1 + 0.12, Y0 - 0.12, Y1 + 0.12,
              0.0, 0.30)
    kit.block("Nave", BODY, X0, X1, Y0, Y1, 0.0, EAVE_Z)
    kit.prism_x("Gable_Front", BODY, X0, X1, 0.0, EAVE_Z, RIDGE_Z,
                Y0, Y0 + 0.14)
    kit.prism_x("Gable_Back", BODY, X0, X1, 0.0, EAVE_Z, RIDGE_Z,
                Y1 - 0.14, Y1)

    # The roof. `_BARE`: the planes carry their own snow slabs, and a plane
    # that whitens behind its snow is the fault propkit's BARE block exists to
    # close. The ridge keeps a dark line, which rule 10 asks for.
    _roof_pair("Roof_", kit.bare(DARK), ROOF_T, -ROOF_T / 2.0, ROOF_LEN)
    _roof_pair("Roof_Snow_", SNOW, SNOW_T, ROOF_T / 2.0 + SNOW_T / 2.0,
               ROOF_LEN + 0.06, inset=0.10)
    kit.block("Ridge_Cap", kit.bare(DARK), -0.09, 0.09,
              -ROOF_LEN / 2.0, ROOF_LEN / 2.0, RIDGE_Z - 0.04, RIDGE_Z + 0.06)

    # The tower, its ledge and the belfry. The ledge's snow is a flat panel:
    # rule 4's vocabulary, a rectangle and nothing else.
    kit.block("Bell_Tower", BODY_MID, -TW_X, TW_X, TW_Y0, TW_Y1, 0.0, TW_TOP)
    kit.block("Belfry_Ledge", TRIM, -TW_X - 0.13, TW_X + 0.13,
              TW_Y0 - 0.13, TW_Y1 + 0.13, 5.30, 5.48)
    kit.panel("Ledge_Snow", SNOW, "+z", 5.50, -TW_X - 0.09, TW_X + 0.09,
              TW_Y0 - 0.09, TW_Y1 + 0.09)

    # One four-sided winter spire, and the cross that names the building.
    kit.tube("Bell_Spire", kit.bare(DARK), (0.0, -4.85, TW_TOP - 0.10),
             (0.0, -4.85, SPIRE_TIP), 1.52, 0.0, sides=4,
             roll=math.radians(45.0))
    kit.block("Cross_Vertical", SNOW_SHADE, -0.07, 0.07, -4.92, -4.78,
              SPIRE_TIP - 0.15, SPIRE_TIP + 0.85)
    kit.block("Cross_Horizontal", SNOW_SHADE, -0.40, 0.40, -4.92, -4.78,
              SPIRE_TIP + 0.32, SPIRE_TIP + 0.46)

    # The belfry openings. Only the front one is lit: this landmark is a
    # beacon, and the amber window is the whole reason the model is on the
    # warm list at all (rule 12).
    kit.panel("Belfry_Glow", BEACON, "-y", TW_Y0 - 0.02, -0.42, 0.42,
              5.62, 6.28)
    kit.panel("Belfry_Dark_L", DARK, "-x", -TW_X - 0.02, -5.15, -4.45,
              5.62, 6.28)
    kit.panel("Belfry_Dark_R", DARK, "+x", TW_X + 0.02, -5.15, -4.45,
              5.62, 6.28)
    kit.panel("Rose_Window", DARK, "-y", TW_Y0 - 0.02, -0.35, 0.35, 3.05, 3.75)

    # The porch: two posts, a steep little gable, and the door under it.
    for side, x in (("L", -0.86), ("R", 0.86)):
        kit.block("Porch_Post_" + side, TRIM, x - 0.08, x + 0.08,
                  -6.28, -6.12, 0.0, 2.55)
    porch_run, porch_rise = 0.62, 0.30
    porch_slope = math.hypot(porch_run, porch_rise)
    for sign, side in ((-1, "Front"), (1, "Back")):
        kit.slope_y("Porch_Roof_" + side, kit.bare(DARK), sign, -5.95, 2.75,
                    porch_run, porch_rise, -1.10, 1.10, 0.10,
                    0.0, porch_slope + 0.12, -0.05)
        kit.slope_y("Porch_Snow_" + side, SNOW, sign, -5.95, 2.78,
                    porch_run, porch_rise, -1.13, 1.13, 0.05,
                    0.02, porch_slope + 0.10, 0.045)
    kit.panel("Door_Surround", SNOW, "-y", TW_Y0 - 0.02, -0.62, 0.62, 0.0, 2.30)
    kit.panel("Door_Panel", TRIM, "-y", TW_Y0 - 0.04, -0.50, 0.50, 0.0, 2.20)
    kit.block("Step_Low", TRIM, -1.00, 1.00, -6.62, -6.28, 0.0, 0.16)
    kit.block("Step_High", TRIM, -0.82, 0.82, -6.44, -6.16, 0.14, 0.32)

    # Nave windows: flat rectangles, no frame geometry (rule 4), and dark --
    # the warm quota is spent on the belfry.
    for y in (-2.40, 0.0, 2.40):
        kit.panel("Nave_Window_L_%.1f" % y, DARK, "-x", X0 - 0.02,
                  y - 0.32, y + 0.32, 1.15, 2.75)
        kit.panel("Nave_Window_R_%.1f" % y, DARK, "+x", X1 + 0.02,
                  y - 0.32, y + 0.32, 1.15, 2.75)

    # Buttresses, which is what makes the long wall read as masonry rather
    # than as a barn at landmark distance.
    for side, x in (("L", X0 - 0.14), ("R", X1 + 0.14)):
        for y in (-2.55, 0.0, 2.55):
            kit.block("Buttress_%s_%.1f" % (side, y), BODY_MID,
                      x - 0.14, x + 0.14, y - 0.26, y + 0.26, 0.0, 2.20)

    # Three icicles on the front eave, where the porch visitor looks up.
    for i, (x, length) in enumerate(((-1.45, 0.32), (0.15, 0.21), (1.30, 0.27))):
        kit.spike("Icicle_%d" % (i + 1), ICE, x, Y0 - 0.37,
                  EAVE_Z - 0.05, length, 0.09)

    # One drift against the back wall, because no wall in this valley stands
    # in open snow without one.
    kit.block("Drift", SNOW, -1.80, 0.80, Y1 - 0.06, Y1 + 0.55, 0.0, 0.42)


def _clear_scene():
    """Empty the scene without `read_factory_settings`.

    The batch file's `build_one` does exactly this: factory reset is right for
    a private background process but destructive to a live Blender MCP session,
    and data-block removal gives both workflows the same empty scene.
    """
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
        root, "assets", "models", "buildings", "church", "church.glb"))
    blend = kit.argument("--blend", os.path.join(
        root, "assets", "source", "buildings", "church.blend"))
    renders = kit.argument("--renders", os.path.join(
        root, ".superpowers", "sdd", "world-landmarks"))

    _clear_scene()
    build()
    obj = kit.finish("Church", BUDGET, label="church")
    low, high = kit.bbox(obj)
    print("church: %.2f x %.2f m on plan, %.2f m to the cross"
          % (high[0] - low[0], high[1] - low[1], high[2]))
    kit.export_glb(glb)
    kit.save_blend(blend)

    if not kit.has_flag("--no-render"):
        fx, fy = low[0] - 1.2, TW_Y0 - 1.5
        kit.three_quarter(
            os.path.join(renders, "church.png"),
            [low, high, (low[0], low[1], 0.0), (high[0], high[1], 0.0)]
            + kit.figure_corners(fx, fy),
            figure=(fx, fy, math.radians(20.0)), resolution=(1500, 1100))


main()
