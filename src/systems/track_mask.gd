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

## The CPU keeps one canonical 2048-square image because stamping, decay and
## threat reads all need a continuous world-space field.  The GPU transport is
## split into sixteen layers instead: one changed footprint uploads one 512
## square neighbourhood, not the four-megabyte world window.
##
## Each layer carries a one-texel gutter.  The shader selects one layer and lets
## hardware bilinear filtering read through that gutter, so the optimisation
## costs one texture fetch and remains bit-for-bit continuous at layer borders.
## A gutterless array either clamps at every 22.5 m boundary or needs four
## texture fetches per sample; both are worse contracts for a low-end GPU.
const UPLOAD_CHUNK := 512
const UPLOAD_GUTTER := 1
const UPLOAD_LAYER_SIZE := UPLOAD_CHUNK + UPLOAD_GUTTER * 2
const UPLOAD_CHUNKS_ACROSS := RESOLUTION / UPLOAD_CHUNK
const UPLOAD_LAYER_COUNT := UPLOAD_CHUNKS_ACROSS * UPLOAD_CHUNKS_ACROSS
const UPLOAD_BYTES_PER_LAYER := UPLOAD_LAYER_SIZE * UPLOAD_LAYER_SIZE

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

## Every creature writes the same surface. The subject says whose trail it is;
## consumers that only care about the snow deliberately ignore it, while a
## future perception system can follow a particular trail without inventing a
## second event and a second mask.
const FOOTPRINT_EVENT := &"track.footprint"
const FURROW_EVENT := &"player.furrow"
const TRACK_PROFILE_DIRECTORY := "res://data/tracks"

## ---------------------------------------------------------------------------
## What a print in snow actually looks like
## ---------------------------------------------------------------------------
## Judged against a photograph of real prints, and the gap it named was not
## subtlety of amount, it was the wrong SHAPE in three separate ways:
##
##   1. a print is first and foremost a dark hole. The shadow carries the depth;
##      the outline barely matters. Ours read as a pale oval with a dark crescent
##      down one side.
##   2. the outline is TORN at a coarse scale -- lobes, tears, bites out of the
##      shape -- not a fine wobble on a smooth oval. "An oval with noise applied"
##      against "a hole that fell in on itself".
##   3. in thin snow the foot SCRAPES rather than punches, so the mark there is a
##      broken scuffed patch and not a small version of the hole.
##
## HOW THE SHADOW IS ACTUALLY DRAWN, because it decides every number below. The
## mask is never seen. What is seen is the normal snow_ground.gdshader rebuilds
## from it by central difference at 6 cm, run through a two-band cel: with the
## sun 21.5 degrees up and the band at 0.12, a patch of snow goes dark once its
## own surface tilts more than about 15 degrees away from the sun, and it is
## fully dark past 19. Nothing else in this file can make a print dark. So the
## question a profile has to answer is not "how deep" but "over how much of its
## area does it hold 15 degrees of tilt".
##
## Measured with a CPU model of that shader over one print, as a fraction of the
## print's own plan area:
##
##   flat core + smoothstep shoulder (what this was)     19 %
##   ...lowering `core` toward a dome                    14 %   (worse)
##   ...raising `core` toward a punched cylinder         19 %   (no better)
##   ...a pow(1 - t, 1.3) taper instead of the smoothstep 19 %   (no better)
##   ...tearing the outline hard                         19 %   (no better)
##   ...doubling track_depth in the ground shader        29 %   (and it would
##                                                              take the road and
##                                                              the furrow with it)
##
## SO THE FIRST OF THE THREE IS CAPPED, and it is worth being plain about why.
## The shadow only ever falls on the WALL of a print, the wall is at most as wide
## as the shader's own 6 cm epsilon smears it, and the print is 37 cm across --
## so a fifth of it is the ceiling for any shape this file can write. The palette
## caps the other end: the darkest snow tone in color_bible.tres is 74% of the
## lit tone's luminance, and a print at the very bottom of that range is still
## nothing like a photograph's black hole. Measured over a whole print, the mark
## reads at about 90% of untouched snow and this pass moved that by a point.
##
## What the shape CAN do is the other two, and they are what the rest of this
## block is: an outline that is torn instead of rippled, and a mark in thin snow
## that is a scrape instead of a small hole.

## Lobes across one print. COARSE, deliberately: 1.6 -- what this was -- puts
## three wavelengths across a print and reads as a noisy ellipse, which is
## exactly what was rejected. At 1.05 there are about two, so each one is a lobe
## of the boot's own size and a bite out of it is visible as a bite.
const EDGE_NOISE_LOBES := 1.05

