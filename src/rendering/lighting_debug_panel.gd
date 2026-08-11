class_name LightingDebugPanel
extends CanvasLayer

## Art Bible section 4.3's slider panel, reproducing the controls of
## `Refs/game ref/lighting control.png`.
##
## Lighting is high-frequency iteration work. Without live sliders every tweak is
## an edit, a regenerate and a restart, and the Art Bible argues -- correctly --
## that this costs an order of magnitude in iteration speed. The whole point is
## that a value can be found by dragging rather than by guessing, and then typed
## into tools/generate_lighting_presets.gd once it is right.
##
## ---------------------------------------------------------------------------
## DEBUG BUILDS ONLY, AND NOT EVEN THEN UNTIL IT IS ASKED FOR
## ---------------------------------------------------------------------------
## LightingDirector builds this the first time F1 is pressed and never before, so
## it does not exist in an exported build (OS.is_debug_build() gates the input
## handler) and it is never in shot for a screenshot harness or a test. GDScript
## cannot literally exclude a file from a build the way a #ifdef would; built
## lazily behind a debug gate is the closest honest equivalent, and it also means
## the panel costs nothing at all until a human wants it.
##
## ---------------------------------------------------------------------------
## WHAT THE CONTROLS ACTUALLY MOVE
## ---------------------------------------------------------------------------
## The group headings are the reference's own, and they are honest about which
## of the two rigs each row touches -- which matters more here than anywhere,
## because a person dragging FILL and seeing only the character move needs to
## know that is correct rather than broken:
##
##   KEY LIGHT      the character. The world's cel shaders ignore light energy
##                  and colour outright.
##   SHADOW COLOR   the character. Every world shader declares
##                  `ambient_light_disabled`.
##   WARM ACCENT    published for whatever burns; nothing warm is placed yet.
##   AIR            the whole frame -- fog is the one hue control that reaches
##                  the world.
##   SHADING        TONEMAP is the whole frame. 2 BANDS-REAL is authored on the
##                  preset but not yet wired to the shader uniforms, so dragging
##                  it changes the number the preset would ship with and not the
##                  picture. Labelled as such rather than quietly inert.

const PALETTE_PATH := "res://data/palette/color_bible.tres"

const ROW_HEIGHT := 22
const PANEL_WIDTH := 380

var _director: LightingDirector = null
var _look: LightingPreset = null
var _bible: ColorBible = null
var _title: Label = null
## Slider -> the Label showing its value, so a drag reads out as a number that
## can be typed into the generator.
var _readouts: Dictionary = {}


func attach(director: LightingDirector) -> void:
	_director = director
	_bible = load(PALETTE_PATH)
	layer = 100
	_build()
	sync()


## Pulls the director's current look back into the controls. Called when the
## panel opens and whenever the clock has moved the lighting underneath it, so
## the sliders never lie about what is on screen.
func sync() -> void:
	if _director == null:
		return
	var active := _director.active_preset()
	if active == null:
		return
	_look = active.duplicate() as LightingPreset
	if _title != null:
		_title.text = "%s   %s" % [_look.display_name, String(_look.id)]
	for slider in _readouts:
		var control := slider as Range
		control.set_block_signals(true)
		control.value = _value_of(control.get_meta(&"field"))
		control.set_block_signals(false)
		_write_readout(control)
	for node in _checkboxes():
		node.set_block_signals(true)
		node.button_pressed = bool(_value_of(node.get_meta(&"field")))
		node.set_block_signals(false)


func _checkboxes() -> Array:
	var found: Array = []
	for node in _flat_children(self):
		if node is CheckBox and node.has_meta(&"field"):
			found.append(node)
	return found


func _flat_children(node: Node) -> Array:
	var found: Array = [node]
	for child in node.get_children():
		found.append_array(_flat_children(child))
	return found


