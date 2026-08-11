"""Shared modelling kit for the farmstead props.

Art Bible section 5.1 decides that the *script* is the artifact and the mesh is
output: when a roof line is wrong you change a number in a build script and
re-run, you do not open the mesh. This module holds the parts every prop build
script needs -- the palette, the primitives, the export, and the acceptance
render -- so that each `build_*.py` beside it is nothing but a list of parts.

    "Don't ask AI for realistic meshes. It will not deliver. Simple shapes, it
     does well. This house is just boxes and a roof. The light does the rest."

Nothing here bevels, subdivides, smooths or weathers anything. Every primitive
below is convex and flat-shaded, and the four of them -- box, prism, flat panel
and tapered tube -- are the whole vocabulary.

---------------------------------------------------------------------------
CO-ORDINATES  (identical to tools/blender/build_farmhouse.py)
---------------------------------------------------------------------------
Blender is Z-up; glTF and Godot are Y-up, and the exporter converts:

    Blender +Z (up)      -> Godot +Y   (up)
    Blender -Y (front)   -> Godot +Z
    Blender +X (right)   -> Godot +X

So **every prop's front faces -Y in Blender**, which is +Z in Godot -- the same
way the farmhouse faces, so a camera that sees the porch also sees the truck's
grille and the shed's door. Origins are at ground level unless a build script
says otherwise in its docstring.

---------------------------------------------------------------------------
MATERIALS
---------------------------------------------------------------------------
Materials are named `PAL_<BAND>_<n>` after the Art Bible's 12-colour table
(section 1.1). **The names, not the colours, are the contract**: Godot's
importer runs `tools/palette_import_materials.gd`, which reads the real colour
out of `data/palette/color_bible.tres` and rebuilds each material flat,
non-metallic and specular-disabled. That is the only way an imported .glb can
pass tests/art/test_shading_features.gd, because Godot's glTF importer leaves
`specular_mode` enabled on everything it makes.

The hex values below are therefore only for Blender's viewport and for the
acceptance renders. They are hardcoded, which is allowed in `tools/` and
nowhere else.

---------------------------------------------------------------------------
ONE MESH PER ASSET
---------------------------------------------------------------------------
`finish()` joins every part into a single object, so each prop exports as
exactly one mesh. That is deliberate and it is a test result, not a convenience:
tests/art/test_topology.gd is a **per-mesh** gate, so an asset split across
several meshes can be far over its class budget while every mesh in it passes
(the farmhouse needed its own test to add itself up). A one-mesh prop makes the
per-mesh gate an exact per-asset gate, with nothing left to fall through.

The farmhouse is the exception it earned: it is split by interior-reveal group
because the game has to fade its roof. Nothing here has an inside.
"""

import math
import os
import sys

import bpy
from mathutils import Euler, Vector

# ---------------------------------------------------------------------------
# The 12-colour table (Art Bible section 1.1).
# ---------------------------------------------------------------------------
PALETTE = {
    "PAL_SNOW_1": "8FB0D8",    # snow, brightest
    "PAL_SNOW_2": "7FA0C9",
    "PAL_SNOW_3": "748FBB",
    "PAL_SNOW_4": "6987B4",
    "PAL_SNOW_5": "5D7BA6",
    "PAL_STRUCT_1": "33496E",  # structure, lit face
    "PAL_STRUCT_2": "2A3854",
    "PAL_STRUCT_3": "1C2A45",
    "PAL_STRUCT_4": "131C30",  # structure, darkest -- roofs and trees (rule 7)
    "PAL_WARM_1": "6E2F2E",    # deep red -- the truck (rule 12)
    "PAL_WARM_2": "A05A35",    # rust orange -- the scarf
    "PAL_WARM_3": "FFB257",    # amber -- windows, fire
}

# The names the farmhouse uses for the same jobs, so the outbuildings are the
# same blue as the house without either script guessing.
SIDING = "PAL_STRUCT_1"
SKIRT = "PAL_STRUCT_3"
ROOF = "PAL_STRUCT_4"
GLASS_DARK = "PAL_STRUCT_4"
GLASS_LIT = "PAL_WARM_3"
SURROUND = "PAL_SNOW_1"
SNOW = "PAL_SNOW_1"
ICE = "PAL_SNOW_2"
TIMBER = "PAL_STRUCT_4"        # trees, poles, wires -- rule 7's near-black

