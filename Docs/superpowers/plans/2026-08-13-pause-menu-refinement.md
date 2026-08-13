# 暂停菜单（ESC）精修实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 [2026-08-13-pause-menu-refinement-design.md](../specs/2026-08-13-pause-menu-refinement-design.md) 为 ESC 暂停面板补全「设置」入口（三项无障碍设置）并升级动效编排与焦点反馈，保持纪念碑谷式的空间排版架构。

**Architecture:** 数据驱动设置（`AccessibilityCatalog` + `SettingsStore` 静态持久化）；`ExitMenu`（Canvas 命中层）增加第三状态；`SpatialPauseMenu`（3D 排版）从目录构建设置行；新增纯函数 `PauseChoreography` 驱动级联动效，测试可无帧驱动。

**Tech Stack:** Godot 4.7.1 GDScript、FontVariation（wght 轴）、ConfigFile（user://）、项目自研 TestCase 框架。

## Global Constraints

- 测试命令：`bash tools/run_tests.sh <预期通过数>`。**基线 2238 通过**（2026-08-13 实测，控制台干净）。每个任务结束跑全套，控制台必须零 WARNING/ERROR。
- 任何颜色只准来自 `data/ui/tokens.tres`（`UITokens`），测试里允许硬编码期望值。
- 新增文件英文 snake_case；`.gd`/`.tres` 保持 LF 行尾。
- 不碰 `src/core/` 的语义（`ServiceRegistry` 只读用）。
- Godot 控制台可执行文件：`D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe`。
- 提交信息风格：简短祈使句英文（如 `Add pause settings catalog`），**不要** conventional-commits 前缀。
- 无头测试模式：`ExitMenu`/`UILayer` 在测试里不进入 SceneTree，所有动画路径必须在 `not is_inside_tree()` 时同步落到终态（现有 `test_the_cinematic_push_is_reversible` 等依赖此行为）。

## 关键背景（实现者必读）

- `ExitMenu`（[src/ui/exit_menu.gd](../../../src/ui/exit_menu.gd)）：CanvasLayer，`build()` 可无树调用；`_show_confirmation(show, animate)` 管理确认页；`_animate_open()`/`close()` 的 Tween 在 `is_inside_tree()` 为假时直接落终态。
- `SpatialPauseMenu`（[src/ui/spatial_pause_menu.gd](../../../src/ui/spatial_pause_menu.gd)）：Label3D + 细线 QuadMesh，`_update_projection()` 把屏幕像素目标投到相机前方；`_apply_alpha()` 统一乘 `_alpha`。
- `UIFonts.display_at(latin, cjk)` / `interface_at(latin, cjk, spacing)`：重建指定字重的字体链（已是公共 API）。
- `UIAudio.play(cue_id)`：现有 cue：`ui.bloom`、`ui.confirm`、`ui.back`、`ui.move`。
- 测试基类 `TestCase` 断言：`assert_true/assert_false/assert_eq/assert_almost_eq/assert_not_null`（`message` 为末参）。测试文件放 `tests/unit/test_*.gd`，方法名 `test_*`，自动发现。
- **每个测试方法必须至少触发一次断言**（零断言计为失败）。

---

### Task 1: 设置数据模型（定义 + 目录 tres）

**Files:**
- Create: `src/definitions/accessibility_setting.gd`
- Create: `src/definitions/accessibility_catalog.gd`
- Create: `data/ui/accessibility_settings.tres`
- Test: `tests/unit/test_accessibility_settings.gd`

**Interfaces:**
- Produces: `AccessibilitySetting`（`id/label/is_toggle/minimum/maximum/step/default_value`，`clamp_value(v)`, `stepped(v, dir)`, `format_value(v)`, `tick_count()`, `fraction_of(v)`）；`AccessibilityCatalog.entries` + `find(id)`；`AccessibilityCatalog.CATALOG_PATH = "res://data/ui/accessibility_settings.tres"`。

- [ ] **Step 1: 写失败测试**

```gdscript
extends TestCase

const CatalogScript := preload("res://src/definitions/accessibility_catalog.gd")

var _catalog: AccessibilityCatalog = null

func before_each() -> void:
	_catalog = ResourceLoader.load(CatalogScript.CATALOG_PATH) as AccessibilityCatalog

func test_the_catalog_loads_with_three_entries() -> void:
	assert_not_null(_catalog, "accessibility_settings.tres did not load as a catalog")
	assert_eq(_catalog.entries.size(), 3)

func test_the_three_authored_settings_are_present() -> void:
	for id in [&"prompt_hold", &"stroke_bold", &"screen_shake"]:
		assert_not_null(_catalog.find(id), "catalog is missing %s" % id)

func test_prompt_hold_carries_the_authored_range() -> void:
	var setting := _catalog.find(&"prompt_hold")
	assert_almost_eq(setting.minimum, 0.5)
	assert_almost_eq(setting.maximum, 3.0)
	assert_almost_eq(setting.step, 0.25)
	assert_almost_eq(setting.default_value, 1.0)
	assert_false(setting.is_toggle)
	assert_eq(setting.tick_count(), 11)

func test_the_toggles_carry_the_authored_defaults() -> void:
	assert_almost_eq(_catalog.find(&"stroke_bold").default_value, 0.0,
		"stroke bold defaults off (UI document section 4.2)")
	assert_almost_eq(_catalog.find(&"screen_shake").default_value, 1.0,
		"screen shake defaults on (UI document section 4.2)")
	assert_true(_catalog.find(&"stroke_bold").is_toggle)
	assert_eq(_catalog.find(&"stroke_bold").tick_count(), 2)

func test_values_clamp_step_and_format() -> void:
	var hold := _catalog.find(&"prompt_hold")
	assert_almost_eq(hold.clamp_value(99.0), 3.0)
	assert_almost_eq(hold.stepped(3.0, 1), 3.0, "stepping past the top must clamp, not wrap")
	assert_almost_eq(hold.stepped(1.0, 1), 1.25)
	assert_eq(hold.format_value(1.0), "1×")
	assert_eq(hold.format_value(1.25), "1.25×")
	var toggle := _catalog.find(&"stroke_bold")
	assert_eq(toggle.format_value(0.0), "关")
	assert_eq(toggle.format_value(1.0), "开")
	assert_almost_eq(toggle.stepped(0.0, 1), 1.0)
	assert_almost_eq(toggle.stepped(1.0, -1), 0.0)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tools/run_tests.sh 2243`
Expected: FAIL — `Parse Error` / catalog loads as null。

- [ ] **Step 3: 实现**

`src/definitions/accessibility_setting.gd`:

```gdscript
class_name AccessibilitySetting
extends Resource

## One row of the pause menu's settings page (UI document section 4.2).
## Adding a setting is a .tres entry, never a .gd change.

@export var id: StringName = &""
@export var label: String = ""
@export var is_toggle := false
@export var minimum := 0.0
@export var maximum := 1.0
@export var step := 0.25
@export var default_value := 0.0

func clamp_value(value: float) -> float:
	return clampf(value, minimum, maximum)

func stepped(value: float, direction: int) -> float:
	if is_toggle:
		return 0.0 if value >= 0.5 else 1.0
	if direction == 0:
		return clamp_value(value)
	return clamp_value(value + step * signi(direction))

func format_value(value: float) -> String:
	if is_toggle:
		return "开" if value >= 0.5 else "关"
	var clamped := clamp_value(value)
	var text := "%.2f" % clamped
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text + "×"

func tick_count() -> int:
	if is_toggle or step <= 0.0:
		return 2
	return int(roundf((maximum - minimum) / step)) + 1

func fraction_of(value: float) -> float:
	if maximum <= minimum:
		return 0.0
	return clampf((clamp_value(value) - minimum) / (maximum - minimum), 0.0, 1.0)
```

`src/definitions/accessibility_catalog.gd`:

```gdscript
class_name AccessibilityCatalog
extends Resource

## The settings the pause menu offers, in display order.

const CATALOG_PATH := "res://data/ui/accessibility_settings.tres"

@export var entries: Array[AccessibilitySetting] = []

func find(setting_id: StringName) -> AccessibilitySetting:
	for entry in entries:
		if entry != null and entry.id == setting_id:
			return entry
	return null
```

`data/ui/accessibility_settings.tres`（手写，LF；`stepped` 的 toggle 翻转语义由类保证）:

```ini
[gd_resource type="Resource" script_class="AccessibilityCatalog" load_steps=5 format=3]

[ext_resource type="Script" path="res://src/definitions/accessibility_setting.gd" id="1_setting"]
[ext_resource type="Script" path="res://src/definitions/accessibility_catalog.gd" id="2_catalog"]

[sub_resource type="Resource" id="Setting_prompt_hold"]
script = ExtResource("1_setting")
id = &"prompt_hold"
label = "提示停留时长"
is_toggle = false
minimum = 0.5
maximum = 3.0
step = 0.25
default_value = 1.0

[sub_resource type="Resource" id="Setting_stroke_bold"]
script = ExtResource("1_setting")
id = &"stroke_bold"
label = "提示笔画加粗"
is_toggle = true
minimum = 0.0
maximum = 1.0
step = 1.0
default_value = 0.0

[sub_resource type="Resource" id="Setting_screen_shake"]
script = ExtResource("1_setting")
id = &"screen_shake"
label = "屏 幕 震 动"
is_toggle = true
minimum = 0.0
maximum = 1.0
step = 1.0
default_value = 1.0

[resource]
script = ExtResource("2_catalog")
entries = Array[ExtResource("1_setting")]([SubResource("Setting_prompt_hold"), SubResource("Setting_stroke_bold"), SubResource("Setting_screen_shake")])
```

注意：`signi` 不存在于 GDScript——用 `sign(direction)`（返回 float）或 `int(signf(float(direction)))`。**正确写法**是 `step * signf(float(direction))`。修正上面的 `stepped`：

