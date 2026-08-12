class_name MontageFilm
extends CanvasLayer

## The grain and the vignette, as a full-frame pass over the montage.
## UI design document section 4.5.
##
## A CanvasLayer above the world rather than a CompositorEffect, because it has
## to sit above everything the montage draws INCLUDING the inscriptions -- the
## letters are world geometry, and film that graded the valley but not the words
## standing in it would put them on separate stocks.
##
## Built by MontageDirector when a shot carries a grade and freed with it, so
## nothing has to be switched off: outside a montage this node does not exist.

const SHADER_PATH := "res://assets/shaders/montage_film.gdshader"

## Above the interface (UILayer is 10) and below the lighting debug panel (100),
## which must stay readable over anything.
const LAYER_ORDER := 40

var _rect: ColorRect = null

func build() -> void:
	layer = LAYER_ORDER
	if _rect != null:
		return
	var shader := ResourceLoader.load(SHADER_PATH) as Shader
	if shader == null:
		return
	var material := ShaderMaterial.new()
	material.shader = shader
	_rect = ColorRect.new()
	_rect.name = "Film"
	_rect.material = material
	# Full frame at every resolution, and never in the way: the pass reads the
	# screen texture and writes it back, so it must not eat input.
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

func is_ready() -> bool:
	return _rect != null and _rect.material != null

## Pushes a grade onto the pass. `seconds` seeds the grain, so a given montage
## second always grains identically -- two captures of the same moment compare as
## pictures rather than as whenever each one happened to render.
func apply(grade: MontageGrade, seconds: float) -> void:
	if not is_ready() or grade == null:
		return
	var material := _rect.material as ShaderMaterial
	material.set_shader_parameter(&"grain_amount", grade.grain_amount)
	material.set_shader_parameter(&"grain_size", grade.grain_size)
	material.set_shader_parameter(&"grain_highlight_falloff", grade.grain_highlight_falloff)
	material.set_shader_parameter(&"vignette_amount", grade.vignette_amount)
	material.set_shader_parameter(&"vignette_start", grade.vignette_start)
	material.set_shader_parameter(&"vignette_end", grade.vignette_end)
	material.set_shader_parameter(&"vignette_colour", Vector3(
		grade.vignette_colour.r, grade.vignette_colour.g, grade.vignette_colour.b))
	# Quantised to whole frames at 24, so the grain steps the way a projected
	# print does rather than crawling continuously. It is the single cheapest
	# thing here that reads as film rather than as noise.
	material.set_shader_parameter(&"grain_seed", floor(seconds * 24.0))
