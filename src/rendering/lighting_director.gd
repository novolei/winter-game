class_name LightingDirector
extends WorldEnvironment

## Builds the Environment, aims the sun, and decides which of Art Bible section
## 4.2's six looks is on screen. All in code, for the same reason the terrain
## material is: every colour comes out of the palette at runtime, so no colour
## literal ends up sitting in scenes/main.tscn.
##
## Art Bible rule 10 -- shadows are the subject, not a by-product:
##
##   * The sun sits about 11 degrees above the horizon. Shadow length is
##     height / tan(elevation), so at 11 degrees a 5 m tree throws a 26 m
##     shadow. That is what puts a third of the frame in shade.
##   * light_angular_distance gives the penumbra its width, so the edges stay
##     soft over that length instead of turning to a hard stencil.
##   * The shadow *colour* is not set here at all -- it is a palette uniform on
##     the cel shaders. Nothing multiplies anything.
##
## ---------------------------------------------------------------------------
## THE SIX PRESETS, AND WHAT A PRESET CAN ACTUALLY MOVE
## ---------------------------------------------------------------------------
## data/lighting/*.tres holds the six; data/schedule/day_NN.tres names two of
## them per day, one for the daylight phase and one for the night. WorldClock
## announces the phase changes on the EventBus and this crossfades between them.
## Neither system holds a reference to the other, and this file loads the day
## table itself rather than asking the clock for it -- deleting WorldClock has to
## leave the lighting compiling.
##
## CROSSFADING RATHER THAN CUTTING is not decoration. DEEP NIGHT's exposure is a
## third of PALE DAY's, and dropping that in one frame in a game with no HUD
## reads as a rendering fault rather than as nightfall.
##
## What a preset moves, and what it does not, is the single most surprising thing
## about lighting this project. The long version is in
## src/definitions/lighting_preset.gd; the short version:
##
##   THE WORLD is on the two cel shaders. They pick a palette colour outright and
##   read nothing from a light but ATTENUATION. Sun energy, sun colour and
##   ambient do not reach it AT ALL. Exposure, fog, glow and the shadow switch
##   do.
##
##   THE CHARACTER is the only stock StandardMaterial3D in the game. Sun energy,
##   sun colour and ambient reach him and nothing else.
##
## So every preset carries a matched pair of numbers, and the two controls that
## move both halves together are the exposure and the fog.

const PALETTE_PATH := "res://data/palette/color_bible.tres"
const PRESET_DIRECTORY := "res://data/lighting"
const SCHEDULE_DIRECTORY := "res://data/schedule"

## Spelled out rather than preloaded off WorldClock, the same way MusicDirector
## spells them out: systems never hold references to one another.
const EVENT_DAY_STARTED := &"clock.day_started"
const EVENT_NIGHT_STARTED := &"clock.night_started"

## Shadow length on flat ground is height / tan(elevation), and the derivative
## of that is savage down here: at 11 degrees a shadow ran 5.1x its caster and
## every centimetre the character moved vertically became five centimetres of
## shadow, so the walk lurched. At 21.5 it runs 2.5x -- still unmistakably a low
## raking winter sun, still long enough for rule 10 -- and halves the
## amplification of anything that moves vertically.
##
## THE PRESETS CARRY THIS TOO, in LightingPreset.sun_angle_degrees, because the
## six have to be readable side by side and a value hidden in code is a value
## nobody checks. The applied preset is what actually aims the sun; this is the
## reference all six are pinned to, by
## test_every_preset_agrees_with_the_tuned_elevation, and the fallback when no
## preset is loaded. Neither can drift without the other going red.
@export var sun_elevation_degrees := 21.5

