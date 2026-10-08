# UI2 Studio

<img width="1200" alt="UI2 Studio running with native macOS controls" src="../docs/images/ide-macos.png" />


`ide/` is a Delphi/Lazarus-style visual form designer implemented entirely in
V and UI2. It edits an explicit `Absolute` canvas inside a `Screen`, using logical units on
macOS, Windows, Linux, iOS, and Android.

Run it from the repository root:

```sh
v run ide
```

Pass a designer VML file (or a directory containing one) to open it immediately:

```sh
v run ide ide/sample.vml
```

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

The visual loader deliberately accepts one `Absolute` canvas inside `Screen`,
with plain numeric control coordinates. Dynamic expressions, repeaters, and
nested `Flex`, `Row`, `Column`, `Grid`, or `Stack` layouts
remain editable in Source view, but are rejected by the designer instead of
being flattened or silently lost.

Saving a new form will not overwrite an existing VML file that was not opened
first. `Generate main.v` also leaves an existing companion file untouched.

Control event names map to typed per-element callbacks in generated `main.v`.
Callbacks receive event kind, source identity, committed text/value/checked state
and logical pointer coordinates. Element ids are independent of callback names.
Designer dragging uses those pointer payloads.
