# Performance audit and visual-quality plan

## Executive result

The original distance-triggered freeze has been fixed: seeded SnowField
recentres no longer generate a 512 x 512 mature-snow image through a GDScript
pixel loop. In a real D3D12 132 m traversal, the old one-to-one-and-a-half
second pauses no longer occur.

The highest remaining gameplay risks are CPU and host-to-GPU snow state
updates, not the sky, fog, terrain density, or directional-shadow look. They
must be corrected before adding further ground-detail density. Findings marked
"confirmed" were inspected in the current source; findings marked "high-risk"
need the specified movement capture before a visual-system rewrite.

## Measurement baseline

| Scenario | Result | Interpretation |
| --- | --- | --- |
| Seeded SnowField before the recentre repair | 16 pauses across 132 m, each about 1.34--1.44 s | Resolved historical defect; a GDScript 512 x 512 raster rebuild ran every roughly 8 m. |
| Seeded SnowField after the repair, D3D12 on RTX 5090 | 220 samples / 132 m; 6.530 ms average, 35.093 ms worst, no frame at or above 50 ms | The severe movement freeze is gone in this controlled run. |
| Current SnowField recentre | 30.207 ms maximum in the render-audit run | A residual watch item. It must remain covered by the existing less-than-25-ms target rather than being mistaken for the old freeze. |
| TrackMask | No direct timing counter yet | The controlled traversal moved positions directly and did not create continuous deep-snow furrows, so it cannot clear the TrackMask path. |

## Ranked findings

### P1 high-risk -- TrackMask full-image traffic on movement

`src/systems/track_mask.gd` owns a 2048 x 2048 R8 dynamic mask: 4 MiB. A
three-metre recentre duplicates, clears, and blits that whole image, then the
dirty flush uploads the whole image. A deep-snow furrow can mark it dirty at
roughly each 0.06 m of movement, up to about 60 times per second. The
theoretical worst case is consequently 240 MiB/s from CPU to GPU before
counting the full-image copy.

This is a high-risk path rather than a timing-confirmed active hitch: the
controlled traversal moved positions directly and did not create continuous
deep-snow furrows. It is the first path to instrument during real deep-snow
walking. The current image API requires a full-size update, so a pretend
partial update would not solve it.

**Required remediation:** replace the moving monolithic image with a world
anchored 4 x 4 `Texture2DArray` of 512 x 512 R8 layers. Each layer represents
22.5 m and retains the current 4.394 cm per texel. Stamp and upload only the
affected 256 KiB layer; recycle a layer only when it leaves the 4 x 4 window.
The shader selects a layer from world XZ, with a one-texel overlap at edges.
This preserves every footprint, furrow, resolution, and decay rule while
reducing a one-layer upload by sixteen times.

### P0 confirmed -- Sparse-dynamic-snow cap eviction

`SnowDynamicDepthLayer.trim_to_limit()` currently finds the oldest record by
scanning every sparse tile once for every eviction. The 3.75 m tile field has
about 1,024 active tiles. Once the 2,048-tile cap has been reached, a recentre
can introduce 64--96 records and cause about 131,000--197,000 GDScript
dictionary iterations in one 0.5-second simulation tick.

This is bounded in memory but not in time and may recreate a movement-linked
hitch later in a long run. Replace the repeated scan with an age queue,
spatial/age buckets, or min-heap, and set a per-tick eviction budget. Add a
regression that crosses the cap while moving and asserts a fixed work budget.

### P1 -- SnowField recentre residual

The repaired SnowField uses native noise-image generation and only regenerates
the newly exposed strip; it must not regress to per-pixel GDScript. The
30.207-ms maximum is above the project gate but is no longer a visible
multi-second freeze. If it remains over target after the P0 changes, prewarm
the next movement-direction strip within frame budget; do not enlarge the
recentre slack or remove run-seeded variation.

### P0 confirmed -- Snow-cover broadcast

