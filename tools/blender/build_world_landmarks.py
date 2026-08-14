"""Build the missing authored-world batch through Blender.

The panel van follows the owner's reference: a long three-axle cab-over box,
blue-grey rather than another warm vehicle, with two heavy roof snow masses and
thin roof runners. The remaining four files are the GDD's missing beacon
landmarks: gas station, logging camp and transmission tower. The fourth
landmark, the church, moved out to `build_church.py` -- one building, one
script, the same rule the farmstead buildings follow.

Everything uses the farmstead's existing `propkit` vocabulary and therefore the
same promises as the pickup and flatbed: metres, front toward Blender -Y / Godot
+Z, one joined flat-shaded mesh, palette material names, no bevels, no automatic
decimation. Props stay under 200 triangles and secondary locations under 500.

Run one asset (useful through Blender MCP while inspecting the viewport):

    blender --background --python tools/blender/build_world_landmarks.py -- \
        --asset panel_van --no-render

Run the complete batch:

    blender --background --python tools/blender/build_world_landmarks.py
"""

import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402

# A runaway guard, not an art target. The owner explicitly retired the old
# 200-triangle hard ceiling for these authored assets: silhouette and readable
# construction detail decide the count, while this merely catches an accidental
# subdivision/high-poly operation.
DELIVERY_SAFETY_BUDGET = 5000

BODY = "PAL_STRUCT_1"
BODY_MID = "PAL_STRUCT_2"
DARK = "PAL_STRUCT_4"
TRIM = "PAL_STRUCT_3"
SNOW = "PAL_SNOW_1"
SNOW_SHADE = "PAL_SNOW_2"
BEACON = "PAL_WARM_3"


def _wheel(tag, x_sign, at_y, half_width, radius):
    """One buried-inner-cap wheel, matching both existing trucks: 16 tris."""
    centre = half_width - 0.14
    half = 0.16
    inner = (x_sign * (centre - half), at_y, radius)
    outer = (x_sign * (centre + half), at_y, radius)
    kit.tube("Wheel_" + tag, DARK, inner, outer, radius, radius, sides=6)
    kit.disc("Hub_" + tag, TRIM, outer, (x_sign, 0.0, 0.0), radius * 0.56, sides=6)


