# VML styles and themes

Presentation has one argument, `style: [...]`. Each helper produces a typed,
sparse style patch. Compose patches from left to right: the last supplied value
of a property wins, and omitted properties keep their preceding values. Zero,
black and `false` are explicit values.

## Inline and reusable styles

```vml
style card = [
    background(color.surface),
    padding(12),
    radius(8)
]

View(style: [card, background(color.accent)]) {
    Label(text: "Content")
}
```

The local override replaces the background and preserves the padding and radius.
For a single use, write the same helpers directly:

```vml
View(style: [background(color.surface), padding(12), radius(8)]) {
    Label(text: "Content")
}
```

Style declarations can also belong to a component:

```vml
component Card(title string = "Content") {
    style surface = [background(color.surface), padding(12), radius(8)]

    View(style: [surface]) {
        Label(text: title)
    }
}

Column(spacing: 16) {
    Card(title: "Players")
    Card(title: "Games")
}
```

Components can be declared in the document or imported from another `.vml` file.
Component style declarations share the namespace of inputs, state, functions and
element ids; collisions are diagnosed. Style declarations are pure reactive
values, so inputs, state and theme tokens can be used inside them.

Geometry and behavior remain named arguments: `width`, `height`, `x`, `y`, layout
configuration such as `gap` and `columns`, control values and event handlers.
Typography and outer box presentation go through `style`. There are no abbreviated
aliases such as `bg` or `p`, and no parallel `background:` or `color:` arguments.
Specialized component inputs such as `tab_background` customize a distinct child
part and remain component inputs. Transforms and motion keep their existing
typed APIs and arguments.

| Presentation | Helpers |
| --- | --- |
| Box | `background`, `radius`, `transparent` |
| Borders | `border_width`, `border_color`, per-edge width/color helpers, `border_pattern`, `dash_length`, `dash_gap` |
| Outline | `outline_color`, `outline_width`, `outline_offset` |
| Insets | `padding`, `padding_left`, `padding_top`, `padding_right`, `padding_bottom` |
| Text | `foreground`, `text_background`, `font_size`, `font_family`, `weight`, `italic`, `underline`, `strikethrough` |
| Text layout | `text_align`, `text_valign`, `lines`, `letter_spacing`, `line_height`, `line_height_factor`, `baseline_offset`, `tabular_figures` |

Enums stay bare: `text_align(right)` and `border_pattern(dashed)`. Use `weight(700)`
for bold text and `weight(400)` for regular text. Insets apply to layout
containers, `View`, and custom-rendered `Button`/`ToggleButton` content while
preserving the full button hit area. `TextInput` currently supports
`padding_left` only.
Property values follow their ordinary numeric, color, boolean or string types.

For example, a custom button can keep all its appearance inline:

```vml
Button(text: "Save", style: [background(color.accent), padding(12), radius(8)])
```

## Variants and interaction

Variants are typed component inputs resolved to ordinary styles. They need no
separate variant grammar:

```vml
component Notice(title string, emphasized bool = false) {
    style base = [padding(spacing.medium), radius(radius.medium)]
    style normal = [background(color.surface)]
    style strong = [background(color.accent)]

    View(style: [base, emphasized ? strong : normal]) {
        Label(text: title, style: [foreground(emphasized ? color.white : color.text)])
    }
}
```

Hover, focus, pressed and disabled compose nested paint patches:

```vml
Button(
    text: "Save",
    on_click: app.save(),
    style: [
        background(color.accent),
        foreground(color.white),
        radius(8),
        hover([background(#1D4ED8)]),
        focus([outline_color(color.accent), outline_width(2)]),
        pressed([background(#1E40AF)]),
        disabled([background(color.muted)])
    ]
)
```

Interaction patches accept box properties and `foreground`; metric typography and
padding are diagnosed inside them. Hover applies before focus and pressed;
disabled uses its own patch. Explicit rich-run colors remain independent. See
[custom box styles](custom-box-styles.md) for border and pointer behavior.

Container typography does not implicitly cascade to child elements. Apply a
shared text style to each child that needs it; rich `Run` content inherits the
omitted properties of its parent text control.

## Tokens and themes

Tokens are semantic values with typed namespaces: `color.surface`,
`spacing.medium`, `radius.large` and `typography.body`. For example:

```vml
Label(text: "Heading", style: [foreground(color.text), font_size(typography.heading)])
```

A theme supplies token values through the V runtime:

```v
ui2.run_compiled_vml(ui2.CompiledVmlRunConfig[App]{
    model: app
    build: build
    theme: ui2.Theme{
        colors: { 'brand': u32(0x60a5fa) }
        spacing: { 'gutter': f64(16) }
    }
})!
```

The initial theme is available before styles are evaluated, so a document can
use custom tokens such as `color.brand` and `spacing.gutter`. To change the
theme of an existing document:

```v
ui2.set_vml_theme(root, ui2.Theme{
    colors: {
        'surface': u32(0x0f172a)
        'text': u32(0xf8fafc)
        'accent': u32(0x60a5fa)
    }
    spacing: { 'medium': f64(16) }
    radii: { 'medium': f64(10) }
    font_sizes: { 'heading': f64(30) }
})!
```

`root` is the element returned by `$vml`. A component also exposes
`set_theme(Theme)!`. Local tokens inherit from the nearest component ancestor,
then the built-in default theme. Replacing a local theme drops its old overrides.
Unknown tokens and invalid numeric values are diagnosed.
Removing a custom token that is still used is rejected before the theme changes.
The namespaces `color`, `spacing`, `radius` and `typography` are reserved.

Style effects patch retained nodes. A paint change requests painting; text
metrics and insets invalidate measurement and layout. Theme changes preserve
node identity, focus, local text edits and selection.

The visual designer writes canonical inline style lists for its editable literal
forms. Reusable declarations, tokens, expressions and interaction styles remain
available in source mode and compile through the same VML frontend.
