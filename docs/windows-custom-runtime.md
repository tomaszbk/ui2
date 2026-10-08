# Windows custom backend

Windows uses native Win32 controls by default. Select the existing gg/Sokol
custom renderer with `-d ui2_custom_rendering`; its Windows graphics backend is
D3D11. This uses Sokol's existing window and event loop.

Install the matching MSYS2 UCRT64 GCC and Pango/FreeType dependencies described
in [desktop text setup](vglyph-text.md), then run:

```sh
v -cc gcc -d ui2_custom_rendering run examples/windows_custom_runtime
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
The existing native Windows selection/IME path and macOS owned-embedder IME
bridge retain their contracts. Custom Windows does not expose a new preedit
or composition bridge; this work does not establish advanced IME parity.

The custom backend retains the declared tree between updates. D3D must repaint
that tree on each Sokol presentation callback because the backbuffer cannot be
assumed preserved. These presentation frames do not request model rebuilds.
Minimize/suspend suppresses visual work; restoration, resize and DPI changes
invalidate the surface. Worker posts and invalidations during a frame survive
its completion. This does not establish idle sleep on Windows.

The example has single-line and multiline editors with Spanish text. Place
the caret before ñ or select a range and press Delete; it should perform one
edit. Scroll the notes and press F6 while editing: the counter changes while
the editor keeps its local draft, caret/selection and scroll. F7 deliberately
replaces the notes. Resize, minimize/restore and move the window between DPI
scales to inspect presentation. The same example runs on macOS custom and
Linux for regression checks.

## Verification scope

```sh
make check-windows
make check-custom-windows
v -d ui2_custom_rendering test ui/ui_custom_runtime_test.v
```

The Make targets are **typechecks**, including the native backend, custom
runtime fixtures and example. Fork CI has explicit native/custom typecheck
steps on `windows-latest`; each PowerShell invocation checks its exit status.
The shared compiler setup accepts `v-repository` and downloads the pin from
`tomaszbk/v`, so fork-only VML compiler revisions can be selected by updating
the single `v-revision` pin. Its generated-C bootstrap snapshot is pinned
separately; verify both pins together when changing the compiler.

Windows evidence for this scope is typecheck only. Neither cross-target
typechecks nor a successful Windows CI job establish interactive runtime
acceptance, D3D presentation, real DPI transitions or IME behavior. Running
the CPU fixtures on another host verifies the shared contracts; the macOS
custom screenshot verifies only that renderer on macOS.
