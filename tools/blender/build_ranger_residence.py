"""Build and render a detailed second-character winter residence.

This is a concept-source scene rather than a runtime-budget asset.  It keeps
WinterTime's palette and orthographic composition, but deliberately spends
geometry on shingles, clapboards, snow rolls, masonry, railings and yard props.

Run with Blender 5.2:
  blender --background --python tools/blender/build_ranger_residence.py
"""

import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "Docs", "reports", "ranger_residence")
BLEND_PATH = os.path.join(ROOT, "assets", "source", "buildings", "ranger_residence.blend")
RENDER_PATH = os.path.join(OUT_DIR, "ranger_residence_night.png")

PAL = {
    "snow": "8FB0D8", "snow_mid": "7FA0C9", "snow_shadow": "667890",
    "wood": "33496E", "wood_mid": "2A3854", "wood_dark": "1C2A45",
    "roof": "131C30", "brick": "6E2F2E", "trim": "A05A35",
    "warm": "FFB257",
}


def lin(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def rgb(code):
    return tuple(lin(int(code[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def mat(name, emission=0.0):
    m = bpy.data.materials.new("PAL_" + name.upper())
    m.diffuse_color = (*rgb(PAL[name]), 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (*rgb(PAL[name]), 1)
    bs.inputs["Roughness"].default_value = 0.92
    bs.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bs.inputs:
        bs.inputs["Specular IOR Level"].default_value = 0.05
    if emission:
        bs.inputs["Emission Color"].default_value = (*rgb(PAL[name]), 1)
        bs.inputs["Emission Strength"].default_value = emission
    return m


M = {}


def cube(name, loc, scale, material, bevel=0.025, rot=(0, 0, 0), collection=None):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = (scale[0] / 2, scale[1] / 2, scale[2] / 2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new("Softened hand-built edges", "BEVEL")
        mod.width, mod.segments = bevel, 3
    o.data.materials.append(M[material])
    if collection:
        for c in list(o.users_collection): c.objects.unlink(o)
        collection.objects.link(o)
    return o


def uv_sphere(name, loc, scale, material, collection=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1, location=loc)
    o = bpy.context.object
    o.name, o.scale = name, scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(M[material])
    if collection:
        for c in list(o.users_collection): c.objects.unlink(o)
        collection.objects.link(o)
    return o


def cyl(name, loc, radius, depth, material, vertices=32, rot=(0, 0, 0), collection=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth,
                                       location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(M[material])
    if collection:
        for c in list(o.users_collection): c.objects.unlink(o)
        collection.objects.link(o)
    return o


def roof_panel(name, center, width, length, pitch, side, material, z):
    angle = math.radians(pitch) * side
    x = center[0] + side * math.cos(math.radians(pitch)) * width / 2
    return cube(name, (x, center[1], z), (width, length, 0.16), material, 0.035,
                (0, angle, 0))


def window(name, x, y, z, facing="front", lit=True, w=1.15, h=1.35):
    glass = "warm" if lit else "roof"
    if facing == "front":
        cube(name + "_Glass", (x, y - 0.071, z), (w, 0.035, h), glass, 0.015)
        for dx in (-w / 2 - .06, w / 2 + .06, 0):
            cube(name + "_Mullion", (x + dx, y - .10, z), (.09, .08, h + .22), "trim", .012)
        for dz in (-h / 2 - .06, h / 2 + .06, 0):
            cube(name + "_Rail", (x, y - .105, z + dz), (w + .22, .08, .09), "trim", .012)
        cube(name + "_SnowSill", (x, y - .18, z - h / 2 - .13), (w + .35, .24, .14), "snow", .07)
    else:
        cube(name + "_Glass", (x - .071, y, z), (.035, w, h), glass, .015)
        for dy in (-w / 2 - .06, w / 2 + .06, 0):
            cube(name + "_Mullion", (x - .10, y + dy, z), (.08, .09, h + .22), "trim", .012)
        for dz in (-h / 2 - .06, h / 2 + .06, 0):
            cube(name + "_Rail", (x - .105, y, z + dz), (.08, w + .22, .09), "trim", .012)


def lamp(name, loc, energy=350):
    d = bpy.data.lights.new(name, "POINT")
    d.color, d.energy, d.shadow_soft_size = (1.0, .48, .16), energy, .65
    o = bpy.data.objects.new(name, d); o.location = loc
    bpy.context.collection.objects.link(o)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for k in PAL: M[k] = mat(k, 2.5 if k == "warm" else 0)

    # Deep, broad ranger cabin: a clearly different silhouette from the tall farmhouse.
    cube("Stone_Foundation", (0, 0, .35), (9.2, 7.1, .7), "wood_dark", .08)
    cube("Main_Timber_Shell", (0, .3, 2.35), (8.6, 6.3, 4.0), "wood", .05)
    # Individually modelled clapboards give grazing light a real broken rhythm.
    for zi in range(18):
        z = .65 + zi * .205
        cube(f"Front_Clapboard_{zi:02d}", (0, -2.875, z), (8.72, .09, .22), "wood_mid", .018)
        cube(f"Left_Clapboard_{zi:02d}", (-4.325, .3, z), (.09, 6.35, .22), "wood_mid", .018)

    # Steep roof, 38 degrees, with a generous ridge and dozens of visible shingles.
    slope_w = 5.2
    roof_panel("Roof_Left", (0, .3), slope_w, 7.15, 38, -1, "roof", 5.55)
    roof_panel("Roof_Right", (0, .3), slope_w, 7.15, 38, 1, "roof", 5.55)
    for side in (-1, 1):
        ang = math.radians(38) * side
        for row in range(11):
            for col in range(12):
                along = (row + .5) * slope_w / 11
                x = side * along * math.cos(math.radians(38))
                z = 7.12 - along * math.sin(math.radians(38))
                y = -2.75 + col * .505 + (row % 2) * .22
                cube(f"Shingle_{side}_{row}_{col}", (x, y, z + .08),
                     (slope_w / 11 + .05, .55, .07), "wood_dark", .018, (0, ang, 0))
    cube("Ridge_Cap", (0, .3, 7.22), (.32, 7.25, .30), "wood_dark", .14)

    # Half-enclosed porch and off-centre entry.
    cube("Porch_Deck", (1.15, -3.65, .78), (6.2, 1.55, .28), "wood_mid", .05)
    cube("Porch_Step_Low", (1.15, -4.55, .25), (2.25, .55, .28), "wood_mid", .04)
    cube("Porch_Step_High", (1.15, -4.25, .50), (2.05, .55, .27), "wood_mid", .04)
    for x in (-1.85, -.1, 2.4, 4.1):
        cube("Porch_Post", (x, -4.15, 2.55), (.18, .18, 3.75), "trim", .025)
    cube("Porch_Beam", (1.1, -4.15, 4.35), (6.2, .20, .23), "trim", .025)
    cube("Porch_Roof", (1.1, -3.65, 4.43), (6.45, 1.85, .16), "roof", .035,
         (math.radians(-10), 0, 0))
    for x in (-1.65, -.95, 2.9, 3.6):
        cube("Porch_Baluster", (x, -4.20, 1.35), (.09, .10, 1.15), "trim", .015)
    cube("Porch_Rail_Left", (-1.3, -4.2, 1.72), (1.35, .12, .13), "trim", .02)
    cube("Porch_Rail_Right", (3.25, -4.2, 1.72), (1.65, .12, .13), "trim", .02)

    # Door, iron fittings, lit windows and shallow bay window.
    cube("Front_Door", (.9, -2.96, 1.95), (1.25, .16, 2.45), "wood_dark", .04)
    for z in (1.15, 1.75, 2.35): cube("Door_Brace", (.9, -3.07, z), (1.08, .08, .09), "trim", .01)
    cyl("Door_Handle", (1.34, -3.17, 1.82), .065, .18, "warm", 24, (math.pi / 2, 0, 0))
    window("Front_Window_L", -2.55, -2.96, 2.25, lit=True, w=1.45, h=1.55)
    window("Front_Window_R", 3.0, -2.96, 2.25, lit=True, w=1.15, h=1.45)
    window("Side_Window", -4.4, .9, 2.35, "side", False, 1.35, 1.5)

    # Masonry chimney, cap, soot lip and snow shoulder.
    cube("Chimney", (-2.25, 1.35, 6.65), (1.05, 1.05, 3.15), "brick", .045)
    for z in [5.35 + i * .28 for i in range(10)]:
        cube("Chimney_Mortar", (-2.25, .79, z), (1.08, .035, .035), "snow_shadow", .006)
    cube("Chimney_Cap", (-2.25, 1.35, 8.25), (1.28, 1.28, .22), "wood_dark", .05)

    # Side wood shed makes the resident read as a prepared ranger/trapper.
    cube("Woodshed_Back", (4.95, 1.05, 1.75), (.15, 3.4, 2.8), "wood_dark", .025)
    cube("Woodshed_Roof", (5.75, 1.05, 3.30), (2.0, 3.65, .16), "roof", .04,
         (0, math.radians(-12), 0))
    for row in range(4):
        for col in range(9):
            cyl(f"Firewood_{row}_{col}", (5.25 + row * .38, -.25 + col * .30, .68 + row * .36),
                .15, 1.25, "trim", 20, (0, math.pi / 2, 0))

    # Lantern, bench, chopping block, axe and footprints complete the story.
    cube("Porch_Bench_Seat", (-.85, -3.55, 1.18), (1.55, .48, .14), "trim", .035)
    for x in (-1.45, -.25): cube("Bench_Leg", (x, -3.55, .93), (.14, .38, .55), "wood_dark", .02)
    cube("Lantern_Frame", (1.0, -3.18, 3.55), (.32, .24, .48), "wood_dark", .035)
    cube("Lantern_Glass", (1.0, -3.19, 3.55), (.20, .15, .33), "warm", .04)
    cyl("Chopping_Block", (-4.9, -2.8, .55), .48, 1.05, "trim", 40)
    cube("Axe_Handle", (-4.85, -2.8, 1.48), (.10, .10, 1.55), "trim", .025, (0, math.radians(-16), 0))
    cube("Axe_Head", (-5.07, -2.8, 2.08), (.48, .18, .30), "wood_dark", .035)
    for i in range(10):
        side = -1 if i % 2 else 1
        uv_sphere(f"Footprint_{i}", (1.0 + side * .18, -4.8 - i * .45, .08), (.13, .29, .045), "snow_shadow")

    # Uneven snow base and a few drifts around structural feet.
    cube("Snow_Ground", (0, 2, -.16), (24, 22, .40), "snow", .12)
    for i, (x, y, sx, sy) in enumerate([(-4.3,-1,1.3,2.0),(4.2,-2,1.5,1.1),(6,2,1.8,2.3),(-2,4,2.2,1.4)]):
        uv_sphere(f"Snow_Drift_{i}", (x, y, .18), (sx, sy, .48), "snow_mid")


def camera_and_lighting():
    world = bpy.data.worlds.new("Blue winter night")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*rgb("33496E"), 1); bg.inputs[1].default_value = .42
    bpy.context.scene.world = world
    sun_d = bpy.data.lights.new("Moon", "AREA"); sun_d.energy = 1250; sun_d.shape = "DISK"; sun_d.size = 8
    sun_d.color = (.30, .48, 1.0)
    sun = bpy.data.objects.new("Moon", sun_d); sun.location = (-8, -10, 14)
    sun.rotation_euler = (Vector((0,0,3.0)) - sun.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(sun)
    lamp("Interior_Warmth", (-1.2, -1.9, 2.4), 700)
    lamp("Porch_Lantern_Light", (1.0, -3.55, 3.45), 260)
    cam_d = bpy.data.cameras.new("Orthographic_Camera"); cam_d.type = "ORTHO"; cam_d.ortho_scale = 17.5
    cam = bpy.data.objects.new("Orthographic_Camera", cam_d); cam.location = (14, -20, 13)
    cam.rotation_euler = (Vector((.4, .2, 3.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(cam); bpy.context.scene.camera = cam


def finish():
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True); os.makedirs(OUT_DIR, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage = 1400, 1050, 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = RENDER_PATH
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.image_settings.color_mode = "RGBA"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.render.render(write_still=True)
    meshes = [o for o in scene.objects if o.type == "MESH"]
    vertices = sum(len(o.data.vertices) for o in meshes)
    assert len(meshes) > 390, "detail regression: expected hundreds of authored pieces"
    assert vertices > 8000, "detail regression: masonry or yard details lost resolution"
    assert not any("Snow" in o.name and any(tag in o.name for tag in
                   ("Roof", "Eave", "Chimney", "Woodshed")) for o in meshes), \
        "authored roof snow must stay absent; the game snow system owns it"
    assert os.path.getsize(BLEND_PATH) > 300000
    print(f"RANGER_RESIDENCE_OK objects={len(meshes)} vertices={vertices}")
    print(BLEND_PATH); print(RENDER_PATH)


build()
camera_and_lighting()
finish()