## THE AZIMUTH IS THE SHADOWS' DIRECTION ON SCREEN, AND IT WAS SOLVED, NOT PICKED.
##
## The camera never rotates (rule 1), so a ground direction has one fixed screen
## direction. With the rig pitched 45 and yawed -35, a ground vector (x, z) lands
## on screen at
##
##     screen right = (x, z) . ( 0.8192,  0.5736)
##     screen up    = (x, z) . ( 0.5736, -0.8192) * sin(45)
##
## and a shadow runs along the light's own horizontal travel, (-sin a, -cos a).
## Substituting and simplifying, for phi = a + 35:
##
##     screen right = -sin(phi)          screen up = cos(phi) * 0.7071
##
## so the on-screen rake below horizontal is atan(0.7071 * |cot(phi)|). At the
## previous 118 that is **54 degrees** -- shadows that fall down the screen. In
## `Refs/game ref/level.jpg` they rake nearly across it: measured off the crops,
## the farmhouse throws its shadow left and 16 degrees down, the well house left
## and 13 degrees down. Solving the line above for 20 degrees gives phi = 117.2
## and **a = 82**, which is what this is.
##
## Elevation is untouched at 21.5 and must stay there -- see above, it is what
## stops the shadow length lurching with every step. Azimuth is the only control
## that moves a shadow sideways, and it costs nothing: shadow *length* is
## height / tan(elevation) whichever way the sun faces.
##
## What it does change, and what a reviewer should look at: at 118 the sun was
## almost directly behind the subject from the lens, so nearly every camera-facing
## surface in the world was in shade -- that is the defect character_fill_energy
## below was raised to paper over. At 82 the sun is 63 degrees off the view axis
## instead of 27, so more of what the camera sees is lit, and the shadows are 22%
## longer on screen because they now lie across the frame rather than into it.
@export var sun_azimuth_degrees := 82.0
## Penumbra width grows with distance from the caster, and these shadows are
## 25 m long. At 2.2 degrees the far half of every shadow was penumbra and the
## sheds cast fuzzy ovals; rule 10 wants a soft *edge* around a solid block.
@export var sun_angular_softness := 0.9

## What is on screen before the clock has said anything. Day 1's daylight, so
## the first frame of a run is already the frame the run opens on rather than
## whatever the engine defaults to.
@export var boot_preset: StringName = &"pale_day"

## How long a phase change takes to arrive. Long, and deliberately so: the six
## presets are far apart -- DEEP NIGHT's exposure is a third of PALE DAY's -- and
## a cut between two of them reads as a rendering fault rather than as nightfall.
## Day 1's night is 300 s, so eight seconds is under 3% of the shortest phase in
## the game and still slow enough to be a dusk rather than a switch.
@export var crossfade_seconds := 8.0

## Art Bible section 4.3's slider panel, and the six hotkeys of section 4.2.
## Debug builds only, and it also has to be asked for: it is built the first time
## F1 is pressed and never before, so nothing that renders a frame -- a
## screenshot harness, a test -- ever has it in shot.
@export var debug_controls_enabled := true

var _sun: DirectionalLight3D
var _bible: ColorBible

## id -> LightingPreset, and day number -> [daylight id, night id].
var _presets: Dictionary = {}
var _days: Dictionary = {}

var _bus = null
var _subscribed := false

## What is written to the Environment right now -- a blended preset while a
## crossfade is running, one of the six otherwise.
var _active: LightingPreset = null
var _from: LightingPreset = null
var _to: LightingPreset = null
var _fade_elapsed := 0.0
var _fade_duration := 0.0

var _panel: Node = null
var _sky_material: ProceduralSkyMaterial = null


func _ready() -> void:
	_bible = load(PALETTE_PATH)
	_load_presets()
	_load_days()
	_build_environment()
	_resolve_sun()
	# The boot look, applied outright rather than faded: there is nothing to fade
	# from on the first frame.
	if not apply_preset(boot_preset):
		# Not silently. A missing preset directory means the whole run plays in
		# whatever LightingPreset's script defaults happen to be, and with no HUD
		# there is nothing on screen to say so.
		push_warning("lighting_director: no preset '%s' in %s" % [boot_preset, PRESET_DIRECTORY])
		_write(LightingPreset.new())
	_attach_bus()
	var registry := get_node_or_null("/root/ServiceRegistry") if is_inside_tree() else null
	if registry != null:
		registry.register(&"lighting", self)


func _exit_tree() -> void:
	_detach_bus()
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.get_service(&"lighting") == self:
		registry.unregister(&"lighting")


