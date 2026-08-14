extends Node

## Screenshot harness for the interior reveal. Runs the real main scene, walks
## the player up the porch and through the farmhouse door, and shoots four
## frames off the one fixed camera:
##
##   approach     outside, roof on, the house solid
##   crossing     caught mid-tween, at the doorway -- the moment itself
##   inside       at the stove, the room open
##   game-camera  the same instant with the live interior framing modifier,
##                which is the only one of the four that proves the room reads
##                as the player now sees it
##
##   Godot_console.exe --path <project> res://tools/capture_interior.tscn \
##       --resolution 1600x1000 -- --out D:/somewhere/dir [--preset PALE_DAY]
##
## Separate from tools/capture_frame.gd rather than another flag on it. That
## one walks a fixed loop to lay a trail in open snow and shoots once; this one
## walks a straight line at a doorway and shoots on an EVENT -- it waits for
## interior.entered off the EventBus and opens the shutter half a fade later,
## so the middle frame is a real moment of a real tween rather than a fade
## value poked in by hand.
##
## Input goes through Input.action_press, not by moving the body, so the walk
## exercises the same path a player would: the same speed out of the snow
## depth, the same footprints in the track mask, and -- the part that matters
## here -- the same Area3D overlap on the same physics tick.

const REVEAL_ENTERED := &"interior.entered"
const REVEAL_EXITED := &"interior.exited"

## Where the farmhouse stands in scenes/main.tscn, and the door in the model's
## own coordinates: the front door panel spans x 1.30 .. 2.30 at z 0, and the
## three porch steps sit right in front of it at x 1.35 .. 2.25.
const FARMHOUSE := Vector3(13.0, 0.0, -12.0)
const DOOR_LOCAL := Vector2(1.80, 0.0)

## move_forward + move_left, run through the camera's -35 degree yaw, walks
## (-0.173, -0.985) -- within 10 degrees of straight down -Z. The start is
## chosen so that line passes through the doorway rather than through a wall:
## the wing is the whole -X half of the front elevation, and a straighter-
## looking approach walks in through its front wall and trips the threshold
## from the wrong room.
const WALK := Vector2(-0.173, -0.985)
const START_LOCAL := Vector2(3.03, 7.0)

const OUTSIDE_SHOT_AT := 1.1
const HALF_A_FADE := 0.15

## Walked to, not timed to. A stopwatch put the player 13 m out through the back
## wall, because how far he gets in three seconds is a function of the snow
## depth he happened to cross -- which is exactly the thing this project varies
## on purpose. He is released this far from the fire and coasts the rest in.
const RELEASE_AT_M := 2.4

var _out := ""
var _preset := ""
var _wide := 17.0
var _fire := "on"
## CameraRig's own framing, read once before anything widens it. Shot four is
## the whole point of the set -- the room at the size the game actually plays
## at -- and the first version of this asked the rig for its size AFTER shot
## three had already widened it, so three and four came out byte-identical.
var _gameplay_size := 0.0
var _rig: Node3D = null
var _player: Node3D = null
var _reveal = null
var _stove = null
var _door = null
var _warmth = null
var _crossed := false
var _entry_events := 0
var _exit_events := 0
var _held: Array[StringName] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _string_arg(args, "--out", ProjectSettings.globalize_path("user://"))
	_preset = _string_arg(args, "--preset", "")
	_wide = float(_string_arg(args, "--wide", str(_wide)))
	# `--fire out` shoots the same room with the stove smothered. Two uses: it
	# is what a day-7 interior looks like, and it is the only honest way to see
	# how much of the room's light the fire is actually responsible for.
	_fire = _string_arg(args, "--fire", "on")
	DirAccess.make_dir_recursive_absolute(_out)

	_rig = get_node_or_null("Main/CameraRig") as Node3D
	_player = get_node_or_null("Main/Player") as Node3D
	_reveal = get_node_or_null("Main/Farmhouse/InteriorReveal")
	_stove = get_node_or_null("Main/Farmhouse/Stove")
	_door = get_node_or_null("Main/Farmhouse/Door")
	_warmth = get_node_or_null("Main/Farmhouse/InteriorWarmth")
	if _rig == null or _player == null or _reveal == null or _stove == null or _door == null or _warmth == null:
		push_error("capture_interior: main.tscn is not what this expects")
		get_tree().quit()
		return
	# Before the player's first physics frame, so it lands on the snow surface
	# rather than easing down to it -- PlayerController._grounded.
	_player.global_position = Vector3(
		FARMHOUSE.x + START_LOCAL.x, _player.global_position.y, FARMHOUSE.z + START_LOCAL.y
	)
	_gameplay_size = _rig.orthographic_size
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.subscribe(REVEAL_ENTERED, _on_crossed)
		bus.subscribe(REVEAL_EXITED, _on_exited)
	await _run()


