// vtest vflags: -d vml_props -d vml_fixtures
module ui2

// vml: ../tests/compiled_vml/motion.vml

// Motion and transform properties of a component root
// (tests/compiled_vml/motion.vml) against the compiled lowering, and the
// commit fast paths: common properties no build reads are projected onto the
// retained element, layout items only change the child rule, and changes in
// one batch commit once.

pub struct WMotionApp {
pub mut:
	alpha  f64 = 0.8
	offset f64
	hidden bool
	config MotionConfig = MotionConfig{
		reduced_motion: true
	}
}

fn w_motion_compiled(mut app WMotionApp) Element {
	return motion_vml_framed(mut app, rect(0, 0, 160, 80))
}

fn w_motion_generic(mut app WMotionApp) !Element {
	mut d := vml_document(rect(0, 0, 160, 80))!
	mut owner := d.owner
	mut c := owner.child('0')!
	mut title := c.state_factory('title', fn () !string {
		return 'Motion'
	})!
	mut count := c.state_factory('count', fn () !int {
		return 0
	})!
	mut body := vml_root(mut c, ColumnProps{ width: 120, height: 60 }, id: 'body', path: '0.root')!
	body.prop('opacity', fn [mut app, mut c] (mut p ColumnProps) ! {
		c.watch_app()!
		p.opacity = app.alpha
	})!
	body.prop('motion', fn [mut app, mut c] (mut p ColumnProps) ! {
		c.watch_app()!
		p.motion = app.config
	})!
	body.prop('translate_x', fn [mut app, mut c] (mut p ColumnProps) ! {
		c.watch_app()!
		p.translate_x = app.offset
	})!
	body.prop('hidden', fn [mut app, mut c] (mut p ColumnProps) ! {
		c.watch_app()!
		p.hidden = app.hidden
	})!
	mut button := vml_child(mut body, mut c, ButtonProps{
		width:    100
		height:   30
		on_click: c.callback(fn [mut count] (event ElementEvent) ! {
			count.set(count.get()! + 1)!
		})
	}, id: 'increment', path: '0.root.0')!
	button.prop('text', fn [mut count] (mut p ButtonProps) ! {
		p.text = count.get()!
	})!
	mut caption := vml_child(mut body, mut c, LabelProps{ width: 100, height: 20 },
		path: '0.root.1'
	)!
	caption.prop('text', fn [mut title] (mut p LabelProps) ! {
		p.text = title.get()!
	})!
	return d.finish()!
}

fn test_generic_motion_and_transforms_match_compiled_vml() {
	mut compiled_app := WMotionApp{}
	mut generic_app := WMotionApp{}
	compiled := w_motion_compiled(mut compiled_app)
	generic := w_motion_generic(mut generic_app)!
	assert_props_equal('motion', compiled, generic)
	mut compiled_root := compiled.compiled_node
	mut generic_root := generic.compiled_node
	compiled_root.mount()!
	generic_root.mount()!
	compiled_root.element().children[0].on_event(ElementEvent{ kind: .click })
	generic_root.element().children[0].on_event(ElementEvent{ kind: .click })
	button := generic_root.element().children[0]
	assert button.text == '1'
	compiled_app.alpha = 0.25
	compiled_app.offset = 42
	compiled_app.hidden = true
	generic_app = compiled_app
	compiled_root.component.invalidate_app()!
	generic_root.component.invalidate_app()!
	changed := generic_root.element()
	assert changed.opacity == 0.25 && changed.translate_x == 42 && changed.hidden
	assert changed.children[0].compiled_node == button.compiled_node
	assert_props_equal('motion changed', compiled_root.element(), generic_root.element())
	compiled_app.hidden = false
	compiled_app.config = MotionConfig{
		reduced_motion: false
	}
	generic_app = compiled_app
	compiled_root.component.invalidate_app()!
	generic_root.component.invalidate_app()!
	assert_props_equal('motion restored', compiled_root.element(), generic_root.element())
	compiled_root.dispose_document()!
	generic_root.dispose_document()!
	assert generic_root.component.runtime.stats() == SignalStats{}
}

