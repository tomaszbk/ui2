module ui2

// Test harness for the VML props golden tests (ui/vml_props*_test.v); it is
// compiled only with `-d vml_props`. A fixture is built twice: by `$vml(...)`,
// and from hand-written props through the same retained runtime calls the
// compiled code makes (owner.element, style, structural rebuild, child layout
// rules, LayoutTree). The resolved trees must be equal on every authored and
// derived field.

interface VmlTestWidget {
	common_props() CommonProps
	validate() !
	build(ctx VmlBuildContext) !Element
	project(el Element, ctx VmlBuildContext) !Element
	child_placement(placement VmlPlacement) VmlPlacement
	child_input(frame Rect, child_count int) !Rect
}

@[params]
struct PCfg {
	id   string
	key  string
	bind bool // a two-way binding gives the compiled element a callback
	// overlays and bound nodes without an id get a generated control id
	generated bool
	children  []PNode
}

struct PNode {
	tag       string
	id        string
	key       string
	bind      bool
	generated bool
	children  []PNode
	common    CommonProps
	container bool
	build     fn (VmlBuildContext) !Element  = unsafe { nil }
	part      fn (VmlBuildContext) !VmlPart  = unsafe { nil }
	placement fn (VmlPlacement) VmlPlacement = unsafe { nil }
	input     fn (Rect, int) !Rect           = unsafe { nil }
	// a named Screen is a managed screen and rebuilds structurally
	screen_named bool
}

fn pn[P](props P, cfg PCfg) PNode {
	mut node := PNode{
		tag:       P.name.all_after_last('.').trim_string_right('Props')
		id:        cfg.id
		key:       cfg.key
		bind:      cfg.bind
		generated: cfg.generated
		children:  cfg.children
	}
	$if P is VmlTestWidget {
		node = PNode{
			...node
			common:    props.common_props()
			build:     fn [props] [P](ctx VmlBuildContext) !Element {
				return vml_build_element(props, ctx)!
			}
			placement: fn [props] [P](placement VmlPlacement) VmlPlacement {
				return props.child_placement(placement)
			}
			input:     fn [props] [P](frame Rect, count int) !Rect {
				return props.child_input(frame, count)!
			}
		}
	}
	$if P is ScreenProps {
		node = PNode{
			...node
			screen_named: props.name != none
		}
	}
	$if P is VmlContainer {
		node = PNode{
			...node
			container: true
		}
	}
	$if P is VmlPartProps {
		node = PNode{
			...node
			part: fn [props] [P](ctx VmlBuildContext) !VmlPart {
				return props.part(ctx)!
			}
		}
	}
	return node
}

const props_structural_tags = ['Accordion', 'AccordionItem', 'TabbedPanel', 'Tab', 'TreeView',
	'TreeNode', 'ScreenManager', 'ManagedScreen', 'ScreenView', 'Carousel', 'ToggleButton',
	'MessageBox', 'ProgressBar', 'Spinner']

const props_unsourced_tags = ['MessageBox', 'ProgressBar', 'Spinner']

struct PHarness {
mut:
	owner &CompiledVmlComponent
}

fn props_identity(id string, path string) string {
	return if id.len > 0 { id } else { '__vml_control_' + path.replace('.', '_') }
}

fn (mut h PHarness) part(n PNode) !VmlPart {
	if n.part == unsafe { nil } { return error('${n.tag} is not a VML part') }
	mut parts := []VmlPart{}
	for child in n.children { parts << h.part(child)! }
	return n.part(VmlBuildContext{
		id:    n.id
		key:   n.key
		parts: parts
		owner: h.owner
	})!
}

// A binding without a handler still gives the compiled element a callback.
fn props_declare(n PNode, ctx VmlBuildContext) !Element {
	el := n.build(ctx)!
	if n.bind && el.on_event == unsafe { nil } {
		return Element{
			...el
			on_event: fn (event ElementEvent) {}
		}
	}
	return el
}

