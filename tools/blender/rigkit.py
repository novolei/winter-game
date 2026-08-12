"""Shared plumbing for the skinned characters, the way propkit.py is for props.

`propkit` builds world geometry out of boxes and paints it from the 12-colour
table. Nothing in it applies to a character: characters arrive as somebody
else's FBX, they carry a rig and dozens of takes, and the Art Bible's exception
box lets them keep their own maps. This module is the other half of the asset
pipeline -- import, budget, merge takes, export -- and the two share nothing but
`kit.project_root()` and the render helpers.

Everything here is deliberately about *files*, not about behaviour. Naming takes
for what the motion is, wiring a state machine, deciding which clip loops: none
of that is here, because none of it is knowable without the game code that will
play them.

---------------------------------------------------------------------------
THE TWO TRAPS THIS MODULE EXISTS TO CONTAIN
---------------------------------------------------------------------------
**1. An action loose in `bpy.data` does not export.** The glTF exporter walks
what the scene refers to. Blender's FBX importer stashes every take of a
multi-take file into a muted NLA track, which is why all 81 of the bear's come
out the other side -- and why a take merged in from a second file has to be
stashed the same way rather than merely renamed. `merge_take()` does that.

**2. Merging a Mixamo take drags a whole second character in behind it.** Each
`Ch05_nonPBR@*.fbx` is 115 MB because it carries a full copy of the mesh, the
rig, and twelve 4K maps alongside its one animation. Import five of those and
the scene holds five meshes, five armatures and sixty textures -- most of them
orphaned but all of them resident, which is gigabytes -- and whichever ones the
exporter can still see land in the `.glb`. `merge_take()` snapshots every
datablock collection before the import and removes everything new except the
action itself.
"""

import os
import sys

sys.dont_write_bytecode = True

import bpy  # noqa: E402

# Every collection a character FBX can add to. Purging is done by name against a
# snapshot rather than by `orphans_purge`, which needs an outliner context that
# does not exist under --background.
_COLLECTIONS = ("objects", "meshes", "armatures", "materials", "images", "actions")


# ---------------------------------------------------------------------------
# Import
# ---------------------------------------------------------------------------
def import_fbx(path):
    """Import through whichever FBX operator this Blender build ships.

    5.x moved to a built-in `wm.fbx_import`; the Python `io_scene_fbx` add-on is
    still there in some builds and is not in others. Ask rather than assume --
    the same check `tools/decimate_character.py` makes, for the same reason.
    """
    if not os.path.exists(path):
        raise SystemExit("rigkit: no such file: %s" % path)
    if hasattr(bpy.ops.wm, "fbx_import"):
        bpy.ops.wm.fbx_import(filepath=path)
        return
    bpy.ops.import_scene.fbx(filepath=path)


def meshes():
    return [obj for obj in bpy.data.objects if obj.type == "MESH"]


def armature():
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE":
            return obj
    return None