```gdscript
	return clamp_value(value + step * signf(float(direction)))
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tools/run_tests.sh 2243`
Expected: PASS，控制台干净（若通过数不是 2243，以实际为准更新后续任务的数字）。

- [ ] **Step 5: 提交**

```bash
git add src/definitions/accessibility_setting.gd src/definitions/accessibility_catalog.gd data/ui/accessibility_settings.tres tests/unit/test_accessibility_settings.gd
git commit -m "Add accessibility settings catalog"
```

---

### Task 2: SettingsStore 持久化

**Files:**
- Create: `src/ui/settings_store.gd`
- Test: `tests/unit/test_settings_store.gd`

**Interfaces:**
- Consumes: 无（Task 1 的 id 以 StringName 传入，不依赖目录）。
- Produces: `SettingsStore.load_from(path) -> int`、`SettingsStore.value(id, fallback) -> float`、`SettingsStore.store(id, v)`、`SettingsStore.reset()`；`SettingsStore.DEFAULT_PATH = "user://ui_settings.cfg"`。

- [ ] **Step 1: 写失败测试**

```gdscript
extends TestCase

const StoreScript := preload("res://src/ui/settings_store.gd")

const TEST_PATH := "user://test_ui_settings.cfg"

func before_each() -> void:
	StoreScript.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

func after_each() -> void:
	StoreScript.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

func test_missing_file_yields_defaults() -> void:
	assert_eq(StoreScript.load_from(TEST_PATH), 0)
	assert_almost_eq(StoreScript.value(&"prompt_hold", 1.0), 1.0)

func test_store_then_value_round_trips() -> void:
	StoreScript.load_from(TEST_PATH)
	StoreScript.store(&"prompt_hold", 2.5)
	assert_almost_eq(StoreScript.value(&"prompt_hold", 1.0), 2.5)

func test_values_survive_a_fresh_load() -> void:
	StoreScript.load_from(TEST_PATH)
	StoreScript.store(&"stroke_bold", 1.0)
	StoreScript.reset()
	assert_eq(StoreScript.load_from(TEST_PATH), 1)
	assert_almost_eq(StoreScript.value(&"stroke_bold", 0.0), 1.0)

func test_a_corrupt_file_falls_back_to_defaults_without_noise() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{{{{ not a config file")
	file.close()
	assert_eq(StoreScript.load_from(TEST_PATH), 0)
	assert_almost_eq(StoreScript.value(&"screen_shake", 1.0), 1.0)

func test_unknown_ids_return_the_callers_fallback() -> void:
	StoreScript.load_from(TEST_PATH)
	assert_almost_eq(StoreScript.value(&"no_such_setting", 0.75), 0.75)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tools/run_tests.sh 2248`
Expected: FAIL — `preload("res://src/ui/settings_store.gd")` 解析失败。

- [ ] **Step 3: 实现 `src/ui/settings_store.gd`**

```gdscript
class_name SettingsStore
extends RefCounted

## The pause menu settings' home on disk. Static, because the menu, the UI
## layer and future consumers all read the same three values and none of them
## should own the others. ConfigFile, not Resource serialization: a player can
## hand-edit it, and a corrupt file is dropped wholesale back to defaults.

const DEFAULT_PATH := "user://ui_settings.cfg"
const SECTION := "accessibility"

static var _values: Dictionary = {}
static var _path := DEFAULT_PATH
static var _loaded := false

## Reads the file. Missing or corrupt is a legal, silent zero -- the defaults
## in the catalog are the fallback, and the player never sees an error.
static func load_from(path := DEFAULT_PATH) -> int:
	_path = path
	_values = {}
	_loaded = true
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return 0
	var count := 0
	for key in file.get_section_keys(SECTION):
		_values[StringName(key)] = float(file.get_value(SECTION, key, 0.0))
		count += 1
	return count

static func value(id: StringName, fallback: float) -> float:
	if not _loaded:
		load_from()
	return float(_values.get(id, fallback))

static func store(id: StringName, new_value: float) -> void:
	if not _loaded:
		load_from()
	_values[id] = new_value
	var file := ConfigFile.new()
	# Merge whatever is on disk so a hand edit to another key survives.
	file.load(_path)
	file.set_value(SECTION, String(id), new_value)
	file.save(_path)

## Test seam: drops the static state so the next value() re-reads from disk.
static func reset() -> void:
	_values = {}
	_path = DEFAULT_PATH
	_loaded = false
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tools/run_tests.sh 2248`
Expected: PASS，控制台干净。

- [ ] **Step 5: 提交**

```bash
git add src/ui/settings_store.gd tests/unit/test_settings_store.gd
git commit -m "Add settings persistence store"
```

---

### Task 3: 消费方接入（UILayer 停留时长/笔画缩放 + InteractionPrompt 笔画）

**Files:**
- Modify: `src/ui/ui_layer.gd`（apply_accessibility、服务注册、advance 组合乘子）
- Modify: `src/ui/interaction_prompt.gd`（`set_stroke_scale` + `_draw` 两处线宽）
- Modify: `src/ui/interaction_director.gd:197-217`（建 prompt 后传入 stroke_scale）
- Test: `tests/unit/test_accessibility_consumers.gd`

**Interfaces:**
- Consumes: `SettingsStore.value/store/reset`（Task 2）。
- Produces: `UILayer.apply_accessibility()`、`UILayer.preference_scale() -> float`、`UILayer.stroke_scale() -> float`、`UILayer.register_with(registry)`、`UILayer.SERVICE_KEY = &"ui_layer"`；`InteractionPrompt.set_stroke_scale(s)` / `stroke_scale()`。

- [ ] **Step 1: 写失败测试**

```gdscript
extends TestCase

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
	assert_almost_eq(prompt.stroke_scale(), 2.0, "an illegal scale must be refused")
	prompt.free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tools/run_tests.sh 2252`
Expected: FAIL — `preference_scale` 等方法不存在（方法调用失败会计为测试失败或解析错误）。

- [ ] **Step 3: 实现**

`src/ui/ui_layer.gd` 修改：

```gdscript
# 常量区追加（LAYER_ORDER 之后）:
## Registered so the pause menu can push accessibility changes without a
## scene path. Same pattern as CameraRig's "camera_rig" entry.
const SERVICE_KEY := &"ui_layer"

# 成员区追加:
var _preference_scale := 1.0
var _stroke_scale := 1.0
```

`_ready()` 改为：

```gdscript
func _ready() -> void:
	if _tokens == null:
		build()
	register_with(get_node_or_null("/root/ServiceRegistry"))
```

`build()` 末尾（`_performance_overlay` 块之后）追加：

```gdscript
	apply_accessibility()
```

新增方法（放在 `set_time_scale` 之后）：

```gdscript
## Section 4.2's reading aids, re-read from the store. The prompt-hold
## preference COMPOSES with the weather's time scale in advance(): neither
## overwrites the other.
func apply_accessibility() -> void:
	_preference_scale = clampf(SettingsStore.value(&"prompt_hold", 1.0), 0.5, 3.0)
	_stroke_scale = 2.0 if SettingsStore.value(&"stroke_bold", 0.0) >= 0.5 else 1.0

func preference_scale() -> float:
	return _preference_scale

func stroke_scale() -> float:
	return _stroke_scale

func register_with(registry) -> void:
	if registry != null:
		registry.register(SERVICE_KEY, self)
```

文件顶部加 preload（放在 `PerformanceOverlayScript` 行旁）：

```gdscript
const SettingsStoreScript := preload("res://src/ui/settings_store.gd")
```

并把上面 `apply_accessibility` 里的 `SettingsStore.` 全部写成 `SettingsStoreScript.`（`class_name` 全局可用，但本文件测试环境 preload 顺序更稳，二者皆可；**选 preload，与本文件既有风格一致**）。

`advance()` 的 step 行改为组合乘子：

```gdscript
	var step := delta / (_time_scale * _preference_scale)
```

`src/ui/interaction_prompt.gd` 修改——成员区（`_ground` 附近）追加：

```gdscript
var _stroke_scale := 1.0
```

新增方法（`set_ground` 后）：

```gdscript
## UI document section 4.2's stroke-bold aid: every stroke this prompt draws
## doubles. Refused values leave the current scale alone.
func set_stroke_scale(scale: float) -> void:
	if not is_finite(scale) or scale <= 0.0:
		return
	_stroke_scale = scale
	queue_redraw()

func stroke_scale() -> float:
	return _stroke_scale
```

`_draw()` 两处线宽改为乘以 `_stroke_scale`：

```gdscript
		maxf(_px(RING_GROOVE_DESIGN_PX) * _stroke_scale, 1.0), true
	)
```
和 `draw_arc(... ink,` 那处的 `maxf(_px(RING_STROKE_DESIGN_PX), 1.0),` 改为：

```gdscript
		maxf(_px(RING_STROKE_DESIGN_PX) * _stroke_scale, 1.0),
```

`src/ui/interaction_director.gd` `_rebuild_prompt()`：在 `prompt.set_world_anchor(...)` 之前插入：

```gdscript
	prompt.set_stroke_scale(_layer.stroke_scale())
```

