"""Three dogs out of seventeen Unity FBXs: one `.glb` each, every take, plus the
two poses the package does not have.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_dog.py

Optional arguments after `--`:

    --source <dir>   where the seventeen FBXs are, default H:/Repos/animalpack/...
    --out <dir>      default assets/models/characters/dogs
    --breed <name>   build only chihuahua | golden_retriever | great_dane
    --no-export      build and measure, write nothing

---------------------------------------------------------------------------
WHAT ARRIVED, AND WHY IT CANNOT GO STRAIGHT INTO THE PROJECT
---------------------------------------------------------------------------
`Docs/asset-inventory-low-poly-animals.md` section 5 recorded the dogs as
adopted-but-blocked: all seventeen clips shipped as Unity `.anim` files, which
Godot cannot read. The owner re-exported them out of Unity as `Model@Clip.fbx`,
which unblocks the animation and hands over four new problems instead.

**1. Each of the seventeen carries a full copy of the dog.** 24 MB of FBX for
three animals, of which 21 MB is the same mesh and the same 1024 colour map
written out six times. Imported as they arrived, Godot would build seventeen
scenes, seventeen skeletons and seventeen textures. So this script does what
`build_scavenger.py` does with Mixamo's 115 MB-per-clip exports: one file
carries the mesh, and every other file contributes nothing but its take.

**2. Blender loses the root bone, and five per cent of the skin with it.**
The FBX hierarchy is `SKM_Dog_X_Rig > Main > DeformationSystem > Root_M >
bones`, and Blender's importer turns `Root_M` -- the one bone with the whole
skeleton under it -- into the *armature object*. Its children become four
parentless root bones, and the mesh's `Root_M` vertex group is left pointing at
a bone that no longer exists. MEASURED on the three files:

    chihuahua         23.29 of 438 total weight, across 64 vertices
    golden retriever  14.49 of 466 total weight, across 48 vertices
    great dane        21.79 of 496 total weight, across 58 vertices

Nothing errors. Blender's armature modifier renormalises what is left, so those
vertices are simply driven by the wrong bones -- a rump that follows the spine
instead of the root. `rebuild_root_bone()` puts `Root_M` back as a real bone and
`bake_takes()` moves the object-level animation onto it, which is where it was
in the source file.

**3. The takes face Unity's forward.** Unity is left-handed with +Z forward;
Godot is right-handed and `look_at()` aims -Z. The crow shipped a whole wave
flying tail-first for exactly this reason. MEASURED in armature space on all
three rigs before a degree was applied: `Head_M` sits on the opposite side of
the root from `Tail0_M` along the axis that leaves Blender as glTF +Z. So the
rig is turned once, here, at build time -- see MODEL_YAW -- rather than by a
constant every consumer has to remember. `tests/art/test_dog_models.gd` measures
the shipped `.glb`, not a constant, so there is nothing left to forget.

**4. Three authoring scales became one, and that is worth checking rather than
assuming.** The inventory measured the pack's own FBXs arriving at 1.0, 100.0
and 100.0 -- three dogs, two scale families. Unity's re-export normalises them:
all three now arrive life-sized in Blender and `assert_life_sized()` refuses to
write a `.glb` that is not. `data/scale/*.tres` then holds the same expectation
on the Godot side, so the check exists on both sides of the export.

---------------------------------------------------------------------------
THE TWO TAKES THE PACKAGE DOES NOT HAVE
---------------------------------------------------------------------------
No dog in the pack can lie down and none can growl, and the scripted find opens
on a hurt dog in the snow. Both are authored here, on all three rigs, from the
shared bone names -- see `author_lie()` and `author_growl()`. Neither is
quadruped locomotion, which is the thing the owner cannot author: one is a held
pose plus a breath, the other is a held attitude plus a sway.

They are built from ARMATURE-SPACE AXES derived from each rig -- forward from
`Tail0_M` to `Head_M`, up from the armature's own world matrix -- rather than
from per-bone Euler angles, because the three rigs do not share a bone
orientation convention and a pose authored in one rig's local axes lands
somewhere else in the other two. `rotate()` converts an armature-space rotation
into whatever local basis a bone happens to have.

The floor is MEASURED, not guessed: `settle_on_ground()` evaluates the posed
mesh and drops the root until the lowest vertex is at z = 0. That is what makes
one set of angles work on a 0.29 m chihuahua and a 1.28 m great dane.

---------------------------------------------------------------------------
WHAT THIS DOES NOT DO
---------------------------------------------------------------------------
No behaviour, no state machine, no loop flags. Which take loops and what the
game calls it lives in `src/entities/wildlife/dog_animations.gd`, because none
of it is knowable from the files.
"""

import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import propkit as kit  # noqa: E402
import rigkit  # noqa: E402

SOURCE_DEFAULT = "H:/Repos/animalpack/Assets/WinterTimeExport"

TRIANGLE_BUDGET = 8000

## Half a turn about the vertical, applied to the whole rig at build time.
##
## The measurement behind it is in this file's header and is re-taken by
## `report_facing()` on every run: the head leaves Blender on the +Z side, which
## is Unity's forward and the opposite of the one `look_at()` aims.
MODEL_YAW = math.pi

