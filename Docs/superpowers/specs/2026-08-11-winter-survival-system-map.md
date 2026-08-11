# 《长夜将尽》系统地图与建造顺序

项目代号 `WinterTime` · 2026-08-11

---

## 0. 三条工程原则

本项目的架构目标不是"能跑通七天"，而是**七天跑通之后还能持续加内容而不重构**。

| 原则 | 含义 | 检验方式 |
|---|---|---|
| **数据驱动** | 加一种天气、一件物品、一条状态、一个威胁，**不写代码**，只加 `.tres` | 新增内容的 PR 中 `.gd` 改动为零 |
| **解耦** | 系统之间零直接引用，全部经 `EventBus` 通信 | 任一系统可被删除，其余系统仍能编译并通过测试 |
| **抽象** | 熊和饿汉共用一套威胁框架，差异只在数据；玩家和 AI 共用一套状态机 | 新增第三种威胁不需要新的行为代码 |

**命名规范：全部英文，`snake_case`。** 参考计划中的波兰语文件名（`zima` `dolina` `drogi` `drzewa` `kamera` `wrog` `niedzwiedz` `opal` `bron`）一律弃用。

---

## 1. 目录结构

```
res://
├── assets/                          # 二进制美术资产
│   ├── audio/{ambient,music,foley,diegetic}/
│   ├── models/{buildings,characters,props,vegetation}/
│   ├── shaders/
│   └── textures/
│
├── data/                            # ★ 全部内容以 .tres 存在
│   ├── beacons/                     #   5 座信标定义
│   ├── items/                       #   燃料 / 食物 / 药品
│   ├── lighting/                    #   6 个光照预设
│   ├── schedule/                    #   7 天编排
│   ├── stats/                       #   5 条生存状态定义
│   ├── threats/                     #   熊 / 饿汉
│   └── weather/                     #   6 种天气事件
│
├── scenes/
│   ├── entities/{player,threats,beacon,interior}/
│   ├── locations/                   #   农舍 / 加油站 / 教堂 / 伐木场 / 电线塔
│   └── ui/
│
├── src/
│   ├── core/                        # ★ 框架层——不含任何游戏逻辑
│   │   ├── event_bus.gd
│   │   ├── service_registry.gd
│   │   ├── state_machine.gd
│   │   ├── modifier_stack.gd
│   │   └── definition_loader.gd
│   │
│   ├── definitions/                 # ★ Resource 类（数据的形状）
│   │   ├── stat_definition.gd
│   │   ├── stat_modifier.gd
│   │   ├── threshold_effect.gd
│   │   ├── weather_event_definition.gd
│   │   ├── item_definition.gd
│   │   ├── threat_definition.gd
│   │   ├── beacon_definition.gd
│   │   ├── lighting_preset.gd
│   │   └── day_schedule.gd
│   │
│   ├── systems/                     # Autoload 单例（全局状态）
│   │   ├── world_clock.gd
│   │   ├── weather_system.gd
│   │   ├── wind_system.gd
│   │   ├── snow_field.gd
│   │   ├── track_mask.gd
│   │   ├── survival_system.gd
│   │   ├── fuel_economy.gd
│   │   ├── beacon_network.gd
│   │   └── game_state.gd
│   │
│   ├── entities/                    # 场景节点脚本
│   │   ├── player/{player_controller.gd,player_states/}
│   │   ├── threats/{threat_base.gd,threat_states/,perception/}
│   │   ├── beacon/beacon.gd
│   │   └── interior/interior_reveal.gd
│   │
│   ├── rendering/
│   │   ├── camera_rig.gd
│   │   ├── lighting_director.gd
│   │   ├── terrain_renderer.gd
│   │   ├── roads.gd
│   │   └── vegetation.gd
│   │
│   ├── audio/
│   │   ├── audio_director.gd
│   │   ├── music_director.gd
│   │   ├── ambient_player.gd
│   │   ├── foley_player.gd
│   │   ├── diegetic_source.gd
│   │   └── threat_audio.gd
│   │
│   └── debug/
│       └── lighting_panel.gd
│
└── tests/
    ├── framework/test_runner.gd
    ├── unit/
    └── art/                         # 美术验收测试
```

---

## 2. 框架层：四个核心抽象

`src/core/` 中的代码**不认识这个游戏**。它不知道什么是雪、什么是熊。它可以原样搬到下一个项目。

