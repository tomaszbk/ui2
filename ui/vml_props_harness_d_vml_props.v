module ui2

// Test harness for the VML props golden tests (ui/vml_props*_test.v and
// ui/vml_widget_*_test.v); it is compiled only with `-d vml_props`. A fixture
// is built twice: by `$vml(...)`, and from hand-written props declared
// through the generic node runtime (vml_widget_node.v), which retains,
// styles, rebuilds and lays out the nodes. The resolved trees must be equal
// on every authored and derived field.

@[params]
struct PCfg {
	id   string
	key  string
	bind bool // a two-way binding (here a write-back that does nothing)
	// Overlays get a generated control id; the runtime derives it from the
	// props type (`control_id_required`), so this only documents the fixture.
	generated bool
	children  []PNode
}

// PParent is a type-erased parent handle: stored declarations call the
// runtime's generic vml_child with it.
struct PParent {
	handle VmlParent
}

fn (mut p PParent) vml_parent() VmlParent {
	return p.handle
}

struct PNode {
	tag       string
	id        string
	key       string
	bind      bool
	children  []PNode
	element   bool
	container bool
	declare   fn (mut CompiledVmlComponent, ?PParent, VmlNodeOptions, bool) !PParent = unsafe { nil }
}

fn props_no_write[P](p P) ! {}

fn pn[P](props P, cfg PCfg) PNode {
	mut node := PNode{
		tag:      P.name.all_after_last('.').trim_string_right('Props')
		id:       cfg.id
		key:      cfg.key
		bind:     cfg.bind
		children: cfg.children
		declare:  fn [props] [P](mut owner CompiledVmlComponent, parent ?PParent, o VmlNodeOptions, bind bool) !PParent {
			mut n := if handle := parent {
				mut host := PParent{
					handle: handle.handle
				}
				vml_child(mut host, mut owner, props, o)!
			} else {
				vml_root(mut owner, props, o)!
			}
			if bind {
				n.bind('bind', props_no_write[P])!
			}
			return PParent{
				handle: n.vml_parent()
			}
		}
	}
	$if P is VmlElementProps {
		node = PNode{
			...node
			element: true
		}
	}
	$if P is VmlContainer {
		node = PNode{
			...node
			container: true
		}
	}
	return node
}

// Unnamed children of a Flex, Row, Column or Grid are numbered among the
// element children, like the compiled lowering.
fn props_declare(n PNode, mut owner CompiledVmlComponent, parent ?PParent, path string) ! {
	handle := n.declare(mut owner, parent, VmlNodeOptions{
		id:   n.id
		key:  n.key
		path: path
	}, n.bind)!
	layout_parent := n.tag in ['Flex', 'Row', 'Column', 'Grid']
	mut visible := 0
	for index, child in n.children {
		element_child := child.element && n.container
		child_path := '${path}.${if layout_parent && element_child { visible } else { index }}'
		if element_child {
			visible++
		}
		props_declare(child, mut owner, handle, child_path)!
	}
}

fn props_document(root PNode, frame Rect) !Element {
	mut d := vml_document(frame)!
	props_declare(root, mut d.owner, none, '0')!
	return d.finish()!
}

// Comparison ignores runtime-only fields (mounted paths, retained owners,
// snapshots and motion state). Callbacks compare by presence; metadata by its
// records.
fn props_normal(el Element) Element {
	return Element{
		...el
		mounted_generation:  0
		mounted_path:        ''
		mounted_parent_path: ''
		mounted_scroll_id:   ''
		mounted_tooltip_key: ''
		// The reset base of the compiled style effect: the compiled lowering
		// sets it whenever a style is authored, props when it is not empty.
		style_default_box:   none
		// A reactive compiled ProgressBar also writes its value into the
		// view's `value` after an update (a property effect the structural
		// rebuild overwrites at layout); the bar itself draws its fill child.
		value:               if el.accessibility_role == 'progressbar' { 0 } else { el.value }
		layout:              props_normal_layout(el.layout)
		compiled_source:     unsafe { nil }
		motion_state:        unsafe { nil }
		compiled_node:       unsafe { nil }
		compiled_metadata:   unsafe { nil }
		on_event:            unsafe { nil }
		menu:                el.menu.map(MenuEntry{ ...it, on_select: unsafe { nil } })
		overlay:             if config := el.overlay {
			?OverlayConfig(OverlayConfig{
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

// Stack rules default to auto alignment for children without an entry, so a
// list of default rules equals no list (when the runtime last projected the
// rules depends on update order, not on the document).
fn props_normal_layout(layout LayoutSpec) LayoutSpec {
	if layout.stack.children.len > 0
		&& layout.stack.children.all(it.align_x == .auto && it.align_y == .auto) {
		return LayoutSpec{
			...layout
			stack: StackConfig{
				...layout.stack
				children: []
			}
		}
	}
	return layout
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
	current      int = 1
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
