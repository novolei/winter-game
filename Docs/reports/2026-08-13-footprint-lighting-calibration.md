# Footprint lighting calibration — 2026-08-13

## Status

DONE, not committed. The owner-approved `ad54b3c` pale-day/tree-shadow cavity is
unchanged. Deep night and whiteout now receive continuous, data-driven restraint
from the lighting inputs the terrain material already receives.

## What changed

- Added tuneable footprint tone/wall scales for the deep-night and whiteout ends
  of the lighting range.
- Derived their continuous blend weights from `cel_band_threshold` and
  `cel_band_softness`; this survives LightingDirector crossfades and does not add
  a preset-name branch.
- Pale day resolves to tone scale `1.0` and wall scale `1.0`, so the signed-off
  daylight and cast-shadow result remains byte-for-byte on the existing path.
- Deep night lowers cavity floor ink to an effective scale of about `0.639` and
  wall amplification to `0.856`. This retains shape without a dead-black hole at
  the preset's 0.42 exposure.
- Whiteout lowers floor ink to `0.44` and wall amplification to `0.35`, preserving
  a shallow depression without a high-contrast decal in the soft fog band.
- Gated shade-family cast-shadow wall recovery with `LIGHT_IS_DIRECTIONAL`.
  Godot's Omni/Spot `ATTENUATION` contains distance falloff; treating it as a
  directional shadow would otherwise put false walls around stove/beacon lights.
- Roads, baked furrows, pixels outside a dynamic footprint and all mask/raster
  paths are untouched. No texture lookup, draw call, texture upload or varying
  was added.

## Measured final-light contract

The focused CPU model uses the shipped palette and shipped LightingPreset cel
inputs. Contrast is linear relative luminance before the preset's common tonemap.

| Case | Cavity contrast | Contract |
|---|---:|---:|
| pale day | 0.1011 | 0.090–0.112 |
| pale-day tree shadow | 0.0512 | 0.045–0.065 |
| deep night | about 0.0646 | 0.055–0.075 |
| whiteout | about 0.0344 | 0.025–0.045 |

The dedicated test also pins pale wall scale `1.0`, deep-night wall scale
`0.68–0.90`, whiteout wall scale `0.25–0.45`, directional-light gating, and zero
texture lookups in `light()`.

## TDD evidence

### RED

Command (CPU/headless, 0.9 seconds):

```text
Godot_v4.7.1-stable_win64_console.exe --headless --path "D:/Godot resource/winter-time" --script res://tools/_focused_footprint_lighting_calibration.gd
```

Expected failures before implementation:

```text
FAIL test_cavity_tone_is_stable_across_signed_off_lighting_extremes -- assert_true failed. deep-night cavity contrast 0.1011 is dead-black or has disappeared
FAIL test_cavity_tone_is_stable_across_signed_off_lighting_extremes -- assert_true failed. whiteout cavity contrast 0.0782 reads as a high-contrast decal
FAIL test_wall_calibration_keeps_tree_shadow_but_restrains_whiteout -- assert_true failed. deep-night wall scale 1.000 is outside the restrained readable range
FAIL test_wall_calibration_keeps_tree_shadow_but_restrains_whiteout -- assert_true failed. whiteout wall scale 1.000 is still too graphic for fog
FAIL test_wall_calibration_keeps_tree_shadow_but_restrains_whiteout -- assert_true failed. the final light pass does not consume the lighting calibration
FAIL test_wall_calibration_keeps_tree_shadow_but_restrains_whiteout -- assert_true failed. the final light pass does not restrain directional walls by lighting look
footprint lighting calibration focused: 0 passed, 2 failed
```

This was the intended RED: the former shader applied its full pale-day strength
to both lighting extremes and had no look calibration seam.

### GREEN

Final focused run includes the existing final-footprint regression, both new
calibration tests, and a real `Shader` load/uniform-list compile check. It took
1.0 second; no GUI, D3D12, visual capture, long benchmark or full suite ran.

Full final console output:

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

footprint lighting calibration focused: 3 passed, 0 failed
[godot_ai game_helper] registered mcp capture (debugger active=false, logger=true)
```

The plugin registration line is informational and was present in the RED run as
well; there was no `WARNING`, `ERROR`, `SCRIPT ERROR`, leak or shader error.

## Files changed

- `src/rendering/snow_ground.gdshader`
- `tests/unit/test_footprint_lighting_calibration.gd`
- `Docs/reports/2026-08-13-footprint-lighting-calibration.md`

The temporary focused runner was deleted after the final proof.

## Self-review and concerns

- The calibration uses existing LightingPreset cel controls rather than explicit
  preset ids. This makes transitions smooth and keeps the material independent of
  weather naming, but those controls now carry a documented secondary meaning.
- `light()` already emits a full palette contribution per light. That pre-existing
  multi-light accumulation deserves a separate audit; this task does not expand
  it and specifically prevents Omni/Spot attenuation from entering the new
  cast-shadow recovery.
- This is a CPU final-light and shader-compile proof, not a photographic approval.
  Hardware visual acceptance remains necessary, but was intentionally not run
  because the owner prohibited heavy tests after a GPU lockup.
