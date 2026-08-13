# Snow interaction VFX — second pass

## Runtime audit

The current player runtime emits planted-foot and deep-wade furrow events, but
does not contain a knockdown, fall-impact or body-contact state.  Animation/model
material exists for later use; it is not a gameplay producer.  This pass therefore
does not invent a fall mechanic.  It ships the `snow.interaction` consumer contract
for `body_press` and `impact`, verified with composite synthetic contacts.  A future
fall state closes the loop by publishing that event through EventBus.

## Root causes and correction

- Thin snow was authored as a different “scrape”: +70% length, -18% width, a
  0.03 core and 0.9 breakup.  At the gameplay camera this necessarily became a
  dragged smear.  The winter-boot profile now keeps a 1.03 length scale, 0.96
  width scale, 0.58 core, 0.16 breakup and 0.78 sole definition in a dusting.
  Anonymous legacy profiles retain their old semantics.
- The deep-wade furrow was a perfect 34 cm-wide, 0.72-depth centre channel at
  every physics segment.  Its definition now scales width to 76%, depth to 72%,
  varies continuity down to 48%, and applies a restrained world-stable 1.2 cm
  lateral meander.  Boot pockets remain dominant because all marks still max-
  composite in the same R8 mask.
- Body compression is a collection of contact primitives (for example torso,
  forearm, lower leg), not one body-sized ellipse.  Strength derives from snow
  depth and impulse distributed over total contact area, with a per-definition
  ceiling.  Larger contact area under equal impulse therefore produces a
  shallower mark.

## Architecture and performance boundary

Five authored definitions ship under `data/snow_interactions/`: `footprint`,
`furrow`, `body_press`, `impact`, and `drag`.  `StringName type + Resource`
selects one of four generic raster primitives.  The compatibility listeners for
`track.footprint` and `player.furrow` remain while producers migrate.

The implementation keeps the existing 2048² R8 canonical mask and 4×4 sparse
`Texture2DArray` transport.  It creates no mark Nodes/Decals, adds no texture
fetch and no persistent draw call.  A synthetic body event touching one chunk
is pinned by test to one 514² R8 layer: 264,196 bytes.

## Evidence and deferred gates

- TDD RED: 8 expected failures — seven missing unified-interaction contracts and
  one thin boot stretched to 132% of the deep print while narrowing to 53%.
- Focused CPU-only headless suite: **53 passed, 0 failed**, 1.3 seconds.
- `--check-only`: TrackMask, focused tests and runner clean.
- The first post-implementation full wrapper reached **2080 passed, 2 failed**;
  both failures were obsolete assertions that explicitly required the rejected
  scrape and untuned legacy furrow.  They were migrated, then confirmed in the
  focused green run.

D3D12 captures and fresh p50/p95/p99 probes were deliberately not rerun after
the reported GPU thermal/full-load stability incident and the instruction to
avoid excessive performance testing.  Visual acceptance remains deferred; use
the existing user screenshots and the mask-shape assertions for this delivery,
then obtain a user-authorised very short fixed-camera capture in a cool session.

## Thin-snow cadence correction

The second user screenshot showed that the first correction still read as a
lengthwise skate mark. Static inspection found two independent contributors:

- the profile still lengthened a dust print to `1.03`, while keeping `0.16`
  world-space breakup and the full thin-print edge irregularity;
- the running Godot editor process predates commit `d66fbcc`, so a game already
  running from that editor can retain the older script/resource instances until
  the play session is stopped and started again.

The winter-boot resource now owns a compact thin-snow response: length `0.80`,
width `1.08`, core `0.72`, breakup `0.03`, sole definition `0.92`, and thin edge
irregularity scale `0.20`. Deep, body-contact and furrow values are unchanged.
The mask applies that irregularity scale only as `scuff` approaches one, so deep
walls keep their approved torn silhouette.

The conservative no-bridge contract removes the real left/right offset and uses
the widest shipped scale jitter:

`gap = 0.72 - 2 * (0.28 * 0.74 * 1.08) * 0.80 * (1 + 0.34 * 0.20)`

This yields **0.338 m of guaranteed untouched snow** between consecutive print
extents. The real alternating lateral positions increase centre distance from
`0.720 m` to `sqrt(0.72^2 + 0.38^2) = 0.814 m`, so this is the worst case even
under heading jitter. A focused CPU-only RED/GREEN test pins a minimum `0.30 m`
gap, breakup at most `0.06`, and dust sole definition at least `0.90`.

No D3D12 process, GUI run, capture, full wrapper or performance probe was started
for this correction. The focused CPU-only suite completed in 1.3 seconds with
**54 passed, 0 failed**. Visual acceptance remains deliberately deferred; first
stop the currently running play session and start it again so the new resource is
actually loaded, then judge a newly walked, non-retraced line (old persistent
marks and turn-overlap are expected to remain in the mask).
