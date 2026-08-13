# TrackMask cross-hardware upload validation

Date: 2026-08-13  
Engine: Godot 4.7.1, Forward+, D3D12  
Reference device: NVIDIA RTX 5090

## Outcome

The dynamic footprint field keeps its original 2048 x 2048 R8 canonical image,
90 m world extent, 4.394 cm texel density, stamping, decay, recentering and
threat-query semantics. Only its CPU-to-GPU transport changed.

The former path uploaded the complete 4 MiB image whenever any footprint or
decay texel changed. In a measured deep-snow walk this produced 300 uploads in
five seconds: 1,200 MiB, or 240 MiB/s. Submission averaged 0.734--0.760 ms and
reached 1.409--1.858 ms on the reference GPU. The time was acceptable on that
device, but the sustained bandwidth and full-resource update were not a safe
contract for integrated and low-end GPUs.

The new path transports a 4 x 4 `Texture2DArray`. Each layer has a 512 x 512
core and a one-texel gutter, for 514 x 514 R8 = 264,196 bytes per ordinary
upload. The gutter duplicates real neighbouring texels and lets the shader use
one hardware-filtered sample. A gutterless design was rejected because it
either clamps at each 22.5 m boundary or multiplies every footprint shader read
into four manual bilinear samples.

## Real-main measurements

`tools/probe_track_mask_chunking.tscn` instantiates the shipping main scene,
renders every frame, stamps a 3.3 m/s deep-snow-equivalent walk for 300 frames,
then runs a rendered 100 m zigzag through repeated recenter boundaries.

Three D3D12 runs produced:

| Measure | Run 1 | Run 2 | Run 3 |
|---|---:|---:|---:|
| Dynamic layers uploaded, 300 frames | 711 | 710 | 710 |
| Bytes uploaded, 300 frames | 187,843,356 | 187,579,160 | 187,579,160 |
| Upload p50 | 0.096 ms | 0.108 ms | 0.104 ms |
| Upload p95 | 0.254 ms | 0.265 ms | 0.258 ms |
| Upload p99 | 0.662 ms | 0.668 ms | 0.598 ms |
| Full-frame p50 | 6.212 ms | 6.230 ms | 6.228 ms |
| Full-frame p95 | 7.051 ms | 7.275 ms | 7.164 ms |
| Full-frame p99 | 7.433 ms | 12.352 ms | 8.578 ms |
| 100 m zigzag frames >= 50 ms | 0 | 0 | 0 |
| 100 m zigzag worst frame | 32.400 ms | 33.218 ms | 35.145 ms |
| 100 m zigzag maximum upload | 1.047 ms | 1.161 ms | 1.186 ms |

The rendered walk sends about 35.8 MiB/s, a 6.7x reduction from the confirmed
240 MiB/s baseline. It is higher than the single-layer theoretical 15.1 MiB/s
because decay can dirty neighbouring layers and a recenter correctly refreshes
all sixteen layers.

A separate unpaced 300-update script records occasional 5--7 ms driver queue
stalls. It intentionally submits hundreds of updates without rendered frames
between them and is not a gameplay model. The paced real-main probe above is
the shipping evidence and keeps upload p99 below 0.7 ms across all three runs.

## Continuity and quality gates

- The CPU canonical image remains unchanged, so footprint shape, furrows,
  subtractive fill, four-neighbour slump, threat reads and world anchoring use
  exactly the established implementation.
- Dirty rectangles expand by one texel before layer selection. A texel changed
  on one side of a transport boundary therefore updates the neighbour whose
  gutter observes it.
- Unit coverage pins ordinary one-layer uploads, four-layer corner uploads,
  matching horizontal/vertical/corner gutter texels and a 100 m CPU zigzag.
- The shader selects one array layer and uses the gutter for the same bilinear
  interpolation as the former monolithic texture. It compiled and rendered in
  the real D3D12 main scene without console output.
- F3 now shows the most recent TrackMask layer count, transfer size and upload
  duration alongside frame and SnowField metrics.

## Remaining cross-hardware gate

The architecture removes the known bandwidth hazard, but one high-end GPU
cannot certify every low-end driver. Before declaring a minimum specification,
run the same committed probe on the minimum target or a representative cloud/
borrowed device. The acceptance boundary is:

- no 100 m zigzag frame at or above 50 ms;
- TrackMask upload p99 below 2.0 ms and maximum below 5.0 ms;
- no visible 22.5 m grid seam while a print crosses a horizontal, vertical or
  four-layer corner boundary;
- unchanged 4.394 cm texel density and no footprint-resolution quality tier.

If a particular driver fails this gate, the next response is staging or
double-buffering array updates. Reducing footprint resolution is not an
accepted fallback.
