class_name BirdSpecies
extends Resource

## What makes a bird that bird: which model, which colour, which way round, which
## takes, how many of them sit together, and what they do at nightfall.
##
## ---------------------------------------------------------------------------
## WHY THIS RESOURCE EXISTS, WHICH IS A NUMBER
## ---------------------------------------------------------------------------
## `.superpowers/sdd/wave3/task-w3-pigeon-report.md` §4.1 measured the second
## bird in this game at **209 lines of code against 31 of data** -- 87% code --
## even though it reused all 2,128 lines of the first. That reads like success
## until §4.3, which says why the number stops falling:
##
##     GDScript will not let a subclass redeclare a parent's constant.
##
## `Crow` named its model in a `const preload`, its colour in a `static func`
## and its facing in a `const`. A bird differing in exactly those three things
## could not say so by declaring different values -- it had to rename all three
## and then override every method that read the parent's. So `Pigeon._build_rig()`
## was a near-copy of `Crow._build_rig()` rather than a two-line override, and
## **animal number three would have cost the same 209 again**, and the fourth,
## and the eighth.
##
## Binding rule 4 says adding a creature should need only a new `.tres`. This is
## that `.tres`. A bird is now `Bird` plus one of these, and the parent is a bird
## rather than a crow.
##
## ---------------------------------------------------------------------------
## THE SEVEN ROLES
## ---------------------------------------------------------------------------
## `Bird`'s timeline asks for a MOTION, not for a take name: it wants "the perch
## take" at the moment a bird settles, and what that is called is the delivery's
## business. `roles` is the map, and it is what lets one state machine drive two
## packs that share no vocabulary at all:
##
##   role       the raven pack        the dove pack
##   perch      Rav_Perch             Dove_Idle Left
##   look       Rav_Turn_Right        Dove_Idle Right
##   flap       Rav_Fly_Stand         Dove_Idle to Fly   <- a substitution
##   take_off   Rav_TakeOff           Dove_Idle to Fly
##   fly        Rav_Fly_Forward       Dove_Fly
##   glide      Rav_Fly_Glide         Dove_Fly           <- a substitution
##   land       Rav_Land              Dove_Fly to Idle
##
## Two of the dove's rows are substitutions rather than translations, and they
## are visible AS substitutions here -- two roles pointing at one take -- where
## in the old `Pigeon.TRANSLATION` they looked exactly like the other five. A
## species that genuinely has no glide is a species whose `glide` and `fly` rows
## are the same string, and anybody reading the data can see it.
##
## A role with no row at all is not an error: `Bird._play()` leaves whatever was
## already running, which is what a bird with no balance take should do.
##
## ---------------------------------------------------------------------------
## WHAT IS **NOT** HERE, AND WHY
## ---------------------------------------------------------------------------
## Nothing about the shot. `vanish_distance_m`, `hover_m`, `flare_distance_m`
## and the wheel bounds stay on `Bird` and `BirdFlock` as ordinary exports,
## because they are decisions about the camera and the frame rather than about
## the animal -- an orthographic camera does not shrink a departing bird, so it
## has to leave the frame, and that is true of every species at once.
##
## Nothing about the palette either, beyond an index. The colour is READ from
## `data/palette/color_bible.tres` at runtime (`tone()`), never stored here, so
## this resource cannot become a second place a colour lives.

## The seven motions `Bird`'s timeline asks for. Named constants rather than
## string literals at the call site, so a rename is a compile-time move.
const PERCH := &"perch"
const LOOK := &"look"
const FLAP := &"flap"
const TAKE_OFF := &"take_off"
const FLY := &"fly"
const GLIDE := &"glide"
const LAND := &"land"

## Every role, in the order a departure uses them. `test_bird_species.gd` holds
## each species to covering all of them.
const ROLES: Array = [PERCH, LOOK, FLAP, TAKE_OFF, FLY, GLIDE, LAND]

const PALETTE_PATH := "res://data/palette/color_bible.tres"

## What to call it. Used in node names (`Crow1`, `Pigeon3`) and in failure
## messages, so a gate that fires names the animal rather than a file path.
@export var species_name := "bird"

