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
    "PAL_SNOW_4": "76889F",
    "PAL_SNOW_5": "667890",
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

## ---------------------------------------------------------------------------
## THE SNOW A PART REFUSES, and why it rides in the material NAME
## ---------------------------------------------------------------------------
## `assets/shaders/cel_flat.gdshader` paints a settled mass onto every solid in
## the world that faces the sky, keyed off nothing but the surface normal and one
## world scalar. That is right for a fence rail and a branch and wrong for two
## kinds of surface:
##
##   * a HAIRLINE. The shader's pattern is 1.33 m across; a power wire is one to
##     two pixels at the game camera. A wire cannot carry a pattern, it can only
##     break into dashes, and a wire breaking into dashes reads as a mesh coming
##     apart. Measured: the line goes dotted from cover 0.14.
##   * a ROOF PLANE that has a `snow_cap` on it. Two white things on one roof is
##     the fault this whole mechanism exists to close -- the cap's silhouette
##     stops reading the moment the plane behind it is white too, and what the
##     eye picks out instead is the cap's stepped edges and cast shadows. The
##     owner's words for it were "the roof resolves into rectangles".
##
## Neither is a fact about a palette COLOUR, so `CelPainter.receptivity_for()`
## cannot express it: the wire, the insulators, the antenna, the roof planes and
## every tree in the wood are all `PAL_STRUCT_4`. It is a fact about the PART.
##
## So the part says so in the one channel this pipeline is already built on --
## **the material name.** `PAL_STRUCT_4` becomes `PAL_STRUCT_4_BARE`, the palette
## resolves it to exactly the same colour (`palette_import_materials.gd` reads
## the digits and stops at the underscore), and `CelPainter` gives it
## `snow_receptivity = 0`. No new channel, no new gate, and a name is the thing
## the docstring above already calls the contract.
##
## WHY NOT VERTEX COLOUR, which is where this started. It works -- until it
## doesn't. Measured on Blender 5.2 exporting this very building: a mark of 0
## written to every vertex of a part survived `join()` intact (dumped from
## Blender immediately before the export call, values `[0.0, 1.0]`), and came out
## of the .glb as **all white** for every primitive in which the mark was
## UNIFORM, while surviving correctly in the one primitive where black and white
## vertices were mixed. Two primitives of `FH_Fade_Porch` lost it; the mixed one
## in `FH_Fade_Roof` kept it. So the exporter is entitled to rewrite a constant
## colour attribute, and a data channel an exporter may optimise is not a data
## channel. A material name it will not touch.
BARE = "_BARE"


def bare(slot):
    """The same palette slot, for a part a settled mass does not lie on."""
    return slot + BARE


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
    """One Blender material per palette slot, created on first use.

    A `_BARE` suffix is a different material with the same colour -- see the
    block above BARE. It has to be a separate material because that is the only
    way one part of a joined mesh can carry a property another part does not.
    """
    if slot in _MATERIALS:
        return _MATERIALS[slot]
    base = slot[:-len(BARE)] if slot.endswith(BARE) else slot
    if base not in PALETTE:
        raise SystemExit("propkit: %s is not a palette slot" % slot)
    hexcode = PALETTE[base]
    rgb = [srgb_to_linear(int(hexcode[i:i + 2], 16) / 255.0) for i in (0, 2, 4)]
    mat = bpy.data.materials.new(name=slot)
    mat.use_nodes = True
    bsdf = next(
        node for node in mat.node_tree.nodes
        if node.type == "BSDF_PRINCIPLED"
    )
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


