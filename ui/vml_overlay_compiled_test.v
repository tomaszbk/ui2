// vtest vflags: -d ui2_custom_rendering -d vml_fixtures
module ui2

// vml: fixtures/compiled_overlay_surface.vml
// vml: fixtures/compiled_overlay_config.vml
// vml: fixtures/compiled_overlay_scroll.vml
// vml: fixtures/compiled_overlay_namespaces.vml

@[heap]
pub struct OverlayCompiledModel {
pub mut:
	open           bool
	hidden         bool
	count          int
	context_open   bool
	tip_open       bool
	point          ?OverlayPoint
	config         OverlayConfig = OverlayConfig{ kind: .dialog }
	scroll_mode    ScrollMode    = .vertical_only
	dismiss_reason OverlayDismissReason
	items          []OverlayCompiledItem = [OverlayCompiledItem{ id: 1 }, OverlayCompiledItem{ id: 2 }]
}

pub struct OverlayCompiledItem {
pub:
	id int
}

pub fn (mut app OverlayCompiledModel) increment() { app.count++ }

pub fn (mut app OverlayCompiledModel) dismiss(reason OverlayDismissReason) {
	app.dismiss_reason = reason
	app.open = false
	app.config = OverlayConfig{ ...app.config, open: false }
}

pub fn (mut app OverlayCompiledModel) open_context(x f64, y f64) {
	app.point = OverlayPoint{ x: x, y: y }
	app.context_open = true
}

pub fn (mut app OverlayCompiledModel) dismiss_context() { app.context_open = false }

pub fn (mut app OverlayCompiledModel) show_tip() { app.tip_open = true }

pub fn (mut app OverlayCompiledModel) hide_tip() { app.tip_open = false }

fn overlay_compiled_surface(mut app OverlayCompiledModel) Element {
	return compiled_overlay_surface_vml_framed(mut app, rect(0, 0, 500, 400))
}

fn overlay_compiled_config(mut app OverlayCompiledModel) Element {
	return compiled_overlay_config_vml_framed(mut app, rect(0, 0, 500, 400))
}

fn overlay_compiled_scroll(mut app OverlayCompiledModel) Element {
	return compiled_overlay_scroll_vml_framed(mut app, rect(0, 0, 100, 80))
}

fn overlay_compiled_namespaces(mut app OverlayCompiledModel) Element {
	return compiled_overlay_namespaces_vml_framed(mut app, rect(0, 0, 500, 480))
}

fn overlay_compiled_find(element Element, id string) !Element {
	if element.id == id { return element }
	for child in element.children {
		if found := overlay_compiled_find(child, id) { return found }
	}
	return error('missing compiled overlay control `${id}`')
}

fn test_compiled_dialog_open_hidden_and_dismiss_preserve_child_identity() ! {
	mut app := &OverlayCompiledModel{}
	initial := overlay_compiled_surface(mut app)
	defer { initial.compiled_node.dispose_document() or { panic(err) } }
	dialog := overlay_compiled_find(initial, 'dialog')!.compiled_node
	draft := overlay_compiled_find(initial, 'draft')!.compiled_node
	counter := overlay_compiled_find(initial, 'counter')!.compiled_node
	assert dialog.element().hidden
	app.open = true
	dialog.component.invalidate_app()!
	assert !dialog.element().hidden
	assert dialog.element().focus_scope
	assert dialog.element().accessibility_role == 'dialog'
	counter.element().on_event(ElementEvent{ kind: .click, id: 'counter' })
	assert app.count == 1
	assert overlay_compiled_find(dialog.element(), 'count')!.text == '1'
	app.hidden = true
	dialog.component.invalidate_app()!
	assert dialog.element().hidden
	app.hidden = false
	dialog.component.invalidate_app()!
	assert !dialog.element().hidden
	config := dialog.element().overlay or { panic('missing overlay') }
	config.on_dismiss(ElementEvent{ kind: .dismiss, id: 'dialog', dismiss_reason: .escape })
	assert !app.open
	assert app.dismiss_reason == .escape
	assert dialog.element().hidden
	app.open = true
	dialog.component.invalidate_app()!
	assert !dialog.element().hidden
	assert overlay_compiled_find(dialog.element(), 'draft')!.compiled_node == draft
	assert overlay_compiled_find(dialog.element(), 'counter')!.compiled_node == counter
	assert overlay_compiled_find(dialog.element(), 'count')!.text == '1'
}

