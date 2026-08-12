class_name Snowfall
extends Node3D

## How hard it is snowing, and where the snow is.
##
## GDD section 7 makes the weather a mechanic and section 4 makes day 7 a
## whiteout, so the snowfall is not decoration and is not constant. This is the
## one place that decides the rate, and it publishes that rate to three places:
## the three SnowfallLayers, and TrackMask, whose footprints fill in faster the
## harder it snows.
##
## ---------------------------------------------------------------------------
## WHERE THE RATE COMES FROM TODAY, AND WHERE IT WILL COME FROM
## ---------------------------------------------------------------------------
## src/systems/weather_system.gd is Wave 3 and does not exist. Leaving the snow
## waiting for it would mean shipping an inert effect, so today the rate comes
## from the lighting: the six presets already switch per day through
## LightingDirector, and WHITEOUT is the storm by construction. `storm_by_preset`
## below is that mapping, and it is exported so it can be re-tuned in the scene
## without touching this file.
##
## THE LIGHTING IS READ, NEVER WRITTEN. This asks LightingDirector which look is
## on screen and nothing else; a preset carries no snowfall field and does not
## need one.
##
## When the weather system arrives it calls set_snowfall_rate() and takes the
## wheel permanently -- see that method. Nothing has to be unwired.
##
## ---------------------------------------------------------------------------
## WEATHER ARRIVES, IT DOES NOT SNAP
## ---------------------------------------------------------------------------
## LightingDirector crossfades between presets over eight seconds and, from the
## first frame of that fade, reports the preset it is BECOMING. So a snowfall
## that read the preset id directly would go from clear to blizzard in one tick
## while the light took eight seconds to follow. The rate is therefore eased
## toward its target on a time constant of its own, which also means a weather
## system that steps its output does not step the sky.

## The rate this reports when nothing has an opinion: an unmapped preset, no
## lighting at all, or a director that has not resolved one yet. Not zero, and
## deliberately: a new preset that nobody thought about should look like weather,
## not like a bug.
@export var default_storm := 0.3

## Art Bible section 4.2's six looks, as snowfall. WHITEOUT is day 7 and is the
## blizzard; PALE DAY is days 1-2 and is nearly clear but never quite clear,
## because a sky with nothing in it reads as a different game. FLAT is the debug
## reference and is the only one that asks for none.
##
## Keys are the preset ids in data/lighting/*.tres.
@export var storm_by_preset: Dictionary = {
	&"flat": 0.0,
	&"pale_day": 0.12,
	&"sunrise": 0.1,
	&"nightfall": 0.35,
	&"deep_night": 0.28,
	&"whiteout": 1.0,
}

## How long the sky takes to arrive at a new rate, as a time constant. In the
## same range as the lighting's own eight-second crossfade: the two are showing
## the same weather and they must not disagree about when it happened.
@export var rate_response_seconds := 6.0

## The extra drift a full gale adds, as an acceleration, in world metres. Handed
## to every layer through SnowfallLayer.set_wind(); at rest it is exactly zero
## and the layers drift on their own authored numbers.
##
## Mostly +X with a little +Z, which is the style document's wind direction and
## which the camera's fixed -35 degree yaw turns into snow crossing the frame
## from the left rather than into or out of it.
@export var gale_wind := Vector3(1.6, 0.0, 0.5)

## The height the camera's view axis is taken to meet the ground at. Not the
## snow's floor -- flakes fall past it and are hidden by the terrain, which is
## what they should do -- just the point the volume is centred on.
@export var ground_height := 1.0

const LAYER_GROUP := SnowfallLayer.GROUP

var _rate := 0.0
var _target := 0.0
var _overridden := false
var _wind_strength := 0.0

var _lighting = null
var _mask = null
var _framed := false
## The look the current rate came from, for _lighting_cut().
var _seen_preset: StringName = &""
var _camera_position := Vector3.ZERO
var _forward := Vector3(0.0, -1.0, 0.0)
## What the camera is drawing, in world metres. See frame_size().
var _frame := Vector2.ZERO
## ...and the same frame in pixels, which is a different fact and is needed for a
## different reason: SnowfallLayer's legibility floor is about aliasing, and
## aliasing is about pixels.
var _pixels := Vector2.ZERO