func _build_environment() -> void:
	var env := Environment.new()
	# A GRADIENT SKY RATHER THAN A FLAT COLOUR. The stops come off the preset and
	# are rewritten on every _write(), so the six do not all share one sky.
	#
	# Honest about its reach: the ground plane is 140 m across and the camera is
	# pitched 45 degrees into it, so at every framing the game currently uses the
	# frame is entirely ground and NONE of this is on screen. It earns its place
	# anyway -- it is what the fog resolves toward as `fog_sky_affect` comes up in
	# the storm, and it is what stops the first shot that tips the camera finding
	# six presets with the same sky.
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.use_debanding = true
	# No sun disc. The sun is 21.5 degrees up and its light is the frame's
	# subject; a white blob on the horizon is not.
	_sky_material.sun_angle_max = 0.0
	_sky_material.sun_curve = 1.0
	var sky := Sky.new()
	sky.sky_material = _sky_material
	# The sky is a backdrop, not a light -- the radiance cubemap exists to be
	# sampled by ambient and by reflections, and both are switched off below. It
	# is REALTIME anyway because the gradient is rewritten every frame of a
	# crossfade, and a realtime sky is the cheap path for that. 256 is not a
	# choice: anything smaller draws
	# "WARNING: Realtime Skies can only use a radiance size of 256" on the first
	# frame, which the test and capture runs are required to be free of.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.background_color = _bible.snow_tones[0]
	# Ambient is the CHARACTER's fill and nothing else's -- every world shader
	# declares ambient_light_disabled. The colour and the energy come off the
	# preset; the source mode is what makes them mean anything.
	#
	# THE SKY MUST NOT TAKE THIS OVER. Switching the background from a flat
	# colour to a sky is exactly the change that would quietly start lighting the
	# character from the sky instead of from the authored fill, and
	# tests/art/test_character_lighting.gd would then be measuring a number
	# nothing uses. Both lines below are that, said out loud.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = 0.0
	# The character is the one stock StandardMaterial3D in the game, so he is the
	# one thing a sky reflection could reach. Art Bible rule 8 bans environment
	# reflections in the world and the character has no business acquiring one
	# from a backdrop nobody can see.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	# DEPTH, NOT EXPONENTIAL, AND THE REASON IS THE BOOM.
	#
	# The rig is orthographic 90 m back, so the whole farmstead sits between
	# about 69 m and 100 m from the camera -- not because anything is far away,
	# but because the camera is. Over that stretch 1 - exp(-density * depth) is
	# very nearly a straight line that starts a long way above zero: fog enough
	# to blue the far tree already greys the near one, and the near one is the
	# one that has to stay black. That is why every tree in the scene was the
	# same near-black whatever its distance, and it is the main reason the frame
	# read flat.
	#
	# A depth window can begin its ramp in front of the nearest thing in the
	# frame and end it past the furthest, which is what aerial perspective is.
	# The price is that the window is measured from the CAMERA and is therefore
	# tied to CameraRig.boom_length -- see tests/art/test_aerial_perspective.gd,
	# which is that coupling written down.
	#
	# Note what this does to `fog_density`: in DEPTH mode it is the fog's OPACITY
	# at the far edge of the window, a 0..1 blend, not a density. Every preset's
	# value was re-authored for it.
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.0
	env.fog_aerial_perspective = 0.0
	# Bloom off whatever is brightest in the frame. The threshold sits just under
	# 1.0 so a palette colour at full intensity -- a lit window, snow in a storm
	# -- crosses it and nothing in the shadow band comes close.
	env.glow_hdr_threshold = 0.95
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# THE MIPS THE BLOOM IS BUILT FROM, authored rather than left at Godot's
	# default of levels 3 and 5.
	#
	# Level 5 is a 1/32 buffer, which for a small very bright source -- a lit
	# window, a firebox seen through a door -- upsamples into a visibly BLOCKY
	# rectangle tens of pixels across rather than a halo. It is plainly a
	# rendering artifact rather than a look, and it is what a wide frame of the
	# farmstead shows around the house the moment anything inside it emits.
	# Levels 2 to 4 give the same soft spread at a quarter the radius and no
	# staircase. Style document section 13 asks for exactly this restraint --
	# a small glow on the warm points, and none on the snow.
	#
	# set_glow_level() is ZERO-based while the inspector's `glow_levels/N` is
	# one-based, so index 1..3 here is the inspector's levels 2 to 4. Godot's
	# own default is indices 2 and 4. Getting that wrong is not silent: index 7
	# prints "Index p_level = 7 is out of bounds" on every frame, which is how
	# this comment came to be written.
	for level in range(0, 7):
		env.set_glow_level(level, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.5)
	environment = env