## The model, and the file the takes come out of unless a take names its own.
@export var model_path := ""

## The library the takes are hung under, so a take is asked for as "crow/perch".
## One per species, or two birds in one scene would collide on the player.
@export var library := &"bird"

## The rate the pack was authored at. Every frame number in `takes` is an index
## into a take sampled at this rate, and `animation/fps` in the `.import` is set
## to match -- so a frame index divided by this is a time in seconds.
@export var source_fps := 30.0

## Where the skeleton hangs under the imported model, and therefore the node
## half of every track path a SLICED take is rebuilt with.
##
## Only the frame-range deliveries need it. The raven pack's four animation
## files carry no armature at all -- 3ds Max exported the rig as a hierarchy of
## nulls -- so their tracks arrive addressed to NODES the model does not have and
## every one has to be readdressed. A pack that ships its takes in the same file
## as its mesh already addresses the right thing, and `BirdAnimations` leaves
## those alone.
@export var skeleton_path := "Skeleton3D"

## The half-turn that undoes Unity's forward, in radians.
##
## ---------------------------------------------------------------------------
## THE MOST EXPENSIVE FIELD IN THIS FILE
## ---------------------------------------------------------------------------
## Both packs arrived in `.unitypackage`s. Unity is left-handed and a model
## authored for it faces **+Z**; Godot is right-handed and `look_at()` aims a
## node's **-Z**. An asset brought across without a correction points exactly
## backwards, and every consumer that aims it from a velocity puts its tail
## where its beak should be.
##
## The crow shipped a whole wave flying tail-first on this. It survived review
## because at the widest framing stop a crow is sixteen pixels, and sixteen
## pixels of bird flying backwards still reads as a bird -- the owner caught it,
## not the suite. The perched birds were reversed along their wires too and
## nobody saw that at all.
##
## MEASURED per asset, never assumed, because arriving at the same number twice
## is not evidence:
##
##   crow    bind pose  BeakTop  z = +0.1722, Tail Center z = -0.1389
##           vertices   the bird occupies z = -0.0035 .. +0.2902, beak tip the
##                      furthest +Z vertex at +0.2794
##   dove    bind pose  JawEnd_M z = +0.0777, Tail3_M     z = -0.1830
##           vertices   z = -0.1850 .. +0.0781, and the skull at the +Z end
##
## `tests/art/test_crow_model.gd` and `test_pigeon_model.gd` measure both halves
## of each delivery THROUGH this field, so a species whose yaw is dropped in a
## refactor reports a bird facing backwards rather than reporting nothing.
@export var model_yaw := 0.0

## Which of the palette's three families, and which entry in it.
##
## `structure` for both birds so far: Art Bible rule 7 makes a bird at this
## framing a silhouette and nothing else. The crow is the darkest (index 3) and
## the dove one step in (index 1), because a rock dove is the grey one and two
## near-black birds at sixteen pixels are one bird.
@export var palette_family := "structure"
@export var palette_index := 0

## Every take, in the order the library should hold them.
@export var takes: Array[BirdTake] = []

## role -> the name of the take that plays it. See the header.
@export var roles: Dictionary = {}

# --- the beats, which are the take lengths and therefore the delivery ----------
#
# These seed the matching `@export`s on `Bird` when a species is adopted, so a
# test or a capture can still override any of them on one bird afterwards.

## How long the launch take runs, and how much of it the feet stay closed.
##
## The dove's departure is a THIRD of the crow's (0.375 s against 0.933) and its
## landing a fifth, and that is the delivery rather than a choice: `Dove_Idle to
## Fly` is nine frames. So the crouch fraction is raised for the dove, to keep a
## readable gather inside a much shorter take.
@export var launch_seconds := 29.0 / 30.0
@export var crouch_fraction := 0.34

## How far the bird rises off the wire during the second half of the launch.
@export var launch_climb_m := 0.30

## How long the landing take runs, and where in it the feet touch.
##
## `land_flare` is MEASURED off the take rather than chosen. `Rav_Land` holds
## its flare from frame 33 to about 60, then the body drops 0.193 -> 0.096
## between 60 and 72: 58 per cent of the way through the slice. Get it wrong in
## either direction and it reads as one specific kind of wrong -- early, and the
## bird stands on the wire flapping at nothing; late, and it finishes its
## landing in mid-air and then drops.
@export var land_seconds := 67.0 / 30.0
@export var land_flare := 0.58