（`_layer` 已是 UILayer——`get_parent() as UILayer`，见该文件 35 行。）

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tools/run_tests.sh 2252`
Expected: PASS，控制台干净。

- [ ] **Step 5: 提交**

```bash
git add src/ui/ui_layer.gd src/ui/interaction_prompt.gd src/ui/interaction_director.gd tests/unit/test_accessibility_consumers.gd
git commit -m "Wire accessibility settings into the UI layer"
```

---

### Task 4: ExitMenu 设置状态（Canvas 命中层 + 导航）

**Files:**
- Modify: `src/ui/exit_menu.gd`
- Modify: `data/audio/ui_sounds.tres`（追加 `ui.boundary` cue）
- Test: `tests/unit/test_pause_settings_state.gd`

**Interfaces:**
- Consumes: `AccessibilityCatalog`/`AccessibilitySetting`（Task 1）、`SettingsStore`（Task 2）、`UILayer.SERVICE_KEY` + `apply_accessibility`（Task 3）。
- Produces: `ExitMenu.open_settings()`、`ExitMenu.close_settings()`、`ExitMenu.is_adjusting() -> bool`（设置页是否为当前状态）、`ExitMenu.settings_button() -> Button`、`ExitMenu.settings_row_buttons() -> Array`、`ExitMenu.adjust_focused(direction) -> bool`、`ExitMenu.state() -> StringName`（`&"menu"`/`&"settings"`/`&"confirm"`）。

- [ ] **Step 1: 写失败测试**

```gdscript
extends TestCase

const ExitMenuScript := preload("res://src/ui/exit_menu.gd")
const StoreScript := preload("res://src/ui/settings_store.gd")

const TEST_PATH := "user://test_ui_settings_menu.cfg"

var _menu = null

func before_each() -> void:
	StoreScript.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	StoreScript.load_from(TEST_PATH)
	_menu = ExitMenuScript.new()
	_menu.set_quit_action(func() -> void: pass)
	_menu.build()

func after_each() -> void:
	if _menu != null:
		_menu.free()
		_menu = null
	StoreScript.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

func test_the_menu_offers_settings_between_continue_and_exit() -> void:
	_menu.toggle()
	assert_not_null(_menu.settings_button())
	assert_eq(_menu.settings_button().text, "设　置")
	assert_eq(_menu.state(), &"menu")

func test_opening_settings_swaps_the_state_without_closing() -> void:
	_menu.toggle()
	_menu.open_settings()
	assert_true(_menu.is_open())
	assert_eq(_menu.state(), &"settings")
	assert_true(_menu.is_adjusting())
	assert_false(_menu.is_confirming())

func test_escape_from_settings_returns_to_the_menu() -> void:
	_menu.toggle()
	_menu.open_settings()
	_menu.handle_cancel()
	assert_eq(_menu.state(), &"menu")
	_menu.handle_cancel()
	assert_false(_menu.is_open(), "escape from the menu still closes the pause")

func test_the_rows_come_from_the_catalog() -> void:
	_menu.toggle()
	_menu.open_settings()
	var rows: Array = _menu.settings_row_buttons()
	assert_eq(rows.size(), 3)
	assert_true((rows[0] as Button).text.begins_with("提示停留时长"))

func test_adjusting_writes_through_and_clamps() -> void:
	_menu.toggle()
	_menu.open_settings()
	# 焦点默认在第一行（prompt_hold，默认 1.0）
	assert_true(_menu.adjust_focused(1))
	assert_almost_eq(StoreScript.value(&"prompt_hold", 1.0), 1.25)
	for i in range(20):
		_menu.adjust_focused(1)
	assert_almost_eq(StoreScript.value(&"prompt_hold", 1.0), 3.0)
	assert_false(_menu.adjust_focused(1), "at the ceiling a step must refuse, not wrap")

func test_row_text_reflects_the_stored_value() -> void:
	_menu.toggle()
	_menu.open_settings()
	_menu.adjust_focused(1)
	var rows: Array = _menu.settings_row_buttons()
	assert_true((rows[0] as Button).text.contains("1.25×"))
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tools/run_tests.sh 2258`
Expected: FAIL — `settings_button` 等方法不存在。

- [ ] **Step 3: 实现**

`data/audio/ui_sounds.tres`：追加一个 cue（`load_steps` 计数 +1，`cues` 数组追加 `SubResource("Resource_boundary")`）：

```ini
[sub_resource type="Resource" id="Resource_boundary"]
script = ExtResource("1_ufs2m")
cue_id = &"ui.boundary"
stream_path = "res://assets/audio/ui/button_press.wav"
gain_db = -12.0
pitch_scale = 0.6674
notes = "档位边界。The confirm sound seven semitones down -- a wall, not an error."
```

`src/ui/exit_menu.gd` 修改：

顶部常量区追加：

```gdscript
const CATALOG_PATH := "res://data/ui/accessibility_settings.tres"
const STATE_MENU := &"menu"
const STATE_SETTINGS := &"settings"
const STATE_CONFIRM := &"confirm"
```

成员区追加：

```gdscript
var _catalog: AccessibilityCatalog = null
var _settings_button: Button = null
var _settings_panel: VBoxContainer = null
var _settings_rows: Array = []          # Button，每行一个
var _settings_row_settings: Array = []  # 对应的 AccessibilitySetting
var _focused_setting: AccessibilitySetting = null
var _state: StringName = STATE_MENU
var _ui_layer = null
```

`build()` 中（`_spatial.setup(...)` 之后）加载目录：

```gdscript
	_catalog = ResourceLoader.load(CATALOG_PATH) as AccessibilityCatalog
```

`_build_states()` 中，在 `_continue_button` 与 `_exit_button` 之间插入设置按钮：

```gdscript
	_settings_button = _make_choice("设　置", 104.0)
	_settings_button.name = "Settings"
	_settings_button.pressed.connect(open_settings)
	_menu_panel.add_child(_settings_button)
	_menu_panel.move_child(_settings_button, 1)
```

`_build_states()` 末尾构建设置面板：

```gdscript
	_settings_panel = VBoxContainer.new()
	_settings_panel.name = "AccessibilitySettings"
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_panel.visible = false
	_state_slot.add_child(_settings_panel)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "设　置"
	heading.add_theme_font_override("font", _fonts.display)
	heading.add_theme_color_override("font_color", _tokens.ink_primary)
	_settings_panel.add_child(heading)

	if _catalog != null:
		for setting in _catalog.entries:
			var row := _make_choice(_row_text(setting), 232.0)
			row.name = String(setting.id).to_pascal_case()
			row.pressed.connect(_on_setting_row_pressed.bind(setting))
			_settings_panel.add_child(row)
			_settings_rows.append(row)
			_settings_row_settings.append(setting)
```

新增方法：

```gdscript
func state() -> StringName:
	return _state

func is_adjusting() -> bool:
	return _settings_panel != null and _settings_panel.visible

func settings_button() -> Button:
	return _settings_button

func settings_row_buttons() -> Array:
	return _settings_rows

func open_settings() -> void:
	if not _is_open or _state != STATE_MENU:
		return
	_play(&"ui.confirm")
	_show_settings(true, is_inside_tree())

func close_settings() -> void:
	if not is_adjusting():
		return
	_play(&"ui.back")
	_show_settings(false, is_inside_tree())

## Left/right on a settings row. True when the value moved; at a boundary it
## refuses and sounds the wall instead of wrapping.
func adjust_focused(direction: int) -> bool:
	if not is_adjusting() or _focused_setting == null or direction == 0:
		return false
	var setting := _focused_setting
	var old := SettingsStore.value(setting.id, setting.default_value)
	var next := setting.stepped(old, direction)
	if is_equal_approx(next, old):
		_play(&"ui.boundary")
		return false
	SettingsStore.store(setting.id, next)
	_apply_setting(setting)
	_play(&"ui.move")
	return true
```

（文件顶部 preload 区追加 `const SettingsStoreScript := preload("res://src/ui/settings_store.gd")`，方法内用 `SettingsStoreScript.`；`_apply_setting`、`_row_text`、`_on_setting_row_pressed`、`_show_settings` 如下。）

```gdscript
func _row_text(setting: AccessibilitySetting) -> String:
	return "%s　%s" % [setting.label,
		setting.format_value(SettingsStoreScript.value(setting.id, setting.default_value))]

func _on_setting_row_pressed(setting: AccessibilitySetting) -> void:
	_focused_setting = setting
	adjust_focused(1)

func _apply_setting(setting: AccessibilitySetting) -> void:
	var index := _settings_row_settings.find(setting)
	if index >= 0:
		(_settings_rows[index] as Button).text = _row_text(setting)
	match setting.id:
		&"prompt_hold", &"stroke_bold":
			_resolve_ui_layer()
			if _ui_layer != null:
				_ui_layer.apply_accessibility()
		# screen_shake: persisted only -- the shake system it gates has not
		# shipped yet (DEFERRED).

func _resolve_ui_layer() -> void:
	if _ui_layer != null or not is_inside_tree():
		return
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null:
		_ui_layer = registry.get_service(UILayer.SERVICE_KEY)
```

`_show_settings`（镜像 `_show_confirmation` 的结构；级联动效在 Task 6 替换，这里先用与确认页相同的 bloom）：

```gdscript
func _show_settings(show: bool, animate: bool) -> void:
	_state = STATE_SETTINGS if show else STATE_MENU
	if _menu_panel != null:
		_menu_panel.visible = not show
	if _settings_panel != null:
		_settings_panel.visible = show
	if _hint_label != null:
		_hint_label.text = "ESC   返回暂停" if show else "ESC   返回风雪"
	if show and not _settings_row_settings.is_empty():
		_focused_setting = _settings_row_settings[0]
	var arriving: Control = _settings_panel if show else _menu_panel
	if animate and is_inside_tree() and arriving != null:
		arriving.modulate.a = 0.0
		var home := arriving.position
		arriving.position.y = home.y + 8.0 * _frame_scale
		var transition := create_tween().set_parallel(true)
		transition.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		transition.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		transition.tween_property(arriving, "modulate:a", 1.0, _tokens.bloom_seconds)
		transition.tween_property(arriving, "position:y", home.y, _tokens.bloom_seconds)
	else:
		if _menu_panel != null:
			_menu_panel.modulate.a = 1.0
		if _settings_panel != null:
			_settings_panel.modulate.a = 1.0
	if show and not _settings_rows.is_empty():
		_focus(_settings_rows[0])
	elif not show:
		_focus(_settings_button)