## How hard that noise is squared off. Simplex is a wobble and a wall does not
## collapse in a sine: tanh pushes the middle of the range out to the ends, so
## what is left is broad lobes with short steep transitions between them -- torn
## rather than rippled.
##
## tanh() rather than the obvious sign(n) * pow(abs(n), p): the power form has an
## infinite slope at zero, so the outline would move by a whole lobe between two
## adjacent texels wherever the noise crossed it. tanh is smooth everywhere and
## still arrives flat at both ends.
##
## EDGE_TEAR_GAIN is 1 / tanh(EDGE_TEAR * 0.94) -- 0.94 being the peak this
## noise field actually reaches, measured -- so a lobe at the field's own maximum
## warps the outline by the full `irregularity` and no more.
const EDGE_TEAR := 2.2
const EDGE_TEAR_GAIN := 1.033

## The outline collapses INWARD more often than it bulges out, which is both what
## a bite is and what keeps this change from undoing the furrow's. Two prints a
## stride apart are 0.81 m between centres against a 0.28 m half-length: an
## outline free to grow by the full irregularity would close that gap and run the
## chain back into the continuous ribbon it took three passes to escape.
const EDGE_BITE_BIAS := 0.24

## ...and the tear is a thing that happens to the WALLS. Held off the middle of
## the print, where the sole's own mark is, and brought fully in by the shoulder.
const EDGE_TEAR_FROM := 0.15
const EDGE_TEAR_FULL := 0.75

## ...and what DOES go outward goes where the foot pushed. A boot displaces snow
## ahead of the sole and out to the sides, not evenly around a ring, and a ring
## is what reads as procedural. Behind the print the outward reach is scaled by
## this; ahead of it, by 1.
const EDGE_PUSH_BEHIND := 0.4

## THE BROKEN FLOOR, and the one thing here sampled in WORLD space rather than in
## the print's own.
##
## That is not an implementation detail, it is the whole of requirement 5 -- where
## the walker stopped or turned, the prints have to churn together into one broken
## patch with no clean outlines in it. Everything on this layer composites with
## max(), and max() of two prints that each carry their own private floor noise is
## smoother than either: the peaks of one fill the troughs of the other and heavy
## overlap converges on a flat plateau, which is the exact opposite of churn.
## Sampled in world space the two prints share the same field, and
## max(P1*(1-b), P2*(1-b)) is (1-b)*max(P1,P2) -- the break survives any amount of
## overlap exactly.
##
## A hand span, because the shader cannot see anything finer. Its normal is a
## central difference at 6 cm, whose response is sin(ke)/(ke): at a 0.28 m
## wavelength that is 0.72, at 0.15 m it is 0.03, and below 0.12 m it INVERTS.
## Relief finer than a hand span is not subtle in this renderer, it is absent.
const FLOOR_BREAK_M := 0.28
const FLOOR_BREAK_GAIN := 0.85

## THE SCUFF. In snow too thin to punch through, the foot scrapes: the mark is a
## broken scraped patch that is longer than the boot, has no pressed floor under
## it, and carries almost no shadow. It is a different event from a hole and not
## a small one, so these are what `scuff` morphs the shape toward.
##
## `SCUFF_CORE` rather than zero: even a scrape presses a little of the snow flat
## where the sole first touched. Everything else about it is the absence of the
## hole -- no floor, a longer and narrower mark, and relief that is almost
## entirely broken rather than a shape with a rim.
const SCUFF_STRETCH := 0.7
const SCUFF_NARROW := 0.18
const SCUFF_CORE := 0.03
const SCUFF_BREAK := 0.9

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
var _texture: Texture2DArray
var _upload_layers: Array[Image] = []
var _dirty_upload_layers := PackedByteArray()
var _dirty := false
var _last_upload_layer_count := 0
var _last_upload_bytes := 0
var _last_upload_duration_ms := 0.0
var _total_upload_layer_count := 0
var _total_upload_bytes := 0
var _edge_noise: FastNoiseLite
var _floor_noise: FastNoiseLite
## Subject id -> authored shape resource, loaded once from data/tracks.  Unknown
## subjects retain the legacy ellipse instead of silently inheriting a boot.
var _profiles_by_subject: Dictionary = {}
var _compiled_profiles: Dictionary = {}

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
	_load_profiles()
	if _mask == null:
		_mask = Image.create_empty(RESOLUTION, RESOLUTION, false, Image.FORMAT_R8)
		_create_upload_texture()
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
	if _floor_noise == null:
		_floor_noise = FastNoiseLite.new()
		_floor_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		# One octave, unlike the edge noise: a second would land at 15 cm, which
		# is inside the shader's blind spot. See FLOOR_BREAK_M.
		_floor_noise.fractal_octaves = 1
		# ...and in METRES, because unlike the outline this one is a fact about
		# the ground rather than about the boot that stood on it.
		_floor_noise.frequency = 1.0 / FLOOR_BREAK_M
	var tiles := DECAY_TILES_ACROSS * DECAY_TILES_ACROSS
	if _tile_inked.size() != tiles:
		_tile_inked.resize(tiles)
		_tile_elapsed.resize(tiles)
	_tile_inked.fill(0)
	_tile_elapsed.fill(0.0)
	_decay_cursor = 0
	_mask.fill(Color(0.0, 0.0, 0.0, 1.0))
	_origin = _snap(Vector2(centre.x, centre.z) - Vector2(EXTENT_M, EXTENT_M) * 0.5, CELL_M)
	_mark_all_upload_layers()
	bake_at(centre)


