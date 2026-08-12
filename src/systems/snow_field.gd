class_name SnowField
extends Node

## The ground, as a world-anchored raster window that follows whoever is being
## tracked. 512x512 texels over 120 m, so one texel is 23 cm.
##
## Two stored layers:
##
##   terrain -- normalised ground height, from FastNoiseLite. Broad dunes.
##   packed  -- how much of the snow has been trodden flat. 0 fresh, 1 flat.
##
## and everything else is derived from them:
##
##   ground  = drift_relief(terrain - 0.5) * terrain_amplitude_m
##   depth   = max_depth_m * scour(terrain) * (1 - packed)
##   surface = ground + depth
##
## `scour` is the part that makes the terrain mean something. Snow does not lie
## evenly: the wind strips the crests and dumps it in the hollows. So depth is a
## *function of* the ground rather than a second independent noise -- a hollow
## holds a metre of it, a crest holds almost none. That is what makes the relief
## you can see and the speed you can feel the same fact, and it is why one
## texture is enough for both.
##
## assets/shaders/snow_ground.gdshader reproduces those three lines exactly, so
## a drift you can see is a drift you walk in. There is no second source of
## truth to drift out of sync.
##
## The window origin is always snapped to a whole texel, which is what keeps
## the field world-anchored across a recentre: the noise offset moves by the
## same integer number of texels, and the packed layer is blitted by that same
## integer. Nothing resamples, so nothing smears.
##
## No toroidal wrap yet -- a recentre regenerates the base outright. That is
## about 15 ms of C++ noise every time the target strays 8 m from the middle,
## which is a visible-in-a-profiler cost and an invisible-on-screen one. It is
## deliberately the naive version; the wrap can come once there is something to
## measure it against.

const RESOLUTION := 512
const EXTENT_M := 120.0
const CELL_M := EXTENT_M / float(RESOLUTION)

## How far the target may stray from the middle before the window is rebuilt.
## The window reaches 60 m in every direction, so at full slack the shortest
## covered direction is still 52 m -- further than the camera can see.
const RECENTER_SLACK_M := 8.0

const FOOTPRINT_EVENT := &"player.footprint"

## A building announcing the ground it stands on. Published by whatever knows
## where a building's rooms are -- in practice src/entities/interior/
## interior_reveal.gd, which already holds those bounds because the roof needs
## them. Nothing here names that script and it names nothing here.
const BUILDING_FOOTPRINT_EVENT := &"building.footprint"

## Peak-to-trough relief of the bare ground, in metres -- reached only at the
## noise's extremes. See drift_flatten: most of the field gets a fraction of it.
##
## This and noise_frequency are a pair, and the pair is set by the *camera*, not
## by the terrain. The orthographic frame shows about 16 m by 14 m of ground, so
## a 60 m dune fills the whole shot with a single uniform tilt and the ground
## reads as flat -- which is exactly what the first orthographic capture showed.
## Relief is only visible when a crest and a hollow are in frame together.
##
## Slope, which is what the light actually draws, is roughly PI * amplitude /
## wavelength -- but only out where the drift profile below has opened the gain
## up. 2.4 m over a 28 m wavelength is 15 degrees at the drifts and, at the 0.34
## gain the rest of the field runs at, 5 degrees everywhere else. The sun is 21.5
## degrees up and the cel band turns at 14 (terrain_renderer.gd), so the drifts
## shade and the field does not, which is the whole arrangement.
@export var terrain_amplitude_m := 2.4

## ---------------------------------------------------------------------------
## THE DRIFT PROFILE -- why the relief is not proportional to the noise
## ---------------------------------------------------------------------------
## A straight `(terrain - 0.5) * amplitude` gives every part of the field the
## same slope statistics, and that cannot serve both framings at once. Tuned for
## the 16 m gameplay frame it needs metres of swing, and the 70 m establishing
## shot then contains three whole swells whose away-facing flanks all cross the
## cel band: measured, 21% of the frame shaded itself. `Refs/game ref/level.jpg`
## shades none of it -- the painting's field is flat but for the occasional
## drift, and every dark shape on it is something's cast shadow.
##
## So the relief is a *curve* on the noise rather than a multiple of it:
##
##     relief(s) = s * (drift_flatten + (1 - drift_flatten) * |2s|^drift_sharpness)
##
## where s is the noise about its mean, in [-0.5, 0.5]. Near the mean -- which is
## most of the field -- the gain is drift_flatten and the ground undulates
## gently. Out at the tails, where the noise rarely goes, the gain climbs to 1
## and the full amplitude arrives as a bank of drifted snow with a real edge on
## it. One field, two behaviours, and the transition is smooth: the derivative at
## s = 0 is exactly drift_flatten, so there is no crease down the middle of the
## world.
##
## **This is not a flattening.** Nothing about the depth mechanic goes through
## here: depth is a function of the *normalised* height, which is untouched, so
## the wade-through-a-hollow gradient and the footprint depths still run their
## full range. What changes is only how much of that height the eye is shown.
## Measured over the 70 m frame: 79% of it lit before, 97.1% after, with the
## surface still running -0.60 to +1.20 m between its 5th and 95th percentiles
## and 2.4 m corner to corner out in the tails.
##
## The alternative considered and rejected was varying the amplitude by distance
## from the farmstead. It makes the ground a function of where the buildings are,
## which stops being true the moment the player walks out of the yard -- and the
## establishing shot is centred on the farmstead, so the calm part would sit
## exactly where the composition is and the roll would still fill the frame's
## edges.
@export var drift_flatten := 0.34

