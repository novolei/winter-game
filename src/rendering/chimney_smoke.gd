class_name ChimneySmoke
extends GPUParticles3D

## 袅袅炊烟 -- the thread of smoke from the farmhouse flue. 有烟火气才有生命力.
##
## The motion lives in assets/shaders/chimney_smoke.gdshader and the reasoning
## for it lives there too. This file owns the four things a shader cannot know:
## WHERE the flue is, WHETHER the fire is lit, WHAT COLOUR smoke is in this
## project, and what the rest of the game is told about the column.
##
## ---------------------------------------------------------------------------
## 袅袅 IS A CONSTRAINT, NOT A MOOD
## ---------------------------------------------------------------------------
## Not a plume, not a column, not a cone of particles: a thin ribbon that curls,
## folds back on itself and thins away. Everything tuned below was chosen against
## that word, and the four properties it rules in are:
##
##   * buoyancy FALLS OFF -- a constant rise speed reads as a jet
##   * turbulence grows with AGE, not with height -- that is what makes it curl
##     rather than travel
##   * it DISSIPATES, it does not end -- particles cut off at a lifetime
##     boundary put a visible ceiling on the column
##   * it is a RIBBON -- narrow mouth, low spread, widened by turbulence
##
## ---------------------------------------------------------------------------
## THE WIND IS THE POINT
## ---------------------------------------------------------------------------
## This is the most legible wind cue the scene has, and better than the swaying
## wire, because it is always there and its WHOLE SILHOUETTE responds. Light wind
## bends it and carries it downwind as it rises; strong wind lays it nearly flat
## and tears it into scraps.
##
## And the part that separates smoke that responds to wind from smoke that is
## MADE OF wind history: a gust arrives as a bend that travels UP the column,
## because the smoke already emitted remembers the wind it was born into. That
## falls out of applying the wind as a per-particle drag rather than as a
## displacement -- the shader header derives it, and
## `test_chimney_smoke.gd::test_a_gust_travels_up_the_column` is it as a
## property, checked against the wind model itself rather than against a
## screenshot.
##
## No wind is invented here. `WindSystem` is the source; this node publishes the
## two hooks that system sweeps the tree for -- `set_wind(Vector3)` and
## `set_wind_strength(float)` -- so it is driven with no edit to either file and
## no path between them.
##
## ONE RECONCILIATION, stated rather than hidden. `WindSystem.velocity()` is
## named a velocity, is documented as an acceleration in m/s^2, and is added
## into a `ParticleProcessMaterial.gravity` by all three of the older consumers.
## This one needs a target VELOCITY for its drag term -- "the air the smoke is
## in" -- and 1.68 m/s at a full gale would bend the column by about 50 degrees
## and no further, which is not "nearly flat". `wind_gain` converts the shared
## vocabulary into this one, in one place, without retuning anything else.
##
## ---------------------------------------------------------------------------
## IT ONLY SMOKES WHEN THE FIRE IS LIT, AND IT ASKS RATHER THAN LISTENS
## ---------------------------------------------------------------------------
## The `&"fires"` group already means "alight" -- membership tracks the state, so
## a cold stove is not in it (see src/entities/fires.gd). This node therefore
## ASKS the group, on a short timer, and subscribes to nothing.
##
## That is deliberate and it is the correction of a fault this project has found
## twice: a node that only listens for a transition can never learn about a fire
## that was already burning when it woke up. An event subscription would need an
## on-ready query beside it to be correct -- two paths to one fact, one of which
## is exercised on the first frame only. Asking is the on-ready query, repeated;
## it cannot go stale and it has no second path to keep in step. A quarter of a
## second of latency on a column that takes `kindle_seconds` to build is not
## visible.
##
## WHICH fire: one burning BELOW THIS FLUE, inside `hearth_radius_m` of its
## axis. Not the nearest fire -- wave 4 lights beacons in the valley and a
## chimney that smoked because something was burning in a field would be worse
## than one that never smoked at all.
##
## ---------------------------------------------------------------------------
## COLOUR: COOL, AND NOT NEGOTIABLE
## ---------------------------------------------------------------------------
## Art Bible rule 12 allows warm pixels on windows, fire, beacon, truck and the
## scarf. Smoke is on none of those lists, and at this framing a warm column
## against a blue sky would be the brightest thing in the frame. Real wood smoke
## against a winter sky is a pale neutral grey anyway, so the rule and the truth
## agree. Read from data/palette/color_bible.tres, never written here.
##
## No glow. Bloom on smoke reads cheap -- the same reason the snowfall was
## refused it -- and `test_chimney_smoke.gd` pins the peak under the
## LightingDirector's own 0.95 threshold.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const PROCESS_SHADER_PATH := "res://assets/shaders/chimney_smoke.gdshader"