func _create_upload_texture() -> void:
	_upload_layers.clear()
	_dirty_upload_layers.resize(UPLOAD_LAYER_COUNT)
	_dirty_upload_layers.fill(0)
	for _layer_index in range(UPLOAD_LAYER_COUNT):
		_upload_layers.append(Image.create_empty(
			UPLOAD_LAYER_SIZE, UPLOAD_LAYER_SIZE, false, Image.FORMAT_R8
		))
	_texture = Texture2DArray.new()
	var error := _texture.create_from_images(_upload_layers)
	assert(error == OK, "TrackMask Texture2DArray creation failed: %s" % error_string(error))


func _load_profiles() -> void:
	if not _profiles_by_subject.is_empty():
		return
	var directory := DirAccess.open(TRACK_PROFILE_DIRECTORY)
	if directory == null:
		return
	for file_name in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var profile := load(TRACK_PROFILE_DIRECTORY.path_join(file_name)) as TrackProfileDefinition
		if profile == null:
			continue
		_compiled_profiles[profile.get_instance_id()] = _compile_profile(profile)
		for subject in profile.subjects:
			if subject != &"":
				_profiles_by_subject[subject] = profile


func profile_for_subject(subject: StringName) -> TrackProfileDefinition:
	_load_profiles()
	return _profiles_by_subject.get(subject, null) as TrackProfileDefinition


func _compile_profile(profile: TrackProfileDefinition) -> PackedFloat32Array:
	return PackedFloat32Array([
		profile.heel_centre_x, profile.heel_half_length, profile.heel_half_width,
		profile.waist_centre_x, profile.waist_half_length, profile.waist_half_width,
		profile.forefoot_centre_x, profile.forefoot_half_length, profile.forefoot_half_width,
		profile.heel_weight, profile.forefoot_weight,
		profile.weight_transition_from_x, profile.weight_transition_to_x,
	])


func _compiled_profile(profile: TrackProfileDefinition) -> PackedFloat32Array:
	var key := profile.get_instance_id()
	if not _compiled_profiles.has(key):
		_compiled_profiles[key] = _compile_profile(profile)
	return _compiled_profiles[key]


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
## `irregularity` is HOW FAR THE WALLS FELL IN, and it drives both halves of
## that: the outline is torn into coarse lobes and bitten into, and the floor
## under it is broken up by what fell onto it. A perfect ellipse is what makes a
## print read as *stamped*; real snow collapses, and no two steps collapse the
## same way. See the shape block at the top of this file for the measurements
## that set the character of it -- the short version is that a fine wobble on a
## smooth oval is not what a print looks like and is not what this now draws.
##
## `edge_seed` shifts that noise. It is a parameter rather than a randf() inside
## because a stamp has to be a pure function of its arguments -- the caller
## varies it per step, and the tests can hold it still. Once written, a print is
## texels and can never shimmer or redraw itself differently.
##
## `scuff` is 0 for a boot punched into a drift and 1 for one SCRAPED across snow
## too thin to punch through. It is a different event, not a smaller one: the
## scrape is longer than the boot that made it, has no pressed floor under it and
## carries almost no shadow, which is why it is a parameter here rather than a
## smaller `radius_m` at the call site. The caller morphs it continuously with the
## snow, so there is no moment at which the mark changes kind.
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
	downhill_scale := 1.0,
	scuff := 0.0
) -> void:
	if _mask == null:
		return
	_written(_blob(
		_mask, RESOLUTION, CELL_M, cell_of(Vector2(world.x, world.z)),
		Vector2(world.x, world.z),
		radius_m, strength, forward, aspect, core, irregularity, edge_seed, fall,
		downhill_scale, scuff, null
	))


