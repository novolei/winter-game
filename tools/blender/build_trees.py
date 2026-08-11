"""Build the three bare winter trees.

Art Bible rule 7 is the whole spec: *"trees are silhouettes -- completely
leafless dead branches, value #131C30, limbs as thin elongated blocks or crossed
planes."* In `Refs/game ref/level.jpg` they read as ink drawings against the
snow, and nothing else about them matters -- there is no bark, no leaf, no
colour variation, and at the game's distance there is no surface at all. There
is only the outline.

Run it -- Blender 5.x, background, no GUI:

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/build_trees.py

Optional arguments after `--`:

    --models  <dir>   default assets/models/vegetation
    --source  <dir>   default assets/source/vegetation
    --renders <dir>   default .superpowers/sdd/wave1
    --no-render       skip the acceptance renders

It never touches an open Blender session: it runs in its own background process
and starts from factory settings with an empty scene.

---------------------------------------------------------------------------
WHY TAPERED THREE-SIDED TUBES, AND WHAT 300 TRIANGLES BUYS
---------------------------------------------------------------------------
Rule 6 allows a tree 300 triangles. A branch modelled as a box costs 12, so a
box tree is 25 branches and reads as a coat rack. The cheapest thing that still
reads as a branch from every angle is a **three-sided tapered tube**: 6
triangles for a length of limb, and 3 for a twig that tapers to a point, with no
end caps anywhere because every limb starts inside its parent (see
`propkit.tube`). That is a quarter the cost of a box per branch, and it is the
only reason these trees have thirty-odd twig tips rather than eight.

A three-sided section is not visible on a limb 30 mm thick. A crossed-plane tree
would be cheaper still and is allowed by rule 7, but crossed planes need a
cutout texture to read as twigs, and rule 5.0's line on in-game textures is
that this project does not generate any.

**These trees are sparser than the reference.** `level.jpg` is a painting and its
big tree has well over a hundred visible twig ends; 300 triangles buys about
thirty. The response was to spend the budget on *spread* rather than on depth --
a wide, forked, asymmetric crown with long terminal twigs reads as a bare tree
at the game's orthographic distance, where a denser but smaller crown would read
as a blob. Counts and reasoning are in the report; nothing here exceeds 300.

---------------------------------------------------------------------------
THE THREE VARIANTS
---------------------------------------------------------------------------
Scattering one tree three times reads as wallpaper, so the variants differ in
the two things the eye actually reads at distance -- overall proportion and
crown shape -- not in twig noise:

    A  the yard tree     8.4 m, tall clear trunk, high spreading crown, and one
                         long near-horizontal low limb. The tire swing hangs
                         from that limb; its tip is printed by this script and
                         recorded in the report.
    B  the field tree    5.6 m, forks low into four limbs, vase-shaped, no clear
                         trunk. The one in the reference's lower left.
    C  the wind sapling  3.9 m, thin, leaning away from the weather, sparse and
                         one-sided. The one in the reference's right margin.

All three are `PAL_STRUCT_4` throughout -- rule 7's `#131C30`, resolved from the
palette at import. One material, one mesh, one draw call each.

Origins are at ground level, at the trunk's centre, so a tree drops onto Y=0
with no offset. The first trunk segment starts 0.25 m below zero so the base is
still solid when it is set into snow.
"""

import math
import os
import random
import sys

# Importing propkit would otherwise drop a __pycache__ into the repo on every
# run, which is generated output in a source tree and nobody's to review.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mathutils import Vector  # noqa: E402  (bpy must be importable first)

import propkit as kit  # noqa: E402

BUDGET = 300
WOOD = kit.TIMBER            # PAL_STRUCT_4 -- rule 7's #131C30

## How deep the trunk starts below Y=0, so that setting a tree into snow does
## not open the bottom of the tube (propkit.tube writes no end caps).
ROOT_DEPTH = 0.25


def _rotate_off(direction, angle, roll):
    """`direction` tilted by `angle` about an axis chosen by `roll`."""
    u, v = kit.frame(direction)
    axis = u * math.cos(roll) + v * math.sin(roll)
    return (Vector(direction).normalized() * math.cos(angle)
            + axis * math.sin(angle)).normalized()


