extends Node3D

## Autoload "LegSnow". Snow packs onto a walker's boots and shins in a drift,
## and he knocks it off again, step by step, until his legs are clean.
##
## ---------------------------------------------------------------------------
## THE MODEL: IT COMES OFF BY IMPACT, NOT BY THE PASSAGE OF TIME
## ---------------------------------------------------------------------------
## Nothing here runs on a timer and nothing here fades. Snow leaves a leg
## because the leg hits the ground, so every change to the load happens on a
## FOOTFALL and on nothing else. That one decision buys the effect its rhythm
## for free: the bursts land on the steps because they ARE the steps, and a walk
## that slows down sheds more slowly without a line of code saying so.
##
## Each step takes the same FRACTION of what is still there, so the load decays
## exponentially per footfall rather than linearly. That is the physical claim,
## not a curve chosen for looks: the loose powder goes in the first two or three
## strides, and what is left has been compacted by the leg and part-melted by
## body heat and refrozen, and it clings. At the shipped retention of 0.70 the
## sheds run 0.30, 0.21, 0.15, 0.10, 0.07, ... -- three bursts you cannot miss as
## he clears the drift, then progressively less, then a trace on the boot that is
## still there twenty steps later.
##
## Loading is the same rule read backwards: a step in deep snow packs a fixed
## fraction of what is still BARE, so a leg fills quickly and can never fill past
## full. One rule, two directions, and the walk in and the walk out are the same
## arithmetic.
##
## ---------------------------------------------------------------------------
## TWO POPULATIONS, SEPARATED BY DRAG AND BY NOTHING ELSE
## ---------------------------------------------------------------------------
##   FINE POWDER  high drag. It barely falls, it hangs, it spreads, and it goes
##                out as a soft mist. This is the 雾状 the effect is for.
##   CLUMPS       low drag. Few, heavy, thrown down and forward, and they arrive
##                somewhere. Fewer than the powder by an order of magnitude.
##
## Mist alone reads weightless -- steam off a boot. Clumps alone read dirty --
## gravel. Both together read true, and the reason they behave differently is
## one number each, `mist_damping` and `clump_damping`. The wind hook then falls
## out of that same number rather than being a second decision: see
## `wind_response()`, which is why a gust carries the mist away and hardly
## touches a clump.
##
## ---------------------------------------------------------------------------
## THE LOAD HAS TO BE VISIBLE ON THE LEG, OR THE PARTICLES ARE MEANINGLESS
## ---------------------------------------------------------------------------
## The mist is what the player reads as "and now I am losing it". What they read
## as "I am carrying snow" is the legs themselves going whiter -- a cool white
## crust up the boot and shin, masked below the knee, driven by the same scalar
## the shedding drains. `assets/shaders/leg_snow.gdshader` holds it, and it rides
## `GeometryInstance3D.material_overlay` so that neither the character's Meshy
## maps nor the x-ray ghost already in his `next_pass` is disturbed.
##
## ---------------------------------------------------------------------------
## IT KNOWS ABOUT FOOTFALLS, NOT ABOUT THE PLAYER
## ---------------------------------------------------------------------------
## Everything above is driven by `player.footprint` off the EventBus, which
## `PlayerController` emits deliberately so that nothing needs to know about the
## player -- its own comment says the bear will emit the same event in Wave 4.
## So this file makes no edits to the player, contains no reference to him, and
## a second walker gets leg snow by registering itself as a service and dropping
## a second copy of `scenes/effects/leg_snow.tscn` in. No `.gd` changes.
##
## The depth that loads a leg is `SnowField.deep_depth_m`, read off the field
## rather than restated here. It is the same 0.42 m that already means "reduced
## to a trudge" and that gates the ploughed furrow: one fact about the snow, now
## read three ways rather than four.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const CRUST_SHADER_PATH := "res://assets/shaders/leg_snow.gdshader"
const FOOTPRINT_EVENT := &"player.footprint"

## Who is carrying the snow. Resolved through the ServiceRegistry, the same way
## OccluderFader, CameraRig and InteriorReveal find him -- and the same reason:
## nothing may hold a node path into somebody else's scene.
@export var subject_service: StringName = &"player"

