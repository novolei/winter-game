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
## TWO LAYERS, which Art Bible section 3 requires and which is why this file is
## not simply the dynamic mask it started as:
##
##   dynamic -- footprints, and the channel a walker drags behind him in snow too
##              deep to lift his feet clear of, made while the game runs, in a
##              window that follows the player and scrolls. The wind will erase
##              this one.
##   static  -- the ploughed field and old tyre tracks, baked once at startup
##              into a window that is FIXED in the world and never scrolls. The
##              wind must never touch it.
##
## Both layers hold something called a furrow and they are not the same thing:
## the static layer's are the field's, cut by a plough last autumn and part of
## the terrain, while plough() below draws the one the player cuts with his own
## legs as he wades, which fades like every other mark he leaves.
##
## Without the split the first gust flattens the farmland along with the
## footprints, and the only texture the Art Bible allows an otherwise empty
## white field goes with it.
##
## DECAY IS A MECHANIC, NOT A POLISH ITEM, and it is the reason the sentence
## above says "the wind will erase this one" rather than "the wind could".
##
## GDD section 8: the bear and the scavenger read THIS texture, the same one the
## terrain shader reads. So what the snow still remembers is exactly what can
## follow you home:
##
##   风大 -> 足迹速消 -> 你安全; 风停 -> 足迹留存 -> 你被跟上。
##
## The 寒流 event stills the air, and that stillness is what leaves a clear path
## behind you. Silence is both the omen of danger and its cause. None of it is
## true unless prints fade, and unless the weather is what sets the pace.
##
## The decay belongs to THE MASK. Nothing about it knows or cares who made a
## mark, so when the bear starts walking in a later wave its tracks fade like
## everybody else's with nothing to wire up.
##
## HOW A PRINT DIES. Two things happen to it at once, and they are the difference
## between a print that fills in and a print that fades out behind glass:
##
##   fill   snow lands in the hollow, so a fixed amount of DEPTH is removed
##          everywhere per second. Because it is subtraction rather than a scale,
##          a deep boot pocket outlives a shallow scuff for free, and the print's
##          outline -- which is a level set of the depth -- pulls inward as it
##          goes rather than staying put and getting faint.
##   slump  each texel settles toward the average of its four neighbours, so the
##          rim, which has empty snow on one side, is dragged down faster than
##          the core and the flat pressed floor of the print rounds off into a
##          dome. This is what stops the last of a print vanishing all at once
##          when its whole plateau reaches zero on the same tick.
##
## Neither is applied to the static layer. Furrows are terrain.
##
## WHERE IS THE "REMAINING LIFE" CHANNEL? The Wave 0 spec reserves the mask's G
## for it, with R as compacted depth. This image is FORMAT_R8 -- one channel, no
## G to write into -- and the mask's format is read by the snow shader, so it is
## not ours to change. It does not need changing: because the fill is subtractive
## at a rate the weather sets, remaining life IS depth divided by that rate, and
## remaining_life_at() returns it. Same fact, derived instead of stored, and one
## byte per texel instead of two.
##
## COST. A full 2048x2048 pass with the four-neighbour read measures 81 ms on
## this machine, which is not a per-frame budget by any reading. So the sweep is
## split into 128x128 tiles -- 0.4 ms each, measured -- and only tiles that have
## ever been marked are visited, which in play is the handful the walker is
## standing in. A tile is swept only once it has banked a whole byte of depth to
## remove, and the remainder is carried as TIME rather than dropped, so 8-bit
## quantisation cannot quietly stall the decay at a fraction of the authored rate.
##
## The static window does not follow anybody, and that is the point rather than
## a shortcut: furrows are a *place*, not a property of wherever the player
## happens to be standing, so they are baked once in world coordinates and read
## by world coordinates. It also means the bake never has to be repeated -- a
## scrolling static layer would have to re-rasterise every stroke on every
## recentre, which is exactly the per-frame cost this system exists to avoid.
## The price is that the layer covers one fixed square of world; outside it the
## shader reads zero, which is correct, because outside it nothing was ploughed.

## 2048 rather than the 1080 this started at. A boot print is about 29 cm long
## and 13 cm wide; at 1080 over 90 m a texel is 8.3 cm, so the print was under
## two texels across and could only ever be a blob. At 2048 a texel is 4.4 cm
## and the print is about 7 by 3 -- enough for the shape to survive. The cost is
## 4 MB instead of 1.1 MB, which is nothing, and the draw cost is unchanged
## because it is still exactly one texture fetch.
const RESOLUTION := 2048
const EXTENT_M := 90.0
const CELL_M := EXTENT_M / float(RESOLUTION)

