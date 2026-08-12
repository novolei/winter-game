# ⚠️ Director 评估（2026-08-12）

**这份文档已被审阅并分档。执行前必读本节。**

作者是在看着截图给建议，不知道本项目已经确立的**两段式 cel shading** 与 **12 色 albedo 表**。因此文档在光照、大气、构图上非常有价值，在着色模型上则与既定方向直接冲突。逐条分档如下。

## ✅ 采纳（本文档最有价值的部分）

| 条目 | 理由 |
|---|---|
| **90% 冷 / 10% 暖 的比例** | 与美术圣经规则 12「暖色 ≤0.5%」同源，只是说法不同。文档说的 10% 是**画面感知**，规则 12 说的 0.5% 是**像素统计**，两者不矛盾 |
| **渐变天空**（顶 `#5D96D3` → 地平线 `#B1D0EA`） | 当前是平涂纯蓝，这是真实缺口 |
| **深度雾做空气透视**（前景树 `#17283D` → 中景 `#355777` → 远景 `#7099C2`） | **本文档最大的贡献。** 我们现在所有树都是同一个近黑色，远近不分，这是画面扁平的主因 |
| **体积雾**（密度 0.0008-0.002） | Forward+ 专属，我们正是 Forward+ |
| **烟囱炊烟** | 极好的叙事元素——「屋子里面有人」。与 GDD「暖色即生存」直接呼应 |
| **积雪 shader**（朝上的面积雪） | 屋顶、棚顶、树枝、车顶，成本低效果大 |
| **屋檐厚雪几何体**（0.03-0.10 厚） | 文档说得对：shader 改不出厚度 |
| **压实雪地**（房屋周围更暗更蓝） | 「这里经常有人活动」——叙事性地面，与美术圣经 §3「雪地上的线是叙事性的」同源 |
| **三层雪花粒子**，尤其**镜头前那层** | 30-60 颗、贴在相机上的那层是廉价而有效的电影感。所有者明确点名要这一套 |
| **雪面细微 noise**（§14-15） | **评估更正**：我最初把它连同那段 PBR shader 一起划进拒绝档，那是错的。PBR 部分该拒绝，但「让雪面有极不可见的变化」这个想法本身好、且可分离。见下方「实现方式」 |
| **轮胎痕做 decal** | 已有静态遮罩层可承载 |
| **Hero Tree / 前景框架 / 远景树降对比** | 真正的构图思维 |
| **AGX tonemap** | 4.7.1 可用 |
| **最后那份优先级表** | **文档最好的一段。** 「先不要建 100 个新资产，你缺的不是东西，而是光、雪、空气、层次、色彩和叙事」——完全正确，且与本项目当前状态高度吻合 |

## ❌ 拒绝（与既定美术方向冲突）

| 条目 | 冲突点 |
|---|---|
| **`specular_schlick_ggx` / `SPECULAR = 0.15`** | 美术圣经规则 8 **明令禁止高光**，`test_shading_features.gd` 会直接判失败。这不是偏好，是有测试把关的硬约束 |
| **`diffuse_burley` PBR 着色** | 我们用**两段式 cel**，暗部颜色**从色表取另一个色**，不是亮部乘系数。文档的 shader 是 PBR 光照，整体采纳等于放弃 `level.jpg` 那套平涂语言 |
| **`ROUGHNESS = 0.92` / 粗糙度贴图** | 同规则 8，禁止 |
| **SSAO 强度 1.2-1.5** | AO 产生**角落渐变**，而规则 8 禁止任何形式的渐变。cel 画面上的 SSAO 通常会打架。**若要用，强度不超过 0.4，且必须截图验收** |
| **太阳 Rotation X = -52°** | **文档自相矛盾**：它要求「低角度太阳」「极长软阴影」，但 -52° 是接近正午的高角度，出来的是短影。我们已定 **21.5°**，且是有代价换来的——更低会让阴影长度随每一步剧烈跳变（长度 = 高度 ÷ tan(仰角)，11° 时 1 cm 垂直位移变成 6 cm 阴影）。**保持 21.5°，方位角保持 82°** |

## 🔧 雪面 noise 的实现方式（与规则 8 的调和）

文档 §15 的目标是对的：雪地不该是

```
#9BC3E8  #9BC3E8  #9BC3E8  #9BC3E8
```

而该是

```
#9BC3E8  #96BEE4  #A0C7E9  #93BDE3
```

**但直接照搬会同时违反两条约束**：规则 8 禁止任何形式的颜色渐变，`verify_palette` 门禁禁止 12 色表之外的 albedo。文档给的那组示例值一个都不在表内。

**正确做法：让 noise 扰动波段阈值，而不是扰动颜色。**

我们的 cel 着色器已经是两段式，暗部颜色从色表**取另一个色**而非乘系数。所以只要让 noise 对 `cel_band_threshold` 施加一个极小的世界坐标扰动，哪个 texel 落进哪一档就会细微变化——

- 产生了文档想要的变化
- **一个表外色都不会出现**（每个像素仍然精确等于某个色表条目）
- 不是渐变，是**在离散档位之间抖动**，规则 8 管的是前者

扰动幅度要小到「肉眼几乎看不到」，与文档 §15 的要求一致。若需要更多层次，可从两段扩到三段——多一档雪色仍在表内，仍是平涂。

**不要**引入文档 §14 那段 shader 的 `ROUGHNESS`、`SPECULAR`、`diffuse_burley`，也**不要**用它的 `snow_color` / `snow_shadow_color` 默认值（表外）。

## ⚖️ 需要划清的边界：albedo vs 大气

文档提出的 `#6399D5`、`#668BB5`、`#8CB4D9`、`#9B3D3D` 等色值**不在我们的 12 色表内**。这不构成冲突，因为两者管的是不同的东西：

- **12 色表管 albedo**——物体表面的固有色，由 `verify_palette` 门禁把关
- **天空、雾、环境光、太阳色**是**大气与光照**，不是表面固有色，**不受 12 色表约束**

这条边界要写进美术圣经，否则下一个 agent 会以为可以随便加色，或者反过来不敢调雾色。

## 执行顺序

采用文档自己给的顺序，它是对的：**光照 → 雪材质 → 积雪 → 空气透视 → 构图**，然后才是脚印、轮胎痕、暖窗、炊烟，最后才是雪花粒子。

---

我建议不要把它往“写实 AAA 冬景”方向推，而是建立一套非常明确的 Stylized Cinematic Winter 渲染体系：  
  
冷蓝环境 + 暖色低角度阳光 + 极长软阴影 + 雪面微变化 + 厚重积雪 + 蓝色空气透视 + 少量暖色生命痕迹。  
  
下面我直接按 Godot 4 / Forward+ 给你一套可以落地的方案。Godot 的 Environment 本身就负责环境光、雾、Glow、Tonemap 和后期 Adjustments；Godot 4.6 还提供 AGX、Filmic、ACES 等 Tone Mapper。   
G   
Godot Engine documentation   
+1  
  
一、先确定你的最终视觉目标  
  
我建议把这张图的视觉基准定成：  
  
```
                SKY
          #6399D5
              ↓
          #82B0DF
              ↓

```

  
HOUSE LIGHT ─ #FFB45C  
  

  
DEEP SHADOW ─ #203954  
  
  
核心比例：  
  
冷色       ██████████████████  90%   
暖色       ██                  10%  
  
  
而不是让所有东西都蓝。  
  
二、推荐的 Godot 场景结构  
  
你的场景可以整理成：  
  
World   
│   
├── WorldEnvironment   
│   
├── Sun   
│   └── DirectionalLight3D   
│   
├── Snow   
│   ├── Ground   
│   ├── SnowAccumulation   
│   └── SnowParticles   
│   
├── Environment   
│   ├── Background   
│   ├── ForegroundTrees   
│   ├── MidgroundTrees   
│   └── BackgroundTrees   
│   
├── House   
│   ├── Walls   
│   ├── Roof   
│   ├── Windows   
│   └── Chimney   
│   
└── Props   
├── Car   
├── Pole   
├── Shed   
└── Firewood  
  
  
如果你使用 Forward+，后面可以使用 SSAO、Volumetric Fog 等；其中 Volumetric Fog 是 Forward+ 专属，Mobile/Compatibility 不支持。   
G   
Godot Engine documentation  
  
三、WorldEnvironment：这是整个画面的核心  
  
创建：  
  
WorldEnvironment   
└── Environment  
1. Background  
  
如果你现在没有复杂天空系统，我建议先使用一个非常简单的 Gradient Sky。  
  
Sky 顶部   
#5D96D3   
Sky 中部   
#79A9DC   
Horizon   
#B1D0EA  
  
  
不要纯蓝。  
  
要有：  
  
深蓝   
↓   
中蓝   
↓   
浅蓝  
  
  
这样画面上方会有更强的空气感。  
  
四、Environment 环境光  
  
进入：  
  
Environment   
→ Ambient Light  
  
  
建议：  
  
Ambient Source:   
Color  
  
Ambient Light Color:   
#668BB5  
  
Ambient Light Energy:   
0.55 ~ 0.70  
  
Ambient Light Sky Contribution:   
0.35 ~ 0.50  
  
  
我建议初始：  
  
Color = #668BB5   
Energy = 0.62   
Sky Contribution = 0.40  
  
  
这里不要把环境光开得太亮。  
  
你的长阴影是非常重要的视觉资产。  
  
如果 Ambient 太强：  
  
房屋下面 → 蓝亮   
阴影 → 蓝亮   
太阳阴影 → 不明显  
  
你的画面就会失去现在最好看的地方。  
  
五、DirectionalLight3D：重新设计太阳  
  
这是我认为对你的截图影响最大的参数。  
  
创建：  
  
DirectionalLight3D   
Name = WinterSun   
Rotation  
  
你现在需要一个明显的低角度太阳。  
  
从这个方向开始：  
  
Rotation X = -52°   
Rotation Y = -35°   
Rotation Z = 0°  
  
  
然后根据你的房屋朝向微调。  
  
最重要的不是绝对角度，而是：  
  
让房屋阴影明显地向右下/远处拉出去。  
  
你截图中电线杆、房屋已经有很好的长阴影基础。  
  
Light Color  
  
不要纯白：  
  
Color:   
#FFD5A6  
  
  
或者：  
  
#FFE0BD  
  
  
这是“冬日太阳”。  
  
Energy  
  
从：  
  
1.15  
  
  
开始。  
  
如果你的场景整体偏暗：  
  
1.25 ~ 1.45  
  
  
不要直接用 2、3。  
  
否则雪会非常容易变成纯白。  
  
六、太阳阴影  
  
开启：  
  
Shadow Enabled = ON  
  
  
然后重点调整：  
  
Shadow Max Distance  
  
  
对于你这种俯视角第三人称：  
  
Shadow Max Distance = 80 ~ 120  
  
  
如果你的地图比较小：  
  
60 ~ 80  
  
  
即可。  
  
你的截图里房屋、汽车、电线杆的阴影都很重要，所以不要让阴影距离太短。  
  
Shadow Blur  
  
如果你的版本/渲染设置允许，适当增加阴影软度。  
  
目标：  
  
不是硬边游戏阴影。  
  
而是：  
  
冬日上午摄影。  
  
树枝的阴影应该：  
  
🌳   
╲ ╲ ╲   
╲ ╲   
╲  
  
  
稍微柔和。  
  
七、非常重要：Environment → Tonemap  
  
如果你使用 Godot 4.6：  
  
Tonemap Mode:   
AGX  
  
  
AGX 在 Godot 4.6 中是可用的电影感 Tone Mapper，并且比其他模式更擅长保持高亮区域的色相。   
G   
Godot Engine documentation  
  
如果你的版本没有 AGX：  
  
Filmic  
  
  
或者：  
  
ACES   
我的初始值   
4.6：   
Tonemap:   
AGX  
  
Exposure:   
1.0  
  
AGX Contrast:   
[1.05 ~ 1.12](x-apple-data-detectors://embedded-result/2722)  
  
  
如果整体太亮：  
  
Exposure = 0.92  
  
  
如果太暗：  
  
Exposure = 1.05   
八、Color Grading  
  
进入：  
  
Environment   
→ Adjustments  
  
  
打开：  
  
Adjustment Enabled = ON  
  
  
建议：  
  
Brightness = 1.00  
  
Contrast = 1.08  
  
Saturation = 0.90  
  
  
注意：  
  
不要增加 Saturation。  
  
你现在的画面已经很蓝。  
  
如果：  
  
Saturation = 1.2  
  
  
会变成：  
  
“蓝色滤镜”。  
  
我反而建议：  
  
0.88 ~ 0.94  
  
  
这样红车和橙色窗户会显得更加突出。  
  
Godot 的 Adjustment 是在 Tonemap 后处理阶段执行的，因此这里适合做最后的整体色彩微调，而不是拿它代替光照。   
G   
Godot Engine documentation  
  
九、我建议做一个 LUT  
  
如果你愿意做 LUT，我建议最终的 Color Grade：  
  
Shadows  
  
偏：  
  
Blue + Cyan   
Midtones  
  
偏：  
  
Blue   
Highlights  
  
偏：  
  
Warm Yellow / Orange  
  
  
也就是：  
  
SHADOW   
↓   
Blue / Cyan  
  
MID   
↓   
Cold Blue  
  
HIGHLIGHT   
↓   
Warm White  
  
  
这是整个游戏的核心色彩逻辑。  
  
十、SSAO  
  
打开：  
  
Environment   
→ SSAO  
  
  
建议：  
  
Enabled = ON  
  
Radius:   
[1.5 ~ 2.5](x-apple-data-detectors://embedded-result/3431)  
  
Intensity:   
[1.2 ~ 1.5](x-apple-data-detectors://embedded-result/3454)  
  
Power:   
1.2  
  
Detail:   
0.4 ~ 0.6  
  
  
Godot 的 SSAO 会加强角落和凹陷区域的环境遮蔽，特别适合小型动态物件和建筑细节。   
G   
Godot Engine documentation  
  
但是：  
  
不要让 AO 黑成一条线。  
  
你的风格应该是：  
  
雪   
████████  
  
墙   
██████  
  
交界   
██████  ← 深一点  
  
  
而不是：  
  
██████   
██████   
██████  ← 黑线   
十一、Fog：让远处变蓝  
  
这个对于你的截图非常重要。  
  
设置：  
  
Fog Mode:   
Depth  
  
  
然后：  
  
Fog Light Color:   
#8CB4D9  
  
Fog Light Energy:   
0.7  
  
Fog Density:   
0.015 ~ 0.025  
  
Fog Depth Begin:   
30  
  
Fog Depth End:   
120  
  
  
如果你的场景单位比较大，可以扩大到：  
  
Begin = 50   
End = 200  
  
  
Godot 的 Depth Fog 可以通过开始距离和深度控制提供比纯指数雾更直接的艺术控制，很适合你的这种风格化空气透视。   
G   
Godot Engine documentation  
  
十二、Aerial Perspective  
  
如果你使用 Sky：  
  
Background Energy Multiplier:   
0.4 ~ 0.7  
  
  
我推荐：  
  
0.55  
  
  
这个参数正好适合：  
  
远处逐渐融入天空。  
  
于是：  
  
前景树   
#17283D  
  
```
    ↓

```
中景树   
#355777  
  
```
    ↓

```
远景树   
#7099C2  
  
  
这会非常漂亮。  
  
十三、Glow/Bloom  
  
你的游戏千万不要做强 Bloom。  
  
只需要：  
  
Glow Enabled = ON  
  
Glow Bloom = 0.04 ~ 0.08  
  
Glow Intensity = very low  
  
  
重点：  
  
只有暖光需要 Glow。  
  
例如：  
  
🟧 Window   
🟧 Lantern   
🟧 Campfire  
  
  
不要让雪发光。  
  
否则：  
  
雪地 = 圣光。  
  
会很廉价。  
  
Godot 的 Glow 本质上是让亮像素向周围扩散，因此只需要让少量 HDR 暖光进入阈值即可。   
G   
Godot Engine documentation  
  
十四、雪地 Shader  
  
现在开始真正提升画面。  
  
我给你一个无贴图版本。  
  
它通过世界坐标生成非常细腻的雪面变化。  
  
创建：  
  
ShaderMaterial   
→ SnowGround.tres  
  
  
Shader：  
  
shader_type spatial;  
  
render_mode diffuse_burley, specular_schlick_ggx;  
  
uniform vec3 snow_color : source_color = vec3(0.60, 0.76, 0.90);   
uniform vec3 snow_shadow_color : source_color = vec3(0.38, 0.55, 0.72);  
  
uniform float noise_scale = 0.045;   
uniform float noise_strength = 0.055;  
  
uniform float streak_scale = 0.12;   
uniform float streak_strength = 0.025;  
  
uniform float roughness = 0.92;  
  
varying vec3 world_pos;  
  
  
/* -----------------------------   
Simple hash   
----------------------------- */  
  
float hash21(vec2 p) {   
p = fract(p * vec2(123.34, 456.21));   
p += dot(p, p + 45.32);   
return fract(p.x * p.y);   
}  
  
  
/* -----------------------------   
Value Noise   
----------------------------- */  
  
float noise2d(vec2 p) {  
  
```
vec2 i = floor(p);
vec2 f = fract(p);

f = f * f * (3.0 - 2.0 * f);

float a = hash21(i);
float b = hash21(i + vec2(1.0, 0.0));
float c = hash21(i + vec2(0.0, 1.0));
float d = hash21(i + vec2(1.0, 1.0));

return mix(
    mix(a, b, f.x),
    mix(c, d, f.x),
    f.y
);

```
}  
  
  
void vertex() {  
  
```
world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

```
}  
  
  
void fragment() {  
  
```
vec2 p = world_pos.xz;

float large_noise =
    noise2d(p * noise_scale);

float small_noise =
    noise2d(p * noise_scale * 4.0);

float variation =
    (large_noise - 0.5) * noise_strength;

variation +=
    (small_noise - 0.5) * noise_strength * 0.35;


/* Wind-shaped snow streaks */

float streak =
    sin(
        p.x * streak_scale +
        noise2d(p * 0.03) * 4.0
    );

streak =
    smoothstep(
        0.55,
        0.95,
        streak
    );

variation +=
    streak * streak_strength;


vec3 base =
    mix(
        snow_shadow_color,
        snow_color,
        0.65
    );

ALBEDO =
    clamp(
        base + variation,
        vec3(0.0),
        vec3(1.0)
    );

ROUGHNESS = roughness;

SPECULAR = 0.15;

```
}   
十五、这个 Shader 应该呈现什么效果？  
  
不是：  
  
Noise Noise Noise Noise  
  
  
而是：  
  
────────────────────   
很轻微的色彩变化   
────────────────────   
～～～～   
────────────────────  
  
  
你肉眼应该几乎看不到 Noise。  
  
但是整个雪地不再是：  
  
#9BC3E8   
#9BC3E8   
#9BC3E8   
#9BC3E8  
  
  
而是：  
  
#9BC3E8   
#96BEE4   
#A0C7E9   
#93BDE3  
  
  
这样会非常自然。  
  
十六、如果你有真实雪地高度，可以再加一点 Vertex Displacement  
  
如果你的地形本身是大平面：  
  
可以增加：  
  
uniform float displacement = 0.15;  
  
  
然后：  
  
VERTEX.y +=   
noise2d(VERTEX.xz * 0.03)   
* displacement;  
  
  
但是：  
  
我不建议现在直接加。  
  
你的游戏风格是极简。  
  
先用真实地形：  
  
Snowbank   
Snowdrift   
Footprint  
  
  
比 Shader 乱起伏更好。  
  
十七、最重要的 Shader：积雪 Shader  
  
这个东西会让你的房屋提升非常明显。  
  
思路：  
  
# NORMAL 朝上   
# +   
# 高度   
# +   
# Noise  
  
积雪   
SnowAccumulation.gdshader   
shader_type spatial;  
  
render_mode diffuse_burley, specular_schlick_ggx;  
  
uniform vec3 base_color : source_color = vec3(0.30, 0.43, 0.57);   
uniform vec3 snow_color : source_color = vec3(0.78, 0.88, 0.96);  
  
uniform float snow_amount = 0.55;   
uniform float snow_threshold = 0.58;   
uniform float snow_softness = 0.16;  
  
uniform float snow_noise_scale = 0.08;   
uniform float snow_noise_strength = 0.15;  
  
uniform float snow_brightness = 1.0;  
  
varying vec3 world_pos;   
varying vec3 world_normal;  
  
  
/* -----------------------------   
Hash   
----------------------------- */  
  
float hash21(vec2 p) {  
  
```
p = fract(p * vec2(123.34, 456.21));

p += dot(
    p,
    p + 45.32
);

return fract(
    p.x * p.y
);

```
}  
  
  
/* -----------------------------   
Noise   
----------------------------- */  
  
float noise2d(vec2 p) {  
  
```
vec2 i = floor(p);
vec2 f = fract(p);

f = f * f * (3.0 - 2.0 * f);

float a = hash21(i);
float b = hash21(i + vec2(1.0, 0.0));
float c = hash21(i + vec2(0.0, 1.0));
float d = hash21(i + vec2(1.0, 1.0));

return mix(
    mix(a, b, f.x),
    mix(c, d, f.x),
    f.y
);

```
}  
  
  
void vertex() {  
  
```
world_pos =
    (MODEL_MATRIX *
    vec4(VERTEX, 1.0)).xyz;

world_normal =
    normalize(
        (MODEL_MATRIX *
        vec4(NORMAL, 0.0)).xyz
    );

```
}  
  
  
void fragment() {  
  
```
float topness =
    dot(
        normalize(world_normal),
        vec3(0.0, 1.0, 0.0)
    );


/* -----------------------------
   Only surfaces facing upward
----------------------------- */

float top_mask =
    smoothstep(
        snow_threshold - snow_softness,
        snow_threshold + snow_softness,
        topness
    );


/* -----------------------------
   Natural snow edge
----------------------------- */

float n =
    noise2d(
        world_pos.xz *
        snow_noise_scale
    );

float snow_edge =
    smoothstep(
        0.5 - snow_noise_strength,
        0.5 + snow_noise_strength,
        n
    );


float snow_mask =
    top_mask *
    snow_edge *
    snow_amount;


vec3 final_color =
    mix(
        base_color,
        snow_color,
        snow_mask
    );


ALBEDO =
    final_color *
    snow_brightness;

ROUGHNESS =
    mix(
        0.8,
        0.96,
        snow_mask
    );

SPECULAR =
    mix(
        0.35,
        0.08,
        snow_mask
    );

```
}   
十八、这个 Shader 怎么使用？   
房屋墙体  
  
不要用。  
  
屋顶  
  
非常适合。  
  
木棚  
  
适合。  
  
汽车  
  
可以使用，但是：  
  
snow_amount = 0.25   
电线杆   
snow_amount = 0.10   
树枝   
snow_amount = 0.35   
十九、屋顶的参数  
  
你的截图中屋顶是非常重要的。  
  
建议：  
  
snow_amount = 0.75  
  
snow_threshold = 0.48  
  
snow_softness = 0.12  
  
snow_noise_scale = 0.05  
  
snow_noise_strength = 0.12  
  
  
这样：  
  
屋顶大部分积雪。  
  
而墙壁：  
  
基本没有。  
  
二十、但是我建议屋顶再做一层“厚雪边缘”  
  
Shader 只能改变颜色。  
  
它不能真正形成厚度。  
  
所以屋顶最好再放一层：  
  
SnowCapMesh  
  
  
也就是非常薄的几何体。  
  
比如：  
  
Roof   
████████████  
  
Snow   
▓▓▓▓▓▓▓▓▓▓  
  
  
厚度：  
  
0.03 ~ 0.10  
  
  
根据你的世界尺寸调整。  
  
这会让屋檐出现：  
  
```
  ❄❄❄❄❄
███████████

```
████████████  
  
  
这是非常值得做的。  
  
二十一、雪花粒子系统  
  
你的雪花不要一套解决全部。  
  
我建议：  
  
三层雪   
Layer 1：远景雪   
GPUParticles3D   
Amount = 1000 ~ 1800   
Lifetime = 8 ~ 14  
  
  
Emission Box：  
  
X = 60   
Y = 25   
Z = 60  
  
  
速度：  
  
Initial Velocity = 0.8 ~ 1.4  
  
  
Gravity：  
  
Y = -0.15 ~ -0.25  
  
  
风：  
  
X = 0.25 ~ 0.45   
Z = 0.05 ~ 0.15  
  
  
粒子尺寸：  
  
0.025 ~ 0.05   
二十二、第二层雪  
  
这是玩家真正能看到的。  
  
Amount:   
300 ~ 600  
  
Lifetime:   
5 ~ 8 sec  
  
Size:   
0.04 ~ 0.08  
  
  
速度：  
  
1.2 ~ 2.0  
  
  
风：  
  
X = 0.5 ~ 0.8  
  
  
随机性：  
  
Randomness:   
0.35 ~ 0.55  
  
  
Godot 的 GPUParticles3D 可以直接使用 ParticleProcessMaterial，粒子数据在 GPU 上处理；同时也可以使用自定义 ShaderMaterial。   
G   
Godot Engine documentation   
+1  
  
二十三、第三层：镜头前雪花  
  
这个非常重要。  
  
Amount:   
30 ~ 60  
  
Lifetime:   
3 ~ 5 sec  
  
Size:   
0.10 ~ 0.18  
  
  
然后放在：  
  
Camera   
└── SnowForeground  
  
  
它不需要真实世界空间。  
  
目的就是：  
  
偶尔有一片雪从镜头前经过。  
  
这会让截图瞬间有电影感。  
  
二十四、雪花材质  
  
不要用普通白色圆点。  
  
可以使用：  
  
QuadMesh  
  
  
配：  
  
StandardMaterial3D  
  
  
或者：  
  
ShaderMaterial  
  
  
做一个非常简单的雪花：  
  
```
  *
* | *

```
*---+---*   
* | *   
*  
  
  
但是实际尺寸非常小。  
  
二十五、如果你想让雪花有轻微旋转  
  
Godot 粒子 Shader 可以读取 INSTANCE_CUSTOM；对于默认粒子数据，其中包含旋转角、生命周期相位等信息。   
G   
Godot Engine documentation   
+1  
  
可以使用：  
  
shader_type spatial;  
  
render_mode unshaded, cull_disabled, depth_draw_alpha_prepass;  
  
varying float particle_phase;  
  
void vertex() {  
  
```
particle_phase = INSTANCE_CUSTOM.y;

float angle =
    INSTANCE_CUSTOM.x;

mat2 rotation = mat2(
    vec2(cos(angle), -sin(angle)),
    vec2(sin(angle),  cos(angle))
);

VERTEX.xz =
    rotation *
    VERTEX.xz;

```
}  
  
void fragment() {  
  
```
vec2 p = UV - vec2(0.5);

float d = length(p);

float alpha =
    smoothstep(
        0.5,
        0.15,
        d
    );

ALBEDO =
    vec3(0.9, 0.97, 1.0);

ALPHA =
    alpha * 0.75;

```
}  
  
  
不过这个版本是“柔和雪点”。  
  
如果你的目标是更艺术化，我更推荐用六角雪花纹理。  
  
二十六、你的汽车应该怎么改  
  
回到你这张截图。  
  
现在：  
  
```
    HOUSE
      │
   🚗

```
我会把汽车变成第二视觉中心。  
  
汽车材质  
  
红色不要纯红：  
  
#9B3D3D  
  
  
受光面：  
  
#B64A43  
  
  
阴影：  
  
#5E2930   
汽车上积雪  
  
不要整个覆盖。  
  
只覆盖：  
  
车顶   
引擎盖   
后备箱   
轮胎上缘  
  
  
而且：  
  
snow_amount = 0.25   
二十七、汽车下面一定增加接地阴影  
  
你现在汽车有阴影。  
  
但是可以加强：  
  
Car   
↓   
Dark AO   
↓   
Snow depression  
  
  
可以做一个非常淡的 decal：  
  
深蓝透明   
alpha = 0.15 ~ 0.25  
  
  
不要黑。  
  
二十八、轮胎痕迹  
  
这个我强烈建议做成独立 Decal。  
  
比如：  
  
```
  HOUSE
    │
    │
   🚗
  ╱  ╲
 ╱    ╲

```
两条轮胎痕。  
  
颜色：  
  
#7199BD  
  
  
透明度：  
  
0.25 ~ 0.45  
  
  
然后逐渐消失：  
  
🚗   
╲   
╲   
╲   
╲   
...  
  
  
这会比任何后处理都更有“生存游戏”的感觉。  
  
二十九、你截图里的房屋：具体这样改  
  
你的房子是整个画面的核心。  
  
我会做：  
  
屋顶   
80% 雪   
墙体   
冷蓝灰木材   
窗户   
2~3 个暖窗  
  
  
颜色：  
  
#FFB45C  
  
  
Emission：  
  
1.5 ~ 3.0  
  
  
但是只让非常少的窗口发光。  
  
三十、烟囱  
  
你已经有烟囱。  
  
这是一个极好的叙事元素。  
  
加入：  
  
GPUParticles3D  
  
  
不是黑烟。  
  
而是：  
  
淡灰蓝 + 半透明  
  
  
初始：  
  
Amount = 2040   
Lifetime = 47   
Velocity Y = 0.30.6   
Spread = 2035  
  
  
然后烟：  
  
上升   
→   
稍微被风吹   
→   
消散  
  
  
这一个东西就可以告诉玩家：  
  
屋子里面有人。  
  
三十一、树木：不要全部同一种黑  
  
你截图里右上方的大树非常有潜力。  
  
我会把它变成：  
  
Hero Tree  
  
也就是视觉元素。  
  
它应该比其他树：  
  
更深   
更复杂   
更有轮廓  
  
  
颜色：  
  
#172638  
  
  
然后树下有一点：  
  
#789BC0  
  
  
蓝色反射光。  
  
三十二、左下角的树  
  
现在它比较像：  
  
地图装饰。  
  
我会让它成为前景框架。  
  
例如：  
  
```
    HOUSE

          🌲

```
🌲   
███   
███   
███  
  
  
左下树可以稍微放大：  
  
Scale:   
[1.2 ~ 1.4](x-apple-data-detectors://embedded-result/12473)  
  
  
然后让一部分枝干靠近镜头。  
  
这样形成：  
  
Foreground Framing  
  
三十三、右边孤零零的小树  
  
这个我建议保留。  
  
因为它非常有：  
  
“孤独感”。  
  
但是把它降低一点对比度。  
  
例如：  
  
原:   
#182638  
  
改:   
#3E5D7D  
  
  
它应该是：  
  
环境叙事。  
  
而不是：  
  
视觉中心。  
  
三十四、电线杆是构图核心  
  
你现在电线：  
  
House ───────── Pole  
  
  
非常好。  
  
不要删。  
  
甚至可以略微强化。  
  
电线颜色：  
  
#253A50  
  
  
但不要纯黑。  
  
电线杆：  
  
#344B63  
  
  
然后让太阳在杆上产生：  
  
细长阴影  
  
  
这样它会和房屋阴影一起形成视觉方向。  
  
三十五、你的画面应该增加“雪地层次”  
  
我建议把地面分成：  
  
SnowBase   
↓   
SnowDrift   
↓   
Footprints   
↓   
TireTracks   
↓   
ObjectAO   
↓   
SmallProps  
  
  
而不是一张 Plane。  
  
三十六、雪堆 Shader 可以很简单  
  
例如雪堆材质：  
  
shader_type spatial;  
  
uniform vec3 snow_color : source_color = vec3(0.63, 0.78, 0.91);  
  
varying vec3 world_pos;  
  
void vertex() {  
  
```
world_pos =
    (MODEL_MATRIX *
    vec4(VERTEX, 1.0)).xyz;

float wave =
    sin(world_pos.x * 0.15) *
    sin(world_pos.z * 0.11);

VERTEX.y +=
    wave * 0.03;

```
}  
  
void fragment() {  
  
```
float lighting =
    dot(
        normalize(NORMAL),
        normalize(vec3(-0.3, 1.0, 0.2))
    );

lighting =
    clamp(lighting, 0.65, 1.0);

ALBEDO =
    snow_color * lighting;

ROUGHNESS = 0.95;

```
}  
  
  
只要一点点。  
  
不要做成沙丘。  
  
三十七、你需要一个“雪地压实区”  
  
房屋周围：  
  
```
   HOUSE

```
┌─────────┐   
│         │   
└─────────┘  
  
```
  ╭─────╮

```
╭──╯     ╰──╮  
  
  
也就是：  
  
房屋周围的雪应该比远处稍暗、稍蓝。  
  
因为人经常走。  
  
颜色：  
  
Normal Snow:   
#A4C7E7  
  
Compacted Snow:   
#789CC1  
  
  
这样玩家自然会看到：  
  
“这里经常有人活动。”  
  
三十八、把整个场景的“冷暖故事”建立起来  
  
最终：  
  
```
             BLUE
              ↓
         ❄ ❄ ❄ ❄

     🌲
       \
        \
    ┌─────────┐
    │   🟧    │
    │ 🟧      │
    │  HOUSE  │
    └─────────┘
          \
           \
          🚗
         RED

   👣 👣 👣

             │
             │
             │
           POLE

```
你会得到三个视觉层：  
  
第一层  
  
蓝色自然  
  
第二层  
  
房屋 / 汽车  
  
第三层  
  
橙色生命  
  
这就是我认为最适合你游戏的视觉语言。  
  
三十九、建议加一个非常轻的 Volumetric Fog  
  
如果你用 Forward+：  
  
Volumetric Fog:   
ON  
  
Density:   
0.0008 ~ 0.002  
  
Albedo:   
#B8D4EA  
  
Anisotropy:   
0.1 ~ 0.2  
  
Ambient Inject:   
0.15  
  
Sky Affect:   
0.6  
  
  
千万不要：  
  
Density = 0.01  
  
  
那会太雾。  
  
你的目标是：  
  
空气中有一点冰冷湿度。  
  
而不是：  
  
玩家看不见路。  
  
Godot 4.6 的 Volumetric Fog 是基于 froxel buffer 的体积散射系统，并能与灯光交互；但只适用于 Forward+。   
G   
Godot Engine documentation  
  
四十、最后加入轻微 Camera DOF  
  
这里要谨慎。  
  
因为这是游戏，不是宣传片。  
  
我建议：  
  
DOF Enabled = ON  
  
Near:   
1 ~ 2  
  
Far:   
100 ~ 150  
  
Blur:   
非常低  
  
  
甚至我建议：  
  
Gameplay  
  
关闭。  
  
Photo Mode  
  
开启。  
  
因为你这个场景非常适合 Photo Mode。  
  
四十一、我建议你做一个 Photo Mode  
  
因为你的画面已经很接近：  
  
游戏截图 = 概念艺术  
  
所以可以给玩家：  
  
Photo Mode   
│   
├── Exposure   
├── Saturation   
├── Snow Intensity   
├── Fog   
├── Sun Angle   
├── Camera Tilt   
└── Depth of Field  
  
  
这会非常适合这种第三人称俯视游戏。  
  
四十二、最终参数表  
  
你可以直接照着做第一版：  
  
系统	参数	推荐值   
Tonemap	AGX	ON   
Exposure		1.00   
Contrast		1.08   
Saturation		0.90   
Ambient Color		#668BB5   
Ambient Energy		0.62   
Sun Color		#FFD5A6   
Sun Energy		1.15   
Sun X		-52°   
Sun Y		-35°   
Shadow Distance		80120   
Fog Color		#8CB4D9   
Fog Density		0.0150.025   
Fog Begin		30   
Fog End		120   
SSAO		ON   
SSAO Intensity		1.21.5   
Glow		ON   
Glow Bloom		0.040.08   
Volumetric Fog		0.00080.002   
Snow Noise		极低   
Snow Roughness		0.920.96   
Snow Particles		10001800   
Foreground Snow		3060   
Window Emission		1.5~3.0   
四十三、按照你这张截图，我会这样改  
  
这是最重要的一部分。  
  
① 右上大树  
  
保留。  
  
但是：  
  
更深   
更大   
更有枝条  
  
  
把它做成画面右上角的“剪影”。  
  
② 房屋  
  
这是：  
  
第一视觉中心  
  
增加：  
  
屋顶厚雪   
窗户暖光   
烟囱烟雾   
墙体 AO   
门口脚印   
屋檐积雪   
③ 红色汽车  
  
这是：  
  
第二视觉中心  
  
增加：  
  
积雪   
轮胎压痕   
车底 AO   
车轮轨迹   
一点红色高光   
④ 左下树  
  
变成：  
  
前景框架  
  
放大：  
  
1.2x ~ 1.4x  
  
  
并让枝干进入画面边缘。  
  
⑤ 右边小树  
  
降低：  
  
Contrast   
Saturation  
  
  
让它退到中景。  
  
⑥ 电线杆  
  
保留并强化。  
  
让电线形成：  
  
Pole   
╲   
╲   
╲   
HOUSE  
  
  
的构图线。  
  
⑦ 雪地  
  
现在最大的问题是：  
  
太平。  
  
增加：  
  
Snow Drift   
Footprints   
Tire Tracks   
Compacted Snow   
Subtle Noise  
  
  
但不要加大量纹理。  
  
⑧ 天空  
  
增加：  
  
Gradient  
  
  
顶部：  
  
#5D96D3  
  
  
底部：  
  
#B1D0EA   
四十四、最终应该得到这样的“视觉层级”   
┌───── Atmosphere ─────┐  
  
```
                🌲
             HERO TREE

                  ↓

        ┌────────────────┐
        │                │
        │    🟧 HOUSE    │ ← 主体
        │                │
        └────────────────┘

             👣 👣
          🚗               ← 第二主体

   🌲                           🌲
Foreground                 Background

              │
              │
              │
             POLE
              ╲
               ╲
                ╲

      ─── Snow Landscape ───

```
这时候你的游戏截图就会从：  
  
“一个做得不错的低多边形冬季场景”  
  
变成：  
  
“有明确美术指导和摄影语言的独立游戏场景”。  
  
四十五、最后一个非常重要的建议：先不要加更多模型  
  
如果你现在让我给你的项目排优先级，我会这样排：  
  
★★★★★ 光照   
★★★★★ 雪材质   
★★★★★ 积雪   
★★★★★ 空气透视   
★★★★★ 构图  
  
★★★★☆ 脚印   
★★★★☆ 轮胎痕   
★★★★☆ 暖窗   
★★★★☆ 烟囱烟  
  
★★★☆☆ 雪花   
★★★☆☆ 小道具  
  
★★☆☆☆ 更复杂模型   
★☆☆☆☆ 更高分辨率纹理  
  
  
也就是说：  
  
先不要建 100 个新资产。  
  
你现在已有的：  
  
房子 + 汽车 + 树 + 电线杆 + 雪地  
  
其实已经足够做出很漂亮的场景。  
  
你缺的不是“东西”。  
  
而是：  
  
光、雪、空气、层次、色彩和叙事。  
  
最推荐的实际实施顺序   
Day 1   
DirectionalLight   
↓   
Environment   
↓   
Tonemap   
↓   
SSAO   
↓   
Fog  
  
  
先把整张图调到漂亮。  
  
Day 2   
Snow Ground Shader   
↓   
Snow Accumulation Shader   
↓   
Roof Snow Mesh  
  
  
让“雪”成为真正的主角。  
  
Day 3   
Footprints   
↓   
Tire Tracks   
↓   
Compacted Snow   
↓   
AO Decals  
  
  
让世界开始“有人生活”。  
  
Day 4   
Warm Windows   
↓   
Chimney Smoke   
↓   
Car Snow  
  
  
加入生命感。  
  
Day 5   
Snow Particles   
↓   
Foreground Snow   
↓   
Atmospheric Fog   
↓   
Final Color Grade  
  
  
最后才做氛围。  
  
这样做出来的结果会比一上来堆 Bloom、粒子、DOF、雾、贴图稳定得多。  
  
如果你现在使用的是 Godot 4.x + Forward+，上面的体系可以直接作为第一版基准；Godot 官方文档目前的 4.6 API 也支持上述 Environment、Spatial Shader 和 GPUParticles3D 相关能力。   
G   
Godot Engine documentation   
