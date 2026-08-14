"""Build the small, snow-bedded things that make the farmstead inhabited.

The farm has deliberately few hero silhouettes: the farmhouse, two vehicles,
the shed and the well.  This kit supplies the middle scale between them and the
snow: a fuel stack, a supply cache, a gate marker, and a fallen limb.  They are
four separate assets rather than one scatter mesh so the scene can place each
where its story belongs without repeating a recognisable cluster.
"""

import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import propkit as kit  # noqa: E402


MODELS = {
	"woodpile": ("Woodpile", 200),
	"supply_cache": ("Supply_Cache", 200),
	"field_marker": ("Field_Marker", 200),
	"fallen_limb": ("Fallen_Limb", 200),
	"emergency_sled": ("Emergency_Sled", 200),
	"departure_pack": ("Departure_Pack", 200),
	"chopping_block": ("Chopping_Block", 200),
}


def woodpile() -> None:
    # Logs are deliberately cut short and stacked irregularly: this is a
    # household's remaining fuel, not a decorative timber wall.
    for index, (x, y, z, length) in enumerate((
        (-0.38, -0.18, 0.25, 1.05), (0.34, -0.12, 0.25, 1.18),
        (-0.12, 0.31, 0.52, 0.96), (0.48, 0.24, 0.51, 0.82),
        (-0.47, 0.17, 0.77, 1.10), (0.10, -0.30, 0.78, 1.08),
    )):
        kit.tube("Log_%d" % index, kit.TIMBER, (x, y - length * 0.5, z),
                 (x, y + length * 0.5, z), 0.15, 0.13, sides=5, roll=0.25 * index)
    kit.block("Snow_Cap", kit.SNOW, -0.72, 0.76, -0.66, 0.82, 0.75, 0.90)


def supply_cache() -> None:
    # A crate, a low drum, and a tarp-like snow cap.  No warm paint: fuel and
    # provisions must remain subordinate to the window and the vehicles.
    kit.block("Crate_Low", kit.SIDING, -0.78, -0.02, -0.48, 0.28, 0.0, 0.62)
    kit.block("Crate_High", kit.SKIRT, -0.70, -0.10, -0.42, 0.22, 0.62, 1.12)
    kit.cylinder("Drum", kit.SKIRT, (0.36, -0.16, 0.0), (0.36, -0.16, 0.78), 0.29, sides=6)
    kit.panel("Crate_Snow", kit.SNOW, "+z", 1.14, -0.72, -0.08, -0.44, 0.24)
    kit.disc("Drum_Snow", kit.SNOW, (0.36, -0.16, 0.80), (0.0, 0.0, 1.0), 0.25, sides=6)


def field_marker() -> None:
    # A narrow, slightly leaning field gate post: it marks ownership and turns
    # the road/field junction into a place without becoming a new landmark.
    kit.tube("Post", kit.TIMBER, (0.0, 0.0, -0.22), (0.10, 0.02, 1.52), 0.105, 0.082, sides=4, roll=0.78)
    kit.block("Crossbar", kit.TIMBER, -0.56, 0.64, -0.05, 0.09, 1.00, 1.13)
    kit.panel("Post_Snow", kit.SNOW, "+z", 1.55, -0.08, 0.28, -0.08, 0.18)
    kit.panel("Crossbar_Snow", kit.SNOW, "+z", 1.15, -0.58, 0.65, -0.08, 0.10)


def fallen_limb() -> None:
    # A branch that has come down under snow.  Two forks make it look wind-broken
    # instead of like a log accidentally dropped in a field.
    kit.tube("Main", kit.TIMBER, (-1.12, -0.26, 0.08), (0.96, 0.26, 0.18), 0.13, 0.075, sides=4, roll=0.5)
    kit.tube("Fork_A", kit.TIMBER, (0.22, 0.07, 0.14), (0.64, -0.36, 0.66), 0.08, 0.025, sides=4)
    kit.tube("Fork_B", kit.TIMBER, (0.48, 0.13, 0.16), (1.04, 0.41, 0.48), 0.065, 0.018, sides=4)
    kit.panel("Snow_Main", kit.SNOW, "+z", 0.23, -0.70, 0.78, -0.14, 0.22)