func _resolve_sun() -> void:
	_sun = get_node_or_null("Sun") as DirectionalLight3D
	if _sun == null:
		return
	_sun.light_specular = 0.0
	_sun.light_angular_distance = sun_angular_softness
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# The orthographic frame is about 18 m by 16 m of ground, so the shadow
	# cascades only have to cover the casters just outside it. 170 m spread the
	# same texels over a hundred times the area and the shadow edges crawled.
	_sun.directional_shadow_max_distance = 75.0
	_sun.directional_shadow_split_1 = 0.06
	_sun.directional_shadow_split_2 = 0.16
	_sun.directional_shadow_split_3 = 0.42
	# A grazing sun makes every receiver a near-parallel surface, which is the
	# worst case for shadow acne; the normal bias is what buys it off without
	# detaching the shadow from its caster.
	# Godot fades shadows out over the last stretch of their range by default,
	# which on a 25 m shadow means the tip dissolves into stipple. These are
	# the frame's subject; they get to reach their end.
	_sun.directional_shadow_fade_start = 0.98
	_sun.shadow_normal_bias = 2.0
	_sun.shadow_bias = 0.04
	_sun.shadow_blur = 1.0


# --- the six ----------------------------------------------------------------

func _load_presets() -> void:
	_presets.clear()
	var dir := DirAccess.open(PRESET_DIRECTORY)
	if dir == null:
		return
	var file_names := dir.get_files()
	file_names.sort()
	for entry in file_names:
		var file_name := entry
		# An exported build serves data/*.tres as *.tres.remap.
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource := ResourceLoader.load(PRESET_DIRECTORY.path_join(file_name))
		if resource is LightingPreset and (resource as LightingPreset).id != &"":
			_presets[(resource as LightingPreset).id] = resource


## GDD section 4's table, read straight off the day files rather than out of
## WorldClock: the clock announces WHEN the phase changed and this owns WHAT it
## changed to, so neither has to know the other exists.
func _load_days() -> void:
	_days.clear()
	var dir := DirAccess.open(SCHEDULE_DIRECTORY)
	if dir == null:
		return
	for entry in dir.get_files():
		var file_name := entry
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource := ResourceLoader.load(SCHEDULE_DIRECTORY.path_join(file_name))
		if resource is DaySchedule:
			var schedule := resource as DaySchedule
			_days[schedule.day_number] = [
				schedule.primary_lighting_preset,
				schedule.night_lighting_preset,
			]


func preset(id: StringName) -> LightingPreset:
	return _presets.get(id, null)


func preset_ids() -> Array:
	var ids: Array = _presets.keys()
	ids.sort()
	return ids


## The blended preset currently written to the Environment. Not one of the six
## while a crossfade is running -- that is the point of it.
func active_preset() -> LightingPreset:
	return _active


## Where the frame is going: the far end of a running crossfade, or where it
## already is.
func target_preset_id() -> StringName:
	if _to != null:
		return _to.id
	return _active.id if _active != null else &""


## Art Bible rule 12's warm quota, published for whatever burns. Nothing warm has
## been placed in the world yet, so this is a seam rather than a value with a
## consumer -- a stove or a lit window scales its own energy by it.
func warm_accent_energy() -> float:
	return _active.warm_accent_energy if _active != null else 0.0


# --- what the world's shaders read off the light ----------------------------
#
# The three values the two cel shaders take from a preset. TerrainRenderer pulls
# them every frame for the ground; CelPainter is handed them in _write() for
# every solid, because a painter is a RefCounted nobody holds.

func cel_band_threshold() -> float:
	return _active.cel_band_threshold if _active != null else 0.12


func cel_band_softness() -> float:
	return _active.cel_band_softness if _active != null else 0.07


## THE COLOUR THE LIT CEL BAND IS MULTIPLIED BY -- normalised so it cannot dim.
##
## A raw multiply by an amber light darkens snow as much as it warms it, and the
## exposure would have to be re-tuned to pay for it, per preset, by hand.
## Dividing the light colour by its own luminance first makes the tint a pure hue
## rotation: white and a unit-luminance colour both have luminance 1, so every
## point on the lerp between them does too.
##
## In LINEAR space, because that is where the shader multiplies. The uniform is
## deliberately not `source_color` -- it is a multiplier, and its red channel
## goes above 1.0 whenever the light is warm.
func world_light_tint() -> Color:
	return tint_for(_active) if _active != null else Color.WHITE


static func tint_for(look: LightingPreset) -> Color:
	if look.world_light_strength <= 0.0:
		return Color.WHITE
	var target := look.world_light_color.srgb_to_linear()
	var luma := 0.2126 * target.r + 0.7152 * target.g + 0.0722 * target.b
	if luma <= 0.0:
		return Color.WHITE
	var unit := Color(target.r / luma, target.g / luma, target.b / luma)
	return Color.WHITE.lerp(unit, clampf(look.world_light_strength, 0.0, 1.0))