def panel_van():
    """The reference's long, blunt winter service van, detail-led not cap-led."""
    half_width = 1.08
    wheel_r = 0.43

    # Three stepped masses keep it in the same visual family as the pickup and
    # flatbed. The flat nose and long rear box make it a van, not a third truck.
    kit.block("Van_Chassis", BODY_MID, -half_width, half_width, -3.18, 3.18, 0.46, 0.82)
    kit.block("Van_Cab", BODY, -half_width, half_width, -3.12, -1.42, 0.72, 2.42)
    kit.block("Van_Box", BODY, -half_width, half_width, -1.38, 3.12, 0.72, 2.64)

    # Real slabs because these are the skyline in the 45-degree camera. Two
    # masses preserve the reference's broken, wind-scoured roof rhythm.
    kit.block("Snow_Cab", SNOW, -1.02, 1.02, -3.06, -1.48, 2.42 - kit.BITE, 2.56)
    kit.block("Snow_Box", SNOW, -1.02, 1.02, -1.30, 3.04, 2.64 - kit.BITE, 2.78)

    # The reference has two dark roof runners. Triangular tubes buy that line at
    # six triangles each and remain subordinate to the snow masses.
    for side, x in (("L", -0.86), ("R", 0.86)):
        kit.tube("Roof_Runner_" + side, DARK, (x, -2.88, 2.58), (x, 2.88, 2.78),
                 0.035, 0.035, sides=3)

    # Rule 4 panels: the split windscreen is the face of the whole silhouette.
    kit.panel("Windscreen_L", DARK, "-y", -3.13, -0.96, -0.04, 1.42, 2.26)
    kit.panel("Windscreen_R", DARK, "-y", -3.13, 0.04, 0.96, 1.42, 2.26)
    kit.panel("Cab_Window_L", DARK, "-x", -1.09, -2.84, -1.54, 1.38, 2.24)
    kit.panel("Cab_Window_R", DARK, "+x", 1.09, -2.84, -1.54, 1.38, 2.24)
    kit.panel("Grille", TRIM, "-y", -3.19, -0.68, 0.68, 0.82, 1.24)
    kit.panel("Lamp_L", SNOW_SHADE, "-y", -3.20, -0.92, -0.70, 1.02, 1.24)
    kit.panel("Lamp_R", SNOW_SHADE, "-y", -3.20, 0.70, 0.92, 1.02, 1.24)
    kit.panel("Rear_Doors_L", TRIM, "+y", 3.13, -1.00, -0.03, 0.94, 2.46)
    kit.panel("Rear_Doors_R", TRIM, "+y", 3.13, 0.03, 1.00, 0.94, 2.46)
    kit.panel("Side_Door", TRIM, "+x", 1.09, 0.12, 1.82, 0.88, 2.44)
    kit.block("Front_Bumper", TRIM, -1.06, 1.06, -3.25, -3.13, 0.48, 0.68)

    # Details that the retired 200-triangle cap would have thrown away. The
    # mirrors and steps affect silhouette; the side ribs and rear equipment make
    # the long box read as constructed sheet metal rather than one blue cuboid.
    for side, sign in (("L", -1.0), ("R", 1.0)):
        kit.tube("Mirror_Arm_" + side, TRIM,
                 (sign * 1.03, -2.68, 1.92), (sign * 1.34, -2.82, 2.02),
                 0.035, 0.035, sides=3)
        kit.box("Mirror_" + side, TRIM, (sign * 1.38, -2.84, 2.03),
                (0.12, 0.26, 0.30))
        kit.block("Cab_Step_" + side, TRIM,
                  min(sign * 1.22, sign * 0.96), max(sign * 1.22, sign * 0.96),
                  -2.42, -1.52, 0.42, 0.56)
        for index, y in enumerate((-0.95, -0.15, 0.65, 1.45, 2.25)):
            x0, x1 = sorted((sign * 1.09, sign * 1.13))
            kit.block("Box_Rib_%s_%d" % (side, index), BODY_MID,
                      x0, x1, y - 0.055, y + 0.055, 0.88, 2.54)
    kit.block("Rear_Bumper", TRIM, -1.05, 1.05, 3.12, 3.27, 0.46, 0.68)
    kit.panel("Rear_Lamp_L", "PAL_WARM_1", "+y", 3.28, -0.92, -0.70, 0.78, 1.12)
    kit.panel("Rear_Lamp_R", "PAL_WARM_1", "+y", 3.28, 0.70, 0.92, 0.78, 1.12)
    for index, z in enumerate((0.90, 1.05, 1.20)):
        kit.panel("Grille_Bar_%d" % index, DARK, "-y", -3.205, -0.66, 0.66, z, z + 0.035)
    kit.panel("Front_Plate", SNOW_SHADE, "-y", -3.255, -0.28, 0.28, 0.56, 0.72)
    # Scoured darker seams break the two white roof masses without adding a
    # noisy texture that would shimmer when the van is only a few dozen pixels.
    for index, y in enumerate((-0.80, 0.65, 2.10)):
        kit.panel("Roof_Scour_%d" % index, SNOW_SHADE, "+z", 2.785,
                  -0.92, 0.92, y - 0.035, y + 0.035)

    # Three axles are the key reference cue. The middle and rear pair make the
    # cargo mass feel heavy without any suspension geometry.
    for axle, at_y in (("F", -2.38), ("M", 1.38), ("R", 2.35)):
        _wheel(axle + "L", -1.0, at_y, half_width, wheel_r)
        _wheel(axle + "R", 1.0, at_y, half_width, wheel_r)


