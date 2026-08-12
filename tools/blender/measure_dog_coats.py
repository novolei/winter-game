"""What colour is each dog, measured through its own UVs, against the palette.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/blender/measure_dog_coats.py

Optional arguments after `--`: `--source <dir>`, `--textures <dir>`, `--samples <n>`.

---------------------------------------------------------------------------
WHY THIS EXISTS RATHER THAN A COLOUR PICKED BY EYE
---------------------------------------------------------------------------
The Director's amendment to Art Bible rule 12 puts the companion dog on the warm
list and says the golden retriever is gold. Turning that into a palette entry
needs two numbers nobody has: what colour the dog actually IS, and which of the
twelve is nearest to it.

Neither is answerable from the texture's own histogram.
`Docs/asset-inventory-low-poly-animals.md` section 4 reports all three dogs as
326 colours with `#2B2B2D` at 40.2% -- that is one map counted three times, and
it is a count of PIXELS. Most of a 1024 map is unused UV space, and the parts
that are used are used at wildly different scales: a dog's head takes as much
map as its whole body and is a tenth of its surface.

**The pack ships five dog maps, one per breed variant**, and the number that
matters is area-weighted through the mesh: for every triangle, its texture colour
counted in proportion to the SQUARE METRES of dog it covers. That is what a
viewer sees, and it is a different answer -- measured below, the golden
retriever's `#2B2B2D` nose-and-eye value drops from 40% of the map to under 3% of
the animal.

The palette is read out of `data/palette/color_bible.tres` rather than typed in.
`tools/` is the one place a colour may be hardcoded (binding constraint 6), and
reading the real file is better than being allowed to.
"""

import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

import propkit as kit  # noqa: E402
import rigkit  # noqa: E402

SOURCE_DEFAULT = "H:/Repos/animalpack/Assets/WinterTimeExport"
TEXTURES_DEFAULT = "H:/Repos/animalpack/Assets/polyperfect/Low Poly Animated Animals/Textures/Animals"

## [breed, the FBX that carries the mesh, the maps the pack ships for it].
##
## Two of the three have variants. Which one Unity had assigned is not recorded
## in the re-export -- the `Lit` material came across with no image at all -- so
## every variant is measured and the choice is made in the report rather than
## guessed here.
BREEDS = [
    ("chihuahua", "SKM_Dog_Chihuahua_Rig@Dog_Chihuahua_Idle.fbx",
     ["Dog_Chihauhau_COL_1k.png", "Dog_Chihauhau_Black_COL_1k.png"]),
    ("golden_retriever", "SKM_Dog_GoldenRetriever_Rig@Dog_GoldenRetriever_Idle.fbx",
     ["Dog_GoldenRetriever_COL_1k.png"]),
    ("great_dane", "SKM_Dog_GreatDane_Rig@Dog_GreatDane_Idle.fbx",
     ["Dog_GreatDane_Brown_COL_1k.png", "Dog_GreatDane_Black_COL_1k.png"]),
]

## Barycentric points per triangle. Three corners and the centroid would miss a
## seam running through a face; seven spread points is enough that no island
## boundary decides the answer on a 900-triangle animal.
SAMPLES = [
    (1 / 3.0, 1 / 3.0), (0.6, 0.2), (0.2, 0.6), (0.2, 0.2),
    (0.5, 0.25), (0.25, 0.5), (0.45, 0.45),
]


def palette(project_root):
    """The twelve, read out of the shipped `.tres`.

    Godot writes them as linear floats inside `Array[Color](...)`, grouped by
    family. Parsed rather than typed so this cannot drift from the game.
    """
    path = os.path.join(project_root, "data", "palette", "color_bible.tres")
    families = {}
    for line in open(path, encoding="utf-8"):
        if "_tones = Array[Color]" not in line:
            continue
        family = line.split("_tones")[0].strip()
        colours = []
        for chunk in line.split("Color(")[1:]:
            parts = chunk.split(")")[0].split(",")
            colours.append(tuple(float(p) for p in parts[:3]))
        families[family] = colours
    return families


def to_srgb(linear):
    """The sRGB transfer curve, applied to a Blender pixel to get its byte value.

    ---------------------------------------------------------------------
    APPLIED TO THE TEXTURE AND **NOT** TO THE PALETTE, WHICH COST A ROUND
    ---------------------------------------------------------------------
    Blender hands back `image.pixels` already de-gamma'd into scene linear for an
    sRGB-tagged PNG, so this puts the texture back into the byte values a person
    reading `#D2BA94` would recognise. That part is right.

    The first pass ALSO ran the palette through it, on the reasoning that Godot
    stores colours linear. That is true of the storage and false of the use.
    Briefing trap 7: this project's cel shader writes the palette value straight
    into `DIFFUSE_LIGHT` with `ALBEDO = vec3(1.0)`, so the number in the `.tres`
    is a DISPLAY value -- the snow's `#8FB0D8` is what the snow looks like, and
    every document in this repository quotes it that way.

    MEASURED on a saved frame to settle it rather than believe it: the snow
    arrives as `#A6CBF9`, which is `#8FB0D8` times 1.155 on all three channels --
    a flat gain, not a curve. A gain cancels in a nearest-neighbour comparison; a
    gamma does not, and running the palette through one reordered the warm
    entries and would have chosen a different colour for the dog.

    So: texture to bytes, palette left alone, and both compared as bytes.
    """
    out = []
    for value in linear:
        value = max(0.0, min(1.0, value))
        out.append(value * 12.92 if value <= 0.0031308 else 1.055 * value ** (1 / 2.4) - 0.055)
    return tuple(out)