func _ready() -> void:
	# Guarded on is_inside_tree() rather than merely null-checked: an absolute
	# path from outside the tree is an engine ERROR, not a null, and a unit test
	# builds this the way it builds everything else -- with new() and no tree.
	var registry := _registry()
	if registry != null:
		registry.register(&"snowfall", self)
	# The first frame of a run is already the weather that day asks for, rather
	# than a sky that fills in over the first six seconds of play.
	settle()


func _exit_tree() -> void:
	var registry := _registry()
	if registry != null and registry.get_service(&"snowfall") == self:
		registry.unregister(&"snowfall")


## Trap 3: an autoload is a node under /root, never an Engine singleton. And an
## absolute path asked for from outside the tree is an engine error rather than
## a null, which is why every caller here goes through this.
func _registry() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/ServiceRegistry")


# --- the hooks --------------------------------------------------------------

## THE WEATHER HOOK. 0 clear .. 1 heavy, and the same word TrackMask chose for
## the same fact -- see src/systems/track_mask.gd.
##
## Calling this takes the rate away from the lighting presets for good, which is
## what src/systems/weather_system.gd (Wave 3) will want: two things easing the
## same number in opposite directions is worse than either.
func set_snowfall_rate(rate: float) -> void:
	_overridden = true
	_target = clampf(rate, 0.0, 1.0)


## What is falling right now. Eased toward the target -- see the header -- so
## this and target_snowfall_rate() differ for a few seconds after a change.
func snowfall_rate() -> float:
	return _rate


func target_snowfall_rate() -> float:
	return _target


## THE WIND HOOK. 0 dead still .. 1 full gale, in TrackMask's vocabulary again.
## src/systems/wind_system.gd is Wave 3. At the default of zero the snow still
## drifts, on the layers' own numbers: this adds a gale on top rather than being
## the only thing that moves the snow sideways.
##
## The wind is NOT pushed to TrackMask. Its wind hook belongs to the wind system,
## and a snowfall that invented a wind to feed it would be a second wind in the
## game before the first one exists.
func set_wind_strength(strength: float) -> void:
	_wind_strength = clampf(strength, 0.0, 1.0)


func wind_strength() -> float:
	return _wind_strength


## The gale as the layers take it: an acceleration, in the vocabulary
## SnowfallLayer.set_wind() and BreathFog.set_wind() share.
func wind_velocity() -> Vector3:
	return gale_wind * _wind_strength


## THE FRAMING HOOK, and it is a push rather than a pull: every layer is told
## what the camera is drawing on the same frame, and through the same call, as
## it is told the weather. See _read_camera(), which is the one place it is
## sampled, and drive(), which is the one place it is handed on.
func set_frame_size(metres: Vector2) -> void:
	_frame = metres


func frame_metres() -> Vector2:
	return _frame


## The viewport, in pixels. Only the legibility floor uses it -- see
## SnowfallLayer.min_flake_pixels -- and it is a separate hook because it is a
## separate fact: resizing a window changes this without changing the framing.
func set_frame_pixels(pixels: Vector2) -> void:
	_pixels = pixels


func frame_pixels() -> Vector2:
	return _pixels


## Injected by a test, or by whoever wires the scene. Resolved from the
## ServiceRegistry otherwise, the same way LightingDirector.set_event_bus() works.
func set_lighting(lighting) -> void:
	_lighting = lighting


func set_track_mask(mask) -> void:
	_mask = mask


# --- the geometry -----------------------------------------------------------

## Where the emission volume belongs, given where the camera is and which way it
## is looking. Static and arithmetic-only, so the whole of it is testable without
## a viewport, a camera or a rendered frame.
##
## Two steps. The first is where the view axis meets the ground, which is what
## the camera is actually looking at -- not the camera's own position, which on a
## 90 m boom is most of a hundred metres away from anything in shot.
##
## The second is why this is not simply "put the box in the air above that": the
## projection is PARALLEL, so sliding a point along the view axis does not move
## it on screen AT ALL. Backing up the axis therefore raises the volume into the
## sky and leaves it exactly where it was in frame, where a world-vertical offset
## under a 45 degree pitch would carry it off the top of the picture.
static func volume_centre(
	camera_position: Vector3, forward: Vector3, ground_height: float, pullback_m: float
) -> Vector3:
	var direction := forward.normalized()
	var focus := camera_position
	# A camera that is not looking down never meets the ground, and the step
	# below divides by exactly how steeply it is. The frame stays snowy rather
	# than sending the volume to infinity.
	if direction.y < -0.001:
		focus = camera_position + direction * ((ground_height - camera_position.y) / direction.y)
	return focus - direction * pullback_m