def gas_station():
    """A low rural station with a snow canopy and one amber roof beacon."""
    # Six convex bodies: shop, two roof planes, canopy and two posts.
    kit.block("Station_Shop", BODY, -4.2, 4.2, -0.15, 3.45, 0.0, 2.72)
    roof_run = math.sqrt(1.95 * 1.95 + 0.82 * 0.82)
    for sign, side in ((-1, "Front"), (1, "Rear")):
        kit.slope_y("Station_Roof_" + side, DARK, sign, 1.65, 3.58, 1.95, 0.82,
                    -4.38, 4.38, 0.18, 0.0, roof_run, 0.0)
        kit.slope_y("Station_Snow_" + side, SNOW, sign, 1.65, 3.61, 1.95, 0.82,
                    -4.42, 4.42, 0.08, 0.04, roof_run - 0.04, 0.07)
    kit.block("Canopy", BODY_MID, -3.3, 3.3, -2.35, -0.12, 2.42, 2.62)
    kit.panel("Canopy_Snow", SNOW, "+z", 2.64, -3.24, 3.24, -2.30, -0.16)
    for side, x in (("L", -2.72), ("R", 2.72)):
        kit.block("Canopy_Post_" + side, DARK, x - 0.10, x + 0.10, -2.12, -1.92, 0.0, 2.48)
    kit.panel("Station_Door", TRIM, "-y", -0.16, -0.54, 0.54, 0.0, 2.28)
    kit.panel("Station_Window_L", DARK, "-y", -0.16, -3.62, -0.88, 0.78, 2.18)
    kit.panel("Station_Window_R", DARK, "-y", -0.16, 0.88, 3.62, 0.78, 2.18)
    kit.panel("Station_Beacon", BEACON, "-y", -0.18, -0.34, 0.34, 2.78, 3.38)
    # Two fuel pumps are the one prop pair this landmark cannot be read without.
    for side, x in (("L", -1.15), ("R", 1.15)):
        kit.block("Fuel_Pump_" + side, TRIM, x - 0.30, x + 0.30, -1.86, -1.26, 0.0, 1.36)
        kit.panel("Pump_Face_" + side, DARK, "-y", -1.87, x - 0.22, x + 0.22, 0.72, 1.18)
        kit.tube("Pump_Hose_" + side, DARK,
                 (x + 0.28, -1.55, 1.10), (x + 0.52, -1.55, 0.36),
                 0.025, 0.025, sides=3)
    kit.block("Road_Sign_Post", DARK, 3.45, 3.63, -2.12, -1.94, 0.0, 4.15)
    kit.block("Road_Sign", BODY_MID, 3.04, 4.04, -2.16, -1.90, 3.42, 4.42)
    kit.panel("Road_Sign_Light", BEACON, "-y", -2.17, 3.18, 3.90, 3.62, 4.18)


def logging_camp():
    """A compact saw shelter, lean-to work bay and stacked winter logs."""
    # The workshop itself remains six convex bodies. The logs are location
    # dressing inside this one low-cost landmark, not extra building masses.
    kit.block("Mill_House", BODY, -4.25, 1.55, -2.45, 2.45, 0.0, 2.72)
    run = math.sqrt(2.55 * 2.55 + 0.88 * 0.88)
    for sign, side in ((-1, "Front"), (1, "Rear")):
        kit.slope_y("Mill_Roof_" + side, DARK, sign, 0.05, 3.56, 2.55, 0.88,
                    -4.42, 1.72, 0.18, 0.0, run, 0.0)
        kit.slope_y("Mill_Snow_" + side, SNOW, sign, 0.05, 3.60, 2.55, 0.88,
                    -4.46, 1.76, 0.07, 0.05, run - 0.03, 0.07)
    kit.block("LeanTo_Roof", BODY_MID, 1.48, 4.45, -2.35, 2.35, 2.52, 2.70)
    kit.panel("LeanTo_Snow", SNOW, "+z", 2.72, 1.52, 4.40, -2.30, 2.30)
    for side, y in (("F", -2.02), ("R", 2.02)):
        kit.block("LeanTo_Post_" + side, DARK, 4.18, 4.36, y - 0.09, y + 0.09, 0.0, 2.58)
    kit.panel("Mill_Door", TRIM, "-y", -2.46, -1.18, 0.18, 0.0, 2.28)
    kit.panel("Mill_Window", BEACON, "-y", -2.47, -3.62, -1.72, 0.92, 2.18)
    # A row of logs reads as fuel at the fixed camera; five-sided tubes retain
    # the cut-end silhouette without spending cylinders on hidden end caps.
    for row in range(2):
        for index in range(4 - row):
            z = 0.30 + row * 0.52
            y = -0.92 + index * 0.62 + row * 0.30
            kit.tube("Log_%d_%d" % (row, index), DARK,
                     (2.02, y, z), (3.92, y, z), 0.25, 0.25, sides=5)
            kit.disc("Log_End_%d_%d" % (row, index), TRIM,
                     (3.93, y, z), (1.0, 0.0, 0.0), 0.24, sides=5)