def hexof(srgb):
    return "#%02X%02X%02X" % tuple(int(round(c * 255.0)) for c in srgb)


def distance(a, b):
    """Weighted RGB, the cheap perceptual distance. Green counts most because
    the eye does; blue least. Good enough to rank twelve entries that are not
    close to each other, and it says so rather than pretending to be CIEDE2000.
    """
    return math.sqrt(2.0 * (a[0] - b[0]) ** 2 + 4.0 * (a[1] - b[1]) ** 2 + 3.0 * (a[2] - b[2]) ** 2)


def coat_of(mesh_object, image):
    """Area-weighted colour histogram of one mesh under one texture.

    Returns [(srgb, square metres), ...] sorted by area, plus the total area.
    """
    mesh = mesh_object.data
    mesh.calc_loop_triangles()
    uv_layer = mesh.uv_layers.active
    if uv_layer is None:
        raise SystemExit("measure_dog_coats: %s has no UVs" % mesh_object.name)
    width, height = image.size
    pixels = list(image.pixels)
    matrix = mesh_object.matrix_world

    by_colour = {}
    total = 0.0
    for triangle in mesh.loop_triangles:
        corners = [matrix @ mesh.vertices[v].co for v in triangle.vertices]
        area = (corners[1] - corners[0]).cross(corners[2] - corners[0]).length * 0.5
        if area <= 0.0:
            continue
        total += area
        uvs = [uv_layer.data[loop].uv for loop in triangle.loops]
        share = area / float(len(SAMPLES))
        for u_weight, v_weight in SAMPLES:
            w = 1.0 - u_weight - v_weight
            u = uvs[0].x * w + uvs[1].x * u_weight + uvs[2].x * v_weight
            v = uvs[0].y * w + uvs[1].y * u_weight + uvs[2].y * v_weight
            x = min(width - 1, max(0, int(u * width)))
            y = min(height - 1, max(0, int(v * height)))
            index = (y * width + x) * 4
            # Blender hands back the image already de-gamma'd into scene linear
            # for an sRGB texture, so it is converted back here rather than
            # compared in two different spaces.
            key = hexof(to_srgb(pixels[index:index + 3]))
            by_colour[key] = by_colour.get(key, 0.0) + share
    ordered = sorted(by_colour.items(), key=lambda row: -row[1])
    return ordered, total


def main():
    root = kit.project_root()
    source = kit.argument("--source", SOURCE_DEFAULT)
    textures = kit.argument("--textures", TEXTURES_DEFAULT)
    families = palette(root)
    entries = []
    for family, colours in families.items():
        for index, colour in enumerate(colours):
            # NOT through `to_srgb`. See its docstring: the `.tres` holds display
            # values, and converting them reorders the warm entries.
            entries.append(("%s[%d]" % (family, index), colour))

    print("measure_dog_coats: the palette, as the frame renders it")
    for name, srgb in entries:
        print("   %-14s %s" % (name, hexof(srgb)))

    for breed, model, maps in BREEDS:
        kit.reset()
        rigkit.import_fbx(os.path.join(source, model))
        meshes = rigkit.meshes()
        if not meshes:
            raise SystemExit("measure_dog_coats: %s holds no mesh" % model)
        for name in maps:
            path = os.path.join(textures, name)
            if not os.path.exists(path):
                print("measure_dog_coats: %s missing" % path)
                continue
            image = bpy.data.images.load(path, check_existing=True)
            ordered, total = coat_of(meshes[0], image)
            print("")
            print("measure_dog_coats: %s / %s -- %.4f m2 of skin, %d distinct colours"
                  % (breed, name, total, len(ordered)))
            # The area-weighted mean, which is what the animal reads as at the
            # size this game draws it: at fifty pixels the markings average out
            # and the silhouette carries one value.
            mean = [0.0, 0.0, 0.0]
            for key, area in ordered:
                for axis in range(3):
                    mean[axis] += int(key[1 + axis * 2:3 + axis * 2], 16) / 255.0 * area
            mean = tuple(c / max(total, 1e-9) for c in mean)
            for key, area in ordered[:6]:
                srgb = tuple(int(key[1 + i * 2:3 + i * 2], 16) / 255.0 for i in range(3))
                nearest = min(entries, key=lambda entry: distance(entry[1], srgb))
                print("   %s %6.2f%% of the animal   nearest %-14s %s  d=%.3f"
                      % (key, 100.0 * area / total, nearest[0], hexof(nearest[1]),
                         distance(nearest[1], srgb)))
            nearest = min(entries, key=lambda entry: distance(entry[1], mean))
            print("   MEAN %s                    nearest %-14s %s  d=%.3f"
                  % (hexof(mean), nearest[0], hexof(nearest[1]), distance(nearest[1], mean)))
            print("   ranked against every warm entry:")
            for name_of, srgb in entries:
                if not name_of.startswith("warm"):
                    continue
                print("      %-14s %s  d(mean)=%.3f" % (name_of, hexof(srgb), distance(srgb, mean)))


main()