## How near a footfall has to be to count as this walker's.
##
## The footprint payload carries no publisher, and it should not: it is a fact
## about a patch of snow, not a message from a character. So a walker's own steps
## are picked out by where they landed. One and a half metres is wider than a
## stride and much narrower than the distance between two characters who are not
## standing on each other.
##
## WITH NO SUBJECT RESOLVED THIS CLAIMS EVERYTHING, which is the useful default
## rather than the safe-looking one: a scene with one walker and no registry
## still sheds snow, and the alternative -- an effect that silently does nothing
## when a lookup fails -- is the failure mode this project has been bitten by
## most.
@export var claim_radius_m := 1.5

## ---------------------------------------------------------------------------
## The load
## ---------------------------------------------------------------------------
## How much of what is still bare gets packed on by one step in deep snow. High:
## wading is not subtle, and a leg that took eight strides to load would spend
## most of a drift looking clean.
@export var pack_per_step := 0.55

## How much of the load SURVIVES one step on ground that is not deep. The whole
## shape of the effect is this number -- see the header for the sequence it
## produces. Lower and he is clean in two strides with one big burst; higher and
## the bursts never become distinct.
@export var shed_retention := 0.70

## Below this the leg is treated as clean for the purposes of throwing snow. The
## crust keeps fading below it -- it is continuous all the way to zero -- but an
## exponential never actually arrives, and emitting a burst of nought point three
## of a particle for the rest of the run is not a physical claim, it is a leak.
@export var shed_floor := 0.02

## ---------------------------------------------------------------------------
## The hook Wave 3's weather can drive, and the only optional thing here
## ---------------------------------------------------------------------------
## Dry powder in hard cold does not stick; snow near freezing does. So colder air
## should shed faster, and the model already has the number that says so.
##
## THIS IS A HOOK AND IT IS INERT, in the vocabulary BreathFog's and
## SnowfallLayer's identically-named hooks use. `src/systems/weather_system.gd`
## is Wave 3 and does not exist, and there is no air temperature anywhere in the
## project today -- `core_temperature` is the BODY's reserve, which is a
## different fact and would be the wrong one to read. Inventing an air
## temperature here would mean two of them later. `_air_chill` therefore stays 0
## until something calls `set_air_chill()`, and at 0 `shed_retention` above is
## exactly what applies.
@export var shed_retention_cold := 0.56

## ---------------------------------------------------------------------------
## Where on the leg it sits
## ---------------------------------------------------------------------------
## As fractions of the subject's height. Measured off the shipped rig rather than
## chosen: its ankle sits at 7.9% of the figure and its knee at 25.7%, so a crust
## running to 21% is on the shin and under the knee, and the powder is thrown off
## the band between the boot and there.
@export var boot_line := 0.10
@export var shin_line := 0.21

## Fallback height for a subject that publishes no `body_height`.
@export var subject_height := 1.9

## ---------------------------------------------------------------------------
## The powder
## ---------------------------------------------------------------------------
## Particles in one burst at a full shed. The count scales with the shed, so this
## is the FIRST stride out of a drift and every later one is a fraction of it.
@export var mist_per_shed := 26.0

## How long a puff of powder survives, and how fast it leaves the boot. Slow: it
## is knocked loose, not thrown.
@export var mist_life := 1.5
@export var mist_speed := 0.85

## The drag, and it is the whole difference between the two populations. High
## enough that the kick off the boot is spent in about a third of a second and
## what is left drifts.
@export var mist_damping := 2.6

## What is left of gravity once the air is holding it up. Not 9.8 and not
## pretending to be: a powder grain reaches terminal velocity immediately, and
## against the damping above this settles at about 35 cm a second, which is a
## puff sinking rather than a stone dropping.
@export var mist_fall := 0.9

## The still-air drift, in metres a second. SnowfallLayer makes the same argument
## for the same reason: snow that hangs dead still looks wrong on a calm day too,
## and this is the part the wind hook then adds to rather than replaces.
@export var mist_drift := Vector3(0.16, 0.0, 0.06)

## Birth and death radius of one puff, in metres. It EXPANDS -- powder disperses,
## so the oldest puff in a shed is the biggest and the faintest. BreathFog makes
## the same point about vapour at greater length and it is the same physics.
@export var mist_radius_birth := 0.055
@export var mist_radius_death := 0.34

