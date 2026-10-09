# Custom desktop text

The custom desktop renderer uses [vglyph](https://github.com/vlang/vglyph)
for text layout, shaping and drawing. UI2 includes its runtime at
`thirdparty/vglyph`, based on upstream commit
`72377fbe720dbd658ee96c59b49904ba30ebe059` (module version 0.9.0), with the
integration changes described in [the vendor notes](../thirdparty/vglyph/README.ui2.md).
There is no separate `v install vglyph` step.

| Build | Text path |
| --- | --- |
| Linux desktop | vglyph |
| macOS or Windows with `-d ui2_custom_rendering` | vglyph |
| macOS with `-d ui2_custom_rendering -d ui2_embedder` | vglyph with the owned Metal context |
| Native AppKit, UIKit and Win32 | Existing platform controls and native/Fontstash CPU measurement |
| Android custom and `-d ui2_headless` | Existing Fontstash text and CPU measurement |

The native, Android and headless paths do not import the vendored runtime and
do not require its C libraries. The remaining Fontstash helpers serve those
paths. This rollout preserves the existing editor state, binding and undo
contracts and the host's IME bridge. Full cursor movement and deletion by
grapheme, and complete bidirectional editing, remain separate work.

## Build dependencies

Use the published `tomaszbk/v` compiler revision
[`80bffb6af279210c3dca80c155bffb538f11ade7`](https://github.com/tomaszbk/v/commit/80bffb6af279210c3dca80c155bffb538f11ade7).
It includes the compiled VML visual and structural lowering. The V 0.5.2 release binary lacks required
Sokol sampler APIs and does not compile the current UI2 source. CI uses
[the shared setup action](../.github/actions/setup-v/action.yml) to bootstrap
that revision with `vc` snapshot
`8af812feb76c678abd86a8e682fd9ab2790e519c` and the system C compiler.
The workflows also pin each platform's official `tccbin` bundle to supply
V's default Boehm GC library; compilation uses GCC or Clang.
Only the compiler bootstrap uses `-gc none`; UI2 builds retain the default GC.

The vendored text runtime also requires Pango
1.50 or newer, FreeType, HarfBuzz, FriBidi, Fontconfig, GLib and GObject, and a
working `pkg-config` command. The Pango minimum comes from the
[absolute line-height attribute](https://docs.gtk.org/Pango/func.attr_line_height_new_absolute.html)
used to retain UI2's legacy line spacing.

The required pkg-config modules are:

```text
pango pangoft2 freetype2 harfbuzz fribidi fontconfig gobject-2.0 glib-2.0
```

Pango's packaged dependencies can also include Cairo, libthai, libdatrie,
Graphite2, image decoders and platform libraries. Package managers resolve
those transitive dependencies. UI2 continues to draw through gg/Sokol; it
does not use GTK widgets.

On Linux the vendor discovers optional ATK/AT-SPI development packages when
both `atk` and `atk-bridge-2.0` pkg-config modules are available, which can add
linked libraries. UI2 does not initialize that accessibility integration in
this rollout.

UI2 keeps its host IME bridge. The vendor's native IME and overlay code is
disabled by default, including its optional IBus dependency. The
`vglyph_native_ime` define is reserved for standalone vendor users; do not
enable it in UI2 builds.

On macOS, install the Homebrew libraries for the same architecture as V:

```sh
brew install pango freetype harfbuzz fribidi fontconfig pkgconf
```

On Debian or Ubuntu, install the text development packages alongside the
existing gg/X11/OpenGL dependencies:

```sh
sudo apt-get install pkg-config libpango1.0-dev libfreetype6-dev \
  libharfbuzz-dev libfribidi-dev libfontconfig1-dev
sudo apt-get install fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji
```

The Noto packages supply optional multilingual fallback fonts. Bundled
Roboto, Roboto Mono, Noto Sans Symbols 2 and Noto Emoji remain the defaults
shipped by UI2.
The adapter prefers bundled Noto Emoji outlines to preserve the current
profile's monochrome appearance. Installing a color emoji font does not
switch that default.

On Windows, use an [MSYS2 UCRT64 environment](https://www.msys2.org/docs/environments/)
and matching GCC libraries:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-gcc \
  mingw-w64-ucrt-x86_64-pkgconf mingw-w64-ucrt-x86_64-pango \
  mingw-w64-ucrt-x86_64-freetype
v -cc gcc -d ui2_custom_rendering run examples/counter
```

Keep the UCRT64 `bin` directory ahead of other compilers and pkg-config
implementations in `PATH`. In PowerShell, a default MSYS2 installation can
be exposed with:

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;$env:PATH"
$env:PKG_CONFIG_PATH = 'C:\msys64\ucrt64\lib\pkgconfig;C:\msys64\ucrt64\share\pkgconfig'
```

This gives the compiler, import libraries and runtime DLLs the same ABI.
Other Windows toolchains need a matching Pango/FreeType stack; installing
headers alone is insufficient.

Check discovery before compiling:

```sh
pkg-config --exists pango pangoft2 freetype2 harfbuzz fribidi fontconfig gobject-2.0 glib-2.0
pkg-config --atleast-version=1.50 pango
pkg-config --modversion pango pangoft2 freetype2 harfbuzz fribidi fontconfig gobject-2.0 glib-2.0
```

CI checks these modules and logs the installed versions on Linux and custom
macOS/Windows builds. The vglyph source revision is fixed in the repository;
the C package versions follow the runner's package repositories.

## Measurement and units

`measure_layout_text(text, style, max_width)` works before opening a custom
desktop window. It uses a CPU vglyph context with the same font resolution,
shaping, wrapping and the same logical em sizes as drawing. CPU measurement
does not create an atlas texture, window or Sokol device.
Wrapping preserves the existing line spacing and does not insert automatic
hyphens.

The layout boundary keeps fractional logical measurements, accepts available
width and known dimensions, and distinguishes available-width measurement
from minimum and maximum content. Internal results include the baseline.
`measure_layout_text` keeps its existing public signature and `LayoutSize`
result; the adapter's request/result types are internal.

Typography uses the same [logical units](logical-units.md) as geometry on every
platform. A size of 18 means an 18-unit em square; there is no platform point
conversion or selectable profile. Device DPI applies separately, when glyphs are rasterized and presented; it does
not change logical line breaks. [Fixed composition scaling](scaled-content.md)
also preserves the original layout. [VML typography](vml-typography.md) documents
numeric weights, tracking, line height and styled label runs.

Labels, control captions, menus, tooltips, editable text and CPU intrinsic
measurement use the same text adapter in migrated builds. Font families and
file overrides use UI2's existing font discovery. The adapter preserves
UI2's explicit and bundled fallback priorities, including `UI2_FONT_SYMBOLS`
before bundled symbol and emoji fallbacks. Normal text resolves through its
requested and default text faces before symbol fallbacks. Emoji preferences
are separate and belong to each text context, so they do not replace normal
letters or digits. Pango/Fontconfig uses system faces for scripts and
codepoints still missing from the preferred fonts; those glyphs and advances
can depend on the installation. Compare layout using the same fonts and
preferences on each platform.

## Window and frame resources

Each drawing context owns its text context, glyph atlas and Sokol resources.
The owned macOS embedder supplies its window's device scale; text does not
read a global `sokol_app` scale for that path. The existing host continues
to own windows, events, Metal/Sokol surfaces and presentation.

New glyphs upload during a requested frame, and atlas changes are committed
before presentation. Text resources are resized or recreated with their
context and released while its graphics device is still alive. The text
backend adds no polling timer: resize, DPI, edits, selection and IME continue
through UI2's existing invalidation and scheduling paths. See
[rendering and idle behavior](custom-rendering-scheduler.md) for the distinct
Metal and GL/EGL/D3D presentation contracts.

## Distribution and licenses

The desktop builds use the linker flags returned by `pkg-config`, normally
linking these libraries dynamically. Vendoring the V runtime does not embed
the C libraries or fonts into the executable.

On Linux, declare the shared-library runtime packages for the target
distribution. On macOS, inspect `otool -L` and package the required dylibs
with suitable install names/rpaths for the app bundle. On Windows, ship
the required UCRT64 DLL dependency chain beside the application, or provide
an equivalent runtime installation. Fontconfig configuration/data and the
bundled fonts must also be available on the target machine. Test the package
on a clean machine; the development machine's package manager paths are not
a portable distribution contract.

| Component | Upstream license |
| --- | --- |
| vglyph | [MIT declaration](https://github.com/vlang/vglyph/blob/72377fbe720dbd658ee96c59b49904ba30ebe059/v.mod) |
| Pango | [LGPL](https://gitlab.gnome.org/GNOME/pango/-/blob/main/COPYING) |
| GLib/GObject | [LGPL 2.1 or later](https://docs.gtk.org/glib/) |
| FriBidi | [LGPL 2.1](https://github.com/fribidi/fribidi/blob/master/COPYING) |
| HarfBuzz | [Old MIT](https://github.com/harfbuzz/harfbuzz/blob/main/COPYING), with notices for individual components |
| FreeType | [FreeType License or GPL v2](https://freetype.org/license.html) |
| Fontconfig | [Permissive notices](https://gitlab.freedesktop.org/fontconfig/fontconfig/-/blob/main/COPYING) |
| UI2 bundled fonts | Font-specific notices in `assets/fonts/` |

Include the notices and licenses for the actual libraries, fonts and
transitive components shipped with the application. The license terms of
those components remain applicable to redistribution and linking.

## Verification

The focused CPU suite checks shaping, measurement without a window, long
text and device-scale invariance:

```sh
v -d ui2_custom_rendering test ui/text_backend_vglyph_test.v
v -d ui2_custom_rendering test thirdparty/vglyph/ui2_context_test.v
v -d ui2_custom_rendering test thirdparty/vglyph/ui2_host_ime_test.v
```

On Linux the custom renderer is already the default, so the define is
optional. For MSYS2 Windows custom tests use `-cc gcc`.

The existing checks cover the backend and retained input/layout contracts:

```sh
make test
make examples
make examples-custom
make check-embedder-macos
make test-embedder
make screenshot EXAMPLE=message
```

The embedder resource suite requires a real macOS graphics device. CI's
embedder check compiles the path; it does not establish interactive IME
acceptance. A screenshot tests the gg/OpenGL presentation path on macOS;
inspect the owned Metal path separately. Native and mobile checks keep
their existing SDK/toolchain requirements.

The example builder treats warnings as errors with `-W`. Informational
compiler notices, including unused private helpers shared across backends,
do not fail the build.