## The same pure stamp boundary with one authored silhouette.  Separate from
## `stamp()` so anonymous threats, decay fixtures and baked marks preserve their
## exact legacy semantics until data assigns them a profile.
func stamp_profiled(
	world: Vector3,
	radius_m: float,
	strength: float,
	forward: Vector2,
	aspect: float,
	core: float,
	irregularity: float,
	edge_seed: float,
	fall: Vector2,
	downhill_scale: float,
	scuff: float,
	track_profile: TrackProfileDefinition
) -> void:
	if _mask == null or track_profile == null:
		return
	_written(_blob(
		_mask, RESOLUTION, CELL_M, cell_of(Vector2(world.x, world.z)),
		Vector2(world.x, world.z),
		radius_m, strength, forward, aspect, core, irregularity, edge_seed, fall,
		downhill_scale, scuff, track_profile
	))


## Both rasterisers report the box of texels they actually wrote, rather than
## merely whether they wrote any. The dynamic layer needs the box: a tile that
## has never been marked is a tile the decay sweep can skip forever, and that is
## the whole reason a 2048-square mask can be decayed at all inside a frame.
func _written(box: Rect2i) -> void:
	if box.size.x <= 0:
		return
	_mark_upload_box(box)
	_ink(box)


## Marks the layers whose core OR one-texel gutter observes this rectangle.
## Expanding by the gutter is what keeps a write to texel 511 visible from the
## neighbouring layer that owns texel 512; missing that case draws a hairline
## seam only when a footprint happens to cross a 22.5 m boundary.
func _mark_upload_box(box: Rect2i) -> void:
	if box.size.x <= 0 or box.size.y <= 0:
		return
	var first_x := clampi(box.position.x - UPLOAD_GUTTER, 0, RESOLUTION - 1)
	var first_y := clampi(box.position.y - UPLOAD_GUTTER, 0, RESOLUTION - 1)
	var last_x := clampi(box.end.x - 1 + UPLOAD_GUTTER, 0, RESOLUTION - 1)
	var last_y := clampi(box.end.y - 1 + UPLOAD_GUTTER, 0, RESOLUTION - 1)
	for chunk_y in range(first_y / UPLOAD_CHUNK, last_y / UPLOAD_CHUNK + 1):
		for chunk_x in range(first_x / UPLOAD_CHUNK, last_x / UPLOAD_CHUNK + 1):
			_dirty_upload_layers[chunk_y * UPLOAD_CHUNKS_ACROSS + chunk_x] = 1
	_dirty = true


func _mark_all_upload_layers() -> void:
	_dirty_upload_layers.resize(UPLOAD_LAYER_COUNT)
	_dirty_upload_layers.fill(1)
	_dirty = true


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


## Shapes the raw noise into lobes. See EDGE_TEAR.
func _lobed(noise_value: float) -> float:
	return clampf(tanh(noise_value * EDGE_TEAR) * EDGE_TEAR_GAIN, -1.0, 1.0)