## The static layer. Wider than the dynamic window because it has to hold a
## whole ploughed field and the road that runs past it, and because it never
## moves -- 120 m is the same span SnowField covers, so a farmstead that fits in
## the terrain window fits in this one. The texel is 5.9 cm against the dynamic
## layer's 4.4: a furrow is 20 cm wide where a boot print is 13, so the coarser
## grid still resolves the thing this layer draws.
const STATIC_RESOLUTION := 2048
const STATIC_EXTENT_M := 120.0
const STATIC_CELL_M := STATIC_EXTENT_M / float(STATIC_RESOLUTION)

## Smaller than the snow field's, because this window is smaller and its texels
## are finer: a stale edge here shows up as tracks that stop dead.
const RECENTER_SLACK_M := 3.0

const FOOTPRINT_EVENT := &"player.footprint"
const FURROW_EVENT := &"player.furrow"

## Lobes across the width of one print. Two or three reads as a boot edge
## crumbling; ten reads as static.
const EDGE_NOISE_LOBES := 1.6

## The decay sweep's unit of work. 128 texels is 5.6 m of world and 0.4 ms of
## GDScript, measured; the whole mask in one go is 81 ms, which is why this
## number exists at all.
const DECAY_TILE := 128
const DECAY_TILES_ACROSS := RESOLUTION / DECAY_TILE

## Full depth, in 8-bit texels. The fill rate is authored in seconds-to-gone and
## converted through this.
const DEPTH_STEPS := 255.0

## How long the FILL alone would take to remove a print at full depth, with the
## air dead still and nothing falling out of the sky.
##
## The fill alone, and that distinction is worth the line: slumping also takes
## depth off a deep print, so the life you actually get is shorter than the
## number here and by an amount that depends on how deep the print was. Measured
## on this build, in still air:
##
##   full depth (1.0)   80 s      shallow scuff (0.3)   36 s
##
## A shallow print matches the arithmetic exactly, because there is barely any
## depth for the slump to move about; a deep one goes about a third sooner. Both
## are the intended behaviour rather than an error in the constant -- see the
## class comment on why the print has to fill in and not merely fade.
##
## 80 s is the tuning that matters. A man walks the 90 m of this window in about
## 67 s, so the oldest print in a full window is just about to go: what you can
## see of your own trail is what can still be followed.
##
## This is the 寒流 case and the dangerous one.
@export var decay_still_seconds := 120.0

## ...and the same, for a full gale working on the print alone. Both terms are
## always in play, so a gale really clears a full print in about 18 s: 风大 ->
## 足迹速消 -> 你安全.
@export var decay_gale_seconds := 26.0

## ...and under heavy snowfall alone. Snow fills a hollow from above where wind
## scours it from the side, so they are separate hooks with separate rates, and a
## still night of heavy snow erases a trail just as surely as a windy clear one.
@export var decay_snowfall_seconds := 34.0

## How fast a print settles toward its surroundings, as a fraction of the way to
## the local average per second. This is the "fills in" half of the decay -- see
## the class comment. Wind moves loose snow about, so it slumps harder in a gale.
@export var decay_slump_still := 0.22
@export var decay_slump_gale := 0.60

## Tiles swept per decay() call. Four is 1.6 ms in the worst case, and only when
## four tiles happen to be due on the same frame; a walker inks two or three at a
## time and the usual frame sweeps one or none. Raising it makes the decay's
## timing finer, never faster: the pace is set by the rates above, and a tile
## that waits its turn banks the time it waited.
@export var decay_tiles_per_step := 4

var _origin := Vector2.ZERO
var _mask: Image
var _texture: ImageTexture
var _dirty := false
var _edge_noise: FastNoiseLite

var _static_origin := Vector2.ZERO
var _static: Image
var _static_texture: ImageTexture
var _static_dirty := false

## 0 dead still .. 1 full gale, and 0 clear .. 1 heavy. Both are HOOKS: see
## set_wind_strength() and set_snowfall_rate().
var _wind_strength := 0.0
var _snowfall_rate := 0.0

## One entry per tile. `_tile_inked` is 1 where a mark has been written and not
## yet swept away, so an empty mask -- which is most of it, most of the time --
## costs nothing. `_tile_elapsed` is the weather that tile has yet to be shown.
var _tile_inked := PackedByteArray()
var _tile_elapsed := PackedFloat32Array()
var _decay_cursor := 0


func _ready() -> void:
	build_at(Vector3.ZERO)
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null:
		registry.register(&"track_mask", self)
	# Trap 3: an autoload is a node under /root, never an Engine singleton.
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.subscribe(FOOTPRINT_EVENT, _on_footprint)
		bus.subscribe(FURROW_EVENT, _on_furrow)


func _exit_tree() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.get_service(&"track_mask") == self:
		registry.unregister(&"track_mask")
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.unsubscribe(FOOTPRINT_EVENT, _on_footprint)
		bus.unsubscribe(FURROW_EVENT, _on_furrow)


