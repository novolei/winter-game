class_name BirdTake
extends Resource

## One animation take a bird can play, and where it comes from.
##
## ---------------------------------------------------------------------------
## TWO DELIVERY SHAPES, ONE ROW
## ---------------------------------------------------------------------------
## The two bird packs this game has taken animals from lay their clips out in
## opposite ways, and a take table that could only describe one of them is why
## the second bird needed a second `*_animations.gd`:
##
##   FRAME RANGES   Malbers' ravens. An `.FBX` holds **one long take** and the
##                  clips are frame ranges named only in a Unity `.meta` file.
##                  `Raven Fly.FBX` is a single 512-frame take carrying fifteen
##                  clips end to end, so there is nothing on disk to import as
##                  "the glide" -- it has to be cut out.
##                  -> `source_path` names the file, `first_frame`/`last_frame`
##                     name the range, and `BirdAnimations` slices it.
##
##   NAMED STACKS   The low-poly animal pack. Each clip is its own FBX
##                  `AnimationStack`, so Godot's importer produces them already
##                  separated and already named. There is nothing to cut.
##                  -> `source_name` is the pack's own name for it and the
##                     frame numbers stay at -1.
##
## Which shape applies is read off the data (`is_sliced()`), not declared, for
## the same reason `AssetScale` has one `covers` field instead of a folder flag
## and a file flag: two fields make "which one applies" a rule somebody has to
## remember, and one field makes it arithmetic.

## The name the game asks for: `perch`, `fly`, `idle_left`. The library holds it
## under this, so `_play()` composes "crow/perch" from the species' library name
## and this.
@export var take_name := &""

## Which file it lives in. Empty means the species' own model file, which is the
## common case for a pack that ships mesh and takes together.
@export var source_path := ""

## The pack's own name for it, for a delivery that names its takes.
##
## THIS FIELD IS WHY THE MATCHING IS DEFENSIVE. The dove pack's exporter wrote
## `Dove_Run to Idle ` with a **trailing space**, and a lookup that does not
## carry the space finds nothing and drops the take in silence -- which it did,
## on the pigeon's first run. `BirdAnimations.matching_name()` falls back to a
## whitespace-insensitive match and warns, so a stray space costs a warning
## rather than a missing animation. The value stored here is still the file's
## own byte-for-byte name, so the shipped configuration matches exactly and the
## warning never fires.
@export var source_name := ""

## The frame range inside a long take, or -1 for a take that arrived on its own.
@export var first_frame := -1
@export var last_frame := -1

## Whether it cycles. Every take in the dove pack imports LOOP_NONE including
## the idles and the flight cycle, so this is not cosmetic: a perched bird whose
## idle does not loop plays four seconds of bird and then stands frozen.
@export var loops := false

## Whether the take's own root travel is flattened to a single key.
##
## A take that moves the bird AND code that moves the bird are two answers to
## one question, and the visible result is a bird travelling at twice the speed
## anything asked for. `Rav_TakeOff` drives the CG bone 0.30 m up and 0.37 m
## forward across 29 frames; the dove's takes move their root by at most 33 mm,
## which is a wingbeat bob rather than travel, so nothing there needs taking
## away from the animator.
@export var in_place := false

## How long it must import at, in seconds.
##
## THE CHEAPEST THING IN THE PIGEON DELIVERY AND THE ONE THAT CAUGHT THE TRAP.
## `animation/trimming` has to be ON for one pack and OFF for the other; get it
## wrong and takes import carrying the whole preceding timeline as dead air
## (`idle_right` measured at 8.958 s against a true 3.958 s). The symptom is a
## bird that lands on a wire and stands still for five seconds, which errors
## nothing. Asserting the length turns that into a red run.
@export var seconds := -1.0


## Whether this row describes a range inside a longer take.
func is_sliced() -> bool:
	return first_frame >= 0 and last_frame > first_frame


## How long it should be, from the frame range when it has one and from
## `seconds` otherwise. Both are kept so the two can be checked against each
## other -- a generator that derived one from the other could not be wrong.
func expected_seconds(fps: float) -> float:
	if is_sliced() and fps > 0.0:
		return float(last_frame - first_frame) / fps
	return seconds


## The file this take is cut from: its own, or the species' model.
func file(model_path: String) -> String:
	return source_path if source_path != "" else model_path
