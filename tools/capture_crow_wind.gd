extends Node

## Photographs perched crows through a real squall, and MEASURES how far each
## bird is from the wire it is standing on.
##
##   Godot_console.exe --path <project> --fixed-fps 60 --resolution 1600x1000 \
##       res://tools/capture_crow_wind.tscn -- --out D:/somewhere/crow-wind
##
## Writes `<out>-00.png` .. and prints, per shot, the wind strength, how far the
## middle wire has been carried off its rest, and per bird:
##
##   ON WIRE   the perpendicular distance from the crow to the line of the span
##             it is gripping. THE NUMBER THE FIX EXISTS TO KEEP AT ZERO.
##   ONCE      the same distance measured from where the bird was standing WHEN
##             IT LANDED -- what a perch sampled once and cached would have left
##             on screen. Both columns come out of one run, so the before and the
##             after are the same shot of the same birds in the same weather,
##             which is the only way the briefing accepts a comparison.
##
## The distance is to the WIRE ITSELF -- `placement().origin` and its own -Z --
## not to the perch the crow is holding. Measuring against the perch would be
## measuring the fix with the fix's own arithmetic and would read zero however
## broken it was.
##
## THE WIND IS SET, NOT FORCED. `WindSystem.strength_at` is a pure function of t,
## so a squall can be found by arithmetic (`tools/_probe_wind.gd`, thrown away)
## and then watched at 1x with every consumer lagging the way it will in play.
## `wind_valley` crosses the crows' 0.75 threshold at t = 83.18 and peaks at
## 0.799; --at 76 opens the sequence seven seconds before that, while the birds
## are still sitting.
##
## ONLY SPAN PERCHES ARE OFFERED, and only spans are measured. A crossarm perch
## is a point on the pole, the pole is not in the `wind_sway` group, and it does
## not move -- so a bird on one is not evidence either way. Measured the other way
## first and every crossarm bird reported a 7.97 m "gap", which is just its height
## above the pole's own axis: an instrument that answers confidently about the
## wrong question.
##
## The gap columns are running maxima taken EVERY FRAME, not at the shutter. The
## sway is a 1.9 s sine and the shots are half a second apart, so sampling at the
## shutter catches four phases out of the travel and reports whatever it happened
## to land on -- shot 08 caught the wire 3 mm from rest.
##
##   --out <prefix>     required
##   --at <seconds>     where to start the wind's own clock (default 76)
##   --shots <n>        how many frames (default 24)
##   --every <seconds>  between shots (default 0.5)
##   --preset <id>      the sky (default pale_day, which is wind_valley's own)
##   --stop <metres>    orthographic size (default 10.5, the tight stop)
##   --hold             raise the scatter threshold out of reach, so the birds sit
##                      through the whole squall and the ride can be measured
##                      across the wire's full travel

## Where the camera looks: the one place in the valley where the pole and all
## three wires share a frame. Same numbers as `tools/capture_crows.gd`, so the
## two sets of frames are of the same shot.
const LOOK_AT := Vector2(5.6, 12.0)
const LOOK_HEIGHT := 4.6
const NEAR_M := 11.0

## Long enough for `Farmstead._ready()` to have settled the pole onto the snow
## and strung the wires between whatever it and the house settled at.
const SETTLE_FRAMES := 40

var _out := ""
var _at := 76.0
var _shots := 24
var _every := 0.5
var _preset := "pale_day"
var _stop := 10.5
var _hold := false