## Builds both layers centred on `centre`. Separate from _ready() so a test can
## drive it without a tree.
func build_at(centre: Vector3 = Vector3.ZERO) -> void:
	if _mask == null:
		_mask = Image.create_empty(RESOLUTION, RESOLUTION, false, Image.FORMAT_R8)
		_texture = ImageTexture.create_from_image(_mask)
	if _static == null:
		_static = Image.create_empty(STATIC_RESOLUTION, STATIC_RESOLUTION, false, Image.FORMAT_R8)
		_static_texture = ImageTexture.create_from_image(_static)
	if _edge_noise == null:
		_edge_noise = FastNoiseLite.new()
		_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_edge_noise.fractal_octaves = 2
		# Sampled in the print's own normalised space, where the rim is at
		# distance 1, so the frequency is in lobes-per-print rather than in
		# anything to do with world scale.
		_edge_noise.frequency = EDGE_NOISE_LOBES
	var tiles := DECAY_TILES_ACROSS * DECAY_TILES_ACROSS
	if _tile_inked.size() != tiles:
		_tile_inked.resize(tiles)
		_tile_elapsed.resize(tiles)
	_tile_inked.fill(0)
	_tile_elapsed.fill(0.0)
	_decay_cursor = 0
	_mask.fill(Color(0.0, 0.0, 0.0, 1.0))
	_origin = _snap(Vector2(centre.x, centre.z) - Vector2(EXTENT_M, EXTENT_M) * 0.5, CELL_M)
	_dirty = true
	bake_at(centre)


## Re-centres and clears the static layer, without touching the footprints.
## Called once, by whoever owns the composition, before it bakes its strokes in
## -- the window is fixed from then on.
func bake_at(centre: Vector3 = Vector3.ZERO) -> void:
	if _static == null:
		return
	_static.fill(Color(0.0, 0.0, 0.0, 1.0))
	_static_origin = _snap(
		Vector2(centre.x, centre.z) - Vector2(STATIC_EXTENT_M, STATIC_EXTENT_M) * 0.5, STATIC_CELL_M
	)
	_static_dirty = true


func _snap(point: Vector2, cell: float) -> Vector2:
	return Vector2(floorf(point.x / cell) * cell, floorf(point.y / cell) * cell)


func cell_of(world_xz: Vector2) -> Vector2:
	return (world_xz - _origin) / CELL_M


func static_cell_of(world_xz: Vector2) -> Vector2:
	return (world_xz - _static_origin) / STATIC_CELL_M


func origin() -> Vector2:
	return _origin


func extent() -> float:
	return EXTENT_M


func static_origin() -> Vector2:
	return _static_origin


func static_extent() -> float:
	return STATIC_EXTENT_M


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
	_written(_blob(
		_mask, RESOLUTION, CELL_M, cell_of(Vector2(world.x, world.z)),
		radius_m, strength, forward, aspect, core, irregularity, edge_seed, fall, downhill_scale
	))


## Both rasterisers report the box of texels they actually wrote, rather than
## merely whether they wrote any. The dynamic layer needs the box: a tile that
## has never been marked is a tile the decay sweep can skip forever, and that is
## the whole reason a 2048-square mask can be decayed at all inside a frame.
func _written(box: Rect2i) -> void:
	if box.size.x <= 0:
		return
	_dirty = true
	_ink(box)


## Flags every tile the box overlaps. Freshly inked tiles start their clock now;
## a tile that was already inked keeps the time it has banked, because a print
## landing next to an older one must not reset the older one's age.
func _ink(box: Rect2i) -> void:
	var first_x := clampi(box.position.x / DECAY_TILE, 0, DECAY_TILES_ACROSS - 1)
	var first_y := clampi(box.position.y / DECAY_TILE, 0, DECAY_TILES_ACROSS - 1)
	var last_x := clampi((box.position.x + box.size.x - 1) / DECAY_TILE, 0, DECAY_TILES_ACROSS - 1)
	var last_y := clampi((box.position.y + box.size.y - 1) / DECAY_TILE, 0, DECAY_TILES_ACROSS - 1)
	for tile_y in range(first_y, last_y + 1):
		for tile_x in range(first_x, last_x + 1):
			var index := tile_y * DECAY_TILES_ACROSS + tile_x
			if _tile_inked[index] == 0:
				_tile_inked[index] = 1
				_tile_elapsed[index] = 0.0


