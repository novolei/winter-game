"""Build the farmhouse -- the player's home -- out of boxes and a roof.

Art Bible section 5.1 decides that the *script* is the artifact and the mesh is
output: when the roof is wrong you change a number here and re-run, you do not
open the mesh. Nothing in this file sculpts, bevels, subdivides or weathers
anything. Every part is one convex block, one line, one name.

    "Don't ask AI for realistic meshes. It will not deliver. Simple shapes, it
     does well. This house is just boxes and a roof. The light does the rest."

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_farmhouse.py

Optional arguments after `--`:

    --glb    <path>   default assets/models/buildings/farmhouse/farmhouse.glb
    --blend  <path>   default assets/source/buildings/farmhouse.blend
    --renders <dir>   default .superpowers/sdd/wave1
    --no-render       skip the three acceptance renders (they cost ~2 min)

It never touches an open Blender session. It starts from factory settings with
an empty scene, so the scene a human has open elsewhere is not at risk.

---------------------------------------------------------------------------
CO-ORDINATES
---------------------------------------------------------------------------
Blender is Z-up; glTF and Godot are Y-up, and the exporter converts. What
survives the conversion, and what the game code may rely on:

    Blender +Z (up)      -> Godot +Y   (up)
    Blender -Y (front)   -> Godot +Z   (the porch, the door, the front wall)
    Blender +X (right)   -> Godot +X

So **the front of the house faces +Z in Godot**, and a camera placed at +Z
looking back at the origin sees the porch. Origin is at the main block's
front-left corner at ground level, so the model sits on Y=0 with no offset.

---------------------------------------------------------------------------
MATERIALS
---------------------------------------------------------------------------
Twelve materials, named `PAL_<BAND>_<n>` after the Art Bible's 12-colour table
(section 1.1). The names, not the colours, are the contract: Godot's importer
runs `tools/palette_import_materials.gd`, which reads the real colour out of
`data/palette/color_bible.tres` and rebuilds every material as a flat,
non-metallic, specular-disabled StandardMaterial3D. That is the only way an
imported .glb can pass tests/art/test_shading_features.gd, because Godot's glTF
importer leaves `specular_mode` enabled on everything it makes -- including the
white material it invents for a surface that arrives without one.

The hex values below are therefore only for Blender's own viewport and for the
acceptance renders. They are hardcoded, which is allowed here and nowhere else:
`tools/` is the documented exception to the no-hardcoded-colour rule, being the
place that writes the palette in the first place.

---------------------------------------------------------------------------
UVs
---------------------------------------------------------------------------
Rule 4: the clapboard lines are the shader's job, not geometry's. So every face
is projected along its own dominant axis at **1 UV unit = 1 metre**, which puts
world height into V on every vertical face. A siding shader is then
`fract(UV.y / board_spacing)` with no per-object tuning and no stretching on a
wall of a different size. glTF flips V on the way out; stripes are periodic, so
the flip does not matter.

---------------------------------------------------------------------------
GROUPS -- the interior-reveal contract
---------------------------------------------------------------------------
Parts are joined into ten objects named for what the reveal system does with
them, so the fade list is a list of *names* and never of indices.

Fade these five when the player crosses the threshold -- this is the set:

    FH_Fade_Roof        every roof plane, the ground-floor ceiling, roof snow,
                        the chimney and the antenna
    FH_Fade_Front       every -Y facing wall and what is mounted on it: the
                        front facade, the front gable, the wing's front and
                        porch-facing walls, their windows, the door
    FH_Fade_Porch       porch roof, its snow, its icicles, its four posts
    FH_Fade_SideLeft    the -X walls and their windows
    FH_Fade_Divider     the wall between the two rooms
    FH_Door             the front door leaf. Its own group because it is the
                        one part that MOVES -- it is hinged, and its origin is
                        on the hinge stile rather than at the world origin. It
                        fades with the facade it sits in, or an open door would
                        be left hanging in the air once the wall had gone.

FH_Fade_SideLeft and FH_Fade_Divider were built addressable but out of the set, because the camera's
final yaw and pitch were open when this was written. They are settled now --
orthographic, pitched 45, yawed -35 -- and that camera looks at the front-LEFT
corner, so the -X walls face the lens exactly as the +Z ones do. FH_Fade_SideLeft
was hiding about a third of the room's width including the bed; FH_Fade_Divider
was hiding the whole wing, so a player walking to the workbench vanished behind
a wall under a camera that cannot move to look round it.

Never faded:

    FH_Shell            the walls that are never in the way
    FH_Porch            deck, steps and railing -- knee height, they frame the
                        view rather than block it
    FH_Room             floors
    FH_Furniture        stove, table, bed, bench, storage

Each group is one MeshInstance3D in Godot, so a fade is
`get_node("FH_Fade_Roof").transparency = t` -- no material juggling.
"""

import math
import os
import sys

import bpy
from mathutils import Euler, Vector

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402

TRIANGLE_BUDGET = 1500

# ---------------------------------------------------------------------------
# The 12-colour table (Art Bible section 1.1). Names are the contract; see the
# module docstring on why the values here are Blender-only.
# ---------------------------------------------------------------------------
PALETTE = {
    "PAL_SNOW_1": "8FB0D8",    # snow, brightest
    "PAL_SNOW_2": "7FA0C9",
    "PAL_SNOW_3": "748FBB",
    "PAL_SNOW_4": "76889F",
    "PAL_SNOW_5": "667890",
    "PAL_STRUCT_1": "33496E",  # structure, lit face
    "PAL_STRUCT_2": "2A3854",
    "PAL_STRUCT_3": "1C2A45",
    "PAL_STRUCT_4": "131C30",  # structure, darkest -- roofs and trees
    "PAL_WARM_1": "6E2F2E",    # deep red -- the chimney
    "PAL_WARM_2": "A05A35",    # rust orange -- the trim line
    "PAL_WARM_3": "FFB257",    # amber -- lit windows, fire
}

SIDING = "PAL_STRUCT_1"
SKIRT = "PAL_STRUCT_3"
ROOF = "PAL_STRUCT_4"
TRIM = "PAL_WARM_2"
GLASS_DARK = "PAL_STRUCT_4"
GLASS_LIT = "PAL_WARM_3"
SURROUND = "PAL_SNOW_1"
SNOW = "PAL_SNOW_1"
ICE = "PAL_SNOW_2"
## The same near-black, for the parts a settled mass does not lie on. See
## propkit's block above BARE for the whole argument.
##
##   the roof planes  they carry a `snow_cap`, and two white things on one roof
##                    is the fault this build closes -- the owner's own words
##                    for it were that the roof "resolves into rectangles"
##   the antenna      0.06 m bars against a 1.33 m pattern, so a bar can only
##                    take it in whole pieces or not at all, and an antenna
##                    flickering between white and black pieces reads as a
##                    broken mesh. The power wire's argument, one storey up.
##   the flue         a hole that goes pale in bright weather stops being a hole
ROOF_BARE = "PAL_STRUCT_4_BARE"
PORCH_PAINT = "PAL_SNOW_2"
INSIDE = "PAL_STRUCT_2"

# ---------------------------------------------------------------------------
# Dimensions, in metres. The character is 1.8 m: the door is 2.10, the interior
# doorway 2.10, the step rise 0.15, the railing 0.90 above the deck, and the
# clearance under the porch roof at its lowest point 2.27.
# ---------------------------------------------------------------------------
T = 0.16                    # wall thickness
FLOOR_Z = 0.45              # top of the ground floor, and of the porch deck
CEIL_Z = 3.05               # underside of the ground-floor ceiling
CEIL_TOP = 3.20
MAIN_TOP = 5.00             # top of the two-storey walls
MAIN_X0, MAIN_X1 = -3.60, 3.60
MAIN_Y0, MAIN_Y1 = 0.00, 6.00
MAIN_RISE = 2.40            # over a 3.60 half-span: a 33.7 degree pitch
MAIN_RIDGE_Z = MAIN_TOP + MAIN_RISE

