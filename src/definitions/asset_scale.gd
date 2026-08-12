class_name AssetScale
extends Resource

## How big a model is allowed to be, in metres.
##
## ---------------------------------------------------------------------------
## THE DEFECT THIS EXISTS FOR
## ---------------------------------------------------------------------------
## `Docs/asset-inventory-low-poly-animals.md` section 1.1, measured on the
## animal package this project draws its wildlife from:
##
##     The pack is authored at three different scales and Godot normalises none.
##     A wolf arrives 15 mm long, imports clean, and passes every art gate.
##
## Every gate this project has says yes to that wolf. Its triangle count is
## right, its material is right, its takes all play, its `.import` is wired the
## way the others are. The only symptom is a creature nobody can see -- which at
## this game's framing reads as "the spawn logic isn't working" and sends you
## looking in a file that has nothing wrong with it.
##
## An FBX carries a `UnitScaleFactor` and Godot divides by 100 whatever it says,
## so a model authored in metres arrives at 1/100 and a model authored in
## decimetres at 1/10. Nothing errors, because nothing is wrong with the file --
## the units are simply not the ones the importer assumed.
##
## ---------------------------------------------------------------------------
## ONE FIELD, NOT TWO, AND WHY
## ---------------------------------------------------------------------------
## `covers` is a res:// path that is either a FOLDER (a band for a whole asset
## class) or a FILE (that one asset's own expectation). There is no flag saying
## which: the gate matches on a path separator and the LONGEST match wins, so a
## per-asset entry beats its folder's band automatically, for the same reason
## `tests/art/test_topology.gd::_budget_for` resolves its triangle budgets that
## way. Two fields would have made "which one applies" a rule someone has to
## remember; one field makes it arithmetic.
##
## ---------------------------------------------------------------------------
## THE NUMBERS COME FROM THE WORLD, NOT FROM THE FILE
## ---------------------------------------------------------------------------
## `tools/generate_asset_scales.gd` writes these, and every band in it is a
## real-world size with the source of the figure in a comment beside it. It does
## NOT measure the models and write a band around what it found: a generator
## that read its expectation off the asset would accept a 15 mm wolf and print
## "verified" doing it, which is the same circularity CLAUDE.md forbids when it
## says a palette test may not read its expected colour out of the palette.
##
## `tools/measure_model_scale.gd` is the other half -- it prints what every
## model actually measures, so a person can compare the two lists. The gate is
## what compares them on every run.
##
## ---------------------------------------------------------------------------
## THE LONGEST DIMENSION, AND WHAT THAT DOES NOT CATCH
## ---------------------------------------------------------------------------
## The band is on the largest of the bounding box's three dimensions, because
## that is the one number that means the same thing for every asset: a bird's is
## its wingspan, a tree's is its height, a truck's is its length. A band on all
## three at once cannot fit a bird that is 0.73 m across and 0.26 m tall without
## being so wide it catches nothing.
##
## So this will not catch a model scaled wrongly on ONE axis, and that is said
## out loud rather than left to be discovered. It catches the whole of the
## defect class above, which is uniform scaling by 10 or by 100.

## What this band covers: a res:// folder, or one model file.
##
## Matched on a path separator, so `res://assets/models/characters` does not
## sweep in a sibling `characters_wip`. The longest matching entry wins.
@export var covers := ""

## Why this band is what it is. Carried in the resource rather than only in the
## generator so a failing gate can print the reasoning at the person reading it.
@export var reason := ""

## The largest dimension of the whole asset's bounding box must be at least this
## many metres.
@export var smallest_m := 0.0

## ...and at most this many.
@export var largest_m := 0.0


## Whether this band has anything to say about `path`.
##
## The trailing-slash rule is the same one `AssetScanner.is_surface_rule_exempt`
## uses, and for the same reason: a prefix match without it lets a folder called
## `props_wip` inherit `props`' band and report green over an asset class nobody
## chose to cover.
func applies_to(path: String) -> bool:
	if covers == "":
		return false
	return path == covers or path.begins_with(covers + "/")


## How specific this band is. Longest wins, so a file beats its folder.
func specificity() -> int:
	return covers.length()


## "" when `size` is inside the band, or the reason it is not.
##
## Takes the whole Vector3 rather than the largest dimension so the message can
## print all three -- a person reading "0.015 m" needs to see whether the asset
## is small or merely thin.
func refusal(size: Vector3) -> String:
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest < smallest_m:
		return ("measures %.4f x %.4f x %.4f m, whose longest side %.4f m is under the %.3f m floor for %s. "
			+ "%s A model that arrives at a hundredth of its size imports cleanly and passes every other gate: "
			+ "set nodes/root_scale in its .import until it measures what it is.") % [
			size.x, size.y, size.z, longest, smallest_m, covers, reason]
	if longest > largest_m:
		return ("measures %.4f x %.4f x %.4f m, whose longest side %.4f m is over the %.3f m ceiling for %s. %s") % [
			size.x, size.y, size.z, longest, largest_m, covers, reason]
	return ""
