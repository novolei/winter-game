class_name PauseCinematic
extends RefCounted

## The pause camera's motion as pure functions of time -- the same shape as
## PauseChoreography, so a test can drive it with no frames at all.
##
## Three moves:
##
##   push    -- EXPO OUT, decoupled from the type cascade. The frame detaches
##              fast (the first fifth of the time carries most of the travel)
##              and then glides for over a second: detach, glide, hover. A
##              linear push reads as a UI zoom; this reads as a camera.
##   return_ -- QUAD IN, quicker than the arrival. Leaving accelerates back
##              into play the way a cutaway returns on action.
##   drift   -- the living frame while the menu holds. Two sines whose periods
##              (40 s, 57 s) share no divisor with a breath or a heartbeat, at
##              amplitudes you feel rather than see. Design spec section 2.5's
##              nausea ruling is why these numbers are this small.
##
## Nothing here knows a camera exists; ExitMenu maps these onto CameraRig's
## offsets, whose exact-zero contract is what makes the return bit-perfect.

var push_seconds := 1.6
var return_seconds := 0.55
var drift_frame_amplitude := 0.012
var drift_frame_seconds := 40.0
var drift_yaw_radians := 0.002618
var drift_yaw_seconds := 57.0


func configure(tokens: UITokens) -> void:
	push_seconds = tokens.pause_push_seconds
	return_seconds = tokens.pause_return_seconds
	drift_frame_amplitude = tokens.pause_drift_frame_amplitude
	drift_frame_seconds = tokens.pause_drift_frame_seconds
	drift_yaw_radians = deg_to_rad(tokens.pause_drift_yaw_degrees)
	drift_yaw_seconds = tokens.pause_drift_yaw_seconds


## 0 at 0, 1 at 1, and strongly non-linear between: the midpoint of the TIME
## sits past 99% of the TRAVEL. Endpoints are exact so the push lands bit for
## bit on the authored tableau.
static func push_ease(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	return 1.0 - pow(2.0, -10.0 * t)


## QUAD IN: slow off the mark, accelerating away. The midpoint of the time
## carries only a quarter of the travel.
static func return_ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t


## Multiplicative dolly drift, e.g. ±0.012 around the pushed factor.
func drift_frame(elapsed: float) -> float:
	if drift_frame_seconds <= 0.0:
		return 0.0
	return drift_frame_amplitude * sin(TAU * elapsed / drift_frame_seconds)


## Additive yaw drift, in radians, on the same slow-clock principle.
func drift_yaw(elapsed: float) -> float:
	if drift_yaw_seconds <= 0.0:
		return 0.0
	return drift_yaw_radians * sin(TAU * elapsed / drift_yaw_seconds)