## How far a block that sits on another one sinks into it.
##
## Not a style choice. Two exactly coplanar faces make a path tracer shadow the
## surface against itself -- the farmhouse's first interior render came back
## with a black floor for exactly this -- and a rasteriser z-fights instead,
## which is worse because it only shows on some frames. Parts overlap by this
## much and neither renderer has a decision to make.
BITE = 0.03

_MATERIALS = {}
_PARTS = []


# ---------------------------------------------------------------------------
# Scene plumbing
# ---------------------------------------------------------------------------
def reset():
    """Start from an empty scene in this process.

    **This is what keeps an open Blender session safe.** Every build script runs
    under `blender --background`, which is a private process; factory settings
    with `use_empty=True` then guarantee it inherits nothing. Nothing in this
    module ever reaches for a scene it did not create.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATERIALS.clear()
    del _PARTS[:]


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(slot):
    """One Blender material per palette slot, created on first use."""
    if slot in _MATERIALS:
        return _MATERIALS[slot]
    if slot not in PALETTE:
        raise SystemExit("propkit: %s is not a palette slot" % slot)
    hexcode = PALETTE[slot]
    rgb = [srgb_to_linear(int(hexcode[i:i + 2], 16) / 255.0) for i in (0, 2, 4)]
    mat = bpy.data.materials.new(name=slot)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    # Rule 8 bans specular highlights. Blender renamed this socket across
    # versions, so ask rather than assume -- an unknown name would leave a
    # highlight in the acceptance renders and nowhere else.
    for name in ("Specular IOR Level", "Specular"):
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = 0.0
    mat.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    _MATERIALS[slot] = mat
    return mat


def emit(name, slot, verts, faces):
    """Add one part. Vertices are already in world space -- no object transform
    is ever set, so what the mesh holds is what the exporter writes."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([Vector(v) for v in verts], [], faces)
    mesh.validate()
    mesh.materials.append(material(slot))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    _PARTS.append(obj)
    return obj