## What wave 5 subscribes to. GDD section 8's threats approach the farmstead, and
## a column visible across the valley is exactly the kind of thing that should
## draw them -- so the column announces itself now, and that becomes a
## subscription later rather than a rewrite. `column_position()` and
## `column_strength()` are the polled form of the same fact.
const EVENT_COLUMN_RAISED := &"smoke.column_raised"
const EVENT_COLUMN_FADED := &"smoke.column_faded"

## ---------------------------------------------------------------------------
## Where the flue is
## ---------------------------------------------------------------------------
## Resolved in three steps, most explicit first, and `flue_source()` reports
## which one won so a test can fail when the marker silently stops resolving.
##
##   1. `flue_path`, if the scene authored one.
##   2. a node under this one's parent whose name is in `flue_marker_names`, or
##      failing that any node with "flue" in its name. The chimney's hole is
##      opened in the Blender pipeline and the marker comes with it; the
##      contains-match is the rendezvous, so whichever of the plausible names it
##      lands under is found without an edit here.
##   3. `placeholder_offset`, below.
@export var flue_path: NodePath = NodePath()

## `Chimney_Flue_Mouth` is what the Blender pipeline actually shipped -- an empty
## at (0, 8.55, -5.25) inside farmhouse.glb, which is the same point to the
## millimetre as the `placeholder_offset` below, derived independently off the
## build script. The rest are kept because a second building's flue will be named
## by whoever builds it, and the contains-"flue" fallback catches the ones nobody
## thought of.
@export var flue_marker_names: Array[StringName] = [
	&"Chimney_Flue_Mouth", &"FH_Flue", &"Flue", &"Flue_Mouth", &"Chimney_Flue",
]

## THE PLACEHOLDER, and it is a measurement rather than a guess.
## tools/blender/build_farmhouse.py puts `Chimney_Stack` at Blender
## x -0.45..0.45, y 4.90..5.60, z 4.00..8.40 and `Chimney_Cap` on top of it to
## z 8.55. Godot takes Blender's +Z to +Y and its +Y to -Z, so the cap's top
## face is y = 8.55 and the stack's centre line is x = 0, z = -5.25 -- which is
## 0.10 m from the stove the scene stands at (0, 0.45, -5.35), as the build
## script's own comment says it should be ("directly above the stove").
##
## Local to this node's parent, which is the Farmhouse: the building settles
## itself onto the snow at _ready() and the flue has to come down with it.
@export var placeholder_offset := Vector3(0.0, 8.55, -5.25)

## ---------------------------------------------------------------------------
## The fire below
## ---------------------------------------------------------------------------
## How far off the flue's vertical axis a fire may be and still be this
## chimney's. The farmhouse main room is under 7 m across, so this reaches the
## whole of it and none of the valley.
@export var hearth_radius_m := 4.0

## How far below the flue to stop looking. The stove sits 8.1 m under the cap;
## anything below the floor is not in this house.
@export var hearth_drop_m := 12.0

## Seconds for the column to build once the fire is lit, and to fade once it is
## out. FADING IS THE SLOWER OF THE TWO ON PURPOSE: a flue that has been drawing
## for hours is hot, and it goes on drawing after the fire in it dies. A column
## that switched off with the fire would read as a light being turned off.
@export var kindle_seconds := 6.0
@export var ember_seconds := 14.0

## ---------------------------------------------------------------------------
## The wind
## ---------------------------------------------------------------------------
## Converts `WindSystem.velocity()` -- which the shared vocabulary states in
## m/s^2 and which this node needs as the metres-per-second of the air itself --
## into a target speed for the drag term. See the class comment; at 2.2 a full
## gale is about 3.7 m/s against a rise that has settled near 1 m/s, which lays
## the column over past 70 degrees and reads as nearly flat.
@export var wind_gain := 2.2

