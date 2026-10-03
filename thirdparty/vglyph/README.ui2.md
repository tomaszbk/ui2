# VGlyph runtime used by UI2

This directory contains the runtime sources of
[VGlyph](https://github.com/vlang/vglyph), pinned to
[`72377fbe720dbd658ee96c59b49904ba30ebe059`](https://github.com/vlang/vglyph/tree/72377fbe720dbd658ee96c59b49904ba30ebe059)
(`v.mod` version 0.9.0). Examples, assets, upstream tests and planning files are
excluded. Pango, HarfBuzz, FreeType, Fontconfig, FriBidi and their transitive
libraries remain native dependencies; see [UI2 text setup](../../docs/vglyph-text.md).
This is an adapter integration, not a rewrite of those libraries.

Local changes are intentionally narrow:

- Internal accessibility imports use `ui2.thirdparty.vglyph.accessibility`.
- `new_context_with_config` adds opt-in fractional glyph advances and an explicit
  text byte budget. `new_context` retains the upstream default of rounded
  positions and 10,240 bytes. UI2 disables advance rounding and the byte budget;
  UTF-8 and embedded NUL validation remain enforced. `Context.free` is idempotent.
- `Context.fonts_changed` synchronizes existing font maps after application-font
  registration. `Context.set_emoji_families` adds opt-in, per-map emoji preference
  without modifying global Fontconfig rules. Pango's generic emoji selection then
  honors bundled/explicit outline fonts, including ZWJ and variation selectors.
  An empty preference list preserves normal Pango behavior. This uses Pango 1.48's
  font-map substitution API; its callback data is released with the map.
- Baked layouts and face-based cache keys retain unique `PangoFont` references in
  their context, so FreeType faces survive eviction from Pango's bounded fontset
  cache. References are released on font registration/configuration changes,
  emoji-preference changes and context destruction. Returned layouts must be
  reshaped after those changes. Ordinary family lists exclude emoji faces; Pango
  1.50 can otherwise select emoji faces for ASCII digits or blank-line metrics.
- `BlockStyle` adds logical `line_height`, `max_lines`, `ellipsize` and
  `insert_hyphens`. Hyphen insertion retains its upstream default; UI2 disables
  it for compatibility with existing wrapping. These fields participate in the
  layout-cache key. Width `-1`
  is unconstrained and width zero is a real Pango constraint. `Layout.ellipsized`
  reports Pango truncation. Pango 1.50 or newer is required for absolute line
  height; advance rounding requires Pango 1.44. The `max_lines` setting uses
  Pango's paragraph limit for values above one; the UI2 adapter joins a shaped
  prefix with an ellipsized tail to enforce a global line limit across paragraphs.
  One line uses Pango's global height zero.
- `Line.baseline` exposes Pango's baseline for every line, including empty lines.
  With an explicit horizontal line height, ellipsized layouts normalize glyph
  baselines, line boxes and cursor/selection geometry to the same line grid;
  Pango-generated ellipsis runs can otherwise lose the line-height attribute.
- Atlas allocation checks GPU resource state. Growth and page reuse preserve
  queued quads by uploading their old texture before replacement. Deferred images
  are released by their gg cache indices, with their shared sampler kept alive.
  Atlas teardown removes both cache entries and GPU resources, including deferred
  images, and can be called repeatedly. `Renderer.clear_glyph_cache` invalidates
  font-face identities after a map change while preserving queued atlas pixels.
  `Renderer.atlas_images` provides borrowed resource snapshots for embedding tests.
- Native IME callback integer types use `i32`, matching the C ABI even with a V
  compiler whose `int` is 64 bits. The default build links only the inert C host
  stub: VGlyph's macOS Objective-C bridge/overlay and IBus are excluded, preventing
  category loading, method swizzling and competing input contexts. They remain
  behind the standalone opt-in `vglyph_native_ime`; UI2 must not enable it and
  retains its existing host IME bridge.
- Optional imports follow their platform/profile guards. Unused font-size
  constants from upstream validation tests are excluded from the runtime copy.
  Optional Linux accessibility linking requires both `atk` and `atk-bridge-2.0`.

- Numeric `TextStyle.weight` overrides description/typeface weight in both plain and rich font descriptions; the text cache includes it. This UI2 extension exposes 100–900 weights without collapsing them to a bold flag.

For updates, compare these files with the pinned upstream tree and reconcile the
listed patches before changing the pin. Exercise CPU layout at multiple DPI
values, new glyph upload in the same frame, atlas growth/reuse and context
teardown alongside the affected UI2 backends.

## License and attribution

Upstream identifies the project as **MIT** in both its
[`v.mod`](https://github.com/vlang/vglyph/blob/72377fbe720dbd658ee96c59b49904ba30ebe059/v.mod)
and the **License** section of its
[`README.md`](https://github.com/vlang/vglyph/blob/72377fbe720dbd658ee96c59b49904ba30ebe059/README.md).
The original `v.mod`, including author Mike Ward and the MIT declaration, is
preserved here. That pinned tree contains no standalone LICENSE file or copyright
notice; this copy adds no invented notice. The native dependencies carry their
own licenses, documented in the UI2 setup guide.
