extends SceneTree

## Writes data/wildlife/*.tres -- one file per bird, holding everything that
## makes it that bird.
##
## Run:
##   godot --headless --path <project> --script res://tools/generate_bird_species.gd
##
## ---------------------------------------------------------------------------
## EVERY NUMBER BELOW HAS A SOURCE, AND THE SOURCE IS BESIDE IT
## ---------------------------------------------------------------------------
## The frame ranges are Malbers' own, read out of each `.FBX.meta`'s
## `clipAnimations` block. The dove's durations are its `AnimationStack` lengths
## divided by the pack's 24 fps. The flare fraction was measured off `Rav_Land`'s
## CG track; the balance latch was swept over an hour of each shipped wind
## profile; the yaws were measured on the delivered rigs four ways and two ways
## respectively. None of it is a preference and none of it may be re-derived from
## the assets -- a generator that read its expectation off the file it is meant
## to be checking would accept anything, which is the circularity CLAUDE.md
## forbids for the palette.
##
## ---------------------------------------------------------------------------
## WHY THE TAKE TABLES LIVE HERE AND NOT IN A `.gd`
## ---------------------------------------------------------------------------
## They used to be `CrowAnimations.FRAMES` and `PigeonAnimations.TAKES`, in two
## classes that did the same job because the two packs lay their clips out in
## opposite ways -- one long take cut into frame ranges, or each clip its own
## `AnimationStack`. `BirdTake` describes both shapes in one row and
## `BirdAnimations` reads which is which off the row, so a third bird from
## either pack is one more block in the array below and no code at all.

const SpeciesScript := preload("res://src/definitions/bird_species.gd")
const TakeScript := preload("res://src/definitions/bird_take.gd")

const OUT := "res://data/wildlife"

const CROW_MODEL := "res://assets/models/characters/crow/crow.fbx"
const CROW_PERCH_FILE := "res://assets/models/characters/crow/crow_perch.fbx"
const CROW_TURN_FILE := "res://assets/models/characters/crow/crow_turn.fbx"
const CROW_FLY_FILE := "res://assets/models/characters/crow/crow_fly.fbx"
const CROW_TAKEOFF_FILE := "res://assets/models/characters/crow/crow_takeoff.fbx"

const PIGEON_MODEL := "res://assets/models/characters/pigeon/pigeon.fbx"

## [our name, source file, first frame, last frame, loops, in place, the Unity
## clip it came from].
##
## IN PLACE is the column worth reading twice. `Rav_TakeOff` carries baked root
## motion -- the CG bone climbs 0.30 m and travels 0.37 m forward across its 29
## frames -- and so do the two flight cycles. A take that moves the bird AND code
## that moves the bird are two answers to one question, and the visible result is
## a crow travelling at twice the speed anything asked for. So the three takes
## the game drives are flattened to a single root key and `Bird` owns every
## metre. The two perched takes keep theirs: it is 2 mm of sway, and it is the
## difference between a bird and a decal.
const CROW_TAKES: Array = [
	# The whole point of the asset: feet closed round something thin.
	["perch", CROW_PERCH_FILE, 123, 182, true, false, "Rav_Perch"],
	# The look. Malbers marks it looping, which would be a bird spinning on the
	# spot; it is played once here and the perch take's own root track puts the
	# bird back the way it was.
	["look", CROW_TURN_FILE, 0, 24, false, false, "Rav_Turn_Right"],
	# Wings worked without leaving the perch. The fidget, and the balance.
	["flap", CROW_FLY_FILE, 1, 25, true, true, "Rav_Fly_Stand"],
	["take_off", CROW_TAKEOFF_FILE, 1, 29, false, true, "Rav_TakeOff"],
	["fly", CROW_FLY_FILE, 82, 106, true, true, "Rav_Fly_Forward"],
	["glide", CROW_FLY_FILE, 163, 195, true, true, "Rav_Fly_Glide"],
	# The OTHER half of `Raven Land TakeOff.FBX`, which Wave 2 sliced the first 29
	# frames out of and left the rest of. MEASURED on the CG bone's height, the
	# long take is two clips joined at frame 30 with a hard cut:
	#
	#   0..29   rest 0.121 -> crouch 0.058 (f9) -> climb 0.422 (f29)   the take-off
	#   32..99  0.193 held with wingbeats to f60 -> drop to 0.096 (f72)
	#           -> settle -> rest 0.120 (f95)                          THE LANDING
	#
	# So the flare is frames 33..60 and the drop onto the perch is 60..72, which is
	# 40 to 58 per cent of the way through the slice below -- which is where
	# `land_flare` comes from.
	["land", CROW_TAKEOFF_FILE, 33, 99, false, true, "Rav_Land"],
]