func _blob(
	image: Image,
	resolution: int,
	cell_m: float,
	cell: Vector2,
	centre_world: Vector2,
	radius_m: float,
	strength: float,
	forward: Vector2,
	aspect: float,
	core: float,
	irregularity: float,
	edge_seed: float,
	fall: Vector2,
	downhill_scale: float,
	scuff: float,
	track_profile: TrackProfileDefinition = null
) -> Rect2i:
	var touched := Rect2i()
	var scrape := clampf(scuff, 0.0, 1.0)
	var radius := maxf(radius_m / cell_m, 1.0)
	# A scrape is longer than the boot that made it AND narrower, so the two axes
	# move in opposite directions -- and the box below has to be told, or the ends
	# of the scrape are clipped square across. Both need a heading to have a
	# meaning; with none given the mark stays round whatever `scuff` says.
	var stretch := 1.0 + SCUFF_STRETCH * scrape
	var narrow := 1.0 - SCUFF_NARROW * scrape
	# The warp pushes the outline outward as often as inward, so the box has to
	# allow for it or the ragged edge is clipped back to a straight line.
	var reach := radius * (1.0 + maxf(irregularity, 0.0)) * stretch
	var min_x := maxi(int(floorf(cell.x - reach)), 0)
	var max_x := mini(int(ceilf(cell.x + reach)), resolution - 1)
	var min_y := maxi(int(floorf(cell.y - reach)), 0)
	var max_y := mini(int(ceilf(cell.y + reach)), resolution - 1)
	var clamped := clampf(strength, 0.0, 1.0)
	# The pressed floor goes as the mark stops being a hole -- see SCUFF_CORE.
	var pressed := lerpf(core, SCUFF_CORE, scrape)
	# How much of the floor is broken up by what fell onto it. Both terms, because
	# the two are different events with the same symptom: a deep print's walls
	# collapse into it, and a scrape never had a floor to begin with.
	var broken := clampf(FLOOR_BREAK_GAIN * maxf(irregularity, 0.0) + SCUFF_BREAK * scrape, 0.0, 0.9)

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
	elif along != Vector2.ZERO:
		# The old square bound used the boot's long axis in both directions. A
		# 1.5:1 footprint therefore visited almost twice as many untouched texels
		# as its rotated ellipse can reach. This exact rotated AABB includes the
		# full irregularity allowance and changes no mask value or overlap rule.
		var edge_allowance := 1.0 + maxf(irregularity, 0.0)
		var along_reach := radius * stretch * edge_allowance
		var across_reach := radius * narrow / aspect * edge_allowance
		var half_x := sqrt(
			along.x * along.x * along_reach * along_reach
			+ along.y * along.y * across_reach * across_reach
		)
		var half_y := sqrt(
			along.y * along.y * along_reach * along_reach
			+ along.x * along.x * across_reach * across_reach
		)
		min_x = maxi(int(floorf(cell.x - half_x)), 0)
		max_x = mini(int(ceilf(cell.x + half_x)), resolution - 1)
		min_y = maxi(int(floorf(cell.y - half_y)), 0)
		max_y = mini(int(ceilf(cell.y + half_y)), resolution - 1)

	# Resource dispatch inside the texel loop was four times more expensive than
	# the whole legacy stamp. Resolve the snow band and copy the authored scalar
	# profile once; the hot path below stays arithmetic-only.
	var profiled := track_profile != null and along != Vector2.ZERO
	var sole_definition := 0.0
	var heel_centre_x := 0.0
	var heel_half_length := 1.0
	var heel_half_width := 1.0
	var waist_centre_x := 0.0
	var waist_half_length := 1.0
	var waist_half_width := 1.0
	var forefoot_centre_x := 0.0
	var forefoot_half_length := 1.0
	var forefoot_half_width := 1.0
	var heel_weight := 1.0
	var forefoot_weight := 1.0
	var weight_transition_from_x := 0.0
	var weight_transition_to_x := 1.0
	var heel_inv_length := 1.0
	var heel_inv_width := 1.0
	var waist_inv_length := 1.0
	var waist_inv_width := 1.0
	var forefoot_inv_length := 1.0
	var forefoot_inv_width := 1.0
	if profiled:
		sole_definition = track_profile.sole_definition_at(1.0 - scrape)
		var compiled := _compiled_profile(track_profile)
		heel_centre_x = compiled[0]
		heel_half_length = compiled[1]
		heel_half_width = compiled[2]
		waist_centre_x = compiled[3]
		waist_half_length = compiled[4]
		waist_half_width = compiled[5]
		forefoot_centre_x = compiled[6]
		forefoot_half_length = compiled[7]
		forefoot_half_width = compiled[8]
		heel_weight = compiled[9]
		forefoot_weight = compiled[10]
		weight_transition_from_x = compiled[11]
		weight_transition_to_x = compiled[12]
		heel_inv_length = 1.0 / heel_half_length
		heel_inv_width = 1.0 / heel_half_width
		waist_inv_length = 1.0 / waist_half_length
		waist_inv_width = 1.0 / waist_half_width
		forefoot_inv_length = 1.0 / forefoot_half_length
		forefoot_inv_width = 1.0 / forefoot_half_width

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
					offset.dot(along) / (radius * stretch),
					offset.dot(across) / (radius * narrow / aspect)
				)
			var distance_squared := local.length_squared()
			var distance := 0.0
			if profiled:
				# A dusting cannot hold a sole mould and a drift collapses back
				# into a pocket. Only the middle snow band records the boot clearly.
				# Three squared ellipse distances share one sqrt, then blend back
				# toward the legacy pocket according to the authored snow band.
				var waist_x := (local.x - waist_centre_x) * waist_inv_length
				var waist_y := local.y * waist_inv_width
				var sole_distance_squared := waist_x * waist_x + waist_y * waist_y
				# The waist is the overlap seam. On either side only the adjacent
				# lobe can own the union, so evaluating the distant end buys nothing
				# except two multiplies per footprint texel.
				if local.x < waist_centre_x:
					var heel_x := (local.x - heel_centre_x) * heel_inv_length
					var heel_y := local.y * heel_inv_width
					sole_distance_squared = minf(
						sole_distance_squared, heel_x * heel_x + heel_y * heel_y
					)
				else:
					var forefoot_x := (local.x - forefoot_centre_x) * forefoot_inv_length
					var forefoot_y := local.y * forefoot_inv_width
					sole_distance_squared = minf(
						sole_distance_squared,
						forefoot_x * forefoot_x + forefoot_y * forefoot_y
					)
				# Morph squared fields and take one root. Apart from avoiding a second
				# sqrt per texel this keeps every authored 1.0 contour pinned exactly.
				distance = sqrt(lerpf(
					distance_squared, sole_distance_squared, sole_definition
				))
			else:
				distance = sqrt(distance_squared)
			if irregularity > 0.0:
				# Warping the distance rather than the radius means the outline
				# is displaced in whatever direction the noise happens to run,
				# which is what makes it crumble rather than merely ripple.
				# Warping the distance UP moves the outline inward, which is a
				# bite; warping it down moves the outline out, which is snow the
				# boot displaced. The bias is what keeps the first commoner than
				# the second -- see EDGE_BITE_BIAS.
				var warp := _lobed(_edge_noise.get_noise_2d(
					local.x + edge_seed, local.y + edge_seed
				)) + EDGE_BITE_BIAS
				if warp < 0.0 and distance > 0.0001:
					# Displaced snow goes where the foot pushed it -- ahead of the
					# sole and out to the sides, not evenly around a ring, and an
					# even ring is exactly what reads as procedural.
					warp *= lerpf(
						EDGE_PUSH_BEHIND, 1.0, 0.5 + 0.5 * local.x / distance
					)
				# ...and it is the WALLS that fall in, not the sole's own mark. Left
				# ungated, a warp this coarse tears the print into three or four
				# disconnected islands -- which is not a bite out of a hole, it is
				# the ring of hard little fragments that was rejected once already.
				distance += warp * irregularity * smoothstep(
					EDGE_TEAR_FROM, EDGE_TEAR_FULL, distance
				)
			if distance >= 1.0:
				continue
			# Flat to `pressed`, then smoothstep out. smoothstep rather than a
			# linear ramp or 1 - d*d because it arrives flat at both ends, so
			# the rim meets the snow without a slope discontinuity -- a
			# discontinuity in the height field is a crease in the normal, and
			# a crease is what shows up as a shard.
			#
			# A pow(1 - t, 1.3) taper was tried here on the argument that a
			# smoothstep is flat across the middle of its shoulder and so only
			# holds a usable tilt over part of it -- which is the argument that
			# won for the furrow's V. It is not true at this scale and the CPU
			# model of the shader says so: both drop the same depth over the same
			# distance, the shader's 6 cm normal epsilon is as wide as the whole
			# shoulder, and the shaded fraction came out 18.6% against 19.1%.
			# It cost tone across the shoulder for nothing. Left recorded so the
			# next pass does not spend the afternoon rediscovering it.
			var profile := 1.0 - smoothstep(pressed, 1.0, distance)
			if broken > 0.0 and distance > pressed:
				# The rubble, in WORLD space so that overlapping prints churn
				# together instead of averaging each other smooth -- see
				# FLOOR_BREAK_M.
				#
				# On the SHOULDER only, faded in across it, and SIGNED. The sole
				# presses the floor of the print flat and it is the collapsed
				# wall that is broken, so breaking the floor as well merely spent
				# the print's depth -- it measured a third of it, and a third of
				# the depth is a third of every shadow the mark has. Signed for
				# the same reason: a break that only ever subtracts is a print
				# that is always shallower than the one it replaced.
				#
				# Fading it in from the core is what keeps the join smooth. A
				# break applied to the shoulder outright is a step at the core
				# boundary, which is a crease ring in the normal.
				var out := (distance - pressed) / maxf(1.0 - pressed, 0.0001)
				var here := centre_world + Vector2(
					float(x) - cell.x, float(y) - cell.y
				) * cell_m
				profile *= 1.0 + broken * out * 0.5 * _lobed(
					_floor_noise.get_noise_2d(here.x, here.y)
				)
			var compression := 1.0
			if profiled and sole_definition > 0.0:
				var weight := lerpf(
					heel_weight, forefoot_weight,
					smoothstep(weight_transition_from_x, weight_transition_to_x, local.x)
				)
				compression = lerpf(
					1.0, weight, sole_definition
				)
			var value := clamped * compression * clampf(profile, 0.0, 1.0)
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