class Tree(object):
    """One tree. Everything it needs to know about itself is in the spec dict;
    the recursion below has no numbers of its own."""

    def __init__(self, spec):
        self.spec = spec
        self.rng = random.Random(spec["seed"])
        self.tips = 0
        self.limbs = 0

    # -- the recursion ----------------------------------------------------
    def limb(self, base, direction, length, radius, depth, max_depth):
        """Emit one limb -- a chain of segments -- and recurse into its children.

        A limb at `max_depth` is a twig: its last segment tapers to a point and
        costs 3 triangles instead of 6, and it has no children.
        """
        levels = self.spec["levels"]
        spec = levels[min(depth, len(levels) - 1)]
        segs = spec["segs"]
        terminal = depth >= max_depth
        seg_len = length / segs
        # A limb that tapers to nearly nothing over its own length reads as a
        # needle. Real bare wood holds most of its thickness and then forks, so
        # the taper here is gentle and the *fork* is what makes a branch thin.
        tip_radius = 0.0 if terminal else radius * spec["taper"]
        p = Vector(base)
        d = Vector(direction).normalized()
        r = radius
        for s in range(segs):
            last = (s == segs - 1)
            # A limb that curls as it goes reads as grown rather than assembled.
            # `lift` biases the curl upward, which is what bare wood does.
            wobble = Vector((self.rng.uniform(-1.0, 1.0),
                             self.rng.uniform(-1.0, 1.0),
                             spec["lift"] + self.rng.uniform(-0.2, 0.2)))
            d = (d + wobble * spec["curve"]).normalized()
            nxt = p + d * seg_len
            r_next = radius + (tip_radius - radius) * ((s + 1.0) / segs)
            kit.tube("Limb_%d" % self.limbs, WOOD, p, nxt, r,
                     0.0 if (last and terminal) else r_next,
                     sides=spec.get("sides", 3),
                     roll=self.rng.uniform(0.0, math.pi))
            self.limbs += 1
            if last and terminal:
                self.tips += 1
            p, r = nxt, r_next
        # Short twigs sprouting along the limb rather than only at its end.
        # Three triangles each, and they are what fills the crown's perimeter:
        # without them a tree is a starburst of long spokes.
        for i in range(spec.get("twigs", 0)):
            t = (i + 0.65) / (spec["twigs"] + 0.3)
            at = Vector(base) + (p - Vector(base)) * t
            self._side_twig(at, d, length, radius * (1.0 - 0.4 * t))
        if terminal:
            return
        child = levels[min(depth + 1, len(levels) - 1)]
        roll0 = self.rng.uniform(0.0, 2.0 * math.pi)
        for i in range(child["count"]):
            # Child 0 carries the parent's line on; the rest fork away from it.
            # A tree whose children all diverge equally reads as an antenna.
            share = 0.38 if i == 0 else 1.0
            angle = math.radians(child["spread"] * share
                                 + self.rng.uniform(-child["jitter"], child["jitter"]))
            roll = roll0 + 2.0 * math.pi * i / child["count"] + self.rng.uniform(-0.5, 0.5)
            self.limb(p, _rotate_off(d, angle, roll),
                      length * child["length"] * self.rng.uniform(0.82, 1.16),
                      r * child["radius"], depth + 1, max_depth)

    def _side_twig(self, at, direction, length, radius):
        # Shallow, not perpendicular: a twig leaving its limb at a right angle
        # reads as a thorn, which was the first version's most obvious tell.
        angle = math.radians(self.rng.uniform(32.0, 56.0))
        d = _rotate_off(direction, angle, self.rng.uniform(0.0, 2.0 * math.pi))
        kit.tube("Twig_%d" % self.limbs, WOOD, at,
                 at + d * length * self.rng.uniform(0.30, 0.46),
                 radius * 0.62, 0.0, sides=3)
        self.limbs += 1
        self.tips += 1

    # -- the trunk --------------------------------------------------------
    def build(self):
        spec = self.spec
        trunk = spec["trunk"]
        pts = [Vector((0.0, 0.0, -ROOT_DEPTH))]
        d = Vector(trunk["lean"]).normalized()
        seg_len = (trunk["height"] + ROOT_DEPTH) / trunk["segs"]
        radii = [trunk["base_r"]]
        p = pts[0]
        r = trunk["base_r"]
        for s in range(trunk["segs"]):
            d = (d + Vector((self.rng.uniform(-0.05, 0.05),
                             self.rng.uniform(-0.05, 0.05), 0.0))).normalized()
            nxt = p + d * seg_len
            r_next = trunk["base_r"] + (trunk["top_r"] - trunk["base_r"]) * ((s + 1.0) / trunk["segs"])
            # The trunk gets four sides where every limb gets three. It is the
            # one part thick enough for a triangular section to read as a
            # plank, and two extra triangles a segment is the cheapest fix.
            kit.tube("Trunk_%d" % s, WOOD, p, nxt, r, r_next,
                     sides=trunk.get("sides", 4), roll=math.pi / 4.0)
            self.limbs += 1
            pts.append(nxt)
            radii.append(r_next)
            p, r = nxt, r_next
        self.trunk_direction = d

        anchors = {}
        for primary in spec["primaries"]:
            at = primary["at"]
            base = pts[at]
            direction = Vector((
                math.cos(math.radians(primary["el"])) * math.sin(math.radians(primary["az"])),
                -math.cos(math.radians(primary["el"])) * math.cos(math.radians(primary["az"])),
                math.sin(math.radians(primary["el"])),
            ))
            self.limb(base, direction, primary["length"],
                      radii[at] * primary["radius"], 0, primary["depth"])
            if primary.get("anchor"):
                # Where the tire swing hangs from. Reported rather than guessed
                # at by whoever places the scene.
                anchors[primary["anchor"]] = tuple(
                    round(v, 2) for v in (base + direction * primary["length"] * 0.72))
        return anchors


