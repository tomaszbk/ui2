# Menus in VML

`menu_bar_from_vml_with_callbacks` converts a standalone menu document to
`[]Menu`. Supply callbacks for explicit `on_tap` names, then install it with
`set_menu_bar`:

```v
menus := ui2.menu_bar_from_vml_with_callbacks($embed_file('menus.vml').to_string(), {
    'file_new': ui2.ElementCallback(fn (event ui2.ElementEvent) { println('New') })
})!
ui2.set_menu_bar(menus)
```

```vml
MenuBar {
    Menu {
        title: "File"
        MenuItem { id: new_row text: "New" on_tap: file_new shortcut: "cmd+n" }
        MenuSeparator {}
        Menu { title: "Export" MenuItem { id: export_pdf text: "PDF" } }
    }
}
```

`id` is source identity. It never supplies an implicit action; rows with no
callback remain inert. The callback receives `.tap` and the declared source id.
V declarations use `MenuItem.on_select`; a menu-less tray uses `TrayConfig.on_event`.

A document contains one Menu or a MenuBar. Titles accept `title` or `text`.
Nested Menu/MenuItem nodes form submenus. Separators and submenus cannot carry
a leaf callback. Check marks and enabled state are declarations: update the
menu after handling an action. `cmd` names Command on macOS and Control on
Windows/Linux.

The loader accepts literal values and explicit callback names. It rejects app
expressions, calls, assignments, interpolation, bindings and property declarations.
`menu_bar_from_vml` and `menu_bar_from_vnode` remain useful for inert declarations.
Conversion validates
menus and does not install native UI. An empty MenuBar clears the menu declaration.

Keep menu documents separate from visual Screen documents. Flat context menu
rows on visual controls use the same per-row callbacks. Compiler lowering of
menu documents is separate work.

Run `v run examples/vml_menu` and `v test ui/vml_menu_test.v` for the example and
focused fixtures. Cross-target checks only compile backend integrations.