## How far the palette's lightest snow is taken toward white, and the most alpha
## a puff ever carries. Both are bloom controls as much as colour ones: Art Bible
## rule 12 gives the glow to the fire and the windows, and the product of these
## two has to stay under the environment's HDR threshold or a boot-height puff
## backlit by a 21.5-degree sun blooms.
@export var mist_whiteness := 0.55
@export var mist_alpha := 0.62

## ---------------------------------------------------------------------------
## The clumps
## ---------------------------------------------------------------------------
## Expected clumps in one burst at a full shed. Under one on purpose for anything
## but the first stride out of a drift -- see `burst_count()`, which turns a
## fractional expectation into an occasional whole clump rather than into a
## permanent dribble.
@export var clumps_per_shed := 3.2
@export var clump_life := 0.9
@export var clump_speed := 1.3

## The other half of the drag pair. Nearly nothing: a clump is ballistic, which
## is what makes it land.
@export var clump_damping := 0.18
@export var clump_fall := 9.2
@export var clump_radius := 0.035
@export var clump_whiteness := 0.42
@export var clump_alpha := 0.9

## ---------------------------------------------------------------------------
## The crust on the leg
## ---------------------------------------------------------------------------
@export var crust_whiteness := 0.55
@export var crust_opacity := 0.86

## How much drag has to be present before the air can carry a particle at all.
## The mist and the clumps get their wind response from this one expression
## rather than from two hand-set numbers, which is what keeps them a single
## physical claim -- see `wind_response()`.
const WIND_COUPLING_REFERENCE := 1.0

## Godot's `emit_particle` flags, named rather than spelled 5.
const EMIT_PLACED := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY

var _bus: Node
var _registry: Node
var _snow: Node
var _subject: Node3D
var _mist: GPUParticles3D
var _clumps: GPUParticles3D
var _mist_material: ParticleProcessMaterial
var _clump_material: ParticleProcessMaterial
var _crusts: Array[ShaderMaterial] = []
var _dressed: Array[MeshInstance3D] = []
var _load := 0.0
var _last_shed := 0.0
var _steps_since_drift := 0
var _wind := Vector3.ZERO
var _air_chill := 0.0


func _ready() -> void:
	_build()
	# Trap 3: an autoload is a node under /root, never an Engine singleton. Guarded
	# on is_inside_tree() because an absolute path cannot be resolved from a node
	# that is not in a tree, and a unit test builds this one with `.new()` --
	# unguarded it is an engine ERROR, which by this project's standard is a failed
	# run whatever the assertions said.
	if is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
	if _bus != null:
		_bus.subscribe(FOOTPRINT_EVENT, _on_footprint)


func _exit_tree() -> void:
	if _bus != null:
		_bus.unsubscribe(FOOTPRINT_EVENT, _on_footprint)
	_undress()


# --- the model ----------------------------------------------------------------

## What a footfall in deep snow leaves on the leg.
##
## A fixed fraction of what is still BARE, so the first stride into a drift packs
## the most on and no number of strides packs past full. Static and contextless
## on purpose: it is arithmetic with a right answer, and it is the piece a test
## can pin down exactly without a scene, a bus or a snow field.
static func loaded_after(carried: float, gain: float) -> float:
	var held := clampf(carried, 0.0, 1.0)
	return clampf(held + (1.0 - held) * clampf(gain, 0.0, 1.0), 0.0, 1.0)


## What a footfall on ground that is not deep knocks OFF.
##
## The same rule read the other way: a fixed fraction of what is still there. The
## consequence is the whole look -- successive sheds fall away geometrically, so
## the first strides out of a drift burst and the later ones do not.
static func shed_by_a_step(carried: float, retention: float) -> float:
	return clampf(carried, 0.0, 1.0) * (1.0 - clampf(retention, 0.0, 1.0))


## How much of a wind a particle with this much drag picks up, 0 .. 1.
##
## The two populations differ in ONE property and everything else follows from
## it. Drag is what couples a particle to the air it is in, so a grain of powder
## -- which stops dead in a third of a second -- is carried, and a clump, which
## is ballistic, is barely deflected. Writing two hand-tuned wind strengths would
## have got the same picture out of two decisions that could drift apart; this
## way there is one decision and it is `mist_damping` against `clump_damping`.
static func wind_response(damping: float) -> float:
	var drag := maxf(damping, 0.0)
	return drag / (drag + WIND_COUPLING_REFERENCE)


