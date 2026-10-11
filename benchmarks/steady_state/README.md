# Retained-frame allocation acceptance

The fixture in `ui/steady_state_allocation_embedder_test.v` opens a hidden
macOS Metal window with 300 labels, a counter signal and a button with a hover
style. It runs both a flat tree and a tree whose static labels share a retained
`View` subtree. It measures the actual input and `on_frame` paths, including retained
layout, clipping, text and GPU submission. Both alternating counter values and
hover positions are warmed before sampling. The measurement loop creates no
strings or arrays, and reporting occurs outside it.

Run with the pinned compiler and GC enabled:

```sh
V_MACOS_V3_NO_FALLBACK=1 make bench-allocations V=/path/to/v
# Default: 120 callbacks/frames per phase. Override for a longer run:
UI2_ALLOCATION_FRAMES=1000 V_MACOS_V3_NO_FALLBACK=1 make bench-allocations V=/path/to/v
```

The output includes mount allocations, bytes per idle callback, bytes per hover
frame, bytes per retained counter tick, GC collections and time per phase.
Idle must submit no draws. Hover must draw every frame without rebuilding. Each
tick patches the retained compiled node without running the builder. All 302
controls are painted and stay mounted.

Acceptance after warmup requires zero Boehm allocation bytes and zero collections
for idle and hover. A grouped counter tick may allocate at most 128 KiB; a flat
tick may allocate at most 6 MiB, including immutable copies of the changed
ancestor's direct child arrays. Both total and peak per-tick allocations are
bounded, and collections are bounded over the sampled run. Strings and effects
changed by an action may allocate. Boehm's cumulative byte counter
counts allocation traffic rather than current heap size, so reclaimed garbage
cannot hide a regression. These counters cover managed allocations, not libc,
the platform text libraries or the graphics driver.

The target adds `-d no_gc_thread_local_alloc` to retain the threaded collector
while disabling its small-object allocation batching. Without this flag Boehm
counts thread-local free-list refills, which can hide individual small
allocations between samples. This affects measurement precision, not UI logic.

For a before/after comparison of an older revision, copy the measurement files
into that revision and set `UI2_ALLOCATION_BASELINE=1` while running the same
fixture. This reports the same workloads while omitting allocation acceptance.
Run ordinary tests without that variable to enforce the budget.

The same fixture on a macOS Metal host produced the following 120-frame samples.
The baseline is revision `7857c36`; both revisions use compiler `4c58652`,
Boehm enabled and precise sampling with its source-built collector:

| Workload | Flat before, bytes/frame | Flat after | Grouped before, bytes/frame | Grouped after |
| --- | ---: | ---: | ---: | ---: |
| Idle | 0 | 0 | 0 | 0 |
| Hover | 10,608,077 | 0 | 10,697,022 | 0 |
| Counter tick | 17,632,810 | 3,919,568 | 13,471,154 | 78,048 |

Hover collections fell from 12 / 8 to 0 / 0 for the flat / grouped trees. Tick
collections fell from 14 / 10 to 6 / 1. The optimized peak tick allocations
were 3,919,568 bytes flat and 78,048 bytes grouped. The grouped bound covers
the changed node and immutable copies of its small direct ancestor arrays;
the static subtree remains retained.

The 1,000-frame acceptance run also passed: idle and hover remained at zero
bytes and zero collections, and tick means and peaks stayed at 3,919,568 bytes
flat and 78,048 bytes grouped. Tick collections were 30 / 1. CI runs this longer
fixture to cover bookkeeping growth that a short sample could miss.

Mount allocated 48.6 / 54.5 MB before and 39.8 / 40.0 MB after for the flat /
grouped trees. The calculator's first-build and warm-build comparison is in
[`../vml_build/README.md`](../vml_build/README.md).
Mount and timing results depend on platform caches; acceptance targets warmed
allocation scopes rather than machine-specific elapsed-time thresholds.