func _blob(
	image: Image,
	resolution: int,
	cell_m: float,
	cell: Vector2,
	radius_m: float,
	strength: float,
	forward: Vector2,
	aspect: float,
	core: float,
	irregularity: float,
	edge_seed: float,
	fall: Vector2,
	downhill_scale: float
) -> Rect2i:
	var touched := Rect2i()
	var radius := maxf(radius_m / cell_m, 1.0)
	# The warp pushes the outline outward as often as inward, so the box has to
	# allow for it or the ragged edge is clipped back to a straight line.
	var reach := radius * (1.0 + maxf(irregularity, 0.0))
	var min_x := maxi(int(floorf(cell.x - reach)), 0)
	var max_x := mini(int(ceilf(cell.x + reach)), resolution - 1)
	var min_y := maxi(int(floorf(cell.y - reach)), 0)
	var max_y := mini(int(ceilf(cell.y + reach)), resolution - 1)
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
		max_x = mini(int(ceilf(cell.x + reach)), resolution - 1)
		min_y = maxi(int(floorf(cell.y - reach)), 0)
		max_y = mini(int(ceilf(cell.y + reach)), resolution - 1)

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
			var current := image.get_pixel(x, y).r
			if value > current:
				image.set_pixel(x, y, Color(value, 0.0, 0.0, 1.0))
				touched = _grown(touched, x, y)
	return touched


## The box of written texels, one texel at a time. An empty Rect2i means nothing
## has been written yet -- distinguishable from a one-texel box, which is why
## this is not simply a min/max pair of ints.
func _grown(box: Rect2i, x: int, y: int) -> Rect2i:
	if box.size.x <= 0:
		return Rect2i(x, y, 1, 1)
	return box.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))


## ---------------------------------------------------------------------------
## The ploughed furrow
## ---------------------------------------------------------------------------
## Ploughs one short length of the channel a wading walker drags behind him.
##
## THE PHYSICS, which the two rejected passes at this were both missing. In snow
## past wading depth you cannot lift your feet clear of it: you drag them, and a
## dragged boot does not stamp, it ploughs, the way a plough turns a furrow. What
## it leaves is not a shallow version of a footprint. It is a groove with an
## INVERTED-TRIANGLE cross-section -- 倒三角 -- deepest along the centre line and
## rising in a straight taper to the surface at both edges.
##
## So the profile here is LINEAR in the distance off the centre line, and that is
## the one line of this method that must not be changed back:
##
##     value = depth * (1 - distance / half_width)
##
## not the flat core and smoothstep shoulder `stamp()` and `_groove()` use. The
## difference is the whole read. A smoothstep sits at full depth across the
## middle half of its width, which is a channel with a floor -- a ribbon laid on
## the snow. A straight taper gives two flat facets meeting at a line, and under
## a sun eleven degrees up two flat facets at opposite tilts take DIFFERENT
## palette tones out of the cel bands. The groove is drawn by the shading, not by
## the tint, which is the only way it can read at gameplay framing at all.
##
## `half_width_m` is the half-width, and `depth` the value on the centre line.
## Composited with max() like everything else here, so wherever a boot pocket is
## deeper the print wins outright and keeps its outline and its rim -- the legs
## plough the channel down the middle and the boots punch pockets either side
## of it.
##
## SHORT SEGMENTS, and this is the other half of the fix. The caller emits one of
## these per physics tick from the walker's real position, so each is a few
## centimetres long against a half-width of about seventeen. Where the segment is
## shorter than the groove is wide, the union of the whole run IS the exact swept
## region of the path -- max() of the capsules is the distance field to the
## polyline -- so the groove curves because the walk curves and there is no joint
## anywhere to see. A segment per FOOTFALL is twelve times longer than the groove
## is wide, which is a polyline by construction with a visible elbow at every
## change of direction; that is what the second pass shipped and what was
## rejected. No strength reduction fixes a corner.
##
## No edge noise. A stamp is a pure function of its arguments (see `edge_seed` on
## stamp() for why), and the variation this shape needs runs along its LENGTH
## rather than around its outline -- so the caller wobbles `depth` and
## `half_width_m` down the run, from a noise indexed by distance walked. Warping
## the outline per segment instead would decorrelate neighbouring segments and
## put the joints back.
func plough(from: Vector3, to: Vector3, half_width_m: float, depth: float) -> void:
	if _mask == null or depth <= 0.0 or half_width_m <= 0.0:
		return
	_written(_furrow(
		_mask, RESOLUTION, CELL_M,
		cell_of(Vector2(from.x, from.z)), cell_of(Vector2(to.x, to.z)),
		half_width_m, depth
	))