## Turns an expected particle count into a whole one.
##
## THE FRACTIONAL PART IS A PROBABILITY, and that is what makes the clumps
## OCCASIONAL rather than continuous. At an expectation of 0.4 a clump is thrown
## on two steps in five and no clump at all on the other three, which is what a
## boot shedding lumps of packed snow actually does. Rounding instead would give
## either a clump every single step or none ever, depending on which side of a
## half the tuning happened to land.
##
## Takes the roll rather than making it, so a test can pin both branches.
static func burst_count(expected: float, roll: float) -> int:
	if expected <= 0.0:
		return 0
	var whole := int(floorf(expected))
	if roll < expected - float(whole):
		whole += 1
	return whole


## The retention actually in force, after the air temperature hook. At the
## inert default this is `shed_retention` exactly.
func retention_now() -> float:
	return lerpf(shed_retention, shed_retention_cold, clampf(_air_chill, 0.0, 1.0))


## How much snow the legs are carrying, 0 clean .. 1 straight out of a drift.
func carried() -> float:
	return _load


## What the last footfall knocked off. Zero on a step that loaded instead.
func last_shed() -> float:
	return _last_shed


## One line for tools/capture_sequence.gd. A still cannot show whether the first
## step bursts and the fourth does not; the numbers beside the frames can.
func report() -> String:
	return "legsnow[load=%.2f shed=%.2f steps=%d]" % [_load, _last_shed, _steps_since_drift]


# --- the hooks ----------------------------------------------------------------

## THE WIND HOOK, in the vocabulary BreathFog and SnowfallLayer already use for
## the identical hook. `src/systems/wind_system.gd` is Wave 3; until it exists
## this is called by nobody and the value stays zero, and the powder drifts on
## `mist_drift` alone. Both populations are driven from it through
## `wind_response()`, so one call moves the mist a long way and the clumps
## hardly at all.
func set_wind(velocity: Vector3) -> void:
	_wind = velocity
	_apply_wind()


func wind() -> Vector3:
	return _wind


## 0 near freezing .. 1 hard dry cold. See `shed_retention_cold`: this is the
## optional half of the effect and it is deliberately inert, because there is no
## air temperature in this project yet and inventing one here would mean two of
## them later.
func set_air_chill(amount: float) -> void:
	_air_chill = clampf(amount, 0.0, 1.0)


## Injection point for a test, and for whoever wires a second walker without a
## registry. Null is a legal state and means nothing ever loads -- a walker with
## no snow field is a walker with no snow.
func set_snow_field(field: Node) -> void:
	_snow = field


func set_subject(subject: Node3D) -> void:
	_undress()
	_subject = subject


# --- the footfall -------------------------------------------------------------

## Untyped, because it arrives off the bus and a payload this cannot use must be
## ignored rather than crash the publisher.
func _on_footprint(payload) -> void:
	if not (payload is Dictionary):
		return
	var data: Dictionary = payload
	var spot = data.get("position", null)
	if not (spot is Vector3):
		return
	if not _claims(spot):
		return
	# The depth AT THE FOOT, which the publisher has already measured, rather
	# than a second sample taken from the field at the body's centre. The foot is
	# where the leg meets the snow, so it is the honest place to ask.
	step(spot, float(data.get("depth", 0.0)), _heading_of(data))


## One footfall, and the whole of the model. Public so a test can walk a body
## through a drift and out of it without a bus, a field or a scene tree.
func step(spot: Vector3, depth: float, heading: Vector2) -> void:
	var deep := _deep_depth()
	if depth >= deep:
		_load = loaded_after(_load, pack_per_step)
		_last_shed = 0.0
		_steps_since_drift = 0
		_place(spot)
		return
	_steps_since_drift += 1
	var shed := shed_by_a_step(_load, retention_now())
	_load = maxf(_load - shed, 0.0)
	_last_shed = shed
	_place(spot)
	if _load + shed < shed_floor:
		# Long clean. Nothing left to knock off, and the crust below the floor is
		# already fading to nothing on its own.
		return
	_throw(spot, shed, heading)


## The depth at which a leg starts collecting snow.
##
## READ OFF THE FIELD AND NOT RESTATED. `SnowField.deep_depth_m` is already the
## depth the game calls a trudge and already the depth the ploughed furrow starts
## at; a copy of the number here would be a fourth threshold that could disagree
## with the other three. With no field resolved this returns INF, which is the
## correct behaviour rather than a guard: there is no snow, so nothing loads.
func _deep_depth() -> float:
	_resolve()
	if _snow == null:
		return INF
	return float(_snow.deep_depth_m)


