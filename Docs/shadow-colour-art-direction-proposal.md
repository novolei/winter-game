# Snow shadow colour — art-direction proposal

**Status:** proposal only — no game, asset, palette, or shader file was changed.
**Question:** the supplied gameplay image makes the blue cast shadows feel artificial. Should they be refined?

## Decision

**Yes. Keep cool shadows, but make the daytime shadow band a quieter slate-blue.**

Cold skylight in snow is correct and is an important part of WinterTime's winter identity. The issue is not that the shadows are blue; it is that, in the supplied frame, the shadow becomes materially *more chromatic* than the snow carrying it. It reads as a separately painted blue shape rather than snow temporarily deprived of direct light. That competes with the traveller's rust scarf, the route, and the long-shadow composition that should be doing the storytelling.

The intended feeling is: the light leaves the snow, the air remains cold. The shadow should read as a **softly muted absence of sun**, not as an additional blue object.

## Evidence

### Supplied image

Samples were taken from uncontaminated adjacent snow and the broad tree/structure shadow, avoiding the character and soft penumbra:

| Sample | Encoded screen colour | Screen luminance | RGB chroma range |
|---|---:|---:|---:|
| Lit snow | `#B9C2D0` | 0.757 | 23 |
| Main blue shadow | `#81A2D2` | 0.621 | 81 |

The shadow is 18% darker, which is a useful readable separation, but its chroma range is **3.5×** the adjacent snow. Its blue-minus-red separation is 81, versus 23 in the lit snow. That is the precise source of the “blue sticker” impression.

### Current implementation

The world is intentionally not coloured by the DirectionalLight or Environment ambient:

- `assets/shaders/snow_ground.gdshader` and `assets/shaders/cel_flat.gdshader` select a palette `shade` colour in `light()` and disable ambient.
- `src/rendering/terrain_renderer.gd` assigns ground snow `snow_tones[0]` as lit and `snow_tones[3]` as shade.
- `src/rendering/cel_painter.gd` uses the same three-step snow descent for snow settling on props.
- The palette generator currently defines that shade as `#6987B4`; the source of the hue is therefore the **palette shadow band**, not sun colour, ambient fill, or a post-process multiply.

A real D3D12/Forward+ run was captured with `tools/capture_frame.tscn`; its `PALE DAY` pair was `#A6CBF9` lit / `#96BCEB` shadow. The exact supplied-image colours do not reproduce from the screenshot alone (no preset, save state, display transform, or capture metadata was provided), so it would be unsafe to tune directly to its absolute hex values. It does, however, confirm the code path and the fixed shadow-band source above.

Six full-preset captures also confirm the intended time-of-day ladder: the shadow stays cool in daylight, becomes slate/navy by NIGHTFALL and DEEP NIGHT, and is deliberately removed in WHITEOUT. The correction must preserve that narrative role.

## Direction for each time of day

| Look | Direction |
|---|---|
| `PALE DAY` / `FLAT` | The priority. Make shadow blue-grey and subordinate to the snow surface; preserve long, clear silhouettes. |
| `SUNRISE` | Keep the shadow cool while the lit band warms. That warm-light/cold-shadow contrast is valuable, but it must remain slate rather than lavender-blue. |
| `NIGHTFALL` / `DEEP NIGHT` | Preserve the stronger slate/navy descent created by exposure and fog. Do not neutralise the whole game into grey; warm beacons must remain the only strong chromatic punctuation. |
| `WHITEOUT` | Keep cast shadows disabled. A blizzard should erase directional form rather than receive a new shadow colour. |

## Recommended implementation sequence

### 1. Palette A/B, first and reversible

Author two temporary palette candidates through `tools/generate_palette.gd`, then regenerate the dependent palette-authored materials/assets before judging them. Do **not** hand-edit `data/palette/color_bible.tres`.

