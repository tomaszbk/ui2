// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn anonymous_retained_measure(_text string, _style TextStyle, _width f64) !LayoutSize {
		return LayoutSize{ width: 80, height: 24 }
	}

	fn test_anonymous_property_effect_patches_custom_layout_without_building_or_exposing_id() ! {
		previous_app := g_gg_app
		previous_window := capture_custom_window_state()
		defer {
			g_gg_app = previous_app
			previous_window.restore()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		mut owner := new_vml_document('anonymous custom')!
		defer { owner.dispose() or { panic(err) } }
		mut root := owner.element(Element{ kind: .screen, frame: rect(0, 0, 200, 100) },
			identity: 'root'
		)!
		mut label := owner.element(Element{ kind: .label, frame: rect(0, 0, 100, 24) },
			identity: 'label'
		)!
		mut text := owner.state('caption', 'Before')!
		label.effect('text', fn [mut text] (element Element) !Element {
			return Element{ ...element, text: text.get()! }
		})!
		root.set_children([label])!
		app.declared_root = root.element()
		initial := app.scheduler.begin_frame(0) or { panic('missing initial frame') }
		resolve_custom_layout(mut app, initial, anonymous_retained_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(initial)
		root.mount()!
		app.layout_tree.reset_stats()
		text.set('Después')!
		assert app.layout_patches.len == 1
		assert app.layout_patches[0].compiled == label
		work := app.scheduler.begin_frame(1) or { panic('missing property frame') }
		assert !work.build
		resolved := resolve_custom_layout(mut app, work, anonymous_retained_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(work)
		assert resolved.children[0].text == 'Después'
		assert resolved.children[0].id == '' && resolved.id == ''
		assert app.layout_tree.stats().builds == 0
		assert !app.scheduler.stats().pending
	}
}