## Metres per second: milling, and committed. A pigeon flies slower than a crow
## and turns harder.
@export var mill_speed := 5.0
@export var cruise_speed := 12.0

## The wind at which a perched bird opens its wings for balance, and the weaker
## wind at which it settles again. The band between them is hysteresis: `_play()`
## restarts the take every call, so a strength jittering across one threshold
## would be a bird vibrating rather than a bird balancing.
@export var balance_on := 0.45
@export var balance_off := 0.36

# --- the flock ------------------------------------------------------------------

## One bird or several. Rock doves feed and roost in groups where a crow perches
## in ones and twos.
@export var fewest := 1
@export var most := 5

## How close whoever is being watched has to get. The dove's is inside the
## crow's, because a pigeon is used to people: the same walk past the pole puts
## the crows up first and the pigeons only if he keeps coming.
@export var flush_radius_m := 8.0

## Whether nightfall empties the wire.
##
## True for the crow, and it is the owner's own word -- 只有白天才会有乌鸦出现.
## False for the rock dove, which roosts on the ledges it feeds from: it is on
## the eave at dusk and still on it at dawn, and a valley whose only bird
## vanishes the moment the sun goes down is a valley that is obviously running a
## day/night switch.
@export var daylight_only := true

## Whether it declines a perch another bird is already standing on.
##
## Both flocks gather from the same `perches` group, which is what lets two
## species share a wire -- and which means two flocks that cannot see each other
## can hand out the same perch twice. At sixteen pixels, two birds in one place
## is a single wrong-shaped blob.
@export var avoids_occupied_perches := false

## How near another bird has to be for a perch to count as taken. A perched dove
## is 0.30 m long and the wire spacings in `scenes/main.tscn` are 2.2 m to 3.0 m,
## so this only ever fires on two birds sent to the SAME perch.
@export var occupied_within_m := 0.35


## The bird's colour, READ from the palette and never written here (briefing
## constraint 6, CLAUDE.md's "no hardcoded colour outside tools/").
##
## Black on failure rather than a guess: a bird that cannot resolve its tone is
## a silhouette, which is the one wrong answer that still looks deliberate.
func tone() -> Color:
	var bible = load(PALETTE_PATH)
	if bible == null:
		return Color(0.0, 0.0, 0.0)
	var family = bible.get("%s_tones" % palette_family)
	if not (family is Array) or family.size() <= palette_index or palette_index < 0:
		return Color(0.0, 0.0, 0.0)
	return family[palette_index]


## The take that plays `role`, or "" for a species that has none. Empty is a
## real answer -- the dove has no wings-out-on-the-perch take -- and `Bird._play()`
## leaves whatever was running rather than falling back to something wrong.
func take_for(role: StringName) -> StringName:
	return roles.get(role, &"") as StringName


## The row named `take_name`, or null.
func take_named(name: StringName) -> BirdTake:
	for take in takes:
		if take != null and take.take_name == name:
			return take
	return null


## How long a named take is meant to be, or -1 for a name this species does not
## carry. For a gate, and for anybody timing a behaviour against a take.
func length_of(name: StringName) -> float:
	var take := take_named(name)
	return take.expected_seconds(source_fps) if take != null else -1.0


## Every file the takes are cut from, the model included, without repeats.
func source_files() -> PackedStringArray:
	var seen: Dictionary = {}
	var found := PackedStringArray()
	for take in takes:
		if take == null:
			continue
		var path := take.file(model_path)
		if path == "" or seen.has(path):
			continue
		seen[path] = true
		found.append(path)
	return found


## The model as a PackedScene, or null. Loaded rather than preloaded, which is
## the whole point: a preload is written in a `.gd` and this is written in a
## `.tres`.
func model() -> PackedScene:
	if model_path == "" or not ResourceLoader.exists(model_path):
		return null
	return ResourceLoader.load(model_path) as PackedScene
