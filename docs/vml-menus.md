# Menus in compiled VML

A standalone Menu or MenuBar document compiles to `[]ui2.Menu`. Attach explicit
callbacks and install the result with `set_menu_bar`:

```v okfmt
fn file_new(event ui2.ElementEvent) {
	println('New')
}

fn menus() []ui2.Menu {
	return $vml('menus.vml')
}
```

```vml
MenuBar {
    Menu(title: "File") {
        MenuItem(id: "new_row", text: "New", on_tap: file_new, shortcut: "cmd+n")
        MenuSeparator {}
        Menu(title: "Export") { MenuItem(id: "export_pdf", text: "PDF") }
    }
}
```

IDs identify rows and never imply handlers. Unhandled actions remain inert.
Callbacks accept zero arguments or one `ui2.ElementEvent` and return `void`.
Nested Menu/MenuItem nodes form submenus. Separators and submenus cannot carry
leaf callbacks. Check marks and enabled state are declarations; install the
updated menu after changes. `cmd` denotes Command on macOS and Control on
Windows/Linux. V declarations use `MenuItem.on_select`; a menu-less tray uses
`TrayConfig.on_event`.

Compilation validates the declaration without installing native UI. An empty
MenuBar clears it. Keep menu documents separate from visual Screen documents.
Flat context menu rows on visual controls use the same per-row callback types.

Run `v -b c run examples/vml_menu` for the example and `v -b c test examples/menubar` for
the compiled menu fixtures. Cross-target checks compile backend integrations.