## Is this footfall this walker's?
##
## See `claim_radius_m`: with nobody resolved, everything is claimed.
func _claims(spot: Vector3) -> bool:
	_resolve()
	if _subject == null or not is_instance_valid(_subject):
		return true
	var here := _subject.global_position
	return Vector2(spot.x - here.x, spot.z - here.z).length() <= claim_radius_m


static func _heading_of(data: Dictionary) -> Vector2:
	var forward = data.get("forward", null)
	if forward is Vector2 and (forward as Vector2).length_squared() > 0.0001:
		return (forward as Vector2).normalized()
	return Vector2.ZERO


# --- throwing it --------------------------------------------------------------

## The burst: powder first, then whatever clumps this step happened to earn.
##
## Emitted one particle at a time, in WORLD space, at a transform this file
## chooses. That is what lets the count be exactly proportional to the shed --
## the thing the whole design rests on -- and it is why the emitters are driven
## by `emit_particle()` rather than by a rate. A rate would put the burst on a
## clock, and the clock is the one thing this effect must not have.
func _throw(spot: Vector3, shed: float, heading: Vector2) -> void:
	if _mist == null or _clumps == null:
		return
	var top := _leg_top_m()
	var count := burst_count(mist_per_shed * shed, randf())
	for _index in range(count):
		_mist.emit_particle(
			Transform3D(Basis.IDENTITY, _birth_point(spot, top)),
			_powder_velocity(heading), Color.WHITE, Color.WHITE, EMIT_PLACED)
	var lumps := burst_count(clumps_per_shed * shed, randf())
	for _index in range(lumps):
		_clumps.emit_particle(
			Transform3D(Basis.IDENTITY, _birth_point(spot, top * 0.8)),
			_clump_velocity(heading), Color.WHITE, Color.WHITE, EMIT_PLACED)


## Somewhere on the boot or the shin. Spread over the whole band rather than
## emitted from a point, because the snow is not on a point -- it is on a leg.
func _birth_point(spot: Vector3, top: float) -> Vector3:
	return spot + Vector3(
		randf_range(-0.055, 0.055),
		randf_range(0.02, maxf(top, 0.06)),
		randf_range(-0.055, 0.055))


## Off the boot, forward and a little up. The leg is swinging when the snow comes
## off it, so the powder goes where the leg was going; the rest is scatter.
func _powder_velocity(heading: Vector2) -> Vector3:
	var throw := Vector3(heading.x, 0.0, heading.y) * randf_range(0.25, 0.7)
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * randf_range(0.2, 0.6)
	var rise := Vector3(0.0, randf_range(0.1, 0.45), 0.0)
	return (throw + scatter + rise) * mist_speed


## Down and forward. A clump leaves the boot on the same swing the powder does
## and then does what its mass says: it falls.
func _clump_velocity(heading: Vector2) -> Vector3:
	var throw := Vector3(heading.x, 0.0, heading.y) * randf_range(0.3, 0.9)
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.25
	var drop := Vector3(0.0, randf_range(-0.6, -0.1), 0.0)
	return (throw + scatter + drop) * clump_speed


## Where the crust reaches on this subject, in world metres. Read off the body it
## is actually on rather than assumed, so a bear with different proportions gets
## its own number from its own height.
func _leg_top_m() -> float:
	return _subject_height() * shin_line


## How tall the walker says he is, in metres. Published by PlayerController as
## `body_height`; the fallback is for a subject that publishes nothing, and for a
## test with no body at all.
func _subject_height() -> float:
	if _subject != null and is_instance_valid(_subject):
		var published = _subject.get("body_height")
		if published != null:
			return float(published)
	return subject_height


## Keeps the emitters' culling boxes over the walker.
##
## A GPUParticles3D is culled by `visibility_aabb` around its own node, and these
## particles are in WORLD space -- so without this the whole shed would be culled
## out of existence the moment the walker got 4 m from wherever this node started.
## Moving the node does not drag the particles: that is the point of world space,
## and it is the same arrangement Snowfall uses to place its layers.
func _place(spot: Vector3) -> void:
	# global_position asserts is_inside_tree() and prints an engine ERROR when it
	# fails, which the suite's pristine-output rule turns into a failure a long way
	# from its cause. Out of a tree there is no camera to cull against anyway.
	if is_inside_tree():
		global_position = spot
	else:
		position = spot