## A field remembered through a settled snow layer, rather than a comb stamped
## over it.  The individual furrows are still laid out by the same field-space
## arguments as `bake_furrows()`, but every pass is interrupted by independent
## wind-packed drifts.  At an establishing distance the eye reads a worked
## field from the shared direction and uneven density, not from a screen-wide
## stack of perfectly continuous parallel strokes.
##
## This is deliberately a static-layer primitive: these are autumn furrows
## partially buried by winter, not new tracks the wind should erase.  The
## caller supplies every shaping value so a different farm or future biome can
## choose its own evidence without adding a game noun to this system.
func bake_broken_furrows(
	origin: Vector3,
	direction: Vector2,
	length_m: float,
	spacing_m: float,
	count: int,
	radius_m: float,
	strength: float,
	segment_min_m: float,
	segment_max_m: float,
	gap_min_m: float,
	gap_max_m: float,
	seed: int,
	irregularity := 0.0
) -> void:
	if direction.length_squared() < 0.0001 or length_m <= 0.0 or count <= 0:
		return
	var along := direction.normalized()
	var across := Vector2(-along.y, along.x)
	var shortest_segment := maxf(minf(segment_min_m, segment_max_m), 0.001)
	var longest_segment := maxf(maxf(segment_min_m, segment_max_m), shortest_segment)
	var shortest_gap := maxf(minf(gap_min_m, gap_max_m), 0.0)
	var longest_gap := maxf(maxf(gap_min_m, gap_max_m), shortest_gap)
	for index in range(count):
		var rng := RandomNumberGenerator.new()
		# A prime stride makes adjacent rows independent without making the
		# field reshuffle between loads.
		rng.seed = seed + index * 104729
		var offset := across * (spacing_m * float(index))
		var row_start := origin + Vector3(offset.x, 0.0, offset.y)
		# No shared first edge: a rectangular field of aligned stroke starts is
		# nearly as visible as the continuous lines this primitive replaces.
		var travelled := rng.randf_range(0.0, longest_gap)
		while travelled < length_m:
			var run := rng.randf_range(shortest_segment, longest_segment)
			var end := minf(travelled + run, length_m)
			bake_stroke(
				row_start + Vector3(along.x, 0.0, along.y) * travelled,
				row_start + Vector3(along.x, 0.0, along.y) * end,
				radius_m,
				strength * rng.randf_range(0.72, 1.0),
				0.35,
				irregularity,
				rng.randf() * 97.0
			)
			travelled = end + rng.randf_range(shortest_gap, longest_gap)


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
		_mark_upload_box(Rect2i(tile_x, tile_y, inner_w, inner_h))
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
	# Every layer's contents move relative to its layer after a recenter.  This
	# remains one four-megabyte upload only on that infrequent boundary crossing;
	# ordinary deep-snow steps stay at one roughly 258 KiB layer.
	_mark_all_upload_layers()


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