WING_X0, WING_X1 = -3.60, 0.00
WING_Y0, WING_Y1 = -3.60, 0.00
WING_TOP = 3.20
WING_RISE = 1.20            # over a 1.80 half-span: the same 33.7 degrees
WING_RIDGE_Y = (WING_Y0 + WING_Y1) / 2.0
WING_RIDGE_Z = WING_TOP + WING_RISE

EAVE = 0.35                 # overhang past the wall on a sloping side
VERGE = 0.30                # overhang past the wall at a gable end
ROOF_T = 0.14

## ---------------------------------------------------------------------------
## THE SETTLED MASS ON THE ROOFS
## ---------------------------------------------------------------------------
## propkit's `snow_cap` block carries the whole of the reasoning -- read that
## first. These are this building's numbers.
##
## What was here until now was ten flat 0.17 m slabs, `Snow_Main_*`,
## `Snow_Wing_*` and `Porch_Roof_Snow`, authored as *the* snow on a roof that
## was always dark. They read perfectly for as long as that held. The day
## `cel_flat.gdshader` started whitening the roof plane behind them their
## silhouettes stopped reading and what survived was their cast shadows, their
## stepped edges and the bare slate between them -- angular dark shapes on a
## white field, which is what "the roof looks like it is rendering through
## itself" actually was. They are gone, the roof planes now refuse the shader's
## snow outright (see NO_SETTLED_SNOW), and the mass below is the only white
## thing on this roof.
##
## SNOW_DEPTH is what the owner asked for and what a threshold cannot give: at
## 0.24 m against a 1.8 m character the mass is a hand's span thick, which is
## what a week of it looks like on a 33.7-degree pitch.
SNOW_DEPTH = 0.28
## The roll. 0.20 puts the widest point of the bulge 0.20 m out from where the
## top face stops and 0.04 m above the roof plane -- low on the mass, which is
## where surface tension puts it.
SNOW_ROLL = 0.22
## Past the eave at full settle. The lip hangs over the roof edge by 0.15 m,
## which is the silhouette the whole exercise is for.
SNOW_OVER = 0.15
## Down-slope of the ridge the mass starts, so Art Bible rule 10's ridge line
## still reads with two caps meeting either side of it.
SNOW_RIDGE_GAP = 0.06
## How deep the collapsed state sits inside the 0.14 m roof slab, and how much
## deeper its eave end sits than its ridge end.
SNOW_REST_SINK = -0.035
SNOW_REST_TILT = -0.055

## How far a block that sits on another one sinks into it.
##
## Not a style choice. Two exactly coplanar faces make a path tracer shadow the
## surface against itself, and the first interior render came back with a
## pure-black floor because the foundation slab's top and the floor's top were
## both at 0.45. Godot will not do that -- a rasteriser z-fights instead, which
## is its own kind of wrong -- so parts overlap by this much and neither
## renderer has a decision to make.
BITE = 0.03

TRIM_Z0, TRIM_Z1 = 3.02, 3.18
TRIM_OUT = 0.05             # how far the trim board stands proud of the siding

PORCH_X0, PORCH_X1 = 0.00, 3.35
PORCH_Y0, PORCH_Y1 = -3.05, 0.00
PORCH_EAVE_Y = -3.25
PORCH_HIGH_Z = 3.35         # where the shed roof meets the house
PORCH_LOW_Z = 2.72          # and where it ends
RAIL_LINE_X = 3.13          # the open right edge
RAIL_LINE_Y = -2.92         # the open front edge
STEP_X0, STEP_X1 = 1.35, 2.25
BALUSTER_STEP = 0.32

# ---------------------------------------------------------------------------
# Scene plumbing
# ---------------------------------------------------------------------------
GROUPS = {}
PART_COUNT = {}
## Per group, the collapsed position of every settled-snow vertex in it, keyed
## by the settled one. Consumed after the join, which is the only moment both
## states and the final vertex indices exist at once.
SNOW_REST = {}
_MATERIALS = {}


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(slot):
    """One Blender material per palette slot, created on first use.

    A `_BARE` suffix is a second material with the same colour, for a part a
    settled mass does not lie on -- see propkit's block above BARE.
    """
    if slot in _MATERIALS:
        return _MATERIALS[slot]
    base = slot[:-len(kit.BARE)] if slot.endswith(kit.BARE) else slot
    if base not in PALETTE:
        raise SystemExit("build_farmhouse: %s is not a palette slot" % slot)
    hexcode = PALETTE[base]
    rgb = [srgb_to_linear(int(hexcode[i:i + 2], 16) / 255.0) for i in (0, 2, 4)]
    mat = bpy.data.materials.new(name=slot)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    # Rule 8 bans specular highlights. Blender renamed this socket across
    # versions, so ask rather than assume -- an unknown name would otherwise
    # leave a highlight in the acceptance renders and nowhere else.
    for name in ("Specular IOR Level", "Specular"):
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = 0.0
    mat.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    _MATERIALS[slot] = mat
    return mat