# --- the crust ----------------------------------------------------------------

func _process(_delta: float) -> void:
	_resolve()
	if _subject != null and is_instance_valid(_subject):
		_dress(_subject)
	var feet := 0.0
	if _subject != null and is_instance_valid(_subject):
		feet = _subject.global_position.y
	var fill: Color = ambient_fill()
	for crust in _crusts:
		crust.set_shader_parameter(&"load", _load)
		# Every frame, not once: his feet move, and a crust anchored to a stale
		# height would ride up his legs the moment he walked downhill.
		crust.set_shader_parameter(&"origin_y", feet)
		crust.set_shader_parameter(&"fill", Vector3(fill.r, fill.g, fill.b))


## One property write per mesh, and nothing about the character's own material
## changes.
##
## `material_overlay` rather than `material_override` or `next_pass`, and the
## choice is forced twice over: the override is where PlayerController mounts the
## four Meshy maps, and `next_pass` is where `STENCIL_MODE_XRAY` builds the ghost
## that lets the figure read through the farmhouse. Overlay is the third slot and
## nothing else is using it.
##
## An overlay that is already occupied is left alone. A silent fight over one
## property between two systems is the defect this project has already paid for
## once, with `transparency`.
func _dress(subject: Node3D) -> void:
	if not _dressed.is_empty():
		return
	var meshes: Array[MeshInstance3D] = []
	_meshes_of(subject, meshes)
	for mesh in meshes:
		if mesh.mesh == null or mesh.material_overlay != null:
			continue
		var crust := crust_material()
		crust.set_shader_parameter(&"figure_height", _subject_height())
		mesh.material_overlay = crust
		_dressed.append(mesh)
		_crusts.append(crust)


## The Environment's ambient fill, in linear light.
##
## READ OFF THE LIVE ENVIRONMENT, never restated. The crust's shader declares
## `ambient_light_disabled` because every shader in this project must -- see
## `tests/art/test_character_lighting.gd`, which is the gate holding that rule
## shut -- and on this character that rule removes very nearly all of his light,
## because the sun sits nearly behind the lens and the fill is what is actually
## lighting him. So the fill is handed to the shader and added back as emission
## on that one material. Reading it here rather than copying the number is what
## stops the crust and the coat drifting into two different lights the first time
## somebody retunes the Environment.
##
## Returns black when there is no ambient to have, which is the right answer
## rather than a guard: the crust is then lit by the sun and the key alone, which
## is exactly what the coat under it gets in that case too.
func ambient_fill() -> Color:
	var env := _environment()
	if env == null or env.ambient_light_source != Environment.AMBIENT_SOURCE_COLOR:
		return Color(0.0, 0.0, 0.0)
	var linear := env.ambient_light_color.srgb_to_linear()
	var energy := env.ambient_light_energy
	return Color(linear.r * energy, linear.g * energy, linear.b * energy)


func _environment() -> Environment:
	if not is_inside_tree():
		return null
	var viewport := get_viewport()
	if viewport == null:
		return null
	var camera := viewport.get_camera_3d()
	if camera != null and camera.environment != null:
		return camera.environment
	var world := viewport.find_world_3d()
	return null if world == null else world.environment


func _undress() -> void:
	for index in range(_dressed.size()):
		var mesh := _dressed[index]
		if is_instance_valid(mesh) and mesh.material_overlay == _crusts[index]:
			mesh.material_overlay = null
	_dressed.clear()
	_crusts.clear()


## A crust material carrying everything that does not depend on the mesh it
## lands on. Public so a test can read what it was given without building a body.
##
## One per surface rather than one shared, because `foot_y` and `figure_height`
## are facts about a particular mesh -- a subject drawn as two meshes at two
## scales would otherwise get one of them masked against the other's box.
func crust_material() -> ShaderMaterial:
	var crust := ShaderMaterial.new()
	crust.shader = load(CRUST_SHADER_PATH)
	crust.set_shader_parameter(&"snow_color", _cool_white(crust_whiteness))
	crust.set_shader_parameter(&"boot_line", boot_line)
	crust.set_shader_parameter(&"shin_line", shin_line)
	crust.set_shader_parameter(&"max_opacity", crust_opacity)
	crust.set_shader_parameter(&"load", _load)
	return crust