## ---------------------------------------------------------------------------
## The shape of it -- mirrored onto the shader, which holds the reasoning
## ---------------------------------------------------------------------------
@export_group("Ribbon")
@export var mouth_radius := 0.16
@export var exit_speed := 1.35
@export var buoyancy := 1.10
@export var buoyancy_decay := 3.20
@export var coupling_seconds := 0.55

@export_group("Break-up")
@export var curl_strength := 2.00
@export var curl_growth := 1.70
@export var curl_wind_gain := 1.80
@export var curl_scale := 0.55

@export_group("Size and fade")
## In metres ACROSS, not radius -- the draw quad is one unit square, so this is
## the width of the puff. Checked against the widest framing the camera rig
## offers (orthographic_size 17.0): see
## `test_chimney_smoke.gd::test_the_wisp_survives_the_widest_framing`.
@export var size_birth := 0.45
@export var size_death := 3.60
## How much of the growth has happened by half life. Below 0.5 the swell is
## back-loaded, which is what dispersal looks like: slow while the puff is still
## coherent, quick once it has broken up.
@export var size_bias := 0.38
@export var peak_alpha := 0.30
## Where the alpha reaches full and where it starts to go, as fractions of the
## life. In quickly -- smoke is dense at the lip -- and out over most of the
## rest, so the column thins OUT of existence rather than reaching a ceiling.
@export var alpha_in := 0.07
@export var alpha_hold := 0.14
## How much of the alpha a full gale takes off. Wind does not only bend smoke,
## it mixes it away.
@export var wind_thinning := 0.25
## How much of the rise is bled off, as a time constant in seconds. With the
## buoyancy above, this settles the climb at a terminal speed instead of letting
## it run away.
@export var rise_damping_seconds := 1.60

@export_group("Colour")
## Which snow tone the smoke is built from, and how far it is taken toward
## white. Never a literal -- binding constraint 6.
##
## The SECOND snow tone rather than the lightest, and that is the difference
## between smoke and steam: the breath fog takes the lightest tone 42% of the
## way to white because condensing breath really is nearly white, and wood smoke
## is a shade greyer and sits down off the sky it is seen against.
@export var smoke_tone_index := 1
@export var smoke_whiteness := 0.55

## ---------------------------------------------------------------------------
## The buffer
## ---------------------------------------------------------------------------
## Allocated once at the full figure and never rewritten. Density is carried by
## `amount_ratio`: assigning `amount` re-allocates and every puff in the air
## disappears on that frame, which on a column that is meant to build and fade
## would tear visibly every time the fire changed state.
##
## `puff_life_seconds` is long on purpose. It is how many seconds of weather the
## column holds -- the valley profile's slowest gust octave is 9 s, so a life
## near that keeps most of one gust cycle in the air at once, which is what makes
## a travelling kink something you can watch rather than infer.
@export var puffs := 110
@export var puff_life_seconds := 9.0

## How often the fires group is re-asked, in seconds. See the class comment.
@export var hearth_poll_seconds := 0.25

var _wind := Vector3.ZERO
var _strength := 0.0
var _draught := 0.0
var _lit := false
var _raised := false
var _since_poll := INF
var _flue_source: StringName = &"unresolved"
var _material: ShaderMaterial = null
var _bus = null


func _ready() -> void:
	_build()
	if _bus == null and is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
	# Ask before the first frame rather than waiting for the timer, so a run that
	# opens on a lit stove opens with a column instead of kindling one.
	_place()
	_poll_hearth()
	# ...and start where the fire already is. A house whose fire has been going
	# since before the world existed should not be seen lighting it.
	_draught = 1.0 if _lit else 0.0
	_apply()


# --- what the wind system drives --------------------------------------------

## THE HOOK `WindSystem` sweeps for. The vector is the shared
## acceleration-flavoured vocabulary; `wind_gain` converts it. See the class
## comment.
func set_wind(velocity: Vector3) -> void:
	_wind = Vector3(velocity.x, 0.0, velocity.z) * wind_gain