The selected day-shadow entry should retain its cool hue family but reduce blue-red separation from the current source colour's 75 channels to roughly **35–50 channels**. A starting review swatch is a muted blue-grey in the vicinity of `#70809A`, with the darkest snow tone stepped down in the same muted family. This is a review starting point, not an approved shipping value: it must be judged in real captures against the existing palette and dark looks.

Keep the light snow and warm palette entries unchanged in this first pass. The aim is to restore hierarchy, not recolour the entire world.

### 2. Validate the global consequence

This palette route is intentionally global: the ground, accumulated roof snow, and shaded snow-bearing props will agree. It is the smallest trustworthy change, but it also changes every existing material that uses the palette. The importer/material generation step and art gates must be run so no old `#6987B4` material survives outside the new ColorBible.

If the global revision makes DEEP NIGHT insufficiently cold, do **not** restore saturation by multiplying the shader. Instead, evaluate a second, explicitly data-driven enhancement: add a `shadow_band_colour` (or palette index) to `LightingPreset`, generated from `ColorBible` and pushed alongside the existing band threshold. The shaders would still **select** a palette entry; no per-band colour multiply or gradient is permitted. This is a larger design/engineering choice and should only follow the A/B capture review.

## Explicit non-changes

Do not use any of these controls to solve this colour problem:

- `sun_color` or `ambient_color`: they primarily affect the StandardMaterial character, not the cel-shaded world.
- fog density/colour: it alters depth and the whole frame, not the near shadow band; using it here would risk the established aerial-perspective ladder.
- sun elevation/azimuth, shadow bias/normal bias, or shadow resolution: they govern composition and contact, not hue. In particular, retain the measured `21.5°` elevation and `shadow_normal_bias = 2.0`.
- PCF/soft-filter blur or post-process blur: Art Bible §10 requires a clean cel threshold; soft geometric composition is not a blurred shadow map.

## Acceptance criteria

The next implementation job should create a deterministic shadow-swatch capture (fixed camera, caster, snow plane, preset) in addition to gameplay captures. Approve a candidate only when all conditions hold:

1. In `PALE DAY`, a broad shadow remains readable at gameplay camera distance, but its screen chroma is no more than **1.5×** that of immediately adjacent lit snow; the supplied frame's 3.5× relationship fails this criterion.
2. The shadow-to-adjacent-snow luminance ratio is between **0.78 and 0.88** in the swatch capture. This preserves form without turning the shadow into a foreground graphic.
3. `SUNRISE` still reads as warm direct light over cool shadow; `NIGHTFALL` and `DEEP NIGHT` still descend in perceived brightness; `WHITEOUT` still has no cast shadow.
4. Long silhouettes, contact attachment, and hard/clean cel boundaries are unchanged. No adjustment may trade colour for floating, short, or noisy shadows.
5. Regenerated content passes the full clean wrapper: `bash tools/run_tests.sh 1959`, including palette, lighting preset, cel-painter, and cel-band-broadcast gates.
6. Art-direction review uses matched D3D12 captures at the same camera and state, plus one human play pass. A single unlabelled screenshot is evidence of the symptom, not enough evidence to choose a final absolute colour.

## Tooling note

The project registered its Godot AI debug capture helper during each live capture (`[godot_ai game_helper] registered mcp capture`). This agent environment did not expose a callable Godot AI MCP capture tool, so the built-in deterministic `tools/capture_frame.tscn` harness was used instead. The proposed implementation should use the MCP capture route where it is exposed, with the harness retained as the reproducible fallback.

## Audit scope

Read: AGENT briefing; Art Bible §4 and §10; ColorBible; palette and lighting generators; `LightingPreset`, `LightingDirector`, `TerrainRenderer`, `CelPainter`; both exterior cel shaders; related unit/art tests; Wave 2 and Wave 3 lighting reports.
Captured: six real runtime presets on Godot 4.7.1 / D3D12 / Forward+; no project files were modified for the capture.