func _run() -> void:
	_hold(&"move_forward")
	_hold(&"move_left")

	await get_tree().create_timer(OUTSIDE_SHOT_AT).timeout
	await _shoot("interior-1-approach", _wide)

	# Walk up to the door and open it. The reveal is gated on the door being
	# open (InteriorReveal.entry_gate_path), so without this the player walks
	# into a house that keeps its roof on -- which is the point of the gate.
	var reached := 0.0
	while not _door.is_occupant_near() and reached < 20.0:
		await get_tree().process_frame
		reached += get_process_delta_time()
	if not _door.is_occupant_near():
		push_error("capture_interior: never reached the doorstep in %.1f s" % reached)
	Input.action_press(&"interact")
	await get_tree().process_frame
	Input.action_release(&"interact")
	await get_tree().create_timer(0.35).timeout
	await _shoot("interior-2-door", _wide)

	# The shutter is opened by the event, not by a stopwatch: whatever the snow
	# depth does to the walking speed, this frame is always half a fade after
	# the threshold.
	var waited := 0.0
	while not _crossed and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not _crossed:
		push_error("capture_interior: the player never crossed the threshold in %0.1f s" % waited)
	await get_tree().create_timer(HALF_A_FADE).timeout
	await _shoot("interior-3-crossing", _wide)

	var walked := 0.0
	while _to_the_fire() > RELEASE_AT_M and walked < 12.0:
		await get_tree().process_frame
		walked += get_process_delta_time()
	if _to_the_fire() > RELEASE_AT_M:
		push_error("capture_interior: never reached the stove; stopped %.2f m short" % _to_the_fire())
	_release_all()
	# Long enough for the body to coast to a stop and for any footstep one-shot
	# to finish -- quitting on top of one leaves the AudioServer holding both
	# WAVs and the run ends on "resources still in use".
	await get_tree().create_timer(1.0).timeout
	if _fire == "out":
		_stove.extinguish()
		# WAITED OUT, NOT SHOT OVER. `extinguish()` starts InteriorWarmth's 0.8 s
		# fade; `_shoot()` awaits three frames. So this flag used to photograph a
		# room at warmth 0.85 while its own docstring said "smothered" and its own
		# report line printed the 0.85 -- the number was on screen the whole time
		# and read as the fire dying rather than as the shot being wrong. A room
		# 85 % still warm is the reveal's payoff frame with the caption changed.
		#
		# Waited on the STATE and not on a stopwatch, for the same reason the
		# threshold shot is: `warm_seconds` is authored and may be retuned, and a
		# sleep tuned to today's value would silently start shooting early again.
		var fading := 0.0
		while _warmth.warmth() > 0.001 and fading < 5.0:
			await get_tree().process_frame
			fading += get_process_delta_time()
		if _warmth.warmth() > 0.001:
			push_error("capture_interior: the room never went cold; warmth %.3f after %.1f s"
				% [_warmth.warmth(), fading])

	await _shoot("interior-4-inside", _wide)
	await _shoot("interior-5-game-camera", _rig.framing_target())
	if _entry_events != 1 or _exit_events != 0:
		push_error("capture_interior: unstable threshold emitted %d enters and %d exits"
			% [_entry_events, _exit_events])
	_report()
	get_tree().quit()


## Held every frame, not pressed once.
##
## Pressed once, one run in four came out with move_left inert: the player
## walked the move_forward-only heading, 75 m out across the valley on a
## bearing that matched that single action to three decimal places. Godot
## releases every pressed event when the window loses focus, and a capture run
## opens a real window on a machine with other things on it -- so a walk that
## depends on a press surviving 30 s of wall clock is a walk that is sometimes
## a different walk. Re-pressing is idempotent and makes the route the same
## route every time.
func _process(_delta: float) -> void:
	for action in _held:
		if not Input.is_action_pressed(action):
			Input.action_press(action)


func _hold(action: StringName) -> void:
	if not _held.has(action):
		_held.append(action)
	Input.action_press(action)


func _release_all() -> void:
	for action in _held:
		Input.action_release(action)
	_held.clear()


func _on_crossed(_payload) -> void:
	_entry_events += 1
	_crossed = true


func _on_exited(_payload) -> void:
	_exit_events += 1


