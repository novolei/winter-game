class_name Pigeon
extends Bird

## A rock dove: `Bird` plus `data/wildlife/pigeon.tres`, and nothing else.
##
## ---------------------------------------------------------------------------
## THE 209 LINES THIS FILE USED TO BE
## ---------------------------------------------------------------------------
## `.superpowers/sdd/wave3/task-w3-pigeon-report.md` §4.1 measured the second
## bird in this game at 209 lines of code against 31 of data, and §4.3 named the
## reason: `Pigeon extends Crow` could not change the parent's model, colour or
## yaw by declaring different values, because GDScript forbids a subclass
## redeclaring a parent's constant. It had to rename all three (`DOVE_MODEL`,
## `DOVE_PALETTE_INDEX`, `DOVE_YAW`) and then override `_init`, `_build_rig`,
## `material`, `palette_tone` and `_play` to reach them -- a near-copy of the
## parent in each case.
##
## All five overrides are gone:
##
##   `_init`         -> the beat lengths are `launch_seconds`/`land_seconds`/
##                      `crouch_fraction`/`launch_climb_m`/`mill_speed`/
##                      `cruise_speed` on the species, seeded by `Bird.set_species()`
##   `_build_rig`    -> reads `species.model()` and `species.model_yaw`
##   `material`      -> `palette_tone()` is an instance method now, so it dispatches
##   `palette_tone`  -> `species.tone()`
##   `_play`         -> `species.roles` replaced `Pigeon.TRANSLATION`, and the two
##                      SUBSTITUTIONS it hid (there is no glide take and no
##                      wings-out-on-the-perch take) are now visible AS
##                      substitutions: two roles pointing at one take
##
## ---------------------------------------------------------------------------
## WHAT IS STILL TRUE OF THIS BIRD AND IS NOW IN THE `.tres`
## ---------------------------------------------------------------------------
##   * thirteen takes, of which the behaviour drives seven; `walk`, `run` and the
##     transitions are named but nothing drives them yet
##   * `structure_tones[1]`, one step in from the crow's near-black, because a
##     rock dove is the grey one and two near-black birds at sixteen pixels are
##     one bird -- and not `structure_tones[0]`, which is the farmhouse siding
##     the bird sits on
##   * it does not leave at nightfall: `daylight_only = false`
##   * it will not land on a perch another bird is standing on
##   * `animation/trimming` is **ON** for this pack, which is the opposite of the
##     crow's -- see `data/wildlife/pigeon.tres`'s generator and `BirdTake.seconds`
const SPECIES := preload("res://data/wildlife/pigeon.tres")


func _init() -> void:
	species = SPECIES