```

`handle_cancel()` 改为三级：

```gdscript
func handle_cancel() -> void:
	if not _is_open:
		open()
	elif is_adjusting():
		close_settings()
	elif is_confirming():
		cancel_exit()
	else:
		close(true)
```

`_unhandled_input` 增加左右调节：

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		handle_cancel()
		get_viewport().set_input_as_handled()
		return
	if is_adjusting():
		if event.is_action_pressed("ui_left"):
			adjust_focused(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right"):
			adjust_focused(1)
			get_viewport().set_input_as_handled()
```

`_show_confirmation()` 增加状态记账（开头一行）：

```gdscript
	_state = STATE_CONFIRM if show else STATE_MENU
```

`open()` 里 `_show_confirmation(false, false)` 已经把状态落回 `STATE_MENU`——确认 `_show_settings(false, false)` 也在 `open()` 中被调用一次以保证初始可见性：

```gdscript
	# open() 中 _show_confirmation(false, false) 之后追加:
	_show_settings(false, false)
```

键盘焦点链（`_build_states()` 末尾）：

```gdscript
	_continue_button.focus_neighbor_bottom = _continue_button.get_path_to(_settings_button)
	_settings_button.focus_neighbor_top = _settings_button.get_path_to(_continue_button)
	_settings_button.focus_neighbor_bottom = _settings_button.get_path_to(_exit_button)
	_exit_button.focus_neighbor_top = _exit_button.get_path_to(_settings_button)
	for i in range(_settings_rows.size()):
		var row: Button = _settings_rows[i]
		if i > 0:
			row.focus_neighbor_top = row.get_path_to(_settings_rows[i - 1])
		if i + 1 < _settings_rows.size():
			row.focus_neighbor_bottom = row.get_path_to(_settings_rows[i + 1])
```

`_on_choice_focus_entered` 中同步 `_focused_setting`：

```gdscript
func _on_choice_focus_entered(button: Button) -> void:
	_set_choice_line(button, true)
	var row_index := _settings_rows.find(button)
	if row_index >= 0:
		_focused_setting = _settings_row_settings[row_index]
	if _spatial != null:
		_spatial.set_focus(_spatial_choice_id(button))
	if _is_open:
		_play(&"ui.move")
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tools/run_tests.sh 2258`
Expected: PASS，控制台干净。

- [ ] **Step 5: 提交**

```bash
git add src/ui/exit_menu.gd data/audio/ui_sounds.tres tests/unit/test_pause_settings_state.gd
git commit -m "Add settings state to the pause menu"
```

---

### Task 5: SpatialPauseMenu 设置副本（3D 排版）

**Files:**
- Modify: `src/ui/spatial_pause_menu.gd`
- Modify: `src/ui/exit_menu.gd`（spatial 状态/焦点同步接线）
- Test: `tests/unit/test_spatial_pause_settings.gd`

**Interfaces:**
- Consumes: 目录（Task 1）、`ExitMenu._show_settings`（Task 4）。
- Produces: `SpatialPauseMenu.SETTINGS`（菜单项 id）、`SpatialPauseMenu.set_state(state: StringName)`（**替换**现有 bool 版，三态）、`SpatialPauseMenu.set_row_value(setting_id, formatted_text, fraction)`、`SpatialPauseMenu.row_label_ids() -> Array[StringName]`、`SpatialPauseMenu.track_quads() -> Array[MeshInstance3D]`。焦点 id 扩展：菜单项 `SETTINGS`，设置行 `StringName("row_%s" % setting.id)`。

- [ ] **Step 1: 写失败测试**

```gdscript
extends TestCase

const SpatialScript := preload("res://src/ui/spatial_pause_menu.gd")
const Tokens: UITokens = preload("res://data/ui/tokens.tres")

var _spatial: SpatialPauseMenu = null

func before_each() -> void:
	var fonts := UIFonts.new()
	fonts.build(Tokens)
	_spatial = SpatialScript.new()
	_spatial.setup(Tokens, fonts)

func after_each() -> void:
	if _spatial != null:
		_spatial.free()
		_spatial = null

func test_the_menu_gains_a_settings_choice() -> void:
	var found := false
	for label in _spatial.labels():
		if label.text == "设　置":
			found = true
	assert_true(found, "the spatial menu has no settings choice")

func test_settings_rows_are_built_from_the_catalog() -> void:
	var ids := _spatial.row_label_ids()
	assert_eq(ids.size(), 3)
	assert_true(ids.has(&"row_prompt_hold"))

func test_rows_hide_outside_the_settings_state() -> void:
	_spatial.set_state(&"settings")
	var visibility := {}
	for label in _spatial.labels():
		visibility[label.name] = label.visible
	_spatial.set_state(&"menu")
	for label in _spatial.labels():
		if String(label.name).begins_with("Row"):
			assert_false(label.visible, "%s stayed visible in the menu state" % label.name)

func test_tracks_and_ticks_are_depth_composited_quads() -> void:
	var quads := _spatial.track_quads()
	# 3 轨道 + 3 游标 + 11 + 2 + 2 刻度
	assert_eq(quads.size(), 21)
	for quad in quads:
		assert_true(quad.mesh is QuadMesh)
		var material := quad.material_override as StandardMaterial3D
		assert_not_null(material)
		assert_false(material.no_depth_test)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tools/run_tests.sh 2262`
Expected: FAIL — `row_label_ids`/`track_quads` 不存在。

- [ ] **Step 3: 实现**

`src/ui/spatial_pause_menu.gd` 修改：

常量区追加：

```gdscript
const SETTINGS := &"settings"
const STATE_MENU := &"menu"
const STATE_SETTINGS := &"settings"
const STATE_CONFIRM := &"confirm"
const CATALOG_PATH := "res://data/ui/accessibility_settings.tres"
const TRACK_WIDTH := 96.0     # 设计像素，设置行轨道
const TICK_WIDTH := 1.25
const TICK_HEIGHT := 5.0
const MARKER_WIDTH := 2.5
const MARKER_HEIGHT := 9.0
```

成员区追加：

```gdscript
var _catalog: AccessibilityCatalog = null
var _row_settings: Array = []                 # AccessibilitySetting
var _row_ids: Array[StringName] = []          # 名称 label id
var _row_value_ids: Array[StringName] = []    # 值 label id
var _row_fractions: Dictionary = {}           # id -> 0..1
var _tracks: Dictionary = {}                  # id -> MeshInstance3D（轨道/游标/刻度共用）
var _track_layouts: Dictionary = {}           # id -> Rect2（屏幕像素）
var _state: StringName = STATE_MENU
```

`setup()` 中（`_make_label(HINT, ...)` 之后）：

```gdscript
	_make_label(SETTINGS, "设　置", fonts.display, tokens.line_deep)
	_catalog = ResourceLoader.load(CATALOG_PATH) as AccessibilityCatalog
	if _catalog != null:
		for setting in _catalog.entries:
			var row_id := StringName("row_%s" % setting.id)
			var value_id := StringName("row_%s_value" % setting.id)
			_make_label(row_id, setting.label, fonts.interface, tokens.line_deep)
			_make_label(value_id, setting.format_value(setting.default_value),
				fonts.instrument, tokens.scrim_veil)
			_row_settings.append(setting)
			_row_ids.append(row_id)
			_row_value_ids.append(value_id)
			_row_fractions[setting.id] = setting.fraction_of(setting.default_value)
			_make_track(row_id)
			_make_track(value_id)  # 游标挂在 value id 上
			for tick in range(setting.tick_count()):
				_make_track(StringName("%s_tick_%d" % [row_id, tick]))
```

并把 SETTINGS 加入动作组倾斜：`_set_group_tilt([CONTINUE, SETTINGS, EXIT], Vector3(0.0, -0.087266, 0.017453))`（替换原 `[CONTINUE, EXIT]` 行）；设置行一组：名称+值 label 用 `Vector3(0.0, -0.10472, -0.017453)`（与 QUESTION 组同）。

`_make_track(id)`（细线 quad 的简化版，复用 `_make_line` 的材质模式但独立字典）：

```gdscript
func _make_track(id: StringName) -> void:
	var quad := MeshInstance3D.new()
	quad.name = String(id).to_pascal_case()
	quad.mesh = QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.albedo_color = _tokens.line_hairline
	quad.material_override = material
	add_child(quad)
	_tracks[id] = quad
	_track_layouts[id] = Rect2()
```

**`set_state` 改为三态**（替换现有 `set_state(confirming: bool)`）：

```gdscript
func set_state(state: StringName) -> void:
	_state = state
	_set_text(HINT, "ESC   返回暂停" if state != STATE_MENU else "ESC   返回风雪")
	match state:
		STATE_CONFIRM:
			set_focus(RETURN)
		STATE_SETTINGS:
			set_focus(_row_ids[0] if not _row_ids.is_empty() else CONTINUE)
		_:
			set_focus(CONTINUE)
	_apply_state_visibility()
```

`_apply_state_visibility()` 重写：

```gdscript
func _apply_state_visibility() -> void:
	if _labels.is_empty():
		return
	var in_menu := _state == STATE_MENU
	var in_confirm := _state == STATE_CONFIRM
	var in_settings := _state == STATE_SETTINGS
	for id in [CONTINUE, SETTINGS, EXIT]:
		(_labels[id] as Label3D).visible = in_menu
		(_lines[id] as MeshInstance3D).visible = in_menu
	for id in [QUESTION, CONSEQUENCE, RETURN, CONFIRM]:
		(_labels[id] as Label3D).visible = in_confirm
	for id in [RETURN, CONFIRM]:
		(_lines[id] as MeshInstance3D).visible = in_confirm
	for id in _row_ids + _row_value_ids:
		(_labels[id] as Label3D).visible = in_settings
	for id in _tracks.keys():
		(_tracks[id] as MeshInstance3D).visible = in_settings
	(_labels[HINT] as Label3D).visible = not _compact
```