fn test_compiled_context_and_tooltip_open_callbacks_update_controlled_sources() ! {
	mut app := &OverlayCompiledModel{}
	initial := overlay_compiled_surface(mut app)
	defer { initial.compiled_node.dispose_document() or { panic(err) } }
	context := overlay_compiled_find(initial, 'context')!.compiled_node
	help := overlay_compiled_find(initial, 'help')!.compiled_node
	context_config := context.element().overlay or { panic('missing context menu') }
	context_config.on_open(ElementEvent{ kind: .open, id: 'context', x: 72.5, y: 96.25 })
	assert app.context_open
	assert !context.element().hidden
	point := (context.element().overlay or { panic('missing context menu') }).point or { panic('missing point') }
	assert point == OverlayPoint{ x: 72.5, y: 96.25 }
	app.point = none
	context.component.invalidate_app()!
	assert (context.element().overlay or { panic('missing context menu') }).point == none
	context_config.on_dismiss(ElementEvent{ kind: .dismiss, id: 'context', dismiss_reason: .outside_pointer })
	assert context.element().hidden
	tip_config := help.element().overlay or { panic('missing tooltip') }
	assert tip_config.tooltip_delay == 0.25
	tip_config.on_open(ElementEvent{ kind: .open, id: 'help' })
	assert app.tip_open
	assert !help.element().hidden
	assert help.element().focus_policy == .unfocusable
	tip_config.on_dismiss(ElementEvent{ kind: .dismiss, id: 'help', dismiss_reason: .pointer_leave })
	assert !app.tip_open
	assert help.element().hidden
}

fn test_compiled_typed_overlay_config_updates_open_and_role_without_replacing_content() ! {
	mut app := &OverlayCompiledModel{}
	initial := overlay_compiled_config(mut app)
	defer { initial.compiled_node.dispose_document() or { panic(err) } }
	node := initial.compiled_node
	draft := overlay_compiled_find(initial, 'typed_draft')!.compiled_node
	assert node.element().hidden
	app.config = OverlayConfig{ kind: .dialog, open: true }
	node.component.invalidate_app()!
	assert !node.element().hidden
	assert node.element().accessibility_role == 'dialog'
	app.config = OverlayConfig{ kind: .popover, open: true, point: OverlayPoint{ x: 30, y: 40 } }
	node.component.invalidate_app()!
	assert node.element().accessibility_role == ''
	assert !node.element().focus_scope
	assert overlay_compiled_find(node.element(), 'typed_draft')!.compiled_node == draft
	app.config = OverlayConfig{ ...app.config, open: false }
	node.component.invalidate_app()!
	assert node.element().hidden
	app.config = OverlayConfig{ ...app.config, open: true }
	node.component.invalidate_app()!
	assert !node.element().hidden
	assert overlay_compiled_find(node.element(), 'typed_draft')!.compiled_node == draft
}

fn test_compiled_scroll_mode_changes_leave_scrolling_content_axes_loose() ! {
	mut app := &OverlayCompiledModel{ scroll_mode: .horizontal_only }
	initial := overlay_compiled_scroll(mut app)
	defer { initial.compiled_node.dispose_document() or { panic(err) } }
	root := initial.compiled_node
	content := overlay_compiled_find(initial, 'content')!.compiled_node
	assert content.inherit_width && content.inherit_height
	mut tree := &LayoutTree{}
	tree.replace(root.element())!
	mut resolved := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert overlay_compiled_find(resolved, 'content')!.frame.width == 160
	assert overlay_compiled_find(resolved, 'content')!.frame.height == 80
	app.scroll_mode = .both
	root.component.invalidate_app()!
	tree.patch(root.element().id, root.element())!
	resolved = tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert overlay_compiled_find(resolved, 'content')!.frame.width == 160
	assert overlay_compiled_find(resolved, 'content')!.frame.height == 62
	assert overlay_compiled_find(resolved, 'content')!.compiled_node == content
}

fn overlay_compiled_panels(element Element) []Element {
	mut panels := []Element{}
	if element.compiled_node != unsafe { nil } && element.compiled_node.authored_id == 'panel' {
		panels << element
	} else {
		for child in element.children { panels << overlay_compiled_panels(child) }
	}
	return panels
}

fn test_compiled_overlay_local_refs_follow_keyed_component_namespaces() ! {
	mut app := &OverlayCompiledModel{}
	initial := overlay_compiled_namespaces(mut app)
	defer { initial.compiled_node.dispose_document() or { panic(err) } }
	root := initial.compiled_node
	before := overlay_compiled_panels(initial)
	assert before.len == 2
	assert before[0].id != before[1].id
	mut surfaces := []&CompiledVmlNode{}
	for panel in before {
		owner := panel.compiled_node.component
		trigger := overlay_compiled_find(panel, owner.control_id('trigger'))!
		first := overlay_compiled_find(panel, owner.control_id('first'))!
		surface := overlay_compiled_find(panel, owner.control_id('surface'))!
		config := surface.overlay or { panic('missing namespaced overlay') }
		assert config.anchor == trigger.id
		assert config.owner == panel.id
		assert config.initial_focus == first.id
		surfaces << surface.compiled_node
	}
	app.items = [OverlayCompiledItem{ id: 2 }, OverlayCompiledItem{ id: 1 }]
	app.open = true
	root.component.invalidate_app()!
	after := overlay_compiled_panels(root.element())
	assert after.len == 2
	assert after[0].id == before[1].id
	assert after[1].id == before[0].id
	for index, panel in after {
		owner := panel.compiled_node.component
		surface := overlay_compiled_find(panel, owner.control_id('surface'))!
		config := surface.overlay or { panic('missing namespaced overlay') }
		assert surface.compiled_node == surfaces[1 - index]
		assert !surface.hidden
		assert config.anchor == owner.control_id('other_trigger')
		assert config.owner == panel.id
		assert config.initial_focus == owner.control_id('first')
	}
}
