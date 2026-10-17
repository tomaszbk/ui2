# Windows

On Windows, as everywhere, ui2 draws every control with its gg/Sokol renderer
in one sokol_app window. The Win32 host (see `ui/platform.v`) adds the menu
bar as the window's `HMENU`, the notification area icon, the clipboard,
`MessageBoxW`, the common file dialogs and the hidden-titlebar window chrome.
There are no Win32 child controls.

Sokol draws through OpenGL (GLCORE) by default. Pass `-d sokol_d3d11` to draw
through Direct3D 11 instead; CI does not run that configuration.

Install the matching MSYS2 UCRT64 GCC and Pango/FreeType dependencies described
in [desktop text setup](vglyph-text.md), then run:

```sh
v -cc gcc run examples/runtime_smoke
```

`run_window`, `TextInputConfig`, element callbacks, `text`, `set_text`,
`request_refresh`, and `ui_dispatcher` use the shared UI2 API. Keep element ids
stable. Unchanged declared text preserves local edits, selection and scroll
across unrelated updates; `set_text` explicitly replaces the mounted editor's
contents. Text selections use rune offsets. Pointer positions and layout are
logical units; device DPI is applied at presentation, separately from
`ScaledContent`. See [logical units](logical-units.md) and
[scheduler and worker dispatch](custom-rendering-scheduler.md).

Character events contain committed Unicode scalars. Editing commands are
handled by key events: gg's synthetic character event after Delete must not
insert DEL into the document or report a second edit. C0 controls, DEL and
invalid scalars are ignored by character input. Printable characters from
AltGr, accents, ñ and decoded supplementary scalars still enter the editor.
The renderer has no preedit or composition bridge on Windows, so input
methods that compose text before committing it are not supported yet.

Menus: the host builds the declared menu bar as an `HMENU` and routes its
`WM_COMMAND` messages, and the notification area icon's clicks, through a
subclass of sokol's window. Sokol's message loop does not translate
accelerators, so the renderer matches the declared shortcuts against its own
key events, as it does on Linux.

The renderer retains the declared tree between updates. It repaints that tree
on each Sokol presentation callback because the backbuffer cannot be assumed
preserved. These presentation frames do not request model rebuilds.
Minimize/suspend suppresses visual work; restoration, resize and DPI changes
invalidate the surface. Worker posts and invalidations during a frame survive
its completion. This does not establish idle sleep on Windows.

The example has single-line and multiline editors with Spanish text. Place
the caret before ñ or select a range and press Delete; it should perform one
edit. Scroll the notes and press F6 while editing: the counter changes while
the editor keeps its local draft, caret/selection and scroll. F7 deliberately
replaces the notes. Resize, minimize/restore and move the window between DPI
scales to inspect presentation. The same example runs on macOS and Linux for
regression checks.

## Verification scope

```sh
make check-windows
v test ui/ui_custom_runtime_test.v
```

`make check-windows` **typechecks** the library, the renderer's runtime
fixtures and the example for Windows. CI runs the same typechecks and the
desktop test suite on `windows-latest`; each PowerShell invocation checks its
exit status. The shared compiler setup accepts `v-repository` and downloads the
pin from `tomaszbk/v`, so fork-only VML compiler revisions can be selected by
updating the single `v-revision` pin. Its generated-C bootstrap snapshot is
pinned separately; verify both pins together when changing the compiler.

Neither cross-target typechecks nor a successful Windows CI job establish
interactive runtime acceptance: presentation, real DPI transitions, the native
menu bar and tray, and IME behavior need a person at a Windows desktop.