def drop_empties():
    """Remove the childless nulls. Leave anything with a child alone.

    The bear's source carries ten locators marking bone tips (`RigTail2_end`)
    that hold nothing and export as unexplained nodes. Those go.

    ---------------------------------------------------------------------
    AND A WRAPPER NULL STAYS, WHICH COST A REBUILD TO LEARN
    ---------------------------------------------------------------------
    That same file has a null named `Bear_Animated` with the whole rig under
    it, and flattening it looked free: it would put the skeleton at
    `Armature/Skeleton3D` in Godot, the same path the player's takes already
    address, instead of one level deeper. So the first version of this function
    re-parented the children with `CLEAR_KEEP_TRANSFORM` and deleted it.

    **The bear came into Blender eighty-five times too big and nothing said so.**

    The source's transforms are nested garbage that happens to cancel:

        Bear_Animated  EMPTY     scale (0.0117, 0.0111, 0.0117)
        RigRoot        ARMATURE  scale (1, 1, 1)
        sm_3_0_0       MESH      scale (82.2, 90.5, 82.2)     -> net ~1.0

    `CLEAR_KEEP_TRANSFORM` is faithful and that is the problem: it composes the
    null's rotation with its **non-uniform** scale onto the armature, and a
    rotation times a non-uniform scale is a *shear*. glTF nodes carry
    translation, rotation and scale and cannot express shear at all, so the
    exporter dropped the 0.0117 rather than writing something it could not
    represent -- leaving the joints in the file's centimetres with a node scale
    of 1.

    Nothing errors. The `.glb` is valid, the mesh is right, the takes are right,
    and the bear is 225 m tall. On a wrapper node with no skin attached the same
    matrix exports fine, because only *skinned* geometry makes the exporter
    reconcile the two.

    The zombie has no wrapper and a clean uniform 0.01 on its armature, which is
    why it round-tripped correctly and made the bear look like a one-off.
    """
    for obj in list(bpy.data.objects):
        if obj.type != "EMPTY" or obj.children:
            continue
        print("rigkit: dropped empty %r" % obj.name)
        bpy.data.objects.remove(obj, do_unlink=True)


# ---------------------------------------------------------------------------
# Budget
# ---------------------------------------------------------------------------
def triangle_count(objects):
    total = 0
    for obj in objects:
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