## The other hook, 0 dead still .. 1 full gale. Read by a puff at birth and
## remembered for its whole life, which is what makes a gust tear a SEGMENT of
## the column rather than all of it.
func set_wind_strength(strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)


func wind_metres_per_second() -> Vector3:
	return _wind


func wind_strength() -> float:
	return _strength


# --- what the rest of the game may ask ---------------------------------------

## Where the column starts, in world space. The thing wave 5's threats will home
## on; see EVENT_COLUMN_RAISED.
func column_position() -> Vector3:
	return global_position if is_inside_tree() else position


## How much of a column there is, 0 nothing .. 1 a fire drawing well. Continuous,
## so a subscriber can weigh a guttering fire against a roaring one instead of
## being told only that something is burning.
func column_strength() -> float:
	return _draught


## Whether there is a column to see at all. The latch EVENT_COLUMN_RAISED and
## EVENT_COLUMN_FADED are published on, with hysteresis, so a fire hovering at
## the edge of lighting does not publish a storm.
func column_visible() -> bool:
	return _raised


## Whether a fire is burning under this flue right now.
func hearth_is_lit() -> bool:
	return _lit


## Which of the three resolution steps placed this node: &"path", &"marker",
## &"placeholder" or &"unresolved". Public so a test can fail the day the
## Blender marker stops resolving -- a smoke column that silently falls back to
## a hardcoded offset when the chimney moves is the defect this exists to catch.
func flue_source() -> StringName:
	return _flue_source


# --- the fire ----------------------------------------------------------------

## Is a fire burning below this flue?
##
## Asked of the `&"fires"` group, whose membership already means alight, so
## there is no `is_lit()` filter here and there must not be one -- see fires.gd
## on why letting a caller filter is how the group's meaning rots.
##
## Beneath the flue and inside `hearth_radius_m` of its axis, rather than
## nearest: wave 4 lights beacons out in the valley, and a chimney that smoked
## because something was burning in a field would be worse than one that never
## smoked at all.
func _poll_hearth() -> void:
	_since_poll = 0.0
	var flue := column_position()
	_lit = false
	for fire in Fires.all(self):
		if is_this_chimneys_fire(flue, Fires.position_of(fire), hearth_radius_m, hearth_drop_m):
			_lit = true
			return


## The build and the fade, as a pure function, so the asymmetry can be asserted
## without waiting fourteen seconds for it.
static func draught_step(current: float, lit: bool, delta: float,
		kindle: float, ember: float) -> float:
	var span := maxf(kindle if lit else ember, 0.001)
	var target := 1.0 if lit else 0.0
	var step := delta / span
	if current < target:
		return minf(current + step, target)
	return maxf(current - step, target)


## Is `fire` this chimney's? Beneath the flue, inside `radius` of its axis and
## no further than `drop` below it. Static and taking bare points so the rule can
## be asserted without a scene: the whole risk it guards is that a beacon lit out
## in the valley makes the farmhouse smoke.
static func is_this_chimneys_fire(flue: Vector3, fire: Vector3,
		radius: float, drop: float) -> bool:
	if fire.y > flue.y:
		return false
	if flue.y - fire.y > drop:
		return false
	return Vector2(fire.x - flue.x, fire.z - flue.z).length() <= radius


# --- the model, mirrored out of the shader ------------------------------------
#
# THESE FIVE ARE THE SHADER'S OWN ARITHMETIC, IN GDSCRIPT, and they exist for one
# reason: the claims this effect is built on -- the buoyancy falls off, the
# turbulence grows with age, the alpha never reaches a cliff, and above all THE
# GUST TRAVELS UP THE COLUMN -- are properties of the model rather than of the
# picture, and a property is worth more as a test than as a screenshot.
#
# They are a MIRROR and that is a real cost, stated rather than hidden: two
# copies of one model can drift. What stops them is that each one is two or three
# lines, they are named the same on both sides, and the shader block each mirrors
# is marked. The alternative -- asserting all of this off captured PNGs -- would
# test the renderer and the tuning together and tell you neither when it failed.