def emergency_sled() -> None:
    # An improvised haul sled, left on the road-facing edge of the yard.  It
    # says "we were going to leave" without adding a second vehicle silhouette.
    for x in (-0.43, 0.43):
        kit.tube("Runner_%s" % x, kit.TIMBER, (x, -0.84, 0.08), (x, 0.78, 0.08),
                 0.065, 0.055, sides=4)
    for y in (-0.48, 0.06, 0.57):
        kit.tube("Slat_%s" % y, kit.TIMBER, (-0.58, y, 0.16), (0.58, y, 0.16),
                 0.055, 0.045, sides=4)
    kit.block("Rolled_Blanket", kit.SIDING, -0.30, 0.30, -0.28, 0.30, 0.17, 0.40)
    kit.panel("Blanket_Snow", kit.SNOW, "+z", 0.42, -0.31, 0.31, -0.28, 0.31)
    kit.tube("Tow_Rope", kit.bare(kit.TIMBER), (0.0, -0.85, 0.09), (0.0, -1.42, 0.09),
             0.028, 0.022, sides=4)


def departure_pack() -> None:
    # A satchel and enamel can tucked beside the pickup.  It reads as a choice
    # made in haste, and stays below the prop horizon so it cannot compete with
    # the house or the stalled vehicle.
    kit.box("Satchel", kit.SIDING, (-0.08, 0.0, 0.26), (0.78, 0.42, 0.48), (0.0, 0.0, 0.14))
    kit.tube("Handle", kit.TIMBER, (-0.22, 0.0, 0.48), (0.18, 0.0, 0.48),
             0.035, 0.028, sides=4)
    kit.cylinder("Can", kit.SKIRT, (0.42, -0.18, 0.0), (0.42, -0.18, 0.39), 0.16, sides=6)
    kit.panel("Satchel_Snow", kit.SNOW, "+z", 0.54, -0.42, 0.25, -0.22, 0.25)
    kit.disc("Can_Snow", kit.SNOW, (0.42, -0.18, 0.405), (0.0, 0.0, 1.0), 0.14, sides=6)


def chopping_block() -> None:
    # The working end of the woodpile: a split stump and an axe-shaped wedge.
    # This gives the fuel stack a human action without adding a character.
    kit.cylinder("Stump", kit.TIMBER, (0.0, 0.0, 0.0), (0.0, 0.0, 0.68), 0.31, sides=6)
    kit.block("Split_Face", kit.SIDING, -0.13, 0.14, -0.16, 0.16, 0.68, 0.74)
    kit.tube("Axe_Handle", kit.TIMBER, (-0.42, -0.10, 0.73), (0.35, 0.12, 0.90),
             0.043, 0.032, sides=4)
    kit.block("Axe_Head", kit.SKIRT, 0.24, 0.38, 0.05, 0.20, 0.84, 0.95)
    kit.disc("Stump_Snow", kit.SNOW, (0.0, 0.0, 0.755), (0.0, 0.0, 1.0), 0.25, sides=6)


def export_one(file: str, name: str, budget: int, build) -> None:
    root = kit.project_root()
    kit.reset()
    build()
    obj = kit.finish(name, budget, label=file)
    kit.export_glb(os.path.join(root, "assets", "models", "props", file + ".glb"))
    kit.save_blend(os.path.join(root, "assets", "source", "props", file + ".blend"))
    low, high = kit.bbox(obj)
    print("%s: %.2f x %.2f x %.2f m" % (file, high[0] - low[0], high[1] - low[1], high[2] - low[2]))


def main() -> None:
    export_one("woodpile", *MODELS["woodpile"], woodpile)
    export_one("supply_cache", *MODELS["supply_cache"], supply_cache)
    export_one("field_marker", *MODELS["field_marker"], field_marker)
    export_one("fallen_limb", *MODELS["fallen_limb"], fallen_limb)
    export_one("emergency_sled", *MODELS["emergency_sled"], emergency_sled)
    export_one("departure_pack", *MODELS["departure_pack"], departure_pack)
    export_one("chopping_block", *MODELS["chopping_block"], chopping_block)


main()
