class_name TrackMask
extends Node

## Every line in the snow, in one image.
##
## Art Bible rule 11: the snow itself has almost no texture, and the entire
## sense of detail in the reference comes from lines -- footprint chains, ruts,
## plough furrows. So this is the project's main *art* system as much as a
## gameplay one.
##
## One 1080x1080 image over 90 m (8.3 cm per texel), world-anchored, following
## the target. A print is composited in the moment it is made and then it is
## just texels: a thousand footprints cost exactly what one costs, at draw time
## and at memory. That is the whole reason this is a mask and not a list of
## decals.
##
## The static/dynamic split the Art Bible calls for (baked furrows the wind
## cannot erase, versus footprints it can) is not here yet -- there is no wind
## and nothing baked. When it arrives it is a second image and a second
## uniform, not a rework of this one.

## 2048 rather than the 1080 this started at. A boot print is about 29 cm long
## and 13 cm wide; at 1080 over 90 m a texel is 8.3 cm, so the print was under
## two texels across and could only ever be a blob. At 2048 a texel is 4.4 cm
## and the print is about 7 by 3 -- enough for the shape to survive. The cost is
## 4 MB instead of 1.1 MB, which is nothing, and the draw cost is unchanged
## because it is still exactly one texture fetch.
const RESOLUTION := 2048
const EXTENT_M := 90.0
const CELL_M := EXTENT_M / float(RESOLUTION)

## Smaller than the snow field's, because this window is smaller and its texels
## are finer: a stale edge here shows up as tracks that stop dead.
const RECENTER_SLACK_M := 3.0

const FOOTPRINT_EVENT := &"player.footprint"

## Lobes across the width of one print. Two or three reads as a boot edge
## crumbling; ten reads as static.
const EDGE_NOISE_LOBES := 1.6

var _origin := Vector2.ZERO
var _mask: Image
var _texture: ImageTexture
var _dirty := false
var _edge_noise: FastNoiseLite


func _ready() -> void:
	build_at(Vector3.ZERO)
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null:
		registry.register(&"track_mask", self)
	# Trap 3: an autoload is a node under /root, never an Engine singleton.
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.subscribe(FOOTPRINT_EVENT, _on_footprint)


func _exit_tree() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.get_service(&"track_mask") == self:
		registry.unregister(&"track_mask")
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.unsubscribe(FOOTPRINT_EVENT, _on_footprint)


## Builds the mask centred on `centre`. Separate from _ready() so a test can
## drive it without a tree.
func build_at(centre: Vector3 = Vector3.ZERO) -> void:
	if _mask == null:
		_mask = Image.create_empty(RESOLUTION, RESOLUTION, false, Image.FORMAT_R8)
		_texture = ImageTexture.create_from_image(_mask)
	if _edge_noise == null:
		_edge_noise = FastNoiseLite.new()
		_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_edge_noise.fractal_octaves = 2
		# Sampled in the print's own normalised space, where the rim is at
		# distance 1, so the frequency is in lobes-per-print rather than in
		# anything to do with world scale.
		_edge_noise.frequency = EDGE_NOISE_LOBES
	_mask.fill(Color(0.0, 0.0, 0.0, 1.0))
	_origin = _snap(Vector2(centre.x, centre.z) - Vector2(EXTENT_M, EXTENT_M) * 0.5)
	_dirty = true


func _snap(point: Vector2) -> Vector2:
	return Vector2(floorf(point.x / CELL_M) * CELL_M, floorf(point.y / CELL_M) * CELL_M)


func cell_of(world_xz: Vector2) -> Vector2:
	return (world_xz - _origin) / CELL_M


func origin() -> Vector2:
	return _origin


func extent() -> float:
	return EXTENT_M


