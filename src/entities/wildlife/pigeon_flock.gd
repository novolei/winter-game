class_name PigeonFlock
extends BirdFlock

## The pigeons in the valley: `BirdFlock` driven by `data/wildlife/pigeon.tres`.
##
## ---------------------------------------------------------------------------
## THE THREE OVERRIDES THIS CLASS USED TO NEED
## ---------------------------------------------------------------------------
## `PigeonFlock extends CrowFlock` had to override six methods -- `_init`,
## `ask_the_clock`, `_on_day_started`, `_on_night_started`, `available_perches`
## and `_build_crow` -- to say three things. All three are fields now:
##
##   1. NIGHT IS NOT A REASON TO EMPTY THE WIRE. `daylight_only = false`.
##      A rock dove roosts on the ledges it feeds from: it is on the eave at dusk
##      and still on it at dawn. The parent's `_night` flag means one thing in
##      its own logic -- the wires must be empty -- and `_dark` is the separate
##      fact that the sun is down. `BirdFlock` now keeps both for every species,
##      so nothing has to be held at false by hand.
##
##   2. IT WILL NOT LAND ON A BIRD THAT IS ALREADY THERE.
##      `avoids_occupied_perches = true`. **And it now works in both directions
##      if the crows ever want it**: the filter is on `BirdFlock` and asks the
##      tree for `Bird`, so it sees crows and pigeons alike. It is still one-way
##      today only because `crow.tres` leaves the flag false, which is a data
##      decision rather than a file nobody could touch.
##
##   3. A FLOCK OF PIGEONS IS BIGGER AND LESS EASILY MOVED. `fewest 2, most 6,
##      flush_radius_m 5.0`. Both are the bird rather than a preference: rock
##      doves feed and roost in groups where a crow perches in ones and twos, and
##      they are used to people. The flush radius being inside the crow's 8 m is
##      what makes the same walk past the pole put the crows up first and the
##      pigeons only if he keeps coming.
##
## What is left is the same one method `CrowFlock` keeps, and for the same
## reason: `test_pigeon_flock.gd` asserts the flock hatches pigeons rather than
## plain birds, which is the assertion that would have caught a lost override
## back when there were five of them.
const SPECIES := preload("res://data/wildlife/pigeon.tres")


func _init() -> void:
	species = SPECIES


func _new_bird() -> Bird:
	return Pigeon.new()
