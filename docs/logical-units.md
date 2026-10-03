# Logical units and legacy migration

Existing applications retain `UnitProfile.legacy`: geometry uses window logical
coordinates and text sizes retain platform point conversion. Opt in explicitly
with `TextStyle{units: .logical}` or `VmlRunConfig{units: .logical}`. In VML,
`Screen { units: "logical" ... }` inherits the profile through its descendants;
an explicit `units: "legacy"` overrides it for a subtree.

The logical profile gives `font_size` the same unit as geometry on every platform.
A size of 18 means an 18-unit em square. Device DPI remains a separate, per-window
presentation scale. Native controls preserve their toolkit appearance; the Win32
adapter converts logical sizes to points before the existing DPI-aware font API.
Existing declarations should be reviewed when opting in: Linux/Windows legacy
18-point text uses a 24-unit em square, while logical 18 uses 18 units.

Custom rectangle presentation and scissor clipping round accumulated physical
edges, deriving widths from the rounded boundaries. Layout and text measurement
remain fractional. `presentation_rect(rect, device_scale)` exposes that conversion
for custom geometry; it returns window-logical coordinates and never mutates layout.
Native control layout continues to use its toolkit presentation rules.
