extends "res://tools/capture_frame.gd"

## A deterministic same-camera diagnostic for the fine screen-space striping
## that can appear on snow.  This is deliberately a live-only A/B: it never
## changes a shipping preset, palette or scene.  Run with one of:
##
##   --ripple-mode control          Current render path.
##   --ripple-mode no_terrain_cast  Keep tree/prop shadows, remove the ground
##                                   from the shadow map (self-shadow control).
##   --ripple-mode no_shadows       Remove every cast shadow (upper bound).
##   --ripple-mode flat_ground      Remove snow relief, keep tree/prop shadows.
##   --ripple-mode no_grain         Remove only the snow material grain band.
##   --ripple-mode no_penumbra      Remove light-area/constant shadow blur.
##   --ripple-mode penumbra_015     Narrow, still soft 0.15 degree penumbra.
##   --ripple-mode penumbra_030     Medium 0.30 degree penumbra.
##   --ripple-mode penumbra_050     Half-width 0.50 degree penumbra.
##   --ripple-mode hard_filter      Request Godot's hard directional filtering
##                                   before the first shadow map is rendered.
##
## The controls are intentionally independent.  A line that survives the
## terrain-caster and grain controls is not a terrain seam or snow texture;
## a line that disappears under hard_filter is shadow-map filtering noise.

const DEFAULT_MODE := &"control"
const RIPPLE_MODES := [
	&"control",
	&"no_terrain_cast",
	&"no_shadows",
	&"flat_ground",
	&"no_grain",
	&"no_penumbra",
	&"penumbra_015",
	&"penumbra_030",
	&"penumbra_050",
	&"hard_filter",
]


func _init() -> void:
	# This must happen before the first shadow atlas is rendered.  ProjectSettings
	# is the renderer's only switch for directional PCF quality; the Directional
	# Light has no equivalent per-light setting.
	if _mode_from_args() == &"hard_filter":
		ProjectSettings.set_setting(
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
			0
		)


func _mode_from_args() -> StringName:
	var raw := _string_arg(OS.get_cmdline_user_args(), "--ripple-mode", String(DEFAULT_MODE))
	return StringName(raw)


func _apply_mode() -> bool:
	var mode := _mode_from_args()
	if not RIPPLE_MODES.has(mode):
		push_error("capture_shadow_ripple_ab: unknown mode '%s'" % mode)
		return false
	var terrain := get_node_or_null("Main/Terrain") as MeshInstance3D
	var sun := get_node_or_null("Main/Lighting/Sun") as DirectionalLight3D
	if terrain == null or sun == null:
		push_error("capture_shadow_ripple_ab: expected real Terrain and Sun")
		return false
	var material := terrain.material_override as ShaderMaterial
	match mode:
		&"no_terrain_cast":
			terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		&"no_shadows":
			sun.shadow_enabled = false
		&"flat_ground":
			if material == null:
				push_error("capture_shadow_ripple_ab: Terrain has no snow material")
				return false
			material.set_shader_parameter("terrain_amplitude", 0.0)
			material.set_shader_parameter("max_depth", 0.0)
		&"no_grain":
			if material == null:
				push_error("capture_shadow_ripple_ab: Terrain has no snow material")
				return false
			material.set_shader_parameter("grain_amount", 0.0)
		&"no_penumbra":
			sun.light_angular_distance = 0.0
			sun.shadow_blur = 0.0
		&"penumbra_015":
			sun.light_angular_distance = 0.15
			sun.shadow_blur = 0.25
		&"penumbra_030":
			sun.light_angular_distance = 0.30
			sun.shadow_blur = 0.50
		&"penumbra_050":
			sun.light_angular_distance = 0.50
			sun.shadow_blur = 0.75
		&"hard_filter":
			# The ProjectSettings switch is written in _init().  Keep the desired
			# penumbra geometry; this control is about the PCF kernel only.
			pass
		_:
			pass
	print(
		"capture_shadow_ripple_ab: mode=%s, terrain_cast=%d, sun_shadows=%s, angular=%.2f, blur=%.2f, filter=%d"
		% [
			mode,
			terrain.cast_shadow,
			sun.shadow_enabled,
			sun.light_angular_distance,
			sun.shadow_blur,
			int(ProjectSettings.get_setting(
				"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
				-1
			)),
		]
	)
	return true


func _capture() -> void:
	# Reapply after the timed route and after the preset snap: TerrainRenderer and
	# LightingDirector correctly republish their normal values every frame, so a
	# diagnostic needs to win only at the shutter, not by modifying game code.
	if _settle > 0.0:
		await get_tree().create_timer(_settle).timeout
	_release_all()
	var rig := get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.snap_to_target()
	if rig != null and _has_look:
		(rig as Node3D).global_position = Vector3(_look.x, 1.0, _look.y)
	if _preset != "":
		var lighting := get_node_or_null("Main/Lighting")
		if lighting == null or not lighting.apply_preset(StringName(_preset)):
			push_error("capture_shadow_ripple_ab: no lighting preset '%s'" % _preset)
		else:
			print("capture_shadow_ripple_ab: lit with %s" % _preset)
		await RenderingServer.frame_post_draw
	if not _apply_mode():
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output)
	if error != OK:
		push_error("capture_shadow_ripple_ab: could not write %s (error %d)" % [_output, error])
	else:
		print("capture_shadow_ripple_ab: wrote ", ProjectSettings.globalize_path(_output))
	print("capture_shadow_ripple_ab: %.0f s, walked %.1f m; snow depth %.2f..%.2f m; speed %.2f..%.2f m/s" % [
		_elapsed, _distance, _shallowest, _deepest, _slowest, _fastest,
	])
	get_tree().quit()