## The take every `.glb` is re-posed on after it is written, to prove the export
## did not change the animal's size. `idle` because it is the only take all three
## breeds share that holds a neutral stance for its whole length.
VERIFY_TAKE = "idle"

## What the pack calls a clip, and what this project calls it. All six are
## straight lowercasings, and one of them nearly was not.
##
## `Stand` was renamed to `rear_up` in the first pass of this file, on a
## MEASUREMENT: the take takes the golden retriever from 0.80 m tall to 1.18 m
## and shortens it from 1.22 m to 1.01 m, which is the signature of an animal
## coming up onto its hind legs. The render says otherwise -- the dog is standing
## squarely on all four feet, and the height is its HEAD and its TAIL coming up
## as it settles into an alert stance.
##
## The briefing's rule, in its own words: when a number is supposed to describe
## the picture, check it against the picture. A bounding box cannot tell a dog
## rearing up from a dog raising its tail, and `rear_up` would have shipped into
## the companion vocabulary as a verb no dog in this game can perform.
CLIP_NAMES = {
    "Bark": "bark",
    "Idle": "idle",
    "Run": "run",
    "Sit": "sit",
    "Stand": "stand",
    "Walk": "walk",
}

## [breed, the FBX stem, the clip prefix inside each file, the clips it has].
##
## The chihuahua has no `Stand`. That is the pack's gap, it is recorded here
## rather than papered over, and what the game does when it asks a chihuahua to
## rear up is decided in `dog_animations.gd`, in code, not by a null.
BREEDS = [
    ("chihuahua", "SKM_Dog_Chihuahua_Rig", "Dog_Chihuahua_",
     ["Idle", "Walk", "Run", "Sit", "Bark"]),
    ("golden_retriever", "SKM_Dog_GoldenRetriever_Rig", "Dog_GoldenRetriever_",
     ["Idle", "Walk", "Run", "Sit", "Stand", "Bark"]),
    ("great_dane", "SKM_Dog_GreatDane_Rig", "Dog_GreatDane_",
     ["Idle", "Walk", "Run", "Sit", "Stand", "Bark"]),
]

## Real-world nose-to-tail lengths, so a re-export that lost its units cannot be
## written. Wide, because the bind pose is a standing dog and the box is over the
## whole animal including its tail.
LIFE_SIZE_M = {
    "chihuahua": (0.18, 0.50),
    "golden_retriever": (0.85, 1.60),
    "great_dane": (1.00, 1.90),
}

## The pack authored every dog at 24 fps, like 55 of the package's 66 animals.
SOURCE_FPS = 24


# ---------------------------------------------------------------------------
# The rig, as it should have arrived
# ---------------------------------------------------------------------------
def rebuild_root_bone(arm):
    """Put `Root_M` back as a bone and hang the loose roots off it.

    Head at the armature's own origin, tail one unit along +Y, roll zero -- so
    its rest matrix is the identity and a pose written onto it is read straight
    off as an armature-space transform, with no basis conversion at all. That is
    the whole reason for choosing those numbers; any other orientation would make
    `bake_takes()` compose a rotation it does not need to.
    """
    if "Root_M" in arm.data.bones:
        return
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    root = arm.data.edit_bones.new("Root_M")
    root.head = Vector((0.0, 0.0, 0.0))
    root.tail = Vector((0.0, 1.0, 0.0))
    root.roll = 0.0
    adopted = []
    for bone in arm.data.edit_bones:
        # By name, not by identity: `edit_bones` hands out a fresh Python wrapper
        # on every access, so `bone is root` is False for the bone just created
        # and the new root was listed as adopting itself.
        if bone.name == "Root_M" or bone.parent is not None:
            continue
        bone.parent = root
        bone.use_connect = False
        adopted.append(bone.name)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("build_dog: rebuilt Root_M, adopting %s" % sorted(adopted))


def quaternion_pose_bones(arm):
    """Every pose bone on quaternions.

    `matrix_basis` is written and read all through this script and a bone left on
    Euler stores the rotation in channels the keyframes never touch, which shows
    up as a bone that will not move and nothing at all in the console.
    """
    for bone in arm.pose.bones:
        bone.rotation_mode = "QUATERNION"


def rest_pose(arm):
    for bone in arm.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


# ---------------------------------------------------------------------------
# Armature-space axes, so one pose fits three rigs
# ---------------------------------------------------------------------------
class Axes:
    """Forward, up and side for a rig, in ARMATURE space.

    Up is taken from the armature's own world matrix rather than assumed, because
    the FBX axis conversion leaves armature-local +Y pointing at world -Z on
    these files. Forward is taken from the animal -- the line from the tail root
    to the head -- with the vertical component removed, so it is horizontal even
    on a rig whose spine slopes.
    """

    def __init__(self, arm):
        basis = arm.matrix_world.to_3x3()
        self.scale = arm.matrix_world.to_scale().x
        self.up = (basis.inverted() @ Vector((0.0, 0.0, 1.0))).normalized()
        head = arm.data.bones["Head_M"].head_local
        tail = arm.data.bones["Tail0_M"].head_local
        forward = head - tail
        forward -= self.up * forward.dot(self.up)
        self.forward = forward.normalized()
        # Right-handed: side = up x forward, so a positive rotation about `side`
        # pitches the nose down and a positive rotation about `up` yaws left.
        self.side = self.up.cross(self.forward).normalized()
        self.body_length = (head - tail).length
        self.body_height = max(b.head_local.dot(self.up) for b in arm.data.bones)


