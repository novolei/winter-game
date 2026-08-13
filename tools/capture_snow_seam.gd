extends "res://tools/capture_frame.gd"

## A deterministic wide-frame probe for the real game scene.  The normal
## gameplay stop is deliberately intimate, so it cannot reveal the old 120 m
## SnowField-window diamond.  This harness inherits the normal capture route,
## lighting and shutter; it changes only the framing to the widest supported
## acceptance view before the first process tick.
##
## Run with:
##   Godot_console.exe --path <project> res://tools/capture_snow_seam.tscn \
##       --resolution 1600x1000 -- --out D:/capture.png --seconds 2 \
##       --settle 0.9 --preset pale_day
##
## `capture_frame.gd` still accepts `--ortho`, but this probe deliberately wins
## afterwards.  A seam regression must not depend on a human remembering to
## pass the one argument that makes it visible.
const SEAM_PROBE_ORTHO := 100.0


func _ready() -> void:
	super._ready()
	_frame_at(SEAM_PROBE_ORTHO)