## Snaps to one of the six, abandoning any crossfade. False if there is no such
## preset, and nothing moves.
func apply_preset(id: StringName) -> bool:
	var found: LightingPreset = _presets.get(id, null)
	if found == null:
		return false
	apply_look(found)
	return true


## Snaps to a look that is not necessarily one of the six -- what the debug
## panel drags. Abandons any crossfade, for the same reason apply_preset does:
## a fade still running underneath would drag the frame away from whatever was
## just set, which from a slider looks like the slider not working.
func apply_look(look: LightingPreset) -> void:
	_from = null
	_to = null
	_fade_duration = 0.0
	_fade_elapsed = 0.0
	_write(look)


## Starts a crossfade. False when there is nothing to fade to, or when the frame
## is already there.
##
## It fades from where the frame ACTUALLY IS, not from the last whole preset:
## interrupting a fade halfway to DEEP NIGHT and turning for WHITEOUT must
## continue from the half-dark frame on screen, not snap back to PALE DAY and set
## off again.
func crossfade_to(id: StringName, seconds := -1.0) -> bool:
	var found: LightingPreset = _presets.get(id, null)
	if found == null:
		return false
	if _to == null and _active != null and _active.id == id:
		return false
	if _to != null and _to.id == id:
		return false
	var duration := seconds if seconds >= 0.0 else crossfade_seconds
	if duration <= 0.0 or _active == null:
		return apply_preset(id)
	_from = _active
	_to = found
	_fade_duration = duration
	_fade_elapsed = 0.0
	return true


func is_crossfading() -> bool:
	return _to != null


func _process(delta: float) -> void:
	if _to == null:
		return
	_fade_elapsed += delta
	var t := clampf(_fade_elapsed / _fade_duration, 0.0, 1.0)
	if t >= 1.0:
		var arrived := _to
		_from = null
		_to = null
		_write(arrived)
		# The debug panel's sliders must not go on claiming a look the clock has
		# moved away from. Synced when the fade ARRIVES, not when it starts: at
		# the start the frame is still the old preset, and the readouts exist to
		# be typed back into tools/generate_lighting_presets.gd, so the number
		# worth showing is a whole preset's rather than a frame of a blend.
		if _panel != null:
			(_panel as LightingDebugPanel).sync()
		return
	_write(blend(_from, _to, t))


# --- blending ---------------------------------------------------------------

