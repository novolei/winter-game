extends Node

## Fixed-camera evidence for the snow a bird loosens from a live surface.
## The default is the swaying wire; `--surface eave` runs the same real landing
## and take-off against the farmhouse receiver. The main scene, Bird timelines,
## PerchPoints, snow receivers and WindSway are all production objects. This
## tool only fixes the seed, one perch, one bird, camera and crosswind.

const SETTLE_FRAMES := 12
# The current crow approach is intentionally slow: the last third decelerates
# before the flare. Twenty seconds used to cover the older take, but now cuts it
# off a few metres above the span on a stable 60 Hz capture. Keep a real arrival
# and give that authored deceleration enough room instead of teleporting the bird.
const MAX_APPROACH_FRAMES := 1800
const MAX_SETTLE_FRAMES := 360
const MAX_LAUNCH_FRAMES := 240
const EFFECT_CLEAR_FRAMES := 96
const DEFAULT_CAMERA_SIZE_M := 17.0
const CAMERA_DISTANCE_M := 32.0
const WIND_STRENGTH := 0.42
const LANDING_OFFSETS := [0, 4, 10, 20, 34]
const TAKEOFF_OFFSETS := [0, 5, 12, 22, 36]

var _out := ""
var _seed := 417
var _camera_size := DEFAULT_CAMERA_SIZE_M
var _hide_weather := false
var _surface_kind := "wire"
var _wire: Node3D = null
var _perches: PerchPoints = null
var _flock: BirdFlock = null
var _camera: Camera3D = null
var _target: Dictionary = {}
var _wire_rest := Vector3.ZERO
var _previous_emissions := {"grains": 0, "mist": 0}
var _reported_output_size := false


func _ready() -> void:
	# Make every offset below a real 1/60-second visual step on fast GPUs. Without
	# a cap this tool can render 140+ frames per second while Bird correctly uses
	# wall-time delta, so the old frame guard expires before the authored approach.
	Engine.max_fps = 60
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out", "")
	_seed = int(_arg(args, "--seed", "417"))
	_camera_size = maxf(float(_arg(args, "--ortho", str(DEFAULT_CAMERA_SIZE_M))), 1.0)
	_hide_weather = args.has("--hide-weather")
	_surface_kind = _arg(args, "--surface", "wire").to_lower()
	if _surface_kind != "wire" and _surface_kind != "eave":
		_fail("--surface must be wire or eave")
		return
	if _out == "":
		_fail("--out is required")
		return
	if not _out.is_absolute_path():
		_out = ProjectSettings.globalize_path(_out)
	var made := DirAccess.make_dir_recursive_absolute(_out)
	if made != OK and made != ERR_ALREADY_EXISTS:
		_fail("cannot create output directory %s (error %d)" % [_out, made])
		return
	call_deferred("_run")


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _run() -> void:
	for _frame in range(SETTLE_FRAMES):
		await _draw_frame()
	if not _resolve_scene():
		return
	if not _choose_perch():
		return
	_prepare_world()
	_prepare_camera()
	await _draw_frame()
	_save("baseline-%s.png" % _surface_kind)

	print("capture_wire_bird_snow: renderer=%s adapter=%s seed=%d" % [
		RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(),
		_seed,
	])
	print("capture_wire_bird_snow: surface=%s fixed camera size %.2f m at %s; ambient weather %s" % [
		_surface_kind,
		_camera_size,
		_camera.global_position.snapped(Vector3(0.001, 0.001, 0.001)),
		"hidden" if _hide_weather else "visible",
	])
	_report_point("before arrival")
	_report_particles("before arrival")

	var created := _flock.arrive_now()
	if created != 1:
		_fail("expected one naturally approaching bird, got %d" % created)
		return
	var previous_feet := false
	var landing_found := false
	for _frame in range(MAX_APPROACH_FRAMES):
		await _draw_frame()
		var bird := _bird()
		if bird == null:
			if _frame % 120 == 0:
				print("capture_wire_bird_snow: approach frame=%d bird=none count=%d" % [
					_frame, _flock.bird_count(),
				])
			continue
		if _frame % 120 == 0:
			print("capture_wire_bird_snow: approach frame=%d inbound=%s landing=%s settling=%s perched=%s gap=%.3fm travelled=%.3fm" % [
				_frame, bird.is_inbound(), bird.is_landing(), bird.is_settling(), bird.is_perched(),
				bird.where().distance_to(_live_target()), bird.travelled(),
			])
		var feet := bird.has_feet_down()
		if feet and not previous_feet:
			landing_found = true
			_report_point("landing edge")
			_report_particles("landing edge")
			await _capture_offsets("landing", LANDING_OFFSETS)
			break
		previous_feet = feet
	if not landing_found:
		_fail("the bird never put its feet on the %s" % _surface_kind)
		return

	var settled := false
	for _frame in range(MAX_SETTLE_FRAMES):
		var bird := _bird()
		if bird != null and bird.is_perched():
			settled = true
			break
		await _draw_frame()
	if not settled:
		_fail("the %s landing never settled into the perched state" % _surface_kind)
		return
	for _frame in range(EFFECT_CLEAR_FRAMES):
		await _draw_frame()
	_save("perched-before-startle.png")

	var left := _flock.scatter(BirdFlock.CAUSE_PLAYER)
	if left != 1:
		_fail("expected one perched bird to scatter, got %d" % left)
		return
	previous_feet = true
	var takeoff_found := false
	for _frame in range(MAX_LAUNCH_FRAMES):
		await _draw_frame()
		var bird := _bird()
		if bird == null:
			break
		var feet := bird.has_feet_down()
		if previous_feet and not feet:
			takeoff_found = true
			_report_point("take-off edge")
			_report_particles("take-off edge")
			await _capture_offsets("takeoff", TAKEOFF_OFFSETS)
			break
		previous_feet = feet
	if not takeoff_found:
		_fail("the bird never lifted its feet from the %s" % _surface_kind)
		return

	print("capture_wire_bird_snow: complete -- %s" % _out)
	get_tree().quit()


