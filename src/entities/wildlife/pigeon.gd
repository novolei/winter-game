class_name Pigeon
extends Crow

## One rock dove. Sits on a wire, an eave, a pole or a branch; goes when
## something comes too close; comes back.
##
## ---------------------------------------------------------------------------
## WHY THIS EXTENDS `Crow` RATHER THAN BEING A BIRD OF ITS OWN
## ---------------------------------------------------------------------------
## `src/entities/wildlife/crow.gd` is eight hundred lines of TIMELINE -- perch,
## stagger, crouch, rise, wheel, commit, beat, glide, gone, and the whole return
## with its flare and its touchdown frame. **None of that is about crows.** It is
## what any bird that sits on a thin thing and leaves it does, and duplicating it
## for a second species would be duplicating the four defects it has already been
## debugged through (the double-scatter, the identity transform outside the tree,
## the seam between the lift and the wheel, the wire that sways under a bird).
##
## So the pigeon inherits the timeline and replaces the three things that are
## genuinely about the species: WHICH MODEL, WHICH TAKES, WHICH COLOUR.
##
## THE COST OF DOING IT THIS WAY, STATED PLAINLY, BECAUSE IT IS THE ANSWER TO
## "HOW CHEAP IS ANIMAL NUMBER TWO". `Crow` names its model in a `const
## preload`, its library in `CrowAnimations`, and its colour in a `static func`.
## GDScript cannot override a constant, and a static function does not dispatch
## through an instance, so none of the three can be changed by a subclass
## declaring a different value -- each has to be reached by overriding the METHOD
## that reads it. That is why `_build_rig()` below is a near-copy of the parent's
## rather than a two-line override: the parent is a crow, not a bird, and the
## seam is in the wrong place.
##
## **No line of `crow.gd` or `crow_flock.gd` was changed to make this work**, on
## purpose -- another agent is live in both files. What a later wave should do,
## once they are quiet, is lift `Crow` into a `Bird` that takes a species
## definition (`.tres`: model, take map, palette index, yaw, durations) and leave
## `Crow` and `Pigeon` as two data files. That is the shape binding rule 4 asks
## for and it is a refactor of the parent, not of this file.
##
## ---------------------------------------------------------------------------
## WHAT THE PIGEON HAS THAT THE CROW DOES NOT, AND WHAT IT LACKS
## ---------------------------------------------------------------------------
## The inventory's claim was "13 takes covering every state `Crow` already has".
## Measured against `CrowAnimations`' seven, that is nearly true and not quite:
##
##   perch     -> `idle_left`          the pack's two idles are a left/right pair
##   look      -> `idle_right`         so the tell before it goes is the other one
##   take_off  -> `take_off`           0.375 s against the crow's 0.933
##   fly       -> `fly`                0.583 s
##   land      -> `land`               0.417 s against the crow's 2.233
##   glide     -> `fly`                THERE IS NO GLIDE TAKE. A pigeon does not
##                                     glide; it flaps the whole way, which is
##                                     both true of the bird and all the pack
##                                     authored.
##   flap      -> `take_off`, held     THERE IS NO WINGS-OUT-ON-THE-PERCH TAKE
##                                     either. See `_play()`.
##
## And four the crow has no use for and the pigeon has authored: `walk`, `run`
## and the transitions into and out of both. A pigeon on an eave can walk along
## it. Nothing drives that yet and this file does not pretend otherwise.
##
## ---------------------------------------------------------------------------
## THE COLOUR
## ---------------------------------------------------------------------------
## `structure_tones[1]`, one step in from the crow's `structure_tones[3]`. The
## crow is the palette's near-black because Art Bible rule 7 makes a crow a
## silhouette and nothing else; a pigeon is a GREY bird and has to read as a
## different animal at sixteen pixels, which at this palette means a different
## value rather than a different hue.
##
## Not `structure_tones[0]`: that is the farmhouse's own siding, and one of the
## places this bird sits is the farmhouse eave.
##
## THE 2K TEXTURE IS DISCARDED AT IMPORT rather than repainted.
## `fbx/embedded_image_handling=0` in `pigeon.fbx.import` throws the pack's
## colour map away before it becomes a project file. The inventory priced the
## repaint as "trivial -- already grey/near-black" and expected a
## colour-substitution table over 46 colours; at this framing the bird is one
## flat value and the table would have been 46 lookups all landing on the same
## answer. Dropping it also took 71 KB of extracted PNG out of the repository.
##
## `snow_receptivity` is refused through `CelPainter.material_for(tone, true)`,
## the same door the crow uses, and for the same reason: a living bird carries no
## settled snow, and writing the parameter onto the material afterwards would
## turn the snow off for every tree that shares the colour. The `bare` flag is
## part of the painter's CACHE KEY, so the pigeon and anything else painted
## `#2A3854` become two materials rather than one.