func _furrow(
	image: Image,
	resolution: int,
	cell_m: float,
	start: Vector2,
	finish: Vector2,
	half_width_m: float,
	depth: float
) -> Rect2i:
	var touched := Rect2i()
	var radius := maxf(half_width_m / cell_m, 1.0)
	var min_x := maxi(int(floorf(minf(start.x, finish.x) - radius)), 0)
	var max_x := mini(int(ceilf(maxf(start.x, finish.x) + radius)), resolution - 1)
	var min_y := maxi(int(floorf(minf(start.y, finish.y) - radius)), 0)
	var max_y := mini(int(ceilf(maxf(start.y, finish.y) + radius)), resolution - 1)
	var clamped := clampf(depth, 0.0, 1.0)

	var span := finish - start
	var length := span.length()
	# A walker who has not moved ploughs nothing, and normalising a zero-length
	# span is a division by zero.
	var direction := Vector2.RIGHT
	if length > 0.0001:
		direction = span / length
	var sideways := Vector2(-direction.y, direction.x)
	var length_units := length / radius

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var offset := Vector2(float(x) - start.x, float(y) - start.y)
			# The channel's own frame, in half-widths: how far along it, and how
			# far off its centre line. Capping `along` at the two ends is what
			# rounds the segment off into its neighbours instead of cutting it
			# square across them.
			var along := offset.dot(direction) / radius
			var across := offset.dot(sideways) / radius
			var past_end := maxf(maxf(-along, along - length_units), 0.0)
			var distance := sqrt(past_end * past_end + across * across)
			if distance >= 1.0:
				continue
			# The inverted triangle. See the block above plough().
			var value := clamped * (1.0 - distance)
			var current := image.get_pixel(x, y).r
			if value > current:
				image.set_pixel(x, y, Color(value, 0.0, 0.0, 1.0))
				touched = _grown(touched, x, y)
	return touched


func _groove(
	image: Image,
	resolution: int,
	cell_m: float,
	start: Vector2,
	finish: Vector2,
	radius_m: float,
	strength: float,
	core: float,
	irregularity: float,
	edge_seed: float
) -> Rect2i:
	var touched := Rect2i()
	var radius := maxf(radius_m / cell_m, 1.0)
	var reach := radius * (1.0 + maxf(irregularity, 0.0))
	var min_x := maxi(int(floorf(minf(start.x, finish.x) - reach)), 0)
	var max_x := mini(int(ceilf(maxf(start.x, finish.x) + reach)), resolution - 1)
	var min_y := maxi(int(floorf(minf(start.y, finish.y) - reach)), 0)
	var max_y := mini(int(ceilf(maxf(start.y, finish.y) + reach)), resolution - 1)
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
			var current := image.get_pixel(x, y).r
			if value > current:
				image.set_pixel(x, y, Color(value, 0.0, 0.0, 1.0))
				touched = _grown(touched, x, y)
	return touched


## ---------------------------------------------------------------------------
## The static layer
## ---------------------------------------------------------------------------
## Everything below writes into the baked image instead of the scrolling one.
## Same two rasterisers, a different target -- which is the point: a furrow and
## a footprint are the same kind of mark in the snow and must read as one
## surface, not as two systems that happen to overlap.


## One straight rut. `bake_path` is what a caller normally wants; this is the
## primitive underneath it, exposed because a single stroke is a legitimate
## thing to bake and because it is what the tests can pin down exactly.
func bake_stroke(
	from: Vector3,
	to: Vector3,
	radius_m: float,
	strength: float,
	core := 0.55,
	irregularity := 0.0,
	edge_seed := 0.0
) -> void:
	if _static == null or strength <= 0.0:
		return
	# No _written() here, and that is the point rather than an omission: the ink
	# flags drive the decay sweep, and this layer is never swept. A furrow is a
	# place, not a thing that happened.
	if _groove(
		_static, STATIC_RESOLUTION, STATIC_CELL_M,
		static_cell_of(Vector2(from.x, from.z)), static_cell_of(Vector2(to.x, to.z)),
		radius_m, strength, core, irregularity, edge_seed
	).size.x > 0:
		_static_dirty = true


## A run of strokes through a list of world points. A road that bends is a
## polyline, not an arc: the mask has no curve primitive and does not need one,
## because at 5.9 cm per texel a bend sampled every few metres has no visible
## corners in it.
func bake_path(
	points: Array,
	radius_m: float,
	strength: float,
	core := 0.55,
	irregularity := 0.0,
	edge_seed := 0.0
) -> void:
	for index in range(points.size() - 1):
		bake_stroke(
			points[index], points[index + 1], radius_m, strength, core, irregularity,
			# Shifted per segment, or every segment of a road crumbles in exactly
			# the same places and the repeat is visible along its whole length.
			edge_seed + float(index) * 3.7
		)


