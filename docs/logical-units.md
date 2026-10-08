# Logical units

Geometry, `TextStyle.size` and VML `font_size` use logical units on every
platform. A font size of 18 means an 18-unit em square. There is no unit
profile: `UnitProfile`, `TextStyle.units`, `VmlRunConfig.units` and the VML
`units` property have been removed. An authored `units` property is an error.

Device DPI is a separate, per-window presentation scale. Native Apple controls
receive the declared logical font size directly; Win32 converts it to a physical
em height with `size * DPI / 96` and rounds only that final height. Fontstash
converts em size to its font's ascender-to-descender height for measurement and
drawing; this font-metric conversion is independent of platform DPI.

Declarations previously using the logical profile keep their sizes. Review old
Linux/Windows point declarations: legacy 18-point text used a 24-unit em square,
while font size 18 now uses 18 logical units. Increase an authored size only when
the larger em square is the intended design. Remove profile declarations from
V, runner configurations and VML documents. Apple declarations retain their
numeric em sizes.

Layout and text measurement remain fractional. Custom rectangle presentation
and scissor clipping round accumulated physical edges, deriving widths from
the rounded boundaries. `presentation_rect(rect, device_scale)` exposes that
conversion for custom geometry; it returns window-logical coordinates and never
mutates layout. Native controls use their toolkit presentation rules.

[ScaledContent](scaled-content.md) applies a composition transform after layout.
Its scale and device DPI remain independent: changing DPI does not change a
composition's logical dimensions or fit calculation.
