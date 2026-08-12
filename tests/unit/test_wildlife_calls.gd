extends TestCase

## The owner's two wildlife takes, cut into calls -- and the gate on the half
## that was previously untestable, because the folder was empty.
##
## ---------------------------------------------------------------------------
## WHAT WAS IN THE TWO FILES
## ---------------------------------------------------------------------------
## Measured with Blender's audaspace (the only mp3 decoder on this machine) by
## `tools/cut_animal_calls.py`, which carries the full numbers in its header.
##
##   crow_raw.mp3   2.0434 s, 44100 Hz, dual mono in a stereo container.
##                  THREE caws with digital silence at each end, the third 4 dB
##                  down with a third the energy above 3 kHz -- the same bird
##                  further away. Cut to three files.
##
##   dog_raw.mp3    5.7379 s, 44100 Hz, true stereo, room tone throughout at
##                  -39.4 dBFS. Three barks, three whines, two whimpers, a yelp,
##                  a huff and some breath. **No growl** -- see the cutter's
##                  header for the band measurement that settles it.
##
##   dog_growl_raw  13.9755 s, 44100 Hz, near-dual-mono (L/R correlate 0.9989),
##   .mp3           room tone at -41.8 dBFS, 11 ms of head silence and a natural
##                  decay to digital silence at the tail. FIVE growl passages
##                  separated by the animal's own breaths, and a growl by
##                  measurement rather than by filename: 158 of 279 windows put
##                  60-250 Hz more than 15 dB over its own floor, the
##                  fundamental runs 145-200 Hz, and the 20-60 Hz rumble band
##                  that fooled nobody in the first file is empty here.
##
## ---------------------------------------------------------------------------
## THE CLAIM THIS FILE EXISTS TO CHECK
## ---------------------------------------------------------------------------
## `.superpowers/sdd/wave3/task-w3-startle-report.md` section 5 says the caw
## system shipped complete and silent, and that "drop files into
## `assets/audio/wildlife/crow/` and they play, with no `.gd` change". That is a
## claim about code nobody had been able to run, so it is checked here rather
## than trusted: `test_the_crow_system_plays_them_with_no_code_change` puts a
## real `CrowCalls` in the tree, runs a real burst, and asserts `is_playing()`.
##
## `play()` RETURNING TRUE IS NOT PROOF A SOUND PLAYED -- this project's fifth
## false-PASS was 44 successful `play()` calls the engine refused every one of,
## because an AudioStreamPlayer outside the tree cannot play. So: in the tree,
## and `is_playing()`.
##
## ---------------------------------------------------------------------------
## A DEFECT FOUND WHILE VERIFYING, LEFT FOR ITS OWNER
## ---------------------------------------------------------------------------
## `CrowCalls.call_count()` reports **6 for the 3 files on disk**. `calls()`
## walks `DirAccess.get_files()` and trims `.import` off each name, on the
## comment's belief that a source tree lists the asset and an exported build
## lists its companion. Running from source Godot lists **both**, so every caw
## is loaded and appended twice.
##
## Harmless in effect -- a uniform draw over duplicated entries is still uniform,
## the memory is three tiny WAVs, and an exported build lists only the `.import`
## so it self-corrects -- but `call_count()` is the number the startle report and
## its gate use to "say the honest number", and today it is double.
##
## The fix is one line (`if not found.has(path)`), and it is not made here:
## `crow_calls.gd` belongs to the bird work that is live, and briefing 4.5 says
## record somebody's in-flight file rather than edit it.
##
## So `test_every_stream_the_folder_yields_is_a_file_on_disk` measures the
## DISTINCT set. That neither hides the duplication nor fails on a file that is
## not mine to fix.

const CallsScript := preload("res://src/entities/wildlife/crow_calls.gd")
const CrowScript := preload("res://src/entities/wildlife/crow.gd")

const CROW_FOLDER := "res://assets/audio/wildlife/crow"
const DOG_FOLDER := "res://assets/audio/wildlife/dog"

## Zero crossings per second. Below this is a growl's register, above it is
## everything else this project has recorded. Measured, not chosen -- see
## `test_the_growl_slot_holds_something_that_is_actually_low`.
const GROWL_CROSSINGS := 1450.0

const FRAME := 1.0 / 60.0

var _calls: CrowCalls = null
var _birds: Array[Crow] = []


func before_each() -> void:
	_calls = CallsScript.new()
	_calls.random_seed = 4711
	_root().add_child(_calls)
	_calls.seed_rng()