func _resolve_scene() -> bool:
	var host_path := "Main/Farmstead/Wires/WireToTruckPole"
	if _surface_kind == "eave":
		host_path = "Main/Farmhouse/EaveSnowShed"
	_wire = get_node_or_null(host_path) as Node3D
	_perches = get_node_or_null(host_path.path_join("Perches")) as PerchPoints
	_flock = get_node_or_null("Main/Crows") as BirdFlock
	if _wire == null or _perches == null or _flock == null:
		_fail("main scene is missing the %s snow host/Perches or Crows" % _surface_kind)
		return false
	for receiver in [&"receive_perch_landing", &"receive_perch_departure",
		&"emission_totals", &"last_burst_position"]:
		if not _wire.has_method(receiver):
			_fail("the %s snow host did not load receiver method %s" % [_surface_kind, receiver])
			return false
	var particle_nodes := _wire.find_children("*", "GPUParticles3D", true, false)
	if particle_nodes.size() < 2:
		_fail("the %s snow host built only %d of its two particle systems" % [
			_surface_kind, particle_nodes.size(),
		])
		return false
	return true


func _choose_perch() -> bool:
	var offered := _perches.perches()
	if offered.is_empty():
		_fail("the %s offered no live perches" % _surface_kind)
		return false
	var centre := Vector3.ZERO
	for value in offered:
		centre += value.get("at", Vector3.ZERO) as Vector3
	centre /= float(offered.size())
	var best_gap := INF
	for value in offered:
		var perch: Dictionary = value
		var gap := (perch.get("at", Vector3.ZERO) as Vector3).distance_squared_to(centre)
		if gap < best_gap:
			best_gap = gap
			_target = perch.duplicate(true)
	_wire_rest = _wire.global_position
	return not _target.is_empty()


func _prepare_world() -> void:
	# WireSnow uses the global random stream only to distribute individual grains
	# within its fixed profile. Seed that stream too, so renderer A/B evidence is
	# the same physical burst rather than two equally valid random puffs.
	seed(_seed)
	var pigeons := get_node_or_null("Main/Pigeons") as BirdFlock
	if pigeons != null:
		pigeons.enabled = false
	var startle := get_node_or_null("Main/StartleShot") as Node
	if startle != null:
		startle.process_mode = Node.PROCESS_MODE_DISABLED

	# Keep the production sway process running, but freeze its weather producer
	# and feed one repeatable crosswind through the same public hooks.
	var wind := get_node_or_null("Main/Wind") as Node
	if wind != null:
		wind.set_process(false)
	var spindrift := get_node_or_null("Main/Wind/Spindrift") as Node3D
	if spindrift != null:
		spindrift.visible = false
	if _hide_weather:
		var snowfall := get_node_or_null("Main/Snowfall") as Node3D
		if snowfall != null:
			snowfall.visible = false
			snowfall.process_mode = Node.PROCESS_MODE_DISABLED
	var sway := get_node_or_null("Main/Wind/WireSway") as Node
	var local_facing: Vector3 = _target.get("local_facing", Vector3(0.0, 0.0, -1.0))
	var axis := (_perches.placement().basis * local_facing).normalized()
	var crosswind := Vector3(-axis.z, 0.0, axis.x).normalized()
	if sway != null:
		sway.call("set_wind", crosswind)
		sway.call("set_wind_strength", WIND_STRENGTH)

	var watcher := Node3D.new()
	watcher.name = "FarWatcher"
	watcher.position = Vector3(1000.0, 0.0, 1000.0)
	add_child(watcher)
	_flock.enabled = true
	_flock.fewest = 1
	_flock.most = 1
	_flock.flush_radius_m = 0.0
	_flock.stagger_seconds = 0.0
	_flock.random_seed = _seed
	_flock.set_watched(watcher)
	_flock.set_perches([_target])
	_flock.set_wind(crosswind)
	_flock.set_wind_strength(WIND_STRENGTH)
	_flock.attach()