注意：`_make_line` 的调用列表 `[CONTEXT_LINE, CONTINUE, EXIT, RETURN, CONFIRM]` 需加入 `SETTINGS`，`_set_choice_line(SETTINGS, 104.0 * frame_scale)` 加入 `layout()`。

`layout()` 中动作区重排（CONTINUE/SETTINGS/EXIT 三行）：

```gdscript
	_targets[CONTINUE] = Vector2(left, actions_top + 20.0 * frame_scale)
	_targets[SETTINGS] = Vector2(left, actions_top + 70.0 * frame_scale)
	_targets[EXIT] = Vector2(left, actions_top + 120.0 * frame_scale)
```

设置行布局（`layout()` 末尾，HINT 之前）：

```gdscript
	for i in range(_row_settings.size()):
		var row_top := actions_top + (16.0 + 52.0 * i) * frame_scale
		var row_id: StringName = _row_ids[i]
		var value_id: StringName = _row_value_ids[i]
		_targets[row_id] = Vector2(left, row_top)
		_targets[value_id] = Vector2(left + 148.0 * frame_scale, row_top)
		_label_sizes[row_id] = body_size
		_label_sizes[value_id] = body_size
		var track_y := row_top + 30.0 * frame_scale
		_track_layouts[row_id] = Rect2(left + 148.0 * frame_scale, track_y,
			TRACK_WIDTH * frame_scale, maxf(frame_scale, 1.0))
		var setting: AccessibilitySetting = _row_settings[i]
		var fraction: float = _row_fractions[setting.id]
		_track_layouts[value_id] = Rect2(
			left + (148.0 + TRACK_WIDTH * fraction) * frame_scale - MARKER_WIDTH * 0.5 * frame_scale,
			track_y - (MARKER_HEIGHT - 1.0) * 0.5 * frame_scale,
			MARKER_WIDTH * frame_scale, MARKER_HEIGHT * frame_scale)
		for tick in range(setting.tick_count()):
			var tick_fraction := float(tick) / float(maxi(setting.tick_count() - 1, 1))
			_track_layouts[StringName("%s_tick_%d" % [row_id, tick])] = Rect2(
				left + (148.0 + TRACK_WIDTH * tick_fraction) * frame_scale - TICK_WIDTH * 0.5 * frame_scale,
				track_y - (TICK_HEIGHT - 1.0) * 0.5 * frame_scale,
				TICK_WIDTH * frame_scale, TICK_HEIGHT * frame_scale)
```

`_update_projection()` 末尾追加轨道投影：

```gdscript
	for id in _tracks.keys():
		var track := _tracks[id] as MeshInstance3D
		if not track.visible:
			continue
		var rect := _track_layouts[id] as Rect2
		var quad := track.mesh as QuadMesh
		quad.size = Vector2(maxf(rect.size.x * world_per_pixel, 0.001),
			maxf(rect.size.y * world_per_pixel, 0.001))
		var track_transform := track.global_transform
		track_transform.origin = _camera.project_position(rect.get_center(), _depth - 0.01)
		track_transform.basis = _camera.global_transform.basis.orthonormalized() \
			* Basis.from_euler(_label_tilts.get(QUESTION, Vector3.ZERO) as Vector3)
		track.global_transform = track_transform
```

公开 API：

```gdscript
func row_label_ids() -> Array[StringName]:
	return _row_ids.duplicate()

func track_quads() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for raw in _tracks.values():
		result.append(raw as MeshInstance3D)
	return result

## The menu pushed a new value: refresh the value word and slide the marker.
func set_row_value(setting_id: StringName, formatted: String, fraction: float) -> void:
	var value_id := StringName("row_%s_value" % setting_id)
	_set_text(value_id, formatted)
	_row_fractions[setting_id] = clampf(fraction, 0.0, 1.0)
```

焦点扩展——`set_focus()` 的候选列表加入 SETTINGS 与行 id：

```gdscript
func set_focus(id: StringName) -> void:
	_focus = id
	for choice in [CONTINUE, SETTINGS, EXIT, RETURN, CONFIRM]:
		var focused: bool = choice == id
		_line_targets[choice] = 1.0 if focused else 0.0
		_label_colours[choice] = _tokens.scrim_veil if focused else _tokens.line_deep
	for i in range(_row_ids.size()):
		var focused: bool = _row_ids[i] == id
		_label_colours[_row_ids[i]] = _tokens.scrim_veil if focused else _tokens.line_deep
		_label_colours[_row_value_ids[i]] = _tokens.scrim_veil if focused else _tokens.line_deep
	_apply_alpha()
```

`ExitMenu` 接线（exit_menu.gd）：
- `_show_settings()` 中追加 `_spatial.set_state(&"settings" if show else &"menu")`（替换/并立于确认页的 `_spatial.set_state(show)`——把 `_show_confirmation` 里的调用改为 `_spatial.set_state(&"confirm" if show else &"menu")`）。
- `_apply_setting()` 末尾追加：

```gdscript
	if _spatial != null:
		_spatial.set_row_value(setting.id, setting.format_value(
			SettingsStoreScript.value(setting.id, setting.default_value)),
			setting.fraction_of(SettingsStoreScript.value(setting.id, setting.default_value)))
```

- `_spatial_choice_id()` 中 settings 按钮映射：

```gdscript
	if button == _settings_button:
		return SpatialPauseMenu.SETTINGS
```

- 设置行按钮的 spatial 焦点 id：`_on_choice_focus_entered` 中 row 分支用 `StringName("row_%s" % _settings_row_settings[row_index].id)` 调 `_spatial.set_focus()`（覆盖默认的 `_spatial_choice_id` 结果）。

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tools/run_tests.sh 2262`
Expected: PASS，控制台干净。

- [ ] **Step 5: 提交**

```bash
git add src/ui/spatial_pause_menu.gd src/ui/exit_menu.gd tests/unit/test_spatial_pause_settings.gd
git commit -m "Add spatial settings copy to the pause surface"
```

---

### Task 6: PauseChoreography 级联动效

**Files:**
- Create: `src/ui/pause_choreography.gd`
- Modify: `src/ui/spatial_pause_menu.gd`（per-line envelope 通道）
- Modify: `src/ui/exit_menu.gd`（`_animate_open`/`close`/`_show_settings`/`_show_confirmation` 改走编排）
- Test: `tests/unit/test_pause_choreography.gd`

**Interfaces:**
- Consumes: Task 5 的三态 spatial；`UITokens.bloom_seconds/drift_fast_seconds`。
- Produces: `PauseChoreography.opening(tokens, ids)`、`PauseChoreography.closing(tokens, ids)`、`total_seconds()`、`alpha_at(i, t)`、`offset_at(i, t)`；`SpatialPauseMenu.set_line_envelope(id, alpha, y_offset_px)`、`SpatialPauseMenu.reset_envelopes(ids)`。

- [ ] **Step 1: 写失败测试**

```gdscript
extends TestCase

const ChoreographyScript := preload("res://src/ui/pause_choreography.gd")
const Tokens: UITokens = preload("res://data/ui/tokens.tres")

const IDS: Array[StringName] = [&"status", &"line", &"caption", &"a", &"b", &"c"]

func test_stagger_derives_from_the_bloom_token() -> void:
	var schedule = ChoreographyScript.opening(Tokens, IDS)
	assert_almost_eq(schedule.stagger_seconds, Tokens.bloom_seconds * 0.35)
	assert_almost_eq(schedule.line_seconds, Tokens.bloom_seconds)

func test_lines_bloom_in_order() -> void:
	var schedule = ChoreographyScript.opening(Tokens, IDS)
	var t := schedule.stagger_seconds * 2.5
	assert_almost_eq(schedule.alpha_at(0, t), 1.0)
	assert_almost_eq(schedule.alpha_at(1, t), 1.0)
	var mid := schedule.alpha_at(2, t)
	assert_true(mid > 0.0 and mid < 1.0, "the third line should be mid-bloom, got %f" % mid)
	assert_almost_eq(schedule.alpha_at(5, t), 0.0, "the last line has not started")

func test_a_line_rises_into_place_as_it_blooms() -> void:
	var schedule = ChoreographyScript.opening(Tokens, IDS)
	assert_almost_eq(schedule.offset_at(0, 0.0), 8.0)
	assert_almost_eq(schedule.offset_at(0, schedule.line_seconds), 0.0)

func test_total_covers_the_last_lines_bloom() -> void:
	var schedule = ChoreographyScript.opening(Tokens, IDS)
	var expected := schedule.stagger_seconds * 5.0 + schedule.line_seconds
	assert_almost_eq(schedule.total_seconds(), expected)

func test_closing_is_the_exact_reverse() -> void:
	var schedule = ChoreographyScript.closing(Tokens, IDS)
	assert_eq(schedule.lines[0], &"c", "the last line leaves first")
	assert_eq(schedule.lines[5], &"status", "the status line leaves last")
	assert_almost_eq(schedule.alpha_at(0, 0.0), 1.0)
	assert_almost_eq(schedule.alpha_at(0, schedule.line_seconds), 0.0)
	assert_true(schedule.offset_at(0, schedule.line_seconds) < 0.0,
		"closing lines drift upward")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tools/run_tests.sh 2267`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: 实现**

`src/ui/pause_choreography.gd`：

```gdscript
class_name PauseChoreography
extends RefCounted