func after_each() -> void:
	for crow in _birds:
		crow.free()
	_birds.clear()
	if _calls != null:
		for voice in _calls.voices():
			voice.stop()
		_root().remove_child(_calls)
		_calls.free()
		_calls = null


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _wavs_in(folder: String) -> Array[String]:
	var found: Array[String] = []
	var directory := DirAccess.open(folder)
	if directory == null:
		return found
	for name in directory.get_files():
		if name.to_lower().ends_with(".wav"):
			found.append("%s/%s" % [folder, name])
	found.sort()
	return found


func _some_birds(count: int) -> void:
	for index in range(count):
		var crow: Crow = CrowScript.new()
		crow.perch_on(Vector3(0.0, 6.0, float(index) * 2.0), Vector3(1.0, 0.0, 0.0))
		_birds.append(crow)


# --- the files themselves ----------------------------------------------------


## Three caws, not one compilation. The startle brief's rhythm is "one bird, then
## two overlapping, then a gap, then a last one already distant" -- four slots
## from at least two different birds, which a single 2 s file containing all
## three cannot serve at all.
func test_the_crow_take_was_cut_into_separate_calls() -> void:
	var files := _wavs_in(CROW_FOLDER)
	assert_eq(files.size(), 3, "expected three caws in %s, found %s" % [CROW_FOLDER, files])
	for path in files:
		assert_true(
			path.get_file().begins_with("crow_caw_"),
			"%s is not named crow_caw_NN.wav" % path
		)


func test_the_dog_take_was_cut_into_separate_calls() -> void:
	var files := _wavs_in(DOG_FOLDER)
	assert_true(files.size() >= 6, "expected at least six dog calls, found %d" % files.size())
	var families: Dictionary = {}
	for path in files:
		var name := path.get_file().trim_suffix(".wav")
		var parts := name.split("_")
		assert_true(parts.size() == 3, "%s is not named dog_<call>_NN.wav" % path)
		if parts.size() == 3:
			families[parts[1]] = true
	for wanted in ["bark", "whine", "whimper", "growl"]:
		assert_true(
			families.has(wanted),
			"the dog folder has no %s: %s" % [wanted, families.keys()]
		)


## Import settings, asserted rather than read off a `.import` file -- the
## `.import` is what Godot was ASKED for and this is what it produced.
##
## LOOPING IS THE ONE THAT MATTERS. A caw imported with a loop never stops: the
## emitter is claimed forever, `_free_voice()` never finds it idle, and the flock
## grows a voice per call until the pool is the size of the day. Nothing errors.
func test_no_call_loops_and_every_one_is_mono() -> void:
	var files := _wavs_in(CROW_FOLDER) + _wavs_in(DOG_FOLDER)
	assert_true(files.size() >= 9, "found only %d calls to check" % files.size())
	for path in files:
		var stream := ResourceLoader.load(path) as AudioStreamWAV
		assert_not_null(stream, "%s did not import as an AudioStreamWAV" % path)
		if stream == null:
			continue
		assert_eq(
			stream.loop_mode, AudioStreamWAV.LOOP_DISABLED,
			"%s imported with looping on -- it would never release its emitter" % path
		)
		# Mono, because these are played through AudioStreamPlayer3D and a stereo
		# stream has its own image to place before the engine places it in the
		# world. The crow take is dual mono anyway (L/R correlate at 1.0000); the
		# dog take is true stereo and the downmix cost 0.7 dB of RMS.
		assert_false(stream.stereo, "%s is stereo; a positional call should be mono" % path)
		assert_eq(stream.mix_rate, 44100, "%s resampled to %d Hz" % [path, stream.mix_rate])


## Long enough to be a call, short enough to be one call.
##
## ---------------------------------------------------------------------------
## A GROWL IS NOT AN EVENT AND IS NOT BOUNDED LIKE ONE
## ---------------------------------------------------------------------------
## A bark, a caw, a whine and a whimper are EVENTS: the animal does one, then
## stops, and a slice that ran past a second would mean the cut had swallowed the
## silence and the next call with it. That bound is real and it stays.
##
## A growl is a HELD ATTITUDE -- `DogAnimations.LOOPS` marks its take as looping
## for the same reason -- so the same bound applied to it would be measuring the
## wrong thing. Its own bound is the take: each slice has to be long enough to
## carry a 3.042 s animation cycle without a hole in the middle, and short enough
## that two consecutive cycles are not three dogs growling at once.
##
## This test was NOT loosened to let the growls through. It grew a second band,
## and both are tighter than one band wide enough for both would have been.
func test_every_call_is_one_call_long() -> void:
	for path in _wavs_in(CROW_FOLDER) + _wavs_in(DOG_FOLDER):
		var stream := ResourceLoader.load(path) as AudioStream
		assert_not_null(stream, path)
		if stream == null:
			continue
		var length := stream.get_length()
		if path.get_file().begins_with("dog_growl_"):
			assert_true(
				length > 1.5 and length < 4.5,
				"%s is %.3f s -- a growl has to cover a 3.042 s take cycle" % [path, length]
			)
			continue
		assert_true(
			length > 0.15 and length < 1.0,
			"%s is %.3f s -- a single call is a fifth of a second to a second" % [path, length]
		)


