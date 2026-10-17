// vfmt off
@[has_globals]
module ui2

// Every backend reports hover changes through hover_transitions, so this part
// runs natively too (and keeps the file from being empty there).
fn test_hover_transitions_report_nothing_for_an_unchanged_chain() {
	chain := [HoverTarget{ identity: 'root/0', id: 'list' }, HoverTarget{ identity: 'root/0/0', id: 'row:1' }]
	left, entered := hover_transitions(chain, chain)
	assert left.len == 0 && entered.len == 0
}

$if (android || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	@[heap]
	struct HoverLog {
	mut:
		events []string
	}

	fn hover_test_element(id string, mut log HoverLog) Element {
		return Element{
			...with_hover(view(id, Rect{}, BoxStyle{}, []Element{}))
			on_event: fn [mut log] (event ElementEvent) {
				log.events << '${event.kind}:${event.id}:${event.x}:${event.y}'
			}
		}
	}

	// hover_test_paint registers a frame the way the renderer paints it: a list
	// with two rows, the first row with a button, and a popover drawn last over
	// the second row's button.
	fn hover_test_paint(mut log HoverLog) {
		window := rect(0, 0, 400, 300)
		begin_hover_frame()
		root := enter_hover_element(view('', window, BoxStyle{}, []Element{}), 'root', window, window, false)
		list := enter_hover_element(hover_test_element('list', mut log), 'root/0', rect(10, 10, 200, 200), window, false)
		row1 := enter_hover_element(hover_test_element('row:1', mut log), 'root/0/0', rect(10, 10, 200, 40), window, false)
		more := enter_hover_element(hover_test_element('more:1', mut log), 'root/0/0/0', rect(150, 15, 50, 30), window, false)
		leave_hover_element(more)
		leave_hover_element(row1)
		row2 := enter_hover_element(hover_test_element('row:2', mut log), 'root/0/1', rect(10, 50, 200, 40), window, false)
		leave_hover_element(row2)
		leave_hover_element(list)
		popover := enter_hover_element(view('popover', Rect{}, BoxStyle{}, []Element{}), 'root/1', rect(140, 50, 120, 60), window, false)
		leave_hover_element(popover)
		leave_hover_element(root)
	}

	fn hover_test_fire() {
		for pending in take_hover_events() {
			pending.fire()
		}
	}

	fn hover_test_move(x f64, y f64) {
		hover_pointer_moved(x, y)
		hover_test_fire()
	}

	fn test_hover_reports_enter_and_leave_like_css_hover() {
		mut log := &HoverLog{}
		g_hover = HoverState{}
		hover_test_paint(mut log)
		hover_test_move(20, 20)
		assert log.events == ['pointer_enter:list:20.0:20.0', 'pointer_enter:row:1:20.0:20.0']
		log.events.clear()
		// A repaint with fresh callbacks keeps the same elements hovered.
		hover_test_paint(mut log)
		hover_test_fire()
		assert log.events.len == 0
		// Onto the row's own button: its ancestors stay hovered.
		hover_test_move(160, 20)
		assert log.events == ['pointer_enter:more:1:160.0:20.0']
		log.events.clear()
		hover_test_move(20, 60)
		assert log.events == ['pointer_leave:more:1:20.0:60.0', 'pointer_leave:row:1:20.0:60.0',
			'pointer_enter:row:2:20.0:60.0']
		log.events.clear()
		// The popover covers the row there, so nothing hoverable is hovered.
		hover_test_move(180, 60)
		assert log.events == ['pointer_leave:row:2:180.0:60.0', 'pointer_leave:list:180.0:60.0']
		log.events.clear()
		hover_test_move(20, 60)
		hover_pointer_left()
		hover_test_fire()
		assert log.events == ['pointer_enter:list:20.0:60.0', 'pointer_enter:row:2:20.0:60.0',
			'pointer_leave:row:2:20.0:60.0', 'pointer_leave:list:20.0:60.0']
		g_hover = HoverState{}
	}

	fn test_hover_regions_are_clipped_to_what_is_visible() {
		mut log := &HoverLog{}
		g_hover = HoverState{}
		begin_hover_frame()
		clip := rect(0, 50, 100, 50)
		scroll_area := enter_hover_element(hover_test_element('scroll', mut log), 'root', rect(0, 0, 100, 100), clip, false)
		hidden := enter_hover_element(view('', Rect{}, BoxStyle{}, []Element{}), 'root/0', rect(0, 0, 100, 10), clip, false)
		leave_hover_element(hidden)
		leave_hover_element(scroll_area)
		assert g_hover.regions.len == 1
		assert g_hover.regions[0].frame == rect(0, 50, 100, 50)
		assert hovered_chain_at(10, 10).len == 0
		assert hovered_chain_at(10, 60).map(it.id) == ['scroll']
		// An inert element (under a modal overlay, say) is not hoverable.
		begin_hover_frame()
		inert := enter_hover_element(hover_test_element('scroll', mut log), 'root', rect(0, 0, 100, 100), clip, true)
		leave_hover_element(inert)
		assert hovered_chain_at(10, 60).len == 0
		g_hover = HoverState{}
	}
}
