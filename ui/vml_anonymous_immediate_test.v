// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn anonymous_retained_measure(_text string, _style TextStyle, _width f64) !LayoutSize {
		return LayoutSize{ width: 80, height: 24 }
	}

	fn test_anonymous_property_effect_patches_custom_layout_without_building_or_exposing_id() ! {
		mut w := &Window{}
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
		w.declared_root = root.element()
		initial := w.scheduler.begin_frame(0) or { panic('missing initial frame') }
		w.resolve_custom_layout(initial, anonymous_retained_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(initial)
		root.mount()!
		w.layout_tree.reset_stats()
		text.set('Después')!
		assert w.layout_patches.len == 1
		assert w.layout_patches[0].compiled == label
		work := w.scheduler.begin_frame(1) or { panic('missing property frame') }
		assert !work.build
		resolved := w.resolve_custom_layout(work, anonymous_retained_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(work)
		assert resolved.children[0].text == 'Después'
		assert resolved.children[0].id == '' && resolved.id == ''
		assert w.layout_tree.stats().builds == 0
		assert !w.scheduler.stats().pending
	}
}