## How abruptly the gentle field turns into a drift. 1 is no curve at all; the
## higher it goes the rarer and the steeper the drifts become.
@export var drift_sharpness := 3.0

## Snow deep enough to wade through. max_depth_m is what a hollow holds;
## deep_depth_m is where the player is reduced to a trudge.
##
## max_depth_m is much smaller than it was, and deep_depth_m came down with it
## so the mechanic still swings its full range. It has to be small: see the
## note on scour_hollow.
@export var max_depth_m := 0.6
@export var deep_depth_m := 0.42

## The wind's work, in normalised terrain height. At or below scour_hollow the
## snow is at full depth; at or above scour_crest the ground is swept bare.
##
## THE TRAP HERE: snow that fills hollows and spares crests is *anti-correlated*
## with the ground, so it flattens the very relief it is draped over. Across the
## ramp the drawn surface changes by
##
##     terrain_amplitude_m  -  max_depth_m / (scour_crest - scour_hollow)
##
## and if that reaches zero the dunes vanish; if it goes negative the hollows
## bulge upward.
##
## This has been wrong twice and both times the symptom was "the ground looks
## flat", never anything that pointed at the scour. At 3.4 m and 1.05 m over a
## 0.36-wide ramp it was +0.48; at 2.4 m and 0.6 m over a 0.32-wide ramp it was
## +0.53, about a fifth of the bare relief -- a 4.7 degree surface under a sun
## that needs 15 to cast a band. Widening the ramp is the cheap fix: it costs
## nothing in depth range (the snow still runs 0 to max) and it divides the
## cancelling term.
##
## The drift profile moved this sum again and it is worth writing down where it
## landed. The ramp spans the *middle* of the noise, which is exactly where the
## profile's gain is lowest, so the cancellation now eats a larger share of a
## smaller number: across the ramp the ground rises about 0.5 m and the snow
## thins by 0.6, and the drawn surface is very nearly level there. **That is the
## intended result and not a return of the old defect** -- the relief has moved
## out to the tails, where the ramp is already saturated and nothing cancels
## anything. Do not read a flat middle here as the terrain having vanished; read
## the 5th-to-95th percentile range in drift_flatten above, which is measured on
## the drawn surface.
@export var scour_hollow := 0.20
@export var scour_crest := 0.80

## Pushes the noise away from its mid-grey mean so the field reaches real crests
## and real hollows instead of hovering near the average. It scales the slopes
## by the same factor, so it is a lighting control as much as a terrain one.
## Raised alongside the wider scour ramp: the ramp now spans 0.20 to 0.80 of
## normalised height, and the noise has to actually reach those ends or the
## snow never gets deep and the crests never get bare.
@export var terrain_contrast := 1.8

@export var noise_seed := 20260811

## Cycles per metre. 0.036 is a swell about 28 m across.
##
## It was 0.05, chosen when the relief was proportional to the noise and the
## constraint was that a crest and a hollow had to be inside the 16 m gameplay
## frame together or the ground read flat. The drift profile above changes what
## that constraint asks for: the gameplay frame's relief now comes from the
## gentle part rather than from a crest, and what the *establishing* frame
## needs is for drifts to be occasional. One drift per 28 m swell puts four or
## five in a 70 m frame; at 0.05 there were a dozen and they read as dunes.
##
## The thing to keep watching is that the depth mechanic still swings. It does:
## measured over the 16 m gameplay box the snow still runs the full 0.00 to
## 0.60 m, because the scour ramp reads normalised height and a 28 m swell
## crosses it just as completely as a 20 m one -- it simply takes a few more
## paces to walk from the crest to the hollow.
@export var noise_frequency := 0.036

