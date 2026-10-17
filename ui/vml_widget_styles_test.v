// vtest vflags: -d vml_props
module ui2

// Named, inline and reactive styles with theme tokens, on plain elements and
// on generated widgets with parts (tests/compiled_vml/styles.vml), written by
// hand in the shape of the generic lowering. Value, style and theme changes
// keep both documents equal.

pub struct WStylesApp {
pub mut:
	emphasized bool
	patch      StylePatch
	progress   f64    = 0.25
	choice     string = 'One'
}

fn w_styles_compiled(mut app WStylesApp) Element {
	return $vml('../tests/compiled_vml/styles.vml', rect(0, 0, 300, 240))
}

// style card = [background(color.surface), padding(spacing.medium), radius(radius.medium)]
fn w_card(mut owner CompiledVmlComponent) !StylePatch {
	return compose_styles([style_background(owner.color_token('surface')!),
		style_padding(owner.spacing_token('medium')!), style_radius(owner.radius_token('medium')!)])
}

fn w_styles_generic(mut app WStylesApp) !Element {
	mut d := vml_document(rect(0, 0, 300, 240))!
	mut owner := d.owner
	owner.prepare_theme_tokens(['color:surface', 'spacing:medium', 'radius:medium', 'color:accent',
		'color:text', 'font_size:body'])!
	mut n_0 := vml_root(mut owner, ColumnProps{ spacing: 8, width: 300, height: 240 }, path: '0')!
	mut named := vml_child(mut n_0, mut owner, ViewProps{ width: 160, height: 60 },
		id:   'named'
		path: '0.0'
	)!
	named.prop('style', fn [mut owner] (mut p ViewProps) ! {
		p.style = compose_styles([w_card(mut owner)!, style_background(owner.color_token('accent')!)])
	})!
	mut text := vml_child(mut named, mut owner, LabelProps{
		text:   'Contenido'
		width:  100
		height: 20
	}, path: '0.0.0')!
	text.prop('style', fn [mut owner] (mut p LabelProps) ! {
		p.style = compose_styles([style_foreground(owner.color_token('text')!),
			style_font_size(owner.font_size_token('body')!)])
	})!
	mut inline := vml_child(mut n_0, mut owner, ViewProps{
		width:  160
		height: 60
		style:  compose_styles([style_background(0x112233), style_padding(12), style_radius(8)])
	}, id: 'inline', path: '0.1')!
	vml_child(mut inline, mut owner, LabelProps{ text: 'Inline', width: 100, height: 20 },
		path: '0.1.0'
	)!
	mut variant := vml_child(mut n_0, mut owner, ViewProps{ width: 160, height: 60 },
		id:   'variant'
		path: '0.2'
	)!
	variant.prop('style', fn [mut app, mut owner] (mut p ViewProps) ! {
		owner.watch_app()!
		chosen := if app.emphasized {
			compose_styles([w_card(mut owner)!, style_background(owner.color_token('accent')!),
				style_radius(0)])
		} else {
			w_card(mut owner)!
		}
		p.style = compose_styles([chosen, app.patch])
	})!
	mut button := vml_child(mut variant, mut owner, ButtonProps{
		text:   'Cambiar'
		width:  100
		height: 30
	}, path: '0.2.0')!
	button.prop('style', fn [mut owner] (mut p ButtonProps) ! {
		p.style = compose_styles([
			style_hover([style_background(owner.color_token('accent')!), style_foreground(0x000000)])!,
			style_pressed([style_radius(0)])!,
		])
	})!
	mut progress := vml_child(mut n_0, mut owner, ProgressBarProps{
		width:  160
		height: 20
		max:    1
	}, id: 'progress', path: '0.3')!
	progress.prop('value', fn [mut app, mut owner] (mut p ProgressBarProps) ! {
		owner.watch_app()!
		p.value = app.progress
	})!
	progress.prop('style', fn [mut app, mut owner] (mut p ProgressBarProps) ! {
		owner.watch_app()!
		p.style = if app.emphasized {
			compose_styles([style_background(0x112233), style_foreground(0x445566), style_radius(8)])
		} else {
			compose_styles([])
		}
	})!
	mut spinner := vml_child(mut n_0, mut owner, SpinnerProps{
		width:  160
		height: 30
		style:  compose_styles([style_background(0x112233), style_foreground(0xffffff),
			style_font_size(18), style_radius(0)])
	}, path: '0.4')!
	spinner.prop('text', fn [mut app, mut owner] (mut p SpinnerProps) ! {
		owner.watch_app()!
		p.text = app.choice
	})!
	vml_child(mut spinner, mut owner, OptionProps{ text: 'One' }, path: '0.4.0')!
	vml_child(mut spinner, mut owner, OptionProps{ text: 'Two' }, path: '0.4.1')!
	mut caption := vml_child(mut n_0, mut owner, LabelProps{
		text:   'Removable typography'
		width:  160
		height: 30
	}, path: '0.5')!
	caption.prop('style', fn [mut app, mut owner] (mut p LabelProps) ! {
		owner.watch_app()!
		p.style = if app.emphasized {
			compose_styles([style_foreground(0xff0000), style_font_size(30), style_weight(700),
				style_italic(true)])
		} else {
			compose_styles([])
		}
	})!
	return d.finish()!
}

fn test_generic_styles_tokens_and_generated_widgets_match_compiled_vml() {
	mut compiled_app := WStylesApp{}
	mut generic_app := WStylesApp{}
	compiled := w_styles_compiled(mut compiled_app)
	generic := w_styles_generic(mut generic_app)!
	assert_props_equal('styles', compiled, generic)
	mut compiled_root := compiled.compiled_node
	mut generic_root := generic.compiled_node
	compiled_root.mount()!
	generic_root.mount()!
	before := generic_root.element()
	mut compiled_owner := compiled_root.component
	mut generic_owner := generic_root.component
	// Reactive style variants, a composite value and a part-backed value.
	compiled_app.emphasized = true
	compiled_app.patch = compose_styles([style_background(0), style_radius(0)])
	compiled_app.progress = 0.75
	compiled_app.choice = 'Two'
	generic_app = compiled_app
	compiled_owner.invalidate_app()!
	generic_owner.invalidate_app()!
	after := generic_root.element()
	assert after.children[2].box.bg == 0
	assert after.children[2].compiled_node == before.children[2].compiled_node
	assert after.children[3].compiled_node == before.children[3].compiled_node
	assert after.children[4].text == 'Two'
	assert_props_equal('styles emphasized', compiled_root.element(), generic_root.element())
	// Theme tokens are reactive sources of the style properties.
	theme := Theme{
		colors:  {
			'surface': u32(0x445566)
			'accent':  u32(0x778899)
			'text':    u32(0x222222)
		}
		spacing: {
			'medium': f64(6)
		}
	}
	compiled_owner.set_theme(theme)!
	generic_owner.set_theme(theme)!
	assert generic_root.element().children[0].box.bg == 0x778899
	assert_props_equal('styles theme', compiled_root.element(), generic_root.element())
	// Removed variants restore the constructor defaults.
	compiled_app.emphasized = false
	compiled_app.patch = StylePatch{}
	generic_app = compiled_app
	compiled_owner.invalidate_app()!
	generic_owner.invalidate_app()!
	assert generic_root.element().children[5].text_style == TextStyle{}
	assert generic_root.element().children[3].box.bg == 0xe2e8f0
	assert_props_equal('styles plain', compiled_root.element(), generic_root.element())
	compiled_root.dispose_document()!
	generic_root.dispose_document()!
	assert generic_owner.runtime.stats() == SignalStats{}
}