## Writes one print. Composited with max() rather than added, so walking the
## same line twenty times leaves a track rather than a white-hot smear.
##
## `radius_m` is the half-length. A boot is longer than it is wide, so pass
## `forward` (the world XZ direction of travel) and an `aspect` above 1 to get
## an oval that points where the walker was going; the half-width is then
## `radius_m / aspect`. Leave `forward` at zero for a circular mark.
##
## `core` is the fraction of the radius that is pressed to full strength before
## the edge starts falling away, and it is the difference between a footprint
## and a smudge. A boot in snow leaves a defined hollow with a fairly sharp rim;
## it does not fade out over a metre. At core = 0.55 the mark keeps its shape
## and the whole transition happens in the outer 45% of the radius -- large
## print, compact edge, rather than a small print with a wide gentle halo.
##
## `irregularity` breaks the outline. A perfect ellipse is what makes a print
## read as *stamped*: real snow crumbles unevenly and no two steps collapse the
## same way. The edge is warped by noise sampled in the print's own space, so
## the raggedness scales with the print rather than with the world.
##
## `edge_seed` shifts that noise. It is a parameter rather than a randf() inside
## because a stamp has to be a pure function of its arguments -- the caller
## varies it per step, and the tests can hold it still. Once written, a print is
## texels and can never shimmer or redraw itself differently.
##
## `fall` and `downhill_scale` put the print into the ground rather than onto
## it. This mask is a plan view -- it is sampled by world XZ -- so a shape that
## is round *on a tilted surface* has to be stored squashed along the fall line
## by cos(slope), and a boot placed on a flank also skews downhill. The caller
## folds both into one number; above 1 the print reaches further downhill than
## across. Leave at 1 for level ground.
func stamp(
	world: Vector3,
	radius_m: float,
	strength: float,
	forward := Vector2.ZERO,
	aspect := 1.0,
	core := 0.55,
	irregularity := 0.0,
	edge_seed := 0.0,
	fall := Vector2.ZERO,
	downhill_scale := 1.0
) -> void:
	if _mask == null:
		return
	var cell := cell_of(Vector2(world.x, world.z))
	var radius := maxf(radius_m / CELL_M, 1.0)
	# The warp pushes the outline outward as often as inward, so the box has to
	# allow for it or the ragged edge is clipped back to a straight line.
	var reach := radius * (1.0 + maxf(irregularity, 0.0))
	var min_x := maxi(int(floorf(cell.x - reach)), 0)
	var max_x := mini(int(ceilf(cell.x + reach)), RESOLUTION - 1)
	var min_y := maxi(int(floorf(cell.y - reach)), 0)
	var max_y := mini(int(ceilf(cell.y + reach)), RESOLUTION - 1)
	var clamped := clampf(strength, 0.0, 1.0)

	var along := Vector2.ZERO
	if forward.length_squared() > 0.0001 and aspect > 1.0:
		along = forward.normalized()

	# The slope transform acts on the *ground*, before the print's own frame, so
	# the two anisotropies keep their separate meanings: one is which way the
	# hill runs, the other is which way the boot points. Both are folded into a
	# single affine squash of the offset, and `along` is carried into the same
	# basis so the ellipse is still measured against the right axis.
	var downhill := Vector2.ZERO
	var sideways := Vector2.ZERO
	if fall.length_squared() > 0.0001 and absf(downhill_scale - 1.0) > 0.001:
		downhill = fall.normalized()
		sideways = Vector2(-downhill.y, downhill.x)
		if along != Vector2.ZERO:
			along = Vector2(along.dot(downhill), along.dot(sideways))
		reach *= maxf(downhill_scale, 1.0)
		min_x = maxi(int(floorf(cell.x - reach)), 0)
		max_x = mini(int(ceilf(cell.x + reach)), RESOLUTION - 1)
		min_y = maxi(int(floorf(cell.y - reach)), 0)
		max_y = mini(int(ceilf(cell.y + reach)), RESOLUTION - 1)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var offset := Vector2(float(x) - cell.x, float(y) - cell.y)
			if downhill != Vector2.ZERO:
				offset = Vector2(offset.dot(downhill) / downhill_scale, offset.dot(sideways))
			var local := Vector2.ZERO
			if along == Vector2.ZERO:
				local = offset / radius
			else:
				# Measured in the print's own frame, so squashing the across
				# axis narrows the oval without rotating the sampling grid.
				var across := Vector2(-along.y, along.x)
				local = Vector2(
					offset.dot(along) / radius,
					offset.dot(across) / (radius / aspect)
				)
			var distance := local.length()
			if irregularity > 0.0:
				# Warping the distance rather than the radius means the outline
				# is displaced in whatever direction the noise happens to run,
				# which is what makes it crumble rather than merely ripple.
				distance += _edge_noise.get_noise_2d(
					local.x + edge_seed, local.y + edge_seed
				) * irregularity
			if distance >= 1.0:
				continue
			# Flat to `core`, then smoothstep out. smoothstep rather than a
			# linear ramp or 1 - d*d because it arrives flat at both ends, so
			# the rim meets the snow without a slope discontinuity -- a
			# discontinuity in the height field is a crease in the normal, and
			# a crease is what shows up as a shard.
			var value := clamped * (1.0 - smoothstep(core, 1.0, distance))
			var current := _mask.get_pixel(x, y).r
			if value > current:
				_mask.set_pixel(x, y, Color(value, 0.0, 0.0, 1.0))
				_dirty = true


