# Footprint final-shading depth diagnosis

## Outcome

The owner's screenshot is a real remaining defect, not a stale game session and
not evidence that the 8 cm veneer or TrackMask stamp failed to arrive.  The
shipping weakest thin-snow step already produces a compact boot raster and a
22--30 mm normal-derived response, but the final snow light pass reduced that
response to two signals: a soft normal and a low-weight track tone.  Inside a
tree shadow `ATTENUATION` drives both cavity walls to the same shade band, so the
normal cue disappears; the remaining tone is a uniformly pale stain.

The immediate fix keeps the existing normal-relief architecture and adds the
missing cavity response to `snow_ground.gdshader`:

- a pressed-centre shade tone that survives cast shadow;
- amplified directional separation between the two cavity walls, including a
  bounded shade-family response when cast shadow removes the lit band;
- a restrained snow-lip release toward untouched surface snow;
- a deeper pressed-interior track tone, using only existing palette colours.

Only the dynamic TrackMask produces these cavity/lip terms.  Baked roads and
furrows retain their existing tone and normal response and are not turned into
pits.  The centre dynamic/static samples were moved from `light()` to
`fragment()` rather than duplicated; the broad normal is also passed from the
already-computed fragment result.  The fix therefore adds zero texture fetches,
zero draw calls and no new resource upload.

This is perceptual relief shading, not mesh displacement.  The 29 cm boot is
smaller than the terrain's 44 cm quads; true geometric deformation in the
current mesh would recreate the radiating shards previously measured.  A local
high-density interaction patch remains the honest future route if the approved
relief result is still insufficient, but it is not justified before this
zero-fetch fix receives visual acceptance.

## Ranked hypotheses

1. **Confirmed:** final shading had no independent floor/wall/lip
   response. Prediction: under cast shadow the valid normal depression collapses
   to one shade colour, leaving only the 0.5 track tint.
2. **Contributing:** pale-day's soft cel threshold maps the weakest normal slopes
   into nearly the same band. Prediction: increasing directional detail around
   the broad-surface Lambert term separates opposite walls without changing
   untouched ground.
3. **Amplifier, not root cause:** exposure/fog compresses already-small contrast.
   Changing it would affect the whole scene and merely mask the missing local
   response.
4. **Rejected:** veneer/TrackMask data did not reach rendering. The regression
   constructs the real weakest production stamp and measures non-zero raster,
   centre and wall values before evaluating the final palette light output.

## Regression seam and acceptance

`test_footprint_final_shading.gd` constructs the weakest production thin boot
through the real `TrackMask.stamp_profiled()` path.  It then evaluates the
shipping height, normal, pale-day cel band and palette output over the full boot,
including a tree-shadow (`ATTENUATION = 0`) case.  It asserts the downstream
picture rather than mask millimetres:

- tree-shadow cavity-floor contrast at least `0.045` luminance;
- lip-to-floor separation at least `0.032`;
- opposing wall separation at least `0.055`;
- opposing shade-wall separation at least `0.025` under zero attenuation;
- at least eight direct and eight tree-shadow samples respond to a 180-degree
  light reversal;
- disabling the tree-shadow wall term removes that directional response and
  therefore makes the acceptance assertion red;
- untouched shaded snow is invariant;
- no footprint/terrain texture read is introduced inside `light()`;
- cavity relief is dynamic-only, leaving baked roads/furrows unchanged.

## TDD evidence

Focused command (temporary runner removed after GREEN):

```text
D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path "D:/Godot resource/winter-time" --script res://tools/_focused_footprint_final_shading.gd
```

RED, before the shader fix (`1.0 s`, exit `1`):

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

FAIL assert_true failed. tree-shadow cavity contrast is 0.0060; the print is still a flat pale stain
FAIL assert_true failed. the displaced-snow lip separates from the cavity by only 0.0051
FAIL assert_true failed. pale-day opposing walls separate by only 0.0098
FAIL assert_true failed. snow_ground no longer derives a cavity core from the sampled footprint
FAIL assert_true failed. snow_ground no longer separates the two directional cavity walls
FAIL assert_true failed. snow_ground no longer darkens the cavity in tree shadow
FAIL assert_true failed. snow_ground no longer gives the pressed interior its palette depth
FAIL assert_true failed. snow_ground no longer releases the snow lip back toward surface snow
[godot_ai game_helper] registered mcp capture (debugger active=false, logger=true)
```

The first review mutation caught a false mechanism claim: subtracting cavity
occlusion after `ATTENUATION` was already zero could not change the clamped cel
input.  Replacing it with shade-family wall separation made the corrected
mutation guard red as intended before the final GREEN:

```text
FAIL assert_true failed. disabling shadow-wall relief still leaves 0.0505 separation; regression is not red-capable
```

That first guard measured generic tonal spread rather than direction, so it was
replaced with a 180-degree shadow-light reversal. With the new term disabled,
the maximum reversal delta is zero; with it enabled, at least eight wall samples
cross the accepted difference. This directly proves the new term owns the
tree-shadow directionality rather than crediting the darker floor tone.

GREEN, after the corrected zero-fetch shade-wall fix (`0.9 s`, exit `0`):

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

PASS footprint final shading
[godot_ai game_helper] registered mcp capture (debugger active=false, logger=true)
```

No D3D12 scene, GPU capture, full suite or long performance run was started.
The focused runner synchronously loaded the shipping shader and completed in one
second.  The `godot_ai` registration line appears identically on RED and GREEN;
there was no warning, error, shader error, parse error or leak output.

## Files changed

- `src/rendering/snow_ground.gdshader`
- `tests/unit/test_footprint_final_shading.gd`
- `Docs/reports/2026-08-13-footprint-final-shading-depth.md`

## Self-review and concerns

- All colour endpoints remain the existing `snow_lit`, `snow_shade`,
  `track_lit` and `track_shade` palette uploads; no colour literal was added.
- No player, SnowField, TrackMask upload, baked-road or deep-furrow behaviour was
  changed.
- Shader compilation/resource loading was exercised headlessly, but owner visual
  acceptance is still required because the hardware-safety instruction forbids
  a rendered D3D12 capture in this task.
- The result creates cavity depth in lighting but does not change the
  silhouette or generate geometric self-occlusion.  If a future close camera
  requires those, use a tightly bounded high-density interaction patch rather
  than displacing the current coarse terrain mesh.