## ---------------------------------------------------------------------------
## BUILDINGS DISPLACE SNOW
## ---------------------------------------------------------------------------
## The field covered the whole valley and did not know buildings existed, so the
## farmhouse's floorboards sat under as much as 0.59 m of it -- and because the
## player is grounded on this same field and nothing else (player_controller.gd:
## no gravity, no floor collider), he stood on that rather than on the boards.
## Raising the house would only have hidden him.
##
## A house is a thing that keeps snow out. So a building carves its footprint
## out of the field, and the player's grounding comes right for free.
##
## WHAT THE MEASUREMENT CHANGED ABOUT THIS. Sampled over the main room before
## any of it existed:
##
##     surface 0.280..1.200   bare ground 0.273..1.200   max depth 0.007
##
## The snow in that room is SEVEN MILLIMETRES DEEP. What buries the floor is the
## bare ground -- the house stands on the flank of a crest the wind has already
## scoured clean -- so removing snow would have changed nothing whatsoever in
## the one room that needed it. A building therefore does two things: it LEVELS
## the ground it stands on, to its own floor, and it keeps the snow off it. Both
## are needed and neither is sufficient.
##
## BOTH ARE WRITTEN INTO THE TWO RASTERS THIS FIELD ALREADY HAS. There is no
## third texture and no shader edit, because assets/shaders/snow_ground.gdshader
## reads exactly `terrain` and `packed` and rebuilds `ground + depth` from them
## line for line. Write the field correctly and the picture follows.
##
## The one thing that cost a design round: `depth` is not free to choose. It is
## `max_depth * scour(terrain) * (1 - packed)`, and `scour` reads the same
## normalised height that sets the ground -- one texture answers both, which is
## this field's whole idea and is exactly what bites here. Levelling the main
## room to its floor puts its normalised height at 0.88, past scour_crest, where
## the model says no snow can lie at all. So the drift through the doorway
## CANNOT be made of depth on this site: it is carried by the terrain layer,
## with `packed` at 1 across the whole interior. The cost is honest and small --
## a player does not wade through the threshold drift and a footprint in it
## reads as thin snow. The alternative was a doorway that works or does not
## depending on where the house happened to settle.

## How far past the outer wall face the carve fades out.
##
## NOT a wall thickness, and this is the number a reviewer should push on. The
## ground mesh is 140 m over 320 subdivisions -- a vertex every 43.75 cm -- so a
## 16 cm falloff is a hard step between two adjacent vertices however smooth the
## curve is on paper, which is precisely the rectangular cliff-edge the brief
## forbids and which the footprint round already paid for once. This is two mesh
## quads, which is the least that can be *drawn* as a slope; the visible result
## is snow banked against the wall rather than sheared off at it.
@export var carve_falloff_m := 1.2

## How far under the floorboards the levelled ground is set.
##
## Small and deliberately not zero. The terrain raster is 8 bit, so the pad
## cannot land on an arbitrary height -- at the farmhouse's height one step is
## 2.6 cm -- and the rounding is DOWNWARD, because a pad a millimetre proud of
## the boards is snow drawn on top of the floor while a pad a centimetre under
## them is hidden by the slab and invisible at any framing this game uses.
@export var carve_clearance_m := 0.005

## The drift that blows in through an open doorway: how deep at the threshold,
## how far it reaches in, and how far past the door jamb it feathers out.
##
## Modest on purpose. It is not decoration -- it is the cheapest possible proof
## that the carve respects openings instead of stamping a rectangle -- but a
## tongue that reached the middle of the room would say the house has no walls
## rather than that it has a door.
@export var doorway_drift_m := 0.12
@export var doorway_reach_m := 1.6
@export var doorway_spread_m := 0.35

var _origin := Vector2.ZERO
## The noise as generated, before any building has been stamped into it. Kept
## because a carve is a LEVEL and not a subtraction: re-stamping has to start
## from the untouched ground or a second pass would dig a second time, and
## forgetting a building has to be able to give its ground back.
var _terrain_base: Image
var _terrain: Image
## What feet have trodden, and what the shader is handed. They are two images
## because the carve raises `_packed` to 1 across a building's interior and a
## boot raises it a little wherever it lands -- one is derived from the other so
## that removing a building removes only its own contribution.
var _packed_walked: Image
var _packed: Image
var _terrain_texture: ImageTexture
var _packed_texture: ImageTexture
var _packed_dirty := false
var _noise: FastNoiseLite
## Building instance id -> {areas, floor_y, doorways}. Keyed by the publisher so
## a building that announces itself twice replaces rather than doubles.
var _carves := {}


func _ready() -> void:
	build_at(Vector3.ZERO)
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null:
		registry.register(&"snow_field", self)
	# Trap 3: an autoload is a node under /root, never an Engine singleton.
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.subscribe(FOOTPRINT_EVENT, _on_footprint)
		bus.subscribe(BUILDING_FOOTPRINT_EVENT, on_building_footprint)


