# Compiled VML components

VML files compile to V with `$vml('app.vml')`. The compiler lowers declarations
to the ui2 signal, component and layout APIs. A compiled document creates its
elements once; property effects patch retained nodes and repeaters reconcile
children by key. `app` refers to the hosting V application and its services.

```vml
component Counter(title string = "Count", changed event(value int)) {
    state count := 0
    computed doubled := count * 2

    fn increment() {
        count++
        changed(count)
    }

    Column(gap: 12) {
        Label(text: title)
        Label(text: doubled)
        Button(text: "Add", on_tap: increment)
        Button(text: "Reset", on_tap: { count = 0; changed(count) })
    }
}
```

Inputs are declared in the component signature. Ordinary inputs are read-only;
`state` creates private mutable data once per instance and `computed` declares
a lazy memo. Types follow V inference. Member names and element ids share the
component's namespace; collisions are compile errors. There is no implicit
shadowing or `self` prefix.

An event has an exact payload signature and returns void. Emitting
`changed(count)` notifies the connected handler; it does not assign parent data.
Connect `changed` with `on_changed: app.observe`. An omitted event handler is a
typed no-op. Control handlers accept `fn()` or `fn(ui2.ElementEvent)`, returning
void. Component event handlers accept the
event's declared parameter types or `fn()` to ignore the payload. The compiler
rejects incompatible signatures.

## Explicit writable connections

```vml
component NameEditor(bind name string) {
    TextInput(bind.text: name)
}
```

Import that component from `name_editor.vml`:

```vml
import NameEditor
Screen {
    NameEditor(bind.name: app.name)
}
```

`bind name string` declares a bindable input. Passing `name: expression` reads
its value; passing `bind.name: writable_source` connects writes to the source.
Writing requires an explicit binding. A local editable copy uses `state`.
`text: value` displays strings or numbers; `bind.text` requires a writable
string. Numeric editing therefore needs an explicit conversion in application
logic. VML enum properties use bare values, for example `align: right`.
`TextInput` edits one line and supports password entry and submit events;
`TextArea` edits multiple lines and accepts rich `Run` content. They are separate
controls, with `text_input` and `text_area` constructors in the V API.

## Handlers and lifetime

Handlers can refer to local functions, contain a short statement such as
`on_tap: count++`, or contain a block. Writes batch per action. `mount { ... }`
runs once when an instance enters the mounted tree; `unmount { ... }` runs when
that mounted instance is disposed. `cleanup { ... }` releases resources owned by its
scope. Removed keyed instances dispose their effects and cleanups. A callback
retained after disposal cannot update the old instance.

V application code can obtain a scope-owned `VmlTask` with
`component.task("load")!`. Workers check `is_cancelled()` and deliver results
with `post(dispatcher, action)`, which batches the action on the UI thread.
Disposing the component cancels its tasks and discards queued deliveries.
Cancellation does not undo side effects a worker has already performed.

Ordinary V fields on `app` remain application data. VML actions invalidate
bindings that read them; changes made by timers or other application code need
`ui2.request_refresh()` on the UI thread. Component state updates invalidate
their signal dependents directly.

## Slots and typed refs

```vml
component Card(title string, content slot) {
    Column {
        Label(text: title)
        Slot(name: "content")
    }
}
```

```vml
import Card
Card(title: "Details") {
    Label(text: app.name)
}
```

Slot content keeps the author's lexical values. The receiving instance owns
its mounted nodes, effects and cleanup. A declared default `content` slot
accepts the invocation's content block. Named slots use `Slot(name: "name")`.

```vml
component Editor() {
    ref name_field TextInput
    Column {
        TextInput(id: "name_input", ref: name_field)
        Button(text: "Focus", on_tap: name_field.focus()!)
    }
}
```

Refs are typed handles, excluded from bindings and state snapshots. They become
available after mount and unavailable after removal or disposal. Control marker
types constrain supported operations: editable refs provide `set_text`, and
focusable refs provide `focus`. `set_text` explicitly replaces the local edit
buffer. Ref commands require an authored `id` on the target, as shown above;
calling a command without one produces a diagnostic. An unchanged declared
text value preserves local editing.

`run_compiled_vml` closes the document and its scopes when the window closes.
Code hosting an explicit `$vml(..., frame)` tree closes it with
`root.compiled_node.dispose_document()!`, including a document whose visual root
is an imported component.

See `examples/counter` for two independent imported Counter instances, one with
a connected output event and one with the event omitted. The compiled acceptance
fixtures verify identity, state independence, lifecycle and late callbacks.