## Upward acceleration at `age`, 0 at the lip .. 1 at the end. See the shader's
## point 1: a constant rise is the tell of an emitter pointed upward.
static func buoyancy_at(age: float, lift: float, decay: float) -> float:
	return lift * exp(-clampf(age, 0.0, 1.0) * decay)


## How hard the curl field pushes a puff of this age that was born into this
## wind. Grows with AGE, not with height -- that is what makes smoke curl rather
## than travel.
static func curl_gain_at(age: float, born_into: float, strength: float,
		growth: float, wind_gain: float) -> float:
	return strength * pow(clampf(age, 0.0, 1.0), growth) \
		* (1.0 + clampf(born_into, 0.0, 1.0) * wind_gain)


## Alpha over life. Zero at both ends, and the tail is cubed so it meets zero
## with no slope: a linear fall still has an edge where it lands, and at this
## camera the eye finds that edge as the top of the column.
static func alpha_at(age: float, born_into: float, peak: float,
		rise_in: float, hold: float, thinning: float) -> float:
	var held := clampf(age, 0.0, 1.0)
	var up := smoothstep(0.0, maxf(rise_in, 0.001), held)
	var fall := 1.0 - smoothstep(clampf(hold, 0.0, 0.99), 1.0, held)
	fall = fall * fall * fall
	return peak * up * fall * (1.0 - clampf(born_into, 0.0, 1.0) * clampf(thinning, 0.0, 1.0))


## Width of a puff of this age, in metres. Only ever grows -- smoke disperses, so
## the oldest puff is the biggest and the faintest.
static func size_at(age: float, birth: float, death: float, bias: float) -> float:
	var shaped := pow(clampf(age, 0.0, 1.0), log(clampf(bias, 0.05, 0.95)) / log(0.5))
	return lerpf(birth, death, shaped)


## How high a puff has climbed after `seconds`, integrating the same buoyancy and
## the same damping the shader does.
static func rise_after(seconds: float, step: float, lift: float, decay: float,
		damping: float, exit: float, life: float) -> float:
	var speed := exit
	var height := 0.0
	var t := 0.0
	while t < seconds:
		var d := minf(step, seconds - t)
		speed += buoyancy_at(t / maxf(life, 0.001), lift, decay) * d
		speed -= speed * (1.0 - exp(-d / maxf(damping, 0.001)))
		height += speed * d
		t += d
	return height


## THE WHOLE CLAIM, AS ARITHMETIC.
##
## `wind_samples[i]` is the air at the flue at time `i * step`, oldest first, in
## metres a second. The answer's element `i` is where the puff BORN at that
## sample has drifted to by the end of the run -- so element 0 is the oldest and
## highest puff in the column and the last element is the one still at the lip.
##
## The shape of that array IS the column, seen from the side. And because each
## puff integrates a drag toward the air around it,
##
##     offset(born) = INTEGRAL from t_born to now of (the wind, lagged)
##
## the DIFFERENCE between adjacent elements is the wind at the moment between
## their births. A gust is therefore a steep stretch of this array at a fixed
## BIRTH TIME -- which means that as `now` advances, the stretch belongs to ever
## older and therefore ever higher puffs. The kink climbs, and it climbs because
## of what integrating a shared force per particle means rather than because
## anything computes it.
##
## `test_chimney_smoke.gd::test_a_gust_travels_up_the_column` drives this with
## the real valley profile and measures where the steepest stretch is at two
## times a second apart.
static func column_offsets(wind_samples: PackedVector2Array, step: float,
		coupling: float) -> PackedVector2Array:
	var offsets := PackedVector2Array()
	var count := wind_samples.size()
	offsets.resize(count)
	var catch_up := 1.0 - exp(-maxf(step, 0.0001) / maxf(coupling, 0.001))
	for born in range(count):
		var speed := Vector2.ZERO
		var where := Vector2.ZERO
		for now in range(born, count):
			speed += (wind_samples[now] - speed) * catch_up
			where += speed * step
		offsets[born] = where
	return offsets


# --- lifecycle ---------------------------------------------------------------

func _process(delta: float) -> void:
	_place()
	_since_poll += delta
	if _since_poll >= hearth_poll_seconds:
		_poll_hearth()
	_draught = draught_step(_draught, _lit, delta, kindle_seconds, ember_seconds)
	_apply()
	_report()