## Drags a groove between two prints, so a trail through deep powder reads as
## one channel with foot pockets in it rather than as a row of separate marks.
##
## That is what wading actually leaves: below about knee depth the legs never
## clear the snow between footfalls, they plough through it, and the sides of
## each hole collapse into the next. On a wind-scoured crest none of that
## happens and the prints stay separate and sharp -- so the caller gates this on
## snow depth and simply does not call it up there.
##
## Deliberately weaker and narrower than the prints it joins. Composited with
## max() like everything else here, so wherever a print is deeper the print
## wins and stays legible: this fills the gaps between them, it does not
## replace them with a ditch.
##
## Geometrically it is `stamp()`'s profile measured from a segment instead of
## from a point -- flat to `core`, then smoothstep out, with the same edge noise
## warping the outline. `irregularity` matters more here than on a print,
## because a channel with two straight parallel sides reads as machined.
func drag(
	from: Vector3,
	to: Vector3,
	radius_m: float,
	strength: float,
	core := 0.55,
	irregularity := 0.0,
	edge_seed := 0.0
) -> void:
	if _mask == null or strength <= 0.0:
		return
	var start := cell_of(Vector2(from.x, from.z))
	var finish := cell_of(Vector2(to.x, to.z))
	var radius := maxf(radius_m / CELL_M, 1.0)
	var reach := radius * (1.0 + maxf(irregularity, 0.0))
	var min_x := maxi(int(floorf(minf(start.x, finish.x) - reach)), 0)
	var max_x := mini(int(ceilf(maxf(start.x, finish.x) + reach)), RESOLUTION - 1)
	var min_y := maxi(int(floorf(minf(start.y, finish.y) - reach)), 0)
	var max_y := mini(int(ceilf(maxf(start.y, finish.y) + reach)), RESOLUTION - 1)
	var clamped := clampf(strength, 0.0, 1.0)

	var span := finish - start
	var length := span.length()
	# Two prints in the same place is a stamp, not a drag, and normalising a
	# zero-length span is a division by zero.
	var direction := Vector2.RIGHT
	if length > 0.0001:
		direction = span / length
	var sideways := Vector2(-direction.y, direction.x)
	var length_units := length / radius

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var offset := Vector2(float(x) - start.x, float(y) - start.y)
			# The channel's own frame, in radii: how far along it, and how far
			# off its centre line. Capping `along` at the two ends is what
			# rounds the groove off into the prints instead of cutting it
			# square across them.
			var along := offset.dot(direction) / radius
			var across := offset.dot(sideways) / radius
			var past_end := maxf(maxf(-along, along - length_units), 0.0)
			var distance := sqrt(past_end * past_end + across * across)
			if irregularity > 0.0:
				distance += _edge_noise.get_noise_2d(
					along + edge_seed, across + edge_seed
				) * irregularity
			if distance >= 1.0:
				continue
			var value := clamped * (1.0 - smoothstep(core, 1.0, distance))
			var current := _mask.get_pixel(x, y).r
			if value > current:
				_mask.set_pixel(x, y, Color(value, 0.0, 0.0, 1.0))
				_dirty = true


## Nearest texel, not bilinear. The shader is the only thing that needs a
## smooth read and it gets one from the sampler for free; borrowing SnowField's
## interpolator to do it here would be a direct reference between two systems
## that are supposed to be deletable independently.
func value_at(world: Vector3) -> float:
	if _mask == null:
		return 0.0
	var cell := cell_of(Vector2(world.x, world.z)).round()
	if cell.x < 0.0 or cell.y < 0.0 or cell.x > float(RESOLUTION - 1) or cell.y > float(RESOLUTION - 1):
		return 0.0
	return _mask.get_pixel(int(cell.x), int(cell.y)).r


## Moves the window if `world` has strayed past the slack. Returns true when it
## actually moved.
func follow(world: Vector3) -> bool:
	if _mask == null:
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
	_shift(shift_x, shift_y)
	return true


## The window moved +shift texels, so whatever sat at texel p now sits at
## p - shift. Blitted, never resampled: a resample would blur every print a
## little more on every recentre until the whole trail dissolved.
func _shift(shift_x: int, shift_y: int) -> void:
	var previous: Image = _mask.duplicate()
	_mask.fill(Color(0.0, 0.0, 0.0, 1.0))
	var width := RESOLUTION - absi(shift_x)
	var height := RESOLUTION - absi(shift_y)
	if width > 0 and height > 0:
		var source := Rect2i(maxi(shift_x, 0), maxi(shift_y, 0), width, height)
		_mask.blit_rect(previous, source, Vector2i(maxi(-shift_x, 0), maxi(-shift_y, 0)))
	_dirty = true


## One upload per frame at most, however many prints landed in it.
func flush() -> void:
	if _dirty and _texture != null:
		_texture.update(_mask)
		_dirty = false


func texture() -> ImageTexture:
	return _texture


func _on_footprint(payload) -> void:
	if not (payload is Dictionary):
		return
	var data: Dictionary = payload
	# The groove first, so the print is composited over it -- immaterial with
	# max(), but it is the order the two things happen in.
	if data.has("trench_from"):
		drag(
			data.get("trench_from", Vector3.ZERO),
			data.get("position", Vector3.ZERO),
			data.get("trench_radius", 0.12),
			data.get("trench_strength", 0.0),
			data.get("core", 0.55),
			data.get("trench_irregularity", 0.0),
			data.get("edge_seed", 0.0)
		)
	stamp(
		data.get("position", Vector3.ZERO),
		data.get("radius", 0.28),
		data.get("strength", 0.6),
		data.get("forward", Vector2.ZERO),
		data.get("aspect", 1.0),
		data.get("core", 0.55),
		data.get("irregularity", 0.0),
		data.get("edge_seed", 0.0),
		data.get("fall", Vector2.ZERO),
		data.get("downhill_scale", 1.0)
	)