# ---------------------------------------------------------------------------
# SETTLED SNOW -- the mass that lies on a roof
# ---------------------------------------------------------------------------
# **Roof snow and body snow are different materials and must not share a look.**
# Write that down here, because it is the thing somebody will flatten later.
#
#   * BODY snow is powder caught in cloth. Noise-broken patches with ragged
#     edges. That is `src/entities/snow_load.gd` and its crust shader, and it is
#     correct there.
#   * ROOF snow is a settled MASS. It slumps under its own weight, its edges
#     roll off and bulge, and it reads smooth and swelling -- the opposite of
#     ragged. At every boundary it shows a CROSS-SECTION, and that cross-section
#     is where the thickness lives. At an eave it overhangs.
#
# A noise threshold cannot draw the second one. A threshold has no thickness: it
# can only decide, per pixel, which side of a line the pixel is on, and both
# sides are the same flat plane. The roof snow that shipped before this was ten
# flat 0.17 m slabs of it, and the day the shader learned to whiten the roof
# plane behind them their silhouettes stopped reading -- what the eye picked out
# instead was their cast shadows and their stepped edges, which is a roof that
# looks like it is coming apart.
#
# So the mass is GEOMETRY, and the arc at its edge is a real silhouette:
#
#       ridge                                              eave
#   ______________________________________
#  /  top face, `depth` above the plane    \___
# |                                            \__      <- the roll, bulging
# |                                               |        outward, widest near
# =================================================        its base
#                                        |<- over ->|
#
# WHY IT IS NOT GROWN BY DISPLACING THE ROOF'S OWN VERTICES. Every model in this
# project is split-vertex flat-shaded, so pushing a shared corner along "the"
# normal tears every hard edge it belongs to. This is a SEPARATELY GENERATED
# SHELL -- its own closed solid, its own vertices -- so nothing it does can crack
# the roof it lies on.
#
# WHY IT GROWS AT ALL, and this is the part that is not optional. A cap authored
# at one fixed size is a white shape that is there from the first frame, on a
# roof whose own coverage moves all week: exactly the fault above, rebuilt. So
# the cap is authored TWICE -- collapsed and settled -- and shipped as a blend
# shape named `snow_mass`. `src/rendering/cel_painter.gd` drives it from the same
# world scalar that drives everything else, so the mass thickens, its leading
# edge creeps down the slope, and its lip finally rolls out past the eave, all as
# one continuous function of the weather. Collapsed, it is a small well-formed
# slab sunk inside the roof solid: invisible, and with its normals still pointing
# the way the settled one's do, so the half-blended state is not half nonsense.
SNOW_MASS_KEY = "snow_mass"

## The roll, in six rings. `(inset, drop)` are fractions of the rim radius:
## inset from the cap's outer extent, drop below the top face. The arc is swept
## from 0 through 110 degrees, then the base tucks back under. Five curved
## Four curved facets are enough for a smooth game-camera silhouette while preserving the
## project's deliberately faceted low-poly lighting.
##
## **PAST 90 DEGREES ON PURPOSE, and this is the difference between reading and
## not reading.** A quarter-round stopping at 90 gives the lip three facets that
## all face upward, and the game's camera looks DOWN at 45 degrees -- so all
## three land in the same band of a two-band cel light and the roll comes out as
## a flat extension of the top face with no cross-section at all. Measured at the
## eave, at game framing, before this changed: one tone across the whole lip.
##
## Carrying the last facet to 110 gives it a normal that is horizontal and
## slightly undercut, so it is a genuinely different surface from the top -- it
## takes its own Lambert, it can fall into the shadow band, and it is the
## CROSS-SECTION the thickness is read from. It also puts the widest point of the
## bulge just below the roof plane, which is where surface tension puts it: a
## settled mass is fattest near its base and rolls under at the very edge.
##
## Five segments and no more. The added shoulder facets are silhouette geometry,
## not extra colour bands: together they make the edge read as cohesive surface
## tension rather than a stack of planar shelves. More would land inside the
## same cel bands and spend triangles without changing the edge the player sees.
_CAP_RINGS = (
    (1.00000, 0.00000),
    (0.65798, 0.06031),   # 20 degrees
    (0.29289, 0.29289),   # 45 degrees
    (0.03407, 0.74118),   # 75 degrees -- widest shoulder
    (0.06031, 1.34202),   # 110 -- horizontal and past it, the undercut
    (1.00000, None),      # the base: `base` height rather than a drop
)