## EVERY CONSTANT HERE CARRIES A `DOVE_` PREFIX, AND THAT IS NOT A STYLE CHOICE.
## GDScript refuses to let a subclass declare a member its parent already has --
## `Parse Error: The member "MODEL" already exists in parent class Crow` -- so a
## bird that differs from the crow only in its model, its colour and its facing
## cannot say so by redeclaring the three constants that hold them. It has to
## give them different names and then override every method that reads the
## parent's. That is the sharpest measurement in this task of how much of animal
## number two is code rather than data, and it is a property of the language
## rather than of anyone's design.
const DOVE_MODEL := preload("res://assets/models/characters/pigeon/pigeon.fbx")

## Which of the twelve. Structure, one step in from the crow's near-black.
const DOVE_PALETTE_FAMILY := "structure"
const DOVE_PALETTE_INDEX := 1

## Half a turn, because the delivery faces UNITY's forward and this is Godot.
##
## MEASURED on the imported rig, two instruments, both agreeing, before a single
## degree was applied:
##
##   bind pose      JawEnd_M (the beak tip)  z = +0.0777
##                  Tail3_M  (the tail tip)  z = -0.1830
##   mesh vertices  the bird occupies z = -0.1850 .. +0.0781, and the head --
##                  taken as the highest tenth of the vertices, which on this
##                  model is the skull -- sits at the POSITIVE end
##
## Both say the beak is at +Z, which is Unity's forward and the opposite of the
## one `look_at()` aims. Same value as `Crow.MODEL_YAW` and the same reason, and
## it is worth saying that arriving at the same number is not evidence: the crow
## shipped a wrong yaw for a whole wave on a reading of the pose that had the
## sign inverted, and the only thing that settles it is measuring this asset.
##
## ONE THING THAT DOES **NOT** TRANSFER FROM THE CROW, and it is the reason
## `tests/art/test_pigeon_model.gd` does not simply copy the crow's gate:
## `test_crow_model.gd` decides which end of the bird is the beak by asking which
## end reaches FURTHER from the origin. That is true of a raven, whose origin
## sits at its tail and whose whole body runs forward of it. It is false of this
## bird: the dove's origin sits under its feet, so the tail reaches 0.185 m back
## and the beak only 0.078 m forward, and the crow's test applied here would
## report a correctly-built pigeon as backwards. The pigeon's gate measures the
## HEAD instead, which is a fact about the animal rather than about the file.
const DOVE_YAW := PI

## What the crow's state machine asks for, against what this bird actually has.
##
## `Crow` plays takes by the seven names in `CrowAnimations`; this turns each of
## them into the pigeon's own. Two rows are substitutions rather than
## translations and both are called out in this file's header: there is no glide
## take and no balance take in the delivery.
const TRANSLATION := {
	CrowAnimations.PERCH: PigeonAnimations.IDLE_LEFT,
	CrowAnimations.LOOK: PigeonAnimations.IDLE_RIGHT,
	CrowAnimations.FLAP: PigeonAnimations.TAKE_OFF,
	CrowAnimations.TAKE_OFF: PigeonAnimations.TAKE_OFF,
	CrowAnimations.FLY: PigeonAnimations.FLY,
	CrowAnimations.GLIDE: PigeonAnimations.FLY,
	CrowAnimations.LAND: PigeonAnimations.LAND,
}


