# Desktop custom typography

The desktop custom renderer supports `weight` (100–900), `letter_spacing`,
`line_height`, `line_height_factor`, `baseline_offset` and `tabular_figures` on
`TextStyle` and VML text controls. `weight: 0` retains the existing `bold` mapping
(400 or 700); explicit weight overrides it. Fontconfig selects the nearest
available real face. Bundled Inter provides upright 400–900 faces; application
font directories and file paths still work.

Spacing and baseline offsets use logical geometry units. Positive baseline
values raise text. `line_height` is an absolute logical line advance;
`line_height_factor` multiplies the platform's existing logical em size. Choose
one; zero keeps legacy spacing. Defaults preserve existing point-size behavior.
`tabular_figures` requests the OpenType `tnum` feature where the font supports it.

```vml
Label {
    font_family: "Inter"
    font_size: 24
    weight: 800
    line_height_factor: 1.4
    lines: 4
    Run { text: "Revenue " }
    Run { text: "$123" font_size: 16 weight: 400 color: #44AA88 baseline_offset: 2 }
}
```

Use either `text` or `Run` children. Runs inherit omitted parent properties;
explicit false/zero overrides inheritance. Each child has its own text, size,
weight, font, color, underline, strike-through, tracking and baseline shift.
The parent controls wrapping, alignment, line limit and line grid. Measurement
and drawing use one rich layout, including styled ellipsis across paragraphs.
VML expressions in run properties follow ordinary runtime binding rules.

In V, `rich_label(id, runs, frame, style)` constructs the same label using
existing `TextRun` values. V run styles are complete styles, with their ordinary
TextStyle defaults; they do not implicitly inherit the parent.

These additions currently render on desktop custom (macOS, Windows and Linux).
Native, Android and headless retain their existing text paths: a rich label's
concatenated text remains visible, but new typography attributes and per-run
styles do not gain portable native rendering in this delivery. Existing native
rich TextArea contracts remain unchanged. This does not extend grapheme editing,
IME or accessibility support. Runtime and `$vml` compiler lowering are distinct;
new Run syntax requires runtime VML, not the external compiler's existing lowering.