# ---------------------------------------------------------------------------
# The four primitives
# ---------------------------------------------------------------------------
# A unit cube wound counter-clockwise seen from outside, so nothing ends up
# inside-out -- Godot culls back faces, and an inverted part does not look
# wrong, it looks absent.
_CUBE_V = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
           (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
_CUBE_F = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
           (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]


def box(name, slot, center, size, rot=(0.0, 0.0, 0.0)):
    """A convex block. 12 triangles."""
    basis = Euler(rot, "XYZ").to_matrix()
    half = Vector((size[0] / 2.0, size[1] / 2.0, size[2] / 2.0))
    origin = Vector(center)
    verts = [origin + basis @ Vector((v[0] * half.x, v[1] * half.y, v[2] * half.z))
             for v in _CUBE_V]
    return emit(name, slot, verts, _CUBE_F)


def block(name, slot, x0, x1, y0, y1, z0, z1):
    """A box given by its bounds, which is how walls read easiest. 12 tris."""
    return box(name, slot,
               ((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0),
               (x1 - x0, y1 - y0, z1 - z0))


def prism_x(name, slot, x0, x1, x_apex, z_base, z_apex, y0, y1):
    """A gable end: a triangle in XZ extruded along Y. 8 triangles."""
    tri = [(x0, z_base), (x1, z_base), (x_apex, z_apex)]
    verts = [(p[0], y0, p[1]) for p in tri] + [(p[0], y1, p[1]) for p in tri]
    faces = [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]
    return emit(name, slot, verts, faces)


def prism_y(name, slot, y0, y1, y_apex, z_base, z_apex, x0, x1):
    """The same gable turned ninety degrees: a triangle in YZ extruded along X."""
    tri = [(y0, z_base), (y1, z_base), (y_apex, z_apex)]
    verts = [(x0, p[0], p[1]) for p in tri] + [(x1, p[0], p[1]) for p in tri]
    faces = [(0, 1, 2), (5, 4, 3), (3, 4, 1, 0), (4, 5, 2, 1), (5, 3, 0, 2)]
    return emit(name, slot, verts, faces)


def slope_y(name, slot, sign, ridge_y, ridge_z, run, rise,
            x0, x1, thick, d0, d1, lift):
    """A slab lying on a roof plane whose ridge runs along X.

    `d0`..`d1` are distances measured down the slope from the ridge, so the roof
    plane and the snow lying on it are the same call with different numbers --
    which is the whole point of doing this in a script. `lift` offsets the slab
    along the plane's outward normal.
    """
    ang = math.atan2(rise, run)
    down = Vector((0.0, sign * math.cos(ang), -math.sin(ang)))
    out = Vector((0.0, sign * math.sin(ang), math.cos(ang)))
    ridge = Vector(((x0 + x1) / 2.0, ridge_y, ridge_z))
    center = ridge + down * ((d0 + d1) / 2.0) + out * lift
    return box(name, slot, center, (x1 - x0, d1 - d0, thick),
               (-sign * ang, 0.0, 0.0))


def panel(name, slot, axis, at, u0, u1, v0, v1):
    """A flat rectangle. Rule 4: a window is this and nothing else -- no frame
    geometry, no muntins, no reveal. 2 triangles.

    `axis` is the wall's outward direction, one of +x -x +y -y +z; `at` is where
    the panel sits on that axis; u runs along the wall and v is height (for +z,
    u is x and v is y).
    """
    if axis in ("+x", "-x"):
        pts = [(at, u0, v0), (at, u1, v0), (at, u1, v1), (at, u0, v1)]
        if axis == "-x":
            pts.reverse()
    elif axis == "+z":
        pts = [(u0, v0, at), (u1, v0, at), (u1, v1, at), (u0, v1, at)]
    else:
        pts = [(u0, at, v0), (u1, at, v0), (u1, at, v1), (u0, at, v1)]
        if axis == "+y":
            pts.reverse()
    return emit(name, slot, pts, [(0, 1, 2, 3)])


def spike(name, slot, x, y, z_top, length, width):
    """An icicle: a tapered four-sided spike. 6 triangles. It exists for the
    silhouette along an eave and for nothing else."""
    h = width / 2.0
    verts = [(x - h, y - h, z_top), (x + h, y - h, z_top),
             (x + h, y + h, z_top), (x - h, y + h, z_top),
             (x, y, z_top - length)]
    faces = [(0, 1, 2, 3), (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)]
    return emit(name, slot, verts, faces)


def frame(direction, roll=0.0):
    """A right-handed (u, v) pair across `direction`, with u x v = direction.

    Deterministic: the reference vector only flips when the direction is within
    ~25 degrees of vertical, so a limb and its children get a stable twist and
    re-running the script produces byte-identical geometry.
    """
    d = Vector(direction).normalized()
    ref = Vector((0.0, 0.0, 1.0)) if abs(d.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    u = ref.cross(d).normalized()
    v = d.cross(u)
    if roll:
        c, s = math.cos(roll), math.sin(roll)
        u = (u * c + v * s).normalized()
        v = d.cross(u)
    return u, v


def tube(name, slot, p0, p1, r0, r1, sides=3, roll=0.0):
    """A tapered N-sided tube from `p0` to `p1`. The whole tree is these.

    Costs `2 * sides` triangles, or `sides` when `r1` is zero -- a limb that
    tapers to a point is a pyramid, and every twig tip in the wood is one.

    **No end caps.** Every tube in this project starts inside the thing it grew
    out of (a child limb inside its parent, a trunk below the snow line), so the
    open base is never visible, and paying 2-6 triangles per twig to close a
    hole nobody can see would halve the number of twigs a tree can afford.
    """
    a, b = Vector(p0), Vector(p1)
    axis = b - a
    if axis.length < 1.0e-6:
        return None
    u, v = frame(axis, roll)
    angles = [2.0 * math.pi * i / sides for i in range(sides)]
    ring0 = [a + (u * math.cos(t) + v * math.sin(t)) * r0 for t in angles]
    if r1 <= 1.0e-6:
        verts = ring0 + [b]
        faces = [(i, (i + 1) % sides, sides) for i in range(sides)]
    else:
        ring1 = [b + (u * math.cos(t) + v * math.sin(t)) * r1 for t in angles]
        verts = ring0 + ring1
        faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i)
                 for i in range(sides)]
    return emit(name, slot, verts, faces)


def disc(name, slot, center, normal, radius, sides=6, roll=0.0):
    """A flat regular n-gon facing `normal`. `sides - 2` triangles.

    It exists so a wheel can be a 6-sided `tube` (12 triangles, no caps) plus
    one outer face (4), instead of a `cylinder` (20) whose inner cap is pressed
    into the body and never seen. Sixteen triangles a wheel against twenty is
    the difference between the truck affording snow in its bed and not.
    """
    c = Vector(center)
    u, v = frame(normal, roll)
    verts = [c + (u * math.cos(2.0 * math.pi * i / sides)
                  + v * math.sin(2.0 * math.pi * i / sides)) * radius
             for i in range(sides)]
    return emit(name, slot, verts, [tuple(range(sides))])


def cylinder(name, slot, base, top, radius, sides=8):
    """A capped prism -- the transformer can, and nothing else so far.

    `2 * sides` triangles for the wall plus `2 * (sides - 2)` for the two caps.
    """
    a, b = Vector(base), Vector(top)
    u, v = frame(b - a)
    angles = [2.0 * math.pi * i / sides for i in range(sides)]
    ring0 = [a + (u * math.cos(t) + v * math.sin(t)) * radius for t in angles]
    ring1 = [b + (u * math.cos(t) + v * math.sin(t)) * radius for t in angles]
    verts = ring0 + ring1
    faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i)
             for i in range(sides)]
    faces.append(tuple(range(sides, 2 * sides)))          # top, normal +axis
    faces.append(tuple(range(sides - 1, -1, -1)))         # base, normal -axis
    return emit(name, slot, verts, faces)