### 2.1 `EventBus` — 系统间零引用

所有跨系统通信经此发生。`SnowField` 不认识 `Player`，`WeatherSystem` 不认识 `Beacon`。

```
EventBus.emit("weather.event_started", event_id)
EventBus.subscribe("weather.event_started", _on_weather_started)
```

**检验**：注释掉任一 autoload，其余系统仍应编译通过、单元测试仍应运行。

### 2.2 `ModifierStack` — 数据驱动的心脏

五条生存状态**不是五个硬编码变量**。任何系统都能向任意状态推入一个修饰器：

| 字段 | 含义 |
|---|---|
| `source_id` | 谁加的（用于精确移除） |
| `target_stat` | 作用于哪条状态 |
| `operation` | `ADD` / `MULTIPLY` / `OVERRIDE` |
| `value` | 数值 |
| `duration` | 持续秒数，`-1` = 永久直到手动移除 |

于是 GDD §5 的"饥饿低 → 体温下降加速"变成 `stats/hunger.tres` 里的一行数据：

```
threshold_effects:
  - when: below 0.3
    modifier: { target: temperature_decay, op: MULTIPLY, value: 1.5 }
```

**新增一条状态（比如"理智"）或一条咬合关系，不需要碰任何 `.gd` 文件。**

### 2.3 `StateMachine` — 玩家与 AI 共用

资源可配置的通用状态机。玩家的 `走 / 跑 / 陷雪 / 倒地` 与威胁的 `游荡 / 警觉 / 追击 / 攻击` 是同一套机制的两份数据。

**检验**：新增第三种威胁不应产生新的行为代码，只产生一个 `threat_definition.tres`。

### 2.4 `ServiceRegistry` — 可测试性

单例通过注册表访问而非直接 autoload 引用，测试可注入假实现。这是"一个任务一个会话"能成立的技术前提——测 `beacon.gd` 时不需要启动整个天气系统。

---

## 3. 威胁的抽象化

熊与饿汉**不是两套代码**，是一套框架 + 两份数据。

| 抽象 | 熊 | 饿汉 |
|---|---|---|
| `PerceptionModule` | `ScentPerception`（顺风生效） | `SightPerception`（视锥）+ `TrackPerception`（读足迹） |
| `LocomotionProfile` | 速度 > 玩家全速 | 速度 ≈ 玩家步行 |
| `EngagementBehavior` | 先警告后冲锋、撞倒 | 尾随、伺机接近、可被吓退 |
| `ThreatDefinition.tres` | `data/threats/bear.tres` | `data/threats/scavenger.tres` |

感知模块是可组合的组件。**未来加"狼群"只需一份新 `.tres`：`ScentPerception` + 高速 + 群体行为。**

---

## 4. 四个关键技术方案

### 4.1 雪深高度场 `snow_field.gd`

| 项 | 规格 |
|---|---|
| 格式 | R16 单通道高度纹理 |
| 分辨率 | 512 × 512 |
| 覆盖 | 120 m × 120 m（每像素 23 cm） |
| 跟随 | **环形滚动**（toroidal wrap），只重建新进入视野的边缘条带 |

**写入**：脚步压实（负）· 风力堆积（正）· 降雪全局抬升
**读取**：玩家采样脚下决定能否奔跑；地形着色器采样做顶点位移与着色

> **对参考做法的技术修正**：参考视频称"不缓存，因为高度一直在变"。GPU 端每帧采样 11 万顶点是对的——顶点着色器本就该这样。但 **CPU 端不该整张重建**，只有被写入的区域需要重算。每帧重建整张 512² 是白烧 CPU。

### 4.2 足迹遮罩 `track_mask.gd`

| 项 | 规格 |
|---|---|
| 分辨率 | 1080 × 1080 |
| 覆盖 | 90 m（每像素 8.3 cm） |
| 格式 | **RG8**：R = 压实深度，G = 剩余寿命 |

写入只在有新脚印时绘制，不每帧全清。**双层**：静态烘焙层（犁沟、旧车辙，风不可擦）+ 动态层（玩家/威胁足迹，风可擦）。

**这张图是三个系统的交汇点**：地形着色器读它（美术）· 威胁的 `TrackPerception` 读它（玩法）· `WindSystem` 衰减它（天气）。1000 条足迹与 1 条开销完全相同。