## [our name, the pack's own name, loops, the duration it must import at].
##
## THE PACK'S NAME IS STORED BYTE FOR BYTE, TRAILING SPACE AND ALL.
## `Dove_Run to Idle ` is what the exporter wrote. A lookup without the space
## finds nothing and drops the take in silence, which it did on the pigeon's
## first run. `BirdAnimations.matching_name()` now tolerates it and warns, but
## the shipped value matches exactly so the warning never fires.
##
## `Dove_Atttack` is the pack's own spelling. A pigeon pecking at grit is what
## the take actually reads as, so it is named for that rather than for what a
## Unity demo used it as.
##
## All thirteen are named even though the behaviour plays seven, because the
## owner cannot author bird animation: a take that is imported and named is a
## feature somebody can build later, and a take nobody wrote down is one that has
## to be rediscovered out of a 122 MB package.
const PIGEON_TAKES: Array = [
	["idle_left", "Dove_Idle Left", true, 3.958],
	["idle_right", "Dove_Idle Right", true, 3.958],
	["idle_to_walk", "Dove_Idle to Walk", false, 0.417],
	["walk", "Dove_Walk", true, 1.167],
	["walk_to_idle", "Dove_Walk to Idle", false, 0.417],
	["idle_to_run", "Dove_Idle to Run", false, 0.292],
	["run", "Dove_Run", true, 0.583],
	["run_to_idle", "Dove_Run to Idle ", false, 0.292],
	["take_off", "Dove_Idle to Fly", false, 0.375],
	["fly", "Dove_Fly", true, 0.583],
	["land", "Dove_Fly to Idle", false, 0.417],
	["peck", "Dove_Atttack", false, 1.667],
	["death", "Dove_Death", false, 0.875],
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_write(_crow(), "crow")
	_write(_pigeon(), "pigeon")
	quit()


## The carrion crow, out of Malbers' "Poly Art Ravens & Crows" v4.1.
func _crow() -> BirdSpecies:
	var species: BirdSpecies = SpeciesScript.new()
	species.species_name = "crow"
	species.model_path = CROW_MODEL
	species.library = StringName("crow")
	# Every frame number in CROW_TAKES is an index into a take sampled at this
	# rate, and `animation/fps=30` in each `.import` is set to match.
	species.source_fps = 30.0
	species.skeleton_path = "Skeleton3D"
	# Half a turn: the delivery faces Unity's forward and this is Godot. Measured
	# four ways -- bind pose, mesh vertices, every take's beak-minus-tail, and
	# `Rav_TakeOff`'s +Z root travel -- all agreeing. See BirdSpecies.model_yaw.
	species.model_yaw = PI
	# TEN PER CENT LARGER, on the owner's ask, and it is data because it had to
	# become data: nothing in the project scaled a bird at all before this field.
	# `crow.fbx` measures 0.9599 m across the wings, so the game now draws it at
	# 1.0559 m, still well inside the 0.70..1.30 m band `data/scale/crow.tres`
	# holds a carrion crow to. On screen: 26.3 px -> 28.9 px at the tight framing
	# stop, 16.0 px -> 17.6 px at the widest.
	species.model_scale = 1.1
	# Art Bible rule 7's near-black, the same value the trees get: a crow at this
	# framing is a shape against snow and nothing else. The delivered pack ships
	# six material variants, two near-white and one with a yellow beak; rule 12
	# reserves warm for windows, fire, beacon, truck and scarf, and a leucistic
	# bird on a snowfield is not a bird at all.
	species.palette_family = "structure"
	species.palette_index = 3

	var rows: Array[BirdTake] = []
	for row in CROW_TAKES:
		var take: BirdTake = TakeScript.new()
		take.take_name = StringName(row[0])
		take.source_path = row[1]
		take.first_frame = int(row[2])
		take.last_frame = int(row[3])
		take.loops = bool(row[4])
		take.in_place = bool(row[5])
		take.seconds = float(int(row[3]) - int(row[2])) / species.source_fps
		rows.append(take)
	species.takes = rows
	# The crow has a take of its own for all seven roles, which is why it never
	# needed a translation layer and the dove did.
	species.roles = {
		SpeciesScript.PERCH: StringName("perch"),
		SpeciesScript.LOOK: StringName("look"),
		SpeciesScript.FLAP: StringName("flap"),
		SpeciesScript.TAKE_OFF: StringName("take_off"),
		SpeciesScript.FLY: StringName("fly"),
		SpeciesScript.GLIDE: StringName("glide"),
		SpeciesScript.LAND: StringName("land"),
	}

	# `Rav_TakeOff` is 29 frames at 30 fps; a third of it is the gather, which is
	# also long enough for the wings to have opened.
	species.launch_seconds = 29.0 / 30.0
	species.crouch_fraction = 0.34
	# The take's own number: `Rav_TakeOff`'s CG bone climbs 0.3009 m.
	species.launch_climb_m = 0.30
	# `Rav_Land` is 67 frames at 30 fps, and its body drops 58 per cent of the way
	# through the slice -- see CROW_TAKES' comment on the landing.
	species.land_seconds = 67.0 / 30.0
	species.land_flare = 0.58
	# THE CROW'S LANDING IS UNCHANGED, AND THESE TWO ARE HOW THAT IS SAID.
	# The descent used to be `land_seconds * land_flare` implicitly; it is a field
	# now, and for this bird it is that same product, so the shot the Art Bible
	# signed off is untouched to the millisecond. The settle is the rest of
	# `Rav_Land` -- 42 per cent of a 67-frame take, which is the wing-fold the
	# animator already drew, so the crow names no `settle` role and simply plays
	# the take out.
	species.descent_seconds = (67.0 / 30.0) * 0.58
	species.settle_seconds = (67.0 / 30.0) * 0.42
	# AND IT DECLINES THE FLARE'S HANG, which is the same statement one field
	# further on. A bent parameter buys a float at the cost of fall rate (see
	# BirdSpecies.flare_hang's sweep), and the crow's landing was reviewed and
	# approved as it was -- so it keeps the unbent curve and its peak descent
	# stays 3.29 m/s rather than becoming 3.72 as a side effect of fixing the
	# pigeon. The two birds differing here costs one row in a .tres.
	species.flare_hang = 1.0
	species.mill_speed = 5.0
	species.cruise_speed = 12.0
	# Swept over an hour of each shipped profile: 0.45 on / 0.36 off holds 10.8
	# per cent of the time on `wind_valley` in stretches averaging 8.3 s, and
	# never fires at all on `wind_calm`.
	species.balance_on = 0.45
	species.balance_off = 0.36

	# 一只或者多只 -- one bird or several. The upper bound is what the wires can
	# carry without the farmyard reading as a rookery.
	species.fewest = 1
	species.most = 5
	# Inside the tight framing stop's 10.5 m of world, so the flush happens on
	# screen rather than off the edge of it.
	species.flush_radius_m = 8.0
	# 只有白天才会有乌鸦出现.
	species.daylight_only = true
	# The crows will still come down on a pigeon. Turning this on would change
	# behaviour the shipped tests measure, and it is one boolean whenever the
	# Director wants it.
	species.avoids_occupied_perches = false
	return species


## The rock dove, out of the low-poly animal package's `SKM_DoveRock_Animations`.
func _pigeon() -> BirdSpecies:
	var species: BirdSpecies = SpeciesScript.new()
	species.species_name = "pigeon"
	# ONE FILE: mesh, 45-bone skeleton and all thirteen takes. The pack's separate
	# `SKM_DoveRock_Rig.fbx` was measured and deliberately not taken -- identical
	# 832-triangle mesh, identical skeleton, no AnimationPlayer, and a junk
	# `Take 001` that inflates any census of what we own.
	species.model_path = PIGEON_MODEL
	species.library = StringName("pigeon")
	species.source_fps = 24.0
	species.skeleton_path = "Skeleton3D"
	# Measured on the imported rig before a single degree was applied: JawEnd_M
	# (beak tip) z = +0.0777 against Tail3_M z = -0.1830, and the mesh's skull
	# vertices at the +Z end. Same value as the crow's and NOT copied from it --
	# the crow shipped a wrong yaw for a whole wave on a misread of its own pose.
	species.model_yaw = PI
	# The same ten per cent the crow got, and for the same reason -- the two birds
	# share a wire and share a framing, so making one larger without the other
	# would change what the pair reads as. `pigeon.fbx` measures 0.7267 m across
	# the wings and is drawn at 0.7994 m, inside `data/scale/pigeon.tres`'s
	# 0.55..0.90 m band for a rock dove.
	species.model_scale = 1.1
	# One step in from the crow's near-black. A rock dove is the grey one and has
	# to read as a different animal at sixteen pixels, which at this palette means
	# a different VALUE rather than a different hue. Not `structure_tones[0]`:
	# that is the farmhouse's own siding, and the eave is one of the four things
	# this bird sits on.
	species.palette_family = "structure"
	species.palette_index = 1

	var rows: Array[BirdTake] = []
	for row in PIGEON_TAKES:
		var take: BirdTake = TakeScript.new()
		take.take_name = StringName(row[0])
		# No source_path: every take is in the model file itself.
		take.source_name = row[1]
		take.loops = bool(row[2])
		take.seconds = float(row[3])
		# Nothing needs its root flattened. Measured over twenty-one samples of
		# every take, the `Root_M` bone travels at most 33 mm across a take -- a
		# wingbeat bob rather than travel -- so the code owns every metre by
		# default and nothing has to be taken away from the animator.
		take.in_place = false
		rows.append(take)
	species.takes = rows
	# TWO OF THESE SEVEN ARE SUBSTITUTIONS RATHER THAN TRANSLATIONS.
	#
	#   glide -> fly        THERE IS NO GLIDE TAKE. A pigeon does not glide; it
	#                       flaps the whole way, which is true of the bird and is
	#                       all the pack authored.
	#   flap  -> take_off   THERE IS NO WINGS-OUT-ON-THE-PERCH TAKE. The crow's
	#                       `flap` is `Rav_Fly_Stand`, wings worked with the feet
	#                       still closed; this pack has nothing equivalent, so the
	#                       gust plays the nine frames of the dove opening its
	#                       wings and holds the last of them. A held pose is not a
	#                       beat, and it is the weakest thing in this delivery --
	#                       but `z-gustbird.png` shows a bird on a wire with one
	#                       wing flared, which is what balancing looks like.
	#
	# In the old `Pigeon.TRANSLATION` these looked exactly like the other five
	# rows. Here they are two roles pointing at one take, which anybody reading
	# the data can see.
	species.roles = {
		SpeciesScript.PERCH: StringName("idle_left"),
		# The pack's two idles are a left/right pair -- the nearest thing in the
		# whole package to a bird turning its head to watch you -- so the tell
		# before it goes is the other one.
		SpeciesScript.LOOK: StringName("idle_right"),
		SpeciesScript.FLAP: StringName("take_off"),
		SpeciesScript.TAKE_OFF: StringName("take_off"),
		SpeciesScript.FLY: StringName("fly"),
		SpeciesScript.GLIDE: StringName("fly"),
		SpeciesScript.LAND: StringName("land"),
		# THE EIGHTH ROLE, and the dove needs it where the crow does not. Its
		# landing take runs out 0.175 s after the feet touch, so without this the
		# bird stands frozen on the take's last frame and then snaps to its idle.
		# The other idle of the left/right pair is the pack's nearest thing to a
		# bird looking about as it settles, and `Bird` drops into `perch` --
		# `idle_left` -- when the settle is over.
		SpeciesScript.SETTLE: StringName("idle_right"),
	}

	# The delivery, not a choice: `Dove_Idle to Fly` is nine frames at 24 fps, so
	# the dove's departure is a THIRD of the crow's and its landing a fifth. A
	# pigeon does leave a ledge faster than a crow leaves a wire -- but the take
	# has far less of the crouch the whole `crouch_fraction` treatment was built
	# around, so the fraction is raised to keep a readable gather inside it.
	species.launch_seconds = 0.375
	species.land_seconds = 0.417
	species.crouch_fraction = 0.45
	# The take's own rise is 32 mm over nine frames against the crow's 0.30 m over
	# twenty-nine. A dove bursting off a ledge climbs faster and over a shorter
	# window, so the height is kept and the window is what shrank.
	species.launch_climb_m = 0.22
	species.land_flare = 0.58
	# ---------------------------------------------------------------------------
	# 停靠降落在电线上的过程太多余突兀和生硬了
	# ---------------------------------------------------------------------------
	# The descent used to BE `land_seconds * land_flare` -- 0.2419 s -- because
	# nothing separated "how long the bird takes to come down" from "how long the
	# landing take is", and `Dove_Fly to Idle` is ten frames where `Rav_Land` is
	# 67. Flown a frame at a time, the pigeon came down the same 2.9 m of air at a
	# peak of 18.097 m/s against the crow's 3.349.
	#
	# 1.05 s is chosen against that rate rather than against the crow's duration:
	# with `hover_m` 2.6 and `flare_distance_m` 3.4 the drop is about 2.93 m, and
	# a descent that eases in and out covers it at a peak near 1.5 * 2.93 / T. At
	# T = 1.05 that is 4.2 m/s -- a shade brisker than the crow, which is right
	# for the smaller bird, and a quarter of what it was.
	species.descent_seconds = 1.05
	# The take has only 0.175 s of tail left after touchdown, which is not a beat.
	# So the dove holds its other idle for the rest of this -- see the `settle`
	# role below -- and stands there looking about before it becomes furniture.
	species.settle_seconds = 0.60
	# ...and unlike the crow it needs the parameter bent, because the dove pack
	# gave it no flare to play: `Dove_Fly to Idle` is ten frames. Without the
	# bend the descent is a symmetric slide that is still doing two thirds of
	# its peak a quarter of the way from the wire. At 1.3 the last quarter of
	# the time carries 7.4 per cent of the drop instead of 15.7, and the peak
	# rate rises only to 4.66 m/s -- against the 18.10 it used to arrive at.
	species.flare_hang = 1.3
	# A pigeon flies slower than a crow and turns harder.
	species.mill_speed = 4.2
	species.cruise_speed = 9.0
	species.balance_on = 0.45
	species.balance_off = 0.36

	# Rock doves feed and roost in groups where a crow perches in ones and twos.
	species.fewest = 2
	species.most = 6
	# Inside the crow's 8 m, because a pigeon is used to people: the same walk
	# past the pole puts the crows up first and the pigeons only if he keeps
	# coming.
	species.flush_radius_m = 5.0
	# THE WHOLE DIFFERENCE FROM THE CROWS. A rock dove roosts on the ledges it
	# feeds from: it is on the eave at dusk and still on it at dawn.
	species.daylight_only = false
	# Two flocks that cannot see each other can hand out the same perch twice, and
	# at sixteen pixels two birds in one place is a single wrong-shaped blob.
	species.avoids_occupied_perches = true
	species.occupied_within_m = 0.35
	return species


func _write(species: BirdSpecies, name: String) -> void:
	var path: String = OUT.path_join("%s.tres" % name)
	var status := ResourceSaver.save(species, path)
	print("%s  %s  %d takes, %d roles, %s, yaw %.4f, scale %.2f, descent %.4f s + settle %.4f s, hang %.2f, %s" % [
		"ok " if status == OK else "FAIL",
		path,
		species.takes.size(),
		species.roles.size(),
		species.tone().to_html(false),
		species.model_yaw,
		species.model_scale,
		species.descent_seconds,
		species.settle_seconds,
		species.flare_hang,
		"daylight only" if species.daylight_only else "day and night",
	])