var _frame := 0
var _shot := 0
var _next := 0.0
var _clock := 0.0
var _done := false
var _started := false
var _flock: CrowFlock = null
var _camera: Camera3D = null
## crow instance id -> where it was standing the frame it landed.
var _landed: Dictionary = {}
## The middle wire, and where it was strung before the wind touched it.
var _wire: Node3D = null
var _wire_rest := Vector3.INF
## Worst case seen on ANY frame, not just at a shutter. See the header.
var _worst_ride := 0.0
var _worst_once := 0.0
var _worst_swing := 0.0
## Instantaneous, refreshed every frame and printed at the shutter.
var _now_ride := 0.0
var _now_once := 0.0
var _on_wire := 0
var _balancing := 0
var _aloft := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_at = float(_arg(args, "--at", "76"))
	_shots = int(_arg(args, "--shots", "24"))
	_every = float(_arg(args, "--every", "0.5"))
	_preset = _arg(args, "--preset", "pale_day")
	_stop = float(_arg(args, "--stop", "10.5"))
	_hold = args.has("--hold")
	if _out == "":
		push_error("capture_crow_wind: --out is required")
		get_tree().quit()


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _process(delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame < SETTLE_FRAMES:
		_aim()
		return
	if not _started:
		_start()
		return
	_aim()
	# EVERY FRAME, before the shutter test. The sway is a 1.9 s sine and the shots
	# are half a second apart; a worst case sampled at the shutter is a worst case
	# of four phases.
	_measure()
	_clock += delta
	if _clock < _next:
		return
	_next += _every
	if _shot >= _shots:
		_done = true
		get_tree().quit()
		return
	_capture()


func _start() -> void:
	_started = true
	_camera = get_node_or_null("Main/CameraRig/Camera3D") as Camera3D
	_flock = get_node_or_null("Main/Crows") as CrowFlock
	if _camera == null or _flock == null:
		push_error("capture_crow_wind: expected Main/CameraRig/Camera3D and Main/Crows")
		get_tree().quit()
		return

	var lighting := get_node_or_null("Main/Lighting")
	if lighting != null:
		lighting.apply_preset(StringName(_preset))

	# Straight onto the wind's clock, then one step of zero so the state and the
	# latches settle at the new time without publishing a minute of events we
	# skipped. Same manoeuvre as tools/capture_gust.gd.
	var wind = _service(&"wind")
	if wind != null:
		wind.set("_elapsed", _at)
		wind.advance(0.0)

	# Deterministic, landing now rather than on the game's own schedule, and
	# frightened of nothing -- so what empties the wire in these frames is the
	# weather and only the weather.
	_flock.random_seed = 20260812
	_flock.first_arrival_seconds = 0.0
	_flock.fewest = 5
	_flock.most = 5
	_flock.flush_radius_m = 0.0
	if _hold:
		# Out of reach of any wind this profile produces, so the birds sit through
		# the whole squall and the ride can be measured across the full travel.
		_flock.gust_scatter_strength = 2.0
	_frame_at(_stop)
	_aim()
	_flock.set_perches(_near_perches())
	print("capture_crow_wind: %d birds landed" % _flock.arrive_now())
	for crow in _crows():
		_landed[crow.get_instance_id()] = crow.where()

	_wire = get_node_or_null("Main/Farmstead/Wires/WireDrop") as Node3D
	var sway := get_node_or_null("Main/Wind/WireSway")
	if _wire != null and sway != null:
		# WireSway's own record of where each span was strung, before any sway.
		# Read rather than sampled, because by this frame it has already moved.
		var rest: Dictionary = sway.get("_rest")
		_wire_rest = rest.get(_wire.get_instance_id(), _wire.global_position)


func _capture() -> void:
	var wind = _service(&"wind")
	var strength := 0.0
	var elapsed := 0.0
	if wind != null:
		strength = wind.strength()
		elapsed = wind.elapsed()
	var swing := Vector3.ZERO
	if _wire != null and _wire_rest != Vector3.INF:
		swing = _wire.global_position - _wire_rest

	var path := "%s-%02d.png" % [_out, _shot]
	var image := get_viewport().get_texture().get_image()
	var directory := path.get_base_dir()
	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	image.save_png(path)

	print("shot %02d  t=%7.2f  str=%.3f  wire=%+.3f,%+.3f,%+.3f |%.3f|  wire %d(%d flapping) aloft %d  gap now %.4f/%.4f  worst %.4f/%.4f" % [
		_shot, elapsed, strength, swing.x, swing.y, swing.z, swing.length(),
		_on_wire, _balancing, _aloft, _now_ride, _now_once, _worst_ride, _worst_once])
	_shot += 1


## One frame of the measurement. Only birds gripping a SPAN count -- see header.
func _measure() -> void:
	_now_ride = 0.0
	_now_once = 0.0
	_on_wire = 0
	_balancing = 0
	_aloft = 0
	if _wire != null and _wire_rest != Vector3.INF:
		_worst_swing = maxf(_worst_swing, (_wire.global_position - _wire_rest).length())
	for crow in _crows():
		if not crow.is_on_the_wire():
			_aloft += 1
			continue
		var span := crow.anchor()
		if span == null or span.kind != PerchPoints.Kind.SPAN:
			continue
		_on_wire += 1
		if crow.is_balancing():
			_balancing += 1
		_now_ride = maxf(_now_ride, _off_the_line(crow.where(), span))
		var landed: Vector3 = _landed.get(crow.get_instance_id(), crow.where())
		_now_once = maxf(_now_once, _off_the_line(landed, span))
	_worst_ride = maxf(_worst_ride, _now_ride)
	_worst_once = maxf(_worst_once, _now_once)


## Perpendicular distance from a point to the infinite line of a span.
##
## The span's own transform, not the perch: `Farmstead._span()` puts the wire's
## origin at one anchor and aims its -Z at the other, so origin + t * (-Z) IS the
## wire. Measuring against the perch the crow is holding would be checking the
## fix with the fix's own arithmetic.
func _off_the_line(at: Vector3, span: PerchPoints) -> float:
	var placed := span.placement()
	var along := -placed.basis.z
	if along.length_squared() < 0.000001:
		return 0.0
	along = along.normalized()
	var offset := at - placed.origin
	return (offset - along * offset.dot(along)).length()


## Holds the camera on the pole. Re-applied every frame because the rig follows
## the player in its own `_process`, and a frame taken mid-ease is a frame of a
## different shot.
func _aim() -> void:
	var rig := get_node_or_null("Main/CameraRig") as Node3D
	if rig != null:
		rig.global_position = Vector3(LOOK_AT.x, LOOK_HEIGHT, LOOK_AT.y)


func _frame_at(ortho: float) -> void:
	var rig := get_node_or_null("Main/CameraRig")
	if rig == null:
		return
	rig.orthographic_size = ortho
	rig.refresh_framing()
	var tween: Tween = rig.framing_tween()
	if tween != null and tween.is_valid():
		tween.kill()
	rig.apply_framed_size(rig.framing_target())


## The declared perches near enough to the camera to be in shot, on a wire. This
## FILTERS the props' own list; it does not invent one, so every perch offered
## still carries the declaration that owns it and the birds still ride.
##
## Wires only, because the wires are the subject: the crossarm does not move, so
## a bird on it is neither evidence nor counter-evidence.
func _near_perches() -> Array:
	var spot := Vector3(LOOK_AT.x, 0.0, LOOK_AT.y)
	var offered := _flock.available_perches()
	var near: Array = []
	for perch in offered:
		var span := perch.get("anchor", null) as PerchPoints
		if span == null or span.kind != PerchPoints.Kind.SPAN:
			continue
		var at: Vector3 = perch["at"]
		if Vector2(at.x - spot.x, at.z - spot.z).length() <= NEAR_M:
			near.append(perch)
	print("capture_crow_wind: %d of %d perches are on a wire and within %.0f m of the camera" % [
		near.size(), offered.size(), NEAR_M])
	return near


func _crows() -> Array[Crow]:
	var found: Array[Crow] = []
	if _flock == null:
		return found
	for child in _flock.get_children():
		if child is Crow:
			found.append(child as Crow)
	return found


func _service(name: StringName):
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return null
	return registry.get_service(name)