## One upload per dirty layer per frame at most, however many prints landed in
## it. The static layer goes up the old way, which in practice means exactly
## once -- it is dirty on the frame it was baked and never again.
func flush() -> void:
	_last_upload_layer_count = 0
	_last_upload_bytes = 0
	_last_upload_duration_ms = 0.0
	if _dirty and _texture != null:
		var started_us := Time.get_ticks_usec()
		for layer_index in range(UPLOAD_LAYER_COUNT):
			if _dirty_upload_layers[layer_index] == 0:
				continue
			_refresh_upload_layer(layer_index)
			_texture.update_layer(_upload_layers[layer_index], layer_index)
			_dirty_upload_layers[layer_index] = 0
			_last_upload_layer_count += 1
		_last_upload_bytes = _last_upload_layer_count * UPLOAD_BYTES_PER_LAYER
		_last_upload_duration_ms = float(Time.get_ticks_usec() - started_us) / 1000.0
		_total_upload_layer_count += _last_upload_layer_count
		_total_upload_bytes += _last_upload_bytes
		_dirty = false
	if _static_dirty and _static_texture != null:
		_static_texture.update(_static)
		_static_dirty = false


## Copies one 512-square core plus its one-texel neighbours into a reusable
## layer image.  All work is native Image blits; no 264,196-iteration GDScript
## loop is introduced on the upload path.
func _refresh_upload_layer(layer_index: int) -> void:
	var chunk_x := layer_index % UPLOAD_CHUNKS_ACROSS
	var chunk_y := layer_index / UPLOAD_CHUNKS_ACROSS
	var core_x := chunk_x * UPLOAD_CHUNK
	var core_y := chunk_y * UPLOAD_CHUNK
	var source_x := maxi(core_x - UPLOAD_GUTTER, 0)
	var source_y := maxi(core_y - UPLOAD_GUTTER, 0)
	var source_end_x := mini(core_x + UPLOAD_CHUNK + UPLOAD_GUTTER, RESOLUTION)
	var source_end_y := mini(core_y + UPLOAD_CHUNK + UPLOAD_GUTTER, RESOLUTION)
	var destination := Vector2i(
		UPLOAD_GUTTER if chunk_x == 0 else 0,
		UPLOAD_GUTTER if chunk_y == 0 else 0
	)
	var layer: Image = _upload_layers[layer_index]
	layer.blit_rect(
		_mask,
		Rect2i(source_x, source_y, source_end_x - source_x, source_end_y - source_y),
		destination
	)
	# The outer world edge matches repeat_disable on the original monolithic
	# texture: duplicate its last valid texel into the missing gutter.
	if chunk_x == 0:
		layer.blit_rect(layer, Rect2i(UPLOAD_GUTTER, 0, 1, UPLOAD_LAYER_SIZE), Vector2i.ZERO)
	elif chunk_x == UPLOAD_CHUNKS_ACROSS - 1:
		layer.blit_rect(
			layer, Rect2i(UPLOAD_LAYER_SIZE - 2, 0, 1, UPLOAD_LAYER_SIZE),
			Vector2i(UPLOAD_LAYER_SIZE - 1, 0)
		)
	if chunk_y == 0:
		layer.blit_rect(layer, Rect2i(0, UPLOAD_GUTTER, UPLOAD_LAYER_SIZE, 1), Vector2i.ZERO)
	elif chunk_y == UPLOAD_CHUNKS_ACROSS - 1:
		layer.blit_rect(
			layer, Rect2i(0, UPLOAD_LAYER_SIZE - 2, UPLOAD_LAYER_SIZE, 1),
			Vector2i(0, UPLOAD_LAYER_SIZE - 1)
		)