func _exit_tree() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.get_service(&"snow_field") == self:
		registry.unregister(&"snow_field")
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.unsubscribe(FOOTPRINT_EVENT, _on_footprint)
		bus.unsubscribe(BUILDING_FOOTPRINT_EVENT, on_building_footprint)


## Builds the field centred on the origin. Separate from _ready() so a test can
## drive it without a tree.
func build_at(centre: Vector3 = Vector3.ZERO) -> void:
	_build()
	_packed_walked.fill(Color(0.0, 0.0, 0.0, 1.0))
	_packed.fill(Color(0.0, 0.0, 0.0, 1.0))
	_packed_dirty = true
	_origin = _snap(Vector2(centre.x, centre.z) - Vector2(EXTENT_M, EXTENT_M) * 0.5)
	_regenerate_terrain()


func _build() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Two octaves, not four. Fine detail in the height turns into fine detail
	# in the shading, and rule 11 says the snow itself is nearly textureless --
	# the lines are supposed to be the only detail in the frame.
	_noise.fractal_octaves = 2
	# The second octave is at double frequency, so at the default 0.5 gain it
	# contributes as much *slope* as the first and the dunes come out ridged.
	# 0.35 keeps it as surface variation rather than a second landscape.
	_noise.fractal_gain = 0.35
	# get_image() samples on integer texel coordinates, so the frequency the
	# noise object sees is per texel. Multiplying by the cell size lets
	# noise_frequency be stated in the unit that means something -- cycles per
	# metre of world.
	_noise.frequency = noise_frequency * CELL_M
	_packed_walked = Image.create_empty(RESOLUTION, RESOLUTION, false, Image.FORMAT_R8)
	_packed_walked.fill(Color(0.0, 0.0, 0.0, 1.0))
	_packed = Image.create_empty(RESOLUTION, RESOLUTION, false, Image.FORMAT_R8)
	_packed.fill(Color(0.0, 0.0, 0.0, 1.0))
	_packed_texture = ImageTexture.create_from_image(_packed)


func _snap(point: Vector2) -> Vector2:
	return Vector2(floorf(point.x / CELL_M) * CELL_M, floorf(point.y / CELL_M) * CELL_M)


func _regenerate_terrain() -> void:
	# Whole-texel offset: texel (x, y) always sees the same noise input for the
	# same world position, whatever the window is currently showing.
	_noise.offset = Vector3(roundf(_origin.x / CELL_M), roundf(_origin.y / CELL_M), 0.0)
	# normalize = false matters. Normalising rescales each generated block to
	# its own min/max, so the same world position would change height every time
	# the window moved -- the ground would breathe as you walked.
	_terrain_base = _noise.get_image(RESOLUTION, RESOLUTION, false, false, false)
	_apply_carves()


## World XZ -> texel coordinates, fractional. The inverse of everything above.
func cell_of(world_xz: Vector2) -> Vector2:
	return (world_xz - _origin) / CELL_M


func origin() -> Vector2:
	return _origin


func extent() -> float:
	return EXTENT_M


## Bilinear read of a single-channel image, clamped at the border.
##
## Static and imageless-of-context on purpose: this is the one piece of the
## field that is pure arithmetic, and it is the piece a test can pin down
## exactly. Everything else here is noise, and noise is judged by eye.
static func sample_bilinear(image: Image, x: float, y: float) -> float:
	var width := image.get_width()
	var height := image.get_height()
	var cx := clampf(x, 0.0, float(width - 1))
	var cy := clampf(y, 0.0, float(height - 1))
	var x0 := int(floorf(cx))
	var y0 := int(floorf(cy))
	var x1 := mini(x0 + 1, width - 1)
	var y1 := mini(y0 + 1, height - 1)
	var fx := cx - float(x0)
	var fy := cy - float(y0)
	var top := lerpf(image.get_pixel(x0, y0).r, image.get_pixel(x1, y0).r, fx)
	var bottom := lerpf(image.get_pixel(x0, y1).r, image.get_pixel(x1, y1).r, fx)
	return lerpf(top, bottom, fy)


## Normalised ground height at a world position: 0 is the deepest hollow the
## noise can reach, 1 the highest crest. Every other height question here is
## answered from this one number.
func terrain_normal_at(world: Vector3) -> float:
	if _terrain == null:
		return 0.5
	var cell := cell_of(Vector2(world.x, world.z))
	var raw := sample_bilinear(_terrain, cell.x, cell.y)
	return clampf((raw - 0.5) * terrain_contrast + 0.5, 0.0, 1.0)