## A FILE NAMED GROWL IS NOT EVIDENCE.
##
## ---------------------------------------------------------------------------
## WHY THIS GATE EXISTS AT ALL
## ---------------------------------------------------------------------------
## The first dog take the owner supplied was believed to hold a growl and did
## not: measured, its 60-250 Hz band never rose more than 10.5 dB above its own
## floor, and the low energy it did have sat at 31-47 Hz -- mic rumble, present
## at the same level in the silent tail. The whole dog voice shipped one commit
## with `dog.growl` declared and silent on the strength of that measurement.
##
## So the growl slot is the one place in this project where "the filename says
## so" has already been wrong once, and it is the one that carries the warning
## mechanic. It gets a gate that reads the samples.
##
## ---------------------------------------------------------------------------
## ZERO CROSSINGS, BECAUSE GDSCRIPT HAS NO FFT AND DOES NOT NEED ONE
## ---------------------------------------------------------------------------
## A growl is phonation at 145-200 Hz; a bark sits at 800-2000 Hz and a caw
## higher still. Counting sign changes is the cheap form of that question, and
## measured across all sixteen calls it separates them completely:
##
##   growls          568, 739, 881, 938, 1213 crossings/s
##   everything else 1670 .. 4032
##
## The threshold below sits in the gap with 16% clear on one side and 15% on the
## other. It needs `compress/mode=0` in the `.import` -- QOA is not readable from
## GDScript -- which is why these sixteen files are PCM while the engine default
## is QOA. That is a second reason for a choice already worth making, since the
## sources are lossy mp3 and QOA would be a second lossy generation.
func test_the_growl_slot_holds_something_that_is_actually_low() -> void:
	var growls := 0
	for path in _wavs_in(CROW_FOLDER) + _wavs_in(DOG_FOLDER):
		var stream := ResourceLoader.load(path) as AudioStreamWAV
		assert_not_null(stream, path)
		if stream == null:
			continue
		assert_eq(
			stream.format, AudioStreamWAV.FORMAT_16_BITS,
			"%s is not 16-bit PCM, so its samples cannot be read here" % path
		)
		if stream.format != AudioStreamWAV.FORMAT_16_BITS:
			continue
		var rate := stream.mix_rate
		var crossings := _crossings_per_second(stream, 1.0)
		if path.get_file().begins_with("dog_growl_"):
			growls += 1
			assert_true(
				crossings < GROWL_CROSSINGS,
				"%s crosses zero %.0f times a second; a growl is under %d and a bark is over 2000 -- this is not a growl" % [
					path, crossings, GROWL_CROSSINGS]
			)
		else:
			assert_true(
				crossings > GROWL_CROSSINGS,
				"%s crosses zero only %.0f times a second, which is a growl's register, not a %s's" % [
					path, crossings, path.get_file().split("_")[1]]
			)
		assert_true(rate == 44100, "%s is at %d Hz" % [path, rate])
	assert_true(growls >= 3, "only %d growl(s) to check" % growls)


## Sign changes per second over the first `seconds` of a stream, read straight
## out of the imported 16-bit PCM. Zero samples are skipped rather than counted
## as a crossing -- a run of silence would otherwise read as an enormous
## frequency, which is the opposite of the truth.
func _crossings_per_second(stream: AudioStreamWAV, seconds: float) -> float:
	var samples := stream.data.size() / 2
	var window := mini(samples, int(stream.mix_rate * seconds))
	if window <= 1:
		return 0.0
	var crossings := 0
	var previous := 0
	for index in range(window):
		var value := stream.data.decode_s16(index * 2)
		var sign := 0
		if value > 0:
			sign = 1
		elif value < 0:
			sign = -1
		if sign != 0:
			if previous != 0 and sign != previous:
				crossings += 1
			previous = sign
	return float(crossings) / (float(window) / float(stream.mix_rate))


# --- the crow system, unchanged ----------------------------------------------


func test_every_stream_the_folder_yields_is_a_file_on_disk() -> void:
	var on_disk: Dictionary = {}
	for path in _wavs_in(CROW_FOLDER):
		on_disk[path] = true
	var yielded: Dictionary = {}
	for stream in _calls.calls():
		assert_not_null(stream, "the folder yielded a null stream")
		if stream != null:
			yielded[stream.resource_path] = true
	assert_eq(
		yielded.size(), on_disk.size(),
		"the folder holds %d caws and CrowCalls yielded %d distinct streams" % [
			on_disk.size(), yielded.size()]
	)
	for path in yielded:
		assert_true(on_disk.has(path), "CrowCalls loaded %s, which is not a caw on disk" % path)