## Sits on the flue. Every frame rather than once, because the Farmhouse settles
## itself onto the snow in its own `_ready()` -- which Godot runs AFTER this
## node's, children first -- so a placement made once at startup would be the
## height the building had before it sat down.
func _place() -> void:
	var flue := _resolve_flue()
	if flue == null:
		position = placeholder_offset
		return
	# `global_position` fails an engine assertion outside the tree and answers
	# with the ORIGIN rather than erroring loudly -- Stove._origin_of() carries
	# the same guard for the same reason. Out of a tree the local position is the
	# only honest answer, and marker and smoke share a parent by construction.
	if is_inside_tree() and flue.is_inside_tree():
		global_position = flue.global_position
	else:
		position = flue.position


## See `flue_path` for the three steps and why there are three.
func _resolve_flue() -> Node3D:
	if not flue_path.is_empty():
		var authored := get_node_or_null(flue_path) as Node3D
		if authored != null:
			_flue_source = &"path"
			return authored
	var host := get_parent()
	if host != null:
		for name in flue_marker_names:
			var found := _descendant_named(host, String(name))
			if found != null:
				_flue_source = &"marker"
				return found
		var loose := _descendant_containing(host, "flue")
		if loose != null:
			_flue_source = &"marker"
			return loose
	_flue_source = &"placeholder"
	return null


static func _descendant_named(root: Node, wanted: String) -> Node3D:
	for child in root.get_children():
		if child.name == wanted and child is Node3D:
			return child
		var deeper := _descendant_named(child, wanted)
		if deeper != null:
			return deeper
	return null


static func _descendant_containing(root: Node, fragment: String) -> Node3D:
	for child in root.get_children():
		if child is Node3D and String(child.name).to_lower().contains(fragment):
			return child
		var deeper := _descendant_containing(child, fragment)
		if deeper != null:
			return deeper
	return null


# --- building it -------------------------------------------------------------

func _build() -> void:
	var bible = load(PALETTE_PATH)

	# WORLD SPACE IS THE WHOLE EFFECT. A puff must stay exactly where the air
	# left it, or the column rides the building and the wind history the shader
	# spends its whole length building is thrown away every time anything moves.
	local_coords = false
	one_shot = false
	explosiveness = 0.0
	randomness = 0.0
	amount = maxi(puffs, 1)
	lifetime = maxf(puff_life_seconds, 0.1)
	draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	# A few hundred soft quads in the sun's shadow map, for something that is
	# semi-transparent and would cast nothing legible: the same bill the snowfall
	# and the spindrift both refused.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The column climbs about ten metres and at a gale drifts most of thirty
	# downwind before it has thinned away. Culling it early would blink the whole
	# plume out whenever the flue itself left the frame, which at this camera is
	# most of the time the player is outdoors.
	visibility_aabb = AABB(Vector3(-32.0, -4.0, -32.0), Vector3(64.0, 32.0, 64.0))

	_material = ShaderMaterial.new()
	_material.shader = load(PROCESS_SHADER_PATH)
	process_material = _material

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _puff_material(bible)
	draw_pass_1 = quad


## Cool, pale, unshaded and well short of solid.
##
## `vertex_color_use_as_albedo` is what lets the shader own the alpha while this
## owns the colour: the particle writes (1, 1, 1, a) into COLOR and the multiply
## against this albedo leaves the palette tone untouched. The same identity trick
## trap 7 uses on ALBEDO, for the same reason -- a colour that goes through two
## multiplies arrives squared.
func _puff_material(bible) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = smoke_colour(bible, smoke_tone_index, smoke_whiteness)
	# A bare quad is a rectangle, and a rectangle of flat grey is a paper card
	# taped over the chimney. The bell is not a refinement.
	surface.albedo_texture = _puff_texture()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# MIX, never ADD: two puffs overlapping must not be brighter than either, or
	# the middle of the column blooms exactly where it is densest.
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	surface.billboard_keep_scale = true
	surface.disable_receive_shadows = true
	surface.vertex_color_use_as_albedo = true
	return surface


