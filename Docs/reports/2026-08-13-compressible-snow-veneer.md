# Compressible mature-snow veneer

The opening valley now separates two snow facts:

- `structural_depth_at()` is the existing mature plus dynamic snow column after
  packing. It alone drives wading, route safety, furrows and mobility.
- `visible_depth_at()` is the drawn surface column. On unpacked ground it has an
  authored 8 cm minimum, enough material for a readable boot cavity. The same
  packed/building mask removes it, so interiors and fully beaten paths remain
  clear instead of receiving a cosmetic white layer.

The profile also authors an 8 cm full-imprint threshold, a 35 mm maximum boot
depression, a 20 mm residual bed and the 160 mm TrackMask response scale. The
player converts the allowed depression from metres into mask strength and emits
the structural depth, visible depth, imprint factor and allowed depression in
the footprint payload. This keeps the event truthful while adding no texture
fetch, draw call, per-frame scan or coordinate special case.

The CPU surface and ground shader apply the same `max(structural column,
minimum cover) * unpacked` formula. Dynamic snow's existing sparse simulation
and persistence representation are unchanged; the veneer derives from the
profile and packed raster, so it is deterministic across run seed, recenter and
save replay without another stored layer.

## Future local thaw/suppression seam

A fire heat field must suppress the minimum veneer before the final `max()`;
it must not subtract from the rendered result afterward. The future query is
therefore `minimum_cover * (1 - local_thaw)` before packing, with the same scalar
available to CPU and shader. Until an authored heat-field system exists, thaw is
implicitly zero everywhere. No current fire, tire swing or landmark coordinate
is special-cased.