## The parent's beat lengths are the crow's takes; these are the dove's.
##
## Set in `_init()` rather than in `_ready()`, because `Crow._ready()` builds the
## rig and starts a take, and a launch already running at the crow's 0.933 s
## would have to be corrected mid-flight.
##
## The dove's departure is a THIRD of the crow's and its landing a fifth, and
## that is the delivery rather than a choice: `Dove_Idle to Fly` is nine frames.
## A pigeon does leave a ledge faster than a crow leaves a wire, so the shorter
## beat is not wrong -- but it does mean the take-off has far less of the crouch
## the crow's whole `crouch_fraction` treatment was built around, so the fraction
## is raised to keep a readable gather inside a much shorter take.
func _init() -> void:
	launch_seconds = PigeonAnimations.length_of(PigeonAnimations.TAKE_OFF)
	land_seconds = PigeonAnimations.length_of(PigeonAnimations.LAND)
	crouch_fraction = 0.45
	# The take's own rise is 32 mm over nine frames; the crow's was 0.30 m over
	# twenty-nine. A dove bursting off a ledge climbs faster than a crow leaving
	# a wire and over a shorter window, so the height is kept and the window is
	# what shrank.
	launch_climb_m = 0.22
	# A pigeon flies slower than a crow and turns harder.
	mill_speed = 4.2
	cruise_speed = 9.0


## The pigeon's colour, read from the palette and never written here (briefing
## constraint 6). Static, mirroring `Crow.palette_tone()`, so the gate can assert
## what it resolved to rather than trusting a comment.
static func palette_tone() -> Color:
	var bible = load(PALETTE_PATH)
	if bible == null or bible.structure_tones.size() <= DOVE_PALETTE_INDEX:
		return Color(0.0, 0.0, 0.0)
	return bible.structure_tones[DOVE_PALETTE_INDEX]


## The material this bird wears: a grey structure tone on the world's two-band
## cel shader, keyed BARE so no snow ever settles on it.
##
## Overridden rather than inherited because `Crow.material()` calls
## `palette_tone()` as a STATIC, which resolves at the class that declares it --
## a subclass redeclaring the static does not get called. That is a GDScript
## fact worth knowing before anyone adds a third bird by copying this file: the
## override has to be on the instance method, not on the static.
func material() -> ShaderMaterial:
	if _material != null:
		return _material
	if _painter == null:
		_painter = CelPainter.new()
	_material = _painter.material_for(palette_tone(), true)
	return _material


## Instantiates the dove, turns it round, paints it, and hangs its takes on the
## file's own AnimationPlayer.
##
## A near-copy of `Crow._build_rig()` differing in three constants, which is the
## price of the parent naming its model in a `const preload` -- see the header.
func _build_rig() -> void:
	var rig := DOVE_MODEL.instantiate() as Node3D
	if rig == null:
		return
	rig.name = "Rig"
	if absf(DOVE_YAW) > 0.0001:
		rig.rotate_y(DOVE_YAW)
	add_child(rig)
	_paint(rig)
	for node in rig.find_children("*", "AnimationPlayer", true, false):
		_player = node as AnimationPlayer
		break
	if _player == null:
		return
	if _player.has_animation_library(PigeonAnimations.LIBRARY):
		_player.remove_animation_library(PigeonAnimations.LIBRARY)
	_player.add_animation_library(PigeonAnimations.LIBRARY, PigeonAnimations.build())


## The crow's seven names, played out of the pigeon's library.
##
## THE BALANCE TAKE IS A SUBSTITUTION AND IT IS THE ONE THING HERE THAT IS NOT A
## RENAME. `Crow._balance()` plays `flap` when a gust crosses 0.45 and `perch`
## again when it falls back, and the crow's `flap` is `Rav_Fly_Stand` -- wings
## worked without leaving the perch. The dove has no such take: this pack gives
## it two idles, a walk, a run, a flight cycle and the transitions between them,
## and nothing that opens its wings while its feet stay closed.
##
## So the gust plays `take_off` WITHOUT LOOPING, which runs the nine frames of
## the dove opening its wings and then holds the last of them. A held
## wings-half-open pose is not a beat, and a bird balancing through a squall
## should be working at it -- so this is the weakest thing in the delivery and it
## is written down rather than dressed up. The alternative considered and
## rejected was playing the other idle, which reads as a bird that has not
## noticed the wind at all.
##
## The pigeon does not leave the perch on this take: `Crow._lift_off()` only
## moves the bird in LAUNCHING, and `_balance()` only runs in PERCHED.
func _play(take: StringName) -> void:
	if _player == null:
		return
	var named: StringName = TRANSLATION.get(take, take)
	var full := "%s/%s" % [PigeonAnimations.LIBRARY, named]
	if not _player.has_animation(full):
		return
	# Cross-faded rather than cut, for the same reason the crow's is: no take in
	# this pack was authored to follow another, so a hard switch pops -- most
	# visibly between the idle's folded wings and the launch's open ones.
	_player.play(full, 0.12)
