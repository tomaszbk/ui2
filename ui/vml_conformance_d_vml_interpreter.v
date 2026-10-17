module ui2

import os

// The conformance check between compiled and interpreted VML (design §3.6),
// compiled only with `-d vml_interpreter`. A document is built twice against
// the same model, once by `$vml(...)` and once by the interpreter; both
// builds then receive the same scripted events. The resolved element trees
// before and after the events, the event log and the model state must be
// equal. Compiled VML is the source of truth: the interpreter may accept
// programs V rejects, never the reverse.

// VmlConformance describes one document to check.
@[params]
pub struct VmlConformance[T] {
pub:
	// The document file; the interpreter reads it, `compiled` embeds it.
	path  string
	frame Rect = Rect{
		width:  640
		height: 480
	}
	// The model both builds use. `reset` restores its initial state before
	// each build, so external callbacks may keep using a global model.
	model &T         = unsafe { nil }
	reset fn (mut T) = unsafe { nil }
	// Builds the document with `$vml(path, frame)`.
	compiled fn (mut T, Rect) Element = unsafe { nil }
	// The compiled build follows the viewport (`$vml(path)` without a
	// frame); `frame` is then the viewport both builds start in.
	follow_viewport bool
	// The external callbacks the document names, as the compiled build sees
	// them (`callback_save` and so on).
	callbacks map[string]ElementCallback
	// The model state compared after the events; by default its V string.
	state fn (&T) string = unsafe { nil }
	// The application theme both documents start with (as run_compiled_vml's
	// `theme`).
	theme ?Theme
	// Send the scripted events.
	events bool = true
}

// VmlConformanceReport is the result of one check.
pub struct VmlConformanceReport {
pub:
	path string
	// Elements in the built tree.
	elements int
	// Events sent to each build.
	events int
	// Every difference, as `where: compiled ... interpreted ...`.
	differences []string
}

pub fn (r VmlConformanceReport) equal() bool {
	return r.differences.len == 0
}

pub fn (r VmlConformanceReport) str() string {
	if r.equal() {
		return '${os.file_name(r.path)}: equal (${r.elements} elements, ${r.events} events)'
	}
	return '${os.file_name(r.path)}: ${r.differences.len} difference(s)\n' +
		r.differences#[..40].join('\n')
}

struct VmlConformanceRun {
mut:
	before   []VmlConformanceNode
	after    []VmlConformanceNode
	log      []string
	state    string
	disposed string
}

struct VmlConformanceNode {
	path   string
	fields []string
}

// vml_conformance builds the document both ways and compares the results.
pub fn vml_conformance[T](c VmlConformance[T]) !VmlConformanceReport {
	if c.model == unsafe { nil } { return error('vml_conformance requires a model') }
	if c.compiled == unsafe { nil } { return error('vml_conformance requires the compiled build') }
	source := os.read_file(c.path)!
	compiled := vml_conformance_run(c, '')!
	interpreted := vml_conformance_run(c, source)!
	mut out := []string{}
	vml_conformance_trees('built', compiled.before, interpreted.before, mut out)
	vml_conformance_lines('events', compiled.log, interpreted.log, mut out)
	vml_conformance_trees('after events', compiled.after, interpreted.after, mut out)
	if compiled.state != interpreted.state {
		out << 'model after events:\n    compiled    ${compiled.state}\n    interpreted ${interpreted.state}'
	}
	if compiled.disposed != interpreted.disposed {
		out << 'model after disposal:\n    compiled    ${compiled.disposed}\n    interpreted ${interpreted.disposed}'
	}
	return VmlConformanceReport{
		path:        c.path
		elements:    compiled.before.len
		events:      compiled.log.len
		differences: out
	}
}

fn vml_conformance_state[T](c VmlConformance[T]) string {
	if c.state != unsafe { nil } { return c.state(c.model) }
	return '${*c.model}'
}