# --- construction -----------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var panel := PanelContainer.new()
	margin.add_child(panel)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_child(column)

	_title = Label.new()
	column.add_child(_title)

	_group(column, "KEY LIGHT", "DirectionalLight3D -- the character only")
	_check(column, "MOONLIGHT", &"shadows_enabled")
	_slide(column, "ENERGY", &"sun_energy", 0.0, 2.0)
	_slide(column, "HOUR", &"sun_angle_degrees", 5.0, 60.0)

	_group(column, "SHADOW COLOR", "Environment.ambient -- the character only")
	_slide(column, "FILL", &"ambient_energy", 0.0, 6.0)
	_slide(column, "NAVY - GREY", &"ambient_tint", 0.0, 1.0)

	_group(column, "WARM ACCENT", "OmniLight3D + light() -- published, unconsumed")
	_slide(column, "BLEED", &"warm_accent_energy", 0.0, 4.0)

	_group(column, "AIR", "fog + glow -- the whole frame")
	_check(column, "FOG", &"fog_enabled")
	_slide(column, "DENSITY", &"fog_density", 0.0, 0.05)
	_check(column, "BLOOM", &"glow_enabled")
	_slide(column, "GLOW", &"glow_strength", 0.0, 1.5)

	_group(column, "SHADING", "light() + tonemap")
	_slide(column, "2 BANDS - REAL *", &"cel_band_threshold", 0.0, 0.6)
	_slide(column, "TONEMAP", &"tonemap_exposure", 0.1, 2.0)

	var note := Label.new()
	note.text = "* authored only -- not yet wired to the shader uniforms"
	note.add_theme_font_size_override("font_size", 10)
	column.add_child(note)

	var keys := Label.new()
	keys.text = "F1 panel   BKSP flat   F2 nightfall   F3 deep night\nF4 whiteout   F5 sunrise   F6 pale day"
	keys.add_theme_font_size_override("font_size", 10)
	column.add_child(keys)

	_paint(column)


## Every colour in here comes out of the palette. A debug panel is still inside
## the project, and briefing constraint 6 has no exception for tooling that
## happens to be a Control.
func _paint(column: Node) -> void:
	if _bible == null:
		return
	var ink: Color = _bible.snow_tones[0]
	var accent: Color = _bible.warm_tones[2]
	var style := StyleBoxFlat.new()
	style.bg_color = _bible.structure_tones[3]
	style.bg_color.a = 0.92
	style.set_content_margin_all(12)
	(column.get_parent() as PanelContainer).add_theme_stylebox_override("panel", style)
	for node in _flat_children(column):
		if node is Label:
			(node as Label).add_theme_color_override(
				"font_color", accent if node.has_meta(&"heading") else ink
			)
		elif node is CheckBox:
			(node as CheckBox).add_theme_color_override("font_color", ink)


func _group(column: Node, name: String, subtitle: String) -> void:
	var heading := Label.new()
	heading.text = "%s  ·  %s" % [name, subtitle]
	heading.add_theme_font_size_override("font_size", 11)
	heading.set_meta(&"heading", true)
	column.add_child(heading)


func _check(column: Node, text: String, field: StringName) -> void:
	var box := CheckBox.new()
	box.text = text
	box.set_meta(&"field", field)
	box.toggled.connect(func(pressed: bool) -> void: _set_value(field, pressed))
	column.add_child(box)


func _slide(column: Node, text: String, field: StringName, low: float, high: float) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	column.add_child(row)

	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	# Continuous. A quantised slider silently rounds the preset's own value when
	# the panel syncs -- DEEP NIGHT's 0.42 exposure read back as 0.4183 on a
	# 400-step slider -- and a readout that disagrees with the .tres by a
	# thousandth is worse than no readout, because it is the number a person
	# types back into the generator.
	slider.step = 0.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.set_meta(&"field", field)
	row.add_child(slider)

	var readout := Label.new()
	readout.custom_minimum_size = Vector2(64, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(readout)

	_readouts[slider] = readout
	slider.value_changed.connect(func(value: float) -> void:
		_set_value(field, value)
		_write_readout(slider)
	)


func _write_readout(slider: Range) -> void:
	var readout := _readouts.get(slider, null) as Label
	if readout != null:
		readout.text = "%.4f" % slider.value


# --- the working look -------------------------------------------------------

## `ambient_tint` is not a field on LightingPreset: the fill is stored as a
## colour, and the reference panel's NAVY-GREY slider is how much of the snow
## tone that colour keeps. Derived on read, rebuilt on write, so the slider and
## the resource stay one value rather than two that can disagree.
func _value_of(field: StringName):
	if _look == null:
		return 0.0
	if field == &"ambient_tint":
		if _bible == null:
			return 0.0
		var snow: Color = _bible.snow_tones[0]
		if absf(1.0 - snow.r) < 0.0001:
			return 0.0
		return clampf((1.0 - _look.ambient_color.r) / (1.0 - snow.r), 0.0, 1.0)
	return _look.get(field)


func _set_value(field: StringName, value) -> void:
	if _look == null or _director == null:
		return
	if field == &"ambient_tint":
		if _bible != null:
			_look.ambient_color = Color.WHITE.lerp(_bible.snow_tones[0], float(value))
	else:
		_look.set(field, value)
	_director.apply_look(_look)