def ring(name, slot, center, normal, major_r, minor_r, major_seg=10, minor_seg=3):
    """A torus. The tire, and only the tire.

    `2 * major_seg * minor_seg` triangles. At `minor_seg=3` the tube's section is
    a triangle, which is invisible on a near-black ring 0.06 m thick and saves a
    third of the cost of a square one.
    """
    c = Vector(center)
    u, v = frame(normal)
    n = Vector(normal).normalized()
    verts = []
    for i in range(major_seg):
        theta = 2.0 * math.pi * i / major_seg
        radial = u * math.cos(theta) + v * math.sin(theta)
        hub = c + radial * major_r
        for j in range(minor_seg):
            phi = 2.0 * math.pi * j / minor_seg
            verts.append(hub + (radial * math.cos(phi) + n * math.sin(phi)) * minor_r)
    faces = []
    for i in range(major_seg):
        i1 = (i + 1) % major_seg
        for j in range(minor_seg):
            j1 = (j + 1) % minor_seg
            faces.append((i * minor_seg + j, i1 * minor_seg + j,
                          i1 * minor_seg + j1, i * minor_seg + j1))
    return emit(name, slot, verts, faces)


# ---------------------------------------------------------------------------
# Finishing
# ---------------------------------------------------------------------------
def project_uvs(obj):
    """One UV unit per metre, projected along each face's dominant axis, so V is
    world height on every vertical face.

    Rule 4 says the clapboard lines are the shader's job, not geometry's. A
    siding shader is then `fract(UV.y / board_spacing)` with no per-object
    tuning and no stretching on a wall of a different size. glTF flips V on the
    way out; stripes are periodic, so the flip does not matter.
    """
    mesh = obj.data
    layer = mesh.uv_layers[0] if mesh.uv_layers else mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        n = poly.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in poly.loop_indices:
            co = mesh.vertices[mesh.loops[loop].vertex_index].co
            if az >= ax and az >= ay:
                layer.data[loop].uv = (co.x, co.y)
            elif ax >= ay:
                layer.data[loop].uv = (co.y, co.z)
            else:
                layer.data[loop].uv = (co.x, co.z)


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def finish(name, budget, label=None):
    """Join every part into one object, UV it, and refuse to go over budget.

    Returns the joined object. The budget check is here rather than in a test so
    that an edit which busts it fails at build time, in the script that made it,
    naming the number -- rather than three commands later in Godot.
    """
    if not _PARTS:
        raise SystemExit("propkit: %s has no parts" % name)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in _PARTS:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = _PARTS[0]
    if len(_PARTS) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    project_uvs(joined)
    count = triangles(joined)
    print("%s: %d parts, %d triangles against a %d budget"
          % (label or name, len(_PARTS), count, budget))
    if count > budget:
        raise SystemExit("%s: %d triangles is over the %d budget"
                         % (label or name, count, budget))
    del _PARTS[:]
    return joined