func texture() -> Texture2DArray:
	return _texture


func last_upload_layer_count() -> int:
	return _last_upload_layer_count


func last_upload_bytes() -> int:
	return _last_upload_bytes


func last_upload_duration_ms() -> float:
	return _last_upload_duration_ms


func total_upload_layer_count() -> int:
	return _total_upload_layer_count


func total_upload_bytes() -> int:
	return _total_upload_bytes


## The exact reusable image passed to Texture2DArray.update_layer(). Kept as a
## read-only instrumentation hook because the dummy renderer cannot read a
## Texture2DArray back, while boundary tests still need to prove what is sent to
## the real renderer. Callers must not modify the returned image.
func upload_layer_image(layer_index: int) -> Image:
	if layer_index < 0 or layer_index >= _upload_layers.size():
		return null
	return _upload_layers[layer_index]


func _on_footprint(payload) -> void:
	if not (payload is Dictionary):
		return
	var data: Dictionary = payload
	var subject = data.get("subject", &"")
	if not (subject is StringName or subject is String) or StringName(subject) == &"":
		return
	var track_profile := profile_for_subject(StringName(subject))
	if track_profile == null:
		stamp(
			data.get("position", Vector3.ZERO), data.get("radius", 0.28),
			data.get("strength", 0.6), data.get("forward", Vector2.ZERO),
			data.get("aspect", 1.0), data.get("core", 0.55),
			data.get("irregularity", 0.0), data.get("edge_seed", 0.0),
			data.get("fall", Vector2.ZERO), data.get("downhill_scale", 1.0),
			data.get("scuff", 0.0)
		)
	else:
		stamp_profiled(
			data.get("position", Vector3.ZERO), data.get("radius", 0.28),
			data.get("strength", 0.6), data.get("forward", Vector2.ZERO),
			data.get("aspect", 1.0), data.get("core", 0.55),
			data.get("irregularity", 0.0), data.get("edge_seed", 0.0),
			data.get("fall", Vector2.ZERO), data.get("downhill_scale", 1.0),
			data.get("scuff", 0.0), track_profile
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