## The startle report's claim, checked. No `.gd` file changed for this to pass;
## the only thing that changed is that the folder has files in it.
func test_the_crow_system_plays_them_with_no_code_change() -> void:
	_calls.fewest = 4
	_some_birds(4)
	var scheduled := _calls.announce(_birds)
	assert_true(scheduled > 0, "a flock of four scheduled nothing")

	var elapsed := 0.0
	while elapsed < 1.0 and _calls.voices().is_empty():
		_calls.advance(FRAME)
		elapsed += FRAME
	var voices := _calls.voices()
	assert_true(not voices.is_empty(), "1.0 s of burst opened no emitter at all")
	if voices.is_empty():
		return

	var playing := 0
	for voice in voices:
		if voice.is_playing():
			playing += 1
	# is_playing(), not the return of play(). The engine refuses playback outside
	# the tree and says so only in the console.
	assert_true(playing > 0, "%d emitter(s) opened and none of them is playing" % voices.size())
	assert_not_null(voices[0].stream, "an emitter was opened with no stream on it")


## Positional is the half the owner asked for by name. Two calls from two birds
## on different perches must come from two different places.
func test_the_calls_come_from_where_the_birds_are() -> void:
	_calls.fewest = 3
	_some_birds(4)
	_calls.announce(_birds)
	var elapsed := 0.0
	while elapsed < 2.0:
		_calls.advance(FRAME)
		elapsed += FRAME
	var voices := _calls.voices()
	assert_true(voices.size() >= 2, "only %d emitter(s) for a three-call burst" % voices.size())
	if voices.size() < 2:
		return
	var places: Dictionary = {}
	for voice in voices:
		places[voice.global_position] = true
	assert_true(
		places.size() >= 2,
		"%d emitters, all at the same point -- that is one stereo event" % voices.size()
	)


## Three files played at one pitch are three files. The jitter is what makes
## them a flock rather than a sample library.
func test_no_two_caws_in_a_burst_share_a_pitch() -> void:
	_calls.fewest = 4
	_some_birds(4)
	_calls.announce(_birds)
	var elapsed := 0.0
	while elapsed < 3.0:
		_calls.advance(FRAME)
		elapsed += FRAME
	var voices := _calls.voices()
	assert_true(voices.size() >= 2, "only %d emitter(s) opened" % voices.size())
	if voices.size() < 2:
		return
	var pitches: Dictionary = {}
	for voice in voices:
		pitches[voice.pitch_scale] = true
	assert_true(
		pitches.size() >= 2,
		"%d emitters all at pitch %.4f" % [voices.size(), voices[0].pitch_scale]
	)


## One emitter per call and no more.
##
## ---------------------------------------------------------------------------
## THE ASSERTION THIS TEST WAS FIRST WRITTEN AS, AND WHY IT CANNOT BE WRITTEN
## ---------------------------------------------------------------------------
## It was "a caw releases its emitter": advance 2.5 s, assert `is_playing()` has
## gone false on a 0.62 s file. **It failed, and the code was right.**
##
## `_calls.advance(FRAME)` in a tight loop moves a SIMULATED clock. The
## AudioServer moves on the WALL clock, and a hundred and fifty iterations of a
## `while` loop take a couple of milliseconds of it -- so the emitter really was
## still playing, 2.5 simulated seconds and 0.002 real ones after it started.
## Every other test in this file gets away with the same loop because they assert
## a sound STARTED, and starting is synchronous.
##
## Verified in real time instead, with a throwaway probe under `--script` where
## `_process` is driven by the engine: three emitters opened, `is_playing()` true
## on each as it opened, and 0 of 3 still playing at t = 2.50 s. That is the
## evidence for release; what stands here is the invariant that needs no clock,
## and the loop-mode gate above, which is the cause rather than the symptom.
func test_a_burst_opens_one_emitter_per_call_and_no_more() -> void:
	_calls.fewest = 4
	_some_birds(4)
	var scheduled := _calls.announce(_birds)
	assert_true(scheduled >= 2, "the burst scheduled only %d call(s)" % scheduled)
	var elapsed := 0.0
	while elapsed < 3.0:
		_calls.advance(FRAME)
		elapsed += FRAME
	var voices := _calls.voices()
	assert_true(not voices.is_empty(), "no emitter opened at all")
	assert_true(
		voices.size() <= scheduled,
		"%d call(s) opened %d emitter(s) -- the pool is growing faster than the burst" % [
			scheduled, voices.size()]
	)
