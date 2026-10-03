# Bundled fonts

Roboto 3.016, the `web/static` build from
[googlefonts/roboto-classic](https://github.com/googlefonts/roboto-classic/releases/tag/v3.016),
covering Latin, Greek, Cyrillic, and Vietnamese, Roboto Mono 3.001 from
[googlefonts/RobotoMono](https://github.com/googlefonts/RobotoMono), Material
Icons from [google/material-design-icons](https://github.com/google/material-design-icons),
Noto Sans Symbols 2 v2.008, the `unhinted` build from
[notofonts/symbols](https://github.com/notofonts/symbols/releases/tag/NotoSansSymbols2-v2.008),
and Noto Emoji 3.002 from
[google/fonts](https://github.com/google/fonts/tree/main/ofl/notoemoji).

The custom renderer uses these files unless the application overrides them
(see "Fonts and text sizes" in the top-level README). The desktop vglyph
adapter registers the bundled faces with Pango/Fontconfig before measuring
or drawing. Android custom and headless measurement retain Fontstash.

`RobotoMono-Regular.ttf` has to keep that name and stay in this directory: the
remaining gg/Fontstash paths find the mono face by rewriting `-Regular` to
`Mono-Regular` in the path they receive. UI2 also uses it when an element asks
for an unavailable fixed-pitch family, such as `Consolas` or generic `monospace`.

`MaterialIcons-Regular.ttf` supplies portable equivalents for platform icon
names such as SF Symbols on a custom-rendered desktop. It makes those
private-use glyphs available without a machine-installed icon font.

`NotoSansSymbols2-Regular.ttf` supplies geometric shapes, dingbats, box
elements and braille that the text faces do not cover. `NotoEmoji-Regular.ttf`
supplies monochrome emoji outlines, which take the text's color.

On desktop, Pango shapes clusters and Fontconfig chooses fallback faces,
preserving UI2's explicit and bundled priorities. `UI2_FONT_SYMBOLS` takes
precedence over bundled symbol and emoji fallbacks. The current profile
prefers bundled Noto Emoji outlines; installing color emoji does not switch
that default. System fonts cover scripts and codepoints still missing from
these faces. Use the same font set and preferences for layout comparisons. See
[the desktop text contract](../../docs/vglyph-text.md).

The Android/headless Fontstash paths keep an explicit fallback chain:
Material Icons, Noto Sans Symbols 2, an installed symbol face, then Noto Emoji.
Their `stb_truetype` rasterizer reads neither bitmap color emoji nor COLR layers,
and draws individual code points without complex shaping. The bundled
monochrome face also covers U+FE0F and U+200D so those paths do not draw empty
boxes for variation selectors and joiners. Its presence does not add
grapheme-aware editing to the existing editor.

The bundled monochrome family is a static regular instance of upstream's
variable `NotoEmoji[wght].ttf`, generated with:

```sh
fonttools varLib.instancer -q 'NotoEmoji[wght].ttf' wght=400 \
	--update-name-table -o NotoEmoji-Regular.ttf
```

These static instances work on both text paths. The remaining Fontstash
rasterizer ignores `fvar` and `gvar`, so a variable `Roboto[wdth,wght].ttf`
would draw its default weight there. UI2's styles currently select bold and
italic; additional desktop weight/variation controls require a separate API.

For Roboto, the `web` build rather than `unhinted` because it is a third of the
size and carries the same outlines. The Fontstash path never runs hinting
instructions, so the `hinted` build would only add bytes there. For the same reason
Noto Sans Symbols 2 is the `unhinted` build rather than the `googlefonts` one,
which is the same outlines and twice the file.

Roboto, Roboto Mono, Noto Sans Symbols 2, and Noto Emoji are licensed under the
SIL Open Font License 1.1. They carry
different copyright notices, so each keeps its own copy: `Roboto-OFL.txt`,
`RobotoMono-OFL.txt`, `NotoSansSymbols2-OFL.txt` and `NotoEmoji-OFL.txt`.
Material Icons is licensed under Apache License 2.0, kept as
`MaterialIcons-LICENSE.txt`.