def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_apply=False,
        export_normals=True,
        export_texcoords=True,
        export_animations=False,
    )
    print("propkit: wrote %s" % path)


def save_blend(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Blender's factory default keeps one numbered backup, which would drop a
    # .blend1 into the repo next to the file on every single run.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path)
    print("propkit: wrote %s" % path)


# ---------------------------------------------------------------------------
# The acceptance render.
#
# Built only after the export, so no camera, light, ground plane or scale
# figure can end up in a .glb.
#
# One caveat that applies to every image these produce: they are Cycles renders
# of the palette's *albedo* under a plain low sun. The game will not look like
# this and specifically will not be this dark -- the structure tones are 2-9%
# reflective in linear light, and the project's two-band `light()` does not
# multiply them, it picks a different palette entry for the lit band (Art Bible
# section 4.1). Read these images for form, silhouette and scale. Read level.jpg
# for final value.
# ---------------------------------------------------------------------------
def setup_world(sun_energy=4.6):
    world = bpy.data.worlds.new("Winter")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    # A blue sky filling the shadows, so the dark band stays blue rather than
    # going grey -- Art Bible section 4.1, in spirit, for a still.
    bg.inputs[0].default_value = (0.28, 0.45, 0.72, 1.0)
    bg.inputs[1].default_value = 0.85
    bpy.context.scene.world = world

    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = sun_energy
    sun_data.angle = math.radians(2.0)
    sun_data.color = (1.0, 0.95, 0.86)
    sun = bpy.data.objects.new("Sun", sun_data)
    # Low winter sun: rule 10 wants long, soft-edged shadows, and in level.jpg
    # the shadows are a third of the frame.
    sun.rotation_euler = Euler((math.radians(72.0), 0.0, math.radians(-38.0)), "XYZ")
    bpy.context.scene.collection.objects.link(sun)

    ground = bpy.data.meshes.new("Ground")
    ground.from_pydata([(-60, -60, 0), (60, -60, 0), (60, 60, 0), (-60, 60, 0)],
                       [], [(0, 1, 2, 3)])
    ground.validate()
    ground.materials.append(material("PAL_SNOW_1"))
    obj = bpy.data.objects.new("Ground", ground)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def scale_figure(x, y, facing=0.0):
    """A 1.8 m person, for the renders only.

    The brief's one hard scale instruction is "scale against a 1.8 m character",
    and a render without a person in it cannot be checked against that. Six
    boxes, one of them the rust-orange scarf, because that scarf is how the
    player finds themselves on the snow (Art Bible section 5.3).

    Never exported: every build script calls this after export_glb().
    """
    parts = [
        ("Fig_LegL", SKIRT, (-0.10, 0.0, 0.42), (0.17, 0.19, 0.85)),
        ("Fig_LegR", SKIRT, (0.10, 0.0, 0.42), (0.17, 0.19, 0.85)),
        ("Fig_Torso", "PAL_STRUCT_2", (0.0, 0.0, 1.13), (0.44, 0.26, 0.62)),
        ("Fig_ArmL", "PAL_STRUCT_2", (-0.27, 0.0, 1.12), (0.13, 0.15, 0.56)),
        ("Fig_ArmR", "PAL_STRUCT_2", (0.27, 0.0, 1.12), (0.13, 0.15, 0.56)),
        ("Fig_Scarf", "PAL_WARM_2", (0.0, 0.0, 1.47), (0.34, 0.24, 0.13)),
        ("Fig_Head", "PAL_STRUCT_3", (0.0, 0.0, 1.66), (0.27, 0.26, 0.28)),
    ]
    made = []
    c, s = math.cos(facing), math.sin(facing)
    for name, slot, (px, py, pz), size in parts:
        made.append(box(name, slot,
                        (x + px * c - py * s, y + px * s + py * c, pz),
                        size, (0.0, 0.0, facing)))
    # Straight back onto the render pile: these are not part of any asset.
    del _PARTS[:]
    return made


def camera(name, target, azimuth, elevation, distance, ortho_scale):
    """Orthographic, because the game is (Art Bible rule 1).

    The default caller passes azimuth 30 / elevation 45, which is the farmhouse
    renders' angle and the game camera's, so a prop render and a farmhouse
    render can be held side by side.
    """
    data = bpy.data.cameras.new(name)
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    cam = bpy.data.objects.new(name, data)
    az, el = math.radians(azimuth), math.radians(elevation)
    offset = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el),
                     math.sin(el)))
    cam.location = Vector(target) + offset * distance
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    return cam