## A preset partway between two others. Static and allocation-only so the whole
## crossfade is testable without a SceneTree, an Environment or a frame.
##
## Two fields are not interpolable and each is handled where it is least
## visible:
##
##   FOG is switched on the moment either end wants it and the DENSITY carries
##   the fade, because fog off IS fog at density zero. Flipping the switch at the
##   midpoint instead would make the haze appear all at once, at half strength --
##   exactly the pop a crossfade exists to prevent.
##
##   SHADOWS have no continuous parameter: a shadow is cast or it is not. So the
##   switch flips at the midpoint, where it lands against a frame that is already
##   half-way to somewhere else rather than against either look at full strength.
static func blend(from: LightingPreset, to: LightingPreset, t: float) -> LightingPreset:
	var result := LightingPreset.new()
	var k := clampf(t, 0.0, 1.0)
	# A blend reports the preset it is BECOMING, so target_preset_id() and any
	# readout stay meaningful for the whole of the fade.
	result.id = to.id
	result.display_name = to.display_name
	result.sun_energy = lerpf(from.sun_energy, to.sun_energy, k)
	result.sun_color = from.sun_color.lerp(to.sun_color, k)
	result.sun_angle_degrees = lerpf(from.sun_angle_degrees, to.sun_angle_degrees, k)
	result.shadows_enabled = to.shadows_enabled if k >= 0.5 else from.shadows_enabled
	result.ambient_color = from.ambient_color.lerp(to.ambient_color, k)
	result.ambient_energy = lerpf(from.ambient_energy, to.ambient_energy, k)
	result.fog_enabled = from.fog_enabled or to.fog_enabled
	result.fog_color = from.fog_color.lerp(to.fog_color, k)
	result.fog_density = lerpf(
		from.fog_density if from.fog_enabled else 0.0,
		to.fog_density if to.fog_enabled else 0.0,
		k
	)
	result.fog_light_energy = lerpf(from.fog_light_energy, to.fog_light_energy, k)
	# The window travels with the fade. Two presets whose windows differ would
	# otherwise snap the whole depth ramp at the midpoint -- every distant tree
	# in the frame changing colour in one tick, which is the pop the crossfade
	# exists to prevent.
	result.fog_depth_begin = lerpf(from.fog_depth_begin, to.fog_depth_begin, k)
	result.fog_depth_end = lerpf(from.fog_depth_end, to.fog_depth_end, k)
	result.fog_sky_affect = lerpf(from.fog_sky_affect, to.fog_sky_affect, k)
	result.sky_zenith_color = from.sky_zenith_color.lerp(to.sky_zenith_color, k)
	result.sky_horizon_color = from.sky_horizon_color.lerp(to.sky_horizon_color, k)
	result.sky_curve = lerpf(from.sky_curve, to.sky_curve, k)
	result.sky_energy = lerpf(from.sky_energy, to.sky_energy, k)
	# Volumetric air, on the same rule as the fog switch above: on the moment
	# either end wants it, with the density carrying the fade, because volumetric
	# fog off IS volumetric fog at density zero.
	result.volumetric_fog_enabled = from.volumetric_fog_enabled or to.volumetric_fog_enabled
	result.volumetric_fog_density = lerpf(
		from.volumetric_fog_density if from.volumetric_fog_enabled else 0.0,
		to.volumetric_fog_density if to.volumetric_fog_enabled else 0.0,
		k
	)
	result.volumetric_fog_albedo = from.volumetric_fog_albedo.lerp(to.volumetric_fog_albedo, k)
	result.volumetric_fog_anisotropy = lerpf(
		from.volumetric_fog_anisotropy, to.volumetric_fog_anisotropy, k)
	result.volumetric_fog_ambient_inject = lerpf(
		from.volumetric_fog_ambient_inject, to.volumetric_fog_ambient_inject, k)
	result.world_light_color = from.world_light_color.lerp(to.world_light_color, k)
	result.world_light_strength = lerpf(from.world_light_strength, to.world_light_strength, k)
	result.glow_enabled = from.glow_enabled or to.glow_enabled
	result.glow_strength = lerpf(
		from.glow_strength if from.glow_enabled else 0.0,
		to.glow_strength if to.glow_enabled else 0.0,
		k
	)
	result.cel_band_threshold = lerpf(from.cel_band_threshold, to.cel_band_threshold, k)
	result.cel_band_softness = lerpf(from.cel_band_softness, to.cel_band_softness, k)
	result.tonemap_exposure = lerpf(from.tonemap_exposure, to.tonemap_exposure, k)
	result.warm_accent_energy = lerpf(from.warm_accent_energy, to.warm_accent_energy, k)
	return result


