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
##   ground  = (terrain - 0.5) * terrain_amplitude_m
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

## Peak-to-trough relief of the bare ground, in metres.
##
## This and noise_frequency are a pair, and the pair is set by the *camera*, not
## by the terrain. The orthographic frame shows about 16 m by 14 m of ground, so
## a 60 m dune fills the whole shot with a single uniform tilt and the ground
## reads as flat -- which is exactly what the first orthographic capture showed.
## Relief is only visible when a crest and a hollow are in frame together.
##
## Slope, which is what the light actually draws, is roughly PI * amplitude /
## wavelength: 2.4 m over 22 m is about 19 degrees at the steepest. With the sun
## 11 degrees up that puts the away-facing side of every swell firmly in the
## shadow band, and the surface becomes legible.
@export var terrain_amplitude_m := 3.2

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
## cancelling term. At 3.2 m over a 0.60-wide ramp the surface keeps 2.2 of the
## 3.2, which is a 17 degree face -- comfortably inside the cel band.
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

## Cycles per metre. 0.05 is a swell about 20 m across. Two constraints meet
## here: much longer and a crest and a hollow are never in the 16 m frame
## together so the ground reads flat, much shorter and the slopes get too steep
## for the amplitude the relief needs. Measured over a 38 m walk at 0.038 the
## route never reached a scoured crest at all.
@export var noise_frequency := 0.05

var _origin := Vector2.ZERO
var _terrain: Image
var _packed: Image
var _terrain_texture: ImageTexture
var _packed_texture: ImageTexture
var _packed_dirty := false
var _noise: FastNoiseLite


func _ready() -> void:
	build_at(Vector3.ZERO)
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null:
		registry.register(&"snow_field", self)
	# Trap 3: an autoload is a node under /root, never an Engine singleton.
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.subscribe(FOOTPRINT_EVENT, _on_footprint)


func _exit_tree() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.get_service(&"snow_field") == self:
		registry.unregister(&"snow_field")
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.unsubscribe(FOOTPRINT_EVENT, _on_footprint)


## Builds the field centred on the origin. Separate from _ready() so a test can
## drive it without a tree.
func build_at(centre: Vector3 = Vector3.ZERO) -> void:
	_build()
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
	_terrain = _noise.get_image(RESOLUTION, RESOLUTION, false, false, false)
	if _terrain_texture == null:
		_terrain_texture = ImageTexture.create_from_image(_terrain)
	else:
		_terrain_texture.update(_terrain)


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


## The bare ground under the snow, in metres, signed about zero.
func terrain_height_at(world: Vector3) -> float:
	return (terrain_normal_at(world) - 0.5) * terrain_amplitude_m


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
			var current := _packed.get_pixel(x, y).r
			_packed.set_pixel(x, y, Color(minf(current + amount * falloff, 1.0), 0.0, 0.0, 1.0))
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
	_regenerate_terrain()
	_shift_packed(shift_x, shift_y)
	return true


## The window moved +shift texels, so whatever sat at texel p now sits at
## p - shift. Blitting rather than resampling is what keeps a footprint on the
## exact patch of world it was made on.
func _shift_packed(shift_x: int, shift_y: int) -> void:
	var previous: Image = _packed.duplicate()
	_packed.fill(Color(0.0, 0.0, 0.0, 1.0))
	var width := RESOLUTION - absi(shift_x)
	var height := RESOLUTION - absi(shift_y)
	if width > 0 and height > 0:
		var source := Rect2i(maxi(shift_x, 0), maxi(shift_y, 0), width, height)
		_packed.blit_rect(previous, source, Vector2i(maxi(-shift_x, 0), maxi(-shift_y, 0)))
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


func _on_footprint(payload) -> void:
	if not (payload is Dictionary):
		return
	var data: Dictionary = payload
	pack_at(data.get("position", Vector3.ZERO), data.get("pack_radius", 0.35), data.get("pack_amount", 0.45))