def transmission_tower():
    """An open 15 m lattice tower; sparse enough to stay a drawing in snow."""
    height = 14.8
    base_x, base_y = 3.55, 2.10
    top_x, top_y = 0.52, 0.38
    corners = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    for sx, sy in corners:
        kit.tube("Tower_Leg_%d_%d" % (sx, sy), DARK,
                 (sx * base_x, sy * base_y, -0.18),
                 (sx * top_x, sy * top_y, 12.15), 0.17, 0.10, sides=4)
    # Three rigid belts carry the silhouette; crossed braces explain how the
    # narrowing legs stand without turning the tower into dense visual noise.
    for level, z in enumerate((3.8, 7.7, 11.4)):
        t = z / 12.15
        x = base_x + (top_x - base_x) * t
        y = base_y + (top_y - base_y) * t
        kit.block("Belt_X_%d" % level, BODY_MID, -x, x, -0.07, 0.07, z - 0.08, z + 0.08)
        kit.block("Belt_Y_%d" % level, BODY_MID, -0.07, 0.07, -y, y, z - 0.08, z + 0.08)
    levels = [(0.0, 3.8), (3.8, 7.7), (7.7, 11.4)]
    for band, (z0, z1) in enumerate(levels):
        for sx in (-1, 1):
            for sy in (-1, 1):
                t0, t1 = z0 / 12.15, z1 / 12.15
                x0 = base_x + (top_x - base_x) * t0
                y0 = base_y + (top_y - base_y) * t0
                x1 = base_x + (top_x - base_x) * t1
                y1 = base_y + (top_y - base_y) * t1
                kit.tube("Brace_%d_%d_%d" % (band, sx, sy), BODY_MID,
                         (sx * x0, sy * y0, z0 + 0.15),
                         (-sx * x1, sy * y1, z1 - 0.15), 0.055, 0.045, sides=3)
    for level, (z, width) in enumerate(((10.1, 3.5), (12.0, 4.3), (13.7, 3.0))):
        kit.block("Crossarm_%d" % level, DARK, -width, width, -0.14, 0.14, z - 0.12, z + 0.12)
        kit.panel("Crossarm_Snow_%d" % level, SNOW, "+z", z + 0.14, -width, width, -0.16, 0.16)
        for side, x in (("L", -width * 0.82), ("R", width * 0.82)):
            kit.tube("Insulator_%d_%s" % (level, side), SNOW_SHADE,
                     (x, 0.0, z - 0.12), (x, 0.0, z - 0.66), 0.09, 0.065, sides=4)
    kit.tube("Tower_Crown", DARK, (0.0, 0.0, 12.05), (0.0, 0.0, height),
             0.16, 0.06, sides=4)
    kit.box("Tower_Beacon", BEACON, (0.0, 0.0, height + 0.18), (0.34, 0.34, 0.36))


ASSETS = {
    "panel_van": (panel_van, "Panel_Van", DELIVERY_SAFETY_BUDGET, "props"),
    "gas_station": (gas_station, "Gas_Station", DELIVERY_SAFETY_BUDGET, "buildings/gas_station"),
    "logging_camp": (logging_camp, "Logging_Camp", DELIVERY_SAFETY_BUDGET, "buildings/logging_camp"),
    "transmission_tower": (transmission_tower, "Transmission_Tower", DELIVERY_SAFETY_BUDGET,
                           "buildings/transmission_tower"),
}


def build_one(key, render=False):
    root = kit.project_root()
    build, mesh_name, budget, folder = ASSETS[key]
    # `propkit.reset()` uses read_factory_settings, correct for a private
    # background Blender process but destructive to the live Blender MCP
    # context. Data-block removal gives both workflows the same empty scene.
    import bpy
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)
    kit._MATERIALS.clear()
    del kit._PARTS[:]
    build()
    obj = kit.finish(mesh_name, budget, label=key)
    low, high = kit.bbox(obj)
    model_path = os.path.join(root, "assets", "models", folder, key + ".glb")
    source_folder = "props" if key == "panel_van" else "buildings"
    blend_path = os.path.join(root, "assets", "source", source_folder, key + ".blend")
    kit.export_glb(model_path)
    kit.save_blend(blend_path)
    print("%s: %.2f wide x %.2f long x %.2f high" %
          (key, high[0] - low[0], high[1] - low[1], high[2] - low[2]))
    if render:
        render_dir = os.path.join(root, ".superpowers", "sdd", "world-landmarks")
        fx, fy = high[0] + 1.35, low[1] + 0.5
        kit.three_quarter(
            os.path.join(render_dir, key + ".png"),
            [low, high] + kit.figure_corners(fx, fy),
            figure=(fx, fy, math.radians(205.0)),
            resolution=(1400, 1050), samples=32,
        )


def main():
    chosen = kit.argument("--asset", "all")
    render = not kit.has_flag("--no-render")
    keys = list(ASSETS.keys()) if chosen == "all" else [chosen]
    for key in keys:
        if key not in ASSETS:
            raise SystemExit("unknown --asset %s; choose %s" % (key, ", ".join(ASSETS)))
        # A complete batch renders only the hero request, not four future
        # landmarks. Each landmark can be rendered explicitly with --asset.
        build_one(key, render and (chosen != "all" or key == "panel_van"))


main()
