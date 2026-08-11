"""Build one segment of low post-and-rail fence.

A fence is what turns open snow into *someone's land*. There is none in
`Refs/game ref/level.jpg` -- the reference stops at a ploughed field and a road
-- but the same job is being done there by the field boundary, and a farmstead
with a yard, a truck and a wood pile in front of it wants a line that says where
the yard ends.

Run it -- Blender 5.x, background, no GUI:

    blender --background --python tools/blender/build_fence.py

Optional arguments after `--`:

    --models  <dir>   default assets/models/props
    --source  <dir>   default assets/source/props
    --renders <dir>   default .superpowers/sdd/wave1
    --no-render       skip the acceptance render

---------------------------------------------------------------------------
IT IS A SEGMENT, AND THE SEGMENT'S AXIS IS THE CONTRACT
---------------------------------------------------------------------------
The brief asked for something repeatable along a line rather than one long
fence, and that decides the geometry more than any proportion does.

**One post, at the origin. Rails running from the origin along Blender +Y, which
is Godot -Z.** -Z is the axis `Node3D.look_at()` aims, which is the same
convention `build_power_pole.py` chose for the wire and for the same reason:
laying a run of fence is then two lines per segment and no trigonometry.

    post.global_position = here
    post.look_at(here + along)          # no scale -- see below

**The segment is never scaled**, unlike the wire. Scaling a wire stretches a
uniform tube and is harmless; scaling this would stretch the post with the rails
and give a long span a fat post. So the run is laid out in whole segments and
`SPAN` below is the number the scene has to step by. It is printed at build time
so nothing has to guess it.

The rails overrun both ends by 7 cm so they are buried in the post at each end
and no two faces are ever coplanar (`propkit.BITE`'s reasoning). The consequence
worth knowing: the last segment of a run leaves 7 cm of rail past the final post.
That is 1.6 mm on screen at establishing framing.

---------------------------------------------------------------------------
SNOW ON THE RAILS, AND WHY THE TOP ONE COSTS SIX TIMES THE BOTTOM ONE
---------------------------------------------------------------------------
The camera looks down at 45 degrees and never rotates (rule 1), so snow lying on
a horizontal surface is only ever seen from above. The lower rail's cap is
therefore a flat panel at 2 triangles. The top rail's is a real slab at 12,
because at gameplay framing that edge is the fence's skyline against the snow
behind it and an edgeless panel there reads as a painted stripe.

    post 8 + post cap 2 + 2 rails 24 + top snow 12 + lower snow 2  =  48

48 triangles against the 200 a prop is allowed, which matters because this one
is instanced fourteen times: 672 triangles for the whole run.
"""

import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402

BUDGET = 200
NAME = "Fence_Segment"
FILE = "fence_segment"

WOOD = "PAL_STRUCT_3"       # weathered timber -- a step lighter than the trees'
SNOW = "PAL_SNOW_1"         # near-black, so a fence line does not read as a wood

## The distance between posts, and therefore the step the scene lays segments
## at. 2.6 m is a real post-and-rail spacing and it is short enough that a run
## following a gentle curve does not visibly chord.
SPAN = 2.6

## Buried, so the open base of the post's tube is never above the snow.
ROOT_DEPTH = 0.30
POST_TOP = 1.22
OVERRUN = 0.07


def build():
    # A four-sided tapered tube, no caps: the butt is under the snow and the cap
    # slab sits on the head. 8 triangles where a box would be 12.
    kit.tube("Post", WOOD, (0.0, 0.0, -ROOT_DEPTH), (0.0, 0.0, POST_TOP),
             0.098, 0.082, sides=4, roll=0.7854)
    kit.panel("Post_Snow", SNOW, "+z", POST_TOP + 0.01, -0.108, 0.108, -0.108, 0.108)

    # The gap between the rails is the whole readability of the thing. At 0.24 m
    # apart the two merged into one beam in the acceptance render and the fence
    # read as a guard rail; at 0.44 the sky shows through and it reads as
    # post-and-rail.
    for name, low, high in (("Lower", 0.36, 0.50), ("Upper", 0.94, 1.08)):
        kit.block("Rail_%s" % name, WOOD, -0.058, 0.058,
                  -OVERRUN, SPAN + OVERRUN, low, high)
    # The one edge that has to survive gameplay framing.
    kit.block("Rail_Snow_Upper", SNOW, -0.080, 0.080,
              -OVERRUN, SPAN + OVERRUN, 1.08 - kit.BITE, 1.15)
    kit.panel("Rail_Snow_Lower", SNOW, "+z", 0.51, -0.080, 0.080, -OVERRUN, SPAN + OVERRUN)


def main():
    root = kit.project_root()
    models = kit.argument("--models", os.path.join(root, "assets", "models", "props"))
    source = kit.argument("--source", os.path.join(root, "assets", "source", "props"))
    renders = kit.argument("--renders", os.path.join(root, ".superpowers", "sdd", "wave1"))

    kit.reset()
    build()
    obj = kit.finish(NAME, BUDGET, label=FILE)
    kit.export_glb(os.path.join(models, FILE + ".glb"))
    kit.save_blend(os.path.join(source, FILE + ".blend"))
    print("%s: span %.2f m (Godot -Z), post %.2f m tall -- step the scene by the span"
          % (FILE, SPAN, POST_TOP))
    if not kit.has_flag("--no-render"):
        # Three segments in a row for the render only, so the picture shows what
        # a run looks like rather than what one post looks like. Built after the
        # export, exactly like the scale figure, so none of it reaches the .glb.
        for index in (1, 2):
            offset = SPAN * index
            kit.tube("R_Post_%d" % index, WOOD, (0.0, offset, -ROOT_DEPTH),
                     (0.0, offset, POST_TOP), 0.098, 0.082, sides=4, roll=0.7854)
            kit.panel("R_Cap_%d" % index, SNOW, "+z", POST_TOP + 0.01,
                      -0.108, 0.108, offset - 0.108, offset + 0.108)
            for name, low, high in (("Lower", 0.36, 0.50), ("Upper", 0.94, 1.08)):
                kit.block("R_Rail_%s%d" % (name, index), WOOD, -0.058, 0.058,
                          offset - OVERRUN, offset + SPAN + OVERRUN, low, high)
            kit.block("R_Snow_%d" % index, SNOW, -0.080, 0.080,
                      offset - OVERRUN, offset + SPAN + OVERRUN, 1.08 - kit.BITE, 1.15)
        low, high = kit.bbox(obj)
        run_high = (high[0], SPAN * 3.0, high[2])
        fx, fy = high[0] + 1.5, 1.2
        kit.three_quarter(
            os.path.join(renders, "prop-fence-segment.png"),
            [low, run_high] + kit.figure_corners(fx, fy),
            figure=(fx, fy, 1.5), resolution=(1400, 1050))


main()