## A band of parallel furrows -- the ploughed field of Art Bible section 3.
##
## `origin` is the near corner, `direction` the way the plough ran, `length` how
## far it ran, `spacing` the gap between furrows and `count` how many. Stated
## that way rather than as a rectangle because a field is defined by the
## direction it was worked in: rotate the rectangle and the furrows rotate with
## it, which is the one thing that must never come apart.
func bake_furrows(
	origin: Vector3,
	direction: Vector2,
	length_m: float,
	spacing_m: float,
	count: int,
	radius_m: float,
	strength: float,
	irregularity := 0.0
) -> void:
	if direction.length_squared() < 0.0001:
		return
	var along := direction.normalized()
	var across := Vector2(-along.y, along.x)
	for index in range(count):
		var offset := across * (spacing_m * float(index))
		var start := origin + Vector3(offset.x, 0.0, offset.y)
		var finish := start + Vector3(along.x, 0.0, along.y) * length_m
		# A ploughed field is not a print of a comb: the passes are not all the
		# same length and they do not all bite equally. Two cheap per-furrow
		# variations are enough to stop the band reading as a hatching pattern,
		# and both are deterministic functions of the index so a rebuild is
		# identical.
		var wobble := sin(float(index) * 2.399) * 0.5 + 0.5
		bake_stroke(
			start + Vector3(along.x, 0.0, along.y) * (wobble * spacing_m * 2.0),
			finish - Vector3(along.x, 0.0, along.y) * ((1.0 - wobble) * spacing_m * 3.0),
			radius_m,
			strength * (0.72 + 0.28 * wobble),
			0.35,
			irregularity,
			float(index) * 11.3
		)


## Nearest texel on the baked layer, matching value_at()'s contract.
func static_value_at(world: Vector3) -> float:
	if _static == null:
		return 0.0
	var cell := static_cell_of(Vector2(world.x, world.z)).round()
	if (
		cell.x < 0.0 or cell.y < 0.0
		or cell.x > float(STATIC_RESOLUTION - 1) or cell.y > float(STATIC_RESOLUTION - 1)
	):
		return 0.0
	return _static.get_pixel(int(cell.x), int(cell.y)).r


## What the shader draws: the deeper of the two layers. max(), not add, for the
## same reason every composite here is max() -- a footprint that lands in a
## furrow is one mark in the snow, not a hole twice as deep.
func combined_value_at(world: Vector3) -> float:
	return maxf(value_at(world), static_value_at(world))


func static_texture() -> ImageTexture:
	return _static_texture


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
	var target := _snap(here - Vector2(EXTENT_M, EXTENT_M) * 0.5, CELL_M)
	var shift_x := int(roundf((target.x - _origin.x) / CELL_M))
	var shift_y := int(roundf((target.y - _origin.y) / CELL_M))
	if shift_x == 0 and shift_y == 0:
		return false
	_origin = target
	_shift(shift_x, shift_y)
	return true


## ---------------------------------------------------------------------------
## Decay
## ---------------------------------------------------------------------------
## See the class comment for what this is for and why it is a mechanic. Below is
## only how it is done.


## THE WIND HOOK. 0 dead still .. 1 full gale.
##
## src/systems/wind_system.gd is Wave 3 and does not exist. This is left here
## rather than left out so that whoever writes it has one obvious place to
## connect, instead of inventing a second wind inside this file -- and the decay
## does NOT wait for it: at the default of zero, prints still fill in at
## decay_still_seconds. Still air is a weather condition, not an absence of one,
## and in this game it is the dangerous one.
func set_wind_strength(strength: float) -> void:
	_wind_strength = clampf(strength, 0.0, 1.0)


## THE SNOWFALL HOOK. 0 clear .. 1 heavy. src/systems/weather_system.gd is
## Wave 3. Same contract as the wind hook above.
func set_snowfall_rate(rate: float) -> void:
	_snowfall_rate = clampf(rate, 0.0, 1.0)


func wind_strength() -> float:
	return _wind_strength


func snowfall_rate() -> float:
	return _snowfall_rate


## Depth removed from every mark, per second, at the weather currently set. The
## three terms are independent because the three causes are: snow settles into a
## hollow on its own, wind drives it in from the side, and falling snow fills it
## from above. Summing inverse lifetimes is what makes them compose -- two
## half-speed causes erase a print at the speed one full-speed cause would.
func fill_rate() -> float:
	var rate := 0.0
	if decay_still_seconds > 0.0:
		rate += 1.0 / decay_still_seconds
	if decay_gale_seconds > 0.0:
		rate += _wind_strength / decay_gale_seconds
	if decay_snowfall_seconds > 0.0:
		rate += _snowfall_rate / decay_snowfall_seconds
	return rate


## How hard a mark settles toward its surroundings, per second. Wind is what
## moves loose snow about, so a gale both fills prints faster AND blurs what is
## left of them -- a wind-worked trail goes soft before it goes.
func slump_rate() -> float:
	return lerpf(decay_slump_still, decay_slump_gale, _wind_strength)