def render_settings(samples=64, resolution=(1400, 1050)):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.image_settings.file_format = "PNG"
    # AgX would desaturate the palette into something that is not the palette.
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x, scene.render.resolution_y = resolution


def render_to(path, cam):
    scene = bpy.context.scene
    scene.camera = cam
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("propkit: wrote %s" % path)


def bbox(obj):
    """(min, max) corners in world space. No object here is ever transformed,
    so the local bound box is the world one."""
    xs = [c[0] for c in obj.bound_box]
    ys = [c[1] for c in obj.bound_box]
    zs = [c[2] for c in obj.bound_box]
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def fit(corners, resolution, azimuth=30.0, elevation=45.0, margin=1.16):
    """Camera target and ortho scale that hold every point in `corners`.

    Framing by hand needed one magic number per asset and got two of them wrong
    in the first pass -- a tree with its scale figure cropped off the bottom
    proves nothing about scale, which is the only thing that render is for. This
    projects the points onto the camera's own right and up axes and solves for
    the scale, so the numbers are derived rather than guessed.

    Blender's `ortho_scale` spans the *larger* of the two resolution axes, hence
    the aspect term.
    """
    az, el = math.radians(azimuth), math.radians(elevation)
    right = Vector((math.cos(az), math.sin(az), 0.0))
    up = Vector((-math.sin(az) * math.sin(el), math.cos(az) * math.sin(el), math.cos(el)))
    pts = [Vector(c) for c in corners]
    us = [p.dot(right) for p in pts]
    vs = [p.dot(up) for p in pts]
    w, h = resolution
    span_u = (max(us) - min(us)) * margin
    span_v = (max(vs) - min(vs)) * margin
    scale = max(span_u, span_v * w / h) if w >= h else max(span_v, span_u * h / w)
    centre_u = (max(us) + min(us)) / 2.0
    centre_v = (max(vs) + min(vs)) / 2.0
    forward = right.cross(up)          # into the screen, away from the camera
    target = right * centre_u + up * centre_v + forward * 0.0
    return tuple(target), scale


def three_quarter(path, corners, figure=None, samples=64,
                  resolution=(1400, 1050), azimuth=30.0, elevation=45.0,
                  margin=1.16):
    """The one render every asset gets: three-quarter, orthographic, 45 down.

    `corners` is every point that must be in frame -- normally `bbox()` of the
    asset, plus the scale figure's own footprint.
    """
    render_settings(samples, resolution)
    setup_world()
    if figure is not None:
        scale_figure(figure[0], figure[1], figure[2] if len(figure) > 2 else 0.0)
    target, scale = fit(corners, resolution, azimuth, elevation, margin)
    render_to(path, camera("Cam", target, azimuth, elevation, 80.0, scale))


def figure_corners(x, y):
    """The box a 1.8 m scale figure at (x, y) occupies, for `fit`."""
    return [(x - 0.4, y - 0.4, 0.0), (x + 0.4, y + 0.4, 1.8)]


# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------
def project_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def argument(flag, default):
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if flag in rest and rest.index(flag) + 1 < len(rest):
        return rest[rest.index(flag) + 1]
    return default


def has_flag(flag):
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return flag in rest