@[heap]
struct WBuilds {
mut:
	count int
}

// WCountingProps counts its builds.
pub struct WCountingProps {
	CommonProps
pub mut:
	text   string
	builds &WBuilds = unsafe { nil }
}

pub fn (p WCountingProps) build(ctx VmlBuildContext) !Element {
	mut builds := p.builds
	builds.count++
	return vml_handled(label(ctx.id, p.text, ctx.frame, TextStyle{}), ctx, p.element_callback())
}

struct WFastState {
mut:
	opacity f64 = 1
	grow    f64
	text    string = 'a'
	cursor  string
}

fn w_fast_document(initial WFastState, builds &WBuilds) !(&Signal[WFastState], Element) {
	mut d := vml_document(rect(0, 0, 200, 100))!
	mut owner := d.owner
	mut source := owner.state('state', initial)!
	mut row := vml_root(mut owner, RowProps{}, id: 'row', path: '0')!
	mut leaf := vml_child(mut row, mut owner, WCountingProps{
		builds: builds
	}, id: 'leaf', path: '0.0')!
	leaf.prop('opacity', fn [mut source] (mut p WCountingProps) ! {
		p.opacity = source.get()!.opacity
	})!
	leaf.prop('flex_grow', fn [mut source] (mut p WCountingProps) ! {
		p.flex_grow = source.get()!.grow
	})!
	leaf.prop('text', fn [mut source] (mut p WCountingProps) ! {
		p.text = source.get()!.text
	})!
	leaf.prop('cursor', fn [mut source] (mut p WCountingProps) ! {
		cursor := source.get()!.cursor
		p.cursor = if cursor.len > 0 { cursor } else { none }
	})!
	vml_child(mut row, mut owner, LabelProps{ text: 'sibling' }, path: '0.1')!
	element := d.finish()!
	return source, element
}

fn test_generic_commits_use_fast_paths_and_coalesce_per_batch() {
	mut builds := &WBuilds{}
	mut state, element := w_fast_document(WFastState{}, builds)!
	mut root := element.compiled_node
	assert builds.count == 1
	// An unchanged value commits nothing.
	state.set(WFastState{})!
	assert builds.count == 1
	// Common properties no build reads: projected, not rebuilt.
	state.set(WFastState{ opacity: 0.5, cursor: 'pointer' })!
	assert builds.count == 1
	assert root.element().children[0].opacity == 0.5
	assert root.element().children[0].cursor == 'pointer'
	// A layout item only changes the child rule.
	state.set(WFastState{ opacity: 0.5, cursor: 'pointer', grow: 2 })!
	assert builds.count == 1
	assert root.element().layout.flex_rules[0].grow == 2
	// A built property rebuilds once, also with other changes in the batch.
	mut runtime := root.component.runtime
	runtime.batch(fn [mut state] () ! {
		state.set(WFastState{ opacity: 0.25, cursor: 'pointer', grow: 2, text: 'b' })!
		state.set(WFastState{ opacity: 0.75, cursor: 'text', grow: 1, text: 'c' })!
	})!
	assert builds.count == 2
	// Every path ends where a fresh build with the final values starts.
	final := WFastState{
		opacity: 0.75
		cursor:  'text'
		grow:    1
		text:    'c'
	}
	fresh_builds := &WBuilds{}
	_, fresh := w_fast_document(final, fresh_builds)!
	assert_props_equal('fast paths', fresh.compiled_node.element(), root.element())
	// A fast field that becomes absent restores the constructor default.
	state.set(WFastState{ ...final, cursor: '' })!
	assert root.element().children[0].cursor == ''
	assert builds.count == 3
	fresh.compiled_node.dispose_document()!
	root.dispose_document()!
	assert root.component.runtime.stats() == SignalStats{}
}