def rotate(arm, name, axis, degrees):
    """Turn one bone by `degrees` about `axis`, an axis in ARMATURE space.

    A bone's pose basis acts in the frame `parent_pose * parent_rest^-1 * rest`,
    which is a different frame for every bone and a different one again once the
    parent has been posed. Converting into it -- rather than writing Euler angles
    per bone -- is what lets `author_lie()` say "roll the body 80 degrees about
    the line it lies along" and have that mean the same thing on all three rigs.

    Composes on top of whatever the bone already holds, so a chain can be built
    up in several passes, and returns False for a bone this rig does not have so
    a caller can name the union of the three skeletons without branching.
    """
    bone = arm.pose.bones.get(name)
    if bone is None:
        return False
    bpy.context.view_layer.update()
    rest = bone.bone.matrix_local.to_3x3()
    if bone.parent is None:
        frame = rest
    else:
        frame = bone.parent.matrix.to_3x3() @ bone.parent.bone.matrix_local.to_3x3().inverted() @ rest
    delta = frame.inverted() @ Matrix.Rotation(math.radians(degrees), 3, axis) @ frame
    bone.matrix_basis = delta.to_4x4() @ bone.matrix_basis
    bpy.context.view_layer.update()
    return True


def shift_root(arm, axes, along, metres):
    """Move the whole animal `metres` along an armature-space direction.

    Root_M's rest matrix is the identity by construction, so its basis
    translation is in armature units; the armature's uniform world scale converts
    them. Stated rather than left implicit because the three rigs are authored a
    hundred times larger than they render and every raw number in this file is in
    those units.
    """
    root = arm.pose.bones["Root_M"]
    root.location = root.location + along.normalized() * (metres / axes.scale)
    bpy.context.view_layer.update()


def hold(arm):
    return {bone.name: bone.matrix_basis.copy() for bone in arm.pose.bones}


def restore(arm, held):
    for bone in arm.pose.bones:
        bone.matrix_basis = held[bone.name].copy()
    bpy.context.view_layer.update()


def height_of(arm, name):
    """World z of a posed bone's head."""
    bpy.context.view_layer.update()
    return (arm.matrix_world @ arm.pose.bones[name].head).z


def tip_height_of(arm, name):
    """World z of a posed bone's TIP.

    The tail is measured at its tip rather than its last joint, because on the
    chihuahua the last joint is barely two centimetres from the one before it and
    a target set on the joint moves the tail by almost nothing.
    """
    bpy.context.view_layer.update()
    return (arm.matrix_world @ arm.pose.bones[name].tail).z


def solve_pitch(arm, axes, chain, measure, target, low=-90.0, high=120.0, coarse=10.0, steps=14,
                must_reach=True):
    """Bisect the total pitch spread across `chain` until `measure` hits `target`.

    ---------------------------------------------------------------------
    WHY A SOLVER AND NOT THREE TABLES OF ANGLES
    ---------------------------------------------------------------------
    The first version of this file wrote the neck as fixed degrees and the head
    came out thrown BACK on all three dogs. The reason is that the bind pose is
    not a neutral stance -- the golden retriever's bind stands 0.798 m tall
    against 0.589 m in its own idle, because the rig was bound with the head
    high -- so a fixed rotation lands somewhere different on every rig and on
    every re-export.

    What is actually being specified is a RELATIONSHIP: the muzzle below the
    withers for a growl, the neck in line with the spine for a dog on its side.
    Bisecting on a measurement states that relationship directly, and it is why
    one set of numbers fits a 0.33 m chihuahua and a 1.21 m great dane.

    `measure` returns a world height and the pitch is spread evenly across the
    chain, so no single joint carries a bend the geometry cannot take.

    IT SCANS BEFORE IT BISECTS, and that is not caution either. A bone's tip
    traces a CIRCLE as it turns, so height against angle is a sinusoid and a
    plain bisection on the two endpoints is only correct if they happen to
    straddle one crossing. MEASURED on the golden retriever's skull -- the muzzle
    runs 0.388 m at -30 degrees up to 0.672 m at +150 -- a bracket of
    [-120, +140] has the target BETWEEN its two positive ends, so the bisection
    refused a target that two different angles reach. The scan finds every
    crossing and the one nearest zero is taken, which is also the one that does
    not fold the neck backwards to get there.
    """
    held = hold(arm)

    def apply(total):
        restore(arm, held)
        for name in chain:
            rotate(arm, name, axes.side, total / float(len(chain)))
        return measure() - target

    scan = []
    degrees = low
    while degrees <= high + 1e-6:
        scan.append((degrees, apply(degrees)))
        degrees += coarse

    crossings = [(scan[i], scan[i + 1]) for i in range(len(scan) - 1)
                 if (scan[i][1] > 0.0) != (scan[i + 1][1] > 0.0)]
    if not crossings:
        # The rig will not reach it. Take the nearest angle and print the whole
        # scan rather than returning a pose quietly off by an unknown amount.
        #
        # `must_reach=False` says the target is a DIRECTION, not a position: the
        # tails are asked to go below their own root and the honest answer for
        # some rigs is "as far as this one goes". The chihuahua carries its tail
        # curled over its back at rest and 30 degrees per joint will not undo
        # that -- MEASURED, its tip reaches 0.2154 m against a root at 0.2304 m,
        # so it lies flat rather than hanging. Calling that a WARNING every run
        # would train everyone to ignore the word.
        nearest = min(scan, key=lambda sample: abs(sample[1]))
        apply(nearest[0])
        print("build_dog: %s %s cannot reach %.4f m; nearest %.4f m at %+.1f deg. Scan: %s"
              % ("WARNING" if must_reach else "LIMIT", chain[0], target,
                 target + nearest[1], nearest[0],
                 " ".join("%+.0f:%.4f" % (d, target + e) for d, e in scan)))
        return nearest[0]

    (a, at_a), (b, _) = min(crossings, key=lambda pair: abs(pair[0][0] + pair[1][0]))
    for _ in range(steps):
        middle = 0.5 * (a + b)
        error = apply(middle)
        if (error > 0.0) == (at_a > 0.0):
            a, at_a = middle, error
        else:
            b = middle
    total = 0.5 * (a + b)
    apply(total)
    return total