# ---------------------------------------------------------------------------
# The three trees. Every number that decides what a tree looks like is here.
# ---------------------------------------------------------------------------
## Per-depth shape. `count`/`spread`/`length`/`radius` describe how a limb at
## this depth is born from its parent; `segs`/`taper`/`curve`/`lift`/`twigs`
## describe what it does once it exists.
##
##   segs    segments in the limb (2 gives it a visible bend, and costs double)
##   taper   how much radius it keeps end to end -- gentle, see limb()
##   curve   how hard each segment swings off the last
##   lift    upward bias in that swing
##   twigs   short pointed twigs sprouting along the limb, 3 triangles each
##   count   children at the next depth
##   spread  degrees a child forks away by (child 0 forks by 38% of it)
##   length  the child's length as a fraction of this limb's
##   radius  the child's base radius as a fraction of this limb's tip
LEVELS_FULL = [
    # depth 0 -- the primary limbs off the trunk
    dict(segs=2, taper=0.72, curve=0.15, lift=1.30, twigs=0, count=0, spread=0.0, jitter=0.0, length=0.00, radius=0.00),
    # depth 1 -- secondaries
    dict(segs=1, taper=0.75, curve=0.14, lift=1.10, twigs=1, count=2, spread=30.0, jitter=7.0, length=0.66, radius=0.76),
    # depth 2 -- tertiaries
    dict(segs=1, taper=0.75, curve=0.13, lift=0.90, twigs=0, count=2, spread=36.0, jitter=9.0, length=0.60, radius=0.74),
    # depth 3 -- twigs, tapering to a point
    dict(segs=1, taper=0.00, curve=0.11, lift=0.70, twigs=0, count=2, spread=42.0, jitter=11.0, length=0.50, radius=0.78),
]

