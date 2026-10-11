module main

import ui2

pub struct StylesContractApp {
pub mut:
	emphasized      bool
	patch           ui2.StylePatch
	startup_color   u32
	startup_padding f64
	startup_size    f64
	progress        f64    = 0.25
	choice          string = 'One'
}

fn styles_tree(mut app StylesContractApp) ui2.Element {
	return $vml('styles.vml', ui2.rect(0, 0, 300, 240))
}

fn local_styles_tree(mut app StylesContractApp) ui2.Element {
	return $vml('styles_local.vml', ui2.rect(0, 0, 300, 200))
}

fn startup_styles_tree(mut app StylesContractApp) ui2.Element {
	initial := $vml('styles_custom_tokens.vml', ui2.rect(0, 0, 300, 200))
	app.startup_color = initial.box.bg
	app.startup_padding = initial.layout.stack.padding.left
	app.startup_size = initial.children[0].text_style.size
	// Stop at the runner's validation stage, before opening a platform window.
	return ui2.Element{
		...initial
		children: [
			ui2.Element{ kind: .label, id: 'duplicate' },
			ui2.Element{ kind: .label, id: 'duplicate' },
		]
	}
}

fn test_application_theme_is_available_before_custom_token_consumers_are_built() ! {
	mut app := &StylesContractApp{}
	ui2.run_compiled_vml(ui2.CompiledVmlRunConfig[StylesContractApp]{
		model: app
		build: startup_styles_tree
		theme: ui2.Theme{
			colors:     {
				'brand': u32(0x445566)
			}
			spacing:    {
				'gutter': f64(7)
			}
			radii:      {
				'card': f64(5)
			}
			font_sizes: {
				'brand': f64(19)
			}
		}
	}) or {
		assert err.msg().contains('duplicate')
		assert app.startup_color == 0x445566
		assert app.startup_padding == 7
		assert app.startup_size == 19
		// Failed startup must release its theme context before the next document.
		mut owner := ui2.new_vml_document('after themed startup')!
		assert owner.color_token('surface')! == 0xffffff
		owner.color_token('brand') or {
			assert err.msg().contains('unknown color token')
			owner.dispose()!
			return
		}
		assert false, 'startup theme leaked into a later document'
	}
	assert false, 'the duplicate-id fixture unexpectedly reached the platform runner'
}

fn test_named_inline_and_typed_styles_compose_and_react_without_replacing_nodes() ! {
	mut app := &StylesContractApp{}
	initial := styles_tree(mut app)
	mut root := initial.compiled_node
	root.mount()!
	mut owner := root.component
	before := root.element()
	assert before.children[0].box.bg == 0x2563eb
	assert before.children[0].box.radius == 8
	assert before.children[0].layout.stack.padding.left == 12
	assert initial.children[0].children[0].frame.x == 12
	assert initial.children[0].children[0].frame.y == 12
	assert before.children[1].box.bg == 0x112233
	assert before.children[1].box.radius == 8
	assert before.children[2].box.bg == 0xffffff
	app.emphasized = true
	app.patch = ui2.compose_styles([ui2.style_background(0), ui2.style_radius(0)])
	owner.invalidate_app()!
	after := root.element()
	assert after.children[2].box.bg == 0
	assert after.children[2].box.radius == 0
	assert after.children[2].compiled_node == before.children[2].compiled_node
	assert after.children[2].children[0].interaction_style.hover.bg == ?u32(0x2563eb)
	app.emphasized = false
	app.patch = ui2.StylePatch{}
	owner.invalidate_app()!
	assert root.element().children[2].box.bg == 0xffffff
	assert root.element().children[2].box.radius == 8
	root.dispose_document()!
	assert owner.runtime.stats() == ui2.SignalStats{}
}

fn test_local_styles_keep_instance_state_and_inherit_theme_overrides() ! {
	mut app := &StylesContractApp{}
	initial := local_styles_tree(mut app)
	mut root := initial.compiled_node
	root.mount()!
	mut owner := root.component
	before := root.element()
	first := before.children[0]
	second := before.children[1]
	first.children[0].children[1].on_event(ui2.ElementEvent{ kind: .click })
	assert root.element().children[0].children[0].children[1].text == '1'
	assert root.element().children[1].children[0].children[1].text == '0'
	ui2.set_vml_theme(initial, ui2.Theme{
		colors:  {
			'surface': u32(0x223344)
			'accent':  u32(0x334455)
		}
		spacing: {
			'medium': f64(4)
		}
		radii:   {
			'medium': f64(3)
		}
	})!
	themed := root.element()
	assert themed.children[0].box.bg == 0x223344
	assert themed.children[1].box.bg == 0x223344
	assert themed.children[0].layout.stack.padding.left == 4
	assert themed.children[0].box.radius == 3
	mut second_owner := second.compiled_node.component
	second_owner.set_theme(ui2.Theme{ colors: {
		'surface': u32(0x556677)
	} })!
	app.emphasized = true
	owner.invalidate_app()!
	assert root.element().children[0].box.bg == 0x334455
	assert root.element().children[0].box.radius == 0
	assert root.element().children[1].box.bg == 0x556677
	assert root.element().children[0].compiled_node == first.compiled_node
	assert root.element().children[0].children[0].children[1].text == '1'
	owner.set_theme(ui2.Theme{})!
	assert root.element().children[0].box.bg == 0x2563eb
	assert root.element().children[1].box.bg == 0x556677
	assert root.element().children[0].layout.stack.padding.left == 12
	second_owner.set_theme(ui2.Theme{})!
	assert root.element().children[1].box.bg == 0xffffff
	root.dispose_document()!
	assert owner.runtime.stats() == ui2.SignalStats{}
}

fn test_composite_value_changes_keep_styles_and_removed_variants_restore_defaults() ! {
	mut app := &StylesContractApp{ emphasized: true }
	initial := styles_tree(mut app)
	mut root := initial.compiled_node
	root.mount()!
	mut owner := root.component
	before := root.element()
	assert before.children[3].box.bg == 0x112233
	assert before.children[3].children[0].box.bg == 0x445566
	assert before.children[3].children[0].box.radius == 8
	assert before.children[5].text_style.color == 0xff0000
	assert before.children[5].text_style.size == 30
	assert before.children[5].text_style.bold && before.children[5].text_style.italic
	app.progress = 0.75
	app.choice = 'Two'
	owner.invalidate_app()!
	updated := root.element()
	assert updated.children[3].box.bg == 0x112233
	assert updated.children[3].children[0].box.bg == 0x445566
	assert updated.children[3].children[0].box.radius == 8
	assert updated.children[3].children[0].frame.width == updated.children[3].frame.width * 0.75
	assert updated.children[3].compiled_node == before.children[3].compiled_node
	assert updated.children[3].children[0].compiled_node == before.children[3].children[0].compiled_node
	assert updated.children[4].box.bg == 0x112233
	assert updated.children[4].box.radius == 0
	assert updated.children[4].text_style.color == 0xffffff
	assert updated.children[4].text_style.size == 18
	assert updated.children[4].text == 'Two'
	app.emphasized = false
	owner.invalidate_app()!
	plain := root.element().children[3]
	assert plain.box.bg == 0xe2e8f0
	assert plain.box.radius == 4
	assert plain.children[0].box.bg == 0x3b82f6
	assert plain.children[0].box.radius == 4
	caption := root.element().children[5]
	assert caption.text_style == ui2.TextStyle{}
	assert caption.compiled_node == before.children[5].compiled_node
	root.dispose_document()!
	assert owner.runtime.stats() == ui2.SignalStats{}
}