def decimate_to(objects, target):
    """Collapse every mesh by one shared ratio so it lands near `target`.

    One ratio across all meshes rather than one each, so a model split into a
    body and a head does not come back with the head five times denser than the
    body. The ratio is `target / total`, which is exact only if the decimator
    hits it; it does not, so callers report the measured result rather than the
    request.

    The modifier is moved to the top of the stack before it is applied. Vertex
    weights survive a collapse and the rig still drives the mesh afterwards --
    but only when the decimate runs before the armature deform. Applying it out
    of order works and warns, and a warning in this project's console is a
    failed run.
    """
    total = triangle_count(objects)
    if total <= target:
        print("rigkit: %d triangles already at or under %d, not decimating" % (total, target))
        return
    ratio = min(1.0, float(target) / float(total))
    for obj in objects:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        modifier = obj.modifiers.new(name="Budget", type="DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = ratio
        while obj.modifiers.find("Budget") > 0:
            bpy.ops.object.modifier_move_up(modifier="Budget")
        bpy.ops.object.modifier_apply(modifier="Budget")
        obj.select_set(False)


def dimensions(objects):
    """(x, y, z) extent over every mesh, in the file's own units.

    Reported rather than corrected. The player model is in centimetres and the
    game scales it at load (`player_controller._scale_to_body_height`), so
    normalising here would make these two characters disagree about their own
    units for no gain.
    """
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ _vector(corner)
            for axis in range(3):
                lo[axis] = min(lo[axis], world[axis])
                hi[axis] = max(hi[axis], world[axis])
    return tuple(round(hi[a] - lo[a], 3) for a in range(3))


def _vector(triple):
    from mathutils import Vector
    return Vector(triple)


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
# The exception box in Art Bible section 2 lets a character keep its own maps, so
# nothing here removes a texture. What it does remove is the *specular
# workflow* these assets were authored for: both sources predate PBR --
# `a_c_bear_01_*` is a Unity asset and `Ch05_nonPBR` says so in its own name --
# and their Specular and Glossiness maps have no slot in glTF. Blender's
# importer wires them into Roughness and Specular IOR Level anyway, the glTF
# exporter then bakes a metallic-roughness texture out of them, and what arrives
# in Godot is a shiny bear.
#
# Rule 8 bans specular highlights across the whole game and the exception box is
# about *colour*, not about gloss. Flat, rough, non-metal is what fur and a
# canvas coat are.
_MATTE = {"Metallic": 0.0, "Roughness": 0.92, "Specular IOR Level": 0.0, "Specular": 0.0}

# Sockets whose incoming links carry the surface itself and must survive.
_KEEP_LINKED = ("Base Color", "Normal", "Alpha")


def make_matte(objects):
    """Keep Base Color, Normal and Alpha. Disconnect everything else.

    A whitelist rather than a list of sockets to clear, and that is the whole
    lesson of the first version of this function. It named the sockets it knew
    about -- Metallic, Roughness, `Specular IOR Level` -- and Blender's FBX
    importer had wired the Specular map into **Specular Tint**, which was not on
    the list. Nothing errored. The map stayed connected, the glTF exporter wrote
    a `KHR_materials_specular` extension with a `specularColorTexture` behind
    it, and the scavenger shipped three specular maps it is not supposed to have
    plus 1.9 MB of file to carry them.

    The failure mode is the one this project keeps meeting: not a wrong answer,
    a question never asked. A whitelist cannot go stale when Blender renames or
    adds a socket, because a socket nobody named is disconnected rather than
    quietly kept.

    A default_value written to a *linked* socket is stored and silently ignored,
    so the links have to go before the values are set, not after.
    """
    for material in _materials_of(objects):
        node = _principled(material)
        if node is None:
            continue
        for socket in node.inputs:
            if socket.name in _KEEP_LINKED:
                continue
            for link in list(socket.links):
                print("rigkit: %s.%s <- %s disconnected"
                      % (material.name, socket.name, link.from_node.name))
                material.node_tree.links.remove(link)
        for name, value in _MATTE.items():
            if name in node.inputs:
                node.inputs[name].default_value = value


def report_materials(objects):
    for material in _materials_of(objects):
        node = _principled(material)
        images = []
        if node is not None:
            for socket in _KEEP_LINKED:
                if socket not in node.inputs:
                    continue
                for image in _images_behind(node.inputs[socket]):
                    images.append("%s<-%s %dx%d" % (socket, image.name, image.size[0], image.size[1]))
        print("rigkit: material %-16s %s" % (material.name, images or "no maps"))


def downscale_images(limit):
    """Cap every image at `limit` on its long edge.

    Mixamo ships twelve 4096-square maps with a 47,000 triangle mesh, which is
    where 115 MB per file comes from. At the game's framing a character is about
    11% of the screen height (Art Bible rule 1) -- roughly 120 px on a 1080p
    display -- so a 4K map is two hundred times more texel than the screen can
    show, and the whole set of them would be a bigger download than every other
    asset in this project put together.

    `Image.scale()` rewrites the pixel buffer and leaves the *packed bytes*
    alone, and the glTF exporter prefers the packed bytes when it can use them.
    Without the re-pack this function measurably does nothing: the `.glb` comes
    out the same size, holding the same 4K maps, and the only symptom is a
    number in a log.
    """
    for image in bpy.data.images:
        width, height = image.size
        if max(width, height) <= limit or width == 0:
            continue
        scale = float(limit) / float(max(width, height))
        target = (max(1, int(round(width * scale))), max(1, int(round(height * scale))))
        image.scale(target[0], target[1])
        image.pack()
        print("rigkit: scaled %s %dx%d -> %dx%d" % (image.name, width, height, target[0], target[1]))


def _materials_of(objects):
    seen = []
    for obj in objects:
        for material in obj.data.materials:
            if material is not None and material not in seen:
                seen.append(material)
    return seen


def _principled(material):
    if material.node_tree is None:
        return None
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            return node
    return None


def _images_behind(socket, depth=0):
    """Every image feeding `socket`, following one or two nodes back.

    A normal map arrives as Image -> Normal Map -> Normal, so a check that only
    looks at the socket's immediate neighbour reports a character with a normal
    map as having none.
    """
    found = []
    if depth > 3:
        return found
    for link in socket.links:
        node = link.from_node
        if node.type == "TEX_IMAGE" and node.image is not None:
            found.append(node.image)
            continue
        for inner in node.inputs:
            found.extend(_images_behind(inner, depth + 1))
    return found


# ---------------------------------------------------------------------------
# Takes
# ---------------------------------------------------------------------------
def rename_actions():
    """`Armature|Walking` back to `Walking`.

    Blender's FBX importer prefixes every take with the object it was bound to.
    glTF names its animations after the actions and Godot names its animations
    after those, so without this the game asks for a clip called
    `Armature|Walking`.
    """
    for action in bpy.data.actions:
        if "|" in action.name:
            action.name = action.name.rsplit("|", 1)[-1]


def fcurves_of(action):
    """Blender 5 actions are slotted and no longer expose `fcurves` directly."""
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                curves.extend(bag.fcurves)
    return curves


def shift_to_frame_one(action):
    """Slide an action so its first key is on frame 1.

    Mixamo's and Meshy's files start on frame 2. The glTF exporter bakes from
    frame 1 regardless, so the take ships with its first frames holding the
    *bind* pose and then snapping into the authored first one -- which reads as
    a hitch rather than as an anticipation.
    """
    start = action.frame_range[0]
    delta = 1.0 - start
    if abs(delta) < 0.5:
        return
    for curve in fcurves_of(action):
        for key in curve.keyframe_points:
            key.co.x += delta
            key.handle_left.x += delta
            key.handle_right.x += delta
        curve.update()


def _snapshot():
    return {name: set(getattr(bpy.data, name).keys()) for name in _COLLECTIONS}


def _purge_since(before, keep_actions):
    """Remove every datablock added since `before`, except the named actions.

    Objects first: removing a mesh or an armature that an object still points at
    leaves the object referring to nothing, and Blender resolves that by
    printing an error nobody asked for.
    """
    order = ("objects", "meshes", "armatures", "materials", "images", "actions")
    for name in order:
        collection = getattr(bpy.data, name)
        for key in list(collection.keys()):
            if key in before[name]:
                continue
            if name == "actions" and key in keep_actions:
                continue
            collection.remove(collection[key], do_unlink=True)


def merge_take(target_armature, path, name):
    """Fold one animation FBX into `target_armature`'s take list as `name`.

    The take is named by the caller rather than by whatever the exporter called
    it, because neither source names them usefully: every Mixamo file's single
    action is called `mixamo.com`, so five of them merged under their own names
    would collide into one.

    Everything else the file brought -- and for a Mixamo export that is a full
    47,000 triangle mesh, a 65-bone rig and twelve 4K maps -- is removed
    immediately, before the next file is opened. See this module's header.
    """
    before = _snapshot()
    import_fbx(path)

    added = [a for a in bpy.data.actions if a.name not in before["actions"]]
    if not added:
        raise SystemExit("rigkit: %s holds no animation" % path)
    if len(added) > 1:
        raise SystemExit("rigkit: %s holds %d takes; this expects one per file "
                         "because the take is named by the caller"
                         % (path, len(added)))

    action = added[0]
    action.name = name
    action.use_fake_user = True
    shift_to_frame_one(action)
    frames = int(action.frame_range[1] - action.frame_range[0]) + 1

    _purge_since(before, keep_actions={action.name})
    stash(target_armature, action)

    print("rigkit: merged %s as %r (%d frames)" % (os.path.basename(path), name, frames))
    return action


def stash(target_armature, action):
    """Put `action` on an NLA track so the glTF exporter can see it.

    Muted, exactly as the FBX importer leaves the takes it stashes itself. The
    exporter evaluates each action on its own; an unmuted stack would only
    change what the viewport shows.
    """
    if target_armature.animation_data is None:
        target_armature.animation_data_create()
    track = target_armature.animation_data.nla_tracks.new()
    track.name = action.name
    strip = track.strips.new(action.name, int(action.frame_range[0]), action)
    # Blender 5 actions carry slots; an unbound strip evaluates to nothing.
    if hasattr(action, "slots") and action.slots and hasattr(strip, "action_slot"):
        strip.action_slot = action.slots[0]
    track.mute = True
    return track


def root_travel(action, root_bone):
    """How far the root bone moves between the first and last key, and the
    largest distance it reaches from its start.

    This is the one thing about a take that a name never tells you and that
    decides how it can be used: a charge whose root travels is a clip that moves
    the character through the world, and one whose root does not is a clip that
    has to be driven by code. Both are usable and they are used differently.
    """
    path = 'pose.bones["%s"].location' % root_bone
    axes = {}
    for curve in fcurves_of(action):
        if curve.data_path != path:
            continue
        keys = sorted(curve.keyframe_points, key=lambda k: k.co.x)
        if keys:
            axes[curve.array_index] = [k.co.y for k in keys]
    if not axes:
        return 0.0, 0.0
    count = min(len(v) for v in axes.values())
    if count < 2:
        return 0.0, 0.0

    def at(index):
        return [axes.get(a, [0.0] * count)[index] for a in range(3)]

    start = at(0)
    net = _length([a - b for a, b in zip(at(count - 1), start)])
    peak = max(_length([a - b for a, b in zip(at(i), start)]) for i in range(count))
    return round(net, 3), round(peak, 3)


def _length(vec):
    return sum(component * component for component in vec) ** 0.5


def print_inventory(target_armature, fps=30.0):
    """Every take: name, frames, seconds, and root travel. Machine-greppable."""
    roots = [b.name for b in target_armature.data.bones if b.parent is None]
    root = roots[0] if roots else ""
    print("rigkit: inventory of %d takes, root bone %r" % (len(bpy.data.actions), root))
    for action in sorted(bpy.data.actions, key=lambda a: a.name.lower()):
        first, last = action.frame_range
        frames = int(last - first) + 1
        net, peak = root_travel(action, root) if root else (0.0, 0.0)
        print("TAKE\t%s\t%d\t%.2f\t%.3f\t%.3f"
              % (action.name, frames, frames / fps, net, peak))


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------
def skinned_meshes():
    """Every mesh actually driven by an armature.

    The membership test the renders and the verification both need, and it is
    not "every mesh in the file". Measured on 5.2:
    `read_factory_settings(use_empty=True)` leaves the startup file's Icosphere
    in `bpy.data.objects`, unlinked from the scene, and **removing it does not
    stick across an import** -- it is back afterwards. It never renders, so
    nothing about the picture gives it away; it just folds a 2 m sphere at the
    origin into any bounding box taken over "every mesh", which framed the first
    pass of every render in this wave for a subject twice the size of the one in
    it, and put the zombie's height at 2.88 m instead of 1.91.

    Asking which meshes a rig drives answers the real question and cannot be
    fooled by whatever else is resident.
    """
    return [obj for obj in bpy.data.objects
            if obj.type == "MESH"
            and any(mod.type == "ARMATURE" for mod in obj.modifiers)]


def set_pose(target_armature, take, where=0.5):
    """Put the rig on `take` at `where` through its range. Returns the frame.

    Three things have to be true at once or the rig stays in bind pose and
    nothing says so: the action assigned, its **slot** bound (Blender 5 actions
    are slotted and an unbound action evaluates to nothing at all), and every
    NLA track muted so the stack the importer built does not win over the
    assignment.
    """
    action = bpy.data.actions.get(take)
    if action is None:
        raise SystemExit("rigkit: no take called %r; have %s"
                         % (take, sorted(bpy.data.actions.keys())[:12]))
    if target_armature.animation_data is None:
        target_armature.animation_data_create()
    for track in target_armature.animation_data.nla_tracks:
        track.mute = True
    target_armature.animation_data.action = action
    if hasattr(action, "slots") and action.slots:
        target_armature.animation_data.action_slot = action.slots[0]
    first, last = action.frame_range
    frame = int(round(first + (last - first) * where))
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    return frame


def clear_pose(target_armature):
    """Unassign the measuring pose before exporting.

    The exporter walks the NLA stack for `export_animation_mode="ACTIONS"`, and
    an action left assigned on the object is a second reference to a take that
    is already stashed.
    """
    if target_armature.animation_data is not None:
        target_armature.animation_data.action = None
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()


def posed_span(target_armature, take, where=0.5):
    """World-space (x, y, z) extent of the skinned meshes **as posed**.

    Not `dimensions()`, which reads `bound_box` -- the mesh datablock's own box,
    in whatever pose the exporting DCC happened to store the vertices in. That
    is not a stable thing to compare across a glTF round trip: the Mixamo
    scavenger's mesh is stored in its Boxing pose while the exporter writes bind
    pose, so the two measurements disagree by 187% on a file that is entirely
    correct. The evaluated depsgraph copy at a named frame is the same geometry
    on both sides of the export by construction.
    """
    set_pose(target_armature, take, where)
    graph = bpy.context.evaluated_depsgraph_get()
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for obj in skinned_meshes():
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        for vertex in mesh.vertices:
            world = evaluated.matrix_world @ vertex.co
            for axis in range(3):
                lo[axis] = min(lo[axis], world[axis])
                hi[axis] = max(hi[axis], world[axis])
        evaluated.to_mesh_clear()
    if lo[0] == float("inf"):
        raise SystemExit("rigkit: no skinned mesh to measure")
    return tuple(round(hi[a] - lo[a], 3) for a in range(3))


def verify_export(path, take, expected_span, where=0.5, tolerance=0.10):
    """Re-import the `.glb`, pose it the same way, and refuse to leave if it is
    not the size it was.

    **This is the gate that caught the wrapper-null shear**, and it exists
    because that failure was completely silent: valid file, right mesh, right
    takes, right materials, and a bear eighty-five times too big. Nothing in the
    build log, the glTF JSON or Godot's importer says a word about it. The only
    way to know is to open the thing you just wrote and measure it.

    The tolerance covers float rounding and the exporter's per-frame resampling,
    nothing more. The error class this exists for is *units* -- 85x, 100x, 0.01x
    -- and ten percent catches every one of them with three orders of magnitude
    to spare.

    Destroys the scene, so it runs last and nothing may follow it.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)

    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if not armatures:
        raise SystemExit("rigkit: %s came back with no armature" % path)
    got = posed_span(armatures[0], take, where)

    worst = max(abs(got[a] - expected_span[a]) / max(expected_span[a], 1e-6) for a in range(3))
    print("rigkit: verify %s on %r -- before %s, after %s (worst axis %.1f%%)"
          % (os.path.basename(path), take, expected_span, got, worst * 100.0))
    if worst > tolerance:
        raise SystemExit(
            "rigkit: %s re-imports at %s but was %s in Blender -- the exporter "
            "could not represent something in the transform chain. A rotation "
            "composed with a non-uniform scale is the usual cause; glTF nodes "
            "carry TRS and cannot express shear."
            % (path, got, expected_span))
    return got


def export_character_glb(path, materials="EXPORT"):
    """The one export every character gets.

    `export_optimize_animation_size=False` because the takes are already sampled
    per frame and a cycle's first and last poses are the same one; trimming to
    "actually moved" clips the loop point off the end.

    `materials` is "EXPORT" by default because the Art Bible's exception box lets
    a character keep its own maps, and the man, the scavenger, the zombie and the
    bear all do. It is a parameter because that is a permission, not an
    obligation: `build_dog.py` passes "NONE" because a dog painted from
    `data/palette/color_bible.tres` at runtime samples no map, and a map shipped
    in the `.glb` that nothing reads is bytes plus a surface no gate judges.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_materials=materials,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_bake_animation=True,
        export_optimize_animation_size=False,
    )
