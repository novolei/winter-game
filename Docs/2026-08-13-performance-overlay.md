# Performance overlay

`F3` toggles a developer-only performance slate in the upper-right corner. It
is hidden by default and samples only while visible, so it cannot compete with
the normal poetic UI or add monitoring work to a player who has not asked for
it. `Shift+F3` remains the lighting director's deep-night preview.

The slate updates its text at 4 Hz and retains a fixed 240-visible-frame window
for the worst frame duration. It reports FPS, current and worst frame time,
process and physics time, draw calls, primitives, objects, RAM, renderer-reported
VRAM, sparse dynamic-snow tile count, and the latest SnowField recenter cost.

The GPU and VRAM monitors are renderer-dependent. A zero or unavailable reading
is displayed as `n/a`, not converted into a guessed value. Snow diagnostics are
resolved through `ServiceRegistry`, so the overlay has no scene-path dependency
on the snow system.

For a movement stall, open the overlay before walking through the affected area
and record the current frame time, `worst/240f`, CPU timings, draw calls, dynamic
tile count and `recenter`. A rising recenter number isolates sliding-window work;
stable recenter with rising CPU/GPU timings points elsewhere. The overlay is an
instrument, not an automatic quality scaler: it never changes rendering,
weather, effects or gameplay to make the numbers look better.
