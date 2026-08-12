class_name VitalReadout
extends Resource

## One survival reading's place in the interface: where it stands in the
## permanent stack, what it is called, and what it becomes on section 6.1's ring.
##
## ---------------------------------------------------------------------------
## WHY LAYOUT IS DATA
## ---------------------------------------------------------------------------
## Briefing constraint 4: adding a stat must be a new `.tres` and zero `.gd`
## changes. A readout that knew there were five stats -- or six, which is what
## data/stats actually holds once frostbite is split into hands and feet -- would
## make every new stat a code change, and the survival model would be data-driven
## right up to the point where it has to be looked at.
##
## So nothing in src/ui counts the stats. It reads this table.
##
## ---------------------------------------------------------------------------
## WHY THE PERMANENT STACK AND THE Tab RING SHARE ONE ROW
## ---------------------------------------------------------------------------
## They are two views of one thing, and the failure mode of two tables is that
## somebody reorders one. A stat that is second in the margin and fourth on the
## ring is not a design decision, it is a bug that nobody will ever file.

## Where section 6.1's Tab readout hangs this reading. The ring carries the
## whole-body stats; frostbite is 局部 (GDD section 5) and grows on the
## silhouette's own limbs instead -- 冻伤 不在环上. DIAL is the day dial, which is
## a corner gauge and has no place on a ring drawn around the character at all.
enum Anchor { RING, HANDS, FEET, DIAL }

## Where a reading gets its value.
##
## Five of the six are survival stats. The sixth is the day dial, whose value is
## how much daylight is left and which belongs to WorldClock -- so the source has
## to be a field rather than an assumption, or the layout table could only ever
## describe stats.
enum Source { STAT, DAYLIGHT }

@export var source: Source = Source.STAT

@export var stat: StringName = &""

## A second site for a reading that has two.
##
## GDD section 5: 冻伤是局部的. Frostbite accumulates per limb and the two limbs
## cost different things -- hands slow fire-lighting and spoil aim, feet cost
## speed until treated at a fire. It is NOT a consequence of core temperature and
## it is not one number; it is one reading with two sites, and this is the
## second one.
@export var second_stat: StringName = &""

## What the interface calls it, in the language the design document is written
## in. Not StatDefinition.display_name, which is English and belongs to the
## model rather than to the screen.
@export var label: String = ""

## 手 / 足 for the two frostbite rows, empty for the rest. Section 6.1 prints
## them as one line -- 冻伤 手 82 / 足 61 -- so the rows that merge are the rows
## that share a `label` and differ in this.
@export var limb: String = ""

## Position in the permanent stack and around the ring, low first.
@export var order: int = 0

## Length of the permanent stroke, relative to the others.
##
## Section 6.1 gives core temperature 110 degrees against everyone else's 58 and
## says why: 它是主时钟，是唯一致死的一条，层级必须在视觉上说出来. The permanent
## stack owes the player the same hierarchy in the same proportion, which is what
## this number is -- not a size somebody liked.
@export var track_weight: float = 1.0

## Section 6.1's arc span, in degrees.
@export var ring_degrees: float = 58.0

@export var ring_anchor: Anchor = Anchor.RING

## The icon at the centre of this reading's gauge, named without its extension:
## `assets/ui/icons/<glyph>.png`.
##
## A NAME, not a file. The glyphs are drawn as vector strokes at runtime, in
## palette colour, at whatever weight the reading's state calls for -- so they
## crystallise from a seed like everything else, stay sharp at every framing stop
## and every window size, and can carry emphasis through stroke weight, which is
## the only way rule 3 leaves open once warmth is spoken for. A bitmap can do
## none of those four things.
##
## Naming the glyph rather than the stat is what keeps constraint 4: a new stat
## picks an existing pictograph in data, and no code learns another noun.
@export var glyph: StringName = &"core_temperature"

## The day dial alone: the icon it swaps to after dark. Empty for everything
## else. The swap IS the nightfall signal -- the largest thing on the interface
## changing what it depicts, at the moment GDD section 3 calls a literal
## deadline.
@export var glyph_night: StringName = &""