def emit(name, group, slot, verts, faces):
    """Add one part. Vertices are already in world space -- no object transform
    is ever set, so what the mesh holds is what the exporter writes."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([Vector(v) for v in verts], [], faces)
    mesh.validate()
    mesh.materials.append(material(slot))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    GROUPS.setdefault(group, []).append(obj)
    PART_COUNT[group] = PART_COUNT.get(group, 0) + 1
    return obj


# A unit cube with every face wound counter-clockwise seen from outside, so
# nothing ends up inside-out -- Godot culls back faces, and an inverted part
# does not look wrong, it looks absent.
_CUBE_V = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
           (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
_CUBE_F = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
           (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]


def box(name, group, slot, center, size, rot=(0.0, 0.0, 0.0)):
    """A convex block. 12 triangles. The only shape this building is made of."""
    basis = Euler(rot, "XYZ").to_matrix()
    half = Vector((size[0] / 2.0, size[1] / 2.0, size[2] / 2.0))
    origin = Vector(center)
    verts = [origin + basis @ Vector((v[0] * half.x, v[1] * half.y, v[2] * half.z))
             for v in _CUBE_V]
    return emit(name, group, slot, verts, _CUBE_F)


def block(name, group, slot, x0, x1, y0, y1, z0, z1):
    """A box given by its bounds, which is how walls are easiest to read."""
    return box(name, group, slot,
               ((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0),
               (x1 - x0, y1 - y0, z1 - z0))


def prism_x(name, group, slot, x0, x1, x_apex, z_base, z_apex, y0, y1):
    """A gable end: a triangle in XZ, extruded along Y. 8 triangles."""
    tri = [(x0, z_base), (x1, z_base), (x_apex, z_apex)]
    verts = [(p[0], y0, p[1]) for p in tri] + [(p[0], y1, p[1]) for p in tri]
    faces = [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]
    return emit(name, group, slot, verts, faces)


def prism_y(name, group, slot, y0, y1, y_apex, z_base, z_apex, x0, x1):
    """The same gable end turned ninety degrees: a triangle in YZ, extruded
    along X. The wing's roof runs at a right angle to the main block's, so its
    ends are these."""
    tri = [(y0, z_base), (y1, z_base), (y_apex, z_apex)]
    verts = [(x0, p[0], p[1]) for p in tri] + [(x1, p[0], p[1]) for p in tri]
    faces = [(0, 1, 2), (5, 4, 3), (3, 4, 1, 0), (4, 5, 2, 1), (5, 3, 0, 2)]
    return emit(name, group, slot, verts, faces)


def slope_x(name, group, slot, sign, ridge_x, ridge_z, run, rise,
            y0, y1, thick, d0, d1, lift):
    """A slab lying on a roof plane whose ridge runs along Y.

    `d0`..`d1` are distances measured down the slope from the ridge, so the
    roof plane itself and the snow lying on it are the same call with different
    numbers -- which is the whole point of doing this in a script.
    `lift` offsets the slab along the plane's outward normal.
    """
    ang = math.atan2(rise, run)
    down = Vector((sign * math.cos(ang), 0.0, -math.sin(ang)))
    out = Vector((sign * math.sin(ang), 0.0, math.cos(ang)))
    ridge = Vector((ridge_x, (y0 + y1) / 2.0, ridge_z))
    center = ridge + down * ((d0 + d1) / 2.0) + out * lift
    return box(name, group, slot, center, (d1 - d0, y1 - y0, thick),
               (0.0, sign * ang, 0.0))


def slope_y(name, group, slot, sign, ridge_y, ridge_z, run, rise,
            x0, x1, thick, d0, d1, lift):
    """The same, for a roof whose ridge runs along X."""
    ang = math.atan2(rise, run)
    down = Vector((0.0, sign * math.cos(ang), -math.sin(ang)))
    out = Vector((0.0, sign * math.sin(ang), math.cos(ang)))
    ridge = Vector(((x0 + x1) / 2.0, ridge_y, ridge_z))
    center = ridge + down * ((d0 + d1) / 2.0) + out * lift
    return box(name, group, slot, center, (x1 - x0, d1 - d0, thick),
               (-sign * ang, 0.0, 0.0))


def panel(name, group, slot, axis, at, u0, u1, v0, v1):
    """A flat rectangle. Rule 4: a window is this and nothing else -- no frame
    geometry, no muntins, no reveal. 2 triangles.

    `axis` is the wall's outward direction, one of +x -x +y -y; `at` is where
    the panel sits on that axis; u runs along the wall and v is height.
    """
    if axis in ("+x", "-x"):
        pts = [(at, u0, v0), (at, u1, v0), (at, u1, v1), (at, u0, v1)]
        outward = 1 if axis == "+x" else -1
        if outward < 0:
            pts.reverse()
    else:
        pts = [(u0, at, v0), (u1, at, v0), (u1, at, v1), (u0, at, v1)]
        outward = 1 if axis == "+y" else -1
        if outward > 0:
            pts.reverse()
    return emit(name, group, slot, pts, [(0, 1, 2, 3)])


def window(name, group, axis, at, u_center, u_size, v0, v1, lit=False):
    """A window: a dark or amber pane, and a shallow flat plane behind it for
    the white surround. Two flat rectangles, 4 triangles, no moulding."""
    proud = 0.03 if axis in ("+x", "+y") else -0.03
    u0, u1 = u_center - u_size / 2.0, u_center + u_size / 2.0
    panel(name + "_Surround", group, SURROUND, axis, at + proud * 0.5,
          u0 - 0.11, u1 + 0.11, v0 - 0.11, v1 + 0.11)
    panel(name + "_Pane", group, GLASS_LIT if lit else GLASS_DARK, axis,
          at + proud, u0, u1, v0, v1)


def spike(name, group, slot, x, y, z_top, length, width):
    """An icicle: a tapered four-sided spike. 6 triangles. It exists for the
    silhouette along the porch eave and for nothing else."""
    h = width / 2.0
    verts = [(x - h, y - h, z_top), (x + h, y - h, z_top),
             (x + h, y + h, z_top), (x - h, y + h, z_top),
             (x, y, z_top - length)]
    faces = [(0, 1, 2, 3), (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)]
    return emit(name, group, slot, verts, faces)


# ---------------------------------------------------------------------------
# The building. One line per part.
# ---------------------------------------------------------------------------
SHELL = "FH_Shell"
F_ROOF = "FH_Fade_Roof"
F_FRONT = "FH_Fade_Front"
F_PORCH = "FH_Fade_Porch"
F_LEFT = "FH_Fade_SideLeft"
F_DIVIDER = "FH_Fade_Divider"
F_DOOR = "FH_Door"
PORCH = "FH_Porch"
ROOM = "FH_Room"
FURN = "FH_Furniture"

# The door leaf, and where its hinge is.
#
# Every other object in this build has its origin at the world origin, because
# every vertex is written in world space and no object transform is ever set --
# see emit(). The door is the single exception: its mesh data is shifted so the
# object origin sits on the hinge stile, and the object is then moved back to
# where the mesh was. glTF carries that as a node translation, so in Godot the
# leaf is a node whose local Y rotation swings it about the hinge, and opening
# the door is one property.
#
# Blender +Z is Godot +Y, so a Blender rotation about Z arrives as a Godot
# rotation about Y. Hinged on the LEFT stile looking at the house, opening
# INWARD: a door that opened onto the porch would foul the steps it stands at
# the top of, and would be shut by the first drift against it.
DOOR_X0, DOOR_X1 = 1.30, 2.30
DOOR_HINGE = (DOOR_X0, MAIN_Y0 - 0.04, FLOOR_Z)

## What the interior-reveal system fades when the player crosses the threshold.
## FH_Fade_SideLeft and FH_Fade_Divider are built and named but left out: they
## are opt-in, for a camera that turns out to need them.
# Kept in step with REVEAL_GROUPS in tests/art/test_farmhouse_model.gd and with
# the authored fade_parts on the InteriorReveal in scenes/main.tscn. It is used
# here for nothing but hide_render on the interior acceptance render -- no
# geometry, no material and no export depends on it, so the .glb is unchanged by
# an edit to this line.
DEFAULT_REVEAL = [F_ROOF, F_FRONT, F_PORCH, F_LEFT, F_DIVIDER, F_DOOR]


def build_shell():
    block("Skirt_Main", SHELL, SKIRT, MAIN_X0 - 0.06, MAIN_X1 + 0.06, MAIN_Y0 - 0.06, MAIN_Y1 + 0.06, 0.00, FLOOR_Z - BITE)
    block("Skirt_Wing", SHELL, SKIRT, WING_X0 - 0.06, WING_X1 + 0.06, WING_Y0 - 0.06, MAIN_Y0 - 0.06, 0.00, FLOOR_Z - BITE)
    block("Wall_Back", SHELL, SIDING, MAIN_X0, MAIN_X1, MAIN_Y1 - T, MAIN_Y1, 0.30, MAIN_TOP)
    block("Wall_Right", SHELL, SIDING, MAIN_X1 - T, MAIN_X1, MAIN_Y0, MAIN_Y1, 0.30, MAIN_TOP)
    block("Wall_Left", F_LEFT, SIDING, MAIN_X0, MAIN_X0 + T, MAIN_Y0, MAIN_Y1, 0.30, MAIN_TOP)
    block("Wall_Front_Upper", F_FRONT, SIDING, MAIN_X0, MAIN_X1, MAIN_Y0, MAIN_Y0 + T, CEIL_Z, MAIN_TOP)
    block("Wall_Front_Porch", F_FRONT, SIDING, 0.00, MAIN_X1, MAIN_Y0, MAIN_Y0 + T, 0.30, CEIL_Z)
    # The wall between the two rooms, with a 1.00 x 2.10 doorway through it.
    # Its own group, and deliberately not part of FH_Fade_Front: it is the
    # thing that makes the interior read as *rooms* rather than one shed, so
    # the default reveal keeps it. It is still addressable on its own, because
    # at a steep enough camera it will hide the near third of the main room --
    # at which point adding one string to the fade list is the whole fix.
    block("Wall_Party_Left", F_DIVIDER, SIDING, MAIN_X0, -2.70, MAIN_Y0, MAIN_Y0 + T, 0.30, CEIL_Z)
    block("Wall_Party_Right", F_DIVIDER, SIDING, -1.70, 0.00, MAIN_Y0, MAIN_Y0 + T, 0.30, CEIL_Z)
    block("Wall_Party_Header", F_DIVIDER, SIDING, -2.70, -1.70, MAIN_Y0, MAIN_Y0 + T, 2.55, CEIL_Z)
    prism_x("Gable_Front", F_FRONT, SIDING, MAIN_X0, MAIN_X1, 0.00, MAIN_TOP, MAIN_RIDGE_Z, MAIN_Y0, MAIN_Y0 + T)
    prism_x("Gable_Back", SHELL, SIDING, MAIN_X0, MAIN_X1, 0.00, MAIN_TOP, MAIN_RIDGE_Z, MAIN_Y1 - T, MAIN_Y1)

    block("Wing_Wall_Front", F_FRONT, SIDING, WING_X0, WING_X1, WING_Y0, WING_Y0 + T, 0.30, WING_TOP)
    block("Wing_Wall_Porch", F_FRONT, SIDING, WING_X1 - T, WING_X1, WING_Y0, WING_Y1, 0.30, WING_TOP)
    block("Wing_Wall_Left", F_LEFT, SIDING, WING_X0, WING_X0 + T, WING_Y0, WING_Y1, 0.30, WING_TOP)
    prism_y("Wing_Gable_Left", F_LEFT, SIDING, WING_Y0, WING_Y1, WING_RIDGE_Y, WING_TOP, WING_RIDGE_Z, WING_X0, WING_X0 + T)
    prism_y("Wing_Gable_Porch", F_FRONT, SIDING, WING_Y0, WING_Y1, WING_RIDGE_Y, WING_TOP, WING_RIDGE_Z, WING_X1 - T, WING_X1)


def build_trim():
    """Rule 12's warm quota, spent deliberately: one rust-orange line at the
    ground-floor ceiling, all the way round both blocks."""
    block("Trim_Main_Right", SHELL, TRIM, MAIN_X1 - 0.10, MAIN_X1 + TRIM_OUT, MAIN_Y0 - TRIM_OUT, MAIN_Y1 + TRIM_OUT, TRIM_Z0, TRIM_Z1)
    block("Trim_Main_Back", SHELL, TRIM, MAIN_X0 - TRIM_OUT, MAIN_X1 + TRIM_OUT, MAIN_Y1 - 0.10, MAIN_Y1 + TRIM_OUT, TRIM_Z0, TRIM_Z1)
    block("Trim_Main_Left", F_LEFT, TRIM, MAIN_X0 - TRIM_OUT, MAIN_X0 + 0.10, MAIN_Y0 - TRIM_OUT, MAIN_Y1 + TRIM_OUT, TRIM_Z0, TRIM_Z1)
    block("Trim_Main_Front", F_FRONT, TRIM, 0.00, MAIN_X1 + TRIM_OUT, MAIN_Y0 - TRIM_OUT, MAIN_Y0 + 0.10, TRIM_Z0, TRIM_Z1)
    block("Trim_Wing_Front", F_FRONT, TRIM, WING_X0 - TRIM_OUT, WING_X1 + TRIM_OUT, WING_Y0 - TRIM_OUT, WING_Y0 + 0.10, TRIM_Z0, TRIM_Z1)
    block("Trim_Wing_Porch", F_FRONT, TRIM, WING_X1 - 0.10, WING_X1 + TRIM_OUT, WING_Y0 - TRIM_OUT, WING_Y1, TRIM_Z0, TRIM_Z1)
    block("Trim_Wing_Left", F_LEFT, TRIM, WING_X0 - TRIM_OUT, WING_X0 + 0.10, WING_Y0 - TRIM_OUT, WING_Y1, TRIM_Z0, TRIM_Z1)


def snow_cap(name, group, origin, down, along, d0, d1, a0, a1, edge, spans,
             over=SNOW_OVER, depth=SNOW_DEPTH, roll=SNOW_ROLL):
    """A settled-snow mass over one roof plane. See propkit's `snow_cap` block.

    `edge` is where the leading edge sits, per vertex along the ridge, as a
    fraction of the slope, in the COLLAPSED state -- so the mass creeps down in
    lobes and the lobes close up as it fills. At full settle every one of them is
    at the eave and past it.

    `over` is 0 on a slope that ends against a wall rather than at an eave:
    there is nothing there to hang over.
    """
    settled = kit.snow_cap_state(
        depth=depth, radius=roll, over=over,
        ridge_gap=SNOW_RIDGE_GAP, side=SNOW_OVER, edge=[1.0] * (spans + 1))
    rest = kit.snow_cap_state(
        depth=SNOW_REST_SINK, radius=0.015, over=-0.10,
        ridge_gap=SNOW_RIDGE_GAP + 0.12, side=-0.16, edge=edge,
        tilt=SNOW_REST_TILT)
    if rest["deepest"] >= ROOF_T:
        raise SystemExit("build_farmhouse: %s collapses %.3f m below the plane, "
                         "through a %.3f m roof slab" % (name, rest["deepest"], ROOF_T))
    verts, rest_verts, faces = kit.snow_cap_shape(
        origin, down, along, d0, d1, a0, a1, settled, rest, spans)
    emit(name, group, SNOW, verts, faces)
    SNOW_REST.setdefault(group, {}).update(kit.rest_map(verts, rest_verts))


def build_roof():
    main_run, main_rise = MAIN_X1, MAIN_RISE
    main_len = math.hypot(main_run, main_rise)
    main_ang = math.atan2(main_rise, main_run)
    for sign, side, lobes in ((1, "Right", (0.58, 0.44, 0.66, 0.50)),
                              (-1, "Left", (0.47, 0.68, 0.42, 0.61))):
        slope_x("Roof_Main_" + side, F_ROOF, ROOF_BARE, sign, 0.0, MAIN_RIDGE_Z,
                main_run, main_rise, MAIN_Y0 - VERGE, MAIN_Y1 + VERGE,
                ROOF_T, -0.08, main_len + EAVE, -ROOF_T / 2.0)
        snow_cap(
            "Snow_Main_" + side, F_ROOF,
            (0.0, 0.0, MAIN_RIDGE_Z),
            (sign * math.cos(main_ang), 0.0, -math.sin(main_ang)),
            (0.0, sign, 0.0),
            0.0, main_len + EAVE,
            *((MAIN_Y0 - VERGE, MAIN_Y1 + VERGE) if sign > 0
              else (-MAIN_Y1 - VERGE, -MAIN_Y0 + VERGE)),
            edge=lobes, spans=3)

    wing_run, wing_rise = 1.80, WING_RISE
    wing_len = math.hypot(wing_run, wing_rise)
    wing_ang = math.atan2(wing_rise, wing_run)
    slope_y("Roof_Wing_Front", F_ROOF, ROOF_BARE, -1, WING_RIDGE_Y, WING_RIDGE_Z, wing_run, wing_rise,
            WING_X0 - VERGE, WING_X1 + VERGE, ROOF_T, -0.08, wing_len + EAVE, -ROOF_T / 2.0)
    slope_y("Roof_Wing_Back", F_ROOF, ROOF_BARE, 1, WING_RIDGE_Y, WING_RIDGE_Z, wing_run, wing_rise,
            WING_X0 - VERGE, WING_X1 + VERGE, ROOF_T, -0.08, wing_len, -ROOF_T / 2.0)
    # `along` is -sign on X, so the run along the ridge is measured in the
    # direction that keeps `down x along` pointing out of the roof -- which
    # flips which end of the wing a0 is. propkit refuses a plane whose outward
    # normal comes out pointing down, so this is checked rather than trusted.
    for sign, side, reach, over, lobes in (
        (-1, "Front", wing_len + EAVE, SNOW_OVER, (0.52, 0.45)),
        (1, "Back", wing_len, 0.0, (0.60, 0.43)),
    ):
        snow_cap(
            "Snow_Wing_" + side, F_ROOF,
            (0.0, WING_RIDGE_Y, WING_RIDGE_Z),
            (0.0, sign * math.cos(wing_ang), -math.sin(wing_ang)),
            (-sign, 0.0, 0.0),
            0.0, reach,
            *((WING_X0 - VERGE, WING_X1 + VERGE) if sign < 0
              else (-WING_X1 - VERGE, -WING_X0 + VERGE)),
            edge=lobes, spans=1, over=over)

    build_chimney()

    # The antenna is pure silhouette: thin crossed bars on the ridge.
    block("Antenna_Mast", F_ROOF, ROOF_BARE, -0.03, 0.03, 1.17, 1.23, MAIN_RIDGE_Z - 0.20, MAIN_RIDGE_Z + 1.45)
    block("Antenna_Boom", F_ROOF, ROOF_BARE, -0.03, 0.03, 0.75, 1.85, MAIN_RIDGE_Z + 1.38, MAIN_RIDGE_Z + 1.44)
    for i, (half, y) in enumerate(((0.52, 0.82), (0.44, 1.08), (0.36, 1.34), (0.28, 1.60))):
        block("Antenna_Bar_%d" % (i + 1), F_ROOF, ROOF_BARE, -half, half, y - 0.03, y + 0.03, MAIN_RIDGE_Z + 1.385, MAIN_RIDGE_Z + 1.425)

    block("Ceiling", F_ROOF, INSIDE, MAIN_X0 + T, MAIN_X1 - T, MAIN_Y0 + T, MAIN_Y1 - T, CEIL_Z, CEIL_TOP)


## The chimney straddles the ridge, directly above the stove. It is beacon one
## (GDD section 6): the first warm point in the valley, lit on day one -- so it
## is the one part of this building the player looks at to know the house is
## alive, and until now it was a closed block with a lid on it.
##
##     "屋顶上的烟囱：需要开一个洞 并在洞里出现袅袅炊烟，有烟火气才有生命力"
##
## THE CAP IS OPENED RATHER THAN VENTED UNDER. A real rain-capped chimney lets
## the smoke out of the gap between the shaft and the lid, which is more truthful
## and, at this camera, four pixels of shadow -- the owner asked to see INTO a
## hole. So the lid becomes a RIM: the same slab, the same overhang, with the
## flue cut straight through it.
##
## THE HOLE HAS TO BE A RECESS, NOT A DARK SQUARE. At the game's 45-degree
## camera the near lip occludes the flue's floor for the first
## `FLUE_HALF * 2 / tan(45) = 0.48 m` of depth, so anything shallower than that
## shows its own floor and reads as a painted panel. FLUE_DEPTH is 0.75.
CHIMNEY_X0, CHIMNEY_X1 = -0.45, 0.45
CHIMNEY_Y0, CHIMNEY_Y1 = 4.90, 5.60
CHIMNEY_TOP = 8.40
CAP_Z0, CAP_Z1 = CHIMNEY_TOP - BITE, 8.55
CAP_OUT = 0.10              # how far the rim stands proud of the shaft
FLUE_X0, FLUE_X1 = -0.24, 0.24
FLUE_Y0, FLUE_Y1 = 5.06, 5.44
FLUE_DEPTH = 0.75


def open_box(name, group, slot, x0, x1, y0, y1, z0, z1, inward=False):
    """A box with no top face. Six quads become five.

    `inward` reverses every winding, which is how the flue is built: Godot culls
    back faces, so a shaft you are meant to see the INSIDE of has to be a solid
    turned outside in. There is no other way to get a hole out of convex blocks.
    """
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    faces = [(0, 3, 2, 1), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    if inward:
        faces = [tuple(reversed(f)) for f in faces]
    return emit(name, group, slot, v, faces)


def rim(name, group, slot, ox0, ox1, oy0, oy1, ix0, ix1, iy0, iy1, z0, z1):
    """A flat frame with a rectangular hole: 8 quads, no bottom, no inside."""
    outer = [(ox0, oy0), (ox1, oy0), (ox1, oy1), (ox0, oy1)]
    inner = [(ix0, iy0), (ix1, iy0), (ix1, iy1), (ix0, iy1)]
    v = ([(p[0], p[1], z1) for p in outer] + [(p[0], p[1], z1) for p in inner]
         + [(p[0], p[1], z0) for p in outer])
    faces = []
    for k in range(4):
        n = (k + 1) % 4
        faces.append((k, n, 4 + n, 4 + k))          # the frame's top
        faces.append((k, 8 + k, 8 + n, n))          # its outer wall
    return emit(name, group, slot, v, faces)


def build_chimney():
    # The shaft keeps its top face: the rim sits on it and the flue is sunk
    # through it, so nothing of it is visible from above.
    block("Chimney_Stack", F_ROOF, "PAL_WARM_1",
          CHIMNEY_X0, CHIMNEY_X1, CHIMNEY_Y0, CHIMNEY_Y1, 4.00, CHIMNEY_TOP)

    # The lid, with the flue cut through it. Four bars would have been the
    # obvious build and cost 48 triangles against the slab's 12; this is 16,
    # because the rim needs neither a bottom (it sits on the shaft) nor an
    # inside (the flue below provides its own lining, and that lining runs a
    # BITE proud of the rim's top so there is no seam to catch the light).
    rim("Chimney_Rim", F_ROOF, ROOF,
        CHIMNEY_X0 - CAP_OUT, CHIMNEY_X1 + CAP_OUT,
        CHIMNEY_Y0 - CAP_OUT, CHIMNEY_Y1 + CAP_OUT,
        FLUE_X0, FLUE_X1, FLUE_Y0, FLUE_Y1, CAP_Z0, CAP_Z1)

    # The flue itself, turned outside in so what you see is its lining.
    #
    # ROOF_BARE, and that is the whole of why the mark exists on this building
    # beyond the roof planes: the shaft's FLOOR faces the sky, so the settled
    # snow term would find it and whiten it, and a chimney with a white disc at
    # the bottom of it is not a chimney. The lining is the darkest structure
    # tone, which `CelPainter.shade_for()` clamps to itself -- so the flue is the
    # same near-black in the lit band and the shadow band, at every one of the
    # six lighting presets, and cannot go pale in bright weather.
    open_box("Chimney_Flue", F_ROOF, ROOF_BARE,
             FLUE_X0, FLUE_X1, FLUE_Y0, FLUE_Y1,
             CAP_Z1 - FLUE_DEPTH, CAP_Z1 + BITE, inward=True)


def build_flue_mouth():
    """An empty at the flue's mouth, for whoever hangs the smoke on it.

    A node rather than a documented coordinate, because a coordinate has to be
    copied and a node moves when this script does. It is NOT in any reveal
    group: the groups are meshes the interior reveal fades, and a marker that
    faded would take the smoke with it the moment the player stepped indoors --
    at which point the house is still standing and still lit, seen from outside.

    Blender +Z is Godot +Y, so in Godot this arrives at
    (x, z, -y) = (0.00, 8.55, -5.25).
    """
    mouth = bpy.data.objects.new("Chimney_Flue_Mouth", None)
    mouth.empty_display_type = "PLAIN_AXES"
    mouth.empty_display_size = 0.25
    mouth.location = ((FLUE_X0 + FLUE_X1) / 2.0, (FLUE_Y0 + FLUE_Y1) / 2.0, CAP_Z1)
    bpy.context.scene.collection.objects.link(mouth)
    return mouth


def build_openings():
    for tag, y in (("1", 1.60), ("2", 4.20)):
        window("Win_Left_G" + tag, F_LEFT, "-x", MAIN_X0, y, 1.10, 1.15, 2.45)
        window("Win_Left_U" + tag, F_LEFT, "-x", MAIN_X0, y, 1.00, 3.55, 4.65)
    for tag, y in (("1", 2.20), ("2", 4.60)):
        window("Win_Right_G" + tag, SHELL, "+x", MAIN_X1, y, 1.10, 1.15, 2.45)
        window("Win_Right_U" + tag, SHELL, "+x", MAIN_X1, y, 1.00, 3.55, 4.65)
    window("Win_Back_G1", SHELL, "+y", MAIN_Y1, -1.60, 1.10, 1.15, 2.45)
    window("Win_Back_U1", SHELL, "+y", MAIN_Y1, -1.60, 1.00, 3.55, 4.65)
    window("Win_Front_U1", F_FRONT, "-y", MAIN_Y0, -2.00, 1.00, 3.55, 4.65)
    window("Win_Front_U2", F_FRONT, "-y", MAIN_Y0, 2.00, 1.00, 3.55, 4.65)
    # The one small attic window in the main gable.
    window("Win_Attic", F_FRONT, "-y", MAIN_Y0, 0.00, 0.80, 5.30, 6.00)
    # Two windows are lit. That is the entire warm-window quota for this
    # building: one beside the door, one on the wing's front.
    window("Win_Front_G1", F_FRONT, "-y", MAIN_Y0, 2.90, 1.10, 1.15, 2.45, lit=True)
    window("Win_Wing_F1", F_FRONT, "-y", WING_Y0, -2.55, 1.40, 1.15, 2.55, lit=True)
    window("Win_Wing_F2", F_FRONT, "-y", WING_Y0, -0.90, 1.00, 1.15, 2.45)
    window("Win_Wing_Porch", F_FRONT, "+x", WING_X1, -1.20, 1.00, 1.15, 2.45)
    window("Win_Wing_Left", F_LEFT, "-x", WING_X0, -1.80, 1.00, 1.15, 2.45)

    # The door: 1.00 x 2.10 against a 1.8 m character, under the porch roof.
    #
    # The LEAF is its own group so that it can swing. Everything else in this
    # model is welded into whichever group the reveal does or does not fade,
    # which is right for walls and wrong for the one part that has to move: a
    # door welded into the front facade can only ever be a painted rectangle.
    # The surround stays in the facade -- it is the frame, and frames do not
    # move -- so FH_Door is exactly one quad, 2 triangles, one draw call.
    #
    # DOOR_HINGE below is where its origin ends up, and the whole reason the
    # group exists.
    panel("Door_Surround", F_FRONT, SURROUND, "-y", MAIN_Y0 - 0.02, 1.18, 2.42, FLOOR_Z, 2.67)
    panel("Door_Panel", F_DOOR, SKIRT, "-y", MAIN_Y0 - 0.04, DOOR_X0, DOOR_X1, FLOOR_Z, 2.55)


def build_porch():
    block("Porch_Deck", PORCH, INSIDE, PORCH_X0, PORCH_X1, PORCH_Y0, PORCH_Y1, 0.05, FLOOR_Z)
    for i, (z0, z1, y0) in enumerate(((0.30, 0.45, -3.33), (0.15, 0.30, -3.61), (0.00, 0.15, -3.89))):
        block("Porch_Step_%d" % (3 - i), PORCH, INSIDE, STEP_X0, STEP_X1, y0, PORCH_Y0, z0, z1)

    # Posts 2 and 5 are the NEWELS, one either side of the step opening, and
    # their x values are derived from STEP_X0/STEP_X1 rather than typed.
    #
    # Post 2 used to stand at x = 1.70. The steps run 1.35 .. 2.25 and the door
    # is 1.30 .. 2.30, so 1.70 is the exact centre of the only way in: the post
    # stood in the middle of the top step, dead in front of the door. It read
    # fine in an elevation render and was only obvious once someone walked at
    # it. Moved flush to the left edge of the steps, where it reads as a newel
    # terminating the railing instead of as an obstacle, and a matching one
    # added on the right so the opening is framed rather than merely missing a
    # post. Twelve triangles for the second newel.
    for i, (x, y) in enumerate(((0.22, RAIL_LINE_Y), (STEP_X0 - 0.07, RAIL_LINE_Y),
                                (RAIL_LINE_X, RAIL_LINE_Y), (RAIL_LINE_X, -1.45),
                                (STEP_X1 + 0.07, RAIL_LINE_Y))):
        block("Porch_Post_%d" % (i + 1), F_PORCH, PORCH_PAINT, x - 0.07, x + 0.07, y - 0.07, y + 0.07, FLOOR_Z, 2.88)

    runs = [("Front_A", "x", 0.22, STEP_X0), ("Front_B", "x", STEP_X1, RAIL_LINE_X),
            ("Right", "y", RAIL_LINE_Y, -0.05)]
    balusters = 0
    for name, axis, a0, a1 in runs:
        for tag, z0, z1 in (("Top", 1.27, 1.35), ("Bottom", 0.62, 0.70)):
            if axis == "x":
                block("Porch_Rail_%s_%s" % (name, tag), PORCH, PORCH_PAINT, a0, a1, RAIL_LINE_Y - 0.05, RAIL_LINE_Y + 0.05, z0, z1)
            else:
                block("Porch_Rail_%s_%s" % (name, tag), PORCH, PORCH_PAINT, RAIL_LINE_X - 0.05, RAIL_LINE_X + 0.05, a0, a1, z0, z1)
        span = a1 - a0
        count = max(1, int(span / BALUSTER_STEP))
        for i in range(count):
            at = a0 + span * (i + 0.5) / count
            balusters += 1
            if axis == "x":
                block("Porch_Baluster_%s_%d" % (name, i + 1), PORCH, PORCH_PAINT, at - 0.025, at + 0.025, RAIL_LINE_Y - 0.025, RAIL_LINE_Y + 0.025, FLOOR_Z, 1.30)
            else:
                block("Porch_Baluster_%s_%d" % (name, i + 1), PORCH, PORCH_PAINT, RAIL_LINE_X - 0.025, RAIL_LINE_X + 0.025, at - 0.025, at + 0.025, FLOOR_Z, 1.30)

    run = PORCH_Y1 - PORCH_EAVE_Y
    rise = PORCH_HIGH_Z - PORCH_LOW_Z
    length = math.hypot(run, rise)
    slope_y("Porch_Roof", F_PORCH, ROOF_BARE, -1, PORCH_Y1, PORCH_HIGH_Z, run, rise,
            PORCH_X0 - 0.10, PORCH_X1 + 0.15, 0.12, 0.0, length, -0.06)
    # The mass on the porch roof stops SHORT of the eave even at full settle --
    # `over` is negative. The icicles hang off that eave, and they need a dark
    # strip of roof to hang from or they read as part of the snow rather than as
    # what the snow is dripping into. Shallower than the main roof, too: this
    # plane is 2.4 m long against the main roof's 4.3 and a mass at the house's
    # depth would read as a pillow rather than as a roof.
    porch_ang = math.atan2(rise, run)
    snow_cap(
        "Porch_Roof_Snow", F_PORCH,
        (0.0, PORCH_Y1, PORCH_HIGH_Z),
        (0.0, -math.cos(porch_ang), -math.sin(porch_ang)),
        (1.0, 0.0, 0.0),
        0.0, length,
        PORCH_X0 - 0.05, PORCH_X1 + 0.10,
        edge=(0.48, 0.58), spans=1,
        over=-0.34, depth=0.17, roll=0.14)

    # A row of icicles along the porch eave. Tapered spikes, nothing more.
    for i in range(9):
        x = 0.05 + i * 0.40
        length_i = (0.52, 0.31, 0.44, 0.26, 0.55, 0.34, 0.47, 0.29, 0.38)[i]
        spike("Icicle_%d" % (i + 1), F_PORCH, ICE, x, PORCH_EAVE_Y + 0.02, PORCH_LOW_Z - 0.02, length_i, 0.075)
    return balusters


def build_interior():
    """Two rooms, laid out for what the GDD says the player actually does at
    home (sections 5 and 6): tend the stove, melt snow, cook, repair gear,
    sleep. The reference interior's kit is kept -- stove, work surface,
    storage -- but each verb gets its own station with clearance around it, and
    repair moves into the wing so the main room stays legible from a camera
    looking down into it.
    """
    block("Floor_Main", ROOM, INSIDE, MAIN_X0 + T, MAIN_X1 - T, MAIN_Y0 + T, MAIN_Y1 - T, 0.30, FLOOR_Z)
    # Runs past the party wall to meet Floor_Main, or the foundation shows
    # through the seam once the roof is off.
    block("Floor_Wing", ROOM, INSIDE, WING_X0 + T, WING_X1 - T, WING_Y0 + T, WING_Y1 + T, 0.30, FLOOR_Z)

    # Heat: the stove, under the chimney. Everything else in the run depends on it.
    block("Stove_Body", FURN, "PAL_STRUCT_4", -0.48, 0.48, 4.98, 5.72, FLOOR_Z, 1.40)
    panel("Stove_Firebox", FURN, GLASS_LIT, "-y", 4.96, -0.22, 0.22, 0.75, 1.07)
    block("Stove_Pipe", FURN, "PAL_STRUCT_4", -0.09, 0.09, 4.96, 5.14, 1.40 - BITE, CEIL_Z)
    block("Stove_Pot", FURN, INSIDE, -0.17, 0.17, 5.18, 5.52, 1.40 - BITE, 1.74)
    block("Wood_Stack", FURN, SKIRT, 0.70, 1.80, 5.12, 5.67, FLOOR_Z, 1.10)
    # Water and food: the counter where snow is melted and meals are made.
    block("Counter_Base", FURN, INSIDE, 2.37, 3.32, 2.75, 4.65, FLOOR_Z, 1.35)
    block("Counter_Bucket", FURN, "PAL_SNOW_4", 2.62, 2.98, 3.35, 3.71, 1.35 - BITE, 1.68)
    # The table.
    block("Table_Top", FURN, INSIDE, -0.25, 1.45, 2.12, 3.07, 1.19, 1.28)
    block("Table_Leg_A", FURN, SKIRT, -0.18, -0.08, 2.20, 3.00, FLOOR_Z, 1.19 + BITE)
    block("Table_Leg_B", FURN, SKIRT, 1.28, 1.38, 2.20, 3.00, FLOOR_Z, 1.19 + BITE)
    block("Stool_A", FURN, SKIRT, 0.40, 0.80, 1.55, 1.95, FLOOR_Z, 0.90)
    block("Stool_B", FURN, SKIRT, 0.40, 0.80, 3.25, 3.65, FLOOR_Z, 0.90)
    # Sleep: the bed advances the day.
    block("Bed_Frame", FURN, SKIRT, -3.32, -2.17, 0.85, 2.90, FLOOR_Z, 0.80)
    block("Bed_Bedding", FURN, "PAL_SNOW_4", -3.27, -2.22, 1.10, 2.85, 0.80 - BITE, 1.02)
    block("Bed_Pillow", FURN, SURROUND, -3.20, -2.30, 0.90, 1.25, 0.80 + BITE, 0.96)
    block("Cabinet", FURN, INSIDE, -3.20, -1.90, 5.12, 5.67, FLOOR_Z, 2.10)
    block("Chest", FURN, SKIRT, -3.30, -2.70, 3.45, 4.40, FLOOR_Z, 1.00)
    # Repair: the wing is the workshop and the store.
    block("Bench_Base", FURN, SKIRT, -3.15, -0.65, -3.35, -2.80, FLOOR_Z, 0.90)
    block("Bench_Top", FURN, INSIDE, -3.25, -0.55, -3.42, -2.72, 0.90 - BITE, 1.00)
    block("Shelf_A", FURN, INSIDE, -3.42, -2.97, -2.90, -0.70, 1.90, 1.98)
    block("Shelf_B", FURN, INSIDE, -3.42, -2.97, -2.90, -0.70, 2.45, 2.53)
    block("Crate_A", FURN, SIDING, -1.00, -0.40, -1.05, -0.45, FLOOR_Z, 1.05)
    block("Crate_B", FURN, SIDING, -1.02, -0.47, -1.72, -1.17, FLOOR_Z, 1.00)
    block("Crate_C", FURN, SIDING, -0.97, -0.47, -1.00, -0.50, 1.05 - BITE, 1.55)
    block("Fuel_Drum", FURN, SKIRT, -1.05, -0.55, -2.55, -2.05, FLOOR_Z, 1.30)


# ---------------------------------------------------------------------------
# Finishing
# ---------------------------------------------------------------------------
def project_uvs(obj):
    """One UV unit per metre, projected along each face's dominant axis, so V
    is world height on every vertical face. See the module docstring."""
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


def join_group(name, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    return joined


def set_origin(obj, pivot):
    """Move `obj`'s origin to `pivot` without moving the geometry in the world.

    The mesh data is walked back by the pivot and the object is walked forward
    by the same amount, so the vertices land exactly where they were. Done with
    a data transform rather than bpy.ops.object.origin_set, which needs the 3D
    cursor, a selection and a context, none of which a --background run has
    reliably.
    """
    from mathutils import Matrix

    offset = Vector(pivot)
    obj.data.transform(Matrix.Translation(-offset))
    obj.location = offset
    obj.data.update()
    return obj


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


# ---------------------------------------------------------------------------
# Renders. Built after the export so no camera, light or ground plane can end
# up in the .glb.
# ---------------------------------------------------------------------------
def add_camera(name, target, azimuth, elevation, distance, scale):
    cam_data = bpy.data.cameras.new(name)
    cam_data.type = "ORTHO"          # Art Bible rule 1: the game is orthographic
    cam_data.ortho_scale = scale
    cam = bpy.data.objects.new(name, cam_data)
    az, el = math.radians(azimuth), math.radians(elevation)
    offset = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam.location = Vector(target) + offset * distance
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    return cam


def add_warm_lamp(name, location, energy, radius):
    """The amber inside the house. GDD section 6: on day one the whole valley is
    one lit window, and it is this one."""
    data = bpy.data.lights.new(name, type="POINT")
    data.energy = energy
    data.shadow_soft_size = radius
    data.color = (1.0, 0.66, 0.32)
    lamp = bpy.data.objects.new(name, data)
    lamp.location = location
    bpy.context.scene.collection.objects.link(lamp)
    return lamp


def setup_render_world():
    world = bpy.data.worlds.new("Winter")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    # A blue sky filling the shadows, so the dark band stays blue rather than
    # going grey -- Art Bible section 4.1, in spirit, for a still.
    bg.inputs[0].default_value = (0.28, 0.45, 0.72, 1.0)
    bg.inputs[1].default_value = 0.85
    bpy.context.scene.world = world

    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 4.2
    sun_data.angle = math.radians(2.0)
    sun_data.color = (1.0, 0.95, 0.86)
    sun = bpy.data.objects.new("Sun", sun_data)
    # Low winter sun: rule 10 wants long, soft-edged shadows.
    sun.rotation_euler = Euler((math.radians(72.0), 0.0, math.radians(-38.0)), "XYZ")
    bpy.context.scene.collection.objects.link(sun)

    ground = bpy.data.meshes.new("Ground")
    ground.from_pydata([(-40, -40, 0), (40, -40, 0), (40, 40, 0), (-40, 40, 0)], [], [(0, 1, 2, 3)])
    ground.validate()
    ground.materials.append(material("PAL_SNOW_1"))
    obj = bpy.data.objects.new("Ground", ground)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def render_to(path, camera):
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("build_farmhouse: wrote %s" % path)


def do_renders(directory):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.image_settings.file_format = "PNG"
    # AgX would desaturate the palette into something that is not the palette.
    scene.view_settings.view_transform = "Standard"

    setup_render_world()
    # Reaching out of the two lit windows and the stove door, which is why the
    # porch and the ground in front of it are warm in the exterior view.
    add_warm_lamp("Lamp_Main", (0.4, 3.4, 2.10), 320.0, 1.2)
    add_warm_lamp("Lamp_Wing", (-1.9, -1.9, 2.10), 160.0, 1.0)

    exterior = add_camera("Cam_Exterior", (0.10, 1.20, 3.55), 30.0, 45.0, 40.0, 17.2)
    interior = add_camera("Cam_Interior", (-0.30, 1.40, 1.10), 16.0, 54.0, 40.0, 13.0)
    closeup = add_camera("Cam_Porch", (1.90, -1.50, 1.55), 24.0, 32.0, 40.0, 8.6)

    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    render_to(os.path.join(directory, "farmhouse-exterior.png"), exterior)
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    render_to(os.path.join(directory, "farmhouse-porch.png"), closeup)

    # Hiding exactly the groups the reveal system fades by default is also the
    # cheapest possible test of the naming scheme: if a part is in the wrong
    # group, this render is where it shows.
    for name in DEFAULT_REVEAL:
        for obj in GROUPS[name]:
            obj.hide_render = True
    # The room is lit by its stove and its lamp, not by the sky. Cycles renders
    # the palette's *albedo*, and the structure tones are 2-9% reflective in
    # linear light, so an honestly-exposed interior is black. The game does not
    # have this problem -- its two-band light() picks a brighter palette entry
    # for the lit band rather than multiplying (Art Bible 4.1, briefing trap 7)
    # -- but a still has to be lit to be looked at.
    bpy.data.objects["Lamp_Main"].data.energy = 1500.0
    bpy.data.objects["Lamp_Wing"].data.energy = 650.0
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    render_to(os.path.join(directory, "farmhouse-interior.png"), interior)
    for objects in GROUPS.values():
        for obj in objects:
            obj.hide_render = False


# ---------------------------------------------------------------------------
def argument(flag, default):
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return rest[rest.index(flag) + 1] if flag in rest and rest.index(flag) + 1 < len(rest) else default


def has_flag(flag):
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return flag in rest


def main():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    glb_path = argument("--glb", os.path.join(root, "assets", "models", "buildings", "farmhouse", "farmhouse.glb"))
    blend_path = argument("--blend", os.path.join(root, "assets", "source", "buildings", "farmhouse.blend"))
    render_dir = argument("--renders", os.path.join(root, ".superpowers", "sdd", "wave1"))

    bpy.ops.wm.read_factory_settings(use_empty=True)

    build_shell()
    build_trim()
    build_roof()
    build_openings()
    balusters = build_porch()
    build_interior()
    # After every part, and outside GROUPS: it is an empty, so it joins nothing
    # and is counted in no budget.
    build_flue_mouth()

    parts = sum(PART_COUNT.values())
    order = [SHELL, F_ROOF, F_FRONT, F_PORCH, F_LEFT, F_DIVIDER, F_DOOR, PORCH, ROOM, FURN]
    joined = [join_group(name, GROUPS[name]) for name in order]
    for obj in joined:
        project_uvs(obj)
    # After the UVs, never before, for two different reasons. project_uvs reads
    # vertex coordinates as world metres, so moving the door's mesh first would
    # slide its siding stripes; and the snow key SINKS the caps to their
    # collapsed positions, which would put the mass's UVs half a metre inside
    # the roof.
    for name, obj in zip(order, joined):
        key = kit.add_snow_mass_key(obj, SNOW_REST.get(name, {}))
        if key is not None:
            print("build_farmhouse:   %-20s carries '%s' over %d vertices"
                  % (name, key.name, len(SNOW_REST[name])))
    set_origin(GROUPS[F_DOOR][0], DOOR_HINGE)
    GROUPS.clear()
    for obj in joined:
        GROUPS[obj.name] = [obj]

    total = 0
    print("build_farmhouse: %d parts, %d balusters" % (parts, balusters))
    for obj in joined:
        count = triangles(obj)
        total += count
        print("build_farmhouse:   %-20s %5d tris" % (obj.name, count))
    print("build_farmhouse: %d triangles against a %d budget" % (total, TRIANGLE_BUDGET))
    if total > TRIANGLE_BUDGET:
        raise SystemExit("build_farmhouse: %d triangles is over the %d budget" % (total, TRIANGLE_BUDGET))

    for directory in (os.path.dirname(glb_path), os.path.dirname(blend_path), render_dir):
        os.makedirs(directory, exist_ok=True)

    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_apply=False,
        export_normals=True,
        export_texcoords=True,
        export_animations=False,
        # The settled-snow mass. `export_morph_normal` is off by default --
        # see propkit.export_glb() for why it must not be left that way.
        export_morph=True,
        export_morph_normal=True,
    )
    print("build_farmhouse: wrote %s" % glb_path)

    # AFTER the export, and only for the stills: the .glb carries the collapsed
    # state as its base mesh and the settled one as a morph target, which is
    # right for the game and useless to look at -- a render at rest shows a roof
    # with no snow on it, because the mass is inside the roof slab where it
    # belongs at cover 0. The acceptance renders are for judging the settled
    # shape, so they are shot at full settle.
    for obj in joined:
        if obj.data.shape_keys is None:
            continue
        for key in obj.data.shape_keys.key_blocks:
            if key.name == kit.SNOW_MASS_KEY:
                key.value = 1.0

    if not has_flag("--no-render"):
        do_renders(render_dir)

    # Blender's factory default keeps one numbered backup, which would drop a
    # farmhouse.blend1 into the repo next to the file every single run.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print("build_farmhouse: wrote %s" % blend_path)


main()