## The colour, as a pure function of the palette, so a test can assert it is cool
## and under the bloom threshold without standing a node up.
static func smoke_colour(bible, tone_index: int, whiteness: float) -> Color:
	if bible == null or bible.snow_tones.is_empty():
		return Color(1.0, 1.0, 1.0)
	var tone: Color = bible.snow_tones[clampi(tone_index, 0, bible.snow_tones.size() - 1)]
	return Color(
		lerpf(tone.r, 1.0, whiteness),
		lerpf(tone.g, 1.0, whiteness),
		lerpf(tone.b, 1.0, whiteness),
		1.0
	)


## A smooth bell rather than a disc with a soft rim, and the difference is what
## makes two overlapping puffs read as one mass with a waist instead of as two
## circles with a bright lens between them. A disc has a shoulder in it; a bell
## has none anywhere, so the composited alpha rises smoothly through the join.
## Same argument as breath_fog.gd, and it matters more here because a smoke
## column is nothing BUT overlapping puffs.
func _puff_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.26, 0.50, 0.70, 0.86, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.90),
		Color(1.0, 1.0, 1.0, 0.66),
		Color(1.0, 1.0, 1.0, 0.36),
		Color(1.0, 1.0, 1.0, 0.11),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


## Everything, onto the shader. Nothing here re-allocates, so all of it is safe
## to write while the column is in the air.
func _apply() -> void:
	if _material == null:
		return
	amount_ratio = clampf(_draught, 0.0, 1.0)
	# Stopped outright at nothing rather than merely emptied -- an emitter at
	# amount_ratio 0 still runs, and for most of a run there is no fire here.
	emitting = _draught > 0.001

	_material.set_shader_parameter("wind", _wind)
	_material.set_shader_parameter("wind_strength", _strength)
	# Density carries the fade; this carries only the last of it. Compressed to a
	# floor rather than run to zero because it dims puffs ALREADY IN THE AIR --
	# which is right for a column thinning away as its fire dies, and would be
	# wrong as the main channel, since a puff's opacity is a fact about the air
	# it was made of rather than about the fire's current state.
	_material.set_shader_parameter("draught", lerpf(0.45, 1.0, clampf(_draught, 0.0, 1.0)))

	_material.set_shader_parameter("mouth_radius", mouth_radius)
	_material.set_shader_parameter("exit_speed", exit_speed)
	_material.set_shader_parameter("buoyancy", buoyancy)
	_material.set_shader_parameter("buoyancy_decay", buoyancy_decay)
	_material.set_shader_parameter("coupling_seconds", coupling_seconds)
	_material.set_shader_parameter("curl_strength", curl_strength)
	_material.set_shader_parameter("curl_growth", curl_growth)
	_material.set_shader_parameter("curl_wind_gain", curl_wind_gain)
	_material.set_shader_parameter("curl_scale", curl_scale)
	_material.set_shader_parameter("rise_damping_seconds", rise_damping_seconds)
	_material.set_shader_parameter("size_birth", size_birth)
	_material.set_shader_parameter("size_death", size_death)
	_material.set_shader_parameter("size_bias", size_bias)
	_material.set_shader_parameter("peak_alpha", peak_alpha)
	_material.set_shader_parameter("alpha_in", alpha_in)
	_material.set_shader_parameter("alpha_hold", alpha_hold)
	_material.set_shader_parameter("wind_thinning", wind_thinning)


## THE ONE LINE FOR LATER. Wave 5's threats approach the farmstead and a column
## visible across the valley should draw them; publishing the crossings now makes
## that a subscription rather than a rewrite.
##
## Crossings with hysteresis rather than levels, for the reason WindSystem gives:
## a value hovering on a threshold publishes a storm of events, and for a
## subscriber a chattering onset is worse than no onset at all.
func _report() -> void:
	if _bus == null:
		return
	if not _raised and _draught >= 0.35:
		_raised = true
		_bus.emit_event(EVENT_COLUMN_RAISED, _payload())
	elif _raised and _draught <= 0.12:
		_raised = false
		_bus.emit_event(EVENT_COLUMN_FADED, _payload())


func _payload() -> Dictionary:
	return {
		"position": column_position(),
		"strength": _draught,
		"source": self,
	}