fn (mut h PHarness) node(n PNode, path string, input Rect, placement VmlPlacement) !&CompiledVmlNode {
	if n.build == unsafe { nil } { return error('${n.tag} is not an element') }
	frame := n.common.resolve_frame(input, placement)
	id := if n.id.len > 0 || !(n.bind || n.generated) { n.id } else { props_identity(n.id, path) }
	identity := props_identity(n.id, path)
	layout_parent := n.tag in ['Flex', 'Row', 'Column', 'Grid']
	child_placement := n.placement(placement)
	mut elements := []Element{}
	mut layouts := []VmlLayoutItem{}
	mut parts := []VmlPart{}
	mut visible := 0
	for index, child in n.children {
		if child.build == unsafe { nil } || !n.container {
			parts << h.part(child)!
			continue
		}
		child_path := '${path}.${if layout_parent { visible } else { index }}'
		visible++
		child_input := n.input(frame, n.children.len)!
		mut child_node := h.node(child, child_path, child_input, child_placement)!
		if n.tag in ['Flex', 'Row', 'Column'] {
			child_node.set_child_layout(VmlChildLayout{ flex: child.common.flex_child(Element{}) })!
		} else if n.tag == 'Grid' {
			child_node.set_child_layout(VmlChildLayout{ grid: child.common.grid_span() })!
		}
		elements << child_node.element()
		layouts << child.common.layout_item()
	}
	ctx := VmlBuildContext{
		id:            id
		key:           n.key
		frame:         frame
		children:      elements
		child_layouts: layouts
		parts:         parts
		owner:         h.owner
	}
	declaration := props_declare(n, ctx)!
	authored_width := n.common.width != none
	authored_height := n.common.height != none
	inherited := placement in [.normal, .inherited_preferred]
	mut node := h.owner.element(declaration,
		identity:        identity
		authored_width:  authored_width
		authored_height: authored_height
		inherit_width:   inherited && !authored_width
		inherit_height:  inherited && !authored_height
	)!
	node.set_element_children(declaration.children)!
	style := n.common.style
	styled := style != StylePatch{}
	if styled {
		node.style(fn [style] () !StylePatch {
			return style
		})!
	}
	if n.tag in props_structural_tags || n.screen_named {
		unsourced := n.tag in props_unsourced_tags
		if !unsourced { node.set_sources(elements)! }
		node.structure('@widget', fn [mut node, n, ctx, style, styled, unsourced] () !Element {
			element := node.element()
			children := if unsourced { []Element{} } else { node.child_elements()! }
			rebuilt := props_declare(n, VmlBuildContext{
				...ctx
				key:      element.key
				frame:    node.frame()!
				children: children
			})!
			return if styled { apply_style(rebuilt, style)! } else { rebuilt }
		})!
	}
	return node
}

fn props_document(root PNode, frame Rect) !Element {
	mut h := PHarness{
		owner: new_vml_document('root', VmlDocumentConfig{})!
	}
	node := h.node(root, '0', frame, .normal)!
	element := node.element()
	validate_element_tree(element)!
	mut tree := LayoutTree{}
	tree.replace(element)!
	return tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
}

// Comparison ignores runtime-only fields (mounted paths, retained owners,
// snapshots and motion state). Callbacks compare by presence; metadata by its
// records.
fn props_normal(el Element) Element {
	return Element{
		...el
		mount:               unsafe { nil }
		runtime:             unsafe { nil }
		compiled_node:       unsafe { nil }
		compiled_metadata:   unsafe { nil }
		on_event:            unsafe { nil }
		menu:                el.menu.map(MenuEntry{ ...it, on_select: unsafe { nil } })
		overlay:             if config := el.overlay {
			?&OverlayConfig(&OverlayConfig{
				...config
				on_open:    unsafe { nil }
				on_dismiss: unsafe { nil }
			})
		} else {
			none
		}
		children:            []
	}
}

fn props_set(callback ElementCallback) string {
	return if callback == unsafe { nil } { '-' } else { '+' }
}

fn props_callbacks(el Element) string {
	mut parts := ['on_event${props_set(el.on_event)}']
	for entry in el.menu { parts << 'menu:${entry.id}${props_set(entry.on_select)}' }
	if config := el.overlay {
		parts << 'open${props_set(config.on_open)} dismiss${props_set(config.on_dismiss)}'
	}
	return parts.join(' ')
}

fn props_tree_node(node TreeViewNode) string {
	return '${node.id}|${node.text}|${node.expanded}|${node.selected}|${node.enabled}|${props_set(node.on_event)}${props_set(node.on_toggle)}[${node.children.map(props_tree_node(it)).join(',')}]'
}

fn props_metadata(el Element) string {
	metadata := el.compiled_metadata
	if metadata == unsafe { nil } { return 'none' }
	mut parts := []string{}
	if item := metadata.accordion {
		parts << 'accordion ${item.id}|${item.title}|${item.enabled}|${props_set(item.on_event)}'
	}
	if tab := metadata.tab {
		parts << 'tab ${tab.id}|${tab.title}|${tab.enabled}|${props_set(tab.on_event)}'
	}
	if node := metadata.tree { parts << 'tree ${props_tree_node(node)}' }
	if screen := metadata.screen { parts << 'screen ${screen.name}' }
	if metadata.menu_document { parts << 'menus ${metadata.menus.len}' }
	return parts.join(' ')
}