`TerrainRenderer._process()` calls snow-cover propagation every frame.
`CelPainter.set_snow_cover()` creates fresh arrays, walks every registered
material and snow-mass mesh, and writes a uniform/blend shape even when cover
is unchanged. Snow cover changes slowly enough that a 1/255 shader-visible
bucket is visually lossless; at the maximum observed slew this advances no
more frequently than about once every 4.88 seconds. Cache that bucket and
assert that no material or snow-mass write occurs while it is unchanged.

### P2 -- Change-driven material, visibility, and particle work

* The terrain renderer also repeats texture, origin, and profile parameter
  writes every frame. Cache invariant groups; retain only live lighting values
  during a lighting crossfade.
* `Spindrift` rebuilds and uploads a 4096-pixel point texture every 0.25
  seconds even without wind. Skip that bake while visually inactive, and bake
  once at the threshold crossing. Preserve the active storm particle budget.
* `OccluderFader` can allocate and submit up to eight Jolt ray queries each
  rendered frame. Sample when camera/subject movement requires it or at
  15--20 Hz, retaining tweened fades between samples.
* Snowfall layers and chimney smoke repeatedly submit unchanged particle
  parameters. Send them only when wind, intensity, camera framing, or fire
  state changes.
* WindSway and WindPendulum update all members each frame. Cache membership,
  cull by visibility/distance, or update at a fixed visual cadence with
  interpolation.

### P2 -- State lifetime

`CrowCalls` creates AudioStreamPlayer3D voices on overlapping calls with no
concurrency ceiling, retaining the historical pool peak. Add a
data-authored cap and voice-stealing policy plus a soak test. WindPendulum
retains per-instance state after a member departs; prune or unregister it
before procedural prop populations grow.

### P3 -- GPU quality options require visual review, not blind cuts

The scene uses an 8192 directional shadow map with four cascades and a
high-density terrain plane. Those are legitimate GPU cost candidates, but
they carry the game's atmosphere. Do not lower shadow resolution, cascade
count, fog, wind snow, or terrain detail to hide a CPU upload problem.

Instead, capture fixed daytime, night, whiteout, and tree-shadow shots on the
target hardware at the present setting and a candidate quality setting. Only
ship a quality tier whose image comparison is art-approved. If terrain later
proves GPU-bound, use a near high-density / far low-density clipmap rather
than reducing the player-facing snow surface first.

## Acceptance gates

1. On the target D3D12 hardware, perform 60 seconds each of still, shallow
   snow, deep-snow straight, and deep-snow diagonal movement. Record CPU and
   GPU p50, p95, and p99 separately.
2. No gameplay frame may reach 50 ms; target p99 is at most 16.7 ms for the
   chosen performance tier.
3. TrackMask reports `last_shift_ms`, `last_upload_ms`,
   `uploaded_bytes`, and `flush_count`. In deep snow, a dynamic upload is
   at most 256 KiB and never a 4 MiB whole-window upload.
4. Dynamic snow cap eviction has an explicit fixed-work budget, proved after
   travelling beyond the tile cap.
5. SnowField retains a less-than-25-ms recentre gate and a 100 m seeded
   traversal gate.
6. A 100 m zig-zag across TrackMask layers produces no seam, discontinuity,
   drift, or altered decay in screenshots or sampled track values.
7. Every shadow/fog/particle quality tier is accepted through fixed-camera
   capture review before it can be a default.

## Immediate delivery state

The pending F3 performance overlay is hidden by default, samples at a low
cadence, and shows frame/FPS statistics, renderer counters, memory, dynamic
snow tiles, and SnowField recentre cost. Shift+F3 retains the previous
deep-night lighting preview, so the two diagnostics do not conflict.

## Delivery sequence

1. Ship the F3 instrument panel and collect a baseline capture on target
   hardware.
2. Cache the snow-cover broadcast and replace dynamic-snow repeated scans with
   bounded eviction.
3. Instrument TrackMask during true deep-snow movement, then implement and
   test the Texture2DArray conversion if its byte/timing gate confirms risk.
4. Cache unchanged terrain/material/particle submissions.
5. Run the gates above, then make any art-approved GPU quality tier explicit.
