# Footprint weathering lip correction

## Outcome

Old footprints no longer grow a new-looking snow lip as their remaining core
passes through the mask values used by a fresh shoulder. `TrackMask` remains
unchanged: subtractive fill, neighbour slump, R8 storage, max composition,
threat reads and upload behaviour keep their existing semantics.

The correction is entirely in `snow_ground.gdshader`. The shader already uses
four neighbours to reconstruct `track_slope`. The lip now also needs that
slope to contain a real spatial wall before it can release the track tone back
toward surface snow. A flat residual core has no wall and therefore no lip.

The two edge thresholds are height-gradient magnitudes:

- start: `0.002` metres per metre
- full: `0.010` metres per metre

Worked weathering samples from the focused visual model:

| state | spatial slope | legacy value-only lip | corrected lip |
|---|---:|---:|---:|
| flat residual core (`0.10`) | 0.000000 | 0.5495 | 0.0000 |
| fresh outer wall | 0.009600 | 0.1983 | 0.1968 |
| filling wall | 0.002875 | 0.5495 | 0.0183 |
| almost-flat old wall | 0.000507 | 0.4914 | 0.0000 |

Thus the real fresh shoulder retains 99.3% of its restrained lip while the
false mid-decay peak is removed. Cavity derivation is untouched and its plan
area remains monotonic as depth is removed.

## Sampling and performance

The gate reuses `track_slope` after it has already been computed in
`fragment()`. There are:

- four `track_at()` calls in `track_gradient()` (unchanged),
- one dynamic centre lookup in `fragment()` (unchanged),
- one baked centre lookup in `fragment()` (unchanged),
- zero TrackMask lookups in `light()` (unchanged),
- no new draw call, texture upload, texture allocation or TrackMask write.

The added runtime work is one vector length and one smoothstep per snow pixel.

## TDD evidence

Seam: the final shader lip weight over worked four-neighbour weathering samples,
plus the shader's existing fetch budget. This is the visible contract: whether
a spatially flat old core is presented as displaced snow.

### RED

Command: a temporary focused `SceneTree` runner loading only
`test_footprint_weathering_visual.gd`; headless CPU/dummy renderer, bounded to
four seconds. The runner was removed after the final run.

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

[godot_ai game_helper] registered mcp capture (debugger active=false, logger=true)
FAIL test_flat_weathered_core_never_becomes_a_new_snow_lip: assert_true failed. a flat 0.10 weathered core still becomes 0.550 snow lip
FAIL test_snow_lip_recedes_before_the_cavity_core_finishes_filling: assert_true failed. the lip grew while filling: fresh 0.198, filling 0.550
FAIL test_snow_lip_recedes_before_the_cavity_core_finishes_filling: assert_true failed. an almost-flat old core still carries 0.491 of a fresh snow lip
PASS test_dynamic_cavity_area_is_monotonic_while_the_print_weathers
FAIL test_weathering_gate_reuses_fragment_neighbours_without_more_fetches: assert_true failed. lip weight is not gated by the already-computed spatial edge
FAIL test_weathering_gate_reuses_fragment_neighbours_without_more_fetches: assert_true failed. the spatial edge evidence is not routed into the lip
footprint weathering focused: 1 passed, 3 failed
```

This is the intended failure: the legacy formula used centre value alone, so a
flat `0.10` core produced more lip than a fresh spatial wall.

### GREEN

The final run also loads the shader with `CACHE_MODE_IGNORE` and verifies that
the engine reports its uniforms, so the new shader source was parsed rather
than only inspected as text.

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

[godot_ai game_helper] registered mcp capture (debugger active=false, logger=true)
PASS test_flat_weathered_core_never_becomes_a_new_snow_lip
PASS test_snow_lip_recedes_before_the_cavity_core_finishes_filling
PASS test_dynamic_cavity_area_is_monotonic_while_the_print_weathers
PASS test_weathering_gate_reuses_fragment_neighbours_without_more_fetches
PASS test_snow_shader_compiles_with_the_weathering_gate
footprint weathering focused: 5 passed, 0 failed
```

Wall time was about one second. No D3D12 capture, visual stress run, complete
suite or long performance sample was run, per the hardware-safety restriction.

## Files changed

- `src/rendering/snow_ground.gdshader`
- `tests/unit/test_footprint_weathering_visual.gd`
- `Docs/reports/2026-08-13-footprint-weathering-lip.md`

## Self-review

- The patch is based on `ffc8743`; `LIGHT_IS_DIRECTIONAL` and the lighting
  calibration block are unchanged.
- Dynamic cavity detection remains derived from `centre_track` only.
- Baked tracks and furrows do not enter the new lip gate.
- TrackMask decay and gameplay/threat semantics are untouched.
- A terrain flank multiplies `track_slope` by the existing perpendicular
  correction before this gate, so the visual shoulder does not weaken merely
  because the same boot landed on a slope.

## Concern

This is a deterministic shader/CPU contract, not a new visual capture. The
thresholds deliberately preserve the measured fresh wall and remove the known
flat-core alias, but final artistic judgement still belongs to a short normal
play session observing newly made prints age under wind or snowfall.
