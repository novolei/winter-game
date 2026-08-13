extends "res://tools/capture_frame.gd"

## Diagnostic capture only: hides the in-progress WinterStubble MultiMesh after
## its normal setup has completed.  The scene still runs Farmstead and its
## TrackMask bake unchanged, so a line present in this frame belongs to the
## shipped baked surface rather than to the uncommitted stalk geometry.


func _ready() -> void:
	super._ready()
	var stubble := get_node_or_null("Main/Farmstead/WinterStubble") as GeometryInstance3D
	if stubble != null:
		stubble.visible = false
		print("capture_farmstead_mask_only: WinterStubble hidden; inspecting baked surface")
