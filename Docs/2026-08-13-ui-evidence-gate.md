# UI evidence gate (P0)

This is a measurement gate, not a visual redesign. It changes no UI colour,
copy, layout, asset, gameplay, or layer ordering.

## What is now reproducible

`tools/ui_evidence.gd` is the shared image-difference instrument used by the
real-scene capture tools. It compares a frozen world plate with the delivered
render rather than treating an authored token as a visual result. It reports:

- the 10th/90th-percentile core contrast of actually delivered ink;
- the transient element's frame share, clipping, and edge anchor;
- the fraction and duration of key ink altered by a front layer, where that
  layer exists.

Use the real D3D12 scene captures at 1600x1000:

```powershell
& 'D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe' --path 'D:/Godot resource/winter-time' 'res://tools/capture_threshold_note.tscn' --resolution 1600x1000 -- --preset pale_day --seconds 0.2
& 'D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe' --path 'D:/Godot resource/winter-time' 'res://tools/capture_threshold_note.tscn' --resolution 1600x1000 -- --preset deep_night --night --seconds 0.2
& 'D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe' --path 'D:/Godot resource/winter-time' 'res://tools/capture_threshold_note.tscn' --resolution 1600x1000 -- --preset whiteout --seconds 0.2
```

The same plate/difference path is also available in
`tools/capture_time_prompt.tscn`.

Append `--verify` to a capture command to turn those thresholds into its process
exit code. The known deep-night and time-prompt text baselines below intentionally
fail that strict mode until the P2 readability job changes the delivered image.

## Acceptance thresholds

| Measure | Gate | Current role |
| --- | --- | --- |
| Body text core contrast | >= 4.5:1 | P2 readability target; measure now, do not silently claim current deep night meets it. |
| Graphic core contrast | >= 3.0:1 | P2 readability target. |
| Transient Control bounds | <= 1% of frame and fully in-frame | P0 gate. |
| Edge placement | control is anchored in its intended breathing-border band | P0 gate. |
| Front-weather key ink occlusion | <= 10% for no longer than 250 ms | P2b gate after a deliberate compositor/layer decision. |

## Current architectural blocker: front-of-UI snow

The captured scene's `Snowfall` is a 3D world node and `UI` is a `CanvasLayer`.
There is no current UI-front weather layer, compositor pass, or controllable
between-plate overlay. Therefore the project cannot truthfully measure snow
occluding UI ink: in the shipped render order it does not occur. The occlusion
algorithm and its unit tests are ready, but activating that metric requires an
owner decision to introduce a deliberate foreground-weather presentation layer
and to state whether it may temporarily thin around critical text. No such layer
is introduced by P0.

## Baseline captured on 2026-08-13

With the real `capture_threshold_note` path at 1600x1000 (1152x720 canvas):

| Preset | Delivered sentence core contrast |
| --- | --- |
| `pale_day` | 6.31:1 |
| `deep_night` | 2.64:1 |
| `whiteout` | 5.52:1 |

The deep-night result confirms the proposal's P0 finding: it is below the 4.5:1
body-text target. This document records the defect for the later visual job;
P0 does not change colour, font, opacity, particles, or scene layering to mask
it.