func _prepare_camera() -> void:
	var rig := get_node_or_null("Main/CameraRig") as Node3D
	var game_camera := get_node_or_null("Main/CameraRig/Camera3D") as Camera3D
	if rig != null:
		rig.set_process(false)
	if game_camera != null:
		game_camera.current = false
	_camera = Camera3D.new()
	_camera.name = "WireSnowCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _camera_size
	_camera.near = 0.05
	_camera.far = 200.0
	add_child(_camera)
	var basis := Basis.IDENTITY
	if rig != null:
		basis = rig.global_basis.orthonormalized()
	var target := _live_target()
	_camera.global_transform = Transform3D(
		basis, target + basis.z.normalized() * CAMERA_DISTANCE_M
	)
	_camera.current = true


func _capture_offsets(prefix: String, offsets: Array) -> void:
	var elapsed := 0
	for index in range(offsets.size()):
		var offset: int = int(offsets[index])
		for _frame in range(maxi(offset - elapsed, 0)):
			await _draw_frame()
		elapsed = offset
		var milliseconds := roundi(float(offset) * 1000.0 / 60.0)
		_save("%s-%02d-%04dms.png" % [prefix, index, milliseconds])


func _draw_frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save(name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		_fail("viewport returned no image for %s" % name)
		return
	if not _reported_output_size:
		_reported_output_size = true
		print("capture_wire_bird_snow: output_pixels=%s logical_viewport=%s" % [
			image.get_size(), get_viewport().get_visible_rect().size,
		])
	var path := _out.path_join(name)
	var saved := image.save_png(path)
	if saved != OK:
		_fail("could not save %s (error %d)" % [path, saved])
		return
	print("capture_wire_bird_snow: wrote %s" % path)


func _bird() -> Bird:
	if _flock == null:
		return null
	var birds := _flock.birds()
	return null if birds.is_empty() else birds[0]


func _live_target() -> Vector3:
	if _perches == null or _target.is_empty():
		return Vector3.ZERO
	var local: Vector3 = _target.get("local", Vector3.ZERO)
	return _perches.placement() * local


func _report_point(label: String) -> void:
	var stale: Vector3 = _target.get("at", Vector3.ZERO)
	var live := _live_target()
	var bird := _bird()
	var bird_at := bird.where() if bird != null else Vector3.INF
	var screen := _camera.unproject_position(live) if _camera != null else Vector2.ZERO
	var burst_gap := -1.0
	var has_burst := false
	if _wire.has_method("emission_totals"):
		var totals: Dictionary = _wire.call("emission_totals")
		has_burst = int(totals.get("grains", 0)) + int(totals.get("mist", 0)) > 0
	if has_burst and _wire.has_method("last_burst_position"):
		var last: Vector3 = _wire.call("last_burst_position")
		burst_gap = last.distance_to(live)
	var live_anchor := burst_gap >= 0.0 and burst_gap <= 0.03
	print("capture_wire_bird_snow: %s surface=%s live=%s stale_gap=%.4fm surface_motion=%s bird_gap=%s burst_gap=%s live_anchor=%s screen=(%.1f, %.1f)" % [
		label,
		_surface_kind,
		live.snapped(Vector3(0.0001, 0.0001, 0.0001)),
		live.distance_to(stale),
		(_wire.global_position - _wire_rest).snapped(Vector3(0.0001, 0.0001, 0.0001)),
		"n/a" if bird == null else "%.4fm" % bird_at.distance_to(live),
		"n/a" if burst_gap < 0.0 else "%.4fm" % burst_gap,
		"n/a" if burst_gap < 0.0 else ("yes" if live_anchor else "NO"),
		screen.x,
		screen.y,
	])


func _report_particles(label: String) -> void:
	var found := 0
	for child in _wire.find_children("*", "GPUParticles3D", true, false):
		var particles := child as GPUParticles3D
		if particles == null:
			continue
		found += 1
		print("capture_wire_bird_snow: %s particle=%s amount=%d lifetime=%.3f emitting=%s world_scale=%s" % [
			label, particles.name, particles.amount, particles.lifetime, particles.emitting,
			particles.global_basis.get_scale().snapped(Vector3(0.001, 0.001, 0.001)),
		])
	var totals := {}
	if _wire.has_method("emission_totals"):
		totals = _wire.call("emission_totals")
	var burst_delta := {"grains": 0, "mist": 0}
	if not totals.is_empty():
		burst_delta = {
			"grains": int(totals.get("grains", 0)) - int(_previous_emissions.get("grains", 0)),
			"mist": int(totals.get("mist", 0)) - int(_previous_emissions.get("mist", 0)),
		}
		_previous_emissions = totals.duplicate()
	print("capture_wire_bird_snow: %s particle_nodes=%d burst_delta=%s manual_emissions=%s" % [
		label, found, burst_delta, totals,
	])


func _fail(message: String) -> void:
	push_error("capture_wire_bird_snow: %s" % message)
	get_tree().quit(1)
