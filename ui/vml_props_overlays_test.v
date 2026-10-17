// vtest vflags: -d vml_props
module ui2

// Golden equivalence of the overlay props (Dialog, Popover, MenuOverlay,
// ContextMenu, Tooltip, View overlay) and context-menu MenuItem parts.


fn props_overlays_compiled(mut app PropsApp, frame Rect) Element {
	return $vml('fixtures/props_overlays.vml', frame)
}

fn props_overlays_tree(mut app PropsApp) PNode {
	return pn(ViewProps{ width: 500, height: 400 }, id: 'document', children: [
		pn(ButtonProps{ width: 80, height: 30, text: 'Open' }, id: 'anchor'),
		pn(ViewProps{ width: 50, height: 20 }, id: 'owner_view'),
		pn(DialogProps{
			width:      320
			height:     180
			open:       app.open
			on_dismiss: props_hit(mut app, 'dismiss')
			on_open:    props_hit(mut app, 'open')
		}, id: 'dialog', children: [
			pn(ColumnProps{}, children: [
				pn(LabelProps{ text: 'in dialog', width: 100, height: 20 }),
			]),
		]),
		pn(DialogProps{
			open:               true
			owner:              'owner_view'
			initial_focus:      'anchor'
			dismiss_on_escape:  false
			dismiss_on_outside: false
			backdrop:           app.backdrop
			backdrop_opacity:   0.5
			width:              100
			height:             50
		}, generated: true, children: [
			pn(ViewProps{}),
		]),
		pn(PopoverProps{
			anchor:    'anchor'
			placement: .top
			gap:       10
			margin:    4
			width:     100
			height:    60
			open:      app.open
		}, id: 'pop', children: [
			pn(LabelProps{ text: 'pop' }),
		]),
		pn(MenuOverlayProps{ anchor: 'anchor', placement: .right_start, width: 120, height: 80 }, id: 'menu_overlay', children: [
			pn(ButtonProps{ text: 'Item' }),
		]),
		pn(ContextMenuProps{
			width:  160
			height: 100
			anchor: 'anchor'
			point:  app.point
			open:   app.context_open
		}, id: 'context', children: [
			pn(ButtonProps{ text: 'Action', width: 140, height: 30 }, id: 'context_action'),
		]),
		pn(TooltipProps{
			width:              120
			height:             40
			anchor:             'anchor'
			open:               false
			tooltip_delay:      0.25
			accessibility_role: 'note'
		}, id: 'help', children: [
			pn(LabelProps{ text: 'Help' }),
		]),
		pn(ViewProps{
			overlay:    app.overlay
			width:      40
			height:     40
			on_dismiss: props_hit(mut app, 'view dismiss')
		}, id: 'with_overlay'),
		pn(ViewProps{ width: 40, height: 40 }, id: 'with_menu', children: [
			pn(MenuItemProps{ text: 'Copy', on_click: props_hit(mut app, 'copy') }, id: 'copy'),
			pn(MenuItemProps{ text: 'Paste' }),
		]),
		pn(LabelProps{ text: 'menu', width: 40, height: 20 }, id: 'label_menu', children: [
			pn(MenuItemProps{ text: 'Cut', on_click: props_hit(mut app, 'cut') }, id: 'cut'),
		]),
	])
}

fn test_props_overlays_match_compiled_vml() {
	frame := rect(0, 0, 500, 400)
	mut compiled_app := PropsApp{}
	mut props_app := PropsApp{}
	compiled := props_overlays_compiled(mut compiled_app, frame)
	built := props_document(props_overlays_tree(mut props_app), frame)!
	assert_props_equal('overlays', compiled, built)
	assert_props_events(compiled, built, mut compiled_app, mut props_app)
}
