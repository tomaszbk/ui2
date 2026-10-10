module ui2

struct DiagnosticListItem {
	id   string
	text string
}

@[heap]
struct DiagnosticListCounts {
mut:
	builds int
}

fn diagnostic_list(mut owner CompiledVmlComponent, mut counts DiagnosticListCounts) !(&CompiledVmlNode, &VmlKeyedList[DiagnosticListItem]) {
	owner.publish = fn (_ string, _ Element) {}
	mut parent := owner.element(Element{ kind: .view, id: 'list' })!
	list := new_vml_keyed_list(mut parent, 'rows', fn (item DiagnosticListItem) string {
		return item.id
	}, fn [mut counts] (mut instance CompiledVmlComponent, source &Signal[DiagnosticListItem]) ![]&CompiledVmlNode {
		counts.builds++
		mut item := source
		mut node := instance.element(Element{ kind: .text_field, id: 'edit' })!
		node.effect('text', fn [mut item] (element Element) !Element {
			return Element{ ...element, text: item.get()!.text }
		})!
		return [node]
	})!
	return parent, list
}

fn test_keyed_list_initial_key_errors_include_the_authored_source() ! {
	for items in [
		[DiagnosticListItem{ id: 'a' }, DiagnosticListItem{ id: 'a' }],
		[DiagnosticListItem{ id: '' }],
	] {
		mut owner := new_vml_component('initial list diagnostic')!
		mut counts := &DiagnosticListCounts{}
		parent, mut list := diagnostic_list(mut owner, mut counts)!
		before := parent.element()
		if _ := list.bind(fn [items] () ![]DiagnosticListItem { return items },
			source: 'views/rows.vml'
			line:   7
			column: 3
		) {
			assert false, 'invalid keys were accepted'
		} else {
			expected := if items.len == 2 {
				'duplicate compiled VML list key `a`'
			} else {
				'compiled VML list key cannot be empty'
			}
			assert err.msg().ends_with('views/rows.vml:7:3: ${expected}')
		}
		assert list.nodes().len == 0
		assert parent.element() == before
		assert counts.builds == 0
		owner.dispose()!
		assert owner.runtime.stats() == SignalStats{}
	}
}

fn test_keyed_list_reactive_errors_preserve_nodes_order_and_recover() ! {
	mut owner := new_vml_component('reactive list diagnostic')!
	mut counts := &DiagnosticListCounts{}
	parent, mut list := diagnostic_list(mut owner, mut counts)!
	mut items := owner.state('rows', [DiagnosticListItem{ id: 'a', text: 'A' },
		DiagnosticListItem{ id: 'b', text: 'B' }])!
	mut unavailable := owner.state('unavailable', false)!
	list.bind(fn [mut items, mut unavailable] () ![]DiagnosticListItem {
		if unavailable.get()! { return error_with_code('service unavailable', 17) }
		return items.get()!
	}, source: 'views/rows.vml', line: 11, column: 5)!
	first := list.nodes()[0]
	second := list.nodes()[1]
	before := parent.element()
	for invalid in [
		[DiagnosticListItem{ id: 'a', text: 'changed' },
			DiagnosticListItem{ id: 'a', text: 'duplicate' }],
		[DiagnosticListItem{ id: '', text: 'empty' }],
	] {
		if _ := items.set(invalid) {
			assert false, 'invalid keys were accepted'
		} else {
			expected := if invalid.len == 2 {
				'duplicate compiled VML list key `a`'
			} else {
				'compiled VML list key cannot be empty'
			}
			assert err.msg().ends_with('views/rows.vml:11:5: ${expected}')
		}
		assert list.nodes() == [first, second]
		assert parent.element() == before
		assert first.element().text == 'A' && second.element().text == 'B'
		assert counts.builds == 2
	}
	items.set([DiagnosticListItem{ id: 'b', text: 'B!' }, DiagnosticListItem{ id: 'a', text: 'A' }])!
	assert list.nodes() == [second, first]
	assert second.element().text == 'B!'
	assert counts.builds == 2
	if _ := unavailable.set(true) {
		assert false, 'source failure was ignored'
	} else {
		assert err.msg().ends_with('views/rows.vml:11:5: service unavailable')
	}
	assert list.nodes() == [second, first]
	assert first.element().text == 'A' && second.element().text == 'B!'
	unavailable.set(false)!
	assert list.nodes() == [second, first]
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}

fn test_keyed_list_initial_source_errors_keep_optional_location() ! {
	for located in [false, true] {
		mut owner := new_vml_component('list source diagnostic')!
		mut counts := &DiagnosticListCounts{}
		parent, mut list := diagnostic_list(mut owner, mut counts)!
		location := if located {
			VmlSourceLocation{ source: 'views/rows.vml', line: 2, column: 9 }
		} else {
			VmlSourceLocation{}
		}
		if _ := list.bind(fn () ![]DiagnosticListItem {
			return error_with_code('service unavailable', 17)
		}, location) {
			assert false, 'source failure was ignored'
		} else {
			expected := if located {
				'views/rows.vml:2:9: service unavailable'
			} else {
				'service unavailable'
			}
			assert err.msg().ends_with(expected)
			assert err.msg().contains('views/rows.vml') == located
		}
		assert list.nodes().len == 0 && parent.children.len == 0
		assert counts.builds == 0
		owner.dispose()!
		assert owner.runtime.stats() == SignalStats{}
	}
}