## Seconds until a mark this deep is gone, at the weather currently set. This is
## the Wave 0 spec's "remaining life", derived rather than stored -- see the
## class comment on why there is no G channel to keep it in.
##
## An UPPER BOUND, and honestly so: it counts the fill and not the slumping, so a
## deep print goes about a third sooner than this says while a shallow one goes
## exactly when it says. What it is exactly right about is the ordering -- deeper
## is always fresher, and every print's number falls as the weather works on it,
## which is what a tracking animal is actually asking.
func remaining_life(depth: float) -> float:
	var rate := fill_rate()
	if rate <= 0.0:
		return 0.0
	return maxf(depth, 0.0) / rate


## What a tracking animal would ask the ground: how fresh is this, and how long
## have I got. Zero where there is nothing to follow.
func remaining_life_at(world: Vector3) -> float:
	return remaining_life(value_at(world))


## One frame of weather over the footprints. Returns true when the snow actually
## changed, so flush() has something to upload.
##
## Driven from the tree rather than by whoever made the print, which is the whole
## design: the bear does not have to remember to age its own tracks.
func _process(delta: float) -> void:
	decay(delta)


## Advances every mark on the dynamic layer toward being filled in. The static
## layer is not touched.
##
## Bounded work: `delta` is banked against every inked tile, and at most
## decay_tiles_per_step of the tiles that have banked a whole byte of depth are
## swept. A tile that waits its turn is shown all the time it waited, so the pace
## is set by fill_rate() and never by how busy the frame was.
func decay(delta: float) -> bool:
	if _mask == null or delta <= 0.0:
		return false
	var rate := fill_rate()
	if rate <= 0.0:
		return false

	var tiles := _tile_inked.size()
	for index in range(tiles):
		if _tile_inked[index] != 0:
			_tile_elapsed[index] += delta

	# The time it takes to owe one whole 8-bit step of depth. Sweeping sooner
	# would round the debt away and stall the decay; sweeping later is merely
	# coarser, and the banked time makes it exact either way.
	var due := 1.0 / (rate * DEPTH_STEPS)
	var budget := maxi(decay_tiles_per_step, 1)
	var examined := 0
	var changed := false
	while budget > 0 and examined < tiles:
		var index := _decay_cursor
		_decay_cursor = (_decay_cursor + 1) % maxi(tiles, 1)
		examined += 1
		if _tile_inked[index] == 0 or _tile_elapsed[index] < due:
			continue
		budget -= 1
		if _sweep(index, rate):
			changed = true
	if changed:
		_dirty = true
	return changed


## One tile, swept. Returns true when a texel changed.
func _sweep(index: int, rate: float) -> bool:
	var tile_x := (index % DECAY_TILES_ACROSS) * DECAY_TILE
	var tile_y := (index / DECAY_TILES_ACROSS) * DECAY_TILE

	# Whole steps of depth to take off, with the remainder carried as TIME. Drop
	# the remainder instead and a print decays at whatever fraction of the
	# authored rate the rounding happens to leave -- which looks like a tuning
	# problem and is not one.
	var owed := rate * DEPTH_STEPS * _tile_elapsed[index]
	var fill := int(owed)
	if fill < 1:
		return false
	var elapsed := _tile_elapsed[index]
	_tile_elapsed[index] = (owed - float(fill)) / (rate * DEPTH_STEPS)

	# Clamped at 0.45: an explicit four-neighbour diffusion above 0.5 oscillates,
	# and an oscillating height field is a shimmer in the terrain normal.
	var slump := clampf(slump_rate() * elapsed, 0.0, 0.45)

	# Read one texel wider than the tile on every side, so the texels on a tile
	# boundary see their real neighbours. Without the margin the sweep leaves a
	# 128-texel grid printed faintly into the snow, which is exactly the kind of
	# defect that reads as a shader bug.
	var from_x := maxi(tile_x - 1, 0)
	var from_y := maxi(tile_y - 1, 0)
	var to_x := mini(tile_x + DECAY_TILE + 1, RESOLUTION)
	var to_y := mini(tile_y + DECAY_TILE + 1, RESOLUTION)
	var width := to_x - from_x
	var height := to_y - from_y
	var patch: Image = _mask.get_region(Rect2i(from_x, from_y, width, height))
	var source: PackedByteArray = patch.get_data()
	var target: PackedByteArray = source.duplicate()

	var inner_x := tile_x - from_x
	var inner_y := tile_y - from_y
	var inner_w := mini(tile_x + DECAY_TILE, RESOLUTION) - tile_x
	var inner_h := mini(tile_y + DECAY_TILE, RESOLUTION) - tile_y
	var touched := false
	var remaining := false

	for y in range(inner_y, inner_y + inner_h):
		var row := y * width
		# At the very edge of the mask a texel is its own neighbour, which is the
		# no-flux boundary: snow does not drain off the side of the window.
		var above := row - width if y > 0 else row
		var below := row + width if y < height - 1 else row
		for x in range(inner_x, inner_x + inner_w):
			var value: int = source[row + x]
			if value == 0:
				continue
			var left: int = source[row + x - 1] if x > 0 else value
			var right: int = source[row + x + 1] if x < width - 1 else value
			var average := float(left + right + source[above + x] + source[below + x]) * 0.25
			# Settle toward the neighbourhood, then take the fill off. A texel
			# that is already empty is never revisited above, so a print can
			# slump inward and soften but can never creep outward: the mark on
			# the ground only ever gets smaller.
			var settled := float(value) + slump * (average - float(value)) - float(fill)
			# ROUNDED, not truncated, and this is not a detail. `fill` is already a
			# whole number of steps, so the fraction here is entirely the slump
			# term -- and truncating a fraction of a step downward on every sweep
			# charges a whole step for it, which measured as a print decaying at
			# just over twice its authored rate. Rounding costs a dead zone for
			# gradients under half a step per texel, which no print has: across a
			# print's shoulder the profile falls by tens of steps per texel.
			var next := clampi(roundi(settled), 0, 255)
			if next != value:
				target[row + x] = next
				touched = true
			if next > 0:
				remaining = true

	if touched:
		patch.set_data(width, height, false, Image.FORMAT_R8, target)
		# Only the inner tile is written back: the margin was read for its
		# neighbours and belongs to somebody else's sweep.
		_mask.blit_rect(
			patch, Rect2i(inner_x, inner_y, inner_w, inner_h), Vector2i(tile_x, tile_y)
		)
	if not remaining:
		_tile_inked[index] = 0
		_tile_elapsed[index] = 0.0
	return touched


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
	_shift_ink(shift_x, shift_y)
	_dirty = true


