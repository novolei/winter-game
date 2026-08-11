"""Render the whole farmstead in one frame, from the exported .glb files.

This is the acceptance image. Every other render in this wave shows one asset
against a 1.8 m figure and answers "is this the right shape and the right size";
this one answers the only question that matters, which is **whether the set of
them, together, reads like `Refs/game ref/level.jpg`**.

It is deliberately built from the exported `.glb` files rather than by calling
the build scripts again, so it is also the cheapest possible end-to-end check of
the exports: a model that failed to write, exported inside-out, or came out at
the wrong scale shows up here and nowhere else in this wave.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/render_farmstead.py

Optional arguments after `--`: `--models <dir>`, `--out <png>`.

Nothing here is placement. `scenes/main.tscn` belongs to another task and this
script does not touch it or write anything a scene could read; the layout below
exists to make one picture and says nothing about where these things go in the
game.
"""

import math
import os
import sys

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

import propkit as kit  # noqa: E402


def place(path, x, y, turn=0.0, z=0.0):
    """Import one .glb and stand it at (x, y, z), turned `turn` degrees.

    Two traps here, both silent:

    1. The glTF importer rotates its imports to get from glTF's Y-up to
       Blender's Z-up. That rotation has to be *applied* before anything else is
       set, or writing a rotation throws it away and the model lies on its face.

    2. **The importer leaves every object in QUATERNION rotation mode, and in
       that mode `rotation_euler` is written, stored, and then ignored.** No
       error, no warning: the assignment simply does nothing. The first version
       of this script set `turn` on every prop and strung three wires by
       direction, and every one of them came out unrotated -- which looked like
       a slightly dull layout rather than like a bug. It was caught by printing
       a wire's world bounding box and finding it running along +Y from its own
       start point instead of towards the pole it was supposed to reach.
    """
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    made = [o for o in bpy.data.objects if o not in before]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in made:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = made[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")
    root = [o for o in made if o.parent is None][0]
    root.rotation_mode = "XYZ"          # see trap 2 above
    root.rotation_euler = Euler((0.0, 0.0, math.radians(turn)), "XYZ")
    root.location = Vector((x, y, z))
    return root


def string_wire(path, a, b):
    """One wire between two tie points. The model is 1 m long along +Y, so this
    is: stand it at `a`, aim +Y at `b`, scale Y by the span."""
    root = place(path, a[0], a[1], 0.0, a[2])
    span = Vector(b) - Vector(a)
    root.rotation_euler = span.to_track_quat("Y", "Z").to_euler()
    root.scale.y = span.length
    return root


def main():
    root_dir = kit.project_root()
    models = kit.argument("--models", os.path.join(root_dir, "assets", "models"))
    out = kit.argument("--out", os.path.join(
        root_dir, ".superpowers", "sdd", "wave1", "prop-farmstead.png"))

    props = os.path.join(models, "props")
    buildings = os.path.join(models, "buildings")
    veg = os.path.join(models, "vegetation")
    wire = os.path.join(props, "power_wire.glb")

    kit.reset()

    # The farmhouse is the fixed point: it was built by another task at the
    # scale everything here was matched to, and if these props are wrong beside
    # it that is the finding.
    place(os.path.join(buildings, "farmhouse", "farmhouse.glb"), 0.0, 0.0)

    # Roughly the reference's arrangement: house centre, truck and shed to the
    # left, well house alone in the middle distance, poles marching off to the
    # right, and the yard tree over the house's shoulder with the swing on it.
    tree_a = (9.4, -3.2)
    place(os.path.join(veg, "tree_bare_a.glb"), tree_a[0], tree_a[1])
    # The swing hangs from tree A's low limb, at the anchor build_trees.py
    # prints. Not a guess and not a nudge: the same number, used.
    place(os.path.join(props, "tire_swing.glb"),
          tree_a[0] - 1.90, tree_a[1] + 0.14, 0.0, 2.80)
    place(os.path.join(veg, "tree_bare_b.glb"), -16.5, 12.5)
    place(os.path.join(veg, "tree_bare_c.glb"), 15.5, 7.5)

    place(os.path.join(props, "pickup_truck.glb"), -7.4, 0.4, 24.0)
    place(os.path.join(buildings, "tool_shed", "tool_shed.glb"), -12.0, 6.6, 18.0)
    # Alone in open snow with nothing near it, which is where the reference puts
    # it and the only place its shadow is the point.
    place(os.path.join(buildings, "well_house", "well_house.glb"), -10.4, -3.0, -28.0)

    # Two poles and the line between them: rule 11's long line across the frame.
    pole_a, pole_b = (7.6, 13.0), (16.6, 22.4)
    place(os.path.join(props, "power_pole.glb"), pole_a[0], pole_a[1])
    place(os.path.join(props, "power_pole.glb"), pole_b[0], pole_b[1])
    for dx in (-1.0, 1.0):
        string_wire(wire, (pole_a[0] + dx, pole_a[1], 8.06),
                    (pole_b[0] + dx, pole_b[1], 8.06))
    # ...and the service drop to the house, which is the line the reference runs
    # right across the middle of the picture.
    string_wire(wire, (pole_a[0] + 0.34, pole_a[1], 5.30), (2.9, 4.6, 5.05))

    kit.render_settings(samples=96, resolution=(1900, 1200))
    kit.setup_world()
    # Two of them, and both standing on open snow rather than tucked behind the
    # house: a scale figure nobody can see proves nothing.
    kit.scale_figure(5.2, -6.6, math.radians(150.0))
    kit.scale_figure(-7.6, 9.4, math.radians(-40.0))
    kit.render_to(out, kit.camera("Cam", (1.6, 6.2, 3.0), 30.0, 45.0, 90.0, 46.0))


main()
