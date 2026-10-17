module ui2

// The interpreter registry fragment of the kit's popups: overlays, menus,
// dialogs and toasts, with the legacy tags they replace. A tag is one line
// here; the registry test checks the bindable fields and part-only tags
// listed below against the props types.

fn kit_popups_widgets() map[string]VmlWidgetType {
	return {
		'Dropdown':    vml_widget[DropdownProps]()
		'Option':      vml_widget[OptionProps]()
		'MessageBox':  vml_widget[MessageBoxProps]()
		'Dialog':      vml_widget[DialogProps]()
		'Popover':     vml_widget[PopoverProps]()
		'MenuOverlay': vml_widget[MenuOverlayProps]()
		'ContextMenu': vml_widget[ContextMenuProps]()
		'Tooltip':     vml_widget[TooltipProps]()
	}
}

// kit_popups_expected_bindables are the fragment's bindable properties,
// `Tag.field`, which the registry test checks.
fn kit_popups_expected_bindables() []string {
	return ['Dropdown.text']
}

// kit_popups_expected_parts are the fragment's part-only tags, which take no
// common properties.
fn kit_popups_expected_parts() []string {
	return ['Option']
}