def lowest_point(arm):
    """World z of the lowest vertex of the posed skin."""
    graph = bpy.context.evaluated_depsgraph_get()
    lowest = float("inf")
    for obj in rigkit.skinned_meshes():
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        for vertex in mesh.vertices:
            lowest = min(lowest, (evaluated.matrix_world @ vertex.co).z)
        evaluated.to_mesh_clear()
    if lowest == float("inf"):
        raise SystemExit("build_dog: nothing skinned to measure")
    return lowest


def settle_on_ground(arm, axes):
    """Drop the posed animal until its lowest vertex is exactly on z = 0.

    The reason the same angles read on a 0.29 m chihuahua and a 1.28 m great dane
    is that none of them decides the height: this does, from the mesh, after the
    pose. A hand-set root height would be three numbers to keep, and they would
    be wrong the first time a rig is re-exported.
    """
    drop = lowest_point(arm)
    shift_root(arm, axes, axes.up, -drop)
    return drop


# ---------------------------------------------------------------------------
# Chains, read off the hierarchy rather than listed per rig
# ---------------------------------------------------------------------------
def chain_up(arm, leaf, stop):
    """`leaf` and every parent above it, up to but not including `stop`.

    Returned root-first. The three rigs disagree about how many bones are in the
    neck and the spine -- the great dane has `Spine11_M` and `tempRename_M` where
    the other two have `Spine1Part1_M`, `Spine1Part2_M` and `Chest_M` -- so every
    chain here is discovered, never listed.
    """
    names = []
    bone = arm.data.bones.get(leaf)
    while bone is not None and bone.name != stop:
        names.append(bone.name)
        bone = bone.parent
    names.reverse()
    return names


def spine_chain(arm):
    """Root_M (exclusive) up to the last bone before the neck."""
    return chain_up(arm, arm.data.bones["Neck_M"].parent.name, "Root_M")


def neck_chain(arm):
    """The neck bones, head excluded."""
    return chain_up(arm, arm.data.bones["Head_M"].parent.name,
                    arm.data.bones["Neck_M"].parent.name)


def tail_chain(arm):
    """Tail0_M and everything hanging off it, root-first."""
    names = []
    stack = [arm.data.bones["Tail0_M"]]
    while stack:
        bone = stack.pop(0)
        names.append(bone.name)
        stack.extend(bone.children)
    return names


def leg_chain(arm, prefix, side):
    """`frontHip_L` and down, or `backHip_L` and down, root-first."""
    names = []
    stack = [arm.data.bones["%sHip_%s" % (prefix, side)]]
    while stack:
        bone = stack.pop(0)
        names.append(bone.name)
        stack.extend(bone.children)
    return names


# ---------------------------------------------------------------------------
# The two authored takes
# ---------------------------------------------------------------------------
## How long each authored take runs, in seconds, and how many cycles of its
## motion fit in that. Both are integers over the take so the last frame returns
## to the first and the take loops without a seam.
LIE_SECONDS = 6.0
LIE_BREATHS = 2
GROWL_SECONDS = 3.0


