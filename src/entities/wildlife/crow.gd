class_name Crow
extends Bird

## A crow: `Bird` plus `data/wildlife/crow.tres`, and nothing else.
##
## ---------------------------------------------------------------------------
## THIS FILE USED TO BE 993 LINES
## ---------------------------------------------------------------------------
## All of them are now `src/entities/wildlife/bird.gd`, unchanged in behaviour
## and renamed in vocabulary, because none of them were about crows: perch,
## stagger, crouch, rise, wheel, commit, beat, glide, gone, and the whole return
## with its flare and its touchdown frame are what any bird that sits on a thin
## thing and leaves it does.
##
## What made this file 993 lines rather than six was that the three things which
## ARE about crows -- which model, which colour, which way round -- lived in a
## `const preload`, a `static func` and a `const`, and **GDScript will not let a
## subclass redeclare a parent's constant**. So the second bird could not say
## "same timeline, different model": it had to rename all three and override
## every method that read them, at 209 lines a species, forever. See
## `.superpowers/sdd/wave3/task-w3-pigeon-report.md` §4.3.
##
## They are fields on a resource now, and this class exists for one reason.
##
## ---------------------------------------------------------------------------
## WHY IT STILL EXISTS AT ALL, WHICH IS NOT A DESIGN REASON
## ---------------------------------------------------------------------------
## `src/rendering/startle_shot.gd` types its flock as `CrowFlock` and finds it
## with `node is CrowFlock`; `tests/unit/test_crow_*.gd` build subjects with
## `Crow.new()` and count them with `child is Crow`. A third bird needs no such
## class -- `BirdFlock` with a species in the scene hatches plain `Bird`s -- and
## that is the measurement this refactor exists to be able to state. `Crow` and
## `Pigeon` are the vocabulary two dozen existing call sites already speak, not
## a requirement of the design.
##
## ---------------------------------------------------------------------------
## WHERE THE CROW'S OWN NUMBERS WENT
## ---------------------------------------------------------------------------
## Into `tools/generate_bird_species.gd`, which writes the `.tres` below with
## every figure's source beside it -- the take frame ranges out of Malbers'
## `.meta` files, the 0.58 flare measured off `Rav_Land`'s own CG track, the
## 0.45/0.36 balance latch swept over an hour of each wind profile, and
## `model_yaw = PI` measured four ways on the delivered rig.
const SPECIES := preload("res://data/wildlife/crow.tres")


## Before `_ready()`, so the rig is built from the right model and the beat
## lengths are right before the first take plays. `BirdFlock._build_bird()`
## assigns the flock's species over the top, which for a `CrowFlock` is this
## same resource.
func _init() -> void:
	species = SPECIES