## The drift profile, as a pure function of the noise about its mean. Static and
## contextless on purpose, like sample_bilinear above: it is the one piece of the
## relief a test can pin down exactly, and assets/shaders/snow_ground.gdshader
## holds the same three lines.
static func drift_relief(signed: float, flatten: float, sharpness: float) -> float:
	var crest := pow(absf(signed * 2.0), sharpness)
	return signed * (flatten + (1.0 - flatten) * crest)


## The bare ground under the snow, in metres, signed about zero.
func terrain_height_at(world: Vector3) -> float:
	return drift_relief(terrain_normal_at(world) - 0.5, drift_flatten, drift_sharpness) \
		* terrain_amplitude_m


## How much of max_depth_m the wind has left here. 1 in a hollow, 0 on a crest.
func scour_at(world: Vector3) -> float:
	return 1.0 - smoothstep(scour_hollow, scour_crest, terrain_normal_at(world))


## Snow depth in metres -- the distance from the bare ground up to the surface.
func depth_at(world: Vector3) -> float:
	if _terrain == null:
		return 0.0
	var cell := cell_of(Vector2(world.x, world.z))
	var packed := sample_bilinear(_packed, cell.x, cell.y)
	return max_depth_m * scour_at(world) * (1.0 - packed)


## What you would stand on if the snow held your weight: ground plus snow. This
## is the height the ground mesh is drawn at.
func surface_height_at(world: Vector3) -> float:
	return terrain_height_at(world) + depth_at(world)


## Slope of that surface as (d/dx, d/dz), pointing uphill. Its length is the
## tangent of the steepest angle, so 0 is flat and 1 is 45 degrees.
##
## Sampled at 0.6 m rather than at a texel: anything finer picks up the
## heightfield's own 23 cm grid, and a footprint asking "which way is downhill"
## wants the shape of the drift, not the texture of the sampling.
func surface_gradient_at(world: Vector3, epsilon := 0.6) -> Vector2:
	var dx := surface_height_at(world + Vector3(epsilon, 0.0, 0.0)) \
		- surface_height_at(world - Vector3(epsilon, 0.0, 0.0))
	var dz := surface_height_at(world + Vector3(0.0, 0.0, epsilon)) \
		- surface_height_at(world - Vector3(0.0, 0.0, epsilon))
	return Vector2(dx, dz) / (2.0 * epsilon)


## 0 where the snow is bare enough to run on, 1 where it is deep enough to
## wade. The player controller reads this rather than the raw depth so the
## thresholds live in one place.
func wade_factor(world: Vector3) -> float:
	if deep_depth_m <= 0.0:
		return 0.0
	return clampf(depth_at(world) / deep_depth_m, 0.0, 1.0)