def author_lie(arm, axes):
    """A dog lying on its side in the snow, breathing.

    ---------------------------------------------------------------------
    WHY ON ITS SIDE RATHER THAN SPHINX
    ---------------------------------------------------------------------
    A dog folded sternal with its head up is a dog RESTING, and the scene this
    take exists for opens on a hurt one. Flat on the flank is unambiguous, and at
    this game's framing it is also the stronger read: a low horizontal mass in the
    snow against a standing silhouette.

    It is also the pose the rig gives most cheaply. The bind pose is a standing
    dog with its legs vertical; roll the body ninety degrees and those legs are
    already horizontal and stacked, which is what a side-lying dog's legs do. The
    work left is bending the joints so they are not four rigid poles, dropping the
    head to the ground and settling the whole thing onto z = 0.

    ---------------------------------------------------------------------
    THE BREATH, AND THE ONE TWITCH THE RIG CAN GIVE
    ---------------------------------------------------------------------
    Two breaths over six seconds -- twenty a minute, a dog at rest -- carried by
    the chest bones rolling about the body's own long axis, which on a side-lying
    animal lifts the upper flank. The root rises with it by a fraction of the
    body's height so the whole mass moves rather than the ribs sliding inside a
    still silhouette.

    **There are no ear bones on any of the three rigs**, so the brief's "an ear or
    tail twitch" can only be the tail. It happens once, at three fifths through,
    over half a second, and it is the only thing in the take that is not periodic
    -- which is what stops six seconds of breathing reading as a machine.
    """
    rest_pose(arm)
    spine = spine_chain(arm)
    neck = neck_chain(arm)
    withers = height_of(arm, spine[-1])

    # ---------------------------------------------------------------------
    # EVERYTHING IS POSED STANDING AND THE BODY IS ROLLED **LAST**, WHICH IS
    # NOT A TIDINESS CHOICE
    # ---------------------------------------------------------------------
    # `rotate()` works in armature space, so `axes.side` is the pitch axis only
    # while the animal is the right way up. The first version of this function
    # rolled first and then pitched the neck, and `side` was by then the body's
    # ROLL axis -- so the neck swung round instead of down and all three dogs
    # shipped with the head thrown back over the shoulder. It read as rigor
    # mortis, which is a different animal from an injured one.

    # The neck ends up in line with the spine: on a dog lying on its flank the
    # head rests on the snow at the same height as the ribs, and it is the roll
    # that puts it there, not a downward bend.
    solve_pitch(arm, axes, neck, lambda: height_of(arm, "Head_M"), withers)
    solve_pitch(arm, axes, ["Head_M"], lambda: height_of(arm, "JawEnd_M"),
                height_of(arm, "Head_M"))

    # The spine opens a little rather than curling: an animal that went down is
    # extended, not tucked. A tucked spine reads as sleeping.
    for name in spine[:2]:
        rotate(arm, name, axes.side, -4.0)

    # The legs. Front pair reaching forward, back pair trailing, both bent --
    # and the two sides differ, because a perfectly stacked pair reads as a
    # cut-out rather than as an animal.
    for side, near in (("L", 1.0), ("R", 0.55)):
        rotate(arm, "frontHip_%s" % side, axes.side, -26.0 * near)
        rotate(arm, "frontKnee_%s" % side, axes.side, 30.0 * near)
        rotate(arm, "frontAnkle_%s" % side, axes.side, -16.0 * near)
        rotate(arm, "backHip_%s" % side, axes.side, 24.0 * near)
        rotate(arm, "backKnee_%s" % side, axes.side, -42.0 * near)
        rotate(arm, "backAnkle_%s" % side, axes.side, 26.0 * near)

    # The tail, laid out behind and limp. Solved to hang below its own root for
    # the reason `author_growl` gives: the chihuahua carries its tail curled over
    # its back at rest and the other two do not, so a fixed angle is three
    # different tails.
    #
    # NEGATIVE runs it downward, and that sign caught this file twice. A positive
    # rotation about `side` tilts a bone's own direction DOWNWARD -- but the tail
    # points backwards, so its direction is -forward and the same positive
    # rotation lifts it. The first pass put a cheerful tail in the air on a dog
    # that had just collapsed.
    limp = tail_chain(arm)
    solve_pitch(arm, axes, limp, lambda: tip_height_of(arm, limp[-1]),
                height_of(arm, limp[0]) * 0.70, low=-150.0, high=30.0, must_reach=False)

    # And now onto the flank. Not the full ninety: a dog on its side settles
    # with the shoulder and hip taking the weight and the spine slightly open.
    rotate(arm, "Root_M", axes.forward, 82.0)

    settle_on_ground(arm, axes)
    print("build_dog: lie -- withers was %.4f m, muzzle now %.4f m, floor %.4f m"
          % (withers, height_of(arm, "JawEnd_M"), lowest_point(arm)))
    held = hold(arm)

    frames = int(round(LIE_SECONDS * SOURCE_FPS)) + 1
    chest = spine[-2:]
    tail = tail_chain(arm)
    samples = []
    for index in range(frames):
        phase = index / float(frames - 1)
        breath = math.sin(phase * LIE_BREATHS * 2.0 * math.pi)
        # A raised cosine, so the twitch starts and ends at rest instead of
        # stepping. 0.6 through the take, half a second wide.
        twitch = 0.0
        span = 0.5 / LIE_SECONDS
        if abs(phase - 0.60) < span:
            twitch = 0.5 - 0.5 * math.cos((0.5 + (phase - 0.60) / (2.0 * span)) * 2.0 * math.pi)

        restore(arm, held)
        for name in chest:
            rotate(arm, name, axes.forward, 2.4 * breath)
        rotate(arm, "Head_M", axes.side, 1.2 * breath)
        for name in tail[1:]:
            rotate(arm, name, axes.up, 9.0 * twitch)
        # Re-settled EVERY frame rather than once for the pose. Rolling the
        # ribcage lifts the flank the animal is lying on, so without this the
        # whole dog rises off the snow as it inhales -- MEASURED at 12 mm on the
        # golden retriever, which at this framing is several pixels of a dog
        # hovering. Settling makes the same roll show as the ribs rising against
        # a body that stays on the ground, which is what breathing looks like.
        settle_on_ground(arm, axes)
        samples.append(snapshot(arm))
    return samples


