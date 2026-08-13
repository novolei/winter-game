extends TestCase

## The consumers of the pause menu's accessibility settings -- UI design
## document section 4.2.
##
## The UILayer applies prompt_hold as a time-scale multiplier that COMPOSES
## with the weather's own scale, and stroke_bold as a stroke scale the
## InteractionPrompt honors when it draws its ring. The layer also registers
## itself with the ServiceRegistry so the menu can push changes at it without
## a scene path.

const UILayerScript := preload("res://src/ui/ui_layer.gd")
const StoreScript := preload("res://src/ui/settings_store.gd")
const PromptScript := preload("res://src/ui/interaction_prompt.gd")
const ServiceRegistryScript := preload("res://src/core/service_registry.gd")

const TEST_PATH := "user://test_ui_settings_consumers.cfg"

var _layer: UILayer = null

func before_each() -> void:
	StoreScript.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	StoreScript.load_from(TEST_PATH)
	_layer = UILayerScript.new()
	_layer.build()

func after_each() -> void:
	if _layer != null:
		_layer.free()
		_layer = null
	StoreScript.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

func test_prompt_hold_scales_the_layers_clock() -> void:
	assert_almost_eq(_layer.preference_scale(), 1.0)
	StoreScript.store(&"prompt_hold", 2.0)
	_layer.apply_accessibility()
	assert_almost_eq(_layer.preference_scale(), 2.0)

func test_stroke_bold_doubles_the_stroke_scale() -> void:
	assert_almost_eq(_layer.stroke_scale(), 1.0)
	StoreScript.store(&"stroke_bold", 1.0)
	_layer.apply_accessibility()
	assert_almost_eq(_layer.stroke_scale(), 2.0)

func test_the_layer_registers_itself_for_the_menu_to_find() -> void:
	var registry = ServiceRegistryScript.new()
	_layer.register_with(registry)
	assert_eq(registry.get_service(UILayer.SERVICE_KEY), _layer)
	registry.free()

func test_the_prompt_accepts_a_stroke_scale() -> void:
	var prompt = PromptScript.new()
	assert_almost_eq(prompt.stroke_scale(), 1.0)
	prompt.set_stroke_scale(2.0)
	assert_almost_eq(prompt.stroke_scale(), 2.0)
	prompt.set_stroke_scale(-1.0)
	assert_almost_eq(prompt.stroke_scale(), 2.0, 0.0001, "an illegal scale must be refused")
	prompt.free()
