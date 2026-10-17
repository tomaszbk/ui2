# UI2 Studio

<img width="1200" alt="UI2 Studio running with native macOS controls" src="../docs/images/ide-macos.png" />


`ide/` is a Delphi/Lazarus-style visual form designer implemented entirely in
V and UI2. It edits an explicit `Absolute` canvas inside a `Screen`, using logical units on
macOS, Windows, Linux, iOS, and Android.

Run it from the repository root. The designer previews documents with ui2's
VML interpreter, which is compiled in with `-d vml_interpreter`:

```sh
v -b c -d vml_interpreter run ide
```

Pass a designer VML file (or a directory containing one) to open it immediately:

```sh
v -b c -d vml_interpreter run ide ide/sample.vml
```

The palette and inspector follow the VML widget registry: a control is offered
only for a registered tag, with the properties its descriptor declares.

The designer provides:

- a single-window Delphi-style workspace with the component palette across the
  top, the object tree above the inspector on the left, and document tabs below
  the central design/code surface;
- a component palette for labels, buttons, fields, text areas, checkboxes,
  dropdowns, views, and images, with click-to-place and drag-to-form
  placement;
- a scaled WYSIWYG form with selection, drag, resize, arrow-key movement,
  grid display, and grid snapping;
- project and object trees plus a live property/event inspector whose editable
  rows support Tab and Shift+Tab traversal;
- a Layout inspector describing the canvas and control visibility;
- phone, tablet, desktop, rotated, and custom-size previews that do not rewrite
  the saved design;
- undo/redo, duplicate, delete, and z-order commands;
- generated VML source with a source-to-designer apply workflow;
- an interactive preview and a messages/build pane;
- VML save/open, file drop, safe unsaved-change prompts, `main.v` scaffolding,
  and project checking through the installed V compiler.

Preview interprets the current source with ui2's VML interpreter: it parses
the document with the same parser as the compiler, checks it against the
widget registry, and declares the same retained nodes as compiled VML. It needs
no compiler, so it works on every OS. Entering Preview again reloads the
document in place: declarations whose path and key did not change keep their
component state, relative component imports are read again, and a source that
does not load keeps the previous preview alive. Named callbacks report preview
events, and `app` is a sample model without fields whose method calls are
logged. Closing or replacing the preview disposes its document and lifecycle
scopes. The designer supplies property publication and ref commands to its
active backend.

Compiled VML stays the source of truth. **Verify with compiler** (Preview
toolbar, Run menu) compiles the source to a declaration library with the same
compiler as the designer and shows the compiled document in the preview; a
compilation error is reported in Messages and keeps the current preview. The
designer and its preview libraries use V's C backend for their exported struct
and callback ABI. A preview library has no garbage collector of its own: it is
linked against the designer's, which the designer exports on Linux and macOS.
V cannot link a Windows DLL that way, so on Windows the compiler verification
reports an error and the interpreted preview remains. Preview libraries do not
create additional platform controls or renderer instances.

The visual loader accepts one `Absolute` canvas inside `Screen`,
with plain numeric control coordinates. Dynamic expressions, repeaters, and
nested `Flex`, `Row`, `Column`, `Grid`, or `Stack` layouts
open in Source view, where they can be edited, saved and previewed.
Applying them to the visual canvas reports a diagnostic. Preview callbacks that
depend on application services require those services in the generated companion
application; the standalone designer preview supplies only its event callbacks.

Saving a new form will not overwrite an existing VML file that was not opened
first. `Generate main.v` also leaves an existing companion file untouched.

Control event names map to typed per-element callbacks in generated `main.v`.
Callbacks receive event kind, source identity, committed text/value/checked state
and logical pointer coordinates. Element ids are independent of callback names.
Designer dragging uses those pointer payloads.