def author_growl(arm, axes):
    """Head low and forward, weight back, tail low and slowly moving.

    Most of a growl is audio and orientation. What the animation has to carry is
    that the dog has DROPPED and is FACING something -- the head below the line of
    the shoulders and pushed out in front of the chest, the hindquarters loaded.
    A dog growling at something the player cannot see is the best warning this
    roster can give, and it only works if the pose reads before the sound does.

    It is a held attitude, not a cycle, so the only motion is what keeps it alive:
    one slow sweep of the tail and a small sway of the head over three seconds,
    both returning to where they started.
    """
    rest_pose(arm)
    spine = spine_chain(arm)
    neck = neck_chain(arm)
    standing = height_of(arm, spine[-1])

    # Weight back and down over the hind legs.
    for side in ("L", "R"):
        rotate(arm, "backHip_%s" % side, axes.side, 12.0)
        rotate(arm, "backKnee_%s" % side, axes.side, -20.0)
        rotate(arm, "backAnkle_%s" % side, axes.side, 10.0)
        rotate(arm, "frontKnee_%s" % side, axes.side, 6.0)
    # The shoulders drop with them, so the topline slopes down to the front
    # rather than the neck alone doing all the work.
    for name in spine[-2:]:
        rotate(arm, name, axes.side, 6.0)

    withers = height_of(arm, spine[-1])

    # THE WHOLE POSE IS THIS ONE RELATIONSHIP: the skull below the shoulders and
    # the muzzle below the skull. A dog with its head above the line of its back
    # is an alert dog, not a threatening one, and the difference is entirely in
    # where the head is -- which is why it is solved rather than dialled in.
    #
    # 0.88 of the withers and not lower. MEASURED at 0.68 the muzzle reached the
    # snow and the dog read as EATING; the difference between a threat and an
    # animal feeding is about eight centimetres of skull on this rig, and it is
    # the reason this number is written down with what it was tried at.
    solve_pitch(arm, axes, neck, lambda: height_of(arm, "Head_M"), withers * 0.88)
    # ...and the muzzle very slightly ABOVE the skull joint, which is what turns
    # a lowered head from sniffing into aiming. At level, and at anything below
    # it, the animal reads as interested in the ground.
    solve_pitch(arm, axes, ["Head_M"], lambda: height_of(arm, "JawEnd_M"),
                height_of(arm, "Head_M") + 0.015 * standing)
    rotate(arm, "Jaw_M", axes.side, 9.0)

    # Tail low and stiff -- a growling dog does not wag -- and SOLVED, not dialled.
    #
    # A fixed -32 degrees put the golden retriever's and the great dane's tails
    # down and left the CHIHUAHUA's curled up over its back, because that is where
    # its rest pose carries it and the breeds do not share a rest tail at all. A
    # target of "the tip below the root" is the thing actually being asked for and
    # it lands on all three.
    #
    # Negative angles run the tail DOWNWARD, which is the opposite of every other
    # bone here: a positive pitch about `side` tilts a bone's own direction down,
    # and the tail's direction is -forward.
    tail = tail_chain(arm)
    solve_pitch(arm, axes, tail, lambda: tip_height_of(arm, tail[-1]),
                height_of(arm, tail[0]) * 0.55, low=-150.0, high=30.0, must_reach=False)

    settle_on_ground(arm, axes)
    print("build_dog: growl -- standing withers %.4f m, crouched %.4f m, skull %.4f m, muzzle %.4f m"
          % (standing, withers, height_of(arm, "Head_M"), height_of(arm, "JawEnd_M")))
    held = hold(arm)

    frames = int(round(GROWL_SECONDS * SOURCE_FPS)) + 1
    tail = tail_chain(arm)
    samples = []
    for index in range(frames):
        phase = index / float(frames - 1)
        sway = math.sin(phase * 2.0 * math.pi)
        restore(arm, held)
        for name in tail:
            rotate(arm, name, axes.up, 5.0 * sway)
        rotate(arm, "Head_M", axes.up, 2.0 * sway)
        rotate(arm, "Neck_M", axes.up, 1.0 * sway)
        for name in spine[-2:]:
            rotate(arm, name, axes.forward, 0.8 * math.sin(phase * 6.0 * math.pi))
        samples.append(snapshot(arm))
    return samples


# ---------------------------------------------------------------------------
# Sampling and rebuilding the pack's own takes
# ---------------------------------------------------------------------------
def snapshot(arm):
    """Every bone's pose basis, decomposed. One frame of a take."""
    frame = {}
    for bone in arm.pose.bones:
        location, rotation, scale = bone.matrix_basis.decompose()
        frame[bone.name] = (tuple(location), tuple(rotation), tuple(scale))
    return frame


