extends Node

## D3D12 walking-performance probe.  This drives the real main scene across
## the same SnowField.follow() seam a player crosses, measures full rendered
## frame time, then reports the SnowField-only recentre cost separately.
##
## Run:
##   Godot --path "D:/Godot resource/winter-time" res://tools/probe_movement_stall.tscn
##
## It is a regression boundary, not a benchmark leaderboard: the world must
## never stop for a second because the height window moved.  The test uses the
## same 132 m crossing that first reproduced sixteen 1.3 s hitches.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const STEP_M := 0.6
const STEP_COUNT := 220
const MAX_FRAME_MS := 50.0
const MAX_RECENTER_MS := 25.0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	for _frame in range(3):
		await get_tree().process_frame
	var player := main.get_node_or_null("Player") as Node3D
	var snow := main.get_node_or_null("SnowField") as SnowField
	var tracks := main.get_node_or_null("TrackMask")
	if player == null or snow == null or tracks == null:
		push_error("MOVEMENT_PROBE_SETUP_FAILED")
		get_tree().quit(2)
		return
	player.global_position = Vector3.ZERO
	var hitches := 0
	var worst_ms := 0.0
	var total_ms := 0.0
	var max_snow_recentre_ms := 0.0
	for step in range(STEP_COUNT):
		var start_us := Time.get_ticks_usec()
		player.global_position.x += STEP_M
		await get_tree().process_frame
		var frame_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
		total_ms += frame_ms
		worst_ms = maxf(worst_ms, frame_ms)
		max_snow_recentre_ms = maxf(max_snow_recentre_ms, snow.last_recentre_duration_ms())
		if frame_ms >= MAX_FRAME_MS:
			hitches += 1
			print("MOVEMENT_HITCH step=%d x=%.2f frame_ms=%.3f snow_recentre_ms=%.3f snow_origin=%s track_origin=%s dynamic_tiles=%d" % [
				step,
				player.global_position.x,
				frame_ms,
				snow.last_recentre_duration_ms(),
				str(snow.origin()),
				str(tracks.origin()),
				snow.dynamic_tile_count(),
			])
	print("MOVEMENT_PROBE_SUMMARY steps=%d distance_m=%.2f hitches=%d worst_ms=%.3f avg_ms=%.3f max_snow_recentre_ms=%.3f" % [
		STEP_COUNT,
		STEP_COUNT * STEP_M,
		hitches,
		worst_ms,
		total_ms / float(STEP_COUNT),
		max_snow_recentre_ms,
	])
	var passed := hitches == 0 and max_snow_recentre_ms < MAX_RECENTER_MS
	main.queue_free()
	await get_tree().process_frame
	if not passed:
		push_error("MOVEMENT_PROBE_FAILED hitches=%d max_snow_recentre_ms=%.3f" % [
			hitches, max_snow_recentre_ms,
		])
		get_tree().quit(1)
		return
	get_tree().quit()