fn vml_conformance_run[T](c VmlConformance[T], source string) !VmlConformanceRun {
	mut model := unsafe { c.model }
	if c.reset != unsafe { nil } { c.reset(mut model) }
	mut runtime := compiled_vml_runtime()
	runtime.initial_theme = c.theme
	mut frame := ?Rect(c.frame)
	if c.follow_viewport {
		runtime.initial_bounds = c.frame
		frame = none
	}
	element := if source.len == 0 {
		c.compiled(mut model, c.frame)
	} else {
		vml_interpret(source, model,
			path:      c.path
			frame:     frame
			callbacks: c.callbacks
			theme:     c.theme
		) or {
			runtime.initial_theme = none
			runtime.initial_bounds = none
			return err
		}
	}
	runtime.initial_theme = none
	runtime.initial_bounds = none
	mut root := element.compiled_node
	if root == unsafe { nil } { return error('${c.path}: the build has no retained node') }
	root.mount()!
	mut run := VmlConformanceRun{}
	vml_conformance_flatten(root.element(), '0', mut run.before)
	if c.events {
		// The scripted events come from a window of their own, which never runs,
		// so that callbacks reach a window as they do in a running application.
		mut app := new_app()
		window := app.new_window(
			title: 'VML conformance'
			build: fn (mut _ Window) Element { return Element{} }
		)!
		vml_conformance_fire(root.element(), '0', window, mut run.log)
		root.component.invalidate_app()!
		root.mount()!
	}
	vml_conformance_flatten(root.element(), '0', mut run.after)
	run.state = vml_conformance_state(c)
	root.dispose_document()!
	run.disposed = vml_conformance_state(c)
	return run
}

// The event kinds sent to every element callback, in order.
const vml_conformance_event_kinds = [ElementEventKind.click, .change, .submit, .scroll, .open,
	.dismiss, .pointer_down, .pointer_drag, .pointer_up, .long_press, .swipe_left, .link]