def sample_source(path, reference):
    """Play one source FBX and read every frame off it.

    Returns `(frames, reference)`, where a frame is `{bone: (loc, quat, scale)}`
    with an extra `Root_M` entry carrying the armature OBJECT's motion expressed
    in armature space:

        B(t) = M_reference^-1 * M_world(t)

    which is exactly the transform the lost root bone used to apply. Every take
    is measured against the SAME reference -- the first frame of the model file's
    idle -- so the six takes agree about where the dog stands.

    A fresh scene per file, and nothing from the file survives the call. That is
    `build_scavenger.py`'s reason exactly: each of these carries a full copy of
    the mesh, the rig and a 1024 map, and six of them resident at once is six
    skeletons the exporter can see.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rigkit.import_fbx(path)
    arm = rigkit.armature()
    if arm is None:
        raise SystemExit("build_dog: %s holds no armature" % path)
    quaternion_pose_bones(arm)
    actions = list(bpy.data.actions)
    if len(actions) != 1:
        raise SystemExit("build_dog: %s holds %d actions, expected one"
                         % (path, len(actions)))
    first, last = (int(round(v)) for v in actions[0].frame_range)

    scene = bpy.context.scene
    frames = []
    for number in range(first, last + 1):
        scene.frame_set(number)
        bpy.context.view_layer.update()
        if reference is None:
            reference = arm.matrix_world.copy()
        frame = snapshot(arm)
        frame["Root_M"] = _decomposed(reference.inverted() @ arm.matrix_world)
        frames.append(frame)
    return frames, reference


def _decomposed(matrix):
    location, rotation, scale = matrix.decompose()
    return (tuple(location), tuple(rotation), tuple(scale))


def write_take(arm, name, frames):
    """Turn sampled frames into an Action on `arm`, stashed so glTF sees it.

    EVERY bone is keyed in EVERY take, including the ones that never move. Godot
    is imported with `animation/remove_immutable_tracks=false` for the same
    reason and `tests/art/test_dog_models.gd` asserts it: a take that omits a
    bone leaves that bone wherever the previous take left it, so a dog that has
    just run stands up from lying down with its legs still mid-stride. Nothing
    errors and it is invisible until somebody plays two takes in a row.
    """
    if arm.animation_data is None:
        arm.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data.action = action
    for number, frame in enumerate(frames, start=1):
        for bone in arm.pose.bones:
            sample = frame.get(bone.name)
            if sample is None:
                continue
            bone.location = sample[0]
            bone.rotation_quaternion = sample[1]
            bone.scale = sample[2]
            bone.keyframe_insert("location", frame=number)
            bone.keyframe_insert("rotation_quaternion", frame=number)
            bone.keyframe_insert("scale", frame=number)
    arm.animation_data.action = None
    rigkit.stash(arm, action)
    return action


# ---------------------------------------------------------------------------
# Reporting, which is the half that makes the build checkable
# ---------------------------------------------------------------------------
def report_facing(arm, axes, label):
    """Which way the animal points, in the space the `.glb` will be written in.

    Blender's glTF exporter maps Blender (x, y, z) to (x, z, -y), so Blender -Y
    is glTF +Z. Printed for both the bones and the geometry, because a rig turned
    round while its mesh was not passes any test that consults only one of them --
    which is the trap `test_crow_model.gd` was written around.
    """
    head = arm.matrix_world @ arm.data.bones["Head_M"].head_local
    tail = arm.matrix_world @ arm.data.bones["Tail0_M"].head_local
    graph = bpy.context.evaluated_depsgraph_get()
    top = []
    points = []
    for obj in rigkit.skinned_meshes():
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        for vertex in mesh.vertices:
            points.append(evaluated.matrix_world @ vertex.co)
        evaluated.to_mesh_clear()
    if points:
        highest = max(p.z for p in points)
        lowest = min(p.z for p in points)
        line = lowest + (highest - lowest) * 0.9
        top = [p for p in points if p.z >= line]
    skull = sum((p.y for p in top), 0.0) / len(top) if top else 0.0
    body = sum((p.y for p in points), 0.0) / len(points) if points else 0.0
    print("build_dog: %s facing -- bone head y %+.4f tail y %+.4f (glTF z %+.4f / %+.4f); "
          "skull y %+.4f body y %+.4f" % (label, head.y, tail.y, -head.y, -tail.y, skull, body))
    return -head.y


def assert_life_sized(breed, span):
    smallest, largest = LIFE_SIZE_M[breed]
    longest = max(span)
    if not (smallest <= longest <= largest):
        raise SystemExit(
            "build_dog: %s measures %s m, whose longest side %.3f m is outside the "
            "%.2f..%.2f m a real one is. The pack is authored at three different "
            "scales and Godot normalises none of them; check the source export."
            % (breed, span, longest, smallest, largest))


def main():
    root = kit.project_root()
    source = kit.argument("--source", SOURCE_DEFAULT)
    out = kit.argument("--out", os.path.join(root, "assets", "models", "characters", "dogs"))
    only = kit.argument("--breed", "")

    for breed, stem, prefix, clips in BREEDS:
        if only and only != breed:
            continue
        build(breed, stem, prefix, clips, source, os.path.join(out, "%s.glb" % breed))


def build(breed, stem, prefix, clips, source, destination):
    def source_of(clip):
        return os.path.join(source, "%s@%s%s.fbx" % (stem, prefix, clip))

    # The first clip carries the mesh and sets the reference every other take is
    # measured against. Idle, because it is the one take that holds a neutral
    # stance for its whole length.
    takes = {}
    reference = None
    for clip in clips:
        frames, reference = sample_source(source_of(clip), reference)
        takes[CLIP_NAMES[clip]] = frames
        print("build_dog: %s sampled %-8s %3d frames (%.3f s)"
              % (breed, CLIP_NAMES[clip], len(frames), len(frames) / float(SOURCE_FPS)))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    rigkit.import_fbx(source_of(clips[0]))
    arm = rigkit.armature()
    meshes = rigkit.meshes()
    if not meshes:
        raise SystemExit("build_dog: %s holds no mesh" % source_of(clips[0]))

    triangles = rigkit.triangle_count(meshes)
    if triangles > TRIANGLE_BUDGET:
        raise SystemExit("build_dog: %s is %d triangles, over the %d character budget"
                         % (breed, triangles, TRIANGLE_BUDGET))

    # The bone tips the importer could not fold into the armature -- `Tail4_M`,
    # `joint3_L`, `frontToes4_R` and the rest -- arrive as empties parented to a
    # bone. MEASURED: not one of them carries a vertex weight on any of the three
    # dogs, so they are geometry-free nodes that would export as unexplained
    # children of the skeleton. `Geometry` is childless for the same reason: the
    # mesh is parented to the armature, not to it.
    rigkit.drop_empties()

    # Freeze the hierarchy at the reference frame and take every object-level
    # animation off it. From here the only thing that moves is the skeleton, and
    # `Root_M` -- rebuilt below -- is what carries what the objects used to.
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    frozen = [(obj, obj.matrix_world.copy()) for obj in bpy.data.objects]
    for obj, _ in frozen:
        obj.animation_data_clear()
    for obj, matrix in frozen:
        obj.matrix_world = matrix
    bpy.context.view_layer.update()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)

    rebuild_root_bone(arm)
    quaternion_pose_bones(arm)
    rest_pose(arm)

    # The armature OBJECT is called `Root_M` in the source, and the bone rebuilt
    # above is called `Root_M` too, because that is what the mesh's vertex group
    # asks for. Godot resolves the collision by renaming the BONE to `Root_M_2`,
    # which is silent, cosmetic in the skeleton and a trap for anything that ever
    # addresses the root by name. Renaming the object is free; renaming the bone
    # would break the vertex group.
    arm.name = "Armature"

    axes = Axes(arm)
    print("build_dog: %s axes -- forward %s up %s side %s, body %.3f x %.3f (armature units)"
          % (breed, _short(axes.forward), _short(axes.up), _short(axes.side),
             axes.body_length, axes.body_height))

    for name, frames in takes.items():
        write_take(arm, name, frames)

    takes["lie"] = author_lie(arm, axes)
    write_take(arm, "lie", takes["lie"])
    takes["growl"] = author_growl(arm, axes)
    write_take(arm, "growl", takes["growl"])
    rest_pose(arm)

    # Rule 8 and rule 9: the pack's 1024 colour map has nothing to contribute to
    # an animal painted from `data/palette/color_bible.tres` at runtime, and a
    # map carried into the `.glb` is a surface the art gates would have to judge.
    for obj in meshes:
        obj.data.materials.clear()

    facing = report_facing(arm, axes, breed)
    top = [obj for obj in bpy.data.objects if obj.parent is None]
    for obj in top:
        obj.matrix_world = Matrix.Rotation(MODEL_YAW, 4, "Z") @ obj.matrix_world
    bpy.context.view_layer.update()
    turned = report_facing(arm, axes, "%s (turned)" % breed)
    if turned >= 0.0:
        raise SystemExit("build_dog: %s still faces glTF +Z after the yaw (%.4f -> %.4f)"
                         % (breed, facing, turned))

    span = rigkit.posed_span(arm, VERIFY_TAKE)
    assert_life_sized(breed, span)
    print("build_dog: %s is %s m on %r, %d triangles, %d bones, %d takes"
          % (breed, span, VERIFY_TAKE, triangles, len(arm.data.bones), len(bpy.data.actions)))
    for name in sorted(takes):
        print("TAKE\t%s\t%s\t%d\t%.3f" % (breed, name, len(takes[name]),
                                          len(takes[name]) / float(SOURCE_FPS)))
    rigkit.clear_pose(arm)

    if kit.has_flag("--no-export"):
        print("build_dog: --no-export, nothing written for %s" % breed)
        return

    rigkit.export_character_glb(destination, materials="NONE")
    print("build_dog: wrote %s" % destination)
    rigkit.verify_export(destination, VERIFY_TAKE, span)


def _short(vector):
    return "(%+.2f %+.2f %+.2f)" % (vector.x, vector.y, vector.z)


main()