def snow_cap_state(depth, radius, over, ridge_gap, side, edge, base=None, tilt=0.0):
    """One end of the mass's travel.

    depth      how far the top face stands off the roof plane
    radius     the rim's radius -- how far in from the outer extent the top
               face stops, and how far the roll bulges out past it
    over       how far past the eave the outer extent reaches
    ridge_gap  how far DOWN-slope of the ridge the cap starts. Positive leaves a
               dark line along the ridge, which Art Bible rule 10 wants kept.
    side       how far past the verges the outer extent reaches
    edge       `spans + 1` fractions of the slope, one per vertex along the eave
               edge: where the leading edge sits. Authored rather than derived,
               so a partly-settled mass creeps down in lobes instead of as a
               ruled line, and the lobes close up as it fills.
    base       where the underside sits, relative to the roof plane. Derived by
               default, and derived rather than typed because the arc now sweeps
               PAST horizontal: its lowest ring is below the top face by
               1.342 * radius, and a base typed above that turns the last band of
               faces inside out. `_check_outward` catches it, but only after
               somebody has typed a number and re-run Blender -- so the number
               computes itself and the caller says how thick the mass is instead.
    tilt       extra height added at the eave end and none at the ridge. Negative
               on the collapsed state so the mass emerges from the ridge downward
               rather than surfacing all at once -- two planes crossing over the
               whole of a roof in one frame is a z-fight, and it would be the one
               frame somebody screenshots.
    """
    lowest = depth - _CAP_RINGS[-2][1] * radius
    if base is None:
        base = lowest - max(0.02, radius * 0.3)
    elif base >= lowest:
        raise SystemExit("propkit: a snow cap's base at %.3f is not below its "
                         "lowest arc ring at %.3f" % (base, lowest))
    return {
        "depth": depth, "radius": radius, "over": over, "ridge_gap": ridge_gap,
        "side": side, "edge": tuple(edge), "base": base, "tilt": tilt,
        # How far below the roof plane the whole state reaches, so a caller can
        # check it against the thickness of the slab it has to hide inside.
        "deepest": -(base + min(0.0, tilt)),
    }


def _cap_ring(origin, down, along, out, d0, d1, a0, a1, spans, state, inset, drop):
    """One closed loop of the cap, wound counter-clockwise seen from outside."""
    span_d = d1 - d0
    lo_d = d0 + state["ridge_gap"] + inset
    lo_a = a0 - state["side"] + inset
    hi_a = a1 + state["side"] - inset
    edge = state["edge"]

    def eave(j):
        return d0 + edge[j] * span_d + state["over"] - inset

    def at(d, a):
        height = (state["base"] if drop is None else state["depth"] - drop)
        height += state["tilt"] * (d - d0) / span_d
        return origin + down * d + along * a + out * height

    def across(j):
        return lo_a + (hi_a - lo_a) * j / spans

    points = [at(lo_d, lo_a)]
    for j in range(spans + 1):
        points.append(at(eave(j), across(j)))
    points.append(at(lo_d, hi_a))
    for j in range(spans - 1, 0, -1):
        points.append(at(lo_d, across(j)))
    return points


def snow_cap_shape(origin, down, along, d0, d1, a0, a1, settled, rest, spans=1):
    """(settled vertices, collapsed vertices, faces) for one roof plane's mass.

    `origin` is a point on the ridge line, `down` runs down the slope and `along`
    runs down the ridge; `d0..d1` is the slope's extent measured from `origin`
    and `a0..a1` the run along the ridge. The outward normal is `down x along`,
    which is checked rather than assumed -- a cap wound inside-out does not look
    wrong, it looks absent.
    """
    down = Vector(down).normalized()
    along = Vector(along).normalized()
    out = down.cross(along)
    if out.z <= 0.0:
        raise SystemExit("propkit: snow_cap_shape got a plane whose outward "
                         "normal points down -- swap the sign of `along`")

    verts = {"settled": [], "rest": []}
    for key, state in (("settled", settled), ("rest", rest)):
        for inset_f, drop_f in _CAP_RINGS:
            verts[key] += _cap_ring(
                Vector(origin), down, along, out, d0, d1, a0, a1, spans, state,
                inset_f * state["radius"],
                None if drop_f is None else drop_f * state["radius"])

    ring = 2 * spans + 2
    faces = [tuple(range(ring))]
    for k in range(len(_CAP_RINGS) - 1):
        for i in range(ring):
            j = (i + 1) % ring
            faces.append((k * ring + i, (k + 1) * ring + i,
                          (k + 1) * ring + j, k * ring + j))
    # NO BOTTOM FACE, for the same reason `tube()` has no end caps: the base
    # ring is tucked a rim radius back inside the roof's own outline and sits
    # `base` below the plane, so it is enclosed by the roof slab and there is no
    # angle from which the hole can be seen. On the hero building that is 24
    # triangles of a 1500 budget spent on nothing.
    _check_outward(verts["settled"], faces)
    _check_outward(verts["rest"], faces)
    return verts["settled"], verts["rest"], faces