## The stagger schedule behind the pause surface's cascade (design spec
## section 2.1/2.4). A pure function of time: ExitMenu drives it from one
## tween, and a test drives it with no frames at all.
##
## Opening: each line blooms (opacity 0 -> 1, +8px -> home, QUINT OUT),
## starting stagger_seconds after the line before it.
## Closing: the same lines in EXACT reverse, drifting up and out (QUAD IN).

const STAGGER_RATIO := 0.35
const RISE_PIXELS := 8.0

var lines: Array[StringName] = []
var stagger_seconds := 0.07
var line_seconds := 0.20
var is_closing := false

static func opening(tokens: UITokens, ids: Array[StringName]) -> PauseChoreography:
	var schedule := PauseChoreography.new()
	schedule.lines = ids.duplicate()
	schedule.line_seconds = tokens.bloom_seconds
	schedule.stagger_seconds = tokens.bloom_seconds * STAGGER_RATIO
	schedule.is_closing = false
	return schedule

static func closing(tokens: UITokens, ids: Array[StringName]) -> PauseChoreography:
	var schedule := PauseChoreography.new()
	schedule.lines = ids.duplicate()
	schedule.lines.reverse()
	schedule.line_seconds = tokens.drift_fast_seconds
	schedule.stagger_seconds = tokens.drift_fast_seconds * STAGGER_RATIO
	schedule.is_closing = true
	return schedule

func start_at(index: int) -> float:
	return stagger_seconds * index

func total_seconds() -> float:
	return stagger_seconds * maxi(lines.size() - 1, 0) + line_seconds

func alpha_at(index: int, t: float) -> float:
	var p := _eased(_progress_at(index, t))
	return (1.0 - p) if is_closing else p

func offset_at(index: int, t: float) -> float:
	var p := _eased(_progress_at(index, t))
	# Opening settles AT home from +8 below; closing leaves home upward.
	return (-p * RISE_PIXELS) if is_closing else ((1.0 - p) * RISE_PIXELS)

func _progress_at(index: int, t: float) -> float:
	if index < 0 or index >= lines.size() or line_seconds <= 0.0:
		return 1.0
	return clampf((t - start_at(index)) / line_seconds, 0.0, 1.0)

func _eased(p: float) -> float:
	# QUINT OUT to arrive, QUAD IN to leave -- the tween curves the menu
	# already uses, written out so no Tween is needed to evaluate them.
	return p * p if is_closing else 1.0 - pow(1.0 - p, 5.0)
```

`src/ui/spatial_pause_menu.gd`——per-line envelope 通道：

成员区追加：

```gdscript
var _envelope_alpha: Dictionary = {}    # id -> 0..1 乘子（默认 1）
var _envelope_offset: Dictionary = {}   # id -> y 像素偏移（默认 0）
```

新增：

```gdscript
## The cascade's handle on one line. Alpha multiplies every colour channel the
## line owns; offset shifts its projected home in screen pixels.
func set_line_envelope(id: StringName, alpha: float, y_offset: float) -> void:
	_envelope_alpha[id] = clampf(alpha, 0.0, 1.0)
	_envelope_offset[id] = y_offset
	_apply_alpha()
	_update_projection()

func reset_envelopes(ids: Array) -> void:
	for id in ids:
		_envelope_alpha[id] = 1.0
		_envelope_offset[id] = 0.0
	_apply_alpha()
	_update_projection()

func _envelope_alpha_for(id: StringName) -> float:
	return float(_envelope_alpha.get(id, 1.0))

func _envelope_offset_for(id: StringName) -> float:
	return float(_envelope_offset.get(id, 0.0))
```

`_apply_alpha()` 的 label 循环中 `fill.a *= _alpha` 改为：

```gdscript
		fill.a *= _alpha * _envelope_alpha_for(id)
```

（outline 同步：`outline.a *= _alpha * _envelope_alpha_for(id)`；细线材质循环同样乘 `_envelope_alpha_for(id)`。）

`_update_projection()` label 定位行改为带偏移：

```gdscript
		label_transform.origin = _camera.project_position(
			(_targets[id] as Vector2) + Vector2(0.0, _envelope_offset_for(id)), _depth)
```

`src/ui/exit_menu.gd`——级联驱动：

成员追加：

```gdscript
var _choreography = null   # PauseChoreography，打开/关闭期间持有
```

新增：

```gdscript
## The lines the open cascade breathes in, in order. Spatial ids; the canvas
## fallback maps them in _cascade_canvas_line().
func _cascade_ids() -> Array[StringName]:
	var ids: Array[StringName] = [
		SpatialPauseMenu.STATUS, SpatialPauseMenu.CONTEXT_LINE,
		SpatialPauseMenu.CAPTION, SpatialPauseMenu.TIME,
	]
	if _state == STATE_SETTINGS:
		for row_id in _spatial.row_label_ids() if _spatial != null else []:
			ids.append(row_id)
	elif _state == STATE_CONFIRM:
		ids.append_array([SpatialPauseMenu.QUESTION, SpatialPauseMenu.CONSEQUENCE,
			SpatialPauseMenu.RETURN, SpatialPauseMenu.CONFIRM])
	else:
		ids.append_array([SpatialPauseMenu.CONTINUE, SpatialPauseMenu.SETTINGS,
			SpatialPauseMenu.EXIT])
	ids.append(SpatialPauseMenu.HINT)
	return ids

func _apply_choreography(t: float) -> void:
	if _choreography == null:
		return
	for i in range(_choreography.lines.size()):
		var id: StringName = _choreography.lines[i]
		var alpha: float = _choreography.alpha_at(i, t)
		var offset: float = _choreography.offset_at(i, t)
		if _spatial_mode and _spatial != null:
			_spatial.set_line_envelope(id, alpha * _spatial.alpha(), offset)
		else:
			_cascade_canvas_line(id, alpha, offset)

func _cascade_canvas_line(id: StringName, alpha: float, offset: float) -> void:
	# 非 spatial 模式（无相机）：Canvas 控件自己做级联。
	var control: Control = null
	match id:
		SpatialPauseMenu.STATUS: control = _status_label
		SpatialPauseMenu.CONTEXT_LINE: control = _context_line
		SpatialPauseMenu.CAPTION: control = _remaining_caption
		SpatialPauseMenu.TIME: control = _remaining_value
		SpatialPauseMenu.CONTINUE: control = _continue_button
		SpatialPauseMenu.SETTINGS: control = _settings_button
		SpatialPauseMenu.EXIT: control = _exit_button
		SpatialPauseMenu.QUESTION: control = _confirmation_label
		SpatialPauseMenu.HINT: control = _hint_label
	if control == null:
		return
	control.modulate.a = alpha
	# 位置由容器管理的控件只调透明度；自由定位的（hint）带位移。
	if control == _hint_label:
		control.position.y = 392.0 * _frame_scale + offset
```

`_animate_open()` 改造（保持无树同步落终态的既有契约）：

```gdscript
func _animate_open() -> void:
	_set_cinematic_factor(CINEMATIC_FRAME_FACTOR)
	_content.modulate.a = 1.0
	_content.position = _content_home
	if _spatial != null and _spatial.has_camera():
		_spatial.visible = true
		_spatial.set_alpha(1.0)
		_choreography = PauseChoreography.opening(_tokens, _cascade_ids())
	if not is_inside_tree():
		# 无树（测试/截图具）：级联直接落终态。
		_apply_choreography(_choreography.total_seconds())
		return
	_kill_animation()
	_set_cinematic_factor(1.0)
	if _spatial != null and _spatial.has_camera():
		_spatial.set_alpha(1.0)
	_apply_choreography(0.0)
	_animation = create_tween()
	_animation.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_animation.tween_method(_apply_choreography, 0.0,
		_choreography.total_seconds(), _choreography.total_seconds())
	_animation.parallel().tween_method(_set_cinematic_factor, 1.0,
		CINEMATIC_FRAME_FACTOR, _choreography.total_seconds())
```

（`PauseChoreography` 顶部 preload：`const PauseChoreographyScript := preload(...)` 并统一用 Script 名调用——无 class_name 冲突时 `class_name` 直接可用，二者取其一，保持文件内一致。）

`close()` 的动画段改为逆向级联：

```gdscript
	_kill_animation()
	_choreography = PauseChoreography.closing(_tokens, _cascade_ids())
	_animation = create_tween()
	_animation.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_animation.tween_method(_apply_choreography, 0.0,
		_choreography.total_seconds(), _choreography.total_seconds())
	_animation.parallel().tween_method(_set_cinematic_factor, _camera_factor, 1.0,
		_choreography.total_seconds())
	_animation.chain().tween_callback(_finish_close)
```

`_finish_close()` 里 `_content.modulate.a = 1.0` 之后追加 `_choreography = null`，并在 `_spatial` 上 `reset_envelopes(_cascade_ids())`（若 `_spatial != null`）。

`_show_settings()` 与 `_show_confirmation()` 的 animate 分支替换为级联：进场面板先 `visible = true`，然后

```gdscript
	if animate and is_inside_tree():
		_choreography = PauseChoreography.opening(_tokens, _cascade_ids())
		_apply_choreography(0.0)
		var transition := create_tween()
		transition.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		transition.tween_method(_apply_choreography, 0.0,
			_choreography.total_seconds(), _choreography.total_seconds())
	else:
		_choreography = PauseChoreography.opening(_tokens, _cascade_ids())
		_apply_choreography(_choreography.total_seconds())
```

（`_state` 赋值必须先于 `_cascade_ids()` 调用，否则级联拿到旧状态的行。）

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tools/run_tests.sh 2267`
Expected: PASS，控制台干净；既有 `test_exit_menu.gd` 全绿（终态契约未变）。

- [ ] **Step 5: 提交**

```bash
git add src/ui/pause_choreography.gd src/ui/spatial_pause_menu.gd src/ui/exit_menu.gd tests/unit/test_pause_choreography.gd
git commit -m "Choreograph the pause surface cascade"
```