fn props_diff(compiled Element, props Element, path string, mut out []string) {
	a := props_normal(compiled)
	b := props_normal(props)
	if a != b {
		$for field in Element.fields {
			$if field.name != 'on_event' {
				lv := a.$(field.name)
				rv := b.$(field.name)
				left := '${lv}'
				right := '${rv}'
				if left != right {
					out << '${path}.${field.name}:\n    compiled ${left}\n    props    ${right}'
				}
			}
		}
	}
	if props_callbacks(compiled) != props_callbacks(props) {
		out << '${path} callbacks: compiled ${props_callbacks(compiled)} props ${props_callbacks(props)}'
	}
	if props_metadata(compiled) != props_metadata(props) {
		out << '${path} metadata: compiled ${props_metadata(compiled)} props ${props_metadata(props)}'
	}
	if compiled.children.len != props.children.len {
		out << '${path} children: compiled ${compiled.children.len} props ${props.children.len}'
		return
	}
	for index, child in compiled.children {
		props_diff(child, props.children[index], '${path}/${index}:${child.id}', mut out)
	}
}

fn props_count(el Element) int {
	mut count := 1
	for child in el.children { count += props_count(child) }
	return count
}

fn assert_props_equal(name string, compiled Element, props Element) {
	mut out := []string{}
	props_diff(compiled, props, name, mut out)
	if out.len > 0 {
		for line in out#[..40] { eprintln(line) }
		assert false, '${name}: ${out.len} differences'
	}
	assert props_count(compiled) == props_count(props)
}

fn style_list(patches []StylePatch) StylePatch {
	return compose_styles(patches)
}

struct PropsApp {
pub mut:
	count        int    = 7
	name         string = 'Ada'
	notes        string = 'n'
	agree        bool
	color        string = 'Green'
	level        f64    = 20
	dark         bool
	place        string = 'Work'
	bold         bool   = true
	msg_hidden   bool
	current      int    = 1
	tab          int
	screen       string = 'settings'
	open         bool   = true
	context_open bool
	point        ?OverlayPoint = OverlayPoint{
		x: 5
		y: 6
	}
	backdrop     BoxStyle = BoxStyle{
		bg:     0x101010
		radius: 3
	}
	overlay      OverlayConfig = OverlayConfig{
		kind:             .dialog
		gap:              3
		backdrop_opacity: 0.2
	}
	motion       MotionConfig = MotionConfig{
		reduced_motion: true
	}
	log          []string
}

pub fn (mut a PropsApp) hit(name string) {
	a.log << name
}

fn props_hit(mut app PropsApp, name string) ElementCallback {
	return fn [mut app, name] (event ElementEvent) {
		app.hit(name)
	}
}

fn (a PropsApp) state() string {
	return '${a.count} ${a.name} ${a.notes} ${a.agree} ${a.color} ${a.level} ${a.dark} ${a.place} ${a.bold} ${a.current} ${a.tab} ${a.screen} ${a.open}\n${a.log.join('\n')}'
}

const props_event_kinds = [ElementEventKind.click, .change, .submit, .scroll, .open, .dismiss,
	.pointer_down, .pointer_drag, .pointer_up, .long_press, .swipe_left, .link]

// props_fire sends every event kind to each element callback, context-menu
// entry and overlay callback of a tree, logging where it is sent.
fn props_fire(el Element, path string, mut app PropsApp) {
	if el.on_event != unsafe { nil } {
		for kind in props_event_kinds {
			app.log << '${path} ${kind}'
			el.on_event(ElementEvent{
				kind:    kind
				id:      el.id
				text:    'T${int(kind)}'
				value:   f64(int(kind)) + 0.5
				checked: int(kind) % 2 == 1
				x:       1
				y:       2
			})
		}
	}
	for entry in el.menu {
		if entry.on_select != unsafe { nil } {
			app.log << '${path} menu ${entry.id}'
			entry.on_select(ElementEvent{ kind: .click, id: entry.id })
		}
	}
	if config := el.overlay {
		if config.on_open != unsafe { nil } {
			app.log << '${path} overlay open'
			config.on_open(ElementEvent{ kind: .open, id: el.id })
		}
		if config.on_dismiss != unsafe { nil } {
			app.log << '${path} overlay dismiss'
			config.on_dismiss(ElementEvent{ kind: .dismiss, id: el.id })
		}
	}
	for index, child in el.children {
		props_fire(child, '${path}/${index}', mut app)
	}
}

fn assert_props_events(compiled Element, built Element, mut compiled_app PropsApp, mut props_app PropsApp) {
	props_fire(compiled, '0', mut compiled_app)
	props_fire(built, '0', mut props_app)
	if compiled_app.state() != props_app.state() {
		eprintln('compiled events:\n${compiled_app.state()}\nprops events:\n${props_app.state()}')
	}
	assert compiled_app.state() == props_app.state()
	assert compiled_app.log.len > 0
}