def _check_outward(verts, faces):
    """Every face wound so its normal leaves the solid.

    Worth the six lines because of how this fails: Godot culls back faces, so a
    cap wound inside-out does not look wrong, it looks ABSENT -- and the two
    states are built by the same code from different numbers, so one of them
    flipping while the other does not is a thing that can happen.
    """
    centre = sum(verts, Vector((0.0, 0.0, 0.0))) / len(verts)
    for face in faces:
        a, b, c = verts[face[0]], verts[face[1]], verts[face[2]]
        normal = (b - a).cross(c - a)
        if normal.dot(a - centre) <= 0.0:
            raise SystemExit("propkit: a snow cap face is wound inside out")


def add_snow_mass_key(obj, rest_by_point):
    """Ship the settled state as a blend shape and sink the mesh to its rest.

    `rest_by_point` maps a rounded settled position to its collapsed position.
    Matched by POSITION rather than by index because the caps have been through
    `join()` by then and a join concatenates in an order nobody should depend on;
    the count is asserted, so a miss is a build failure with a number on it
    rather than a cap that never grows.
    """
    if not rest_by_point:
        return None
    mesh = obj.data
    obj.shape_key_add(name="Basis", from_mix=False)
    key = obj.shape_key_add(name=SNOW_MASS_KEY, from_mix=False)
    basis = obj.data.shape_keys.key_blocks["Basis"]
    matched = 0
    for index, vertex in enumerate(mesh.vertices):
        found = rest_by_point.get(_point_key(vertex.co))
        if found is None:
            continue
        key.data[index].co = Vector(vertex.co)
        basis.data[index].co = Vector(found)
        vertex.co = Vector(found)
        matched += 1
    if matched != len(rest_by_point):
        raise SystemExit("propkit: %s matched %d of %d snow-cap vertices"
                         % (obj.name, matched, len(rest_by_point)))
    mesh.update()
    return key


def _point_key(point):
    return (round(point[0], 5), round(point[1], 5), round(point[2], 5))


def rest_map(settled, rest):
    """The position map `add_snow_mass_key` wants, for one cap."""
    return dict(zip((_point_key(p) for p in settled), rest))


def snow_cap(name, origin, down, along, d0, d1, a0, a1, settled, rest, spans=1):
    """A settled-snow cap as a prop part, returning its rest-position map."""
    verts, rest_verts, faces = snow_cap_shape(
        origin, down, along, d0, d1, a0, a1, settled, rest, spans)
    emit(name, SNOW, verts, faces)
    return rest_map(verts, rest_verts)


def gable_cap(name, sign, ridge_z, run, rise, x0, x1, reach, edge,
              depth, over, sink, roof_t, spans=1, ridge_y=0.0):
    """The settled mass over one plane of a `slope_y` gable roof.

    The outbuildings' roofs are all this shape, so their build scripts are two
    calls rather than two copies of the reasoning.

    `sink` is how far below the roof plane the COLLAPSED state's ridge end sits.
    It has to be less than the slab is thick or the mass is visible at cover 0,
    which is checked here rather than looked for in a frame. The eave end sits
    deeper again, so the mass emerges from the ridge downward instead of
    surfacing all at once -- a whole roof plane crossing another in one frame is
    a z-fight, and it would be the frame somebody screenshots.
    """
    roll = depth * 0.8
    angle = math.atan2(rise, run)
    settled = snow_cap_state(depth=depth, radius=roll, over=over,
                             ridge_gap=depth * 0.3, side=over,
                             edge=[1.0] * (spans + 1))
    rest = snow_cap_state(depth=-sink, radius=roll * 0.15, over=-roll * 0.6,
                          ridge_gap=depth * 0.3 + roll, side=-roll * 0.9,
                          edge=edge, tilt=-sink * 1.1)
    if rest["deepest"] >= roof_t:
        raise SystemExit("propkit: %s collapses %.3f m below the plane, which is "
                         "through a %.3f m roof slab -- it would be visible at "
                         "cover 0" % (name, rest["deepest"], roof_t))
    return snow_cap(
        name, (0.0, ridge_y, ridge_z),
        (0.0, sign * math.cos(angle), -math.sin(angle)), (-sign, 0.0, 0.0),
        0.0, reach,
        *((x0, x1) if sign < 0 else (-x1, -x0)),
        settled=settled, rest=rest, spans=spans)


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
        # The settled-snow mass. `export_morph_normal` is OFF by default -- the
        # exporter will not compute morph normals unasked -- and without it a
        # half-settled cap is lit by the collapsed state's normals.
        export_morph=True,
        export_morph_normal=True,
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
    bg = next(
        node for node in world.node_tree.nodes
        if node.type == "BACKGROUND"
    )
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