---

### Task 7: 焦点三重反馈 + 调节微交互

**Files:**
- Modify: `src/ui/spatial_pause_menu.gd`（字重 +100、−2px 上浮、非焦点 dim、值落定脉冲）
- Modify: `src/ui/exit_menu.gd`（Canvas 侧镜像 + 脉冲触发）
- Test: `tests/unit/test_pause_focus_feedback.gd`

**Interfaces:**
- Consumes: `UIFonts.display_at/interface_at`；Task 5 的行 id；Task 6 envelope。
- Produces: `SpatialPauseMenu.pulse_row_value(setting_id)`、`SpatialPauseMenu.row_pulse(setting_id) -> float`、`SpatialPauseMenu.focus_lift_for(id) -> float`；常量 `FOCUS_WEIGHT_STEP := 100`、`FOCUS_LIFT_PIXELS := -2.0`、`PULSE_SCALE := 0.03`。

- [ ] **Step 1: 写失败测试**

```gdscript
extends TestCase

const SpatialScript := preload("res://src/ui/spatial_pause_menu.gd")
const Tokens: UITokens = preload("res://data/ui/tokens.tres")

var _spatial: SpatialPauseMenu = null
var _fonts: UIFonts = null

func before_each() -> void:
	_fonts = UIFonts.new()
	_fonts.build(Tokens)
	_spatial = SpatialScript.new()
	_spatial.setup(Tokens, _fonts)

func after_each() -> void:
	if _spatial != null:
		_spatial.free()
		_spatial = null

func _weight_of(label: Label3D) -> int:
	var variation := label.font as FontVariation
	if variation == null:
		return 0
	var coords: Dictionary = variation.variation_opentype
	return int(coords.values()[0]) if not coords.is_empty() else 0

func test_focus_boldens_the_choice_by_one_weight_step() -> void:
	_spatial.set_state(&"menu")
	_spatial.set_focus(SpatialPauseMenu.CONTINUE)
	var focused := _label(&"Continue")
	var resting := _label(&"Exit")
	assert_eq(_weight_of(focused) - _weight_of(resting),
		SpatialScript.FOCUS_WEIGHT_STEP)

func test_unfocused_choices_dim_to_the_third_opacity_step() -> void:
	_spatial.set_state(&"menu")
	_spatial.set_focus(SpatialPauseMenu.CONTINUE)
	var resting := _label(&"Exit") as Label3D
	assert_almost_eq(resting.modulate.a, Tokens.opacity_steps[2], 0.02)

func test_the_focused_choice_lifts_two_pixels() -> void:
	_spatial.set_state(&"menu")
	_spatial.set_focus(SpatialPauseMenu.EXIT)
	assert_almost_eq(_spatial.focus_lift_for(SpatialPauseMenu.EXIT),
		SpatialScript.FOCUS_LIFT_PIXELS)
	assert_almost_eq(_spatial.focus_lift_for(SpatialPauseMenu.CONTINUE), 0.0)

func test_a_value_pulse_decays_over_a_few_frames() -> void:
	_spatial.set_state(&"settings")
	_spatial.pulse_row_value(&"prompt_hold")
	assert_almost_eq(_spatial.row_pulse(&"prompt_hold"), 1.0)
	for i in range(30):
		_spatial._process(1.0 / 60.0)
	assert_true(_spatial.row_pulse(&"prompt_hold") < 0.1,
		"the settle pulse never decayed")

func test_focus_moves_between_settings_rows() -> void:
	_spatial.set_state(&"settings")
	_spatial.set_focus(&"row_stroke_bold")
	assert_almost_eq(_spatial.focus_lift_for(&"row_stroke_bold"),
		SpatialScript.FOCUS_LIFT_PIXELS)
	assert_almost_eq(_spatial.focus_lift_for(&"row_prompt_hold"), 0.0)

func _label(label_name: String) -> Label3D:
	for label in _spatial.labels():
		if label.name == label_name:
			return label
	return null
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tools/run_tests.sh 2272`
Expected: FAIL — `FOCUS_WEIGHT_STEP`/`pulse_row_value` 等不存在。

- [ ] **Step 3: 实现**

`src/ui/spatial_pause_menu.gd`：

常量区：

```gdscript
## 焦点三重反馈（设计规范 2.2）：字重 +100、上浮 -2px、其余降到 opacity_steps[2]。
const FOCUS_WEIGHT_STEP := 100
const FOCUS_LIFT_PIXELS := -2.0
const PULSE_SCALE := 0.03
const PULSE_RESPONSE := 12.0
```

成员区：

```gdscript
var _focus_lift: Dictionary = {}   # id -> 像素
var _row_pulses: Dictionary = {}   # setting_id -> 0..1
```

`set_focus()` 末尾（`_apply_alpha()` 之前）追加字重/上浮/dim：

```gdscript
	var focusables := [CONTINUE, SETTINGS, EXIT, RETURN, CONFIRM] + _row_ids
	for id in focusables:
		var focused: bool = id == _focus
		_focus_lift[id] = FOCUS_LIFT_PIXELS if focused else 0.0
		var label := _labels.get(id) as Label3D
		if label != null:
			label.font = _focused_font_for(id, focused)
```

`_focused_font_for`：

```gdscript
func _focused_font_for(id: StringName, focused: bool) -> Font:
	var base := _label_fonts.get(id) as Font
	if not focused:
		return base
	if base == _fonts.display:
		return _fonts.display_at(_tokens.display_latin_weight + FOCUS_WEIGHT_STEP,
			_tokens.display_cjk_weight + FOCUS_WEIGHT_STEP)
	if base == _fonts.interface:
		return _fonts.interface_at(_tokens.interface_latin_weight + FOCUS_WEIGHT_STEP,
			_tokens.interface_cjk_weight + FOCUS_WEIGHT_STEP)
	return base  # instrument 是静态字重：值字用颜色与脉冲表达焦点
```

注意：`_label_fonts[id]` 在字体替换后仍保存**基础**字体（测量用原字号即可，VF 变体 advance 相同，见 UIFonts 文档注释），不要更新 `_label_fonts`。

dim：`_apply_alpha()` 的 label 循环中追加焦点衰减：

```gdscript
		var focusables := [CONTINUE, SETTINGS, EXIT, RETURN, CONFIRM] + _row_ids
		if id in focusables and id != _focus and _state != STATE_CONFIRM:
			fill.a *= _tokens.opacity_steps[2]
```

（确认页双按钮保留原有颜色对比逻辑即可，故排除 STATE_CONFIRM。）

上浮：`_update_projection()` 的 label origin 行改为：

```gdscript
		label_transform.origin = _camera.project_position(
			(_targets[id] as Vector2) + Vector2(0.0,
				_envelope_offset_for(id) + float(_focus_lift.get(id, 0.0))), _depth)
```

公开：

```gdscript
func focus_lift_for(id: StringName) -> float:
	return float(_focus_lift.get(id, 0.0))
```

值落定脉冲：

```gdscript
func pulse_row_value(setting_id: StringName) -> void:
	_row_pulses[setting_id] = 1.0

func row_pulse(setting_id: StringName) -> float:
	return float(_row_pulses.get(setting_id, 0.0))
```

`_process()` 中追加衰减：

```gdscript
	for setting_id in _row_pulses.keys():
		var current := float(_row_pulses[setting_id])
		if current <= 0.001:
			_row_pulses[setting_id] = 0.0
			continue
		_row_pulses[setting_id] = lerpf(current, 0.0, 1.0 - exp(-PULSE_RESPONSE * maxf(delta, 0.0)))
```

`_update_projection()` 值 label 的 `pixel_size` 乘脉冲（label 循环内，若 `id` 在 `_row_value_ids` 中）：

```gdscript
		var pulse := 1.0
		var row_index := _row_value_ids.find(id)
		if row_index >= 0:
			var setting := _row_settings[row_index] as AccessibilitySetting
			pulse = 1.0 + PULSE_SCALE * float(_row_pulses.get(setting.id, 0.0))
		label.pixel_size = world_per_pixel * screen_size / float(BASE_FONT_SIZE) * pulse
```

`ExitMenu._apply_setting()` 末尾追加脉冲触发：

```gdscript
	if _spatial != null:
		_spatial.pulse_row_value(setting.id)
```

Canvas 侧（非 spatial 模式可见）：`adjust_focused()` 成功后对焦点行按钮做字体替换：

```gdscript
	# _on_choice_focus_entered 内追加:
	var row_index := _settings_rows.find(button)
	if row_index >= 0:
		button.add_theme_font_override("font", _fonts.interface_at(
			_tokens.interface_latin_weight + 100, _tokens.interface_cjk_weight + 100))
# _on_choice_focus_exited 内恢复:
	button.add_theme_font_override("font", _fonts.display)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tools/run_tests.sh 2272`
Expected: PASS，控制台干净。

- [ ] **Step 5: 提交**

```bash
git add src/ui/spatial_pause_menu.gd src/ui/exit_menu.gd tests/unit/test_pause_focus_feedback.gd
git commit -m "Give the pause focus weight, lift and dim"
```

---

### Task 8: 鼠标微差（Parallax）

**Files:**
- Modify: `src/ui/spatial_pause_menu.gd`
- Test: `tests/unit/test_pause_parallax.gd`

**Interfaces:**
- Produces: `SpatialPauseMenu.set_pointer_normalized(Vector2)`（-1..1 视口坐标）、`pointer_offset() -> Vector2`、常量 `POINTER_PARALLAX_PIXELS := 6.0`；compact 或无相机时强制归零。

- [ ] **Step 1: 写失败测试**

