// vtest vflags: -d vml_props
module ui2

// The kit Button built through the generic node runtime: its control height,
// its rebuild on a theme change, and a component whose Button part sends the
// component's events through ctx.emitter to its binding and handlers.

fn test_buttons_are_at_least_their_control_height_in_a_row() ! {
	tree := props_document(pn(RowProps{ align_items: .start },
		children: [
			pn(ButtonProps{ text: 'Save' }, id: 'save'),
			pn(ButtonProps{ text: 'Small', size: .small }, id: 'small'),
			pn(ButtonProps{ text: 'Large', size: .large, icon: .check }, id: 'large'),
			pn(ButtonProps{ icon: .check }, id: 'icon'),
			pn(ButtonProps{ text: 'Short', height: 20 }, id: 'short'),
		]
	), rect(0, 0, 600, 100))!
	assert tree.children.map(it.frame.height) == [32.0, 24, 40, 32, 20]
	save := tree.children[0]
	assert save.button_behavior && save.accessibility_label == 'Save'
	assert save.layout.flex.orientation == .horizontal
	assert save.children.len == 1 && save.children[0].text == 'Save'
	// The icon-only button is shorter than its control height without the
	// floor: its icon and padding leave room.
	t := kit_tokens(default_theme())
	m := t.metrics(.medium)
	assert m.icon + 2 * m.padding_y < m.height
	assert tree.children[2].children.len == 2
	assert tree.children[2].children[0].accessibility_role == 'img'
}

fn test_button_variants_take_their_colors_from_the_tokens() ! {
	tree := props_document(pn(RowProps{ align_items: .start },
		children: [
			pn(ButtonProps{ text: 'Primary', variant: .primary }, id: 'primary'),
			pn(ButtonProps{ text: 'Ghost', variant: .ghost }, id: 'ghost'),
			pn(ButtonProps{ text: 'Off', variant: .danger, enabled: false }, id: 'off'),
			pn(ButtonProps{ text: 'Wait', loading: true }, id: 'wait'),
		]
	), rect(0, 0, 600, 100))!
	t := kit_tokens(default_theme())
	primary := tree.children[0]
	assert primary.box.bg == t.accent && !primary.box.transparent
	assert primary.children[0].text_style.color == t.on_accent
	ring := primary.interaction_style.focus.outline_color or { 0 }
	assert ring == t.focus_ring
	ghost := tree.children[1]
	assert ghost.box.transparent && ghost.box.border_left == 0
	off := tree.children[2]
	assert !off.enabled && off.children[0].text_style.color == t.disabled_text
	assert off.interaction_style == InteractionStyle{}
	wait := tree.children[3]
	assert wait.children[0].accessibility_role == 'progressbar'
	assert wait.on_event != unsafe { nil }
}

fn test_a_theme_change_rebuilds_the_button() ! {
	tree := props_document(pn(ColumnProps{ align_items: .start },
		children: [
			pn(ButtonProps{ text: 'Save' }, id: 'save'),
		]
	), rect(0, 0, 300, 100))!
	mut root := tree.compiled_node
	root.mount()!
	light := kit_tokens(default_theme())
	dark := kit_tokens(dark_theme())
	before := root.element().children[0]
	assert before.box.bg == light.surface_muted
	assert before.children[0].text_style.color == light.text
	set_vml_theme(tree, dark_theme())!
	after := root.element().children[0]
	assert after.box.bg == dark.surface_muted
	assert after.children[0].text_style.color == dark.text
	assert after.compiled_node == before.compiled_node
	root.dispose_document()!
}

@[heap]
struct KitButtonLog {
mut:
	lines []string
}

// KitCounterProps is a component in the kit's shape: its Button part sends
// the component's change through ctx.emitter, and `value` is bindable.
struct KitCounterProps {
	CommonProps
pub mut:
	value int
}

pub fn (p KitCounterProps) vml_themed() {}

pub fn (p KitCounterProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (mut p KitCounterProps) apply_event(event ElementEvent) {
	if event.kind == .change {
		p.value = int(event.value)
	}
}

pub fn (p KitCounterProps) build(ctx VmlBuildContext) !Element {
	emitter := ctx.emitter(p.element_callback())
	next := f64(p.value + 1)
	increment := kit_button(ctx, 'increment', ButtonProps{
		text:     '${p.value}'
		on_click: fn [emitter, next] (event ElementEvent) {
			emitter.emit(ElementEvent{
				kind:  .change
				id:    event.id
				value: next
			})
		}
	})!
	return vml_handled(view(ctx.id, ctx.frame, BoxStyle{}, [increment]), ctx, p.element_callback())
}

fn test_a_part_emits_through_the_bind_and_the_handlers() ! {
	mut log := &KitButtonLog{}
	mut d := vml_document(rect(0, 0, 300, 100))!
	mut owner := d.owner
	mut root := vml_root(mut owner, ColumnProps{ align_items: .start }, id: 'root', path: '0')!
	mut counter := vml_child(mut root, mut owner, KitCounterProps{
		width:     120
		height:    40
		on_change: fn [mut log] (event ElementEvent) {
			log.lines << 'change ${event.id} ${event.target} ${event.value}'
		}
	}, id: 'counter', path: '0.0')!
	counter.bind('value', fn [mut log] (p KitCounterProps) ! {
		log.lines << 'bind ${p.value}'
	})!
	tree := d.finish()!
	mut node := tree.compiled_node
	node.mount()!
	button := node.element().children[0].children[0]
	assert button.id.ends_with('counter__increment')
	assert button.children[0].text == '0'
	button.on_event(ElementEvent{ kind: .click, id: button.id })
	assert log.lines == ['bind 1', 'change counter ${button.id} 1.0']
	assert node.element().children[0].children[0].children[0].text == '1'
	node.dispose_document()!
}