## The ink flags, carried through the same move the texels just made.
##
## Whatever sat at texel p now sits at p - shift, so one tile's contents land
## across up to four destination tiles, and each inked tile flags the ones its
## own span moved into. Banked time comes with it -- the largest of whatever
## arrives, so no mark can have its decay clock quietly restarted by a recentre.
##
## Flagging ALL of them instead is correct and is what this did first. It is also
## a real cost: follow() recentres every 3 m, which at a run is twice a second,
## and each recentre would put 256 empty tiles into the sweep queue -- work that
## finds nothing, and a queue that real prints then have to wait behind.
func _shift_ink(shift_x: int, shift_y: int) -> void:
	var moved := PackedByteArray()
	moved.resize(_tile_inked.size())
	var banked := PackedFloat32Array()
	banked.resize(_tile_elapsed.size())
	for source in range(_tile_inked.size()):
		if _tile_inked[source] == 0:
			continue
		var from_x := (source % DECAY_TILES_ACROSS) * DECAY_TILE - shift_x
		var from_y := (source / DECAY_TILES_ACROSS) * DECAY_TILE - shift_y
		var last_x := from_x + DECAY_TILE - 1
		var last_y := from_y + DECAY_TILE - 1
		# Scrolled clean off the window: those marks are gone, not relocated.
		if last_x < 0 or last_y < 0 or from_x >= RESOLUTION or from_y >= RESOLUTION:
			continue
		for tile_y in range(maxi(from_y, 0) / DECAY_TILE, mini(last_y, RESOLUTION - 1) / DECAY_TILE + 1):
			for tile_x in range(maxi(from_x, 0) / DECAY_TILE, mini(last_x, RESOLUTION - 1) / DECAY_TILE + 1):
				var index := tile_y * DECAY_TILES_ACROSS + tile_x
				moved[index] = 1
				banked[index] = maxf(banked[index], _tile_elapsed[source])
	_tile_inked = moved
	_tile_elapsed = banked


## One upload per frame at most, however many prints landed in it. The static
## layer goes up the same way, which in practice means exactly once -- it is
## dirty on the frame it was baked and never again.
func flush() -> void:
	if _dirty and _texture != null:
		_texture.update(_mask)
		_dirty = false
	if _static_dirty and _static_texture != null:
		_static_texture.update(_static)
		_static_dirty = false


func texture() -> ImageTexture:
	return _texture


func _on_footprint(payload) -> void:
	if not (payload is Dictionary):
		return
	var data: Dictionary = payload
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


## One tick of the walker's drag. Both ends are required rather than defaulted:
## a payload carrying only `from` used to plough a groove from the world origin
## to wherever the walker was, which is a line ruled across snow nobody walked on
## and is the kind of defect that only shows up in a screenshot of somewhere else
## entirely.
func _on_furrow(payload) -> void:
	if not (payload is Dictionary):
		return
	var data: Dictionary = payload
	if not (data.has("from") and data.has("to")):
		return
	plough(
		data.get("from", Vector3.ZERO),
		data.get("to", Vector3.ZERO),
		data.get("half_width", 0.0),
		data.get("depth", 0.0)
	)
