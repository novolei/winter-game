# Shadow palette shipping record — 2026-08-13

## Decision

The approved restrained Slate B pair is now the source-of-truth snow-shadow
palette.  It replaces the visibly blue control pair without changing fog,
light intensity, shadow bias, or any shader behaviour:

| Palette role | Control (A) | Shipped Slate B |
| --- | --- | --- |
| Snow shadow | `#6987B4` | `#76889F` |
| Deep snow / track | `#5D7BA6` | `#667890` |

The canonical output is `data/palette/color_bible.tres`; the palette, UI-token,
lighting-preset, and Blender source generators agree with it.  World-model
palette imports now load the ColorBible with `CACHE_MODE_IGNORE`, so a palette
regeneration cannot silently retain a previously cached colour.

## Runtime evidence

The last clean D3D12 / Forward+ gameplay capture pass is outside the repository
at `C:/Users/aresr/AppData/Local/Temp/winter-time-shadow-palette-shipping-20260813/`:

| Preset | Captured frame | Lit / shaded sample | Slate-B chroma ratio | Luminance ratio |
| --- | --- | --- | ---: | ---: |
| Pale day | `shipping_pale_day.png` | `#A6CBF9` / `#8FA8C7` | 0.675 | 0.830 |
| Sunrise | `shipping_sunrise.png` | `#AAB4C2` / `#8196B0` | 1.958 | 0.825 |
| Nightfall | `shipping_nightfall.png` | `#6B86A8` / `#5B6C83` | 0.656 | 0.811 |
| Deep night | `shipping_deep_night.png` | `#50647D` / `#434F5F` | 0.622 | 0.796 |
| Whiteout | `shipping_whiteout.png` | `#9ABDE6` / `#98BAE2` | 0.974 | 0.987 |

Whiteout is accepted only without a directional cast silhouette; its sampled
contrast is recorded for continuity, not used as a cast-shadow test.  The
paired control material and measurements are retained at
`C:/Users/aresr/AppData/Local/Temp/winter-time-shadow-palette-shipping-measure-20260813/`.

## Validation boundary

An attempted post-reimport capture set at
`C:/Users/aresr/AppData/Local/Temp/winter-time-shadow-palette-shipping-20260813-final/`
is intentionally **not evidence**: it ran while the concurrent SnowField line
had a parse error and reported invalid `inf` snow telemetry.  It must be
recaptured during integration once that independent line is green.

`tests/art/test_shadow_palette_shipping.gd` pins the shipped pair and asserts
that it remains cold, restrained, and subordinate to lit snow.  The normal
test wrapper also confirmed the palette art gate passes after reimporting the
two formerly stale static world models (Farmhouse and PowerPole).
