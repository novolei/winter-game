# Snow-shadow slate-blue A/B capture report

**Status:** review experiment complete; **no shipping palette, data, shader, or lighting setting changed.**

## Question and boundary

The shadow-colour proposal identified the current snow-shadow entry as a likely
source of the “blue sticker” impression in supplied gameplay. This job tests
two restrained slate-blue candidates in the real game instead of recolouring a
reference image or adjusting sun, fog, shadow bias, filtering, or exposure.

The experiment deliberately does **not** choose a shipping colour. A permanent
change remains a ColorBible/generator review, because changing a palette entry
recolours ground, settled snow, and snow-bearing props globally.

## Reproducible route

`tools/capture_shadow_palette_ab.tscn` inherits the existing real-game capture
harness. At the shutter it creates an unsaved, complete 12-colour `ColorBible`,
replacing only snow tones 4 and 5 in memory, and retints the live
`snow_ground`/`cel_flat` materials. It changes 21 live materials in the current
opening scene, then discards all changes on process exit.

`tools/measure_shadow_palette_ab.gd` measures matched 1600x1000 output. It
samples a stable clear-snow rectangle `(850,300,200,60)` and the adjacent broad
farmhouse cast-shadow rectangle `(900,430,200,70)`. Both exclude the traveller,
architecture, particles, and the band edge.

```powershell
$out = 'C:/Users/aresr/AppData/Local/Temp/winter-time-shadow-palette-ab'
foreach ($candidate in @('control', 'slate_a', 'slate_b')) {
    foreach ($preset in @('pale_day', 'sunrise', 'nightfall', 'deep_night', 'whiteout')) {
        & 'D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe' `
            --path 'D:/Godot resource/winter-time' --fixed-fps 60 `
            'res://tools/capture_shadow_palette_ab.tscn' --resolution 1600x1000 -- `
            --out "$out/${candidate}_${preset}.png" --seconds 1.0 --settle 0.3 `
            --preset $preset --shadow-candidate $candidate
    }
}
& 'D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe' --headless `
    --path 'D:/Godot resource/winter-time' --script `
    res://tools/measure_shadow_palette_ab.gd -- --dir $out
```

The 15 review PNGs are local evidence, intentionally not checked into Git:
`C:/Users/aresr/AppData/Local/Temp/winter-time-shadow-palette-ab/`.

## Candidate palettes

| Candidate | Snow shadow (tone 4) | Track shadow (tone 5) | Intent |
|---|---:|---:|---|
| Control | `#6987B4` | `#5D7BA6` | Shipping palette |
| Slate A — Quiet slate | `#708099` | `#60708A` | Most muted / most sombre |
| Slate B — Lifted slate | `#76889F` | `#667890` | Muted, with more daylight separation |

All variants are complete 12-colour in-memory ColorBibles. They are palette
entries selected outright by the cel shaders, never colour multipliers.

## PALE DAY gate measurement

Encoded luminance uses `0.2126R + 0.7152G + 0.0722B`; chroma is the encoded
max-channel minus min-channel range. The approved proposal gate is shadow/lit
chroma `<= 1.5` and shadow/lit luminance `0.78..0.88`.

| Candidate | Lit sample | Shadow sample | Chroma ratio | Luminance ratio | Gate |
|---|---:|---:|---:|---:|---|
| Control | `#A6CBF9` | `#84A7D9` | 1.024 | 0.822 | Pass |
| Slate A | `#A6CBF9` | `#8AA1C2` | 0.675 | 0.799 | Pass |
| Slate B | `#A6CBF9` | `#8FA8C7` | 0.675 | 0.830 | Pass |

The prior user-supplied frame measured as a substantially more chromatic shadow
than this controlled capture. It came without preset, display transform, or
save-state metadata, so its absolute pixels cannot responsibly override the
matched D3D12 experiment. It remains valid qualitative evidence that the
shipping blue feels too independent. Both candidates materially reduce that
independence while preserving the same camera, shadow geometry, and hard cel
edge.

## Full lighting-ladder result

| Candidate | SUNRISE shadow | NIGHTFALL shadow / lit ratio | DEEP NIGHT shadow / lit ratio | WHITEOUT |
|---|---:|---:|---:|---|
| Control | `#7795C1` | `#526B91` / 0.800 | `#3C4F6B` / 0.784 | No cast silhouette |
| Slate A | `#7D90AB` | `#57667F` / 0.768 | `#404A5C` / 0.752 | No cast silhouette |
| Slate B | `#8196B0` | `#5B6C83` / 0.812 | `#434F5F` / 0.796 | No cast silhouette |

- SUNRISE keeps its data-authored warm direct-light beat; the tool only changes
  the shadow band. Both candidates leave direct-lit pixels untouched and keep a
  cooler shadow.
- Both NIGHTFALL and DEEP NIGHT still descend in brightness. Slate A is
  noticeably denser at DEEP NIGHT, so it has less legibility headroom.
- WHITEOUT has no long directional cast silhouette in all three captures. The
  palette adjustment does not re-enable shadowing; `whiteout.tres` remains
  authored with shadows disabled and its existing lighting test enforces that.
- The temporary edit changes only material uniforms. Sun elevation/azimuth,
  `shadow_normal_bias = 2.0`, cascade quality, filtering, fog, exposure,
  geometry, and the cast-shadow toggle are byte-for-byte untouched. Thus it
  cannot trade hue for floating contacts, short shadows, or soft/noisy edges.

## Decision for the next review

**Both Slate A and Slate B meet the stated A/B gates.** Slate B is the safer
review lead: it removes the conspicuous blue saturation, preserves the PALE DAY
contrast margin at 0.830, and holds more separation in the two dark looks.
Slate A remains a valid deliberately austere reference, but its DEEP NIGHT
sample is darker than the proposal's daylight comfort band and should not become
the default by assumption.

Neither is approved for shipping without art-direction review of the matched
captures and a human play pass. If one is selected, update
`tools/generate_palette.gd`, regenerate `color_bible.tres`, and run every art
gate in one isolated implementation job; do not hand-edit a `.tres` or tune
lighting controls around it.

## Validation and concerns

- `--check-only` passed for the new capture and measurement tools and the
  candidate unit test.
- All 15 real captures completed successfully on Godot 4.7.1 / D3D12 / Forward+
  with the Godot AI capture helper registered. The measurement tool exited 0;
  all three PALE DAY rows passed.
- An early concurrent wrapper attempt reported `1968 passed, 1 failed`: an
  unrelated palette fixture could not create/load `user://` files while other
  jobs were active, and the wrapper correctly rejected its console `ERROR:`
  lines. It was not treated as green.
- After the concurrent fixture writes had stopped, the required wrapper passed
  cleanly: `bash tools/run_tests.sh` → **`1970 passed, 0 failed`**, exit 0, with
  no console warning/error/parse/leak output.