## The palette's lightest snow, taken part of the way to white.
##
## NOT a literal, and not white. Every colour in this game comes out of
## `data/palette/color_bible.tres`, and Art Bible rule 12 reserves the warm
## pixels for the fire, the windows, the beacon, the truck and the scarf -- snow
## off a boot is none of those, so it stays firmly in the cool tones. Lerping
## toward white keeps it there: white is neutral, so the blue stays above the red
## the whole way.
func _cool_white(toward_white: float) -> Color:
	var bible = load(PALETTE_PATH)
	if bible == null:
		return Color(0.8, 0.86, 0.93)
	var snow: Color = bible.snow_tones[0]
	return snow.lerp(Color.WHITE, clampf(toward_white, 0.0, 1.0))


# --- the emitters -------------------------------------------------------------

func _build() -> void:
	_mist = _build_population(
		"Powder", 96, mist_life, mist_damping, mist_radius_birth,
		_swell_curve(mist_radius_death / maxf(mist_radius_birth, 0.0001)),
		_powder_ramp(), _powder_texture(), _cool_white(mist_whiteness), mist_alpha)
	_mist_material = _mist.process_material as ParticleProcessMaterial
	_clumps = _build_population(
		"Clumps", 24, clump_life, clump_damping, clump_radius,
		null, _clump_ramp(), _clump_texture(), _cool_white(clump_whiteness), clump_alpha)
	_clump_material = _clumps.process_material as ParticleProcessMaterial
	_apply_wind()


func _build_population(
		name_of: String, buffer: int, life: float, damping: float, radius: float,
		swell: CurveTexture, ramp: GradientTexture1D, dot: GradientTexture2D,
		tone: Color, alpha: float) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = name_of
	# THE WHOLE EFFECT, and the one line here that cannot go wrong quietly. A puff
	# knocked off a boot stays where it was knocked off; the walker keeps going and
	# leaves it behind him. In local space every puff would drag along with the leg
	# and the shed would read as a permanent smear on his shins.
	emitter.local_coords = false
	emitter.amount = buffer
	emitter.lifetime = life
	emitter.one_shot = false
	emitter.explosiveness = 0.0
	# NOT EMITTING, AND THAT IS WHAT MAKES THE MANUAL EMISSION WORK. Every
	# particle here arrives by `emit_particle()`, on a footfall.
	#
	# MEASURED ON 4.7.1, because the plausible arrangement is the broken one. The
	# obvious way to stop an emitter producing a rate of its own while still
	# accepting manual particles is `emitting = true` with `amount_ratio = 0`, on
	# the reasoning that a system has to be running to simulate anything. It is
	# silent and it emits NOTHING: three emitters side by side under one camera,
	# configured true/0, false/1 and true/1, produced no particles, particles, and
	# particles. `emitting = false` is processed on demand, and a burst still
	# appears on an emitter whose previous particles all died a second earlier --
	# which is the case that actually matters here, since a walk on clear ground
	# sheds nothing for minutes at a time.
	emitter.emitting = false
	# Rule 10 makes the long shadows the subject of the frame, cast at 8192 across
	# four splits. A hundred grains of powder do not belong in that map.
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Around the walker, who this node follows. Generous enough to cover where the
	# powder drifts to over its life and where a clump lands.
	emitter.visibility_aabb = AABB(Vector3(-3.0, -1.5, -3.0), Vector3(6.0, 4.5, 6.0))

	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	motion.damping_min = damping * 0.8
	motion.damping_max = damping * 1.2
	motion.scale_min = radius * 0.7
	motion.scale_max = radius * 1.3
	motion.color_ramp = ramp
	if swell != null:
		motion.scale_curve = swell
	emitter.process_material = motion

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _surface(tone, alpha, dot)
	emitter.draw_pass_1 = quad
	add_child(emitter)
	return emitter


## Cool, unshaded, alpha-blended and mixed rather than added.
##
## Unshaded is Art Bible rule 8's banned list in one property -- there is no
## specular, no roughness and no reflection to switch off -- and MIX rather than
## ADD is rule 12 again: additive blending is a glow by another name, and two
## puffs crossing would be brighter than either. `tests/unit/test_leg_snow.gd`
## holds the peak under the environment's bloom threshold.
func _surface(tone: Color, alpha: float, dot: GradientTexture2D) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color(tone.r, tone.g, tone.b, alpha)
	surface.albedo_texture = dot
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	surface.billboard_keep_scale = true
	surface.disable_receive_shadows = true
	return surface


