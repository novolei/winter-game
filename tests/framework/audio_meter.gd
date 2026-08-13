class_name AudioMeter
extends RefCounted

## Did a sound actually happen?
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## This project's registered false-PASS class 5 is an `AudioStreamPlayer` that
## reported success 44 times while the engine mixed nothing. Every audio
## assertion in this suite until now has been one of:
##
##     play() was called          -- says nothing; on 4.7.1 `play()` returns void
##     playing / is_playing()     -- says the SERVER ACCEPTED it, not that it sounded
##
## Both are true of a voice that is inaudible, and both were true for every one
## of the three crow caws for the whole time they have been in the repository:
## measured at **-200.00 dB**, digital silence, with `playing == true`, because
## the emitter's `max_distance` cut off before the listener (see briefing trap
## 19). **The suite was green throughout.**
##
## This class reads the number at the other end: the level that actually reached
## an audio bus. It is the difference between「设进去了」and「起作用了」for sound.
##
## ---------------------------------------------------------------------------
## WHY IT WORKS HEADLESS, WHICH IS NOT OBVIOUS
## ---------------------------------------------------------------------------
## The headless driver is `Dummy`, and the reasonable assumption is that it
## discards audio without mixing. **It does not: it mixes on its own thread.**
## Measured -- one `AudioStreamPlayer`, `OS.delay_msec()` only, **zero frames**:
##
##     +25 ms   -10.89 dB      +100 ms   -21.94 dB
##     +50 ms    -8.59 dB      +200 ms  -200.00 dB   (the 0.62 s caw has ended)
##
## That matters because `test_runner.gd` calls every test synchronously inside a
## single `_process()` and **cannot await a frame**. Wall clock is the only thing
## a test can spend, and wall clock is all this needs.
##
## ---------------------------------------------------------------------------
## TWO THINGS THAT WILL BITE
## ---------------------------------------------------------------------------
## 1. **The node must be inside the tree before `play()`.** Outside it, the
##    engine refuses with `Playback can only happen when a node is inside the
##    scene tree` -- which is false-PASS class 5's actual mechanism. Under
##    `--script`, `root` is only inside the tree from `_process()` onwards
##    (briefing trap 1), so a test that builds its emitter in `before_each()`
##    is fine and a probe that builds one in `_initialize()` is not.
##
## 2. **An `AudioStreamPlayer3D` needs a listener.** With none, distance is
##    undefined and the reading is not meaningful. Use `with_listener_at()` to
##    plant one, and free it afterwards -- an `AudioListener3D` is a `Node`, so
##    briefing constraint 2 applies.

## The engine's own floor. A bus with nothing on it reads exactly this.
const SILENCE_DB := -200.0

## Above this, a human at a normal mix level hears something. Chosen as a
## reporting convenience, not as a psychoacoustic claim -- assertions should
## prefer explicit comparisons against a measured floor.
const AUDIBLE_DB := -60.0

## Long enough to cover the attack of every one-shot this project ships (the
## longest caw is 0.62 s and peaks inside 50 ms) without making a suite of these
## slow. Sampled repeatedly across the window rather than once at the end,
## because the bus meter decays.
const DEFAULT_WINDOW_MS := 320
const SAMPLE_MS := 16


static func bus_index(bus_name: StringName = &"Master") -> int:
	var found := AudioServer.get_bus_index(String(bus_name))
	return found if found >= 0 else 0


## The level on `bus_name` right now. One reading, no waiting.
static func peak_db(bus_name: StringName = &"Master") -> float:
	return AudioServer.get_bus_peak_volume_left_db(bus_index(bus_name), 0)


## The loudest level to reach `bus_name` over `window_ms` of WALL CLOCK.
##
## Call it immediately after `play()`. It spends real milliseconds -- that is the
## point, and it is what makes the reading true rather than hopeful.
static func loudest_db(window_ms: int = DEFAULT_WINDOW_MS, bus_name: StringName = &"Master") -> float:
	var index := bus_index(bus_name)
	var loudest := SILENCE_DB
	var spent := 0
	while spent < window_ms:
		OS.delay_msec(SAMPLE_MS)
		spent += SAMPLE_MS
		loudest = maxf(loudest, AudioServer.get_bus_peak_volume_left_db(index, 0))
	return loudest


## What the bus reads with nothing deliberately playing. Subtract it, or assert
## against it -- a scene under test may have its own ambience running, and a
## measurement that ignores that is measuring the weather.
static func floor_db(window_ms: int = DEFAULT_WINDOW_MS, bus_name: StringName = &"Master") -> float:
	return loudest_db(window_ms, bus_name)


## Plant a listener so an `AudioStreamPlayer3D` has something to be a distance
## FROM. Returns the node; **the caller frees it** (briefing constraint 2).
static func with_listener_at(parent: Node, at: Vector3) -> AudioListener3D:
	var listener := AudioListener3D.new()
	parent.add_child(listener)
	listener.global_position = at
	listener.make_current()
	return listener


## True when `db` is meaningfully above `floor`. The margin exists so a reading
## a hair over the floor is not reported as a sound.
static func is_audible(db: float, floor: float = SILENCE_DB, margin_db: float = 6.0) -> bool:
	return db > floor + margin_db
