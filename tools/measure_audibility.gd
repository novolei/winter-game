extends Node

## What every positional sound in the game actually arrives at, in dB on the bus
## it plays to, at a distance a player really hears it from.
##
##   Godot_console.exe --path <project> --headless res://tools/measure_audibility.tscn
##
## THIS IS THE INSTRUMENT THAT WAS MISSING. Until it existed the strongest audio
## assertion available was `is_playing()`, which says the server accepted the
## playback and says nothing about whether a sample reached the output -- and
## every crow caw in the repository measured -200.00 dB with `playing == true`
## for the whole time it had been shipped (briefing trap 19).
##
## Kept as a committed tool rather than a throwaway probe because re-levelling is
## not a one-off: any change to `boom_length`, to a `carry_m`, to a bed gain or
## to the listener has to be able to print this table again.
##
## The suite has its own copy of the measurement in `tests/framework/audio_meter.gd`
## and asserts the parts that do not need a whole scene.

const FRAME := 1.0 / 60.0

## Where each source is heard from in ordinary play. Not worst cases -- typical
## ones, because a level chosen against a worst case is wrong everywhere else.
##
## The crow: on a wire eight metres up, the player somewhere under or near it.
## The dog: loose in the yard. The hearth: the room it is in.
const AT_M := {
	"crow": 12.0,
	"dog": 18.0,
	"fire": 6.0,
}

var _main: Node = null
var _player: Node3D = null
var _ear: Node3D = null


func _ready() -> void:
	for _i in range(4):
		await get_tree().process_frame
	_main = get_node_or_null("Main")
	_player = _main.get_node_or_null("Player") as Node3D
	var settle := 0.0
	while settle < 6.0:
		await get_tree().process_frame
		settle += FRAME
	_report_ear()
	await _report_bed()
	await _report_sources()
	print("PROBE DONE")
	get_tree().quit()


func _report_ear() -> void:
	print("=== WHERE THE EAR IS ===")
	var viewport := get_viewport()
	var listener := viewport.get_audio_listener_3d()
	var camera := viewport.get_camera_3d()
	print("AudioListener3D current : %s" % (str(listener.get_path()) if listener != null else "<none>"))
	print("Camera3D                : %s" % (str(camera.get_path()) if camera != null else "<none>"))
	_ear = listener if listener != null else camera
	print("ear at                  : %s" % str(_ear.global_position))
	print("player at               : %s" % str(_player.global_position))
	print("EAR-TO-PLAYER           : %.2f m" % _ear.global_position.distance_to(_player.global_position))
	print("camera-to-player        : %.2f m" % camera.global_position.distance_to(_player.global_position))
	var director := _main.get_node_or_null("Ambience")
	if director != null:
		print("AmbienceDirector.listener_position() : %s" % str(director.listener_position()))
		print("AmbienceDirector.emitter_position()  : %s  (%.2f m from the ear)" % [
			str(director.emitter_position()),
			director.emitter_position().distance_to(_ear.global_position),
		])


func _report_bed() -> void:
	print("")
	print("=== THE BED, which is the ground everything else is levelled against ===")
	var bed: float = await _peak(1.5)
	print("ambience bed on Master  : %8.2f dB" % bed)
	var director := _main.get_node_or_null("Ambience")
	if director != null and director.has_method("bed_level"):
		print("director.bed_level()    : %8.4f (linear, loudest layer)" % director.bed_level())


func _report_sources() -> void:
	print("")
	print("=== EACH SOURCE, at the distance it is usually heard from ===")
	print("(measured against a floor with the ambience bus muted, so each figure")
	print(" is the source alone; the 'over bed' column is what a player hears)")
	var bed_live: float = await _peak(1.0)
	AudioServer.set_bus_mute(_bus("Ambience"), true)
	var quiet: float = await _peak(1.0)
	print("floor with ambience muted : %.2f dB   |   bed alone : %.2f dB" % [quiet, bed_live])
	print("")
	print("%-34s %8s %8s %8s %9s" % ["source (gain, unit, carry)", "dist", "peak", "vs floor", "vs bed"])
	# The crow, exactly as CrowCalls builds it.
	await _one("crow caw", "res://assets/audio/wildlife/crow/crow_caw_01.wav",
		0.0, 8.0, 60.0, AT_M["crow"], quiet, bed_live)
	# The dog, exactly as AnimalVoice builds it from data/audio/dog_voice.tres.
	var dog := load("res://data/audio/dog_voice.tres")
	for entry in dog.calls:
		if entry == null or entry.stream_paths.is_empty():
			continue
		var path: String = entry.stream_paths[0]
		if not ResourceLoader.exists(path):
			print("%-34s   (no audio on disk)" % String(entry.call_id))
			continue
		await _one(String(entry.call_id), path,
			entry.gain_db, entry.unit_size, entry.carry_m, AT_M["dog"], quiet, bed_live)
	# The hearth.
	var map := load("res://data/audio/ambience.tres")
	var fire_path: String = map.fire_stream() if map.has_method("fire_stream") else ""
	if fire_path != "" and ResourceLoader.exists(fire_path):
		await _one("hearth", fire_path, map.fire_gain_db, map.fire_unit_size,
			map.fire_audible_m, AT_M["fire"], quiet, bed_live)
	AudioServer.set_bus_mute(_bus("Ambience"), false)


func _one(label: String, path: String, gain_db: float, unit_size: float,
		carry_m: float, at_m: float, floor_db: float, bed_db: float) -> void:
	var stream := ResourceLoader.load(path) as AudioStream
	if stream == null:
		print("%-34s   (failed to load)" % label)
		return
	var voice := AudioStreamPlayer3D.new()
	voice.bus = &"Master"
	voice.stream = stream
	voice.volume_db = gain_db
	voice.unit_size = unit_size
	voice.max_distance = carry_m
	add_child(voice)
	# Placed at `at_m` from the EAR, along the ear-to-player axis, which is the
	# direction a source near the player actually lies in.
	var toward := (_player.global_position - _ear.global_position).normalized()
	voice.global_position = _ear.global_position + toward * at_m
	voice.play()
	var peak: float = await _peak(0.9)
	print("%-34s %7.1fm %8.2f %8.2f %9.2f" % [
		"%s (%.1f dB, u%.0f, %.0fm)" % [label, gain_db, unit_size, carry_m],
		at_m, peak, peak - floor_db, peak - bed_db,
	])
	voice.stop()
	voice.queue_free()
	await get_tree().process_frame


func _bus(name: String) -> int:
	var found := AudioServer.get_bus_index(name)
	return found if found >= 0 else 0


func _peak(seconds: float) -> float:
	var peak := -200.0
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += FRAME
		peak = maxf(peak, AudioServer.get_bus_peak_volume_left_db(0, 0))
	return peak
