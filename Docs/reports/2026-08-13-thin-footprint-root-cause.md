# Thin-snow footprint root-cause and recovery — 2026-08-13

## Outcome

The tire-swing screenshot is not showing a stale resource. The current code is
running, but three later footprint revisions deliberately reduced the thin-snow
branch below the camera's useful visual response. This change restores only the
player's dusting endpoint to a complete, planted three-lobe boot depression. It
does not roll back run seeding, seam work, chunked `Texture2DArray` upload,
data-driven profiles, deep-snow pockets, body impacts, or furrows.

## Git evidence and cause

- `f2054c0` established the approved `track_depth = 0.16` response: enough
  reconstructed-normal slope for marks to enter the cel shadow band.
- `8223a99` introduced the depth-dependent boot profile and the thin scuff.
- `d1c822f` then set the dust endpoint to no waist, shortened lobes, and only
  `0.18 / 0.25` heel/forefoot pressure.
- `f217eb1` multiplied that endpoint by `1.55`, but did not restore the lost
  contact area or enough mask height at the production caller's weakest bite.

The player emits a dusting at strength `0.22 * bite`, with bite in `0.70..1.0`.
Before this fix, the focused raster regression measured:

| Production case | Heel peak | Forefoot peak | Waist | Forefoot response |
|---|---:|---:|---:|---:|
| weakest bite | 0.0549 | 0.0706 | 0.0118 | 11.3 mm |
| ordinary bite | 0.0824 | 0.1020 | 0.0157 | 16.3 mm |

At the weakest bite, the reconstructed slope tilted only `5.38°`, which was
`5.17°` short of the pale-day cel boundary. The shader also disabled the rim
entirely below a `0.30` mask peak. The result could only read as two faint tonal
dots: no connected sole, no shaded wall, and no displaced-snow shoulder.

## Recovery

The human boot's dust endpoint now keeps the authored three-lobe sole and its
restrained existing load difference:

- waist influence `1.0`;
- lobe length `1.0`;
- heel / forefoot pressure `0.88 / 1.0`;
- readability multiplier neutral at `1.0`.

The renderer retains `55%` of the rim response below the deep-print gate. A
10,001-sample CPU sweep of the shader's height equation found maximum positive
height exactly `0 m`: the rim gives the depression a restrained shoulder without
raising a white halo above untouched snow.

Expected centre responses from the production range are:

| Production case | Heel peak / depth | Forefoot peak / depth | Cel slope margin |
|---|---:|---:|---:|
| weakest bite (`0.70`) | 0.137 / 21.9 mm | 0.154 / 24.6 mm | +1.06° |
| ordinary bite (`1.0`) | 0.196 / 31.3 mm | 0.220 / 35.2 mm | +5.80° |

These are visual height-field responses reconstructed per pixel. They are not
mesh displacement: a boot is smaller than the terrain mesh's quads, and pushing
those vertices down previously produced radiating shards.

## Focused TDD evidence

Only the five CPU footprint regressions were run. No D3D12 scene, capture,
full suite, or long performance test was started.

RED command:

```text
Godot_v4.7.1-stable_win64_console.exe --headless --path "D:/Godot resource/winter-time" --script res://tools/_focused_footprint_tests.gd
```

RED result:

```text
FAIL test_rim_uses_one_shared_peak_gate_without_more_track_fetches
  the shader still turns the displaced thin-snow shoulder completely off
FAIL test_every_production_bite_leaves_a_readable_thin_boot_depression
  heel peak 0.0549 is a flat tonal dot, not a depression
  forefoot peak 0.0706 left the readable thin-snow response
  waist 0.0118 disconnects heel 0.0549 from forefoot 0.0706
  weakest production bite is only 11.3 mm deep
  weakest bite tilts 5.38 degrees, only -5.17 past the cel boundary
```

GREEN result from the identical command:

```text
PASS test_rim_uses_one_shared_peak_gate_without_more_track_fetches
PASS test_the_shared_gate_keeps_a_restrained_thin_rim_below_the_snow
PASS test_every_production_bite_leaves_a_readable_thin_boot_depression
PASS test_dust_lobe_language_fades_out_completely_in_deep_snow
PASS test_dust_readability_gain_leaves_a_deep_stamp_identical
```

The temporary focused runner was deleted after GREEN. The console contained no
`WARNING:`, `ERROR:`, `SCRIPT ERROR`, parse error, or leak report. The console
processes were stopped and rechecked; only the owner's existing Godot editor was
left running.

## Files changed

- `data/tracks/human_winter_boot.tres`
- `src/definitions/track_profile_definition.gd`
- `src/rendering/snow_ground.gdshader`
- `src/systems/track_mask.gd` (comment correction only)
- `tests/unit/test_footprint_visual_profile.gd`
- `tools/generate_track_profiles.gd`

## Remaining visual acceptance

The numerical defect and its production-range regression are closed. A fresh
trail at the tire swing still needs owner visual acceptance after stopping and
restarting the currently running game, because existing mask pixels keep the
shape they were stamped with. No automated GPU capture was attempted under the
current hardware-safety constraint.