## The only place anything is written to the Environment or the sun.
func _write(look: LightingPreset) -> void:
	_active = look
	var env := environment
	if env != null:
		env.ambient_light_color = look.ambient_color
		env.ambient_light_energy = look.ambient_energy
		env.tonemap_exposure = look.tonemap_exposure
		env.fog_enabled = look.fog_enabled
		env.fog_light_color = look.fog_color
		env.fog_light_energy = look.fog_light_energy
		env.fog_density = look.fog_density
		env.fog_depth_begin = look.fog_depth_begin
		env.fog_depth_end = look.fog_depth_end
		env.fog_sky_affect = look.fog_sky_affect
		env.glow_enabled = look.glow_enabled
		env.glow_intensity = look.glow_strength
		env.volumetric_fog_enabled = look.volumetric_fog_enabled
		env.volumetric_fog_density = look.volumetric_fog_density
		env.volumetric_fog_albedo = look.volumetric_fog_albedo
		env.volumetric_fog_anisotropy = look.volumetric_fog_anisotropy
		env.volumetric_fog_ambient_inject = look.volumetric_fog_ambient_inject
		# For the same reason ambient_light_sky_contribution is 0: the sky is a
		# backdrop nobody can see at any framing this game uses, and it has no
		# business being a light source. Measured, in case it looks like
		# superstition: it moves nothing in the current frame either way.
		env.volumetric_fog_sky_affect = 0.0
		# The froxel volume is 64 m deep by default and the farmstead starts at
		# about 69 m from an orthographic camera 90 m back, so at the default
		# length the volumetric fog is entirely BEHIND the near plane of its own
		# volume and does nothing at all. It has to reach the end of the depth
		# window, plus a margin for the far corners of a wide frame.
		env.volumetric_fog_length = look.fog_depth_end + 20.0
		env.background_energy_multiplier = look.sky_energy
	if _sky_material != null:
		_sky_material.sky_top_color = look.sky_zenith_color
		_sky_material.sky_horizon_color = look.sky_horizon_color
		_sky_material.sky_curve = look.sky_curve
		# Below the horizon is the ground plane's own colour rather than a
		# default brown: nothing in this game is ever above the horizon line, so
		# the lower dome only ever shows through as fog and as the sliver past
		# the plane's edge in a very wide shot.
		_sky_material.ground_horizon_color = look.sky_horizon_color
		_sky_material.ground_bottom_color = look.sky_zenith_color
		_sky_material.ground_curve = look.sky_curve
	# The world's two cel shaders. The ground pulls these itself every frame
	# (TerrainRenderer._process); every solid is reached here, because a
	# CelPainter is a RefCounted nobody keeps a reference to.
	CelPainter.set_world_shading(
		look.cel_band_threshold, look.cel_band_softness, tint_for(look)
	)
	if _sun == null:
		return
	_sun.rotation = Vector3(
		deg_to_rad(-look.sun_angle_degrees),
		deg_to_rad(sun_azimuth_degrees),
		0.0
	)
	# The cel shaders read ATTENUATION, not LIGHT_COLOR, so both of these reach
	# the character and nothing else in the frame. Set anyway, and correctly:
	# the character is the one thing here that IS lit by a light.
	_sun.light_color = look.sun_color
	_sun.light_energy = look.sun_energy
	_sun.shadow_enabled = look.shadows_enabled


# --- the clock drives it ----------------------------------------------------

func set_event_bus(bus) -> void:
	_detach_bus()
	_bus = bus
	_attach_bus()


func _attach_bus() -> void:
	if _bus == null and is_inside_tree():
		_bus = get_node_or_null("/root/EventBus")
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.subscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_subscribed = true


func _detach_bus() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_DAY_STARTED, _on_day_started)
	_bus.unsubscribe(EVENT_NIGHT_STARTED, _on_night_started)
	_subscribed = false


# EventBus always calls back with exactly one argument, so the day number is
# named even where it would otherwise be dropped.
func _on_day_started(payload) -> void:
	_change_to(int(payload), false)


func _on_night_started(payload) -> void:
	_change_to(int(payload), true)


## A day the schedule does not have leaves the frame exactly where it is. Silent
## on purpose: the clock cannot emit one, and a push_warning here would fire from
## any test that pokes the bus.
func _change_to(day: int, night: bool) -> void:
	var pair: Array = _days.get(day, [])
	if pair.size() != 2:
		return
	crossfade_to(pair[1] if night else pair[0])


# --- the debug controls -----------------------------------------------------
#
# Art Bible section 4.2's six hotkeys and section 4.3's slider panel. Debug
# builds only -- OS.is_debug_build() is false in an exported build -- and the
# panel is built the first time it is asked for and never before, so nothing
# that renders a frame unattended ever has it in shot.
#
# The hotkeys are a debug OVERRIDE, not a mode: the next phase change crossfades
# away from whatever was forced, which is correct. They exist to answer "what
# does this scene look like at midnight" without playing four days to find out.

const _HOTKEYS := {
	KEY_BACKSPACE: &"flat",
	KEY_F2: &"nightfall",
	KEY_F3: &"deep_night",
	KEY_F4: &"whiteout",
	KEY_F5: &"sunrise",
	KEY_F6: &"pale_day",
}


func _unhandled_key_input(event: InputEvent) -> void:
	if not debug_controls_enabled or not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F1:
		_toggle_panel()
		get_viewport().set_input_as_handled()
		return
	if not _HOTKEYS.has(key.keycode):
		return
	apply_preset(_HOTKEYS[key.keycode])
	if _panel != null:
		_panel.sync()
	get_viewport().set_input_as_handled()


func _toggle_panel() -> void:
	if _panel == null:
		_panel = LightingDebugPanel.new()
		add_child(_panel)
		(_panel as LightingDebugPanel).attach(self)
		return
	var panel := _panel as CanvasLayer
	panel.visible = not panel.visible
	if panel.visible:
		(_panel as LightingDebugPanel).sync()
