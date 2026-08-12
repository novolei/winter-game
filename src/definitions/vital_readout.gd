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

## Where section 6.1 hangs this reading. The ring carries the whole-body stats;
## frostbite is 局部 (GDD section 5) and grows on the silhouette's own limbs
## instead -- 冻伤 不在环上.
enum Anchor { RING, HANDS, FEET }

@export var stat: StringName = &""

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

## Which pictograph stands in the middle of this reading's gauge.
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
@export var glyph: StringName = &"crystal"