## Horizontal only: the player walks on the snow surface and the stove stands on
## a floor 0.45 m above the building's origin, so the vertical gap between them
## is a constant that would just bias the stopping distance.
func _to_the_fire() -> float:
	var gap: Vector3 = _stove.global_position - _player.global_position
	return Vector2(gap.x, gap.z).length()


func _shoot(tag: String, frame_height: float) -> void:
	var camera := get_node_or_null("Main/CameraRig/Camera3D") as Camera3D
	if camera != null:
		# CameraRig._ready() has already pushed its own size onto the Camera3D,
		# so setting only the export is silent and does nothing. Set both.
		_rig.orthographic_size = frame_height
		camera.size = frame_height
	# The rig lags the player by design; without this every shot is framed on
	# where he was half a second ago.
	if _rig.has_method("snap_to_target"):
		_rig.snap_to_target()
	if _preset != "":
		var lighting := get_node_or_null("Main/Lighting")
		if lighting != null and lighting.has_method("apply_preset"):
			lighting.apply_preset(StringName(_preset))
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, tag]
	if image.save_png(path) != OK:
		push_error("capture_interior: could not write %s" % path)
	else:
		print("capture_interior: wrote %s  (revealed=%s fade=%.2f)" % [
			path, _reveal.is_revealed(), _reveal.fade(),
		])


## Printed rather than assumed. A shot of a room is the same picture whether
## the fire is lit or the firebox is just a painted rectangle.
func _report() -> void:
	var here: Vector3 = _player.global_position
	var local := here - FARMHOUSE
	print("capture_interior: player at local %.2f, %.2f, %.2f (door is %.2f, %.2f)" % [
		local.x, local.y, local.z, DOOR_LOCAL.x, DOOR_LOCAL.y,
	])
	print("capture_interior: reveal revealed=%s fade=%.3f fading %d part(s)" % [
		_reveal.is_revealed(), _reveal.fade(), _reveal.parts().size(),
	])
	print("capture_interior: threshold events entered=%d exited=%d" % [
		_entry_events, _exit_events,
	])
	for part in _reveal.parts():
		print("capture_interior:   %-18s transparency=%.2f cast_shadow=%d visible=%s" % [
			part.name, part.transparency, part.cast_shadow, part.visible,
		])
	print("capture_interior: stove lit=%s fuel=%.0f s warmth_here=%.2f cull_mask=%d" % [
		_stove.is_lit(), _stove.fuel_remaining(), _stove.warmth_at(here), _stove.light_cull_mask,
	])
	print("capture_interior: door open=%s swing=%.2f; room warmth=%.2f over %d part(s)" % [
		_door.is_open(), _door.swing(), _warmth.warmth(), _warmth.parts().size(),
	])
	var recovery: Dictionary = _stove.recovery_at(here)
	for target in recovery:
		print("capture_interior:   %s += %.5f /s" % [target, recovery[target]])
	_report_the_floor()


## How much of the farmhouse floor the snow is actually above.
##
## Nothing could see inside this building until the reveal existed, so nothing
## had ever compared the two surfaces. Farmhouse._settle() beds the building
## onto the LOWEST snow under its footprint, and the ground floor is only
## 0.45 m above the building's origin -- so anywhere the snow inside the
## footprint stands more than 0.45 m proud of that lowest point, the drift is
## over the floorboards and the room is floored with snow.
func _report_the_floor() -> void:
	var house := get_node_or_null("Main/Farmhouse") as Node3D
	var registry := get_node_or_null("/root/ServiceRegistry")
	if house == null or registry == null:
		return
	var snow := registry.get_service(&"snow_field") as Node
	if snow == null:
		return
	var floor_y: float = house.global_position.y + 0.45
	var lowest := INF
	var highest := -INF
	var over := 0
	var samples := 0
	var x := -3.4
	while x <= 3.4:
		var z := -5.8
		while z <= -0.2:
			var spot: Vector3 = house.global_position + Vector3(x, 0.0, z)
			var surface: float = snow.terrain_height_at(spot) + snow.depth_at(spot)
			lowest = minf(lowest, surface - floor_y)
			highest = maxf(highest, surface - floor_y)
			samples += 1
			if surface > floor_y:
				over += 1
			z += 0.4
		x += 0.4
	print("capture_interior: main room floor at y=%.2f; snow surface runs %.2f .. %.2f m relative to it" % [
		floor_y, lowest, highest,
	])
	print("capture_interior: snow stands over the floorboards on %d of %d sampled points (%.0f%%)" % [
		over, samples, 100.0 * float(over) / float(maxi(samples, 1)),
	])


func _string_arg(args: PackedStringArray, name: String, fallback: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback
