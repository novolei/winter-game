# 字体

《长夜将尽》的三个字族，全部 **SIL Open Font License 1.1**，可随游戏发行，无需署名于游戏内。

规格见 [UI 设计文档 §2.2](../../Docs/superpowers/specs/2026-08-12-winter-survival-ui-design.md)。

---

## 文件

轴范围是从每个文件自己的 `fvar` 表里读出来的，不是抄自网页。

| 文件 | 体积 | 轴 | 用途 |
|---|---|---|---|
| `NotoSerifSC-VF.otf` | 21.57 MB | `wght` **200–900**（默认 200） | 展示族 · 中文 |
| `NotoSansSC-VF.otf` | 14.36 MB | `wght` 100–900（默认 100） | 界面族 · 中文 |
| `CormorantGaramond-VF.ttf` | 1.14 MB | `wght` 300–700（默认 300） | 展示族 · 拉丁 |
| `Inter-VF.ttf` | 0.84 MB | `opsz` 14–32 · `wght` 100–900 | 界面族 · 拉丁 |
| `IBMPlexMono-Light.ttf` | 0.13 MB | 静态 | 仪表族 |

**`NotoSerifSC-VF` 的下限是 200，不是 100。** ExtraLight 已经是它能到的最细一档——设计要的正是这一档，但想再细是调不动的，别把时间花在找那个轴上。

Cormorant Garamond 的默认值就是 300，即设计要的 Light，不设 `wght` 也对。

### 来源

```
NotoSerifSC-VF.otf        notofonts/noto-cjk  Serif/Variable/OTF/Subset/NotoSerifSC-VF.otf
NotoSansSC-VF.otf         notofonts/noto-cjk  Sans/Variable/OTF/Subset/NotoSansSC-VF.otf
CormorantGaramond-VF.ttf  google/fonts        ofl/cormorantgaramond/CormorantGaramond[wght].ttf
Inter-VF.ttf              google/fonts        ofl/inter/Inter[opsz,wght].ttf
IBMPlexMono-Light.ttf     google/fonts        ofl/ibmplexmono/IBMPlexMono-Light.ttf
```

**为什么用可变字体而不是静态字重。** 不是为了灵活，是因为它更小：Noto Serif SC 的
单个 ExtraLight 静态 OTF 是 20.41 MB，而整条 200–900 轴的可变字体是 21.57 MB。多花
1.16 MB 买到全部七档字重，没有理由不要。

---

## 在 Godot 里怎么装 —— 顺序是反的

**拉丁字体必须是主字体，中文字体必须是回退字体。** 反过来写会得到一份看起来完全正常、
但拉丁字母全部错误的 UI。

Noto Serif SC / Noto Sans SC **自带一套拉丁字形**（思源系列基于 Source Serif / Source
Sans 做了配套拉丁）。Godot 逐字形解析：主字体有这个字就用主字体，没有才落到回退。所以
把 Noto 放在主位，它自己的拉丁字形永远命中，**Cormorant 和 Inter 一次都不会被用到**——
而且不会有任何报错，字也照样显示，只是显示的不是你选的那一套。

正确的写法：

```gdscript
# 展示族：Cormorant 主 + 思源宋体回退
var display := FontVariation.new()
display.base_font = load("res://assets/fonts/CormorantGaramond-VF.ttf")
display.variation_opentype = { &"wght": 300 }

var display_cjk := FontVariation.new()
display_cjk.base_font = load("res://assets/fonts/NotoSerifSC-VF.otf")
display_cjk.variation_opentype = { &"wght": 200 }

display.fallbacks = [display_cjk]
```

界面族同理：`Inter-VF.ttf` 主，`NotoSansSC-VF.otf` 回退，字重 300。

Inter 还有一条 `opsz` 光学尺寸轴（14–32）。把它设成实际字号，字形会按该尺寸优化：

```gdscript
interface.variation_opentype = { &"wght": 300, &"opsz": 22 }
```

仪表族是静态文件，直接 `load()` 即可，不需要 `FontVariation`。它只用来排数字，
**必须开表格数字**：

```gdscript
instrument.opentype_features = { &"tnum": 1 }
```

---

## 一条排版补偿

Cormorant Garamond 是 Garamond 血统，**x-height 明显偏小**：同样字号下，它比 Inter 或
Marcellus 视觉上小一号。字样比对（`Docs/prototypes/` 的字样页）确认了这一点。

- 拉丁与中文**分行**出现时（标题/副标题就是这样），不必补偿——副标题本来就该更弱
- 拉丁与中文**同行混排**时，拉丁字号取 **1.15×** 才能视觉等大

---

## 授权

五个文件全部为 SIL Open Font License 1.1：

- Noto Serif SC / Noto Sans SC — © Google，OFL-1.1
- Cormorant Garamond — © Christian Thalmann / Catharsis Fonts，OFL-1.1
- Inter — © Rasmus Andersson，OFL-1.1
- IBM Plex Mono — © IBM Corp.，OFL-1.1

OFL 允许随软件捆绑与再发行，**不要求在游戏内署名**，唯一的硬性要求是：若修改字体文件，
改名后不得使用原保留字体名。本项目不修改字体文件。