```gdscript
extends TestCase

const SpatialScript := preload("res://src/ui/spatial_pause_menu.gd")
const Tokens: UITokens = preload("res://data/ui/tokens.tres")

var _spatial: SpatialPauseMenu = null

func before_each() -> void:
	var fonts := UIFonts.new()
	fonts.build(Tokens)
	_spatial = SpatialScript.new()
	_spatial.setup(Tokens, fonts)

func after_each() -> void:
	if _spatial != null:
		_spatial.free()
		_spatial = null

func test_the_pointer_offset_is_capped() -> void:
	_spatial.set_pointer_normalized(Vector2(5.0, -5.0))
	for i in range(120):
		_spatial._process(1.0 / 60.0)
	var offset := _spatial.pointer_offset()
	assert_true(offset.length() <= SpatialScript.POINTER_PARALLAX_PIXELS * 1.42,
		"parallax escaped its cap: %s" % offset)

func test_parallax_counters_the_cursor() -> void:
	_spatial.set_pointer_normalized(Vector2(1.0, 0.0))
	for i in range(120):
		_spatial._process(1.0 / 60.0)
	assert_true(_spatial.pointer_offset().x < 0.0,
		"the copy must drift AGAINST the cursor, not with it")

func test_compact_layout_forces_zero() -> void:
	_spatial.set_pointer_normalized(Vector2(1.0, 1.0))
	_spatial.layout(Rect2(Vector2.ZERO, Vector2(300, 320)), 0.78, true, 104.0)
	for i in range(120):
		_spatial._process(1.0 / 60.0)
	assert_eq(_spatial.pointer_offset(), Vector2.ZERO)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tools/run_tests.sh 2275`
Expected: FAIL — 方法/常量不存在。

- [ ] **Step 3: 实现**

`src/ui/spatial_pause_menu.gd`：

```gdscript
# 常量区:
## ≤6px，反向追随，指数平滑。相机不动——相机一动画面就"晕"（设计规范 2.5）。
const POINTER_PARALLAX_PIXELS := 6.0
const POINTER_RESPONSE := 4.0

# 成员区:
var _pointer_target := Vector2.ZERO
var _pointer_current := Vector2.ZERO

# 公开:
func set_pointer_normalized(offset: Vector2) -> void:
	if not offset.is_finite():
		return
	_pointer_target = -offset.clampf(-1.0, 1.0) * POINTER_PARALLAX_PIXELS

func pointer_offset() -> Vector2:
	return _pointer_current
```

`_process()` 开头（visible/相机守卫之后）：

```gdscript
	if _compact:
		_pointer_current = Vector2.ZERO
	else:
		_pointer_current = _pointer_current.lerp(_pointer_target,
			1.0 - exp(-POINTER_RESPONSE * maxf(delta, 0.0)))
```

`_update_projection()` 的 label/line/ornament 三处 `project_position(...)` 的屏幕坐标参数统一 `+ _pointer_current`。

注意：`_process` 现有守卫是 `if not visible or _camera == null: return`——测试里无相机时不会走到平滑。**调整守卫**：把 parallax 平滑移到守卫之前，使无相机也衰减；投影仍受相机守卫保护。测试 `test_compact_layout_forces_zero` 依赖这一点。改为：

```gdscript
func _process(delta: float) -> void:
	if _compact:
		_pointer_current = Vector2.ZERO
	else:
		_pointer_current = _pointer_current.lerp(_pointer_target,
			1.0 - exp(-POINTER_RESPONSE * maxf(delta, 0.0)))
	if not visible or _camera == null:
		return
	...
```

鼠标读取（`ExitMenu` 无需参与）：`_process` 内在有相机时读取：

```gdscript
	var viewport := _camera.get_viewport()
	if viewport != null:
		var mouse := viewport.get_mouse_position()
		var rect := viewport.get_visible_rect().size
		if rect.x > 0.0 and rect.y > 0.0:
			set_pointer_normalized(Vector2(
				mouse.x / rect.x * 2.0 - 1.0,
				mouse.y / rect.y * 2.0 - 1.0))
```

（放在平滑之前。）

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tools/run_tests.sh 2275`
Expected: PASS，控制台干净。

- [ ] **Step 5: 提交**

```bash
git add src/ui/spatial_pause_menu.gd tests/unit/test_pause_parallax.gd
git commit -m "Let the pause copy counter-follow the cursor"
```

---

### Task 9: 排版层级刷新 + 收尾（DEFERRED 登记 + 全套件）

**Files:**
- Modify: `src/ui/exit_menu.gd`（`layout_for_viewport` 字号层级）
- Modify: `src/ui/spatial_pause_menu.gd`（`layout` 字号层级同步）
- Modify: `Docs/DEFERRED.md`（三条登记）
- Test: `tests/unit/test_pause_typography.gd`

**Interfaces:**
- Consumes: 前序全部任务。

- [ ] **Step 1: 写失败测试**

```gdscript
extends TestCase

const ExitMenuScript := preload("res://src/ui/exit_menu.gd")

var _menu = null

func before_each() -> void:
	_menu = ExitMenuScript.new()
	_menu.set_quit_action(func() -> void: pass)
	_menu.build()

func after_each() -> void:
	if _menu != null:
		_menu.free()
		_menu = null

func test_the_status_line_anchors_the_hierarchy() -> void:
	_menu.layout_for_viewport(Vector2(1920.0, 1080.0))
	var status := _menu.get_node("ExitMenuRoot/BreathRail/NightContext/DayAndPhase") as Label
	var status_size := status.get_theme_font_size("font_size")
	# 42 设计像素 × 1080 短边缩放（frame_scale 上限 1.25 不计入 tokens.scale_for 的 1.0 基准）
	assert_true(status_size >= 40,
		"the day line must anchor the composition, got %d" % status_size)

func test_the_caption_steps_down_from_the_status() -> void:
	_menu.layout_for_viewport(Vector2(1920.0, 1080.0))
	var status := _menu.get_node("ExitMenuRoot/BreathRail/NightContext/DayAndPhase") as Label
	var caption := _menu.get_node("ExitMenuRoot/BreathRail/NightContext/Remaining/Caption") as Label
	assert_true(caption.get_theme_font_size("font_size") <=
		int(roundf(status.get_theme_font_size("font_size") * 0.45)),
		"the caption must clearly subordinate to the day line")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tools/run_tests.sh 2277`
Expected: FAIL — 状态行当前 34 设计像素。

- [ ] **Step 3: 实现**

`exit_menu.gd` `layout_for_viewport()`：
- `_status_label` 字号：`maxi(int(roundf(42.0 * _frame_scale)), 26)`
- `_remaining_caption`：`maxi(int(roundf(15.0 * _frame_scale)), 12)`
- `_remaining_value` 保持 20 档

`spatial_pause_menu.gd` `layout()`：
- `title_size`（STATUS/CONTINUE/SETTINGS/EXIT/QUESTION/RETURN/CONFIRM）保持 `34.0 * frame_scale` 下限 22
- STATUS 单独一行：`_label_sizes[STATUS] = maxf(42.0 * frame_scale, 26.0)`（在循环后覆盖）
- `body_size`（CAPTION/CONSEQUENCE/设置行）改 `15.0 * frame_scale` 下限 12

DEFERRED.md 追加（遵循该文件既有格式追加三条，由实现者先读文件匹配格式；内容要点必须包含）：

```markdown
- 屏幕震动设置的消费者：设置已持久化（SettingsStore.screen_shake），但 CameraRig 尚无震动系统可门控。归属：震动系统落地之 Wave。
- 提示停留时长与寒流 time_scale 的组合义务：UILayer.advance() 已将两者相乘（_time_scale × _preference_scale），但寒流驱动器当前只存在于测试；游戏内落地时必须走 set_time_scale（乘算语义），不得覆盖 preference。
- 笔画加粗 ×2 的剩余表面：InteractionPrompt 与暂停菜单已接入；ThresholdNote、VitalStroke（Tab 弧）尚未读取 stroke_scale。归属：U3 框架层收尾。
```

- [ ] **Step 4: 全套件 + 截图验证**

```bash
bash tools/run_tests.sh 2277
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --path "D:/Godot resource/winter-time" --headless --import
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --path "D:/Godot resource/winter-time" tools/capture_exit_menu.tscn
```

Expected: 2277 passed、控制台干净；截图人工目检级联落点与设置排版。

- [ ] **Step 5: 提交**

```bash
git add src/ui/exit_menu.gd src/ui/spatial_pause_menu.gd Docs/DEFERRED.md tests/unit/test_pause_typography.gd
git commit -m "Refresh pause typography hierarchy"
```

---

## Self-Review 记录

- **Spec 覆盖**：§1.1 主页结构（T4/T5/T9）、§1.2 设置页（T1/T4/T5）、§1.3 导航（T4）、§2.1 级联打开（T6）、§2.2 焦点三重（T7）、§2.3 调节微交互（T4 边界音、T7 脉冲/刻度）、§2.4 逆向关闭（T6）、§2.5 微差（T8）、§2.6 状态切换（T6）、§3 数据流（T1/T2/T3）、§4 错误处理（T2 坏档、T3 非法 scale、既有 WorldClock/相机守卫）、§5 测试（每任务自带）。
- **类型一致性**：`SpatialPauseMenu.set_state(StringName)` 在 T5 替换 bool 版，T5 同时更新 ExitMenu 全部调用点；`_spatial_choice_id` 的返回值集合在 T5 扩展。T6 的 `_cascade_ids()` 依赖 T5 的 `row_label_ids()`。
- **已知取舍**（与 spec 的偏差，已在步骤内注明）：刻度"逐格点亮"简化为游标滑动 + 值脉冲；Canvas 侧焦点字重仅应用于设置行（菜单项 Canvas 副本在 spatial 模式不可见）；`signi` 笔误已在 T1 修正为 `signf`。
