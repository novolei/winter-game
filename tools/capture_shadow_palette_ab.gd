extends "res://tools/capture_frame.gd"

## Reproducible, non-shipping A/B capture for the snow shadow palette review.
##
## Run it exactly as capture_frame, adding one of:
##   --shadow-candidate control | slate_a | slate_b
##
## The candidate exists only in the live ShaderMaterial instances created by the
## real main scene. No .tres, shader, lighting preset, or generated asset is
## rewritten. This makes a review image reversible while preserving the real
## D3D12 / Forward+ lighting, camera, weather, and mesh path.

const DEFAULT_CANDIDATE := &"control"
const PALETTE_PATH := "res://data/palette/color_bible.tres"
const GROUND_SHADER := "res://src/rendering/snow_ground.gdshader"
const CEL_SHADER := "res://assets/shaders/cel_flat.gdshader"

## These are complete temporary palette entries, not post-process multipliers.
## The first three snow tones remain the shipped ColorBible values; only the
## two shadow-side tones differ. Hex values are allowed in tools: this tool is
## the source of a review-only palette and does not author game content.
const SHADOW_CANDIDATES := {
	&"control": {
		"label": "Shipped control",
		"snow_shade": Color("#6987B4"),
		"track_shade": Color("#5D7BA6"),
	},
	&"slate_a": {
		"label": "Quiet slate",
		"snow_shade": Color("#708099"),
		"track_shade": Color("#60708A"),
	},
	&"slate_b": {
		"label": "Lifted slate",
		"snow_shade": Color("#76889F"),
		"track_shade": Color("#667890"),
	},
}


func candidate_for(id: StringName) -> Dictionary:
	if SHADOW_CANDIDATES.has(id):
		return SHADOW_CANDIDATES[id].duplicate()
	return {}


## Builds an unsaved, complete ColorBible for the live capture. This is not a
## pair of arbitrary shader colours: the candidate occupies exactly the two
## snow-shadow slots a generated shipping Bible would own, while all ten other
## palette entries remain the authoritative shipped values.
func review_bible_for(id: StringName) -> ColorBible:
	var candidate := candidate_for(id)
	if candidate.is_empty():
		return null
	var shipped: ColorBible = load(PALETTE_PATH)
	if shipped == null:
		return null
	var review: ColorBible = shipped.duplicate()
	var snow: Array[Color] = []
	for tone in shipped.snow_tones:
		snow.append(tone)
	if snow.size() < 5:
		return null
	var shade: Color = candidate["snow_shade"]
	var track_shade: Color = candidate["track_shade"]
	snow[3] = shade
	snow[4] = track_shade
	review.snow_tones = snow
	return review


func _candidate_id() -> StringName:
	var raw := _string_arg(OS.get_cmdline_user_args(), "--shadow-candidate", String(DEFAULT_CANDIDATE))
	return StringName(raw)


func _capture() -> void:
	# Keep the parent harness's shutdown-safe settling and fixed camera sequence.
	if _settle > 0.0:
		await get_tree().create_timer(_settle).timeout

	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()
	if rig != null and _has_look:
		(rig as Node3D).global_position = Vector3(_look.x, 1.0, _look.y)

	if _preset != "":
		var lighting := get_node_or_null("Main/Lighting")
		if lighting == null or not lighting.apply_preset(StringName(_preset)):
			push_error("capture_shadow_palette_ab: no lighting preset '%s'" % _preset)
		else:
			print("capture_shadow_palette_ab: lit with %s" % _preset)
		await RenderingServer.frame_post_draw

	var id := _candidate_id()
	var candidate := candidate_for(id)
	var bible := review_bible_for(id)
	if candidate.is_empty() or bible == null:
		push_error("capture_shadow_palette_ab: unknown candidate '%s'" % id)
		get_tree().quit(1)
		return
	var touched := _apply_candidate(get_node_or_null("Main"), bible)
	if touched == 0:
		push_error("capture_shadow_palette_ab: candidate reached no live cel materials")
		get_tree().quit(1)
		return
	var shade: Color = bible.snow_tones[3]
	var track_shade: Color = bible.snow_tones[4]
	print(
		"capture_shadow_palette_ab: %s (%s), snow shade #%s, track shade #%s, %d materials"
		% [id, candidate["label"], shade.to_html(false), track_shade.to_html(false), touched]
	)

	# The material edit needs one frame to reach the render thread before sampling.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output)
	if error != OK:
		push_error("capture_shadow_palette_ab: could not write %s (error %d)" % [_output, error])
	else:
		print("capture_shadow_palette_ab: wrote ", ProjectSettings.globalize_path(_output))
	print("capture_shadow_palette_ab: %.0f s, walked %.1f m; snow depth %.2f..%.2f m; speed %.2f..%.2f m/s" % [
		_elapsed, _distance, _shallowest, _deepest, _slowest, _fastest,
	])
	get_tree().quit()


func _apply_candidate(node: Node, bible: ColorBible) -> int:
	if node == null:
		return 0
	var seen: Dictionary = {}
	return _apply_candidate_recursive(node, bible, seen)


func _apply_candidate_recursive(node: Node, bible: ColorBible, seen: Dictionary) -> int:
	var touched := 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		touched += _apply_to_material(mesh_instance.material_override, bible, seen)
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				touched += _apply_to_material(
					mesh_instance.get_surface_override_material(surface), bible, seen
				)
	for child in node.get_children():
		touched += _apply_candidate_recursive(child, bible, seen)
	return touched


func _apply_to_material(material: Material, bible: ColorBible, seen: Dictionary) -> int:
	var shader_material := material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return 0
	var material_id := shader_material.get_instance_id()
	if seen.has(material_id):
		return 0
	var shader_path := shader_material.shader.resource_path
	if shader_path != GROUND_SHADER and shader_path != CEL_SHADER:
		return 0
	seen[material_id] = true
	var shade: Color = bible.snow_tones[3]
	shader_material.set_shader_parameter("snow_shade", shade)
	if shader_path == GROUND_SHADER:
		var track_shade: Color = bible.snow_tones[4]
		shader_material.set_shader_parameter("track_shade", track_shade)
	return 1