### 4.3 两段式 cel shading `lighting_director.gd`

亮部 / 暗部两个 band，阈值与过渡宽度可调。**暗部颜色从 12 色表取另一个色，不是亮部乘系数**——乘法会产生表外颜色。

### 4.4 室内揭示 `interior_reveal.gd`

跨过 Area3D threshold → 导出的固定部件列表 0.30 s tween 淡出。**不用射线、不用遮挡剔除。** 同时切换 `AudioDirector` 的室内滤波与混响。

---

## 5. 建造顺序：31 个任务

**一个系统 · 一个文件 · 一个任务 · 一次独立会话 · 以一个测试收尾。**

### 波次 0 · 框架地基（5）— 严格顺序

| # | 任务 | 路径 | 出口测试 |
|---|---|---|---|
| 0 | 测试框架 | `tests/framework/test_runner.gd` | 跑通一个假测试，并对必失败用例正确报错 |
| 1 | **核心抽象层** | `src/core/*.gd` | EventBus 收发正确；ModifierStack 三种运算与过期正确；StateMachine 可由资源配置 |
| 2 | **Resource 类定义** | `src/definitions/*.gd` | 九类定义均可实例化并被编辑器识别 |
| 3 | 美术验收套件 | `tests/art/*.gd` | 四项检查（色表 / 暖色配额 / 面数 / 禁用特性）均可运行 |
| 4 | 世界时钟 | `src/systems/world_clock.gd` | 7 天推进；昼夜时长符合 GDD §4 |

> **对参考流程的改动**：参考视频把测试框架（THE GATES）排在第 16 位。**这是错的顺序**——测试框架若最后才有，前 15 个系统就没有"以测试收尾"的能力，而那正是整套工作流的立身之本。测试框架必须是 0 号任务，美术验收套件紧随其后，让第一个模型诞生时 12 条美术规则就已在把关。

### 波次 1 · 地面（3）— 严格顺序

| # | 任务 | 路径 | 出口测试 |
|---|---|---|---|
| 5 | 雪深高度场 | `src/systems/snow_field.gd` | 120 m 窗口随玩家滚动；深处只能走、浅处可跑 |
| 6 | 足迹遮罩 | `src/systems/track_mask.gd` | 双层生效；风只擦动态层；1000 迹与 1 迹同开销 |
| 7 | 山谷与地点布局 | `scenes/locations/` + `src/rendering/terrain_renderer.gd` | 5 个地点可达；往返时间符合 GDD §4 昼长 |

### 波次 2 · 角色（5）

| # | 任务 | 路径 | 出口测试 |
|---|---|---|---|
| 8 | 玩家控制 | `src/entities/player/player_controller.gd` | 速度随雪深变化；落脚写入遮罩；状态机驱动 |
| 9 | 相机 | `src/rendering/camera_rig.gd` | 55-60° 固定角跟随，永不旋转 |
| 10 | **生存状态系统** | `src/systems/survival_system.gd` | 五条状态**全部由 `data/stats/*.tres` 定义**；咬合关系经 ModifierStack 生效；归零发出死亡事件 |
| 11 | 音频总线 | `src/audio/audio_director.gd` | 室内外滤波与混响可切换 |
| 12 | 脚步与身体 | `src/audio/foley_player.gd` | 脚步随雪深变；呼吸随体温与疲劳变 |

### 波次 3 · 世界（7）— 14/15/16 可并行

| # | 任务 | 路径 | 出口测试 |
|---|---|---|---|
| 13 | 风 | `src/systems/wind_system.gd` | 风向擦除足迹；影响体感温度 |
| 14 | **天气事件** | `src/systems/weather_system.gd` | 六种事件**全部由 `data/weather/*.tres` 定义**；均先预兆后落地，预兆期 20-40 s |
| 15 | 道路 | `src/rendering/roads.gd` | 路上雪浅可跑 |
| 16 | 植被 | `src/rendering/vegetation.gd` | 树按 12 色着色；面数 < 300 |
| 17 | 光照栈 + 调试面板 | `src/rendering/lighting_director.gd` · `src/debug/lighting_panel.gd` | 6 预设热键切换；滑块实时生效 |
| 18 | 环境音 | `src/audio/ambient_player.gd` | 随天气事件插值，无突变 |
| 19 | 自适应配乐 | `src/audio/music_director.gd` | 四层交叉淡入不切歌；**威胁靠近时抽走高频层** |

