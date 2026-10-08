# Incremental layout

Every window owns a retained `LayoutTree`. Flex, Grid, Stack and Absolute retain
both their layout rules and authored child sizes. `Element.frame` is the resolved
parent-local frame; `Element.layout_input` retains the authored frame. Positive
authored dimensions are preferred explicit sizes; zero requests intrinsic sizing.
`LayoutConstraints` distinguishes a tight zero from an unbounded maximum (`-1`).
Geometry stays fractional in logical units until backend presentation.

## Updating a subtree

```v
ui2.refresh_element('description', ui2.label('description', new_text,
    ui2.Rect{}, ui2.TextStyle{ lines: 20 }))
```

This replaces a mounted declaration without calling the screen builder. Its id
must remain `description`; duplicate ids anywhere in the tree and duplicate
sibling keys are rejected before mutation. Custom rendering queues/coalesces work
for the next frame. Native backends reconcile the resolved tree immediately so
siblings whose frames moved are updated too. Call on the UI thread; custom
workers deliver changes with `UiDispatcher.post`.

Color, fill, border, outline, hover and other paint properties reuse geometry.
Text, metric typography, wrapping width, control insets, layout rules, order,
hiding and declared sizes invalidate affected geometry. Flex measures preferred
bases before redistribution and measures automatic heights again at the assigned
width. Grid spans and Stack stretch use their assigned widths too. Hard Flex
limits may overflow; they are not silently clamped to the parent's available size.

An ancestor with fixed authored width **and** height is a relayout boundary: its
internal children still rearrange, but its preferred exterior size cannot change.
Intrinsic ancestors propagate size invalidation until a boundary. Siblings still
participate in allocation when their parent depends on the changed child. A
boundary's assigned size changing also rearranges its descendants. This is
inferred from actual size dependencies; there is no unsafe force-boundary flag.

Use a fresh constructor when changing authored geometry, or
`element.with_layout_frame(new_frame)` when starting from a resolved Element.
Replacing only `frame` on a resolved Element does not discard its retained input.
The same inputs work with ordinary V builders and `run_compiled_vml` builders;
layout does not depend on interpreter `VNode`s. The pinned compiler's old `$vml`
grammar/lowering migration is the separate compiler roadmap work described in the
README; this feature does not restore removed compiler APIs.

## Identity, caches and environment

Supply an explicit `id`, or a sibling `key`, for stable measurement identity.
Ids are unique in a window; key paths encode separators without ambiguity. Keyed
reordering preserves generations. Removal, reintroduction and kind replacement
retire the old generation. Anonymous children get fresh generations on each full
build, because an array index is not durable identity. The window root has its
own stable identity. No cache identity uses an address or event callback.

Measurement keys cover generation, content version, exact constraints, metric
text styles and rich runs, text/placeholder, declared dimensions, container rules,
control insets and scroll gutter, measurer identity, and `LayoutEnvironment`.
Paint values are excluded. Measurement and child disposition caches are separate.
Each node retains at most 16 constraint results and 16 typography results;
content changes and unmounts retire obsolete entries. Equal ids in different windows never share a cache.

Call `invalidate_layout_environment(LayoutEnvironment{ font_version: revision })`
when fonts/fallbacks change. This retires CPU measurement and active window
shaping caches together. Desktop custom font registration and context revisions
are also included automatically.
`version` describes other metric environment changes;
`scale` describes a measurer's metric environment and must be finite and positive.
It invalidates cache entries, rather than scaling authored logical geometry.
Device DPI and ScaledContent's presentation transform remain separate. Custom
resize requests rebuild responsive declarations and resolve new constraints;
unchanged logical metrics can remain cached across device DPI changes.

Layout uses authored editor text. An unchanged declaration preserves the backend's
local UTF-8 edit buffer, focus, selection, scroll and IME composition. Layout does
not rewrite those states. `set_text` retains its explicit replacement behavior.

For headless layout or an embedder:

```v
mut tree := ui2.LayoutTree{}
tree.replace(root)!
resolved := tree.resolve(ui2.LayoutConstraints{ max_width: 600 },
    ui2.measure_layout_text, ui2.LayoutEnvironment{})!
tree.patch('description', replacement)!
updated := tree.resolve(ui2.LayoutConstraints{ max_width: 600 },
    ui2.measure_layout_text, ui2.LayoutEnvironment{})!
```

The owner is UI-thread confined; a supplied measurer must be side-effect free.
Changing captured measurer state requires an environment version even when its
function pointer is unchanged. `clear()` retires mounted generations; it does not
reuse them. `identity(id)` exposes generation and external content version.

## Inspecting work

`layout_stats()` exposes the current window's cumulative counters. A standalone
owner offers `stats()` and `reset_stats()`. `builds` counts full declaration
replacements; patches do not increment it. `reconciled` counts declarations
diffed, `measure_visits` counts measurement cache misses, and `layout_visits`
counts local arrangements. `text_measurements` counts shared typography measure
requests. `measure_hits`, `text_hits` and `layout_hits` count cache reuse
separately. These counters exclude tree validation, assembling output Elements, painting, shaping performed by the
renderer itself, and native control reconciliation. The desktop custom text
engine separately retains shaping geometry (up to 128 blocks per context), keys font/environment
revisions and exact text constraints, and applies foreground paint without
reshaping, including rich runs and synthetic ellipsis ownership. Link metadata
also reuses shaping; decoration attributes remain shaping dependencies. Native
AppKit measurement consults its actual cell for the required text height.
Cached layout does not imply
zero allocations, partial painting or avoided declarative builds.

Run the maintained example:

```sh
v -d ui2_custom_rendering run examples/incremental_layout
v -d ui2_custom_rendering run examples/incremental_layout --long
v -d ui2_custom_rendering run examples/incremental_layout --measure
```

Omit the custom define for native controls. Type accented text, select it, change
color/text and resize. The editor keeps its local edit, while text changes can
move its frame. `--measure` uses the same 612-unit scene for 20 alternating color
or text updates under three policies: uncached reconstruction, retained full
builds, and targeted patches. It prints actual counts, with normal GC; the
uncached policy is an explicit reconstruction reference, not a measurement of a
different upstream checkout or a wall-clock speed claim.