// vml_conformance_fire sends every event kind to each element callback,
// context-menu entry and overlay callback of the tree, in tree order.
fn vml_conformance_fire(el Element, path string, window &Window, mut log []string) {
	if el.on_event != unsafe { nil } {
		for kind in vml_conformance_event_kinds {
			log << '${path} ${el.id} ${kind}'
			el.on_event(ElementEvent{
				window:  window
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
			log << '${path} menu ${entry.id}'
			entry.on_select(ElementEvent{ window: window, kind: .click, id: entry.id })
		}
	}
	if config := el.overlay {
		if config.on_open != unsafe { nil } {
			log << '${path} overlay open'
			config.on_open(ElementEvent{ window: window, kind: .open, id: el.id })
		}
		if config.on_dismiss != unsafe { nil } {
			log << '${path} overlay dismiss'
			config.on_dismiss(ElementEvent{ window: window, kind: .dismiss, id: el.id })
		}
	}
	for index, child in el.children {
		vml_conformance_fire(child, '${path}/${index}', window, mut log)
	}
}

fn vml_conformance_flatten(el Element, path string, mut out []VmlConformanceNode) {
	out << VmlConformanceNode{
		path:   '${path}:${el.id}'
		fields: vml_conformance_fields(el)
	}
	for index, child in el.children {
		vml_conformance_flatten(child, '${path}/${index}', mut out)
	}
}

// Fields that are runtime state rather than the resolved declaration: the
// mount and runtime records, the retained owner, and the children (compared
// one by one).
fn vml_conformance_skipped(name string) bool {
	return name in ['children', 'compiled_node', 'mount', 'runtime']
}

fn vml_conformance_set(callback ElementCallback) string {
	return if callback == unsafe { nil } { '-' } else { '+' }
}

// vml_conformance_fields renders the compared fields of one element. Fields
// are found by reflection, so the check follows Element as it changes.
// Callbacks compare by presence and metadata by its records. A Checkbox's
// accessibility value is derived from `checked` (compared): the compiled lowering's
// property effect patches `checked` alone and leaves the value computed at
// build time, while the generic runtime rebuilds both.
fn vml_conformance_fields(el Element) []string {
	mut out := []string{}
	$for field in Element.fields {
		if !vml_conformance_skipped(field.name) {
			$if field.typ is ElementCallback {
				callback := el.$(field.name)
				out << '${field.name}=${vml_conformance_set(callback)}'
			} $else $if field.name == 'menu' {
				out << vml_conformance_menu_entries(el)
			} $else $if field.name == 'overlay' {
				out << vml_conformance_overlay(el)
			} $else $if field.name == 'compiled_metadata' {
				out << 'metadata=${vml_conformance_metadata(el)}'
			} $else $if field.name == 'layout' {
				out << 'layout=${vml_conformance_layout(el.layout)}'
			} $else $if field.name == 'accessibility_value' {
				if el.accessibility_role != 'checkbox' {
					out << 'accessibility_value=${el.accessibility_value}'
				}
			} $else {
				value := el.$(field.name)
				out << '${field.name}=${value}'
			}
		}
	}
	return out
}

fn vml_conformance_menu_entries(el Element) string {
	return 'menu=[${el.menu.map('${it.id}|${it.title}|${vml_conformance_set(it.on_select)}').join(', ')}]'
}

fn vml_conformance_overlay(el Element) string {
	config := el.overlay or { return 'overlay=none' }
	normalized := OverlayConfig{
		...*config
		on_open:    unsafe { nil }
		on_dismiss: unsafe { nil }
	}
	return 'overlay=${normalized} open${vml_conformance_set(config.on_open)} dismiss${vml_conformance_set(config.on_dismiss)}'
}

// Stack rules default to auto alignment for children without an entry, so a
// list of default rules equals no list.
fn vml_conformance_layout(layout LayoutSpec) LayoutSpec {
	if layout.stack_rules.len > 0
		&& layout.stack_rules.all(it.align_x == .auto && it.align_y == .auto) {
		return LayoutSpec{
			...layout
			stack_rules: []
		}
	}
	return layout
}

fn vml_conformance_metadata(el Element) string {
	metadata := el.compiled_metadata
	if metadata == unsafe { nil } { return 'none' }
	mut parts := []string{}
	if screen := metadata.screen { parts << 'screen ${screen.name}' }
	if metadata.menu_document {
		parts << 'menus ${vml_conformance_menus(metadata.menus).join(' ')}'
	}
	for record in metadata.records { parts << 'record ${vml_record_text(record)}' }
	return parts.join(' ')
}

// vml_conformance_menus renders application menus with callbacks by presence.
pub fn vml_conformance_menus(menus []Menu) []string {
	return menus.map(vml_conformance_menu(it))
}

fn vml_conformance_menu(menu Menu) string {
	mut parts := []string{}
	for item in menu.items {
		parts << vml_conformance_menu_item(item)
	}
	return '${menu.title}{${parts.join(', ')}}'
}

fn vml_conformance_menu_item(item MenuItem) string {
	normalized := MenuItem{
		...item
		on_select: unsafe { nil }
		items:     []
	}
	return '${normalized} select${vml_conformance_set(item.on_select)} [${item.items.map(vml_conformance_menu_item(it)).join(', ')}]'
}

fn vml_conformance_trees(stage string, compiled []VmlConformanceNode, interpreted []VmlConformanceNode, mut out []string) {
	if compiled.len != interpreted.len {
		out << '${stage}: compiled has ${compiled.len} elements, interpreted ${interpreted.len}'
	}
	for index in 0 .. if compiled.len < interpreted.len { compiled.len } else { interpreted.len } {
		a := compiled[index]
		b := interpreted[index]
		if a.path != b.path {
			out << '${stage} element ${index}: compiled ${a.path}, interpreted ${b.path}'
			return
		}
		for field_index, field in a.fields {
			other := if field_index < b.fields.len { b.fields[field_index] } else { '' }
			if field != other {
				out << '${stage} ${a.path}:\n    compiled    ${field}\n    interpreted ${other}'
			}
		}
	}
}

fn vml_conformance_lines(stage string, compiled []string, interpreted []string, mut out []string) {
	for index in 0 .. if compiled.len > interpreted.len { compiled.len } else { interpreted.len } {
		a := if index < compiled.len { compiled[index] } else { '(none)' }
		b := if index < interpreted.len { interpreted[index] } else { '(none)' }
		if a != b {
			out << '${stage} ${index}: compiled ${a}, interpreted ${b}'
			return
		}
	}
}

// vml_conformance_menu_document compares a compiled menu document (`$vml`
// of a MenuBar or Menu, which returns the menus) with the interpreted one.
pub fn vml_conformance_menu_document(path string, compiled []Menu, callbacks map[string]ElementCallback) !VmlConformanceReport {
	source := os.read_file(path)!
	element := vml_interpret_model(source, vml_sample_model(map[string]VmlValue{}, none),
		path:      path
		callbacks: callbacks
	)!
	interpreted := menus(element)!
	a := vml_conformance_menus(compiled)
	b := vml_conformance_menus(interpreted)
	mut out := []string{}
	vml_conformance_lines('menus', a, b, mut out)
	if a.len != b.len { out << 'menus: compiled ${a.len}, interpreted ${b.len}' }
	if element.compiled_node != unsafe { nil } { element.compiled_node.dispose_document()! }
	return VmlConformanceReport{
		path:        path
		elements:    a.len
		differences: out
	}
}