## Tread the snow down. `amount` is how much of what is left gets compacted at
## the centre, falling off to nothing at `radius_m`.
##
## THIS IS THE SPATIAL HALF OF A PAIR, and the other half is in the player.
## Packing gives speed back on snow the walker has already beaten flat;
## PlayerController's momentum gives it back to a walker who has kept going. Same
## idea -- persistence is rewarded -- once in ground and once in time.
##
## They cannot double up, and it is worth saying why here rather than only there,
## because the obvious worry is that a man at full rhythm on his own packed trail
## ends up faster than flat shallow snow. The relief the momentum grants is a
## fraction OF the terrain penalty; packing is what REMOVES that penalty. By the
## time the trail is beaten flat there is nothing left for the rhythm to hand
## back, so the two shrink into each other rather than adding. See
## PlayerController.terrain_factor(), and
## test_a_beaten_trail_and_a_found_rhythm_do_not_stack_past_the_ceiling.
func pack_at(world: Vector3, radius_m: float, amount: float) -> void:
	if _packed == null:
		return
	var cell := cell_of(Vector2(world.x, world.z))
	var radius := maxf(radius_m / CELL_M, 1.0)
	var min_x := maxi(int(floorf(cell.x - radius)), 0)
	var max_x := mini(int(ceilf(cell.x + radius)), RESOLUTION - 1)
	var min_y := maxi(int(floorf(cell.y - radius)), 0)
	var max_y := mini(int(ceilf(cell.y + radius)), RESOLUTION - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var distance := Vector2(float(x) - cell.x, float(y) - cell.y).length() / radius
			if distance > 1.0:
				continue
			var falloff := 1.0 - distance * distance
			var current := _packed_walked.get_pixel(x, y).r
			var trodden := minf(current + amount * falloff, 1.0)
			_packed_walked.set_pixel(x, y, Color(trodden, 0.0, 0.0, 1.0))
			# The composite only ever rises -- treading rises, a carve rises --
			# so a max here is the same answer a full rebuild would give, for
			# the cost of one texel. A hundred footprints a frame do not get to
			# re-stamp every building in the valley.
			_packed.set_pixel(
				x, y, Color(maxf(trodden, _packed.get_pixel(x, y).r), 0.0, 0.0, 1.0)
			)
			_packed_dirty = true


func packed_at(world: Vector3) -> float:
	if _packed == null:
		return 0.0
	var cell := cell_of(Vector2(world.x, world.z))
	return sample_bilinear(_packed, cell.x, cell.y)


## Moves the window if `world` has strayed past the slack. Returns true when it
## actually moved, so a caller can avoid re-uploading uniforms for nothing.
func follow(world: Vector3) -> bool:
	if _terrain == null:
		return false
	var centre := _origin + Vector2(EXTENT_M, EXTENT_M) * 0.5
	var here := Vector2(world.x, world.z)
	if here.distance_to(centre) <= RECENTER_SLACK_M:
		return false
	var target := _snap(here - Vector2(EXTENT_M, EXTENT_M) * 0.5)
	var shift_x := int(roundf((target.x - _origin.x) / CELL_M))
	var shift_y := int(roundf((target.y - _origin.y) / CELL_M))
	if shift_x == 0 and shift_y == 0:
		return false
	_origin = target
	# Shifted BEFORE the terrain is regenerated, because _regenerate_terrain()
	# ends by re-stamping every carve into both rasters -- and it must stamp
	# them over the shifted tracks, not have them shifted out from under it.
	_shift_packed(shift_x, shift_y)
	_regenerate_terrain()
	return true


## The window moved +shift texels, so whatever sat at texel p now sits at
## p - shift. Blitting rather than resampling is what keeps a footprint on the
## exact patch of world it was made on.
func _shift_packed(shift_x: int, shift_y: int) -> void:
	var previous: Image = _packed_walked.duplicate()
	_packed_walked.fill(Color(0.0, 0.0, 0.0, 1.0))
	var width := RESOLUTION - absi(shift_x)
	var height := RESOLUTION - absi(shift_y)
	if width > 0 and height > 0:
		var source := Rect2i(maxi(shift_x, 0), maxi(shift_y, 0), width, height)
		_packed_walked.blit_rect(previous, source, Vector2i(maxi(-shift_x, 0), maxi(-shift_y, 0)))
	_packed_dirty = true


## Uploads whatever changed this frame. Batched rather than per-stamp so a
## hundred footprints in one frame still cost one upload.
func flush() -> void:
	if _packed_dirty and _packed_texture != null:
		_packed_texture.update(_packed)
		_packed_dirty = false


func terrain_texture() -> ImageTexture:
	return _terrain_texture


func packed_texture() -> ImageTexture:
	return _packed_texture


# ---------------------------------------------------------------------------
# BUILDINGS
# ---------------------------------------------------------------------------

## A building, announced. Untyped because it arrives off the bus and a payload
## the field cannot use must be ignored rather than crash the publisher.
func on_building_footprint(payload) -> void:
	if not (payload is Dictionary):
		return
	carve_building(payload)


## Take a building's footprint into the field. Idempotent per building: a
## republished footprint replaces the one before it, so a building that settles
## and then announces itself again does not stamp twice.
##
## Shape of `footprint`, and every part of it optional except the areas:
##
##   id         int, the publisher, so the entry can be replaced or dropped
##   areas      the rooms, each {centre, axis_x, axis_z, half} in world XZ,
##              reaching to the OUTER face of the wall
##   floor_y    world height of the interior floor. NAN means "not known", and
##              then the snow still goes but the ground is left alone -- see
##              below on why guessing would be worse
##   doorways   each {centre, inward, width} in world XZ
func carve_building(footprint: Dictionary) -> void:
	var areas := _read_areas(footprint.get("areas"))
	if areas.is_empty():
		return
	_carves[int(footprint.get("id", 0))] = {
		"areas": areas,
		"floor_y": float(footprint.get("floor_y", NAN)),
		"doorways": _read_doorways(footprint.get("doorways")),
	}
	_apply_carves()


func forget_building(id: int) -> void:
	if not _carves.has(id):
		return
	_carves.erase(id)
	_apply_carves()


func carved_count() -> int:
	return _carves.size()


func _read_areas(raw) -> Array:
	var areas := []
	if not (raw is Array):
		return areas
	for entry in (raw as Array):
		if not (entry is Dictionary):
			continue
		var area: Dictionary = entry
		if not (area.has("centre") and area.has("axis_x") and area.has("axis_z") and area.has("half")):
			continue
		areas.append(area)
	return areas


func _read_doorways(raw) -> Array:
	var doorways := []
	if not (raw is Array):
		return doorways
	for entry in (raw as Array):
		if not (entry is Dictionary):
			continue
		var door: Dictionary = entry
		if door.has("centre") and door.has("inward") and door.has("width"):
			doorways.append(door)
	return doorways


## Distance from a world point to the edge of one room, in metres: negative
## inside, zero on the wall line, positive outside. Measured in the BUILDING's
## axes rather than the world's, so a farmstead laid out on the diagonal -- which
## every building after the farmhouse is -- carves its own rectangle and not an
## axis-aligned one around it.
##
## Static and contextless on purpose, like sample_bilinear and drift_relief
## above: it is arithmetic with a right answer, and it is the piece a test can
## pin down exactly.
static func area_distance(point: Vector2, area: Dictionary) -> float:
	var centre: Vector2 = area["centre"]
	var axis_x: Vector2 = area["axis_x"]
	var axis_z: Vector2 = area["axis_z"]
	var half: Vector2 = area["half"]
	var offset := point - centre
	var local := Vector2(absf(offset.dot(axis_x)), absf(offset.dot(axis_z))) - half
	return Vector2(maxf(local.x, 0.0), maxf(local.y, 0.0)).length() + minf(maxf(local.x, local.y), 0.0)


## How much of the carve applies at that distance. 1 everywhere inside the wall
## line, falling smoothly to 0 by `falloff` outside it. Smooth at both ends --
## a linear ramp creases at the wall, and a crease in snow reads as a seam in
## the mesh.
static func edge_weight(distance: float, falloff: float) -> float:
	if distance <= 0.0:
		return 1.0
	if falloff <= 0.0 or distance >= falloff:
		return 0.0
	return 1.0 - smoothstep(0.0, falloff, distance)


## How much snow the wind has pushed through an open door, as a profile in 0..1:
## full at the threshold, thinning to nothing `reach` metres in, and no wider
## than the door plus `spread` of feathering at each jamb.
##
## ASYMMETRIC, and that is measured rather than stylistic. The first version
## used the same profile in both directions, and the drift reached as far OUT of
## the door as into it: 11 cm of snow standing over the porch deck and the top
## two steps, which from the game camera read as a smooth pale blob covering the
## way in rather than as snow blowing through a doorway. The porch has its own
## roof over it -- there is nothing for a drift to build against out there -- so
## outside the threshold this falls away in a quarter of the distance, far
## enough to meet the sill and not far enough to bury the steps.
const DOORWAY_OUTWARD_SHARE := 0.25

static func doorway_drift(point: Vector2, doorway: Dictionary, reach: float, spread: float) -> float:
	var centre: Vector2 = doorway["centre"]
	var inward: Vector2 = doorway["inward"]
	var width := float(doorway["width"])
	var offset := point - centre
	var along := offset.dot(inward)
	if along > reach:
		return 0.0
	# Perpendicular to the way the snow is blowing: across the doorway.
	var aside := absf(offset.dot(Vector2(-inward.y, inward.x)))
	var run := reach if along >= 0.0 else reach * DOORWAY_OUTWARD_SHARE
	var fade := 1.0 - smoothstep(0.0, maxf(run, 0.0001), absf(along))
	# It NARROWS as it thins. A constant-width tongue is a slab with rounded
	# shoulders, and at 45 degrees over a 44 cm ground mesh that is what the
	# first version drew: a smooth pillow by the door rather than snow that had
	# come through it. Snow driven through an opening spreads from the gap and
	# runs out, so the drift is a wedge -- full doorway at the sill, a third of
	# it by the time it has died away.
	var span := width * 0.5 * (0.4 + 0.6 * fade)
	return fade * (1.0 - smoothstep(span, span + maxf(spread, 0.0001), aside))


## The normalised terrain height that draws as `height` metres -- the inverse of
## terrain_height_at, by bisection because drift_relief is a quartic and is not
## worth solving in closed form for something that runs once per building.
## Monotonic, so bisection is exact to the bit within 40 steps.
func normal_for_height(height: float) -> float:
	var target := height / maxf(terrain_amplitude_m, 0.0001)
	var low := -0.5
	var high := 0.5
	for _step in range(40):
		var middle := (low + high) * 0.5
		if drift_relief(middle, drift_flatten, drift_sharpness) < target:
			low = middle
		else:
			high = middle
	return clampf((low + high) * 0.5 + 0.5, 0.0, 1.0)


## Height in metres of a raw texel value, and the raw texel value that draws a
## height. The pair has to agree with terrain_normal_at() exactly, which is why
## both go through terrain_contrast the same way it does.
func _height_of_raw(raw: float) -> float:
	var normal := clampf((raw - 0.5) * terrain_contrast + 0.5, 0.0, 1.0)
	return drift_relief(normal - 0.5, drift_flatten, drift_sharpness) * terrain_amplitude_m


func _raw_for_height(height: float) -> float:
	var raw := (normal_for_height(height) - 0.5) / maxf(terrain_contrast, 0.0001) + 0.5
	# Rounded DOWN onto the 8-bit raster rather than to nearest. The error is
	# one step either way; which way it goes decides whether a levelled floor
	# ends up a millimetre over the floorboards, where the snow is drawn on top
	# of them, or a centimetre under, where the slab hides it.
	return clampf(floorf(clampf(raw, 0.0, 1.0) * 255.0) / 255.0, 0.0, 1.0)


## Rebuild both rasters from the untouched ground and the trodden layer, then
## stamp every building back in. Called after anything that regenerates or
## shifts them, which is what keeps a carve world-anchored: the window moves,
## the buildings do not, and the stamp is recomputed from world coordinates
## every time rather than carried along.
func _apply_carves() -> void:
	if _terrain_base == null:
		return
	if _terrain == null:
		_terrain = _terrain_base.duplicate()
	else:
		_terrain.copy_from(_terrain_base)
	if _packed != null and _packed_walked != null:
		_packed.copy_from(_packed_walked)
	for id in _carves:
		_stamp(_carves[id])
	_packed_dirty = true
	if _terrain_texture == null:
		_terrain_texture = ImageTexture.create_from_image(_terrain)
	else:
		_terrain_texture.update(_terrain)


func _stamp(carve: Dictionary) -> void:
	var areas: Array = carve["areas"]
	var doorways: Array = carve["doorways"]
	var floor_y: float = carve["floor_y"]
	# A building whose floor could not be found still keeps the snow out; it
	# just does not get to say where the ground is. Levelling to a height nobody
	# measured would trade a room full of snow for a room of bare terrain, which
	# is the same wrong picture with a different colour.
	var pad := floor_y - carve_clearance_m if is_finite(floor_y) else NAN
	var span := _texel_span(areas)
	for y in range(span.position.y, span.end.y + 1):
		for x in range(span.position.x, span.end.x + 1):
			var here := _origin + Vector2(float(x), float(y)) * CELL_M
			var distance := INF
			for area in areas:
				distance = minf(distance, area_distance(here, area))
			var weight := edge_weight(distance, carve_falloff_m)
			if weight <= 0.0:
				continue
			if weight > _packed.get_pixel(x, y).r:
				_packed.set_pixel(x, y, Color(weight, 0.0, 0.0, 1.0))
			if not is_finite(pad):
				continue
			var lift := 0.0
			for door in doorways:
				lift = maxf(lift, doorway_drift(here, door, doorway_reach_m, doorway_spread_m))
			var natural := _height_of_raw(_terrain_base.get_pixel(x, y).r)
			var wanted := lerpf(natural, pad + lift * doorway_drift_m, weight)
			_terrain.set_pixel(x, y, Color(_raw_for_height(wanted), 0.0, 0.0, 1.0))


## The texels a carve can possibly reach: every room's world bounding box, grown
## by the falloff, clipped to the window. Buildings are small and the window is
## 512 square, so bounding the loop is the difference between 3,000 texels and
## 260,000 of them every time the player walks 8 m.
func _texel_span(areas: Array) -> Rect2i:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for entry in areas:
		var area: Dictionary = entry
		var centre: Vector2 = area["centre"]
		var axis_x: Vector2 = area["axis_x"]
		var axis_z: Vector2 = area["axis_z"]
		var half: Vector2 = area["half"]
		var reach := Vector2(
			absf(axis_x.x) * half.x + absf(axis_z.x) * half.y,
			absf(axis_x.y) * half.x + absf(axis_z.y) * half.y
		) + Vector2.ONE * carve_falloff_m
		low = Vector2(minf(low.x, centre.x - reach.x), minf(low.y, centre.y - reach.y))
		high = Vector2(maxf(high.x, centre.x + reach.x), maxf(high.y, centre.y + reach.y))
	if low.x > high.x:
		return Rect2i()
	var first := cell_of(low)
	var last := cell_of(high)
	var min_x := clampi(int(floorf(first.x)), 0, RESOLUTION - 1)
	var min_y := clampi(int(floorf(first.y)), 0, RESOLUTION - 1)
	var max_x := clampi(int(ceilf(last.x)), 0, RESOLUTION - 1)
	var max_y := clampi(int(ceilf(last.y)), 0, RESOLUTION - 1)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)


func _on_footprint(payload) -> void:
	if not (payload is Dictionary):
		return
	var data: Dictionary = payload
	pack_at(data.get("position", Vector3.ZERO), data.get("pack_radius", 0.35), data.get("pack_amount", 0.45))