VARIANTS = [
    dict(
        name="Tree_Bare_A",
        file="tree_bare_a",
        seed=20260811,
        note="the yard tree -- tall clear trunk, high crown, one long low limb for the swing",
        trunk=dict(segs=3, height=3.30, base_r=0.24, top_r=0.155, lean=(0.05, -0.03, 1.0)),
        levels=LEVELS_FULL,
        primaries=[
            # Three limbs off the top of the trunk make the crown.
            dict(at=3, az=-40.0, el=70.0, length=2.30, radius=0.88, depth=3),
            dict(at=3, az=86.0, el=63.0, length=2.45, radius=0.92, depth=3),
            dict(at=3, az=200.0, el=74.0, length=2.20, radius=0.84, depth=3),
            # ...and one long, near-horizontal limb lower down, bare to two
            # levels. This is the limb the tire swing hangs from, and it is bare
            # in the reference too: a limb with a rope on it has been climbed.
            dict(at=2, az=-100.0, el=20.0, length=2.80, radius=0.66, depth=2,
                 anchor="swing"),
        ],
    ),
    dict(
        name="Tree_Bare_B",
        file="tree_bare_b",
        seed=770914,
        note="the field tree -- forks low, vase-shaped, no clear trunk",
        trunk=dict(segs=2, height=1.45, base_r=0.20, top_r=0.150, lean=(-0.04, 0.05, 1.0)),
        levels=LEVELS_FULL,
        primaries=[
            dict(at=2, az=-24.0, el=74.0, length=1.95, radius=0.82, depth=3),
            dict(at=2, az=74.0, el=66.0, length=1.85, radius=0.78, depth=3),
            dict(at=2, az=162.0, el=78.0, length=2.05, radius=0.84, depth=3),
            dict(at=1, az=248.0, el=56.0, length=1.70, radius=0.64, depth=2),
        ],
    ),
    dict(
        name="Tree_Bare_C",
        file="tree_bare_c",
        seed=41255,
        note="the wind sapling -- thin, leaning, sparse and one-sided",
        trunk=dict(segs=2, height=1.70, base_r=0.130, top_r=0.098, lean=(0.20, -0.09, 1.0)),
        levels=[
            dict(segs=1, taper=0.74, curve=0.15, lift=1.20, twigs=1, count=0, spread=0.0, jitter=0.0, length=0.00, radius=0.00),
            dict(segs=1, taper=0.75, curve=0.14, lift=1.00, twigs=1, count=2, spread=34.0, jitter=8.0, length=0.70, radius=0.76),
            dict(segs=1, taper=0.00, curve=0.12, lift=0.80, twigs=0, count=2, spread=40.0, jitter=10.0, length=0.56, radius=0.78),
            dict(segs=1, taper=0.00, curve=0.11, lift=0.70, twigs=0, count=2, spread=44.0, jitter=11.0, length=0.52, radius=0.66),
        ],
        primaries=[
            dict(at=2, az=18.0, el=70.0, length=1.35, radius=0.88, depth=2),
            dict(at=2, az=96.0, el=62.0, length=1.20, radius=0.82, depth=2),
            dict(at=2, az=-72.0, el=76.0, length=1.30, radius=0.86, depth=2),
            dict(at=1, az=44.0, el=52.0, length=1.10, radius=0.64, depth=2),
            dict(at=1, az=-124.0, el=58.0, length=1.00, radius=0.60, depth=2),
        ],
    ),
]


def main():
    root = kit.project_root()
    models = kit.argument("--models", os.path.join(root, "assets", "models", "vegetation"))
    source = kit.argument("--source", os.path.join(root, "assets", "source", "vegetation"))
    renders = kit.argument("--renders", os.path.join(root, ".superpowers", "sdd", "wave1"))

    for spec in VARIANTS:
        kit.reset()
        tree = Tree(spec)
        anchors = tree.build()
        obj = kit.finish(spec["name"], BUDGET, label=spec["file"])
        print("%s: %d limbs, %d twig tips -- %s"
              % (spec["file"], tree.limbs, tree.tips, spec["note"]))
        for label, at in anchors.items():
            print("%s: %s anchor at %s (local metres, Blender Z-up)"
                  % (spec["file"], label, at))
        kit.export_glb(os.path.join(models, spec["file"] + ".glb"))
        kit.save_blend(os.path.join(source, spec["file"] + ".blend"))
        if not kit.has_flag("--no-render"):
            low, high = kit.bbox(obj)
            print("%s: %.2f m tall, crown %.2f x %.2f m"
                  % (spec["file"], high[2], high[0] - low[0], high[1] - low[1]))
            fx, fy = high[0] + 0.9, low[1] - 0.5
            kit.three_quarter(
                os.path.join(renders, "prop-%s.png" % spec["file"].replace("_", "-")),
                [low, high, (low[0], low[1], 0.0), (high[0], high[1], 0.0)]
                + kit.figure_corners(fx, fy),
                figure=(fx, fy, 0.5), resolution=(1100, 1400))


main()
