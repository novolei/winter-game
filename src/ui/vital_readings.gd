class_name VitalReadings
extends RefCounted

## What a survival reading is WORTH, and what state that puts it in. No pixels,
## no placement, no lifetime.
##
## ---------------------------------------------------------------------------
## THIS IS THE SEAM BETWEEN THE MODEL AND EVERYTHING THAT SHOWS IT
## ---------------------------------------------------------------------------
## It used to live inside the permanent corner cluster, which meant that deleting
## the cluster would have deleted the reading with it. It does not belong to a
## view: section 5.2's note, section 6.1's Tab ring and anything else that has to
## know how the body is doing all want the same answer to the same question, and
## two of them working it out separately is how two parts of one game come to
## disagree about what "in trouble" means.
##
##   In front of this seam -- values, thresholds, states:
##     SurvivalSystem   the model. Owns the numbers and announces the crossings
##     VitalLayout      which readings exist, in what order, and which have two
##                      sites. Data, so a sixth stat is a .tres and no .gd
##     VitalTone        the threshold table: what a fraction MEANS
##     this class       the two of them put together, per reading
##
##   Behind it -- pixels:
##     VitalStroke / VitalPaint / Engraved, ThresholdNote, and whatever draws next
##
## ---------------------------------------------------------------------------
## IT CACHES NOTHING, AND THAT IS THE FIX RATHER THAN A STYLE
## ---------------------------------------------------------------------------
## This project has three times shipped a listener that could only ever learn
## about transitions, and therefore never learned the state it was born into. The
## structural answer is to hold no state at all: every question here is answered
## by asking the model at the moment it is asked. A reading is correct on its
## first frame whatever happened before the reader existed, because there is
## nowhere for a stale answer to be kept.
##
## Crossings are still events -- see ThresholdSurfacing. A crossing is a MOMENT
## and rediscovering it by comparing this frame with the last would miss exactly
## the ones the model sub-steps at 0.25 s to catch.

const LAYOUT_PATH := "res://data/ui/vital_layout.tres"

var _layout: VitalLayout = null
var _model = null


## Loads the layout from data unless one was injected. Idempotent.
func build() -> void:
	if _layout == null and ResourceLoader.exists(LAYOUT_PATH):
		_layout = ResourceLoader.load(LAYOUT_PATH) as VitalLayout


func set_layout(layout: VitalLayout) -> void:
	_layout = layout


## The survival model -- `/root/SurvivalSystem` in a run, an injected one in a
## test. Untyped because the model is an autoload script with no class_name.
func set_model(model) -> void:
	_model = model


func layout() -> VitalLayout:
	return _layout


func model():
	return _model


## The readings, in the order the interface draws them. Empty with no layout,
## which is a legal inert state: a missing data file should cost the readout and
## not the run.
func rows() -> Array[VitalReadout]:
	var empty: Array[VitalReadout] = []
	return empty if _layout == null else _layout.ordered()


func row_for(stat: StringName) -> VitalReadout:
	return null if _layout == null else _layout.row_for(stat)


func has(stat: StringName) -> bool:
	return _layout != null and _layout.has_row(stat) and _model != null and _model.has_stat(stat)


## ONE SITE, unfolded: `{stat, fraction, depleted, recovering, state}`.
##
## For an announcement that NAMES a place on the body. 手指不听使唤了 with the
## feet's number beside it would be a lie, however true the number is, so a
## caller that has already been told which stat crossed asks for that one.
##
## An unknown reading comes back as a full, steady one rather than as nothing.
## A caller with no model at all -- a scene with no run going, a screenshot
## harness, a menu -- should show a well man, not a dead one.
func read_site(stat: StringName) -> Dictionary:
	var out := {
		"stat": stat,
		"fraction": 1.0,
		"depleted": false,
		"recovering": false,
		"state": VitalTone.State.STEADY,
	}
	if _model == null or stat == &"" or not _model.has_stat(stat):
		return out
	out["fraction"] = _model.fraction_of(stat)
	out["depleted"] = _model.is_depleted(stat)
	out["recovering"] = _model.net_rate_of(stat) > 0.0
	out["state"] = VitalTone.state_for(float(out["fraction"]), bool(out["depleted"]))
	return out


## ONE READING, folded over every site it has, showing the WORSE.
##
## GDD section 5 makes frostbite local -- hands slow fire-lighting and spoil aim,
## feet cost speed -- and a player acts on whichever limb is further gone, so an
## average would hide the one that matters behind the one that does not.
##
## This is the form anything asking "how is he" wants. read_site() is the form
## something naming a limb wants. They differ for exactly one reading today and
## the difference is the whole reason both exist.
func read(stat: StringName) -> Dictionary:
	var out := read_site(stat)
	var row := row_for(stat)
	if row == null or row.second_stat == &"" or row.second_stat == stat:
		return out
	var other := read_site(row.second_stat)
	if float(other["fraction"]) >= float(out["fraction"]):
		return out
	other["stat"] = stat
	return other


func fraction_of(stat: StringName) -> float:
	return float(read(stat)["fraction"])


func state_of(stat: StringName) -> VitalTone.State:
	return read(stat)["state"]


func is_recovering(stat: StringName) -> bool:
	return bool(read(stat)["recovering"])


## The reading in the most trouble, or an empty dictionary if there is nothing to
## read. Ties break on the layout's own order, so the answer is stable rather
## than dependent on which stat the model happened to list first.
##
## Published because "how badly is he doing" is a question with exactly one right
## answer and several places that want it -- the Tab ring's hierarchy, and
## anything in the world that reacts to the man's condition. Two of them working
## it out separately is the disagreement this file exists to prevent.
func worst() -> Dictionary:
	var worst_reading: Dictionary = {}
	for row in rows():
		var reading := read(row.stat)
		if worst_reading.is_empty() or float(reading["fraction"]) < float(worst_reading["fraction"]):
			worst_reading = reading
	return worst_reading