## ---------------------------------------------------------------------------
## WHAT THE CAMERA IS ACTUALLY DRAWING
## ---------------------------------------------------------------------------
## The frame, in world metres: x across the picture and y up it. Under a parallel
## projection this is a real, finite rectangle, and it is the only thing the snow
## needs in order to size itself -- see SnowfallLayer's header.
##
## READ OFF THE CAMERA, and deliberately so. CameraRig owns the framing: it holds
## the player's chosen stop, resolves it through a ModifierStack so later systems
## can argue with it, and EASES to the result over a fifth of a second. Every one
## of those steps lands in exactly one place -- `Camera3D.size`, written by
## CameraRig.apply_framed_size(), which is the rig's own single writer. Sampling
## the camera therefore gets the resolved, tweened, actually-rendered frame for
## free, on every frame, with nothing here holding a reference to the rig and no
## copy of its stops anywhere in this system.
##
## It also picks up the one framing the rig does not know about:
## tools/capture_frame.gd's `--ortho` writes the camera directly.
##
## How many PIXELS a viewport is, which is a different question from how big its
## rect is and has a different answer.
##
## `get_visible_rect()` is 2D canvas space: under this project's `canvas_items`
## stretch it reports the project's base viewport -- measured as 1152 x 720 in a
## 1280 x 800 window -- so a legibility floor converted through it would be out by
## eleven per cent, in the safe-looking direction. `get_texture().get_size()` is
## worse: it reported 1423 x 889 for the same window, an internal allocation that
## does not match the 1280 x 800 image the frame actually saves.
##
## The window's own size is the one that matches the pixels on the glass, checked
## against a saved PNG. A SubViewport answers the same question with `size`.
static func viewport_pixels(viewport: Viewport) -> Vector2:
	if viewport == null:
		return Vector2.ZERO
	if viewport is Window:
		return Vector2((viewport as Window).size)
	if viewport is SubViewport:
		return Vector2((viewport as SubViewport).size)
	return viewport.get_visible_rect().size


## A perspective camera has no frame height in metres -- it has a different one
## at every depth -- so this says ZERO rather than inventing one, and the layers
## fall back to the numbers their scene files were authored with.
static func frame_size(camera: Camera3D, viewport_pixels: Vector2) -> Vector2:
	if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return Vector2.ZERO
	if viewport_pixels.x <= 0.0 or viewport_pixels.y <= 0.0:
		return Vector2.ZERO
	var aspect := viewport_pixels.x / viewport_pixels.y
	# `size` is whichever extent keep_aspect nominates -- height by default. Read
	# the wrong way round it would scale the snow by the aspect ratio.
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		return Vector2(camera.size, camera.size / aspect)
	return Vector2(camera.size * aspect, camera.size)


## How far back up the view axis a layer's volume belongs, at the framing now in
## force. The pullback is what lifts the box into the air; a box that grew with
## the frame while its pullback stayed put would sink into the ground it is
## supposed to be falling onto.
func pullback_for(layer: SnowfallLayer) -> float:
	if layer == null:
		return 0.0
	return layer.pullback_m * layer.geometry_scale()


# --- driving it -------------------------------------------------------------

## Applies the weather to one layer, and places it if it is a world layer. Public
## and taking the layer as an argument so that the whole of what a frame does can
## be tested against one emitter, with no tree and no camera.
func drive(layer: SnowfallLayer) -> void:
	if layer == null:
		return
	layer.set_snowfall_rate(_rate)
	layer.set_wind(wind_velocity())
	# ...and what it is drawing into, which is what sizes the volume and the
	# flake. Here rather than read by the layer for the same reason the weather is
	# here: one place samples the camera, so no layer can end up running this
	# frame's snowfall against last frame's framing.
	layer.set_frame_size(_frame)
	layer.set_frame_pixels(_pixels)
	# A lens layer is parented to the camera and rides it. Moving it would be
	# taking it off the lens, which is the only thing it does -- and it places its
	# own emission box in camera space, from the frame it was just handed.
	if layer.camera_space or not _framed:
		return
	layer.global_position = volume_centre(
		_camera_position, _forward, ground_height, pullback_for(layer)
	)


