# Farmhouse window lighting — final art and implementation report

Date: 2026-08-14

## Art intent

The farmhouse is the valley's warm visual promise: the panes must remain clear
and architectural, while the light outside them becomes soft, atmospheric and
painterly. The final hierarchy is deliberately asymmetrical:

- the upper window is the hero light and casts a shaped reflection onto the
  snow-covered porch roof;
- the lower window is a quieter domestic light and opens into a much broader,
  lower-density reflection across the snow;
- the two windows never become equal orange signs: dark muntins preserve the
  complete window silhouette, and the outside scattering is softer and less
  saturated than the pane core.

## Shipped visual stack

`FarmhouseWindowLight` builds four complementary layers per authored window:

1. an isolated HDR emissive pane, graded independently for the upper and lower
   storeys;
2. a broad, feathered wall halo;
3. a very low-density air shaft that visually connects pane and receiving
   surface;
4. a projected snow reflection. The upper reflection is a restrained porch-roof
   trapezoid; the lower reflection is a `4.80 m × 5.40 m` soft area with a long
   near-to-far falloff and zero-alpha projector boundary.

The pane shader adds one vertical and two horizontal dark muntins. Its centre is
brighter than its edge, but the grid remains legible, so the result reads as a
lit room behind a complete window instead of a flat orange texture.

A conventional warm `SpotLight3D` is not the main snow-light solution. The
project's cel world and snow shaders intentionally quantise local-light
attenuation without using `LIGHT_COLOR`; a spot light would therefore create a
brighter cold disc rather than a warm diffuse reflection. The soft projected
Decals provide the authored warm receiver colour, while their masks create the
wide area-light silhouette requested by the reference.

## Runtime adaptation

The effect consumes the already published continuous lighting state instead of
subscribing directly to clock or weather events:

```text
LightingDirector.warm_accent_energy()
    × Stove.light_energy_now() / authored fire energy
    × (1 - InteriorReveal.fade())
    × farmhouse geometry visibility
```

Pane energy follows that master continuously. Halo, shaft and snow reflection
use a steeper response so they retreat faster in bright daytime while the panes
retain a small readable indoor warmth. The stove's final fuel fade is preserved;
when the fire is out, every pane and exterior-light layer reaches zero. The
geometry visibility term also prevents detached light from reappearing during
`OccluderFader` silhouette transitions.

The only motion is a slow, approximately 2.6% fire breath. It is intentionally
below flicker strength so the emotional read remains calm and hopeful.

## Fixed-camera review frames

- Deep night: `.superpowers/sdd/window-lighting/final-area-deep-night.png`
- Pale day: `.superpowers/sdd/window-lighting/final-area-pale-day.png`
- Deep night, fire out: `.superpowers/sdd/window-lighting/final-area-deep-night-fire-out.png`

Art review passed all three states: clear pane structure, wide and soft lower
snow reflection, upper/lower hierarchy, daylight restraint, and complete
fire-out extinction.

### Pixel acceptance

The final 1280×800 captures were compared against the identical fire-out frame:

- the lower diffuse-light component covers `15,395 px` (`1.5034%` of the
  frame), with a `182 × 142 px` connected footprint rather than a narrow cone;
- near/mid/far added luminance is `15.00 → 13.73 → 7.57`, while added warm/cool
  margin is `28.97 → 23.66 → 14.53`; the far end therefore resolves at roughly
  half the near strength instead of ending at a hard edge;
- the illuminated snow remains chromatically cold: the lower ground area
  contains zero pixels over the project's warm-pixel threshold;
- in pale day the same ground samples stay within `±2.4%` luminance of their
  control snow, so the exterior scattering retreats into the environment;
- lit-pane to muntin luminance remains `1.42–1.48×` in both states, confirming
  that bloom and haze do not erase the complete window structure;
- effect-only warm share is `0.9663%` at deep night, `0.6209%` in pale day and
  `0.0056%` with the fire out. Warm colour outside the effect changes by only
  `0.0315` percentage points between day and night, showing no global warm cast.

## Verification

- Focused farmhouse-window suite: **11 passed, 0 failed**.
- Both new shaders compile in the project's real shader compilation gate.
- `farmhouse_window_light.gd` and its test pass Godot `--check-only`.
- `git diff --check` is clean.
- The full shared worktree run reached **2351 passed, 5 failed**. All five
  failures are in the concurrently edited `test_perch_snow_shed.gd` /
  snowy-perch scene contract, including two GDScript type-inference parse
  errors. The farmhouse-window tests and shader gate passed in that run; the
  unrelated perch work was preserved rather than modified as part of this
  lighting task.

## Principal files

- `src/rendering/farmhouse_window_light.gd`
- `src/rendering/window_emission.gdshader`
- `src/rendering/window_scatter.gdshader`
- `scenes/effects/farmhouse_window_light.tscn`
- `tools/blender/build_farmhouse.py`
- `tests/unit/test_farmhouse_window_light.gd`