### 波次 4 · 玩法（4）

| # | 任务 | 路径 | 出口测试 |
|---|---|---|---|
| 20 | 燃料经济 | `src/systems/fuel_economy.gd` | 物品**全部由 `data/items/*.tres` 定义**；水/食物/体温/信标四条支路扣费守恒 |
| 21 | **信标** | `src/systems/beacon_network.gd` · `src/entities/beacon/beacon.gd` | 5 座**由 `data/beacons/*.tres` 定义**；点亮/耗尽自灭/被风吹灭；暴雪必灭至少一座 |
| 22 | 室内揭示 | `src/entities/interior/interior_reveal.gd` | 跨 threshold 后 0.30 s 淡出；音频同步切换 |
| 23 | 世界音源 | `src/audio/diegetic_source.gd` | 火炉/信标/发电机 3D 定位；白茫茫中可循声导航 |

### 波次 5 · 威胁（5）— 25/26 可并行

| # | 任务 | 路径 | 出口测试 |
|---|---|---|---|
| 24 | **威胁框架** | `src/entities/threats/threat_base.gd` + `perception/` | 感知模块可组合；状态机由 `threat_definition.tres` 配置 |
| 25 | 饿汉数据 | `data/threats/scavenger.tres` | 视锥发现玩家；**能追踪足迹**；**零新增 `.gd` 代码** |
| 26 | 熊数据 | `data/threats/bear.tres` | **顺风才能闻到**；先警告后冲锋；跑不过；**零新增 `.gd` 代码** |
| 27 | 武器 | `src/entities/player/weapon.gd` | F 键锁定最近目标 |
| 28 | 威胁音频 | `src/audio/threat_audio.gd` | 熊的呼吸随距离衰减；与配乐抽层联动 |

> 任务 25 与 26 的出口测试**明确要求零新增代码**。若实现它们时不得不改 `threat_base.gd`，说明任务 24 的抽象没做到位——这时应回滚 24 重做，而不是打补丁。

### 波次 6 · 收尾（2）

| # | 任务 | 路径 | 出口测试 |
|---|---|---|---|
| 29 | 胜负与存档 | `src/systems/game_state.gd` | 三种结局均可触发；永久死亡正确删档 |
| 30 | 〔后挂〕客人事件 | `src/systems/guest_event.gd` | 第 3 天触发；二选一正确改写第 4-7 天 |

---

## 6. 依赖与并行

```
波次 0 ──> 波次 1 ──> 波次 2 ──> 波次 3 ──> 波次 4 ──> 波次 5 ──> 波次 6
 (顺序)     (顺序)              (14/15/16 并行)      (25/26 并行)
```

- **波次 0 → 1 → 2 是硬依赖**，必须顺序完成
- 波次 3 中任务 15、16、17 互不依赖，可同时开三个会话
- 波次 5 中任务 25、26 互不依赖（且都是纯数据），可同时开两个会话
- 任务 30 可在骨架跑通后任意时间插入

---

## 7. 工作流教条

1. **不要在一个 prompt 里要整个游戏。** 让最强的模型写计划，每个任务各自开一个干净会话。
2. **每个任务以测试收尾。** 失败时回滚这一个任务，不是整个游戏。
3. **一个会话只带一个任务的上下文。** 模型读得更少、错得更少、也更省 token。
4. **模型由脚本生成。** 屋顶不对时改一行重跑，不去动网格。

---

## 8. 项目设置约束

已在 `project.godot` 中锁定，新代码须与之一致：

| 设置 | 值 | 含义 |
|---|---|---|
| 渲染器 | Forward+ | 可用完整桌面管线；不考虑 Compatibility 回退 |
| 3D 物理 | **Jolt Physics** | 接触上报与关节行为与 Godot Physics 有差异 |
| Windows 驱动 | Direct3D 12 | 渲染异常时可用 `--rendering-driver vulkan` 隔离 |
| 窗口拉伸 | `canvas_items` / `expand` | UI 须锚定屏幕边缘，不可依赖固定视口尺寸 |

---

## 9. 相关文档

- 游戏设计文档：[2026-08-11-winter-survival-gdd.md](2026-08-11-winter-survival-gdd.md)
- 美术圣经：[2026-08-11-winter-survival-art-bible.md](2026-08-11-winter-survival-art-bible.md)