## Puts the sky where it is going immediately, skipping the ease. For the first
## frame of a run, and for a test that does not want to spend six seconds.
func settle() -> void:
	_target = _resolve_target()
	_rate = _target
	_seen_preset = _current_preset_id()
	_publish()


func _process(delta: float) -> void:
	_target = _resolve_target()
	if _lighting_cut():
		# The look did not fade, it CUT. See _lighting_cut().
		_rate = _target
	elif rate_response_seconds > 0.0 and delta > 0.0:
		# Exponential ease, frame-rate independent: what is fixed is the fraction
		# of the gap closed per second, not per frame. Same form as CameraRig's
		# follow.
		_rate = lerpf(_rate, _target, 1.0 - exp(-delta / rate_response_seconds))
	else:
		_rate = _target
	_publish()


## True on the frame the lighting CUT to a different look rather than fading to
## one, in which case the weather cuts with it.
##
## Both of the things that cut are tools for looking at the game: Art Bible
## section 4.2's six hotkeys, and tools/capture_frame.gd, which snaps a preset on
## one frame before the shutter. Both exist to answer "what does this look like
## on day 7" without playing to day 7, and an eased snowfall answers with day 1's
## weather -- six seconds of ease against one frame of warning.
##
## A lighting that cannot say whether it is crossfading is taken to be fading,
## which is the safe reading: easing a cut looks like slow weather, cutting a
## fade looks like a bug.
func _lighting_cut() -> bool:
	var id := _current_preset_id()
	var changed := id != _seen_preset and _seen_preset != &""
	_seen_preset = id
	if not changed or _lighting == null or not _lighting.has_method("is_crossfading"):
		return false
	return not _lighting.is_crossfading()


## The look the rate is currently derived from, or nothing at all when a weather
## system has taken the wheel -- in which case there is no look to cut between.
func _current_preset_id() -> StringName:
	if _overridden or _lighting == null or not _lighting.has_method("active_preset"):
		return &""
	var look = _lighting.active_preset()
	return look.id if look != null else &""


func _publish() -> void:
	_framed = _read_camera()
	for layer in _layers():
		drive(layer as SnowfallLayer)
	_tell_the_ground()


## Every layer in the game, including the one under the camera. Found by group
## rather than by path, which is the only reason the lens layer can live inside
## a node this system must not hold a reference to.
func _layers() -> Array:
	if not is_inside_tree():
		return []
	return get_tree().get_nodes_in_group(LAYER_GROUP)


## Snow filling a footprint in is TrackMask's own mechanic, on TrackMask's own
## hook; this only tells it the weather. Guarded on the method rather than the
## type so that a stand-in, or a mask that has not been registered yet, is a
## quiet no-op instead of a crash on the first frame.
func _tell_the_ground() -> void:
	if _mask == null:
		var registry := _registry()
		if registry != null:
			_mask = registry.get_service(&"track_mask")
	if _mask == null or not _mask.has_method("set_snowfall_rate"):
		return
	_mask.set_snowfall_rate(_rate)


func _read_camera() -> bool:
	if not is_inside_tree():
		return false
	var viewport := get_viewport()
	if viewport == null:
		return false
	var camera := viewport.get_camera_3d()
	if camera == null:
		return false
	_camera_position = camera.global_position
	_forward = -camera.global_basis.z
	# Sampled every frame, which is the whole of "follows the tween": the rig
	# eases the frame over 0.12-0.22 s and this reads wherever it currently is,
	# rather than what stop it is heading for.
	_pixels = viewport_pixels(viewport)
	_frame = frame_size(camera, _pixels)
	return true


func _resolve_target() -> float:
	if _overridden:
		return _target
	if _lighting == null:
		var registry := _registry()
		if registry != null:
			_lighting = registry.get_service(&"lighting")
	if _lighting == null or not _lighting.has_method("active_preset"):
		return default_storm
	var look = _lighting.active_preset()
	if look == null:
		return default_storm
	return _storm_for(look.id)


## The table lookup, tried both ways round. A Dictionary authored in this script
## has StringName keys, one edited in the inspector or written into a .tscn may
## have String ones, and the whole mapping silently falling back to the default
## because of which of the two it was is exactly the kind of failure that looks
## like a tuning problem.
func _storm_for(id: StringName) -> float:
	if storm_by_preset.has(id):
		return float(storm_by_preset[id])
	if storm_by_preset.has(String(id)):
		return float(storm_by_preset[String(id)])
	return default_storm