## A smooth bell, centre to rim, for the powder.
##
## The same shape and the same reasoning as `BreathFog._puff_texture()`, and
## deliberately not a different one: a disc has a shoulder in it, and where two
## discs overlap the eye finds both outlines and reads two circles. A bell has no
## shoulder anywhere, so the composited alpha rises smoothly through the join and
## a shed reads as one drifting mass rather than as a handful of dots.
func _powder_texture() -> GradientTexture2D:
	return _radial(
		PackedFloat32Array([0.0, 0.24, 0.48, 0.7, 1.0]),
		PackedFloat32Array([1.0, 0.9, 0.62, 0.28, 0.0]))


## A clump is not a bell. It is a lump with an edge on it, and at the size these
## are drawn the core has to hold nearly to the rim or there is nothing left.
func _clump_texture() -> GradientTexture2D:
	return _radial(
		PackedFloat32Array([0.0, 0.6, 0.85, 1.0]),
		PackedFloat32Array([1.0, 1.0, 0.5, 0.0]))


func _radial(offsets: PackedFloat32Array, alphas: PackedFloat32Array) -> GradientTexture2D:
	var gradient := Gradient.new()
	var colors := PackedColorArray()
	for alpha in alphas:
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 48
	texture.height = 48
	return texture


## Alpha over a puff's life. It emerges and it disperses; neither end is a cliff.
## The long convex tail is what stops the mist having a frame in which it
## visibly stopped existing.
func _powder_ramp() -> GradientTexture1D:
	return _ramp(
		PackedFloat32Array([0.0, 0.08, 0.3, 0.62, 0.85, 1.0]),
		PackedFloat32Array([0.0, 1.0, 0.86, 0.46, 0.15, 0.0]))


## A clump is opaque until it is gone. It does not disperse -- it lands, and the
## short fade at the end is the only concession, so it does not blink out in
## mid-air.
func _clump_ramp() -> GradientTexture1D:
	return _ramp(
		PackedFloat32Array([0.0, 0.1, 0.8, 1.0]),
		PackedFloat32Array([0.9, 1.0, 1.0, 0.0]))


func _ramp(offsets: PackedFloat32Array, alphas: PackedFloat32Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	var colors := PackedColorArray()
	for alpha in alphas:
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Radius over life, as a multiple of the size the puff was born at. Up quickly
## out of the boot, then it KEEPS OPENING while the ramp above thins it -- which
## is what dispersal looks like. A curve that came back down would make the
## oldest puff the smallest and the shed would read as sparks going out.
func _swell_curve(growth: float) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = maxf(growth, 1.0)
	curve.add_point(Vector2(0.0, 0.45))
	curve.add_point(Vector2(0.18, 1.0))
	curve.add_point(Vector2(0.6, growth * 0.62))
	curve.add_point(Vector2(1.0, growth))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## Gravity is where a ParticleProcessMaterial keeps every constant acceleration,
## so what is left of a grain's weight and whatever the wind system is blowing
## arrive in the same slot. The drift is the still-air part and the wind adds to
## it; each population takes the share of the wind its own drag earns it.
func _apply_wind() -> void:
	if _mist_material != null:
		_mist_material.gravity = Vector3(mist_drift.x, -mist_fall, mist_drift.z) \
			+ _wind * wind_response(mist_damping)
	if _clump_material != null:
		_clump_material.gravity = Vector3(0.0, -clump_fall, 0.0) \
			+ _wind * wind_response(clump_damping)


# --- resolution ---------------------------------------------------------------

## get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is a
## node under /root and never enters the engine's singleton registry (briefing
## trap 3).
func _resolve() -> void:
	if _registry == null and is_inside_tree():
		_registry = get_node_or_null("/root/ServiceRegistry")
	if _registry == null:
		return
	if _snow == null:
		_snow = _registry.get_service(&"snow_field") as Node
	if _subject == null or not is_instance_valid(_subject):
		_subject = _registry.get_service(subject_service) as Node3D


static func _meshes_of(node: Node, found: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		_meshes_of(child, found)
