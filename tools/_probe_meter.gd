extends SceneTree

## Can the audibility instrument live INSIDE the test suite?
##
## The runner calls every test synchronously inside one `_process()` and cannot
## await a frame. So the question is whether the headless `Dummy` driver mixes on
## its own thread -- if it does, `OS.delay_msec()` is enough and the suite can
## assert "a sound occurred"; if it does not, the instrument must be a scene
## harness and the suite can only assert the geometry.
##
## Run from `_process()`, not `_initialize()`: briefing trap 1 -- `root` is not
## inside the tree yet during `_initialize()`, and an AudioStreamPlayer outside
## the tree refuses to play. **That is registered false-PASS class 5's actual
## mechanism**, and the first draft of this probe reproduced it by accident.

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	print("driver: %s   root.is_inside_tree()=%s" % [
		AudioServer.get_driver_name(), str(root.is_inside_tree()),
	])
	var stream := ResourceLoader.load("res://assets/audio/wildlife/crow/crow_caw_01.wav") as AudioStream
	print("stream length: %.3f s" % stream.get_length())

	# --- non-positional, the simplest possible case --------------------------
	var flat := AudioStreamPlayer.new()
	flat.bus = &"Master"
	flat.stream = stream
	root.add_child(flat)
	print("peak before play : %.2f dB" % AudioServer.get_bus_peak_volume_left_db(0, 0))
	flat.play()
	# NOTE: on 4.7.1 `play()` returns void -- so the registered "44 consecutive
	# true returns" cannot have been this call's return value. It was `playing`
	# / `is_playing()` reading true while the engine mixed nothing.
	print("play() called, playing=%s" % str(flat.playing))
	var best := -200.0
	for step in [25, 25, 50, 50, 100, 100, 200]:
		OS.delay_msec(step)
		var peak := AudioServer.get_bus_peak_volume_left_db(0, 0)
		best = maxf(best, peak)
		print("  +%4d ms (no frame): peak %8.2f dB  playing=%s" % [step, peak, str(flat.playing)])
	print("BEST over ~550 ms of pure wall clock, zero frames: %.2f dB" % best)
	print("")
	if best > -190.0:
		print(">>> THE DUMMY DRIVER MIXES ON ITS OWN THREAD.")
		print(">>> The instrument CAN live in the suite: play, delay, read the peak.")
	else:
		print(">>> The Dummy driver does NOT mix without a frame.")
		print(">>> The suite can assert geometry; audibility needs a scene harness.")
	flat.stop()
	flat.queue_free()
	return true
