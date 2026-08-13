# Directional Shadow Ripple Validation

## Finding

The fine herringbone/scanline pattern reported in the snow was not a road,
footprint, farm-furrow, snow-grain, terrain-window seam, or the snow-shadow
palette. It was the variable PCSS penumbra of the directional light. At the
previous `0.9` degree angular size, a long, grazing shadow spread the rotating
shadow-map samples over enough pixels for the two-band snow shader to make the
samples visible as a ripple.

The affected snow is a **receiver** of external cast shadows. It is not the
terrain casting onto itself: turning the Terrain node's shadow caster off left
the artifact present, while disabling the directional shadows removed it.

## Reproducible capture

The real scene is captured by `tools/capture_shadow_ripple_ab.tscn`, not a
mock. It supports controls that isolate each plausible cause:

```powershell
& "D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" `
  --path "D:/Godot resource/winter-time" `
  "res://tools/capture_shadow_ripple_ab.tscn" --resolution 1600x1000 -- `
  --out "C:/Users/aresr/AppData/Local/Temp/shadow-ripple.png" `
  --seconds 3 --settle 1 --preset pale_day --ripple-mode control
```

`no_terrain_cast`, `no_shadows`, `flat_ground`, `no_grain`, `no_penumbra`, and
the three penumbra widths are intentionally independent controls. The test
`tests/art/test_shadow_ripple_capture.gd` prevents this actual-scene capture
path and its isolation matrix from silently disappearing.

## A/B result

| Control | Result |
| --- | --- |
| Current before: Soft High, 0.90 degrees, blur 1.0 | Broad tree shadows contain visible fine herringbone/ripple samples. |
| Terrain does not cast shadows | Ripple remains; ground self-shadowing is not the source. |
| All directional shadows disabled | Ripple disappears; normal snow, static tracks and grain are cleared. |
| Flat terrain / no snow grain | Does not remove the ripple at the original penumbra. |
| Hard filter at 0.90 degrees | Does not remove the ripple: the oversized variable penumbra is the root condition. |
| No penumbra | Removes ripple, but exposes unacceptable stair-step shadow edges. |
| 0.15 / 0.30 / 0.50 degrees | 0.30 is the narrowest setting that retains a visibly continuous, snow-soft long shadow without the broad high-frequency pattern. |

## Shipping correction

The directional filter remains Soft High, which preserves the intended soft
silhouette. The light's angular size is reduced from `0.9` to `0.3` degrees and
its matching constant blur from `1.0` to `0.5`. This removes the oversized
sampled penumbra rather than hiding the fault by changing shadow hue, fog,
terrain shape, tracks, shadow bias, normal bias, or cascade coverage.

The final actual-tree verification was written outside the repository to:

`C:/Users/aresr/AppData/Local/Temp/winter_time_shadow_ripple_tree_after.png`

It keeps long tree shadows and has no fine screen-space ripple in the affected
snow. The temporary in-repository A/B PNGs were removed after review so they
cannot be accidentally staged as game content.

## Test state at validation

`bash tools/run_tests.sh` reached the new shadow-ripple tests successfully.
The overall run was not clean: two unrelated, in-progress farmstead/winter
stubble transition tests failed, and the wrapper reported existing absolute
`get_node()` errors. No test in this change failed.
