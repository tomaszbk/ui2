// vtest vflags: -d ui2_document_library
module ui2

@[heap]
struct VmlHostFixture {
mut:
	commands []VmlHostCommand
}

fn test_document_commands_require_a_host_and_relay_existing_and_future_scopes() ! {
	mut owner := new_vml_document('host commands')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut existing := owner.child('existing')!
	mut nested := existing.child('nested')!
	mut node := nested.element(text_input(TextInputConfig{ id: 'input', text: 'declared' })!)!
	mut ref := owner.ref[VmlTextInput]('input')!
	ref.bind(node)!
	mut root := owner.element(Element{ kind: .view, id: 'root' })!
	root.set_children([node])!
	mut rejected := false
	ref.focus() or {
		rejected = true
		assert err.msg().contains('before mount')
	}
	assert rejected
	root.mount()!
	$if ui2_document_library ? {
		rejected = false
		ref.focus() or {
			rejected = true
			assert err.msg().contains('host command handler')
		}
		assert rejected
		rejected = false
		ref.set_text('no host') or {
			rejected = true
			assert err.msg().contains('host command handler')
		}
		assert rejected
		assert node.element().text == 'declared'
	}
	mut fixture := &VmlHostFixture{}
	owner.set_command_handler(fn [mut fixture] (command VmlHostCommand) ! {
		fixture.commands << command
	})!
	mut future := existing.child('future')!
	mut next := future.element(text_area(TextAreaConfig{ id: 'area', text: 'area declared' })!)!
	mut area := future.ref[VmlTextArea]('area')!
	area.bind(next)!
	root.set_children([node, next])!
	ref.focus()!
	ref.set_text('ñ café🙂')!
	area.focus()!
	area.set_text('multiline\ntext')!
	assert fixture.commands == [
		VmlHostCommand{ kind: .focus, id: node.element().id },
		VmlHostCommand{ kind: .set_text, id: node.element().id, text: 'ñ café🙂' },
		VmlHostCommand{ kind: .focus, id: next.element().id },
		VmlHostCommand{ kind: .set_text, id: next.element().id, text: 'multiline\ntext' },
	]
	assert node.element().text == 'declared' && next.element().text == 'area declared'
	owner.set_command_handler(fn (_ VmlHostCommand) ! { return error('host unavailable') })!
	rejected = false
	ref.focus() or {
		rejected = true
		assert err.msg() == 'host unavailable'
	}
	assert rejected
	owner.set_command_handler(unsafe { nil }) or { assert err.msg().contains('nil') }
	root.set_children([next])!
	rejected = false
	ref.set_text('stale') or {
		rejected = true
		assert err.msg().contains('unavailable')
	}
	assert rejected
	owner.dispose()!
	owner.set_command_handler(fn (_ VmlHostCommand) ! {}) or { assert err.msg().contains('disposed') }
	assert owner.runtime.stats() == SignalStats{}
}
